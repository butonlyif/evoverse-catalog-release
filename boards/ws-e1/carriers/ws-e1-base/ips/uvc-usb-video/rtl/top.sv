module top
(
	//pll0
	input					fx10_gpif_lvds_pclk,
	output					pll0_rstn,
	input					pll0_locked,
	//pll0
    input					clk_100m,
	output					pll1_rstn,
	input					pll1_locked,
	//pll ddr
	output					pll_ddr_rstn,
	
	input					fx10_spi_sck,
	input					fx10_spi_csn,
	input					fx10_spi_mosi,
	output					fx10_spi_miso,
	
	// FX10
	output         			fx10_gpif_m_oe_n_o,          // Reset pin, active low
	output         			fx10_gpif_m_pktend_n_o,      // PACKET END
	output [ 1:0]  			fx10_gpif_m_addr_o,          // Address
	output         			fx10_gpif_m_rd_req_n_o,      // Slave read
	input          			fx10_gpif_m_full_flag_i,     // DMA Full/Ready
	input          			fx10_gpif_m_par_flag_i,      // DMA Partial
	
	
	output[8-1:0]			fx10_gpif_lvds0_pclk_data,
	output[8-1:0]			fx10_gpif_lvds0_pctrl,
	output[8-1:0]			fx10_gpif_lvds0_pdata0,
	output[8-1:0]			fx10_gpif_lvds0_pdata1,
	output[8-1:0]			fx10_gpif_lvds0_pdata2,
	output[8-1:0]			fx10_gpif_lvds0_pdata3,
	output[8-1:0]			fx10_gpif_lvds0_pdata4,
	output[8-1:0]			fx10_gpif_lvds0_pdata5,
	output[8-1:0]			fx10_gpif_lvds0_pdata6,
	output[8-1:0]			fx10_gpif_lvds0_pdata7,
	
	output[8-1:0]			fx10_gpif_lvds1_pclk_data,
	output[8-1:0]			fx10_gpif_lvds1_pctrl,
	output[8-1:0]			fx10_gpif_lvds1_pdata0,
	output[8-1:0]			fx10_gpif_lvds1_pdata1,
	output[8-1:0]			fx10_gpif_lvds1_pdata2,
	output[8-1:0]			fx10_gpif_lvds1_pdata3,
	output[8-1:0]			fx10_gpif_lvds1_pdata4,
	output[8-1:0]			fx10_gpif_lvds1_pdata5,
	output[8-1:0]			fx10_gpif_lvds1_pdata6,
	output[8-1:0]			fx10_gpif_lvds1_pdata7,
	
	input					fx10_gpif_lvds0_ctl0,
	input					fx10_gpif_lvds0_ctl1,
	input					fx10_gpif_lvds0_ctl2,
	input					fx10_gpif_lvds0_ctl3,
	input					fx10_gpif_lvds0_ctl4,
	input					fx10_gpif_lvds0_ctl5,
	input					fx10_gpif_lvds0_ctl6,
	
	input					fx10_gpif_lvds1_ctl0,
	input					fx10_gpif_lvds1_ctl1,
	input					fx10_gpif_lvds1_ctl2,
	input					fx10_gpif_lvds1_ctl3,
	input					fx10_gpif_lvds1_ctl4,
	input					fx10_gpif_lvds1_ctl5,
	input					fx10_gpif_lvds1_ctl6,
	
	output					fx10_gpif_lvds0_clk_oe,
	output					fx10_gpif_lvds0_ctrl_oe,
	output					fx10_gpif_lvds0_data0_oe,
	output					fx10_gpif_lvds0_data1_oe,
	output					fx10_gpif_lvds0_data2_oe,
	output					fx10_gpif_lvds0_data3_oe,
	output					fx10_gpif_lvds0_data4_oe,
	output					fx10_gpif_lvds0_data5_oe,
	output					fx10_gpif_lvds0_data6_oe,
	output					fx10_gpif_lvds0_data7_oe,
	output					fx10_gpif_lvds1_clk_oe,
	output					fx10_gpif_lvds1_ctrl_oe,
	output					fx10_gpif_lvds1_data0_oe,
	output					fx10_gpif_lvds1_data1_oe,
	output					fx10_gpif_lvds1_data2_oe,
	output					fx10_gpif_lvds1_data3_oe,
	output					fx10_gpif_lvds1_data4_oe,
	output					fx10_gpif_lvds1_data5_oe,
	output					fx10_gpif_lvds1_data6_oe,
	output					fx10_gpif_lvds1_data7_oe,
	
	output					fx10_gpif_lvds0_clk_rst,
	output					fx10_gpif_lvds0_ctrl_rst,
	output					fx10_gpif_lvds0_data0_rst,
	output					fx10_gpif_lvds0_data1_rst,
	output					fx10_gpif_lvds0_data2_rst,
	output					fx10_gpif_lvds0_data3_rst,
	output					fx10_gpif_lvds0_data4_rst,
	output					fx10_gpif_lvds0_data5_rst,
	output					fx10_gpif_lvds0_data6_rst,
	output					fx10_gpif_lvds0_data7_rst,
	output					fx10_gpif_lvds1_clk_rst,
	output					fx10_gpif_lvds1_ctrl_rst,
	output					fx10_gpif_lvds1_data0_rst,
	output					fx10_gpif_lvds1_data1_rst,
	output					fx10_gpif_lvds1_data2_rst,
	output					fx10_gpif_lvds1_data3_rst,
	output					fx10_gpif_lvds1_data4_rst,
	output					fx10_gpif_lvds1_data5_rst,
	output					fx10_gpif_lvds1_data6_rst,
	output					fx10_gpif_lvds1_data7_rst

);
assign	pll0_rstn 		= 1'b1;
assign	pll1_rstn 		= 1'b1;
assign	pll_ddr_rstn	= 1'b1;
wire	pll_all_locked;
assign	pll_all_locked	= pll0_locked&pll1_locked;
wire	axis_clk					= clk_100m;
wire	axis_rst					= ~pll_all_locked;
wire	fx10_gpif_lvds_pclk_reset_n = pll_all_locked;
`define BAND1_COLOR_YUYV                32'h80ff80ff    // White
`define BAND2_COLOR_YUYV                32'h94ff00ff    // Yellow
`define BAND3_COLOR_YUYV                32'h1ac8bfc8    // Blue
`define BAND4_COLOR_YUYV                32'h4aca55ca    // Green
`define BAND5_COLOR_YUYV                32'hf3969f96    // Pink
`define BAND6_COLOR_YUYV                32'hff4c544c    // Red

