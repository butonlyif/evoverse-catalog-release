
module top #(
parameter	HACT		= 16'd3840,
parameter	VACT		= 14'd2160,
parameter	HSP				= 12'd88,
parameter	HBP				= 12'd296,
parameter	HFP				= 12'd176,
parameter	VSP				= 12'd10,
parameter	VBP				= 12'd72,
parameter	VFP				= 12'd8,
// parameter	HACT		= 16'd1920,
// parameter	VACT		= 14'd1080,
// parameter	HSP				= 12'd44,
// parameter	HBP				= 12'd148,
// parameter	HFP				= 12'd88,
// parameter	VSP				= 12'd5,
// parameter	VBP				= 12'd36,
// parameter	VFP				= 12'd4,
parameter   NUM_DATA_LANE   = 4,
    parameter PIXEL_BIT  = 16,
    parameter PACK_BIT   = 64,
    parameter DATATYPE = 6'h1E     //24 - YUV4222

)(

//`default_nettype none
    ////////////////////////    CLOCK & PLL     ////////////////////////
    
    input       i_fb_clk,
    input       i_sysclk_div2,
    input       dphy_byte_clk, //312.5MHz
    input       mipi_rx_cfg_clk,
    input       CLK_5M,
    output      pll_mipi_rstn,
    output      pll0_rstn,
    output      pll_byteclk_rstn,

	input 		pll0_locked,
    input       pll_mipi_locked,
    input       pll_byteclk_locked,  
    ////////////////////////    USER CONTROL    ///////////////////

   // input       i_arstn,

    ///---- MIPI blocks related clocks   ----///
    input  logic         mipi_dphy_tx_pclk,      //MIPI HS byte clock from MIPI block 
    input  logic         esc_clk,   //20Mhz
    
    ///---- MIPI blocks control signals   ----///
    input   logic        mipi_dphy_tx_inst1_PLL_UNLOCK,
    output  logic        mipi_dphy_tx_inst1_RESET_N,
    output  logic        mipi_dphy_tx_inst1_PLL_SSC_EN, 

    ///---- Clock Lane   ----///
    input   logic        mipi_dphy_tx_inst1_STOPSTATE_CLK,
    output  logic        mipi_dphy_tx_inst1_TX_REQUEST_HS,
    output  logic        mipi_dphy_tx_inst1_TX_ULPS_CLK,
    output  logic        mipi_dphy_tx_inst1_TX_ULPS_EXIT,
    input   logic        mipi_dphy_tx_inst1_TX_ULPS_ACTIVE_CLK_NOT,

    ///---- Data Lane ULPS ----///
    output  logic        mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN0,
    output  logic        mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN1,
    output  logic        mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN2,
    output  logic        mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN3,
    output  logic        mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN0,
    output  logic        mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN1,
    output  logic        mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN2,
    output  logic        mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN3,
    input   logic        mipi_dphy_tx_inst1_TX_ULPS_ACTIVE_NOT_LAN0,
    input   logic        mipi_dphy_tx_inst1_TX_ULPS_ACTIVE_NOT_LAN1,
    input   logic        mipi_dphy_tx_inst1_TX_ULPS_ACTIVE_NOT_LAN2,
    input   logic        mipi_dphy_tx_inst1_TX_ULPS_ACTIVE_NOT_LAN3,

    ///---- Data Lane LP mode   ----///
    output  logic        mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN0,
    output  logic        mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN1,
    output  logic        mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN2,
    output  logic        mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN3,
    input   logic        mipi_dphy_tx_inst1_STOPSTATE_LAN0,
    input   logic        mipi_dphy_tx_inst1_STOPSTATE_LAN1,
    input   logic        mipi_dphy_tx_inst1_STOPSTATE_LAN2,
    input   logic        mipi_dphy_tx_inst1_STOPSTATE_LAN3,

    ///---- Data Lane HS mode   ----///
    output  logic        mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN0,
    output  logic        mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN1,
    output  logic        mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN2,
    output  logic        mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN3,
    input   logic        mipi_dphy_tx_inst1_TX_READY_HS_LAN0,
    input   logic        mipi_dphy_tx_inst1_TX_READY_HS_LAN1,
    input   logic        mipi_dphy_tx_inst1_TX_READY_HS_LAN2,
    input   logic        mipi_dphy_tx_inst1_TX_READY_HS_LAN3,
    output  logic        mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN0,
    output  logic        mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN1,
    output  logic        mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN2,
    output  logic        mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN3,
    output  logic [15:0] mipi_dphy_tx_inst1_TX_DATA_HS_LAN0,
    output  logic [15:0] mipi_dphy_tx_inst1_TX_DATA_HS_LAN1,
    output  logic [15:0] mipi_dphy_tx_inst1_TX_DATA_HS_LAN2,
    output  logic [15:0] mipi_dphy_tx_inst1_TX_DATA_HS_LAN3,
    output  logic        mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN0,
    output  logic        mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN1,
    output  logic        mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN2,
    output  logic        mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN3

    



	// output reg	r_lcd_rstn
);



