/////////////////////////////////////////////////////////////////////////////
//           _____       
//          / _______    Copyright (C) 2013-2020 Efinix Inc. All rights reserved.
//         / /       \   
//        / /  ..    /   
//       / / .'     /    
//    __/ /.'      /     
//   __   \       /      
//  /_/ /\ \_____/ /     
// ____/  \_______/      
//
// *******************************
// Revisions:
// 1.0 Initial rev
//
// *******************************
`timescale 1 ns / 1 ns
//`include "header.v"  // use JTAG hard block

module ws_e1_tse
(
//Globle Signals
//----pll_0
input                           clk_50m,
input                           clk_125m,
input                           pll_0_locked,
input                           pll_rgmii_rx_clk,
input                           pll_rgmii_locked,
output wire                     pll_rstn,
output wire                     pll_rgmii_rstn,

//TEMAC PHY RGMII Interface
output  wire    [3:0]           rgmii_txd_HI,
output  wire    [3:0]           rgmii_txd_LO,
// output  wire                    rgmii_tx_ctl,
output  wire                    rgmii_tx_ctl_HI,
output  wire                    rgmii_tx_ctl_LO,
output  wire                    rgmii_txc_HI,
output  wire                    rgmii_txc_LO,
// RGMII RX data：Interface Designer 生成 4 路独立 DDIO
// （LO 主名/HI 交换 + pipeline = falling edge 采样，匹配 IP 参数 RGMII_RXC_EDGE=1）
input                           rgmii_rxd0_HI,
input                           rgmii_rxd0_LO,
input                           rgmii_rxd1_HI,
input                           rgmii_rxd1_LO,
input                           rgmii_rxd2_HI,
input                           rgmii_rxd2_LO,
input                           rgmii_rxd3_HI,
input                           rgmii_rxd3_LO,
// input                           rgmii_rx_ctl,
input                           rgmii_rx_ctl_HI,
input                           rgmii_rx_ctl_LO,
input                           rgmii_rxc,
//TEMAC PHY Ctr Interface
// 注意：载板 ws-e1-base 无 ETH 复位网络（见 pinout/ws-e1-base-v1.csv），
// 故顶层不导出 phy_rstn，避免产生 Unassigned Core Pin。PHY 复位由板级硬件完成。
`ifdef SIM_MODE
// 仿真：SoC 缺位，APB3 master 由 testbench 驱动（模拟固件总线写序列）
input  wire [15:0]              apb3_paddr,
input  wire                     apb3_psel,
input  wire                     apb3_penable,
input  wire                     apb3_pwrite,
input  wire [31:0]              apb3_pwdata,
output wire                     apb3_pready,
output wire [31:0]              apb3_prdata,
output wire                     apb3_pslverror,
`endif
//hardware Jtag Interface

`ifndef SIM_MODE

`ifndef SOFT_TAP
input                           jtag_inst1_TCK,
input                           jtag_inst1_TDI,
output  wire                    jtag_inst1_TDO,
input                           jtag_inst1_SEL,
input                           jtag_inst1_CAPTURE,
input                           jtag_inst1_SHIFT,
input                           jtag_inst1_UPDATE,
input                           jtag_inst1_RESET,
`else
//software Jtag Interface
input                           io_jtag_tms,
input                           io_jtag_tdi,
output  wire                    io_jtag_tdo,
input                           io_jtag_tck,
`endif

//Debug Signals
//output  wire    [1:0]           debug_led
output  wire                    system_uart_0_io_txd,
input                           system_uart_0_io_rxd,
`endif
//TEMAC PHY MDIO Interface
input                           phy_mdi,
output  wire                    phy_mdo,
output  wire                    phy_mdo_en,
output  wire                    phy_mdc,

// ===================== Camera CSI-2 链路（P1/G8，peri 硬核端口）=====================
// syn_peri_port=0：非物理芯片引脚，Interface Designer 硬核/IO 寄存器按名自动连接
//（用法同 helloworld.v 的 clk 端口；名字与 constraints/cam_csi2_bootstrap.isf 一致）
// SIM_MODE 下这些端口由 testbench 悬空（z），相机域 always 块不触发，探针保持初值
// clk_100m/clk_200m：pll_0 直接输出（2026-11-06 移除 pll_csi，统一由 pll_0 供时钟：
// 50/125/125/100/200M，VCO=1000；IO 寄存器与 DPHY CFG_CLK 同步改挂新时钟名）
(* syn_peri_port = 0 *) input                           clk_100m,
(* syn_peri_port = 0 *) input                           clk_200m,
// DPHY RX2 控制/状态（端口名与 ISF 引脚属性值逐一精确匹配，参考工程同构）
(* syn_peri_port = 0 *) input                           dphy_rx2_clk_CLKOUT,
(* syn_peri_port = 0 *) output                          dphy_rx2_RESET_N,
(* syn_peri_port = 0 *) output                          dphy_rx2_RST0_N,
(* syn_peri_port = 0 *) input                           dphy_rx2_STOPSTATE_CLK,
(* syn_peri_port = 0 *) input                           dphy_rx2_RX_CLK_ACTIVE_HS,
(* syn_peri_port = 0 *) input                           dphy_rx2_ERR_SOT_HS_LAN0,
(* syn_peri_port = 0 *) input                           dphy_rx2_ERR_SOT_HS_LAN1,
(* syn_peri_port = 0 *) input                           dphy_rx2_ERR_SOT_HS_LAN2,
(* syn_peri_port = 0 *) input                           dphy_rx2_ERR_SOT_HS_LAN3,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN0_SOTSYNC_ERROR,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN1_SOTSYNC_ERROR,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN2_SOTSYNC_ERROR,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN3_SOTSYNC_ERROR,
(* syn_peri_port = 0 *) input                           dphy_rx2_ESC_LAN0_ERROR,
(* syn_peri_port = 0 *) input                           dphy_rx2_ESC_LAN1_ERROR,
(* syn_peri_port = 0 *) input                           dphy_rx2_ESC_LAN2_ERROR,
(* syn_peri_port = 0 *) input                           dphy_rx2_ESC_LAN3_ERROR,
(* syn_peri_port = 0 *) input                           dphy_rx2_LINESTATE_LAN0_ERROR,
(* syn_peri_port = 0 *) input                           dphy_rx2_LINESTATE_LAN1_ERROR,
(* syn_peri_port = 0 *) input                           dphy_rx2_LINESTATE_LAN2_ERROR,
(* syn_peri_port = 0 *) input                           dphy_rx2_LINESTATE_LAN3_ERROR,
(* syn_peri_port = 0 *) input                           dphy_rx2_ESC_LAN0_CLK,
(* syn_peri_port = 0 *) input                           dphy_rx2_ESC_LAN1_CLK,
(* syn_peri_port = 0 *) input                           dphy_rx2_ESC_LAN2_CLK,
(* syn_peri_port = 0 *) input                           dphy_rx2_ESC_LAN3_CLK,
(* syn_peri_port = 0 *) input                           dphy_rx2_ULPS_CLK_ENTER,
(* syn_peri_port = 0 *) input                           dphy_rx2_ULPS_CLK_ACTIVEN,
(* syn_peri_port = 0 *) input                           dphy_rx2_ULPS_LAN0_ENTER,
(* syn_peri_port = 0 *) input                           dphy_rx2_ULPS_LAN1_ENTER,
(* syn_peri_port = 0 *) input                           dphy_rx2_ULPS_LAN2_ENTER,
(* syn_peri_port = 0 *) input                           dphy_rx2_ULPS_LAN3_ENTER,
(* syn_peri_port = 0 *) input                           dphy_rx2_ULPS_LAN0_ACTIVEN,
(* syn_peri_port = 0 *) input                           dphy_rx2_ULPS_LAN1_ACTIVEN,
(* syn_peri_port = 0 *) input                           dphy_rx2_ULPS_LAN2_ACTIVEN,
(* syn_peri_port = 0 *) input                           dphy_rx2_ULPS_LAN3_ACTIVEN,
(* syn_peri_port = 0 *) input                           dphy_rx2_STOPSTATE_LAN0,
(* syn_peri_port = 0 *) input                           dphy_rx2_STOPSTATE_LAN1,
(* syn_peri_port = 0 *) input                           dphy_rx2_STOPSTATE_LAN2,
(* syn_peri_port = 0 *) input                           dphy_rx2_STOPSTATE_LAN3,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN0_SYNC,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN1_SYNC,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN2_SYNC,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN3_SYNC,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN0_SKEWCAL,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN1_SKEWCAL,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN2_SKEWCAL,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN3_SKEWCAL,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN0_VALID,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN1_VALID,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN2_VALID,
(* syn_peri_port = 0 *) input                           dphy_rx2_HS_LAN3_VALID,
(* syn_peri_port = 0 *) input [15:0]                    dphy_rx2_HS_LAN0_DATA,
(* syn_peri_port = 0 *) input [15:0]                    dphy_rx2_HS_LAN1_DATA,
(* syn_peri_port = 0 *) input [15:0]                    dphy_rx2_HS_LAN2_DATA,
(* syn_peri_port = 0 *) input [15:0]                    dphy_rx2_HS_LAN3_DATA,
// cam I2C pad（IO 寄存器化，clk_200m 域）
// 端口名必须与 peri.xml/interface.csv 的 pad 信号名一致（cam_1_scl_IN/OUT/OE
// 命名），否则 map 将 RTL 端口当无约束 IO 随机摆位、I2C 物理不通
//（2026-11-06 G8 教训：旧名 cam_1_scl_i/o/oe 曾致 6 个 IO cell random placement）
(* syn_peri_port = 0 *) output                          cam_1_en,
(* syn_peri_port = 0 *) input                           cam_1_scl_IN,
(* syn_peri_port = 0 *) output                          cam_1_scl_OUT,
(* syn_peri_port = 0 *) output                          cam_1_scl_OE,
(* syn_peri_port = 0 *) input                           cam_1_sda_IN,
(* syn_peri_port = 0 *) output                          cam_1_sda_OUT,
(* syn_peri_port = 0 *) output                          cam_1_sda_OE
);
// Parameter Define 
`include "ip/mytse/mytse_define.svh"

// Register Define

// Wire Define
wire                            clk_50m_rstn;
wire                            clk_100m_rstn;  // 前向声明：L565 等处在声明式赋值（复位链区）之前
wire                            clk_200m_rstn;  //   已有消费，无 default_nettype none 会隐式分裂同名网
wire                            mac_reset;
wire                            proto_reset;
wire                            mac_rstn;
//AXI4-Stream Interface
wire                            rx_axis_clk;
wire    [7:0]                   rx_axis_mac_tdata;
wire                            rx_axis_mac_tvalid;
wire                            rx_axis_mac_tlast;
wire                            rx_axis_mac_tuser;
wire                            rx_axis_mac_tready;
wire                            tx_axis_clk;
wire    [7:0]                   tx_axis_mac_tdata;
wire                            tx_axis_mac_tvalid;
wire                            tx_axis_mac_tlast;
wire                            tx_axis_mac_tuser;
wire                            tx_axis_mac_tready;
wire    [7:0]                   udp_tx_axis_mac_tdata;
wire                            udp_tx_axis_mac_tvalid;
wire                            udp_tx_axis_mac_tlast;
wire                            udp_tx_axis_mac_tready;
wire    [7:0]                   mac_tx_axis_mac_tdata;
wire                            mac_tx_axis_mac_tvalid;
wire                            mac_tx_axis_mac_tlast;
wire                            mac_tx_axis_mac_tready;
wire    [7:0]                   pat_tx_axis_mac_tdata;
wire                            pat_tx_axis_mac_tvalid;
wire                            pat_tx_axis_mac_tlast;
wire                            pat_tx_axis_mac_tuser;
wire                            pat_tx_axis_mac_tready;
wire    [7:0]                   loop_tx_axis_mac_tdata;
wire                            loop_tx_axis_mac_tvalid;
wire                            loop_tx_axis_mac_tlast;
wire                            loop_tx_axis_mac_tuser;
wire                            loop_tx_axis_mac_tready;
//RiscV APB3 Interface
`ifdef SIM_MODE
//（SIM_MODE 下 apb3_* 已提升为顶层端口，由 testbench 驱动，不再声明内部 wire）
`else
wire    [15:0]                  apb3_paddr;
wire                            apb3_psel;
wire                            apb3_penable;
wire                            apb3_pready;
wire                            apb3_pwrite;
wire    [31:0]                  apb3_pwdata;
wire    [31:0]                  apb3_prdata;
wire                            apb3_pslverror;
`endif
//Mac APB3 Interface
wire    [9:0]                   mac_apb3_paddr;
wire                            mac_apb3_psel;
wire                            mac_apb3_penable;
wire                            mac_apb3_pready;
wire                            mac_apb3_pwrite;
wire    [31:0]                  mac_apb3_pwdata;
wire    [31:0]                  mac_apb3_prdata;
wire                            mac_apb3_pslverror;
//Ex APB3 Interface
wire    [9:0]                   ex_apb3_paddr;
wire                            ex_apb3_psel;
wire                            ex_apb3_penable;
wire                            ex_apb3_pready;
wire                            ex_apb3_pwrite;
wire    [31:0]                  ex_apb3_pwdata;
wire    [31:0]                  ex_apb3_prdata;
wire                            ex_apb3_pslverror;
//AXI4-Lite Interface
wire    [9:0]                   axi_awaddr;
wire                            axi_awvalid;
wire                            axi_awready;
wire    [31:0]                  axi_wdata;
wire                            axi_wvalid;
wire                            axi_wready;
wire    [1:0]                   axi_bresp;
wire                            axi_bvalid;
wire                            axi_bready;
wire    [9:0]                   axi_araddr;
wire                            axi_arvalid;
wire                            axi_arready;
wire    [1:0]                   axi_rresp;
wire    [31:0]                  axi_rdata;
wire                            axi_rvalid;
wire                            axi_rready;
//Cfg Space Registers
wire                            mac_sw_rst;
wire                            axi4_st_mux_select;
wire                            pat_mux_select;
wire                            udp_pat_gen_en;
wire                            mac_pat_gen_en;
wire    [15:0]                  pat_gen_num;
wire    [15:0]                  pat_gen_ipg;
wire    [47:0]                  pat_dst_mac;
wire    [47:0]                  pat_src_mac;
wire    [15:0]                  pat_mac_dlen;
wire    [31:0]                  pat_src_ip;
wire    [31:0]                  pat_dst_ip;
wire    [15:0]                  pat_src_port;
wire    [15:0]                  pat_dst_port;
wire    [15:0]                  pat_udp_dlen;
wire                            eth_sw_tx_sel;
//Ethernet Packet FIFO (CPU RX/TX path)——与 reg_apb3/eth_pkt_fifo 间的显式 wire
//（此前未声明，隐式 1 位 wire 导致 word_cnt/free_cnt 位截断，读数不可信）
wire    [11:0]                  eth_rx_word_cnt;
wire                            eth_rx_overflow;
wire                            eth_rx_overflow_clr;
wire                            eth_rx_rd_en;
wire    [9:0]                   eth_rx_rddata;
wire    [12:0]                  eth_tx_free_cnt;
wire                            eth_tx_full;
wire    [8:0]                   eth_tx_wrdata;
wire                            eth_tx_wr_en;
//Ethernet Packet FIFO (CPU RX/TX path)
wire    [7:0]                   sw_tx_axis_mac_tdata;
wire                            sw_tx_axis_mac_tvalid;
wire                            sw_tx_axis_mac_tlast;
wire                            sw_tx_axis_mac_tuser;
wire                            sw_tx_axis_mac_tready;
wire    [1:0]                   tx_mux_select;
wire  [31:0]                  frame_num_dbg;      //v2 已发帧号（诊断，暂未引出）
wire  [9:0]                   pat_dbg_w;          //v2 状态探针 {raw10_r,pat_en,inf,state[2:0],frame_tick,en_d1,0}
wire  [1:0]                   pat_mode;           //RAW10 图案选择（reg_apb3 0x208[5:4] → raw10_pat_src，G11n16 迁移）
wire                          pat_gen_kill;       //包边界停车（0x208[3] → udp_pat_gen_v2，2026-11-06 模式切换）

//RX 诊断探针：双时钟计数，一次读数二分"引脚无时钟"vs"PLL 输出无时钟"
//rxc_pin_cnt：rgmii_rxc 引脚 fabric 镜像计数；pll_cnt：PLL 输出计数。
//跨域读取允许撕裂，仅作诊断判 0/非 0 用。
reg  [15:0] dbg_rxc_pin_cnt;
reg  [15:0] dbg_pll_cnt;
wire [15:0] eth_dbg_rxc_cnt  = dbg_rxc_pin_cnt;
wire [15:0] eth_dbg_pll_cnt  = dbg_pll_cnt;
always @(posedge rgmii_rxc)        dbg_rxc_pin_cnt <= dbg_rxc_pin_cnt + 16'd1;
always @(posedge pll_rgmii_rx_clk) dbg_pll_cnt     <= dbg_pll_cnt     + 16'd1;

//TSE DDIO
//wire                            rgmii_rx_ctl_LO;
//wire                            rgmii_rx_ctl_HI;
// wire                            rgmii_tx_ctl_LO;
// wire                            rgmii_tx_ctl_HI;
/*----------------------------------------------------------------------------------*\
                                 The main code
\*----------------------------------------------------------------------------------*/
assign pll_rstn = 1;
assign pll_rgmii_rstn = 1;
/*----------------------- Clock Region -----------------------*/
//手册 Table 5：1G @ AXIS 8bit 要求 axis 时钟 ≥125MHz。官方例子接 50M 是因为
//UDP/MAC pattern 生成器组合逻辑多无法过 125M 时序；软件帧路径（eth_pkt_fifo）
//与回环路径为寄存器化逻辑，按最低频率要求接 clk_125m（125M，8ns）。
assign rx_axis_clk = clk_125m;
assign tx_axis_clk = clk_125m;


/*----------------------- Reset Region -----------------------*/
//assign pll_0_reset = 1'b0;
assign clk_50m_rstn = pll_0_locked;
assign mac_reset = ~pll_0_locked & ~pll_rgmii_locked;
assign proto_reset = mac_sw_rst;
assign mac_rstn = ~(mac_reset || proto_reset);

/*----------------------- MCU Module ----------------------------*/
`ifndef SIM_MODE
myriscv u_mcu
(
//user custom ports
	//SOC
    .io_systemClk               (clk_50m                    ),
    .io_asyncReset              (1'b0                       ),
    .system_uart_0_io_txd       (system_uart_0_io_txd       ),
    .system_uart_0_io_rxd       (system_uart_0_io_rxd       ),
    .jtagCtrl_tck               (jtag_inst1_TCK             ),
    .jtagCtrl_tdi               (jtag_inst1_TDI             ),
    .jtagCtrl_tdo               (jtag_inst1_TDO             ),
    .jtagCtrl_enable            (jtag_inst1_SEL             ),
    .jtagCtrl_capture           (jtag_inst1_CAPTURE         ),
    .jtagCtrl_shift             (jtag_inst1_SHIFT           ),
    .jtagCtrl_update            (jtag_inst1_UPDATE          ),
    .jtagCtrl_reset             (jtag_inst1_RESET           ),
//APB3 Master Interface
    .io_apbSlave_0_PADDR        (apb3_paddr                 ),
    .io_apbSlave_0_PSEL         (apb3_psel                  ),
    .io_apbSlave_0_PENABLE      (apb3_penable               ),
    .io_apbSlave_0_PREADY       (apb3_pready                ),
    .io_apbSlave_0_PWRITE       (apb3_pwrite                ),
    .io_apbSlave_0_PWDATA       (apb3_pwdata                ),
    .io_apbSlave_0_PRDATA       (apb3_prdata                ),
    .io_apbSlave_0_PSLVERROR    (apb3_pslverror             )
);
`endif

assign apb3_pready = (apb3_paddr[9] == 1'b0) ? mac_apb3_pready : ex_apb3_pready;
assign apb3_prdata = (apb3_paddr[9] == 1'b0) ? mac_apb3_prdata : ex_apb3_prdata;
assign apb3_pslverror = (apb3_paddr[9] == 1'b0) ? mac_apb3_pslverror : ex_apb3_pslverror;

assign mac_apb3_paddr = apb3_paddr[9:0];
assign mac_apb3_psel = (apb3_paddr[9] == 1'b0) ? apb3_psel : 1'b0;
assign mac_apb3_penable = apb3_penable;
assign mac_apb3_pwrite = apb3_pwrite;
assign mac_apb3_pwdata = apb3_pwdata;

assign ex_apb3_paddr = apb3_paddr[9:0];
assign ex_apb3_psel = (apb3_paddr[9] == 1'b1) ? apb3_psel : 1'b0;
assign ex_apb3_penable = apb3_penable;
assign ex_apb3_pwrite = apb3_pwrite;
assign ex_apb3_pwdata = apb3_pwdata;

apb3_2_axi4_lite#(
    .ADDR_WTH                   (10                         )
)
u_apb3_2_axi4_lite
(
//Globle Signals
    .clk                        (clk_50m                    ),
    .rstn                       (clk_50m_rstn               ),
//APB3 Slave Interface
    .s_apb3_paddr               (mac_apb3_paddr             ),
    .s_apb3_psel                (mac_apb3_psel              ),
    .s_apb3_penable             (mac_apb3_penable           ),
    .s_apb3_pready              (mac_apb3_pready            ),
    .s_apb3_pwrite              (mac_apb3_pwrite            ),
    .s_apb3_pwdata              (mac_apb3_pwdata            ),
    .s_apb3_prdata              (mac_apb3_prdata            ),
    .s_apb3_pslverror           (mac_apb3_pslverror         ),
//AXI4-Lite Master Interface
    .m_axi_awaddr               (axi_awaddr                 ),
    .m_axi_awvalid              (axi_awvalid                ),
    .m_axi_awready              (axi_awready                ),
    .m_axi_wdata                (axi_wdata                  ),
    .m_axi_wvalid               (axi_wvalid                 ),
    .m_axi_wready               (axi_wready                 ),
    .m_axi_bresp                (axi_bresp                  ),
    .m_axi_bvalid               (axi_bvalid                 ),
    .m_axi_bready               (axi_bready                 ),
    .m_axi_araddr               (axi_araddr                 ),
    .m_axi_arvalid              (axi_arvalid                ),
    .m_axi_arready              (axi_arready                ),
    .m_axi_rresp                (axi_rresp                  ),
    .m_axi_rdata                (axi_rdata                  ),
    .m_axi_rvalid               (axi_rvalid                 ),
    .m_axi_rready               (axi_rready                 )
);

// cam_status / cam_lane_status 必须在 u_reg_apb3 例化之前声明：Verific 对未
// 声明标识符会创建隐式 1 位 net，导致后方的声明+赋值 wire 成孤立网、读分支
// 被综合删除（cam_status 0x2A0 恒读 0 的根因，cam_lane_status 同踩，2026-11-06）
wire [31:0] cam_status;
wire [7:0]  cam_lane_status;

// ---- G9 单帧捕获声明（P2 专用 RAM dump，逻辑体在 my_csi2_rx 之后）----
// 协议：CSR 0x2B0 写 bit0=1 出单拍 arm（脉冲，与 done 解耦）；0x2B0 读={18'h0,done,arm,cnt[11:0]}；
// 0x2B4 读=拍[31:0]；0x2B8 读=拍[39:32] 且读脉冲步进一拍（G11i：dout 读后粘滞，同拍采样即当前组）。
// 成对读 lo→hi 遍历全部拍；FIFO 读过即丢，重复 dump 需重新 arm（30fps 零成本）。
// 跨钟（200M 写/50M 读）用 rtl/async_fifo.sv（格雷码指针，标准协议，BRAM；
// G11i 统一：首组由预读呈现，0x2B8 读脉冲步进，见 u_cap_fifo 下方注释）。
localparam [12:0] CAP_BEATS_M1 = 13'd30719;     // 64 行 × 480 组 - 1
wire        cap_arm_w;                          // reg_apb3 输出
wire        cap_rd_en_w;                        // reg_apb3 输出（0x2B8 读脉冲 = FIFO rd_en）
reg  [2:0]  cap_done_sy;                        // done 200M→50M 2FF
reg  [12:0] cap_rcnt_q;                         // 50M 读出计数（状态观测）
reg  [2:0]  cap_arm_sy;                         // arm 50M→200M 2FF
reg         cap_armed_200, cap_active, cap_done_200;
reg  [12:0] cap_wptr;                           // 200M 写计数
reg         cap_fifo_wr_en;                     // FIFO 写门控（active && tvalid && !full）
reg  [39:0] cap_wr_data_r;                      //G11i：din 与打一拍的 wr_en 对齐（否则丢首组+尾组重复）
wire        cap_fifo_full, cap_fifo_empty;
wire [39:0] cap_fifo_dout;                      //G11i 标准 FIFO dout：读后粘滞（rd 脉冲下一拍换组）
wire [39:0] raw_tdata;                          // raw_2_axi4st 窗口流（防隐式 net，声明前置）
wire        raw_tvalid, raw_tlast;
wire [2:0]  raw_tuser;                          // {eof, sol, sof}
// ---- G11n16 图案源（200M 域）与 FIFO 写源选择 ----
wire [39:0] pat_tdata;                          // raw10_pat_src 输出（同构 AXI-Stream）
wire        pat_tvalid, pat_tlast;
wire [2:0]  pat_tuser;                          // {eof, sol, sof}
wire        fifo_src_sel;                       // reg_apb3 0x208 bit7（50M 域）：0=相机 RX 1=图案源
reg  [1:0]  src_sel_sy;                         // fifo_src_sel 200M 2FF
reg         sel_eff;                            // 帧边界锁存：切换当帧仍是旧源完整帧，下一帧新源
wire [39:0] src_tdata;                          // 源 mux 输出 → G10 写路径（魔数插入/FIFO）
wire        src_tvalid, src_tlast;
wire [2:0]  src_tuser;                          // {eof, sol, sof}

// ---- G10 相机 UDP 直推声明（逻辑体在 u_udp_pat_gen 前后）----
// 写窗（200M）：cam_src_en 同步后于 sof 开窗、下个 sof 关窗，整帧窗口组入流 FIFO；
// pacer（125M）按占用率门控发包 → udp_pat_gen_v2 cam 源。诊断 CSR 0x2C0。
// 自由计数器（0x2C4）：判定 pll_0 输出时钟是否真实在跑（2026-11-06 I2C 停死排查）
reg  [15:0] free200_cnt, free100_cnt;
wire        cam_src_en;                         // reg_apb3 0x208 bit6（50M 域）
wire [31:0] cam_udp_status;                     // pacer 状态 → CSR 0x2C0
wire        cam_pkt_req_w;                      // pacer → udp_pat_gen_v2
wire        cam_pkt_go_w;                       //G11i pacer occ 电平 → gen S_IPG 包间门控
wire [8:0]  cam_pkt_len_w;                      //G11n15 pacer 动态包长 min(290,occ) → gen
wire        cam_quad_rd_w;                      // udp_pat_gen_v2 组消费 → pacer/FIFO
wire [39:0] cam_udp_dout;                       // 相机流 FIFO FWFT dout（125M 域）
wire        cam_udp_empty, cam_udp_full;
wire        cam_udp_sof_evt;                    // sof 拍（帧首组）
wire        cam_udp_eof_evt;                    // eof 拍（帧末组）
wire        cam_udp_wr_rst_n_w;                 // 流 FIFO 写侧软复位（帧尾后 2 拍）
//G11n14：cam_fifo_bank 指针探针（模 163840 计数，18 位；原单 async_fifo 的
// cam_fwr_bin/cam_frd_bin/cam_frd_sync_bin 14 位探针废弃——bank 内部指针各自独立，
// 总序由 bank 内 wcnt/rq 承担）
wire [17:0] cam_fifow_cnt, cam_fifor_cnt;   // bank 写/读总计数（dbg_wcnt/dbg_rq）
wire [17:0] cam_bank_occrd;                 // bank 读域精确总占用 → pacer fifo_occ
wire        cam_udp_rd_rst_n;                   // pacer 输出：读侧软复位
wire        cam_udp_fifo_rd_rstn_w;             // mac_rstn & 读侧软复位
reg         cam_udp_wr_en;                      // 200M FIFO 写
reg         cam_udp_armed;                      // 帧内写窗（sof→sof）
//G11n14：cam_udp_wcnt/wgray 镜像寄存器已删——写计数改由 cam_fifo_bank 内部
// dbg_wcnt 精确承担（模 163840），同步消除 G11n6 板级实证的"wcnt 多计 7"问题
//（原镜像与 FIFO wr_accept 判据同拍竞争，bank 版在模块内与写路由同源零偏差）
reg  [39:0] cam_udp_wr_data;                    //G11i：din 与打一拍的 wr_en 对齐（否则丢首组+尾组重复）
//G11n14：cam_udp_wgray（顶层格雷镜像 → pacer 同步链）已删——pacer occ 改由
// cam_fifo_bank 读域合成直供（fifo_occ 端口），顶层不再维护跨域格雷视图
reg  [31:0] cam_fullrej_cnt;                    // G11n6 0x2EC：armed 窗口真满丢组累计（当拍判 armed&&tvalid&&full，含被压 wr_en 的 skip 拍）
wire        cam_udp_pause;                      // G11m：0x2F4 bit0 pacer 软暂停
reg  [31:0] cam_tx_pkt_cnt;                     // G11n 0x2F0：gen 包完成数（tlast&&tvalid&&tready，125M 域）
reg  [31:0] cam_tx_bp_cnt;                      // G11n 0x2F8：gen tvalid&&!tready 背压拍数（125M 域）
reg  [31:0] cam_rd_cnt;                         // G11n2 0x2FC：cam_quad_rd 拉高累计（=FIFO 弹出，125M 域）
reg  [31:0] cam_ipgwait_cnt;                    // G11n2 0x300：gen S_IPG 等待 cam_pkt_go 白等拍（125M 域）
reg  [31:0] cam_ipgnact_cnt;                   //G11n5 0x304 白等成分①：S_IPG 且 frame_active=0（帧门关）
reg  [31:0] cam_ipgnoarm_cnt;                   //G11n5 0x308 白等成分②：S_IPG 且 active=1 且 burst_armed=0（occ 门）
//G11n9 裁决探针（锯齿 82~500 稳态 vs rej 21% 的矛盾）：full/occ 时间分布 + 写侧 run-length
reg  [31:0] cam_fullhi_cnt;                     //G11n9 0x30C full=1 拍累计（rej 的拍视角交叉验证）
reg  [31:0] cam_fullrise_cnt;                   //G11n9 0x310 full 上升沿数（满事件次数；均值=fullhi/rise）
reg  [31:0] cam_rejrun_max;                     //G11n9 0x314 连续 rej 最大拍数（单次满事件最长泄洪）
reg  [31:0] cam_tvrun_max;                      //G11n9 0x318 连续 raw_tvalid 最大拍数（写侧密簇验证）
wire [31:0] cam_occ_dbg;                        //G11n9 0x31C pacer {occ_min, occ_peak}（sof 清零帧内锯齿范围）
reg  [31:0] cam_hsgap_max;                      //G11n11 0x320 hs→hs 间隔最大拍（密排 vs 均匀裁决）
reg  [31:0] cam_hsgap_min;                      //G11n11 0x324 hs→hs 间隔最小拍
reg  [31:0] cam_hsgap_a;                        //G11n13 0x328 行距直方 <3500 拍（近距行）
reg  [31:0] cam_hsgap_b;                        //G11n13 0x32C 直方 3500..5499
reg  [31:0] cam_hsgap_c;                        //G11n13 0x330 直方 5500..7999（正常带）
reg  [31:0] cam_hsgap_d;                        //G11n13 0x334 直方 >=8000（远距/vblank）
wire        cam_pact  = cam_udp_status[14];     // pacer frame_active（G11n6 status bit14）
wire        cam_parmed = cam_udp_status[31];    // pacer burst_armed（status bit31，G11n5）
reg         cam_udp_sof_tg;                     // 帧尾 toggle（200M→125M）
reg  [1:0]  cam_src_sy;                         // cam_src_en 200M 2FF
reg  [31:0] cam_sof_cnt;                        //G11j 0x2CC：sof 事件计数（200M，诊断 occ=82 冻结）
reg  [31:0] cam_rawdt_cnt;                      //G11j 0x2D0：raw_tvalid 输出拍计数（200M）
wire [31:0] cam_mark_dbg;                       //G11j-3 0x2D4 tuser[1] 裸计数（200M）
wire [31:0] cam_sync_dbg;                       //G11j-3 0x2D8 tuser[0] 裸计数（200M）
wire [31:0] cam_vsedge_dbg;                     //G11j-3 0x2DC vs 上升沿计数（200M）
wire [31:0] cam_hsedge_dbg;                     //G11j-3 0x2E0 hs 上升沿计数（200M）
reg         cam_udp_eof_evt_r;                  // eof 打一拍（给帧末组写入让路）
//G11h：cam_udp_wr_rst_cnt 已删——FIFO 指针改为连续流不复位（见 L562 注释）

reg_apb3#(
    .ADDR_WTH                   (10                         )
)
u_reg_apb3
(
//Globle Signals
//
//APB3 Slave Interface
    .s_apb3_clk                 (clk_50m                    ),
    .s_apb3_rstn                (clk_50m_rstn               ),
    .s_apb3_paddr               (ex_apb3_paddr              ),
    .s_apb3_psel                (ex_apb3_psel               ),
    .s_apb3_penable             (ex_apb3_penable            ),
    .s_apb3_pready              (ex_apb3_pready             ),
    .s_apb3_pwrite              (ex_apb3_pwrite             ),
    .s_apb3_pwdata              (ex_apb3_pwdata             ),
    .s_apb3_prdata              (ex_apb3_prdata             ),
    .s_apb3_pslverror           (ex_apb3_pslverror          ),
//Cfg Space Registers
//--Example Registers Field
    .mac_sw_rst                 (mac_sw_rst                 ),
    .axi4_st_mux_select         (axi4_st_mux_select         ),
    .pat_mux_select             (pat_mux_select             ),
    .udp_pat_gen_en             (udp_pat_gen_en             ),
    .mac_pat_gen_en             (mac_pat_gen_en             ),
    .raw10_mode                 (raw10_mode                 ),
    .pat_gen_kill               (pat_gen_kill               ),
    .pat_mode                   (pat_mode                   ),
    .pat_gen_num                (pat_gen_num                ),
    .pat_gen_ipg                (pat_gen_ipg                ),
    .pat_dst_mac                (pat_dst_mac                ),
    .pat_src_mac                (pat_src_mac                ),
    .pat_mac_dlen               (pat_mac_dlen               ),
    .pat_src_ip                 (pat_src_ip                 ),
    .pat_dst_ip                 (pat_dst_ip                 ),
    .pat_src_port               (pat_src_port               ),
    .pat_dst_port               (pat_dst_port               ),
    .pat_udp_dlen               (pat_udp_dlen               ),
    //Ethernet Packet FIFO
    .eth_rx_word_cnt            (eth_rx_word_cnt            ),
    .eth_rx_overflow            (eth_rx_overflow            ),
    .eth_rx_overflow_clr        (eth_rx_overflow_clr        ),
    .eth_rx_rd_en               (eth_rx_rd_en               ),
    .eth_rx_rddata              (eth_rx_rddata              ),
    .eth_tx_free_cnt            (eth_tx_free_cnt            ),
    .eth_tx_full                (eth_tx_full                ),
    .eth_dbg_rxc_cnt            (eth_dbg_rxc_cnt            ),
    .eth_dbg_pll_cnt            (eth_dbg_pll_cnt            ),
    .pll_rgmii_locked           (pll_rgmii_locked           ),
    .pat_dbg_i                  (pat_dbg_w                  ),
    .cam_dt_cnt                 (cam_dt_cnt                 ),
    .cam_sof_dbg                ({cam_udp_full, cam_udp_armed, cam_sof_cnt[29:0]}),
    .cam_rawdt_cnt              (cam_rawdt_cnt              ),
    .cam_mark_dbg               (cam_mark_dbg               ),
    .cam_sync_dbg               (cam_sync_dbg               ),
    .cam_vsedge_dbg             (cam_vsedge_dbg             ),
    .cam_hsedge_dbg             (cam_hsedge_dbg             ),
    //G11n14 重排（bank FIFO 18 位指针）：0x2E4={wcnt[17:0],rq[13:0]}、
    // 0x2E8={rq[17:0],14'b0}——读指针 rq={ptr2[31:14], ptr1[13:0]} 拼装；
    // occ 直读 0x2C0 bits17:0（pacer status）。14 位低段差值仍可算模 16384 占用
    .cam_fifoptr_dbg            ({cam_fifow_cnt, cam_fifor_cnt[13:0]}),
    .cam_fifoptr2_dbg           ({cam_fifor_cnt, 14'b0}),
    .cam_fullrej_cnt            (cam_fullrej_cnt            ),
    .cam_udp_pause              (cam_udp_pause              ),
    .cam_tx_pkt_cnt             (cam_tx_pkt_cnt             ),
    .cam_tx_bp_cnt              (cam_tx_bp_cnt              ),
    .cam_rd_cnt                 (cam_rd_cnt                 ),
    .cam_ipgwait_cnt            (cam_ipgwait_cnt            ),
    .cam_err_sot_cnt            (cam_err_sot_cnt            ),
    .cam_err_sotsync_cnt        (cam_err_sotsync_cnt        ),
    .cam_err_esc_cnt            (cam_err_esc_cnt            ),
    .cam_err_linestate_cnt      (cam_err_ls_cnt             ),
    .cam_status                 (cam_status                 ),
    .cam_lane_status            (cam_lane_status            ),
    .cam_src_en                 (cam_src_en                 ),
    .fifo_src_sel               (fifo_src_sel               ),
    .cam_udp_status             (cam_udp_status             ),
.cam_ipgnact_cnt            (cam_ipgnact_cnt            ),
.cam_ipgnoarm_cnt           (cam_ipgnoarm_cnt           ),
.cam_fullhi_cnt             (cam_fullhi_cnt             ),
.cam_fullrise_cnt           (cam_fullrise_cnt           ),
.cam_rejrun_max             (cam_rejrun_max             ),
.cam_tvrun_max              (cam_tvrun_max              ),
.cam_occ_dbg                (cam_occ_dbg                ),
.cam_hsgap_max              (cam_hsgap_max              ),
.cam_hsgap_min              (cam_hsgap_min              ),
.cam_hsgap_a                (cam_hsgap_a                ),
.cam_hsgap_b                (cam_hsgap_b                ),
.cam_hsgap_c                (cam_hsgap_c                ),
.cam_hsgap_d                (cam_hsgap_d                ),
    .cam_i2c_stat               (cam_i2c_stat               ),
    .free200_cnt                (free200_cnt                ),
    .free100_cnt                (free100_cnt                ),
    .cap_arm                    (cap_arm_w                  ),
    .cap_rd_en                  (cap_rd_en_w                ),
    .cap_done                   (cap_done_sy[2]             ),
    .cap_ptr_stat               ({3'd0, cap_rcnt_q}         ),
    .cap_rdata_lo               (cap_fifo_dout[31:0]        ),
    .cap_rdata_hi               (cap_fifo_dout[39:32]       ),
    .eth_tx_wrdata              (eth_tx_wrdata              ),
    .eth_tx_wr_en               (eth_tx_wr_en               ),
    .eth_sw_tx_sel              (eth_sw_tx_sel              )
);

//generate if (PATTERN_TYPE == 0) begin  //UDP
//	
//assign mac_tx_axis_mac_tdata = 8'h0;
//assign mac_tx_axis_mac_tvalid = 1'b0;
//assign mac_tx_axis_mac_tlast = 1'b0;



/*----------------------- The Ethernet Pattern Module -----------------------*/
// G10 相机流 FIFO：raw_2_axi4st 窗口组（200M）→ udp_pat_gen_v2 组消费（125M），
// 占用率由 pacer 门控（包级预缓冲），包内绝不排空
//G10：必须纯 assign——上方 L463/L465 已前向声明，此处再用声明式赋值会形成双重
//声明，efx_map 静默丢弃第二个驱动 → net 恒 0 → FIFO 双侧永久复位被整删（EFX-0656）
//G11h：FIFO 写侧不再做每帧软复位（连续流缓冲）。wcnt/wgray 与 FIFO wr_bin 同增量、
//pacer rq_cnt 与 rd_bin 同增量——全部不复位则恒一致，occ=真实积压（<8192 模值正确）。
//原 eof 复位窗在读侧消费中清 wr_bin → empty 误判非空 → 消费 1024 回绕垃圾
//（sim 实证 mism=51.6万/帧；板上蓝竖条闪烁）。帧边界由 gen 包结构定义，无需指针归零。
assign cam_udp_wr_rst_n_w     = clk_200m_rstn;
assign cam_udp_fifo_rd_rstn_w = mac_rstn & cam_udp_rd_rst_n;
//G11i：cam UDP 路径换标准 async_fifo（非 FWFT）——FWFT 预取在稀疏读+排空/恢复
//边界交付错位（sim 恒 -2 组）；标准 FIFO rd_en&&!empty 才动指针、空读安全忽略，
//gen 侧提前一拍读（见 udp_pat_gen_v2 G11i 注释）。u_cap_fifo 保持 FWFT 不变。
//G11n6：DEPTH 1024→8192——G11n5 板上收支铁证：rawdt 15.48M/s = accept 11.38M
//+ rej 0.58M + skip 3.52M（FIFO 满压掉 wr_en 的拍从不计入 rej，真实丢数≈26%/帧
//=卷动根源）。1024 量级容量不足，pacing 门限微调救不了（G11n3/4 板测实证：节拍
//由写速守恒，门限只挪锯齿位置），深缓冲吸收写突发使拒收→0。BRAM 8192×40=320Kb。
//G11n14：cam UDP 流 FIFO 换 cam_fifo_bank 多 bank 拼接（bank0=2^17 + bank1=2^15
//= 163,840 组 × 40bit = 640 块 BRAM，总用量 ~942/1280）。G11n13 直方图定案：
// 有效行段瞬时写速 32.43M 组/s > gen 千兆极限 23.96M，段净积 135,351 组——
// 旧 8192 深 FIFO 结构性装不下（rej 21.5%/帧无论门限怎么调），深缓冲吸收后
// 帧尾 17.35ms gap 排空 135K 只需 5.7ms。对外接口与 async_fifo 同构（非 FWFT），
// gen 侧零适配；occ/指针探针由 bank 内部精确计数提供。
cam_fifo_bank #(
    .WIDTH      (40),
    .BANK0_DEPTH(131072),   // 2^17 → 512 块 BRAM
    .BANK1_DEPTH(32768)     // 2^15 → 128 块 BRAM
) u_cam_udp_fifo (
    .wr_clk   (clk_200m                     ),
    .wr_rst_n (clk_200m_rstn & cam_udp_wr_rst_n_w),
    .wr_en    (cam_udp_wr_en                ),
    .din      (cam_udp_wr_data              ),
    .full     (cam_udp_full                 ),
    .rd_clk   (tx_axis_clk                  ),
    .rd_rst_n (cam_udp_fifo_rd_rstn_w       ),
    .rd_en    (cam_quad_rd_w                ),
    .dout     (cam_udp_dout                 ),
    .empty    (cam_udp_empty                ),
    .occ_rd   (cam_bank_occrd               ),
    .occ_wr   (                             ),   // 写域保守占用，板上暂不观测（悬空）
    .dbg_wcnt (cam_fifow_cnt                ),
    .dbg_rq   (cam_fifor_cnt                )
);

// G11n15 发包流控改纯流式：req/go = cam_en && occ>0，动态包长 min(290,occ)，
// 帧尾短包精确排空 → 每帧 FIFO 清零、下一帧魔数天然在 FIFO 头（无门限/无帧窗模型）
cam_udp_pacer #(
    .QUADS_PER_PKT (290    ),
    .FIFO_AW       (18     )   //G11n14：bank 拼接总深 163,840 → occ 18 位（模 2^18 域模减无歧义）
) u_cam_udp_pacer (
    .clk           (tx_axis_clk       ),
    .rstn          (mac_rstn          ),
    .cam_en        (cam_src_en        ),
    .pause_i       (cam_udp_pause     ),
    .sof_toggle    (cam_udp_sof_tg    ),
    .fifo_occ      (cam_bank_occrd    ),   //G11n14：bank 读域精确占用直供（wq_gray 链废弃）
    .cam_quad_rd   (cam_quad_rd_w     ),
    .gen_state     (pat_dbg_w[5:3]    ),
    .cam_pkt_req   (cam_pkt_req_w     ),
    .cam_pkt_go    (cam_pkt_go_w      ),
    .pkt_len_o     (cam_pkt_len_w     ),   //G11n15 动态包长 → gen grp_len_r 锁存
    .status_o      (cam_udp_status    ),
    .occ_dbg_o     (cam_occ_dbg       ),   //G11n9 0x31C
    .fifo_rd_rst_n (cam_udp_rd_rst_n  )
);

udp_pat_gen_v2 u_udp_pat_gen
(
//Globle Signals
    .clk                        (tx_axis_clk                ),
    .rstn                       (mac_rstn                   ),
//Control Interface
    .pat_gen_en                 (udp_pat_gen_en             ),
    .pat_gen_num                (pat_gen_num                ),
    .dbg_state_o                (pat_dbg_w                  ),
    .pat_gen_ipg                (pat_gen_ipg                ),
    .raw10_en                   (raw10_mode                 ),
    .pat_gen_kill               (pat_gen_kill               ),
//G11n16：gen pat_mode 端口已删（图案路径迁移到 raw10_pat_src，200M 域）
//G10 Camera Source
    .cam_en                     (cam_src_en                 ),
    .cam_pkt_req                (cam_pkt_req_w              ),
    .cam_pkt_go                 (cam_pkt_go_w               ),
    .cam_pkt_len                (cam_pkt_len_w              ),   //G11n15 动态包长（授予拍锁存 grp_len_r）
    .cam_quad_i                 (cam_udp_dout               ),
    .cam_quad_valid             (~cam_udp_empty             ),
    .cam_quad_rd                (cam_quad_rd_w              ),
//MAC Protocol Signals
    .dst_mac                    (pat_dst_mac                ),
    .src_mac                    (pat_src_mac                ),
//IP Protocol Signals
    .src_ip                     (pat_src_ip                 ),
    .dst_ip                     (pat_dst_ip                 ),
//UDP Protocol Signals
    .src_port                   (pat_src_port               ),
    .dst_port                   (pat_dst_port               ),
    .udp_dlen                   (pat_udp_dlen               ),
//AXI4-Stream Interface
    .tdata                      (udp_tx_axis_mac_tdata      ),
    .tvalid                     (udp_tx_axis_mac_tvalid     ),
    .tlast                      (udp_tx_axis_mac_tlast      ),
    .tready                     (udp_tx_axis_mac_tready     ),
//Diagnostics
    .frame_num_o                (frame_num_dbg              )
);

//end
//else begin  //MAC
//
//assign udp_tx_axis_mac_tdata = 8'h0;
//assign udp_tx_axis_mac_tvalid = 1'b0;
//assign udp_tx_axis_mac_tlast = 1'b0;
	
mac_pat_gen u_mac_pat_gen
(
//Globle Signals
    .clk                        (tx_axis_clk                ),
    .rstn                       (mac_rstn                   ),
//Control Interface
    .pat_gen_en                 (mac_pat_gen_en             ),
    // .pat_gen_en                 (1'b1             ),
    .pat_gen_num                (pat_gen_num                ),
    .pat_gen_ipg                (pat_gen_ipg                ),
//MAC Protocol Signals
    .dst_mac                    (pat_dst_mac                ),
    .src_mac                    (pat_src_mac                ),
    .mac_dlen                   (pat_mac_dlen               ),
//AXI4-Stream Interface
    .rclk                       (rx_axis_clk                ),
    .rrstn                      (mac_rstn                   ),
    .rdata                      (rx_axis_mac_tdata          ),
    .rvalid                     (rx_axis_mac_tvalid         ),
    .rlast                      (rx_axis_mac_tlast          ),
    .tdata                      (mac_tx_axis_mac_tdata      ),
    .tvalid                     (mac_tx_axis_mac_tvalid     ),
    .tlast                      (mac_tx_axis_mac_tlast      ),
    .tready                     (mac_tx_axis_mac_tready     )
);
//end
//endgenerate

axi4_st_mux u_pat_mux
(
//Globle Signals
    .mux_select                 (pat_mux_select             ),//0:udp pat; 1:mac pat;
    // .mux_select                 (0             ),//0:udp pat; 1:mac pat;
//Mux In 0 Interface
    .tdata0                     (udp_tx_axis_mac_tdata      ),
    .tvalid0                    (udp_tx_axis_mac_tvalid     ),
    .tlast0                     (udp_tx_axis_mac_tlast      ),
    .tuser0                     (1'b0                       ),
    .tready0                    (udp_tx_axis_mac_tready     ),
//Mux In 1 Interface
    .tdata1                     (mac_tx_axis_mac_tdata      ),
    .tvalid1                    (mac_tx_axis_mac_tvalid     ),
    .tlast1                     (mac_tx_axis_mac_tlast      ),
    .tuser1                     (1'b0                       ),
    .tready1                    (mac_tx_axis_mac_tready     ),
//Mux Out Interface
    .tdata                      (pat_tx_axis_mac_tdata      ),
    .tvalid                     (pat_tx_axis_mac_tvalid     ),
    .tlast                      (pat_tx_axis_mac_tlast      ),
    .tuser                      (pat_tx_axis_mac_tuser      ),
    .tready                     (pat_tx_axis_mac_tready     )
);

/*----------------------- The Tx AXI4 St Mux Module -----------------------*/
//3选1：00=pattern；01=rx2tx loopback；1x=software frame（CPU 发包通路）
assign tx_mux_select = {eth_sw_tx_sel, axi4_st_mux_select};

axi4_st_mux3 u_tx_axi4st_mux
(
//Globle Signals
    .mux_select                 (tx_mux_select              ),//00:pat; 01:rx2tx loopback; 1x:sw frame;
//Mux In 0 Interface
    .tdata0                     (pat_tx_axis_mac_tdata      ),
    .tvalid0                    (pat_tx_axis_mac_tvalid     ),
    .tlast0                     (pat_tx_axis_mac_tlast      ),
    .tuser0                     (pat_tx_axis_mac_tuser      ),
    .tready0                    (pat_tx_axis_mac_tready     ),
//Mux In 1 Interface
    .tdata1                     (loop_tx_axis_mac_tdata     ),
    .tvalid1                    (loop_tx_axis_mac_tvalid    ),
    .tlast1                     (loop_tx_axis_mac_tlast     ),
    .tuser1                     (loop_tx_axis_mac_tuser     ),
    .tready1                    (loop_tx_axis_mac_tready    ),
//Mux In 2 Interface
    .tdata2                     (sw_tx_axis_mac_tdata       ),
    .tvalid2                    (sw_tx_axis_mac_tvalid      ),
    .tlast2                     (sw_tx_axis_mac_tlast       ),
    .tuser2                     (sw_tx_axis_mac_tuser       ),
    .tready2                    (sw_tx_axis_mac_tready      ),
//Mux Out Interface
    .tdata                      (tx_axis_mac_tdata          ),
    .tvalid                     (tx_axis_mac_tvalid         ),
    .tlast                      (tx_axis_mac_tlast          ),
    .tuser                      (tx_axis_mac_tuser          ),
    .tready                     (tx_axis_mac_tready         )
);

/*----------------------- The Tri-mode Ethernet MAC core -----------------------*/
// assign rgmii_tx_ctl = rgmii_tx_ctl_HI | rgmii_tx_ctl_LO ;
// assign rgmii_rx_ctl_HI = rgmii_rx_ctl ;
// assign rgmii_rx_ctl_LO = rgmii_rx_ctl ;

mytse u_tsemac
(
//Globle Signals
    .mac_reset                  (mac_reset                  ),
    .proto_reset                (proto_reset                ),
    .tx_mac_aclk                (clk_125m                   ),
    .rx_mac_aclk                (                           ),
    .eth_speed                  (                           ),
//Receive AXI4-Stream Interface
    .rx_axis_clk                (rx_axis_clk                ),
    .rx_axis_mac_tdata          (rx_axis_mac_tdata          ),
    .rx_axis_mac_tvalid         (rx_axis_mac_tvalid         ),
    .rx_axis_mac_tlast          (rx_axis_mac_tlast          ),
    .rx_axis_mac_tstrb          (),
    .rx_axis_mac_tuser          (rx_axis_mac_tuser          ),
    .rx_axis_mac_tready         (rx_axis_mac_tready         ),
//Transmit AXI4-Stream Interface
    .tx_axis_clk                (tx_axis_clk                ),
    .tx_axis_mac_tdata          (tx_axis_mac_tdata          ),
    .tx_axis_mac_tvalid         (tx_axis_mac_tvalid         ),
    .tx_axis_mac_tlast          (tx_axis_mac_tlast          ),
    .tx_axis_mac_tstrb          (1'b1                       ),
    .tx_axis_mac_tuser          (tx_axis_mac_tuser          ),
    .tx_axis_mac_tready         (tx_axis_mac_tready         ), 
    //--RGMII Interface
    .rgmii_txd_HI               (rgmii_txd_HI               ),
    .rgmii_txd_LO               (rgmii_txd_LO               ),
    .rgmii_tx_ctl_HI            (rgmii_tx_ctl_HI            ),
    .rgmii_tx_ctl_LO            (rgmii_tx_ctl_LO            ),
    .rgmii_txc_HI               (rgmii_txc_HI               ),
    .rgmii_txc_LO               (rgmii_txc_LO               ),
    .rgmii_rxd_HI               ({rgmii_rxd3_HI, rgmii_rxd2_HI, rgmii_rxd1_HI, rgmii_rxd0_HI}),
    .rgmii_rxd_LO               ({rgmii_rxd3_LO, rgmii_rxd2_LO, rgmii_rxd1_LO, rgmii_rxd0_LO}),
    .rgmii_rx_ctl_HI            (rgmii_rx_ctl_HI            ),
    .rgmii_rx_ctl_LO            (rgmii_rx_ctl_LO            ),
    .rgmii_rxc                  (pll_rgmii_rx_clk           ), //rgmii_rxc                  ),
    //AXI4-Lite Interface
    .s_axi_aclk                 (clk_50m                    ),
    .s_axi_awaddr               (axi_awaddr                 ),
    .s_axi_awvalid              (axi_awvalid                ),
    .s_axi_awready              (axi_awready                ),
    .s_axi_wdata                (axi_wdata                  ),
    .s_axi_wvalid               (axi_wvalid                 ),
    .s_axi_wready               (axi_wready                 ),
    .s_axi_bresp                (axi_bresp                  ),
    .s_axi_bvalid               (axi_bvalid                 ),
    .s_axi_bready               (axi_bready                 ),
    .s_axi_araddr               (axi_araddr                 ),
    .s_axi_arvalid              (axi_arvalid                ),
    .s_axi_arready              (axi_arready                ),
    .s_axi_rresp                (axi_rresp                  ),
    .s_axi_rdata                (axi_rdata                  ),
    .s_axi_rvalid               (axi_rvalid                 ),
    .s_axi_rready               (axi_rready                 ),
    //MDIO Interface
    .Mdo                        (phy_mdo                    ),
    .MdoEn                      (phy_mdo_en                 ),
    .Mdi                        (phy_mdi                    ),
    .Mdc                        (phy_mdc                    )
);

/*----------------------- User Interface Loopback Module ----------------------------*/
//RX tready 合并：两路均恒 1（TSEMAC UG 不支持 tready 背压，溢出由各自模块
//帧粒度准入保护），保留与结构便于后续扩展
wire                            loop_rx_axis_mac_tready;
wire                            fifo_rx_axis_mac_tready;

assign rx_axis_mac_tready = loop_rx_axis_mac_tready & fifo_rx_axis_mac_tready;

mac_rx2tx u_mac_rx2tx
(
//Globle Signals
//
//Receive AXI4-Stream Interface
    .rx_axis_clk                (rx_axis_clk                ),
    .rx_axis_rstn               (mac_rstn                   ),
    .rx_axis_mac_tdata          (rx_axis_mac_tdata          ),
    .rx_axis_mac_tvalid         (rx_axis_mac_tvalid         ),
    .rx_axis_mac_tlast          (rx_axis_mac_tlast          ),
    .rx_axis_mac_tuser          (rx_axis_mac_tuser          ),
    .rx_axis_mac_tready         (loop_rx_axis_mac_tready    ),
//Transmit AXI4-Stream Interface
    .tx_axis_clk                (tx_axis_clk                ),
    .tx_axis_rstn               (mac_rstn                   ),
    .tx_axis_mac_tdata          (loop_tx_axis_mac_tdata     ),
    .tx_axis_mac_tvalid         (loop_tx_axis_mac_tvalid    ),
    .tx_axis_mac_tlast          (loop_tx_axis_mac_tlast     ),
    .tx_axis_mac_tuser          (loop_tx_axis_mac_tuser     ),
    .tx_axis_mac_tready         (loop_tx_axis_mac_tready    )
);

/*----------------------- Ethernet Packet FIFO (CPU RX/TX path) ----------------------*/
eth_pkt_fifo #(
    .FIFO_DEPTH                 (4096                       ),
    .FRAME_GUARD                (1536                       )
) u_eth_pkt_fifo
(
//RX Side (AXI4-Stream Slave)
    .rx_clk                     (rx_axis_clk                ),
    .rx_rstn                    (mac_rstn                   ),
    .rx_tdata                   (rx_axis_mac_tdata          ),
    .rx_tvalid                  (rx_axis_mac_tvalid         ),
    .rx_tlast                   (rx_axis_mac_tlast          ),
    .rx_tuser                   (rx_axis_mac_tuser          ),
    .rx_tready                  (fifo_rx_axis_mac_tready    ),
//TX Side (AXI4-Stream Master)
    .tx_clk                     (tx_axis_clk                ),
    .tx_rstn                    (mac_rstn                   ),
    .tx_tdata                   (sw_tx_axis_mac_tdata       ),
    .tx_tvalid                  (sw_tx_axis_mac_tvalid      ),
    .tx_tlast                   (sw_tx_axis_mac_tlast       ),
    .tx_tuser                   (sw_tx_axis_mac_tuser       ),
    .tx_tready                  (sw_tx_axis_mac_tready      ),
//CPU Status/Access
    .apb_clk                    (clk_50m                    ),
    .apb_rstn                   (clk_50m_rstn               ),
    .rx_word_cnt                (eth_rx_word_cnt            ),
    .rx_overflow                (eth_rx_overflow            ),
    .rx_overflow_clr            (eth_rx_overflow_clr        ),
    .rx_rd_en                   (eth_rx_rd_en               ),
    .rx_rddata                  (eth_rx_rddata              ),
    .tx_free_cnt                (eth_tx_free_cnt            ),
    .tx_full                    (eth_tx_full                ),
    .tx_wrdata                  (eth_tx_wrdata              ),
    .tx_wr_en                   (eth_tx_wr_en               )
);

/*----------------------- Camera CSI-2 Chain (P1/G8) -----------------------*/
// 时钟统一由 pll_0 提供：clk_100m = IP 核钟 + DPHY CFG_CLK（官方 80–120MHz），
// clk_200m = IP 像素域（官方下限 178.2MHz）。pll_csi 已移除（2026-11-06 板测：
// 旧 clk_25m 输出实际 20MHz、REFCLK_FREQ 声明 25.0 不匹配 → 失锁）。

// 异步复位、同步释放（规则 §4/§8：PLL 锁定后才能释放；每域独立同步链）
// pll_csi 没了，锁定门控改用 pll_0_locked（相机时钟同源自 pll_0）
wire cam_pll_rst_n = pll_0_locked;
(* syn_keep = "true" *) reg [2:0] rst_100m_sync;
always @(posedge clk_100m or negedge cam_pll_rst_n)
    if (!cam_pll_rst_n) rst_100m_sync <= 3'b000;
    else                rst_100m_sync <= {rst_100m_sync[1:0], 1'b1};
assign clk_100m_rstn = rst_100m_sync[2];   // 纯 assign（已前向声明于 Wire Define 区）

(* syn_keep = "true" *) reg [2:0] rst_200m_sync;
always @(posedge clk_200m or negedge cam_pll_rst_n)
    if (!cam_pll_rst_n) rst_200m_sync <= 3'b000;
    else                rst_200m_sync <= {rst_200m_sync[1:0], 1'b1};
assign clk_200m_rstn = rst_200m_sync[2];   // 根因=声明式赋值在 L565 前向使用之后，隐式网分裂
                                           // 致 200M 复位域整域被删、rst_200m_sync[2] "no fanout"

// DPHY 复位随 100M 域释放；DPHY 恢复字钟域复位由 reset_ctrl 生成
//（无流停振、复位保持——参考工程 top_cam 同构）
assign dphy_rx2_RESET_N = clk_100m_rstn;
assign dphy_rx2_RST0_N  = clk_100m_rstn;
wire csi_byte_rstn;
reset_ctrl #(
    .NUM_RST        (1),
    .IN_RST_ACTIVE  (1'b0),
    .OUT_RST_ACTIVE (1'b0)
) u_cam_rst_byte (
    .i_arst (clk_200m_rstn),
    .i_clk  (dphy_rx2_clk_CLKOUT),
    .o_srst (csi_byte_rstn)
);

// ---- cam I2C RTL 初始化（clk_200m 域，SYS_FREQ=200M 板级验证常数）----
// 开漏 pad 映射（参考工程同构）：pad_o 恒 0，oe=~scl/sda（低有效驱动）；
// IO 寄存器由 peri 配置于 clk_200m（见 bootstrap ISF）。
logic cam_i2c_scl_o, cam_i2c_sda_o;
logic cam_i2c_en, cam_i2c_done, cam_i2c_fail, cam_i2c_busy;
logic [7:0] cam_i2c_dbg_idx;
logic [1:0] cam_i2c_dbg_round;
logic [3:0] cam_i2c_dbg_retry;
assign cam_1_en      = cam_i2c_en;
assign cam_1_scl_OUT = 1'b0;
assign cam_1_scl_OE  = ~cam_i2c_scl_o;
assign cam_1_sda_OUT = 1'b0;
assign cam_1_sda_OE  = ~cam_i2c_sda_o;

cam_i2c_init #(
    .SYS_FREQ       (200_000_000),
    .I2C_FREQ       (50_000),
    .MODE_4K        (1'b0)          // 1080p 档：geo1080 VMAX=4500 → 30fps（D2 决策）
) u_cam_i2c_init (
    .clk        (clk_200m       ),
    .rst_n      (clk_200m_rstn  ),  // 不含 init_done（防自锁死，参考工程教训）
    .scl_pad_i  (cam_1_scl_IN         ),
    .scl_pad_o  (cam_i2c_scl_o      ),
    .sda_pad_i  (cam_1_sda_IN         ),
    .sda_pad_o  (cam_i2c_sda_o      ),
    .cam_en     (cam_i2c_en         ),
    .start      (1'b1               ),  // 复位释放后 0→1 出沿自启（参考工程 cam 同构）
    .init_done  (cam_i2c_done       ),
    .init_fail  (cam_i2c_fail       ),
    .busy       (cam_i2c_busy       ),
    .dbg_idx    (cam_i2c_dbg_idx    ),
    .dbg_round  (cam_i2c_dbg_round  ),
    .dbg_retry  (cam_i2c_dbg_retry  )
);

// ---- MIPI CSI-2 RX：my_csi2_rx 裸 IP 直例化（2.5G 变体，AXI CSR tie-off）----
wire [1:0] cam_rx_valid0 = {2{dphy_rx2_HS_LAN0_VALID}};  // 每 lane 2bit，复制扩展
wire [1:0] cam_rx_valid1 = {2{dphy_rx2_HS_LAN1_VALID}};
wire [1:0] cam_rx_valid2 = {2{dphy_rx2_HS_LAN2_VALID}};
wire [1:0] cam_rx_valid3 = {2{dphy_rx2_HS_LAN3_VALID}};
wire [63:0] cam_pixel_data;
wire        cam_pixel_valid, cam_pixel_hs, cam_pixel_vs;
wire [5:0]  cam_pixel_datatype;

my_csi2_rx u_cam_csi2_rx (
    .reset_n         (clk_100m_rstn),
    .clk             (clk_100m),
    .reset_byte_HS_n (csi_byte_rstn),
    .clk_byte_HS     (dphy_rx2_clk_CLKOUT),
    .reset_pixel_n   (clk_200m_rstn),
    .clk_pixel       (clk_200m),

    .RxClkEsc           ({dphy_rx2_ESC_LAN3_CLK,          dphy_rx2_ESC_LAN2_CLK,
                          dphy_rx2_ESC_LAN1_CLK,          dphy_rx2_ESC_LAN0_CLK}),
    .RxUlpsClkNot       (dphy_rx2_ULPS_CLK_ENTER          ),
    .RxUlpsActiveClkNot (dphy_rx2_ULPS_CLK_ACTIVEN        ),
    .RxErrEsc           ({dphy_rx2_ESC_LAN3_ERROR,        dphy_rx2_ESC_LAN2_ERROR,
                          dphy_rx2_ESC_LAN1_ERROR,        dphy_rx2_ESC_LAN0_ERROR}),
    .RxErrControl       ({dphy_rx2_LINESTATE_LAN3_ERROR,  dphy_rx2_LINESTATE_LAN2_ERROR,
                          dphy_rx2_LINESTATE_LAN1_ERROR,  dphy_rx2_LINESTATE_LAN0_ERROR}),
    .RxErrSotSyncHS     ({dphy_rx2_HS_LAN3_SOTSYNC_ERROR, dphy_rx2_HS_LAN2_SOTSYNC_ERROR,
                          dphy_rx2_HS_LAN1_SOTSYNC_ERROR, dphy_rx2_HS_LAN0_SOTSYNC_ERROR}),
    .RxUlpsEsc          ({dphy_rx2_ULPS_LAN3_ENTER,       dphy_rx2_ULPS_LAN2_ENTER,
                          dphy_rx2_ULPS_LAN1_ENTER,       dphy_rx2_ULPS_LAN0_ENTER}),
    .RxUlpsActiveNot    ({dphy_rx2_ULPS_LAN3_ACTIVEN,     dphy_rx2_ULPS_LAN2_ACTIVEN,
                          dphy_rx2_ULPS_LAN1_ACTIVEN,     dphy_rx2_ULPS_LAN0_ACTIVEN}),
    .RxSkewCalHS        ({dphy_rx2_HS_LAN3_SKEWCAL,       dphy_rx2_HS_LAN2_SKEWCAL,
                          dphy_rx2_HS_LAN1_SKEWCAL,       dphy_rx2_HS_LAN0_SKEWCAL}),
    .RxStopState        ({dphy_rx2_STOPSTATE_LAN3,        dphy_rx2_STOPSTATE_LAN2,
                          dphy_rx2_STOPSTATE_LAN1,        dphy_rx2_STOPSTATE_LAN0}),
    .RxSyncHS           ({dphy_rx2_HS_LAN3_SYNC,          dphy_rx2_HS_LAN2_SYNC,
                          dphy_rx2_HS_LAN1_SYNC,          dphy_rx2_HS_LAN0_SYNC}),
    .RxDataHS0          (dphy_rx2_HS_LAN0_DATA),
    .RxDataHS1          (dphy_rx2_HS_LAN1_DATA),
    .RxDataHS2          (dphy_rx2_HS_LAN2_DATA),
    .RxDataHS3          (dphy_rx2_HS_LAN3_DATA),
    .RxDataHS4          (), .RxDataHS5 (), .RxDataHS6 (), .RxDataHS7 (),
    .RxValidHS0         (cam_rx_valid0),
    .RxValidHS1         (cam_rx_valid1),
    .RxValidHS2         (cam_rx_valid2),
    .RxValidHS3         (cam_rx_valid3),
    .RxValidHS4         (), .RxValidHS5 (), .RxValidHS6 (), .RxValidHS7 (),

    // AXI-Lite CSR 不接入（tie off，同参考工程已板测用法）
    .axi_clk     (clk_100m),
    .axi_reset_n (clk_100m_rstn),
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

    .hsync_vc1  (), .hsync_vc2  (), .hsync_vc3  (), .hsync_vc4  (),
    .hsync_vc5  (), .hsync_vc6  (), .hsync_vc7  (), .hsync_vc8  (),
    .hsync_vc9  (), .hsync_vc10 (), .hsync_vc11 (), .hsync_vc12 (),
    .hsync_vc13 (), .hsync_vc14 (), .hsync_vc15 (),
    .vsync_vc1  (), .vsync_vc2  (), .vsync_vc3  (), .vsync_vc4  (),
    .vsync_vc5  (), .vsync_vc6  (), .vsync_vc7  (), .vsync_vc8  (),
    .vsync_vc9  (), .vsync_vc10 (), .vsync_vc11 (), .vsync_vc12 (),
    .vsync_vc13 (), .vsync_vc14 (), .vsync_vc15 (),
    .hsync_vc0        (cam_pixel_hs     ),
    .vsync_vc0        (cam_pixel_vs     ),
    .pixel_data       (cam_pixel_data   ),
    .pixel_data_valid (cam_pixel_valid  ),
    .pixel_datatype   (cam_pixel_datatype),
    .pixel_per_clk    (),
    .datatype         (),
    .shortpkt_data_field (),
    .word_count       (),
    .vcx              (),
    .vc               (),
    .pixel_line_num   (),
    .pixel_frame_num  (),
    .pixel_wordcount  (),
    .pixel_vc         (),
    .pixel_vcx        ()
);

// ---- G8 探针（判据：dt_cnt 步进 ≥ 1944×1091×30 ≈ 63.6M 拍/min；err 计数恒 0）----
// RAW10 有效像素拍计数（200M 域；DT 0x2B = RAW10）
reg [31:0] cam_dt_cnt;
always @(posedge clk_200m or negedge clk_200m_rstn)
    if (!clk_200m_rstn) cam_dt_cnt <= 32'h0;
    else if ((cam_pixel_valid == 1'b1) && (cam_pixel_datatype == 6'h2B))
        cam_dt_cnt <= cam_dt_cnt + 32'd1;

// ---- G9 单帧捕获（P2 专用 RAM dump）：raw_2_axi4st 窗口流 → 前 8 行入 BRAM ----
raw_2_axi4st #(
    .DTYPE           (6'h2B    ),
    .LINE_TOTAL_PIX  (20'd1944 ),
    .LEAD_PIX        (20'd6    ),
    .TRAIL_PIX       (20'd18   ),
    .LINE_SKIP_FIRST (20'd11   ),
    .LINES           (20'd1080 )
) u_raw2axi (
    .aclk         (clk_200m          ),
    .aresetn      (clk_200m_rstn     ),
    .in_data      (cam_pixel_data[39:0]),   // RAW10 4px 打包在低 40 位（同参考 top_cam）
    .in_valid     (cam_pixel_valid   ),
    .in_vs        (cam_pixel_vs      ),
    .in_hs        (cam_pixel_hs      ),
    .in_dtype     (cam_pixel_datatype),
    .m_axis_tdata (raw_tdata         ),
    .m_axis_tvalid(raw_tvalid        ),
    .m_axis_tlast (raw_tlast         ),
    .m_axis_tuser (raw_tuser         )
);

// ---- G11n16 图案源：200M 域自由运行，与相机共用 G10 写路径→cam_fifo_bank 链路 ----
raw10_pat_src u_raw10_pat_src (
    .clk_i      (clk_200m      ),
    .rstn_i     (clk_200m_rstn ),
    .pat_mode_i (pat_mode      ),
    .tdata_o    (pat_tdata     ),
    .tvalid_o   (pat_tvalid    ),
    .tlast_o    (pat_tlast     ),
    .tuser_o    (pat_tuser     )
);

// 源选择：fifo_src_sel 2FF 同步后于帧首组拍（cam_udp_sof_evt）锁存生效——
// 切换当帧仍以旧源完整帧通过（sof 拍 mux 尚未翻转），下一帧起切换新源，
// 杜绝帧内拼接。PC 端魔数每帧重对齐，切换瞬间的残帧由下一帧魔数自然丢弃。
always @(posedge clk_200m or negedge clk_200m_rstn) begin
    if (!clk_200m_rstn) begin
        src_sel_sy <= 2'b00;
        sel_eff    <= 1'b0;
    end else begin
        src_sel_sy <= {src_sel_sy[0], fifo_src_sel};
        if (cam_udp_sof_evt)
            sel_eff <= src_sel_sy[1];
    end
end

//G11n17 板测定案：相机流 40bit 组内像素序与图案源相反（raw_2_axi4st 按字段
//{p3,p2,p1,p0} 组装，raw10_pat_src 按 {p0,p1,p2,p3}）。反序流的下游效应：
//GRBG 解码颜色凑巧正确（RGGB 行 R Gr R Gr 反序后= Gr R Gr R），但组边界像素
//邻接断裂 → 细锯齿（PC 端 perm×CFA 枚举实证：反序+GRBG 色度噪声 9.72 vs
//当前 15.23，唯一显著赢家）；参考工程"WB 标定 200/235/180 发绿"同为此因。
//修复：cam 源进 mux 前字段反序，与图案路径约定一致；PC 端恢复原生 RGGB 解码。
assign src_tdata  = sel_eff ? pat_tdata
                            : {raw_tdata[9:0],   raw_tdata[19:10],
                               raw_tdata[29:20], raw_tdata[39:30]};
assign src_tvalid = sel_eff ? pat_tvalid : raw_tvalid;
assign src_tlast  = sel_eff ? pat_tlast  : raw_tlast;
assign src_tuser  = sel_eff ? pat_tuser  : raw_tuser;

// 200M 写侧：arm 同步沿 → 等下一帧 sof → 连写 CAP_BEATS 拍入 FIFO → done
always @(posedge clk_200m or negedge clk_200m_rstn) begin
    if (!clk_200m_rstn) begin
        cap_arm_sy     <= 3'b000;
        cap_armed_200  <= 1'b0;
        cap_active     <= 1'b0;
        cap_done_200   <= 1'b0;
        cap_wptr       <= 13'h0;
        cap_fifo_wr_en <= 1'b0;
    end else begin
        cap_arm_sy <= {cap_arm_sy[1:0], cap_arm_w};
        cap_wr_data_r <= raw_tdata;             //G11i：数据通路随打一拍的 wr_en 延迟一拍
        if (cap_arm_sy[1:0] == 2'b01) begin        // arm 上升沿：复位上轮 done
            cap_armed_200 <= 1'b1;
            cap_done_200  <= 1'b0;
        end
        cap_fifo_wr_en <= 1'b0;
        if (cap_armed_200 & raw_tvalid & raw_tuser[0]) begin
            cap_armed_200  <= 1'b0;                // sof 拍即首拍（tuser={eof,sol,sof}），直接写入
            cap_active     <= 1'b1;
            cap_wptr       <= 13'd1;
            cap_fifo_wr_en <= ~cap_fifo_full;
        end else if (cap_active & raw_tvalid) begin
            cap_fifo_wr_en <= ~cap_fifo_full;
            if (cap_wptr == CAP_BEATS_M1) begin
                cap_active   <= 1'b0;
                cap_done_200 <= 1'b1;
            end else begin
                cap_wptr <= cap_wptr + 1'b1;
            end
        end
    end
end

//G11i：标准 FIFO 首组预读 + 持有标志。hold 空且 FIFO 非空 → 自动补一发 rd；
//CSR 读命中下一组则 hold 保持（读即装载），FIFO 已空则 hold 清零（后续读
//重复末组，与原 FWFT 行为一致，固件按捕获长度读不会越界）。
//（声明必须前置于 u_cap_fifo 例化——端口先引用后声明会分裂成隐式网，G8 同款坑）
reg  cap_hold_v;
wire cap_pre_rd  = !cap_hold_v && !cap_fifo_empty;
wire cap_rd_hit  = (cap_rd_en_w || cap_pre_rd) && !cap_fifo_empty;
wire cap_rd_en_f = cap_rd_en_w | cap_pre_rd;
always @(posedge clk_50m or negedge clk_50m_rstn) begin
    if (!clk_50m_rstn)    cap_hold_v <= 1'b0;
    else if (cap_rd_hit)  cap_hold_v <= 1'b1;   // CSR 读且有下一组 / 预读装载
    else if (cap_rd_en_w) cap_hold_v <= 1'b0;   // CSR 读且 FIFO 空：消费持有组
end

//G11i：跨钟缓存换标准 async_fifo（与 u_cam_udp_fifo 统一，废弃 FWFT）。CSR 协议
//时序不变：0x2B4/0x2B8 读拍采样 dout，rd 脉冲下一拍才换组 → 同拍采样即当前组。
//唯一缺口是首组需一次 rd 才呈现，由上方预读逻辑补上。
async_fifo #(
    .WIDTH (40),
    .DEPTH (32768)
) u_cap_fifo (
    .wr_clk   (clk_200m        ),
    .wr_rst_n (clk_200m_rstn   ),
    .wr_en    (cap_fifo_wr_en  ),
    .din      (cap_wr_data_r   ),
    .full     (cap_fifo_full   ),
    .rd_clk   (clk_50m         ),
    .rd_rst_n (clk_50m_rstn    ),
    .rd_en    (cap_rd_en_f     ),
    .dout     (cap_fifo_dout   ),
    .empty    (cap_fifo_empty  )
);

// 50M 读侧：done 同步与读出计数（状态观测；done 沿回零）
always @(posedge clk_50m or negedge clk_50m_rstn) begin
    if (!clk_50m_rstn) begin
        cap_done_sy <= 3'b000;
        cap_rcnt_q  <= 12'h0;
    end else begin
        cap_done_sy <= {cap_done_sy[1:0], cap_done_200};
        if (cap_done_sy[1:0] == 2'b01)
            cap_rcnt_q <= 12'h0;
        else if (cap_rd_en_w & !cap_fifo_empty)
            cap_rcnt_q <= cap_rcnt_q + 1'b1;
    end
end

// ---- G10 相机 UDP 直推（200M 写侧）：sof 开窗 → 整帧窗口组入流 FIFO ----
// G11n15 帧对齐：每帧帧首组前插 2 组魔数 40'hFFFFFFFFFF + 40'h0000000000
// （RAW10 里"全白组紧跟全黑组"概率极低）→ FIFO 数据流按帧分节 → PC 按字节流
// 魔数切帧（每帧重对齐自愈，图案/相机切换无需重算帧号）。实现：数据与写门控
// 各延迟 3 拍（d1→d2→d3），sof 拍启动 ins_cnt 1→2→3→0：
//   t=sof 拍    : wr_gate = cam_src_sy[1]&!full（帧首组过门）
//   t+2 拍写 M1 : ins_cnt==1 → wr_data=FFFFFFFFFF，wr_en=cam_src_sy[1]&!full
//   t+3 拍写 M2 : ins_cnt==2 → wr_data=0000000000
//   t+4 拍写帧首组: default → wr_data=dat_d3(=raw_tdata@t)，wr_en=vld_d3(=wr_gate@t)
// 帧首前 ~17ms 消隐大 gap 保证 vld 链干净（残 vld=0）。帧尾 17.35ms gap 排空
// FIFO → 下一帧魔数天然在 FIFO 头。旧"帧尾软复位"已删（G11h 连续流），3 拍延迟无影响。
//G11n16：帧事件改吃源 mux 输出（相机/图案两源同构接口，图案源同样每帧
//sof/eof 各 1 拍 → 魔数插入与帧开窗逻辑两源通用，无需改动）
assign cam_udp_sof_evt = src_tvalid & src_tuser[0];   // 帧首组（sof，tuser={eof,sol,sof}）
assign cam_udp_eof_evt = src_tvalid & src_tuser[2];   // 帧末组（eof）
// 自由计数器：不受任何使能门控，读数步进 = 时钟活
always @(posedge clk_200m) free200_cnt <= free200_cnt + 16'd1;
always @(posedge clk_100m) free100_cnt <= free100_cnt + 16'd1;
//G11n15 魔数插入通路
reg  [1:0]  cam_ins_cnt;                    // sof 拍→1，随后 1→2→3→0（模 4 回零）
reg  [39:0] cam_dat_d1, cam_dat_d2, cam_dat_d3;   // 数据延迟 3 拍
reg         cam_vld_d1, cam_vld_d2, cam_vld_d3;   // 写门控延迟 3 拍（与数据同相）
wire        cam_udp_wr_gate = cam_udp_sof_evt ? (cam_src_sy[1] & !cam_udp_full)
                                                : (cam_udp_armed & src_tvalid & !cam_udp_full);
always @(posedge clk_200m or negedge clk_200m_rstn) begin
    if (!clk_200m_rstn) begin
        cam_src_sy        <= 2'b00;
        cam_udp_armed     <= 1'b0;
        cam_udp_wr_en     <= 1'b0;
        cam_fullrej_cnt   <= 32'h0;
        cam_udp_sof_tg    <= 1'b0;
        cam_udp_eof_evt_r <= 1'b0;
        cam_ins_cnt       <= 2'd0;
        cam_dat_d1 <= 40'h0; cam_dat_d2 <= 40'h0; cam_dat_d3 <= 40'h0;
        cam_vld_d1 <= 1'b0;  cam_vld_d2 <= 1'b0;  cam_vld_d3 <= 1'b0;
    end else begin
        cam_src_sy <= {cam_src_sy[0], cam_src_en};
        //数据/门控延迟链（无条件移位；帧间 gap 期 gate=0 自然清零）
        cam_dat_d1 <= src_tdata;
        cam_dat_d2 <= cam_dat_d1;
        cam_dat_d3 <= cam_dat_d2;
        cam_vld_d1 <= cam_udp_wr_gate;
        cam_vld_d2 <= cam_vld_d1;
        cam_vld_d3 <= cam_vld_d2;
        //G11n15：sof 拍启动魔数计数（sof 间隔 ~17ms ≫ 3 拍，无竞争）
        if (cam_udp_sof_evt)
            cam_ins_cnt <= 2'd1;
        else if (cam_ins_cnt != 2'd0)
            cam_ins_cnt <= cam_ins_cnt + 2'd1;    // 1→2→3→0
        //写数据选择：ins_cnt==1/2 为魔数组，其余透传延迟后的帧数据
        case (cam_ins_cnt)
            2'd1:    cam_udp_wr_data <= 40'hFFFFFFFFFF;   // M1：全白组
            2'd2:    cam_udp_wr_data <= 40'h0000000000;   // M2：全黑组
            default: cam_udp_wr_data <= cam_dat_d3;
        endcase
        //G11h 修复：必须 sof 拍翻转（pacer 契约"写侧每帧 sof 翻转"）。原挂 eof →
        //首帧 frame_active 恒 0 → gen 全程不发 → FIFO 满 → 整帧像素被拒（sim 实证
        //full_rej=517374/518400），后续帧边界错位（板上"帧没对齐"+灰带根因）
        //写使能：魔数组两拍强制过门（帧首 FIFO 近空，full 必 0）；其余用延迟门控
        if (cam_ins_cnt == 2'd1 || cam_ins_cnt == 2'd2)
            cam_udp_wr_en <= cam_src_sy[1] & !cam_udp_full;
        else
            cam_udp_wr_en <= cam_vld_d3;
        if (cam_udp_sof_evt)
            cam_udp_sof_tg <= ~cam_udp_sof_tg;      // 帧首 toggle → pacer（帧边界对齐）
        if (cam_udp_sof_evt) begin
            cam_udp_armed <= cam_src_sy[1];         // 新帧开窗（使能后下一帧生效）
        end
        cam_udp_eof_evt_r <= cam_udp_eof_evt;
        //G11n14：顶层 wcnt/wgray 镜像计数块已删——写计数由 cam_fifo_bank 内部
        // wr_accept 同源承担（原 G11n6 板级实证镜像多计 7 问题连根消除）
        //G11n6：rej 改当拍判满（armed&&raw_tvalid&&full）。原判据 wr_en&&full 只计
        //"放行后被拒"一拍，漏计被 full 压掉 wr_en 的 skip 拍——G11n5 板测收支铁证：
        //rawdt 15.48M = accept 11.38M + rej 0.58M + skip 3.52M（skip 6 倍于 rej 且
        //从未被计数）。新语义 [2EC]=armed 窗口内真满丢组总数（rej+skip 合一）。
        if (cam_udp_armed && src_tvalid && cam_udp_full)
            cam_fullrej_cnt <= cam_fullrej_cnt + 32'd1;
    end
end

//G11n9 裁决探针（200M）：full 时间分布 + rej/tvalid run-length 峰值。
//背景：板测"锯齿 82~500 稳态（白等 50.8%/occ 快照 31 自洽）"与"rej 21%"物理矛盾，
//需 full/occ 时间分布裁决（假满脉冲 / 低频长段 / 计数器虚计三选一）。
//判据（cam 快照差分 + 峰值直读）：fullhi/rise=单次满事件平均时长；rejrun_max=最长
//泄洪段；tvrun_max=写侧最长连续段（对照"tvalid 摊满一行"知识，发现密簇）。
//跨域直读同 cam_fullrej_cnt 先例（单调/峰值，撕裂误差无害）。
reg        cam_full_d;
reg [31:0] cam_rejrun_r, cam_tvrun_r;
wire       cam_rej_now = cam_udp_armed && raw_tvalid && cam_udp_full;
always @(posedge clk_200m or negedge clk_200m_rstn) begin
    if (!clk_200m_rstn) begin
        cam_fullhi_cnt   <= 32'h0;
        cam_fullrise_cnt <= 32'h0;
        cam_rejrun_max   <= 32'h0;
        cam_tvrun_max    <= 32'h0;
        cam_full_d       <= 1'b0;
        cam_rejrun_r     <= 32'h0;
        cam_tvrun_r      <= 32'h0;
    end else begin
        cam_full_d <= cam_udp_full;
        if (cam_udp_full)
            cam_fullhi_cnt <= cam_fullhi_cnt + 32'd1;
        if (cam_udp_full && !cam_full_d)
            cam_fullrise_cnt <= cam_fullrise_cnt + 32'd1;
        if (cam_rej_now) begin
            cam_rejrun_r <= cam_rejrun_r + 32'd1;
            if (cam_rejrun_r + 32'd1 > cam_rejrun_max)
                cam_rejrun_max <= cam_rejrun_r + 32'd1;
        end else begin
            cam_rejrun_r <= 32'h0;
        end
        if (raw_tvalid) begin
            cam_tvrun_r <= cam_tvrun_r + 32'd1;
            if (cam_tvrun_r + 32'd1 > cam_tvrun_max)
                cam_tvrun_max <= cam_tvrun_r + 32'd1;
        end else begin
            cam_tvrun_r <= 32'h0;
        end
    end
end

//G11n11 行间隔分布裁决探针（200M）：hs（tuser[1]=SOL）到 hs 的拍数 max/min。
//背景：门限 300→2048 板测 rej 恒 112K/帧、occ_peak 恒 8192、白等恒 50%——
//净积与门限值完全无关 → 写入"慢-猛"两形态交替；猛段疑为多行密排（行间
//gap 消失，90% 占空连续多行净积 156M/s）。均匀行应 gap≈6000（30µs@200M）
//稳定；密排段 gap_min≈633。ILA 单行窗口与 hs 总数计数均看不到分布，
//此探针一次裁决。0x320=hsgap_max 0x324=hsgap_min（保持型，撕裂无害）。
reg [31:0] cam_hsgap_r;
wire       cam_hs_evt = raw_tvalid && raw_tuser[1];
//G11n13 直方图（min=2961 实锤"半距行"后需分布形态闭合 rej 机制）：
//A<3500 近距/密排行 B=3500..5499 偏近 C=5500..7999 正常 30µs 带 D>=8000 远距。
//max 改帧内语义（sof 清零，去除启动/停流历史污染——上轮 max=515ms 无参考价值）。
wire       cam_sof2_evt = raw_tvalid && raw_tuser[0];
always @(posedge clk_200m or negedge clk_200m_rstn) begin
    if (!clk_200m_rstn) begin
        cam_hsgap_r   <= 32'h0;
        cam_hsgap_max <= 32'h0;
        cam_hsgap_min <= 32'hFFFFFFFF;
        cam_hsgap_a   <= 32'h0;
        cam_hsgap_b   <= 32'h0;
        cam_hsgap_c   <= 32'h0;
        cam_hsgap_d   <= 32'h0;
    end else if (cam_hs_evt) begin
        if (cam_sof2_evt) cam_hsgap_max <= 32'h0;   //帧首行拍清零（sof/hs 同拍）
        cam_hsgap_r <= 32'h0;
        if (cam_hsgap_r != 32'h0) begin      //首个 hs 无参考，不计
            if (cam_hsgap_r > cam_hsgap_max) cam_hsgap_max <= cam_hsgap_r;
            if (cam_hsgap_r < cam_hsgap_min) cam_hsgap_min <= cam_hsgap_r;
            if      (cam_hsgap_r < 32'd3500) cam_hsgap_a <= cam_hsgap_a + 32'd1;
            else if (cam_hsgap_r < 32'd5500) cam_hsgap_b <= cam_hsgap_b + 32'd1;
            else if (cam_hsgap_r < 32'd8000) cam_hsgap_c <= cam_hsgap_c + 32'd1;
            else                             cam_hsgap_d <= cam_hsgap_d + 32'd1;
        end
    end else begin
        cam_hsgap_r <= cam_hsgap_r + 32'd1;
    end
end

//G11n TX 背压定量（125M，卷动根因定位）：gen→mux(2:1)→mux(3:1)→MAC 两级 mux
//组合直通，udp_tx_axis_mac_tready ≈ MAC tready。pkt=包完成数（实际发包率）；
//bp=tvalid&&!tready 拍（MAC 背压定量）。跨域直读同 cam_dt_cnt 先例（单调计数，
//撕裂误差无害，判据看步进）。判据：pkt 差/s=包率（对照 81.2K/s 线速需求）；
//bp/(125M×窗口)=背压占空比。
always @(posedge tx_axis_clk or negedge mac_rstn) begin
    if (!mac_rstn) begin
        cam_tx_pkt_cnt <= 32'h0;
        cam_tx_bp_cnt  <= 32'h0;
    end else begin
        if (udp_tx_axis_mac_tvalid && udp_tx_axis_mac_tready && udp_tx_axis_mac_tlast)
            cam_tx_pkt_cnt <= cam_tx_pkt_cnt + 32'd1;
        if (udp_tx_axis_mac_tvalid && !udp_tx_axis_mac_tready)
            cam_tx_bp_cnt <= cam_tx_bp_cnt + 32'd1;
    end
end

//G11n2 裁决探针（125M）：板上 CAMDBG6 定量——背压仅 0.34%（MAC 无罪）但 gen
//25µs/包（白等 ~12.5µs/包），且收支缺口 3.73M 组/s（FIFO 接受 15.33M ≠ 进包
//11.6M）。rd=cam_quad_rd 拉高（rd 条件含 !empty → 每拉必弹）：若 rd率≈接受率
//→ 组在 gen 内丢弃；若 rd率≈进包率 → 写侧计数虚高。ipgwait=S_IPG&&!go 白等拍：
//若 ≈12.5µs/包 → pacer occ 视角偏低门控过严（主嫌疑）。S_IPG=3'h3（同 pacer）。
always @(posedge tx_axis_clk or negedge mac_rstn) begin
    if (!mac_rstn) begin
        cam_rd_cnt      <= 32'h0;
        cam_ipgwait_cnt <= 32'h0;
        cam_ipgnact_cnt <= 32'h0;
        cam_ipgnoarm_cnt <= 32'h0;
    end else begin
        if (cam_quad_rd_w)
            cam_rd_cnt <= cam_rd_cnt + 32'd1;
        if ((pat_dbg_w[5:3] == 3'h3) && !cam_pkt_go_w) begin
            cam_ipgwait_cnt <= cam_ipgwait_cnt + 32'd1;
            if (!cam_pact)
                cam_ipgnact_cnt <= cam_ipgnact_cnt + 32'd1;   //帧门关（need_pkt=0）
            else if (!cam_parmed)
                cam_ipgnoarm_cnt <= cam_ipgnoarm_cnt + 32'd1; //occ 门（armed=0）
        end
    end
end

//G11j 板级诊断（occ=82 冻结回归，2026-11-07）：观测对称化——[270] 只计窗口模块
//输入拍（cam_pixel_valid&dtype），此处补输出侧：raw_tvalid 拍计数 + sof 事件计数。
//判据（两次快读比差）：[2D0] 步进=窗口输出活；[2D0] 冻结而 [270] 活=帧界停摆；
//[2CC] 低 30 位 +1/33ms=sof 仍在到；[2CC] bit31/30=full/armed 实时电平（frozen 态
//准静态，直读安全——同 cam_dt_cnt 跨域直读先例）。
always @(posedge clk_200m or negedge clk_200m_rstn) begin
    if (!clk_200m_rstn) begin
        cam_sof_cnt   <= 32'h0;
        cam_rawdt_cnt <= 32'h0;
    end else begin
        if (raw_tvalid)      cam_rawdt_cnt <= cam_rawdt_cnt + 32'd1;
        if (cam_udp_sof_evt) cam_sof_cnt   <= cam_sof_cnt + 32'd1;
    end
end

//G11j-3（16 位计数器 2s 回绕歧义后改版，全 32 位 + 裸/门控对照）：
//  0x2D4 = tuser[1] 裸计数（不与 tvalid 相与）——若裸计数步进(≈32.7K/s)而
//          [2CC]/[2D0] 的门控计数恒 0 → tuser 与 tvalid 错拍（消费侧对齐 bug）
//  0x2D8 = tuser[0] 裸计数（应 ≈30/s）
//  0x2DC = vs 上升沿 32 位 / 0x2E0 = hs 上升沿 32 位（应 ≈30/s 与 32.7K/s）
reg [31:0] cam_tuser1_cnt;   // tuser[1] 裸计数
reg [31:0] cam_tuser0_cnt;   // tuser[0] 裸计数
reg [31:0] cam_vs_edge_cnt, cam_hs_edge_cnt;
reg        cam_vs_d, cam_hs_d;
always @(posedge clk_200m or negedge clk_200m_rstn) begin
    if (!clk_200m_rstn) begin
        cam_tuser1_cnt   <= 32'h0;
        cam_tuser0_cnt   <= 32'h0;
        cam_vs_edge_cnt  <= 32'h0;
        cam_hs_edge_cnt  <= 32'h0;
        cam_vs_d         <= 1'b0;
        cam_hs_d         <= 1'b0;
    end else begin
        cam_vs_d <= cam_pixel_vs;
        cam_hs_d <= cam_pixel_hs;
        if (raw_tuser[1])          cam_tuser1_cnt  <= cam_tuser1_cnt + 32'd1;
        if (raw_tuser[0])          cam_tuser0_cnt  <= cam_tuser0_cnt + 32'd1;
        if (cam_pixel_vs & ~cam_vs_d) cam_vs_edge_cnt  <= cam_vs_edge_cnt + 32'd1;
        if (cam_pixel_hs & ~cam_hs_d) cam_hs_edge_cnt  <= cam_hs_edge_cnt + 32'd1;
    end
end
assign cam_mark_dbg = cam_tuser1_cnt;                          // 0x2D4
assign cam_sync_dbg = cam_tuser0_cnt;                          // 0x2D8
assign cam_vsedge_dbg = cam_vs_edge_cnt;                       // 0x2DC
assign cam_hsedge_dbg = cam_hs_edge_cnt;                       // 0x2E0

// 错误脉冲边沿计数（100M 域 = DPHY CFG_CLK 域）
wire cam_err_sot_any     = dphy_rx2_ERR_SOT_HS_LAN0 | dphy_rx2_ERR_SOT_HS_LAN1
                         | dphy_rx2_ERR_SOT_HS_LAN2 | dphy_rx2_ERR_SOT_HS_LAN3;
wire cam_err_sotsync_any = dphy_rx2_HS_LAN0_SOTSYNC_ERROR | dphy_rx2_HS_LAN1_SOTSYNC_ERROR
                         | dphy_rx2_HS_LAN2_SOTSYNC_ERROR | dphy_rx2_HS_LAN3_SOTSYNC_ERROR;
wire cam_err_esc_any     = dphy_rx2_ESC_LAN0_ERROR | dphy_rx2_ESC_LAN1_ERROR
                         | dphy_rx2_ESC_LAN2_ERROR | dphy_rx2_ESC_LAN3_ERROR;
wire cam_err_ls_any      = dphy_rx2_LINESTATE_LAN0_ERROR | dphy_rx2_LINESTATE_LAN1_ERROR
                         | dphy_rx2_LINESTATE_LAN2_ERROR | dphy_rx2_LINESTATE_LAN3_ERROR;
reg cam_err_sot_d, cam_err_sotsync_d, cam_err_esc_d, cam_err_ls_d;
reg [15:0] cam_err_sot_cnt, cam_err_sotsync_cnt, cam_err_esc_cnt, cam_err_ls_cnt;
always @(posedge clk_100m or negedge clk_100m_rstn) begin
    if (!clk_100m_rstn) begin
        cam_err_sot_d     <= 1'b0;
        cam_err_sotsync_d <= 1'b0;
        cam_err_esc_d     <= 1'b0;
        cam_err_ls_d      <= 1'b0;
        cam_err_sot_cnt     <= 16'h0;
        cam_err_sotsync_cnt <= 16'h0;
        cam_err_esc_cnt     <= 16'h0;
        cam_err_ls_cnt      <= 16'h0;
    end else begin
        cam_err_sot_d     <= cam_err_sot_any;
        cam_err_sotsync_d <= cam_err_sotsync_any;
        cam_err_esc_d     <= cam_err_esc_any;
        cam_err_ls_d      <= cam_err_ls_any;
        if (cam_err_sot_any     & ~cam_err_sot_d)     cam_err_sot_cnt     <= cam_err_sot_cnt     + 16'd1;
        if (cam_err_sotsync_any & ~cam_err_sotsync_d) cam_err_sotsync_cnt <= cam_err_sotsync_cnt + 16'd1;
        if (cam_err_esc_any     & ~cam_err_esc_d)     cam_err_esc_cnt     <= cam_err_esc_cnt     + 16'd1;
        if (cam_err_ls_any      & ~cam_err_ls_d)      cam_err_ls_cnt      <= cam_err_ls_cnt      + 16'd1;
    end
end

// 状态位 2FF 同步进 APB(50M) 域（准静态位；I2C dbg 计数器逐事务变化，判读按准静态）
(* syn_keep = "true" *) reg [1:0] st_busy_sync, st_done_sync, st_fail_sync, st_en_sync;
(* syn_keep = "true" *) reg [1:0] st_stopclk_sync, st_active_sync, st_pll_sync;
(* syn_keep = "true" *) reg [7:0] st_idx_s1, st_idx_s2;
(* syn_keep = "true" *) reg [1:0] st_round_s1, st_round_s2;
(* syn_keep = "true" *) reg [3:0] st_retry_s1, st_retry_s2;
always @(posedge clk_50m) begin
    st_busy_sync    <= {st_busy_sync[0],    cam_i2c_busy};
    st_done_sync    <= {st_done_sync[0],    cam_i2c_done};
    st_fail_sync    <= {st_fail_sync[0],    cam_i2c_fail};
    st_en_sync      <= {st_en_sync[0],      cam_i2c_en};
    st_stopclk_sync <= {st_stopclk_sync[0], dphy_rx2_STOPSTATE_CLK};
    st_active_sync  <= {st_active_sync[0],  dphy_rx2_RX_CLK_ACTIVE_HS};
    st_pll_sync     <= {st_pll_sync[0],     pll_0_locked};
    st_idx_s1       <= cam_i2c_dbg_idx;
    st_idx_s2       <= st_idx_s1;
    st_round_s1     <= cam_i2c_dbg_round;
    st_round_s2     <= st_round_s1;
    st_retry_s1     <= cam_i2c_dbg_retry;
    st_retry_s2     <= st_retry_s1;
end
// pll_0_locked 上升沿计数（clk_50m 域，无复位自由计数；判据：0=异常，
// 持续增长/≥1=锁定正常）——注意 bit20 现在语义是 pll_0_locked
// G10 防删独立消费链（'h093 魔数同构）：cam_i2c 原始状态直接打包进 CSR 0x2C8，
// 给综合器一条跨域真负载，防止 cam_i2c_init 被整体优化删除（g10e/g10f 网表事故）。
// bit15 = clk_200m_rstn：给 rst_200m_sync[2]（"no fanout" 警告的真凶）一个不可删
// 扇出；板上读 bit15 可判复位释放状态（0=200M 域复位未释放=锁死根因）
wire [15:0] cam_i2c_stat = {clk_200m_rstn, 3'h0, cam_i2c_dbg_retry, cam_i2c_dbg_round,
                            cam_i2c_busy, cam_i2c_fail, cam_i2c_done, cam_i2c_en};
reg       st_pll_d3;
reg [7:0] cam_lock_edge_cnt;
always @(posedge clk_50m) begin
    st_pll_d3 <= st_pll_sync[1];
    if (st_pll_sync[1] & ~st_pll_d3)
        cam_lock_edge_cnt <= cam_lock_edge_cnt + 8'd1;
end
// G8 诊断：数据 lane 活动探针（2026-11-06，挂 CSR 0x2AC）
// [7:4]=STOPSTATE_LANx 实时（LP-11=1，准静态 2FF 同步）
// [3:0]=lane_seen 粘滞位：HS_LANx_VALID 出现过脉冲即置位（无复位自由运行）
wire [3:0] lane_vld  = {dphy_rx2_HS_LAN3_VALID,  dphy_rx2_HS_LAN2_VALID,
                        dphy_rx2_HS_LAN1_VALID,  dphy_rx2_HS_LAN0_VALID};
wire [3:0] lane_stop = {dphy_rx2_STOPSTATE_LAN3, dphy_rx2_STOPSTATE_LAN2,
                        dphy_rx2_STOPSTATE_LAN1, dphy_rx2_STOPSTATE_LAN0};
(* ASYNC_REG = "TRUE" *) reg [3:0] lane_vld_s1, lane_vld_s2;
(* ASYNC_REG = "TRUE" *) reg [3:0] lane_stop_s1, lane_stop_s2;
reg [3:0] lane_seen;
always @(posedge clk_50m) begin
    lane_vld_s1  <= lane_vld;
    lane_vld_s2  <= lane_vld_s1;
    lane_stop_s1 <= lane_stop;
    lane_stop_s2 <= lane_stop_s1;
    lane_seen    <= lane_seen | lane_vld_s2;
end
assign cam_lane_status = {lane_stop_s2, lane_seen};

assign cam_status = {cam_lock_edge_cnt, 3'h0,
                          st_pll_sync[1],
                          st_retry_s2, st_round_s2, st_idx_s2,
                          st_stopclk_sync[1], st_active_sync[1],
                          st_fail_sync[1], st_done_sync[1],
                          st_busy_sync[1], st_en_sync[1]};

endmodule

