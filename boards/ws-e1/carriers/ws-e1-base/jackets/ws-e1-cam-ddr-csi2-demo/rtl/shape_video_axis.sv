// ============================================================================
// shape_video_axis.sv
// CSI-2 TX 视频成形模块（AXIS-64 入 / 整帧门控 / 帧首水位门）
//
// 直接对接 my_csi2_tx Video Interface；写侧改为标准 AXIS-64。无 s_axis_tready：
// 上游 AXIS 链（rgb2yuv_axis）不可反压，过量输入由整帧门控与 lost_cnt
// 兜底（正常不发生）。
//
// 设计契约（GSV6172 桥接适配的最终形态）：
//  1. 行内连续：CSI-2 TX IP 要求数据行内必须连续。行起点由 haveLine
//     （FIFO 存量 >= 一行）门控放行，行内（Hact）绝不暂停——读侧是
//     FIFO 唯一消费者，结构上行内不可能读空。
//  2. 整帧门控：写侧只在 SOF 拍做"整帧收下/整帧丢弃"判定，帧中段拍
//     不受水位影响——保证 FIFO 非空时队头恒为帧首 sof。
//  3. 帧首纪律：读侧复位直接进 Vsync 自由跑（与已验证出图设计
//     shape_video_data 同构）；队头恒为 sof 由契约 2 的写侧门控保证
//     （drop_frame 复位=1、首字必为帧首，满截断只伤帧尾不碰队头），
//     读侧无需锚定/排空——冷启动第一个 Vact 行天然从帧首字起读。
//  4. 帧首水位门：板级行率失配（sensor 行周期 > 面板行周期）使帧内
//     水位锯齿可达万余拍，任何"行内等待"都会造成输出行率抖动 =>
//     GSV6172 失锁。等待全部挪到帧间消隐段：Vfront 出口等水位回补到
//     帧首门（VFRONT_WAIT_LINES 行）才开新帧，停留期间 h 状态机自由
//     跑（多发整行消隐），行率零影响；帧长被水位环锁定到源帧率。
//  5. CDC：无多 bit 跨域配置（水位经格雷码 2FF 同步后本地使用）。
//  6. 行首锚定（水平滚动修复，2026-09 板级定位）：供给（sensor aclk 域）
//     与读侧 pclk 异源，行率 ppm 级失配；若 Hact 起点纯本地自由节拍，
//     任何丢拍（满拦截）/冷启动错位都会使读窗口相对 FIFO 字流行边界
//     偏移且无恢复机制 => 画面水平滚动/平移。FIFO 流每行恰 480 字连续、
//     行首字带 sol（写侧整帧门控保证队头恒为帧首 sof&sol）=> 锚定规则：
//     仅在 Hback 段要求队头是 sol 才放行 Hact（gate_here/gate_line）；
//     正常态读完 480 字队头自动落回下一 sol，锚点自持、零开销、行率零
//     抖动；队头错位时搜索状态机每 3 拍推进 1 字丢弃残字直到 sol，瞬态
//     冷启动收敛期（满拦截 lost 排水）~8 帧，之后 srch 恒 0。
//  7. 消隐段行粒度排水（帧间调节的高侧手段，2026-09）：供需每帧字数精确
//     平衡但消隐窗错位相位自由慢漂，帧内锯齿最坏 79 行 > FIFO 容量，固定
//     水位带必撞满/读空。v 非 Vact 段且水位超排水帽（DRAIN_CAP_LINES 行）
//     时逐消隐行整行丢弃读（sol 锁存、不输出、行率零影响），稳态水位钉在
//     [Cap-33, Cap+1] 行：谷 > 帧首门（帧长锁定）、峰 << FULL（零 lost）、
//     PPM 级帧率差由排水行数逐帧微调吸收——正常流零丢帧。
// ============================================================================

