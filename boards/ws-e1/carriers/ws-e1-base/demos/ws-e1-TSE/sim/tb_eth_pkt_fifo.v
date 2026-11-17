//============================================================================
// tb_eth_pkt_fifo : eth_pkt_fifo 模块级自校验 testbench
// 覆盖: RX 帧写入->APB 读出比对(含 tlast/tuser/顺序)、APB 写->TX stream 比对、
//       tready 恒 1（TSEMAC UG 不支持背压）、SOF 帧粒度准入整帧丢弃（无部分
//       帧、数据完好）、溢出 sticky 置位/清除、丢帧后恢复接收
// 运行: vsim -c tb_eth_pkt_fifo -do "run -all; quit -f"
//============================================================================
`timescale 1ns/1ps
module tb_eth_pkt_fifo;

reg         rx_clk = 1'b0;
reg         apb_clk = 1'b0;
reg         tx_clk = 1'b0;
reg         rx_rstn = 1'b0;
reg         tx_rstn = 1'b0;
reg         apb_rstn = 1'b0;

always #4    rx_clk  = ~rx_clk;    //125MHz 板级真实
always #10   apb_clk = ~apb_clk;   //50MHz 板级真实
always #4    tx_clk  = ~tx_clk;    //125MHz 板级真实（与 apb 异域异频）

reg  [7:0]  rx_tdata;
reg         rx_tvalid;
reg         rx_tlast;
reg         rx_tuser;
wire        rx_tready;

wire [7:0]  tx_tdata;
wire        tx_tvalid;
wire        tx_tlast;
wire        tx_tuser;
reg         tx_tready;

wire [11:0] rx_word_cnt;
wire        rx_overflow;
reg         rx_overflow_clr;
reg         rx_rd_en;
wire [9:0]  rx_rddata;
wire [12:0] tx_free_cnt;
wire        tx_full;
reg  [8:0]  tx_wrdata;
reg         tx_wr_en;

integer errors;
integer i;
reg [9:0] rd_word;
reg [8:0] mon_word;
integer mon_len;
reg [8:0] mon_mem [0:4095];

eth_pkt_fifo #(
    .FIFO_DEPTH                     (4096),
    .FRAME_GUARD                    (1536)
) dut (
    .rx_clk                         (rx_clk),
    .rx_rstn                        (rx_rstn),
    .rx_tdata                       (rx_tdata),
    .rx_tvalid                      (rx_tvalid),
    .rx_tlast                       (rx_tlast),
    .rx_tuser                       (rx_tuser),
    .rx_tready                      (rx_tready),
    .tx_clk                         (tx_clk),         //125M 独立时钟（板级真实连接）
    .tx_rstn                        (apb_rstn),
    .tx_tdata                       (tx_tdata),
    .tx_tvalid                      (tx_tvalid),
    .tx_tlast                       (tx_tlast),
    .tx_tuser                       (tx_tuser),
    .tx_tready                      (tx_tready),
    .apb_clk                        (apb_clk),
    .apb_rstn                       (apb_rstn),
    .rx_word_cnt                    (rx_word_cnt),
    .rx_overflow                    (rx_overflow),
    .rx_overflow_clr                (rx_overflow_clr),
    .rx_rd_en                       (rx_rd_en),
    .rx_rddata                      (rx_rddata),
    .tx_free_cnt                    (tx_free_cnt),
    .tx_full                        (tx_full),
    .tx_wrdata                      (tx_wrdata),
    .tx_wr_en                       (tx_wr_en)
);

//RX 帧驱动: payload = seed ^ i[7:0], 最后字 tlast=1, 偶发气泡
task rx_send_frame(input integer len, input [7:0] seed);
    integer k;
    begin
        for (k = 0; k < len; k = k + 1) begin
            rx_tdata  <= seed ^ k[7:0];
            rx_tlast  <= (k == len-1);
            rx_tuser  <= 1'b0;
            rx_tvalid <= 1'b1;
            @(posedge rx_clk);
            if ((k % 13) == 5) begin     //偶发插入气泡
                rx_tvalid <= 1'b0;
                @(posedge rx_clk);
            end
        end
        rx_tvalid <= 1'b0;
        rx_tlast  <= 1'b0;
    end
endtask

//APB 侧读弹出: ShowAhead 语义, 采样当前 q 同时弹出
task read_word(output [9:0] d);
    begin
        rx_rd_en = 1'b1;
        @(posedge apb_clk);
        d = rx_rddata;
        #1;
        rx_rd_en = 1'b0;
        @(posedge apb_clk);
    end
endtask

//APB 侧 TX 写入
task tx_write(input [7:0] d, input last);
    begin
        tx_wrdata = {last, d};
        tx_wr_en  = 1'b1;
        @(posedge apb_clk);
        tx_wr_en  = 1'b0;
        @(posedge apb_clk);
    end
endtask

//TX stream 监视收集
always @(posedge tx_clk) begin
    if (tx_tvalid && tx_tready) begin
        mon_mem[mon_len] = {tx_tlast, tx_tdata};
        mon_len = mon_len + 1;
    end
end

//tready 恒 1 监视（TSEMAC UG：背压不受支持，帧中拉低会静默损坏帧）
always @(rx_tready) begin
    if (rx_tready !== 1'b1) begin
        errors = errors + 1;
        $display("[FAIL] rx_tready deasserted (UG: backpressure unsupported)");
    end
end

initial begin
    errors   = 0;
    mon_len  = 0;
    rx_tdata = 0; rx_tvalid = 0; rx_tlast = 0; rx_tuser = 0;
    rx_rd_en = 0; rx_overflow_clr = 0;
    tx_wrdata = 0; tx_wr_en = 0; tx_tready = 1'b1;
    rx_rstn = 0; tx_rstn = 0; apb_rstn = 0;
    repeat (10) @(posedge rx_clk);
    rx_rstn = 1; tx_rstn = 1; apb_rstn = 1;
    repeat (10) @(posedge apb_clk);

    //--------------------------------------------------------------
    // TEST1: RX 帧(512B) 写入 -> 读出逐字比对 (顺序 + tlast + 计数)
    //--------------------------------------------------------------
    $display("[TEST1] RX frame 512B write/readback");
    rx_send_frame(512, 8'hA5);
    repeat (20) @(posedge apb_clk);
    //WrDNum 跨域同步端点差 1（DaulClkFifo 语义），允许 511/512
    if ((rx_word_cnt !== 12'd512) && (rx_word_cnt !== 12'd511)) begin
        errors = errors + 1;
        $display("[FAIL] rx_word_cnt=%0d expect 511~512", rx_word_cnt);
    end
    for (i = 0; i < 512; i = i + 1) begin
        read_word(rd_word);
        if (rd_word[7:0] !== (8'hA5 ^ i[7:0])) begin
            errors = errors + 1;
            $display("[FAIL] RX data[%0d]=%02x expect %02x", i, rd_word[7:0], 8'hA5 ^ i[7:0]);
        end
        if ((i == 511) && (rd_word[8] !== 1'b1)) begin
            errors = errors + 1;
            $display("[FAIL] tlast not seen on last word");
        end
        if ((i < 511) && (rd_word[8] !== 1'b0)) begin
            errors = errors + 1;
            $display("[FAIL] tlast seen on word %0d", i);
        end
    end
    if (errors == 0) $display("[PASS] TEST1");

    //--------------------------------------------------------------
    // TEST2: APB 写 TX(200B 帧) -> AXI4-Stream 读出比对
    //--------------------------------------------------------------
    $display("[TEST2] TX frame 200B write/readback");
    mon_len = 0;
    for (i = 0; i < 200; i = i + 1)
        tx_write(8'h5C ^ i[7:0], (i == 199));
    repeat (50) @(posedge apb_clk);
    if (mon_len !== 200) begin
        errors = errors + 1;
        $display("[FAIL] tx mon_len=%0d expect 200", mon_len);
    end
    for (i = 0; i < 200; i = i + 1) begin
        mon_word = mon_mem[i];
        if (mon_word[7:0] !== (8'h5C ^ i[7:0])) begin
            errors = errors + 1;
            $display("[FAIL] TX data[%0d]=%02x expect %02x", i, mon_word[7:0], 8'h5C ^ i[7:0]);
        end
        if ((i == 199) && (mon_word[8] !== 1'b1)) begin
            errors = errors + 1;
            $display("[FAIL] TX tlast not seen on last byte");
        end
    end
    if (errors == 0) $display("[PASS] TEST2");

    //--------------------------------------------------------------
    // TEST3: SOF 帧粒度准入——放不下整帧则整帧丢弃，sticky 置位/清除
    // 9×300B 帧=2700 字被接纳（SOF 时 wrcnt≤2560），随后 3 帧整帧丢弃
    //--------------------------------------------------------------
    $display("[TEST3] frame-granular admission / overflow sticky");
    rx_overflow_clr = 1'b0;
    for (i = 0; i < 12; i = i + 1)
        rx_send_frame(300, 8'h40 + i[7:0]);
    repeat (20) @(posedge apb_clk);
    //仅前 9 帧入 FIFO：2700 字（WrDNum 跨域端点差 1，允许 2699/2700）
    if ((rx_word_cnt !== 12'd2700) && (rx_word_cnt !== 12'd2699)) begin
        errors = errors + 1;
        $display("[FAIL] rx_word_cnt=%0d expect 2699~2700 (dropped frames must not leak bytes)", rx_word_cnt);
    end
    if (rx_overflow !== 1'b1) begin
        errors = errors + 1;
        $display("[FAIL] rx_overflow not set after dropped frames");
    end
    rx_overflow_clr = 1'b1;
    @(posedge apb_clk);
    rx_overflow_clr = 1'b0;
    #1;
    if (rx_overflow !== 1'b0) begin
        errors = errors + 1;
        $display("[FAIL] rx_overflow not cleared");
    end
    //逐字读回：内容必须与前 9 帧完全一致（丢弃帧不得污染数据流）
    //注：注入任务 payload = seed ^ k[7:0]，k 为帧内字节序号按 8bit 截断
    for (i = 0; i < 2700; i = i + 1) begin
        read_word(rd_word);
        if (rd_word[7:0] !== ((8'h40 + (i/300)) ^ ((i % 300) & 8'hFF))) begin
            errors = errors + 1;
            $display("[FAIL] RX data[%0d]=%02x expect %02x", i, rd_word[7:0], (8'h40 + (i/300)) ^ ((i % 300) & 8'hFF));
        end
        if (((i % 300) == 299) && (rd_word[8] !== 1'b1)) begin
            errors = errors + 1;
            $display("[FAIL] tlast not seen at end of frame %0d", i/300);
        end
        if (((i % 300) != 299) && (rd_word[8] !== 1'b0)) begin
            errors = errors + 1;
            $display("[FAIL] tlast seen at word %0d", i);
        end
    end
    //排空后恢复接收：新帧被完整接纳，且无新的丢帧事件
    rx_send_frame(300, 8'hB0);
    repeat (20) @(posedge apb_clk);
    if ((rx_word_cnt !== 12'd300) && (rx_word_cnt !== 12'd299)) begin
        errors = errors + 1;
        $display("[FAIL] recovery frame word_cnt=%0d expect 299~300", rx_word_cnt);
    end
    if (rx_overflow !== 1'b0) begin
        errors = errors + 1;
        $display("[FAIL] rx_overflow re-set without drop");
    end
    if (errors == 0) $display("[PASS] TEST3");

    //--------------------------------------------------------------
    repeat (20) @(posedge apb_clk);
    if (errors == 0)
        $display("=== TB_ETH_PKT_FIFO: ALL TESTS PASSED ===");
    else
        $display("=== TB_ETH_PKT_FIFO: %0d ERRORS ===", errors);
    $finish;
end

endmodule
`default_nettype wire
