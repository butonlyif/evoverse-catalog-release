// ============================================================================
// frame_writer.v — RAW10 行流（64b 载体）-> LPDDR4X 帧写入
//（v4.10，2026-10-21 载体重构：消除 40b<->2^n LCM 组相位竖线嫌疑）
//
// 输入：AXIS-64 载体（camera_path 将 raw_2_axi4st 的 40b 输出零扩展
//       {24'h0, data[39:0]}，RAW10 段仅低 40b 有效；960 拍/行 = 7680B/行，
//       tuser={eof,sol,sof}，tlast=EOL，无 tready——源不可暂停）。
//       aclk = sys_clk_200m，与 raw 源同域 —— 单时钟，无 CDC。
// 输出：AXI4 写主口（512b/beat）。行几何参数化（任务2 阶段1，默认 4K）：
//       4K = 7680B/行 = 120 word，64+56 两突发，行槽 8KB；cam1 1080 =
//       3840B/行 = 60 word，32+28 两突发，行槽 4KB（Efinix DDR Table5：
//       size6 => len<=63；两段突发各自完全落在单个 4KB 窗内，行槽不重叠）。
//
// 位序约定（v4.10 64b 载体）：8 拍 x 64b = 512b 字整除打包（beat k 写
// [64k+63:64k]，beat0 最低位），无 40b<->2^n LCM 组相位转换（2560b 组
// 移位链删除）；DDR 字节序 = 拍序升序，frame_reader 按同序还原逐拍流。
// （v1.1：原移位链丢 beat / 位序颠倒 —— 板上回放仅行首一小段正确）
//
// 帧布局：FRAME_A=0x0 / FRAME_B=0x1100_0000，行距 8KB，VACT 行/帧
//       （2160 x 8KB = 17.6MB/帧，B 基址在 A 帧尾之外，无重叠）。
//
// 弹性与整帧纪律（v2 核心变更）：
//   - 数据缓冲 = 8 行槽 x 75 字（5 片 BRAM x 128x512，字序 = 组 g 的第 r
//     字 -> mem r 行 {slot,g}），描述队列 8 深 {par,line} —— 单钟直通指针。
//   - 整帧或全无：帧内首次队满 => bad_frame 置位，余行全部丢弃（计数），
//     帧满关闭时【不翻转 par】；仅完整 2160 行才翻 par 给 reader 换帧。
//     DDR 中永远是完整帧或上一完整帧，构造性消灭撕帧。
//   - 帧中 sof = 源帧界异常（源行纪律已由帧锚定计数证实）=> 立即按坏帧
//     关帧重启，防止行账本永久卡死。
//   - 所有丢弃路径计数（v1 的无声 sol 重启通道在本结构中不存在）。
//
// ppm 职责（与 frame_reader 分工）：摄像头/图案源时钟与本地显示时钟的
//   ppm/帧率差在帧界吸收——本模块恒持续写入活流，整帧或全无（坏帧不
//   翻 par），帧率差只表现为 par 翻转沿相对显示行节拍的节奏快慢，由
//   reader 帧请求门限（cnt>=2）+ 忙时跳帧消化；不做行级 ppm 补偿。
//
// 控制器契约（板级实测，沿袭 v1）：WVALID-先于-AWREADY 型；awqos=1；
//   WLAST 与段末 beat 同拍；awapcmd/awallstrb/awcobuf=0。
// ============================================================================

