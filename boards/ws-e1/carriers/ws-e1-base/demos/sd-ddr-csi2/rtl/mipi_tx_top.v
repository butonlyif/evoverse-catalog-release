//============================================================================
// mipi_tx_top.v
//
// MIPI CSI-2 TX video pipe for the TJ180A484S board (phase C).
//
// Structure copied from D:\Projs\ws-e1-mipi-1280x720-yuv\rtl\top.sv with
// pattern_gen replaced by the 64-bit stream coming from video_reader (DDR
// Port 1). Clock network, reset chain, DPHY wiring and the CSI-2 TX IP
// instantiation are identical to the reference design:
//
//   video_reader (sys_clk_125m) -> async FIFO -> timing FSM (pixel_clk
//   18.5625 MHz) -> mipi_csi_tx_2p5g -> DPHY TX2 hard macro (4 data lanes +
//   clock lane, 2500 Mbps/lane)
//
// Timing fixed to 1280x720@60 (reference RES_SEL=1):
//   HACT=1280 VACT=720 HSP=40 HBP=220 HFP=112 VSP=5 VBP=20 VFP=5, PPC=4
//   (HFP 110->112 so every horizontal parameter is divisible by PPC=4)
//============================================================================

module mipi_tx_top #(
    parameter HACT = 16'd1280,
    parameter VACT = 14'd720,
    parameter HSP  = 12'd40,
    parameter HBP  = 12'd220,
    parameter HFP  = 12'd112,
    parameter VSP  = 12'd5,
    parameter VBP  = 12'd20,
    parameter VFP  = 12'd5,

    parameter NUM_DATA_LANE = 4,
    parameter PIXEL_BIT     = 16,
    parameter PACK_BIT      = 64,
    parameter DATATYPE      = 6'h1E   // YUV422 8-bit, 4 pixels/clock (64-bit word)
)(
    ////////////////////////    CLOCK & PLL     ////////////////////////
    input       sys_clk_125m,        // 125 MHz, pll_sys CLKOUT1 (FIFO write side)
    input       pixel_clk,           // 18.5625 MHz word clock, pll_csi CLKOUT1
    output      pll_mipi_refclk_rstn,
    output      pll_csi_rstn,

    input       pll_sys_locked,
    input       pll_csi_locked,
    input       pll_mipi_refclk_locked,

    input       i_clk_27m,

    ///---- MIPI blocks related clocks   ----///
    input  logic         dphy_tx2_WORD_CLKOUT_HS,      // 156.25 MHz (2500Mbps/16)
    input  logic         esc_clk,
    input  logic         mipi_refclk_25m,
    ///---- MIPI blocks control signals   ----///
    input   logic        dphy_tx2_PLL_UNLOCK,
    output  logic        dphy_tx2_RESET_N,
    output  logic        dphy_tx2_PLL_SSC_EN,

    ///---- Clock Lane   ----///
    input   logic        dphy_tx2_STOPSTATE_CLK,
    output  logic        dphy_tx2_TX_REQUEST_HS,
    output  logic        dphy_tx2_TX_ULPS_CLK,
    output  logic        dphy_tx2_TX_ULPS_EXIT,
    input   logic        dphy_tx2_TX_ULPS_ACTIVE_CLK_NOT,

    ///---- Data Lane ULPS ----///
    output  logic        dphy_tx2_TX_ULPS_ESC_LAN0,
    output  logic        dphy_tx2_TX_ULPS_ESC_LAN1,
    output  logic        dphy_tx2_TX_ULPS_ESC_LAN2,
    output  logic        dphy_tx2_TX_ULPS_ESC_LAN3,
    output  logic        dphy_tx2_TX_ULPS_EXIT_LAN0,
    output  logic        dphy_tx2_TX_ULPS_EXIT_LAN1,
    output  logic        dphy_tx2_TX_ULPS_EXIT_LAN2,
    output  logic        dphy_tx2_TX_ULPS_EXIT_LAN3,
    input   logic        dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN0,
    input   logic        dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN1,
    input   logic        dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN2,
    input   logic        dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN3,

    ///---- Data Lane LP mode   ----///
    output  logic        dphy_tx2_TX_REQUEST_ESC_LAN0,
    output  logic        dphy_tx2_TX_REQUEST_ESC_LAN1,
    output  logic        dphy_tx2_TX_REQUEST_ESC_LAN2,
    output  logic        dphy_tx2_TX_REQUEST_ESC_LAN3,
    input   logic        dphy_tx2_STOPSTATE_LAN0,
    input   logic        dphy_tx2_STOPSTATE_LAN1,
    input   logic        dphy_tx2_STOPSTATE_LAN2,
    input   logic        dphy_tx2_STOPSTATE_LAN3,

    ///---- Data Lane HS mode   ----///
    output  logic        dphy_tx2_TX_SKEW_CAL_HS_LAN0,
    output  logic        dphy_tx2_TX_SKEW_CAL_HS_LAN1,
    output  logic        dphy_tx2_TX_SKEW_CAL_HS_LAN2,
    output  logic        dphy_tx2_TX_SKEW_CAL_HS_LAN3,
    input   logic        dphy_tx2_TX_READY_HS_LAN0,
    input   logic        dphy_tx2_TX_READY_HS_LAN1,
    input   logic        dphy_tx2_TX_READY_HS_LAN2,
    input   logic        dphy_tx2_TX_READY_HS_LAN3,
    output  logic        dphy_tx2_TX_REQUEST_HS_LAN0,
    output  logic        dphy_tx2_TX_REQUEST_HS_LAN1,
    output  logic        dphy_tx2_TX_REQUEST_HS_LAN2,
    output  logic        dphy_tx2_TX_REQUEST_HS_LAN3,
    output  logic [15:0] dphy_tx2_TX_DATA_HS_LAN0,
    output  logic [15:0] dphy_tx2_TX_DATA_HS_LAN1,
    output  logic [15:0] dphy_tx2_TX_DATA_HS_LAN2,
    output  logic [15:0] dphy_tx2_TX_DATA_HS_LAN3,
    output  logic        dphy_tx2_TX_WORD_VALID_HS_LAN0,
    output  logic        dphy_tx2_TX_WORD_VALID_HS_LAN1,
    output  logic        dphy_tx2_TX_WORD_VALID_HS_LAN2,
    output  logic        dphy_tx2_TX_WORD_VALID_HS_LAN3,

    ////////////////////////    VIDEO INPUT (sys_clk_125m)  /////////////
    input  wire [63:0]   i_vid_data,   // from video_reader (already pause-qualified)
    input  wire          i_vid_valid,
    output wire          o_vid_pause   // FIFO almost-full backpressure
);


