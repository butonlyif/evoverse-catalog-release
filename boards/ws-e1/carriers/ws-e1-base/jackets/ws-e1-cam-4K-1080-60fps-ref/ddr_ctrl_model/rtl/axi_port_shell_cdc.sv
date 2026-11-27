// AXI4 slave port with the AXI side in the ACLK domain and the core side in
// the ctrl_clk domain. All payloads cross through dual-clock gray FIFOs; the
// channel handshakes and outstanding counters stay in the ACLK domain.
module axi_port_shell_cdc #(
  parameter int PORT = 0,
  parameter int WRITE_OSTD_DEPTH = 8,
  parameter int READ_OSTD_DEPTH = 8,
  parameter int WRITE_DATA_QUEUE_DEPTH = 16,
  parameter int READ_DATA_QUEUE_DEPTH = 16,
  parameter int B_FIFO_DEPTH = 8,
  parameter int W_ACCEPT_INTERVAL = 1,
  parameter int CMD_REQ_DEPTH = 4
) (
  input  logic        aclk,
  input  logic        ctrl_clk,
  input  logic        arstn,
  input  logic        init_block,    // ctrl_clk domain
  input  logic [63:0] cycle_now,     // ctrl_clk domain

  // AW
  input  logic        awvalid,
  input  logic [32:0] awaddr,
  input  logic [1:0]  awburst,
  input  logic [5:0]  awid,
  input  logic [7:0]  awlen,
  input  logic [2:0]  awsize,
  input  logic        awlock,
  input  logic        awapcmd,
  input  logic [3:0]  awqos,
  input  logic [3:0]  awcache,
  input  logic        awallstrb,
  input  logic        awcobuf,
  output logic        awready,

  // W
  input  logic [511:0] wdata,
  input  logic         wlast,
  input  logic [63:0]  wstrb,
  input  logic         wvalid,
  output logic         wready,

  // B
  output logic        bvalid,
  output logic [5:0]  bid,
  output logic [1:0]  bresp,
  input  logic        bready,

  // AR
  input  logic        arvalid,
  input  logic [32:0] araddr,
  input  logic [1:0]  arburst,
  input  logic [5:0]  arid,
  input  logic [7:0]  arlen,
  input  logic [2:0]  arsize,
  input  logic        arlock,
  input  logic        arapcmd,
  input  logic [3:0]  arqos,
  output logic        arready,

  // R
  output logic [511:0] rdata,
  output logic [5:0]   rid,
  output logic         rlast,
  output logic [1:0]   rresp,
  output logic         rvalid,
  input  logic         rready,

  // ctrl-side command FIFO read ports
  input  logic        aw_cmd_pop,
  output logic        aw_cmd_empty,
  output logic [57:0] aw_cmd_head,
  input  logic        ar_cmd_pop,
  output logic        ar_cmd_empty,
  output logic [57:0] ar_cmd_head,

  // ctrl-side W data FIFO read port
  input  logic         w_pop,
  output logic [640:0] w_head,      // ddr_wbeat_t; timestamp is ctrl cycle_now
  output logic         w_empty,
  output logic [31:0]  w_count,

  // ctrl-side B/R FIFO push ports
  input  logic        b_push,
  input  logic [7:0]  b_in,
  output logic        b_full,
  input  logic        r_push,
  input  logic [520:0] r_in,
  output logic         r_full,

  output logic [31:0] wr_ostd,
  output logic [31:0] rd_ostd
);
  import ddr_model_pkg::*;

  // ------------------------------------------------------------------
  // init_block into the ACLK domain
  // ------------------------------------------------------------------
  logic [1:0] init_sync;
  logic       init_blk_a;

  always_ff @(posedge aclk or negedge arstn) begin
    if (!arstn) init_sync <= 2'b00;
    else        init_sync <= {init_sync[0], init_block};
  end

  assign init_blk_a = init_sync[1];

  // ------------------------------------------------------------------
  // AW command FIFO (ACLK -> ctrl)
  // ------------------------------------------------------------------
  ddr_req_t aw_word;
  logic     aw_cmd_full;
  logic [57:0] aw_fifo_din, aw_fifo_dout;

  assign aw_word = {awaddr, awlen, awsize, awburst, awid, awcache,
                    awcobuf, awallstrb};
  assign aw_fifo_din = aw_word;

  ddr_async_fifo #(.DEPTH(CMD_REQ_DEPTH), .WIDTH(58)) u_awq (
    .wclk   (aclk),
    .wrst_n (arstn),
    .push   (awvalid && awready),
    .din    (aw_fifo_din),
    .full   (aw_cmd_full),
    .wempty (),
    .rclk   (ctrl_clk),
    .rrst_n (arstn),
    .pop    (aw_cmd_pop),
    .dout   (aw_fifo_dout),
    .empty  (aw_cmd_empty),
    .rcount ()
  );

  assign aw_cmd_head = aw_fifo_dout;

  // ------------------------------------------------------------------
  // AR command FIFO (ACLK -> ctrl)
  // ------------------------------------------------------------------
  ddr_req_t ar_word;
  logic     ar_cmd_full;
  logic [57:0] ar_fifo_din, ar_fifo_dout;

  assign ar_word = {araddr, arlen, arsize, arburst, arid, 4'b0000,
                    1'b0, 1'b0};
  assign ar_fifo_din = ar_word;

  ddr_async_fifo #(.DEPTH(CMD_REQ_DEPTH), .WIDTH(58)) u_arq (
    .wclk   (aclk),
    .wrst_n (arstn),
    .push   (arvalid && arready),
    .din    (ar_fifo_din),
    .full   (ar_cmd_full),
    .wempty (),
    .rclk   (ctrl_clk),
    .rrst_n (arstn),
    .pop    (ar_cmd_pop),
    .dout   (ar_fifo_dout),
    .empty  (ar_cmd_empty),
    .rcount ()
  );

  assign ar_cmd_head = ar_fifo_dout;

  // ------------------------------------------------------------------
  // W data FIFO (ACLK -> ctrl)
  // ------------------------------------------------------------------
  logic [576:0] w_dout;
  logic         w_full, w_empty_w, w_push;
  logic [31:0]  w_gap;

  assign w_push = wvalid && wready;

  ddr_async_fifo #(.DEPTH(WRITE_DATA_QUEUE_DEPTH), .WIDTH(577)) u_wfifo (
    .wclk   (aclk),
    .wrst_n (arstn),
    .push   (w_push),
    .din    ({wdata, wstrb, wlast}),
    .full   (w_full),
    .wempty (w_empty_w),
    .rclk   (ctrl_clk),
    .rrst_n (arstn),
    .pop    (w_pop),
    .dout   (w_dout),
    .empty  (w_empty),
    .rcount (w_count)
  );

  always_ff @(posedge aclk or negedge arstn) begin
    if (!arstn) w_gap <= '0;
    else if (w_push) w_gap <= (W_ACCEPT_INTERVAL > 1) ? 32'(W_ACCEPT_INTERVAL-1) : '0;
    else if (w_gap != 0) w_gap <= w_gap - 1;
  end

  always_comb begin
    wready = arstn && !init_blk_a && !w_full;
    if (W_ACCEPT_INTERVAL > 1) wready = wready && (w_gap == 0);
  end

  // The ctrl side stamps each beat with its own cycle counter so write
  // response deadlines stay in ctrl_clk units.
  assign w_head = {w_dout, cycle_now};

  // ------------------------------------------------------------------
  // B response FIFO (ctrl -> ACLK)
  // ------------------------------------------------------------------
  logic [7:0] b_dout;
  logic       b_empty;

  ddr_async_fifo #(.DEPTH(B_FIFO_DEPTH), .WIDTH(8)) u_bfifo (
    .wclk   (ctrl_clk),
    .wrst_n (arstn),
    .push   (b_push),
    .din    (b_in),
    .full   (b_full),
    .wempty (),
    .rclk   (aclk),
    .rrst_n (arstn),
    .pop    (bvalid && bready),
    .dout   (b_dout),
    .empty  (b_empty),
    .rcount ()
  );

  assign bvalid = arstn && !b_empty;
  assign bid    = bvalid ? b_dout[7:2] : 6'h0;
  assign bresp  = bvalid ? b_dout[1:0] : 2'b00;

  // ------------------------------------------------------------------
  // R response FIFO (ctrl -> ACLK)
  // ------------------------------------------------------------------
  logic [520:0] r_dout;
  logic         r_empty;

  ddr_async_fifo #(.DEPTH(READ_DATA_QUEUE_DEPTH), .WIDTH(521)) u_rfifo (
    .wclk   (ctrl_clk),
    .wrst_n (arstn),
    .push   (r_push),
    .din    (r_in),
    .full   (r_full),
    .wempty (),
    .rclk   (aclk),
    .rrst_n (arstn),
    .pop    (rvalid && rready),
    .dout   (r_dout),
    .empty  (r_empty),
    .rcount ()
  );

  assign rvalid = arstn && !r_empty;
  assign rdata  = rvalid ? r_dout[520:9] : 512'h0;
  assign rid    = rvalid ? r_dout[8:3] : 6'h0;
  assign rlast  = rvalid ? r_dout[2] : 1'b0;
  assign rresp  = rvalid ? r_dout[1:0] : 2'b00;

  // ------------------------------------------------------------------
  // outstanding counters (ACLK domain)
  // ------------------------------------------------------------------
  logic aw_hs, ar_hs, b_hs, rlast_hs;

  assign aw_hs    = awvalid && awready;
  assign ar_hs    = arvalid && arready;
  assign b_hs     = bvalid && bready;
  assign rlast_hs = rvalid && rready && rlast;

  always_ff @(posedge aclk or negedge arstn) begin
    if (!arstn) begin
      wr_ostd <= '0;
      rd_ostd <= '0;
    end else begin
      wr_ostd <= wr_ostd + 32'(aw_hs) - 32'(b_hs);
      rd_ostd <= rd_ostd + 32'(ar_hs) - 32'(rlast_hs);
    end
  end

  // ------------------------------------------------------------------
  // channel acceptance
  // ------------------------------------------------------------------
  logic w_data_available;
  assign w_data_available = wvalid || !w_empty_w;

  always_comb begin
    awready = arstn && !init_blk_a && awvalid && w_data_available &&
              (wr_ostd < 32'(WRITE_OSTD_DEPTH)) && !aw_cmd_full;
    arready = arstn && !init_blk_a && arvalid &&
              (rd_ostd < 32'(READ_OSTD_DEPTH)) && !ar_cmd_full;
  end

  // unused sidebands are accepted and ignored [MODEL]
  logic _unused;
  assign _unused = awlock ^ awapcmd ^ awcobuf ^ arlock ^ arapcmd ^
                   (|awqos) ^ (|arqos) ^ (|awcache) ^ awallstrb;

endmodule
