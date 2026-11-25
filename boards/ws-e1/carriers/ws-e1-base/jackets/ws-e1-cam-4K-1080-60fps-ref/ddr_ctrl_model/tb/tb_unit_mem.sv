// Unit tests for mem_model (PLAN P1): byte strobes, narrow lane reads,
// init modes, backdoor, and CFG_RESET_CLEAR_MEM.
module tb_unit_mem;
  import ddr_model_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  // zero-init DUT, main stimulus target
  logic         we0, re0;
  logic [32:0]  waddr0, raddr0;
  logic [511:0] wdata0;
  logic [63:0]  wstrb0;
  logic [2:0]   rsize0;
  logic [511:0] rdata0;
  logic         rvalid0;

  // random-init DUT
  logic         re1;
  logic [32:0]  raddr1;
  logic [2:0]   rsize1;
  logic [511:0] rdata1;
  logic         rvalid1;

  // pattern-init DUT
  logic         re2;
  logic [32:0]  raddr2;
  logic [2:0]   rsize2;
  logic [511:0] rdata2;
  logic         rvalid2;

  // clear-on-reset DUT
  logic         cfg_reset_clear;
  logic         re3;
  logic [32:0]  raddr3;
  logic [2:0]   rsize3;
  logic [511:0] rdata3;
  logic         rvalid3;

  int errs = 0;

  mem_model #(
    .MEM_BYTES(64'h2000_0000), .MEM_INIT_MODE(0)
  ) mem0 (
    .clk(clk), .cfg_reset(1'b0),
    .we(we0), .waddr(waddr0), .wdata(wdata0), .wstrb(wstrb0),
    .re(re0), .raddr(raddr0), .rsize(rsize0),
    .rdata(rdata0), .rvalid(rvalid0)
  );

  mem_model #(
    .MEM_BYTES(64'h2000_0000), .MEM_INIT_MODE(1), .MEM_INIT_SEED(32'h1)
  ) mem1 (
    .clk(clk), .cfg_reset(1'b0),
    .we(1'b0), .waddr(33'h0), .wdata(512'h0), .wstrb(64'h0),
    .re(re1), .raddr(raddr1), .rsize(rsize1),
    .rdata(rdata1), .rvalid(rvalid1)
  );

  mem_model #(
    .MEM_BYTES(64'h2000_0000), .MEM_INIT_MODE(2)
  ) mem2 (
    .clk(clk), .cfg_reset(1'b0),
    .we(1'b0), .waddr(33'h0), .wdata(512'h0), .wstrb(64'h0),
    .re(re2), .raddr(raddr2), .rsize(rsize2),
    .rdata(rdata2), .rvalid(rvalid2)
  );

  mem_model #(
    .MEM_BYTES(64'h2000_0000), .MEM_INIT_MODE(0), .CFG_RESET_CLEAR_MEM(1'b1)
  ) mem3 (
    .clk(clk), .cfg_reset(cfg_reset_clear),
    .we(1'b0), .waddr(33'h0), .wdata(512'h0), .wstrb(64'h0),
    .re(re3), .raddr(raddr3), .rsize(rsize3),
    .rdata(rdata3), .rvalid(rvalid3)
  );

  task automatic chk(input bit cond, input string msg);
    if (!cond) begin
      errs++;
      $error("[MEM] %s", msg);
    end
  endtask

  task automatic chk_byte(input logic [511:0] d, input int lane,
                          input logic [7:0] exp, input string msg);
    if (d[8*lane +: 8] !== exp) begin
      errs++;
      $error("[MEM] %s lane%0d got=%02h exp=%02h", msg, lane,
             d[8*lane +: 8], exp);
    end
  endtask

  task automatic wr(input logic [32:0] a, input logic [511:0] d,
                    input logic [63:0] s);
    @(negedge clk);
    we0 = 1'b1; waddr0 = a; wdata0 = d; wstrb0 = s;
    @(negedge clk);
    we0 = 1'b0;
  endtask

  task automatic rd(input logic [32:0] a, input logic [2:0] sz,
                    output logic [511:0] d);
    @(negedge clk);
    re0 = 1'b1; raddr0 = a; rsize0 = sz;
    #1 d = rdata0;
    @(negedge clk);
    re0 = 1'b0;
  endtask

  initial begin
    logic [511:0] d, got;
    logic [511:0] d1, d2, d3;
    logic [7:0]   b;
    int           used;
    string        t;

    we0 = 0; re0 = 0; waddr0 = 0; raddr0 = 0; wdata0 = 0; wstrb0 = 0;
    rsize0 = 6;
    re1 = 0; raddr1 = 0; rsize1 = 6;
    re2 = 0; raddr2 = 0; rsize2 = 6;
    re3 = 0; raddr3 = 0; rsize3 = 6;
    cfg_reset_clear = 0;

    repeat (2) @(posedge clk);

    // unwritten read returns zero
    rd(33'h0000_2000, 3'd6, got);
    chk(got === 512'h0, "zero init unwritten block");
    chk(rvalid0 === 1'b1, "rvalid during read");

    // full-block write with byte pattern
    for (int n = 0; n < 64; n++) d[8*n +: 8] = 8'((n * 3 + 1) & 8'hFF);
    wr(33'h0000_3000, d, 64'hFFFF_FFFF_FFFF_FFFF);
    rd(33'h0000_3000, 3'd6, got);
    chk(got === d, "full block write/read");

    // partial strobe: only lanes 8..15 at 0x4000
    for (int n = 0; n < 64; n++) d[8*n +: 8] = 8'(8'h80 + n);
    wr(33'h0000_4000, d, 64'h0000_0000_0000_FF00);
    rd(33'h0000_4000, 3'd6, got);
    chk(got[511:128] === 384'h0, "partial write untouched high lanes");
    chk(got[63:0] === 64'h0, "partial write untouched low lanes");
    for (int n = 8; n < 16; n++) chk_byte(got, n, 8'(8'h80 + n), "partial write");
    chk(mem0.bd_used_bytes() == 72, "partial write allocates 8 more bytes");

    // narrow write using strobe lanes 16..19 at 0x4010
    for (int n = 0; n < 64; n++) d[8*n +: 8] = 8'(8'h40 + n);
    wr(33'h0000_4010, d, 64'h0000_0000_000F_0000);
    rd(33'h0000_4010, 3'd2, got);
    for (int n = 0; n < 64; n++) begin
      if ((n >= 16) && (n < 20))
        chk_byte(got, n, 8'(8'h40 + n), "narrow write lane");
      else
        chk_byte(got, n, 8'h00, "narrow read invalid lane");
    end

    // narrow read from 0x4008 (4 bytes) uses lanes 8..11
    rd(33'h0000_4008, 3'd2, got);
    for (int n = 8; n < 12; n++) chk_byte(got, n, 8'(8'h80 + n), "narrow read lane");
    for (int n = 0; n < 8; n++) chk_byte(got, n, 8'h00, "narrow read zero low");
    for (int n = 12; n < 64; n++) chk_byte(got, n, 8'h00, "narrow read zero high");

    // backdoor
    mem0.bd_write(64'h0000_5000, 8'hC7);
    mem0.bd_read(64'h0000_5000, b);
    chk(b == 8'hC7, "bd_write/bd_read");
    mem0.bd_write64(64'h0000_5040, d);
    rd(33'h0000_5040, 3'd6, got);
    chk(got === d, "bd_write64 visible to read port");
    used = mem0.bd_used_bytes();
    chk(used > 0, "bd_used_bytes nonzero");
    mem0.bd_clear();
    chk(mem0.bd_used_bytes() == 0, "bd_clear empties array");
    rd(33'h0000_3000, 3'd6, got);
    chk(got === 512'h0, "read after bd_clear returns zero");

    // RANDOM init mode
    @(negedge clk); re1 = 1; raddr1 = 33'h0000_2222; rsize1 = 3'd0;
    #1 d1 = rdata1;
    @(negedge clk); re1 = 0;
    chk_byte(d1, 16'h22, hash_byte(64'h0000_2222, 32'h1), "random init lane");
    mem1.bd_read(64'h0000_2222, b);
    chk(b == hash_byte(64'h0000_2222, 32'h1), "random init backdoor");

    // PATTERN init mode
    @(negedge clk); re2 = 1; raddr2 = 33'h0000_1234; rsize2 = 3'd0;
    #1 d2 = rdata2;
    @(negedge clk); re2 = 0;
    chk_byte(d2, 16'h34, pattern_byte(64'h0000_1234), "pattern init lane");

    // CFG_RESET_CLEAR_MEM
    mem3.bd_write(64'h0000_6000, 8'h5A);
    mem3.bd_write(64'h0000_6001, 8'hA5);
    chk(mem3.bd_used_bytes() == 2, "clear-mode preload");
    @(negedge clk); cfg_reset_clear = 1;
    repeat (2) @(posedge clk);
    @(negedge clk); cfg_reset_clear = 0;
    chk(mem3.bd_used_bytes() == 0, "CFG_RESET_CLEAR_MEM clears array");
    mem3.bd_read(64'h0000_6000, b);
    chk(b == 8'h00, "clear-mode read zero");

    if (errs == 0) begin
      $display("TEST all PASS");
      $finish;
    end else begin
      $display("TEST all FAIL errors=%0d", errs);
      $fatal(1, "mem unit test failed");
    end
  end
endmodule
