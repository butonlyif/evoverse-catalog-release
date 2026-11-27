package tb_pkg;
  import ddr_model_pkg::*;

  localparam int MAX_BEATS = 256;

  function automatic int beats_of(input int len);
    return len + 1;
  endfunction

  function automatic longint unsigned tbeat_addr(input logic [32:0] addr,
                                                 input int beat,
                                                 input int len,
                                                 input int size,
                                                 input logic [1:0] burst);
    return ddr_model_pkg::beat_addr(addr, beat, 8'(len), 3'(size), burst);
  endfunction

  function automatic logic [7:0] tb_byte(input longint unsigned a);
    return a[7:0] ^ 8'h5A;
  endfunction

  function automatic logic [511:0] tb_beat_data(input longint unsigned beat_addr);
    logic [511:0] d;
    longint unsigned base;
    base = beat_addr & ~64'h3F;
    d = '0;
    for (int n = 0; n < 64; n++) d[8*n +: 8] = tb_byte(base + longint'(n));
    return d;
  endfunction

  // strb_mode 0: AXI valid lanes for the transfer size
  // strb_mode 1: alternating 0x55/0xAA within valid lanes
  // strb_mode 2: all zero
  // strb_mode 3: checkerboard mask within valid lanes
  function automatic logic [63:0] tb_wstrb(input longint unsigned beat_addr,
                                           input int size,
                                           input int strb_mode);
    logic [63:0] valid;
    valid = ddr_model_pkg::lane_strobe(beat_addr, 3'(size));
    case (strb_mode)
      1: return valid & (beat_addr[6] ? 64'hAAAA_AAAA_AAAA_AAAA
                                      : 64'h5555_5555_5555_5555);
      2: return '0;
      3: return valid & 64'h00FF_00FF_00FF_00FF;
      4: return beat_addr[6] ? '0 : valid;
      default: return valid;
    endcase
  endfunction

  function automatic logic [511:0] expected_read_beat(input longint unsigned beat_addr,
                                                      input int size,
                                                      input byte unsigned exp_byte);
    // exp_byte is a callback substitute: TB scoreboard does byte lookup itself
    logic [511:0] d;
    d = '0;
    return d;
  endfunction

endpackage
