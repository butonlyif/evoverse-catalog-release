
// Efinity Top-level template
// Version: 2023.1.150.5.11
// Date: 2023-11-06 12:28

// Copyright (C) 2017 - 2023 Efinix Inc. All rights reserved.

// This file may be used as a starting point for Efinity synthesis top-level target.
// The port list here matches what is expected by Efinity constraint files generated
// by the Efinity Interface Designer.

// To use this:
//     #1)  Save this file with a different name to a different directory, where source files are kept.
//              Example: you may wish to save as D:\wrw\Project\Ti_demo\Ti180MIPI\Ti180MIPI.v
//     #2)  Add the newly saved file into Efinity project as design file
//     #3)  Edit the top level entity in Efinity project to:  Ti180MIPI
//     #4)  Insert design content.

`include  "source/MIPI_RAW/MIPI_Parameter.v"
module Top
(
  input MIPI_REF_CLK,
  input pll_inst1_LOCKED,
  input pll_inst2_LOCKED,
  input mipi_dphy_rx_inst2_ERR_CONTENTION_LP0,
  input mipi_dphy_rx_inst2_ERR_CONTENTION_LP1,
  input mipi_dphy_rx_inst2_LINESTATE_LAN0_ERROR,
  input mipi_dphy_rx_inst2_LINESTATE_LAN1_ERROR,
  input mipi_dphy_rx_inst2_LINESTATE_LAN2_ERROR,
  input mipi_dphy_rx_inst2_LINESTATE_LAN3_ERROR,
  input mipi_dphy_rx_inst2_ESC_LAN0_ERROR,
  input mipi_dphy_rx_inst2_ESC_LAN1_ERROR,
  input mipi_dphy_rx_inst2_ESC_LAN2_ERROR,
  input mipi_dphy_rx_inst2_ESC_LAN3_ERROR,
  input mipi_dphy_rx_inst2_ERR_SOT_HS_LAN0,
  input mipi_dphy_rx_inst2_ERR_SOT_HS_LAN1,
  input mipi_dphy_rx_inst2_ERR_SOT_HS_LAN2,
  input mipi_dphy_rx_inst2_ERR_SOT_HS_LAN3,
  input mipi_dphy_rx_inst2_HS_LAN0_SOTSYNC_ERROR,
  input mipi_dphy_rx_inst2_HS_LAN1_SOTSYNC_ERROR,
  input mipi_dphy_rx_inst2_HS_LAN2_SOTSYNC_ERROR,
  input mipi_dphy_rx_inst2_HS_LAN3_SOTSYNC_ERROR,
  input mipi_dphy_rx_inst2_LP_CLK,
  input mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN0,
  input mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN1,
  input mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN2,
  input mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN3,
  input mipi_dphy_rx_inst2_RX_CLK_ACTIVE_HS,
  input mipi_dphy_rx_inst2_ESC_LAN0_CLK,
  input mipi_dphy_rx_inst2_ESC_LAN1_CLK,
  input mipi_dphy_rx_inst2_ESC_LAN2_CLK,
  input mipi_dphy_rx_inst2_ESC_LAN3_CLK,
  input [7:0] mipi_dphy_rx_inst2_RX_DATA_ESC,
  input [15:0] mipi_dphy_rx_inst2_HS_LAN0_DATA,
  input [15:0] mipi_dphy_rx_inst2_HS_LAN1_DATA,
  input [15:0] mipi_dphy_rx_inst2_HS_LAN2_DATA,
  input [15:0] mipi_dphy_rx_inst2_HS_LAN3_DATA,
  input mipi_dphy_rx_inst2_RX_LPDT_ESC,
  input mipi_dphy_rx_inst2_HS_LAN0_SKEWCAL,
  input mipi_dphy_rx_inst2_HS_LAN1_SKEWCAL,
  input mipi_dphy_rx_inst2_HS_LAN2_SKEWCAL,
  input mipi_dphy_rx_inst2_HS_LAN3_SKEWCAL,
  input mipi_dphy_rx_inst2_HS_LAN0_SYNC,
  input mipi_dphy_rx_inst2_HS_LAN1_SYNC,
  input mipi_dphy_rx_inst2_HS_LAN2_SYNC,
  input mipi_dphy_rx_inst2_HS_LAN3_SYNC,
  input [3:0] mipi_dphy_rx_inst2_RX_TRIGGER_ESC,
  input mipi_dphy_rx_inst2_ULPS_CLK_ACTIVEN,
  input mipi_dphy_rx_inst2_ULPS_LAN0_ACTIVEN,
  input mipi_dphy_rx_inst2_ULPS_LAN1_ACTIVEN,
  input mipi_dphy_rx_inst2_ULPS_LAN2_ACTIVEN,
  input mipi_dphy_rx_inst2_ULPS_LAN3_ACTIVEN,
  input mipi_dphy_rx_inst2_ULPS_CLK_ENTER,
  input mipi_dphy_rx_inst2_ULPS_LAN0_ENTER,
  input mipi_dphy_rx_inst2_ULPS_LAN1_ENTER,
  input mipi_dphy_rx_inst2_ULPS_LAN2_ENTER,
  input mipi_dphy_rx_inst2_ULPS_LAN3_ENTER,
  input mipi_dphy_rx_inst2_RX_VALID_ESC,
  input mipi_dphy_rx_inst2_HS_LAN0_VALID,
  input mipi_dphy_rx_inst2_HS_LAN1_VALID,
  input mipi_dphy_rx_inst2_HS_LAN2_VALID,
  input mipi_dphy_rx_inst2_HS_LAN3_VALID,
  input mipi_dphy_rx_inst2_STOPSTATE_CLK,
  input mipi_dphy_rx_inst2_STOPSTATE_LAN0,
  input mipi_dphy_rx_inst2_STOPSTATE_LAN1,
  input mipi_dphy_rx_inst2_STOPSTATE_LAN2,
  input mipi_dphy_rx_inst2_STOPSTATE_LAN3,
  input mipi_dphy_tx_inst1_PLL_UNLOCK,
  input mipi_dphy_tx_inst1_STOPSTATE_CLK,
  input mipi_dphy_tx_inst1_STOPSTATE_LAN0,
  input mipi_dphy_tx_inst1_STOPSTATE_LAN1,
  input mipi_dphy_tx_inst1_STOPSTATE_LAN2,
  input mipi_dphy_tx_inst1_STOPSTATE_LAN3,
  input mipi_dphy_tx_inst1_TX_READY_ESC,
  input mipi_dphy_tx_inst1_HS_LAN0_READY,
  input mipi_dphy_tx_inst1_HS_LAN1_READY,
  input mipi_dphy_tx_inst1_HS_LAN2_READY,
  input mipi_dphy_tx_inst1_HS_LAN3_READY,
  input mipi_dphy_tx_inst1_ULPS_CLK_ACTIVEN,
  input mipi_dphy_tx_inst1_ULPS_LAN0_ACTIVEN,
  input mipi_dphy_tx_inst1_ULPS_LAN1_ACTIVEN,
  input mipi_dphy_tx_inst1_ULPS_LAN2_ACTIVEN,
  input mipi_dphy_tx_inst1_ULPS_LAN3_ACTIVEN,
  input pll_inst2_CLKOUT3,
  input cfg_clk,
  input pll_inst2_CLKOUT2,
  input esc_clk,
  input clk0,
  input mipi_dphy_rx_clk_CLKOUT,
  input mipi_dphy_tx_SLOWCLK,
  input mipi_clk,
  input pixel_clk,
  input mipi_pll_refclkp,
  // input reset_n,
  input start_transfer_n,
  output mipi_dphy_rx_inst2_FORCE_RX_MODE,
  output mipi_dphy_rx_inst2_RESET,
  output mipi_dphy_rx_inst2_RST0_N,
  output mipi_dphy_tx_inst1_PLL_SSC_EN,
  output mipi_dphy_tx_inst1_RESET,
  output [7:0] mipi_dphy_tx_inst1_TX_DATA_ESC,
  output [15:0] mipi_dphy_tx_inst1_HS_LAN0_DATA,
  output [15:0] mipi_dphy_tx_inst1_HS_LAN1_DATA,
  output [15:0] mipi_dphy_tx_inst1_HS_LAN2_DATA,
  output [15:0] mipi_dphy_tx_inst1_HS_LAN3_DATA,
  output mipi_dphy_tx_inst1_TX_LPDT_ESC,
  output mipi_dphy_tx_inst1_REQUESTESC_LAN0,
  output mipi_dphy_tx_inst1_REQUESTESC_LAN1,
  output mipi_dphy_tx_inst1_REQUESTESC_LAN2,
  output mipi_dphy_tx_inst1_REQUESTESC_LAN3,
  output mipi_dphy_tx_inst1_HS_CLK_REQUEST,
  output mipi_dphy_tx_inst1_HS_LAN0_REQUEST,
  output mipi_dphy_tx_inst1_HS_LAN1_REQUEST,
  output mipi_dphy_tx_inst1_HS_LAN2_REQUEST,
  output mipi_dphy_tx_inst1_HS_LAN3_REQUEST,
  output mipi_dphy_tx_inst1_HS_LAN0_SKEWCAL,
  output mipi_dphy_tx_inst1_HS_LAN1_SKEWCAL,
  output mipi_dphy_tx_inst1_HS_LAN2_SKEWCAL,
  output mipi_dphy_tx_inst1_HS_LAN3_SKEWCAL,
  output [3:0] mipi_dphy_tx_inst1_TX_TRIGGER_ESC,
  output mipi_dphy_tx_inst1_ULPS_CLK_ENTER,
  output mipi_dphy_tx_inst1_ULPS_LAN0_ENTER,
  output mipi_dphy_tx_inst1_ULPS_LAN1_ENTER,
  output mipi_dphy_tx_inst1_ULPS_LAN2_ENTER,
  output mipi_dphy_tx_inst1_ULPS_LAN3_ENTER,
  output mipi_dphy_tx_inst1_ULPS_CLK_EXIT,
  output mipi_dphy_tx_inst1_ULPS_LAN0_EXIT,
  output mipi_dphy_tx_inst1_ULPS_LAN1_EXIT,
  output mipi_dphy_tx_inst1_ULPS_LAN2_EXIT,
  output mipi_dphy_tx_inst1_ULPS_LAN3_EXIT,
  output mipi_dphy_tx_inst1_TX_VALID_ESC,
  output mipi_dphy_tx_inst1_HS_LAN0_HIGHVALID,
  output mipi_dphy_tx_inst1_HS_LAN1_HIGHVALID,
  output mipi_dphy_tx_inst1_HS_LAN2_HIGHVALID,
  output mipi_dphy_tx_inst1_HS_LAN3_HIGHVALID,
  output [3:0] led,
  input jtag_inst1_CAPTURE,
  input jtag_inst1_DRCK,
  input jtag_inst1_RESET,
  input jtag_inst1_RUNTEST,
  input jtag_inst1_SEL,
  input jtag_inst1_SHIFT,
  input jtag_inst1_TCK,
  input jtag_inst1_TDI,
  input jtag_inst1_TMS,
  input jtag_inst1_UPDATE,
  output jtag_inst1_TDO
);
    parameter NUM_DATA_LANE = 4;
	parameter		TCo_C   		= 1;    


	localparam  [27:0]  TxPixelClkFreq_C  = `MipiTxPixelClkFreq;
	localparam  [27:0]  RxPixelClkFreq_C  = TxPixelClkFreq_C;
	parameter           RightCntWidth_C   = 24;
  
	localparam  RxClkCyclePerUs_C = RxPixelClkFreq_C / 28'd1_000_000;
	localparam  TxClkCyclePerUs_C = TxPixelClkFreq_C / 28'd1_000_000;