////---- unused signals  ----////




wire        pll_locked;

wire		  i_arstn = 1'b1;

////////////////////////////////////////////////////////////////
//==============================================================
  

//==============================================================
// DSI Tx AXI
wire [31:0] w_axi_rdata;
wire        w_axi_awready;
wire        w_axi_wready;
wire        w_axi_arready;
wire        w_axi_rvalid;
wire        w_axi_bvalid;

wire [ 6:0] w_axi_awaddr;
wire        w_axi_awvalid;
wire [31:0] w_axi_wdata;
wire        w_axi_wvalid;
wire        w_axi_bready;
wire [ 6:0] w_axi_araddr;
wire        w_axi_arvalid;
wire        w_axi_rready;

wire              w_vs;
wire              w_hs;
wire              w_valid;
wire [15:0]       w_r;
wire [15:0]       w_g;
wire [15:0]       w_b;




// Mapping to DPHY TX
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


// assign mipi_dphy_tx_inst1_ESC_CLK = esc_clk;
assign mipi_dphy_tx_inst1_RESET_N = i_arstn;
assign mipi_dphy_tx_inst1_PLL_SSC_EN = 0;

assign TxStopStateC = mipi_dphy_tx_inst1_STOPSTATE_CLK;
assign mipi_dphy_tx_inst1_TX_REQUEST_HS = TxRequestHSc;
assign mipi_dphy_tx_inst1_TX_ULPS_CLK = TxUlpsClk;
assign mipi_dphy_tx_inst1_TX_ULPS_EXIT = TxUlpsExitClk;
assign TxUlpsActiveClkNot = mipi_dphy_tx_inst1_TX_ULPS_ACTIVE_CLK_NOT;

assign mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN0 = TxUlpsEsc[0];
assign mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN1 = TxUlpsEsc[1];
assign mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN2 = TxUlpsEsc[2];
assign mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN3 = TxUlpsEsc[3];
assign mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN0 = TxUlpsExit[0];
assign mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN1 = TxUlpsExit[1];
assign mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN2 = TxUlpsExit[2];
assign mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN3 = TxUlpsExit[3];
assign mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN0 = TxRequestEsc[0];
assign mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN1 = TxRequestEsc[1];
assign mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN2 = TxRequestEsc[2];
assign mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN3 = TxRequestEsc[3];
assign mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN0 = TxSkewCalHS[0];
assign mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN1 = TxSkewCalHS[1];
assign mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN2 = TxSkewCalHS[2];
assign mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN3 = TxSkewCalHS[3];
assign TxStopStateD[0] = mipi_dphy_tx_inst1_STOPSTATE_LAN0;
assign TxStopStateD[1] = mipi_dphy_tx_inst1_STOPSTATE_LAN1;
assign TxStopStateD[2] = mipi_dphy_tx_inst1_STOPSTATE_LAN2;
assign TxStopStateD[3] = mipi_dphy_tx_inst1_STOPSTATE_LAN3;

assign TxUlpsActiveNot[0] = mipi_dphy_tx_inst1_TX_ULPS_ACTIVE_NOT_LAN0;
assign TxUlpsActiveNot[1] = mipi_dphy_tx_inst1_TX_ULPS_ACTIVE_NOT_LAN1;
assign TxUlpsActiveNot[2] = mipi_dphy_tx_inst1_TX_ULPS_ACTIVE_NOT_LAN2;
assign TxUlpsActiveNot[3] = mipi_dphy_tx_inst1_TX_ULPS_ACTIVE_NOT_LAN3;
assign TxReadyHS[0] = mipi_dphy_tx_inst1_TX_READY_HS_LAN0;
assign TxReadyHS[1] = mipi_dphy_tx_inst1_TX_READY_HS_LAN1;
assign TxReadyHS[2] = mipi_dphy_tx_inst1_TX_READY_HS_LAN2;
assign TxReadyHS[3] = mipi_dphy_tx_inst1_TX_READY_HS_LAN3;