module frame_writer #(
    parameter [15:0] VACT     = 16'd2160,           // 每帧写入行数
    parameter [32:0] FRAME_A  = 33'h0_0000_0000,
    parameter [32:0] FRAME_B  = 33'h0_1100_0000,
    // ---- 行几何（任务2 阶段1 参数化，默认=现行 4K，行为零变）----
    // cam0 4K : 960 拍/120 字/64+56/8KB 行槽（7680B 行）
    // cam1 1080: 480 拍/60 字 /32+28/4KB 行槽（3840B 行，cam1-ddr-replay-plan §3）
    parameter [9:0]  BEATS_PER_LINE    = 10'd960,   // 每行 AXIS 拍（64b 载体，4px/拍）
    parameter [6:0]  WORDS_PER_LINE    = 7'd120,    // 每行 512b 字
    parameter [8:0]  WB0_BEATS         = 9'd64,     // burst0（4KB 窗内）
    parameter [8:0]  WB1_BEATS         = 9'd56,     // burst1
    parameter [4:0]  LINE_STRIDE_SHIFT = 5'd13      // 行槽 stride = 1<<SHIFT
)(
    input  wire         aclk,            // sys_clk_200m（raw 源域，单钟）
    input  wire         rstn,
    input  wire         flush_i,         // v4.10c3c 流重置：drain 空闲拍清
                                         // 填充侧账本（源切换后新流帧头前进
                                         // 来前断流会悬空行窗/半行未提交）。
                                         // 仅在 drain 空闲拍执行，AXI 接口
                                         // 零接触——无 2026-10-20 楔死风险
    input  wire [39:0]  s_axis_tdata,
    input  wire         s_axis_tvalid,
    input  wire         s_axis_tlast,    // EOL
    input  wire [2:0]   s_axis_tuser,    // {eof, sol, sof}
    // ---- AXI4 写主口 ----
    output wire [5:0]   awid,
    output reg  [32:0]  awaddr,
    output reg  [7:0]   awlen,
    output reg  [2:0]   awsize,
    output reg  [1:0]   awburst,
    output reg  [3:0]   awcache,
    output reg          awlock,
    output reg          awvalid,
    output reg          awcobuf,
    output reg          awapcmd,
    output reg          awallstrb,
    output reg  [3:0]   awqos,
    input  wire         awready,
    output wire [511:0] wdata,
    output wire [63:0]  wstrb,
    output reg          wlast,
    output reg          wvalid,
    input  wire         wready,
    input  wire [5:0]   bid,
    input  wire         bvalid,
    output reg          bready,
    // ---- 状态（诊断级）----
    output wire [15:0]  line_cnt,        // 当前帧已收行号
    output wire [15:0]  frame_cnt,       // 受理 sof 计数
    output wire [15:0]  pad_cnt,         // VACT 外盈余行
    output wire [15:0]  ovf_cnt,         // 队列满丢弃行
    output wire [3:0]   dbg_state,       // drain 状态机快照
    output wire         wr_par,          // 当前填充帧基址（0=A 1=B）
    output wire [11:0]  wr_line,         // 帧内行进度（0..2160，2160=pad 态）
    output wire         wr_frame_done_o, // v3（架构 v4 SPEC-001 D3）：帧发布
                                         // 单拍脉冲——drain 侧帧末行（desc
                                         // drn_line==VACT-1，坏帧行不入 desc
                                         // 故必属完整帧）bvalid 完成拍，即该帧
                                         // 已全部落 DDR 后；经顶层 2FF+syn_keep
                                         // 送 148.5M 显示域，reader 以此沿为帧
                                         // 请求（替代 v3.4 wr_par 沿 + cnt 跨域）
    output wire [31:0]  wr_perf,         // {drn_lines[15:0], aw_wait, w_wait}
    output wire [31:0]  fw_dbg2          // {bad_frame[15:0], drop[7:0], last_drop_line[7:0]}
);

    localparam [6:0]  GROUPS_PER_LINE= WORDS_PER_LINE;  // 组=字（8 拍 x 64b 组装）
    localparam [32:0] WB0_BYTES      = WB0_BEATS * 64;  // burst0 字节数（burst1 偏移）
    localparam [1:0]  NSLOT          = 2'd3;      // 8 槽（ptr[3] 回绕判满）

    // drain 状态（沿袭 v1，板级验证骨架）
    localparam [2:0] D_SETUP  = 3'd0,
                     D_WADDR  = 3'd1,
                     D_PREWR  = 3'd2,
                     D_WRITE  = 3'd3,
                     D_POSTWR = 3'd4;

    //========================= 填充侧（单钟）=========================
    reg        in_line;          // 行窗打开（sol 后到行完）
    reg [9:0]  beat_in_line;     // 行内已收拍（0..959）
    reg [2:0]  beat_in_group;    // 组内拍（0..7）
    reg [6:0]  group_wa;         // 组写址（0..119）
    reg [511:0] group_sr;        // 8 拍 x 64b = 1 word 组装寄存
    reg        drop_mode;        // 本行丢弃（队满/坏帧期）
    reg        bad_frame;        // 本帧已污染（关帧时不翻 par）
    reg        in_frame;         // 帧窗开启（复位后等 sof；关帧后等下帧 sof）
    reg [11:0] line_in_frame;    // 帧内行号（0..VACT，VACT = 帧满标记）
    reg [11:0] cur_line_r;       // 本行行号（sol 时锁存）
    reg [2:0]  wr_slot;          // 本行数据槽（sol 时锁存 = 写指针）
    reg        frame_par;        // 当前填充帧基址（0=A 1=B）
    reg [15:0] line_cnt_r, frame_cnt_r, pad_cnt_r, ovf_cnt_r;
    reg [15:0] bad_cnt_r, drop_cnt_r;
    reg [7:0]  last_drop_line_r;
    reg        wr_frame_done_r;   // v3：帧发布单拍（默认每拍清 0，发布拍置 1）

    // 描述队列（8 深，单钟直接指针）
    reg [3:0]  dw_ptr, dr_ptr;   // mod 16，槽用 [2:0]
    reg [12:0] desc_mem [0:7];   // {par, line[11:0]}
    reg [2:0]  d_st;             // drain FSM 状态（flush 分支引用——vlog
                                 // 不容前向引用，声明前移自 drain 区）

    wire sol_beat = s_axis_tvalid && s_axis_tuser[1];
    wire acc      = s_axis_tvalid && in_line && !sol_beat;

    wire q_full  = (dw_ptr[3] != dr_ptr[3]) && (dw_ptr[2:0] == dr_ptr[2:0]);
    wire q_empty = (dw_ptr == dr_ptr);

    // 帧行账本：in_frame=1 且未满（<VACT）为数据窗；帧满或等帧头期间
    // 的 sol 按 pad/游离行计数；数据窗内 sof = 源帧界异常（坏帧重启）。
    // 复位后 in_frame=0 —— 首帧行 0 的 sof 走正常开帧（v1.1 修复：原版
    // 误落"帧中 sof"分支丢行 0 且 desc 行号错位）
    wire        pad_zone  = (line_in_frame == VACT[11:0]);
    wire        frame_on  = in_frame && !pad_zone;
    wire        data_line = sol_beat && frame_on;
    wire        this_drop = data_line && (bad_frame || q_full);
    wire        frame_end = data_line && (line_in_frame == VACT[11:0] - 12'd1);
    wire        frame_bad_next = bad_frame || (data_line && q_full);

    // 组提交：第 8 拍落组（beat_in_group==7），512b 字一次写单片 mem。
    // 固定槽打包：beat k 恒写入容器 [64k+63:64k]（beat0 最低位，不随拍
    // 移位），8x64b 整除无跨组相位 —— 与 reader 还原序一致。
    // 提交拍 beat7 尚未落槽 —— commit_sr 将槽 7 替换为当拍 tdata。
    wire         group_commit = acc && (beat_in_group == 3'd7);
    wire [511:0] commit_sr    = {s_axis_tdata, group_sr[447:0]};

    // 数据 mem（单片 1024x512：{slot[2:0], group_wa[6:0]}，组 0..119）
    (* syn_ramstyle = "block_ram" *) reg [511:0] mem [0:1023];
    wire [9:0] mem_wa = {wr_slot, group_wa};

    always @(posedge aclk) begin
        if (group_commit && !drop_mode)
            mem[mem_wa] <= commit_sr;
    end

    assign line_cnt  = line_cnt_r;
    assign frame_cnt = frame_cnt_r;
    assign pad_cnt   = pad_cnt_r;
    assign ovf_cnt   = ovf_cnt_r;
    assign wr_par    = frame_par;
    assign wr_line   = line_in_frame;
    assign wr_frame_done_o = wr_frame_done_r;

    always @(posedge aclk or negedge rstn) begin
        if (!rstn) begin
            in_line        <= 1'b0;
            beat_in_line   <= 10'd0;
            beat_in_group  <= 3'd0;
            group_wa       <= 7'd0;
            group_sr       <= 512'd0;
            drop_mode      <= 1'b0;
            bad_frame      <= 1'b0;
            in_frame       <= 1'b0;
            line_in_frame  <= 12'd0;
            cur_line_r     <= 12'd0;
            wr_slot        <= 3'd0;
            frame_par      <= 1'b0;      // 首帧填 A
            line_cnt_r     <= 16'd0;
            frame_cnt_r    <= 16'd0;
            pad_cnt_r      <= 16'd0;
            ovf_cnt_r      <= 16'd0;
            bad_cnt_r      <= 16'd0;
            drop_cnt_r     <= 16'd0;
            last_drop_line_r <= 8'd0;
            dw_ptr         <= 4'd0;
        end else if (flush_i && (d_st == D_SETUP) && (dw_ptr == dr_ptr)
                     && !awvalid && !wvalid) begin
            // ---- v4.10c3c 流重置（仅 drain 空闲拍）----
            // 源切换断流会悬空行窗（收不到 EOL）/半行未提交；新流帧头
            // 帧中 sof 路径虽可重启账本，但 desc 队列/行号错位组合在板
            // 上表现为切回后黑屏。此处整清填充账本与队列指针（队列本
            // 已空，dr_ptr 不动即等价归零），wr_frame_done 悬挂脉冲清。
            // AXI 接口（aw/w/b）与 drain 状态机不碰——无楔死风险。
            in_line        <= 1'b0;
            beat_in_line   <= 10'd0;
            beat_in_group  <= 6'd0;
            group_wa       <= 4'd0;
            group_sr       <= 2560'd0;
            drop_mode      <= 1'b0;
            bad_frame      <= 1'b0;
            in_frame       <= 1'b0;
            line_in_frame  <= 12'd0;
            cur_line_r     <= 12'd0;
            wr_slot        <= 3'd0;
            // frame_par 绝不能在 flush 中清（v4.10c3d 板测教训：清 par
            // 破坏 writer/reader 乒乓锚——若 par 被拉离 reader 正在读的
            // 对面 bank，writer 会写到 reader 的重放 bank 上 => 撕裂；随
            // 后 reader 切读废弃半帧 => 黑屏，50% 概率随切换前 par 相位
            // 撞上）。par 不动：writer 在原 bank 从行 0 重新记账（半截
            // 旧帧被同 bank 新流覆盖，永不发布），reader 恒读对面完整
            // 帧，乒乓约定完好。
            // wr_frame_done_r 不在此清：它由 drain 侧 always 单一驱动
            //（多驱动会被综合拒绝）；flush 执行条件已保证 drain 空闲，
            // 此拍 done 恒 0，无需清。
            dw_ptr         <= dr_ptr;
        end else begin
            if (sol_beat) begin
                if (data_line && s_axis_tuser[0]) begin
                    // ---- 帧中 sof（v3 语义修正，SPEC-001 整帧或全无）：
                    //      原帧行账本就地重写——原帧永无 VACT-1 完成拍，
                    //      天然不发布（v2 曾丢 sof 行 0 强行发布重启帧，
                    //      内容错位一帧违反 R3）；sof 行即新帧行 0 正常收，
                    //      重启帧完整可发布 ----
                    bad_cnt_r       <= bad_cnt_r + 16'd1;
                    frame_cnt_r     <= frame_cnt_r + 16'd1;
                    line_in_frame   <= 12'd1;
                    cur_line_r      <= 12'd0;
                    line_cnt_r      <= 16'd0;
                    if (q_full) begin
                        drop_mode <= 1'b1;
                        ovf_cnt_r <= ovf_cnt_r + 16'd1;
                        bad_frame <= 1'b1;
                    end else begin
                        drop_mode  <= 1'b0;
                        bad_frame  <= 1'b0;
                        wr_slot    <= dw_ptr[2:0];
                        group_wa   <= 7'd0;
                        group_sr[63:0] <= s_axis_tdata;   // beat0
                        beat_in_group <= 6'd1;
                    end
                    beat_in_line <= 10'd1;
                    in_line      <= 1'b1;
                end else if (data_line) begin
                    // ---- 帧内普通行 ----
                    cur_line_r <= line_in_frame;
                    line_in_frame <= line_in_frame + 12'd1;
                    if (this_drop) begin
                        drop_mode <= 1'b1;
                        if (q_full) begin
                            ovf_cnt_r <= ovf_cnt_r + 16'd1;
                            bad_frame <= 1'b1;
                        end else begin
                            drop_cnt_r <= drop_cnt_r + 16'd1;
                            last_drop_line_r <= line_in_frame[7:0];
                        end
                    end else begin
                        drop_mode  <= 1'b0;
                        line_cnt_r <= {4'd0, line_in_frame};
                        wr_slot    <= dw_ptr[2:0];
                        group_wa   <= 7'd0;
                        group_sr[63:0] <= s_axis_tdata;   // beat0
                        beat_in_group <= 6'd1;
                    end
                    beat_in_line <= 10'd1;
                    in_line      <= 1'b1;
                end else if (s_axis_tuser[0]) begin
                    // ---- 帧行 0：开新帧（等帧头 / 帧满 pad 区 sof 重启）----
                    frame_cnt_r    <= frame_cnt_r + 16'd1;
                    in_frame       <= 1'b1;
                    line_in_frame  <= 12'd1;
                    if (bad_frame || q_full) begin
                        drop_mode <= 1'b1;
                        if (q_full) begin
                            ovf_cnt_r <= ovf_cnt_r + 16'd1;
                            bad_frame <= 1'b1;
                        end else begin
                            drop_cnt_r <= drop_cnt_r + 16'd1;
                            last_drop_line_r <= 8'd0;
                        end
                    end else begin
                        drop_mode  <= 1'b0;
                        line_cnt_r <= 16'd0;
                        cur_line_r <= 12'd0;
                        wr_slot    <= dw_ptr[2:0];
                        group_wa   <= 7'd0;
                        group_sr[63:0] <= s_axis_tdata;   // beat0
                        beat_in_group <= 6'd1;
                    end
                    beat_in_line <= 10'd1;
                    in_line      <= 1'b1;
                end else begin
                    // ---- 帧外 / 帧满盈余行（无 sof）----
                    pad_cnt_r <= pad_cnt_r + 16'd1;
                end
            end else if (acc) begin
                // ---- 行内后续拍：固定槽写入（beat k -> [64k+63:64k]）----
                beat_in_line  <= beat_in_line + 10'd1;
                beat_in_group <= beat_in_group + 3'd1;
                group_sr[beat_in_group*64 +: 64] <= s_axis_tdata;
                if (beat_in_group == 3'd7)
                    group_wa <= group_wa + 7'd1;   // 组提交：写址指向下一组
                if (beat_in_line == BEATS_PER_LINE - 10'd1) begin
                    // ---- 行完成（第 960 拍 = 第 120 组末拍）----
                    in_line       <= 1'b0;
                    beat_in_line  <= 10'd0;
                    beat_in_group <= 3'd0;
                    if (!drop_mode) begin
                        desc_mem[dw_ptr[2:0]] <= {frame_par, cur_line_r};
                        dw_ptr <= dw_ptr + 4'd1;
                    end
                    // ---- 帧关闭（帧末行完成拍；desc 同拍已用旧 par）----
                    // 判据用 cur_line_r（本行行号）—— line_in_frame 在本行
                    // sol 拍已 ++，用它会提前一行关帧（v1.1：曾致帧末行被丢）
                    // （v1.1：曾在帧末行 sol 拍提前翻 par，致帧末行 desc 记到
                    //   下一帧基址）
                    if (in_frame && cur_line_r == VACT[11:0] - 12'd1) begin
                        in_frame <= 1'b0;             // 关帧：等下一帧 sof
                        if (bad_frame || q_full) begin
                            bad_frame <= 1'b0;        // 坏帧：不翻 par
                            bad_cnt_r <= bad_cnt_r + 16'd1;
                        end else begin
                            frame_par <= ~frame_par;  // 完整帧：翻 par
                        end
                    end
                end
            end
        end
    end

    //========================= drain 侧（同钟）=========================
    reg [11:0] drn_line;
    reg        drn_par;
    reg [2:0]  drn_slot;
    reg [8:0]  beat_cnt;
    reg        bi;
    reg [1:0]  b_cnt;
    reg [6:0]  wword;             // 行内字址（0..119）
    reg [32:0] line_off;

    // 单片 mem 1 字超前预取：每个 fire 拍读下一字 {drn_slot, wword+1}。
    // D_SETUP 读新行字 0；D_WADDR 仅 bi=0 重读字 0（幂等保鲜）；bi=1 的
    // D_WADDR 不读 —— burst0 wlast 拍 fire 已预取字 64（burst1 首字），
    // 必须保持到 burst1 fire#0（v1.1 教训：bi=1 预取会覆盖超前字，burst1
    // 首字重复错位）。
    wire        w_fire = (d_st == D_PREWR || d_st == D_WRITE) && wvalid && wready;
    wire        mem_re = w_fire || (d_st == D_SETUP && !q_empty)
                         || (d_st == D_WADDR && !bi);
    wire [9:0]  mem_ra = (d_st == D_SETUP)   ? {dr_ptr[2:0], 7'd0} :
                         (d_st == D_WADDR)   ? {drn_slot,   7'd0} :
                                               {drn_slot, wword + 7'd1};
    reg [511:0] mem_q;
    always @(posedge aclk) begin
        if (mem_re)
            mem_q <= mem[mem_ra];
    end

    // 字推进：正常 fire 拍 +1；末拍（beat_cnt==0）fire 不推进，
    // seg_done 转换拍补 +1（净效果 = 每 fire +1，与 v1.1 等价）

    // 段完成 = 末拍真正发出的那一拍
    wire seg_done = (beat_cnt == 9'd0) && wlast && wvalid && wready;

    assign dbg_state = {2'b00, d_st};
    assign awid      = 6'h0;
    assign wstrb     = {64{1'b1}};
    assign wdata     = mem_q;

    always @(posedge aclk or negedge rstn) begin
        if (!rstn) begin
            d_st       <= D_SETUP;
            dr_ptr     <= 4'd0;
            drn_line   <= 12'd0;
            drn_par    <= 1'b0;
            drn_slot   <= 3'd0;
            beat_cnt   <= 9'd0;
            bi         <= 1'b0;
            b_cnt      <= 2'd0;
            wword      <= 7'd0;
            line_off   <= 33'd0;
            awaddr     <= 33'd0;
            awlen      <= 8'd0;
            awsize     <= 3'd0;
            awburst    <= 2'd0;
            awcache    <= 4'd0;
            awlock     <= 1'b0;
            awvalid    <= 1'b0;
            awcobuf    <= 1'b0;
            awapcmd    <= 1'b0;
            awallstrb  <= 1'b0;
            awqos      <= 4'd0;
            wvalid     <= 1'b0;
            wlast      <= 1'b0;
            bready     <= 1'b0;
            wr_frame_done_r <= 1'b0;
        end else begin
            wr_frame_done_r <= 1'b0;   // v3：单拍默认归零（帧末 desc 完成拍覆盖置 1）
            case (d_st)
            D_SETUP: begin
                if (!q_empty) begin
                    {drn_par, drn_line} <= desc_mem[dr_ptr[2:0]];
                    drn_slot <= dr_ptr[2:0];
                    line_off <= {21'd0, desc_mem[dr_ptr[2:0]][11:0]} << LINE_STRIDE_SHIFT;
                    wword    <= 7'd0;
                    bi       <= 1'b0;
                    b_cnt    <= 2'd0;
                    d_st     <= D_WADDR;
                end
            end
            D_WADDR: begin
                awvalid <= 1'b1;
                if (bvalid)
                    b_cnt <= b_cnt + 2'd1;
                awlen   <= bi ? (WB1_BEATS[7:0] - 8'd1) : (WB0_BEATS[7:0] - 8'd1);
                awsize  <= 3'b110;
                awburst <= 2'b01;
                awqos   <= 4'h1;
                awaddr  <= (drn_par ? FRAME_B : FRAME_A) + line_off
                         + (bi ? WB0_BYTES : 33'd0);
                beat_cnt <= bi ? (WB1_BEATS - 9'd1) : (WB0_BEATS - 9'd1);
                d_st     <= D_PREWR;
            end
            D_PREWR: begin
                if (awready)
                    awvalid <= 1'b0;
                wvalid <= 1'b1;
                bready <= 1'b1;
                if (bvalid)
                    b_cnt <= b_cnt + 2'd1;
                if (wready && wvalid) begin
                    if (beat_cnt == 9'd0) begin
                        wvalid <= 1'b0;
                        wlast  <= 1'b0;
                    end else begin
                        if (beat_cnt == 9'd1)
                            wlast <= 1'b1;
                        beat_cnt <= beat_cnt - 9'd1;
                        wword <= wword + 7'd1;
                    end
                end
                if (seg_done) begin
                    bi   <= ~bi;
                    // 末拍（bc==0）主推进分支不执行，burst 边界 wword 须
                    // 在此补推进——v1.1 只补了 D_WRITE 侧；awready 迟到时
                    // 整个 burst 数据期都停在 D_PREWR（实测 burst1 全程
                    // st=010），缺失使 burst1 起系统性后移 1 word（行尾
                    // 704B 全错，单元 TB V2-WORD-DIST 64..74 各 270 实锤）
                    wword <= wword + 7'd1;
                    d_st <= bi ? D_POSTWR : D_WADDR;
                end else if (awready && wready) begin
                    d_st <= D_WRITE;
                end
            end
            D_WRITE: begin
                if (bvalid)
                    b_cnt <= b_cnt + 2'd1;
                if (wready && wvalid) begin
                    if (beat_cnt == 9'd0) begin
                        wvalid <= 1'b0;
                        wlast  <= 1'b0;
                    end else begin
                        if (beat_cnt == 9'd1)
                            wlast <= 1'b1;
                        beat_cnt <= beat_cnt - 9'd1;
                        wword <= wword + 7'd1;
                    end
                end
                if (seg_done) begin
                    bi   <= ~bi;
                    wword <= wword + 7'd1;   // 末拍（bc==0）未推进 —— 此处补推进（v1.1：缺失致 burst1 首字重复）
                    d_st <= bi ? D_POSTWR : D_WADDR;
                end
            end
            D_POSTWR: begin
                if (awready)
                    awvalid <= 1'b0;
                if (wready) begin
                    wlast  <= 1'b0;
                    wvalid <= 1'b0;
                end
                if (bvalid) begin
                    b_cnt <= b_cnt + 2'd1;
                    if (b_cnt == 2'd1) begin
                        bready <= 1'b0;
                        dr_ptr <= dr_ptr + 4'd1;    // 出队释放
                        d_st   <= D_SETUP;
                        // v3：帧末行 desc（drn_line==VACT-1，坏帧行不入 desc
                        // 故必属完整帧）字节全部落 DDR 完成拍 —— 帧发布脉冲。
                        // 此刻该帧最后一个写事务 bvalid 完成读侧即安全（R3）。
                        if (drn_line == VACT[11:0] - 12'd1)
                            wr_frame_done_r <= 1'b1;
                    end
                end
            end
            default: d_st <= D_SETUP;
            endcase
        end
    end

    // ---- 写口性能诊断（沿袭 v1 语义）----
    reg [15:0] drn_lines_r;
    reg [7:0]  aw_wait_r;
    reg [7:0]  w_wait_r;
    assign wr_perf = {drn_lines_r, aw_wait_r, w_wait_r};
    assign fw_dbg2 = {bad_cnt_r, drop_cnt_r[7:0], last_drop_line_r};

    always @(posedge aclk or negedge rstn) begin
        if (!rstn) begin
            drn_lines_r <= 16'd0;
            aw_wait_r   <= 8'd0;
            w_wait_r    <= 8'd0;
        end else begin
            if (d_st == D_POSTWR && bvalid)
                drn_lines_r <= drn_lines_r + 16'd1;
            if ((d_st == D_WADDR || d_st == D_PREWR) && awvalid && !awready)
                aw_wait_r <= aw_wait_r + 8'd1;
            if (wvalid && !wready)
                w_wait_r <= w_wait_r + 8'd1;
        end
    end

    // 未用输出收敛（v1 遗留端口名，置常量）
    wire [5:0] unused_bid = bid;

endmodule
