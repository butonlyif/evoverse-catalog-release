////////////////////////////////////////////////////////////////////////////
//  top_cam_demo.v — 摄像头直连顶层（CSI-2 RX IP -> camera_path -> CSI-2 TX IP）
//
//  数据通路（无 DDR、无帧缓冲，显示帧率跟随传感器）：
//    DPHY RX0 -> my_csi2_rx (裸 IP) -> RAW10 4px @ sys_clk_200m
//             -> camera_path (raw->demosaic->wb->rgb2yuv->shape，跨域成形)
//             -> UYVY 4px @ pixel_clk (CSI-2 TX Video Interface)
//             -> my_csi2_tx (裸 IP) -> DPHY TX2 (4 lane, 2.5Gbps)
//
//  时钟：
//    sys_clk_200m : my_csi2_rx 像素输出域 + camera_path 流水线 (aclk)
//    pixel_clk    : pll_csi#1 148.5MHz —— cam0 shape 读侧 / my_csi2_tx 像素域
//                   + pattern 行节拍源（4K60@PPC4，CEA 2x 1080p 消隐）
//    pixel_clk_1080 : pll_csi#0 37.125MHz —— cam1 camera_path 流水线
//                   / shape 写读 / TX 像素域（1080p60@PPC4）
//    sys_clk_100m  : my_csi2_rx 控制器时钟（AXI tie off，仍需供给）
//    dphy_rx0_clk_CLKOUT : DPHY RX 恢复字时钟（byte 域复位随其停振保持）
//    i_clk_27m    : TX 侧上电自复位基准；esc_clk / mipi_refclk_25m : DPHY TX
//
//  复位：
//    camera_path.aresetn    = sys_clk_200m_rstn
//    camera_path.pixel_rst_n = TX 侧 reset_chain pixel_clk_arstn
//      （释放晚于 PLL 锁定 + ~300us + ~600us；传感器在软件 I2C 配置完成后
//       才开始发流，满足"pixel_rst_n 先于数据释放"的 shape 冷启动锚定契约）
//    my_csi2_rx 复位随 sys_clk_100m 域释放（PLL 锁定前 DPHY RX 硬核保持复位）
//
//  控制：riscv_soc APB slave0 -> apb_cam_ctrl
//    （bayer_phase/adaptive/wb 增益，复位默认 = 板级标定值上电即出像）；
//    APB slave1/2/3 dummy 即答；I2C0/1 -> IMX415；GPIO0.bit0 -> cam_0_en；
//    UART/JTAG USER1 原样（JTAG UPDATE/RESET 为 BRAM 固件加载路径，不可改）。
//
//  DDR：直通阶段双端口全 idle + CFG FSM 照常初始化硬核。2026-10-18 阶段 0
//    起挂 ddr_memcheck（DDR_MEMTEST=1）做读写自检，DIAG11 读回；正式视频
//    通路（frame_writer/reader）接入后置 0 回 idle。
//
//    camera_path 的 4 个 dbg 输出空连（板级如需再从 CSR/LA 引回）。
////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module top_cam_demo (
  (* syn_peri_port = 0 *) input jtag_inst1_CAPTURE,
  (* syn_peri_port = 0 *) input jtag_inst1_DRCK,
  (* syn_peri_port = 0 *) input jtag_inst1_RESET,
  (* syn_peri_port = 0 *) input jtag_inst1_RUNTEST,
  (* syn_peri_port = 0 *) input jtag_inst1_SEL,
  (* syn_peri_port = 0 *) input jtag_inst1_SHIFT,
  (* syn_peri_port = 0 *) input jtag_inst1_TCK,
  (* syn_peri_port = 0 *) input jtag_inst1_TDI,
  (* syn_peri_port = 0 *) input jtag_inst1_TMS,
  (* syn_peri_port = 0 *) input jtag_inst1_UPDATE,
  (* syn_peri_port = 0 *) output jtag_inst1_TDO,

  (* syn_peri_port = 0 *) input sys_clk_100m,   
  (* syn_peri_port = 0 *) input sys_clk_200m,
  (* syn_peri_port = 0 *) input pll_sys_locked,
  (* syn_peri_port = 0 *) input pll_ddr_locked,
  (* syn_peri_port = 0 *) input pll_mipi_refclk_locked,
  (* syn_peri_port = 0 *) input pll_csi_locked,
  (* syn_peri_port = 0 *) input pll_csi2_locked,    // pll_csi2（BL1，cam1 37.125M）
  (* syn_peri_port = 0 *) input i_clk_27m,
  (* syn_peri_port = 0 *) input pixel_clk,        // pll_csi #1: 148.5MHz（cam0 4K60@PPC4）
  (* syn_peri_port = 0 *) input pixel_clk_1080,   // pll_csi2 #1: 37.125MHz（cam1 1080p60@PPC4）
  (* syn_peri_port = 0 *) input esc_clk,
  (* syn_peri_port = 0 *) input mipi_refclk_25m,
  (* syn_peri_port = 0 *) output pll_mipi_refclk_rstn,
  (* syn_peri_port = 0 *) output pll_csi_rstn,
  (* syn_peri_port = 0 *) output pll_csi2_rstn,     // pll_csi2（BL1）
  (* syn_peri_port = 0 *) output pll_ddr_rstn,
  (* syn_peri_port = 0 *) output pll_sys_rstn,

  (* syn_peri_port = 0 *) input ddr_inst_ARREADY_0,
  (* syn_peri_port = 0 *) input ddr_inst_ARREADY_1,
  (* syn_peri_port = 0 *) input ddr_inst_AWREADY_0,
  (* syn_peri_port = 0 *) input ddr_inst_AWREADY_1,
  (* syn_peri_port = 0 *) input [5:0] ddr_inst_BID_0,
  (* syn_peri_port = 0 *) input [5:0] ddr_inst_BID_1,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_BRESP_0,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_BRESP_1,
  (* syn_peri_port = 0 *) input ddr_inst_BVALID_0,
  (* syn_peri_port = 0 *) input ddr_inst_BVALID_1,
  (* syn_peri_port = 0 *) input ddr_inst_CFG_DONE,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_BUSY,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_CTRL_CKE,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_CMD_Q_ALMOST_FULL,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_DP_IDLE,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_INT,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_MEM_RST_VALID,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_CTRL_PORT_BUSY,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_REFRESH,
  (* syn_peri_port = 0 *) input [511:0] ddr_inst_RDATA_0,
  (* syn_peri_port = 0 *) input [511:0] ddr_inst_RDATA_1,
  (* syn_peri_port = 0 *) input [5:0] ddr_inst_RID_0,
  (* syn_peri_port = 0 *) input [5:0] ddr_inst_RID_1,
  (* syn_peri_port = 0 *) input ddr_inst_RLAST_0,
  (* syn_peri_port = 0 *) input ddr_inst_RLAST_1,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_RRESP_0,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_RRESP_1,
  (* syn_peri_port = 0 *) input ddr_inst_RVALID_0,
  (* syn_peri_port = 0 *) input ddr_inst_RVALID_1,
  (* syn_peri_port = 0 *) input ddr_inst_WREADY_0,
  (* syn_peri_port = 0 *) input ddr_inst_WREADY_1,
  (* syn_peri_port = 0 *) output [32:0] ddr_inst_ARADDR_0,
  (* syn_peri_port = 0 *) output [32:0] ddr_inst_ARADDR_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARAPCMD_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARAPCMD_1,
  (* syn_peri_port = 0 *) output [1:0] ddr_inst_ARBURST_0,
  (* syn_peri_port = 0 *) output [1:0] ddr_inst_ARBURST_1,
  (* syn_peri_port = 0 *) output [5:0] ddr_inst_ARID_0,
  (* syn_peri_port = 0 *) output [5:0] ddr_inst_ARID_1,
  (* syn_peri_port = 0 *) output [7:0] ddr_inst_ARLEN_0,
  (* syn_peri_port = 0 *) output [7:0] ddr_inst_ARLEN_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARLOCK_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARLOCK_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARQOS_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARQOS_1,
  (* syn_peri_port = 0 *) output [2:0] ddr_inst_ARSIZE_0,
  (* syn_peri_port = 0 *) output [2:0] ddr_inst_ARSIZE_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARSTN_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARSTN_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARVALID_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARVALID_1,
  (* syn_peri_port = 0 *) output [32:0] ddr_inst_AWADDR_0,
  (* syn_peri_port = 0 *) output [32:0] ddr_inst_AWADDR_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWALLSTRB_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWALLSTRB_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWAPCMD_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWAPCMD_1,
  (* syn_peri_port = 0 *) output [1:0] ddr_inst_AWBURST_0,
  (* syn_peri_port = 0 *) output [1:0] ddr_inst_AWBURST_1,
  (* syn_peri_port = 0 *) output [3:0] ddr_inst_AWCACHE_0,
  (* syn_peri_port = 0 *) output [3:0] ddr_inst_AWCACHE_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWCOBUF_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWCOBUF_1,
  (* syn_peri_port = 0 *) output [5:0] ddr_inst_AWID_0,
  (* syn_peri_port = 0 *) output [5:0] ddr_inst_AWID_1,
  (* syn_peri_port = 0 *) output [7:0] ddr_inst_AWLEN_0,
  (* syn_peri_port = 0 *) output [7:0] ddr_inst_AWLEN_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWLOCK_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWLOCK_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWQOS_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWQOS_1,
  (* syn_peri_port = 0 *) output [2:0] ddr_inst_AWSIZE_0,
  (* syn_peri_port = 0 *) output [2:0] ddr_inst_AWSIZE_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWVALID_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWVALID_1,
  (* syn_peri_port = 0 *) output ddr_inst_BREADY_0,
  (* syn_peri_port = 0 *) output ddr_inst_BREADY_1,
  (* syn_peri_port = 0 *) output ddr_inst_CFG_RESET,
  (* syn_peri_port = 0 *) output ddr_inst_CFG_SEL,
  (* syn_peri_port = 0 *) output ddr_inst_CFG_START,
  (* syn_peri_port = 0 *) output ddr_inst_RREADY_0,
  (* syn_peri_port = 0 *) output ddr_inst_RREADY_1,
  (* syn_peri_port = 0 *) output [511:0] ddr_inst_WDATA_0,
  (* syn_peri_port = 0 *) output [511:0] ddr_inst_WDATA_1,
  (* syn_peri_port = 0 *) output ddr_inst_WLAST_0,
  (* syn_peri_port = 0 *) output ddr_inst_WLAST_1,
  (* syn_peri_port = 0 *) output [63:0] ddr_inst_WSTRB_0,
  (* syn_peri_port = 0 *) output [63:0] ddr_inst_WSTRB_1,
  (* syn_peri_port = 0 *) output ddr_inst_WVALID_0,
  (* syn_peri_port = 0 *) output ddr_inst_WVALID_1,
  // MIPI TX peri pins

  (* syn_peri_port = 0 *) input dphy_tx2_WORD_CLKOUT_HS,
  (* syn_peri_port = 0 *) input dphy_tx2_PLL_UNLOCK,
  (* syn_peri_port = 0 *) input dphy_tx2_STOPSTATE_CLK,
  (* syn_peri_port = 0 *) input dphy_tx2_STOPSTATE_LAN0,
  (* syn_peri_port = 0 *) input dphy_tx2_STOPSTATE_LAN1,
  (* syn_peri_port = 0 *) input dphy_tx2_STOPSTATE_LAN2,
  (* syn_peri_port = 0 *) input dphy_tx2_STOPSTATE_LAN3,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_READY_ESC,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_READY_HS_LAN0,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_READY_HS_LAN1,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_READY_HS_LAN2,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_READY_HS_LAN3,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_ULPS_ACTIVE_CLK_NOT,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN0,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN1,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN2,
  (* syn_peri_port = 0 *) input dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN3,

  (* syn_peri_port = 0 *) output dphy_tx2_PLL_SSC_EN,
  (* syn_peri_port = 0 *) output dphy_tx2_RESET_N,
  (* syn_peri_port = 0 *) output [7:0] dphy_tx2_TX_DATA_ESC,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_LPDT_ESC,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_VALID_ESC,
  (* syn_peri_port = 0 *) output [3:0] dphy_tx2_TX_TRIGGER_ESC,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_ESC_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_ESC_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_ESC_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_ESC_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_HS,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_HS_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_HS_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_HS_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_REQUEST_HS_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_SKEW_CAL_HS_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_SKEW_CAL_HS_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_SKEW_CAL_HS_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_SKEW_CAL_HS_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_CLK,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_ESC_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_ESC_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_ESC_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_ESC_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_EXIT,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_EXIT_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_EXIT_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_EXIT_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_ULPS_EXIT_LAN3,
  (* syn_peri_port = 0 *) output [15:0] dphy_tx2_TX_DATA_HS_LAN0,
  (* syn_peri_port = 0 *) output [15:0] dphy_tx2_TX_DATA_HS_LAN1,
  (* syn_peri_port = 0 *) output [15:0] dphy_tx2_TX_DATA_HS_LAN2,
  (* syn_peri_port = 0 *) output [15:0] dphy_tx2_TX_DATA_HS_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_WORD_VALID_HS_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_WORD_VALID_HS_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_WORD_VALID_HS_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx2_TX_WORD_VALID_HS_LAN3,

  (* syn_peri_port = 0 *) input dphy_tx0_WORD_CLKOUT_HS,
  (* syn_peri_port = 0 *) input dphy_tx0_PLL_UNLOCK,
  (* syn_peri_port = 0 *) input dphy_tx0_STOPSTATE_CLK,
  (* syn_peri_port = 0 *) input dphy_tx0_STOPSTATE_LAN0,
  (* syn_peri_port = 0 *) input dphy_tx0_STOPSTATE_LAN1,
  (* syn_peri_port = 0 *) input dphy_tx0_STOPSTATE_LAN2,
  (* syn_peri_port = 0 *) input dphy_tx0_STOPSTATE_LAN3,
  (* syn_peri_port = 0 *) input dphy_tx0_TX_READY_ESC,
  (* syn_peri_port = 0 *) input dphy_tx0_TX_READY_HS_LAN0,
  (* syn_peri_port = 0 *) input dphy_tx0_TX_READY_HS_LAN1,
  (* syn_peri_port = 0 *) input dphy_tx0_TX_READY_HS_LAN2,
  (* syn_peri_port = 0 *) input dphy_tx0_TX_READY_HS_LAN3,
  (* syn_peri_port = 0 *) input dphy_tx0_TX_ULPS_ACTIVE_CLK_NOT,
  (* syn_peri_port = 0 *) input dphy_tx0_TX_ULPS_ACTIVE_NOT_LAN0,
  (* syn_peri_port = 0 *) input dphy_tx0_TX_ULPS_ACTIVE_NOT_LAN1,
  (* syn_peri_port = 0 *) input dphy_tx0_TX_ULPS_ACTIVE_NOT_LAN2,
  (* syn_peri_port = 0 *) input dphy_tx0_TX_ULPS_ACTIVE_NOT_LAN3,

  (* syn_peri_port = 0 *) output dphy_tx0_PLL_SSC_EN,
  (* syn_peri_port = 0 *) output dphy_tx0_RESET_N,
  (* syn_peri_port = 0 *) output [7:0] dphy_tx0_TX_DATA_ESC,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_LPDT_ESC,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_VALID_ESC,
  (* syn_peri_port = 0 *) output [3:0] dphy_tx0_TX_TRIGGER_ESC,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_REQUEST_ESC_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_REQUEST_ESC_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_REQUEST_ESC_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_REQUEST_ESC_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_REQUEST_HS,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_REQUEST_HS_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_REQUEST_HS_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_REQUEST_HS_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_REQUEST_HS_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_SKEW_CAL_HS_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_SKEW_CAL_HS_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_SKEW_CAL_HS_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_SKEW_CAL_HS_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_ULPS_CLK,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_ULPS_ESC_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_ULPS_ESC_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_ULPS_ESC_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_ULPS_ESC_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_ULPS_EXIT,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_ULPS_EXIT_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_ULPS_EXIT_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_ULPS_EXIT_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_ULPS_EXIT_LAN3,
  (* syn_peri_port = 0 *) output [15:0] dphy_tx0_TX_DATA_HS_LAN0,
  (* syn_peri_port = 0 *) output [15:0] dphy_tx0_TX_DATA_HS_LAN1,
  (* syn_peri_port = 0 *) output [15:0] dphy_tx0_TX_DATA_HS_LAN2,
  (* syn_peri_port = 0 *) output [15:0] dphy_tx0_TX_DATA_HS_LAN3,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_WORD_VALID_HS_LAN0,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_WORD_VALID_HS_LAN1,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_WORD_VALID_HS_LAN2,
  (* syn_peri_port = 0 *) output dphy_tx0_TX_WORD_VALID_HS_LAN3,

  // ---- MIPI CSI-2 RX (camera): DPHY RX0 hard macro pins (peri: dphy_rx0) ----
  // word clock from RX CLK lane (HS byte/word clock, stops when no stream)
  (* syn_peri_port = 0 *) input  dphy_rx0_clk_CLKOUT,
  // DPHY control (active-low resets)
  (* syn_peri_port = 0 *) output dphy_rx0_RESET_N,
  (* syn_peri_port = 0 *) output dphy_rx0_RST0_N,
  // clock lane status (debug observation)
  (* syn_peri_port = 0 *) input  dphy_rx0_STOPSTATE_CLK,
  (* syn_peri_port = 0 *) input  dphy_rx0_RX_CLK_ACTIVE_HS,
  // clock lane ULPS
  (* syn_peri_port = 0 *) input  dphy_rx0_ULPS_CLK_ACTIVEN,
  (* syn_peri_port = 0 *) input  dphy_rx0_ULPS_CLK_ENTER,
  // data lane escape clocks
  (* syn_peri_port = 0 *) input dphy_rx0_LP_CLK,
  (* syn_peri_port = 0 *) input dphy_rx0_ERR_SOT_HS_LAN0,
  (* syn_peri_port = 0 *) input dphy_rx0_ERR_SOT_HS_LAN1,
  (* syn_peri_port = 0 *) input dphy_rx0_ERR_SOT_HS_LAN2,
  (* syn_peri_port = 0 *) input dphy_rx0_ERR_SOT_HS_LAN3,
  (* syn_peri_port = 0 *) input dphy_rx0_ERR_CONTENTION_LP0,
  (* syn_peri_port = 0 *) input dphy_rx0_ERR_CONTENTION_LP1,


  (* syn_peri_port = 0 *) input  dphy_rx0_ESC_LAN0_CLK,
  (* syn_peri_port = 0 *) input  dphy_rx0_ESC_LAN1_CLK,
  (* syn_peri_port = 0 *) input  dphy_rx0_ESC_LAN2_CLK,
  (* syn_peri_port = 0 *) input  dphy_rx0_ESC_LAN3_CLK,
  (* syn_peri_port = 0 *) input [7:0] dphy_rx0_RX_DATA_ESC,
  (* syn_peri_port = 0 *) input dphy_rx0_RX_LPDT_ESC,
  (* syn_peri_port = 0 *) input [3:0] dphy_rx0_RX_TRIGGER_ESC,
  (* syn_peri_port = 0 *) input dphy_rx0_RX_VALID_ESC,

  // LP / escape / control errors
  (* syn_peri_port = 0 *) input  dphy_rx0_LINESTATE_LAN0_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx0_LINESTATE_LAN1_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx0_LINESTATE_LAN2_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx0_LINESTATE_LAN3_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx0_ESC_LAN0_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx0_ESC_LAN1_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx0_ESC_LAN2_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx0_ESC_LAN3_ERROR,
  // lane stop state (LP-11 idle indicator)
  (* syn_peri_port = 0 *) input  dphy_rx0_STOPSTATE_LAN0,
  (* syn_peri_port = 0 *) input  dphy_rx0_STOPSTATE_LAN1,
  (* syn_peri_port = 0 *) input  dphy_rx0_STOPSTATE_LAN2,
  (* syn_peri_port = 0 *) input  dphy_rx0_STOPSTATE_LAN3,
  // HS receive interface
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN0_VALID,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN1_VALID,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN2_VALID,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN3_VALID,
  (* syn_peri_port = 0 *) input  [15:0] dphy_rx0_HS_LAN0_DATA,
  (* syn_peri_port = 0 *) input  [15:0] dphy_rx0_HS_LAN1_DATA,
  (* syn_peri_port = 0 *) input  [15:0] dphy_rx0_HS_LAN2_DATA,
  (* syn_peri_port = 0 *) input  [15:0] dphy_rx0_HS_LAN3_DATA,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN0_SKEWCAL,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN1_SKEWCAL,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN2_SKEWCAL,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN3_SKEWCAL,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN0_SYNC,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN1_SYNC,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN2_SYNC,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN3_SYNC,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN0_SOTSYNC_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN1_SOTSYNC_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN2_SOTSYNC_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx0_HS_LAN3_SOTSYNC_ERROR,
  // data lane ULPS
  (* syn_peri_port = 0 *) input  dphy_rx0_ULPS_LAN0_ACTIVEN,
  (* syn_peri_port = 0 *) input  dphy_rx0_ULPS_LAN1_ACTIVEN,
  (* syn_peri_port = 0 *) input  dphy_rx0_ULPS_LAN2_ACTIVEN,
  (* syn_peri_port = 0 *) input  dphy_rx0_ULPS_LAN3_ACTIVEN,
  (* syn_peri_port = 0 *) input  dphy_rx0_ULPS_LAN0_ENTER,
  (* syn_peri_port = 0 *) input  dphy_rx0_ULPS_LAN1_ENTER,
  (* syn_peri_port = 0 *) input  dphy_rx0_ULPS_LAN2_ENTER,
  (* syn_peri_port = 0 *) input  dphy_rx0_ULPS_LAN3_ENTER,

  // ---- MIPI CSI-2 RX (camera 1): DPHY RX0 hard macro pins (peri: dphy_rx2) ----
  // word clock from RX CLK lane (HS byte/word clock, stops when no stream)
  (* syn_peri_port = 0 *) input  dphy_rx2_clk_CLKOUT,
  // DPHY control (active-low resets)
  (* syn_peri_port = 0 *) output dphy_rx2_RESET_N,
  (* syn_peri_port = 0 *) output dphy_rx2_RST0_N,
  // clock lane status (debug observation)
  (* syn_peri_port = 0 *) input  dphy_rx2_STOPSTATE_CLK,
  (* syn_peri_port = 0 *) input  dphy_rx2_RX_CLK_ACTIVE_HS,
  // clock lane ULPS
  (* syn_peri_port = 0 *) input  dphy_rx2_ULPS_CLK_ACTIVEN,
  (* syn_peri_port = 0 *) input  dphy_rx2_ULPS_CLK_ENTER,
  // data lane escape clocks
  (* syn_peri_port = 0 *) input dphy_rx2_LP_CLK,
  (* syn_peri_port = 0 *) input dphy_rx2_ERR_SOT_HS_LAN0,
  (* syn_peri_port = 0 *) input dphy_rx2_ERR_SOT_HS_LAN1,
  (* syn_peri_port = 0 *) input dphy_rx2_ERR_SOT_HS_LAN2,
  (* syn_peri_port = 0 *) input dphy_rx2_ERR_SOT_HS_LAN3,
  (* syn_peri_port = 0 *) input dphy_rx2_ERR_CONTENTION_LP0,
  (* syn_peri_port = 0 *) input dphy_rx2_ERR_CONTENTION_LP1,


  (* syn_peri_port = 0 *) input  dphy_rx2_ESC_LAN0_CLK,
  (* syn_peri_port = 0 *) input  dphy_rx2_ESC_LAN1_CLK,
  (* syn_peri_port = 0 *) input  dphy_rx2_ESC_LAN2_CLK,
  (* syn_peri_port = 0 *) input  dphy_rx2_ESC_LAN3_CLK,
  (* syn_peri_port = 0 *) input [7:0] dphy_rx2_RX_DATA_ESC,
  (* syn_peri_port = 0 *) input dphy_rx2_RX_LPDT_ESC,
  (* syn_peri_port = 0 *) input [3:0] dphy_rx2_RX_TRIGGER_ESC,
  (* syn_peri_port = 0 *) input dphy_rx2_RX_VALID_ESC,

  // LP / escape / control errors
  (* syn_peri_port = 0 *) input  dphy_rx2_LINESTATE_LAN0_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx2_LINESTATE_LAN1_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx2_LINESTATE_LAN2_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx2_LINESTATE_LAN3_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx2_ESC_LAN0_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx2_ESC_LAN1_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx2_ESC_LAN2_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx2_ESC_LAN3_ERROR,
  // lane stop state (LP-11 idle indicator)
  (* syn_peri_port = 0 *) input  dphy_rx2_STOPSTATE_LAN0,
  (* syn_peri_port = 0 *) input  dphy_rx2_STOPSTATE_LAN1,
  (* syn_peri_port = 0 *) input  dphy_rx2_STOPSTATE_LAN2,
  (* syn_peri_port = 0 *) input  dphy_rx2_STOPSTATE_LAN3,
  // HS receive interface
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN0_VALID,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN1_VALID,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN2_VALID,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN3_VALID,
  (* syn_peri_port = 0 *) input  [15:0] dphy_rx2_HS_LAN0_DATA,
  (* syn_peri_port = 0 *) input  [15:0] dphy_rx2_HS_LAN1_DATA,
  (* syn_peri_port = 0 *) input  [15:0] dphy_rx2_HS_LAN2_DATA,
  (* syn_peri_port = 0 *) input  [15:0] dphy_rx2_HS_LAN3_DATA,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN0_SKEWCAL,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN1_SKEWCAL,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN2_SKEWCAL,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN3_SKEWCAL,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN0_SYNC,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN1_SYNC,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN2_SYNC,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN3_SYNC,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN0_SOTSYNC_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN1_SOTSYNC_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN2_SOTSYNC_ERROR,
  (* syn_peri_port = 0 *) input  dphy_rx2_HS_LAN3_SOTSYNC_ERROR,
  // data lane ULPS
  (* syn_peri_port = 0 *) input  dphy_rx2_ULPS_LAN0_ACTIVEN,
  (* syn_peri_port = 0 *) input  dphy_rx2_ULPS_LAN1_ACTIVEN,
  (* syn_peri_port = 0 *) input  dphy_rx2_ULPS_LAN2_ACTIVEN,
  (* syn_peri_port = 0 *) input  dphy_rx2_ULPS_LAN3_ACTIVEN,
  (* syn_peri_port = 0 *) input  dphy_rx2_ULPS_LAN0_ENTER,
  (* syn_peri_port = 0 *) input  dphy_rx2_ULPS_LAN1_ENTER,
  (* syn_peri_port = 0 *) input  dphy_rx2_ULPS_LAN2_ENTER,
  (* syn_peri_port = 0 *) input  dphy_rx2_ULPS_LAN3_ENTER,


  (* syn_peri_port = 0 *) input uart_0_rxd,
  (* syn_peri_port = 0 *) output uart_0_txd,

  // ---- Camera I2C (IMX415): open-drain emulated GPIOs (peri: cam_scl/cam_sda) ----
  (* syn_peri_port = 0 *) output cam_0_en,
  (* syn_peri_port = 0 *) input  cam_0_scl_i,
  (* syn_peri_port = 0 *) output cam_0_scl_o,
  (* syn_peri_port = 0 *) output cam_0_scl_oe,
  (* syn_peri_port = 0 *) input  cam_0_sda_i,
  (* syn_peri_port = 0 *) output cam_0_sda_o,
  (* syn_peri_port = 0 *) output cam_0_sda_oe,

  (* syn_peri_port = 0 *) output cam_1_en,
  (* syn_peri_port = 0 *) input  cam_1_scl_i,
  (* syn_peri_port = 0 *) output cam_1_scl_o,
  (* syn_peri_port = 0 *) output cam_1_scl_oe,
  (* syn_peri_port = 0 *) input  cam_1_sda_i,
  (* syn_peri_port = 0 *) output cam_1_sda_o,
  (* syn_peri_port = 0 *) output cam_1_sda_oe

);

    //-------------------------------------------------------------------------
    // 全局异步复位
    //-------------------------------------------------------------------------
     //power-up self-reset（cnt 初值 0：FPGA 上电即 0，仿真避免 x 死锁）
    reg [7:0] cnt = 8'h0;
    reg i_arstn;
    always @(posedge i_clk_27m) begin
        if (cnt == 8'hff) begin
            cnt    <= 8'hff;
            i_arstn <= 1'b1;
        end else begin
            cnt    <= cnt + 1'b1;
            i_arstn <= 1'b0;
        end
    end

    // PLL resets (active high release, no system reset)
    // pll_ddr 复位口已拉出（peri reset_name="pll_ddr_rstn"，对齐 gmsl 工程）
    assign pll_mipi_refclk_rstn = i_arstn;
    assign pll_csi_rstn         = i_arstn;
    assign pll_csi2_rstn        = i_arstn;
    assign pll_ddr_rstn         = i_arstn;
    assign pll_sys_rstn         = i_arstn;

    wire sys_clk_100m_rstn, sys_clk_200m_rstn;

    reset_ctrl #(.NUM_RST(1), .IN_RST_ACTIVE(1'b0), .OUT_RST_ACTIVE(1'b0)) u_rx_rst_100m (
        .i_arst (pll_sys_locked), .i_clk (sys_clk_100m),  .o_srst (sys_clk_100m_rstn)
    );
    reset_ctrl #(.NUM_RST(1), .IN_RST_ACTIVE(1'b0), .OUT_RST_ACTIVE(1'b0)) u_rx_rst_pixel (
        .i_arst (pll_sys_locked), .i_clk (sys_clk_200m), .o_srst (sys_clk_200m_rstn)
    );



    // SoC GPIO0 write（v4.11 起 cam_en 不再由固件控制——w_gpio_write 保
    // 留仅作 SoC 端口落点，综合器剪除悬空扇出）
    wire [3:0] w_gpio_write;

    // ---- Camera I2C open-drain pads（v4.11 RTL 接管，doc/cam-i2c-rtl-init-plan.md §4.4）----
    //   驱动源：SoC I2C（SaxonSoc "write" 语义 = 0 驱动低/1 释放）->
    //   cam_i2c_init pad_o（1=释放/0=驱动低，oe = ~pad_o）。SoC I2C
    //   write 线解耦（固件不再配置传感器），read 线保留作总线活动
    //   debug 观测（Q1 评审定案：固件去 I2C 职能留观测）。
    //   错峰 start 链（Q4）：cam0 上电自然出沿（start 接 1'b1，复位释
    //   放后沿检测打出单拍），cam1 start 接 cam0 cam_init_done 电平。
    wire        cam0_scl_o, cam0_sda_o, cam0_en, cam0_i2c_done;
    wire        cam1_scl_o, cam1_sda_o, cam1_en, cam1_i2c_done;
    wire w_i2c_0_scl_write, w_i2c_0_sda_write;      // SoC 侧解耦残留（悬空）
    wire w_i2c_0_scl_read,  w_i2c_0_sda_read;
    wire w_i2c_1_scl_write, w_i2c_1_sda_write;
    wire w_i2c_1_scl_read,  w_i2c_1_sda_read;

    assign w_i2c_0_scl_read = cam_0_scl_i;
    assign cam_0_scl_o      = 1'b0;
    assign cam_0_scl_oe     = ~cam0_scl_o;
    assign w_i2c_0_sda_read = cam_0_sda_i;
    assign cam_0_sda_o      = 1'b0;
    assign cam_0_sda_oe     = ~cam0_sda_o;

    assign w_i2c_1_scl_read = cam_1_scl_i;
    assign cam_1_scl_o      = 1'b0;
    assign cam_1_scl_oe     = ~cam1_scl_o;
    assign w_i2c_1_sda_read = cam_1_sda_i;
    assign cam_1_sda_o      = 1'b0;
    assign cam_1_sda_oe     = ~cam1_sda_o;
    // cam_en pad 接管（v4.11c 板级教训：旧 SoC GPIO0.bit0 路径拆除后漏接
    // 新源，传感器不上电 -> I2C 全 NACK。cam_i2c_init 是唯一驱动源）
    assign cam_0_en         = cam0_en;
    assign cam_1_en         = cam1_en;


    //-------------------------------------------------------------------------
    // LPDDR 配置 FSM。板测迭代记录：
    //  v1：256 拍即发 CFG_START，不等 lock        -> cfg_ok=0（训练未完成，
    //      当时 peri 为 post=2/out=20/lclk 的错误 PLL 配置）
    //  v2：等 pll_ddr_locked + 2^21 拍，peri 改 gmsl(out=28) -> lock=0，
    //      FSM 被 lock 门死，训练根本没发——误诊：lock 门控反成死锁
    //  v3（本版）：解除 lock 门控（复位回 sys_clk_200m_rstn，保留 2^21 拍
    //      ≈10.5ms 等待覆盖 PLL lock）；peri pll_ddr 全参数对齐 ori 工程
    //      （用户确认 DDR 接口工作）：post=2、CLKOUT0 out_div=20（3.33MHz）、
    //      conn=gclk（原 lclk 系唯一路由差异）、reset_name=""（PLL 自由运行，
    //      RTL 删 pll_ddr_rstn 口）。DIAG11 加 cfg_st/done_raw 观测定位。
    //  v3 板测：训练链全通（lock=1 st=3 raw=1 cfg_ok=1）——此时 peri 为 ori
    //      配置（post=2/out=20）。done=0 定位为 checker start 极性反
    //      （.start(~mc_srstn)），已修。
    //  v4（本版，用户指令）：peri pll_ddr 改对齐 gmsl 工程：post=1、
    //      CLKOUT0 out_div=28（4.762MHz）、拉出 pll_ddr_rstn 复位口接
    //      i_arstn。注：v2 板测的 lock=0 系 cam1 全零行假读数，gmsl 配置
    //      真实锁定状态本轮才首次可观测。
    //  v5（本版，用户指令）：FSM 复位门控回接 pll_ddr_locked——lock 之后
    //      才开始 2^21 拍计数并进入 CFG 时序（mem_test.v 同构）。lock 已在
    //      本板实测可读可锁（v3 板测 lock=1），门控安全。
    //-------------------------------------------------------------------------
    localparam [1:0] IDLE      = 2'b00,
                     CFG_START = 2'b01,
                     CFG_DONE  = 2'b11;

    reg  [1:0]  cfg_st, cfg_next;
    reg  [20:0] cfg_count;
    wire        ddr_cfg_ok;

    assign ddr_cfg_ok = (cfg_st == CFG_DONE);

    // DDR PLL 锁定后才开跑（mem_test.v 同构：复位 = sys 复位释放 & lock）
    wire cfg_fsm_rstn = sys_clk_200m_rstn & pll_ddr_locked;

    always_ff @(posedge sys_clk_200m or negedge cfg_fsm_rstn) begin
        if (~cfg_fsm_rstn) begin
            cfg_st    <= IDLE;
            cfg_count <= 21'h0;
        end else begin
            cfg_st <= cfg_next;
            if (cfg_st == IDLE)
                cfg_count <= cfg_count + 1'b1;
            else
                cfg_count <= 21'h0;
        end
    end

    always_comb begin
        cfg_next = cfg_st;
        case (cfg_st)
            IDLE: begin
                if (&cfg_count)
                    cfg_next = CFG_START;
                else
                    cfg_next = IDLE;
            end
            CFG_START: begin
                if (ddr_inst_CFG_DONE)
                    cfg_next = CFG_DONE;
                else
                    cfg_next = CFG_START;
            end
            CFG_DONE: cfg_next = CFG_DONE;
            default:  cfg_next = IDLE;
        endcase
    end

    assign ddr_inst_CFG_START = (cfg_st != IDLE);
    assign ddr_inst_CFG_RESET = (cfg_st == IDLE);
    assign ddr_inst_CFG_SEL   = 1'b0;

    //-------------------------------------------------------------------------
    // DDR 自检（阶段 0，2026-10-18）：DDR_MEMTEST=1 时 ddr_memcheck 接管
    // target0，对帧乒乓区域（0x0~0x02000000，2Gb=256MB）做"行突发写→读回
    // 比对"，结果经 cam0 的 CSR DIAG11(0x2C) 读回。CFG FSM 已在板上验证
    //（照常初始化硬核）；checker 移植自 EvoVerse ddr-memtest（同器件参考
    // 设计），修正其 3 处 bug（fail 洗除/wdata 位宽/握手空拍），burst 形态
    // 改为 120 beat×64B = 一行 UYVY，与 frame_writer/reader 一致。
    // DDR_MEMTEST=0 时双口回全 idle（正式视频通路接入后的稳态）。
    // ARSTN_0/1 两模式相同，保持在 generate 外驱动。
    //-------------------------------------------------------------------------
    localparam FRAME_WRITER = 1;    // Phase 4（2026-10-21）：正式回放链路。
                                    // writer@port0(200M) + reader@port1
                                    // (pixel_clk 148.5M，v4 换域)
    localparam DDR_MEMTEST  = 0;    // 阶段 0 读写自检回归开关
    localparam DDR_P1_148   = 0;    // Phase 0 换绑验证分支（已完成退役）

    wire        mc_done, mc_fail;
    wire [15:0] mc_err_cnt;
    wire [3:0]  mc_state;
    wire        mc_srstn;
    wire [31:0] ddr_diag;

    // frame_writer 状态（-> CSR DIAG12/13）
    wire [31:0] fw_diag, fw_diag2;
    wire [31:0] fw_dbg2;
    wire [15:0] fw_line_cnt, fw_frame_cnt, fw_pad_cnt, fw_ovf_cnt;
    wire [3:0]  fw_state;
    wire [63:0] cam0_cap_tdata;
    wire        cam0_cap_tvalid, cam0_cap_tlast;
    wire [2:0]  cam0_cap_tuser;
    wire        cam0_fw_rstn;               // aclk 域复位（& mc_srstn 后给 fw/rd）
    wire        cam0_fw_flush;              // v4.10c3c 源切换 writer 账本重置
    wire        cam0_rd_flush_fire;         // v4.10c3f reader flush 执行拍
                                            //（透传回 u_cam_0 触发 tx 域复位）
    wire        cam0_line_tick;             // u_cam_0 行节拍输出（tx 域，观测预留）
    wire        cam0_pat_tick;              // u_cam_0 行节拍输出（aclk 域，reader 用）
    wire        cam0_disp_open;             // u_cam_0 显示开帧脉冲（reader 节拍门）
    wire        disp_line_tick;             // v4：disp_timing 同源槽节拍
    wire        disp_line_room;             // v4.4：显示行缓冲空间（发射门）
    wire        disp_sof;                   // v4.9：显示帧界（reader 授权锚）
    wire        disp_stall;                 // v4.9：显示断粮（reader 救援授权）
                                            //（-> u_rd.line_tick，Phase 4）
    // frame_reader 回放流（g_frame_writer 内 u_rd 产出，demosaic 前直入，
    // v3 显示唯一来源；其他配置分支 tie-off）
    wire [63:0] cam0_rd_tdata;
    wire        cam0_rd_tvalid, cam0_rd_tlast;
    wire [2:0]  cam0_rd_tuser;
    // 读链路诊断（-> u_cam_0 CSR DIAG14/15；其他分支 tie-off）
    wire [31:0] rd_diag14, rd_diag15;
    wire [31:0] rd_diag19;              // v4：reader drop/repeat（DIAG19 复用）

    // ---- cam1（1080p60）DDR 回放链顶层连线（阶段5，cam1-ddr-replay-plan §4）----
    // u_cam_1 输出 -> u_fw1（200M 写域）；u_rd1 回放流 -> u_cam_1 demosaic 前；
    // 显示侧行节拍/帧界/断粮由 u_cam_1 内 disp_timing 提供（37.125M 域）；
    // 读 AXI 经 axi_rd_cdc（37.125→148.5）入 u_rd_arb S0（阶段4 已挂空位）。
    wire [63:0] cam1_cap_tdata;
    wire        cam1_cap_tvalid, cam1_cap_tlast;
    wire [2:0]  cam1_cap_tuser;
    wire        cam1_fw_rstn;               // aclk 域复位（& mc_srstn 后给 fw1）
    wire        cam1_fw_flush;              // v4.10c3c 源切换 writer 账本重置
    wire        cam1_rd_flush_fire;         // reader flush 执行拍（-> tx 域复位）
    wire        cam1_disp_line_tick;        // u_cam_1 显示槽节拍（37.125M）
    wire        cam1_disp_line_room;        // -> u_rd1 发射门节流
    wire        cam1_disp_sof;              // -> u_rd1 授权锚
    wire        cam1_disp_stall;            // -> u_rd1 救援授权
    wire [63:0] cam1_rd_tdata;              // u_rd1 回放流 -> u_cam_1
    wire        cam1_rd_tvalid, cam1_rd_tlast;
    wire [2:0]  cam1_rd_tuser;
    // cam1 诊断（-> u_cam_1 CSR DIAG12/13/14/15/19/20；非 FRAME_WRITER 分支 tie 0）
    wire [31:0] cam1_fw_diag, cam1_fw_diag2, cam1_fw_dbg2;
    wire [31:0] cam1_rd_diag14, cam1_rd_diag15, cam1_rd_diag19;
    // 回放域复位线：g_frame_writer 块内 reset_ctrl 驱动，顶层 u_cam_0/u_cam_1
    // 端口引用——必须顶层声明（块内声明对 endgenerate 后的作用域不可见，
    // 否则实例端口落到隐式悬空 wire，复位链断开，efx_map VERI-2561）
    wire        rd_rstn_148;                // cam0 读域（pixel_clk 148.5M）
    wire        rd_rstn_1080;               // cam1 读域（pixel_clk_1080 37.125M）

    assign ddr_inst_ARSTN_0 = ddr_cfg_ok;
    assign ddr_inst_ARSTN_1 = ddr_cfg_ok;

    // CFG 完成前保持 checker 复位，完成后同步释放（CYCLE=4 防亚稳窗）
    reset_ctrl #(.NUM_RST(1), .IN_RST_ACTIVE(1'b1), .OUT_RST_ACTIVE(1'b0), .CYCLE(4))
    u_mc_rst (
        .i_arst (~ddr_cfg_ok), .i_clk (sys_clk_200m), .o_srst (mc_srstn)
    );

    generate if (FRAME_WRITER) begin : g_frame_writer

        // v3 读链路连线（回放流直出 camera_path demosaic 前链路）
        wire        fw_par;                 // writer 填充基址（reader 帧请求沿）
        wire        fw_frame_done;          // v3：帧发布单拍（200M 域；2FF 送
                                            // 148.5M 显示域，Phase 4 集成接线）
        wire [11:0] fw_line;                // writer 帧内行进度
        // 读链路诊断（-> CSR DIAG14/15）
        wire [15:0] rd_frame_cnt, rd_err;
        wire [11:0] rd_line_cnt;
        wire [3:0]  rd_state;
        wire [31:0] rd_fr_cnt;

        // RAW10 行流 -> DDR 帧写入（v2 单钟 aclk；一行 4800B = 75 word =
        // 64+11 两 burst，帧乒乓 A/B，整帧或全无）
        //
        // ---- 阶段3（cam1 计划 §4）：写侧经自研 axi_wr_arb 2→1 ----
        // u_fw AW/W/B 改接仲裁 S1（cam0）；S0=cam1 暂不使能（阶段5）。
        // M 口直驱 DDR target0 写口。同在 sys_clk_200m，零 CDC。
        wire        fw_awvalid, fw_awready;
        wire [32:0] fw_awaddr;
        wire [7:0]  fw_awlen;
        wire [2:0]  fw_awsize;
        wire [1:0]  fw_awburst;
        wire [5:0]  fw_awid;
        wire [3:0]  fw_awqos, fw_awcache;
        wire        fw_awlock;
        wire        fw_wvalid, fw_wready;
        wire [511:0] fw_wdata;
        wire [63:0]  fw_wstrb;
        wire        fw_wlast;
        wire        fw_bvalid, fw_bready;
        wire [1:0]  fw_bresp;
        wire [5:0]  fw_bid;
        wire        fw_awcobuf, fw_awapcmd, fw_awallstrb;   // 恒 0（u_fw 复位段）
        // S0 = cam1 u_fw1（阶段5 使能；同在 sys_clk_200m，零 CDC）
        wire        fw1_awvalid, fw1_awready;
        wire [32:0] fw1_awaddr;
        wire [7:0]  fw1_awlen;
        wire [2:0]  fw1_awsize;
        wire [1:0]  fw1_awburst;
        wire [5:0]  fw1_awid;
        wire [3:0]  fw1_awqos, fw1_awcache;
        wire        fw1_awlock;
        wire        fw1_wvalid, fw1_wready;
        wire [511:0] fw1_wdata;
        wire [63:0]  fw1_wstrb;
        wire        fw1_wlast;
        wire        fw1_bvalid, fw1_bready;
        wire [1:0]  fw1_bresp;
        wire [5:0]  fw1_bid;
        wire        fw1_awcobuf, fw1_awapcmd, fw1_awallstrb;   // 恒 0（u_fw1 复位段）
        wire [68:0] wr_arb_dbg;                                // 诊断预留
        // S0 = cam1_rd 经 axi_rd_cdc（s=37.125M / m=148.5M；m 侧接本仲裁）
        wire        cdc1_m_arvalid, cdc1_m_arready;
        wire [32:0] cdc1_m_araddr;
        wire [7:0]  cdc1_m_arlen;
        wire [2:0]  cdc1_m_arsize;
        wire [1:0]  cdc1_m_arburst;
        wire [5:0]  cdc1_m_arid;
        wire [3:0]  cdc1_m_arqos;
        wire [3:0]  cdc1_m_arcache;
        wire        cdc1_m_arlock;
        wire        cdc1_m_rvalid, cdc1_m_rready;
        wire [511:0] cdc1_m_rdata;
        wire [1:0]  cdc1_m_rresp;
        wire        cdc1_m_rlast;
        wire [5:0]  cdc1_m_rid;
        wire [68:0] rd_arb_dbg;                             // 诊断预留
        frame_writer #(
            .VACT    (16'd2160),            // 4K 有效行
            .FRAME_A (33'h0_0000_0000),
            .FRAME_B (33'h0_0200_0000)      // 与 u_rd 同布局（行槽 8KB）；
                                            // v4.10c3k：B=0x1100_0000 超出
                                            // 2Gb(256MB) 器件地址 [27:0]，
                                            // bit28 被硬核剥离 => 回绕
                                            // 0x0100_0000 = A 帧行 2048 处，
                                            // B 头 112 行与 A 尾 112 行地址
                                            // 竞态 = 底部闪区根因。B 移至
                                            // 32MB 处（A 帧占 0..17.7MB）
        ) u_fw (
            .aclk          (sys_clk_200m),  // 与 raw 源同钟（v2 零 CDC）
            .rstn          (cam0_fw_rstn & mc_srstn),   // 系统复位 & DDR CFG
                                                        // 完成（源切换不复位
                                                        // fw/rd，见 top_cam
                                                        // fw_rstn 块注释）
            .flush_i       (cam0_fw_flush), // v4.10c3c 源切换账本重置
                                            //（仅 drain 空闲拍执行）
            .s_axis_tdata  (cam0_cap_tdata),
            .s_axis_tvalid (cam0_cap_tvalid),
            .s_axis_tlast  (cam0_cap_tlast),
            .s_axis_tuser  (cam0_cap_tuser),

            .awid      (fw_awid),
            .awaddr    (fw_awaddr),
            .awlen     (fw_awlen),
            .awsize    (fw_awsize),
            .awburst   (fw_awburst),
            .awcache   (fw_awcache),
            .awlock    (fw_awlock),
            .awvalid   (fw_awvalid),
            .awcobuf   (fw_awcobuf),
            .awapcmd   (fw_awapcmd),
            .awallstrb (fw_awallstrb),
            .awqos     (fw_awqos),
            .awready   (fw_awready),
            .wdata     (fw_wdata),
            .wstrb     (fw_wstrb),
            .wlast     (fw_wlast),
            .wvalid    (fw_wvalid),
            .wready    (fw_wready),
            .bid       (fw_bid),
            .bvalid    (fw_bvalid),
            .bready    (fw_bready),

            .line_cnt  (fw_line_cnt),
            .frame_cnt (fw_frame_cnt),
            .pad_cnt   (fw_pad_cnt),
            .ovf_cnt   (fw_ovf_cnt),
            .dbg_state (fw_state),
            .wr_par    (fw_par),
            .wr_line   (fw_line),
            .wr_frame_done_o (fw_frame_done),  // v3：帧发布脉冲（Phase 4 接 2FF）
            // .wr_perf 不再引出（DIAG16 写口性能退役，2026-10-19 dbg 清理）
            .fw_dbg2   (fw_dbg2)
        );

        //---------------------------------------------------------------------
        // 阶段3：自研写口 2→1 仲裁（doc/arbiter.md v1.2，S1-S6 冻结）。
        // RR1 复位 last=0 首争用授 S1=cam0；事务级锁定 + 单 outstanding。
        // 复位策略（规格 §6）：仅上电复位树 mc_srstn（= DDR CFG 完成），
        // 源切换/flush 永不复位本模块——与 u_fw 的 cam0_fw_rstn 区分。
        //---------------------------------------------------------------------
        axi_wr_arb u_wr_arb (
            .clk  (sys_clk_200m),
            .rstn (mc_srstn),

            // S1 = cam0 u_fw
            .s1_awvalid (fw_awvalid),  .s1_awready (fw_awready),
            .s1_awaddr  (fw_awaddr),   .s1_awlen   (fw_awlen),
            .s1_awsize  (fw_awsize),   .s1_awburst (fw_awburst),
            .s1_awid    (fw_awid),     .s1_awqos   (fw_awqos),
            .s1_awcache (fw_awcache),  .s1_awlock  (fw_awlock),
            .s1_wvalid  (fw_wvalid),   .s1_wready  (fw_wready),
            .s1_wdata   (fw_wdata),    .s1_wstrb   (fw_wstrb),
            .s1_wlast   (fw_wlast),
            .s1_bvalid  (fw_bvalid),   .s1_bready  (fw_bready),
            .s1_bresp   (fw_bresp),    .s1_bid     (fw_bid),

            // S0 = cam1 u_fw1（阶段5 使能）
            .s0_awvalid (fw1_awvalid),  .s0_awready (fw1_awready),
            .s0_awaddr  (fw1_awaddr),   .s0_awlen   (fw1_awlen),
            .s0_awsize  (fw1_awsize),   .s0_awburst (fw1_awburst),
            .s0_awid    (fw1_awid),     .s0_awqos   (fw1_awqos),
            .s0_awcache (fw1_awcache),  .s0_awlock  (fw1_awlock),
            .s0_wvalid  (fw1_wvalid),   .s0_wready  (fw1_wready),
            .s0_wdata   (fw1_wdata),    .s0_wstrb   (fw1_wstrb),
            .s0_wlast   (fw1_wlast),
            .s0_bvalid  (fw1_bvalid),   .s0_bready  (fw1_bready),
            .s0_bresp   (fw1_bresp),    .s0_bid     (fw1_bid),

            // M → DDR target0 写口
            .m_awvalid  (ddr_inst_AWVALID_0),  .m_awready  (ddr_inst_AWREADY_0),
            .m_awaddr   (ddr_inst_AWADDR_0),   .m_awlen    (ddr_inst_AWLEN_0),
            .m_awsize   (ddr_inst_AWSIZE_0),   .m_awburst  (ddr_inst_AWBURST_0),
            .m_awid     (ddr_inst_AWID_0),     .m_awqos    (ddr_inst_AWQOS_0),
            .m_awcache  (ddr_inst_AWCACHE_0),  .m_awlock   (ddr_inst_AWLOCK_0),
            .m_wvalid   (ddr_inst_WVALID_0),   .m_wready   (ddr_inst_WREADY_0),
            .m_wdata    (ddr_inst_WDATA_0),    .m_wstrb    (ddr_inst_WSTRB_0),
            .m_wlast    (ddr_inst_WLAST_0),
            .m_bvalid   (ddr_inst_BVALID_0),   .m_bready   (ddr_inst_BREADY_0),
            .m_bresp    (ddr_inst_BRESP_0),    .m_bid      (ddr_inst_BID_0),

            .dbg (wr_arb_dbg)
        );

        // Efinity 专有写侧边带：u_fw 恒 0（frame_writer 复位段驱动后不再
        // 变），仲裁器不透传——DDR 侧直接 tie
        assign ddr_inst_AWCOBUF_0   = 1'b0;
        assign ddr_inst_AWAPCMD_0   = 1'b0;
        assign ddr_inst_AWALLSTRB_0 = 1'b0;

        //---------------------------------------------------------------------
        // v4（架构 v4，SPEC-001）：DDR RAW10 帧回放读链路（Phase 4 集成：
        // reader 整体 @ pixel_clk 148.5M = DDR ACLK_1，Phase 0 已证硬核
        // 接受双异步端口时钟；line_tick = disp_timing v2 同源槽节拍——
        // 显示时序唯一发生源 R1，reader 槽节拍与显示时序零偏差）。
        //
        //   帧握手跨域 toggle 方案（Phase 2 记录：200M 单拍直采 148.5M 有
        //   丢失风险）：源域翻转 -> 目标域 2FF -> 异或还原单拍。bank 电平
        //   2FF 直采（慢变）。drop/repeat 帧级仲裁在模块内
        //   （alg-bank-handoff），FRAME_TICKS=2250（D6）。读通道走 DDR
        //   port 1：与 writer 的 port 0 写口物理隔离。
        //---------------------------------------------------------------------
        // 148.5M 域复位：DDR CFG 完成后同步释放（与 200M 侧 mc_srstn 同款）
        // rd_rstn_148 于顶层声明（u_cam_0 端口跨作用域引用）
        reset_ctrl #(.NUM_RST(1), .IN_RST_ACTIVE(1'b1), .OUT_RST_ACTIVE(1'b0), .CYCLE(4))
        u_rd_rst_148 (
            .i_arst (~ddr_cfg_ok), .i_clk (pixel_clk), .o_srst (rd_rstn_148)
        );

        reg  tog200;
        reg [2:0] tog148;
        reg [1:0] par148;
        always @(posedge sys_clk_200m or negedge mc_srstn)
            if (!mc_srstn) tog200 <= 1'b0;
            else if (fw_frame_done) tog200 <= ~tog200;
        always @(posedge pixel_clk or negedge rd_rstn_148)
            if (!rd_rstn_148) begin
                tog148 <= 3'b000;
                par148 <= 2'b00;
            end else begin
                tog148 <= {tog148[1:0], tog200};
                par148 <= {par148[0], fw_par};
            end
        wire fw_done_148 = tog148[1] ^ tog148[2];   // 还原单拍
        wire fw_par_148  = par148[1];               // 慢变电平直采

        //---------------------------------------------------------------------
        // 阶段4：自研读口 2→1 仲裁（doc/arbiter.md v1.2 §4.2，S1-S6 冻结）。
        // RR1 复位 last=0 首争用授 S1=cam0；事务级锁定 + 单 outstanding；
        // R = 半缓冲 skid 1:2 demux，读锁释放 = 末拍宿侧握手（§5.2 修正）。
        // 全口 148.5M 同钟（ACLK_1 = pixel_clk，Phase 0 已证）；cam1 路径的
        // 37.125M→148.5M CDC 由 axi_rd_cdc 承担（阶段5 接入 S0）。
        // 复位策略（§6）：仅 rd_rstn_148（DDR CFG 完成树），flush 永不复位。
        //---------------------------------------------------------------------
        wire        rd_arvalid, rd_arready, rd_arlock;
        wire [32:0] rd_araddr;
        wire [7:0]  rd_arlen;
        wire [2:0]  rd_arsize;
        wire [1:0]  rd_arburst;
        wire [5:0]  rd_arid;
        wire [3:0]  rd_arqos;
        wire        rd_rvalid, rd_rready, rd_rlast;
        wire [511:0] rd_rdata;
        wire [1:0]  rd_rresp;
        wire [5:0]  rd_rid;

        axi_rd_arb u_rd_arb (
            .clk  (pixel_clk),
            .rstn (rd_rstn_148),

            // S1 = cam0 u_rd
            .s1_arvalid (rd_arvalid),  .s1_arready (rd_arready),
            .s1_araddr  (rd_araddr),   .s1_arlen   (rd_arlen),
            .s1_arsize  (rd_arsize),   .s1_arburst (rd_arburst),
            .s1_arid    (rd_arid),     .s1_arqos   (rd_arqos),
            .s1_arcache (4'h0),        .s1_arlock  (rd_arlock),
            .s1_rvalid  (rd_rvalid),   .s1_rready  (rd_rready),
            .s1_rdata   (rd_rdata),
            .s1_rresp   (rd_rresp),    .s1_rlast   (rd_rlast),
            .s1_rid     (rd_rid),

            // S0 = cam1_rd_cdc m 侧（阶段5 使能；s 侧 37.125M = u_rd1）
            .s0_arvalid (cdc1_m_arvalid),  .s0_arready (cdc1_m_arready),
            .s0_araddr  (cdc1_m_araddr),   .s0_arlen   (cdc1_m_arlen),
            .s0_arsize  (cdc1_m_arsize),   .s0_arburst (cdc1_m_arburst),
            .s0_arid    (cdc1_m_arid),     .s0_arqos   (cdc1_m_arqos),
            .s0_arcache (cdc1_m_arcache),  .s0_arlock  (cdc1_m_arlock),
            .s0_rvalid  (cdc1_m_rvalid),   .s0_rready  (cdc1_m_rready),
            .s0_rdata   (cdc1_m_rdata),
            .s0_rresp   (cdc1_m_rresp),    .s0_rlast   (cdc1_m_rlast),
            .s0_rid     (cdc1_m_rid),

            // M → DDR target1 读口（写通道已另行 tie-off）
            .m_arvalid  (ddr_inst_ARVALID_1),  .m_arready (ddr_inst_ARREADY_1),
            .m_araddr   (ddr_inst_ARADDR_1),   .m_arlen   (ddr_inst_ARLEN_1),
            .m_arsize   (ddr_inst_ARSIZE_1),   .m_arburst (ddr_inst_ARBURST_1),
            .m_arid     (ddr_inst_ARID_1),     .m_arqos   (ddr_inst_ARQOS_1),
            .m_arcache  (),                    .m_arlock  (ddr_inst_ARLOCK_1),
            .m_rvalid   (ddr_inst_RVALID_1),   .m_rready  (ddr_inst_RREADY_1),
            .m_rdata    (ddr_inst_RDATA_1),
            .m_rresp    (ddr_inst_RRESP_1),    .m_rlast   (ddr_inst_RLAST_1),
            .m_rid      (ddr_inst_RID_1),

            .dbg (rd_arb_dbg)
        );
        // Efinity 专有读侧边带：u_rd 恒 0（frame_reader 复位段驱动后不再
        // 变），仲裁器不透传——DDR 侧直接 tie（与写侧 AWAPCMD_0 同款）
        assign ddr_inst_ARAPCMD_1 = 1'b0;

        frame_reader #(
            .VACT    (16'd2160),            // 4K 有效行
            .FRAME_TICKS (16'd2250),        // v4（D6）：2160 数据 + 90 pad
            .FRAME_A (33'h0_0000_0000),
            .FRAME_B (33'h0_0200_0000),     // v4.10c3k：与 u_fw 同布局修正
                                            // （行槽 8KB/行 x 2160 = 17.6MB/帧，
                                            // 4KB 对齐排布，AXI burst 不跨
                                            // 4KB 边界）；B 基址 = 32MB 处
                                            // （原 0x1100_0000 超 2Gb 器件
                                            // 256MB 容量，回绕与 A 帧尾重叠）
            .ANCHOR_WAIT (12'd78)           // v4.10c3h 锚窗口：VSP+VBP(82)
                                            // - 余量 4（DDR 0.2+demosaic 2）
        ) u_rd (
            .aclk          (pixel_clk),     // v4 Phase 4：148.5M 显示域
            .rstn          (rd_rstn_148),
            .flush_i       (cam0_fw_flush), // v4.10c3e 源切换安全清零
                                            //（与 u_fw 同一脉冲，各自安全拍
                                            // 执行；起步门等 writer 重新
                                            // 发布 >=2 帧）
            .flush_done_o  (cam0_rd_flush_fire), // v4.10c3f 执行拍透传
            .enable        (1'b1),          // DDR 回放架构恒开（v3 无直通）
            .line_tick     (disp_line_tick),// v4：disp_timing 同源槽节拍
            .line_room_i   (disp_line_room),// v4.4：行缓冲空间（发射门节流）
            .disp_sof_i    (disp_sof),      // v4.9：显示帧界（帧授权锚）
            .disp_stall_i  (disp_stall),    // v4.9：显示断粮（救援授权）
            .wr_frame_done (fw_done_148),   // v4：toggle 跨域还原脉冲
            .wr_frame_par  (fw_par_148),    // v4：writer bank 电平（2FF）

            .m_axis_tdata  (cam0_rd_tdata),
            .m_axis_tvalid (cam0_rd_tvalid),
            .m_axis_tlast  (cam0_rd_tlast),
            .m_axis_tuser  (cam0_rd_tuser),

            // 读通道走 DDR port 1（经 u_rd_arb S1；与 writer 的 port 0 写口
            // 物理隔离，控制器口间仲裁分流读写——同口读写合流时小粒度写突发
            // （512B）被大粒度读突发（7680B）挤死（ovf 11 万行/s 实锤）
            .arid     (rd_arid),
            .araddr   (rd_araddr),
            .arlen    (rd_arlen),
            .arsize   (rd_arsize),
            .arburst  (rd_arburst),
            .arlock   (rd_arlock),
            .arvalid  (rd_arvalid),
            .arapcmd  (),              // Efinity 专有边带恒 0：DDR 侧直接 tie
            .arqos    (rd_arqos),
            .arready  (rd_arready),
            .rid      (rd_rid),
            .rdata    (rd_rdata),
            .rlast    (rd_rlast),
            .rvalid   (rd_rvalid),
            .rready   (rd_rready),
            .rresp    (rd_rresp),

            .rd_frame_cnt (rd_frame_cnt),
            .rd_line      (rd_line_cnt),
            .rd_state     (rd_state),
            .rd_err       (rd_err),
            .dbg_fr_cnt   (rd_fr_cnt)      // v4：DIAG19 {drop, repeat}
        );

        // 读链路诊断组包（-> u_cam_0 -> CSR DIAG14/15）
        //   DIAG14 = {rd_frame_cnt[15:0], rd_state[3:0], rd_line[11:0]}
        //   DIAG15 = rd_err = {late[7:0], miss[7:0], err[7:0], 8'h0}
        assign rd_diag14 = {rd_frame_cnt, rd_state, rd_line_cnt};
        assign rd_diag19 = rd_fr_cnt;
        assign rd_diag15 = rd_err;

        //---------------------------------------------------------------------
        // 阶段5：cam1（1080p60）DDR 回放链（plan §3/§4 冻结参数）。
        //   写：u_cam_1 cap 流 -> u_fw1（VACT=1080/60字/32+28/4KB 行槽，
        //   A1=0x0400_0000/B1=0x0500_0000）-> u_wr_arb S0（200M 同钟零 CDC）。
        //   帧握手：fw1_frame_done(200M) toggle -> 37.125M 2FF 还原（复刻
        //   cam0 tog200/tog148 结构）；bank 电平 2FF 直采。
        //   读：u_rd1（VACT=1080/60字/WAIT37=VSP5+VBP36-余量4）@37.125M，
        //   行节拍/帧界/断粮由 u_cam_1 disp_timing 同源；AXI 经 axi_rd_cdc
        //   （37.125->148.5，阶段4 单元 TB 已证首字延迟 ≤5 拍）入
        //   u_rd_arb S0 -> DDR target1。回放流回 u_cam_1 demosaic 前。
        //   复位：rd_rstn_1080 = DDR CFG 完成树（与 rd_rstn_148 同款）；
        //   flush 链 per-cam 独立（cam1_fw_flush 双向：fw1 账本重置 +
        //   rd1 安全清零，flush_done 透传回 u_cam_1 触发 tx 域复位）。
        //---------------------------------------------------------------------
        // cam1 线网声明（须先于 u_fw1 引用——Verific 单编译单元前向引用
        // 会落 1 位隐式 wire，16 位诊断/12 位行号被静默截断，VERI-2561）；
        // rd_rstn_1080 于顶层声明（u_cam_1 端口跨作用域引用）。
        //---------------------------------------------------------------------
        wire [15:0] fw1_line_cnt, fw1_frame_cnt, fw1_pad_cnt, fw1_ovf_cnt;
        wire [11:0] fw1_line;
        wire [3:0]  fw1_state;
        wire        fw1_par, fw1_frame_done;
        wire [31:0] fw1_dbg2;
        frame_writer #(
            .VACT    (16'd1080),            // 1080p 有效行
            .FRAME_A (33'h0_0400_0000),     // cam1 帧乒乓布局（ddr_interface §10）
            .FRAME_B (33'h0_0500_0000),
            .BEATS_PER_LINE    (10'd480),   // 1920px/4 = 480 拍（64b 载体）
            .WORDS_PER_LINE    (7'd60),     // 3840B/64B = 60 字
            .WB0_BEATS         (9'd32),     // 32+28 两突发（4KB 窗内）
            .WB1_BEATS         (9'd28),
            .LINE_STRIDE_SHIFT (5'd12)      // 4KB 行槽
        ) u_fw1 (
            .aclk          (sys_clk_200m),
            .rstn          (cam1_fw_rstn & mc_srstn),
            .flush_i       (cam1_fw_flush),
            .s_axis_tdata  (cam1_cap_tdata),
            .s_axis_tvalid (cam1_cap_tvalid),
            .s_axis_tlast  (cam1_cap_tlast),
            .s_axis_tuser  (cam1_cap_tuser),

            .awid      (fw1_awid),
            .awaddr    (fw1_awaddr),
            .awlen     (fw1_awlen),
            .awsize    (fw1_awsize),
            .awburst   (fw1_awburst),
            .awcache   (fw1_awcache),
            .awlock    (fw1_awlock),
            .awvalid   (fw1_awvalid),
            .awcobuf   (fw1_awcobuf),
            .awapcmd   (fw1_awapcmd),
            .awallstrb (fw1_awallstrb),
            .awqos     (fw1_awqos),
            .awready   (fw1_awready),
            .wdata     (fw1_wdata),
            .wstrb     (fw1_wstrb),
            .wlast     (fw1_wlast),
            .wvalid    (fw1_wvalid),
            .wready    (fw1_wready),
            .bid       (fw1_bid),
            .bvalid    (fw1_bvalid),
            .bready    (fw1_bready),

            .line_cnt  (fw1_line_cnt),
            .frame_cnt (fw1_frame_cnt),
            .pad_cnt   (fw1_pad_cnt),
            .ovf_cnt   (fw1_ovf_cnt),
            .dbg_state (fw1_state),
            .wr_par    (fw1_par),
            .wr_line   (fw1_line),
            .wr_frame_done_o (fw1_frame_done),
            .wr_perf   (),
            .fw_dbg2   (fw1_dbg2)
        );

        // cam1 帧握手跨域 toggle（200M -> 37.125M，复刻 cam0 tog 结构）
        reg  tog200_1;
        reg [2:0] tog1080;
        reg [1:0] par1080;
        always @(posedge sys_clk_200m or negedge mc_srstn)
            if (!mc_srstn) tog200_1 <= 1'b0;
            else if (fw1_frame_done) tog200_1 <= ~tog200_1;
        always @(posedge pixel_clk_1080 or negedge rd_rstn_1080)
            if (!rd_rstn_1080) begin
                tog1080 <= 3'b000;
                par1080 <= 2'b00;
            end else begin
                tog1080 <= {tog1080[1:0], tog200_1};
                par1080 <= {par1080[0], fw1_par};
            end
        wire fw1_done_1080 = tog1080[1] ^ tog1080[2];
        wire fw1_par_1080  = par1080[1];

        // 37.125M 域复位：DDR CFG 完成后同步释放（与 rd_rstn_148 同款）
        reset_ctrl #(.NUM_RST(1), .IN_RST_ACTIVE(1'b1), .OUT_RST_ACTIVE(1'b0), .CYCLE(4))
        u_rd_rst_1080 (
            .i_arst (~ddr_cfg_ok), .i_clk (pixel_clk_1080), .o_srst (rd_rstn_1080)
        );

        // 读 AXI CDC：u_rd1（37.125M）-> u_rd_arb S0（148.5M）
        wire        rd1_arvalid, rd1_arready, rd1_arlock;
        wire [32:0] rd1_araddr;
        wire [7:0]  rd1_arlen;
        wire [2:0]  rd1_arsize;
        wire [1:0]  rd1_arburst;
        wire [5:0]  rd1_arid;
        wire [3:0]  rd1_arqos;
        wire        rd1_rvalid, rd1_rready, rd1_rlast;
        wire [511:0] rd1_rdata;
        wire [1:0]  rd1_rresp;
        wire [5:0]  rd1_rid;
        wire [15:0] rd1_frame_cnt, rd1_err;
        wire [11:0] rd1_line_cnt;
        wire [3:0]  rd1_state;
        wire [31:0] rd1_fr_cnt;

        axi_rd_cdc u_rd_cdc1 (
            .aclk_s    (pixel_clk_1080), .rstn_s (rd_rstn_1080),
            .s_arvalid (rd1_arvalid),    .s_arready (rd1_arready),
            .s_araddr  (rd1_araddr),     .s_arlen (rd1_arlen),
            .s_arsize  (rd1_arsize),     .s_arburst (rd1_arburst),
            .s_arid    (rd1_arid),       .s_arqos (rd1_arqos),
            .s_arcache (4'h0),           .s_arlock (rd1_arlock),
            .s_rvalid  (rd1_rvalid),     .s_rready (rd1_rready),
            .s_rdata   (rd1_rdata),
            .s_rresp   (rd1_rresp),      .s_rlast (rd1_rlast),
            .s_rid     (rd1_rid),
            .aclk_m    (pixel_clk),      .rstn_m (rd_rstn_148),
            .m_arvalid (cdc1_m_arvalid), .m_arready (cdc1_m_arready),
            .m_araddr  (cdc1_m_araddr),  .m_arlen (cdc1_m_arlen),
            .m_arsize  (cdc1_m_arsize),  .m_arburst (cdc1_m_arburst),
            .m_arid    (cdc1_m_arid),    .m_arqos (cdc1_m_arqos),
            .m_arcache (cdc1_m_arcache), .m_arlock (cdc1_m_arlock),
            .m_rvalid  (cdc1_m_rvalid),  .m_rready (cdc1_m_rready),
            .m_rdata   (cdc1_m_rdata),
            .m_rresp   (cdc1_m_rresp),   .m_rlast (cdc1_m_rlast),
            .m_rid     (cdc1_m_rid)
        );

        frame_reader #(
            .VACT    (16'd1080),
            .FRAME_TICKS (16'd1125),        // 1080p60：5+36+1080+4+pad
            .FRAME_A (33'h0_0400_0000),
            .FRAME_B (33'h0_0500_0000),
            .ANCHOR_WAIT (12'd37),          // plan §3：VSP+VBP 41 - 余量 4
            .BEATS_PER_LINE    (10'd480),
            .WORDS_PER_LINE    (7'd60),
            .WB0_BEATS         (9'd32),
            .WB1_BEATS         (9'd28),
            .LINE_STRIDE_SHIFT (5'd12)
        ) u_rd1 (
            .aclk          (pixel_clk_1080), // cam1 显示域 37.125M
            .rstn          (rd_rstn_1080),
            .flush_i       (cam1_fw_flush),  // per-cam 源切换安全清零
            .flush_done_o  (cam1_rd_flush_fire),
            .enable        (1'b1),
            .line_tick     (cam1_disp_line_tick),
            .line_room_i   (cam1_disp_line_room),
            .disp_sof_i    (cam1_disp_sof),
            .disp_stall_i  (cam1_disp_stall),
            .wr_frame_done (fw1_done_1080),
            .wr_frame_par  (fw1_par_1080),

            .m_axis_tdata  (cam1_rd_tdata),
            .m_axis_tvalid (cam1_rd_tvalid),
            .m_axis_tlast  (cam1_rd_tlast),
            .m_axis_tuser  (cam1_rd_tuser),

            // 读通道经 axi_rd_cdc 入 u_rd_arb S0 -> DDR port 1
            .arid     (rd1_arid),
            .araddr   (rd1_araddr),
            .arlen    (rd1_arlen),
            .arsize   (rd1_arsize),
            .arburst  (rd1_arburst),
            .arlock   (rd1_arlock),
            .arvalid  (rd1_arvalid),
            .arapcmd  (),              // Efinity 专有边带恒 0：DDR 侧直接 tie
            .arqos    (rd1_arqos),
            .arready  (rd1_arready),
            .rid      (rd1_rid),
            .rdata    (rd1_rdata),
            .rlast    (rd1_rlast),
            .rvalid   (rd1_rvalid),
            .rready   (rd1_rready),
            .rresp    (rd1_rresp),

            .rd_frame_cnt (rd1_frame_cnt),
            .rd_line      (rd1_line_cnt),
            .rd_state     (rd1_state),
            .rd_err       (rd1_err),
            .dbg_fr_cnt   (rd1_fr_cnt)
        );

        // cam1 诊断组包（-> u_cam_1 -> CSR DIAG12/13/14/15/19/20）
        assign cam1_fw_diag  = {fw1_frame_cnt, fw1_line_cnt};
        assign cam1_fw_diag2 = {fw1_ovf_cnt, fw1_pad_cnt};
        assign cam1_fw_dbg2  = fw1_dbg2;
        assign cam1_rd_diag14 = {rd1_frame_cnt, rd1_state, rd1_line_cnt};
        assign cam1_rd_diag19 = rd1_fr_cnt;
        assign cam1_rd_diag15 = rd1_err;


        assign fw_diag  = {fw_frame_cnt, fw_line_cnt};
        assign fw_diag2 = {fw_ovf_cnt, fw_pad_cnt};

        // memcheck 未实例化：DIAG11 清零
        assign mc_done    = 1'b0;
        assign mc_fail    = 1'b0;
        assign mc_err_cnt = 16'h0;
        assign mc_state   = 4'h0;

        // port 0 写口恢复纯写：读通道（frame_reader 已迁至 port 1）tie-off
        assign ddr_inst_ARVALID_0   = 1'b0;
        assign ddr_inst_RREADY_0    = 1'b1;

        // port 1 读口 = frame_reader（AW/W 写通道保持 idle）
        assign ddr_inst_AWID_1      = 6'h0;
        assign ddr_inst_AWADDR_1    = 33'h0;
        assign ddr_inst_AWLEN_1     = 8'h0;
        assign ddr_inst_AWSIZE_1    = 3'h0;
        assign ddr_inst_AWBURST_1   = 2'h0;
        assign ddr_inst_AWLOCK_1    = 1'b0;
        assign ddr_inst_AWQOS_1     = 4'h0;
        assign ddr_inst_AWVALID_1   = 1'b0;
        assign ddr_inst_WVALID_1    = 1'b0;
        assign ddr_inst_WDATA_1     = 512'h0;
        assign ddr_inst_WSTRB_1     = 64'h0;
        assign ddr_inst_WLAST_1     = 1'b0;
        assign ddr_inst_BREADY_1    = 1'b1;
        assign ddr_inst_AWALLSTRB_1 = 1'b0;
        assign ddr_inst_AWAPCMD_1   = 1'b0;
        assign ddr_inst_AWCOBUF_1   = 1'b0;
        assign ddr_inst_AWCACHE_1   = 4'h0;

    end else if (DDR_MEMTEST) begin : g_ddr_memtest

        // 回放流 tie-off（memcheck 回归分支无 frame_reader）
        assign cam0_rd_tdata  = 64'h0;
        assign cam0_rd_tvalid = 1'b0;
        assign cam0_rd_tlast  = 1'b0;
        assign cam0_rd_tuser  = 3'h0;
        assign rd_diag14 = 32'h0;
        assign rd_diag19 = 32'h0;
        assign rd_diag15 = 32'h0;
        // cam1 回放流/诊断 tie-off（本分支无 cam1 链）
        assign cam1_rd_tdata  = 64'h0;
        assign cam1_rd_tvalid = 1'b0;
        assign cam1_rd_tlast  = 1'b0;
        assign cam1_rd_tuser  = 3'h0;
        assign cam1_rd_flush_fire = 1'b0;
        assign cam1_fw_diag   = 32'h0;
        assign cam1_fw_diag2  = 32'h0;
        assign cam1_fw_dbg2   = 32'h0;
        assign cam1_rd_diag14 = 32'h0;
        assign cam1_rd_diag15 = 32'h0;
        assign cam1_rd_diag19 = 32'h0;

        ddr_memcheck #(
            .START_ADDR  (33'h0_0000_0000),
            .TOTAL_BURSTS(16'd3495),        // 3495×7680B ≈ 26MB ≈ 帧 A/B 乒乓区
            .ALEN        (8'd119),          // 120 beat = 7680B = 一行 UYVY
            .ASIZE       (3'b110)           // 64B/beat
        ) u_mc (
            .axi_clk   (sys_clk_200m),      // = ACLK_0（peri 绑定）
            .rstn      (mc_srstn),
            .start     (mc_srstn),          // 复位释放（mc_srstn 拉高）即启动

            .awid      (ddr_inst_AWID_0),
            .awaddr    (ddr_inst_AWADDR_0),
            .awlen     (ddr_inst_AWLEN_0),
            .awsize    (ddr_inst_AWSIZE_0),
            .awburst   (ddr_inst_AWBURST_0),
            .awcache   (ddr_inst_AWCACHE_0),
            .awlock    (ddr_inst_AWLOCK_0),
            .awvalid   (ddr_inst_AWVALID_0),
            .awcobuf   (ddr_inst_AWCOBUF_0),
            .awapcmd   (ddr_inst_AWAPCMD_0),
            .awallstrb (ddr_inst_AWALLSTRB_0),
            .awqos     (ddr_inst_AWQOS_0),
            .awready   (ddr_inst_AWREADY_0),
            .wdata     (ddr_inst_WDATA_0),
            .wstrb     (ddr_inst_WSTRB_0),
            .wlast     (ddr_inst_WLAST_0),
            .wvalid    (ddr_inst_WVALID_0),
            .wready    (ddr_inst_WREADY_0),
            .bid       (ddr_inst_BID_0),
            .bvalid    (ddr_inst_BVALID_0),
            .bready    (ddr_inst_BREADY_0),
            .arid      (ddr_inst_ARID_0),
            .araddr    (ddr_inst_ARADDR_0),
            .arlen     (ddr_inst_ARLEN_0),
            .arsize    (ddr_inst_ARSIZE_0),
            .arburst   (ddr_inst_ARBURST_0),
            .arlock    (ddr_inst_ARLOCK_0),
            .arvalid   (ddr_inst_ARVALID_0),
            .arapcmd   (ddr_inst_ARAPCMD_0),
            .arqos     (ddr_inst_ARQOS_0),
            .arready   (ddr_inst_ARREADY_0),
            .rid       (ddr_inst_RID_0),
            .rdata     (ddr_inst_RDATA_0),
            .rlast     (ddr_inst_RLAST_0),
            .rvalid    (ddr_inst_RVALID_0),
            .rready    (ddr_inst_RREADY_0),
            .rresp     (ddr_inst_RRESP_0),

            .done      (mc_done),
            .fail      (mc_fail),
            .err_cnt   (mc_err_cnt),
            .dbg_state (mc_state)
        );

        // port 1 保持 idle（阶段 1 frame_reader 接入前不使用）
        assign ddr_inst_AWID_1      = 6'h0;
        assign ddr_inst_AWADDR_1    = 33'h0;
        assign ddr_inst_AWLEN_1     = 8'h0;
        assign ddr_inst_AWSIZE_1    = 3'h0;
        assign ddr_inst_AWBURST_1   = 2'h0;
        assign ddr_inst_AWLOCK_1    = 1'b0;
        assign ddr_inst_AWQOS_1     = 4'h0;
        assign ddr_inst_AWVALID_1   = 1'b0;
        assign ddr_inst_WVALID_1    = 1'b0;
        assign ddr_inst_WDATA_1     = 512'h0;
        assign ddr_inst_WSTRB_1     = 64'h0;
        assign ddr_inst_WLAST_1     = 1'b0;
        assign ddr_inst_BREADY_1    = 1'b1;
        assign ddr_inst_ARAPCMD_1   = 1'b0;
        assign ddr_inst_AWALLSTRB_1 = 1'b0;
        assign ddr_inst_AWAPCMD_1   = 1'b0;
        assign ddr_inst_AWCOBUF_1   = 1'b0;
        assign ddr_inst_AWCACHE_1   = 4'h0;
        assign ddr_inst_ARVALID_1   = 1'b0;
        assign ddr_inst_ARADDR_1    = 33'h0;
        assign ddr_inst_ARBURST_1   = 2'h0;
        assign ddr_inst_ARID_1      = 6'h0;
        assign ddr_inst_ARLEN_1     = 8'h0;
        assign ddr_inst_ARLOCK_1    = 1'b0;
        assign ddr_inst_ARQOS_1     = 4'h0;
        assign ddr_inst_ARSIZE_1    = 3'h0;
        assign ddr_inst_RREADY_1    = 1'b1;

    end else if (DDR_P1_148) begin : g_ddr_memtest_148

        //---------------------------------------------------------------------
        // Phase 0（2026-10-20，SPEC-001 R6/RK-1 定界）：ACLK_1 换绑验证分支。
        //   peri.xml ACLK_1 已从 sys_clk_200m 换绑 pixel_clk（pll_csi#1，
        //   148.5MHz）。ddr_memcheck 整体挂 target1、axi_clk=pixel_clk——
        //   读写分相（先写完整区再读回），同口无并发，与阶段 0 在 port0 的
        //   板测形态一致。自检过（DIAG11：fail=0 且 done=1）即证明 DDR 硬核
        //   接受 148.5M 独立 AXI 端口时钟 = frame_reader v3 搬域的平台前提。
        //   port0 全 idle（FRAME_WRITER 回 1 前写口空闲）。
        //---------------------------------------------------------------------
        wire mc_srstn_148;
        // CFG 完成后 pixel_clk 域同步释放（2FF+CYCLE=4，与 200M 侧 u_mc_rst 同款）
        reset_ctrl #(.NUM_RST(1), .IN_RST_ACTIVE(1'b1), .OUT_RST_ACTIVE(1'b0), .CYCLE(4))
        u_mc_rst_148 (
            .i_arst (~ddr_cfg_ok), .i_clk (pixel_clk), .o_srst (mc_srstn_148)
        );

        // 回放流 tie-off（本分支无 frame_reader）
        assign cam0_rd_tdata  = 64'h0;
        assign cam0_rd_tvalid = 1'b0;
        assign cam0_rd_tlast  = 1'b0;
        assign cam0_rd_tuser  = 3'h0;
        assign rd_diag14 = 32'h0;
        assign rd_diag15 = 32'h0;
        // cam1 回放流/诊断 tie-off（本分支无 cam1 链）
        assign cam1_rd_tdata  = 64'h0;
        assign cam1_rd_tvalid = 1'b0;
        assign cam1_rd_tlast  = 1'b0;
        assign cam1_rd_tuser  = 3'h0;
        assign cam1_rd_flush_fire = 1'b0;
        assign cam1_fw_diag   = 32'h0;
        assign cam1_fw_diag2  = 32'h0;
        assign cam1_fw_dbg2   = 32'h0;
        assign cam1_rd_diag14 = 32'h0;
        assign cam1_rd_diag15 = 32'h0;
        assign cam1_rd_diag19 = 32'h0;

        ddr_memcheck #(
            .START_ADDR  (33'h0_0000_0000),
            .TOTAL_BURSTS(16'd3495),        // 3495×7680B ≈ 26MB ≈ 帧 A/B 乒乓区
            .ALEN        (8'd119),          // 120 beat = 7680B = 一行 UYVY
            .ASIZE       (3'b110)           // 64B/beat
        ) u_mc148 (
            .axi_clk   (pixel_clk),         // = ACLK_1（peri 换绑验证点）
            .rstn      (mc_srstn_148),
            .start     (mc_srstn_148),      // 复位释放即启动

            .awid      (ddr_inst_AWID_1),
            .awaddr    (ddr_inst_AWADDR_1),
            .awlen     (ddr_inst_AWLEN_1),
            .awsize    (ddr_inst_AWSIZE_1),
            .awburst   (ddr_inst_AWBURST_1),
            .awcache   (ddr_inst_AWCACHE_1),
            .awlock    (ddr_inst_AWLOCK_1),
            .awvalid   (ddr_inst_AWVALID_1),
            .awcobuf   (ddr_inst_AWCOBUF_1),
            .awapcmd   (ddr_inst_AWAPCMD_1),
            .awallstrb (ddr_inst_AWALLSTRB_1),
            .awqos     (ddr_inst_AWQOS_1),
            .awready   (ddr_inst_AWREADY_1),
            .wdata     (ddr_inst_WDATA_1),
            .wstrb     (ddr_inst_WSTRB_1),
            .wlast     (ddr_inst_WLAST_1),
            .wvalid    (ddr_inst_WVALID_1),
            .wready    (ddr_inst_WREADY_1),
            .bid       (ddr_inst_BID_1),
            .bvalid    (ddr_inst_BVALID_1),
            .bready    (ddr_inst_BREADY_1),
            .arid      (ddr_inst_ARID_1),
            .araddr    (ddr_inst_ARADDR_1),
            .arlen     (ddr_inst_ARLEN_1),
            .arsize    (ddr_inst_ARSIZE_1),
            .arburst   (ddr_inst_ARBURST_1),
            .arlock    (ddr_inst_ARLOCK_1),
            .arvalid   (ddr_inst_ARVALID_1),
            .arapcmd   (ddr_inst_ARAPCMD_1),
            .arqos     (ddr_inst_ARQOS_1),
            .arready   (ddr_inst_ARREADY_1),
            .rid       (ddr_inst_RID_1),
            .rdata     (ddr_inst_RDATA_1),
            .rlast     (ddr_inst_RLAST_1),
            .rvalid    (ddr_inst_RVALID_1),
            .rready    (ddr_inst_RREADY_1),
            .rresp     (ddr_inst_RRESP_1),

            .done      (mc_done),
            .fail      (mc_fail),
            .err_cnt   (mc_err_cnt),
            .dbg_state (mc_state)
        );

        // port 0 idle（FRAME_WRITER 回 1 前写口空闲；完整集含 AWCACHE_0）
        assign ddr_inst_AWID_0      = 6'h0;
        assign ddr_inst_AWADDR_0    = 33'h0;
        assign ddr_inst_AWLEN_0     = 8'h0;
        assign ddr_inst_AWSIZE_0    = 3'h0;
        assign ddr_inst_AWBURST_0   = 2'h0;
        assign ddr_inst_AWLOCK_0    = 1'b0;
        assign ddr_inst_AWQOS_0     = 4'h0;
        assign ddr_inst_AWVALID_0   = 1'b0;
        assign ddr_inst_WVALID_0    = 1'b0;
        assign ddr_inst_WDATA_0     = 512'h0;
        assign ddr_inst_WSTRB_0     = 64'h0;
        assign ddr_inst_WLAST_0     = 1'b0;
        assign ddr_inst_BREADY_0    = 1'b1;
        assign ddr_inst_ARAPCMD_0   = 1'b0;
        assign ddr_inst_AWALLSTRB_0 = 1'b0;
        assign ddr_inst_AWAPCMD_0   = 1'b0;
        assign ddr_inst_AWCOBUF_0   = 1'b0;
        assign ddr_inst_AWCACHE_0   = 4'h0;
        assign ddr_inst_ARVALID_0   = 1'b0;
        assign ddr_inst_ARADDR_0    = 33'h0;
        assign ddr_inst_ARBURST_0   = 2'h0;
        assign ddr_inst_ARID_0      = 6'h0;
        assign ddr_inst_ARLEN_0     = 8'h0;
        assign ddr_inst_ARLOCK_0    = 1'b0;
        assign ddr_inst_ARQOS_0     = 4'h0;
        assign ddr_inst_ARSIZE_0    = 3'h0;
        assign ddr_inst_RREADY_0    = 1'b1;

    end else begin : g_ddr_idle

        // 回放流 tie-off（idle 分支无 frame_reader）
        assign cam0_rd_tdata  = 64'h0;
        assign cam0_rd_tvalid = 1'b0;
        assign cam0_rd_tlast  = 1'b0;
        assign cam0_rd_tuser  = 3'h0;
        assign rd_diag14 = 32'h0;
        assign rd_diag15 = 32'h0;
        // cam1 回放流/诊断 tie-off（本分支无 cam1 链）
        assign cam1_rd_tdata  = 64'h0;
        assign cam1_rd_tvalid = 1'b0;
        assign cam1_rd_tlast  = 1'b0;
        assign cam1_rd_tuser  = 3'h0;
        assign cam1_rd_flush_fire = 1'b0;
        assign cam1_fw_diag   = 32'h0;
        assign cam1_fw_diag2  = 32'h0;
        assign cam1_fw_dbg2   = 32'h0;
        assign cam1_rd_diag14 = 32'h0;
        assign cam1_rd_diag15 = 32'h0;
        assign cam1_rd_diag19 = 32'h0;

        // port 0 idle（正式 frame_writer 接入前的原始稳态）
        assign ddr_inst_AWID_0      = 6'h0;
        assign ddr_inst_AWADDR_0    = 33'h0;
        assign ddr_inst_AWLEN_0     = 8'h0;
        assign ddr_inst_AWSIZE_0    = 3'h0;
        assign ddr_inst_AWBURST_0   = 2'h0;
        assign ddr_inst_AWLOCK_0    = 1'b0;
        assign ddr_inst_AWQOS_0     = 4'h0;
        assign ddr_inst_AWVALID_0   = 1'b0;
        assign ddr_inst_WVALID_0    = 1'b0;
        assign ddr_inst_WDATA_0     = 512'h0;
        assign ddr_inst_WSTRB_0     = 64'h0;
        assign ddr_inst_WLAST_0     = 1'b0;
        assign ddr_inst_BREADY_0    = 1'b1;
        assign ddr_inst_ARAPCMD_0   = 1'b0;
        assign ddr_inst_AWALLSTRB_0 = 1'b0;
        assign ddr_inst_AWAPCMD_0   = 1'b0;
        assign ddr_inst_AWCOBUF_0   = 1'b0;
        assign ddr_inst_ARVALID_0   = 1'b0;
        assign ddr_inst_ARADDR_0    = 33'h0;
        assign ddr_inst_ARBURST_0   = 2'h0;
        assign ddr_inst_ARID_0      = 6'h0;
        assign ddr_inst_ARLEN_0     = 8'h0;
        assign ddr_inst_ARLOCK_0    = 1'b0;
        assign ddr_inst_ARQOS_0     = 4'h0;
        assign ddr_inst_ARSIZE_0    = 3'h0;
        assign ddr_inst_RREADY_0    = 1'b1;

        // port 1 idle
        assign ddr_inst_AWID_1      = 6'h0;
        assign ddr_inst_AWADDR_1    = 33'h0;
        assign ddr_inst_AWLEN_1     = 8'h0;
        assign ddr_inst_AWSIZE_1    = 3'h0;
        assign ddr_inst_AWBURST_1   = 2'h0;
        assign ddr_inst_AWLOCK_1    = 1'b0;
        assign ddr_inst_AWQOS_1     = 4'h0;
        assign ddr_inst_AWVALID_1   = 1'b0;
        assign ddr_inst_WVALID_1    = 1'b0;
        assign ddr_inst_WDATA_1     = 512'h0;
        assign ddr_inst_WSTRB_1     = 64'h0;
        assign ddr_inst_WLAST_1     = 1'b0;
        assign ddr_inst_BREADY_1    = 1'b1;
        assign ddr_inst_ARAPCMD_1   = 1'b0;
        assign ddr_inst_AWALLSTRB_1 = 1'b0;
        assign ddr_inst_AWAPCMD_1   = 1'b0;
        assign ddr_inst_AWCOBUF_1   = 1'b0;
        assign ddr_inst_AWCACHE_1   = 4'h0;
        assign ddr_inst_ARVALID_1   = 1'b0;
        assign ddr_inst_ARADDR_1    = 33'h0;
        assign ddr_inst_ARBURST_1   = 2'h0;
        assign ddr_inst_ARID_1      = 6'h0;
        assign ddr_inst_ARLEN_1     = 8'h0;
        assign ddr_inst_ARLOCK_1    = 1'b0;
        assign ddr_inst_ARQOS_1     = 4'h0;
        assign ddr_inst_ARSIZE_1    = 3'h0;
        assign ddr_inst_RREADY_1    = 1'b1;

    end endgenerate

    // DIAG11 @0x2C：{err_cnt[15:0], mcst[15:12], 5'h0, done_raw[6], st[5:4],
    //                lock[3], cfg_ok[2], done[1], fail[0]}
    //  st: 0=IDLE 1=CFG_START(训练中) 3=CFG_DONE
    //  mcst（checker 状态机）: 0=IDLE 1=WRITE_ADDR 2=PRE_WRITE 3=WRITE
    //    4=POST_WRITE(等B) 5=READ_ADDR 6=PRE_READ 7=READ_COMPARE 8=POST_READ 9=DONE
    assign ddr_diag = {mc_err_cnt, mc_state, 5'h0, ddr_inst_CFG_DONE, cfg_st,
                       pll_ddr_locked, ddr_cfg_ok, mc_done, mc_fail};

    //-------------------------------------------------------------------------
    // riscv_soc
    //   APB slave0 -> apb_cam_ctrl（camera_path 控制口）
    //   APB slave1/2/3 -> dummy instant-ack（误访问不挂 CPU）
    //-------------------------------------------------------------------------
    wire [15:0] apb0_paddr;
    wire        apb0_psel;
    wire        apb0_penable;
    wire        apb0_pwrite;
    wire [31:0] apb0_pwdata;
    wire [31:0] apb0_prdata;
    wire        apb0_pready;
    wire        apb0_pslverr;

    wire [15:0] apb1_paddr;
    wire        apb1_psel;
    wire        apb1_penable;
    wire        apb1_pwrite;
    wire [31:0] apb1_pwdata;
    wire [31:0] apb1_prdata;
    wire        apb1_pready;
    wire        apb1_pslverr;

    riscv_soc u_soc (
        .io_systemClk               (sys_clk_200m),
        .io_asyncReset              (~sys_clk_200m_rstn),
        .io_systemReset             (),

        .system_uart_0_io_txd       (uart_0_txd),
        .system_uart_0_io_rxd       (uart_0_rxd),

        .system_i2c_0_io_sda_write  (w_i2c_0_sda_write),
        .system_i2c_0_io_sda_read   (w_i2c_0_sda_read),
        .system_i2c_0_io_scl_write  (w_i2c_0_scl_write),
        .system_i2c_0_io_scl_read   (w_i2c_0_scl_read),

        .system_i2c_1_io_sda_write  (w_i2c_1_sda_write),
        .system_i2c_1_io_sda_read   (w_i2c_1_sda_read),
        .system_i2c_1_io_scl_write  (w_i2c_1_scl_write),
        .system_i2c_1_io_scl_read   (w_i2c_1_scl_read),

        .system_gpio_0_io_read      (4'h0),
        .system_gpio_0_io_write     (w_gpio_write),
        .system_gpio_0_io_writeEnable(),

        // APB slave 0: camera_path 控制 CSR
        .io_apbSlave_0_PADDR    (apb0_paddr),
        .io_apbSlave_0_PSEL     (apb0_psel),
        .io_apbSlave_0_PENABLE  (apb0_penable),
        .io_apbSlave_0_PWRITE   (apb0_pwrite),
        .io_apbSlave_0_PWDATA   (apb0_pwdata),
        .io_apbSlave_0_PREADY   (apb0_pready),
        .io_apbSlave_0_PRDATA   (apb0_prdata),
        .io_apbSlave_0_PSLVERROR(apb0_pslverr),

        // APB slave 1: dummy instant-ack（原 video_reader CSR 位已腾空）
        .io_apbSlave_1_PADDR    (apb1_paddr),
        .io_apbSlave_1_PSEL     (apb1_psel),
        .io_apbSlave_1_PENABLE  (apb1_penable),
        .io_apbSlave_1_PWRITE   (apb1_pwrite),
        .io_apbSlave_1_PWDATA   (apb1_pwdata),
        .io_apbSlave_1_PREADY   (apb1_pready),
        .io_apbSlave_1_PRDATA   (apb1_prdata),
        .io_apbSlave_1_PSLVERROR(apb1_pslverr),

        // APB slave 2/3: dummy instant-ack（同 top_soc_sd 风格）
        .io_apbSlave_2_PADDR    (),
        .io_apbSlave_2_PSEL     (),
        .io_apbSlave_2_PENABLE  (),
        .io_apbSlave_2_PWRITE   (),
        .io_apbSlave_2_PWDATA   (),
        .io_apbSlave_2_PREADY   (1'b1),
        .io_apbSlave_2_PRDATA   (32'h0),
        .io_apbSlave_2_PSLVERROR(1'b0),

        .io_apbSlave_3_PADDR    (),
        .io_apbSlave_3_PSEL     (),
        .io_apbSlave_3_PENABLE  (),
        .io_apbSlave_3_PWRITE   (),
        .io_apbSlave_3_PWDATA   (),
        .io_apbSlave_3_PREADY   (1'b1),
        .io_apbSlave_3_PRDATA   (32'h0),
        .io_apbSlave_3_PSLVERROR(1'b0),

        // JTAG USER1 -> RISC-V 硬调试桥（UPDATE/RESET 是 BRAM 固件提交路径）
        .jtagCtrl_tck               (jtag_inst1_TCK),
        .jtagCtrl_tdi               (jtag_inst1_TDI),
        .jtagCtrl_tdo               (jtag_inst1_TDO),
        .jtagCtrl_enable            (jtag_inst1_SEL),
        .jtagCtrl_capture           (jtag_inst1_CAPTURE),
        .jtagCtrl_shift             (jtag_inst1_SHIFT),
        .jtagCtrl_update            (jtag_inst1_UPDATE),
        .jtagCtrl_reset             (jtag_inst1_RESET)
    );


    // ---- cam0：IMX415 4K60 全像素 + 4K60 面板成形（C1 分阶段，2026-10）----
    //   sensor 窗口：3864 - 12 - 12 = 3840（4 的倍数，WC=4830）；
    //   LEAD=12 / TRAIL=12 / SKIP_FIRST=21。
    //   skip 语义（2026-10-12 依数据手册 DT 表澄清）：EBD=12h、OB=37h
    //   （用户 1080p LA 验证：1 EBD + 18 OB），均被 raw 的 DT=2Bh 门控
    //   滤掉、不占行号 => 行号里只有图像行。4K 全像素图像 = 2192 行，
    //   skip=21 + LINES=2160 = 裁前 21 行、尾 11 行（2192->2160 裁窗），
    //   与 1080p skip=11 裁 1096 行的前 11 行同构。skip 不承担"跳 OB"
    //   职责（OB 根本到不了 raw 行计数），顶部白条与 skip 无关——那是
    //   shape 读相位旋转（显示帧起始点落在发射帧尾部），v2 锚定的
    //   目标病灶，板级未收敛原因另行排查（端到端两钟 TB）。
    //   回退记录：曾试 21->77（按"OB 占行号"的错误假设），已回退。
    //   shape：CEA 4K60 消隐（HSP 88/HBP 296/HFP 176/VSP 10/VBP 72/VFP 8
    //   -> Vtotal 2250）@ 148.5MHz PPC4。c3l（2026-10-22）曾试 VSP 8/VFP 10
    //   + WAIT 76 补偿顶部 2 行滚屏：板测无效（滚屏与该参数无关），已回退
    //   ——滚屏是数据域行相位错位，两条成形路径（disp_timing 回放/
    //   shape_video_axis 直注）同现，且直注路径在更早版本无此现象
    //   （用户记忆），按近期回归排查。显示帧率被供给行数经帧首水位门
    //   锁定到源帧率，桥容差待板级确认；备选：定制 Vtotal 拉回 60.00。
    //   FIFO：65536 字 = 68.27 行（4K 行 960 字）；水位三件套沿用 1080p
    //   行数初值（显示 Vblank 90 行排水窗比 1080p 更宽），4K TB 仿真复核。
    //   pattern：LINE_BEATS 966（参数链自动 = 3864/4），pad = 2250-21-2160
    //   = 69 节拍，帧长 2250 tick x 7.407us = 精确 60fps。
    top_cam #(
        .LINE_TOTAL_PIX    (20'd3864),   // 行总像素（4K, WC=4830 字节）
        .LEAD_PIX          (20'd12),     // 板级确认（4K）
        .TRAIL_PIX         (20'd12),     // 3864-12-12=3840 保持 4 的倍数
        .LINE_SKIP_FIRST   (20'd21),     // 帧结构（板级确认）：36 行 OB(0x37，DT 门
                                         // 滤除不占行号) + 21 行头部 2B + 2160 有
                                         // 效行。SKIP=21 跳头部 2B，行窗=有效帧。
                                         //（v6.0 曾试 SKIP=0，基于错误模型已回退）
        .CAM_LINES         (16'd2160),
        .GW                (16'd960),    // 3840/4（demosaic 组计数已扩 10bit）
        .HACT              (16'd3840),
        .VACT              (16'd2160),
        .HSP               (16'd88),
        .HBP               (16'd296),
        .HFP               (16'd176),
        .VSP               (16'd10),     // CTA 4K60 标准值。c3l 曾试 8 补偿
                                         // 顶部 2 行滚屏：无效，已回退——
                                         // 滚屏与 vsync↔数据相对时序无关，
                                         // 是数据域行相位错位（另行排查）
        .VBP               (16'd72),
        .VFP               (16'd8),      // Vtotal 保持 2250
        .PATTERN_FRAME_PAD (20'd69),     // 2250 - 21 - 2160
        // 4K shape 隔离验证（2026-10-12 运行时切换）：入口直注 UYVY 棋盘
        // 源编译进比特（面积极小），CSR CTRL[6] dbg_sel 运行时切入/切出
        // （变化沿自动触发源切换软复位，切换黑一帧后干净接入）。判读：
        // 直注源冷启动按构造对齐，帧首黑条若不在显示顶缘 => 旋转在
        // shape/外部桥片，与相机流水线无关。
        .DBG_SHAPE_PAT     (1),
        // v4（Phase 4，SPEC-001 mod-top-v4）显示链帧槽：tx_line_buf +
        // disp_timing 替换 shape 成形。v4.10c3m 起 v4 为唯一路径
        //（FIFO_DEPTH/DISP_V4 参数随 shape_video_axis/DISP_V4=0 分支退役）。
        .DISP_FRAME_SLOTS  (16'd2250),  // 4K60：10+72+2160+8+pad
        .MODE_4K           (1'b1)       // v4.11：IMX415 4K geo 段
    )
    u_cam_0 (
        .sys_clk_100m ( sys_clk_100m ),   
        .sys_clk_200m ( sys_clk_200m ),
        .sys_clk_100m_rstn ( sys_clk_100m_rstn ),
        .sys_clk_200m_rstn ( sys_clk_200m_rstn ),
        .i_clk_27m ( i_clk_27m ),
        .pll_mipi_refclk_locked ( pll_mipi_refclk_locked ),
        .tx_pixel_clk ( pixel_clk ),
        .esc_clk ( esc_clk ),
  
        .dphy_tx_WORD_CLKOUT_HS          ( dphy_tx0_WORD_CLKOUT_HS          ),
        .dphy_tx_STOPSTATE_CLK           ( dphy_tx0_STOPSTATE_CLK           ),
        .dphy_tx_STOPSTATE_LAN0          ( dphy_tx0_STOPSTATE_LAN0          ),
        .dphy_tx_STOPSTATE_LAN1          ( dphy_tx0_STOPSTATE_LAN1          ),
        .dphy_tx_STOPSTATE_LAN2          ( dphy_tx0_STOPSTATE_LAN2          ),
        .dphy_tx_STOPSTATE_LAN3          ( dphy_tx0_STOPSTATE_LAN3          ),
        .dphy_tx_TX_READY_HS_LAN0        ( dphy_tx0_TX_READY_HS_LAN0        ),
        .dphy_tx_TX_READY_HS_LAN1        ( dphy_tx0_TX_READY_HS_LAN1        ),
        .dphy_tx_TX_READY_HS_LAN2        ( dphy_tx0_TX_READY_HS_LAN2        ),
        .dphy_tx_TX_READY_HS_LAN3        ( dphy_tx0_TX_READY_HS_LAN3        ),
        .dphy_tx_TX_ULPS_ACTIVE_CLK_NOT  ( dphy_tx0_TX_ULPS_ACTIVE_CLK_NOT  ),
        .dphy_tx_TX_ULPS_ACTIVE_NOT_LAN0 ( dphy_tx0_TX_ULPS_ACTIVE_NOT_LAN0 ),
        .dphy_tx_TX_ULPS_ACTIVE_NOT_LAN1 ( dphy_tx0_TX_ULPS_ACTIVE_NOT_LAN1 ),
        .dphy_tx_TX_ULPS_ACTIVE_NOT_LAN2 ( dphy_tx0_TX_ULPS_ACTIVE_NOT_LAN2 ),
        .dphy_tx_TX_ULPS_ACTIVE_NOT_LAN3 ( dphy_tx0_TX_ULPS_ACTIVE_NOT_LAN3 ),
  
        .dphy_tx_PLL_SSC_EN          ( dphy_tx0_PLL_SSC_EN          ),
        .dphy_tx_RESET_N             ( dphy_tx0_RESET_N             ),
        .dphy_tx_TX_DATA_ESC         ( dphy_tx0_TX_DATA_ESC         ),
        .dphy_tx_TX_LPDT_ESC         ( dphy_tx0_TX_LPDT_ESC         ),
        .dphy_tx_TX_VALID_ESC        ( dphy_tx0_TX_VALID_ESC        ),
        .dphy_tx_TX_TRIGGER_ESC      ( dphy_tx0_TX_TRIGGER_ESC      ),
        .dphy_tx_TX_REQUEST_ESC_LAN0 ( dphy_tx0_TX_REQUEST_ESC_LAN0 ),
        .dphy_tx_TX_REQUEST_ESC_LAN1 ( dphy_tx0_TX_REQUEST_ESC_LAN1 ),
        .dphy_tx_TX_REQUEST_ESC_LAN2 ( dphy_tx0_TX_REQUEST_ESC_LAN2 ),
        .dphy_tx_TX_REQUEST_ESC_LAN3 ( dphy_tx0_TX_REQUEST_ESC_LAN3 ),
        .dphy_tx_TX_REQUEST_HS       ( dphy_tx0_TX_REQUEST_HS       ),
        .dphy_tx_TX_REQUEST_HS_LAN0  ( dphy_tx0_TX_REQUEST_HS_LAN0  ),
        .dphy_tx_TX_REQUEST_HS_LAN1  ( dphy_tx0_TX_REQUEST_HS_LAN1  ),
        .dphy_tx_TX_REQUEST_HS_LAN2  ( dphy_tx0_TX_REQUEST_HS_LAN2  ),
        .dphy_tx_TX_REQUEST_HS_LAN3  ( dphy_tx0_TX_REQUEST_HS_LAN3  ),
        .dphy_tx_TX_SKEW_CAL_HS_LAN0 ( dphy_tx0_TX_SKEW_CAL_HS_LAN0 ),
        .dphy_tx_TX_SKEW_CAL_HS_LAN1 ( dphy_tx0_TX_SKEW_CAL_HS_LAN1 ),
        .dphy_tx_TX_SKEW_CAL_HS_LAN2 ( dphy_tx0_TX_SKEW_CAL_HS_LAN2 ),
        .dphy_tx_TX_SKEW_CAL_HS_LAN3 ( dphy_tx0_TX_SKEW_CAL_HS_LAN3 ),
        .dphy_tx_TX_ULPS_CLK      ( dphy_tx0_TX_ULPS_CLK      ),
        .dphy_tx_TX_ULPS_ESC_LAN0 ( dphy_tx0_TX_ULPS_ESC_LAN0 ),
        .dphy_tx_TX_ULPS_ESC_LAN1 ( dphy_tx0_TX_ULPS_ESC_LAN1 ),
        .dphy_tx_TX_ULPS_ESC_LAN2 ( dphy_tx0_TX_ULPS_ESC_LAN2 ),
        .dphy_tx_TX_ULPS_ESC_LAN3 ( dphy_tx0_TX_ULPS_ESC_LAN3 ),
        .dphy_tx_TX_ULPS_EXIT      ( dphy_tx0_TX_ULPS_EXIT      ),
        .dphy_tx_TX_ULPS_EXIT_LAN0 ( dphy_tx0_TX_ULPS_EXIT_LAN0 ),
        .dphy_tx_TX_ULPS_EXIT_LAN1 ( dphy_tx0_TX_ULPS_EXIT_LAN1 ),
        .dphy_tx_TX_ULPS_EXIT_LAN2 ( dphy_tx0_TX_ULPS_EXIT_LAN2 ),
        .dphy_tx_TX_ULPS_EXIT_LAN3 ( dphy_tx0_TX_ULPS_EXIT_LAN3 ),
        .dphy_tx_TX_DATA_HS_LAN0 ( dphy_tx0_TX_DATA_HS_LAN0 ),
        .dphy_tx_TX_DATA_HS_LAN1 ( dphy_tx0_TX_DATA_HS_LAN1 ),
        .dphy_tx_TX_DATA_HS_LAN2 ( dphy_tx0_TX_DATA_HS_LAN2 ),
        .dphy_tx_TX_DATA_HS_LAN3 ( dphy_tx0_TX_DATA_HS_LAN3 ),
        .dphy_tx_TX_WORD_VALID_HS_LAN0 ( dphy_tx0_TX_WORD_VALID_HS_LAN0 ),
        .dphy_tx_TX_WORD_VALID_HS_LAN1 ( dphy_tx0_TX_WORD_VALID_HS_LAN1 ),
        .dphy_tx_TX_WORD_VALID_HS_LAN2 ( dphy_tx0_TX_WORD_VALID_HS_LAN2 ),
        .dphy_tx_TX_WORD_VALID_HS_LAN3 ( dphy_tx0_TX_WORD_VALID_HS_LAN3 ),
        .dphy_rx_clk_CLKOUT       ( dphy_rx0_clk_CLKOUT       ),
        .dphy_rx_RESET_N          ( dphy_rx0_RESET_N            ),
        .dphy_rx_RST0_N           ( dphy_rx0_RST0_N           ),
        .dphy_rx_ULPS_CLK_ACTIVEN ( dphy_rx0_ULPS_CLK_ACTIVEN ),
        .dphy_rx_ULPS_CLK_ENTER   ( dphy_rx0_ULPS_CLK_ENTER   ),
        .dphy_rx_ESC_LAN0_CLK ( dphy_rx0_ESC_LAN0_CLK ),
        .dphy_rx_ESC_LAN1_CLK ( dphy_rx0_ESC_LAN1_CLK ),
        .dphy_rx_ESC_LAN2_CLK ( dphy_rx0_ESC_LAN2_CLK ),
        .dphy_rx_ESC_LAN3_CLK ( dphy_rx0_ESC_LAN3_CLK ),
        .dphy_rx_LINESTATE_LAN0_ERROR ( dphy_rx0_LINESTATE_LAN0_ERROR ),
        .dphy_rx_LINESTATE_LAN1_ERROR ( dphy_rx0_LINESTATE_LAN1_ERROR ),
        .dphy_rx_LINESTATE_LAN2_ERROR ( dphy_rx0_LINESTATE_LAN2_ERROR ),
        .dphy_rx_LINESTATE_LAN3_ERROR ( dphy_rx0_LINESTATE_LAN3_ERROR ),
        .dphy_rx_ESC_LAN0_ERROR ( dphy_rx0_ESC_LAN0_ERROR ),
        .dphy_rx_ESC_LAN1_ERROR ( dphy_rx0_ESC_LAN1_ERROR ),
        .dphy_rx_ESC_LAN2_ERROR ( dphy_rx0_ESC_LAN2_ERROR ),
        .dphy_rx_ESC_LAN3_ERROR ( dphy_rx0_ESC_LAN3_ERROR ),
        .dphy_rx_STOPSTATE_LAN0 ( dphy_rx0_STOPSTATE_LAN0 ),
        .dphy_rx_STOPSTATE_LAN1 ( dphy_rx0_STOPSTATE_LAN1 ),
        .dphy_rx_STOPSTATE_LAN2 ( dphy_rx0_STOPSTATE_LAN2 ),
        .dphy_rx_STOPSTATE_LAN3 ( dphy_rx0_STOPSTATE_LAN3 ),
        .dphy_rx_HS_LAN0_VALID ( dphy_rx0_HS_LAN0_VALID ),
        .dphy_rx_HS_LAN1_VALID ( dphy_rx0_HS_LAN1_VALID ),
        .dphy_rx_HS_LAN2_VALID ( dphy_rx0_HS_LAN2_VALID ),
        .dphy_rx_HS_LAN3_VALID ( dphy_rx0_HS_LAN3_VALID ),
        .dphy_rx_HS_LAN0_DATA ( dphy_rx0_HS_LAN0_DATA ),
        .dphy_rx_HS_LAN1_DATA ( dphy_rx0_HS_LAN1_DATA ),
        .dphy_rx_HS_LAN2_DATA ( dphy_rx0_HS_LAN2_DATA ),
        .dphy_rx_HS_LAN3_DATA ( dphy_rx0_HS_LAN3_DATA ),
        .dphy_rx_HS_LAN0_SKEWCAL ( dphy_rx0_HS_LAN0_SKEWCAL ),
        .dphy_rx_HS_LAN1_SKEWCAL ( dphy_rx0_HS_LAN1_SKEWCAL ),
        .dphy_rx_HS_LAN2_SKEWCAL ( dphy_rx0_HS_LAN2_SKEWCAL ),
        .dphy_rx_HS_LAN3_SKEWCAL ( dphy_rx0_HS_LAN3_SKEWCAL ),
        .dphy_rx_HS_LAN0_SYNC ( dphy_rx0_HS_LAN0_SYNC ),
        .dphy_rx_HS_LAN1_SYNC ( dphy_rx0_HS_LAN1_SYNC ),
        .dphy_rx_HS_LAN2_SYNC ( dphy_rx0_HS_LAN2_SYNC ),
        .dphy_rx_HS_LAN3_SYNC ( dphy_rx0_HS_LAN3_SYNC ),
        .dphy_rx_HS_LAN0_SOTSYNC_ERROR ( dphy_rx0_HS_LAN0_SOTSYNC_ERROR ),
        .dphy_rx_HS_LAN1_SOTSYNC_ERROR ( dphy_rx0_HS_LAN1_SOTSYNC_ERROR ),
        .dphy_rx_HS_LAN2_SOTSYNC_ERROR ( dphy_rx0_HS_LAN2_SOTSYNC_ERROR ),
        .dphy_rx_HS_LAN3_SOTSYNC_ERROR ( dphy_rx0_HS_LAN3_SOTSYNC_ERROR ),
        .dphy_rx_ULPS_LAN0_ACTIVEN ( dphy_rx0_ULPS_LAN0_ACTIVEN ),
        .dphy_rx_ULPS_LAN1_ACTIVEN ( dphy_rx0_ULPS_LAN1_ACTIVEN ),
        .dphy_rx_ULPS_LAN2_ACTIVEN ( dphy_rx0_ULPS_LAN2_ACTIVEN ),
        .dphy_rx_ULPS_LAN3_ACTIVEN ( dphy_rx0_ULPS_LAN3_ACTIVEN ),
        .dphy_rx_ULPS_LAN0_ENTER ( dphy_rx0_ULPS_LAN0_ENTER ),
        .dphy_rx_ULPS_LAN1_ENTER ( dphy_rx0_ULPS_LAN1_ENTER ),
        .dphy_rx_ULPS_LAN2_ENTER ( dphy_rx0_ULPS_LAN2_ENTER ),
        .dphy_rx_ULPS_LAN3_ENTER ( dphy_rx0_ULPS_LAN3_ENTER ),
        .apb_paddr   ( apb0_paddr   ),
        .apb_psel    ( apb0_psel    ),
        .apb_penable ( apb0_penable ),
        .apb_pwrite  ( apb0_pwrite  ),
        .apb_pwdata  ( apb0_pwdata  ),
        .apb_prdata  ( apb0_prdata  ),
        .apb_pready  ( apb0_pready  ),
        .apb_pslverr ( apb0_pslverr ),
        .ddr_diag    ( ddr_diag     ),   // -> CSR DIAG11
        .ddr_diag2   ( fw_diag      ),   // -> CSR DIAG12
        .ddr_diag3   ( fw_diag2     ),   // -> CSR DIAG13
        .ddr_diag4   ( rd_diag14    ),   // -> CSR DIAG14
        .ddr_diag19  ( rd_diag19    ),   // -> CSR DIAG19（v4：drop/repeat）
        .ddr_diag5   ( rd_diag15    ),   // -> CSR DIAG15
        .ddr_diag7   ( fw_dbg2      ),   // -> CSR DIAG20：fw 输入侧异常
        .cap_tdata  ( cam0_cap_tdata ),     // fw 输入流（raw 直挂）
        .cap_tvalid ( cam0_cap_tvalid ),
        .cap_tlast  ( cam0_cap_tlast ),
        .cap_tuser  ( cam0_cap_tuser ),
        .fw_rstn    ( cam0_fw_rstn ),
        .fw_flush   ( cam0_fw_flush ),
        .disp_rst_req_i ( cam0_rd_flush_fire ), // v4.10c3f：reader 停流拍
                                            // 触发 tx 域显示链同步复位
        .rd_tdata   ( cam0_rd_tdata ),      // frame_reader 回放流直入 demosaic 前
        .rd_tvalid  ( cam0_rd_tvalid ),
        .rd_tlast   ( cam0_rd_tlast ),
        .rd_tuser   ( cam0_rd_tuser ),
        .rd_clk     ( pixel_clk ),          // v4：回放 CDC 写钟 = reader 域
        .rd_rstn    ( rd_rstn_148 ),        // v4：回放 CDC 写侧复位
        .disp_line_tick_o ( disp_line_tick ),// v4：显示槽节拍 -> u_rd.line_tick
        .line_room_o      ( disp_line_room ),// v4.4：行缓冲空间 -> u_rd 发射门
        .disp_sof_o       ( disp_sof ),      // v4.9：显示帧界 -> u_rd 授权锚
        .disp_stall_o     ( disp_stall ),      // v4.9：断粮预警 -> u_rd 救援授权
        .line_tick_o ( cam0_line_tick ),
        .pat_tick_aclk ( cam0_pat_tick ),   // reader 行槽（aclk 域）
        .disp_open_o ( cam0_disp_open ),    // 显示开帧脉冲 -> reader 节拍门
        // ---- cam_i2c_init（v4.11）：上电自启 + pad 直连 + 错峰链根 ----
        .cam_en        ( cam0_en ),
        .cam_scl_pad_i ( cam_0_scl_i ),
        .cam_scl_pad_o ( cam0_scl_o ),
        .cam_sda_pad_i ( cam_0_sda_i ),
        .cam_sda_pad_o ( cam0_sda_o ),
        .cam_i2c_start ( 1'b1 ),            // 复位释放后自然出上升沿
        .cam_init_done ( cam0_i2c_done )    // -> cam1 错峰 start
    );

    // cam1：2026-10-13 与 cam0 统一 v4 架构——流水线跑 pixel_clk_1080
    // 37.125M（v4.10c3m 起 top_cam 内联扁平网表，显示链唯一路径）。
    // 吞吐核算：读容量 37.125M 拍/s（=148.5Mpx/s）≥ 1080p60 供给 ~35.7M
    // 拍/s，读恒快于写，水位趋空自调。
    // 其余参数维持 1080p 板级验证组（top_cam 缺省），仅帧槽 1125
    //（1080p60：VSP+VBP+VACT+VFP+pad = 5+36+1080+4+pad）。
    top_cam #(
        .DISP_FRAME_SLOTS(16'd1125),
        // 1080p60 行内段（拍口径）：CEA 2200px÷4 = HSP 11|HBP 37|HACT
        // 480|HFP 22，HFP 挤 3 拍给 disp_timing 硬编码 GATE(1)+PREF(2)
        // ——行和 11+37+1+2+480+19=550 守卫自洽；LINE_CLKS 由像素行
        // 结构派生自动 = 550
        .HSP_CLKS(16'd11),
        .HBP_CLKS(16'd37),
        .HFP_CLKS(16'd19),
        .MODE_4K (1'b0)     // v4.11：IMX415 1080p geo 段
    ) u_cam_1 (
        .sys_clk_100m ( sys_clk_100m ),   
        .sys_clk_200m ( sys_clk_200m ),
        .sys_clk_100m_rstn ( sys_clk_100m_rstn ),
        .sys_clk_200m_rstn ( sys_clk_200m_rstn ),
        .i_clk_27m ( i_clk_27m ),
        .pll_mipi_refclk_locked ( pll_mipi_refclk_locked ),
        .tx_pixel_clk ( pixel_clk_1080 ),
        .esc_clk ( esc_clk ),
  
        .dphy_tx_WORD_CLKOUT_HS          ( dphy_tx2_WORD_CLKOUT_HS          ),
        .dphy_tx_STOPSTATE_CLK           ( dphy_tx2_STOPSTATE_CLK           ),
        .dphy_tx_STOPSTATE_LAN0          ( dphy_tx2_STOPSTATE_LAN0          ),
        .dphy_tx_STOPSTATE_LAN1          ( dphy_tx2_STOPSTATE_LAN1          ),
        .dphy_tx_STOPSTATE_LAN2          ( dphy_tx2_STOPSTATE_LAN2          ),
        .dphy_tx_STOPSTATE_LAN3          ( dphy_tx2_STOPSTATE_LAN3          ),
        .dphy_tx_TX_READY_HS_LAN0        ( dphy_tx2_TX_READY_HS_LAN0        ),
        .dphy_tx_TX_READY_HS_LAN1        ( dphy_tx2_TX_READY_HS_LAN1        ),
        .dphy_tx_TX_READY_HS_LAN2        ( dphy_tx2_TX_READY_HS_LAN2        ),
        .dphy_tx_TX_READY_HS_LAN3        ( dphy_tx2_TX_READY_HS_LAN3        ),
        .dphy_tx_TX_ULPS_ACTIVE_CLK_NOT  ( dphy_tx2_TX_ULPS_ACTIVE_CLK_NOT  ),
        .dphy_tx_TX_ULPS_ACTIVE_NOT_LAN0 ( dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN0 ),
        .dphy_tx_TX_ULPS_ACTIVE_NOT_LAN1 ( dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN1 ),
        .dphy_tx_TX_ULPS_ACTIVE_NOT_LAN2 ( dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN2 ),
        .dphy_tx_TX_ULPS_ACTIVE_NOT_LAN3 ( dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN3 ),
  
        .dphy_tx_PLL_SSC_EN          ( dphy_tx2_PLL_SSC_EN          ),
        .dphy_tx_RESET_N             ( dphy_tx2_RESET_N             ),
        .dphy_tx_TX_DATA_ESC         ( dphy_tx2_TX_DATA_ESC         ),
        .dphy_tx_TX_LPDT_ESC         ( dphy_tx2_TX_LPDT_ESC         ),
        .dphy_tx_TX_VALID_ESC        ( dphy_tx2_TX_VALID_ESC        ),
        .dphy_tx_TX_TRIGGER_ESC      ( dphy_tx2_TX_TRIGGER_ESC      ),
        .dphy_tx_TX_REQUEST_ESC_LAN0 ( dphy_tx2_TX_REQUEST_ESC_LAN0 ),
        .dphy_tx_TX_REQUEST_ESC_LAN1 ( dphy_tx2_TX_REQUEST_ESC_LAN1 ),
        .dphy_tx_TX_REQUEST_ESC_LAN2 ( dphy_tx2_TX_REQUEST_ESC_LAN2 ),
        .dphy_tx_TX_REQUEST_ESC_LAN3 ( dphy_tx2_TX_REQUEST_ESC_LAN3 ),
        .dphy_tx_TX_REQUEST_HS       ( dphy_tx2_TX_REQUEST_HS       ),
        .dphy_tx_TX_REQUEST_HS_LAN0  ( dphy_tx2_TX_REQUEST_HS_LAN0  ),
        .dphy_tx_TX_REQUEST_HS_LAN1  ( dphy_tx2_TX_REQUEST_HS_LAN1  ),
        .dphy_tx_TX_REQUEST_HS_LAN2  ( dphy_tx2_TX_REQUEST_HS_LAN2  ),
        .dphy_tx_TX_REQUEST_HS_LAN3  ( dphy_tx2_TX_REQUEST_HS_LAN3  ),
        .dphy_tx_TX_SKEW_CAL_HS_LAN0 ( dphy_tx2_TX_SKEW_CAL_HS_LAN0 ),
        .dphy_tx_TX_SKEW_CAL_HS_LAN1 ( dphy_tx2_TX_SKEW_CAL_HS_LAN1 ),
        .dphy_tx_TX_SKEW_CAL_HS_LAN2 ( dphy_tx2_TX_SKEW_CAL_HS_LAN2 ),
        .dphy_tx_TX_SKEW_CAL_HS_LAN3 ( dphy_tx2_TX_SKEW_CAL_HS_LAN3 ),
        .dphy_tx_TX_ULPS_CLK      ( dphy_tx2_TX_ULPS_CLK      ),
        .dphy_tx_TX_ULPS_ESC_LAN0 ( dphy_tx2_TX_ULPS_ESC_LAN0 ),
        .dphy_tx_TX_ULPS_ESC_LAN1 ( dphy_tx2_TX_ULPS_ESC_LAN1 ),
        .dphy_tx_TX_ULPS_ESC_LAN2 ( dphy_tx2_TX_ULPS_ESC_LAN2 ),
        .dphy_tx_TX_ULPS_ESC_LAN3 ( dphy_tx2_TX_ULPS_ESC_LAN3 ),
        .dphy_tx_TX_ULPS_EXIT      ( dphy_tx2_TX_ULPS_EXIT      ),
        .dphy_tx_TX_ULPS_EXIT_LAN0 ( dphy_tx2_TX_ULPS_EXIT_LAN0 ),
        .dphy_tx_TX_ULPS_EXIT_LAN1 ( dphy_tx2_TX_ULPS_EXIT_LAN1 ),
        .dphy_tx_TX_ULPS_EXIT_LAN2 ( dphy_tx2_TX_ULPS_EXIT_LAN2 ),
        .dphy_tx_TX_ULPS_EXIT_LAN3 ( dphy_tx2_TX_ULPS_EXIT_LAN3 ),
        .dphy_tx_TX_DATA_HS_LAN0 ( dphy_tx2_TX_DATA_HS_LAN0 ),
        .dphy_tx_TX_DATA_HS_LAN1 ( dphy_tx2_TX_DATA_HS_LAN1 ),
        .dphy_tx_TX_DATA_HS_LAN2 ( dphy_tx2_TX_DATA_HS_LAN2 ),
        .dphy_tx_TX_DATA_HS_LAN3 ( dphy_tx2_TX_DATA_HS_LAN3 ),
        .dphy_tx_TX_WORD_VALID_HS_LAN0 ( dphy_tx2_TX_WORD_VALID_HS_LAN0 ),
        .dphy_tx_TX_WORD_VALID_HS_LAN1 ( dphy_tx2_TX_WORD_VALID_HS_LAN1 ),
        .dphy_tx_TX_WORD_VALID_HS_LAN2 ( dphy_tx2_TX_WORD_VALID_HS_LAN2 ),
        .dphy_tx_TX_WORD_VALID_HS_LAN3 ( dphy_tx2_TX_WORD_VALID_HS_LAN3 ),
        .dphy_rx_clk_CLKOUT       ( dphy_rx2_clk_CLKOUT       ),
        .dphy_rx_RESET_N          ( dphy_rx2_RESET_N           ),
        .dphy_rx_RST0_N           ( dphy_rx2_RST0_N           ),
        .dphy_rx_ULPS_CLK_ACTIVEN ( dphy_rx2_ULPS_CLK_ACTIVEN ),
        .dphy_rx_ULPS_CLK_ENTER   ( dphy_rx2_ULPS_CLK_ENTER   ),
        .dphy_rx_ESC_LAN0_CLK ( dphy_rx2_ESC_LAN0_CLK ),
        .dphy_rx_ESC_LAN1_CLK ( dphy_rx2_ESC_LAN1_CLK ),
        .dphy_rx_ESC_LAN2_CLK ( dphy_rx2_ESC_LAN2_CLK ),
        .dphy_rx_ESC_LAN3_CLK ( dphy_rx2_ESC_LAN3_CLK ),
        .dphy_rx_LINESTATE_LAN0_ERROR ( dphy_rx2_LINESTATE_LAN0_ERROR ),
        .dphy_rx_LINESTATE_LAN1_ERROR ( dphy_rx2_LINESTATE_LAN1_ERROR ),
        .dphy_rx_LINESTATE_LAN2_ERROR ( dphy_rx2_LINESTATE_LAN2_ERROR ),
        .dphy_rx_LINESTATE_LAN3_ERROR ( dphy_rx2_LINESTATE_LAN3_ERROR ),
        .dphy_rx_ESC_LAN0_ERROR ( dphy_rx2_ESC_LAN0_ERROR ),
        .dphy_rx_ESC_LAN1_ERROR ( dphy_rx2_ESC_LAN1_ERROR ),
        .dphy_rx_ESC_LAN2_ERROR ( dphy_rx2_ESC_LAN2_ERROR ),
        .dphy_rx_ESC_LAN3_ERROR ( dphy_rx2_ESC_LAN3_ERROR ),
        .dphy_rx_STOPSTATE_LAN0 ( dphy_rx2_STOPSTATE_LAN0 ),
        .dphy_rx_STOPSTATE_LAN1 ( dphy_rx2_STOPSTATE_LAN1 ),
        .dphy_rx_STOPSTATE_LAN2 ( dphy_rx2_STOPSTATE_LAN2 ),
        .dphy_rx_STOPSTATE_LAN3 ( dphy_rx2_STOPSTATE_LAN3 ),
        .dphy_rx_HS_LAN0_VALID ( dphy_rx2_HS_LAN0_VALID ),
        .dphy_rx_HS_LAN1_VALID ( dphy_rx2_HS_LAN1_VALID ),
        .dphy_rx_HS_LAN2_VALID ( dphy_rx2_HS_LAN2_VALID ),
        .dphy_rx_HS_LAN3_VALID ( dphy_rx2_HS_LAN3_VALID ),
        .dphy_rx_HS_LAN0_DATA ( dphy_rx2_HS_LAN0_DATA ),
        .dphy_rx_HS_LAN1_DATA ( dphy_rx2_HS_LAN1_DATA ),
        .dphy_rx_HS_LAN2_DATA ( dphy_rx2_HS_LAN2_DATA ),
        .dphy_rx_HS_LAN3_DATA ( dphy_rx2_HS_LAN3_DATA ),
        .dphy_rx_HS_LAN0_SKEWCAL ( dphy_rx2_HS_LAN0_SKEWCAL ),
        .dphy_rx_HS_LAN1_SKEWCAL ( dphy_rx2_HS_LAN1_SKEWCAL ),
        .dphy_rx_HS_LAN2_SKEWCAL ( dphy_rx2_HS_LAN2_SKEWCAL ),
        .dphy_rx_HS_LAN3_SKEWCAL ( dphy_rx2_HS_LAN3_SKEWCAL ),
        .dphy_rx_HS_LAN0_SYNC ( dphy_rx2_HS_LAN0_SYNC ),
        .dphy_rx_HS_LAN1_SYNC ( dphy_rx2_HS_LAN1_SYNC ),
        .dphy_rx_HS_LAN2_SYNC ( dphy_rx2_HS_LAN2_SYNC ),
        .dphy_rx_HS_LAN3_SYNC ( dphy_rx2_HS_LAN3_SYNC ),
        .dphy_rx_HS_LAN0_SOTSYNC_ERROR ( dphy_rx2_HS_LAN0_SOTSYNC_ERROR ),
        .dphy_rx_HS_LAN1_SOTSYNC_ERROR ( dphy_rx2_HS_LAN1_SOTSYNC_ERROR ),
        .dphy_rx_HS_LAN2_SOTSYNC_ERROR ( dphy_rx2_HS_LAN2_SOTSYNC_ERROR ),
        .dphy_rx_HS_LAN3_SOTSYNC_ERROR ( dphy_rx2_HS_LAN3_SOTSYNC_ERROR ),
        .dphy_rx_ULPS_LAN0_ACTIVEN ( dphy_rx2_ULPS_LAN0_ACTIVEN ),
        .dphy_rx_ULPS_LAN1_ACTIVEN ( dphy_rx2_ULPS_LAN1_ACTIVEN ),
        .dphy_rx_ULPS_LAN2_ACTIVEN ( dphy_rx2_ULPS_LAN2_ACTIVEN ),
        .dphy_rx_ULPS_LAN3_ACTIVEN ( dphy_rx2_ULPS_LAN3_ACTIVEN ),
        .dphy_rx_ULPS_LAN0_ENTER ( dphy_rx2_ULPS_LAN0_ENTER ),
        .dphy_rx_ULPS_LAN1_ENTER ( dphy_rx2_ULPS_LAN1_ENTER ),
        .dphy_rx_ULPS_LAN2_ENTER ( dphy_rx2_ULPS_LAN2_ENTER ),
        .dphy_rx_ULPS_LAN3_ENTER ( dphy_rx2_ULPS_LAN3_ENTER ),
        .apb_paddr   ( apb1_paddr   ),
        .apb_psel    ( apb1_psel    ),
        .apb_penable ( apb1_penable ),
        .apb_pwrite  ( apb1_pwrite  ),
        .apb_pwdata  ( apb1_pwdata  ),
        .apb_prdata  ( apb1_prdata  ),
        .apb_pready  ( apb1_pready  ),
        .apb_pslverr ( apb1_pslverr ),
        .ddr_diag    ( 32'h0        ),   // cam1 不挂 DDR 自检（DIAG11 恒 0）
        .ddr_diag2   ( cam1_fw_diag  ),  // -> CSR DIAG12：fw1 {frame, line}
        .ddr_diag3   ( cam1_fw_diag2 ),  // -> CSR DIAG13：fw1 {ovf, pad}
        .ddr_diag4   ( cam1_rd_diag14 ), // -> CSR DIAG14：rd1 {frame, st, line}
        .ddr_diag19  ( cam1_rd_diag19 ), // -> CSR DIAG19：rd1 drop/repeat
        .ddr_diag5   ( cam1_rd_diag15 ), // -> CSR DIAG15：rd1 err
        .ddr_diag7   ( cam1_fw_dbg2  ),  // -> CSR DIAG20：fw1 输入侧异常
        // 阶段5：cam1 DDR 回放链全接（写侧 cap 直挂 u_fw1；读侧 u_rd1 经
        // axi_rd_cdc -> u_rd_arb S0 -> DDR target1，回放流回本 demosaic 前）
        .cap_tdata  ( cam1_cap_tdata ),
        .cap_tvalid ( cam1_cap_tvalid ),
        .cap_tlast  ( cam1_cap_tlast ),
        .cap_tuser  ( cam1_cap_tuser ),
        .fw_rstn    ( cam1_fw_rstn ),
        .fw_flush   ( cam1_fw_flush ),
        .disp_rst_req_i ( cam1_rd_flush_fire ), // reader flush 执行拍 ->
                                            // tx 域显示链同步复位（同 cam0）
        .rd_tdata   ( cam1_rd_tdata ),      // u_rd1 回放流直入 demosaic 前
        .rd_tvalid  ( cam1_rd_tvalid ),
        .rd_tlast   ( cam1_rd_tlast ),
        .rd_tuser   ( cam1_rd_tuser ),
        .rd_clk     ( pixel_clk_1080 ),     // 回放域 = cam1 显示域（同钟直连）
        .rd_rstn    ( rd_rstn_1080 ),       // 回放域复位（DDR CFG 完成树）
        .disp_line_tick_o ( cam1_disp_line_tick ), // 显示槽节拍 -> u_rd1
        .line_room_o      ( cam1_disp_line_room ), // 行缓冲空间 -> u_rd1
        .disp_sof_o       ( cam1_disp_sof ),       // 显示帧界 -> u_rd1 锚
        .disp_stall_o     ( cam1_disp_stall ),     // 断粮预警 -> u_rd1 救援
        .line_tick_o (            ),
        .pat_tick_aclk (          ),
        // ---- cam_i2c_init（v4.11）：错峰启动（Q4）——start 接 cam0
        //      init_done 电平，cam0 配置完成后释放出上升沿；rerun 走
        //      本实例 CSR（APB1）DIAG7@0x1C
        .cam_en        ( cam1_en ),
        .cam_scl_pad_i ( cam_1_scl_i ),
        .cam_scl_pad_o ( cam1_scl_o ),
        .cam_sda_pad_i ( cam_1_sda_i ),
        .cam_sda_pad_o ( cam1_sda_o ),
        .cam_i2c_start ( cam0_i2c_done ),
        .cam_init_done ( cam1_i2c_done )    // 悬空（观测走 APB1 DIAG3；
                                            // wire 留作 TB 层次探测）
    );

endmodule
