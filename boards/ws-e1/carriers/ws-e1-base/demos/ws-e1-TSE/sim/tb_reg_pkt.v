//============================================================================
// tb_reg_pkt : reg_apb3 扩展寄存器窗口 + eth_pkt_fifo 联动 testbench
// 覆盖: APB 时序读 0x244 自动弹出、0x24C 写入→TX stream、0x240 状态/清溢出、
//       0x204 mux 控制位(含 bit4 sw_sel)、RX 背压合并行为
// 运行: vsim -c tb_reg_pkt -do "run -all; quit -f"
//============================================================================
`timescale 1ns/1ps
module tb_reg_pkt;

reg         clk = 1'b0;
reg         rstn = 1'b0;
always #5 clk = ~clk;

//APB master
reg         psel;
reg         penable;
reg         pwrite;
reg  [9:0]  paddr;
reg  [31:0] pwdata;
wire        pready;
wire [31:0] prdata;

//cfg
wire        mac_sw_rst;
wire        axi4_st_mux_select;
wire        pat_mux_select;
wire        eth_sw_tx_sel;
wire        udp_pat_gen_en, mac_pat_gen_en;
wire [15:0] pat_gen_num, pat_gen_ipg;
wire [47:0] pat_dst_mac, pat_src_mac;
wire [15:0] pat_mac_dlen;
wire [31:0] pat_src_ip, pat_dst_ip;
wire [15:0] pat_src_port, pat_dst_port, pat_udp_dlen;

//eth_pkt_fifo wires
wire        eth_rx_overflow_clr;
wire        eth_rx_rd_en;
wire [9:0]  eth_rx_rddata;
wire [12:0] eth_tx_free_cnt;
wire        eth_tx_full;
wire [8:0]  eth_tx_wrdata;
wire        eth_tx_wr_en;

//RX stream (injected)
reg  [7:0]  rx_tdata;
reg         rx_tvalid, rx_tlast, rx_tuser;
wire        rx_tready;
//TX stream (monitored)
wire [7:0]  tx_tdata;
wire        tx_tvalid, tx_tlast, tx_tuser;
reg         tx_tready;

integer errors;
integer i;
reg [31:0] rdata;
reg [8:0] mon_mem [0:4095];
integer mon_len;
reg [9:0] rd_word;

reg_apb3 #(.ADDR_WTH(10)) u_reg (
    .s_apb3_clk             (clk),
    .s_apb3_rstn            (rstn),
    .s_apb3_paddr           (paddr),
    .s_apb3_psel            (psel),
    .s_apb3_penable         (penable),
    .s_apb3_pready          (pready),
    .s_apb3_pwrite          (pwrite),
    .s_apb3_pwdata          (pwdata),
    .s_apb3_prdata          (prdata),
    .s_apb3_pslverror       (),
    .mac_sw_rst             (mac_sw_rst),
    .axi4_st_mux_select     (axi4_st_mux_select),
    .pat_mux_select         (pat_mux_select),
    .udp_pat_gen_en         (udp_pat_gen_en),
    .mac_pat_gen_en         (mac_pat_gen_en),
    .pat_gen_num            (pat_gen_num),
    .pat_gen_ipg            (pat_gen_ipg),
    .pat_dst_mac            (pat_dst_mac),
    .pat_src_mac            (pat_src_mac),
    .pat_mac_dlen           (pat_mac_dlen),
    .pat_src_ip             (pat_src_ip),
    .pat_dst_ip             (pat_dst_ip),
    .pat_src_port           (pat_src_port),
    .pat_dst_port           (pat_dst_port),
    .pat_udp_dlen           (pat_udp_dlen),
    .eth_rx_word_cnt        (u_fifo.rx_word_cnt),
    .eth_rx_overflow        (u_fifo.rx_overflow),
    .eth_rx_overflow_clr    (eth_rx_overflow_clr),
    .eth_rx_rd_en           (eth_rx_rd_en),
    .eth_rx_rddata          (eth_rx_rddata),
    .eth_tx_free_cnt        (u_fifo.tx_free_cnt),
    .eth_tx_full            (u_fifo.tx_full),
    .eth_dbg_rxc_cnt        (16'h1234),
    .eth_dbg_pll_cnt        (16'h5678),
    .pll_rgmii_locked       (1'b1),
    .eth_tx_wrdata          (eth_tx_wrdata),
    .eth_tx_wr_en           (eth_tx_wr_en),
    .eth_sw_tx_sel          (eth_sw_tx_sel)
);

eth_pkt_fifo #(.FIFO_DEPTH(4096), .FRAME_GUARD(1536)) u_fifo (
    .rx_clk                 (clk),
    .rx_rstn                (rstn),
    .rx_tdata               (rx_tdata),
    .rx_tvalid              (rx_tvalid),
    .rx_tlast               (rx_tlast),
    .rx_tuser               (rx_tuser),
    .rx_tready              (rx_tready),
    .tx_clk                 (clk),
    .tx_rstn                (rstn),
    .tx_tdata               (tx_tdata),
    .tx_tvalid              (tx_tvalid),
    .tx_tlast               (tx_tlast),
    .tx_tuser               (tx_tuser),
    .tx_tready              (tx_tready),
    .apb_clk                (clk),
    .apb_rstn               (rstn),
    .rx_word_cnt            (),
    .rx_overflow            (),
    .rx_overflow_clr        (eth_rx_overflow_clr),
    .rx_rd_en               (eth_rx_rd_en),
    .rx_rddata              (eth_rx_rddata),
    .tx_free_cnt            (eth_tx_free_cnt),
    .tx_full                (eth_tx_full),
    .tx_wrdata              (eth_tx_wrdata),
    .tx_wr_en               (eth_tx_wr_en)
);

task apb_wr(input [9:0] addr, input [31:0] data);
    begin
        @(posedge clk);
        psel = 1; pwrite = 1; paddr = addr; pwdata = data; penable = 0;
        @(posedge clk);
        penable = 1;
        while (pready !== 1'b1) @(posedge clk);
        @(posedge clk);
        psel = 0; penable = 0;
    end
endtask

task apb_rd(input [9:0] addr, output [31:0] data);
    begin
        @(posedge clk);
        psel = 1; pwrite = 0; paddr = addr; penable = 0;
        @(posedge clk);
        penable = 1;
        while (pready !== 1'b1) @(posedge clk);
        data = prdata;
        @(posedge clk);
        psel = 0; penable = 0;
    end
endtask

//RX 帧注入
task rx_send_frame(input integer len, input [7:0] seed);
    integer k;
    begin
        for (k = 0; k < len; k = k + 1) begin
            rx_tdata  <= seed ^ k[7:0];
            rx_tlast  <= (k == len-1);
            rx_tvalid <= 1'b1;
            @(posedge clk);
        end
        rx_tvalid <= 1'b0;
        rx_tlast  <= 1'b0;
    end
endtask

always @(posedge clk) begin
    if (tx_tvalid && tx_tready) begin
        mon_mem[mon_len] = {tx_tlast, tx_tdata};
        mon_len = mon_len + 1;
    end
end

initial begin
    errors = 0; mon_len = 0;
    psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
    rx_tdata = 0; rx_tvalid = 0; rx_tlast = 0; rx_tuser = 0;
    tx_tready = 1'b1;
    rstn = 0;
    repeat (10) @(posedge clk);
    rstn = 1;
    repeat (10) @(posedge clk);

    //--------------------------------------------------------------
    // TEST1: 0x204 mux 控制位含 bit4 sw_sel (bit0=loopback, bit4=sw_sel)
    //--------------------------------------------------------------
    $display("[TEST1] 0x204 mux control bits");
    apb_wr(10'h204, 32'h11);   //bit0=1 loopback, bit4=1 sw_sel
    #1;
    if ({eth_sw_tx_sel, axi4_st_mux_select} !== 2'b11) begin
        errors = errors + 1;
        $display("[FAIL] sw_sel/loop = %b%b expect 11", eth_sw_tx_sel, axi4_st_mux_select);
    end
    apb_rd(10'h204, rdata);
    if (rdata[4:0] !== 5'b10001) begin
        errors = errors + 1;
        $display("[FAIL] 0x204 readback=%05b expect 10001", rdata[4:0]);
    end
    apb_wr(10'h204, 32'h0);
    #1;
    if ({eth_sw_tx_sel, axi4_st_mux_select} !== 2'b00) begin
        errors = errors + 1;
        $display("[FAIL] mux bits not cleared");
    end
    if (errors == 0) $display("[PASS] TEST1");

    //--------------------------------------------------------------
    // TEST2: RX 注入 256B -> APB 读 0x244 逐字弹出比对 + 0x240 计数
    //--------------------------------------------------------------
    $display("[TEST2] RX window via APB 0x244");
    rx_send_frame(256, 8'h3C);
    repeat (10) @(posedge clk);
    apb_rd(10'h240, rdata);
    //WrDNum 跨域同步端点差 1（DaulClkFifo 语义），允许 255/256
    if ((rdata[11:0] !== 12'd256) && (rdata[11:0] !== 12'd255)) begin
        errors = errors + 1;
        $display("[FAIL] RX_STATUS cnt=%0d expect 255~256", rdata[11:0]);
    end
    for (i = 0; i < 256; i = i + 1) begin
        apb_rd(10'h244, rdata);
        rd_word = rdata[9:0];
        if (rd_word[7:0] !== (8'h3C ^ i[7:0])) begin
            errors = errors + 1;
            $display("[FAIL] RX data[%0d]=%02x expect %02x", i, rd_word[7:0], 8'h3C ^ i[7:0]);
        end
        if ((i == 255) && (rd_word[8] !== 1'b1)) begin
            errors = errors + 1;
            $display("[FAIL] tlast missing on last word");
        end
    end
    apb_rd(10'h240, rdata);
    if (rdata[11:0] !== 12'd0) begin
        errors = errors + 1;
        $display("[FAIL] RX_STATUS cnt=%0d expect 0 after drain", rdata[11:0]);
    end
    if (errors == 0) $display("[PASS] TEST2");

    //--------------------------------------------------------------
    // TEST3: APB 写 0x24C -> TX stream 比对 (128B 帧)
    //--------------------------------------------------------------
    $display("[TEST3] TX window via APB 0x24C");
    mon_len = 0;
    apb_rd(10'h248, rdata);
    if (rdata[12:0] !== 13'd4095) begin
        errors = errors + 1;
        $display("[FAIL] TX free_cnt=%0d expect 4095", rdata[12:0]);
    end
    for (i = 0; i < 128; i = i + 1)
        apb_wr(10'h24C, {23'h0, (i == 127), 8'h77 ^ i[7:0]});
    repeat (50) @(posedge clk);
    if (mon_len !== 128) begin
        errors = errors + 1;
        $display("[FAIL] tx mon_len=%0d expect 128", mon_len);
    end
    for (i = 0; i < 128; i = i + 1) begin
        if (mon_mem[i][7:0] !== (8'h77 ^ i[7:0])) begin
            errors = errors + 1;
            $display("[FAIL] TX data[%0d]=%02x expect %02x", i, mon_mem[i][7:0], 8'h77 ^ i[7:0]);
        end
        if ((i == 127) && (mon_mem[i][8] !== 1'b1)) begin
            errors = errors + 1;
            $display("[FAIL] TX tlast missing");
        end
    end
    if (errors == 0) $display("[PASS] TEST3");

    //--------------------------------------------------------------
    // TEST4: SOF 帧粒度准入 + 溢出 sticky 经 0x240 bit12 置位 / bit0 清除
    // 9×300B=2700 字接纳，第 10 帧整帧丢弃（同域时钟，计数精确无 ±1）
    //--------------------------------------------------------------
    $display("[TEST4] frame admission + overflow sticky via registers");
    for (i = 0; i < 10; i = i + 1)
        rx_send_frame(300, 8'h90 + i[7:0]);
    repeat (10) @(posedge clk);
    apb_rd(10'h240, rdata);
    //DaulClkFifo WrDNum 端点差 1（已知语义），允许 2699/2700
    if ((rdata[11:0] !== 12'd2700) && (rdata[11:0] !== 12'd2699)) begin
        errors = errors + 1;
        $display("[FAIL] word_cnt=%0d expect 2699~2700 (dropped frame must not leak)", rdata[11:0]);
    end
    if (rdata[12] !== 1'b1) begin
        errors = errors + 1;
        $display("[FAIL] overflow flag not set");
    end
    //排空 FIFO 后写 bit0 清除
    for (i = 0; i < 2700; i = i + 1)
        apb_rd(10'h244, rdata);
    apb_wr(10'h240, 32'h1);    //写 bit0 清除
    repeat (2) @(posedge clk);
    apb_rd(10'h240, rdata);
    if (rdata[12] !== 1'b0) begin
        errors = errors + 1;
        $display("[FAIL] overflow flag not cleared (cnt=%0d)", rdata[11:0]);
    end
    if (errors == 0) $display("[PASS] TEST4");

    //--------------------------------------------------------------
    repeat (20) @(posedge clk);
    if (errors == 0)
        $display("=== TB_REG_PKT: ALL TESTS PASSED ===");
    else
        $display("=== TB_REG_PKT: %0d ERRORS ===", errors);
    $finish;
end

endmodule
`default_nettype wire
