//============================================================================
// axis_frame_check.sv - AXI4-Stream 视频流行长/帧长板级检测（纯旁挂观测）
//
// 接在 raw_2_axi4st 的 m_axis_* 上（或任何同约定的视频 AXIS 流），统计：
//   - 每行 beat 数：最后一行的值 + 本帧最小/最大值
//     （min==max==期望值 即证明全帧行长一致，无需逐行读取）
//   - 每帧总 beat 数 / 总行数（eof 锁存，准静态）
//   - sticky 错误标志：行长 != 期望 / 帧行数 != 期望 / 帧 beat 总数 != 期望
//
// 约定（与 raw_2_axi4st 输出一致，视频惯例）:
//   tlast        = 行尾（EOL）
//   tuser[0]     = sof 帧首拍
//   tuser[1]     = sol 行首拍
//   tuser[2]     = eof 帧末拍
//   无 tready（always-ready 源）；本模块为纯观测，不影响数据流
//
// 输出全部为锁存后的准静态信号，适合：
//   1) mark_debug → Efinity Debugger LA 观测/触发（现工程调试流程）
//   2) 接入 APB CSR 读数（如挂到 cam_frame_writer 的寄存器空间）
//   3) mon_frame_done 为单拍脉冲，可作 LA 触发条件
//============================================================================

module axis_frame_check #(
    parameter int unsigned EXPECT_LINE_BEATS = 480,     // 每行期望 beat 数
    parameter int unsigned EXPECT_LINES      = 1080     // 每帧期望行数
) (
    input  logic        aclk,
    input  logic        aresetn,

    // AXI4-Stream 观测口（只需控制边带）
    input  logic        s_axis_tvalid,
    input  logic        s_axis_tlast,    // 行尾 EOL
    input  logic [2:0]  s_axis_tuser,    // {eof, sol, sof}

    // 锁存结果
    output logic [19:0] mon_line_last,   // 最近一行的 beat 数（每 EOL 更新）
    output logic [19:0] mon_line_min,    // 本帧最短行
    output logic [19:0] mon_line_max,    // 本帧最长行
    output logic [23:0] mon_frame_beats, // 上一完整帧 tvalid 总拍数
    output logic [15:0] mon_frame_lines, // 上一完整帧行数
    output logic        mon_frame_done,  // 帧完成单拍脉冲（触发用）
    output logic [3:0]  mon_err          // {frame_beat_err, frame_line_err,
                                         //  line_len_err, seen_frame}
);

    localparam int unsigned EXPECT_FRAME_BEATS = EXPECT_LINE_BEATS * EXPECT_LINES;

    logic [19:0] beat_cnt;      // 行内已计拍（不含当前拍）
    logic [23:0] fbeat_cnt;     // 帧内已计拍（不含当前拍）
    logic [15:0] line_cnt;      // 帧内已完成行数
    logic        frame_act;     // 帧进行中（sof..eof）

    wire        sof = s_axis_tvalid && s_axis_tuser[0];
    wire        eol = s_axis_tvalid && s_axis_tlast;
    wire        eof = s_axis_tvalid && s_axis_tuser[2];
    wire [19:0] cur_line_beats = beat_cnt + 20'd1;   // 当前行累计（含当前拍）
    wire [23:0] cur_fbeat      = fbeat_cnt + 24'd1;  // 当前帧累计（含当前拍）

    assign mon_frame_done = frame_act && eol && eof;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            beat_cnt        <= 20'd0;
            fbeat_cnt       <= 24'd0;
            line_cnt        <= 16'd0;
            frame_act       <= 1'b0;
            mon_line_last   <= 20'd0;
            mon_line_min    <= 20'hFFFFF;
            mon_line_max    <= 20'd0;
            mon_frame_beats <= 24'd0;
            mon_frame_lines <= 16'd0;
            mon_err         <= 4'b0000;
        end else begin
            if (sof) begin
                // 帧起点：sof 拍本身计为当行第 1 拍
                frame_act    <= 1'b1;
                beat_cnt     <= 20'd1;
                fbeat_cnt    <= 24'd1;
                line_cnt     <= 16'd0;
                mon_line_min <= 20'hFFFFF;
                mon_line_max <= 20'd0;
            end else begin
                if (s_axis_tvalid) begin
                    beat_cnt  <= eol ? 20'd0 : (beat_cnt + 20'd1);
                    fbeat_cnt <= fbeat_cnt + 24'd1;
                end
                if (frame_act && eol) begin
                    mon_line_last <= cur_line_beats;
                    if (cur_line_beats < mon_line_min)
                        mon_line_min <= cur_line_beats;
                    if (cur_line_beats > mon_line_max)
                        mon_line_max <= cur_line_beats;
                    line_cnt <= line_cnt + 16'd1;
                    if (cur_line_beats != EXPECT_LINE_BEATS[19:0])
                        mon_err[1] <= 1'b1;             // 行长错误（sticky）
                end
            end

            if (frame_act && eof) begin
                // 帧收尾：锁存总数并与期望比较
                mon_frame_beats <= cur_fbeat;
                mon_frame_lines <= line_cnt + 16'd1;
                frame_act       <= 1'b0;
                mon_err[0]      <= 1'b1;                // 已完成至少一帧
                if (cur_fbeat != EXPECT_FRAME_BEATS[23:0])
                    mon_err[3] <= 1'b1;                 // 帧总拍数错误
                if ((line_cnt + 16'd1) != EXPECT_LINES[15:0])
                    mon_err[2] <= 1'b1;                 // 帧行数错误
            end
        end
    end

endmodule