wire i_reset_pixel_n;
wire rx_out_valid_1P, rx_out_hs_1P;
wire mipi_clk_Reset_N, mipi_dphy_rx_reset_byte_HS_n,  mipi_dphy_tx_reset_byte_HS_n, reset_esc_n;
wire reset_pixel_n;
reg [21:0] count_led;
wire [5:0] datatype;
wire [15:0] word_count;
wire 	reset_n;
assign 	reset_n = 1'b1;
wire   Reset_N;
assign Reset_N = reset_n&pll_inst1_LOCKED&pll_inst2_LOCKED;
assign mipi_dphy_tx_inst1_RESET =   reset_n;
assign mipi_dphy_rx_inst2_RESET = reset_n;//reset_pixel_n_reg;// MipiRxDPHYRstN;//dphy reset_n
assign mipi_dphy_rx_inst2_RST0_N = reset_n;//MipiRxDPHYRstN;//FIFO reset

assign mipi_dphy_tx_inst1_ESC_CLK = esc_clk;
assign mipi_dphy_rx_inst2_CAL_CLK = cfg_clk;

always @ (posedge mipi_dphy_rx_clk_CLKOUT or negedge mipi_dphy_rx_reset_byte_HS_n) begin
    if (~mipi_dphy_rx_reset_byte_HS_n) begin
        count_led <= 22'h0;
    end
    else begin
        count_led <= count_led + 22'h1;
    end
end


wire  TxSysClk,RxSysClk;
assign TxSysClk = pixel_clk;
assign RxSysClk = pixel_clk;

//复位顺序

localparam RESET_COUNT          		= 32;
localparam RESET_PIXEL_COUNT            = 32'd62500000;
reg [31:0] 		rst_cnt;
always @(posedge pixel_clk or negedge Reset_N )
begin 
 if(~Reset_N) begin
  rst_cnt <= 32'b0 ; 
 end 
 else if(~rst_cnt[24]) begin 
  rst_cnt <= rst_cnt + 8'b1 ;
 end 
end 
 
assign	i_reset_pixel_n = (rst_cnt[24]== 1'b1)?1'b1 : 1'b0;

reset
#(
	.IN_RST_ACTIVE	("LOW"),
	.OUT_RST_ACTIVE	("LOW"),
	.CYCLE			(3)
)
inst_clk_rst
(
	.i_arst	(Reset_N),
	.i_clk	(mipi_clk),
	.o_srst	(mipi_clk_Reset_N)
);

reset
#(
	.IN_RST_ACTIVE	("LOW"),
	.OUT_RST_ACTIVE	("LOW"),
	.CYCLE			(3)
)
inst_rx_byteclk_rst
(
	.i_arst	(Reset_N ),
	.i_clk	(mipi_dphy_rx_clk_CLKOUT),
	.o_srst	(mipi_dphy_rx_reset_byte_HS_n)
);

reset
#(
	.IN_RST_ACTIVE	("LOW"),
	.OUT_RST_ACTIVE	("LOW"),
	.CYCLE			(3)
)
inst_tx_byteclk_rst
(
	.i_arst	(Reset_N),
	.i_clk	(mipi_dphy_tx_SLOWCLK),
	.o_srst	(mipi_dphy_tx_reset_byte_HS_n)
);

reset
#(
	.IN_RST_ACTIVE	("LOW"),
	.OUT_RST_ACTIVE	("LOW"),
	.CYCLE			(3)
)
inst_pixel_clk_rst
(
	.i_arst	(i_reset_pixel_n ),
	.i_clk	(pixel_clk),
	.o_srst	(reset_pixel_n)
);

reset
#(
	.IN_RST_ACTIVE	("LOW"),
	.OUT_RST_ACTIVE	("LOW"),
	.CYCLE			(3)
)
inst_esc_clk_rst
(
	.i_arst	(Reset_N),
	.i_clk	(mipi_dphy_tx_inst1_ESC_CLK),
	.o_srst	(reset_esc_n)
);

//数据类型重复位MipiRxDPHYRstN
wire   mipi_dphy_rx_reset_byte_HS_n_reg;
wire	reset_pixel_n_reg;
wire	i_reset_pixel_n_reg;
reg [31:0] 		rst_cnt2;
always @(posedge pixel_clk or negedge MipiRxDPHYRstN )
begin 
 if(~MipiRxDPHYRstN) begin
  rst_cnt2 <= 32'b0 ; 
 end 
 else if(~rst_cnt2[24]) begin 
  rst_cnt2 <= rst_cnt2 + 8'b1 ;
 end 
end 
 
assign	i_reset_pixel_n_reg = (rst_cnt2[24]== 1'b1)?1'b1 : 1'b0;

reset
#(
	.IN_RST_ACTIVE	("LOW"),
	.OUT_RST_ACTIVE	("LOW"),
	.CYCLE			(3)
)
inst1_rx_byteclk_rst
(
	.i_arst	(MipiRxDPHYRstN ),
	.i_clk	(mipi_dphy_rx_clk_CLKOUT),
	.o_srst	(mipi_dphy_rx_reset_byte_HS_n_reg)
);

reset
#(
	.IN_RST_ACTIVE	("LOW"),
	.OUT_RST_ACTIVE	("LOW"),
	.CYCLE			(3)
)
inst1_pixel_clk_rst
(
	.i_arst	(i_reset_pixel_n_reg ),
	.i_clk	(pixel_clk),
	.o_srst	(reset_pixel_n_reg)
);

// Mapping to DPHY TX
wire TxUlpsClk;
wire TxUlpsExitClk;
wire [NUM_DATA_LANE-1:0] TxUlpsEsc;
wire [NUM_DATA_LANE-1:0] TxUlpsExit;
wire [NUM_DATA_LANE-1:0] TxRequestEsc;
wire [NUM_DATA_LANE-1:0] TxSkewCalHS;
wire [NUM_DATA_LANE-1:0] TxRequestHS;
wire TxRequestHSc;
wire [15:0] TxDataHS0;
wire [15:0] TxDataHS1;
wire [15:0] TxDataHS2;
wire [15:0] TxDataHS3;
wire [1:0] TxReqValidHS0, TxReqValidHS1, TxReqValidHS2, TxReqValidHS3;
wire TxUlpsActiveClkNot;
wire [NUM_DATA_LANE-1:0] TxStopStateD;
wire TxStopStateC;
wire [NUM_DATA_LANE-1:0] TxUlpsActiveNot;
wire [NUM_DATA_LANE-1:0] TxReadyHS;


assign mipi_dphy_tx_inst1_ULPS_CLK_ENTER = TxUlpsClk;
assign mipi_dphy_tx_inst1_ULPS_CLK_EXIT = TxUlpsExitClk;
assign TxUlpsActiveClkNot = mipi_dphy_tx_inst1_ULPS_CLK_ACTIVEN;
assign mipi_dphy_tx_inst1_ULPS_LAN0_ENTER = TxUlpsEsc[0];
assign mipi_dphy_tx_inst1_ULPS_LAN1_ENTER = TxUlpsEsc[1];
assign mipi_dphy_tx_inst1_ULPS_LAN2_ENTER = TxUlpsEsc[2];
assign mipi_dphy_tx_inst1_ULPS_LAN3_ENTER = TxUlpsEsc[3];
assign mipi_dphy_tx_inst1_ULPS_LAN0_EXIT = TxUlpsExit[0];
assign mipi_dphy_tx_inst1_ULPS_LAN1_EXIT = TxUlpsExit[1];
assign mipi_dphy_tx_inst1_ULPS_LAN2_EXIT = TxUlpsExit[2];
assign mipi_dphy_tx_inst1_ULPS_LAN3_EXIT = TxUlpsExit[3];
assign mipi_dphy_tx_inst1_REQUESTESC_LAN0 = TxRequestEsc[0];
assign mipi_dphy_tx_inst1_REQUESTESC_LAN1 = TxRequestEsc[1];
assign mipi_dphy_tx_inst1_REQUESTESC_LAN2 = TxRequestEsc[2];
assign mipi_dphy_tx_inst1_REQUESTESC_LAN3 = TxRequestEsc[3];
assign mipi_dphy_tx_inst1_HS_LAN0_SKEWCAL = TxSkewCalHS[0];
assign mipi_dphy_tx_inst1_HS_LAN1_SKEWCAL = TxSkewCalHS[1];
assign mipi_dphy_tx_inst1_HS_LAN2_SKEWCAL = TxSkewCalHS[2];
assign mipi_dphy_tx_inst1_HS_LAN3_SKEWCAL = TxSkewCalHS[3];
assign TxStopStateD[0] = mipi_dphy_tx_inst1_STOPSTATE_LAN0;
assign TxStopStateD[1] = mipi_dphy_tx_inst1_STOPSTATE_LAN1;
assign TxStopStateD[2] = mipi_dphy_tx_inst1_STOPSTATE_LAN2;
assign TxStopStateD[3] = mipi_dphy_tx_inst1_STOPSTATE_LAN3;
assign TxStopStateC = mipi_dphy_tx_inst1_STOPSTATE_CLK;
assign TxUlpsActiveNot[0] = mipi_dphy_tx_inst1_ULPS_LAN0_ACTIVEN;
assign TxUlpsActiveNot[1] = mipi_dphy_tx_inst1_ULPS_LAN1_ACTIVEN;
assign TxUlpsActiveNot[2] = mipi_dphy_tx_inst1_ULPS_LAN2_ACTIVEN;
assign TxUlpsActiveNot[3] = mipi_dphy_tx_inst1_ULPS_LAN3_ACTIVEN;
assign TxReadyHS[0] = mipi_dphy_tx_inst1_HS_LAN0_READY;
assign TxReadyHS[1] = mipi_dphy_tx_inst1_HS_LAN1_READY;
assign TxReadyHS[2] = mipi_dphy_tx_inst1_HS_LAN2_READY;
assign TxReadyHS[3] = mipi_dphy_tx_inst1_HS_LAN3_READY;
assign mipi_dphy_tx_inst1_HS_LAN0_REQUEST = TxRequestHS[0];
assign mipi_dphy_tx_inst1_HS_LAN1_REQUEST = TxRequestHS[1];
assign mipi_dphy_tx_inst1_HS_LAN2_REQUEST = TxRequestHS[2];
assign mipi_dphy_tx_inst1_HS_LAN3_REQUEST = TxRequestHS[3];
assign mipi_dphy_tx_inst1_HS_CLK_REQUEST = TxRequestHSc;
assign mipi_dphy_tx_inst1_HS_LAN0_DATA = TxDataHS0;
assign mipi_dphy_tx_inst1_HS_LAN1_DATA = TxDataHS1;
assign mipi_dphy_tx_inst1_HS_LAN2_DATA = TxDataHS2;
assign mipi_dphy_tx_inst1_HS_LAN3_DATA = TxDataHS3;
assign mipi_dphy_tx_inst1_HS_LAN0_HIGHVALID = TxReqValidHS0[1];
assign mipi_dphy_tx_inst1_HS_LAN1_HIGHVALID = TxReqValidHS1[1];
assign mipi_dphy_tx_inst1_HS_LAN2_HIGHVALID = TxReqValidHS2[1];
assign mipi_dphy_tx_inst1_HS_LAN3_HIGHVALID = TxReqValidHS3[1];
//MIPI_TX ctrl
  wire  TxConfigEn  ; //(O)Pixel Tx Config Enable
  wire  MipiTxHSync ; //(O)MIPI Tx  Horizontal Synchronization   
  wire  MipiTxVSync ; //(O)MIPI Tx  Vertical Synchronization     
  wire  MipiTxValid ; //(O)MIPI Tx  Pixel Data Valid
  wire  PixelTxEn      ; //(I)Pixel Tx Enable
  wire   [ 5:0]  ConfDataType   ; //Configuration Data Type      
  wire   [ 7:0]  CfgTxFrmRate   ; //(I)Configuration Tx Framer Rate
  wire   [15:0]  CfgTxVPixelNum ; //(I)Configuration Tx Vertical Pixel Number  
  wire   [15:0]  CfgTxHPixelNum ; //(I)Configuration Tx Horizontal Pixel Number
  wire   [11:0]  CfgTxVBlkTime  ; //(I)Configuration Tx Vertical Blanking Time (us)
  wire   [ 7:0]  CfgTxHBlkTime  ; //(I)Configuration Tx Horizontal Blanking Time (us)
  wire   [ 2:0]  ConfLanesNum   ; //(I)Configuration Lanes Number
  wire           ConfTxFrmMod   ; //(I)Configuration Framer Mode
  //Calculate parameter 
  wire   [23:0]  CalcVSyncLen   ; //(O)Calculate Vertical Synchronization Length(Pixel  Clock Cycle)
  wire   [15:0]  CalcHSyncLen   ; //(O)Calculate Horizontal Synchronization Length  (Pixel  Clock Cycle)
  wire   [15:0]  CalcDValidLen  ; //(O)Calculate Data Valid Length  (Pixel  Clock Cycle) 
  wire   [19:0]  CalcVBlankLen  ; //(O)Calculate Vertical Blanking  Length  (Pixel  Clock Cycle)	
  wire   [15:0]  CalcHBlankLen  ; //(O)Calculate Horizontal Blanking  Length  (Pixel  Clock Cycle)
  wire   [15:0]  CalcHPixelNum  ; //(O)Calculate Horizontal Pixel Number
  
  wire	[15:0]	CfgTxHPixelMax;
  wire [15:0]HoriMaxPixelNum; 
  wire [15:0]RealHoriPixelNum; 
