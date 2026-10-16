//============================================================================
// pattern_gen.v - Bayer RAW10 图案拍流发生器（raw_2_axi4st 之前的注入源）
//
// 与 my_csi2_rx 的传感器输出同协议（5 线：data/valid/dtype/hs/vs），由
// top_cam_demo 的 2:1 mux（apb_cam_ctrl CTRL bit3 pat_en）选入 camera_path。
// PRE-window 注入：必须发完整传感器行几何，raw 的 DT 门控/lead-trail 窗口/
// SKIP_FIRST 哑行逻辑原样生效。
//
// 帧结构（拍流，行推进按面板行节拍 line_tick 定界）：
//   [vs 1 拍]（帧尾 pad 的最后一个行节拍发出，先于首行 hs）
//   每行 = [数据 LINE_BEATS 拍]（行启动由 line_tick 触发，行尾等下一节拍）
//   每帧 = DUMMY_LINES 条哑行（黑，供 raw 的 LINE_SKIP_FIRST 丢弃）
//        + LIVE_LINES 条图案行
//        + 帧尾 FRAME_PAD 个行节拍空闲
//
// 帧率配准（pclk 行节拍，2026-09 根治图案慢滚动）：
//   行推进不再数 aclk，而是等 line_tick——top 层用 pixel_clk 计 550 拍/行
//   （(HSP+HBP+HACT+HFP)/PPC），2FF CDC + 边沿检测成 aclk 单拍脉冲。图案
//   每帧 = 1091 行 + 34 pad 节拍 = 1125 节拍 = 618,750 pclk，与面板帧长
//   同钟同频 => shape FIFO 供需零漂移 => 消隐段排水永不触发。旧 aclk 计
//   拍方案（2963 拍/行名义配准）与 pclk 有 37ppm 级独立钟差，60fps 下内
//   容相位以 ~2.5 行/s 漂移，板级表现为图案整体每 0.3~0.5s 滚一行。
//   行数据 486 拍 = 2.43us << 节拍周期 14.8us，节拍只会落在行尾等待态。
//
// 图案（pat_sel，4 像素/拍、10bit、Bayer 域）：
//   0 = 灰度竖 ramp（默认）：像素级 px[10:1]，全宽 0->95% 白渐变
//   1 = 红/蓝竖条：单通道满幅双色组（红 R=0x3C0/G=B=0，蓝 B=0x3C0/
//       R=G=0），128px 条宽。选纯色双条的原因：wb_axis 增益编码
//       0x40=x1.0 而 CSR 复位默认 wb=200/235/180 是 sensor 暗画面校准
//       大增益（x3.1/x3.7/x2.8），旧暖/冷双色组 {768,384,192}/{192,384,
//       768} 被抬升后 R/G 双通道饱和钳 255 => 板级显示黄/青（2026-09
//       确认）。纯红/纯蓝单通道满幅对其免疫：饱和钳 255 仍是纯色，
//       零值站乘任何增益仍为 0；
//       条相位按"显示区像素列"（raw 列 - LEAD 6）计 —— 15 根条恰好铺满
//       显示区，末条收于显示右缘 col1919，右缘不再露出下一根条（旧版按
//       raw 拍号 beat_idx[5] 计，条界在 raw col1920 = 显示 col1914，右缘
//       漏出 6px 下一条 + 1 列过渡混色，板级表现为右缘细蓝条）；
//       站位 = 标准 RGGB（live 行偶+列偶=R、行奇+列奇=B）——demosaic
//       的 rp 是窗中心内容行号奇偶 = 本像素自身行号奇偶，与标准表直
//       接对齐，bayer_phase=0 即出正确颜色。旧版"对齐 rp=~line[0]"
//       的推导有误（把 rp 当成了 down 行奇偶取反），勿照抄
//   2 = 灰度横 ramp：按图案行号（尾 56 行回卷，视觉无碍）
//   3 = 8x8 像素棋盘（0/满幅）
//   灰度/横条/棋盘为 4 像素同值 -> demosaic 后无伪彩（flat 场走 adaptive
//   tie 路径，与 bilinear 逐位一致）；哑行全黑。
//
// 切换语义：mux 行中切换最多撕裂 1 行（raw 限定行首拍组合清零 col_cnt、
//   win0 每 DT 拍刷新，下一 vs 后完全干净）；固件在帧边界切换即可。
//============================================================================

