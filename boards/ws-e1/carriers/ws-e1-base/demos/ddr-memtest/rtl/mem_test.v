module test_ddr_start (

output [5:0] o_led,
input  [1:0] i_sw,

input i_sys_clk,
input axi0_ACLK,
output axi0_ARESETn,
output axi0_ARQOS,
output axi0_AWQOS,
output [5:0] axi0_AWID,
output [32:0] axi0_AWADDR,
output [7:0] axi0_AWLEN,
output [2:0] axi0_AWSIZE,
output [1:0] axi0_AWBURST,
output axi0_AWVALID,
output [3:0] axi0_AWCACHE,
output axi0_AWCOBUF,
output axi0_AWLOCK,
output axi0_AWAPCMD,
output axi0_AWALLSTRB,
output [5:0] axi0_ARID,
output [32:0] axi0_ARADDR,
output [7:0] axi0_ARLEN,
output [2:0] axi0_ARSIZE,
output [1:0] axi0_ARBURST,
output axi0_ARVALID,
output axi0_ARLOCK,
output axi0_ARAPCMD,
output axi0_WLAST,
output axi0_WVALID,
output [511:0] axi0_WDATA,
output [63:0] axi0_WSTRB,
output axi0_BREADY,
output axi0_RREADY,
input axi0_AWREADY,
input axi0_ARREADY,
input axi0_WREADY,
input [5:0] axi0_BID,
input [1:0] axi0_BRESP,
input axi0_BVALID,
input [5:0] axi0_RID,
input axi0_RLAST,
input axi0_RVALID,
input [511:0] axi0_RDATA,
input [1:0] axi0_RRESP,

input axi1_ACLK,
output axi1_ARESETn,
output axi1_ARQOS,
output axi1_AWQOS,
output [5:0] axi1_AWID,
output [32:0] axi1_AWADDR,
output [7:0] axi1_AWLEN,
output [2:0] axi1_AWSIZE,
output [1:0] axi1_AWBURST,
output axi1_AWVALID,
output [3:0] axi1_AWCACHE,
output axi1_AWCOBUF,
output axi1_AWLOCK,
output axi1_AWAPCMD,
output axi1_AWALLSTRB,
output [5:0] axi1_ARID,
output [32:0] axi1_ARADDR,
output [7:0] axi1_ARLEN,
output [2:0] axi1_ARSIZE,
output [1:0] axi1_ARBURST,
output axi1_ARVALID,
output axi1_ARLOCK,
output axi1_ARAPCMD,
output axi1_WLAST,
output axi1_WVALID,
output [511:0] axi1_WDATA,
output [63:0] axi1_WSTRB,
output axi1_BREADY,
output axi1_RREADY,
input axi1_AWREADY,
input axi1_ARREADY,
input axi1_WREADY,
input [5:0] axi1_BID,
input [1:0] axi1_BRESP,
input axi1_BVALID,
input [5:0] axi1_RID,
input axi1_RLAST,
input axi1_RVALID,
input [511:0] axi1_RDATA,
input [1:0] axi1_RRESP,


//Startup Sequencer Signals
    output  ddr_inst_CFG_RST,	//Active-high DDR configuration controller reset.
	output  ddr_inst_CFG_START,	//Start the DDR configuration controller.
	input   ddr_inst_CFG_DONE,	//Indicates the controller configuration is done
	output  ddr_inst_CFG_SEL,	//To select whether to use internal DDR configuration controller or user register ports for configuration:
								//0: Use internal configuration controller.
								//1: Use register configuration ports (cfg_rst, cfg_start, cfg_done will be disabled).

input sys_pll_lock,
input ddr_pll_lock,
output sys_pll_rstn,
output ddr_pll_rstn

/*,

//config
 

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
*/

);

assign o_led[5] = (cfg_st == CFG_DONE);
assign o_led[4] = done_0;
assign o_led[3] = done_1;
assign o_led[2] = (~fail_0) & done_0;
assign o_led[1] = (~fail_1) & done_1;
assign o_led[0] = (~fail_1) & done_1 & (~fail_0) & done_0;


wire ddr_cfg_ok;


/////////////////////////////////////////////////////////////////////////////
//ddr4 config
localparam [1:0]    IDLE        = 2'b00,
                    CFG_START   = 2'b01,
                    CFG_DONE    = 2'b11;

reg [1:0]   cfg_st, cfg_next;
reg [20:0]   cfg_count;
//Reset and PLL
wire        io_asyncResetn;
wire        mem_test_start;
wire        mem_test_start_axi0;
wire        mem_test_start_axi1;


