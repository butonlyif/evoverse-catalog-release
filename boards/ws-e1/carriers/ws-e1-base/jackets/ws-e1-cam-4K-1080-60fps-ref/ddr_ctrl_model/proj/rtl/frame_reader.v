// ============================================================================
// frame_reader.v — DDR RAW10 帧回放读主控（v4 架构：显示域回放 + 帧级仲裁）
//（2026-10-21，SPEC-001 mod-frame-reader-v3）
// v4.10（载体重构）：回放流输出改 64b 载体（与 frame_writer 打包序一致：
//   每 512b 字 8 拍切片 [64k+63:64k]，beat0 最低位），demosaic 前在
//   camera_path 连线层切片 [39:0]（RAW10 段仅低 40b 有效）。行长 7680B =
//   120 word，突发 64+56 拍；组间发射无停顿（bg33..38 重叠预取）。
// ============================================================================
//
// v4 相对 v3.4 的变更（背景：门控路线 v26~v29 证伪，SPEC-001 结构消除）：
//   1) 时钟域整体搬入 148.5MHz 显示域（aclk=pixel_clk）——与 ISP/TX 同域，
//      camera_path 内数据路径 CDC（async_path_fifo）整体删除。
//   2) 帧槽节拍源 = disp_timing 本地行节拍（同域直连 line_tick，2250 槽/帧，
//      D6：+1 相位余量随门控删除而退役）。显示帧率恒 60.000Hz 与源解耦（R1）。
//   3) 帧请求 = writer 帧发布脉冲（wr_frame_done，200M 域单拍）经 2FF+
//      syn_keep 取沿（D3）——替代 v3.4 的 wr_par 电平沿 + wr_frame_cnt
//      多比特跨域（多比特跨域在双异步端口下不安全）。bank 选择用
//      wr_frame_par 电平 2FF（与脉冲同拍翻转，槽 fire 时早已稳定）。
//   4) 帧级仲裁（alg-bank-handoff）：
//        - 槽 fire 有请求沿 → 切读最新完整帧（bank = ~wr_frame_par_sync）；
//          沿堆积合并计 drop（写快于读）
//        - 槽 fire 无请求沿 → 重读当前 bank 计 repeat（读快于写）
//        - 起步门：收到脉冲计数 done_cnt >= 2 才解禁（帧乒乓安全）
//   5) drop_cnt/repeat_cnt 经 dbg_fr_cnt_o 上报（R9 板测核心观测点）。
//   6) disp_open 端口删除（v3.4 已不消费，v4 顶层同步删）。
//
// v3.4 历史教训（保留存档，见 git）：显示节奏必须由本模块以与显示同源的
//   tick 自由跑产生，不得依赖任何被显示行为反馈的信号（v3.1~v3.3 三代死
//   环教训）。v4 的 line_tick 源 = disp_timing 本地节拍（同源单向 disp→
//   reader），源侧任何信号（done/par）都不进入节奏链——门控同类失败（RK-4）
//   在本模块结构上无复活点。
//
// 帧级频偏吸收（与 frame_writer 分工）：writer 整帧或全无（残帧不发布），
//   reader 槽粒度 drop/repeat（快向丢弃过期发布、慢向重放最近完整帧），
//   显示时序恒 60.000Hz。本模块不做行级 ppm 补偿。
//
// 节拍（v2.1 乒乓预取，不变）：
//   双行 RAM 乒乓。读路径恒超前发射路径恰好 1 行：发射第 n 行期间，第 n+1
//   行的 64+11 两突发收字写入另一 bank——DDR 读延迟与 1046 拍发射期重叠。
//   行不丢原则：tick 到而数据未就绪时置 delayed，就绪拍立即发射（行延迟
//   数拍不丢行槽）；每延迟一 tick 计一次 late。
//
// 读写解耦：读路径写 bank w_sel，发射路径读 bank r_sel，约束 w_sel==r_sel
//   时才允许读路径翻 bank 发起下一行——读路径恒超前 1 行，无写读竞争。
//
// AXI 契约（板级验证于 ddr_memcheck / v1 frame_reader）：arvalid 置起等
//   arready（清）；PRE 拍后收 beat；rready 仅 PRE/R_RD 为高（v4.1，见读
//   路径头注）；arqos=0；INCR；rlast 与
//   段末 beat 同拍。
// ============================================================================

