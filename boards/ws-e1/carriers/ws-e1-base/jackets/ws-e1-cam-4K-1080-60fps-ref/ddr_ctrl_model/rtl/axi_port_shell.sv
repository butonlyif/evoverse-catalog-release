// One AXI4 slave port: channel handshakes, per-port W/B/R FIFOs, outstanding
// counters and command request generation. The shared command queue and
// arbiter live in the top level.
//
// v0.1 note: ACLK is tied to ctrl_clk by the top level; CDC-mode FIFOs are a
// later phase (PLAN P6).
module axi_port_shell #(
  parameter int PORT = 0,
  parameter int WRITE_OSTD_DEPTH = 8,
  parameter int READ_OSTD_DEPTH = 8,
  parameter int WRITE_DATA_QUEUE_DEPTH = 16,
  parameter int READ_DATA_QUEUE_DEPTH = 16,
  parameter int B_FIFO_DEPTH = 8,
  parameter int W_ACCEPT_INTERVAL = 1
) (
  input  logic        clk,
  input  logic        arstn,
  input  logic        init_block,   // INIT_AXI_BLOCK && init_busy
  input  logic [63:0] cycle_now,

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
  output logic        aw_req,
  input  logic        aw_grant,

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
  output logic        ar_req,
  input  logic        ar_grant,

  // R
  output logic [511:0] rdata,
  output logic [5:0]   rid,
  output logic         rlast,
  output logic [1:0]   rresp,
  output logic         rvalid,
  input  logic         rready,

  // command-queue space from the top level
  input  logic        cmd_space,

  // write-data FIFO read side (core consumes)
  input  logic        w_pop,
  output logic [640:0] w_head,   // ddr_wbeat_t
  output logic         w_empty,
  output logic [31:0]  w_count,

  // B response FIFO push side (core produces)
  input  logic        b_push,
  input  logic [7:0]  b_in,      // ddr_bresp_t
  output logic        b_full,

  // R response FIFO push side (core produces)
  input  logic        r_push,
  input  logic [520:0] r_in,     // ddr_rbeat_t
  output logic         r_full,

  // status
  output logic [31:0] wr_ostd,
  output logic [31:0] rd_ostd
);
  import ddr_model_pkg::*;

  // ---------------------------------------------------------------
  // W data FIFO
  // ---------------------------------------------------------------
  logic [640:0] w_dout;
  logic         w_full;
  logic         w_push;
  logic [31:0]  w_gap;

  assign w_push = wvalid && wready;
  assign w_head = w_dout;

  ddr_fifo #(.DEPTH(WRITE_DATA_QUEUE_DEPTH), .WIDTH(641)) u_wfifo (
    .clk   (clk),
    .rst_n (arstn),
    .push  (w_push),
    .din   ({wdata, wstrb, wlast, cycle_now}),
    .pop   (w_pop),
    .dout  (w_dout),
    .full  (w_full),
    .empty (w_empty),
    .count (w_count)
  );

  // The beat timestamp (W handshake time) is carried in the FIFO and used by
  // the core to schedule T_WLAST_B.
  always_ff @(posedge clk or negedge arstn) begin
    if (!arstn) w_gap <= '0;
    else if (w_push) w_gap <= (W_ACCEPT_INTERVAL > 1) ? 32'(W_ACCEPT_INTERVAL-1) : '0;
    else if (w_gap != 0) w_gap <= w_gap - 1;
  end

  always_comb begin
    wready = arstn && !init_block && !w_full;
    if (W_ACCEPT_INTERVAL > 1) wready = wready && (w_gap == 0);
  end

  // ---------------------------------------------------------------
  // B response FIFO
  // ---------------------------------------------------------------
  logic [7:0] b_dout;
  logic       b_empty;
  logic       b_pop;

  ddr_fifo #(.DEPTH(B_FIFO_DEPTH), .WIDTH(8)) u_bfifo (
    .clk   (clk),
    .rst_n (arstn),
    .push  (b_push),
    .din   (b_in),
    .pop   (b_pop),
    .dout  (b_dout),
    .full  (b_full),
    .empty (b_empty),
    .count ()
  );

  assign bvalid = arstn && !b_empty;
  assign bid    = bvalid ? b_dout[7:2] : 6'h0;
  assign bresp  = bvalid ? b_dout[1:0] : 2'b00;
  assign b_pop  = bvalid && bready;

  // ---------------------------------------------------------------
  // R response FIFO
  // ---------------------------------------------------------------
  logic [520:0] r_dout;
  logic         r_empty;
  logic         r_pop;

  ddr_fifo #(.DEPTH(READ_DATA_QUEUE_DEPTH), .WIDTH(521)) u_rfifo (
    .clk   (clk),
    .rst_n (arstn),
    .push  (r_push),
    .din   (r_in),
    .pop   (r_pop),
    .dout  (r_dout),
    .full  (r_full),
    .empty (r_empty),
    .count ()
  );

  assign rvalid = arstn && !r_empty;
  assign rdata  = rvalid ? r_dout[520:9] : 512'h0;
  assign rid    = rvalid ? r_dout[8:3] : 6'h0;
  assign rlast  = rvalid ? r_dout[2] : 1'b0;
  assign rresp  = rvalid ? r_dout[1:0] : 2'b00;
  assign r_pop  = rvalid && rready;

  // ---------------------------------------------------------------
  // outstanding counters
  // ---------------------------------------------------------------
  logic aw_hs;
  logic ar_hs;
  logic b_hs;
  logic rlast_hs;

  always_ff @(posedge clk or negedge arstn) begin
    if (!arstn) begin
      wr_ostd <= '0;
      rd_ostd <= '0;
    end else begin
      wr_ostd <= wr_ostd + 32'(aw_hs) - 32'(b_hs);
      rd_ostd <= rd_ostd + 32'(ar_hs) - 32'(rlast_hs);
    end
  end

  // ---------------------------------------------------------------
  // command requests
  // ---------------------------------------------------------------
  logic w_data_available;
  assign w_data_available = wvalid || !w_empty;

  always_comb begin
    aw_req = arstn && !init_block && awvalid && w_data_available &&
             (wr_ostd < 32'(WRITE_OSTD_DEPTH)) && cmd_space;
    ar_req = arstn && !init_block && arvalid &&
             (rd_ostd < 32'(READ_OSTD_DEPTH)) && cmd_space;
    awready = aw_req && aw_grant;
    arready = ar_req && ar_grant;
  end

  assign aw_hs = awvalid && awready;
  assign ar_hs = arvalid && arready;
  assign b_hs  = bvalid && bready;
  assign rlast_hs = rvalid && rready && rlast;

  // unused sideband signals are accepted and ignored [MODEL]
  // verilator lint_off UNUSEDSIGNAL
  logic _unused;
  assign _unused = awlock ^ awapcmd ^ awcobuf ^ arlock ^ arapcmd ^
                   (|awqos) ^ (|arqos) ^ (|awcache) ^ awallstrb;
  // verilator lint_on UNUSEDSIGNAL

endmodule
