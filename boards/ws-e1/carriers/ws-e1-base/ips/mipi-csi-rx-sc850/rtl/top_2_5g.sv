
// synopsys translate_off
`timescale 1 ns / 1 ps													
// synopsys translate_on

module top #(   //csi2 example design
    parameter NUM_DATA_LANE = 4,
    parameter PIXEL_BIT  = 24,
    parameter PACK_BIT   = 48,
    parameter HSA		 = 5,  //minimum value is pixel cnt value, eg: RGB888 - 2
    parameter HBP		 = 5,   //minimum value is pixel cnt value, eg: RGB888 - 2
    parameter HFP		 = 1024,
    parameter HACT_CNT	 = 1920,
    parameter VSA		 = 1,
    parameter VBP		 = 1,
    parameter VFP		 = 100,
    parameter VACT_CNT	 = 1080,
    parameter DATATYPE = 6'h24     //24 - RGB888
)(
input 			mipi_clk,	//100MHz
input			pixel_clk,	//50Mhz
input           cfg_clk,
input			pll0_locked,
input			pll1_locked,


//======================= MIPI RX =====================//
input	logic       mipi_dphy_rx_clk_CLKOUT,   //312.5MHz from RX CLK lane for HS Byte clk
//output  logic       mipi_dphy_rx_inst2_CAL_CLK, // do not need to output to DPHY, will connect direct from pll.
output  logic       mipi_dphy_rx_inst2_RESET,   //active low async reset to RX DPHY
output  logic       mipi_dphy_rx_inst2_RST0_N,  // active low async reset to FIFO

input 	logic		mipi_dphy_rx_inst2_ULPS_CLK_ACTIVEN,
input   logic       mipi_dphy_rx_inst2_ULPS_CLK_ENTER,

input   logic		mipi_dphy_rx_inst2_ESC_LAN0_CLK,
input   logic		mipi_dphy_rx_inst2_ESC_LAN1_CLK,
input   logic		mipi_dphy_rx_inst2_ESC_LAN2_CLK,
input   logic		mipi_dphy_rx_inst2_ESC_LAN3_CLK,
input	logic		mipi_dphy_rx_inst2_LINESTATE_LAN0_ERROR,
input	logic		mipi_dphy_rx_inst2_LINESTATE_LAN1_ERROR,
input	logic		mipi_dphy_rx_inst2_LINESTATE_LAN2_ERROR,
input	logic		mipi_dphy_rx_inst2_LINESTATE_LAN3_ERROR,
input  	logic		mipi_dphy_rx_inst2_STOPSTATE_LAN0,
input  	logic		mipi_dphy_rx_inst2_STOPSTATE_LAN1,
input  	logic		mipi_dphy_rx_inst2_STOPSTATE_LAN2,
input  	logic		mipi_dphy_rx_inst2_STOPSTATE_LAN3,
input 	logic		mipi_dphy_rx_inst2_ESC_LAN0_ERROR,
input 	logic		mipi_dphy_rx_inst2_ESC_LAN1_ERROR,
input 	logic		mipi_dphy_rx_inst2_ESC_LAN2_ERROR,
input 	logic		mipi_dphy_rx_inst2_ESC_LAN3_ERROR,
input 	logic		mipi_dphy_rx_inst2_HS_LAN0_VALID,
input 	logic		mipi_dphy_rx_inst2_HS_LAN1_VALID,
input 	logic		mipi_dphy_rx_inst2_HS_LAN2_VALID,
input 	logic		mipi_dphy_rx_inst2_HS_LAN3_VALID,
input   logic 	[15:0]   mipi_dphy_rx_inst2_HS_LAN0_DATA,
input   logic 	[15:0]   mipi_dphy_rx_inst2_HS_LAN1_DATA,
input   logic 	[15:0]   mipi_dphy_rx_inst2_HS_LAN2_DATA,
input   logic 	[15:0]   mipi_dphy_rx_inst2_HS_LAN3_DATA,
input	logic		mipi_dphy_rx_inst2_HS_LAN0_SKEWCAL,
input	logic		mipi_dphy_rx_inst2_HS_LAN1_SKEWCAL,
input	logic		mipi_dphy_rx_inst2_HS_LAN2_SKEWCAL,
input	logic		mipi_dphy_rx_inst2_HS_LAN3_SKEWCAL,
input	logic		mipi_dphy_rx_inst2_HS_LAN0_SYNC,
input	logic		mipi_dphy_rx_inst2_HS_LAN1_SYNC,
input	logic		mipi_dphy_rx_inst2_HS_LAN2_SYNC,
input	logic		mipi_dphy_rx_inst2_HS_LAN3_SYNC,
input	logic		mipi_dphy_rx_inst2_HS_LAN0_SOTSYNC_ERROR,
input	logic		mipi_dphy_rx_inst2_HS_LAN1_SOTSYNC_ERROR,
input	logic		mipi_dphy_rx_inst2_HS_LAN2_SOTSYNC_ERROR,
input	logic		mipi_dphy_rx_inst2_HS_LAN3_SOTSYNC_ERROR,
input   logic    	mipi_dphy_rx_inst2_ULPS_LAN0_ACTIVEN,
input   logic    	mipi_dphy_rx_inst2_ULPS_LAN1_ACTIVEN,
input   logic    	mipi_dphy_rx_inst2_ULPS_LAN2_ACTIVEN,
input   logic    	mipi_dphy_rx_inst2_ULPS_LAN3_ACTIVEN,
input   logic		mipi_dphy_rx_inst2_ULPS_LAN0_ENTER,
input   logic		mipi_dphy_rx_inst2_ULPS_LAN1_ENTER,
input   logic		mipi_dphy_rx_inst2_ULPS_LAN2_ENTER,
input   logic		mipi_dphy_rx_inst2_ULPS_LAN3_ENTER,

//============== SC535 CONFIG ==============//
input	clk_50m,

output	trig_o	,
output	scl_o	,
output	scl_oe	,
input	scl_i	,
output	sda_o	,
output	sda_oe	,
input	sda_i	

);


assign  mipi_dphy_rx_data0_RST   = 1'b0;
assign  mipi_dphy_rx_data1_RST   = 1'b0;
assign  mipi_dphy_rx_data2_RST   = 1'b0;
assign  mipi_dphy_rx_data3_RST   = 1'b0;


logic	reset_n;
assign  reset_n = pll0_locked&pll1_locked;

logic i_reset_pixel_n;
logic rx_out_valid_1P, rx_out_hs_1P;
logic mipi_clk_reset_n, mipi_dphy_rx_reset_byte_HS_n, reset_pixel_n;
logic [5:0] datatype;
logic [15:0] word_count;

assign mipi_dphy_rx_inst2_RESET 	= reset_n;
assign mipi_dphy_rx_inst2_RST0_N 	= reset_n;
assign mipi_dphy_rx_inst2_CAL_CLK 	= cfg_clk;


logic [18:0] wait_cnt;
always @ (posedge mipi_clk or negedge reset_n) begin
    if (~reset_n) begin
        i_reset_pixel_n <= 1'b0;
		wait_cnt		<= 0;
    end
    else if (wait_cnt[18]) begin
        i_reset_pixel_n <= 1'b1;
		wait_cnt		<= wait_cnt;
    end	else begin
		wait_cnt		<= wait_cnt + 1;	
	end
end





reset
#(
	.IN_RST_ACTIVE	("LOW"),
	.OUT_RST_ACTIVE	("LOW"),
	.CYCLE			(3)
)
inst_rx_byteclk_rst
(
	.i_arst	(reset_n),
	.i_clk	(mipi_dphy_rx_clk_CLKOUT),
	.o_srst	(mipi_dphy_rx_reset_byte_HS_n)
);


reset
#(
	.IN_RST_ACTIVE	("LOW"),
	.OUT_RST_ACTIVE	("LOW"),
	.CYCLE			(3)
)
inst_pixel_clk_rst
(
	.i_arst	(reset_n),
	// .i_arst	(i_reset_pixel_n),
	.i_clk	(pixel_clk),
	.o_srst	(reset_pixel_n)
);





////////////////////////MIPI RX//////////////////////
logic rx_out_valid, rx_out_hs, rx_out_vs;
logic [PACK_BIT-1:0] rx_out_data;

logic	[5:0]	r_rx_axi_araddr_1P;
logic			r_rx_axi_arvalid_1P;
logic			w_rx_axi_arready;
logic	[31:0]	w_rx_axi_rdata;
logic			w_rx_axi_rvalid;
logic			r_rx_axi_rready_1P;

// Mapping to DPHY RX IF
logic RxUlpsClkNot;
logic [NUM_DATA_LANE-1:0]	RxErrEsc;
logic [NUM_DATA_LANE-1:0] 	RxErrControl;
logic [NUM_DATA_LANE-1:0] 	RxErrSotSyncHS;
logic [NUM_DATA_LANE-1:0]	RxClkEsc;
logic [NUM_DATA_LANE-1:0]	RxUlpsEsc;
logic [NUM_DATA_LANE-1:0]	RxUlpsActiveNot;
logic [NUM_DATA_LANE-1:0]	RxSkewCalHS;
logic [NUM_DATA_LANE-1:0]	RxStopState;
logic [NUM_DATA_LANE-1:0] 	RxValidHS;
logic [NUM_DATA_LANE-1:0]  	RxSyncHS;
logic [NUM_DATA_LANE-1:0][15:0]	RxDataHS;

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

hard_csi_rx  inst_csi2_rx_top
(
    .reset_n              	(reset_n),
    .clk                    (mipi_clk),
    .reset_byte_HS_n        (mipi_dphy_rx_reset_byte_HS_n),
    .clk_byte_HS            (mipi_dphy_rx_clk_CLKOUT),
    .reset_pixel_n        	(reset_pixel_n),
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
    .axi_reset_n        		(reset_n),
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

    .hsync_vc0                  	(rx_out_hs),
    .hsync_vc1                  	(),
    .hsync_vc2                  	(),
    .hsync_vc3                  	(),
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
    .vsync_vc0                  	(rx_out_vs),
    .vsync_vc1                  	(),
    .vsync_vc2                 	 	(),
    .vsync_vc3                  	(),
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

    .vc                                 (),
    .vcx                                (),
    .word_count                     	(word_count),
    .shortpkt_data_field				(),
    .datatype                       	(datatype),        // RAW8
    .pixel_per_clk              		(),
    .pixel_data                     	(rx_out_data),
    .pixel_data_valid   				(rx_out_valid),
    .irq                                ()

);
//========== trig =============//
localparam	CLK_FREQ 	 = 50000000;
localparam	FPS 		 = 30;
localparam	FPS_INTERVAL = CLK_FREQ/FPS;

assign	trig_o 		= (fps_cnt>100)&&(fps_cnt<500);
//assign	fsync_o 	= (fps_cnt>100)&&(fps_cnt<500);
reg [24:0] fps_cnt;	
always@(posedge clk_50m)
	if(~reset_n)	
		fps_cnt	<= 0;
	else if(fps_cnt == FPS_INTERVAL-1)
		fps_cnt <= 0;
	else	
		fps_cnt <= fps_cnt + 1;
//=================== I2c ====================//
localparam 	FREQ_I2C_REF = 50000000;
localparam  RAM_INIT_FILE = "sc850sl_init.mem";

logic init_done;
smartsens_init #(	
	.FREQ_I2C_REF (FREQ_I2C_REF),	
	.RAM_INIT_FILE (RAM_INIT_FILE) 
)smartsens_init(
.clk_i2c_ref	(clk_50m	),
.clk_sensor_ref	(	),
.rstn			(reset_n	),

.rst_o			(		),
.pwdn_o			(		),
.xclk_hi_o		(	),
.xclk_lo_o		(	),

.scl_o			(scl_o	),
.scl_oe			(scl_oe	),
.scl_i			(scl_i	),
.sda_o			(sda_o	),
.sda_oe			(sda_oe	),
.sda_i			(sda_i	),

.init_done_o	(init_done)
);
logic [12:0] 	pcnt,lcnt;
logic			rx_out_hs_raise;
logic			rx_out_hs_d0;
assign 			rx_out_hs_raise = rx_out_hs&(~rx_out_hs_d0);
always@(posedge pixel_clk)
	rx_out_hs_d0	<= rx_out_hs;
always@(posedge pixel_clk)
	if(~rx_out_hs)			pcnt <= 0;
	else if(rx_out_valid)	pcnt <= pcnt + 1;
always@(posedge pixel_clk)
	if(~rx_out_vs)			lcnt <= 0;
	else if(rx_out_hs_raise)lcnt <= lcnt + 1;
	


////////////////////////////////

localparam	s_idle			= 2'b00;
localparam	s_wait_arready	= 2'b01;
localparam	s_wait_rvalid	= 2'b10;

reg		[1:0]	r_rx_dbg_fsm_1P;
reg		[14:0]	r_rx_dbg_reg_1P	[0:15];

always@(negedge reset_n or posedge mipi_clk)
begin
	if (~reset_n)
	begin
		r_rx_dbg_fsm_1P		<= s_idle;
		r_rx_axi_arvalid_1P	<= 1'b0;
		r_rx_axi_araddr_1P	<= 6'b0;
		r_rx_axi_rready_1P	<= 1'b0;
	end
	else
	begin
		r_rx_axi_rready_1P	<= 1'b0;
		
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
					
					r_rx_dbg_reg_1P[r_rx_axi_araddr_1P[5:2]]	<= w_rx_axi_rdata[14:0];
/*					r_rx_axi_araddr_1P	<= r_rx_axi_araddr_1P+6'h10;
					if (r_rx_axi_araddr_1P == 6'h30)
						r_rx_axi_araddr_1P	<= 6'b0;
					
					r_rx_dbg_reg_1P[r_rx_axi_araddr_1P[5:4]]	<= w_rx_axi_rdata[14:0];*/
				end
			end
		endcase
	end
end

endmodule
