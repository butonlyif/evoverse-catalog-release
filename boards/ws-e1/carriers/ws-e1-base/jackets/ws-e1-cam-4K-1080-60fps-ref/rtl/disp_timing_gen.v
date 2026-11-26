// ============================================================================
// disp_timing_gen.v — DDR 回放显示时序发生器（阶段 2）
//
// 骨架复刻 shape_pat_gen（已上板验证的 shape 入口直注源）：line_tick 推进的
// 行槽 FSM + 帧尾 pad。区别仅在数据来源：不产生图案，而是按 beat 从
// disp_line_fifo 拉取 DDR 回放数据。
//
//   帧结构：SRC_LINES 个数据行槽（每行 LINE_WORDS 拍 tvalid）+ PAD_TICKS
//   个空闲槽（4K 面板：2160 + 90 = 2250 槽 @ 1100 pclk/槽 = 7.407us）。
//   写侧供给 = writer 帧率（~30fps）< 面板槽率：行启动门控（fifo_words >=
//   一行字数）失败时跳过本槽重试（late_cnt++）——显示帧率经水位门自动锁定
//   到供给率，与真实 4K 相机模式同动态（shape 帧首水位门吸收缺口，已验证）。
//
//   行启动门控保证行内不欠跑：门控字数 = 整行字数，消费中 reader 只增不减
//   （单 FIFO 顺序流），故行中段 rd_beat_ok 的短暂低落仅为预取补位气泡
//   （under_cnt 观测，shape 按拍计数契约下合法）。
//
// AXIS-64 输出契约（与 rgb2yuv_axis / shape_pat_gen 逐位同构）：
//   tlast = EOL（行末数据拍）；tuser = {eof, sol, sof}
// frame_tick：每帧首槽翻转一次（给 frame_reader 做 CDC 帧界）。
// ============================================================================

