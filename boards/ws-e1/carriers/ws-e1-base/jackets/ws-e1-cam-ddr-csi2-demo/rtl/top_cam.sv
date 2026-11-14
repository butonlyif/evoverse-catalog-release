////////////////////////////////////////////////////////////////////////////
//  top_cam_demo.v — 摄像头直连顶层（CSI-2 RX IP -> camera_path -> CSI-2 TX IP）
//
//  数据通路（无 DDR、无帧缓冲，显示帧率跟随传感器）：
//    DPHY RX0 -> my_csi2_rx (裸 IP) -> RAW10 4px @ sys_clk_200m
//             -> camera_path (raw->demosaic->wb->rgb2yuv->shape，跨域成形)
//             -> UYVY 4px @ tx_pixel_clk (CSI-2 TX Video Interface)
//             -> my_csi2_tx (裸 IP) -> DPHY TX2 (4 lane, 2.5Gbps)
//
//  时钟：
//    sys_clk_200m : my_csi2_rx 像素输出域 + camera_path 流水线 (aclk)
//    tx_pixel_clk    : shape 读侧 / my_csi2_tx 像素域 + pattern_gen 行节拍源
//                   （板级 37.125MHz = 1080p60@PPC4）
//    sys_clk_100m  : my_csi2_rx 控制器时钟（AXI tie off，仍需供给）
//    dphy_rx_clk_CLKOUT : DPHY RX 恢复字时钟（byte 域复位随其停振保持）
//    i_clk_27m    : TX 侧上电自复位基准；esc_clk : DPHY TX
//
//  复位：
//    camera_path.aresetn    = sys_clk_200m_rstn
//    camera_path.pixel_rst_n = TX 侧 reset_chain tx_pixel_clk_rstn
//      （释放晚于 PLL 锁定 + ~300us + ~600us；传感器在软件 I2C 配置完成后
//       才开始发流，满足"pixel_rst_n 先于数据释放"的 shape 冷启动锚定契约）
//    my_csi2_rx 复位随 sys_clk_100m 域释放（PLL 锁定前 DPHY RX 硬核保持复位）
//
//  控制：riscv_soc APB slave0 -> apb_cam_ctrl
//    （bayer_phase/adaptive/wb 增益，复位默认 = 板级标定值上电即出像）；
//    APB slave1/2/3 dummy 即答；I2C0/1 -> IMX415；GPIO0.bit0 -> cam_0_en；
//    UART/JTAG USER1 原样（JTAG UPDATE/RESET 为 BRAM 固件加载路径，不可改）。
//
//  DDR：直连架构不再使用。ddr_inst 引脚绑定保留（peri.xml 不动），双端口
//    全 idle + CFG FSM 照常初始化 DDR 硬核（已验证行为，不引入新变量）。
//
//    camera_path 的 4 个 dbg 输出空连（板级如需再从 CSR/LA 引回）。
////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module top_cam #(
    // ---- camera_path: raw_2_axi4st 传感器窗口几何（IMX415 1080p60 RAW10）----
    parameter DTYPE           = 6'h2B,       // 像素 DT（RAW10）
    parameter LINE_TOTAL_PIX  = 20'd1944,    // 行总像素（WC=2430 字节）
    parameter LEAD_PIX        = 20'd6,       // 行首丢弃像素
    parameter TRAIL_PIX       = 20'd18,      // 行尾丢弃像素
    parameter LINE_SKIP_FIRST = 20'd11,      // 帧首丢弃 hs 行数
    parameter CAM_LINES       = 16'd1080,    // 有效行数
    parameter GW              = 16'd480,     // 每行组数（= HACT/4）
    // ---- camera_path: shape_video_axis 成形几何（须与面板时序一致）----
    parameter HACT            = 16'd1920,
    parameter VACT            = 16'd1080,
    parameter HSP             = 16'd44,
    parameter HBP             = 16'd148,
    parameter HFP             = 16'd88,
    parameter VSP             = 16'd5,
    parameter VBP             = 16'd36,
    parameter VFP             = 16'd4,
    parameter PPC             = 16'd4,
    parameter DATA_TYPE       = 6'h1E,       // YUV422 8-bit
    parameter FIFO_DEPTH      = 16'd32768,
    parameter HIGH_LINES      = 16'd60,
    parameter LOW_LINES       = 16'd12,
    parameter TRIM_LINES      = 16'd4,
    parameter VFRONT_WAIT_LINES = 16'd4,
    parameter DRAIN_CAP_LINES   = 16'd54,
    // 帧间调节三件套（2026-09 定版）：显示 Vblank(45 行)与供给 pad(34 行)
    // 错位相位自由慢漂，帧内锯齿最坏 79 行 > FIFO 容量 68.27 行，任何固定
    // 水位带必撞满/读空（pattern 段 lost ~1.2 万字/帧极限环的根因）。
    //   DRAIN_CAP_LINES=54：消隐段行粒度排水帽——水位超帽逐消隐行整行丢弃
    //   读，稳态水位钉 [9,55] 行：峰最坏 55 行 << FULL 68.27（零 lost
    //   => 无缺口 => srch 恒 0）；Vact 谷最坏 ~9 行 > 帧首门 4（Vfront
    //   零等待、帧长锁定 16.6665ms）；PPM 级帧率差（~9.7 行/帧）由排水
    //   行数逐帧吸收，全部藏在消隐段。
    //   VFRONT_WAIT_LINES=4：帧首低水位门（帧间调节低侧，纯读空保险；
    //   门高会每帧 Vfront 等水拖慢帧率——帧内锯齿 46 行 > 门帽带宽 34
    //   行，穿门即等水，2026-09 仿真定位帧长 16.756ms 的根因）
    //   HIGH_LINES=60（> 排水帽+4）：整帧丢弃纯兜底，正常流永不触发
    // ---- camera_path: pattern_gen 图案源（pclk 行节拍配准，见 pattern_gen.v）----
    // 图案行/帧推进与面板同源：pattern_gen 等 line_tick（pixel_clk 每
    // 550 拍一拍的 CDC 节拍脉冲）推进行，每帧 = 1091 + FRAME_PAD = 1125
    // 节拍 = 618,750 pclk 精确 60fps。供需同钟同频 => shape FIFO 水位零
    // 漂移 => 消隐段排水永不触发（旧 aclk 计拍与 pclk 37ppm 级独立钟差，
    // 60fps 下内容相位 ~2.5 行/s 漂移 = 板级图案慢滚动，2026-09 根治）
    parameter PATTERN_FRAME_PAD   = 20'd34      // 帧尾 pad 节拍数（1125 行 - 1091 图案行）
) (
    input sys_clk_100m,   
    input sys_clk_200m,
    input sys_clk_100m_rstn,
    input sys_clk_200m_rstn,
    input i_clk_27m,
    input pll_mipi_refclk_locked,
    input tx_pixel_clk,
    input esc_clk,
  
    input dphy_tx_WORD_CLKOUT_HS,
    input dphy_tx_STOPSTATE_CLK,
    input dphy_tx_STOPSTATE_LAN0,
    input dphy_tx_STOPSTATE_LAN1,
    input dphy_tx_STOPSTATE_LAN2,
    input dphy_tx_STOPSTATE_LAN3,
    input dphy_tx_TX_READY_HS_LAN0,
    input dphy_tx_TX_READY_HS_LAN1,
    input dphy_tx_TX_READY_HS_LAN2,
    input dphy_tx_TX_READY_HS_LAN3,
    input dphy_tx_TX_ULPS_ACTIVE_CLK_NOT,
    input dphy_tx_TX_ULPS_ACTIVE_NOT_LAN0,
    input dphy_tx_TX_ULPS_ACTIVE_NOT_LAN1,
    input dphy_tx_TX_ULPS_ACTIVE_NOT_LAN2,
    input dphy_tx_TX_ULPS_ACTIVE_NOT_LAN3,
  
    // MIPI TX peri pins
  
    output dphy_tx_PLL_SSC_EN,
    output dphy_tx_RESET_N,
    output [7:0] dphy_tx_TX_DATA_ESC,
    output dphy_tx_TX_LPDT_ESC,
    output dphy_tx_TX_VALID_ESC,
    output [3:0] dphy_tx_TX_TRIGGER_ESC,
    output dphy_tx_TX_REQUEST_ESC_LAN0,
    output dphy_tx_TX_REQUEST_ESC_LAN1,
    output dphy_tx_TX_REQUEST_ESC_LAN2,
    output dphy_tx_TX_REQUEST_ESC_LAN3,
    output dphy_tx_TX_REQUEST_HS,
    output dphy_tx_TX_REQUEST_HS_LAN0,
    output dphy_tx_TX_REQUEST_HS_LAN1,
    output dphy_tx_TX_REQUEST_HS_LAN2,
    output dphy_tx_TX_REQUEST_HS_LAN3,
    output dphy_tx_TX_SKEW_CAL_HS_LAN0,
    output dphy_tx_TX_SKEW_CAL_HS_LAN1,
    output dphy_tx_TX_SKEW_CAL_HS_LAN2,
    output dphy_tx_TX_SKEW_CAL_HS_LAN3,
    output dphy_tx_TX_ULPS_CLK,
    output dphy_tx_TX_ULPS_ESC_LAN0,
    output dphy_tx_TX_ULPS_ESC_LAN1,
    output dphy_tx_TX_ULPS_ESC_LAN2,
    output dphy_tx_TX_ULPS_ESC_LAN3,
    output dphy_tx_TX_ULPS_EXIT,
    output dphy_tx_TX_ULPS_EXIT_LAN0,
    output dphy_tx_TX_ULPS_EXIT_LAN1,
    output dphy_tx_TX_ULPS_EXIT_LAN2,
    output dphy_tx_TX_ULPS_EXIT_LAN3,
    output [15:0] dphy_tx_TX_DATA_HS_LAN0,
    output [15:0] dphy_tx_TX_DATA_HS_LAN1,
    output [15:0] dphy_tx_TX_DATA_HS_LAN2,
    output [15:0] dphy_tx_TX_DATA_HS_LAN3,
    output dphy_tx_TX_WORD_VALID_HS_LAN0,
    output dphy_tx_TX_WORD_VALID_HS_LAN1,
    output dphy_tx_TX_WORD_VALID_HS_LAN2,
    output dphy_tx_TX_WORD_VALID_HS_LAN3,
  
    // word clock from RX CLK lane (HS byte/word clock, stops when no stream)
    input  dphy_rx_clk_CLKOUT,
    // DPHY control (active-low resets)
    output dphy_rx_RESET_N,
    output dphy_rx_RST0_N,
    // clock lane status (debug observation)
  
    // clock lane ULPS
    input  dphy_rx_ULPS_CLK_ACTIVEN,
    input  dphy_rx_ULPS_CLK_ENTER,
    // data lane escape clocks
  
    input  dphy_rx_ESC_LAN0_CLK,
    input  dphy_rx_ESC_LAN1_CLK,
    input  dphy_rx_ESC_LAN2_CLK,
    input  dphy_rx_ESC_LAN3_CLK,
  
    // LP / escape / control errors
    input  dphy_rx_LINESTATE_LAN0_ERROR,
    input  dphy_rx_LINESTATE_LAN1_ERROR,
    input  dphy_rx_LINESTATE_LAN2_ERROR,
    input  dphy_rx_LINESTATE_LAN3_ERROR,
    input  dphy_rx_ESC_LAN0_ERROR,
    input  dphy_rx_ESC_LAN1_ERROR,
    input  dphy_rx_ESC_LAN2_ERROR,
    input  dphy_rx_ESC_LAN3_ERROR,
    // lane stop state (LP-11 idle indicator)
    input  dphy_rx_STOPSTATE_LAN0,
    input  dphy_rx_STOPSTATE_LAN1,
    input  dphy_rx_STOPSTATE_LAN2,
    input  dphy_rx_STOPSTATE_LAN3,
    // HS receive interface
    input  dphy_rx_HS_LAN0_VALID,
    input  dphy_rx_HS_LAN1_VALID,
    input  dphy_rx_HS_LAN2_VALID,
    input  dphy_rx_HS_LAN3_VALID,
    input  [15:0] dphy_rx_HS_LAN0_DATA,
    input  [15:0] dphy_rx_HS_LAN1_DATA,
    input  [15:0] dphy_rx_HS_LAN2_DATA,
    input  [15:0] dphy_rx_HS_LAN3_DATA,
    input  dphy_rx_HS_LAN0_SKEWCAL,
    input  dphy_rx_HS_LAN1_SKEWCAL,
    input  dphy_rx_HS_LAN2_SKEWCAL,
    input  dphy_rx_HS_LAN3_SKEWCAL,
    input  dphy_rx_HS_LAN0_SYNC,
    input  dphy_rx_HS_LAN1_SYNC,
    input  dphy_rx_HS_LAN2_SYNC,
    input  dphy_rx_HS_LAN3_SYNC,
    input  dphy_rx_HS_LAN0_SOTSYNC_ERROR,
    input  dphy_rx_HS_LAN1_SOTSYNC_ERROR,
    input  dphy_rx_HS_LAN2_SOTSYNC_ERROR,
    input  dphy_rx_HS_LAN3_SOTSYNC_ERROR,
    // data lane ULPS
    input  dphy_rx_ULPS_LAN0_ACTIVEN,
    input  dphy_rx_ULPS_LAN1_ACTIVEN,
    input  dphy_rx_ULPS_LAN2_ACTIVEN,
    input  dphy_rx_ULPS_LAN3_ACTIVEN,
    input  dphy_rx_ULPS_LAN0_ENTER,
    input  dphy_rx_ULPS_LAN1_ENTER,
    input  dphy_rx_ULPS_LAN2_ENTER,
    input  dphy_rx_ULPS_LAN3_ENTER,

    //-------------------------------------------------------------------------
    // riscv_soc
    //   APB slave0 -> apb_cam_ctrl（camera_path 控制口）
    //-------------------------------------------------------------------------
    input [15:0] apb_paddr,
    input        apb_psel,
    input        apb_penable,
    input        apb_pwrite,
    input  [31:0] apb_pwdata,
    output [31:0] apb_prdata,
    output        apb_pready,
    output        apb_pslverr


);

    wire [1:0]  cp_bayer_phase;
    wire        cp_adaptive;
    wire [7:0]  cp_wb_r, cp_wb_g, cp_wb_b;
    wire        cp_pat_en;
    wire [1:0]  cp_pat_sel;

    apb_cam_ctrl #(
        .CTRL_RESET(32'hB4EB_C80C)   // wb 180/235/200, pat_en=1(上电灰度图案), adaptive=1, phase=0(RGGB)
    ) u_cam_ctrl (
        .pclk        (sys_clk_200m),
        .presetn     (sys_clk_200m_rstn),
        .paddr       (apb_paddr),
        .psel        (apb_psel),
        .penable     (apb_penable),
        .pwrite      (apb_pwrite),
        .pwdata      (apb_pwdata),
        .prdata      (apb_prdata),
        .pready      (apb_pready),
        .pslverr     (apb_pslverr),
        .bayer_phase (cp_bayer_phase),
        .adaptive    (cp_adaptive),
        .wb_r        (cp_wb_r),
        .wb_g        (cp_wb_g),
        .wb_b        (cp_wb_b),
        .pat_en      (cp_pat_en),
        .pat_sel     (cp_pat_sel)
    );

    //-------------------------------------------------------------------------
    // MIPI CSI-2 RX：my_csi2_rx 裸 IP 直例化
    //
    //   clk = sys_clk_100m（IP 控制器时钟，AXI tie off）
    //   clk_pixel = sys_clk_200m（像素输出域，>= 178.2MHz UG 下限）
    //   clk_byte_HS = DPHY 恢复字时钟（无流停振，复位保持）
    //   DPHY 复位随 100M 域释放：PLL 锁定前硬核保持复位
    //-------------------------------------------------------------------------
    wire dphy_rx_clk_CLKOUT_rstn;


    reset_ctrl #(.NUM_RST(1), .IN_RST_ACTIVE(1'b0), .OUT_RST_ACTIVE(1'b0)) u_rx_rst_byte (
        .i_arst (sys_clk_200m_rstn), .i_clk (dphy_rx_clk_CLKOUT), .o_srst (dphy_rx_clk_CLKOUT_rstn)
    );

    assign dphy_rx_RESET_N  = sys_clk_100m_rstn;
    assign dphy_rx_RST0_N = sys_clk_100m_rstn;

    // RxValidHS 端口为每 lane 2bit，DPHY 每 lane 只给 1bit，复制扩展
    wire [1:0] rx_valid_ext0, rx_valid_ext1, rx_valid_ext2, rx_valid_ext3;
    assign rx_valid_ext0 = {2{dphy_rx_HS_LAN0_VALID}};
    assign rx_valid_ext1 = {2{dphy_rx_HS_LAN1_VALID}};
    assign rx_valid_ext2 = {2{dphy_rx_HS_LAN2_VALID}};
    assign rx_valid_ext3 = {2{dphy_rx_HS_LAN3_VALID}};

    // 像素输出（clk_pixel = sys_clk_200m 域）
    wire [63:0] rx_pixel_data;
    wire        rx_pixel_valid, rx_pixel_hs, rx_pixel_vs;
    wire [5:0]  rx_pixel_datatype;

    // TX 复位链输出（reset_ctrl 在下方例化，此处提前声明供 u_path 连接）
    wire tx_pixel_clk_rstn, word_clk_arstn, esc_clk_arstn;

    my_csi2_rx u_csi2_rx_cam0 (
        .reset_n         (sys_clk_100m_rstn),
        .clk             (sys_clk_100m),
        .reset_byte_HS_n (dphy_rx_clk_CLKOUT_rstn),
        .clk_byte_HS     (dphy_rx_clk_CLKOUT),
        .reset_pixel_n   (sys_clk_200m_rstn),
        .clk_pixel       (sys_clk_200m),

        .RxClkEsc           ({dphy_rx_ESC_LAN3_CLK,
                              dphy_rx_ESC_LAN2_CLK,
                              dphy_rx_ESC_LAN1_CLK,
                              dphy_rx_ESC_LAN0_CLK}),
        .RxUlpsClkNot       (dphy_rx_ULPS_CLK_ENTER),
        .RxUlpsActiveClkNot (dphy_rx_ULPS_CLK_ACTIVEN),
        .RxErrEsc           ({dphy_rx_ESC_LAN3_ERROR,
                              dphy_rx_ESC_LAN2_ERROR,
                              dphy_rx_ESC_LAN1_ERROR,
                              dphy_rx_ESC_LAN0_ERROR}),
        .RxErrControl       ({dphy_rx_LINESTATE_LAN3_ERROR,
                              dphy_rx_LINESTATE_LAN2_ERROR,
                              dphy_rx_LINESTATE_LAN1_ERROR,
                              dphy_rx_LINESTATE_LAN0_ERROR}),
        .RxErrSotSyncHS     ({dphy_rx_HS_LAN3_SOTSYNC_ERROR,
                              dphy_rx_HS_LAN2_SOTSYNC_ERROR,
                              dphy_rx_HS_LAN1_SOTSYNC_ERROR,
                              dphy_rx_HS_LAN0_SOTSYNC_ERROR}),
        .RxUlpsEsc          ({dphy_rx_ULPS_LAN3_ENTER,
                              dphy_rx_ULPS_LAN2_ENTER,
                              dphy_rx_ULPS_LAN1_ENTER,
                              dphy_rx_ULPS_LAN0_ENTER}),
        .RxUlpsActiveNot    ({dphy_rx_ULPS_LAN3_ACTIVEN,
                              dphy_rx_ULPS_LAN2_ACTIVEN,
                              dphy_rx_ULPS_LAN1_ACTIVEN,
                              dphy_rx_ULPS_LAN0_ACTIVEN}),
        .RxSkewCalHS        ({dphy_rx_HS_LAN3_SKEWCAL,
                              dphy_rx_HS_LAN2_SKEWCAL,
                              dphy_rx_HS_LAN1_SKEWCAL,
                              dphy_rx_HS_LAN0_SKEWCAL}),
        .RxStopState        ({dphy_rx_STOPSTATE_LAN3,
                              dphy_rx_STOPSTATE_LAN2,
                              dphy_rx_STOPSTATE_LAN1,
                              dphy_rx_STOPSTATE_LAN0}),
        .RxSyncHS           ({dphy_rx_HS_LAN3_SYNC,
                              dphy_rx_HS_LAN2_SYNC,
                              dphy_rx_HS_LAN1_SYNC,
                              dphy_rx_HS_LAN0_SYNC}),
        .RxDataHS0          (dphy_rx_HS_LAN0_DATA),
        .RxDataHS1          (dphy_rx_HS_LAN1_DATA),
        .RxDataHS2          (dphy_rx_HS_LAN2_DATA),
        .RxDataHS3          (dphy_rx_HS_LAN3_DATA),
        .RxDataHS4          (),
        .RxDataHS5          (),
        .RxDataHS6          (),
        .RxDataHS7          (),
        .RxValidHS0         (rx_valid_ext0),
        .RxValidHS1         (rx_valid_ext1),
        .RxValidHS2         (rx_valid_ext2),
        .RxValidHS3         (rx_valid_ext3),
        .RxValidHS4         (),
        .RxValidHS5         (),
        .RxValidHS6         (),
        .RxValidHS7         (),

        // AXI-Lite CSR 不接入（tie off，同 csi_rx_top 已验证用法）
        .axi_clk     (sys_clk_100m),
        .axi_reset_n (sys_clk_100m_rstn),
        .axi_awaddr  (6'b0),
        .axi_awvalid (1'b0),
        .axi_awready (),
        .axi_wdata   (32'b0),
        .axi_wvalid  (1'b0),
        .axi_wready  (),
        .axi_bvalid  (),
        .axi_bready  (1'b1),
        .axi_araddr  (6'b0),
        .axi_arvalid (1'b0),
        .axi_arready (),
        .axi_rdata   (),
        .axi_rvalid  (),
        .axi_rready  (1'b1),
        .irq         (),

        // Video Interface -> camera_path（同域直连，in_dtype 取 pixel 域元数据）
        .hsync_vc1  (), .hsync_vc2  (), .hsync_vc3  (), .hsync_vc4  (),
        .hsync_vc5  (), .hsync_vc6  (), .hsync_vc7  (), .hsync_vc8  (),
        .hsync_vc9  (), .hsync_vc10 (), .hsync_vc11 (), .hsync_vc12 (),
        .hsync_vc13 (), .hsync_vc14 (), .hsync_vc15 (),
        .vsync_vc1  (), .vsync_vc2  (), .vsync_vc3  (), .vsync_vc4  (),
        .vsync_vc5  (), .vsync_vc6  (), .vsync_vc7  (), .vsync_vc8  (),
        .vsync_vc9  (), .vsync_vc10 (), .vsync_vc11 (), .vsync_vc12 (),
        .vsync_vc13 (), .vsync_vc14 (), .vsync_vc15 (),
        .hsync_vc0        (rx_pixel_hs),
        .vsync_vc0        (rx_pixel_vs),
        .pixel_data       (rx_pixel_data),
        .pixel_data_valid (rx_pixel_valid),
        .pixel_datatype   (rx_pixel_datatype),
        .pixel_per_clk    (),
        .datatype (),
        .shortpkt_data_field (),
        .word_count (),
        .vcx(),
        .vc(),
        .pixel_line_num   (),
        .pixel_frame_num  (),
        .pixel_wordcount  (),
        .pixel_vc         (),
        .pixel_vcx        ()

    );

    //-------------------------------------------------------------------------
    // pattern_gen 行节拍发生器：pixel_clk 计 550 拍/行（(HSP+HBP+HACT+HFP)
    // /PPC）翻转触发器，2FF CDC 进 aclk 域取沿 => 每面板行一个 aclk 单拍
    // 脉冲。pattern_gen 行推进改吃此节拍，与面板行/帧节奏同钟同频（根治
    // 图案慢滚动，见 pattern_gen.v 头注释）
    //-------------------------------------------------------------------------
    localparam int PAT_LINE_TICK_PCLK = (HSP + HBP + HACT + HFP) / PPC;  // 550
    reg [9:0]  pat_tick_cnt;
    reg        pat_tick_tgl;
    always @(posedge tx_pixel_clk or negedge tx_pixel_clk_rstn) begin
        if (!tx_pixel_clk_rstn) begin
            pat_tick_cnt <= 10'd0;
            pat_tick_tgl <= 1'b0;
        end else if (pat_tick_cnt == PAT_LINE_TICK_PCLK - 10'd1) begin
            pat_tick_cnt <= 10'd0;
            pat_tick_tgl <= ~pat_tick_tgl;
        end else begin
            pat_tick_cnt <= pat_tick_cnt + 10'd1;
        end
    end
    reg [2:0] pat_tick_sync;
    always @(posedge sys_clk_200m or negedge sys_clk_200m_rstn)
        if (!sys_clk_200m_rstn) pat_tick_sync <= 3'b000;
        else                 pat_tick_sync <= {pat_tick_sync[1:0], pat_tick_tgl};
    wire pat_line_tick = pat_tick_sync[1] ^ pat_tick_sync[2];

    //-------------------------------------------------------------------------
    // pattern_gen：自诊断图案拍流（raw_2_axi4st 之前注入，传感器协议同构）。
    // CSR CTRL[3] pat_en=1 时经下方 mux 替换 my_csi2_rx 输出；行中切换
    // 最多撕裂 1 行（raw 限定行首拍自愈），固件在帧边界切换即可。
    //-------------------------------------------------------------------------
    wire [39:0] pat_data;
    wire        pat_valid, pat_vs, pat_hs;
    wire [5:0]  pat_dtype;

    pattern_gen #(
        .DUMMY_LINES (LINE_SKIP_FIRST),
        .LIVE_LINES  (CAM_LINES),
        .LINE_BEATS  (LINE_TOTAL_PIX[19:2]),
        .FRAME_PAD   (PATTERN_FRAME_PAD),
        .DT_RAW10    (DTYPE)
    ) u_pat_gen (
        .aclk      (sys_clk_200m),
        .aresetn   (sys_clk_200m_rstn),
        .line_tick (pat_line_tick),
        .pat_sel   (cp_pat_sel),
        .pat_data  (pat_data),
        .pat_valid (pat_valid),
        .pat_dtype (pat_dtype),
        .pat_hs    (pat_hs),
        .pat_vs    (pat_vs)
    );

    // ---- 源切换软复位（2026-09 板级修复）：pat_en 变化沿 => camera_path ----
    // 两域脉冲复位。切换瞬间 shape FIFO 残留旧源尾字（非整行/帧对齐），
    // 显示下一帧从残字起读 => 画面垂直偏移 N 行（N=残字/480 行）。软复位
    // 语义：写侧 drop_frame=1 重新等新源 SOF、FIFO 读写指针清零（残字清
    // 光）、读侧 v 回 Vsync 重启帧 => 切换后从新源帧首垂直对齐；代价是切
    // 换瞬间失步/黑一帧（源切换本就撕裂，固件切完即恢复）。aclk 与
    // tx_pixel_clk 同为 sys_clk_200m（u_csi2_rx clk_pixel 同源），单域展宽
    // 脉冲同时复位两侧；pattern_gen 不复位（自由跑，shape 等 SOF 接入）。
    reg [2:0] pat_en_sync;
    always @(posedge sys_clk_200m or negedge sys_clk_200m_rstn)
        if (!sys_clk_200m_rstn) pat_en_sync <= 3'b111;  // 对齐 cp_pat_en 默认 1（消上电假沿）
        else                 pat_en_sync <= {pat_en_sync[1:0], cp_pat_en};
    reg [7:0] sw_rst_cnt;
    reg       sw_rst_act;
    always @(posedge sys_clk_200m or negedge sys_clk_200m_rstn) begin
        if (!sys_clk_200m_rstn) begin
            sw_rst_cnt <= 8'd0;
            sw_rst_act <= 1'b0;
        end else if (pat_en_sync[2] ^ pat_en_sync[1]) begin
            sw_rst_cnt <= 8'd200;               // ~1us 复位脉冲
            sw_rst_act <= 1'b1;
        end else if (sw_rst_act) begin
            sw_rst_cnt <= sw_rst_cnt - 8'd1;
            sw_rst_act <= (sw_rst_cnt != 8'd1);
        end
    end
    wire sw_rstn = ~sw_rst_act;                 // 低有效，正常 1

    // camera_path 输入 mux：pat_en=1 图案源 / 0 传感器直通
    wire [39:0] path_in_data;
    wire        path_in_valid, path_in_vs, path_in_hs;
    wire [5:0]  path_in_dtype;

    assign path_in_data  = cp_pat_en ? pat_data        : rx_pixel_data[39:0];
    assign path_in_valid = cp_pat_en ? pat_valid       : rx_pixel_valid;
    assign path_in_vs    = cp_pat_en ? pat_vs          : rx_pixel_vs;
    assign path_in_hs    = cp_pat_en ? pat_hs          : rx_pixel_hs;
    assign path_in_dtype = cp_pat_en ? DTYPE           : rx_pixel_datatype;

    //-------------------------------------------------------------------------
    // camera_path：五级图像流水线（RAW10 -> demosaic -> wb -> rgb2yuv -> shape）
    //   写侧 aclk = sys_clk_200m；shape 读侧 tx_pixel_clk 输出 CSI-2 TX Video
    //   Interface（跨域 + 成形 + 帧率锁定全部在 shape_video_axis 内完成）
    //-------------------------------------------------------------------------
    (* syn_keep = "true" *)wire        tx_vsync, tx_hsync, tx_pixel_valid;
    (* syn_keep = "true" *)wire [63:0] tx_pixel_data;
    (* syn_keep = "true" *)wire [5:0]  tx_datatype;
    (* syn_keep = "true" *)wire [15:0] tx_haddr, tx_line_num, tx_frame_num;

    camera_path #(
        .DTYPE          (DTYPE),
        .LINE_TOTAL_PIX (LINE_TOTAL_PIX),
        .LEAD_PIX       (LEAD_PIX),
        .TRAIL_PIX      (TRAIL_PIX),
        .LINE_SKIP_FIRST(LINE_SKIP_FIRST),
        .LINES          (CAM_LINES),
        .GW             (GW),
        .HACT(HACT), .VACT(VACT), .HSP(HSP), .HBP(HBP), .HFP(HFP),
        .VSP(VSP), .VBP(VBP), .VFP(VFP), .PPC(PPC),
        .DATA_TYPE      (DATA_TYPE),
        .FIFO_DEPTH     (FIFO_DEPTH),
        .HIGH_LINES     (HIGH_LINES), .LOW_LINES(LOW_LINES), .TRIM_LINES(TRIM_LINES),
        .VFRONT_WAIT_LINES(VFRONT_WAIT_LINES), .DRAIN_CAP_LINES(DRAIN_CAP_LINES)
    ) u_path (
        .aclk         (sys_clk_200m),
        .aresetn      (sys_clk_200m_rstn & sw_rstn),
        .pixel_clk    (tx_pixel_clk),
        .pixel_rst_n  (tx_pixel_clk_rstn & sw_rstn),   // TX 复位链 & 源切换软复位

        .in_data      (path_in_data),          // 4xRAW10 打包在低 40bit
        .in_valid     (path_in_valid),
        .in_vs        (path_in_vs),
        .in_hs        (path_in_hs),
        .in_dtype     (path_in_dtype),

        .bayer_phase  (cp_bayer_phase),
        .adaptive     (cp_adaptive),
        // wb 生效值：pat_en=1（图案源）强制 unity 0x40 直通。图案已按
        // 显示幅度编码，sensor 校准增益（复位默认 200/235/180 = x3.1/
        // x3.7/x2.8）会使其通道饱和变色（旧橙蓝竖条显黄/青、灰 ramp 偏
        // 绿且右 2/3 钳白，2026-09 板级确认）；相机源保持 CSR 值不动。
        // blk_clip 同理旁路：rgb2yuv 暗场钳位（Y<24 归零）是 sensor 暗
        // 场 FPN 噪声钳制，会把精确码值 ramp 的暗部整段压黑（板级表现
        // 为渐变前 ~10% 纯黑平顶后突变，2026-09 确认）
        .wb_r         (cp_pat_en ? 8'h40 : cp_wb_r),
        .wb_g         (cp_pat_en ? 8'h40 : cp_wb_g),
        .wb_b         (cp_pat_en ? 8'h40 : cp_wb_b),
        .blk_clip     (!cp_pat_en),

        .hsync_vc0    (tx_hsync),
        .vsync_vc0    (tx_vsync),
        .datatype     (tx_datatype),
        .pixel_data   (tx_pixel_data),
        .pixel_data_valid(tx_pixel_valid),
        .haddr        (tx_haddr),
        .line_num     (tx_line_num),
        .frame_num    (tx_frame_num)
    );

    //-------------------------------------------------------------------------
    // MIPI CSI-2 TX：my_csi2_tx 裸 IP 直例化
    //
    //   复位释放链：
    //     i_clk_27m 自复位(256 拍) -> PLL 释放 -> DPHY(PLL locked + ~300us)
    //     -> 像素/字/esc 域（再 + ~600us skewcal）
    //-------------------------------------------------------------------------
    // LP (escape) 数据路径未被 CSI-2 TX IP 使用 -> tie off
    assign dphy_tx_TX_DATA_ESC    = 8'h0;
    assign dphy_tx_TX_LPDT_ESC    = 1'b0;
    assign dphy_tx_TX_VALID_ESC   = 1'b0;
    assign dphy_tx_TX_TRIGGER_ESC = 4'h0;




    assign dphy_tx_RESET_N     = pll_mipi_refclk_locked;
    assign dphy_tx_PLL_SSC_EN  = 1'b0;

    //wait for ~300us for DPHY ready
    reg [12:0] cnt_250us;
    reg reset_esc_n;
    reg clk_byte_HS_n;
    always @(posedge i_clk_27m or negedge dphy_tx_RESET_N) begin
        if (~dphy_tx_RESET_N) begin
            cnt_250us     <= 13'd0;
            reset_esc_n   <= 1'b0;
            clk_byte_HS_n <= 1'b0;
        end else if (cnt_250us == 13'h1fff) begin
            cnt_250us     <= 13'h1fff;
            reset_esc_n   <= 1'b1;
            clk_byte_HS_n <= 1'b1;
        end else begin
            cnt_250us     <= cnt_250us + 1'b1;
            reset_esc_n   <= 1'b0;
            clk_byte_HS_n <= 1'b0;
        end
    end

    //wait another ~600us tINIT_NS + skewcal
    reg [13:0] cnt_500us;
    reg reset_pixel_n;
    always @(posedge i_clk_27m or negedge clk_byte_HS_n) begin
        if (~clk_byte_HS_n) begin
            cnt_500us      <= 14'd0;
            reset_pixel_n  <= 1'b0;
        end else if (cnt_500us == 14'h3fff) begin
            cnt_500us      <= 14'h3fff;
            reset_pixel_n  <= 1'b1;
        end else begin
            cnt_500us      <= cnt_500us + 1'b1;
            reset_pixel_n  <= 1'b0;
        end
    end

    // 四个使用域的低有效同步复位（原 8 路版只保留实际使用路）
    // （声明提前到 u_path 例化之前，避免端口连接隐式 wire 与显式声明冲突）

    reset_ctrl #(
        .NUM_RST       (3),
        .CYCLE         (2),
        .IN_RST_ACTIVE (3'b000),
        .OUT_RST_ACTIVE(3'b000)
    ) u_tx_reset_ctrl (
        .i_arst ({reset_pixel_n, clk_byte_HS_n, reset_esc_n}),
        .i_clk  ({tx_pixel_clk, dphy_tx_WORD_CLKOUT_HS, esc_clk}),
        .o_srst ({tx_pixel_clk_rstn, word_clk_arstn, esc_clk_arstn})
    );

    // Mapping to DPHY TX
    wire                      TxUlpsClk;
    wire                      TxUlpsExitClk;
    wire [3:0]                TxUlpsEsc;
    wire [3:0]                TxUlpsExit;
    wire [3:0]                TxRequestEsc;
    wire [3:0]                TxSkewCalHS;
    wire [3:0]                TxRequestHS;
    wire                      TxRequestHSc;
    wire [15:0]               TxDataHS0, TxDataHS1, TxDataHS2, TxDataHS3;
    wire [1:0]                TxReqValidHS0, TxReqValidHS1, TxReqValidHS2, TxReqValidHS3;
    wire                      TxUlpsActiveClkNot;
    wire [3:0]                TxStopStateD;
    wire                      TxStopStateC;
    wire [3:0]                TxUlpsActiveNot;
    wire [3:0]                TxReadyHS;

    assign TxStopStateC = dphy_tx_STOPSTATE_CLK;
    assign dphy_tx_TX_REQUEST_HS = TxRequestHSc;
    assign dphy_tx_TX_ULPS_CLK   = TxUlpsClk;
    assign dphy_tx_TX_ULPS_EXIT  = TxUlpsExitClk;
    assign TxUlpsActiveClkNot = dphy_tx_TX_ULPS_ACTIVE_CLK_NOT;

    assign dphy_tx_TX_ULPS_ESC_LAN0 = TxUlpsEsc[0];
    assign dphy_tx_TX_ULPS_ESC_LAN1 = TxUlpsEsc[1];
    assign dphy_tx_TX_ULPS_ESC_LAN2 = TxUlpsEsc[2];
    assign dphy_tx_TX_ULPS_ESC_LAN3 = TxUlpsEsc[3];
    assign dphy_tx_TX_ULPS_EXIT_LAN0 = TxUlpsExit[0];
    assign dphy_tx_TX_ULPS_EXIT_LAN1 = TxUlpsExit[1];
    assign dphy_tx_TX_ULPS_EXIT_LAN2 = TxUlpsExit[2];
    assign dphy_tx_TX_ULPS_EXIT_LAN3 = TxUlpsExit[3];
    assign dphy_tx_TX_REQUEST_ESC_LAN0 = TxRequestEsc[0];
    assign dphy_tx_TX_REQUEST_ESC_LAN1 = TxRequestEsc[1];
    assign dphy_tx_TX_REQUEST_ESC_LAN2 = TxRequestEsc[2];
    assign dphy_tx_TX_REQUEST_ESC_LAN3 = TxRequestEsc[3];
    assign dphy_tx_TX_SKEW_CAL_HS_LAN0 = TxSkewCalHS[0];
    assign dphy_tx_TX_SKEW_CAL_HS_LAN1 = TxSkewCalHS[1];
    assign dphy_tx_TX_SKEW_CAL_HS_LAN2 = TxSkewCalHS[2];
    assign dphy_tx_TX_SKEW_CAL_HS_LAN3 = TxSkewCalHS[3];
    assign TxStopStateD[0] = dphy_tx_STOPSTATE_LAN0;
    assign TxStopStateD[1] = dphy_tx_STOPSTATE_LAN1;
    assign TxStopStateD[2] = dphy_tx_STOPSTATE_LAN2;
    assign TxStopStateD[3] = dphy_tx_STOPSTATE_LAN3;

    assign TxUlpsActiveNot[0] = dphy_tx_TX_ULPS_ACTIVE_NOT_LAN0;
    assign TxUlpsActiveNot[1] = dphy_tx_TX_ULPS_ACTIVE_NOT_LAN1;
    assign TxUlpsActiveNot[2] = dphy_tx_TX_ULPS_ACTIVE_NOT_LAN2;
    assign TxUlpsActiveNot[3] = dphy_tx_TX_ULPS_ACTIVE_NOT_LAN3;
    assign TxReadyHS[0] = dphy_tx_TX_READY_HS_LAN0;
    assign TxReadyHS[1] = dphy_tx_TX_READY_HS_LAN1;
    assign TxReadyHS[2] = dphy_tx_TX_READY_HS_LAN2;
    assign TxReadyHS[3] = dphy_tx_TX_READY_HS_LAN3;

    assign dphy_tx_TX_DATA_HS_LAN0 = TxDataHS0;
    assign dphy_tx_TX_DATA_HS_LAN1 = TxDataHS1;
    assign dphy_tx_TX_DATA_HS_LAN2 = TxDataHS2;
    assign dphy_tx_TX_DATA_HS_LAN3 = TxDataHS3;
    assign dphy_tx_TX_REQUEST_HS_LAN0 = TxRequestHS[0];
    assign dphy_tx_TX_REQUEST_HS_LAN1 = TxRequestHS[1];
    assign dphy_tx_TX_REQUEST_HS_LAN2 = TxRequestHS[2];
    assign dphy_tx_TX_REQUEST_HS_LAN3 = TxRequestHS[3];
    assign dphy_tx_TX_WORD_VALID_HS_LAN0 = TxReqValidHS0[1];
    assign dphy_tx_TX_WORD_VALID_HS_LAN1 = TxReqValidHS1[1];
    assign dphy_tx_TX_WORD_VALID_HS_LAN2 = TxReqValidHS2[1];
    assign dphy_tx_TX_WORD_VALID_HS_LAN3 = TxReqValidHS3[1];

    // MIPI CSI-2 TX IP : zero software init, free-run streaming mode
    my_csi2_tx u_my_csi2_tx (
        .clk_byte_HS        (dphy_tx_WORD_CLKOUT_HS),
        .reset_byte_HS_n    (word_clk_arstn),

        .clk_pixel          (tx_pixel_clk),
        .reset_pixel_n      (tx_pixel_clk_rstn),  // 像素侧必须用 tx_pixel_clk 域同步释放复位

        .clk_esc            (esc_clk),
        .reset_esc_n        (esc_clk_arstn),

        .hsync_vc1          (), .hsync_vc2 (), .hsync_vc3 (), .hsync_vc4 (),
        .hsync_vc5          (), .hsync_vc6 (), .hsync_vc7 (), .hsync_vc8 (),
        .hsync_vc9          (), .hsync_vc10(), .hsync_vc11(), .hsync_vc12(),
        .hsync_vc13         (), .hsync_vc14(), .hsync_vc15(),
        .vsync_vc1          (), .vsync_vc2 (), .vsync_vc3 (), .vsync_vc4 (),
        .vsync_vc5          (), .vsync_vc6 (), .vsync_vc7 (), .vsync_vc8 (),
        .vsync_vc9          (), .vsync_vc10(), .vsync_vc11(), .vsync_vc12(),
        .vsync_vc13         (), .vsync_vc14(), .vsync_vc15(),
        .frame_num          (tx_frame_num),
        .hsync_vc0          (tx_hsync),
        .vsync_vc0          (tx_vsync),
        .line_num           (tx_line_num),
        .haddr              (tx_haddr),
        .pixel_data         (tx_pixel_data),
        .pixel_data_valid   (tx_pixel_valid),
        .datatype           (tx_datatype),

        // AXI4-Lite tie off, no register access
        .axi_clk            (sys_clk_100m),
        .axi_reset_n        (sys_clk_100m_rstn),
        .axi_awready		(),
        .axi_awaddr         (6'b0),
        .axi_awvalid        (1'b0),
        .axi_wready			(),
        .axi_wdata          (32'b0),
        .axi_wvalid         (1'b0),
        .axi_bready         (1'b0),
        .axi_bvalid			(),
        .axi_araddr         (6'b0),
        .axi_arvalid        (1'b0),
        .axi_rready         (1'b1),
        .axi_arready		(),
        .axi_rdata			(),
        .axi_rvalid			(),
        .irq                (),


        .TxUlpsClk          (TxUlpsClk),
        .TxUlpsExitClk      (TxUlpsExitClk),
        .TxUlpsActiveClkNot (TxUlpsActiveClkNot),
        .TxUlpsEsc          (TxUlpsEsc),
        .TxSkewCalHS        (TxSkewCalHS),
        .TxUlpsExit         (TxUlpsExit),
        .TxRequestEsc       (TxRequestEsc),
        .TxStopStateD       (TxStopStateD),
        .TxStopStateC       (TxStopStateC),
        .TxUlpsActiveNot    (TxUlpsActiveNot),
        .TxReadyHS          (TxReadyHS),
        .TxRequestHS        (TxRequestHS),
        .TxRequestHSc       (TxRequestHSc),
        .TxDataHS0          (TxDataHS0),
        .TxDataHS1          (TxDataHS1),
        .TxDataHS2          (TxDataHS2),
        .TxDataHS3          (TxDataHS3),
        .TxDataHS4          (),
        .TxDataHS5          (),
        .TxDataHS6          (),
        .TxDataHS7          (),
        .TxReqValidHS0      (TxReqValidHS0),
        .TxReqValidHS1      (TxReqValidHS1),
        .TxReqValidHS2      (TxReqValidHS2),
        .TxReqValidHS3      (TxReqValidHS3),
        .TxReqValidHS4      (),
        .TxReqValidHS5      (),
        .TxReqValidHS6      (),
        .TxReqValidHS7      ()
    );

endmodule