module pattern_gen #(
    parameter logic [19:0] DUMMY_LINES = 20'd11,    // 帧头哑行（= raw LINE_SKIP_FIRST）
    parameter logic [19:0] LIVE_LINES  = 20'd1080,  // 图案行（= raw LINES）
    parameter logic [19:0] LINE_BEATS  = 20'd486,   // 每行数据拍（= LINE_TOTAL_PIX/4）
    parameter logic [19:0] FRAME_PAD   = 20'd34,    // 帧尾 pad 节拍数（1125 行 - 1091 图案行）
    parameter logic [5:0]  DT_RAW10    = 6'h2B      // 发出的像素 DT
) (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        line_tick,   // 行节拍（pixel_clk 550 拍/行 CDC 单拍脉冲）
    input  wire [1:0]  pat_sel,     // 图案选择（CSR CTRL[5:4]）
    output reg  [39:0] pat_data,    // 4xRAW10 打包
    output reg         pat_valid,
    output reg  [5:0]  pat_dtype,
    output reg         pat_hs,      // 行首脉冲（1 拍）
    output reg         pat_vs       // 帧首脉冲（1 拍，先于首行 hs）
);

    localparam logic [19:0] N_LINES = DUMMY_LINES + LIVE_LINES;

    //--------------------------------------------------------------------
    // 拍计数：line_cnt（帧内行）/ beat_cnt（行内拍，0..LINE_BEATS-1=数据，
    // LINE_BEATS=行尾等节拍态）/ pad_cnt（帧尾 pad 节拍数）
    //--------------------------------------------------------------------
    reg  [19:0] line_cnt;
    reg  [19:0] beat_cnt;
    reg  [19:0] pad_cnt;
    reg         in_pad;             // 帧尾 pad 段

    wire frame_last = (line_cnt == N_LINES - 20'd1);
    wire tick_now   = line_tick;                                  // 行/帧唯一推进源
    wire line_tail  = !in_pad && (beat_cnt == LINE_BEATS);        // 行尾等节拍
    wire pad_last   = in_pad && (pad_cnt == FRAME_PAD - 20'd1);   // pad 末节拍

    //--------------------------------------------------------------------
    // 图案数据（组合，寄存到 pat_data 时与 valid 同拍对齐）
    //--------------------------------------------------------------------
    wire        in_data_beat = !in_pad && (beat_cnt < LINE_BEATS);  // 行内数据拍
    wire [19:0] beat_idx = beat_cnt;                // 行内数据拍 0-based
    wire        ln_dummy = (line_cnt < DUMMY_LINES);
    wire [19:0] live_ln  = line_cnt - DUMMY_LINES;  // 图案行号 0-based

    // 竖条相位基准：显示区 col0 = raw col6（raw 窗 LEAD_PIX）。条界落在
    // 显示区 128 的整数倍处，raw col<6（丢弃区）下溢回绕取值无影响。
    localparam logic [19:0] BAR_X0 = 20'd6;

    // 双色值组（10bit）：纯红 / 纯蓝，单通道满幅、其余站 0（wb 免疫，
    // 见头注释 pat_sel=1 段）
    localparam logic [9:0] RA = 10'h3C0, GA = 10'h000, BA = 10'h000; // 红
    localparam logic [9:0] RB = 10'h000, GB = 10'h000, BB = 10'h3C0; // 蓝

    // 标准 RGGB 站位：(live 行偶, 列偶) = R、(行奇, 列奇) = B，其余 G。
    // demosaic rp = 窗中心内容行号奇偶 = 像素自身行号奇偶，bayer_phase=0
    // （RGGB）直接配本布局 —— 相机（RGGB）与 pattern 同相位即正确。
    function automatic [9:0] site_val;
        input       ln0;    // 图案行号 bit0
        input       px0;    // 组内像素 bit0
        input       bsel;   // 条选择（0=暖 1=冷）
        begin
            casez ({ln0, px0})
                2'b00:   site_val = bsel ? RB : RA;   // R 站（行偶+列偶）
                2'b11:   site_val = bsel ? BB : BA;   // B 站（行奇+列奇）
                default: site_val = bsel ? GB : GA;   // G 站
            endcase
        end
    endfunction

    reg  [39:0] word_r;
    reg  [19:0] px_col;
    reg  [9:0]  v_s;
    reg  [2:0]  p_i;                // 组内像素下标（integer 位选 iverilog 不支持）
    always @* begin
        word_r = 40'd0;                             // 哑行/消隐拍 = 黑
        if (in_data_beat && !ln_dummy) begin
            for (p_i = 0; p_i < 4; p_i = p_i + 1) begin
                px_col = beat_idx * 20'd4 + p_i;    // 全行像素列
                case (pat_sel)
                    2'd0: v_s = px_col[10:1];           // 灰度竖 ramp
                    // 站位用 live_ln（raw 丢弃哑行后 demosaic 从 sof 计行，
                    // 行奇偶 = live 行奇偶；line_cnt 含哑行，板级 11 哑行反相）
                    2'd1: v_s = site_val(live_ln[0], p_i[0],
                                         ((px_col - BAR_X0) >> 7) & 20'd1);
                                        // 橙/蓝竖条(128px，显示区对齐)
                    2'd2: v_s = live_ln[9:0];           // 灰度横 ramp
                    default: v_s = (((px_col[6:3] + live_ln[7:3]) & 4'h1)
                                    != 4'h0) ? 10'h3FF : 10'h000; // 8x8 棋盘
                endcase
                word_r[10*p_i +: 10] = v_s;
            end
        end
    end

    //--------------------------------------------------------------------
    // 时序壳：行推进只认 line_tick（与面板行节奏同源），行内数据按 aclk
    // 全速跑完后停在行尾等待态
    //--------------------------------------------------------------------
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            line_cnt  <= 20'd0;
            beat_cnt  <= 20'd0;
            pad_cnt   <= 20'd0;
            in_pad    <= 1'b1;              // 复位进 pad，等节拍
            pat_data  <= 40'd0;
            pat_valid <= 1'b0;
            pat_dtype <= 6'd0;
            pat_hs    <= 1'b0;
            pat_vs    <= 1'b0;
        end else begin
            // ---- 节拍推进：pad 计节拍 -> 帧首；行尾等节拍 -> 新行 ----
            if (tick_now) begin
                if (in_pad) begin
                    if (pad_last) begin     // pad 完：vs + 首行预滚（等节拍态）
                        in_pad   <= 1'b0;
                        pad_cnt  <= 20'd0;
                        line_cnt <= 20'd0;
                        beat_cnt <= LINE_BEATS;
                    end else begin
                        pad_cnt <= pad_cnt + 20'd1;
                    end
                end else if (line_tail) begin
                    beat_cnt <= 20'd0;      // 启动新行（hs 打在 beat 0）
                end
                // 行数据中段到达的节拍丢弃（数据 2.43us << 节拍 14.8us，到不了）
            end else if (!in_pad && (beat_cnt != LINE_BEATS)) begin
                beat_cnt <= beat_cnt + 20'd1;
                if (beat_cnt == LINE_BEATS - 20'd1) begin   // 行数据末拍收尾
                    if (frame_last) begin
                        in_pad   <= 1'b1;   // 进帧尾 pad（按节拍计）
                        pad_cnt  <= 20'd0;
                        line_cnt <= 20'd0;
                    end else begin
                        line_cnt <= line_cnt + 20'd1;
                    end
                end
            end

            // ---- 输出打拍（hs/vs/valid/data 对齐同一拍）----
            pat_valid <= in_data_beat;
            pat_hs    <= !in_pad && (beat_cnt == 20'd0);
            pat_vs    <= in_pad && tick_now && pad_last;    // 1 拍脉冲，先于首行 hs
            pat_dtype <= DT_RAW10;
            pat_data  <= word_r;
        end
    end

endmodule
