//============================================================================
// raw_2_axi4st.sv - CSI-2 RAW10 像素流窗口过滤 -> AXI4-Stream 主接口
//
// raw10_window.v 的重构版（旧文件保留未动，工程尚未切换）。从传感器拍流
// 中提取有效记录窗口，重新发出干净、拍对齐的 AXI4-Stream：
//
//   1) datatype 门控: 仅 in_dtype == DTYPE 的拍是像素（如 RAW10 的
//      0x2B）；控制流/嵌数据包（其它 DT）被跳过，win0 也不被污染
//   2) 像素窗口: 每行丢弃前 LEAD_PIX、后 TRAIL_PIX 个像素。前导
//      用 win0（上一个 DT 拍）做动态位滑动（slide = (lead%4)*10，即
//      0/10/20/30 bit），输出保持每拍 4 像素对齐
//   3) 行窗口: 只对"限定行"计数 —— hs 之后首个 datatype 匹配且 valid
//      的拍所在行（OB=0x37、EBD 无有效拍，均不占行号）。丢弃帧首
//      LINE_SKIP_FIRST 条限定行，第 LINE_SKIP_FIRST+1 条限定行丢弃
//      LEAD_PIX 前导后的第一拍即帧首（sof），其后输出 LINES 行
//   4) 热接入契约: 复位释放后须见首个真实 in_vs 上升沿（vs_d 复位值 1，
//      释放时已高的 vs 不合成 rise）才产生行号（saw_vs 门控）——中途
//      接入的残流不会数出假 sof；vs 同时清 hs_seen，落在行载荷中段
//      时半行不占行号
//
// AXI4-Stream 输出（视频惯例）:
//   m_axis_tvalid        窗口内拍有效（行消隐期间自然为低）
//   m_axis_tdata[39:0]   4xRAW10 打包（5 字节，字节对齐）
//   m_axis_tlast         每行最后一拍（EOL）
//   m_axis_tuser[2:0]    {eof, sol, sof}，仅在 tvalid=1 的拍有意义
//                        sol=行首拍, sof=帧首拍, eof=帧末拍
//
// 背压: 本模块没有 m_axis_tready —— 源（CSI-2 RX）不可暂停，下游以
// always-ready 消费（如帧写 FIFO 吸收背压）。行内拍流连续，洞只出现在
// 行/帧消隐处，下游按 sol/eol 重建几何（列=拍计数，行=行计数）。
//
// 几何全部为编译期 parameter（起始拍/滑动量/窗口终点/行区间由 localparam
// 在 elaborate 时预算好，逐拍路径只剩比较器）。更改传感器模式需修改参数
// 重新综合。
//
// 约束（实例化者保证）:
//   (行总像素 - lead_pix - trail_pix) 是 4 的倍数，否则最后一拍会混入
//   后续像素；lead/trail 小于行总像素；skip_first + lines <= 2^20。
//
// RAM: 不需要任何 RAM —— 滑动窗仅一个 40-bit 寄存器 win0，不存在推断
// 分布式 RAM 的风险。
//
// 计数细节（沿用已验证的 raw10_window 语义）:
//   - col_cnt 只统计 DT 匹配拍；限定行首拍组合清零（col_eff），窗口
//     判定用当前拍下标，不依赖 hs 脉冲与载荷的相对相位
//   - 行尾恒有窗口外尾拍（trail 裁剪保证），限定行首拍 col_eff=0 强制
//     重新对齐，陈旧计值不可能误发一拍
//   - line_no = line_cnt + line_qual：限定行首拍组合 +1，1-based 行号
//============================================================================

