`timescale 1ns/1ps
//============================================================================
// raw_wb_axis.sv - RAW10 域白平衡（AXIS-40 -> AXIS-40，doc/wb_design_spec.md）
//
// 位置（top_cam，v5 起）:
//   frame_reader 回放 -> [本模块] -> demosaic -> rgb10_to_rgb8 -> rgb2yuv
//   （白平衡从 demosaic 之后的 wb_axis 前移至此；wb_axis 已退出路径）
//
// 数据流（doc/wb_design_spec.md §2/§3）:
//   q = (pix × g_fp + 2048) >> 12，饱和钳 1023；U4.12 增益（1.0=0x1000）
//   1.0 位精确直通：(v×4096+2048)>>12 = v
//
// AXI4-Stream 约定（与 raw_2_axi4st/demosaic 一致）:
//   tdata[39:0] 4×RAW10（px0 在 LSB，行内从左到右）
//   tlast = EOL；tuser = {eof, sol, sof}；无 tready —— 源不可暂停，
//   1:1 拍映射（气泡原样传递），下游以 always-ready 消费
//
// 通道判定（与 demosaic 逐位一致，R5）:
//   c_of 逐位拷贝自 demosaic.sv；row_p 行奇偶：sof 拍清 0、sol 拍翻转
//   （sof/sol 同拍 sof 优先）；每拍 4 像素仅 2 个通道类（cp=px[0]），
//   px0/px2 共用 gA、px1/px3 共用 gB —— 每 beat 4 次乘法
//
// pat_bypass（R6）: 1 = 全通道强制 0x1000，位精确直通（图案源已按显示
//   幅度编码，任何增益都会变色，v4.10c 板级结论）
//
// 增益 CDC: CSR 域准静态多位直入（同 wb_axis 惯例，改写瞬间允许单帧毛刺）
//
// 流水: 2 级（S0 乘法+舍入+饱和寄存 -> 输出寄存）；tlast/tuser 同深度
//   2 级移位、气泡拍边带清零不泄漏（wb_axis L88-114 原款）。
// 资源: 4 × 10×16 乘法/拍，无 RAM。dbg_sat = 含饱和像素的拍计数（16b 自由计数）
//============================================================================

module raw_wb_axis (
    input  logic         aclk,
    input  logic         aresetn,

    // RAW10 输入（AXI4-Stream 从口，无 tready）
    input  logic [39:0]  s_axis_tdata,   // 4×RAW10，px0 在 LSB
    input  logic         s_axis_tvalid,
    input  logic         s_axis_tlast,   // EOL
    input  logic [2:0]   s_axis_tuser,   // {eof, sol, sof}

    // Bayer 相位（CSR 域，与 demosaic 同源同值）
    input  logic [1:0]   bayer_phase,    // 0=RGGB 1=GRBG 2=GBRG 3=BGGR

    // 增益 U4.12（CSR 域准静态；1.0 = 16'h1000）
    input  logic [15:0]  wb_r,
    input  logic [15:0]  wb_g,
    input  logic [15:0]  wb_b,

    // 图案源直通（1 = unity 位精确）
    input  logic         pat_bypass,

    // RAW10 输出（AXI4-Stream 主口，无 tready）
    output logic [39:0]  m_axis_tdata,
    output logic         m_axis_tvalid,
    output logic         m_axis_tlast,   // EOL
    output logic [2:0]   m_axis_tuser,   // {eof, sol, sof}

    // 观测：含饱和像素的拍计数（16b 自由计数 -> CSR DIAG21）
    output logic [15:0]  dbg_sat
);

    //--------------------------------------------------------------------
    // 站类查表 —— 逐位拷贝 demosaic.sv c_of（0=R 1=G 2=B），
    // (行奇偶 rp, 拍内像素奇偶 cp) 选象限
    //--------------------------------------------------------------------
    function automatic logic [1:0] c_of (input logic [1:0] ph,
                                         input logic       rp,
                                         input logic       cp);
        case (ph)
            2'd0: c_of = (!rp && !cp) ? 2'd0 : (rp && cp) ? 2'd2 : 2'd1;   // RGGB
            2'd1: c_of = (!rp && cp)  ? 2'd0 : (rp && !cp) ? 2'd2 : 2'd1;  // GRBG
            2'd2: c_of = (!rp && cp)  ? 2'd2 : (rp && !cp) ? 2'd0 : 2'd1;  // GBRG
            default: c_of = (!rp && !cp) ? 2'd2 : (rp && cp) ? 2'd0 : 2'd1;// BGGR
        endcase
    endfunction

    //--------------------------------------------------------------------
    // 行奇偶跟踪：sof 清 0（每帧首行 = 偶行），sol 翻转
    //   当拍组合生效（row_cur）：行首拍即用本行奇偶，寄存值下一拍才
    //   落 —— 若直接用 row_p，每行首拍会错用上一行奇偶（4px 异色）。
    //   与 demosaic rp = 真实内容行奇偶 一致（R5；首行 = 偶行 = RGGB
    //   的 R 行，板级实证约定）。
    //--------------------------------------------------------------------
    logic row_p;
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            row_p <= 1'b0;
        else if (s_axis_tvalid) begin
            if      (s_axis_tuser[0]) row_p <= 1'b0;    // sof（优先）
            else if (s_axis_tuser[1]) row_p <= ~row_p;  // sol
        end
    end

    wire row_cur = s_axis_tvalid ? (s_axis_tuser[0] ? 1'b0 :
                                    s_axis_tuser[1] ? ~row_p : row_p)
                                 : row_p;

    //--------------------------------------------------------------------
    // 每拍 2 个通道类 -> 2 个增益（pat_bypass 强制 unity）
    //--------------------------------------------------------------------
    wire [1:0]  chA = c_of(bayer_phase, row_cur, 1'b0);   // px0/px2
    wire [1:0]  chB = c_of(bayer_phase, row_cur, 1'b1);   // px1/px3

    wire [15:0] g_r = pat_bypass ? 16'h1000 : wb_r;
    wire [15:0] g_g = pat_bypass ? 16'h1000 : wb_g;
    wire [15:0] g_b = pat_bypass ? 16'h1000 : wb_b;

    wire [15:0] gA  = (chA == 2'd0) ? g_r : (chA == 2'd2) ? g_b : g_g;
    wire [15:0] gB  = (chB == 2'd0) ? g_r : (chB == 2'd2) ? g_b : g_g;

    //--------------------------------------------------------------------
    // S0: 4 lane 并行 乘法+舍入+饱和（10×16=26b 乘积，1023×65535<2^26）
    //--------------------------------------------------------------------
    logic [39:0] wb_q;
    wire  [3:0]  sat_lane;

    genvar gv;
    generate
        for (gv = 0; gv < 4; gv = gv + 1) begin : g_px
            wire [9:0]  pix  = s_axis_tdata[10*gv +: 10];
            wire [15:0] gsel = gv[0] ? gB : gA;
            wire [25:0] prod = pix * gsel;
            wire [13:0] q    = (prod + 26'h800) >> 12;   // +2048 舍入
            wire [9:0]  satv = (q > 14'h3FF) ? 10'h3FF : q[9:0];

            assign sat_lane[gv] = (q > 14'h3FF);

            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn)
                    wb_q[10*gv +: 10] <= 10'd0;
                else if (s_axis_tvalid)
                    wb_q[10*gv +: 10] <= satv;
            end
        end
    endgenerate

    // 饱和观测（每拍至多 +1；含任一 lane 钳 1023 的拍）
    wire sat_any = s_axis_tvalid & (|sat_lane);

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            dbg_sat <= 16'd0;
        else if (sat_any)
            dbg_sat <= dbg_sat + 16'd1;
    end

    //--------------------------------------------------------------------
    // 输出寄存 + 边带同深度移位（数据 2 级：wb_q -> m_axis_tdata，
    // 边带同级 2 级：user1/last1 -> user2/last2）；气泡拍边带清零
    // 不泄漏（wb_axis L88-114 原款）
    //--------------------------------------------------------------------
    logic       wb_v, last1, last2;
    logic [2:0] user1, user2;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wb_v          <= 1'b0;
            last1         <= 1'b0;
            user1         <= 3'd0;
            last2         <= 1'b0;
            user2         <= 3'd0;
            m_axis_tdata  <= 40'd0;
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
