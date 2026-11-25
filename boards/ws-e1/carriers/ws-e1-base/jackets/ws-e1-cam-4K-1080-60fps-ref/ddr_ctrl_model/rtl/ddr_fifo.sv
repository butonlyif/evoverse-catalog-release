// Synchronous FIFO. v0.1 uses a single clock for both ports; the module
// boundary is kept separate so an asynchronous implementation can replace it.
module ddr_fifo #(
  parameter int DEPTH = 8,
  parameter int WIDTH = 32
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             push,
  input  logic [WIDTH-1:0] din,
  input  logic             pop,
  output logic [WIDTH-1:0] dout,
  output logic             full,
  output logic             empty,
  output logic [31:0]      count
);
  localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH+1);

  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [PTR_W-1:0] wr_ptr;
  logic [PTR_W-1:0] rd_ptr;
  logic [PTR_W-1:0] used;
  logic             do_push;
  logic             do_pop;

  assign full    = (used == PTR_W'(DEPTH));
  assign empty   = (used == '0);
  assign count   = 32'(used);
  assign dout    = mem[rd_ptr];
  assign do_push = push && !full;
  assign do_pop  = pop && !empty;


  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      used   <= '0;
    end else begin
      if (do_push) begin
        mem[wr_ptr] <= din;
        wr_ptr <= (wr_ptr == PTR_W'(DEPTH-1)) ? '0 : wr_ptr + 1'b1;
      end
      if (do_pop) begin
        rd_ptr <= (rd_ptr == PTR_W'(DEPTH-1)) ? '0 : rd_ptr + 1'b1;
      end
      used <= used + PTR_W'(do_push) - PTR_W'(do_pop);
    end
  end

  // synopsys translate_off
  always_ff @(posedge clk) begin
    if (rst_n && (push && full) && !pop) begin
      $warning("ddr_fifo overflow: push while full (depth=%0d)", DEPTH);
    end
  end
  // synopsys translate_on

endmodule