module shape_video_axis #(
    parameter int HACT = 1920,
    parameter int VACT = 1080,
    parameter int HSP  = 44,
    parameter int HBP  = 148,
    parameter int HFP  = 88,
    parameter int VSP  = 5,
    parameter int VBP  = 36,
    parameter int VFP  = 4,
    parameter int PPC  = 4,                 // 每时钟像素数（必须与数据格式匹配）
    parameter logic [5:0] DATA_TYPE = 6'h1E,// YUV422 8-bit
    parameter int FIFO_DEPTH = 32768,       // 深度（2 的幂）
    parameter int HIGH_LINES = 60,          // 水位高阈值（行）：整帧丢弃兜底门（须 > 排水帽+4）
    parameter int LOW_LINES  = 12,          // 水位低阈值（行）
    parameter int TRIM_LINES = 4,           // 已废弃：VFP trim 由帧首水位门取代（保留透传兼容）
    parameter int VFRONT_WAIT_LINES = 36,   // 帧首水位门（行）：Vfront 出口等水位回补
    parameter int DRAIN_CAP_LINES   = 54    // 消隐段排水帽（行）：水位超帽逐行丢弃读
)(
    // ---- 写侧 AXIS-64（相机/流水线时钟域）----
    input  wire        s_axis_aclk,
    input  wire        s_axis_aresetn,
    input  wire [63:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,    // EOL（行尾）：接口完备保留，成形逻辑不依赖
    input  wire [2:0]  s_axis_tuser,    // {eof, sol, sof}：sol=行首字，sof=帧首字

    // ---- 读侧（pixel_clk 域，CSI-2 TX Video Interface）----
    input  wire        pixel_clk,
    input  wire        pixel_rst_n,
    output wire        hsync_vc0,
    output wire        vsync_vc0,
    output wire [5:0]  datatype,
    output wire [63:0] pixel_data,
    output wire        pixel_data_valid,
    output wire [15:0] haddr,
    output wire [15:0] line_num,
    output wire [15:0] frame_num

);

    //================================================================
    // 1. 参数检查（$display+$finish，不用 $fatal 以兼容 iverilog）
    //================================================================
    initial begin
        if (HACT % PPC != 0) begin $display("FATAL: HACT must be multiple of PPC");  $finish; end
        if (HSP  % PPC != 0) begin $display("FATAL: HSP must be multiple of PPC");   $finish; end
        if (HBP  % PPC != 0) begin $display("FATAL: HBP must be multiple of PPC");   $finish; end
        if (HFP  % PPC != 0) begin $display("FATAL: HFP must be multiple of PPC");   $finish; end
        if (FIFO_DEPTH & (FIFO_DEPTH - 1)) begin
            $display("FATAL: FIFO_DEPTH must be power of 2"); $finish;
        end
        if (HIGH_LINES <= LOW_LINES) begin
            $display("FATAL: HIGH_LINES must be > LOW_LINES"); $finish;
        end
        if (VFRONT_WAIT_LINES >= HIGH_LINES) begin
            $display("FATAL: VFRONT_WAIT_LINES must be < HIGH_LINES (keep gate point below drop threshold)"); $finish;
        end
        if (DRAIN_CAP_LINES <= VFRONT_WAIT_LINES) begin
            $display("FATAL: DRAIN_CAP_LINES must be > VFRONT_WAIT_LINES"); $finish;
        end
        if (HIGH_LINES <= DRAIN_CAP_LINES + 4) begin
            $display("FATAL: HIGH_LINES must be > DRAIN_CAP_LINES+4 (keep drop gate clear of drain band)"); $finish;
        end
        if (FIFO_DEPTH <= (HIGH_LINES + 4) * (HACT / PPC)) begin
            $display("FATAL: FIFO_DEPTH too small for HIGH_LINES watermark"); $finish;
        end
    end

    //================================================================
    // 2. 本地参数
    //================================================================
    localparam int FifoAddrWidth = $clog2(FIFO_DEPTH);
    localparam int FifoPtrWidth  = FifoAddrWidth + 1;  // 额外一位区分空/满
    localparam int FifoWidth     = 66;                 // {sof, sol, pixel[63:0]}

    localparam int LineWords = HACT / PPC;
    localparam int HighBeats = HIGH_LINES * LineWords;
    localparam int LowBeats  = LOW_LINES  * LineWords;
    localparam int VfrontWaitBeats = VFRONT_WAIT_LINES * LineWords;
    localparam int DrainCapBeats   = DRAIN_CAP_LINES   * LineWords;

    //================================================================
    // 3. 异步 FIFO（格雷码指针）—— 存储与公共函数
    //================================================================
    // BRAM 推断纪律（Efinity编码风格.md §7.1 + EFX-0657 教训）：
    //   1) (* ram_style = "block" *) 显式标注
    //   2) 读端口同步：读数据寄存器无条件、每拍、单一寄存器地址
    //   3) 读数据寄存器不许有复位值
    //================================================================
    (* ram_style = "block" *)
    reg [FifoWidth-1:0] mem [FIFO_DEPTH];

    function automatic [FifoPtrWidth-1:0] bin2gray;
        input [FifoPtrWidth-1:0] bin;
        begin
            bin2gray = bin ^ (bin >> 1);
        end
    endfunction

    function automatic [FifoPtrWidth-1:0] gray2bin;
        input [FifoPtrWidth-1:0] gray;
        reg [FifoPtrWidth-1:0] b;
        integer i;
        begin
            b = gray;
            for (i = FifoPtrWidth-2; i >= 0; i = i - 1)
                b[i] = b[i+1] ^ gray[i];
            gray2bin = b;
        end
    endfunction

    reg [FifoPtrWidth-1:0]  wr_ptr_bin;
    reg [FifoPtrWidth-1:0]  wr_ptr_gray;
    reg [FifoPtrWidth-1:0]  rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    reg [FifoPtrWidth-1:0]  rd_ptr_bin;
    reg [FifoPtrWidth-1:0]  rd_ptr_gray;
    reg [FifoPtrWidth-1:0]  wr_ptr_gray_sync1, wr_ptr_gray_sync2;

    wire full;

    // 满标志：写格雷码 == 读格雷码取反（高两位相反）
    assign full = (wr_ptr_gray == {~rd_ptr_gray_sync2[FifoPtrWidth-1:FifoPtrWidth-2],
                                   rd_ptr_gray_sync2[FifoPtrWidth-3:0]});

    //================================================================
    // 4. 写侧（s_axis_aclk 域）：AXIS 入 + 整帧门控
    //================================================================
    // drop_frame 复位 = 1（等 SOF 开帧）：复位后数据被拦，直到第一个
    // sof 拍且水位不高才放行——冷启动零丢帧、队头恒为帧首。
    //   - sof 拍：水位 > HIGH => 整帧丢弃（drop_cnt++），否则整帧收下
    //   - 帧中段拍：仅在丢帧模式下拦停；full 阻塞为异常兜底（lost_cnt）
    //================================================================
    wire [FifoPtrWidth-1:0] rd_ptr_bin_wsync = gray2bin(rd_ptr_gray_sync2);
    wire [FifoPtrWidth-1:0] used_words_w     = wr_ptr_bin - rd_ptr_bin_wsync;

    reg        drop_frame;
    reg [15:0] drop_cnt;
    reg [15:0] lost_cnt;

    wire sof_beat       = s_axis_tvalid && s_axis_tuser[0];
    wire frame_overflow = (used_words_w > HighBeats);
    wire wr_en          = s_axis_tvalid && !full
                          && (!drop_frame || sof_beat)
                          && !(sof_beat && frame_overflow);

    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn) begin
            wr_ptr_bin        <= 0;
            wr_ptr_gray       <= 0;
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
            drop_frame        <= 1'b1;      // 等 SOF 开帧
            drop_cnt          <= 16'd0;
            lost_cnt          <= 16'd0;
        end else begin
            // 同步读指针格雷码（两级同步）
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;

            if (wr_en) begin
                mem[wr_ptr_bin[FifoAddrWidth-1:0]]
                    <= {s_axis_tuser[0], s_axis_tuser[1], s_axis_tdata};
                wr_ptr_bin  <= wr_ptr_bin + 1'b1;
                wr_ptr_gray <= bin2gray(wr_ptr_bin + 1'b1);
            end

            // 整帧收/弃判定：仅 SOF 拍更新 drop_frame
            if (sof_beat) begin
                if (frame_overflow) begin
                    drop_frame <= 1'b1;
                    drop_cnt   <= drop_cnt + 16'd1;   // 每个被弃 SOF = 丢一帧
                end else begin
                    drop_frame <= 1'b0;
                end
            end

            // 满阻塞丢拍（写域兜底观测；正常恒 0）
            if (s_axis_tvalid && !drop_frame && full)
                lost_cnt <= lost_cnt + 16'd1;
        end
    end

    //================================================================
    // 5. 读侧（pixel_clk 域）：水位 / 行门控 / 帧首水位门
    //================================================================
    // used_words_rd 用 2 级同步后的写指针计算，滞后实际 2~3 拍且只少
    // 不多（写端只增不减）=> 判"够一行"时实际存量只会更多 => 行内不
    // 可能读空（配合 Hact 内绝不暂停）。
    //================================================================
    wire [FifoPtrWidth-1:0] wr_ptr_bin_rd = gray2bin(wr_ptr_gray_sync2);
    wire [FifoPtrWidth-1:0] used_words_rd = wr_ptr_bin_rd - rd_ptr_bin;
    wire have_line = (used_words_rd >= LineWords);

    //---- 水平状态机（同旧模块）----
    localparam logic [2:0] Hsync  = 3'd0,
                           Hback  = 3'd1,
                           Hact   = 3'd2,
                           Hfront = 3'd3;
    reg [2:0]  h_state;
    reg [15:0] h_cnt;

    //---- 垂直状态机：复位进 Vsync（与已验证出图设计 shape_video_data 同构；
    //      帧首纪律由写侧整帧门控保证——队头恒为 sof，读侧自由跑无需锚定）----
    localparam logic [2:0] Vsync   = 3'd0,
                           Vback   = 3'd1,
                           Vact    = 3'd2,
                           Vfront  = 3'd3;
    reg [2:0]  v_state;
    reg [15:0] v_cnt;
    reg [15:0] line_num_reg;
    reg [15:0] frame_num_reg;

    reg [FifoWidth-1:0] mem_r;   // 唯一 mem 读数据寄存器（EFX-0657 纪律）

    //---- 行首锚定（契约 6）----
    // gate_line：仅在 Hback 段（行首侧消隐）要求队头是行首字（sol）。
    // 检查点选 Hback 的原因：此时 rd_ptr 已自 Hact 结束静止 33+ 拍，
    // mem_r 稳定显示队头、判定无滞后；若把检查放在 Hfront，Hact 尾拍
    // 刚推进 rd_ptr、mem_r 滞后显示最后一字（非 sol），每行都会误触发
    // 搜索（3 拍/行 => 行率拖慢 ~0.55% => FIFO 涨满 => lost 恶性循环，
    // 2026-09 仿真定位）。
    wire gate_here = (v_state == Vact) && (h_state == Hback);
    wire gate_line = have_line && mem_r[64];

    // 搜索重对齐：队头非 sol（丢拍/冷启动残留）时逐字丢弃直到 sol。
    // 3 拍节奏 ADV->WAIT->JUDGE：rd_ptr 在 ADV 拍末推进，mem_r 在 JUDGE 拍
    // 才显示新队头（mem_r(T+1)=mem[rd_ptr(T)]，滞后 1 拍）；JUDGE 见 sol
    // 即回 IDLE，此时 gate_line 已满足，下一拍解冻，Hact 首拍恰读 sol 字。
    // 正常态队头恒为 sol，rsync_start 恒 0，状态机停在 IDLE 零开销。
    localparam logic [1:0] RsIdle = 2'd0, RsAdv = 2'd1, RsWait = 2'd2, RsJudge = 2'd3;
    reg  [1:0] rsync_st;
    wire rsync_start = gate_here && have_line && !mem_r[64]
                       && (rsync_st == RsIdle);
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) rsync_st <= RsIdle;
        else case (rsync_st)
            RsIdle:  if (rsync_start)      rsync_st <= RsAdv;
            RsAdv:                              rsync_st <= RsWait;
            RsWait:                             rsync_st <= RsJudge;
            RsJudge: rsync_st <= (mem_r[64] || !have_line) ? RsIdle : RsAdv;
            default:                       rsync_st <= RsIdle;
        endcase
    end

    //---- 消隐段行粒度排水（帧间调节的高侧手段，契约 7）----
    // 供需行率同格（PPM 级）后每帧写=读=518,400 字精确平衡，但显示 Vblank
    //（45 行，供给可续写 +21,600 字）与供给帧尾 pad（34 行，显示独读
    // -16,320 字）的相位自由慢漂，帧内锯齿最坏 79 行 > FIFO 容量 68.27 行，
    // 固定水位带必撞满（lost 泄压极限环，2026-09 仿真定位）或读空。
    // 排水：v 非 Vact 段且水位 > 排水帽时，每消隐行在 Hback 末拍锁存
    //（要求队头是 sol 且足一行），Hact 480 拍整行丢弃读——不输出
    //（valid_r 只随 raw_active）、不碰 Vact 锚定、行率零影响。稳态水位
    // 钉在 [Cap-33, Cap+1] 行带：Vact 谷最坏 Cap-33 = 21 行 > 帧首门 20
    //（不读空、Vfront 零等待、帧长锁定）；峰最坏 Cap+1 = 55 行（26,400）
    // << FULL 68.27 行（零 lost => 无流内缺口 => rsync 恒 IDLE 零 srch）；
    // 供给 SOF 时刻 <= 26,400 < HIGH 门 28,800（整帧丢弃门退化为纯兜底）。
    wire drain_armed = (v_state != Vact) && (used_words_rd > DrainCapBeats);
    reg  drain_line;    // 本消隐行已锁存整行丢弃读
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n)
            drain_line <= 1'b0;
        else if (h_state == Hsync)
            drain_line <= 1'b0;                      // 行界清锁存
        else if ((h_state == Hback) && (h_cnt == HBP/PPC - 1))
            drain_line <= drain_armed && mem_r[64] && have_line;
    end

    // can_run：锚定检查只卡 Hback 段（Hfront/Hsync 自由跑，零行率开销）
    wire can_run = (v_state != Vact) || (h_state == Hact) || !gate_here || gate_line;
    wire raw_active = (v_state == Vact) && (h_state == Hact);
    wire line_end = (h_state == Hfront) && (h_cnt == HFP/PPC - 1);

    //================================================================
    // 6. H/V 状态机
    //================================================================
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            h_state <= Hsync;
            h_cnt   <= 16'd0;
        end else if (can_run) begin
            case (h_state)
                Hsync:  if (h_cnt == HSP/PPC - 1) begin h_state <= Hback;  h_cnt <= 16'd0; end
                        else h_cnt <= h_cnt + 16'd1;
                Hback:  if (h_cnt == HBP/PPC - 1) begin h_state <= Hact;   h_cnt <= 16'd0; end
                        else h_cnt <= h_cnt + 16'd1;
                Hact:   if (h_cnt == HACT/PPC - 1) begin h_state <= Hfront; h_cnt <= 16'd0; end
                        else h_cnt <= h_cnt + 16'd1;
                Hfront: if (h_cnt == HFP/PPC - 1) begin h_state <= Hsync;  h_cnt <= 16'd0; end
                        else h_cnt <= h_cnt + 16'd1;
                default: h_state <= Hsync;
            endcase
        end
    end

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            v_state       <= Vsync;     // 复位直接进帧同步段（同出图设计）
            v_cnt         <= 16'd0;
            line_num_reg  <= 16'd0;
            frame_num_reg <= 16'd0;
        end else if (can_run) begin
            if (line_end) begin
                case (v_state)
                    Vsync:  if (v_cnt == VSP - 1) begin v_state <= Vback; v_cnt <= 16'd0; end
                            else v_cnt <= v_cnt + 16'd1;
                    Vback:  if (v_cnt == VBP - 1) begin
                                v_state      <= Vact;
                                v_cnt        <= 16'd0;
                                line_num_reg <= 16'd0;
                            end else v_cnt <= v_cnt + 16'd1;
                    // Vact 末行装载 Vfront：装载 L-1 使递减出口恰在 L 行
                    Vact:   if (v_cnt == VACT - 1) begin
                                v_state <= Vfront;
                                v_cnt   <= (VFP == 0) ? 16'd0 : VFP - 16'd1;
                            end else begin
                                v_cnt        <= v_cnt + 16'd1;
                                line_num_reg <= line_num_reg + 16'd1;
                            end
                    // Vfront 出口带帧首水位门：水位不足时停留一行再查
                    // （多发一行消隐、h 状态机自由跑 => 行率零影响，等待
                    // 全部发生在帧间消隐段，帧长被水位环锁定到源帧率）。
                    // 稳态：门控把水位稳定在门附近，水位带远离 HIGH 丢
                    // 帧门（参数检查保证），单环收敛无冲突。
                    Vfront: if (v_cnt == 16'd0) begin
                                if (used_words_rd >= VfrontWaitBeats) begin
                                    v_state       <= Vsync;
                                    frame_num_reg <= frame_num_reg + 16'd1;
                                end
                                // 水位不足：v_cnt 保持 0（停留一行消隐）
                            end else v_cnt <= v_cnt - 16'd1;
                    default: v_state <= Vsync;
                endcase
            end
        end
    end

    //================================================================
    // 7. FIFO 读端（pixel_clk 域）：单读口 mem_r
    //================================================================
    // 读使能 = 未打拍的行有效信号。同步读：当拍用当前指针取数，读数据
    // 统一进唯一读寄存器 mem_r（每拍刷新、无复位值），数据下一拍出现在
    // mem_r —— 与打一拍的 valid_r 严格同拍。全部控制信号同拍寄存器输出。
    //
    // 帧首纪律（替代旧锚定机制，同已验证出图设计）：写侧整帧门控保证
    // 队头恒为 sof（drop_frame 复位=1，首字必为帧首；满截断只伤帧尾、
    // 不碰队头）——读侧自由跑，Vact 首拍天然从帧首字起读。
    //（mem_r 声明已上移至第 5 节行首锚定处，供 gate_line 前向使用）
    //================================================================

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            rd_ptr_bin        <= 0;
            rd_ptr_gray       <= 0;
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            // 同步写指针格雷码（两级同步）
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;

            // ---- 唯一 mem 读口：无条件同步读 ----
            mem_r <= mem[rd_ptr_bin[FifoAddrWidth-1:0]];

            // 推进：Hact 行内读 / 搜索重对齐丢字步进 / 消隐段整行排水
            if (raw_active || (rsync_st == RsAdv)
                || (drain_line && (h_state == Hact))) begin
                rd_ptr_bin  <= rd_ptr_bin + 1'b1;
                rd_ptr_gray <= bin2gray(rd_ptr_bin + 1'b1);
            end
        end
    end

    //================================================================
    // 8. 输出寄存器（数据与全部控制同相位）
    //================================================================
    reg valid_r;
    reg hs_r, vs_r;

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            valid_r <= 1'b0;
            hs_r    <= 1'b1;   // 低有效，复位取非同步电平
            vs_r    <= 1'b1;
        end else begin
            valid_r <= raw_active;
            hs_r    <= (h_state != Hsync);
            vs_r    <= (v_state != Vsync);
        end
    end

    assign pixel_data       = mem_r[63:0];
    assign pixel_data_valid = valid_r;
    assign hsync_vc0        = hs_r;
    assign vsync_vc0        = vs_r;
    assign datatype         = DATA_TYPE;
    assign haddr            = HACT[15:0];
    assign line_num         = line_num_reg;
    assign frame_num        = frame_num_reg;

endmodule
