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
//    pixel_clk    : shape 读侧 / my_csi2_tx 像素域 + pattern_gen 行节拍源
//                   （板级 37.125MHz = 1080p60@PPC4）
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
//  DDR：直连架构不再使用。ddr_inst 引脚绑定保留（peri.xml 不动），双端口
//    全 idle + CFG FSM 照常初始化 DDR 硬核（已验证行为，不引入新变量）。
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
  (* syn_peri_port = 0 *) input i_clk_27m,
  (* syn_peri_port = 0 *) input pixel_clk,
  (* syn_peri_port = 0 *) input esc_clk,
  (* syn_peri_port = 0 *) input mipi_refclk_25m,
  (* syn_peri_port = 0 *) output pll_mipi_refclk_rstn,
  (* syn_peri_port = 0 *) output pll_csi_rstn,
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
    assign pll_mipi_refclk_rstn = i_arstn;
    assign pll_csi_rstn         = i_arstn;
    assign pll_ddr_rstn         = i_arstn;
    assign pll_sys_rstn         = i_arstn;

    wire sys_clk_100m_rstn, sys_clk_200m_rstn;

    reset_ctrl #(.NUM_RST(1), .IN_RST_ACTIVE(1'b0), .OUT_RST_ACTIVE(1'b0)) u_rx_rst_100m (
        .i_arst (pll_sys_locked), .i_clk (sys_clk_100m),  .o_srst (sys_clk_100m_rstn)
    );
    reset_ctrl #(.NUM_RST(1), .IN_RST_ACTIVE(1'b0), .OUT_RST_ACTIVE(1'b0)) u_rx_rst_pixel (
        .i_arst (pll_sys_locked), .i_clk (sys_clk_200m), .o_srst (sys_clk_200m_rstn)
    );



    // SoC GPIO0 write value: bit0 = camera enable (cam_0_en) bit1 = camera enable (cam_1_en)
    wire [3:0] w_gpio_write;
    assign cam_0_en = w_gpio_write[0];   // 0 after power-up (reg init), SW timed sequence
    assign cam_1_en = w_gpio_write[1];   // 0 after power-up (reg init), SW timed sequence

    // Camera I2C open-drain emulation:
    //   SaxonSoc I2C "write" semantics = drive low when 0, release when 1.
    wire w_i2c_0_scl_write, w_i2c_0_sda_write;
    wire w_i2c_0_scl_read,  w_i2c_0_sda_read;
    assign w_i2c_0_scl_read = cam_0_scl_i;
    assign cam_0_scl_o      = 1'b0;
    assign cam_0_scl_oe     = ~w_i2c_0_scl_write;
    assign w_i2c_0_sda_read = cam_0_sda_i;
    assign cam_0_sda_o      = 1'b0;
    assign cam_0_sda_oe     = ~w_i2c_0_sda_write;

    wire w_i2c_1_scl_write, w_i2c_1_sda_write;
    wire w_i2c_1_scl_read,  w_i2c_1_sda_read;
    assign w_i2c_1_scl_read = cam_1_scl_i;
    assign cam_1_scl_o      = 1'b0;
    assign cam_1_scl_oe     = ~w_i2c_1_scl_write;
    assign w_i2c_1_sda_read = cam_1_sda_i;
    assign cam_1_sda_o      = 1'b0;
    assign cam_1_sda_oe     = ~w_i2c_1_sda_write;


    //-------------------------------------------------------------------------
    // LPDDR 配置 FSM（照搬 top_demo：上电计 256 拍后 CFG_START，等 CFG_DONE）
    //-------------------------------------------------------------------------
    localparam [1:0] IDLE      = 2'b00,
                     CFG_START = 2'b01,
                     CFG_DONE  = 2'b11;

    reg  [1:0]  cfg_st, cfg_next;
    reg  [7:0]  cfg_count;
    wire        ddr_cfg_ok;

    assign ddr_cfg_ok = (cfg_st == CFG_DONE);

    always_ff @(posedge sys_clk_200m or negedge sys_clk_200m_rstn) begin
        if (~sys_clk_200m_rstn) begin
            cfg_st    <= IDLE;
            cfg_count <= 8'h0;
        end else begin
            cfg_st <= cfg_next;
            if (cfg_st == IDLE)
                cfg_count <= cfg_count + 1'b1;
            else
                cfg_count <= 8'h0;
        end
    end

    always_comb begin
        cfg_next = cfg_st;
        case (cfg_st)
            IDLE: begin
                if (cfg_count == 8'hff)
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
    // DDR 双端口全 idle（直连架构无人访问；ARSTN 随 CFG 完成释放）
    //-------------------------------------------------------------------------
    // port 0
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
    assign ddr_inst_ARSTN_0     = ddr_cfg_ok;
    assign ddr_inst_ARVALID_0   = 1'b0;
    assign ddr_inst_ARADDR_0    = 33'h0;
    assign ddr_inst_ARBURST_0   = 2'h0;
    assign ddr_inst_ARID_0      = 6'h0;
    assign ddr_inst_ARLEN_0     = 8'h0;
    assign ddr_inst_ARLOCK_0    = 1'b0;
    assign ddr_inst_ARQOS_0     = 4'h0;
    assign ddr_inst_ARSIZE_0    = 3'h0;
    assign ddr_inst_RREADY_0    = 1'b1;
    // port 1
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
    assign ddr_inst_ARSTN_1     = ddr_cfg_ok;
    assign ddr_inst_ARVALID_1   = 1'b0;
    assign ddr_inst_ARADDR_1    = 33'h0;
    assign ddr_inst_ARBURST_1   = 2'h0;
    assign ddr_inst_ARID_1      = 6'h0;
    assign ddr_inst_ARLEN_1     = 8'h0;
    assign ddr_inst_ARLOCK_1    = 1'b0;
    assign ddr_inst_ARQOS_1     = 4'h0;
    assign ddr_inst_ARSIZE_1    = 3'h0;
    assign ddr_inst_RREADY_1    = 1'b1;

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


    top_cam u_cam_0 (
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
        .apb_pslverr ( apb0_pslverr )
    );

    top_cam u_cam_1 (
        .sys_clk_100m ( sys_clk_100m ),   
        .sys_clk_200m ( sys_clk_200m ),
        .sys_clk_100m_rstn ( sys_clk_100m_rstn ),
        .sys_clk_200m_rstn ( sys_clk_200m_rstn ),
        .i_clk_27m ( i_clk_27m ),
        .pll_mipi_refclk_locked ( pll_mipi_refclk_locked ),
        .tx_pixel_clk ( pixel_clk ),
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
        .apb_pslverr ( apb1_pslverr )
    );

endmodule
