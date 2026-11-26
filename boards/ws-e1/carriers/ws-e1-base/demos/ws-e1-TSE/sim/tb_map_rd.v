//============================================================================
// tb_map_rd : 20:10 bit 综合网表（map.v）寄存器读验证
// 判据：复位释放、零写入状态下读 'h092（TX_STATUS）
//   RTL 语义期望 free=4096 -> 读数 0x00001000（full 恒 0）
//   板上实测读数 0x00002000（bit13=1）
//   网表若也读出 0x2000 -> 硅逻辑 != RTL（综合/缓存问题）
//   网表若读出 0x1000 -> 板上跑的不是这个 bit
//============================================================================
`timescale 1ns/1ps
module tb_map_rd;

reg         clk             = 1'b0;
reg         clk_125m        = 1'b0;
reg         pll_rgmii_rx_clk= 1'b0;
reg         pll_0_locked    = 1'b0;
reg         phy_mdi         = 1'b1;
reg         uart_rxd        = 1'b1;
reg         jTCK=0, jTDI=0, jSEL=0, jCAP=0, jSH=0, jUPD=0, jRST=0;
reg [3:0]   rxd0 = 0;
wire        pll_rstn;
wire [3:0]  txd_HI, txd_LO;
wire        tctl_HI, tctl_LO, txc_HI, txc_LO;
wire        mdo, mdo_en, mdc, uart_txd, jTDO;

always #10 clk              = ~clk;   //50MHz
always #4  clk_125m         = ~clk_125m;
always #4  pll_rgmii_rx_clk = ~pll_rgmii_rx_clk;
initial begin #200; pll_0_locked = 1'b1; end

ws_e1_tse dut (
    .clk(clk), .clk_125m(clk_125m), .pll_0_locked(pll_0_locked),
    .pll_rgmii_rx_clk(pll_rgmii_rx_clk), .pll_rstn(pll_rstn),
    .rgmii_txd_HI(txd_HI), .rgmii_txd_LO(txd_LO),
    .rgmii_tx_ctl_HI(tctl_HI), .rgmii_tx_ctl_LO(tctl_LO),
    .rgmii_txc_HI(txc_HI), .rgmii_txc_LO(txc_LO),
    .rgmii_rxd0_HI(rxd0[0]), .rgmii_rxd0_LO(rxd0[0]),
    .rgmii_rxd1_HI(rxd0[1]), .rgmii_rxd1_LO(rxd0[1]),
    .rgmii_rxd2_HI(rxd0[2]), .rgmii_rxd2_LO(rxd0[2]),
    .rgmii_rxd3_HI(rxd0[3]), .rgmii_rxd3_LO(rxd0[3]),
    .rgmii_rx_ctl_HI(1'b0), .rgmii_rx_ctl_LO(1'b0),
    .jtag_inst1_TCK(jTCK), .jtag_inst1_TDI(jTDI), .jtag_inst1_TDO(jTDO),
    .jtag_inst1_SEL(jSEL), .jtag_inst1_CAPTURE(jCAP), .jtag_inst1_SHIFT(jSH),
    .jtag_inst1_UPDATE(jUPD), .jtag_inst1_RESET(jRST),
    .system_uart_0_io_txd(uart_txd), .system_uart_0_io_rxd(uart_rxd),
    .phy_mdi(phy_mdi), .phy_mdo(mdo), .phy_mdo_en(mdo_en), .phy_mdc(mdc)
);

task apb_rd(input [15:0] addr, output [31:0] data);
begin
    //SoC 原始 APB 总线（ex 空间选中 = n258）
    force dut.apb3_paddr  = addr;
    force dut.apb3_pwrite = 1'b0;
    force dut.apb3_pwdata = 32'h0;
    force dut.\u_mcu/u_EfxSapphireSoc/io_apbSlave_0_logic/n258  = 1'b1;
    @(posedge clk);
    force dut.apb3_penable = 1'b1;
    repeat (2) @(posedge clk);   //prdata 是读选通时寄存的
    data = dut.ex_apb3_prdata;
    $display("  dbg addr=%04x n258=%b loc_rd_vld=%b pready=%b prdata=%h",
        addr, dut.\u_mcu/u_EfxSapphireSoc/io_apbSlave_0_logic/n258 ,
        dut.\u_reg_apb3/loc_rd_vld , dut.ex_apb3_pready, dut.ex_apb3_prdata);
    force dut.apb3_penable = 1'b0;
    release dut.apb3_paddr;
    release dut.apb3_pwrite;
    release dut.apb3_pwdata;
    release dut.apb3_penable;
    release dut.\u_mcu/u_EfxSapphireSoc/io_apbSlave_0_logic/n258 ;
    repeat (2) @(posedge clk);
end
endtask

reg [31:0] d0, d1, d2;
initial begin
    repeat (40) @(posedge clk);   //等复位同步释放
    apb_rd(16'h0204, d1);
    $display("[NETLIST] MUX(0x081)       = %08x   (期望 00000010)", d1);
    apb_rd(16'h0240, d0);
    $display("[NETLIST] RX_STATUS(0x090) = %08x", d0);
    apb_rd(16'h0248, d2);
    $display("[NETLIST] TX_STATUS(0x092) = %08x   <- RTL 语义期望 0x00001000", d2);
    if (d2 === 32'h0000_1000)      $display("=== NETLIST == RTL 语义 ===");
    else if (d2 === 32'h0000_2000) $display("=== 网表读出 0x2000：硅逻辑 != RTL，板上现象由综合产物解释 ===");
    else                           $display("=== 网表读数异常，需人工判读 ===");
    if (!$test$plusargs("nofinish")) $finish;
end
endmodule