wire   [35:0]  CalcHoriMaxPixelNum ;
wire  [35:0]  HoriPayloadBitNum  ;
wire  [16:0]  CalcHoriBitNum     ;
wire   [16:0]   CfgTxBitNFactor ;
wire [15:0]   HoriPayloadLen;
wire  [15:0]  HSyncPeriod ;
  MipiTxCtrl  # (.TxPixelClkFreq_C  (TxPixelClkFreq_C))
  U2_MipiTxCtrl
  (   
  	//System Signal
  	.SysClk       (TxSysClk  ),         //System Clock，像素时钟
  	.Reset_N      (reset_pixel_n ),		     //System Reset
  	//Signal
  	.PixelTxEn      (PixelTxEn      ), //(I)Pixel Tx Enable,VIO控制
	.ConfDataType   (ConfDataType   ), //(I)Configuration Data Type，VIO控   
    .CfgTxFrmRate   (CfgTxFrmRate   ), //(I)Configuration Tx Framer Rate，VIO控
    .CfgTxVPixelNum (CfgTxVPixelNum ), //(I)Configuration Tx Vertical Pixel Number，VIO控  
  	.CfgTxHPixelNum (CfgTxHPixelNum ), //(I)Configuration Tx Horizontal Pixel Number
    .CfgTxVBlkTime  (CfgTxVBlkTime  ), //(I)Configuration Tx Vertical Blanking Time (us)
    .CfgTxHBlkTime  (CfgTxHBlkTime  ), //(I)Configuration Tx Horizontal Blanking Time (us)    
	.ConfLanesNum   (ConfLanesNum   ), //(I)Configuration Lanes Number
	.ConfTxFrmMod   (ConfTxFrmMod   ), //(I)Configuration Framer Mode
  	//Calculate Parameter      
  	.CalcVSyncLen   (CalcVSyncLen   ), //(O)Calculate Vertical Synchronization Length(Pixel  Clock Cycle)
  	.CalcHSyncLen   (CalcHSyncLen   ), //(O)Calculate Horizontal Synchronization Length  (Pixel  Clock Cycle)
  	.CalcDValidLen  (CalcDValidLen  ), //(O)Calculate Data Valid Length 	(Pixel  Clock Cycle) 
  	.CalcVBlankLen  (CalcVBlankLen  ), //(O)Calculate Vertical Blanking  Length  (Pixel  Clock Cycle)	
  	.CalcHBlankLen  (CalcHBlankLen  ), //(O)Calculate Horizontal Blanking  Length  (Pixel  Clock Cycle)
	  .CalcHPixelNum  (CalcHPixelNum  ), //(O)Calculate Horizontal Pixel Number
    //Pixel Tx Siganl       
    .TxConfigEn     (TxConfigEn   ), //(O)Pixel Tx Config Enable
    .MipiTxHSync    (MipiTxHSync  ), //(O)MIPI Tx  Horizontal Synchronization   
    .MipiTxVSync    (MipiTxVSync  ), //(O)MIPI Tx  Vertical Synchronization     
    .MipiTxValid    (MipiTxValid  ),  //(O)MIPI Tx  Pixel Data Valid
	.CfgTxHPixelMax	(CfgTxHPixelMax),
	.HoriMaxPixelNum(HoriMaxPixelNum),
	.RealHoriPixelNum(RealHoriPixelNum),
	.CalcHoriMaxPixelNum(CalcHoriMaxPixelNum),
	.HoriPayloadBitNum	(HoriPayloadBitNum	),
	.CalcHoriBitNum    	(CalcHoriBitNum    	),
	.CfgTxBitNFactor (CfgTxBitNFactor),
	.HoriPayloadLen (HoriPayloadLen),
.HSyncPeriod (HSyncPeriod)
  );
  	/////////////////////////////////////////////////////////
	wire          MipiTx_HSYNC = MipiTxHSync ; //(O)[Video]  MIPI Tx Horizontal Synchronization      
	wire          MipiTx_VSYNC = MipiTxVSync ; //(O)[Video]  MIPI Tx Vertical Synchronization        
	wire          MipiTx_VALID = MipiTxValid ; //(O)[Video]  MIPI Tx Valid Fixel Data  
	
	/////////////////////////////////////////////////////////	
	reg   [ 1:0]  ConfLansNumCode;
	
	always @( * )  
	begin
	  case (ConfLanesNum)
	    3'h1    : ConfLansNumCode <= # TCo_C 2'h0;
	    3'h2    : ConfLansNumCode <= # TCo_C 2'h1;
	    3'h3    : ConfLansNumCode <= # TCo_C 2'h2;
	    3'h4    : ConfLansNumCode <= # TCo_C 2'h3;
	    default : ConfLansNumCode <= # TCo_C 2'h0;
	  endcase
  end
/////////////////////////////////////////////////////////
	reg   [ 1:0]  MipiTx_LANES      =  2'h3;    //(O)[Control]MIPI Tx Tx lanes    	
	reg   			  MipiTx_FRAME_MODE =  1'h0;    //(O)[Video]  MIPI Tx Frame Mode
	reg   [15:0]  MipiTx_HRES       = 16'd1920; //(O)[Video]  MIPI Tx Horizontal Resolution
	reg   [ 5:0]  MipiTx_TYPE       =  6'h2a      ; //(O)[Video]  MIPI Tx Video Data Typte	
	
	always @( posedge TxSysClk)  
	begin
	  if (TxConfigEn)
	  begin
	    MipiTx_LANES       <= # TCo_C  ConfLansNumCode;
	    MipiTx_FRAME_MODE  <= # TCo_C  ConfTxFrmMod   ;
	    MipiTx_HRES        <= # TCo_C  CalcHPixelNum  ;
	    MipiTx_TYPE        <= # TCo_C  ConfDataType   ;
    end
  end
 
	/////////////////////////////////////////////////////////
	wire 		CtrlTxDPHYRstN; //MIPI Tx DPHY Reset (Low Active)
	wire 		CtrlTxCSIRstN ; //MIPI Tx CSI-2 Reset (Low Active)  
	
	/////////////////////////////////////////////////////////
	reg     MipiTxAutoRst;  //MIPI-Tx Auto Reset as a Result of Config parameter Changed  
	
	always @( posedge TxSysClk)  
	begin
	  MipiTxAutoRst <= # TCo_C (MipiTx_LANES      != ConfLansNumCode)
	                          |(MipiTx_FRAME_MODE != ConfTxFrmMod   )
							  |(MipiTx_TYPE != ConfDataType);
  end
	
	/////////////////////////////////////////////////////////
	reg [15:0] TxDPHYRstCnt = 16'h0;  //MIPI TX DPHY Reset Counter 
	
	always @( posedge TxSysClk or negedge reset_pixel_n)  
	begin
	  if (!reset_pixel_n)             TxDPHYRstCnt <= # TCo_C 16'h0; 
	  else if (~CtrlTxDPHYRstN) TxDPHYRstCnt <= # TCo_C 16'h0;
	  else if (MipiTxAutoRst)   TxDPHYRstCnt <= # TCo_C 16'h0;
	  else                      TxDPHYRstCnt <= # TCo_C TxDPHYRstCnt + {15'h0,(~TxDPHYRstCnt[15])};
  end
  
  wire  MipiTxDPHYRstN   ;  //MIPI Rx DPHY Reset Operate (Low Active, MIPI-Rx Interface) 
   assign  MipiTxDPHYRstN   = TxDPHYRstCnt[15];
  	/////////////////////////////////////////////////////////	
		reg [15:0] TxCSIRstCnt = 16'h0; //MIPI RX DPHY Reset Counter
	
	always @( posedge TxSysClk or negedge reset_pixel_n)  
	begin
	  if (!reset_pixel_n)             TxCSIRstCnt <= # TCo_C 16'h0;
	  else if (~CtrlTxCSIRstN)  TxCSIRstCnt <= # TCo_C 16'h0;
	  else if (MipiTxAutoRst)   TxCSIRstCnt <= # TCo_C 16'h0;
	  else                      TxCSIRstCnt <= # TCo_C TxCSIRstCnt + {15'h0,(~TxCSIRstCnt[15])};
  end
	
	
