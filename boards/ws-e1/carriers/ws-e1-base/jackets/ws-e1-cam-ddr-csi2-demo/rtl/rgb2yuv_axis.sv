//============================================================================
// rgb2yuv_axis.sv - BT.601 RGB8 -> UYVY（AXI4-Stream，重构自 raw10_color.v
// 的 S3b/S4/S5 段；demosaic 与 WB 拆出为独立模块）
//
// 数据流（全链）:
//   raw_2_axi4st (RAW10) -> demosaic (RGB10) -> wb_axis (RGB8)
//   -> [rgb2yuv_axis 本模块] -> 帧写入/显示
//
// AXI4-Stream 约定（与 wb_axis 一致）:
//   输入  tdata[95:0]  每拍 4 像素 x {R,G,B} 各 8-bit，
//         px p 占 [24*p +: 24]（R 在高位）
//   输出  tdata[63:0]  每拍 4 像素 = 2 个 UYVY 对（4:2:2），
//         对 0 (px0/px1) 在 [31:0]、对 1 (px2/px3) 在 [63:32]，
//         32-bit 对按内存字节序 {Y1, V, Y0, U}（LSB 字节 = U）
//         tlast = EOL; tuser = {eof, sol, sof} 原样旁路
//   无 tready —— 源不可暂停，1:1 拍映射（气泡原样传递）
//
// 处理（与 raw10_color 逐位一致，BT.601/JFIF 定点系数，1/256 缩放）:
//   Y = ( 77R + 150G +  29B) >> 8
//   U = (128B -  43R -  85G) >>> 8，钳 [-128,+127] 后 +128
//   V = (128R - 107G -  21B) >>> 8，同上
//   暗场钳位: blk_clip=1 时 Y < 24 -> Y=0 且 U/V 强制 128（BLKLEVEL=50
//   时暗脚 Y~12，钳掉残留的逐列 FPN 绿竖条；被钳黑像素不带色度噪声）。
//   钳位只在单像素亮度上判，同对的另一像素不受影响。blk_clip=0 旁路
//   （合成图案源：精确码值 ramp 暗部不得被压黑，top 按 ~pat_en 驱动）。
//   色度成对平均: UYVY 每对两像素共享一份色度，取截断均值
//   (u0+u1)>>1（9-bit 和取 [8:1]，与 raw10_color 的 S4 一致）。
//
// 流水: 2 级（S0 逐像素 YUV + 钳位寄存 -> S1 成对平均 + UYVY 装配
// 寄存）。tlast/tuser 与数据同深度移位对齐（同 wb_axis）。
//============================================================================