/////////////////////////////////////////////////////////////////////////////
//Reset and PLL

assign sys_pll_rstn 	= 1'b1;//i_sw[0];
assign ddr_pll_rstn     = 1'b1;//i_sw[0];

assign io_asyncResetn =  sys_pll_lock & ddr_pll_lock;
assign mem_test_start=   ddr_cfg_ok ; 

//ddr4 config
always@(posedge i_sys_clk or negedge io_asyncResetn)
begin
   
    if(!io_asyncResetn)
    begin
        cfg_st <= IDLE;
        cfg_count <= 'h0;
    end 
    else
    begin
            cfg_st <= cfg_next;

            if (cfg_st == IDLE)
                cfg_count <= cfg_count + 1'b1;
            else 
                cfg_count <= 'h0;
    end 
        
end

always@(*)
begin
    cfg_next = cfg_st;
    case(cfg_st)
    IDLE:
    begin
        if(&cfg_count)
            cfg_next = CFG_START;
        else
            cfg_next = IDLE;
    end
    CFG_START:
    begin
        if(ddr_inst_CFG_DONE)
            cfg_next = CFG_DONE;
        else
            cfg_next = CFG_START;
    end
    CFG_DONE:
        cfg_next = CFG_DONE;
    default:
        cfg_next = IDLE;
    endcase
end

assign ddr_inst_CFG_START    = (cfg_st != IDLE);
//assign cfg_ok       = (cfg_st == CFG_DONE);
assign ddr_cfg_ok   = (cfg_st == CFG_DONE);
assign ddr_inst_CFG_RST    = (cfg_st == IDLE);
assign ddr_inst_CFG_SEL      = 1'b0;

assign axi0_ARESETn = ddr_cfg_ok;
assign axi1_ARESETn = ddr_cfg_ok;




        reset
		#(
			.IN_RST_ACTIVE	("LOW"),
			.OUT_RST_ACTIVE	("LOW"),
			.CYCLE			(10)
		)
		inst_start_axi0
		(
			.i_arst	(mem_test_start),
			.i_clk	(axi0_ACLK), 
			.o_srst	(mem_test_start_axi0)
		);	
        
        
        reset
		#(
			.IN_RST_ACTIVE	("LOW"),
			.OUT_RST_ACTIVE	("LOW"),
			.CYCLE			(10)
		)
		inst_start_axi1
		(
			.i_arst	(mem_test_start),
			.i_clk	(axi1_ACLK), 
			.o_srst	(mem_test_start_axi1)
		);	



wire cfg_sel_vio, cfg_start_vio, cfg_reset_vio;


wire done_0, fail_0, done_1, fail_1;


wire [511:0] rdata_obs0, rdata_obs1, rdata_exp0, rdata_exp1;
wire test_rstn;
wire wen, ren;
memory_checker #(.START_ADDR(33'h000000000), .STOP_ADDR(33'h000201900)) checker0(

        .axi_clk(axi0_ACLK),
        .rstn(io_asyncResetn),
        .start(mem_test_start_axi0),
        .awid(axi0_AWID),
        .awaddr(axi0_AWADDR),
        .awlen(axi0_AWLEN),
        .awsize(axi0_AWSIZE),
        .awburst(axi0_AWBURST),
        .awcache(axi0_AWCACHE),
        .awlock(axi0_AWLOCK),
        .awvalid(axi0_AWVALID),
        .awcobuf(axi0_AWCOBUF),
        .awapcmd(axi0_AWAPCMD),
        .awallstrb(axi0_AWALLSTRB),
        .awready(axi0_AWREADY),
        .awqos(axi0_AWQOS),
        .arid(axi0_ARID),
        .araddr(axi0_ARADDR),
        .arlen(axi0_ARLEN),
        .arsize(axi0_ARSIZE),
        .arburst(axi0_ARBURST),
        .arlock(axi0_ARLOCK),
        .arvalid(axi0_ARVALID),
        .arapcmd(axi0_ARAPCMD),
        .arready(axi0_ARREADY),
        .arqos(axi0_ARQOS),
        .atype(),
        .wdata(axi0_WDATA),
        .wstrb(axi0_WSTRB),
        .wlast(axi0_WLAST),
        .wvalid(axi0_WVALID),
        .wready(axi0_WREADY),
        .rid(axi0_RID),
        .rdata(axi0_RDATA),
        .rlast(axi0_RLAST),
        .rvalid(axi0_RVALID),
        .rready(axi0_RREADY),
        .rresp(axi0_RRESP),
        .bid(axi0_BID),
        .bvalid(axi0_BVALID),
        .bready(axi0_BREADY),
        .fail(fail_0),
        .done(done_0),
        .rdata_obs(rdata_obs0),
        .rdata_exp(rdata_exp0)
        
);

