//============================================================================
// shape_pat_gen.sv - shape_video_axis 入口直注测试源（AXIS-64 UYVY，4K）
//
// 目的：绕开回放管线（DDR/frame_reader/demosaic/wb/rgb2yuv），在
// shape_video_axis 写侧入口直接注入 4K UYVY 棋盘拍流，隔离定位显示问题
// 在 shape/TX 之前还是之后。
//
// AXIS-64 规格（与 rgb2yuv_axis 输出逐位同构，shape 契约见其头注释）:
//   tdata[63:0] = 每拍 4 像素 = 2 个 UYVY 对；对 0 (px0/px1) 在 [31:0]、
//   对 1 (px2/px3) 在 [63:32]；32-bit 对字节序 {Y1, V, Y0, U}（LSB=U）
//   tlast = EOL（行末数据拍）；tuser = {eof, sol, sof}
//
// 帧结构（v17 同速同构契约，2026-10-19）：每帧 = 2160 数据行 tick +
// 90 pad tick = 2250 tick = 显示自然帧（VSP10+VBP72+VACT2160+VFP8）。
// 写读同速，shape 门在 Vback 末锚 sof，零积压零排水。
//（历史：直通时代为旧 shape 水位门/排水机制配过 2192+58、2250+1 等
//  故意失衡的帧结构——那些机制 v17 已删除，失衡源在 v17 下必然积满，
//  参数不可回用。）
//   行内连续（LINE_WORDS 拍 tvalid=1，960 拍 @148.5MHz = 6.5us << tick
//   周期 7.407us）；行消隐 tvalid=0。冷启动契约：复位进 pad，首个数据
//   字 = 行 0 首拍带 sof（shape 写侧 drop_frame 复位=1 等首个 sof，帧首
//   纪律满足）。
//
// 图案：32x32 像素白/蓝棋盘（色度两色都非 128，可上板直检 U/V 字节排布）：
//   白块 {Y=235, U=128, V=128}（BT.601 full-range）
//   蓝块 {Y=41,  U=240, V=110}
//   块相位 = (行号[7:5] ^ 像素列[7:5])，行 0/列 0 起白块。
//   同块 32px 同色（每拍 4px 恒不跨块界）=> UYVY 对内色度共享无损。
//   帧参考（2026-10-12）：帧首/帧尾各 2 行整行黑 + 每行行首 16px 行号
//   灰度标尺——棋盘静止旋转无参照，黑条/标尺位置即旋转量（隔离实验判读）。
//
// 用法：编译期 parameter DBG_SHAPE_PAT（camera_path/top_cam）实例化，
// 运行时 CSR CTRL[6] dbg_pat_sel 动态切换。默认 0（正常相机/图案路径，
// 零影响）。
//============================================================================