module rgb2yuv_axis (
    input  logic        aclk,
    input  logic        aresetn,

    // RGB8 输入（AXI4-Stream 从口，无 tready）
    input  logic [95:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    input  logic        s_axis_tlast,   // EOL
    input  logic [2:0]  s_axis_tuser,   // {eof, sol, sof}

    // 暗场钳位使能：1=使能（sensor 域，钳黑电平残留 FPN 噪声）；
    // 0=旁路（合成图案域——精确码值 ramp 的暗部不得被整段压黑，
    // 2026-09 板级：灰 ramp 前 10% 列/行被 Y<24 钳成黑平顶）
    input  logic        blk_clip,

    // UYVY 输出（AXI4-Stream 主口，无 tready）
    output logic [63:0] m_axis_tdata,   // 2 x UYVY 对，对 0 在 [31:0]
    output logic        m_axis_tvalid,
    output logic        m_axis_tlast,   // EOL
    output logic [2:0]  m_axis_tuser    // {eof, sol, sof}
);

    //--------------------------------------------------------------------
    // S0: 逐像素 BT.601 + 暗场钳位 -> YUV 寄存（4 px x 24 bit {Y,U,V}）
    //--------------------------------------------------------------------
    logic [95:0] yuv_q;             // S0 输出寄存
    logic        yuv_v;             // S0 -> S1 有效

    genvar gv;
    generate
        for (gv = 0; gv < 4; gv = gv + 1) begin : g_px
            wire [7:0] r8 = s_axis_tdata[24*gv + 23 -: 8];
            wire [7:0] g8 = s_axis_tdata[24*gv + 15 -: 8];
            wire [7:0] b8 = s_axis_tdata[24*gv + 7  -: 8];

            // 乘加按 32-bit 上下文求值后截到目标宽度，最大值均不溢出
            wire [15:0] y_acc = 77 * r8 + 150 * g8 + 29 * b8;
            wire signed [17:0] u_acc = 128 * b8 - 43 * r8 - 85 * g8;
            wire signed [17:0] v_acc = 128 * r8 - 107 * g8 - 21 * b8;

            // 暗场钳位：Y<24 归零并把色度钉在中性（黑不带彩色噪声）；
            // blk_clip=0 整体旁路（合成图案域）
            wire [7:0] y8_pre = y_acc[15:8];
            wire       y_clip = blk_clip && (y8_pre < 8'd24);
            wire [7:0] y8 = y_clip ? 8'd0 : y8_pre;

            wire signed [9:0] uo = u_acc >>> 8;     // -128..+127 名义范围
            wire signed [9:0] vo = v_acc >>> 8;
            wire [7:0] u8 = y_clip ? 8'd128 :
                            (uo > 10'sd127)  ? 8'd255 :
                            (uo < -10'sd128) ? 8'd0 : (uo + 10'sd128);
            wire [7:0] v8 = y_clip ? 8'd128 :
                            (vo > 10'sd127)  ? 8'd255 :
                            (vo < -10'sd128) ? 8'd0 : (vo + 10'sd128);

            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn)
                    yuv_q[24*gv +: 24] <= {8'd0, 8'd128, 8'd128};
                else if (s_axis_tvalid)
                    yuv_q[24*gv +: 24] <= {y8, u8, v8};
            end
        end
    endgenerate

    //--------------------------------------------------------------------
    // S1: 色度成对平均 + UYVY 装配（内存字节序）+ 输出寄存
    //   边带同深度移位：气泡拍清零，不泄漏上一拍 last/user。
    //--------------------------------------------------------------------
    logic [7:0] y0, y1, y2, y3;
    logic [7:0] u0, u1, u2, u3;
    logic [7:0] v0, v1, v2, v3;
    logic [8:0] u01, v01, u23, v23;     // 对内色度和，[8:1] = 截断均值

    always_comb begin
        y0 = yuv_q[23:16]; u0 = yuv_q[15:8];  v0 = yuv_q[7:0];
        y1 = yuv_q[47:40]; u1 = yuv_q[39:32]; v1 = yuv_q[31:24];
        y2 = yuv_q[71:64]; u2 = yuv_q[63:56]; v2 = yuv_q[55:48];
        y3 = yuv_q[95:88]; u3 = yuv_q[87:80]; v3 = yuv_q[79:72];
        u01 = {1'd0, u0} + {1'd0, u1};
        v01 = {1'd0, v0} + {1'd0, v1};
        u23 = {1'd0, u2} + {1'd0, u3};
        v23 = {1'd0, v2} + {1'd0, v3};
    end

    logic       last1,  last2;
    logic [2:0] user1,  user2;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            yuv_v         <= 1'b0;
            last1         <= 1'b0;
            user1         <= 3'd0;
            last2         <= 1'b0;
            user2         <= 3'd0;
            m_axis_tdata  <= 64'd0;
            m_axis_tvalid <= 1'b0;
        end else begin
            yuv_v         <= s_axis_tvalid;
            last1         <= s_axis_tvalid && s_axis_tlast;
            user1         <= s_axis_tvalid ? s_axis_tuser : 3'd0;
            last2         <= last1;
            user2         <= user1;
            m_axis_tvalid <= yuv_v;
            m_axis_tdata  <= {y3, v23[8:1], y2, u23[8:1],
                              y1, v01[8:1], y0, u01[8:1]};
        end
    end

    always_comb begin
        m_axis_tlast = m_axis_tvalid && last2;
        m_axis_tuser = m_axis_tvalid ? user2 : 3'd0;
    end

endmodule