module raw_2_axi4st #(
    parameter logic [5:0]  DTYPE           = 6'h2B,     // 缺省像素 DT（RAW10）
    parameter logic [19:0] LINE_TOTAL_PIX  = 20'd1944,  // 行总像素（IMX415, WC=2430）
    parameter logic [19:0] LEAD_PIX        = 20'd6,     // 行首丢弃像素
    parameter logic [19:0] TRAIL_PIX       = 20'd18,    // 行尾丢弃像素
    parameter logic [19:0] LINE_SKIP_FIRST = 20'd11,    // 帧首丢弃 hs 行数
    parameter logic [19:0] LINES           = 20'd1080   // 输出行数
) (
    input  logic        aclk,
    input  logic        aresetn,

    // 传感器/图案拍流（不可暂停源）
    (* syn_keep = "true" *) input  logic [39:0] in_data,        // 4xRAW10 打包
    (* syn_keep = "true" *) input  logic        in_valid,
    (* syn_keep = "true" *) input  logic        in_vs,          // 帧起始（上升沿）
    (* syn_keep = "true" *) input  logic        in_hs,          // 行同步（脉冲或行电平均可，
                                        //  仅参与限定行判定）
    input  logic [5:0]  in_dtype,

    // AXI4-Stream 主口（无 tready：always-ready 源）
    (* syn_keep = "true" *) output logic [39:0] m_axis_tdata,
    (* syn_keep = "true" *) output logic        m_axis_tvalid,
    (* syn_keep = "true" *) output logic        m_axis_tlast,
    (* syn_keep = "true" *) output logic [2:0]  m_axis_tuser    // {eof, sol, sof}
);

    //--------------------------------------------------------------------
    // 窗口几何（编译期预算，localparam 常量折叠）
    //   起始拍 = ceil(lead/4)；滑动量 = (lead%4)*10；
    //   窗口拍数 = (total - lead - trail)/4；终点 = 起始 + 窗口拍数
    //--------------------------------------------------------------------
    localparam logic [20:0] P_START21 = ({1'b0, LEAD_PIX} + 21'd3) >> 2;
    // x*10 = (x<<3) + (x<<1)
    localparam logic [4:0]  P_SLIDE   = {LEAD_PIX[1:0], 3'b000}
                                      + {3'b000, LEAD_PIX[1:0], 1'b0};
    localparam logic [20:0] P_END21   = P_START21
                                      + ((({1'b0, LINE_TOTAL_PIX}
                                          - {1'b0, LEAD_PIX})
                                          - {1'b0, TRAIL_PIX}) >> 2);
    localparam logic [19:0] P_WIN_START = P_START21[19:0];
    localparam logic [19:0] P_WIN_END   = P_END21[19:0];
    localparam logic [19:0] P_LINE_FIRST = LINE_SKIP_FIRST + 20'd1; // 首输出限定行(1-based)
    localparam logic [19:0] P_LINE_LAST  = P_LINE_FIRST + LINES - 20'd1;

    //--------------------------------------------------------------------
    // 限定行判定与边沿脉冲
    //   限定行 = hs 之后首个 datatype 匹配且 valid 的拍所在行；
    //   OB(其它 DT)/EBD(无有效拍) 不产生 line_qual，不占行号。
    //   兼容三种 hs 形态: 先脉冲后载荷 / 脉冲与首拍同拍 / 行电平。
    //--------------------------------------------------------------------
    logic       dt_ok;
    logic       vs_d, hs_d;
    logic       vs_rise, hs_rise;
    logic       dt_hit;         // 当前拍是有效 DT 拍
    logic       hs_seen;        // hs 已见、尚无有效 DT 拍
    logic       saw_vs;         // 复位后已见首个 in_vs（热接入门控）
    logic       line_qual;      // 限定行首拍

    assign dt_ok    = (in_dtype == DTYPE);
    assign dt_hit   = in_valid && dt_ok;
    assign vs_rise  = in_vs & ~vs_d;
    assign hs_rise  = in_hs & ~hs_d;
    // 首个 vs 之前不产生行号（复位热接入的残流数不出假 sof）；
    // vs 与帧首行 hs 同拍的源形态由 vs_rise&&hs_rise 项覆盖
    assign line_qual = dt_hit && (hs_rise || hs_seen)
                       && (saw_vs || (vs_rise && hs_rise));

    //--------------------------------------------------------------------
    // 几何计数（DT 拍下标 / 限定行号）+ 滑动窗寄存器
    //--------------------------------------------------------------------
    logic [39:0] win0;      // 上一个 DT 匹配拍（滑动窗低段）
    logic [19:0] col_cnt;   // 行内已完成的 DT 拍数
    logic [19:0] line_cnt;  // 帧内已完成限定行数

    logic [19:0] col_eff;   // 当前拍下标（限定行首拍组合清零）
    logic [19:0] line_no;   // 1-based：限定行首拍组合 +1
    assign col_eff = line_qual ? 20'd0 : col_cnt;
    assign line_no = line_cnt + {19'd0, line_qual};

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            vs_d     <= 1'b1;               // 须见"下降沿后的上升沿"才认帧界：
                                            // 复位释放时 in_vs 已高不合成假 rise
            hs_d     <= 1'b0;
            hs_seen  <= 1'b0;
            saw_vs   <= 1'b0;
            win0     <= 40'd0;
            col_cnt  <= 20'd0;
            line_cnt <= 20'd0;
        end else begin
            vs_d    <= in_vs;
            hs_d    <= in_hs;
            // vs_rise 块须在 hs_seen 链之前：vs 与 hs 同拍时 hs_rise
            // 置位要胜过帧界清零，否则帧首行漏计
            if (vs_rise) begin
                line_cnt <= 20'd0;
                hs_seen  <= 1'b0;           // 帧界重置：半行不占行号
                saw_vs   <= 1'b1;           // 热接入后等真帧首
            end else if (line_qual)
                line_cnt <= line_cnt + 20'd1;
            if (line_qual)
                hs_seen <= 1'b0;
            else if (hs_rise)
                hs_seen <= 1'b1;
            if (dt_hit)
                win0 <= in_data;            // 仅 DT 拍填充，免疫嵌数据包
            if (line_qual)
                col_cnt <= 20'd1;           // 当前拍为下标 0，下一拍为 1
            else if (dt_hit)
                col_cnt <= col_cnt + 20'd1;
        end
    end

    //--------------------------------------------------------------------
    // 窗口判定 + AXI4-Stream 输出
    //--------------------------------------------------------------------
    logic [79:0] slide_bus;     // {当前拍, 上一拍} 拼接，动态右移 a_slide
    logic        beat;          // DT 匹配拍
    logic        in_win;        // 列在窗口内
    logic        line_win;      // 行在窗口内
    logic        sol_beat;      // 行首拍
    logic        eol_beat;      // 行尾拍

    assign slide_bus = {in_data, win0};
    assign beat      = in_valid && dt_ok;
    assign in_win    = (col_eff >= P_WIN_START) && (col_eff < P_WIN_END);
    assign line_win  = (line_no >= P_LINE_FIRST) && (line_no <= P_LINE_LAST);
    assign sol_beat  = (col_eff == P_WIN_START);
    assign eol_beat  = (col_eff == (P_WIN_END - 20'd1));

    always_comb begin
        m_axis_tvalid = beat && in_win && line_win;
        // 右移后截取低 40 位 = 取拼接流的 [P_SLIDE +: 40]
        m_axis_tdata  = slide_bus >> P_SLIDE;
        m_axis_tlast  = m_axis_tvalid && eol_beat;
        m_axis_tuser  = {m_axis_tvalid && eol_beat
                             && (line_no == P_LINE_LAST),          // eof
                         m_axis_tvalid && sol_beat,                // sol
                         m_axis_tvalid && sol_beat
                             && (line_no == P_LINE_FIRST)};        // sof
    end

endmodule