assign mipi_dphy_tx_inst1_TX_DATA_HS_LAN0 = TxDataHS0;
assign mipi_dphy_tx_inst1_TX_DATA_HS_LAN1 = TxDataHS1;
assign mipi_dphy_tx_inst1_TX_DATA_HS_LAN2 = TxDataHS2;
assign mipi_dphy_tx_inst1_TX_DATA_HS_LAN3 = TxDataHS3;
assign mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN0 = TxRequestHS[0];
assign mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN1 = TxRequestHS[1];
assign mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN2 = TxRequestHS[2];
assign mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN3 = TxRequestHS[3];
assign mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN0 = TxReqValidHS0[1];
assign mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN1 = TxReqValidHS1[1];
assign mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN2 = TxReqValidHS2[1];
assign mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN3 = TxReqValidHS3[1];


wire       w_fb_clk_arstn;
wire       w_fb_clk_arst;
wire       w_dphy_byte_clk_arstn;
wire       w_dphy_byte_clk_arst;
wire       w_esc_clk_arstn;
wire       w_esc_clk_arst;
wire       w_confdone;
wire       i_fb_clk_rst_n;

wire cfg_mipi_reset_n;
wire		       w_mipi_rx_vs;
wire		       w_mipi_rx_hs;
wire	       w_mipi_rx_de;
wire	[63:0]			w_mipi_rx_data	;
wire check_fail;
wire frame_stable;
wire  check_pass;
//===================================================================
//reset_ctrl
//===================================================================
assign pll_mipi_rstn        = i_arstn;
assign pll_byteclk_rstn     = i_arstn;
assign pll0_rstn     		= i_arstn;
assign lcd_power_en         = i_arstn;
assign pll_locked  = pll_mipi_locked & pll_byteclk_locked&pll0_locked;
// reg [26:0]	r_rst_cnt;
// always@(negedge i_arstn or posedge i_fb_clk)
// begin
	// if ( ~i_arstn)
	// begin
		// r_rst_cnt			<= {20{1'b0}};
		// r_lcd_rstn			<= 1'b0;
	// end
	// else
	// begin		
		// if (~r_rst_cnt[26])
		// begin
			// r_rst_cnt	<= r_rst_cnt + 1'b1;
			
			// if (r_rst_cnt[26])
				// r_lcd_rstn	<= 1'b1;
			// else
				// r_lcd_rstn	<= 1'b0;
		// end
		// else
			// r_lcd_rstn	<= 1'b1;
	// end
