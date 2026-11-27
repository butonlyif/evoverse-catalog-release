// Idealized DRAM storage array.
// Sparse byte associative array: only written bytes are allocated. Unwritten
// bytes follow MEM_INIT_MODE, which is a documented [MODEL] deviation.
module mem_model #(
  parameter longint unsigned MEM_BYTES = 64'h2000_0000,
  parameter int  MEM_INIT_MODE = 0,      // 0=ZERO 1=RANDOM 2=PATTERN
  parameter logic [31:0] MEM_INIT_SEED = 32'h1,
  parameter bit  CFG_RESET_CLEAR_MEM = 1'b0
) (
  input  logic               clk,
  input  logic               cfg_reset,
  input  logic               we,
  input  logic [32:0]        waddr,
  input  logic [511:0]       wdata,
  input  logic [63:0]        wstrb,
  input  logic               re,
  input  logic [32:0]        raddr,
  input  logic [2:0]         rsize,
  output logic [511:0]       rdata,
  output logic               rvalid
);
  byte unsigned mem [longint unsigned];

  function automatic byte unsigned get_byte(input longint unsigned a);
    if (mem.exists(a)) return mem[a];
    case (MEM_INIT_MODE)
      1: return ddr_model_pkg::hash_byte(a, MEM_INIT_SEED);
      2: return ddr_model_pkg::pattern_byte(a);
      default: return 8'h00;
    endcase
  endfunction

  // byte-lane writes: WSTRB[n] -> WDATA[8n+7:8n], lane n at (waddr & ~63)+n
  always_ff @(posedge clk) begin
    longint unsigned base;
    if (cfg_reset && CFG_RESET_CLEAR_MEM) begin
      mem.delete();
    end else if (we) begin
      base = longint'(waddr) & ~64'h3F;
      for (int n = 0; n < 64; n++) begin
        if (wstrb[n]) mem[base + longint'(n)] = wdata[8*n +: 8];
      end
    end
  end

  // Combinational 64-byte-aligned block read. Narrow transfers are shifted to
  // the byte lanes selected by addr[5:0]; invalid lanes read as zero.
  always_comb begin
    longint unsigned base;
    int off;
    longint unsigned sb;
    rdata  = '0;
    rvalid = re;
    if (re) begin
      base = longint'(raddr) & ~64'h3F;
      off  = int'(raddr[5:0]);
      sb   = ddr_model_pkg::size_bytes(rsize);
      for (int j = 0; j < 64; j++) begin
        if ((longint'(j) >= longint'(off)) &&
            (longint'(j) < longint'(off) + sb) &&
            ((off + (j - off)) < 64)) begin
          rdata[8*j +: 8] = get_byte(base + longint'(j));
        end
      end
    end
  end

  // ------------------------------------------------------------------
  // backdoor (simulation only)
  // ------------------------------------------------------------------
  task automatic bd_write(input longint unsigned a, input byte unsigned d);
    mem[a] = d;
  endtask

  task automatic bd_write64(input longint unsigned a, input logic [511:0] d);
    for (int n = 0; n < 64; n++) mem[a + longint'(n)] = d[8*n +: 8];
  endtask

  task automatic bd_read(input longint unsigned a, output byte unsigned d);
    d = get_byte(a);
  endtask

  task automatic bd_clear();
    mem.delete();
  endtask

  function automatic int bd_used_bytes();
    return mem.num();
  endfunction

endmodule
