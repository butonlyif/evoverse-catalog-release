// ============================================================================
// ddr_memcheck.v — LPDDR4X 读写比对自检 + TG（OSTD 标定扫描，correlation Phase 1）
// 移植自 EvoVerse ws-e1 ddr-memtest/memory_checker.v（板上验证过的参考），
// 修正与改动（相对原参考）：
//  1. [修 bug] 原代码 fail 在每个 burst 的 WRITE_ADDR 拍被清零——中途错后
//     续 burst 会洗掉 fail 标志造成误 PASS。本版 fail 置位即保持（sticky），
//     另加 err_cnt 累计比对错误次数。
//  2. [修 bug] 原代码 reset/IDLE 分支 `wdata <= 256'd0` 位宽不匹配（512 位
//     端口），本版改 512'd0。
//  3. [修时序] 本 DDR 控制器为 WVALID-先于-AWREADY 型（AWREADY 在
//     AWVALID && WVALID 都见过后才断言）：W 通道在 PRE_WRITE 起爆，
//     PRE_WRITE 期间发生的传输同样计入 beat（对齐参考 checker）；
//     wlast 与最后 beat 严格同拍。
//  4. [参数化] ALEN=119 => 120 beat × 64B = 7680B/突发 = 恰好一行 UYVY，
//     与未来 frame_writer/frame_reader 的行 burst 形态一致——自检环境=
//     应用环境。
//  5. 覆盖量 = TOTAL_BURSTS × 7680B（固定 burst 计数制，不用地址阈值，
//     天然无末突发越界；板上 3495 突发覆盖 0x0~0x103F200 ≈ 帧 A/B 乒乓区，
//     2Gb 颗粒 = 256MB，A/B 帧 @ 0x0/0x01000000 各 16MB）。
//  6. 数据图案沿用参考的"地址+beat 指纹"（高低 256 位镜像，自恢复性好）。
//  7. [TG_MODE=1，2026-10-22 Phase 1 新增] OSTD 递增扫描：
//     - 第 1 轮前先写 TG_N_BURST 个 burst 落盘（ALEN=63 → 64 beat×64B=
//       4096B/burst，4KB 安全，仿真/板级口径一致），之后各轮只读不写；
//     - 每轮以 tg_ostd = 1..TG_OSTD_MAX 为在飞上限连续发 AR（RID =
//       发射序号低 4 位，TG_N_BURST≤16 保证同 ID 不重叠），返回乱序按
//       per-RID 上下文（rid_addr/rid_beat）比对 pat 指纹；
//     - 每轮锁存 tg_rd_cyc（进入读态至收完全部 burst 的 axi_clk 拍数）
//       → 板级 UART 扫描帧 / 仿真 TB 曲线采样；
//     - 每轮间隔 TG_ROUND_GAP_TICKS 拍（≥UART 帧时间，供 UART 发帧），
//       err_cnt 轮间清零，fail 保持全局 sticky；
//     - ARVALID 纪律（Phase 0 实锤）：VALID&&READY 完成次拍必须撤，
//       发射门控 !arvalid 天然满足。
//     约束：TG_MODE=1 必须 ALEN=63（64 beat，rid_beat 6 位容量）。
//  8. [TG_MODE=2，2026-10-22 Phase 2 新增] 延迟标定（测试 spec §8.3/§3.2）：
//     - 9 个测量块自动轮跑：块 0-4 低负载（ostd=1）扫 LEN={1,3,7,15,31} beat
//       （SIZE 固定 64B，narrow 扫描不在此期）；块 5-8 高负载 LEN=31 beat、
//       ostd={4,8,12,16}（Phase 1 实测接受上限 16 的 25/50/75/100%）；
//     - 每块先写后读各 blk_n 笔（写兼数据布置；地址 4KB 页对齐 +0x1000/burst，
//       短 burst 跨页会踩模型 SLVERR 丢数据，见 plan §6-2）；
//     - 口径：T_AR_FIRST_R（AR 握手→同 ID 首 R beat）、T_AW_B（AW 握手→B）、
//       T_WLAST_B（WLAST 握手→B）；写基线 AWCACHE 定稿 0000（Phase 2 板级
//       实测 1111 使真控制器 AW/W 握手死锁，见 plan §6-6/§9 Phase 2）；
//     - 每相丢前 TG_LAT_WARMUP 笔 warm-up；直方图 32 bin×64 拍（0..2047），
//       ≥2048 拍样本计 ovf（§8.3-7 窗口无效判据），min/max 精确到拍；
//       块尾 32 拍迭代求 P50/P95/P99（bin 上界；阈值 k% 用 *205/*41>>12 近似，
//       偏差 ±0.1%；量程外 P 值=0xFFFF 哨兵）；
//     - 结果经 lat_word{blk,set,kind,data} 轮发，lat_next 帧尾脉冲推进指针
//       （kind 最快→set→blk；blk=9 为状态字 {fail,err_tot}）；报告在 done
//       后周期性重发，上位机按多数票取值。
//  9. [TG_MODE=2 修订，2026-10-22 Phase 5] B 时机矩阵（测试 spec §8.6）：
//     - 块表改为 (AWCACHE,AWCOBUF) 矩阵：全块 LEN=31、ostd=1 串行（B 归属
//       无歧义），blk_n 压为 TG_LAT_P5_N；1111 板级死锁不入矩阵；
//     - 每块测量 B 符号：WA/WL 原口径 + 新增 BB（B 早于 WLAST 握手笔数，
//       §8.6-3 B_BEFORE_WLAST），报告 set=3 仅 kind=2(cnt) 有效；
//     - B 握手事件化：bready 自 WRITE_ADDR 常开（§8.6-2 ALWAYS），写窗口
//       4 态均可收 B 并置 b_got；POST_WRITE 收尾判据 bvalid→b_got——
//       B 早返时在 PRE_WRITE/WRITE 即被握手，原"POST_WRITE 等 bvalid"
//       会死等。板级实测（§9 Phase 5）真核为 W-first（AWREADY≥WLAST 恒
//       成立）→ BB 恒 0，早返的真实签名是 WA（T_AW_B）骤降至 AW+2-5 拍
//       （AxCACHE[0]=Bufferable 编码）；bit0=0 编码 WA≈WL 55-99 拍。
// 10. [TG_MODE=3，2026-10-23 Phase 3 新增] 固定速率读扫描（测试 spec §8.4）：
//     - 首轮前写布置 16×4KB（同 MODE1），之后 9 轮只读：blk0-8 = AR 发射
//       间隔 INTERVAL {256,128,64,32,16,8,4,2,1} 拍（qd_ivl_f 表），每轮
//       16 笔 ALEN=63（4KB）读，RID=发射序号（同 ID 不重叠）；
//     - 不设在飞上限（测的就是对端何时拒绝）：qd_gap 分频发侧，握手成功
//       重装 ivl-1；统计 qd_bp_cnt（arvalid&&!arready 拍数=真反压）、
//       qd_if_peak（in_flight 峰值=已收 AR 未完 RLAST）、qd_rd_cyc（轮耗时）；
//     - 判据（§8.4-4）：qd_bp_cnt 0→非 0 跃变档=首真反压点；if_peak 饱和
//       值=对端读接受容量（模型=READ_OSTD_DEPTH 门控；板级待测，Phase 1
//       只证 ≥16）→ CMD_QUEUE_DEPTH_ENG 上界估计；
//     - 结果经 lat_word 轮发：blk=档位 0-8（blk9 状态字复用），set 恒 0，
//       kind 0=rd_cyc 1=bp_cnt 2=if_peak 3=err；UART_SCAN_MODE=2 直发，
//       上位机 uart_lat_decode.ps1 多数票（Phase 3 表）。
// 11. [TG_MODE=4，2026-10-23 Phase 6 新增] OOO 探测（测试 spec §8.7）：
//     - 首轮前写布置 16×4KB（同 MODE1，地址步长改 1MB 分散跨 bank/row，
//       §8.7-1"地址分散"），之后 9 轮只读：每轮 16 笔 ALEN=63 背靠背
//       （qd_ivl=1，无在飞上限），ID_COUNT=8 轮转——发射序 s 的
//       arid = s[2:0]（0..7,0..7，每 ID 2 笔，§8.7 ID_MODE=ROTATE）；
//     - 完成侧：同 ID 保序（AXI 契约）→ per-ID 完成计数 id_comp 推导
//       该笔发射序（rid 槽共用，数据比对 rid_addr[seq] 按序选前/后笔）；
//       全局完成序 oo_comp 与发射序 ID 交叉比对：完成 rid[2:0] !=
//       oo_comp[2:0] → 跨 ID 乱序，oo_cnt++，oo_first 锁存首个错位
//       {完成 rid[2:0], 完成序[3:0]}（§8.7-3 判据）；
//     - 判定：oo_cnt=0 → 按序完成，OUT_OF_ORDER_ENABLE 维持 0；oo_cnt>0
//       → 支持乱序，回填 1。同 ID 内顺序 AXI 强制，不在板级检测范围；
//     - 报告：lat_word blk 恒 0（9=状态字），set 恒 0，kind 0=oo_cnt
//       1=oo_first 2=完成笔数 3=err；每轮 TG_ROUND_GAP 锁存轮值后清零。
// 12. [TG_MODE=5，2026-10-23 Phase 7 新增] 容量/别名探测（测试 spec §8.8）：
//     - 板级配置为单 rank LPDDR4x 2Gb（256MB，2 的幂，peri.xml 实锤）→
//       §8.8 的 rank 边界/CS_BIT/非 2 幂扫描均不适用，缩范围为容量边界
//       与越界别名（回绕）行为探测；
//     - 9 探针 blk0-8：{0, 256M-4K, 256M, 256M+4K, 512M, 1G, 2G, 4G-4K, 4G}；
//       每轮 4 笔序列：写 Yi(=Xi mod 256M) 参考 → 写 Xi 探针 → 读 Xi
//       （比对 pattern(Xi)，hi_err=不可存储信号）→ 读 Yi（比对基准仍
//       pattern(Xi)：读回 pattern(Xi)=Xi 回绕到 Yi 实锤 alias_err==0）；
//     - 判读：hi_err=0 且 alias_err>0 → Xi 真实可访问（容量 ≥ Xi）；
//       hi_err=0 且 alias_err=0 → 回绕别名（容量 < Xi，高位被模掉）；
//       hi_err>0 → 不可访问（SLVERR/读丢弃）。探针 0/1（Xi==Yi）alias
//       检测退化无意义，以 hi_err 为准；
//     - 报告：lat_word blk=探针号（9=状态字），kind 0=hi_err 1=alias_err
//       2=探针地址[15:0] 3=探针地址[32:16]；MODE5 不置全局 fail（越界
//       err 是预期观测，err 分计数器自说明）。
// ============================================================================

