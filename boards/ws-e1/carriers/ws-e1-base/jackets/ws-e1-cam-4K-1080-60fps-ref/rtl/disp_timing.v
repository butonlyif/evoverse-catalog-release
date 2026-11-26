// ============================================================================
// disp_timing.v — 本地显示时序发生器 v2（架构 v4 Phase 3/4，mod-disp-timing）
//
// 显示时序唯一发生源（R1：与源零反馈）：本地 h/v FSM 推进 LINE_CLKS pclk/行
// × FRAME_SLOTS 槽/帧。HBP 末门点检查 tx_line_buf 水位 ≥ LINE_WORDS 才开
// 行（alg-line-gate，规格 GATE 冻结语义 v4.4）：不足则 **h 冻结等水位**
// （late_cnt++ 每冻结行一次）——行内 valid 永不断流（R4），机构无 sof 重
// 锚（R8）。
//
// 行结构（pclk）：HSP 44 | HBP 75 | GATE | PREF 2 | HACT 960 拍 | HFP 18
//   = 1100（HACT=LINE_WORDS；PREF 为拉取管线预取对齐拍；GATE 冻结期行周
//   期拉长）。空白行（VSP/VBP/VFP/PAD）免冻结（无拉取），但同样占满 1100。
// 帧结构（行槽）：VSP+VBP+VACT+VFP+PAD = FRAME_SLOTS（2250）。4K60 标准
// 消隐 = VSP 10 | VBP 72 | VFP 8（共 90 槽）——规格"2160 数据 + 90 pad"
// 的 90 即此消隐，PAD 只是余项（实例按 FRAME_SLOTS - VSP-VBP-VACT-VFP
// 推导，独立叠加 PAD 会重复计入：2026-10-21 板级 2340 槽 = 57.69Hz 教训）。
// c3l（2026-10-22）曾试 VSP 8/VFP 10 补偿顶部 2 行滚屏：板测无效已回退
// ——滚屏与 vsync↔数据相对时序无关（详见 top_cam_demo 顶层注释）。
//
// !! v4.4 关键（56fps 极限环根因修复）：line_tick_o 由 **自由跑 1100 计数
// 器**发生，与门控冻结解耦——冻结只拉长显示自身行周期，**不拖慢 reader 槽
// 节拍**（tick 若随冻结拉伸，reader 供给同步延迟 → 门点持续缺水 → 43~56fps
// 极限环，板级实测）。冻结仅吸收瞬态欠供；稳态水位恒 ≥960（首行填充后
// ΔL=0），零冻结、严格 60fps。
//
// TX 接口输出契约 1:1 同 shape_video_axis（D8）：hsync/vsync 低有效（寄存
// 输出）、datatype 常量 6'h1E（YUV422 8b）、haddr=HACT 像素、line_num/
// frame_num 递进、frame_open 为 VBP 末 1 拍脉冲。
// ============================================================================
module disp_timing #(
    parameter LINE_CLKS   = 1100,
    parameter FRAME_SLOTS = 2250,       // VSP+VBP+VACT+VFP+PAD
    parameter LINE_WORDS  = 960,        // HACT 拉取拍数（= HACT/PPC）
    parameter VSP_L    = 10,
    parameter VBP_L    = 72,
    parameter VACT_L   = 2160,
    parameter VFP_L    = 8,
    parameter PAD_L    = 0,             // = FRAME_SLOTS - VSP-VBP-VACT-VFP
                                        //（余项，勿独立叠加消隐）
    parameter HSP_CLKS = 44,
    parameter HBP_CLKS = 75,
    parameter HFP_CLKS = 18,            // 行 = HSP+HBP+GATE(1)+PREF+HACT+HFP
    parameter HACT_PX  = 3840,          // TX haddr（PPC=4 x LINE_WORDS）
    // v4.9：GATE 门限（tx_line_buf 水位口径 = 64b 字，1 行 = 600 字/4K）。
    // 此前 GATE 误用 LINE_WORDS（960 = HACT 拍数）比 64b 字水位 = 门限
    // 1.6 行 -> 帧尾行水位 ~848 字 < 960 -> 每帧帧尾冻结 -> 显示周期
    // 拉伸 -> 帧界滑移 = 板级斜向卷根因之二。
    parameter LINE_BUF_WORDS = 600,
    parameter [5:0] DATA_TYPE = 6'h1E
) (
    input  wire        clk,
    input  wire        rst_n,
    // tx_line_buf 读侧（拉取拍流，读延迟 2 拍）
    output wire        buf_rd_en,
    input  wire [63:0] buf_rdata,
    input  wire        buf_valid,
    input  wire [15:0] buf_level,
    // TX Video Interface（D8 契约）
    output wire        hsync,          // 低有效（HSP 段）
    output wire        vsync,          // 低有效（VSP 段）
    output wire [5:0]  datatype,
    output wire [63:0] pixel_data,
    output wire        pixel_data_valid,
    output wire [15:0] haddr,
    output reg  [15:0] line_num,       // VACT 行号 0..VACT_L-1
    output reg  [15:0] frame_num,
    output wire        frame_open,     // VBP 末 1 拍脉冲
    output reg         line_tick_o,    // 自由跑行节拍（reader 槽节拍同源）
    output wire [31:0] dbg_dtg_cnt_o   // {late_cnt[15:0], under_cnt[15:0]}
);

    localparam PREF_D = 2;               // 拉取管线预取对齐（tx_line_buf 2 拍延迟）

    // ---- 结构守卫：行/槽参数自洽 ----
    // synthesis translate_off
    initial begin
        if (HSP_CLKS + HBP_CLKS + 1 + PREF_D + LINE_WORDS + HFP_CLKS != LINE_CLKS) begin
            $display("FATAL: h segments must sum to LINE_CLKS");
            $finish;
        end
        if (VSP_L + VBP_L + VACT_L + VFP_L + PAD_L != FRAME_SLOTS) begin
            $display("FATAL: v segments must sum to FRAME_SLOTS");
            $finish;
        end
    end
    // synthesis translate_on

    // ---- 自由跑行节拍（v4.4：与门控冻结解耦，恒 LINE_CLKS 周期）----
    // reader 槽节拍同源；冻结只拉长显示自身行，不拖慢本计数器。
    reg [10:0] ftick_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ftick_cnt <= 11'd0;
        else if (ftick_cnt == LINE_CLKS[10:0] - 11'd1)
            ftick_cnt <= 11'd0;
        else
            ftick_cnt <= ftick_cnt + 11'd1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            line_tick_o <= 1'b0;
        else
            line_tick_o <= (ftick_cnt == LINE_CLKS[10:0] - 11'd1);
    end

    // ---- 行内 FSM ----
    localparam [2:0] Hs = 3'd0,         // 行同步
                     Hb = 3'd1,         // 后沿
                     Hg = 3'd2,         // 门点（可冻结）
                     Hp = 3'd3,         // 预取（PREF_D）
                     Ha = 3'd4,         // 有效（LINE_WORDS 拍）
                     Hf = 3'd5;         // 前沿
    reg [2:0]  h_st;
    reg [10:0] h_cnt;
    reg        late_done;                // 本行已计 late（每冻结行一次）
    reg        line_data;                // 本行实发数据
    reg [15:0] late_cnt, under_cnt;

    // ---- 帧内段 ----
    localparam [2:0] Vs = 3'd0, Vb = 3'd1, Va = 3'd2, Vf = 3'd3, Vp = 3'd4;
    reg [2:0]  v_seg;
    reg [11:0] v_cnt;                    // 段内行计数（< 2160）
    reg        frame_open_q;
    wire       v_in_data = (v_seg == Va);

    // 拉取发射：PREF 2 拍 + HACT 前 LINE_WORDS-2 拍 = LINE_WORDS 拍，
    // 经 tx_line_buf 2 拍读延迟，buf_valid#i 恰落在 HACT 第 i 拍。
    wire hact_pull = line_data && ((h_st == Hp) ||
                     (h_st == Ha && h_cnt < LINE_WORDS[10:0] - 11'd2));
    assign buf_rd_en = hact_pull && v_in_data;

    wire line_end = (h_st == Hf) && (h_cnt == HFP_CLKS[10:0] - 11'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_st <= Hs;  h_cnt <= 11'd0;
            v_seg <= Vs; v_cnt <= 12'd0;
            late_done <= 1'b0; line_data <= 1'b0;
            late_cnt <= 16'd0;
            line_num <= 16'd0; frame_num <= 16'd0;
            frame_open_q <= 1'b0;
        end else begin
            // ---- 行推进（规格 GATE 冻结语义：不足则 h 冻结等水位，
            //      行周期拉长、late_cnt++；行内拉取一旦开行永不断流 R4；
            //      空白行过门点直通（无拉取），行周期恒 LINE_CLKS）----
            case (h_st)
            Hs: if (h_cnt == HSP_CLKS[10:0] - 11'd1) begin h_st <= Hb; h_cnt <= 11'd0; end
                else h_cnt <= h_cnt + 11'd1;
            Hb: if (h_cnt == HBP_CLKS[10:0] - 11'd1) begin
                    h_st  <= Hg;                    // 空白/数据行统一过门点
                    h_cnt <= 11'd0;
                    late_done <= 1'b0;
                    line_data <= 1'b0;
                end else h_cnt <= h_cnt + 11'd1;
            Hg: if (!v_in_data || buf_level >= LINE_BUF_WORDS[15:0]) begin
                    h_st <= Hp; h_cnt <= 11'd0;
                    line_data <= v_in_data;         // 空白行过门不置数据标
                end else begin
                    // 冻结：h_cnt/行周期保持，等水位（reader 供给独立于
                    // 本冻结——tick 自由跑，无耦合极限环）
                    if (!late_done) begin
                        late_cnt <= late_cnt + 16'd1;   // 每冻结行一次
                        late_done <= 1'b1;
                    end
                end
            Hp: if (h_cnt == PREF_D[10:0] - 11'd1) begin h_st <= Ha; h_cnt <= 11'd0; end
                else h_cnt <= h_cnt + 11'd1;
            Ha: if (h_cnt == LINE_WORDS[10:0] - 11'd1) begin h_st <= Hf; h_cnt <= 11'd0; end
                else h_cnt <= h_cnt + 11'd1;
            Hf: if (h_cnt == HFP_CLKS[10:0] - 11'd1) begin h_st <= Hs; h_cnt <= 11'd0; end
                else h_cnt <= h_cnt + 11'd1;
            default: h_st <= Hs;
            endcase

            // ---- 行末：帧段推进（Va 段行均为实发行——冻结已保证开行即
            //      有整行数据；空白行计段不发行号）----
            if (line_end) begin
                case (v_seg)
                Vs: if (v_cnt == VSP_L[11:0] - 12'd1) begin v_seg <= Vb; v_cnt <= 12'd0; end
                    else v_cnt <= v_cnt + 12'd1;
                Vb: if (v_cnt == VBP_L[11:0] - 12'd1) begin
                        v_seg <= Va; v_cnt <= 12'd0;
                        line_num <= 16'd0;
                    end else v_cnt <= v_cnt + 12'd1;
                Va: if (line_data) begin
                        if (v_cnt == VACT_L[11:0] - 12'd1) begin
                            v_seg <= Vf; v_cnt <= 12'd0;
                        end else begin
                            v_cnt <= v_cnt + 12'd1;
                            line_num <= line_num + 16'd1;
                        end
                    end
                Vf: if (v_cnt == VFP_L[11:0] - 12'd1) begin
                        // PAD=0 直跳 Vs（状态机按 line_end 步进，经 Vp 中转
                        // 最少耗 1 行——2026-10-21 V7 仿真抓出 98 槽残差）
                        v_seg <= (PAD_L == 0) ? Vs : Vp;
                        v_cnt <= 12'd0;
                    end
                    else v_cnt <= v_cnt + 12'd1;
                // 仅 PAD>=1 可达（PAD=0 由 Vf 直跳 Vs）
                Vp: if (v_cnt == PAD_L[11:0] - 12'd1) begin
                        v_seg <= Vs; v_cnt <= 12'd0;
                        frame_num <= frame_num + 16'd1;
                    end else v_cnt <= v_cnt + 12'd1;
                default: v_seg <= Vs;
                endcase
            end
            // frame_open：VBP 末行槽节拍后 1 拍脉冲（帧开窗预告）
            frame_open_q <= line_end && (v_seg == Vb) &&
                            (v_cnt == VBP_L[11:0] - 12'd1);
        end
    end

    // ---- 行内欠载观测：实发数据行 HACT 拍缺拍（预算失效信号，正常恒 0；
    //      冻结等待期不计）----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) under_cnt <= 16'd0;
        else if ((h_st == Ha) && v_in_data && line_data && !buf_valid)
            under_cnt <= under_cnt + 16'd1;
    end

    // ---- TX D8 输出（数据直连 tx_line_buf 输出寄存；hsync/vsync 寄存
    //      输出，与 shape hs_r/vs_r 同款）----
    reg hsync_r, vsync_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hsync_r <= 1'b1; vsync_r <= 1'b1;
        end else begin
            hsync_r <= (h_st != Hs);      // 低有效
            vsync_r <= (v_seg != Vs);     // 低有效
        end
    end
    assign hsync            = hsync_r;
    assign vsync            = vsync_r;
    assign datatype         = DATA_TYPE;
    assign pixel_data       = buf_rdata;
    assign pixel_data_valid = buf_valid && (h_st == Ha) && line_data;
    assign haddr            = HACT_PX[15:0];
    assign frame_open       = frame_open_q;
    assign dbg_dtg_cnt_o    = {late_cnt, under_cnt};

endmodule