//==============================================================
// video timing generator outputs
//==============================================================
(* syn_keep="true" *) wire              vsync;
(* syn_keep="true" *) wire              hsync;
(* syn_keep="true" *) wire              pixel_data_valid;
wire [63:0]       pixel_data;

//==============================================================
// Mapping to DPHY TX
//==============================================================
logic                       TxUlpsClk;
logic                       TxUlpsExitClk;
logic [NUM_DATA_LANE-1:0]   TxUlpsEsc;
logic [NUM_DATA_LANE-1:0]   TxUlpsExit;
logic [NUM_DATA_LANE-1:0]   TxRequestEsc;
logic [NUM_DATA_LANE-1:0]   TxSkewCalHS;
logic [NUM_DATA_LANE-1:0]   TxRequestHS;
logic                       TxRequestHSc;
logic [15:0]                TxDataHS0;
logic [15:0]                TxDataHS1;
logic [15:0]                TxDataHS2;
logic [15:0]                TxDataHS3;
logic [1:0]                 TxReqValidHS0;
logic [1:0]                 TxReqValidHS1;
logic [1:0]                 TxReqValidHS2;
logic [1:0]                 TxReqValidHS3;
logic                       TxUlpsActiveClkNot;
logic [NUM_DATA_LANE-1:0]   TxStopStateD;
logic                       TxStopStateC;
logic [NUM_DATA_LANE-1:0]   TxUlpsActiveNot;
logic [NUM_DATA_LANE-1:0]   TxReadyHS;

assign dphy_tx2_PLL_SSC_EN = 0;

assign TxStopStateC = dphy_tx2_STOPSTATE_CLK;
assign dphy_tx2_TX_REQUEST_HS = TxRequestHSc;
assign dphy_tx2_TX_ULPS_CLK = TxUlpsClk;
assign dphy_tx2_TX_ULPS_EXIT = TxUlpsExitClk;
assign TxUlpsActiveClkNot = dphy_tx2_TX_ULPS_ACTIVE_CLK_NOT;

