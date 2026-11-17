
module sc535_i2c_init #(	
	parameter	FREQ_I2C_REF = 50000000,	
	parameter	RAM_INIT_FILE = "init.rom"	
)(
input 	clk,
input	rstn,

output	scl_o,
output	scl_oe,
input	scl_i,
output	sda_o,
output	sda_oe,
input	sda_i,

output	init_done_o
);


localparam ROM_DEEP			= 200;
localparam ROM_ADDR_WIDTH 	= 9;
localparam ROM_DATA_WIDTH 	= 24;
localparam I2C_SALVE_ADDR 	= 8'h60;


reg 	[ROM_ADDR_WIDTH-1:0] rom_addr;
wire 	[ROM_DATA_WIDTH-1:0] rom_data;

wire 	i2c_busy;
wire	mst_write_done;
reg		mst_write;
reg		init_done=0;
localparam IDLE 		= 2'd0;
localparam WR_IIC 		= 2'd1;
localparam WR_DONE 		= 2'd2;
localparam CONFIG_DONE 	= 2'd3;
reg	[1:0]state;
reg [10:0] wait_cnt;
always@(posedge clk)
	if(!rstn)begin
		rom_addr <= 0;
		state <= IDLE;
		wait_cnt <= 0;
	end else begin
		case(state)
		IDLE:begin
			wait_cnt <= wait_cnt+1;
			mst_write<= 0;
			init_done<= 0;
			// if(~i2c_busy&(wait_cnt==100))
			if(~i2c_busy)
				state <= WR_IIC;
		end
		WR_IIC:begin
			mst_write 	<= 1;
			state		<= WR_DONE;
		end	
		WR_DONE:begin
			mst_write	<= 0;
			if(mst_write_done)begin
				rom_addr 	<= rom_addr + 1;
				if(rom_addr == ROM_DEEP-1)
					state		<= CONFIG_DONE;
				else begin
					wait_cnt	<= 0;
					state		<= IDLE;
				end	
			end		
		end
		CONFIG_DONE:begin
			rom_addr <= 0;
			init_done<= 1;
		end
		endcase
	end
i2c_master i2c_master (
.clk	(clk	),
.rst	(!rstn	),

.mst_sda_in		(sda_i	),
.mst_sda_out	(sda_o	),
.mst_sda_oe		(sda_oe	),
.mst_scl_in		(scl_i	),
.mst_scl_out	(scl_o	),
.mst_scl_oe		(scl_oe	),

.i2c_busy			(i2c_busy),		//o
.i2c_soft_rst		(1'b0),	//i
.i2c_rxak			(),		//o
.i2c_arb_lost		(),		//o
.i2c_arb_lost_clr	(1'b0),	//i


.i2c_slave_addr		(I2C_SALVE_ADDR),
.mst_command_byte	(rom_data[ROM_DATA_WIDTH-1-:8]),
.mst_num_bytes		(8'd3			),
.mst_din			({rom_data[7:0],rom_data[15:8]}),
.mst_write			(mst_write		),
.mst_write_done		(mst_write_done	),

.mst_read			(1'b0),
.mst_data_out_valid	(),
.mst_data_out		()
);


single_port_rom  
#(
	.DATA_WIDTH (ROM_DATA_WIDTH	),
	.ADDR_WIDTH (ROM_ADDR_WIDTH	),
	.OUTPUT_REG ("FALSE"		),
	.RAM_INIT_FILE (RAM_INIT_FILE)
)sc535_init_rom
(
	.clk	(clk		),
	.addr	(rom_addr	),
	.data	(rom_data	)
);

assign init_done_o = init_done;
endmodule