memory_checker #(.START_ADDR(33'h001000000), .STOP_ADDR(33'h002001900)) checker1 (

        .axi_clk(axi1_ACLK),
        .rstn(io_asyncResetn),
        .start(mem_test_start_axi1),
        .awid(axi1_AWID),
        .awaddr(axi1_AWADDR),
        .awlen(axi1_AWLEN),
        .awsize(axi1_AWSIZE),
        .awburst(axi1_AWBURST),
        .awcache(axi1_AWCACHE),
        .awlock(axi1_AWLOCK),
        .awvalid(axi1_AWVALID),
        .awcobuf(axi1_AWCOBUF),
        .awapcmd(axi1_AWAPCMD),
        .awallstrb(axi1_AWALLSTRB),
        .awready(axi1_AWREADY),
        .awqos(axi1_AWQOS),
        .arid(axi1_ARID),
        .araddr(axi1_ARADDR),
        .arlen(axi1_ARLEN),
        .arsize(axi1_ARSIZE),
        .arburst(axi1_ARBURST),
        .arlock(axi1_ARLOCK),
        .arvalid(axi1_ARVALID),
        .arapcmd(axi1_ARAPCMD),
        .arready(axi1_ARREADY),
        .arqos(axi1_ARQOS),
        .atype(),
        .wdata(axi1_WDATA),
        .wstrb(axi1_WSTRB),
        .wlast(axi1_WLAST),
        .wvalid(axi1_WVALID),
        .wready(axi1_WREADY),
        .rid(axi1_RID),
        .rdata(axi1_RDATA),
        .rlast(axi1_RLAST),
        .rvalid(axi1_RVALID),
        .rready(axi1_RREADY),
        .rresp(axi1_RRESP),
        .bid(axi1_BID),
        .bvalid(axi1_BVALID),
        .bready(axi1_BREADY),
        .fail(fail_1),
        .done(done_1),
        .rdata_obs(rdata_obs1),
        .rdata_exp(rdata_exp1)
);
/*
wire regStart;
wire [14:0] regARADDR_obs;
wire [31:0] regRDATA_obs;
edb_top edb_top_inst (
    .bscan_CAPTURE    ( jtag_inst1_CAPTURE ),
    .bscan_DRCK       ( jtag_inst1_DRCK ),
    .bscan_RESET      ( jtag_inst1_RESET ),
    .bscan_RUNTEST    ( jtag_inst1_RUNTEST ),
    .bscan_SEL        ( jtag_inst1_SEL ),
    .bscan_SHIFT      ( jtag_inst1_SHIFT ),
    .bscan_TCK        ( jtag_inst1_TCK ),
    .bscan_TDI        ( jtag_inst1_TDI ),
    .bscan_TMS        ( jtag_inst1_TMS ),
    .bscan_UPDATE     ( jtag_inst1_UPDATE ),
    .bscan_TDO        ( jtag_inst1_TDO ),
    .vio0_clk       ( axi0_ACLK ),
    .vio0_axi0_rdata0 (rdata_obs0[255:0]),
    .vio0_axi0_rdata1 (rdata_obs0[511:256]),
    .vio0_axi1_rdata0 (rdata_obs1[255:0]),
    .vio0_axi1_rdata1 (rdata_obs1[511:256]),
    .vio0_test_stat (fail),
    .vio0_test_done (done),
    .vio0_regRDATA (regRDATA_obs),
    .vio0_cfg_done (cfg_done),
    .vio0_regARADDR (regARADDR_obs),
    .vio0_regstart (regStart),
    .vio0_cfg_sel (cfg_sel_vio),
    .vio0_test_rstn(test_rstn),
    .vio0_wen(wen),
    .vio0_ren(ren),
	.vio0_ddr_pll_lock(ddr_pll_lock),
    .vio0_cfg_reset(cfg_reset_vio),
    .vio0_cfg_start(cfg_start_vio),
    .vio0_rdata0_exp0(rdata_exp0[255:0]),
    .vio0_rdata0_exp1(rdata_exp0[511:256]),
    .vio0_rdata1_exp0(rdata_exp1[255:0]),
    .vio0_rdata1_exp1(rdata_exp1[511:256])
    
);*/

endmodule
