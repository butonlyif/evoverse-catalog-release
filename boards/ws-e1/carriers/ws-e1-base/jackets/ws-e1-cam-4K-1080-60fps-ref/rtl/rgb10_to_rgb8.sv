`timescale 1ns/1ps
//============================================================================
// rgb10_to_rgb8.sv - RGB10 -> RGB8 量化（AXIS-120 -> AXIS-96，无增益）
//
// v5 起白平衡前移 demosaic 之前（raw_wb_axis，doc/wb_design_spec.md），
// 原 wb_axis 的增益职能移入 RAW 域，本模块只保留其 10->8bit 量化段：
//   v8 = v10 >> 2（÷4 截断 = wb_axis@0x40 的位精确等价；1023>>2=255 无饱和）
//
// 数据流（top_cam）:
//   demosaic (RGB10) -> [本模块] -> rgb2yuv_axis
//
// AXI4-Stream 约定（与 wb_axis 一致）:
//   输入  tdata[119:0] 每拍 4 像素 x {R,G,B} 各 10-bit，
//         px p 占 [30*p +: 30] = {R,G,B}（R 在高位）
//   输出  tdata[95:0]  每拍 4 像素 x {R,G,B} 各 8-bit，打包同上
//         tlast = EOL（行末拍）; tuser = {eof, sol, sof} 原样旁路
//   无 tready —— 源不可暂停，1:1 拍映射（气泡原样传递），
//   下游以 always-ready 消费
//
// 流水: 2 级（量化寄存 -> 输出寄存）。tlast/tuser 同深度 2 级移位、
//   气泡拍清零（wb_axis L88-114 教训：背靠背拍时边带不得提前覆盖/泄漏）。
//============================================================================

module rgb10_to_rgb8 (
    input  logic         aclk,
    input  logic         aresetn,

    // RGB10 输入（AXI4-Stream 从口，无 tready）
    input  logic [119:0] s_axis_tdata,
    input  logic         s_axis_tvalid,
    input  logic         s_axis_tlast,   // EOL
    input  logic [2:0]   s_axis_tuser,   // {eof, sol, sof}

    // RGB8 输出（AXI4-Stream 主口，无 tready）
    output logic [95:0]  m_axis_tdata,   // 4 px x {R,G,B} 8-bit, px0 在 LSB
    output logic         m_axis_tvalid,
    output logic         m_axis_tlast,   // EOL
    output logic [2:0]   m_axis_tuser    // {eof, sol, sof}
);

    //--------------------------------------------------------------------
    // S0: 逐通道 v10 >> 2 寄存（12 lane = 4 px x 3 通道）
    //--------------------------------------------------------------------
    logic [95:0] q8_q;

    genvar gv;
    generate
        for (gv = 0; gv < 12; gv = gv + 1) begin : g_ch
            wire [9:0] v10 = s_axis_tdata[10*gv +: 10];
            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn)
                    q8_q[8*gv +: 8] <= 8'd0;
                else if (s_axis_tvalid)
                    q8_q[8*gv +: 8] <= v10[9:2];
            end
        end
    endgenerate

    //--------------------------------------------------------------------
    // S1: 输出寄存 + 边带同深度移位（数据 2 级：q8_q -> m_axis_tdata，
    //   边带同级 2 级：user1/last1 -> user2/last2）。气泡拍 tvalid=0：
    //   边带移位链同步清零，不把上一拍 last/user 泄漏到气泡后的拍。
    //--------------------------------------------------------------------
    logic       q8_v, last1, last2;
    logic [2:0] user1, user2;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            q8_v          <= 1'b0;
            last1         <= 1'b0;
            user1         <= 3'd0;
            last2         <= 1'b0;
            user2         <= 3'd0;
            m_axis_tdata  <= 96'd0;
            m_axis_tvalid <= 1'b0;
        end else begin
            q8_v          <= s_axis_tvalid;
            last1         <= s_axis_tvalid && s_axis_tlast;
            user1         <= s_axis_tvalid ? s_axis_tuser : 3'd0;
            last2         <= last1;
            user2         <= user1;
            m_axis_tvalid <= q8_v;
            m_axis_tdata  <= q8_q;
        end
    end

    always_comb begin
        m_axis_tlast = m_axis_tvalid && last2;
        m_axis_tuser = m_axis_tvalid ? user2 : 3'd0;
    end

endmodule