reg[31:0] 	line_pixel_counter;
wire		axis_valid;
wire		axis_ready;
wire		axis_en;
reg[511:0]	axis_data;
always @(posedge axis_clk or posedge axis_rst)
begin
	if(axis_rst) begin
		line_pixel_counter <= 0;
	end	else if(axis_ready & axis_en & (line_pixel_counter  == (3840*2 / 64 - 1))) begin
		line_pixel_counter <= 0;
	end	else if(axis_ready & axis_en) begin
		line_pixel_counter <= line_pixel_counter + 1;
	end else begin
		line_pixel_counter <= line_pixel_counter;
	end
end
		
always @(posedge axis_clk or posedge axis_rst)
begin
	if(axis_rst) begin
		axis_data <= {16{`BAND1_COLOR_YUYV}};
	end	else if(line_pixel_counter < ((3840*2 / 64) * 1 /6)) begin
		axis_data <= {16{`BAND2_COLOR_YUYV}};
	end	else if(line_pixel_counter < ((3840*2 / 64) * 2 /6)) begin
		axis_data <= {16{`BAND3_COLOR_YUYV}};
	end	else if(line_pixel_counter < ((3840*2 / 64) * 3 /6)) begin
		axis_data <= {16{`BAND4_COLOR_YUYV}};
	end	else if(line_pixel_counter < ((3840*2 / 64) * 4 /6)) begin
		axis_data <= {16{`BAND5_COLOR_YUYV}};
	end	else if(line_pixel_counter < ((3840*2 / 64) * 5 /6)) begin
		axis_data <= {16{`BAND6_COLOR_YUYV}};
	end else begin
		axis_data <= {16{32'h80008000}} ;
	end
end
assign axis_valid = axis_ready;

localparam	DELAY_TIME = 100000000*3;
reg [31:0]	dly_cnt;
wire	dly_rstn = (dly_cnt == DELAY_TIME)?1'b1:1'b0;
always@(posedge clk_100m)
	if(~pll_all_locked)
		dly_cnt	<= 0;
	else if(dly_cnt < DELAY_TIME)
		dly_cnt	<= dly_cnt + 1;
		
uvc_top_ency uvc_top
(
    .clk_100m				(clk_100m		),
    .rstn_100m				(pll_all_locked&dly_rstn		),
	
	.fx10_spi_sck			(fx10_spi_sck	),
	.fx10_spi_csn			(fx10_spi_csn	),
	.fx10_spi_mosi			(fx10_spi_mosi	),
	.fx10_spi_miso			(fx10_spi_miso	),
	
	// FX10
	.fx10_gpif_m_oe_n_o		(fx10_gpif_m_oe_n_o		),          // Reset pin, active low
	.fx10_gpif_m_pktend_n_o	(fx10_gpif_m_pktend_n_o	),      // PACKET END
	.fx10_gpif_m_addr_o		(fx10_gpif_m_addr_o		),          // Address
	.fx10_gpif_m_rd_req_n_o	(fx10_gpif_m_rd_req_n_o	),      // Slave read
	.fx10_gpif_m_full_flag_i(fx10_gpif_m_full_flag_i),     // DMA Full/Ready
	.fx10_gpif_m_par_flag_i	(fx10_gpif_m_par_flag_i	),      // DMA Partial
	
	.fx10_gpif_lvds_pclk			(fx10_gpif_lvds_pclk		),
	.fx10_gpif_lvds_pclk_reset_n	(fx10_gpif_lvds_pclk_reset_n&dly_rstn),
	
	.fx10_gpif_lvds0_pclk_data		(fx10_gpif_lvds0_pclk_data	),
	.fx10_gpif_lvds0_pctrl			(fx10_gpif_lvds0_pctrl		),
	.fx10_gpif_lvds0_pdata0			(fx10_gpif_lvds0_pdata0		),
	.fx10_gpif_lvds0_pdata1			(fx10_gpif_lvds0_pdata1		),
	.fx10_gpif_lvds0_pdata2			(fx10_gpif_lvds0_pdata2		),
	.fx10_gpif_lvds0_pdata3			(fx10_gpif_lvds0_pdata3		),
	.fx10_gpif_lvds0_pdata4			(fx10_gpif_lvds0_pdata4		),
	.fx10_gpif_lvds0_pdata5			(fx10_gpif_lvds0_pdata5		),
	.fx10_gpif_lvds0_pdata6			(fx10_gpif_lvds0_pdata6		),
	.fx10_gpif_lvds0_pdata7			(fx10_gpif_lvds0_pdata7		),
	
	.fx10_gpif_lvds1_pclk_data		(fx10_gpif_lvds1_pclk_data	),
	.fx10_gpif_lvds1_pctrl			(fx10_gpif_lvds1_pctrl		),
	.fx10_gpif_lvds1_pdata0			(fx10_gpif_lvds1_pdata0		),
	.fx10_gpif_lvds1_pdata1			(fx10_gpif_lvds1_pdata1		),
	.fx10_gpif_lvds1_pdata2			(fx10_gpif_lvds1_pdata2		),
	.fx10_gpif_lvds1_pdata3			(fx10_gpif_lvds1_pdata3		),
	.fx10_gpif_lvds1_pdata4			(fx10_gpif_lvds1_pdata4		),
	.fx10_gpif_lvds1_pdata5			(fx10_gpif_lvds1_pdata5		),
	.fx10_gpif_lvds1_pdata6			(fx10_gpif_lvds1_pdata6		),
	.fx10_gpif_lvds1_pdata7			(fx10_gpif_lvds1_pdata7		),
	
	.fx10_gpif_lvds0_ctl0			(fx10_gpif_lvds0_ctl0		),
	.fx10_gpif_lvds0_ctl1			(fx10_gpif_lvds0_ctl1		),
	.fx10_gpif_lvds0_ctl2			(fx10_gpif_lvds0_ctl2		),
	.fx10_gpif_lvds0_ctl3			(fx10_gpif_lvds0_ctl3		),
	.fx10_gpif_lvds0_ctl4			(fx10_gpif_lvds0_ctl4		),
	.fx10_gpif_lvds0_ctl5			(fx10_gpif_lvds0_ctl5		),
	.fx10_gpif_lvds0_ctl6			(fx10_gpif_lvds0_ctl6		),
	
	.fx10_gpif_lvds1_ctl0			(fx10_gpif_lvds1_ctl0		),
	.fx10_gpif_lvds1_ctl1			(fx10_gpif_lvds1_ctl1		),
	.fx10_gpif_lvds1_ctl2			(fx10_gpif_lvds1_ctl2		),
	.fx10_gpif_lvds1_ctl3			(fx10_gpif_lvds1_ctl3		),
	.fx10_gpif_lvds1_ctl4			(fx10_gpif_lvds1_ctl4		),
	.fx10_gpif_lvds1_ctl5			(fx10_gpif_lvds1_ctl5		),
	.fx10_gpif_lvds1_ctl6			(fx10_gpif_lvds1_ctl6		),
	
	.fx10_gpif_lvds0_clk_oe			(fx10_gpif_lvds0_clk_oe			),
	.fx10_gpif_lvds0_ctrl_oe		(fx10_gpif_lvds0_ctrl_oe		),
	.fx10_gpif_lvds0_data0_oe		(fx10_gpif_lvds0_data0_oe		),
	.fx10_gpif_lvds0_data1_oe		(fx10_gpif_lvds0_data1_oe		),
	.fx10_gpif_lvds0_data2_oe		(fx10_gpif_lvds0_data2_oe		),
	.fx10_gpif_lvds0_data3_oe		(fx10_gpif_lvds0_data3_oe		),
	.fx10_gpif_lvds0_data4_oe		(fx10_gpif_lvds0_data4_oe		),
	.fx10_gpif_lvds0_data5_oe		(fx10_gpif_lvds0_data5_oe		),
	.fx10_gpif_lvds0_data6_oe		(fx10_gpif_lvds0_data6_oe		),
	.fx10_gpif_lvds0_data7_oe		(fx10_gpif_lvds0_data7_oe		),
	.fx10_gpif_lvds1_clk_oe			(fx10_gpif_lvds1_clk_oe			),
	.fx10_gpif_lvds1_ctrl_oe		(fx10_gpif_lvds1_ctrl_oe		),
	.fx10_gpif_lvds1_data0_oe		(fx10_gpif_lvds1_data0_oe		),
	.fx10_gpif_lvds1_data1_oe		(fx10_gpif_lvds1_data1_oe		),
	.fx10_gpif_lvds1_data2_oe		(fx10_gpif_lvds1_data2_oe		),
	.fx10_gpif_lvds1_data3_oe		(fx10_gpif_lvds1_data3_oe		),
	.fx10_gpif_lvds1_data4_oe		(fx10_gpif_lvds1_data4_oe		),
	.fx10_gpif_lvds1_data5_oe		(fx10_gpif_lvds1_data5_oe		),
	.fx10_gpif_lvds1_data6_oe		(fx10_gpif_lvds1_data6_oe		),
	.fx10_gpif_lvds1_data7_oe		(fx10_gpif_lvds1_data7_oe		),
	
	.fx10_gpif_lvds0_clk_rst		(fx10_gpif_lvds0_clk_rst		),
	.fx10_gpif_lvds0_ctrl_rst		(fx10_gpif_lvds0_ctrl_rst		),
	.fx10_gpif_lvds0_data0_rst		(fx10_gpif_lvds0_data0_rst		),
	.fx10_gpif_lvds0_data1_rst		(fx10_gpif_lvds0_data1_rst		),
	.fx10_gpif_lvds0_data2_rst		(fx10_gpif_lvds0_data2_rst		),
	.fx10_gpif_lvds0_data3_rst		(fx10_gpif_lvds0_data3_rst		),
	.fx10_gpif_lvds0_data4_rst		(fx10_gpif_lvds0_data4_rst		),
	.fx10_gpif_lvds0_data5_rst		(fx10_gpif_lvds0_data5_rst		),
	.fx10_gpif_lvds0_data6_rst		(fx10_gpif_lvds0_data6_rst		),
	.fx10_gpif_lvds0_data7_rst		(fx10_gpif_lvds0_data7_rst		),
	.fx10_gpif_lvds1_clk_rst		(fx10_gpif_lvds1_clk_rst		),
	.fx10_gpif_lvds1_ctrl_rst		(fx10_gpif_lvds1_ctrl_rst		),
	.fx10_gpif_lvds1_data0_rst		(fx10_gpif_lvds1_data0_rst		),
	.fx10_gpif_lvds1_data1_rst		(fx10_gpif_lvds1_data1_rst		),
	.fx10_gpif_lvds1_data2_rst		(fx10_gpif_lvds1_data2_rst		),
	.fx10_gpif_lvds1_data3_rst		(fx10_gpif_lvds1_data3_rst		),
	.fx10_gpif_lvds1_data4_rst		(fx10_gpif_lvds1_data4_rst		),
	.fx10_gpif_lvds1_data5_rst		(fx10_gpif_lvds1_data5_rst		),
	.fx10_gpif_lvds1_data6_rst		(fx10_gpif_lvds1_data6_rst		),
	.fx10_gpif_lvds1_data7_rst		(fx10_gpif_lvds1_data7_rst		),

	
	.axis_clk		(axis_clk	),				//160MHz
	.axis_rst		(axis_rst	),
	.axis_en_o		(axis_en	),		
	.axis_valid_i   (axis_valid	),
	.axis_ready_o   (axis_ready	),
	.axis_data_i    (axis_data	)
);

endmodule