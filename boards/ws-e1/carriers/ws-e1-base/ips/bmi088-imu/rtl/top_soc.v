/////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2013-2022 Efinix Inc. All rights reserved.
//
// Description:
// Example top file for EfxSapphireSoc
//
// Language:  Verilog 2001
//
// ------------------------------------------------------------------------------
// REVISION:
//  $Snapshot: $
//  $Id:$
//
// History:
// 1.0 Initial Release. 
/////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module top_soc (
input		jtag_inst1_TCK,
input		jtag_inst1_TDI,
output		jtag_inst1_TDO,
input		jtag_inst1_SEL,
input		jtag_inst1_CAPTURE,
input		jtag_inst1_SHIFT,
output		system_uart_0_io_txd,
input		system_uart_0_io_rxd,
output		system_spi_0_io_sclk_write,
output		system_spi_0_io_data_0_writeEnable,
input		system_spi_0_io_data_0_read,
output		system_spi_0_io_data_0_write,
output		system_spi_0_io_data_1_writeEnable,
input		system_spi_0_io_data_1_read,
output		system_spi_0_io_data_1_write,
output		system_spi_0_io_ss,
input [3:0] system_gpio_0_io_read,
output [3:0] system_gpio_0_io_write,
output [3:0] system_gpio_0_io_writeEnable,

output      systemClk_rstn,
input       systemClk_locked,
input       io_systemClk,
input       arst_n,
input si5338_pll_locked,
input		                    si5338_pll_clk_156m25,
output		system_i2c_0_io_sda_writeEnable,
output		system_i2c_0_io_sda_write,
input		system_i2c_0_io_sda_read,
output		system_i2c_0_io_scl_writeEnable,
output		system_i2c_0_io_scl_write,
input		system_i2c_0_io_scl_read

);
/////////////////////////////////////////////////////////////////////////////
	reg     [31:0]                  sys_cnt;
reg     [31:0]                  si5338_cnt;		

assign FPGA_SI5338_CLK_IN_RX_ENA = 1'b1;
always @ (posedge si5338_pll_clk_156m25 or negedge si5338_pll_locked)
begin
    if(si5338_pll_locked == 1'b0)
        si5338_cnt <= 32'b0;
    else
        si5338_cnt <= si5338_cnt + 1'b1;
end


always @ (posedge io_systemClk or negedge systemClk_locked)
begin
    if(systemClk_locked == 1'b0)
        sys_cnt <= 32'b0;
    else
        sys_cnt <= sys_cnt + 1'b1;
end


//Reset and PLL
wire 		reset;
wire		io_systemReset;
wire        io_asyncResetn;

assign system_i2c_0_io_sda_writeEnable = !system_i2c_0_io_sda_write;
assign system_i2c_0_io_scl_writeEnable = !system_i2c_0_io_scl_write;
/////////////////////////////////////////////////////////////////////////////
//Reset and PLL
assign systemClk_rstn 	= 1'b1;


assign reset = ~( systemClk_locked );


/////////////////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////////////////
reset_synchronizer io_asyncResetn_sync
(
 .reset_in(arst_n),
 .reset_out(io_asyncResetn),
 .clk(io_systemClk)
);



/////////////////////////////////////////////////////////////////////////////

soc soc_inst
(
.io_systemClk(io_systemClk),
.io_asyncReset(reset),
.io_systemReset(io_systemReset),
.jtagCtrl_tck(jtag_inst1_TCK),
.jtagCtrl_tdi(jtag_inst1_TDI),
.jtagCtrl_tdo(jtag_inst1_TDO),
.jtagCtrl_enable(jtag_inst1_SEL),
.jtagCtrl_capture(jtag_inst1_CAPTURE),
.jtagCtrl_shift(jtag_inst1_SHIFT),
.jtagCtrl_update(),
.jtagCtrl_reset(),
.system_uart_0_io_txd(system_uart_0_io_txd),
.system_uart_0_io_rxd(system_uart_0_io_rxd),
.system_spi_0_io_sclk_write(system_spi_0_io_sclk_write),
.system_spi_0_io_data_0_writeEnable(system_spi_0_io_data_0_writeEnable),
.system_spi_0_io_data_0_read(system_spi_0_io_data_0_read),
.system_spi_0_io_data_0_write(system_spi_0_io_data_0_write),
.system_spi_0_io_data_1_writeEnable(system_spi_0_io_data_1_writeEnable),
.system_spi_0_io_data_1_read(system_spi_0_io_data_1_read),
.system_spi_0_io_data_1_write(system_spi_0_io_data_1_write),
.system_spi_0_io_data_2_writeEnable(),
.system_spi_0_io_data_2_read(),
.system_spi_0_io_data_2_write(),
.system_spi_0_io_data_3_writeEnable(),
.system_spi_0_io_data_3_read(),
.system_spi_0_io_data_3_write(),
.system_spi_0_io_ss(system_spi_0_io_ss),

.system_gpio_0_io_read(system_gpio_0_io_read),
.system_gpio_0_io_write(system_gpio_0_io_write),
.system_gpio_0_io_writeEnable(system_gpio_0_io_writeEnable),
//i2c
.system_i2c_0_io_scl_read ( system_i2c_0_io_scl_read ),
.system_i2c_0_io_scl_write ( system_i2c_0_io_scl_write ),
.system_i2c_0_io_sda_read ( system_i2c_0_io_sda_read ),
.system_i2c_0_io_sda_write ( system_i2c_0_io_sda_write )

	
);

endmodule

