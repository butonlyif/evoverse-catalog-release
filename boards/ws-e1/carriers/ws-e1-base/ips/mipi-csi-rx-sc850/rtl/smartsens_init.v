
module smartsens_init #(	
	parameter	FREQ_I2C_REF = 50000000,
	parameter	RAM_INIT_FILE = "init.rom"	
)(
input 	clk_i2c_ref,
input	clk_sensor_ref,
input	rstn,

output	rst_o,
output	pwdn_o,
output	xclk_hi_o,
output	xclk_lo_o,

output	scl_o	,
output	scl_oe	,
input	scl_i	,
output	sda_o	,
output	sda_oe	,
input	sda_i	,

output	init_done_o
);


localparam T_6MS = FREQ_I2C_REF/10*6;
localparam T_2MS = FREQ_I2C_REF/10*2;
localparam T_1MS = FREQ_I2C_REF/10;
localparam T_05MS = FREQ_I2C_REF/5;

reg			pwdn=0;
reg [27:0]	cnt;
wire		t_6ms_en;
wire		t_2ms_en;
wire		t_1ms_en;
wire		t_05ms_en;

assign 		t_6ms_en = (cnt == T_6MS)?1'b1:1'b0;
assign 		t_2ms_en = (cnt > T_2MS)?1'b1:1'b0;
assign 		t_1ms_en = (cnt > T_1MS)?1'b1:1'b0;
assign 		t_05ms_en = (cnt > T_05MS)?1'b1:1'b0;

always@(posedge clk_i2c_ref)
	if(!rstn)begin
		cnt <= 0;
	end else begin
		if(~t_6ms_en)
			cnt <= cnt + 1;
	end	
	
reg xclk_hi,xclk_lo;	
reg t_2ms_en_d1,t_2ms_en_d0;
always@(posedge clk_sensor_ref)
	{t_2ms_en_d1,t_2ms_en_d0}<={t_2ms_en_d0,t_2ms_en};
always@(posedge clk_sensor_ref)
	if(t_2ms_en_d1)begin
		xclk_hi <= 1;
		xclk_lo <= 0;
	end else begin	
		xclk_hi <= 0;
		xclk_lo <= 0;
	end	
		
		
sc535_i2c_init #(	
	.FREQ_I2C_REF 	(FREQ_I2C_REF),	
	.RAM_INIT_FILE 	(RAM_INIT_FILE)	
)sc535_i2c_init(
.clk		(clk_i2c_ref),
.rstn		(t_6ms_en	),
.init_done_o(init_done_o),

.scl_o		(scl_o	),
.scl_oe		(scl_oe	),
.scl_i		(scl_i	),
.sda_o		(sda_o	),
.sda_oe		(sda_oe	),
.sda_i		(sda_i	)
);		
		
		
		
assign rst_o  		= t_05ms_en;
assign pwdn_o  		= t_1ms_en;
assign xclk_hi_o	= xclk_hi;	
assign xclk_lo_o	= xclk_lo;	
endmodule