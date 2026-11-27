// TJ DDR hard-controller AXI behavior model - shared package
// Spec: SPEC-DDR-AXI-MODEL-v0.2
package ddr_model_pkg;

  localparam int AXI_DATA_WIDTH = 512;
  localparam int AXI_STRB_WIDTH = AXI_DATA_WIDTH/8;   // 64
  localparam int AXI_ADDR_WIDTH = 33;
  localparam int AXI_ID_WIDTH   = 6;

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [1:0] RESP_DECERR = 2'b11;

  localparam logic [1:0] BURST_FIXED = 2'b00;
  localparam logic [1:0] BURST_INCR  = 2'b01;
  localparam logic [1:0] BURST_WRAP  = 2'b10;

  // err bit map
  localparam int ERR_BURST_SIZE    = 0;
  localparam int ERR_BURST_LEN     = 1;
  localparam int ERR_CROSS_4KB     = 2;
  localparam int ERR_ADDR_RANGE    = 3;
  localparam int ERR_FIXED_BURST   = 4;
  localparam int ERR_ALLSTRB_BEATS = 5;
  localparam int ERR_ALLSTRB_WSTRB = 6;
  localparam int ERR_WRAP          = 7;
  localparam int ERR_BURST_TYPE    = 8;
  localparam int ERR_ALIGN         = 9;
  localparam int ERR_ARSTN_ABORT   = 10;
  localparam int ERR_NARROW_DISABLED = 11;
  localparam int ERR_ADDR_HOLE       = 12;

  // reserved command/target index values
  localparam int PORT0 = 0;
  localparam int PORT1 = 1;

  typedef struct packed {
    logic         is_write;
    logic [1:0]   port;
    logic [32:0]  addr;
    logic [7:0]   len;
    logic [2:0]   size;
    logic [1:0]   burst;
    logic [5:0]   id;
    logic [3:0]   cache;
    logic         cobuf;
    logic         allstrb;
    logic [1:0]   resp;       // response known at acceptance (precheck)
    logic [15:0]  err;        // one-hot / multi-hot error flags
    logic [63:0]  beats;      // len + 1
    logic [63:0]  t_accept;   // accept timestamp, ctrl_clk cycles
    logic [63:0]  lat;        // latency drawn for this command
  } ddr_cmd_t;

  // Command payload carried across the ACLK -> ctrl_clk boundary by the
  // asynchronous CDC port shell.
  typedef struct packed {
    logic [32:0] addr;
    logic [7:0]  len;
    logic [2:0]  size;
    logic [1:0]  burst;
    logic [5:0]  id;
    logic [3:0]  cache;
    logic        cobuf;
    logic        allstrb;
  } ddr_req_t;

  typedef struct packed {
    logic [AXI_DATA_WIDTH-1:0] data;
    logic [AXI_STRB_WIDTH-1:0] strb;
    logic                      last;
    logic [63:0]               t_accept;
  } ddr_wbeat_t;

  typedef struct packed {
    logic [AXI_DATA_WIDTH-1:0] data;
    logic [AXI_ID_WIDTH-1:0]   id;
    logic                      last;
    logic [1:0]                resp;
  } ddr_rbeat_t;

  typedef struct packed {
    logic [AXI_ID_WIDTH-1:0] id;
    logic [1:0]              resp;
  } ddr_bresp_t;

  // Debug-only address field decode (ADDR_MAP_MODE=FIELD_DECODE_DEBUG).
  // Default profile matches the UG example: CS[27], ROW[26:12],
  // BANK[11:9], COLUMN[8:2], DATAPATH[1:0]. Memory access always uses the
  // undecoded linear address.
  typedef struct packed {
    logic [4:0]  unused;
    logic        cs;
    logic [14:0] row;
    logic [2:0]  bank;
    logic [6:0]  column;
    logic [1:0]  datapath;
  } ddr_addr_fields_t;

  // ------------------------------------------------------------------
  // burst / address helpers
  // ------------------------------------------------------------------

  function automatic longint unsigned burst_bytes(input logic [7:0] len,
                                                  input logic [2:0] size);
    longint unsigned bytes;
    if (size > 6) bytes = 64;
    else          bytes = longint'(1) << size;
    return (longint'(len) + 1) * bytes;
  endfunction

  function automatic longint unsigned size_bytes(input logic [2:0] size);
    if (size > 6) return 64;
    return longint'(1) << size;
  endfunction

  // Table 5 [UG] + AXI4 256-beat limit for SIZE<=3 [AXI4]
  function automatic bit table5_ok(input logic [2:0] size, input logic [7:0] len);
    logic [63:0] beats;
    beats = 64'(len) + 1;
    case (size)
      3'd6: return beats <= 64;
      3'd5: return beats <= 128;
      3'd4: return beats <= 256;
      default: return (size < 7) ? (beats <= 256) : 1'b0;
    endcase
  endfunction

  function automatic bit cross_4kb(input logic [32:0] addr,
                                   input longint unsigned bytes);
    return (longint'(addr[11:0]) + bytes) > 4096;
  endfunction

  function automatic bit wrap_len_ok(input logic [7:0] len);
    logic [63:0] beats;
    beats = 64'(len) + 1;
    return (beats == 2) || (beats == 4) || (beats == 8) || (beats == 16);
  endfunction

  function automatic bit aligned_to_size(input logic [32:0] addr,
                                         input logic [2:0] size);
    longint unsigned sb;
    sb = size_bytes(size);
    return (longint'(addr) % sb) == 0;
  endfunction

  // Beat byte address for INCR / WRAP / FIXED. Returns 64-bit to avoid overflow.
  function automatic longint unsigned beat_addr(input logic [32:0] addr,
                                                input int beat,
                                                input logic [7:0] len,
                                                input logic [2:0] size,
                                                input logic [1:0] burst);
    longint unsigned sb;
    longint unsigned span;
    longint unsigned base;
    longint unsigned off;
    sb = size_bytes(size);
    case (burst)
      BURST_INCR: return longint'(addr) + longint'(beat) * sb;
      BURST_WRAP: begin
        span = (longint'(len) + 1) * sb;
        base = (longint'(addr) / span) * span;
        off  = (longint'(addr) - base + longint'(beat) * sb) % span;
        return base + off;
      end
      default: return longint'(addr); // FIXED
    endcase
  endfunction

  function automatic bit [AXI_STRB_WIDTH-1:0] lane_strobe(input longint unsigned byte_addr,
                                                          input logic [2:0] size);
    longint unsigned sb;
    int off;
    bit [AXI_STRB_WIDTH-1:0] mask;
    sb  = size_bytes(size);
    off = int'(byte_addr % AXI_STRB_WIDTH);
    mask = '0;
    for (int j = 0; j < 64; j++) begin
      if ((j >= off) && (longint'(j) < longint'(off) + sb)) mask[j] = 1'b1;
    end
    return mask;
  endfunction

  // debug byte pattern expected for PATTERN mode / TB data generation
  function automatic logic [7:0] pattern_byte(input longint unsigned addr);
    return addr[7:0];
  endfunction

  function automatic logic [7:0] hash_byte(input longint unsigned addr,
                                           input logic [31:0] seed);
    logic [63:0] x;
    x = addr ^ (addr >> 8) ^ (addr >> 16) ^ (addr >> 24) ^
        (addr >> 32) ^ {32'h0, seed};
    x = x * 64'h9E3779B97F4A7C15;
    return x[7:0];
  endfunction

  function automatic int rank_of(input logic [32:0] addr,
                                 input longint unsigned rank_stride,
                                 input int physical_rank,
                                 input int rank_map_mode,
                                 input int cs_bit_pos);
    case (rank_map_mode)
      0: return 0; // SINGLE_RANK
      1: begin     // CS_STRIDE
        if (rank_stride == 0) return 0;
        if ((longint'(addr) / rank_stride) >= physical_rank) return physical_rank-1;
        return int'(longint'(addr) / rank_stride);
      end
      2: return (cs_bit_pos < 33) ? int'(addr[cs_bit_pos]) : 0; // CS_BIT
      default: return 0;
    endcase
  endfunction

  function automatic longint unsigned calc_mem_bytes_per_channel(
      input int density_gbit, input bit binary_unit);
    longint unsigned bits;
    bits = binary_unit ? (longint'(density_gbit) << 30)
                       : (longint'(density_gbit) * 1000 * 1000 * 1000);
    return bits / 8;
  endfunction

  // Build a command descriptor. resp/err are filled by check_cmd().
  function automatic ddr_cmd_t make_cmd(input bit is_write,
                                        input logic [1:0] port,
                                        input logic [32:0] addr,
                                        input logic [7:0] len,
                                        input logic [2:0] size,
                                        input logic [1:0] burst,
                                        input logic [5:0] id,
                                        input logic [3:0] cache,
                                        input bit cobuf,
                                        input bit allstrb,
                                        input logic [63:0] t_accept);
    ddr_cmd_t c;
    c = '0;
    c.is_write = is_write;
    c.port     = port;
    c.addr     = addr;
    c.len      = len;
    c.size     = size;
    c.burst    = burst;
    c.id       = id;
    c.cache    = cache;
    c.cobuf    = cobuf;
    c.allstrb  = allstrb;
    c.beats    = 64'(len) + 1;
    c.t_accept = t_accept;
    c.resp     = RESP_OKAY;
    c.err      = '0;
    return c;
  endfunction

  // Acceptance-time checks. Updates resp/err in cmd.
  function automatic ddr_cmd_t check_cmd(input ddr_cmd_t c,
                                         input longint unsigned mem_bytes,
                                         input bit support_fixed,
                                         input bit support_wrap,
                                         input bit support_allstrb,
                                         input bit support_narrow,
                                         input bit range_check);
    longint unsigned bytes;
    logic [63:0] beats;
    c.resp = RESP_OKAY;
    c.err  = '0;
    bytes = burst_bytes(c.len, c.size);
    beats = 64'(c.len) + 1;

    if (c.size > 6) begin
      c.err[ERR_BURST_SIZE] = 1'b1;
      c.resp = RESP_SLVERR;
    end

    if (!support_narrow && (c.size < 6)) begin
      c.err[ERR_NARROW_DISABLED] = 1'b1;
      c.resp = RESP_SLVERR;
    end

    if (!table5_ok(c.size, c.len)) begin
      c.err[ERR_BURST_LEN] = 1'b1;
      c.resp = RESP_SLVERR;
    end

    if ((c.burst == BURST_FIXED) && !support_fixed) begin
      c.err[ERR_FIXED_BURST] = 1'b1;
      c.resp = RESP_SLVERR;
    end

    if ((c.burst != BURST_INCR) && (c.burst != BURST_WRAP) &&
        (c.burst != BURST_FIXED)) begin
      c.err[ERR_BURST_TYPE] = 1'b1;
      c.resp = RESP_SLVERR;
    end

    if (c.burst == BURST_WRAP) begin
      if (!support_wrap || !wrap_len_ok(c.len)) begin
        c.err[ERR_WRAP] = 1'b1;
        c.resp = RESP_SLVERR;
      end
      if (!aligned_to_size(c.addr, c.size)) begin
        c.err[ERR_ALIGN] = 1'b1;
        c.resp = RESP_SLVERR;
      end
    end else if ((c.burst == BURST_INCR) && !aligned_to_size(c.addr, c.size)) begin
      // AXI4 requires aligned start addresses; model returns SLVERR [AXI4][MODEL]
      c.err[ERR_ALIGN] = 1'b1;
      c.resp = RESP_SLVERR;
    end

    if ((c.burst == BURST_INCR) && cross_4kb(c.addr, bytes)) begin
      c.err[ERR_CROSS_4KB] = 1'b1;
      c.resp = RESP_SLVERR;
    end

    if (range_check && ((longint'(c.addr) + bytes) > mem_bytes)) begin
      c.err[ERR_ADDR_RANGE] = 1'b1;
      c.resp = RESP_DECERR;
    end

    if (c.allstrb && support_allstrb && (beats > 16)) begin
      c.err[ERR_ALLSTRB_BEATS] = 1'b1;
      c.resp = RESP_SLVERR;
    end

    return c;
  endfunction

  // Debug field decode; cs_pos selects the chip-select bit and therefore the
  // row width. Datapath/column/bank positions are fixed by the UG profile.
  function automatic ddr_addr_fields_t decode_addr_fields(input logic [32:0] addr,
                                                          input int cs_pos);
    ddr_addr_fields_t f;
    f = '0;
    f.datapath = addr[1:0];
    f.column   = addr[8:2];
    f.bank     = addr[11:9];
    for (int i = 0; i < 15; i++) begin
      if (((12 + i) < 33) && ((12 + i) < cs_pos)) f.row[i] = addr[12 + i];
    end
    if ((cs_pos >= 0) && (cs_pos < 33)) f.cs = addr[cs_pos];
    for (int i = 0; i < 5; i++) begin
      if (((cs_pos + 1 + i) < 33) && (cs_pos >= 0))
        f.unused[i] = addr[cs_pos + 1 + i];
    end
    return f;
  endfunction

  // Address-hole policy is only active in FIELD_DECODE_DEBUG with an explicit
  // hole window. policy 0 = DECERR, 1 = ALIAS into the low linear space.
  function automatic ddr_cmd_t apply_addr_hole(input ddr_cmd_t c,
                                               input bit enable,
                                               input longint unsigned hole_start,
                                               input longint unsigned hole_end,
                                               input int policy,
                                               input longint unsigned mem_bytes);
    longint unsigned a, b;
    if (!enable) return c;
    a = longint'(c.addr);
    b = a + burst_bytes(c.len, c.size);
    if ((a < hole_end) && (b > hole_start)) begin
      if (policy == 1) begin
        if (a >= hole_start) c.addr = 33'(a - hole_start);
        else                 c.addr = 33'(a % mem_bytes);
      end else begin
        c.err[ERR_ADDR_HOLE] = 1'b1;
        c.resp = RESP_DECERR;
      end
    end
    return c;
  endfunction

  // Converts a byte response to an aggregate response.
  function automatic logic [1:0] resp_or(input logic [1:0] a, input logic [1:0] b);
    if ((a == RESP_DECERR) || (b == RESP_DECERR)) return RESP_DECERR;
    if ((a == RESP_SLVERR) || (b == RESP_SLVERR)) return RESP_SLVERR;
    return RESP_OKAY;
  endfunction

endpackage