//wire	MipiTxCSIRstN       = TxCSIRstCnt[15]; //(O)MIPI Rx CSI-2 Reset (Low Active, MIPI-Rx Interface) 
	
  
	/////////////////////////////////////////////////////////		
	
	
	reg   TxVSyncNeg      = 1'h0;
	// reg   MipiTxDPHYRstN  = 1'h0;
	reg   MipiTxCSIRstN   = 1'h0;
	
	// always @( posedge TxSysClk)  if (TxVSyncNeg)  MipiTxDPHYRstN  <= # TCo_C TxDPHYRstCnt[15];
	always @( posedge TxSysClk)  if (TxVSyncNeg)  MipiTxCSIRstN   <= # TCo_C TxCSIRstCnt[15] & MipiTxDPHYRstN;
	
	/////////////////////////////////////////////////////////	
	wire 		MipiTx_DPHY_RSTN = MipiTxDPHYRstN; //(O)[Control]MIPI Tx DPHY Reset (Low Active)
	wire 		MipiTx_RSTN      = MipiTxCSIRstN ; //(O)[Control]MIPI Tx CSI-2 Reset (Low Active)
  
//	Generate Mipi Tx Data
//	Input：
//	output：
//***************************************************/ 

	/////////////////////////////////////////////////////////
  reg   PixelTxHSync = 1'h0; //(O)Pixel Tx Horizontal Synchronization
  reg   PixelTxVSync = 1'h0; //(O)Pixel Tx Vertical Synchronization
  reg   PixelTxValid = 1'h0; //(O)Pixel Tx Pixel Data Valid 
	
	always @( posedge TxSysClk)  PixelTxHSync <= # TCo_C  MipiTxHSync;
	always @( posedge TxSysClk)  PixelTxVSync <= # TCo_C  MipiTxVSync;
	always @( posedge TxSysClk)  PixelTxValid <= # TCo_C  MipiTxValid; 	                                     
	                                     
	/////////////////////////////////////////////////////////
	reg   TxVSyncPos = 1'h0;
	
	always @( posedge TxSysClk) TxVSyncNeg <= # TCo_C (~MipiTxVSync ) & PixelTxVSync;
	always @( posedge TxSysClk) TxVSyncPos <= # TCo_C (~PixelTxVSync) & MipiTxVSync ;
	
	/////////////////////////////////////////////////////////
	reg [1:0]   MipiTxVCCnt = 2'h0;
	
	always @( posedge TxSysClk)  if (TxVSyncPos)  MipiTxVCCnt <= # TCo_C MipiTxVCCnt + 2'h1;
	
	/////////////////////////////////////////////////////////
	wire [3:0]    MipiTxVCEn;
	
	reg [1:0] MipiTx_VC = 2'h0;
	
	always @( posedge TxSysClk)  
	begin
	  if (MipiTxVCEn)
	  begin
	    case (MipiTxVCCnt)  
	      2'h0: if(MipiTxVCEn[0])  MipiTx_VC <= # TCo_C 2'h0;
	      2'h1: if(MipiTxVCEn[1])  MipiTx_VC <= # TCo_C 2'h1;
	      2'h2: if(MipiTxVCEn[2])  MipiTx_VC <= # TCo_C 2'h2;
	      2'h3: if(MipiTxVCEn[3])  MipiTx_VC <= # TCo_C 2'h3;
	    endcase
    end
    else MipiTx_VC <= # TCo_C 2'h0;
  end  
  wire      [63:0]     MipiTx_DATA;
    //Input
  wire         MipiTx_clk                           = mipi_clk    ;
  wire  [23:0] MipiTx_ParamTxVertSyncLength_Cycle   = CalcVSyncLen      ; //(O)Calculate Vertical Synchronization Length(Pixel  Clock Cycle)                
  wire  [15:0] MipiTx_ParamTxHoriSyncLength_Cycle   = CalcHSyncLen      ; //(O)Calculate Horizontal Synchronization Length  (Pixel  Clock Cycle)            
  wire  [15:0] MipiTx_paramTxDataValidLength_Cycle  = CalcDValidLen     ; //(O)Calculate Data Valid Length  (Pixel  Clock Cycle)                            
  wire  [19:0] MipiTx_paramTxVertBlankLength_Cycle  = CalcVBlankLen     ; //(O)Calculate Vertical Blanking  Length  (Pixel  Clock Cycle)	   
  wire  [15:0] MipiTx_paramTxHoriBlankLength_Cycle  = CalcHBlankLen     ; //(O)Calculate Horizontal Blanking  Length  (Pixel  Clock Cycle)  
  wire  [15:0] MipiTx_RealTxHoriPixelNumber         = CalcHPixelNum     ; //(O)Calculate Horizontal Pixel Number
  wire  [32:0] MipiTx_TxDataRate_bps                = {TxDataRate,6'h0} ;
  
  //Output 
  wire  [ 7:0] MipiTx_ConfigTxFrameRate       ;     
  wire  [15:0] MipiTx_ConfigTxVertPixelNumber ;     
  wire  [15:0] MipiTx_ConfigTxHoriPixelNumber ;     
  wire  [11:0] MipiTx_ConfigTxVBlankTime_us   ;     
  wire  [ 7:0] MipiTx_ConfigTxHBlankTime_us   ;     
  wire  [ 2:0] MipiTx_configTxLanesNumber     ;     
  wire  [ 5:0] MipiTx_ConfigPixelDataType     ;    
  wire  [ 0:0] MipiTx_ConfigTxFramerMode      ; 
  
  wire  [ 0:0] MipiTx_ControlTxDPHYReset      ;     
  wire  [ 0:0] MipiTx_ControlTxCSIReset       ;     
  wire  [ 0:0] MipiTx_ControlTxDisable        ;     
  wire  [ 3:0] MipiTx_ConfigTxVCEnable        ; 
 	MipiTxData8B  U2_MipiTxData
  (   
  	//System Signal
  	.SysClk       (TxSysClk   ),  //System Clock
  	.Reset_N      (reset_pixel_n    ),  //System Reset
  	//Tx Data Signal
  	.MipiTxDValid (MipiTxValid ), //MIPI Tx Data Valid
  	.MipiTxData   (MipiTx_DATA  )  //MIPI Tx Data
  ); 


//
reg		[5:0]	r_tx_axi_araddr_1P;
reg				r_tx_axi_arvalid_1P;
wire			w_tx_axi_arready;
wire	[31:0]	w_tx_axi_rdata;
wire			w_tx_axi_rvalid;
reg				r_tx_axi_rready_1P;
hard_csi_tx inst_csi2_tx_top
(
    .reset_byte_HS_n    (mipi_dphy_tx_reset_byte_HS_n ),
    .clk_byte_HS        (mipi_dphy_tx_SLOWCLK),
    .reset_pixel_n      (reset_pixel_n ),
    .clk_pixel          (pixel_clk),
    .reset_esc_n        (reset_esc_n ),
    .clk_esc            (mipi_dphy_tx_inst1_ESC_CLK),

    //PPI Interface
    .TxUlpsClk			(TxUlpsClk),
    .TxUlpsExitClk      (TxUlpsExitClk),
    .TxUlpsActiveClkNot (TxUlpsActiveClkNot),
    .TxUlpsEsc          (TxUlpsEsc),
    .TxUlpsExit         (TxUlpsExit),
    .TxRequestEsc       (TxRequestEsc),
    .TxSkewCalHS 		(TxSkewCalHS),
    .TxStopStateD  		(TxStopStateD),
    .TxStopStateC		(TxStopStateC),
    .TxUlpsActiveNot	(TxUlpsActiveNot),
    .TxReadyHS			(TxReadyHS),
    .TxRequestHS		(TxRequestHS),
    .TxRequestHSc		(TxRequestHSc),
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

    //AXI4-Lite Interface
    .axi_clk		    (mipi_clk), 
    .axi_reset_n	    (reset_pixel_n),
    .axi_awaddr		    (6'b0),//Write Address. byte address.
    .axi_awvalid	    (1'b1),//Write address valid.
    .axi_awready	    (),//Write address ready.
    .axi_wdata		    (32'b0),//Write data bus.
    .axi_wvalid		    (1'b0),//Write valid.
    .axi_wready		    (),//Write ready.
    .axi_bvalid		    (),//Write response valid.
    .axi_bready		    (1'b0),//Response ready.      
    .axi_araddr		    (r_tx_axi_araddr_1P),//Read address. byte address.
    .axi_arvalid	    (r_tx_axi_arvalid_1P),//Read address valid.
    .axi_arready	    (w_tx_axi_arready),//Read address ready.
    .axi_rdata		    (w_tx_axi_rdata),//Read data.
    .axi_rvalid		    (w_tx_axi_rvalid),//Read valid.
    .axi_rready		    (1'b1),//Read ready.
	
    .hsync_vc0			(PixelTxHSync),
    .hsync_vc1			(1'b0),
    .hsync_vc2			(1'b0),
    .hsync_vc3			(1'b0),
    .hsync_vc4			(1'b0),
    .hsync_vc5			(1'b0),
    .hsync_vc6			(1'b0),
    .hsync_vc7			(1'b0),
    .hsync_vc8			(1'b0),
    .hsync_vc9			(1'b0),
    .hsync_vc10			(1'b0),
    .hsync_vc11			(1'b0),
    .hsync_vc12			(1'b0),
    .hsync_vc13			(1'b0),
    .hsync_vc14			(1'b0),
    .hsync_vc15			(1'b0),
    .vsync_vc0			(PixelTxVSync),
    .vsync_vc1			(1'b0),
    .vsync_vc2			(1'b0),
    .vsync_vc3			(1'b0),
    .vsync_vc4			(1'b0),
    .vsync_vc5			(1'b0),
    .vsync_vc6			(1'b0),
    .vsync_vc7			(1'b0),
    .vsync_vc8			(1'b0),
    .vsync_vc9			(1'b0),
    .vsync_vc10			(1'b0),
    .vsync_vc11			(1'b0),
    .vsync_vc12			(1'b0),
    .vsync_vc13			(1'b0),
    .vsync_vc14			(1'b0),
    .vsync_vc15			(1'b0),
    .datatype			(ConfDataType),   // data type of the Long Packet
    .pixel_data			(MipiTx_DATA),
    .pixel_data_valid   (MipiTxValid),
    .haddr              (CalcHPixelNum),  //for RAW8 word_count = HACT_CNT
    .line_num			(CfgTxVPixelNum),
    .frame_num			(CfgTxFrmRate),	
    .irq                ()
);


////////////////////////MIPI RX//////////////////////

wire 		r_pass, r_fail;
wire 		[12:0] flash_cnt;
wire 		[2:0] error_bit;



// Mapping to DPHY RX IF
wire RxUlpsClkNot;
wire [NUM_DATA_LANE-1:0]	RxErrEsc;
wire [NUM_DATA_LANE-1:0] 	RxErrControl;
wire [NUM_DATA_LANE-1:0] 	RxErrSotSyncHS;
wire [NUM_DATA_LANE-1:0]	RxClkEsc;
wire [NUM_DATA_LANE-1:0]	RxUlpsEsc;
wire [NUM_DATA_LANE-1:0]	RxUlpsActiveNot;
wire [NUM_DATA_LANE-1:0]	RxSkewCalHS;
wire [NUM_DATA_LANE-1:0]	RxStopState;
wire [NUM_DATA_LANE-1:0] 	RxValidHS;
wire [NUM_DATA_LANE-1:0]  	RxSyncHS;
wire [NUM_DATA_LANE-1:0][15:0]	RxDataHS;

assign RxUlpsClkNot = mipi_dphy_rx_inst2_ULPS_CLK_ENTER;
assign RxUlpsActiveClkNot = mipi_dphy_rx_inst2_ULPS_CLK_ACTIVEN;
assign RxErrEsc[0] = mipi_dphy_rx_inst2_ESC_LAN0_ERROR;
assign RxErrEsc[1] = mipi_dphy_rx_inst2_ESC_LAN1_ERROR;
assign RxErrEsc[2] = mipi_dphy_rx_inst2_ESC_LAN2_ERROR;
assign RxErrEsc[3] = mipi_dphy_rx_inst2_ESC_LAN3_ERROR;
assign RxErrControl[0] = mipi_dphy_rx_inst2_LINESTATE_LAN0_ERROR;
assign RxErrControl[1] = mipi_dphy_rx_inst2_LINESTATE_LAN1_ERROR;
assign RxErrControl[2] = mipi_dphy_rx_inst2_LINESTATE_LAN2_ERROR;
assign RxErrControl[3] = mipi_dphy_rx_inst2_LINESTATE_LAN3_ERROR;
assign RxErrSotSyncHS[0] = mipi_dphy_rx_inst2_HS_LAN0_SOTSYNC_ERROR;
assign RxErrSotSyncHS[1] = mipi_dphy_rx_inst2_HS_LAN1_SOTSYNC_ERROR;
assign RxErrSotSyncHS[2] = mipi_dphy_rx_inst2_HS_LAN2_SOTSYNC_ERROR;
assign RxErrSotSyncHS[3] = mipi_dphy_rx_inst2_HS_LAN3_SOTSYNC_ERROR;
assign RxUlpsEsc[0] = mipi_dphy_rx_inst2_ULPS_LAN0_ENTER;
assign RxUlpsEsc[1] = mipi_dphy_rx_inst2_ULPS_LAN1_ENTER;
assign RxUlpsEsc[2] = mipi_dphy_rx_inst2_ULPS_LAN2_ENTER;
assign RxUlpsEsc[3] = mipi_dphy_rx_inst2_ULPS_LAN3_ENTER;
assign RxClkEsc[0] = mipi_dphy_rx_inst2_ESC_LAN0_CLK;
assign RxClkEsc[1] = mipi_dphy_rx_inst2_ESC_LAN1_CLK;
assign RxClkEsc[2] = mipi_dphy_rx_inst2_ESC_LAN2_CLK;
assign RxClkEsc[3] = mipi_dphy_rx_inst2_ESC_LAN3_CLK;
assign RxUlpsActiveNot[0] = mipi_dphy_rx_inst2_ULPS_LAN0_ACTIVEN;
assign RxUlpsActiveNot[1] = mipi_dphy_rx_inst2_ULPS_LAN1_ACTIVEN;
assign RxUlpsActiveNot[2] = mipi_dphy_rx_inst2_ULPS_LAN2_ACTIVEN;
assign RxUlpsActiveNot[3] = mipi_dphy_rx_inst2_ULPS_LAN3_ACTIVEN;
assign RxSkewCalHS[0] = mipi_dphy_rx_inst2_HS_LAN0_SKEWCAL;
assign RxSkewCalHS[1] = mipi_dphy_rx_inst2_HS_LAN1_SKEWCAL;
assign RxSkewCalHS[2] = mipi_dphy_rx_inst2_HS_LAN2_SKEWCAL;
assign RxSkewCalHS[3] = mipi_dphy_rx_inst2_HS_LAN3_SKEWCAL;
assign RxStopState[0] = mipi_dphy_rx_inst2_STOPSTATE_LAN0;
assign RxStopState[1] = mipi_dphy_rx_inst2_STOPSTATE_LAN1;
assign RxStopState[2] = mipi_dphy_rx_inst2_STOPSTATE_LAN2;
assign RxStopState[3] = mipi_dphy_rx_inst2_STOPSTATE_LAN3;
assign RxValidHS[0] = mipi_dphy_rx_inst2_HS_LAN0_VALID;
assign RxValidHS[1] = mipi_dphy_rx_inst2_HS_LAN1_VALID;
assign RxValidHS[2] = mipi_dphy_rx_inst2_HS_LAN2_VALID;
assign RxValidHS[3] = mipi_dphy_rx_inst2_HS_LAN3_VALID;
assign RxSyncHS[0] = mipi_dphy_rx_inst2_HS_LAN0_SYNC;
assign RxSyncHS[1] = mipi_dphy_rx_inst2_HS_LAN1_SYNC;
assign RxSyncHS[2] = mipi_dphy_rx_inst2_HS_LAN2_SYNC;
assign RxSyncHS[3] = mipi_dphy_rx_inst2_HS_LAN3_SYNC;
assign RxDataHS[0] = mipi_dphy_rx_inst2_HS_LAN0_DATA;
assign RxDataHS[1] = mipi_dphy_rx_inst2_HS_LAN1_DATA;
assign RxDataHS[2] = mipi_dphy_rx_inst2_HS_LAN2_DATA;
assign RxDataHS[3] = mipi_dphy_rx_inst2_HS_LAN3_DATA;

//MIPI_RX
  wire  [1:0]          MipiRx_VC;//rx 虚拟通道
  wire  PixelRxVSync  = MipiRx_VSYNC[MipiRx_VC];    //(O)Pixel Rx Vertical Synchronization
  wire  PixelRxHSync  = MipiRx_HSYNC[MipiRx_VC];    //(O)Pixel Rx Horizontal Synchronization
  wire  PixelRxValid  = MipiRx_VALID;     //(O)Pixel Rx Pixel Data Valid 

	// MIPI Rx Measure Value and State
  wire          PixelRxReset                ; //(I)Pixel Rx DPHY/CSI Reset
  wire  [ 15:0]  MipiRxPixNum = MipiRx_CNT  ; //(I)MIPI Rx Pixel Number 
  wire  [ 1:0]  MipiRxVirtCnl = MipiRx_VC   ; //(I)MIPI Rx Virtual Channel
  wire  [17:0]  MipiRxStaInd ={3'b0,Rx_intp_ennable_reg};// = MipiRx_ERROR; //(I)MIPI Rx State Indicate   
  wire  [ 5:0]  MipiRxDType   = datatype ; //(I)MIPI Rx Data Type
  //MIPI error暂时没有这个信号，需从lite读取0X00信号再放进来
	
	
	//
	wire  [ 7:0]  VidioFrmNum     ; //(O)Vidio Framer Number  
	wire  [15:0]  VidioHPixelNum  ; //(O)Vidio Horizontal Pixel Number
	wire  [15:0]  VidioVPixelNum  ; //(O)Vidio Vertical Pixel Number    
	wire  [15:0]  VidioVBlankTime ; //(O)Vidio Vertical Blanking Time (us)      
	wire  [15:0]  VidioHBlankTime ; //(O)Vidio Horizontal Blanking Time (us)       
	wire  [ 5:0]  VidioDataType   ; //(O)Vidio Data Type     
	wire          VidioRestChg    ; //(O)MIPI Rx Vidio Resolution Change	
	wire          MipiRxStaChg    ; //(O)MIPI Rx State Change  
	wire          MipiRxSyncErr   ; //(O)MIPI Rx VSync&HSync Error
	wire  [3:0]   MipiRxStaVCAct  ; //(O)MIPI Rx VC Active Indicate
    wire          MipiRxLanesAct  ; //(O)MIPI Rx Lanes Active Indicate
		
	MipiRxMoni  # (.RxPixelClkFreq_C  (RxPixelClkFreq_C))
	U3_MipiRxMonitor
  (   
  	//System Signal
  	.SysClk           (RxSysClk       ),  //System Clock
  	.Reset_N          (reset_pixel_n      ),	//System Reset
  	// MIPI Rx Signal                 
    .PixelRxReset     (PixelRxReset   ),  //(I)Pixel Rx DPHY/CSI Reset
    .PixelRxHSync     (PixelRxHSync   ),  //(I)Pixel Rx Horizontal Synchronization
    .PixelRxVSync     (PixelRxVSync   ),  //(I)Pixel Rx Vertical Synchronization
    .PixelRxValid     (PixelRxValid   ),  //(I)Pixel Rx Pixel Data Valid   
    .MipiRxVirtCnl    (MipiRxVirtCnl  ),  //(I)MIPI Rx Virtual Channel
    .MipiRxPixNum     (MipiRxPixNum   ),  //(I)MIPI Rx Pixel Number 
    .MipiRxStaInd     (MipiRxStaInd   ),  //(I)MIPI Rx State Indicate    
    .MipiRxDType      (MipiRxDType    ),  //(I)MIPI Rx Data Type
  	// MIPI Rx Measure Value and State    
  	.VidioFrmNum      (VidioFrmNum    ),  //(O)Vidio Framer Number  
  	.VidioHPixelNum   (VidioHPixelNum ),  //(O)Vidio Horizontal Pixel Number
  	.VidioVPixelNum   (VidioVPixelNum ),  //(O)Vidio Vertical Pixel Number    
  	.VidioVBlankTime  (VidioVBlankTime),  //(O)Vidio Vertical Blanking Time (us)      
  	.VidioHBlankTime  (VidioHBlankTime),  //(O)Vidio Horizontal Blanking Time (us)       
	  .VidioDataType    (VidioDataType  ),  //(O)Vidio Data Type    
  	.VidioRestChg     (VidioRestChg   ),  //(O)MIPI Rx Vidio Resolution Change	
  	.MipiRxStaChg     (MipiRxStaChg   ),  //(O)MIPI Rx State Change      
	  .MipiRxSyncErr    (MipiRxSyncErr  ),  //(O)MIPI Rx VSync&HSync Error  
  	.MipiRxStaVCAct   (MipiRxStaVCAct ),  //(O)MIPI Rx VC Active Indicate
    .MipiRxLanesAct   (MipiRxLanesAct )   //(O)MIPI Rx Lanes Active Indicate
  );


	wire  [ 7:0]  MiPiRxRight ; //MIPI Rx Right
	wire  [ 7:0]  MipiRxError ; //MIPI Rx Error
	wire  [ 5:0]  datatype    ;
	wire  [ 1:0]  MIPIRx_VC   ;
	wire  [15:0]  MipiRx_CNT  ;
	wire  [63:0]  MipiRx_DATA ;
	wire  [7:0]   MipiRxData  ;
    assign  MipiRxData[7]   = MipiRx_DATA[63];
    assign  MipiRxData[6]   = MipiRx_DATA[55];
    assign  MipiRxData[5]   = MipiRx_DATA[47];
    assign  MipiRxData[4]   = MipiRx_DATA[39];
    assign  MipiRxData[3]   = MipiRx_DATA[31];
    assign  MipiRxData[2]   = MipiRx_DATA[23];
    assign  MipiRxData[1]   = MipiRx_DATA[15];
    assign  MipiRxData[0]   = MipiRx_DATA[ 7];
  MipiRxData8B  # (.RightCntWidth_C (RightCntWidth_C))
  U4_MipiRxData
  (   
  	//System Signal
  	.SysClk       (RxSysClk  ), //System Clock
  	.Reset_N      (reset_pixel_n   ),	//System Reset
  	//Rx Data Signal
  	.MipiRxDValid (MipiRx_VALID ), //MIPI Rx Data Valid
  	.MipiRxData   (MipiRx_DATA  ), //MIPI Rx DataOut
  	.MipiRxError  (MipiRxError  ), //MIPI Rx Error
  	.MiPiRxRight  (MiPiRxRight  )  //MIPI Rx Right
  );
  
    reg  [15:0]  RxErrCnt = 16'h0;
  
  always @ (posedge RxSysClk) 
  begin
    if (~(MipiRxDPHYRstN & MipiRxDPHYRstN))   RxErrCnt <= # TCo_C   16'h0;
    else if ((~&MiPiRxRight[4:0]) & (~|RxErrCnt))  RxErrCnt <= # TCo_C   16'h0;
    else if (|MipiRxError[4:0])                    RxErrCnt <= # TCo_C   RxErrCnt + {15'h0, (~&RxErrCnt)};
  end
  
	/////////////////////////////////////////////////////////
  reg   [27:0]  SecondCnt   ;
  reg           SecondEn    ;
  reg   [31:0]  TestTimeCnt ;
  
  always @ (posedge RxSysClk) 
  begin
    if (~(MipiRxDPHYRstN & MipiRxDPHYRstN))   SecondCnt <= # TCo_C `MipiTxPixelClkFreq - 1;
    else if (|SecondCnt)                      SecondCnt <= # TCo_C SecondCnt - 28'h1;
    else                                      SecondCnt <= # TCo_C `MipiTxPixelClkFreq - 1;
  end
    
  always @ (posedge RxSysClk)     SecondEn <= # TCo_C  ( ~|SecondCnt );
  
  always @ (posedge RxSysClk) 
  begin
    if (~(MipiRxDPHYRstN & MipiRxDPHYRstN))   TestTimeCnt <= # TCo_C 32'h0;
    else if (SecondEn)                        TestTimeCnt <= # TCo_C TestTimeCnt + 32'h1;
  end    
    
	/////////////////////////////////////////////////////////
	reg   [27:0]  TxDataCnt   ;
	reg   [26:0]  TxDataRate  ;
	
  always @ (posedge RxSysClk) 
  begin
    if (SecondEn)             TxDataCnt <= # TCo_C {25'h0,PixelTxValid};
    else if (PixelTxValid)    TxDataCnt <= # TCo_C TxDataCnt + 26'h1;
  end
  
  always @ (posedge RxSysClk) if (SecondEn)   TxDataRate <= # TCo_C TxDataCnt;
  	/////////////////////////////////////////////////////////
	//Config & Control Signal
    wire		  CtrlRxDPHYRstN ; //(I)Control MIPI Rx DPHY Reset (Low Active)
	wire		  CtrlRxCSIRstN  ; //(I)Control MIPI Rx CSI-2 Reset (Low Active)
	wire		  CtrlRxErrClr   ; //(I)Control MIPI Rx Error Clear
	wire  [ 3:0]  ConfRxVCEn     ; //(I)Config  MIPI Rx Virtual Channel Enable
	wire  [ 2:0]  ConfRxLanNum   ; //(I)Config  MIPI Rx Lanes  
	//Output To MIPI                                 
    wire	        MipiRxDPHYRstN ; //(O)MIPI Rx DPHY Reset (Low Active, To MIPI-Rx Interface)
	wire	        MipiRxCSIRstN  ; //(O)MIPI Rx CSI-2 Reset  (Low Active, To MIPI-Rx Interface)
	wire	        MipiRxErrClr   ; //(O)MIPI Rx Error Clear  (To MIPI-Rx Interface)
	
	wire   [ 3:0]    MipiRx_VSYNC   ;
	wire   [ 3:0] 	 MipiRx_HSYNC   ;
	wire   [ 15:0]   word_count     ;
	wire   [15:0]    pixel_per_clk  ;
	
	MipiRxCtrl  U3_MipiRxControl
  (   
  	//System Signal
  	.SysClk         (RxSysClk ),  //System Clock
  	.Reset_N        (reset_pixel_n  ),	//System Reset
  	//Config & Control Signal
  	.CtrlRxDPHYRstN  (CtrlRxDPHYRstN), //(I)Control MIPI Rx DPHY Reset，VIO控                   
  	.CtrlRxCSIRstN   (CtrlRxCSIRstN ), //(I)Control MIPI Rx CSI-2 Reset，VIO控                  
  	.CtrlRxErrClr    (CtrlRxErrClr  ), //(I)Control MIPI Rx Error Clear，VIO控                 
  	.ConfRxVCEn      (ConfRxVCEn    ), //(I)Config  MIPI Rx Virtual Channel Enable，VIO控       
  	.ConfRxLanNum    (ConfRxLanNum  ), //(I)Config  MIPI Rx Lanes，VIO控 
	.MipiRxDType	(ConfDataType),	//ConfDataType
    .MipiRxLanesAct  (MipiRxLanesAct), //(I)MIPI Rx Lanes Active Indicate
  	.MipiRxSyncErr   (MipiRxSyncErr ), //(I)MIPI Rx VSync&HSync Error   
  	.PixelRxReset    (PixelRxReset  ), //(O)MIPI Rx Reset Signal                
  	//Output To MIPI                                                 
  	.MipiRxDPHYRstN  (MipiRxDPHYRstN), //(O)[Control]MIPI Rx DPHY Reset                  
  	.MipiRxCSIRstN   (MipiRxCSIRstN ), //(O)[Control]MIPI Rx CSI-2 Reset                 
  	.MipiRxErrClr    (MipiRxErrClr  )  //(O)[Status] MIPI Rx Error Clear               
  );
	/////////////////////////////////////////////////////////	
	wire [ 3:0]  MipiRxVCEn       = ConfRxVCEn  ; //MIPI Rx Virtual Channel Enable (To MIPI-Rx Interface) 
	
	reg  [ 1:0]  MipiRxLanNum     = 2'h0; //MIPI Rx Lanes (To MIPI-Rx Interface) 
	
	always @( posedge RxSysClk)  
	begin
	  case (ConfRxLanNum)
	    3'h1    : MipiRxLanNum <= # TCo_C 2'h0;
	    3'h2    : MipiRxLanNum <= # TCo_C 2'h1;
	    3'h3    : MipiRxLanNum <= # TCo_C 2'h2;
	    3'h4    : MipiRxLanNum <= # TCo_C 2'h3;
	    default : MipiRxLanNum <= # TCo_C 2'h0;
	  endcase
  end
  
	/////////////////////////////////////////////////////////
  wire			   MipiRx_DPHY_RSTN = MipiRxDPHYRstN; //(O)[Control]MIPI Rx DPHY Reset
	wire			   MipiRx_RSTN      = MipiRxCSIRstN ; //(O)[Control]MIPI Rx CSI-2 Reset
	wire		     MipiRx_CLEAR     = MipiRxErrClr  ; //(I)[Status] MIPI Rx Error Clear
	wire [ 3:0]  MipiRx_VC_ENA    = MipiRxVCEn    ; //(O)[Control]MIPI Rx Virtual Channel Enable
	wire [ 1:0]  MipiRx_LANES     = MipiRxLanNum  ; //(O)[Control]MIPI Rx Lanes

hard_csi_rx  inst_csi2_rx_top
(
    .reset_n              	(Reset_N ),
    .clk                    (mipi_clk),
    .reset_byte_HS_n        (mipi_dphy_rx_reset_byte_HS_n ),
    .clk_byte_HS            (mipi_dphy_rx_clk_CLKOUT),
    .reset_pixel_n        	(reset_pixel_n ),
    .clk_pixel              (pixel_clk),

    // PPI Interface
    .RxClkEsc               (RxClkEsc),
    .RxUlpsClkNot			(RxUlpsClkNot),
    .RxUlpsActiveClkNot     (RxUlpsActiveClkNot),
    .RxErrEsc				(RxErrEsc),
    .RxErrControl			(RxErrControl),
    .RxErrSotSyncHS			(RxErrSotSyncHS),
    .RxUlpsEsc				(RxUlpsEsc),
    .RxUlpsActiveNot        (RxUlpsActiveNot),
    .RxSkewCalHS			(RxSkewCalHS),
    .RxStopState			(RxStopState),
    .RxSyncHS				(RxSyncHS),
    .RxDataHS0				(RxDataHS[0]),
    .RxDataHS1              (RxDataHS[1]),
    .RxDataHS2              (RxDataHS[2]),
    .RxDataHS3              (RxDataHS[3]),
    .RxDataHS4              (),
    .RxDataHS5              (),
    .RxDataHS6              (),
    .RxDataHS7              (),
    .RxValidHS0             ({RxValidHS[0], RxValidHS[0]}),
    .RxValidHS1             ({RxValidHS[1], RxValidHS[1]}),
    .RxValidHS2             ({RxValidHS[2], RxValidHS[2]}),
    .RxValidHS3             ({RxValidHS[3], RxValidHS[3]}),
    .RxValidHS4             (),
    .RxValidHS5             (),
    .RxValidHS6             (),
    .RxValidHS7             (),
    //AXI4-Lite Interface
    .axi_clk            		(mipi_clk),
    .axi_reset_n        		(Reset_N),
    .axi_awaddr         		(4'b0),//Write Address. byte address.
    .axi_awvalid        		(1'b0),//Write address valid.
    .axi_awready       			(),//Write address ready.
    .axi_wdata          		(32'b0),//Write data bus.
    .axi_wvalid         		(1'b0),//Write valid.
    .axi_wready         		(),//Write ready.           
    .axi_bvalid         		(),//Write response valid.
    .axi_bready         		(1'b0),//Response ready.      
    .axi_araddr         		(r_rx_axi_araddr_1P),//Read address. byte address.
    .axi_arvalid        		(r_rx_axi_arvalid_1P),//Read address valid.
    .axi_arready        		(w_rx_axi_arready),//Read address ready.
    .axi_rdata          		(w_rx_axi_rdata),//Read data.
    .axi_rvalid         		(w_rx_axi_rvalid),//Read valid.
    .axi_rready         		(1'b1),//Read ready.

    .hsync_vc0                  	(MipiRx_HSYNC[0]),
    .hsync_vc1                  	(MipiRx_HSYNC[1]),
    .hsync_vc2                  	(MipiRx_HSYNC[2]),
    .hsync_vc3                  	(MipiRx_HSYNC[3]),
    .hsync_vc4                  	(),
    .hsync_vc5                  	(),
    .hsync_vc6                  	(),
    .hsync_vc7                  	(),
    .hsync_vc8                  	(),
    .hsync_vc9                  	(),
    .hsync_vc10                  	(),
    .hsync_vc11                  	(),
    .hsync_vc12                  	(),
    .hsync_vc13                  	(),
    .hsync_vc14                  	(),
    .hsync_vc15                  	(),
    .vsync_vc0                  	(MipiRx_VSYNC[0]),
    .vsync_vc1                  	(MipiRx_VSYNC[1]),
    .vsync_vc2                 	 	(MipiRx_VSYNC[2]),
    .vsync_vc3                  	(MipiRx_VSYNC[3]),
    .vsync_vc4                  	(),
    .vsync_vc5                  	(),
    .vsync_vc6                  	(),
    .vsync_vc7                  	(),
    .vsync_vc8                  	(),
    .vsync_vc9                  	(),
    .vsync_vc10                  	(),
    .vsync_vc11                  	(),
    .vsync_vc12                  	(),
    .vsync_vc13                  	(),
    .vsync_vc14                  	(),
    .vsync_vc15                  	(),

    .vc                                 (MipiRx_VC),
    .vcx                                (),
    .word_count                     	(word_count),
    .shortpkt_data_field				(),
    .datatype                       	(datatype),        // RAW8
    .pixel_per_clk              	(MipiRx_CNT),
    .pixel_data                     	(MipiRx_DATA),
    .pixel_data_valid   		(MipiRx_VALID),
    .irq                                ()

);






assign led[0] = count_led[21];
assign led[1] = r_fail;
assign led[2] = r_pass;
assign led[3] = flash_cnt[12];

////////////////////////////////

//axi-lite接口
reg		[5:0]	r_rx_axi_araddr_1P;
reg				r_rx_axi_arvalid_1P;
wire			w_rx_axi_arready;
wire	[31:0]	w_rx_axi_rdata;
wire			w_rx_axi_rvalid;
reg				r_rx_axi_rready_1P;

localparam	s_idle			= 2'b00;
localparam	s_wait_arready	= 2'b01;
localparam	s_wait_rvalid	= 2'b10;

reg		[1:0]	r_tx_dbg_fsm_1P;
reg		[8:0]	r_tx_dbg_reg_1P	[0:7];
reg		[1:0]	r_rx_dbg_fsm_1P;
reg		[14:0]	r_rx_dbg_reg_1P	[0:15];
//Tx控制状态寄存器
reg     [3:0]   Tx_intp_status_reg; //0x00
reg		[4:0]  	Tx_intp_ennable_reg;//0x04
reg		[7:0]	Tx_lane_stop_status;//0x08
reg		[8:0]	Tx_ULPS_status;//0x0c
//Rx控制
reg     [14:0]  Rx_intp_status_reg; //0x00
reg		[14:0]  Rx_intp_ennable_reg;//0x04
reg		[7:0]	Rx_lane0_status;    //0x08
reg		[7:0]	Rx_lane1_status;	//0x0c
reg		[7:0]	Rx_lane2_status;    //0x10
reg		[7:0]	Rx_lane3_status;    //0x14
reg		[7:0]	Rx_lane4_status;    //0x18
reg		[7:0]	Rx_lane5_status;    //0x1c
reg		[7:0]	Rx_lane6_status;    //0x20
reg		[7:0]	Rx_lane7_status;    //0x20
reg		[1:0]	Rx_CLK_LANE_ULPS_status;//0x28
//tx
always @(negedge reset_pixel_n or posedge mipi_clk)
begin
if(!reset_pixel_n)
begin
Tx_intp_status_reg      <= 'h0;
Tx_intp_ennable_reg     <= 'h0;
Tx_lane_stop_status     <= 'h0;
Tx_ULPS_status          <= 'h0;
end
else
begin
if((r_tx_dbg_fsm_1P == s_wait_rvalid)&&(w_tx_axi_rvalid == 1'b1))
begin
	case(r_tx_axi_araddr_1P)
	6'h00:  Tx_intp_status_reg  <= w_tx_axi_rdata[3:0];
	6'h04:  Tx_intp_ennable_reg <= w_tx_axi_rdata[3:0];
	6'h08:  Tx_lane_stop_status <= w_tx_axi_rdata[7:0];
	6'h0c:  Tx_ULPS_status      <= w_tx_axi_rdata[8:0]; 
//	default: 
	endcase
end
else
begin
	Tx_intp_status_reg      <= Tx_intp_status_reg;
    Tx_intp_ennable_reg     <= Tx_intp_ennable_reg;
    Tx_lane_stop_status     <= Tx_lane_stop_status;
    Tx_ULPS_status          <= Tx_ULPS_status;
end
end
end
//Rx
always @(negedge reset_pixel_n or posedge mipi_clk)
begin
if(!reset_pixel_n)
begin
		Rx_intp_status_reg	 	<= 'h0	; 
		Rx_intp_ennable_reg		<= 'h0	;
		Rx_lane0_status			<= 'h0	;    
		Rx_lane1_status			<= 'h0	;	
		Rx_lane2_status			<= 'h0	;    
		Rx_lane3_status			<= 'h0	;     
end
else
begin
if((r_rx_dbg_fsm_1P == s_wait_rvalid)&&(w_rx_axi_rvalid == 1'b1))
begin
	case(r_rx_axi_araddr_1P)
	6'h00:	Rx_intp_status_reg  <= w_rx_axi_rdata[14:0];
	6'h04:  Rx_intp_ennable_reg <= w_rx_axi_rdata[14:0];
	6'h08:  Rx_lane0_status 	<= w_rx_axi_rdata[7:0];
	6'h0c:  Rx_lane1_status     <= w_rx_axi_rdata[7:0]; 
	6'h10:  Rx_lane2_status 	<= w_rx_axi_rdata[7:0];
	6'h14:  Rx_lane3_status     <= w_rx_axi_rdata[7:0]; 
		
//	default: 
	endcase
end
else
begin
	Rx_intp_status_reg  <= Rx_intp_status_reg   ;
	Rx_intp_ennable_reg <= Rx_intp_ennable_reg  ;
	Rx_lane0_status 	<= Rx_lane0_status 	    ;
	Rx_lane1_status     <= Rx_lane1_status      ;
	Rx_lane2_status 	<= Rx_lane2_status 	    ;
	Rx_lane3_status     <= Rx_lane3_status     	;
end
end
end

always@(negedge reset_pixel_n or posedge mipi_clk)
begin
	if (~reset_pixel_n)
	begin
		r_tx_dbg_fsm_1P		<= s_idle;
		r_tx_axi_arvalid_1P	<= 1'b0;
		r_tx_axi_araddr_1P	<= 6'b0;
		r_tx_axi_rready_1P	<= 1'b0;
		
		r_rx_dbg_fsm_1P		<= s_idle;
		r_rx_axi_arvalid_1P	<= 1'b0;
		r_rx_axi_araddr_1P	<= 6'b0;
		r_rx_axi_rready_1P	<= 1'b0;
	end
	else
	begin
		r_tx_axi_rready_1P	<= 1'b0;
		r_rx_axi_rready_1P	<= 1'b0;
		
		case (r_tx_dbg_fsm_1P)
			s_idle:
			begin
				r_tx_dbg_fsm_1P		<= s_wait_arready;
				r_tx_axi_arvalid_1P	<= 1'b1;
			end
			
			s_wait_arready:
			begin
				if (w_tx_axi_arready)
				begin
					r_tx_dbg_fsm_1P		<= s_wait_rvalid;
					r_tx_axi_arvalid_1P	<= 1'b0;
				end
			end
			
			s_wait_rvalid:
			begin
				if (w_tx_axi_rvalid)
				begin
					r_tx_dbg_fsm_1P		<= s_wait_arready;
					r_tx_axi_arvalid_1P	<= 1'b1;
					r_tx_axi_rready_1P	<= 1'b1;
					r_tx_axi_araddr_1P	<= r_tx_axi_araddr_1P+6'h4;
				if (r_tx_axi_araddr_1P == 6'h18)
						r_tx_axi_araddr_1P	<= 6'b0;
					
					/*r_tx_dbg_reg_1P[r_tx_axi_araddr_1P[4:2]]	<= w_tx_axi_rdata[8:0];*/
				end
			end
		endcase
	
		case (r_rx_dbg_fsm_1P)
			s_idle:
			begin
				r_rx_dbg_fsm_1P		<= s_wait_arready;
				r_rx_axi_arvalid_1P	<= 1'b1;
			end
			
			s_wait_arready:
			begin
				if (w_rx_axi_arready)
				begin
					r_rx_dbg_fsm_1P		<= s_wait_rvalid;
					r_rx_axi_arvalid_1P	<= 1'b0;
				end
			end
			
			s_wait_rvalid:
			begin
				if (w_rx_axi_rvalid)
				begin
					r_rx_dbg_fsm_1P		<= s_wait_arready;
					r_rx_axi_arvalid_1P	<= 1'b1;
					r_rx_axi_rready_1P	<= 1'b1;
					r_rx_axi_araddr_1P	<= r_rx_axi_araddr_1P+6'h4;
					if (r_rx_axi_araddr_1P == 6'h28)
						r_rx_axi_araddr_1P	<= 6'b0;
					
					/*	r_rx_dbg_reg_1P[r_rx_axi_araddr_1P[5:2]]	<= w_rx_axi_rdata[14:0];
              	r_rx_axi_araddr_1P	<= r_rx_axi_araddr_1P+6'h10;
					if (r_rx_axi_araddr_1P == 6'h30)
						r_rx_axi_araddr_1P	<= 6'b0;
					
				r_rx_dbg_reg_1P[r_rx_axi_araddr_1P[5:4]]	<= w_rx_axi_rdata[14:0];*/
				end
			end
		endcase 
	end
end
edb_top edb_top_inst (
    .bscan_CAPTURE      ( jtag_inst1_CAPTURE ),
    .bscan_DRCK         ( jtag_inst1_DRCK ),
    .bscan_RESET        ( jtag_inst1_RESET ),
    .bscan_RUNTEST      ( jtag_inst1_RUNTEST ),
    .bscan_SEL          ( jtag_inst1_SEL ),
    .bscan_SHIFT        ( jtag_inst1_SHIFT ),
    .bscan_TCK          ( jtag_inst1_TCK ),
    .bscan_TDI          ( jtag_inst1_TDI ),
    .bscan_TMS          ( jtag_inst1_TMS ),
    .bscan_UPDATE       ( jtag_inst1_UPDATE ),
    .bscan_TDO          ( jtag_inst1_TDO ),
    .MipiTx_clk     ( mipi_clk),


    .MipiTx_ConfigTxFrameRate( MipiTx_ConfigTxFrameRate ),
    .MipiTx_ConfigTxVertPixelNumber( MipiTx_ConfigTxVertPixelNumber ),
    .MipiTx_ConfigTxHoriPixelNumber( MipiTx_ConfigTxHoriPixelNumber ),
    .MipiTx_ConfigTxVBlankTime_us( MipiTx_ConfigTxVBlankTime_us ),
    .MipiTx_ConfigTxHBlankTime_us( MipiTx_ConfigTxHBlankTime_us ),
    .MipiTx_configTxLanesNumber( MipiTx_configTxLanesNumber ),
    .MipiTx_ConfigPixelDataType( MipiTx_ConfigPixelDataType ),
    .MipiTx_ConfigTxFramerMode( MipiTx_ConfigTxFramerMode ),
	 .MipiTx_RealTxHoriPixelNumber( MipiTx_RealTxHoriPixelNumber ),
    .MipiTx_TxDataRate_bps( MipiTx_TxDataRate_bps ),
    .MipiTx_ControlTxDPHYReset( MipiTx_ControlTxDPHYReset ),
    .MipiTx_ControlTxCSIReset( MipiTx_ControlTxCSIReset ),
    .MipiTx_ControlTxDisable( MipiTx_ControlTxDisable ),
    .MipiTx_MipiTx_ConfigTxVCEnable( MipiTx_ConfigTxVCEnable ),
	 .MipiTx_ParamTxVertSyncLength_Cycle( MipiTx_ParamTxVertSyncLength_Cycle ),
    .MipiTx_ParamTxHoriSyncLength_Cycle( MipiTx_ParamTxHoriSyncLength_Cycle ),
    .MipiTx_paramTxDataValidLength_Cycle( MipiTx_paramTxDataValidLength_Cycle ),
    .MipiTx_paramTxVertBlankLength_Cycle( MipiTx_paramTxVertBlankLength_Cycle ),
    .MipiTx_paramTxHoriBlankLength_Cycle( MipiTx_paramTxHoriBlankLength_Cycle ),
	    .MipiTx_CfgTxHPixelMax( CfgTxHPixelMax ),
	    .MipiTx_HoriMaxPixelNum(HoriMaxPixelNum ),
    .MipiTx_RealHoriPixelNum(RealHoriPixelNum ),
	.MipiTx_CalcHoriMaxPixelNum( CalcHoriMaxPixelNum ),
    .MipiTx_HoriPayloadBitNum(   HoriPayloadBitNum ),
    .MipiTx_CalcHoriBitNum( 	 CalcHoriBitNum ),
	 .MipiTx_CfgTxBitNFactor( CfgTxBitNFactor ),
	 .MipiTx_HSyncPeriod( HSyncPeriod ),
    .MipiTx_HoriPayloadLen( HoriPayloadLen ),
	.LA_Mipi_Tx_clk                ( mipi_clk ),
    .LA_Mipi_Tx_MipiTxValid        ( MipiTxValid ),
    .LA_Mipi_Tx_MipiTxHSync        ( MipiTxHSync ),
    .LA_Mipi_Tx_MipiTxVSync        ( MipiTxVSync ),
    .LA_Mipi_Tx_MipiTx_DATA        ( MipiTx_DATA ),
	.LA_Mipi_Tx_r_tx_axi_araddr_1P      ( r_tx_axi_araddr_1P ),
    .LA_Mipi_Tx_w_tx_axi_rvalid     ( w_tx_axi_rvalid ),
    .LA_Mipi_Tx_w_tx_axi_arready        ( w_tx_axi_arready ),
    .LA_Mipi_Tx_w_tx_axi_rdata      ( w_tx_axi_rdata ),
	.LA_Mipi_Tx_Tx_intp_status_reg      ( Tx_intp_status_reg ),
    .LA_Mipi_Tx_Tx_intp_ennable_reg     ( Tx_intp_ennable_reg ),
    .LA_Mipi_Tx_Tx_lane_stop_status     ( Tx_lane_stop_status ),
    .LA_Mipi_Tx_Tx_ULPS_status          ( Tx_ULPS_status ),
	 .LA_Mipi_Tx_r_tx_dbg_fsm_1P     ( r_tx_dbg_fsm_1P ),
	.LA_Mipi_Tx_mipi_dphy_tx_data0_HS_OUT       ( mipi_dphy_tx_inst1_HS_LAN0_DATA ),
    .LA_Mipi_Tx_mipi_dphy_tx_data1_HS_OUT       ( mipi_dphy_tx_inst1_HS_LAN1_DATA ),
    .LA_Mipi_Tx_mipi_dphy_tx_data2_HS_OUT       ( mipi_dphy_tx_inst1_HS_LAN2_DATA ),
    .LA_Mipi_Tx_mipi_dphy_tx_data3_HS_OUT       ( mipi_dphy_tx_inst1_HS_LAN3_DATA ), 
	.LA_Mipi_Tx_MipiTxDPHYRstN      ( MipiTxDPHYRstN ),
    .LA_Mipi_Tx_MipiTx_DPHY_RSTN    ( MipiTx_DPHY_RSTN ),
	.LA_Mipi_Tx_MipiTxAutoRst       ( MipiTxAutoRst ),
	 .LA_Mipi_Tx_TxDPHYRstCnt        ( TxDPHYRstCnt ),
    .LA_Mipi_Tx_TxConfigEn      ( TxConfigEn ),
	 .MipiRx_clk     ( mipi_clk ),
    .MipiRx_VidioFrmNum(     VidioFrmNum ),
    .MipiRx_VidioHPixelNum(  VidioHPixelNum ),
    .MipiRx_VidioVPixelNum(  VidioVPixelNum ),
    .MipiRx_VidioVBlankTime( VidioVBlankTime ),
    .MipiRx_VidioHBlankTime( VidioHBlankTime ),
    .MipiRx_VidioDataType( VidioDataType ),
    .MipiRx_VidioRestChg(  VidioRestChg ),
    .MipiRx_MipiRxLanesAct( MipiRxLanesAct ),
    .MipiRx_MipiRxStaVCAct( MipiRxStaVCAct ),
    .MipiRx_ConfRxLanNum( ConfRxLanNum ),
    .MipiRx_RxErrCnt( RxErrCnt ),
    .MipiRx_MipiRxError( MipiRxError ),
	.MipiRx_CtrlRxDPHYRstN( CtrlRxDPHYRstN ),
    .MipiRx_CtrlRxCSIRstN (  CtrlRxCSIRstN ),
	.MipiRx_TestTimeCnt( TestTimeCnt ),
	.MipiRx_MiPiRxRight( MiPiRxRight ),
    .LA_Mipi_Rx_clk         ( mipi_clk ),
    .LA_Mipi_Rx_Rx_intp_status_reg      (Rx_intp_status_reg ),
    .LA_Mipi_Rx_Rx_intp_ennable_reg     (Rx_intp_ennable_reg ),
    .LA_Mipi_Rx_Rx_lane0_status     (    Rx_lane0_status ),
    .LA_Mipi_Rx_Rx_lane1_status     (    Rx_lane1_status ),
    .LA_Mipi_Rx_Rx_lane2_status     (    Rx_lane2_status ),
    .LA_Mipi_Rx_Rx_lane3_status     (    Rx_lane3_status ),
	.LA_Mipi_Rx_word_count      ( word_count ),
    .LA_Mipi_Rx_MipiRx_CNT      ( MipiRx_CNT ),
    .LA_Mipi_Rx_MipiRx_VALID        ( MipiRx_VALID ),
    .LA_Mipi_Rx_MipiRx_HSYNC        ( MipiRx_HSYNC ),
    .LA_Mipi_Rx_MipiRx_VSYNC        ( MipiRx_VSYNC ),
    .LA_Mipi_Rx_MipiRx_VC       ( MipiRx_VC ),
    .LA_Mipi_Rx_w_rx_axi_rvalid     ( w_rx_axi_rvalid ),
    .LA_Mipi_Rx_w_rx_axi_rdata      ( rx_axi_rdata ),
    .LA_Mipi_Rx_r_rx_axi_araddr_1P      ( r_rx_axi_araddr_1P ),
	.LA_Mipi_Rx_MipiRx_DATA     ( MipiRx_DATA ),
	.LA_Mipi_Rx_MipiRxData      ( MipiRxData ),
    .LA_Mipi_Rx_MipiRxError     ( MipiRxError ),
    .LA_Mipi_Rx_MiPiRxRight     ( MiPiRxRight ),
    .LA_Mipi_Rx_MipiRxDPHYRstN  ( MipiRxDPHYRstN ),
	.LA_Mipi_Rx_RxErrCnt        ( RxErrCnt ),
	.LA_Mipi_Rx_datatype        ( datatype ),
	.LA_Mipi_Rx_mipi_dphy_rx_inst2_HS_LAN0_DATA     ( mipi_dphy_rx_inst2_HS_LAN0_DATA ),
    .LA_Mipi_Rx_mipi_dphy_rx_inst2_HS_LAN1_DATA     ( mipi_dphy_rx_inst2_HS_LAN1_DATA ),
    .LA_Mipi_Rx_mipi_dphy_rx_inst2_HS_LAN2_DATA     ( mipi_dphy_rx_inst2_HS_LAN2_DATA ),
    .LA_Mipi_Rx_mipi_dphy_rx_inst2_HS_LAN3_DATA     ( mipi_dphy_rx_inst2_HS_LAN3_DATA ),
    .LA_Mipi_Rx_mipi_dphy_rx_inst2_HS_LAN0_VALID    ( mipi_dphy_rx_inst2_HS_LAN0_VALID ),
    .LA_Mipi_Rx_mipi_dphy_rx_inst2_HS_LAN1_VALID    ( mipi_dphy_rx_inst2_HS_LAN1_VALID ),
    .LA_Mipi_Rx_mipi_dphy_rx_inst2_HS_LAN2_VALID    ( mipi_dphy_rx_inst2_HS_LAN2_VALID ),
    .LA_Mipi_Rx_mipi_dphy_rx_inst2_HS_LAN3_VALID    ( mipi_dphy_rx_inst2_HS_LAN3_VALID ),
	.la0_clk            ( mipi_dphy_rx_clk_CLKOUT ),
    .la0_mipi_rx_cnt        ( count_led ),
    .la0_RxsyncHs (RxsyncHs),
    .la0_RxValidHS(RxValidHS),
    .la0_RxDataHS0(RxDataHS[0]),
    .la0_RxDataHS1(RxDataHS[1]),
    .la0_RxDataHS2(RxDataHS[2]),
    .la0_RxDataHS3(RxDataHS[3])
    
);


	assign  PixelTxEn     = ~MipiTx_ControlTxDisable          ; //Pixel Tx Enable   
	assign  MipiTxVCEn    = MipiTx_ConfigTxVCEnable           ; //Configuration Tx VC Enable
	assign  CfgTxFrmRate  = MipiTx_ConfigTxFrameRate          ; //Configuration Tx Framer Rate
	assign  CfgTxHPixelNum= MipiTx_ConfigTxHoriPixelNumber    ; //Configuration Tx Horizontal Number
	assign  CfgTxVPixelNum= MipiTx_ConfigTxVertPixelNumber    ; //Configuration Tx Vertical Pixel Number  
	assign  CfgTxVBlkTime = MipiTx_ConfigTxVBlankTime_us      ; //Configuration Tx Vertical Blanking Time (us)
	assign  CfgTxHBlkTime = MipiTx_ConfigTxHBlankTime_us      ; //Configuration Tx Horizontal Blanking Time (us)
	assign  ConfLanesNum  = MipiTx_configTxLanesNumber        ; //Configuration Lanes Number Horizontal
	assign  ConfDataType  = MipiTx_ConfigPixelDataType        ; //Configuration Pixel Data Type                
	assign  ConfTxFrmMod  = MipiTx_ConfigTxFramerMode         ; //Configuration Framer Mode
																	
	assign  CtrlTxDPHYRstN= MipiTx_ControlTxDPHYReset         ; //MIPI Tx DPHY Reset (Low Active)
	assign  CtrlTxCSIRstN = MipiTx_ControlTxCSIReset          ; //MIPI Tx CSI-2 Reset (Low Active) 

                                                                    

	                                                                         
endmodule

