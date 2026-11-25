// Dual-clock FIFO with gray-code pointers and 2-FF pointer synchronizers.
// Reset deassertion is synchronized independently in each clock domain, so
// wrst_n/rrst_n may be driven by the same asynchronous port reset.
module ddr_async_fifo #(
  parameter int DEPTH = 16,
  parameter int WIDTH = 32
) (
  input  logic             wclk,
  input  logic             wrst_n,
  input  logic             push,
  input  logic [WIDTH-1:0] din,
  output logic             full,
  output logic             wempty,   // write-domain empty view

  input  logic             rclk,
  input  logic             rrst_n,
  input  logic             pop,
  output logic [WIDTH-1:0] dout,
  output logic             empty,
  output logic [31:0]      rcount
);
  localparam int ADDR_W = $clog2(DEPTH);
  localparam int PTR_W  = ADDR_W + 1;

  initial begin
    if ((DEPTH < 2) || ((DEPTH & (DEPTH - 1)) != 0))
      $fatal(1, "ddr_async_fifo DEPTH=%0d must be a power of two >= 2", DEPTH);
  end

  logic [WIDTH-1:0] mem [0:DEPTH-1];

  // ------------------------------------------------------------------
  // reset deassertion synchronizers
  // ------------------------------------------------------------------
  logic [1:0] wsync, rsync;
  logic       wactive, ractive;

  always_ff @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) wsync <= 2'b00;
    else         wsync <= {wsync[0], 1'b1};
  end

  always_ff @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) rsync <= 2'b00;
    else         rsync <= {rsync[0], 1'b1};
  end

  assign wactive = wsync[1];
  assign ractive = rsync[1];

  // ------------------------------------------------------------------
  // pointers
  // ------------------------------------------------------------------
  logic [PTR_W-1:0] wbin, wgray, rbin, rgray;
  logic [PTR_W-1:0] wq1_rgray, wq2_rgray;
  logic [PTR_W-1:0] rq1_wgray, rq2_wgray;

  function automatic logic [PTR_W-1:0] gray_of(input logic [PTR_W-1:0] bin);
    return (bin >> 1) ^ bin;
  endfunction

  function automatic logic [PTR_W-1:0] inv_top2(input logic [PTR_W-1:0] g);
    logic [PTR_W-1:0] t;
    t = g;
    t[PTR_W-1] = ~g[PTR_W-1];
    t[PTR_W-2] = ~g[PTR_W-2];
    return t;
  endfunction

  function automatic logic [PTR_W-1:0] gray2bin(input logic [PTR_W-1:0] g);
    logic [PTR_W-1:0] b;
    b = '0;
    for (int i = 0; i < PTR_W; i++) b[i] = ^(g >> i);
    return b;
  endfunction

  logic wfull_i, rempty_i, do_wr, do_rd;

  assign wfull_i  = (wgray == inv_top2(wq2_rgray));
  assign rempty_i = (rgray == rq2_wgray);

  assign full   = !wactive || wfull_i;
  assign empty  = !ractive || rempty_i;
  assign wempty = !wactive || (wgray == wq2_rgray);

  assign do_wr = push && !full;
  assign do_rd = pop && !empty;

  always_ff @(posedge wclk) begin
    if (!wactive) begin
      wbin  <= '0;
      wgray <= '0;
    end else if (do_wr) begin
      wbin  <= wbin + 1'b1;
      wgray <= gray_of(wbin + 1'b1);
    end
  end

  always_ff @(posedge rclk) begin
    if (!ractive) begin
      rbin  <= '0;
      rgray <= '0;
    end else if (do_rd) begin
      rbin  <= rbin + 1'b1;
      rgray <= gray_of(rbin + 1'b1);
    end
  end

  always_ff @(posedge wclk) begin
    if (!wactive) begin
      wq1_rgray <= '0;
      wq2_rgray <= '0;
    end else begin
      wq1_rgray <= rgray;
      wq2_rgray <= wq1_rgray;
    end
  end

  always_ff @(posedge rclk) begin
    if (!ractive) begin
      rq1_wgray <= '0;
      rq2_wgray <= '0;
    end else begin
      rq1_wgray <= wgray;
      rq2_wgray <= rq1_wgray;
    end
  end

  always_ff @(posedge wclk) begin
    if (do_wr) mem[wbin[ADDR_W-1:0]] <= din;
  end

  assign dout   = mem[rbin[ADDR_W-1:0]];
  assign rcount = 32'(gray2bin(rq2_wgray) - gray2bin(rgray));

endmodule