assign dphy_tx2_TX_ULPS_ESC_LAN0 = TxUlpsEsc[0];
assign dphy_tx2_TX_ULPS_ESC_LAN1 = TxUlpsEsc[1];
assign dphy_tx2_TX_ULPS_ESC_LAN2 = TxUlpsEsc[2];
assign dphy_tx2_TX_ULPS_ESC_LAN3 = TxUlpsEsc[3];
assign dphy_tx2_TX_ULPS_EXIT_LAN0 = TxUlpsExit[0];
assign dphy_tx2_TX_ULPS_EXIT_LAN1 = TxUlpsExit[1];
assign dphy_tx2_TX_ULPS_EXIT_LAN2 = TxUlpsExit[2];
assign dphy_tx2_TX_ULPS_EXIT_LAN3 = TxUlpsExit[3];
assign dphy_tx2_TX_REQUEST_ESC_LAN0 = TxRequestEsc[0];
assign dphy_tx2_TX_REQUEST_ESC_LAN1 = TxRequestEsc[1];
assign dphy_tx2_TX_REQUEST_ESC_LAN2 = TxRequestEsc[2];
assign dphy_tx2_TX_REQUEST_ESC_LAN3 = TxRequestEsc[3];
assign dphy_tx2_TX_SKEW_CAL_HS_LAN0 = TxSkewCalHS[0];
assign dphy_tx2_TX_SKEW_CAL_HS_LAN1 = TxSkewCalHS[1];
assign dphy_tx2_TX_SKEW_CAL_HS_LAN2 = TxSkewCalHS[2];
assign dphy_tx2_TX_SKEW_CAL_HS_LAN3 = TxSkewCalHS[3];
assign TxStopStateD[0] = dphy_tx2_STOPSTATE_LAN0;
assign TxStopStateD[1] = dphy_tx2_STOPSTATE_LAN1;
assign TxStopStateD[2] = dphy_tx2_STOPSTATE_LAN2;
assign TxStopStateD[3] = dphy_tx2_STOPSTATE_LAN3;

assign TxUlpsActiveNot[0] = dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN0;
assign TxUlpsActiveNot[1] = dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN1;
assign TxUlpsActiveNot[2] = dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN2;
assign TxUlpsActiveNot[3] = dphy_tx2_TX_ULPS_ACTIVE_NOT_LAN3;
assign TxReadyHS[0] = dphy_tx2_TX_READY_HS_LAN0;
assign TxReadyHS[1] = dphy_tx2_TX_READY_HS_LAN1;
assign TxReadyHS[2] = dphy_tx2_TX_READY_HS_LAN2;
assign TxReadyHS[3] = dphy_tx2_TX_READY_HS_LAN3;

assign dphy_tx2_TX_DATA_HS_LAN0 = TxDataHS0;
assign dphy_tx2_TX_DATA_HS_LAN1 = TxDataHS1;
assign dphy_tx2_TX_DATA_HS_LAN2 = TxDataHS2;
assign dphy_tx2_TX_DATA_HS_LAN3 = TxDataHS3;
assign dphy_tx2_TX_REQUEST_HS_LAN0 = TxRequestHS[0];
assign dphy_tx2_TX_REQUEST_HS_LAN1 = TxRequestHS[1];
assign dphy_tx2_TX_REQUEST_HS_LAN2 = TxRequestHS[2];
assign dphy_tx2_TX_REQUEST_HS_LAN3 = TxRequestHS[3];
assign dphy_tx2_TX_WORD_VALID_HS_LAN0 = TxReqValidHS0[1];
assign dphy_tx2_TX_WORD_VALID_HS_LAN1 = TxReqValidHS1[1];
assign dphy_tx2_TX_WORD_VALID_HS_LAN2 = TxReqValidHS2[1];
assign dphy_tx2_TX_WORD_VALID_HS_LAN3 = TxReqValidHS3[1];