// end
reset_ctrl #(
    .NUM_RST       (6),
    .CYCLE         (2),
    .IN_RST_ACTIVE (6'b000000),
    .OUT_RST_ACTIVE(6'b101010)
) inst_reset_ctrl (
    .i_arst({{2{i_fb_clk_rst_n}},{4{pll_locked}}}),
    .i_clk({
        {2{i_fb_clk}}, {2{esc_clk}}, {2{mipi_dphy_tx_pclk}}
    }),
    .o_srst({
        w_fb_clk_arst,
        w_fb_clk_arstn,
        w_esc_clk_arst,
        w_esc_clk_arstn,
        w_dphy_byte_clk_arst,
        w_dphy_byte_clk_arstn
    })
);

led_ctrl # (
    .LED_NUM(4),
    .LED_TIME(30000000)
  )
  led_ctrl_inst (
    .clk(i_sysclk_div2),
    .rst_n(pll_locked),
    .en({2'b00,check_pass,frame_stable}),
    .led(led)
  );

  wire [63:0]	yuv_data;
  wire			pack_de;
  wire			data_de;
video_pattern_gen #(
	.HSP	(HSP),
	.HBP	(HBP),
	.HFP	(HFP),
	.HACT	(HACT),
	.VSP		(VSP),
	.VBP	(VBP),
	.VFP	(VFP),
	.VACT	(VACT)
)
u_yuv_gen(
.rst_n		(w_fb_clk_arstn),
.clk		(i_sysclk_div2),
.vsync_r	(w_vs)	,
.hsync_r	(w_hs),
.	de_r	(w_valid),
.pixel_data    (yuv_data)
	
);

//==============================================================
//lcd reset
//==============================================================
localparam RESET_COUNT          = 22;
localparam RESET_LCD            = 22'd100;
localparam RELEASE_RESET_LCD    = 22'd1000;
reg         r_lcd_rstn = 1;
reg  [RESET_COUNT-1:0] r_rst_cnt = 0;
always @(posedge i_fb_clk or negedge i_arstn )
begin
    if(!i_arstn) 
        r_rst_cnt <= 'd0;
    else if( pll_locked ) begin
        if( r_rst_cnt != {RESET_COUNT{1'b1}})
            r_rst_cnt <= r_rst_cnt + 1'b1;
    end else 
        r_rst_cnt   <= 'd0;
end
always @(posedge i_fb_clk or negedge i_arstn) 
begin
    if (!i_arstn)
        r_lcd_rstn  <= 1'b1;
    else if (pll_locked) begin
        if (~(&r_rst_cnt)) begin
            if (r_rst_cnt == RESET_LCD)
                r_lcd_rstn <= 1'b0;
            else if (r_rst_cnt == RELEASE_RESET_LCD) 
                r_lcd_rstn <= 1'b1;
        end 
    end else 
        r_lcd_rstn  <= 1'b1;
end
assign o_lcd_rstn = ~r_lcd_rstn;
assign i_fb_clk_rst_n = r_rst_cnt[RESET_COUNT-1];


mipi_csi_tx_2p5g u_mipi_csi_tx_2p5g
(
    .clk_byte_HS        (mipi_dphy_tx_pclk  ),
    .reset_byte_HS_n    (w_dphy_byte_clk_arstn),

    .clk_pixel          (i_sysclk_div2),
    .reset_pixel_n      (w_dphy_byte_clk_arstn),//(w_confdone),
    
    .clk_esc            (esc_clk),
    .reset_esc_n        (i_arstn),

    .irq ( irq ),
    
    .frame_num (  ),
    .hsync_vc0 ( w_hs ),
    .hsync_vc1 (  ),
    .hsync_vc3 (  ),
    
    .vsync_vc0 ( w_vs ),
    .vsync_vc1 (  ),
    .vsync_vc2 (  ),
    .vsync_vc3 (  ),

    
    .line_num (  ),
    .haddr ( HACT ),
    // .pixel_data ( {
        // 16'b0,
        // w_b[15:8],
        // w_g[15:8],
        // w_r[15:8],
        // w_b[7:0],
        // w_g[7:0],
        // w_r[7:0]
    // } ),
	.pixel_data(yuv_data),
    .pixel_data_valid ( w_valid ),
    .datatype (DATATYPE ),


    //AXI4-Lite Interface
    .axi_clk            (i_fb_clk),
    .axi_reset_n        (w_fb_clk_arstn),
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
    
    .TxUlpsClk          ( TxUlpsClk ), //
    .TxUlpsExitClk      ( TxUlpsExitClk ),//
    .TxUlpsActiveClkNot ( TxUlpsActiveClkNot ),//
    .TxUlpsEsc          ( TxUlpsEsc ),//
    .TxSkewCalHS        ( TxSkewCalHS ),//
    .TxUlpsExit         ( TxUlpsExit ),//
    .TxRequestEsc       ( TxRequestEsc ),//
    .TxStopStateD       ( TxStopStateD ),//
    .TxStopStateC       ( TxStopStateC ),//
    .TxUlpsActiveNot    ( TxUlpsActiveNot ),//
    .TxReadyHS          ( TxReadyHS ),//
    .TxRequestHS        ( TxRequestHS ), //
    .TxRequestHSc       ( TxRequestHSc ),//
    .TxDataHS0 ( TxDataHS0 ),//
    .TxDataHS1 ( TxDataHS1 ),
    .TxDataHS2 ( TxDataHS2 ),
    .TxDataHS3 ( TxDataHS3 ),
    .TxDataHS4 ( TxDataHS4 ),
    .TxDataHS5 ( TxDataHS5 ),
    .TxDataHS6 ( TxDataHS6 ),
    .TxDataHS7 ( TxDataHS7 ),
    .TxReqValidHS0 ( TxReqValidHS0 ),//
    .TxReqValidHS1 ( TxReqValidHS1 ),
    .TxReqValidHS2 ( TxReqValidHS2 ),
    .TxReqValidHS3 ( TxReqValidHS3 ),
    .TxReqValidHS4 ( TxReqValidHS4 ),
    .TxReqValidHS5 ( TxReqValidHS5 ),
    .TxReqValidHS6 ( TxReqValidHS6 ),
    .TxReqValidHS7 ( TxReqValidHS7 )
    
);

//========================================================================== 
// csi 
//========================================================================== 



endmodule