module frame_reader #(
    parameter [15:0] VACT        = 16'd2160,        // 每帧行数
    parameter [15:0] FRAME_TICKS = 16'd2250,        // 显示帧槽周期（参考值，
                                                    // v4.7 授权锚 = disp_sof_i
                                                    // 帧界沿，本参数退役保留
                                                    // 兼容顶层参数透传）
                                                    // 2250 = 2160 数据 + 90 pad
                                                    //（D6：v3.4 的 2251 是门控
                                                    // 相位裕量补丁，v4 无源-sof
                                                    // 门，显示帧周期严格 2250）
    parameter [32:0] FRAME_A  = 33'h0_0000_0000,
    parameter [32:0] FRAME_B  = 33'h0_1100_0000,
    parameter [11:0] ANCHOR_WAIT = 12'd0
    // v4.10c3h 锚窗口对齐（B 问题正解）：锚（disp_sof 下降沿）后先空转
    // ANCHOR_WAIT 个 tick 再开始发射行 0——供给起点对齐显示 Va 开拉点
    // （disp_timing VSP+VBP，顶层传 ANCHOR_WAIT=VSP+VBP-余量），发射与
    // 消费平行恒速，消除 v4.10c3g 背压跟随态（帧尾滞后+abort 断流破坏
    // demosaic 3 行窗 = 板测顶+底恒闪）。余量须覆盖：grant+DDR 首字
    // ~0.2 行 + demosaic 3 行窗冲洗 2 行（板级 82-4=78，tb 6-2=4）。
)(
    input  wire          aclk,          // 148.5MHz 显示域（v4：pixel_clk）
    input  wire          rstn,
    input  wire          flush_i,       // v4.10c3e 源切换安全清零（1ms 宽）：
                                        // 在 AXI 无在途拍清发射/读路径账本
                                        // 与起步门计数——切换复刻上电流程
                                        //（reader 等 writer 重新发布 >=2 帧
                                        // 才开工），杜绝跨切换状态污染。
                                        // 不碰 AXI 在途突发（无楔死风险）
    input  wire          enable,        // 帧请求受理门（v3 恒 1：DDR 回放唯一来源）
    input  wire          line_tick,     // 行节拍（disp_timing 自由跑 1100，同域直连）
    input  wire          line_room_i,   // v4.4：显示侧行缓冲有空间（tx_line_buf
                                        // 水位——reader 与 display 同域，该反
                                        // 馈为显示域内部握手，不违反 R1）
    input  wire          disp_sof_i,    // v4.9：显示帧界（disp_timing vsync，
                                        // 同 aclk 域，模块内取沿）——帧授权锚
    input  wire          disp_stall_i,  // v4.9：显示断粮（tlb 水位 < 1 行整）——
                                        // 帧尾救援/引导授权（demosaic 3 行窗
                                        // 需下一帧行 0 冲刷末行，vsync 锚到点
                                        // 前显示已饿 -> 由此喂链解锁帧完成）
    // ---- 帧握手（raw = 200M 域原始信号，模块内 2FF+syn_keep 同步）----
    input  wire          wr_frame_done, // writer 帧发布单拍脉冲（200M 域）
    input  wire          wr_frame_par,  // writer 当前填充 bank 电平（200M 域）
    // ---- 回放流输出（v4.10 64b 载体，打包序同 frame_writer，直入
    //      demosaic 前链路，camera_path 连线层切片 [39:0] 喂 ISP）----
    output reg  [63:0]   m_axis_tdata,
    output reg           m_axis_tvalid,
    output reg           m_axis_tlast,  // EOL（每行末拍）
    output reg  [2:0]    m_axis_tuser,  // {eof, sol, sof}
    // ---- AXI 读主口 ----
    output wire [5:0]    arid,
    output reg  [32:0]   araddr,
    output reg  [7:0]    arlen,
    output reg  [2:0]    arsize,
    output reg [1:0]    arburst,
    output reg           arlock,
    output reg           arvalid,
    output reg           arapcmd,
    output reg  [3:0]    arqos,
    input  wire         arready,
    input  wire [5:0]    rid,
    input  wire [511:0]  rdata,
    input  wire          rlast,
    input  wire          rvalid,
    output reg           rready,
    input  wire [1:0]    rresp,
    // ---- 状态（诊断级）----
    output wire [15:0]   rd_frame_cnt,  // 已发射帧数
    output wire [11:0]   rd_line,       // 帧内行进度（发射路径）
    output wire [3:0]    rd_state,
    output wire          flush_done_o,  // v4.10c3f flush 执行拍单拍脉冲（同
                                        // pixel_clk 域透传顶层）：驱动显示
                                        // 链与 reader 停流同步复位
    output wire [31:0]   rd_err,        // {late[7:0], miss[7:0], err[7:0], 8'h0}
    output wire [31:0]   dbg_fr_cnt     // v4（R9）：{drop_cnt[15:0], repeat_cnt[15:0]}
);

    localparam [9:0]  BEATS_PER_LINE  = 10'd960;   // 960 x 64b = 7680B
    localparam [6:0]  WORDS_PER_LINE  = 7'd120;    // 7680B / 64B
    localparam [8:0]  WB0_BEATS       = 9'd64;     // 4096B（4KB 窗内）
    localparam [8:0]  WB1_BEATS       = 9'd56;     // 3584B
    localparam [4:0]  GROUPS_PER_LINE = 5'd24;     // 24 组 x 8 拍 x 64b
    localparam [5:0]  BG_PER_GROUP    = 6'd40;     // 组内发射拍

    // 发射路径状态
    localparam [2:0] S_IDLE  = 3'd0,   // 等帧请求
                     S_WAIT  = 3'd1,   // 等 tick + 数据就绪
                     S_FETCH = 3'd2,   // 行首组 5 字预取（6 拍，仅组 0）
                     S_SHIFT = 3'd3;   // 组 40 拍 64bit 发射（组间无停顿，
                                       // bg33..38 尾部重叠预取下一组）
    // 读路径状态
    localparam [2:0] R_IDLE  = 3'd0,   // 等帧请求
                     R_AR    = 3'd1,   // AR 握手
                     R_PRE   = 3'd2,   // 突发准备
                     R_RD    = 3'd3,   // 收字入行 RAM
                     R_GAP   = 3'd4,   // 等发射指针追上（bank 消费完）
                     R_DONE  = 3'd5;   // 帧读完，等下一帧请求

    //--------------------------------------------------------------------
    // v4.10c3e flush_i 安全清零：rd_safe = AXI 读通道无在途事务的状态
    // 集。R_GAP 行间必现 => 1ms flush 窗内必有执行拍。清零放主 always
    // case 之后（最后赋值优先，覆盖 case 同拍赋值），一次执行防重入。
    // （rd_safe/flush_fire 定义在 r_st 声明之后——vlog 不容前向引用）
    //--------------------------------------------------------------------

    //--------------------------------------------------------------------
    // 帧握手跨域（v4，D3/D4）：writer 的 done 脉冲与 par 电平均为 200M
    // 域信号，模块内 2FF + syn_keep 同步到显示域。
    //   - done：2FF 后取沿 = 帧请求（本域单拍）
    //   - par ：2FF 后电平 = bank 选择（槽 fire 时距脉冲沿 >= 0 拍、
    //           通常 0~2250 tick，2FF 早已稳定；电平随最新完成帧翻转）
    // syn_keep：跨钟同步链严禁被综合器重定时/合并/复制（2026-10-19 板测
    //   par_sync 未被读被优化掉致假帧界前科，同款第 4 次）——纪律集中
    //   在本模块寄存器上，顶层只做原始信号布线。
    //--------------------------------------------------------------------
    (* syn_keep = "true" *) reg [1:0] done_sync;
    (* syn_keep = "true" *) reg [1:0] par_sync;
    always @(posedge aclk or negedge rstn)
        if (!rstn) begin
            done_sync <= 2'b00;
            par_sync  <= 2'b00;
        end else begin
            done_sync <= {done_sync[0], wr_frame_done};
            par_sync  <= {par_sync[0],  wr_frame_par};
        end
    wire frame_req = enable && done_sync[0] && !done_sync[1];   // 本域单拍沿

    //--------------------------------------------------------------------
    // 帧授权锚（v4.9）：显示帧界取沿。vsync 低有效（Vs 段为低）——
    // **下降沿 = Vs 段起点** = Va[0] 前 41 行（VSP5+VBP36），行 0 推送
    // + demosaic 链 ~2 行冲洗恰好落在 41 行窗口内，Va[0] 门点（水位
    // ≥1 行）足额零冻结。上升沿（Vs 结束）亦可但裕量少 5 行。
    //   板级/仿真证据链（v4.5~v4.9 五代收敛）：
    //   v4.5 slot 自由跑：pattern 板级正确（slot 与显示同频同域锁定），
    //        camera 态 40Hz（发射窗拉满 2250 tick 与槽点同拍竞速，差 1
    //        拍即错过整槽）。
    //   v4.6 R_DONE / v4.8 水位需求授权：帧率对但 reader 帧界与显示帧界
    //        无锁——发射完即再授权（水位稳态 ~1088 字恒过 ≤1088 门），
    //        sof-to-sof = 2160+ε tick << 显示 2250 tick，内容边界每帧
    //        前移 ~90 行 = 斜向卷（板级目视实锤）。
    //   v4.9 上升沿首版 + tb 死锁解剖：GATE 门限单位错（960 px vs 600
    //        字，见 camera_path LINE_WORDS 注释）致帧尾每帧冻结拉伸；
    //        冷启动 tlb 空 -> Va[0] 门冻结 -> vsync 卡高无沿 -> 引导死锁
    //        （tb 8ms frame_num=0/disp_sof_i=1 实锤）。
    //   v4.9 终版：下降沿锚 + boot 豁免 + 门限 600 字。
    //--------------------------------------------------------------------
    reg sof_d;
    always @(posedge aclk or negedge rstn)
        if (!rstn) sof_d <= 1'b1;           // vsync 低有效：复位态按高算
        else       sof_d <= disp_sof_i;
    wire disp_sof = !disp_sof_i && sof_d;   // 下降沿 = Vs 起点（帧界）

    //--------------------------------------------------------------------
    // 帧级仲裁（v4，alg-bank-handoff）：
    //   起步门：done_cnt（本域脉冲计数）>=2 才解禁——两 bank 均有完整帧，
    //     首次读安全（帧乒乓）。done_cnt 16bit 回绕无害（只判 >=2 与
    //     parity 无关）。
    //   请求粘滞：脉冲到而未到槽拍 → req_pending 锁存；槽拍受理。
    //     沿到而已有积压（pending 未消费）= 快向跳帧 → drop_cnt++（合并，
    //     槽拍仅消费最新完成帧）。
    //   槽 fire：
    //     - pending=1 → 切读最新完整帧 bank = ~par_level（writer 已翻离
    //       的 bank；合并期间 writer 或又完成多帧——par 电平跟随最新，
    //       天然"最新帧优先"）
    //     - pending=0 → 重读当前帧（par_r 不变）→ repeat_cnt++（读快于写）
    //--------------------------------------------------------------------
    reg  req_pending;
    reg  [15:0] done_cnt;    // 帧发布脉冲计数（本域，起步门用）
    reg  [15:0] drop_cnt_r, repeat_cnt_r;
    // （arm_fresh/frame_avail/next_par/frame_grant 见下方主状态寄存之后）

    //--------------------------------------------------------------------
    // 主状态寄存
    //--------------------------------------------------------------------
    reg [2:0]  st;             // 发射路径
    reg [2:0]  r_st;           // 读路径
    reg        par_r;          // 本帧读取基址（0=A 1=B，= writer 刚填完的帧）
    reg [11:0] line_r;         // 发射路径帧内行号
    reg [11:0] rdln;           // 读路径帧内行号（恒 <= line_r+1）
    reg        w_sel, r_sel;   // 读/发射 bank 指针（乒乓）
    reg [1:0]  rdy;            // bank 就绪位
    reg        delayed;        // tick 到而数据未就绪（行延迟发射中）
    reg [11:0] anchor_cnt;     // v4.10c3h 锚窗口倒计数（S_WAIT 空转期）
    reg        bi;             // 行内突发序号（0=4096B 段 1=3584B 段）
    reg [8:0]  beat_cnt;       // 突发内剩余拍
    reg [6:0]  word_cnt;       // 行内已收字（0..119）
    reg [4:0]  group;          // 组号（0..23）
    reg [5:0]  bg;             // 组内发射拍（0..39）
    reg [3:0]  fetch_cnt;      // 预取拍（0..5，行首组 0 专用）
    reg [6:0]  ra_r;           // 行 RAM 读址（= group*5 + r）
    reg [10:0] bline;          // 行内发射拍号（0..959，帧格式用）
    reg [2559:0] sr;           // 组移位链：5 字 x 512b = 2560b，40 拍 x 64b
                               // 发射（每拍 sr[63:0]，右移 64），beat k =
                               // 装载词序第 k/8 字的 [64(k%8)+63:64(k%8)]
                               // （v4.10b 修复：v4.10 首版误为 512b，Verilog
                               // 截断后每组仅字 0 有效 -> 板测 24 个 128px
                               // 等宽黑区/行；tb 校验器门缺陷漏检，见下）

    // v4.10c3e flush_i 安全清零（wire 定义放声明后，vlog 不容前向引用）
    reg  flush_done_r;
    wire rd_safe    = !arvalid && (r_st == R_IDLE || r_st == R_GAP
                                   || r_st == R_DONE);
    wire flush_fire = flush_i && !flush_done_r && rd_safe;
    assign flush_done_o = flush_fire;
    reg [511:0] hold0, hold1, hold2, hold3;
    reg [15:0] frame_cnt_r;
    reg [7:0]  err_r, late_r, miss_r;
    reg [7:0]  req_r;    // frame_req 脉冲计数（诊断：对照 fw.frm 判定
                         // 边频是否被源头吞半——2026-10-19 半帧率排查）

    //--------------------------------------------------------------------
    // 帧级仲裁（v4，alg-bank-handoff）组合逻辑与时序
    //   起步门 done_cnt>=2；请求粘滞；槽 fire 三态（切换/重读/合并）
    //--------------------------------------------------------------------
    wire arm_fresh   = frame_req && (done_cnt >= 16'd2);
    wire frame_avail = (req_pending || arm_fresh || (done_cnt >= 16'd2));
    wire next_par    = (req_pending || arm_fresh) ? ~par_sync[1] : par_r;
    // v4.9：授权 = 双路空闲 + [显示帧界（vsync 下降沿 = Vs 起点，帧界
    // 相位钉扎——v4.6/4.8 无锚斜卷根除）OR 断粮救援（tlb < 1 行整，帧
    // 尾/引导喂链——demosaic 3 行窗死锁根除）]。
    // 救援无相位滑移：FIFO 顺序保内容对齐，救援早推的行只是加深缓冲，
    // 显示按序消费（v4.8 滑移源于 1088 门=稳态水位致每帧 +90 行无界
    // 前移；600 门=断粮点，每显示帧仅穿越一次，周期=显示 2250 tick）。
    // boot_granted 与救援冗余，保留兜底（首拍水位语义不确定时保授权）。
    reg boot_granted;
    // ---- v4.10c3g 残帧放弃（B 问题根除：固定偏移+底部闪区）----
    // 死锁结构（tb 实测：phi=锚后 94.6 行才发行 0 vs psi=显示 Va[0] 开拉
    // 6 行）：锚（disp_sof 下降沿）时 reader 正在发射上一帧残行
    // （st!=S_IDLE）→ frame_grant 因 st!=S_IDLE 且 disp_sof 单拍沿而错过
    // → 等 disp_stall_i（tlb 见底）救援才授权 → 新帧行 0 固定迟到 D 行 →
    // 显示帧尾 GATE 冻结 D 行（frz=行 89=底部闪区）且 D=画面偏移量（闪区
    // =偏移部分，板级 82 行窗口下即"几十行"）。每帧自我维持，不自愈。
    // 修复：锚拍残帧放弃——发射态回 S_IDLE 断流，pend_grant 挂起本锚授权，
    // 读路径安静（r_quiet）后立即受理 → 行 0 提前 ~90 行，供给在显示开拉
    // 前到位（tb 空窗 ~1.5 行 < VSP+VBP=6；板级 <82），水位不再见底，帧尾
    // 零冻结。读路径不打断：在途旧突发自然收完（r_st 离开 R_RD 后其数据
    // 不满足 lram_we 自然丢弃；同 ID 按序无混流，grant 时旧数据已全部落
    // bank，新帧行 0 同址覆盖）。
    reg  pend_grant;
    wire abort_frame = disp_sof && frame_avail && (st != S_IDLE);
    wire r_quiet     = (r_st == R_IDLE) || (r_st == R_GAP)
                       || (r_st == R_DONE);
    wire frame_grant = (st == S_IDLE) && frame_avail && r_quiet &&
                       (disp_sof || pend_grant || disp_stall_i
                        || !boot_granted);
    always @(posedge aclk or negedge rstn)
        if (!rstn) begin
            req_pending   <= 1'b0;
            done_cnt      <= 16'd0;
            drop_cnt_r    <= 16'd0;
            repeat_cnt_r  <= 16'd0;
            boot_granted  <= 1'b0;
        end else if (flush_fire) begin
            // v4.10c3e 源切换：起步门/挂起请求清零——reader 等 writer
            // flush 后重新发布 >=2 帧才解禁（切换复刻上电流程）
            done_cnt     <= 16'd0;
            req_pending  <= 1'b0;
            boot_granted <= 1'b0;
        end else begin
            // v4.2 同拍语义：grant 与 req 同拍时 par_sync[1] 滞后 2 拍不
            // 含本拍沿——本拍受理的是更早的帧，新沿必须顺延为 pending，
            // 否则该帧被静默丢弃（原码 else 分支被 grant 抢走，S0 起步
            // 丢 fid1、±2% 段 drop/repeat 计数与流行为颠倒实锤）。
            // drop 只在"沿到且积压未被本拍受理"时计（合并跳帧）。
            if (frame_req && req_pending && !frame_grant)
                drop_cnt_r <= drop_cnt_r + 16'd1;
            if (frame_req)
                done_cnt <= done_cnt + 16'd1;
            if (frame_grant) begin
                req_pending <= frame_req;             // 受理旧沿；同拍新沿顺延
                boot_granted <= 1'b1;                 // v4.9：引导豁免仅首帧
                if (!req_pending && !arm_fresh)       // 槽拍无新沿 = 慢向重读
                    repeat_cnt_r <= repeat_cnt_r + 16'd1;
            end else if (arm_fresh) req_pending <= 1'b1;   // 未受理：粘滞待帧界
        end

    assign dbg_fr_cnt = {drop_cnt_r, repeat_cnt_r};

    // 读路径行基址 stride 8KB（line<<13）恒 4KB 对齐 => 64+56 两突发各自
    // 完全落在单个 4KB 地址窗内，满足 AXI burst 不跨 4KB 边界
    wire [32:0] rd_base = (par_r ? FRAME_B : FRAME_A) + {8'd0, rdln, 13'd0};

    assign rd_frame_cnt = frame_cnt_r;
    assign rd_line      = line_r;
    assign rd_state     = st;
    assign rd_err       = {late_r, miss_r, err_r, req_r};

    //--------------------------------------------------------------------
    // 行 RAM x2（乒乓，各 128x512，一行 120 字）
    //   写口：读路径收 AXI 字（w_sel bank）
    //   读口：发射路径组预取（r_sel bank）
    // BRAM 推断纪律（与 frame_writer mem / shape mem 同款，综合器
    // 推不出"读语句内条件选存储体"——曾整阵列落 FF 致资源超限）：
    //   1) 写/读口各自独立 always 块，每条语句只涉及单一阵列
    //   2) 读口无条件每拍同步读，单寄存器地址，读数据寄存器无复位值
    //   3) bank 二选一放在读寄存器之后
    //--------------------------------------------------------------------
    (* syn_ramstyle = "block_ram" *) reg [511:0] lram0 [0:127];
    (* syn_ramstyle = "block_ram" *) reg [511:0] lram1 [0:127];
    wire         lram_we = (r_st == R_RD) && rvalid && rready;
    wire [6:0]   lram_wa = word_cnt;
    reg  [511:0] lram0_q, lram1_q;

    always @(posedge aclk) begin
        if (lram_we && !w_sel) lram0[lram_wa] <= rdata;
        if (lram_we &&  w_sel) lram1[lram_wa] <= rdata;
    end

    always @(posedge aclk) begin
        lram0_q <= lram0[ra_r];
        lram1_q <= lram1[ra_r];
    end
    wire [511:0] lram_q = r_sel ? lram1_q : lram0_q;
    // 下一组首字址（group*5 + 5；仅 S_SHIFT bg33..38 重叠预取消费）
    wire [6:0] ra_next = {1'b0, group, 2'b00} + {2'b00, group} + 7'd5;

    assign arid     = 6'h0;

    always @(posedge aclk or negedge rstn) begin
        if (!rstn) begin
            st            <= S_IDLE;
            r_st          <= R_IDLE;
            flush_done_r  <= 1'b0;
            par_r         <= 1'b0;
            line_r        <= 12'd0;
            rdln          <= 12'd0;
            w_sel         <= 1'b0;
            r_sel         <= 1'b0;
            rdy           <= 2'b00;
            delayed       <= 1'b0;
            bi            <= 1'b0;
            beat_cnt      <= 9'd0;
            word_cnt      <= 7'd0;
            group         <= 5'd0;
            bg            <= 6'd0;
            fetch_cnt     <= 4'd0;
            ra_r          <= 7'd0;
            bline         <= 11'd0;
            sr            <= 2560'd0;
            hold0         <= 512'd0;
            hold1         <= 512'd0;
            hold2         <= 512'd0;
            hold3         <= 512'd0;
            frame_cnt_r   <= 16'd0;
            err_r         <= 8'd0;
            late_r        <= 8'd0;
            miss_r        <= 8'd0;
            req_r         <= 8'd0;
            araddr        <= 33'd0;
            arlen         <= 8'd0;
            arsize        <= 3'd0;
            arburst       <= 2'd0;
            arlock        <= 1'b0;
            arvalid       <= 1'b0;
            arapcmd       <= 1'b0;
            arqos         <= 4'd0;
            rready        <= 1'b0;
            pend_grant    <= 1'b0;   // v4.10c3g（单驱动：仅本 always）
            m_axis_tdata  <= 64'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            m_axis_tuser  <= 3'd0;
        end else begin
            // 发射通道默认关（S_SHIFT 拍内置起，逐拍一个 beat）
            m_axis_tvalid <= 1'b0;

            // v4.10c3g：授权受理拍清挂起（abort_frame 与 frame_grant 同拍
            // 互斥——前者要求 st!=S_IDLE，后者要求 st==S_IDLE）
            if (frame_grant)
                pend_grant <= 1'b0;

            // 帧请求沿计数；沿到而已有积压（pending 未消费）= 快向跳帧
            if (frame_req)
                req_r <= req_r + 8'd1;
            if (frame_req && req_pending)
                miss_r <= miss_r + 8'd1;

            //================================================================
            // 发射路径（tick 驱动，消费 bank r_sel）
            //================================================================
            case (st)
            S_IDLE: begin
                if (frame_grant) begin
                    par_r       <= next_par;       // 新帧沿 / 慢向重读（v3.4）
                    line_r      <= 12'd0;
                    rdln        <= 12'd0;          // v4：行基址账本随帧清零——
                                                   // rd_base 组合含 rdln（×8KB），
                                                   // 跨帧残留使 burst1/R_GAP 的
                                                   // AR 地址随帧数漂移（单元 TB
                                                   // 实锤：burst0 全对、burst1
                                                   // 跳到行 208 word4=第 3 帧
                                                   // rdln 累计位置）
                    r_sel       <= 1'b0;
                    rdy         <= 2'b00;          // v4：清残留就绪位（重读
                                                   // 帧乒乓须从干净状态起步，
                                                   // 上一帧末行 rdy 残留会使
                                                   // 发射超前于读路径写入）
                    delayed     <= 1'b0;
                    anchor_cnt  <= ANCHOR_WAIT;  // v4.10c3h 锚窗口重置
                    frame_cnt_r <= frame_cnt_r + 16'd1;
                    st          <= S_WAIT;
                end
            end
            S_WAIT: begin
                // v4.10c3h 锚窗口对齐：锚后先空转 ANCHOR_WAIT 个 tick（不
                // 计 late——设计性延迟，非数据缺失）。等待期读路径照常预
                // 取（rdy 先行置位），发射起点整体右移对齐显示开拉点。
                if (line_tick && anchor_cnt != 12'd0)
                    anchor_cnt <= anchor_cnt - 12'd1;
                // 数据未就绪：延迟发射（行不丢，就绪拍立即出），计 late
                if (line_tick && !rdy[r_sel] && anchor_cnt == 12'd0) begin
                    delayed <= 1'b1;
                    late_r  <= late_r + 8'd1;
                end
                // 就绪：tick 拍或延迟追发拍启动组 0（v4.4：加 line_room——
                // 显示行缓冲须有整行空间才发射，防 pad 期显示不拉取时
                // 溢出；空间等待不计 late——非数据缺失）
                // （v4.10c 回退记录：v4.10b 曾给行 0 开"免 tick 专用窗"，
                //   板测证实为恶性回归——行 0 在授权+DDR 读返回拍才入 tlb，
                //   晚于显示帧头拉取 → 首行拉空 → disp_stall → 救援循环 →
                //   频繁黑屏并棘轮挂死。发射节拍必须与显示拉取节拍逐行
                //   tick 锁定，帧头不得抢跑。）
                if (rdy[r_sel] && (line_tick || delayed) && line_room_i
                    && anchor_cnt == 12'd0) begin
                    delayed    <= 1'b0;
                    rdy[r_sel] <= 1'b0;            // 消费该 bank
                    group      <= 5'd0;
                    fetch_cnt  <= 4'd0;
                    ra_r       <= 7'd0;
                    bline      <= 11'd0;
                    st         <= S_FETCH;
                end
            end
            S_FETCH: begin
                // 行首组 5 字顺序预取（仅组 0；ra_r 进入时已 = group*5）：
                //   c0 发读 r0 | c1 收 r0->hold0 发 r1 | ... | c5 收 r4 组装载
                if (fetch_cnt <= 4'd4)
                    ra_r <= ra_r + 7'd1;
                case (fetch_cnt)
                4'd1: hold0 <= lram_q;
                4'd2: hold1 <= lram_q;
                4'd3: hold2 <= lram_q;
                4'd4: hold3 <= lram_q;
                4'd5: begin
                    // {w4,w3,w2,w1,w0}：beat k 位于 [64k+63:64k]
                    sr <= {lram_q, hold3, hold2, hold1, hold0};
                    if (group == 5'd0)
                        bline <= 11'd0;
                    bg <= 6'd0;
                    st <= S_SHIFT;
                end
                default: ;
                endcase
                fetch_cnt <= fetch_cnt + 4'd1;
            end
            S_SHIFT: begin
                m_axis_tdata  <= sr[63:0];
                m_axis_tvalid <= 1'b1;
                m_axis_tlast  <= (bline == BEATS_PER_LINE - 11'd1);
                m_axis_tuser  <= {
                    (line_r == VACT[11:0] - 12'd1) && (bline == BEATS_PER_LINE - 11'd1), // eof
                    (bline == 11'd0),                                                    // sol
                    (line_r == 12'd0) && (bline == 11'd0)                                // sof
                };
                sr    <= {64'd0, sr[2559:64]};
                bg    <= bg + 6'd1;
                bline <= bline + 11'd1;
                // ---- 组尾重叠预取（v4.10）：组间无 S_FETCH 停顿。读序：
                //   bg33 发读 A0 | bg34 发 A1 | bg35 收 w0->hold0 发 A2 |
                //   bg36 收 w1->hold1 发 A3 | bg37 收 w2->hold2 发 A4 |
                //   bg38 收 w3->hold3 | bg39 组装载（lram_q = w4，随组末
                //   分支写入 sr）。行总拍数 = S_WAIT 1 + S_FETCH 6 + 24 组
                //   x 40 = 967 < 1100 行预算（40b 时代 1046），余量 133 拍。
                //   末组不预取（下一行 bank 尚未翻入）。
                if (group != GROUPS_PER_LINE - 5'd1) begin
                    case (bg)
                    6'd33: ra_r <= ra_next;
                    6'd34: ra_r <= ra_next + 7'd1;
                    6'd35: begin hold0 <= lram_q; ra_r <= ra_next + 7'd2; end
                    6'd36: begin hold1 <= lram_q; ra_r <= ra_next + 7'd3; end
                    6'd37: begin hold2 <= lram_q; ra_r <= ra_next + 7'd4; end
                    6'd38: hold3 <= lram_q;
                    default: ;
                    endcase
                end
                if (bg == BG_PER_GROUP - 6'd1) begin
                    bg <= 6'd0;
                    if (group == GROUPS_PER_LINE - 5'd1) begin
                        // ---- 行完成（第 24 组末拍已发射）----
                        group <= 5'd0;
                        bline <= 11'd0;
                        if (line_r == VACT[11:0] - 12'd1)
                            st <= S_IDLE;          // 帧完：等下一帧请求
                        else begin
                            line_r <= line_r + 12'd1;
                            r_sel  <= ~r_sel;      // 消费指针追进下一 bank
                            st     <= S_WAIT;
                        end
                    end else begin
                        // ---- 组界无缝拼接：装载下一组（lram_q = 下组 w4）
                        group <= group + 5'd1;
                        sr    <= {lram_q, hold3, hold2, hold1, hold0};
                    end
                end
            end
            default: st <= S_IDLE;
            endcase

            //================================================================
            // 读路径（DDR 收字，恒超前发射恰好 1 行，写 bank w_sel）
            //================================================================
            // v4.1：rready 默认拉低，仅 R_PRE/R_RD 为高。原"rready 常高"
            // 在突发间隙（R_AR/R_PRE）让从机首拍提前完成 AXI 握手被空耗
            // ——DUT 进 R_RD 收到的首拍实为从机第 2 拍，burst1 整体前移
            // 1 word（单元 TB 实锤 lram[64]=word65 逐位吻合）。板级 DDR
            // 按 rvalid&&rready 完成传输，此缺陷板上同样丢首拍。
            rready <= 1'b0;
            case (r_st)
            R_IDLE: begin
                if (frame_grant) begin
                    // 与发射路径同拍 arm；行 0 立即发行 0 突发（不等首 tick，
                    // par 沿到首 tick >= 7.4us >> DDR 读）。基址用 next_par
                    //（与发射路径 par_r 同拍同值——慢向重读保持旧帧）
                    araddr  <= (next_par ? FRAME_B : FRAME_A);
                    arlen   <= WB0_BEATS[7:0] - 8'd1;  // 63（size6 上限 64 beat）
                    arsize  <= 3'b110;                 // 64B/beat
                    arburst <= 2'b01;                  // INCR
                    arqos   <= 4'h0;                   // 读通道 qos=0（板级契约）
                    arlock  <= 1'b0;
                    arapcmd <= 1'b0;
                    bi      <= 1'b0;
                    word_cnt<= 7'd0;
                    rdln    <= 12'd0;
                    w_sel   <= 1'b0;
                    r_st    <= R_AR;
                end
            end
            R_AR: begin
                arvalid <= 1'b1;
                // 首拍 arvalid 尚未生效（NBA），须待其真实为高再握手
                if (arvalid && arready) begin
                    arvalid <= 1'b0;
                    r_st    <= R_PRE;
                end
            end
            R_PRE: begin
                rready   <= 1'b1;
                beat_cnt <= bi ? (WB1_BEATS - 9'd1) : (WB0_BEATS - 9'd1);
                r_st     <= R_RD;
            end
            R_RD: begin
                rready   <= 1'b1;   // v4.1：R_RD 期保持（默认已拉低）
                // 传输成立 = rvalid && rready；行结束以 rlast 为准
                // （计数满而 rlast 未到：继续消费从机尾拍，防错账到下一行）。
                // 一行拆两突发：burst0(64 word) rlast 后行内直发 burst1(56
                // word)，不回行门。
                if (rvalid && rready) begin
                    word_cnt <= word_cnt + 7'd1;
                    if (rresp != 2'b00)
                        err_r <= err_r + 8'd1;
                    if (rlast) begin
                        if (beat_cnt != 9'd0)
                            err_r <= err_r + 8'd1;     // 短突发
                        if (bi == 1'b0) begin
                            bi      <= 1'b1;
                            araddr  <= rd_base + 33'd4096;
                            arlen   <= WB1_BEATS[7:0] - 8'd1;
                            r_st    <= R_AR;
                        end else begin
                            if (word_cnt != WORDS_PER_LINE - 7'd1)
                                err_r <= err_r + 8'd1; // 行字数错账
                            rdy[w_sel] <= 1'b1;        // bank 就绪，交发射
                            if (rdln == VACT[11:0] - 12'd1)
                                r_st <= R_DONE;        // 帧读完
                            else
                                r_st <= R_GAP;         // 等 bank 被消费
                        end
                    end else begin
                        if (beat_cnt == 9'd0)
                            err_r <= err_r + 8'd1;     // 超长（无 rlast）
                        else
                            beat_cnt <= beat_cnt - 9'd1;
                    end
                end
            end
            R_GAP: begin
                // v4.10c3g：abort 残帧后新帧可经 R_GAP 受理（此时残行已
                // 收完，账本就地重置 = R_IDLE/R_DONE 同款发车准备）
                if (frame_grant) begin
                    araddr  <= (next_par ? FRAME_B : FRAME_A);
                    arlen   <= WB0_BEATS[7:0] - 8'd1;
                    arsize  <= 3'b110;
                    arburst <= 2'b01;
                    arqos   <= 4'h0;
                    arlock  <= 1'b0;
                    arapcmd <= 1'b0;
                    bi      <= 1'b0;
                    word_cnt<= 7'd0;
                    rdln    <= 12'd0;
                    w_sel   <= 1'b0;
                    rdy     <= 2'b00;
                    r_st    <= R_AR;
                end else if (line_r == rdln) begin
                    // 行账本约束（v4.2 重写）：读路径行 n+1 的目标 bank 与发射
                    // 行 n 的 bank 相异，发射"进入"行 n（line_r==rdln）即覆写
                // 安全——行 n-1（n+1 的同 bank 前身）已被发射消费完。v4.1
                // 的 line_r==rdln+1 把读启动压到行末之后，双突发 ~105 拍
                // 读延迟挤不进行尾→tick 的 ~50 拍窗口，逐行交替错过 tick
                // （单元 TB 实锤 S0 12 帧耗 17.87ms=2 槽/帧、drop=11）。
                // v4.2 下读恒超前发射恰好 1 行，rdy 在行末前早已就绪。
                rdln     <= rdln + 12'd1;
                    w_sel    <= ~w_sel;
                    bi       <= 1'b0;
                    word_cnt <= 7'd0;
                    araddr   <= rd_base + 33'd8192;    // 下一行基址（8KB stride）
                    arlen    <= WB0_BEATS[7:0] - 8'd1;
                    r_st     <= R_AR;
                end
            end
            R_DONE: begin
                // 帧读完：等下一发车槽（此时发射路径必已回 S_IDLE）
                if (frame_grant) begin
                    araddr  <= (next_par ? FRAME_B : FRAME_A);  // 同 R_IDLE
                    arlen   <= WB0_BEATS[7:0] - 8'd1;
                    arsize  <= 3'b110;
                    arburst <= 2'b01;
                    arqos   <= 4'h0;
                    arlock  <= 1'b0;
                    arapcmd <= 1'b0;
                    bi      <= 1'b0;
                    word_cnt<= 7'd0;
                    rdln    <= 12'd0;
                    w_sel   <= 1'b0;
                    rdy     <= 2'b00;   // v4：同 S_IDLE（重读帧干净起步）
                    r_st    <= R_AR;
                end
            end
            default: r_st <= R_IDLE;
            endcase

            // ---- v4.10c3e 源切换安全清零（case 后：最后赋值优先）----
            if (!flush_i)
                flush_done_r <= 1'b0;
            else if (flush_fire) begin
                flush_done_r <= 1'b1;
                st     <= S_IDLE;      // 发射链回等请求
                r_st   <= R_IDLE;
                rdy    <= 2'b00;       // bank 就绪清——等新帧数据
                line_r <= 12'd0;
                rdln   <= 12'd0;
                arvalid<= 1'b0;        // 覆盖 case 可能的置起（R_AR 竞态）
                m_axis_tvalid <= 1'b0; // 同拍断流（tx 域复位同步依据）
                pend_grant<= 1'b0;     // 挂起授权随 flush 撤销
                // w_sel/r_sel/par_r 不清：无破坏性，新授权按 par_sync
                // 重新装载；drop/repeat/late/err 诊断计数保留跨切换可观测
            end
            // v4.10c3g 锚拍残帧放弃（独立 if——首版误挂 flush_i else-if 链，
            // flush_i 恒 0 使 abort 不可达，tb [OFF] 数据零变化实锤）：
            // 发射侧断流回 IDLE，本锚授权经 pend_grant 挂起受理（读路径
            // 不打断，r_quiet 后 grant）。与 flush_fire 同拍无害：两者都清
            // 发射态；flush_fire 拍 abort 的 frame_avail 旧值可能为 1 而
            // 置起 pend_grant，flush 清 frame_avail 后 grant 抑制至 writer
            // 重发布，语义正确。
            if (abort_frame) begin
                st            <= S_IDLE;
                m_axis_tvalid <= 1'b0;
                pend_grant    <= 1'b1;
            end
        end
    end

endmodule