//power-up self-reset
reg [7:0] cnt;
reg i_arstn;
always@(posedge i_clk_27m) begin
    if(cnt==8'hff) begin
        cnt <= 8'hff;
        i_arstn <= 1'b1;
    end
    else begin
        cnt <= cnt + 1'b1;
        i_arstn <= 1'b0;
    end
end

//===================================================================
// PLL resets (active high release, no system reset)
//===================================================================
assign pll_mipi_refclk_rstn = i_arstn;
assign pll_csi_rstn = i_arstn;
//using pll_mipi_refclk_locked because PLL MIPI REFCLK generates mipi 25MHz clock
//Reset for DPHY
assign dphy_tx2_RESET_N = pll_mipi_refclk_locked;

//wait for 250us for DPHY ready
reg [12:0] cnt_250us;
reg reset_esc_n;
reg clk_byte_HS_n;
always@(posedge i_clk_27m or negedge dphy_tx2_RESET_N) begin
    if(~dphy_tx2_RESET_N) begin
        cnt_250us <= 13'd0;
        reset_esc_n <= 1'b0;
        clk_byte_HS_n <= 1'b0;
    end
    else if(cnt_250us==13'h1fff) begin
        cnt_250us <= 13'h1fff;
        reset_esc_n <= 1'b1;
        clk_byte_HS_n <= 1'b1;
    end
    else begin
        cnt_250us <= cnt_250us + 1'b1;
        reset_esc_n <= 1'b0;
        clk_byte_HS_n <= 1'b0;
    end
end

//wait another 500us tINIT_NS + skewcal
reg [13:0] cnt_500us;
reg reset_pixel_n;
always@(posedge i_clk_27m or negedge clk_byte_HS_n) begin
    if(~clk_byte_HS_n) begin
        cnt_500us <= 14'd0;
        reset_pixel_n <= 1'b0;
    end
    else if(cnt_500us==14'h3fff) begin
        cnt_500us <= 14'h3fff;
        reset_pixel_n <= 1'b1;
    end
    else begin
        cnt_500us <= cnt_500us + 1'b1;
        reset_pixel_n <= 1'b0;
    end
end


//===================================================================
//reset_ctrl
//===================================================================
wire       sys_clk_arstn;
wire       sys_clk_arst;
wire       pixel_clk_arstn;
wire       pixel_clk_arst;
wire       word_clk_arstn;
wire       word_clk_arst;
wire       esc_clk_arstn;
wire       esc_clk_arst;


reset_ctrl #(
    .NUM_RST       (8),
    .CYCLE         (2),
    .IN_RST_ACTIVE (8'b0),
    .OUT_RST_ACTIVE(8'b10101010)
) inst_reset_ctrl (
    // all domains released only after every PLL locked + power-on delay counter done
    .i_arst({{2{pll_sys_locked}},{2{reset_pixel_n}},{2{clk_byte_HS_n}},{2{reset_esc_n}}}),
    .i_clk({
        {2{sys_clk_125m}}, {2{pixel_clk}}, {2{dphy_tx2_WORD_CLKOUT_HS}}, {2{esc_clk}}
    }),
    .o_srst({
        sys_clk_arst,
        sys_clk_arstn,
        pixel_clk_arst,
        pixel_clk_arstn,
        word_clk_arst,
        word_clk_arstn,
        esc_clk_arst,
        esc_clk_arstn
    })
);

//===================================================================
// video source : video_reader stream @ sys_clk_125m -> async FIFO
//                -> timing FSM @ pixel_clk
//===================================================================
wire [15:0]  haddr;
wire [15:0]  line_num;
wire [15:0]  frame_num;
wire [5:0]   datatype;
shape_video_data #(
	.HSP	(HSP),
	.HBP	(HBP),
	.HFP	(HFP),
	.HACT	(HACT),
	.VSP	(VSP),
	.VBP	(VBP),
	.VFP	(VFP),
	.VACT	(VACT),
	.PPC	(4),
    .FIFO_DEPTH(2048),
    .DATA_TYPE (6'h1E)
) u_shape_video_data (
	.sys_clk	      (sys_clk_125m),          //FIFO 写端 = video_reader
	.sys_rst_n	      (sys_clk_arstn),
	.sys_pixel_data	  (i_vid_data),
	.sys_valid	      (i_vid_valid),
	.pause            (o_vid_pause),
	.pixel_clk	      (pixel_clk),             //FIFO 读端 = 时序状态机
	.pixel_rst_n      (pixel_clk_arstn),
	.vsync_vc0	      (vsync),
	.hsync_vc0	      (hsync),
	.pixel_data_valid (pixel_data_valid),
	.pixel_data       (pixel_data),
    .datatype         (datatype),
    .haddr            (haddr),
    .line_num         (line_num),
    .frame_num        (frame_num)
);



(* syn_keep="true" *)wire [31:0] mipi_debug_out;
//===================================================================
// MIPI CSI-2 TX IP : zero software init, free-run streaming mode
//===================================================================
mipi_csi_tx_2p5g u_mipi_csi_tx_2p5g
(
    .clk_byte_HS        (dphy_tx2_WORD_CLKOUT_HS  ),
    .reset_byte_HS_n    (word_clk_arstn),

    .clk_pixel          (pixel_clk),
    .reset_pixel_n      (pixel_clk_arstn),   // 像素侧必须用 pixel_clk 域同步释放的复位

    .clk_esc            (esc_clk),
    .reset_esc_n        (esc_clk_arstn),

    .irq                (  ),

    .frame_num          ( frame_num ),
    .hsync_vc0          ( hsync ),
    .hsync_vc1          (  ),
    .hsync_vc3          (  ),

    .vsync_vc0          ( vsync ),
    .vsync_vc1          (  ),
    .vsync_vc2          (  ),
    .vsync_vc3          (  ),

    .line_num           ( line_num ),
    .haddr              ( haddr ),
    .pixel_data         ( pixel_data ),
    .pixel_data_valid   ( pixel_data_valid ),
    .datatype           ( datatype ),
    .mipi_debug_in      ( 32'd0 ),
    .mipi_debug_out     ( mipi_debug_out ),

    //AXI4-Lite Interface : tied off, no register access (same as validated design)
    .axi_clk            (sys_clk_125m),
    .axi_reset_n        (sys_clk_arstn),
    .axi_awaddr			(6'b0),//Write Address. byte address.
    .axi_awvalid		(1'b1),//Write address valid.
    .axi_awready		(),//Write address ready.
    .axi_wdata			(32'b0),//Write data bus.
    .axi_wvalid			(1'b0),//Write valid.
    .axi_wready			(),//Write ready.
    .axi_bvalid			(),//Write response valid.
    .axi_bready			(1'b0),//Response ready.
    .axi_araddr			(6'b0),//Read address. byte address.
    .axi_arvalid		(1'b0),//Read address valid.
    .axi_arready		(),//Read address ready.
    .axi_rdata			(),//Read data.
    .axi_rvalid			(),//Read valid.
    .axi_rready			(1'b1),//Read ready.

    .TxUlpsClk          ( TxUlpsClk ),
    .TxUlpsExitClk      ( TxUlpsExitClk ),
    .TxUlpsActiveClkNot ( TxUlpsActiveClkNot ),
    .TxUlpsEsc          ( TxUlpsEsc ),
    .TxSkewCalHS        ( TxSkewCalHS ),
    .TxUlpsExit         ( TxUlpsExit ),
    .TxRequestEsc       ( TxRequestEsc ),
    .TxStopStateD       ( TxStopStateD ),
    .TxStopStateC       ( TxStopStateC ),
    .TxUlpsActiveNot    ( TxUlpsActiveNot ),
    .TxReadyHS          ( TxReadyHS ),
    .TxRequestHS        ( TxRequestHS ),
    .TxRequestHSc       ( TxRequestHSc ),
    .TxDataHS0          ( TxDataHS0 ),
    .TxDataHS1          ( TxDataHS1 ),
    .TxDataHS2          ( TxDataHS2 ),
    .TxDataHS3          ( TxDataHS3 ),
    .TxDataHS4          (  ),
    .TxDataHS5          (  ),
    .TxDataHS6          (  ),
    .TxDataHS7          (  ),
    .TxReqValidHS0      ( TxReqValidHS0 ),
    .TxReqValidHS1      ( TxReqValidHS1 ),
    .TxReqValidHS2      ( TxReqValidHS2 ),
    .TxReqValidHS3      ( TxReqValidHS3 ),
    .TxReqValidHS4      (  ),
    .TxReqValidHS5      (  ),
    .TxReqValidHS6      (  ),
    .TxReqValidHS7      (  )
);

endmodule