module shape_pat_gen #(
    parameter int LINE_WORDS   = 960,    // 每行数据拍（= HACT/PPC = 3840/4）
    parameter int SRC_LINES    = 2160,   // 每帧数据行数（= 显示 VACT）
    parameter int PAD_TICKS    = 90,     // 帧尾空闲 tick（= 2250 - 2160）
    parameter int TICK_CLOCKS  = 1100    // tick 周期（拍）= (HSP+HBP+HACT+HFP)/PPC
) (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        line_tick,        // 行节拍（top_cam: pclk 计
                                        // PAT_LINE_TICK_PCLK 拍的 CDC 单拍）
    // ---- 桥片间隔扫频（doc/csi_bridge_gap_sweep.md，2026-10-19）----
    //   CSR CTRL2 驱动；=0 时行为与历史版逐拍等价
    input  wire [15:0] line_gap,         // 行间距（拍）：行周期 =
                                        // TICK_CLOCKS + line_gap，间隙落 HBP
    input  wire [15:0] frame_gap,        // 帧间距（tick）：帧尾 pad =
                                        // PAD_TICKS + frame_gap，间隙落 VBP
    output reg  [63:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,     // EOL
    output reg  [2:0]  m_axis_tuser      // {eof, sol, sof}
);

    localparam int BEAT_WAIT = LINE_WORDS;  // 行尾等待态拍值（= 每行数据拍数）

    reg [10:0] beat_cnt;                 // 行内拍 0..LINE_WORDS-1（数据），
                                         // LINE_WORDS = 行尾等待态
    reg [11:0] line_cnt;                 // 帧内数据行 0..SRC_LINES-1
    reg        in_pad;                   // 复位冷启动闸（首个 tick 发车行 0）
    reg        last_line;                // 当前行为帧末行（行距门槛换帧距）
    reg [26:0] line_elapsed;             // 发车起已过拍数（行/帧距账目）
    reg        tick_seen;                // 发车后见过 tick（gap>0 时 tick
                                         // 先于门槛到达，见行尾等待注释）

    // 发车门槛（拍）：
    //   行距 = TICK_CLOCKS + line_gap
    //   帧距（帧末行 -> 下帧行 0）= 行距 + (PAD_TICKS+frame_gap)*TICK_CLOCKS
    //   => 帧周期 = SRC_LINES*行周期 + (PAD_TICKS+frame_gap)*TICK_CLOCKS
    //   （= doc/csi_bridge_gap_sweep.md 公式；g 全 0 时 =
    //   (SRC_LINES+PAD_TICKS)*TICK_CLOCKS 基线，逐拍等价历史版）
    wire [26:0] line_thr  = TICK_CLOCKS + {11'd0, line_gap};
    wire [26:0] pad_ext   = (PAD_TICKS + {15'd0, frame_gap}) * TICK_CLOCKS;
    wire [26:0] frame_thr = line_thr + pad_ext;

    wire in_data  = !in_pad && (beat_cnt < BEAT_WAIT[10:0]);
    wire sol_beat = in_data && (beat_cnt == 11'd0);
    wire eol_beat = in_data && (beat_cnt == BEAT_WAIT[10:0] - 11'd1);
    wire line_last = (line_cnt == SRC_LINES[11:0] - 12'd1);

    //--------------------------------------------------------------------
    // 图案数据（组合，寄存到 m_axis_tdata 时与 valid 同拍对齐）
    //--------------------------------------------------------------------
    localparam logic [7:0] Y_W = 8'd235, U_W = 8'd128, V_W = 8'd128; // 白
    localparam logic [7:0] Y_B = 8'd41,  U_B = 8'd240, V_B = 8'd110; // 蓝

    function automatic [23:0] blk_yuv;
        input blk;                       // 0=白 1=蓝
        begin
            blk_yuv = blk ? {Y_B, U_B, V_B} : {Y_W, U_W, V_W};
        end
    endfunction

    //--------------------------------------------------------------------
    // 棋盘明暗（32x32 像素块，块 = 行块 ^ 列块）：
    //   行块 = line_cnt[7:5]（32 行一块）；列块 = px_col[7:5]。
    //   px_col = beat*4 + p -> px_col[7:5] = beat[5:3]（p 只进 bit[1:0]，
    //   每拍 4 像素恒在同一块内）。
    //   明暗 blk = ^(行块 ^ 列块)，行 0/列 0 起白块。
    //--------------------------------------------------------------------
    wire [2:0] row_blk = line_cnt[7:5];
    wire [2:0] col_blk = beat_cnt[5:3];
    wire       blk     = ^(row_blk ^ col_blk);  // 0=白 1=蓝

    //--------------------------------------------------------------------
    // 帧参考特征（2026-10-12，4K 偏移隔离实验）：棋盘是 32 行周期图案，
    // 静止旋转无视觉参照。加两处非周期特征：
    //   1) 帧首 2 行 + 帧尾 2 行整行黑（Y=16，区别于棋盘白 235/蓝 41）
    //      —— 直注源冷启动按构造对齐（dbg_pat_rstn 与读侧同放、写侧等
    //      sof），黑条不在显示顶缘 => 内容被旋转，旋转发生在 shape/桥片；
    //   2) 每行行首 16px（beat 0..3）灰度 = 行号[7:0]（U/V=128）——行号
    //      直读标尺，帧缝（行 2249->0 回卷跳变）可见即旋转，顶行灰度
    //      即旋转量低 8 位。
    //--------------------------------------------------------------------
    localparam logic [7:0] Y_K = 8'd16;         // 标记黑（full-range 底）
    wire head_mrkr = (line_cnt < 12'd2);
    wire tail_mrkr = (line_cnt >= SRC_LINES[11:0] - 12'd2);
    wire in_mrkr   = head_mrkr | tail_mrkr;
    wire row_ruler = (beat_cnt < 11'd4);        // 行首 16px = 4 拍

    // 标记黑 / 标尺灰（U=V=128）/ 棋盘，三选一
    wire [23:0] px_w = in_mrkr ? {V_W, U_W, Y_K}
                     : row_ruler ? {V_W, U_W, line_cnt[7:0]}
                     : blk_yuv(blk);            // 每拍 4 像素同色

    // UYVY 装配：对 0 (px0/px1) 在 [31:0]，对 1 (px2/px3) 在 [63:32]，
    // 字节序 {Y1, V, Y0, U}（同 rgb2yuv_axis S1）
    wire [63:0] word_r = {px_w[23:16], px_w[7:0], px_w[23:16], px_w[15:8],
                          px_w[23:16], px_w[7:0], px_w[23:16], px_w[15:8]};

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            beat_cnt      <= 11'd0;
            line_cnt      <= 12'd0;
            in_pad        <= 1'b1;       // 复位冷启动闸：首 tick 发车行 0
            last_line     <= 1'b0;
            line_elapsed  <= 27'd0;
            tick_seen     <= 1'b0;
            m_axis_tdata  <= 64'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            m_axis_tuser  <= 3'd0;
        end else begin
            // ---- 冷启动 + tick 推进 ----
            // （历史 pad 差一拍教训：帧长必须恰 = SRC_LINES+PAD_TICKS
            // tick，发车 tick 不算进 pad——现版以帧距门槛统一表达。）
            if (in_pad) begin
                // 复位冷启动：首个 tick 发车行 0（首个数据字=行0=sof；
                // shape 写侧 drop_frame 等 sof，冷启动契约不变）
                if (line_tick) begin
                    in_pad       <= 1'b0;
                    line_cnt     <= 12'd0;
                    beat_cnt     <= 11'd0;
                    line_elapsed <= 27'd0;
                    tick_seen    <= 1'b0;
                    last_line    <= 1'b0;
                end
            end else begin
                // 行/帧距账目（自发车拍全程计数）：
                //   周期 = max(门槛, 下一 tick 到达拍)。g=0：门槛与 tick
                //   同拍 => 退化为纯 tick 锚定，与历史版逐拍等价（基线
                //   零回归）；g>0：窗口 > tick 周期必含 tick => elapsed
                //   主导，行周期严格均匀无锯齿（tick 相位不随行漂移）。
                //   比较含当拍增量：发车拍清零、第 n 拍读 n-1，
                //   "+1 >= thr" 即已满 thr 拍（无差一拍）。
                line_elapsed <= line_elapsed + 27'd1;
                if (line_tick)
                    tick_seen <= 1'b1;
                if ((line_tick || tick_seen)
                    && (beat_cnt == BEAT_WAIT[10:0])
                    && (line_elapsed + 27'd1
                        >= (last_line ? frame_thr : line_thr))) begin
                    beat_cnt     <= 11'd0;       // 启动新行
                    line_elapsed <= 27'd0;
                    tick_seen    <= 1'b0;
                    // 本发车行是否帧末行（是 => 下次门槛用帧距；
                    // line_cnt 已在上一行 eol 处进位/回零）
                    last_line    <= (line_cnt == SRC_LINES[11:0] - 12'd1);
                end
            end
            // 行数据中段到达的 tick 丢弃（4.8us << 7.407us，防御性）

            // ---- 行内拍推进 + 帧行计数 ----
            if (in_data) begin
                if (eol_beat) begin
                    beat_cnt <= BEAT_WAIT[10:0];     // 回等待态
                    if (line_last) begin
                        // 末行：下帧行 0（帧末间隔由 last_line 帧距承担）
                        line_cnt <= 12'd0;
                    end else begin
                        line_cnt <= line_cnt + 12'd1;
                    end
                end else begin
                    beat_cnt <= beat_cnt + 11'd1;
                end
            end

            // ---- 输出打拍（data/valid/last/user 同拍对齐）----
            m_axis_tvalid <= in_data;
            m_axis_tdata  <= word_r;
            m_axis_tlast  <= eol_beat;
            m_axis_tuser  <= {eol_beat && line_last,          // eof
                              sol_beat,                       // sol
                              sol_beat && (line_cnt == 12'd0)}; // sof
        end
    end

endmodule
