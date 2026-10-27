//============================================================================
// wb_axis.sv - 白平衡 RGB10 -> RGB8（AXI4-Stream，重构自 raw10_color.v
// 的 S3a WB 段；demosaic 与 BT.601 拆出为独立模块）
//
// 数据流（全链）:
//   raw_2_axi4st (RAW10 窗口流) -> demosaic (RGB10) -> [wb_axis 本模块]
//   -> rgb2yuv_axis
//
// AXI4-Stream 约定（与 demosaic 一致）:
//   输入  tdata[119:0] 每拍 4 像素 x {R,G,B} 各 10-bit，
//         px p 占 [30*p +: 30] = {R,G,B}（R 在高位）
//   输出  tdata[95:0]  每拍 4 像素 x {R,G,B} 各 8-bit，打包同上
//         tlast = EOL（行末拍）; tuser = {eof, sol, sof} 原样旁路
//   无 tready —— 源不可暂停，1:1 拍映射（气泡原样传递），
//   下游以 always-ready 消费
//
// 处理（与 raw10_color 逐位一致）:
//   v8 = saturate255((v10 * gain) >> 8)
//   增益 CSR 8 bit，隐含 x4 编码：0x40 = x1.0，0xFF = x3.98。
//   >>8 把 10x8 乘积按 1/256 缩放 = 1/64 增益解码乘 1/4 的
//   raw10->8bit 缩放，故 1023 * 0x40 = 255。
//   乘积最大 1023*0xFF，>>8 后 [17:8] 非零即溢出 -> 钳 255。
//
// 流水: 2 级（S0 乘法+饱和寄存 -> S1 输出寄存）。tlast/tuser 与数据
// 同深度移位对齐 —— 不能只移一级：背靠背拍时下一拍的边带会提前
// 覆盖当前拍（数据在 S1 寄存而边带只在 S0）。
//============================================================================

module wb_axis (
    input  logic         aclk,
    input  logic         aresetn,

    // RGB10 输入（AXI4-Stream 从口，无 tready）
    input  logic [119:0] s_axis_tdata,
    input  logic         s_axis_tvalid,
    input  logic         s_axis_tlast,   // EOL
    input  logic [2:0]   s_axis_tuser,   // {eof, sol, sof}

    // 白平衡增益（CSR 域，直接静态/慢变；0x40 = x1.0）
    input  logic [7:0]   wb_r,
    input  logic [7:0]   wb_g,
    input  logic [7:0]   wb_b,

    // RGB8 输出（AXI4-Stream 主口，无 tready）
    output logic [95:0]  m_axis_tdata,   // 4 px x {R,G,B} 8-bit, px0 在 LSB
    output logic         m_axis_tvalid,
    output logic         m_axis_tlast,   // EOL
    output logic [2:0]   m_axis_tuser    // {eof, sol, sof}
);

    //--------------------------------------------------------------------
    // S0: 逐像素 (v10 * gain) >> 8 + 饱和 -> RGB8 寄存
    //--------------------------------------------------------------------
    logic [95:0] wb_q;              // S0 输出寄存（4 px x 24 bit）
    logic        wb_v;              // S0 -> S1 有效

    genvar gv;
    generate
        for (gv = 0; gv < 4; gv = gv + 1) begin : g_px
            wire [29:0] px  = s_axis_tdata[30*gv +: 30];
            wire [9:0]  r10 = px[29:20];
            wire [9:0]  g10 = px[19:10];
            wire [9:0]  b10 = px[9:0];

            // 10x8 乘积按 LHS 18 bit 上下文求值（最大 1023*255 < 2^18，
            // 无溢出）；>>8 后 [17:8] 非零 = >255，钳 255
            wire [17:0] rw = ({1'b0, r10} * {2'b00, wb_r}) >> 8;
            wire [17:0] gw = ({1'b0, g10} * {2'b00, wb_g}) >> 8;
            wire [17:0] bw = ({1'b0, b10} * {2'b00, wb_b}) >> 8;
            wire [7:0]  rc = (rw[17:8] != 8'd0) ? 8'hFF : rw[7:0];
            wire [7:0]  gc = (gw[17:8] != 8'd0) ? 8'hFF : gw[7:0];
            wire [7:0]  bc = (bw[17:8] != 8'd0) ? 8'hFF : bw[7:0];

            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn)
                    wb_q[24*gv +: 24] <= 24'd0;
                else if (s_axis_tvalid)
                    wb_q[24*gv +: 24] <= {rc, gc, bc};
            end
        end
    endgenerate

    //--------------------------------------------------------------------
    // S1: 输出寄存 + 边带同深度移位（tlast/tuser 与数据同拍对齐）
    //   气泡拍 tvalid=0：边带移位链同步清零，不会把上一拍的 last/user
    //   泄漏到气泡之后的拍。
    //--------------------------------------------------------------------
    logic       last1,  last2;
    logic [2:0] user1,  user2;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wb_v          <= 1'b0;
            last1         <= 1'b0;
            user1         <= 3'd0;
            last2         <= 1'b0;
            user2         <= 3'd0;
            m_axis_tdata  <= 96'd0;
            m_axis_tvalid <= 1'b0;
        end else begin
            wb_v          <= s_axis_tvalid;
            last1         <= s_axis_tvalid && s_axis_tlast;
            user1         <= s_axis_tvalid ? s_axis_tuser : 3'd0;
            last2         <= last1;
            user2         <= user1;
            m_axis_tvalid <= wb_v;
            m_axis_tdata  <= wb_q;
        end
    end

    always_comb begin
        m_axis_tlast = m_axis_tvalid && last2;
        m_axis_tuser = m_axis_tvalid ? user2 : 3'd0;
    end

endmodule