module disp_timing_gen #(
    parameter LINE_WORDS = 960,     // 每行数据拍（= HACT/PPC = 3840/4）
    parameter SRC_LINES  = 2160,    // 每帧数据行（= frame_writer VACT）
    parameter PAD_TICKS  = 90       // 帧尾空闲槽（= 2250 - 2160）
) (
    input  wire        aclk,            // pixel_clk 域
    input  wire        aresetn,
    input  wire        line_tick,       // 行节拍（top_cam pat_line_tick_tx 同款）
    // disp_line_fifo 读侧（beat 粒度）
    input  wire [11:0] fifo_words,      // 读侧可用字数
    input  wire [63:0] fifo_rdata,
    input  wire        fifo_rd_ok,      // 本拍 FIFO 有 beat
    output wire        fifo_rd_en,      // beat 消费（与发射同拍）
    // AXIS-64 输出（-> camera_path shape_in mux）
    output reg  [63:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,    // EOL
    output reg  [2:0]  m_axis_tuser,    // {eof, sol, sof}
    // 帧界 + 状态
    output reg         frame_tick,      // 每帧首槽翻转（CDC 到 reader）
    output wire [15:0] gen_frame_cnt,
    output reg  [7:0]  late_cnt,        // 行槽门控失败跳过数
    output reg  [7:0]  under_cnt        // 行内补位气泡 beat 数
);

    localparam BEAT_WAIT = LINE_WORDS;                  // 行尾等待态拍值
    localparam LINE_W    = LINE_WORDS / 8;              // 整行字数（120）
    // 行门控阈值：FIFO 读侧 2 槽乒乓预取的字不计入 rd_words，但已是
    // 可消费数据 —— 阈值放宽 2 字，否则整行字数永远差 2 达不到（死锁）
    localparam GATE_W    = LINE_W - 2;

    reg [10:0] beat_cnt;                 // 行内拍 0..LINE_WORDS-1，WAIT=等待
    reg [11:0] line_cnt;                 // 帧内数据行 0..SRC_LINES-1
    reg [6:0]  pad_cnt;                  // 帧尾 pad 槽（< 128）
    reg        in_pad;

    wire in_data = !in_pad && (beat_cnt < BEAT_WAIT[10:0]);
    // 发射 = 行内拍 && FIFO 有 beat（门控保证整行字数已备，此处仅补位气泡）
    wire emit    = in_data && fifo_rd_ok;
    assign fifo_rd_en = emit;

    wire sol_beat  = emit && (beat_cnt == 11'd0);
    wire eol_beat  = emit && (beat_cnt == BEAT_WAIT[10:0] - 11'd1);
    wire line_last = (line_cnt == SRC_LINES[11:0] - 12'd1);
    // 行启动门控：FIFO 备足整行（含预取槽）才发车（防行内断粮）
    wire line_go   = (fifo_words >= GATE_W[11:0]);

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            beat_cnt      <= 11'd0;
            line_cnt      <= 12'd0;
            pad_cnt       <= 7'd0;
            in_pad        <= 1'b1;       // 复位进 pad：首个数据行 = 行 0
            m_axis_tdata  <= 64'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            m_axis_tuser  <= 3'd0;
            frame_tick    <= 1'b0;
        end else begin
            // ---- tick 推进：pad 计槽 -> 帧界翻转；行尾等待态 -> 新行 ----
            if (in_pad) begin
                if (line_tick) begin
                    // pad 退出（2026-10-19 差一拍修复，同 shape_pat_gen）：
                    // 计满 PAD_TICKS 个空闲 tick，下一 tick 发车行 0，
                    // 帧长恰 = SRC_LINES + PAD_TICKS。
                    if (pad_cnt == PAD_TICKS[6:0]) begin
                        in_pad     <= 1'b0;
                        pad_cnt    <= 7'd0;
                        line_cnt   <= 12'd0;
                        beat_cnt   <= BEAT_WAIT[10:0];   // 进等待态：等 tick+门控发车
                        frame_tick <= ~frame_tick;       // 帧界：reader 重锁基址
                    end else begin
                        pad_cnt <= pad_cnt + 7'd1;
                    end
                end
            end else if (line_tick && (beat_cnt == BEAT_WAIT[10:0])) begin
                if (line_go)
                    beat_cnt <= 11'd0;           // 行尾等待态收到 tick：新行
                // 门控失败：跳过本槽重试（late_cnt 由诊断块计数）
            end

            // ---- 发射推进（按实际发出的 beat 计数，气泡不计）----
            if (emit) begin
                if (eol_beat) begin
                    beat_cnt <= BEAT_WAIT[10:0];         // 回等待态
                    if (line_last) begin
                        in_pad  <= 1'b1;                 // 末行：进帧尾 pad
                        pad_cnt <= 7'd0;
                    end else begin
                        line_cnt <= line_cnt + 12'd1;
                    end
                end else begin
                    beat_cnt <= beat_cnt + 11'd1;
                end
            end

            // ---- 输出打拍（data/valid/last/user 同拍对齐）----
            m_axis_tvalid <= emit;
            m_axis_tdata  <= fifo_rdata;
            m_axis_tlast  <= eol_beat;
            m_axis_tuser  <= {eol_beat && line_last,           // eof
                              sol_beat,                        // sol
                              sol_beat && (line_cnt == 12'd0)}; // sof
        end
    end

    reg [15:0] frame_cnt_r;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            frame_cnt_r <= 16'd0;
            late_cnt    <= 8'd0;
            under_cnt   <= 8'd0;
        end else begin
            if (in_pad && line_tick &&
                (pad_cnt == PAD_TICKS[6:0] - 7'd1))
                frame_cnt_r <= frame_cnt_r + 16'd1;      // 帧界（与 tick 同拍）
            if (in_pad == 1'b0 && line_tick &&
                (beat_cnt == BEAT_WAIT[10:0]) && !line_go)
                late_cnt <= late_cnt + 8'd1;
            if (in_data && !fifo_rd_ok)
                under_cnt <= under_cnt + 8'd1;
        end
    end

    assign gen_frame_cnt = frame_cnt_r;

endmodule