module ddr_memcheck #(
    parameter [32:0] START_ADDR = 33'h0_0000_0000,
    parameter [15:0] TOTAL_BURSTS = 16'd3495,   // 3495×7680B ≈ 26MB（帧乒乓区）
    parameter [7:0]  ALEN       = 8'd119,       // 120 beat/burst
    parameter [2:0]  ASIZE      = 3'b110,       // 64B/beat
    parameter        TG_MODE    = 0,            // 0=自检 1=OSTD 扫描 2=延迟标定 3=固定速率扫描 4=OOO 探测 5=容量/别名探测（Phase 7）
    parameter [4:0]  TG_OSTD_MAX= 5'd16,        // 扫描终值（≤16，RID 4 位；5 位防 16 溢出）
    parameter [15:0] TG_N_BURST = 16'd16,       // 每轮 burst 数（≤16，×4KB）
    parameter [31:0] TG_ROUND_GAP_TICKS = 32'd400_000,  // 轮间隔拍（板级 2ms@200M）
    // ---- TG_MODE=2 延迟标定参数 ----
    parameter integer TG_LAT_WARMUP = 100,      // 每相丢前 warm-up 样本数（§8.3-1）
    parameter integer TG_LAT_P5_N   = 600       // Phase 5 B 时机矩阵每块笔数（符号判定+min/P50）
)(
    input  wire        axi_clk,
    input  wire        rstn,          // 低有效，同步释放（ddr_cfg_ok 后）
    input  wire        start,         // rstn 释放后置 1 即启动

    // AXI4 写地址
    output wire [5:0]  awid,
    output reg  [32:0] awaddr,
    output reg  [7:0]  awlen,
    output reg  [2:0]  awsize,
    output reg  [1:0]  awburst,
    output reg  [3:0]  awcache,
    output reg         awlock,
    output reg         awvalid,
    output reg         awcobuf,
    output reg         awapcmd,
    output reg         awallstrb,
    output reg         awqos,
    input  wire        awready,
    // AXI4 写数据
    output reg  [511:0] wdata,
    output wire [63:0]  wstrb,
    output reg         wlast,
    output reg         wvalid,
    input  wire        wready,
    // AXI4 写响应
    input  wire [5:0]  bid,
    input  wire        bvalid,
    output reg         bready,
    // AXI4 读地址
    output reg  [5:0]  arid,          // TG 模式按发射序号轮转，原模式恒 0
    output reg  [32:0] araddr,
    output reg  [7:0]  arlen,
    output reg  [2:0]  arsize,
    output reg  [1:0]  arburst,
    output reg         arlock,
    output reg         arvalid,
    output reg         arapcmd,
    output reg         arqos,
    input  wire        arready,
    // AXI4 读数据
    input  wire [5:0]  rid,
    input  wire [511:0] rdata,
    input  wire        rlast,
    input  wire        rvalid,
    output reg         rready,
    input  wire [1:0]  rresp,

    // 结果（sticky，复位清除）
    output reg         done,          // 全区域扫描完成
    output reg         fail,          // 任一比对错（sticky）
    output reg  [15:0] err_cnt,       // 比对错误累计次数（TG 模式=本轮内）
    output wire [3:0]  dbg_state,     // 状态机快照（板级诊断用）
    // TG 扫描结果（TG_MODE=1 有效）
    output wire [3:0]  tg_ostd,       // 当前轮 OSTD（1..TG_OSTD_MAX；4'h0=16）
    output reg  [15:0] tg_rd_cyc,     // 本轮读耗时（axi_clk 拍，轮结束锁存）
    output wire [7:0]  tg_err_sat,    // 本轮错误数（饱和 255）
    // TG_MODE=2 延迟报告口：lat_word 轮发保持到 lat_next 脉冲（UART 帧尾）
    output wire [31:0] lat_word,      // {blk[3:0],set[1:0],kind[2:0],done,6'h0,data[15:0]}
    input  wire        lat_next       // 推进报告指针（1 拍脉冲）
);

    localparam [8:0]  BEATS      = ALEN + 9'd1;                      // 120
    localparam [32:0] BURST_STEP = {21'b0, BEATS, 6'b0};             // 7680B = 一行
    // 覆盖量 = TOTAL_BURSTS × 7680B（固定计数制：不依赖地址阈值，天然无
    // 末突发越界；板上 3495 突发覆盖 0x0~0x103F200 ≈ 帧 A/B 区）

    // TG 模式写循环 / 读循环条数（MODE0/1 常量折叠）
    // （wr_limit/rd_limit 引用 blk_n_r，定义在本文件 blk_n_r 声明之后）
    wire [15:0] mode_limit = TG_MODE ? TG_N_BURST : TOTAL_BURSTS; // MODE0/1 原口径

    localparam IDLE         = 4'd0,
               WRITE_ADDR   = 4'd1,
               PRE_WRITE    = 4'd2,
               WRITE        = 4'd3,
               POST_WRITE   = 4'd4,
               READ_ADDR    = 4'd5,
               PRE_READ     = 4'd6,
               READ_COMPARE = 4'd7,
               POST_READ    = 4'd8,
               DONE         = 4'd9,
               TG_RD_REQ    = 4'd10,   // TG：连续发 AR + 收数比对（同态并行）
               TG_ROUND_GAP = 4'd11;   // TG：轮间隔（等 UART 发帧）+ 换轮

    reg [3:0]  state;
    reg        start_sync0, start_sync1;
    reg [8:0]  beat_cnt;          // 当前待发/待比 beat 序号（BEATS-1..0）
    reg [15:0] burst_idx;         // 当前 burst 序号
    reg [511:0] exp_rdata;        // 当拍期望值
    reg        rburst_done, read_done;

    // TG 内部
    reg [4:0]  tg_issued;         // 已发射 AR 数（TG_N_BURST=16 需 5 位）
    reg [4:0]  tg_completed;      // 已完整收回 burst 数
    reg [4:0]  tg_ostd_r;         // 当前轮 OSTD（5 位：16 需 5 位，4 位会 15+1→0 溢出）
    reg [32:0] tg_araddr_next;    // 下一条待发地址
    reg [15:0] tg_cyc_cnt;        // 本轮运行拍计数
    reg [31:0] gap_cnt;           // 轮间隔计数
    reg [5:0]  rid_beat  [0:15];  // per-RID 已收 beat 数
    reg [32:0] rid_addr  [0:15];  // per-RID burst 基地址
    reg [15:0] lat_issued;        // MODE2 读相已发总条数（tg_issued 5 位会回绕）
    reg [15:0] lat_completed;     // MODE2 读相已收总条数（16 位对 blk_n_r）

    assign awid  = 6'h0;
    assign wstrb = {64{1'b1}};
    assign dbg_state = state;
    assign tg_ostd = tg_ostd_r[3:0];    // 4'h0 表示 ostd=16（第 16 轮）
    assign tg_err_sat = (err_cnt > 16'd255) ? 8'hFF : err_cnt[7:0];

    // ========================================================================
    // TG_MODE=2 延迟标定（声明与统计机构）
    // ========================================================================
    localparam integer LAT_BINS  = 32;   // 直方图 bin 数
    localparam integer LAT_SHIFT = 6;    // bin 宽 64 拍 → 量程 0..2047

    integer bi;                          // 复位/清零循环变量

    // ---- 测量块表（correlation Phase 5：B 时机矩阵，测试 spec §8.6）----
    // 块→(AWCACHE,AWCOBUF)。基线 0000/0 复测（Phase 2 口径）；核心增量
    // 0000/1（AWCOBUF 是否令 B 早返）；块 2-6 按 modifiable/bufferable/
    // cacheable/allocate 位代表采样（§8.6-1 其他编码逐个跑的缩样子集，
    // 推理可覆盖的合成编码 1110=1111 去 bufferable 加收 COBUF 一点）；
    // 1111 板级 AW/W 死锁（plan §6-6）不入矩阵。全块 LEN=31（B 时机对
    // WLAST 时机敏感）、ostd=1（串行单 burst，B 归属无歧义）。
    function [3:0] blk_cache_f; input [3:0] b;
        case (b)
            4'd0:    blk_cache_f = 4'b0000;  // 基线（Phase 2 定稿口径）
            4'd1:    blk_cache_f = 4'b0000;  // 核心增量：COBUF=1
            4'd2:    blk_cache_f = 4'b0001;  // Bufferable
            4'd3:    blk_cache_f = 4'b0010;  // Modifiable
            4'd4:    blk_cache_f = 4'b0011;  // Modifiable+Bufferable
            4'd5:    blk_cache_f = 4'b0100;  // Allocate
            4'd6:    blk_cache_f = 4'b0111;  // +Cacheable
            4'd7:    blk_cache_f = 4'b1110;  // 1111 去 Bufferable
            default: blk_cache_f = 4'b1110;  // 1110 + COBUF=1
        endcase
    endfunction
    function blk_cobuf_f; input [3:0] b;
        blk_cobuf_f = (b == 4'd1) || (b == 4'd8);
    endfunction
    function [7:0] blk_len_f; input [3:0] b;   // 本块 AXI len（beat-1）
        blk_len_f = 8'd30;           // 全块 31 beat（原 LEN 扫描见 §9 Phase 2）
    endfunction
    function [4:0] blk_ostd_f; input [3:0] b;  // 本块在飞上限
        blk_ostd_f = 5'd1;           // 全块低负载（原 ostd 扫描见 §9 Phase 2）
    endfunction
    function [15:0] blk_n_f; input [3:0] b;    // 本块读/写笔数
        blk_n_f = TG_LAT_P5_N[15:0];
    endfunction

    // ---- Phase 3 固定速率扫描（TG_MODE=3，测试 spec §8.4）----
    // blk→AR 发射间隔（拍）。减半扫描 256→1；ivl=1 即逐条连续注入。
    function [15:0] qd_ivl_f; input [3:0] b;
        case (b)
            4'd0:    qd_ivl_f = 16'd256;
            4'd1:    qd_ivl_f = 16'd128;
            4'd2:    qd_ivl_f = 16'd64;
            4'd3:    qd_ivl_f = 16'd32;
            4'd4:    qd_ivl_f = 16'd16;
            4'd5:    qd_ivl_f = 16'd8;
            4'd6:    qd_ivl_f = 16'd4;
            4'd7:    qd_ivl_f = 16'd2;
            default: qd_ivl_f = 16'd1;
        endcase
    endfunction

    // 测量现场与轮内统计（in-flight ≤15：16 笔 ID 唯一，比较用 16 位防回绕）
    reg  [15:0] qd_ivl_r;                 // 本档发射间隔
    reg  [15:0] qd_gap;                   // 发射分频计数（==0 允发）
    reg  [15:0] qd_bp_cnt;                // arvalid&&!arready 拍数（真反压）
    reg  [15:0] qd_if_peak;               // in_flight 峰值（AR 已收未完）
    // 轮结果 bank（TG_ROUND_GAP 首拍锁存；lat_word blk=档位报告）
    reg [15:0] qd_cyc_r [0:8];
    reg [15:0] qd_bp_r  [0:8];
    reg [15:0] qd_if_r  [0:8];
    reg [15:0] qd_err_r [0:8];

    // ---- Phase 6 OOO 探测（TG_MODE=4，测试 spec §8.7）----
    // 地址 1MB 步长分散（跨 bank/row，§8.7-1）；ID_COUNT=8 轮转每 ID 2 笔
    localparam [32:0] OOO_STEP = 32'h10_0000;   // 1MB
    reg  [15:0] oo_cnt;                   // 跨 ID 乱序笔数（完成 ID != 发射序 ID）
    reg  [15:0] oo_cnt_r;                 // 轮锁存（lat_word kind 0）
    reg  [6:0]  oo_first;                 // 首错位 {完成 rid[2:0], 完成序[3:0]}
    reg  [6:0]  oo_first_r;               // 轮锁存（kind 1）
    reg  [3:0]  oo_comp;                  // 全局完成序 0..15
    reg  [5:0]  oo_done_r;                // 轮锁存完成笔数（kind 2）
    reg  [15:0] oo_err_r;                 // 轮锁存本轮 err（kind 3）
    reg  [1:0]  id_comp [0:7];            // per-ID 完成笔数（推导发射序）

    // ---- Phase 7 容量/别名探测（TG_MODE=5，测试 spec §8.8）----
    // 探针表（单 rank 2Gb=256MB：容量边界 + 越界回绕行为）
    function [32:0] ad_addr_f; input [3:0] b;
        case (b)
            4'd0:    ad_addr_f = 33'h0_0000_0000;   // 基线
            4'd1:    ad_addr_f = 33'h0_0FFF_F000;   // 256M-4K（末合法页）
            4'd2:    ad_addr_f = 33'h0_1000_0000;   // 256M（越界首）
            4'd3:    ad_addr_f = 33'h0_1000_1000;   // 256M+4K
            4'd4:    ad_addr_f = 33'h0_2000_0000;   // 512M
            4'd5:    ad_addr_f = 33'h0_4000_0000;   // 1G
            4'd6:    ad_addr_f = 33'h0_8000_0000;   // 2G
            4'd7:    ad_addr_f = 33'h0_FFFF_F000;   // 4G-4K
            default: ad_addr_f = 33'h1_0000_0000;   // 4G（bit32 置位）
        endcase
    endfunction
    reg  [15:0] ad_hi_err;                // 读 Xi 比对 pattern(Xi) 错 beat 数
    reg  [15:0] ad_al_err;                // 读 Yi 比对 pattern(Xi) 错 beat 数（0=污染）
    reg [15:0] ad_hi_r [0:8];             // 轮锁存（kind 0）
    reg [15:0] ad_al_r [0:8];             // 轮锁存（kind 1）

    // ---- 测量块现场 ----
    reg  [3:0]  blk_idx;                  // 0..8
    // 本轮探针 Xi 与别名参考 Yi（需 blk_idx 已声明）
    wire [32:0] ad_xi = ad_addr_f(blk_idx);              // 本轮探针 Xi
    wire [32:0] ad_yi = ad_xi & 33'h0_0FFF_FFFF;         // 别名参考 Yi = Xi mod 256M
    // 下一轮探针（换轮时装参考首笔地址；blk_idx+1 与 MODE3 换 ivl 同款）
    wire [32:0] ad_xi_n = ad_addr_f(blk_idx + 4'd1);
    wire [32:0] ad_yi_n = ad_xi_n & 33'h0_0FFF_FFFF;
    reg  [7:0]  blk_len_r;
    reg  [8:0]  blk_beats_r;              // blk_len_r+1
    reg  [4:0]  blk_ostd_r;
    reg  [15:0] blk_n_r;
    reg  [3:0]  blk_cache_r;              // 本块 AWCACHE（Phase 5 矩阵）
    reg         blk_cobuf_r;              // 本块 AWCOBUF
    reg  [32:0] blk_step_r;               // 恒 4096（4KB 页对齐步进）
    // 写/读相条数（MODE2 用本块 blk_n_r；MODE5 每轮 2 笔 {Yi,Xi}/{Xi,Yi}；MODE0/1 原口径）
    wire [15:0] wr_limit = (TG_MODE == 2) ? blk_n_r
                         : (TG_MODE == 5) ? 16'd2 : mode_limit;
    wire [15:0] rd_limit = (TG_MODE == 2) ? blk_n_r
                         : (TG_MODE == 5) ? 16'd2 : TG_N_BURST;
    wire [8:0]  cur_beats = (TG_MODE == 2) ? blk_beats_r : BEATS;
    // MODE4：1MB 步长地址分散（§8.7-1）；MODE2 块步长 4KB；其余 4KB
    wire [32:0] cur_step  = (TG_MODE == 2) ? blk_step_r
                          : (TG_MODE == 4) ? OOO_STEP : BURST_STEP;
    // 本 burst 末 beat 序号（MODE0/1 口径依赖 BEATS=64 的 6 位回绕，勿"统一"）
    wire [5:0]  last_beat = (TG_MODE == 2) ? (cur_beats[5:0] - 6'd1)
                                           : (BEATS[5:0] - 6'd1);

    // ---- 延迟基准与握手时戳 ----
    reg  [31:0] lat_cyc;                  // 自由走（32 位减法天然抗回绕）
    reg  [31:0] aw_lat0, wl_lat0;
    reg  [31:0] rid_lat0 [0:15];
    wire [31:0] diff_rd = lat_cyc - rid_lat0[rid];
    wire [31:0] diff_aw = lat_cyc - aw_lat0;
    wire [31:0] diff_wl = lat_cyc - wl_lat0;

    // MODE4：同 ID 保序（AXI）→ per-ID 完成计数推导当前完成笔的发射序，
    // 用于 rid_addr 查表（同 ID 两笔共用 rid 槽，rid_addr 按发射序 0-15 存）
    wire [5:0]  oo_rid_seq = {2'b00, rid[2:0]}
                           + (id_comp[rid[2:0]] != 2'd0 ? 6'd8 : 6'd0);

    // ---- 统计 bank（工作寄存）：0=RD 1=WA 2=WL 3=BB ----
    reg [15:0] wa_hist [0:31];
    reg [15:0] wl_hist [0:31];
    reg [15:0] rd_hist [0:31];
    reg [15:0] wa_min, wa_max, wa_cnt, wa_ovf, wa_smp;
    reg [15:0] wl_min, wl_max, wl_cnt, wl_ovf, wl_smp;
    reg [15:0] rd_min, rd_max, rd_cnt, rd_ovf, rd_smp;

    // ---- B 握手事件化（Phase 5，§8.6-2/3）----
    // b_got：本 burst 的 B 已被握手（bready 自 WRITE_ADDR 常开，B 早返时
    // 在 PRE_WRITE/WRITE 即到达，POST_WRITE 改判 b_got 防死等）；
    // wlast_seen：本 burst WLAST 已握手；bb_cnt：B 早于 WLAST 握手笔数
    reg        b_got;
    reg        wlast_seen;
    reg [15:0] bb_cnt;

    // ---- 全局错误累计（MODE2 报告用，块间不清） ----
    reg [15:0] err_tot;

    // ---- 块结果寄存（kind: 0=min 1=max 2=cnt 3=p50 4=p95 5=p99 6=ovf） ----
    reg [15:0] rd_min_r [0:8]; reg [15:0] rd_max_r [0:8]; reg [15:0] rd_cnt_r [0:8];
    reg [15:0] rd_p50_r [0:8]; reg [15:0] rd_p95_r [0:8]; reg [15:0] rd_p99_r [0:8];
    reg [15:0] rd_ovf_r [0:8];
    reg [15:0] wa_min_r [0:8]; reg [15:0] wa_max_r [0:8]; reg [15:0] wa_cnt_r [0:8];
    reg [15:0] wa_p50_r [0:8]; reg [15:0] wa_p95_r [0:8]; reg [15:0] wa_p99_r [0:8];
    reg [15:0] wa_ovf_r [0:8];
    reg [15:0] wl_min_r [0:8]; reg [15:0] wl_max_r [0:8]; reg [15:0] wl_cnt_r [0:8];
    reg [15:0] wl_p50_r [0:8]; reg [15:0] wl_p95_r [0:8]; reg [15:0] wl_p99_r [0:8];
    reg [15:0] wl_ovf_r [0:8];
    reg [15:0] bb_cnt_r [0:8];            // BB：B 早于 WLAST 握手笔数（set=3）

    // ---- 分位数迭代器（相尾跑 32 bin 累积；量程外=0xFFFF 哨兵） ----
    // 主 FSM 拥有：pct_launch（1 拍脉冲）/launch_set/launch_more/blk_r
    reg        pct_launch, pct_launch_more;
    reg  [1:0] pct_launch_set;
    reg  [3:0] pct_blk_r;
    // pct FSM 拥有：
    reg        pct_run, pct_pend;
    reg  [1:0] pct_set;
    reg  [4:0] pct_bin;
    reg [15:0] pct_cum;
    reg        pct_f50, pct_f95, pct_f99;
    reg [15:0] pct_v50, pct_v95, pct_v99;
    // bank 读出 mux
    wire [15:0] pb_min = (pct_set == 2'd0) ? rd_min : (pct_set == 2'd1) ? wa_min : wl_min;
    wire [15:0] pb_max = (pct_set == 2'd0) ? rd_max : (pct_set == 2'd1) ? wa_max : wl_max;
    wire [15:0] pb_cnt = (pct_set == 2'd0) ? rd_cnt : (pct_set == 2'd1) ? wa_cnt : wl_cnt;
    wire [15:0] pb_ovf = (pct_set == 2'd0) ? rd_ovf : (pct_set == 2'd1) ? wa_ovf : wl_ovf;
    wire [15:0] pb_bin = (pct_set == 2'd0) ? rd_hist[pct_bin] :
                         (pct_set == 2'd1) ? wa_hist[pct_bin] : wl_hist[pct_bin];
    // 阈值：50%=cnt/2；95%=cnt−cnt×5.005%（*205>>12）；99%=cnt−cnt×1.001%（*41>>12）
    wire [31:0] pb_cnt32 = {16'd0, pb_cnt};
    wire [23:0] pb_m95   = pb_cnt32[15:0] * 8'd205;   // 205 需 8 位（7 位会截成 77）
    wire [23:0] pb_m99   = pb_cnt32[15:0] * 8'd41;
    wire [15:0] pb_t50   = pb_cnt32[15:1];
    wire [15:0] pb_t95   = pb_cnt - pb_m95[23:12];
    wire [15:0] pb_t99   = pb_cnt - pb_m99[23:12];

    always @(posedge axi_clk or negedge rstn) begin
        if (!rstn) begin
            pct_run <= 1'b0;  pct_pend <= 1'b0;
            pct_set <= 2'd0;  pct_bin <= 5'd0; pct_cum <= 16'd0;
            pct_f50 <= 1'b0;  pct_f95 <= 1'b0; pct_f99 <= 1'b0;
            pct_v50 <= 16'hFFFF; pct_v95 <= 16'hFFFF; pct_v99 <= 16'hFFFF;
        end else if (!pct_run) begin
            if (pct_launch) begin          // 主 FSM 相尾启动（链式pend 由本块接管）
                pct_run <= 1'b1;
                pct_set <= pct_launch_set;
                pct_pend <= pct_launch_more;   // 写相：WA 后链跑 WL；读相：无
                pct_bin <= 5'd0;  pct_cum <= 16'd0;
                pct_f50 <= 1'b0;  pct_f95 <= 1'b0; pct_f99 <= 1'b0;
                pct_v50 <= 16'hFFFF; pct_v95 <= 16'hFFFF; pct_v99 <= 16'hFFFF;
            end
        end else begin
            // 累积判分：cum=bin[0..i-1] 计数，在 bin i 判定 cum≥阈值时，样本
            // 落于 bin i-1 及更低 → 取值 = i<<6（跨阈 bin 上界，64 拍粒度）
            if (!pct_f50 && pct_cum >= pb_t50) begin
                pct_f50 <= 1'b1;  pct_v50 <= pct_bin << LAT_SHIFT;
            end
            if (!pct_f95 && pct_cum >= pb_t95) begin
                pct_f95 <= 1'b1;  pct_v95 <= pct_bin << LAT_SHIFT;
            end
            if (!pct_f99 && pct_cum >= pb_t99) begin
                pct_f99 <= 1'b1;  pct_v99 <= pct_bin << LAT_SHIFT;
            end
            pct_cum <= pct_cum + pb_bin;
            if (pct_bin == 5'd31) begin
                // 锁存本 set 7 个结果字
                case (pct_set)
                    2'd0: begin
                        rd_min_r[pct_blk_r] <= pb_min;  rd_max_r[pct_blk_r] <= pb_max;
                        rd_cnt_r[pct_blk_r] <= pb_cnt;  rd_p50_r[pct_blk_r] <= pct_v50;
                        rd_p95_r[pct_blk_r] <= pct_v95; rd_p99_r[pct_blk_r] <= pct_v99;
                        rd_ovf_r[pct_blk_r] <= pb_ovf;
                    end
                    2'd1: begin
                        wa_min_r[pct_blk_r] <= pb_min;  wa_max_r[pct_blk_r] <= pb_max;
                        wa_cnt_r[pct_blk_r] <= pb_cnt;  wa_p50_r[pct_blk_r] <= pct_v50;
                        wa_p95_r[pct_blk_r] <= pct_v95; wa_p99_r[pct_blk_r] <= pct_v99;
                        wa_ovf_r[pct_blk_r] <= pb_ovf;
                    end
                    default: begin
                        wl_min_r[pct_blk_r] <= pb_min;  wl_max_r[pct_blk_r] <= pb_max;
                        wl_cnt_r[pct_blk_r] <= pb_cnt;  wl_p50_r[pct_blk_r] <= pct_v50;
                        wl_p95_r[pct_blk_r] <= pct_v95; wl_p99_r[pct_blk_r] <= pct_v99;
                        wl_ovf_r[pct_blk_r] <= pb_ovf;
                    end
                endcase
                if (pct_pend) begin            // 链式装载下一 set 重跑
                    pct_pend <= 1'b0;
                    pct_set  <= pct_set + 2'd1;
                    pct_bin  <= 5'd0;  pct_cum <= 16'd0;
                    pct_f50  <= 1'b0;  pct_f95 <= 1'b0; pct_f99 <= 1'b0;
                    pct_v50  <= 16'hFFFF; pct_v95 <= 16'hFFFF; pct_v99 <= 16'hFFFF;
                end else
                    pct_run <= 1'b0;
            end else
                pct_bin <= pct_bin + 5'd1;
        end
    end

    // ---- 块现场装载（含统计清零；IDLE 与块间 GAP 共用） ----
    task lat_blk_load;
        input [3:0] b;
        begin
            blk_idx     <= b;
            blk_len_r   <= blk_len_f(b);
            blk_beats_r <= {1'b0, blk_len_f(b)} + 9'd1;
            blk_ostd_r  <= blk_ostd_f(b);
            tg_ostd_r   <= blk_ostd_f(b);
            blk_n_r     <= blk_n_f(b);
            blk_cache_r <= blk_cache_f(b);
            blk_cobuf_r <= blk_cobuf_f(b);
            blk_step_r  <= 33'd4096;
            b_got       <= 1'b0;
            wlast_seen  <= 1'b0;
            bb_cnt      <= 16'd0;
            tg_issued      <= 5'd0;
            tg_completed   <= 5'd0;
            tg_cyc_cnt     <= 16'd0;
            err_cnt        <= 16'd0;
            tg_araddr_next <= START_ADDR;
            awaddr         <= START_ADDR;
            wa_min <= 16'hFFFF; wa_max <= 16'd0; wa_cnt <= 16'd0;
            wa_ovf <= 16'd0;    wa_smp <= 16'd0;
            wl_min <= 16'hFFFF; wl_max <= 16'd0; wl_cnt <= 16'd0;
            wl_ovf <= 16'd0;    wl_smp <= 16'd0;
            rd_min <= 16'hFFFF; rd_max <= 16'd0; rd_cnt <= 16'd0;
            rd_ovf <= 16'd0;    rd_smp <= 16'd0;
            for (bi = 0; bi < LAT_BINS; bi = bi + 1) begin
                wa_hist[bi] <= 16'd0;
                wl_hist[bi] <= 16'd0;
                rd_hist[bi] <= 16'd0;
            end
            for (bi = 0; bi < 16; bi = bi + 1)
                rid_lat0[bi] <= 32'd0;
            for (bi = 0; bi < 16; bi = bi + 1)
                rid_beat[bi] <= 6'd0;
        end
    endtask

    // ---- 报告轮发指针（lat_next 帧尾推进；kind→set→blk，blk=9 状态字） ----
    reg [3:0] rpt_blk;
    reg [1:0] rpt_set;
    reg [2:0] rpt_kind;
    always @(posedge axi_clk or negedge rstn) begin
        if (!rstn) begin
            rpt_blk <= 4'd0;  rpt_set <= 2'd0;  rpt_kind <= 3'd0;
        end else if (lat_next) begin
            if (TG_MODE == 3 || TG_MODE == 5) begin
                // Phase 3/7：kind 0-3 回绕（set 恒 0），blk 0-8 + 状态字 9 回绕
                if (rpt_kind == 3'd3) begin
                    rpt_kind <= 3'd0;
                    if (rpt_blk == 4'd9) rpt_blk <= 4'd0;
                    else                 rpt_blk <= rpt_blk + 4'd1;
                end else
                    rpt_kind <= rpt_kind + 3'd1;
            end else if (TG_MODE == 4) begin
                // Phase 6：kind 0-3 回绕（set 恒 0），blk 仅 0（测量）+ 状态字 9
                if (rpt_kind == 3'd3) begin
                    rpt_kind <= 3'd0;
                    rpt_blk  <= (rpt_blk == 4'd0) ? 4'd9 : 4'd0;
                end else
                    rpt_kind <= rpt_kind + 3'd1;
            end else if (rpt_kind == 3'd6) begin
                rpt_kind <= 3'd0;
                if (rpt_set == 2'd3) begin    // 0=RD 1=WA 2=WL 3=BB（Phase 5）
                    rpt_set <= 2'd0;
                    if (rpt_blk == 4'd9) rpt_blk <= 4'd0;
                    else                 rpt_blk <= rpt_blk + 4'd1;
                end else
                    rpt_set <= rpt_set + 2'd1;
            end else
                rpt_kind <= rpt_kind + 3'd1;
        end
    end
    // 数据 mux（blk 0-8 查结果寄存；blk 9 = {fail, err_tot}）
    reg [15:0] lat_data_r;
    // MODE5：报告用探针地址（函数返回值直接位选不可移植，走 wire）
    wire [32:0] rpt_ad_addr = ad_addr_f(rpt_blk);
    always @* begin
        if (rpt_blk == 4'd9)
            lat_data_r = {fail, err_tot[14:0]};
        else if (TG_MODE == 3)
            // Phase 3：kind 0=rd_cyc 1=bp_cnt 2=if_peak 3=err
            case (rpt_kind)
                3'd0:    lat_data_r = qd_cyc_r[rpt_blk];
                3'd1:    lat_data_r = qd_bp_r[rpt_blk];
                3'd2:    lat_data_r = qd_if_r[rpt_blk];
                default: lat_data_r = qd_err_r[rpt_blk];
            endcase
        else if (TG_MODE == 4)
            // Phase 6：kind 0=oo_cnt 1=oo_first{rid,seq} 2=完成笔数 3=err
            case (rpt_kind)
                3'd0:    lat_data_r = oo_cnt_r;
                3'd1:    lat_data_r = {9'd0, oo_first_r};
                3'd2:    lat_data_r = {10'd0, oo_done_r};
                default: lat_data_r = oo_err_r;
            endcase
        else if (TG_MODE == 5)
            // Phase 7：kind 0=hi_err 1=alias_err 2=探针地址[15:0] 3=探针地址[32:16]
            case (rpt_kind)
                3'd0:    lat_data_r = ad_hi_r[rpt_blk];
                3'd1:    lat_data_r = ad_al_r[rpt_blk];
                3'd2:    lat_data_r = rpt_ad_addr[15:0];
                default: lat_data_r = rpt_ad_addr[32:16];
            endcase
        else case (rpt_set)
            2'd0: case (rpt_kind)
                3'd0: lat_data_r = rd_min_r[rpt_blk];
                3'd1: lat_data_r = rd_max_r[rpt_blk];
                3'd2: lat_data_r = rd_cnt_r[rpt_blk];
                3'd3: lat_data_r = rd_p50_r[rpt_blk];
                3'd4: lat_data_r = rd_p95_r[rpt_blk];
                3'd5: lat_data_r = rd_p99_r[rpt_blk];
                default: lat_data_r = rd_ovf_r[rpt_blk];
            endcase
            2'd1: case (rpt_kind)
                3'd0: lat_data_r = wa_min_r[rpt_blk];
                3'd1: lat_data_r = wa_max_r[rpt_blk];
                3'd2: lat_data_r = wa_cnt_r[rpt_blk];
                3'd3: lat_data_r = wa_p50_r[rpt_blk];
                3'd4: lat_data_r = wa_p95_r[rpt_blk];
                3'd5: lat_data_r = wa_p99_r[rpt_blk];
                default: lat_data_r = wa_ovf_r[rpt_blk];
            endcase
            default: case (rpt_kind)
                3'd0: lat_data_r = wl_min_r[rpt_blk];
                3'd1: lat_data_r = wl_max_r[rpt_blk];
                3'd2: lat_data_r = wl_cnt_r[rpt_blk];
                3'd3: lat_data_r = wl_p50_r[rpt_blk];
                3'd4: lat_data_r = wl_p95_r[rpt_blk];
                3'd5: lat_data_r = wl_p99_r[rpt_blk];
                default: lat_data_r = wl_ovf_r[rpt_blk];
            endcase
            2'd3: lat_data_r = (rpt_kind == 3'd2) ? bb_cnt_r[rpt_blk]  // BB 计数
                                                  : 16'd0;
        endcase
    end
    assign lat_word = {rpt_blk, rpt_set, rpt_kind, done, 6'd0, lat_data_r};

    // PRE_WRITE 内全部 beat 已打完（最后一拍清 wvalid 后成立）
    wire wlast_done = (beat_cnt == 9'd0) && (wvalid == 1'b0);

    // start 两拍整形（同域；参考实现同款）
    always @(posedge axi_clk or negedge rstn) begin
        if (!rstn) begin
            start_sync0 <= 1'b0;
            start_sync1 <= 1'b0;
        end else begin
            start_sync0 <= start;
            start_sync1 <= start_sync0;
        end
    end

    // 状态机时序
    always @(posedge axi_clk or negedge rstn) begin
        if (!rstn)
            state <= IDLE;
        else begin
            case (state)
                IDLE:         if (start_sync1) state <= WRITE_ADDR;
                WRITE_ADDR:   state <= PRE_WRITE;
                // 本控制器：AWREADY 在 AWVALID && WVALID 之后才断言——
                // PRE_WRITE 等 AW/W 双 ready，或 beat 已全部在 PRE_WRITE 打完
                PRE_WRITE:   if (awready && (wready || wlast_done))
                                 state <= wlast_done ? POST_WRITE : WRITE;
                WRITE:        if (beat_cnt == 9'd0 && (!wvalid || wready))
                                  state <= POST_WRITE;
                // B 已事件化（b_got，见 §9 头注 9）：B 早返时在 PRE_WRITE/
                // WRITE 即被握手，判 bvalid 会死等
                POST_WRITE:   if (b_got)
                                  state <= (burst_idx == wr_limit - 16'd1)
                                           ? (TG_MODE ? TG_RD_REQ : READ_ADDR)
                                           : WRITE_ADDR;
                READ_ADDR:    if (arready) state <= PRE_READ;
                PRE_READ:     state <= READ_COMPARE;
                READ_COMPARE: if (rvalid && beat_cnt == 9'd0)
                                  state <= POST_READ;
                POST_READ:    state <= read_done ? DONE : READ_ADDR;
                // TG：全部 burst 收完 → 锁存耗时进轮间隔
                TG_RD_REQ:    if ((TG_MODE == 2) ? (lat_completed == rd_limit)
                                                 : (tg_completed == rd_limit))
                                  state <= TG_ROUND_GAP;
                TG_ROUND_GAP: if (gap_cnt >= TG_ROUND_GAP_TICKS - 32'd1)
                                  state <= (TG_MODE == 2)
                                             ? ((blk_idx == 4'd8) ? DONE : WRITE_ADDR)
                                   : (TG_MODE == 3 || TG_MODE == 4)
                                             ? ((blk_idx == 4'd8) ? DONE : TG_RD_REQ)
                                   : (TG_MODE == 5)
                                             ? ((blk_idx == 4'd8) ? DONE : WRITE_ADDR)
                                             : ((tg_ostd_r == TG_OSTD_MAX[4:0]) ? DONE
                                                                        : TG_RD_REQ);
                DONE:         state <= DONE;
                default:      state <= IDLE;
            endcase
        end
    end

    // 写/读数据指纹：地址低 32 位 + beat 序号低 8 位混合（高低 128 位组镜像，
    // 总宽 512 位精确匹配；参考实现同款结构）
    function [511:0] pat;
        input [32:0] a;
        input [8:0]  b;
        reg [31:0] ah;
        reg [7:0]  bc;
        begin
            ah = a[31:0];
            bc = b[7:0];
            pat = {{~ah, ah, {8{bc}}, ah, ~ah, {8{~bc}}},
                   { ah, ~ah, {8{~bc}}, ~ah, ah, {8{bc}}}};
        end
    endfunction

    // 数据/地址通路
    always @(posedge axi_clk or negedge rstn) begin
        if (!rstn) begin
            awaddr      <= START_ADDR;
            awvalid     <= 1'b0;
            awlen       <= 8'd0;
            awsize      <= 3'd0;
            awburst     <= 2'd0;
            awcache     <= 4'd0;
            awlock      <= 1'b0;
            awcobuf     <= 1'b0;
            awapcmd     <= 1'b0;
            awallstrb   <= 1'b0;
            awqos       <= 1'b0;
            araddr      <= START_ADDR;
            arid        <= 6'd0;
            arvalid     <= 1'b0;
            arlen       <= 8'd0;
            arsize      <= 3'd0;
            arburst     <= 2'd0;
            arlock      <= 1'b0;
            arapcmd     <= 1'b0;
            arqos       <= 1'b0;
            wdata       <= 512'd0;
            wvalid      <= 1'b0;
            wlast       <= 1'b0;
            bready      <= 1'b0;
            rready      <= 1'b0;
            beat_cnt    <= 9'd0;
            burst_idx   <= 16'd0;
            exp_rdata   <= 512'd0;
            rburst_done <= 1'b0;
            read_done   <= 1'b0;
            done        <= 1'b0;
            fail        <= 1'b0;
            err_cnt     <= 16'd0;
            tg_issued   <= 5'd0;
            tg_completed<= 5'd0;
            tg_ostd_r   <= 5'd1;
            tg_rd_cyc   <= 16'd0;
            tg_cyc_cnt  <= 16'd0;
            tg_araddr_next <= START_ADDR;
            gap_cnt     <= 32'd0;
            // per-RID 上下文必须复位：X 态会传染（X+1=X、X==63 恒假），
            // 导致 completed 永不加、pat 比对恒错（err 每 beat +1）
            rid_beat[0]  <= 6'd0;  rid_beat[1]  <= 6'd0;
            rid_beat[2]  <= 6'd0;  rid_beat[3]  <= 6'd0;
            rid_beat[4]  <= 6'd0;  rid_beat[5]  <= 6'd0;
            rid_beat[6]  <= 6'd0;  rid_beat[7]  <= 6'd0;
            rid_beat[8]  <= 6'd0;  rid_beat[9]  <= 6'd0;
            rid_beat[10] <= 6'd0;  rid_beat[11] <= 6'd0;
            rid_beat[12] <= 6'd0;  rid_beat[13] <= 6'd0;
            rid_beat[14] <= 6'd0;  rid_beat[15] <= 6'd0;
            rid_addr[0]  <= 33'd0; rid_addr[1]  <= 33'd0;
            rid_addr[2]  <= 33'd0; rid_addr[3]  <= 33'd0;
            rid_addr[4]  <= 33'd0; rid_addr[5]  <= 33'd0;
            rid_addr[6]  <= 33'd0; rid_addr[7]  <= 33'd0;
            rid_addr[8]  <= 33'd0; rid_addr[9]  <= 33'd0;
            rid_addr[10] <= 33'd0; rid_addr[11] <= 33'd0;
            rid_addr[12] <= 33'd0; rid_addr[13] <= 33'd0;
            rid_addr[14] <= 33'd0; rid_addr[15] <= 33'd0;
            // ---- MODE2 延迟标定机构复位 ----
            lat_issued    <= 16'd0;
            lat_completed <= 16'd0;
            lat_cyc       <= 32'd0;
            aw_lat0       <= 32'd0;
            wl_lat0       <= 32'd0;
            err_tot       <= 16'd0;
            lat_blk_load(4'd0);     // 块现场/统计 bank/per-RID 时戳清零
            for (bi = 0; bi < 9; bi = bi + 1) begin   // 块结果寄存清 X
                rd_min_r[bi] <= 16'd0; rd_max_r[bi] <= 16'd0; rd_cnt_r[bi] <= 16'd0;
                rd_p50_r[bi] <= 16'd0; rd_p95_r[bi] <= 16'd0; rd_p99_r[bi] <= 16'd0;
                rd_ovf_r[bi] <= 16'd0;
                wa_min_r[bi] <= 16'd0; wa_max_r[bi] <= 16'd0; wa_cnt_r[bi] <= 16'd0;
                wa_p50_r[bi] <= 16'd0; wa_p95_r[bi] <= 16'd0; wa_p99_r[bi] <= 16'd0;
                wa_ovf_r[bi] <= 16'd0;
                wl_min_r[bi] <= 16'd0; wl_max_r[bi] <= 16'd0; wl_cnt_r[bi] <= 16'd0;
                wl_p50_r[bi] <= 16'd0; wl_p95_r[bi] <= 16'd0; wl_p99_r[bi] <= 16'd0;
                wl_ovf_r[bi] <= 16'd0;
                bb_cnt_r[bi] <= 16'd0;
                // ---- MODE3 固定速率扫描机构复位 ----
                qd_cyc_r[bi] <= 16'd0; qd_bp_r[bi]  <= 16'd0;
                qd_if_r[bi]  <= 16'd0; qd_err_r[bi] <= 16'd0;
                // ---- MODE5 容量/别名探测机构复位 ----
                ad_hi_r[bi] <= 16'd0;  ad_al_r[bi] <= 16'd0;
            end
            qd_ivl_r   <= qd_ivl_f(4'd0);
            qd_gap     <= 16'd0;
            qd_bp_cnt  <= 16'd0;
            qd_if_peak <= 16'd0;
            // ---- MODE4 OOO 探测机构复位 ----
            oo_cnt     <= 16'd0;  oo_cnt_r   <= 16'd0;
            oo_first   <= 7'd0;   oo_first_r <= 7'd0;
            oo_comp    <= 4'd0;   oo_done_r  <= 6'd0;
            oo_err_r   <= 16'd0;
            for (bi = 0; bi < 8; bi = bi + 1)
                id_comp[bi] <= 2'd0;
            // ---- MODE5 计数器复位 ----
            ad_hi_err  <= 16'd0;
            ad_al_err  <= 16'd0;
        end else begin
            // ============================================================
            // MODE2 延迟采样（hoisted 于 case 前：读旧值，首 beat 判定安全）
            // ============================================================
            pct_launch <= 1'b0;         // 1 拍脉冲，case 内相尾可再置位（后写胜出）
            // B 握手事件化（全模式，勿入下方 TG_MODE 门控）：POST_WRITE 收尾
            // 判据 b_got，MODE0/1 同样依赖；B 早返时在 PRE_WRITE/WRITE 即到
            if (bvalid && bready && ((state == WRITE_ADDR) ||
                (state == PRE_WRITE) || (state == WRITE) ||
                (state == POST_WRITE)))
                b_got <= 1'b1;
            // Phase 3 固定速率扫描轮内统计（hoisted 同 MODE2 理由：读旧值）
            //   bp = arvalid&&!arready 拍数（对端拒绝=真反压，§8.4-4）
            //   if_peak = AR 握手拍在飞峰值。tg_issued 在置 VALID 拍已 +1，
            //   故握手拍在飞 = issued(旧) - completed(旧)，无 +1（+1 会双计：
            //   实测饱和 9>8 即此 bug——置位与握手隔拍，置位拍已计入）
            if (TG_MODE == 3 && state == TG_RD_REQ) begin
                if (arvalid && !arready)
                    qd_bp_cnt <= qd_bp_cnt + 16'd1;
                if (arvalid && arready &&
                    ({11'd0, tg_issued} - {11'd0, tg_completed}) > qd_if_peak)
                    qd_if_peak <= {11'd0, tg_issued} - {11'd0, tg_completed};
            end
            if (TG_MODE == 2) begin
                lat_cyc <= lat_cyc + 32'd1;
                if (awvalid && awready)                     // T_AW_B 基准
                    aw_lat0 <= lat_cyc;
                if (wvalid && wready && beat_cnt == 9'd0) begin  // T_WLAST_B 基准
                    wl_lat0 <= lat_cyc;
                    wlast_seen <= 1'b1;                     // WLAST 握手（BB 判据）
                end
                if (arvalid && arready)                     // T_AR_FIRST_R 基准
                    rid_lat0[arid[3:0]] <= lat_cyc;
                // 读：每 burst 首 R beat 采 T_AR_FIRST_R（丢 warm-up 后入直方图）
                if (rvalid && rready && state == TG_RD_REQ &&
                    rid_beat[rid] == 6'd0) begin
                    rd_smp <= rd_smp + 16'd1;
                    if (rd_smp >= TG_LAT_WARMUP) begin
                        rd_cnt <= rd_cnt + 16'd1;
                        if (|diff_rd[31:11])
                            rd_ovf <= rd_ovf + 16'd1;   // ≥2048 拍：窗口无效判据
                        else begin
                            if (diff_rd[15:0] < rd_min) rd_min <= diff_rd[15:0];
                            if (diff_rd[15:0] > rd_max) rd_max <= diff_rd[15:0];
                            rd_hist[diff_rd[10:6]] <= rd_hist[diff_rd[10:6]] + 16'd1;
                        end
                    end
                end
                // 写：B 握手采 T_AW_B 与 T_WLAST_B（写窗口 4 态——Phase 5
                // B 早返时在 PRE_WRITE/WRITE 即到达，仅 POST_WRITE 会漏；
                // b_got 已在上方全模式事件化，此处仅 MODE2 统计）
                if (bvalid && bready && ((state == WRITE_ADDR) ||
                    (state == PRE_WRITE) || (state == WRITE) ||
                    (state == POST_WRITE))) begin
                    if (!wlast_seen)                    // B 早于 WLAST（§8.6-3）
                        bb_cnt <= bb_cnt + 16'd1;
                    wa_smp <= wa_smp + 16'd1;
                    wl_smp <= wl_smp + 16'd1;
                    if (wa_smp >= TG_LAT_WARMUP) begin
                        wa_cnt <= wa_cnt + 16'd1;
                        if (|diff_aw[31:11])
                            wa_ovf <= wa_ovf + 16'd1;
                        else begin
                            if (diff_aw[15:0] < wa_min) wa_min <= diff_aw[15:0];
                            if (diff_aw[15:0] > wa_max) wa_max <= diff_aw[15:0];
                            wa_hist[diff_aw[10:6]] <= wa_hist[diff_aw[10:6]] + 16'd1;
                        end
                    end
                    if (wl_smp >= TG_LAT_WARMUP) begin
                        wl_cnt <= wl_cnt + 16'd1;
                        if (|diff_wl[31:11])
                            wl_ovf <= wl_ovf + 16'd1;
                        else begin
                            if (diff_wl[15:0] < wl_min) wl_min <= diff_wl[15:0];
                            if (diff_wl[15:0] > wl_max) wl_max <= diff_wl[15:0];
                            wl_hist[diff_wl[10:6]] <= wl_hist[diff_wl[10:6]] + 16'd1;
                        end
                    end
                end
            end
            case (state)
                IDLE: begin
                    awaddr  <= START_ADDR;
                    araddr  <= START_ADDR;
                    awvalid <= 1'b0;
                    arvalid <= 1'b0;
                    wvalid  <= 1'b0;
                    wlast   <= 1'b0;
                    bready  <= 1'b0;
                    rready  <= 1'b0;
                    done    <= 1'b0;
                    tg_ostd_r <= 5'd1;
                    tg_issued      <= 5'd0;
                    tg_completed   <= 5'd0;
                    tg_cyc_cnt     <= 16'd0;
                    tg_araddr_next <= START_ADDR;
                    gap_cnt <= 32'd0;
                    if (TG_MODE == 2)
                        lat_blk_load(4'd0);     // 首块现场装载（覆盖上方同值项）
                    if (TG_MODE == 3) begin
                        blk_idx    <= 4'd0;
                        qd_ivl_r   <= qd_ivl_f(4'd0);
                        qd_gap     <= 16'd0;
                        qd_bp_cnt  <= 16'd0;
                        qd_if_peak <= 16'd0;
                    end
                    if (TG_MODE == 4) begin
                        blk_idx    <= 4'd0;
                        qd_ivl_r   <= 16'd1;    // 背靠背（§8.7 制造并发）
                        qd_gap     <= 16'd0;
                        oo_cnt     <= 16'd0;
                        oo_first   <= 7'd0;
                        oo_comp    <= 4'd0;
                    end
                    if (TG_MODE == 5) begin
                        blk_idx    <= 4'd0;
                        ad_hi_err  <= 16'd0;
                        ad_al_err  <= 16'd0;
                    end
                end

                WRITE_ADDR: begin
                    awvalid <= 1'b1;
                    awlen   <= (TG_MODE == 2) ? blk_len_r : ALEN;
                    awsize  <= ASIZE;
                    awburst <= 2'b01;               // INCR
                    awqos   <= 1'b1;                // 参考 checker 同款（写通道 qos 置 1）
                    // Phase 5 B 时机矩阵（spec §8.6）：AWCACHE/AWCOBUF 按块表
                    // 装载；1111 板级 AW/W 死锁不入矩阵（plan §6-6/§9 Phase 2，
                    // 写基线 Phase 2 定稿 0000）
                    awcache <= blk_cache_r;
                    awcobuf <= blk_cobuf_r;
                    // BREADY_MODE=ALWAYS（§8.6-2）：B 早返时在写通道前段即可
                    // 握手；b_got/wlast_seen 每 burst 重装
                    bready  <= 1'b1;
                    b_got      <= 1'b0;
                    wlast_seen <= 1'b0;
                    wvalid  <= 1'b0;                // 每 burst 起始强制清（参考同款）
                    wlast   <= (cur_beats == 9'd1); // 1-beat 块：首拍即 WLAST
                    beat_cnt <= cur_beats - 9'd1;
                    wdata    <= pat(awaddr, cur_beats - 9'd1);
                    done     <= 1'b0;
                end

                PRE_WRITE: begin
                    // 控制器 WVALID-先于-AWREADY 型：W 在此起爆，期间发生的
                    // 传输同样计数（参考 checker 同款）；wlast 与末 beat 同拍
                    if (awready)
                        awvalid <= 1'b0;
                    wvalid <= 1'b1;
                    bready <= 1'b1;
                    if (wready && wvalid) begin
                        if (beat_cnt == 9'd0) begin
                            wvalid <= 1'b0;         // 最后 beat
                            wlast  <= 1'b0;
                        end else begin
                            if (beat_cnt == 9'd1)
                                wlast <= 1'b1;      // 与最后 beat 同拍
                            beat_cnt <= beat_cnt - 9'd1;
                            wdata    <= pat(awaddr, beat_cnt - 9'd1);
                        end
                    end
                end

                WRITE: begin
                    if (wready && wvalid) begin
                        if (beat_cnt == 9'd0) begin
                            wvalid <= 1'b0;         // 最后 beat（wlast 已同拍置位）
                            wlast  <= 1'b0;
                        end else begin
                            if (beat_cnt == 9'd1)
                                wlast  <= 1'b1;     // 与最后 beat 同拍
                            beat_cnt <= beat_cnt - 9'd1;
                            wdata    <= pat(awaddr, beat_cnt - 9'd1);
                        end
                    end
                end

                POST_WRITE: begin
                    if (wready)
                        wlast <= 1'b0;
                    // B 已事件化：早返 B 在 PRE_WRITE/WRITE 被握手时 b_got 已置，
                    // 进本态即收尾，无死等（Phase 5）
                    if (b_got) begin
                        bready <= 1'b0;
                        if (burst_idx == wr_limit - 16'd1) begin
                            araddr    <= START_ADDR;    // 读阶段从头比对
                            burst_idx <= 16'd0;
                            // TG：进入读扫描前的轮 1 初始化
                            if (TG_MODE) begin
                                tg_issued      <= 5'd0;
                                tg_completed   <= 5'd0;
                                lat_issued     <= 16'd0;
                                lat_completed  <= 16'd0;
                                tg_cyc_cnt     <= 16'd0;
                                tg_araddr_next <= START_ADDR;
                                err_cnt        <= 16'd0;    // 本轮独立计数
                                rready         <= 1'b1;
                                gap_cnt        <= 32'd0;
                            end
                            // MODE2：写相尾启动 WA→WL 分位数链（读相期间并行跑完）
                            if (TG_MODE == 2) begin
                                pct_launch      <= 1'b1;
                                pct_launch_set  <= 2'd1;    // WA
                                pct_launch_more <= 1'b1;    // 链式续跑 WL
                                pct_blk_r       <= blk_idx;
                                bb_cnt_r[blk_idx] <= bb_cnt; // BB 锁存（set=3 报告）
                            end
                        end else begin
                            // MODE5：第二笔写探针 Xi（第一笔已写参考 Yi）
                            awaddr    <= (TG_MODE == 5) ? ad_xi
                                                        : awaddr + cur_step;
                            burst_idx <= burst_idx + 16'd1;
                        end
                    end
                end

                READ_ADDR: begin
                    // araddr 由 POST_WRITE（末拍回 START_ADDR）与 POST_READ
                    // （+步进）维护，此处不得改写
                    arvalid <= 1'b1;
                    arlen   <= ALEN;
                    arsize  <= ASIZE;
                    arburst <= 2'b01;
                    beat_cnt <= BEATS - 9'd1;
                    exp_rdata <= pat(araddr, BEATS - 9'd1);
                    // AXI 握手纪律：VALID&&READY 完成后的次拍必须撤 VALID，
                    // 否则对端按拍重复接收。模型 arready 为组合电平（恒可收），
                    // 原实现握手后多保持 1 拍 ARVALID → 每个 AR 被收 2 条，
                    // 读比对整体错位一个命令（smoke TB err=192=3×64 实锤）。
                    // 真硬核 arready 握手后撤销，板测未暴露。同块内后写覆盖
                    // 上面的置位；对端 ready 恒低时行为不变（板级兼容）。
                    if (arvalid && arready)
                        arvalid <= 1'b0;
                end

                PRE_READ: begin
                    arvalid <= 1'b0;
                    rburst_done <= 1'b0;
                    rready  <= 1'b1;
                end

                READ_COMPARE: begin
                    if (rvalid) begin
                        if (rdata !== exp_rdata) begin
                            fail    <= 1'b1;        // sticky
                            err_cnt <= err_cnt + 16'd1;
                        end
                        if (beat_cnt != 9'd0) begin
                            beat_cnt  <= beat_cnt - 9'd1;
                            exp_rdata <= pat(araddr, beat_cnt - 9'd1);
                        end else begin
                            rburst_done <= 1'b1;
                            if (burst_idx == TOTAL_BURSTS - 16'd1)
                                read_done <= 1'b1;
                        end
                    end
                end

                POST_READ: begin
                    if (!read_done) begin
                        araddr    <= araddr + BURST_STEP;
                        burst_idx <= burst_idx + 16'd1;
                    end
                    rready <= 1'b1;
                end

                // ============================================================
                // TG 扫描：发（in-flight ≤ tg_ostd 门控）与收（per-RID 比对）
                // 同态并行；rd_cyc 从进入本态起计到收完为止（轮间口径一致）
                // ============================================================
                TG_RD_REQ: begin
                    rready     <= 1'b1;
                    tg_cyc_cnt <= tg_cyc_cnt + 16'd1;
                    // --- 发侧：空闲且未发完 → 发新条 ---
                    // MODE2 总量界限用 16 位 lat_issued（tg_issued 5 位回绕）；
                    // MODE1 在飞 < tg_ostd 门控；MODE3/4 不限在飞（qd_gap 分频
                    // 定发射节奏：MODE3 测对端拒绝点 §8.4，MODE4 背靠背制造
                    // 并发 §8.7）
                    if (!arvalid &&
                        ((TG_MODE == 2) ? (lat_issued < blk_n_r)
                                        : (tg_issued < ((TG_MODE == 5) ? rd_limit[4:0]
                                                                       : TG_N_BURST[4:0]))) &&
                        ((TG_MODE == 3 || TG_MODE == 4) ? (qd_gap == 16'd0)
                                        : ((tg_issued - tg_completed) < tg_ostd_r))) begin
                        arvalid        <= 1'b1;
                        // MODE4：ID_COUNT=8 轮转（s[2:0]，每 ID 2 笔，§8.7）；
                        // 其余：发射序低 4 位（16 ID 唯一；MODE5 串行 2 笔=0/1）
                        arid           <= (TG_MODE == 4) ? {3'b000, tg_issued[2:0]}
                                                         : {2'b00, tg_issued[3:0]};
                        // MODE5：两笔读地址 {Xi, Yi}（先读探针再读参考）
                        araddr         <= (TG_MODE == 5) ? ((tg_issued == 5'd0) ? ad_xi
                                                                                : ad_yi)
                                                         : tg_araddr_next;
                        arlen          <= (TG_MODE == 2) ? blk_len_r : ALEN;
                        arsize         <= ASIZE;
                        arburst        <= 2'b01;
                        // MODE5：两笔比对基准都是 pattern(Xi)——读 Yi 读回
                        // pattern(Xi) 即 Xi 回绕污染 Yi 实锤（alias_err==0）
                        rid_addr[tg_issued[3:0]] <= (TG_MODE == 5) ? ad_xi
                                                                   : tg_araddr_next;
                        tg_araddr_next <= (TG_MODE == 5) ? tg_araddr_next
                                                         : tg_araddr_next + cur_step;
                        tg_issued      <= tg_issued + 5'd1;
                        if (TG_MODE == 2)
                            lat_issued <= lat_issued + 16'd1;
                    end
                    // AXI 握手纪律（Phase 0 实锤）：握手次拍撤 VALID。
                    // 发侧以 !arvalid 门控，与本撤位互斥，无双驱动冲突。
                    // MODE3/4：握手拍重装发射分频（qd_gap==0 才允许置 VALID，
                    // 与递减分支互斥无冲突）
                    if (arvalid && arready) begin
                        arvalid <= 1'b0;
                        if (TG_MODE == 3 || TG_MODE == 4)
                            qd_gap <= qd_ivl_r - 16'd1;
                    end
                    if ((TG_MODE == 3 || TG_MODE == 4) && qd_gap != 16'd0)
                        qd_gap <= qd_gap - 16'd1;
                    // --- 收侧：按 RID 查上下文比对（乱序安全） ---
                    // 期望指纹用 (63-beat) 反序：写路径第 1 个 W beat 落内存
                    // offset 0 但携带 pat(addr,BEATS-1)，内存布局为 pat(addr,63-idx)
                    //（smoke 期望序列同为 63→0 递减，两处必须一致）
                    if (rvalid) begin
                        // MODE4：完成笔的期望地址按推导发射序查（同 ID 两笔共用
                        // rid 槽）；其余模式 rid=发射序直查
                        if (rdata !== pat((TG_MODE == 4) ? rid_addr[oo_rid_seq]
                                                         : rid_addr[rid],
                                          (cur_beats - 9'd1) - {2'b00, rid_beat[rid]})) begin
                            // MODE5 越界 err 是预期观测，不置全局 fail（§8.8）
                            fail    <= (TG_MODE == 5) ? fail : 1'b1;
                            err_cnt <= err_cnt + 16'd1;
                            if (TG_MODE == 5) begin
                                // 分流：rid 0=读 Xi（hi_err 不可访问信号）
                                //      rid 1=读 Yi（alias_err==0 即回绕污染）
                                if (rid == 6'd0)
                                    ad_hi_err <= ad_hi_err + 16'd1;
                                else
                                    ad_al_err <= ad_al_err + 16'd1;
                            end
                            if (TG_MODE == 2)
                                err_tot <= err_tot + 16'd1;   // 全局错误累计（块间不清）
                        end
                        if (rid_beat[rid] == last_beat) begin
                            rid_beat[rid] <= 6'd0;
                            tg_completed  <= tg_completed + 5'd1;
                            // MODE4 跨 ID 乱序检测（§8.7-3）：第 oo_comp 笔完成
                            // 的 ID 应= oo_comp[2:0]（发射 ID 序 0..7,0..7）；
                            // 错位即乱序。同 ID 内顺序 AXI 强制不检测。
                            if (TG_MODE == 4) begin
                                oo_comp <= oo_comp + 4'd1;
                                id_comp[rid[2:0]] <= id_comp[rid[2:0]] + 2'd1;
                                if (rid[2:0] != oo_comp[2:0]) begin
                                    oo_cnt <= oo_cnt + 16'd1;
                                    if (oo_cnt == 16'd0)      // 首错位快照
                                        oo_first <= {rid[2:0], oo_comp[3:0]};
                                end
                            end
                            if (TG_MODE == 2) begin
                                lat_completed <= lat_completed + 16'd1;
                                // 末条末 beat：读相尾启动 RD 分位数（无链）
                                if (lat_completed == rd_limit - 16'd1) begin
                                    pct_launch      <= 1'b1;
                                    pct_launch_set  <= 2'd0;    // RD
                                    pct_launch_more <= 1'b0;
                                    pct_blk_r       <= blk_idx;
                                end
                            end
                        end else begin
                            rid_beat[rid] <= rid_beat[rid] + 6'd1;
                        end
                    end
                end

                // TG 轮间隔：等 UART 发完本轮帧；进本态首拍锁存耗时，到点换轮
                TG_ROUND_GAP: begin
                    if (gap_cnt == 32'd0) begin
                        tg_rd_cyc <= tg_cyc_cnt;    // 一次性锁存
                        // MODE3：轮结果锁存（lat_word blk=档位报告）
                        if (TG_MODE == 3) begin
                            qd_cyc_r[blk_idx] <= tg_cyc_cnt;
                            qd_bp_r[blk_idx]  <= qd_bp_cnt;
                            qd_if_r[blk_idx]  <= qd_if_peak;
                            qd_err_r[blk_idx] <= err_cnt;
                        end
                        // MODE4：轮结果锁存（blk 恒 0 报告）
                        if (TG_MODE == 4) begin
                            oo_cnt_r   <= oo_cnt;
                            oo_first_r <= oo_first;
                            oo_done_r  <= tg_completed;
                            oo_err_r   <= err_cnt;
                        end
                        // MODE5：轮结果锁存（blk=探针号报告）
                        if (TG_MODE == 5) begin
                            ad_hi_r[blk_idx] <= ad_hi_err;
                            ad_al_r[blk_idx] <= ad_al_err;
                        end
                    end
                    if (gap_cnt >= TG_ROUND_GAP_TICKS - 32'd1) begin
                        gap_cnt <= 32'd0;
                        if (TG_MODE == 2) begin
                            // 装载下一测量块（FSM 本拍已决定 WRITE_ADDR 或 DONE）
                            if (blk_idx != 4'd8)
                                lat_blk_load(blk_idx + 4'd1);
                        end else if (TG_MODE == 3 || TG_MODE == 4) begin
                            // 下一轮：只重发读（数据用首轮布置，地址回 START
                            // 覆盖同区）；轮内统计清零。MODE3 逐档换 ivl，
                            // MODE4 恒背靠背重复采样
                            blk_idx        <= blk_idx + 4'd1;
                            qd_ivl_r       <= (TG_MODE == 4) ? 16'd1
                                                             : qd_ivl_f(blk_idx + 4'd1);
                            qd_gap         <= 16'd0;
                            qd_bp_cnt      <= 16'd0;
                            qd_if_peak     <= 16'd0;
                            tg_issued      <= 5'd0;
                            tg_completed   <= 5'd0;
                            tg_cyc_cnt     <= 16'd0;
                            tg_araddr_next <= START_ADDR;
                            err_cnt        <= 16'd0;    // 本轮独立计数
                            oo_cnt         <= 16'd0;
                            oo_first       <= 7'd0;
                            oo_comp        <= 4'd0;
                            id_comp[0]     <= 2'd0;  id_comp[1] <= 2'd0;
                            id_comp[2]     <= 2'd0;  id_comp[3] <= 2'd0;
                            id_comp[4]     <= 2'd0;  id_comp[5] <= 2'd0;
                            id_comp[6]     <= 2'd0;  id_comp[7] <= 2'd0;
                            rid_beat[0]    <= 6'd0;  rid_beat[1]  <= 6'd0;
                            rid_beat[2]    <= 6'd0;  rid_beat[3]  <= 6'd0;
                            rid_beat[4]    <= 6'd0;  rid_beat[5]  <= 6'd0;
                            rid_beat[6]    <= 6'd0;  rid_beat[7]  <= 6'd0;
                            rid_beat[8]    <= 6'd0;  rid_beat[9]  <= 6'd0;
                            rid_beat[10]   <= 6'd0;  rid_beat[11] <= 6'd0;
                            rid_beat[12]   <= 6'd0;  rid_beat[13] <= 6'd0;
                            rid_beat[14]   <= 6'd0;  rid_beat[15] <= 6'd0;
                        end else if (TG_MODE == 5) begin
                            // 下一轮探针：FSM 回写相（WRITE_ADDR），参考首笔
                            // 地址=下一探针的 Yi（写相第二笔由 POST_WRITE 装 Xi）
                            blk_idx        <= blk_idx + 4'd1;
                            ad_hi_err      <= 16'd0;
                            ad_al_err      <= 16'd0;
                            awaddr         <= ad_yi_n;
                            tg_issued      <= 5'd0;
                            tg_completed   <= 5'd0;
                            tg_cyc_cnt     <= 16'd0;
                            tg_araddr_next <= START_ADDR;
                            err_cnt        <= 16'd0;
                            rid_beat[0]    <= 6'd0;  rid_beat[1]  <= 6'd0;
                            rid_beat[2]    <= 6'd0;  rid_beat[3]  <= 6'd0;
                            rid_beat[4]    <= 6'd0;  rid_beat[5]  <= 6'd0;
                            rid_beat[6]    <= 6'd0;  rid_beat[7]  <= 6'd0;
                            rid_beat[8]    <= 6'd0;  rid_beat[9]  <= 6'd0;
                            rid_beat[10]   <= 6'd0;  rid_beat[11] <= 6'd0;
                            rid_beat[12]   <= 6'd0;  rid_beat[13] <= 6'd0;
                            rid_beat[14]   <= 6'd0;  rid_beat[15] <= 6'd0;
                        end else if (tg_ostd_r != TG_OSTD_MAX[4:0]) begin
                            tg_ostd_r      <= tg_ostd_r + 5'd1;
                            tg_issued      <= 5'd0;
                            tg_completed   <= 5'd0;
                            tg_cyc_cnt     <= 16'd0;
                            tg_araddr_next <= START_ADDR;
                            err_cnt        <= 16'd0;    // 新一轮独立计数
                            rid_beat[0]    <= 6'd0;  rid_beat[1]  <= 6'd0;
                            rid_beat[2]    <= 6'd0;  rid_beat[3]  <= 6'd0;
                            rid_beat[4]    <= 6'd0;  rid_beat[5]  <= 6'd0;
                            rid_beat[6]    <= 6'd0;  rid_beat[7]  <= 6'd0;
                            rid_beat[8]    <= 6'd0;  rid_beat[9]  <= 6'd0;
                            rid_beat[10]   <= 6'd0;  rid_beat[11] <= 6'd0;
                            rid_beat[12]   <= 6'd0;  rid_beat[13] <= 6'd0;
                            rid_beat[14]   <= 6'd0;  rid_beat[15] <= 6'd0;
                        end
                    end else begin
                        gap_cnt <= gap_cnt + 32'd1;
                    end
                end

                DONE: begin
                    done <= 1'b1;
                end

                default: ;
            endcase
        end
    end

endmodule
