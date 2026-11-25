// Unit tests for ddr_model_pkg address/burst/error helpers (PLAN P1).
module tb_unit_addr;
  import ddr_model_pkg::*;

  int errs = 0;

  task automatic chk(input bit cond, input string msg);
    if (!cond) begin
      errs++;
      $error("[ADDR] %s", msg);
    end
  endtask

  task automatic eq64(input longint unsigned got, input longint unsigned exp,
                      input string msg);
    if (got !== exp) begin
      errs++;
      $error("[ADDR] %s got=%0d exp=%0d", msg, got, exp);
    end
  endtask

  task automatic cmd_err(input ddr_cmd_t c, input int bit_idx, input string msg);
    if (c.err[bit_idx] !== 1'b1) begin
      errs++;
      $error("[ADDR] %s: err bit %0d not set (err=%h resp=%b)",
             msg, bit_idx, c.err, c.resp);
    end
  endtask

  initial begin
    ddr_cmd_t c;
    logic [63:0] mask;
    longint unsigned mem_bytes;

    mem_bytes = 64'h4000_0000; // 1 GiB

    // ---- burst_bytes ----
    eq64(burst_bytes(8'd0,  3'd6), 64,  "burst_bytes len0 size6");
    eq64(burst_bytes(8'd3,  3'd6), 256, "burst_bytes len3 size6");
    eq64(burst_bytes(8'd15, 3'd4), 256, "burst_bytes len15 size4");
    eq64(burst_bytes(8'd255,3'd0), 256, "burst_bytes len255 size0");
    eq64(burst_bytes(8'd0,  3'd0), 1,   "burst_bytes len0 size0");

    // ---- Table 5 ----
    chk(table5_ok(3'd6, 8'd63),  "table5 size6 len63 legal");
    chk(!table5_ok(3'd6, 8'd64), "table5 size6 len64 illegal");
    chk(table5_ok(3'd5, 8'd127), "table5 size5 len127 legal");
    chk(!table5_ok(3'd5, 8'd128),"table5 size5 len128 illegal");
    chk(table5_ok(3'd4, 8'd255), "table5 size4 len255 legal");
    chk(table5_ok(3'd3, 8'd255), "table5 size3 len255 legal");
    chk(!table5_ok(3'd7, 8'd0),  "table5 size7 illegal");

    // ---- 4KB crossing ----
    chk(!cross_4kb(33'h0FF0, 16), "4KB 0xFF0+16 fits");
    chk( cross_4kb(33'h0FF0, 17), "4KB 0xFF0+17 crosses");
    chk(!cross_4kb(33'h0FF8, 8),  "4KB 0xFF8+8 fits");
    chk(!cross_4kb(33'h0FFC, 4),  "4KB 0xFFC+4 fits");
    chk( cross_4kb(33'h0FFC, 5),  "4KB 0xFFC+5 crosses");
    chk(!cross_4kb(33'h0000, 4096), "4KB full window fits");
    chk( cross_4kb(33'h0000, 4097), "4KB over full window crosses");

    // ---- WRAP length ----
    chk( wrap_len_ok(8'd1),  "wrap 2 beats legal");
    chk( wrap_len_ok(8'd3),  "wrap 4 beats legal");
    chk( wrap_len_ok(8'd7),  "wrap 8 beats legal");
    chk( wrap_len_ok(8'd15), "wrap 16 beats legal");
    chk(!wrap_len_ok(8'd0),  "wrap 1 beat illegal");
    chk(!wrap_len_ok(8'd2),  "wrap 3 beats illegal");
    chk(!wrap_len_ok(8'd16), "wrap 17 beats illegal");
    chk(!wrap_len_ok(8'd31), "wrap 32 beats illegal");

    // ---- alignment ----
    chk( aligned_to_size(33'h1000, 6), "aligned 64B");
    chk( aligned_to_size(33'h1040, 6), "aligned 64B at 0x1040");
    chk(!aligned_to_size(33'h1020, 6), "unaligned 64B (32B offset)");
    chk(!aligned_to_size(33'h1024, 6), "unaligned 64B");
    chk( aligned_to_size(33'h1004, 2), "aligned 4B");
    chk(!aligned_to_size(33'h1002, 2), "unaligned 4B");

    // ---- beat_addr ----
    eq64(beat_addr(33'h0020, 0, 8'd3, 3'd4, BURST_WRAP), 64'h0020, "wrap beat0");
    eq64(beat_addr(33'h0020, 1, 8'd3, 3'd4, BURST_WRAP), 64'h0030, "wrap beat1");
    eq64(beat_addr(33'h0020, 2, 8'd3, 3'd4, BURST_WRAP), 64'h0000, "wrap beat2");
    eq64(beat_addr(33'h0020, 3, 8'd3, 3'd4, BURST_WRAP), 64'h0010, "wrap beat3");
    eq64(beat_addr(33'h0120, 0, 8'd3, 3'd4, BURST_WRAP), 64'h0120, "wrap1 beat0");
    eq64(beat_addr(33'h0120, 1, 8'd3, 3'd4, BURST_WRAP), 64'h0130, "wrap1 beat1");
    eq64(beat_addr(33'h0120, 2, 8'd3, 3'd4, BURST_WRAP), 64'h0100, "wrap1 beat2");
    eq64(beat_addr(33'h0120, 3, 8'd3, 3'd4, BURST_WRAP), 64'h0110, "wrap1 beat3");
    eq64(beat_addr(33'h1000, 2, 8'd3, 3'd6, BURST_INCR), 64'h1080, "incr beat2");
    eq64(beat_addr(33'h1000, 3, 8'd3, 3'd6, BURST_FIXED), 64'h1000, "fixed beat3");

    // ---- lane_strobe ----
    mask = lane_strobe(64'h1000, 3'd0);
    chk(mask == 64'h0000_0000_0000_0001, "lane size0 offset0");
    mask = lane_strobe(64'h1004, 3'd2);
    chk(mask == 64'h0000_0000_0000_00F0, "lane size2 offset4");
    mask = lane_strobe(64'h103C, 3'd2);
    chk(mask == 64'hF000_0000_0000_0000, "lane size2 offset60");
    mask = lane_strobe(64'h103F, 3'd0);
    chk(mask == 64'h8000_0000_0000_0000, "lane size0 offset63");

    // ---- rank decode ----
    chk(rank_of(33'h0_3FFF_FFFF, 64'h4000_0000, 2, 1, -1) == 0, "rank stride r0");
    chk(rank_of(33'h0_4000_0000, 64'h4000_0000, 2, 1, -1) == 1, "rank stride r1");
    chk(rank_of(33'h0_8000_0000, 64'h4000_0000, 2, 1, -1) == 1, "rank stride clamp");
    chk(rank_of(33'h1_0000_0000, 64'h0, 2, 2, 32) == 1, "rank cs_bit high");
    chk(rank_of(33'h0_1000_0000, 64'h0, 2, 2, 32) == 0, "rank cs_bit low");
    chk(rank_of(33'h1_0000_0000, 64'h1000, 2, 0, 32) == 0, "rank single");

    // ---- density helper ----
    eq64(calc_mem_bytes_per_channel(4, 1'b1), 64'h2000_0000, "4Gbit binary");
    eq64(calc_mem_bytes_per_channel(4, 1'b0), 500_000_000,    "4Gbit decimal");
    eq64(calc_mem_bytes_per_channel(2, 1'b1), 64'h1000_0000, "2Gbit binary");
    eq64(calc_mem_bytes_per_channel(16, 1'b1), 64'h8000_0000, "16Gbit binary");

    // ---- check_cmd ----
    c = make_cmd(1'b1, PORT0, 33'h1000, 8'd3, 3'd6, BURST_INCR,
                 6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    chk(c.resp == RESP_OKAY && c.err == 0, "legal INCR write");

    c = make_cmd(1'b0, PORT0, 33'h1000, 8'd0, 3'd7, BURST_INCR,
                 6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    cmd_err(c, ERR_BURST_SIZE, "size7");
    chk(c.resp == RESP_SLVERR, "size7 resp SLVERR");

    c = make_cmd(1'b0, PORT0, 33'h1000, 8'd64, 3'd6, BURST_INCR,
                 6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    cmd_err(c, ERR_BURST_LEN, "size6 len64");
    chk(c.resp == RESP_SLVERR, "len64 resp SLVERR");

    c = make_cmd(1'b1, PORT0, 33'h0FF0, 8'd1, 3'd4, BURST_INCR,
                 6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    cmd_err(c, ERR_CROSS_4KB, "4KB crossing");

    c = make_cmd(1'b1, PORT0, 33'h1000, 8'd0, 3'd6, BURST_FIXED,
                 6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    cmd_err(c, ERR_FIXED_BURST, "fixed burst");

    c = make_cmd(1'b1, PORT0, 33'h1000, 8'd0, 3'd6, 2'b11,
                 6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    cmd_err(c, ERR_BURST_TYPE, "burst type 11");

    c = make_cmd(1'b0, PORT0, 33'h1020, 8'd2, 3'd4, BURST_WRAP,
                 6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    cmd_err(c, ERR_WRAP, "wrap 3 beats");
    chk(c.resp == RESP_SLVERR, "wrap 3 beats resp");

    c = make_cmd(1'b0, PORT0, 33'h1024, 8'd3, 3'd4, BURST_WRAP,
                 6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    cmd_err(c, ERR_ALIGN, "wrap unaligned");

    c = make_cmd(1'b0, PORT0, 33'h1002, 8'd3, 3'd2, BURST_INCR,
                 6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    cmd_err(c, ERR_ALIGN, "incr unaligned");

    c = make_cmd(1'b0, PORT0, 33'(mem_bytes - 16), 8'd0, 3'd4, BURST_INCR,
                 6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    chk(c.resp == RESP_OKAY, "range last full beat legal");

    c = make_cmd(1'b0, PORT0, 33'(mem_bytes - 8), 8'd0, 3'd4, BURST_INCR,
                 6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    cmd_err(c, ERR_ADDR_RANGE, "range over end");
    chk(c.resp == RESP_DECERR, "range over end resp DECERR");

    c = make_cmd(1'b1, PORT0, 33'h1000, 8'd15, 3'd6, BURST_INCR,
                 6'd1, 4'hF, 1'b0, 1'b1, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    chk(c.resp == RESP_OKAY, "allstrb 16 beats legal");

    c = make_cmd(1'b1, PORT0, 33'h1000, 8'd16, 3'd6, BURST_INCR,
                 6'd1, 4'hF, 1'b0, 1'b1, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 1, 1);
    cmd_err(c, ERR_ALLSTRB_BEATS, "allstrb 17 beats");

    c = make_cmd(1'b1, PORT0, 33'h1000, 8'd0, 3'd2, BURST_INCR,
                 6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
    c = check_cmd(c, mem_bytes, 0, 1, 1, 0, 1);
    cmd_err(c, ERR_NARROW_DISABLED, "narrow disabled");

    chk(resp_or(RESP_OKAY, RESP_SLVERR) == RESP_SLVERR, "resp_or slverr");
    chk(resp_or(RESP_SLVERR, RESP_DECERR) == RESP_DECERR, "resp_or decerr");
    chk(resp_or(RESP_OKAY, RESP_OKAY) == RESP_OKAY, "resp_or okay");

    // ---- runtime-driven helper coverage ----
    // vopt may constant-fold helper calls whose arguments are literals and
    // drop their branch instrumentation, so derive these from run-time values.
    begin
      int              modes[5];
      int              cspos[6];
      longint unsigned hs, he, rstride;
      logic [32:0]     ra, ra_lo, ra_hi, ain, abelow, aout;
      ddr_addr_fields_t f;
      ddr_cmd_t        hc;
      logic [1:0]      rsel[6][2];
      logic [1:0]      rexp[6];
      logic [1:0]      rgot;

      modes[0] = $urandom_range(0, 0);
      modes[1] = $urandom_range(1, 1);
      modes[2] = $urandom_range(2, 2);
      modes[3] = $urandom_range(3, 3);
      modes[4] = $urandom_range(4, 4);
      cspos[0] = $urandom_range(20, 20);
      cspos[1] = $urandom_range(27, 27);
      cspos[2] = $urandom_range(32, 32);
      cspos[3] = $urandom_range(33, 33);
      cspos[4] = -($urandom_range(1, 1));
      cspos[5] = $urandom_range(40, 40);

      ra      = 33'($urandom % 1);
      ra_lo   = 33'($urandom);
      ra_hi   = ra_lo | (33'h1 << 32);
      rstride = 64'($urandom) | 64'h1;

      // rank_of: every case arm, stride-0, clamp, in-range and CS bit paths
      for (int m = 0; m < 5; m++)
        void'(rank_of(ra_lo, rstride, 2, modes[m], cspos[2]));
      void'(rank_of(ra_hi, 64'h0, 2, modes[1], 32));
      void'(rank_of(ra_hi, 64'h4000_0000, 2, modes[1], 32));
      void'(rank_of(ra, 64'h4000_0000, 2, modes[1], 32));
      void'(rank_of(ra_lo, 64'h1, 2, modes[2], cspos[2]));
      void'(rank_of(ra_hi, 64'h1, 2, modes[2], cspos[2]));
      void'(rank_of(ra_lo, 64'h1, 2, modes[2], cspos[3]));

      // decode_addr_fields: narrow row, out-of-range CS, negative CS, unused
      f = decode_addr_fields(ra_lo, cspos[0]);
      for (int i = 0; i < 15; i++)
        chk(f.row[i] == ((i < 8) ? ra_lo[12 + i] : 1'b0),
            $sformatf("decode row[%0d] cs20", i));
      f = decode_addr_fields(ra_lo, cspos[1]);
      chk(f.row[14] == ra_lo[26], "decode row[14] cs27");
      chk(decode_addr_fields(ra_lo, cspos[0]).unused[0] == ra_lo[21],
          "decode unused cs20");
      chk(decode_addr_fields(ra_lo, cspos[4]).unused == '0,
          "decode unused cs negative");
      chk(decode_addr_fields(ra_lo, cspos[3]).cs == 1'b0, "decode cs 33");
      chk(decode_addr_fields(ra_hi, cspos[2]).cs == 1'b1, "decode cs bit32");

      // apply_addr_hole: disabled, DECERR, alias above/below, outside, policy
      hs     = 64'h0030_0040;
      he     = 64'h0030_0100;
      ain    = 33'h0030_0040 + 33'($urandom % 1);
      abelow = 33'h0030_0038 + 33'($urandom % 1);
      aout   = 33'h0030_0100 + 33'($urandom % 1);
      hc = make_cmd(1'b1, PORT0, ain, 8'd0, 3'd6, BURST_INCR,
                    6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
      hc = apply_addr_hole(hc, 1'b0, hs, he, modes[0], mem_bytes);
      chk(hc.resp == RESP_OKAY && hc.addr == ain, "hole disabled");
      hc = make_cmd(1'b1, PORT0, ain, 8'd0, 3'd6, BURST_INCR,
                    6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
      hc = apply_addr_hole(hc, 1'b1, hs, he, modes[0], mem_bytes);
      chk(hc.resp == RESP_DECERR && hc.err[ERR_ADDR_HOLE], "hole decerr");
      hc = make_cmd(1'b1, PORT0, ain, 8'd0, 3'd6, BURST_INCR,
                    6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
      hc = apply_addr_hole(hc, 1'b1, hs, he, modes[1], mem_bytes);
      chk(hc.resp == RESP_OKAY && hc.addr == (ain - 33'(hs)),
          "hole alias above");
      hc = make_cmd(1'b1, PORT0, abelow, 8'd1, 3'd6, BURST_INCR,
                    6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
      hc = apply_addr_hole(hc, 1'b1, hs, he, modes[1], mem_bytes);
      chk(hc.resp == RESP_OKAY &&
          hc.addr == 33'(longint'(abelow) % mem_bytes), "hole alias below");
      hc = make_cmd(1'b1, PORT0, aout, 8'd0, 3'd6, BURST_INCR,
                    6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
      hc = apply_addr_hole(hc, 1'b1, hs, he, modes[1], mem_bytes);
      chk(hc.resp == RESP_OKAY && hc.addr == aout, "hole outside");
      hc = make_cmd(1'b1, PORT0, ain, 8'd0, 3'd6, BURST_INCR,
                    6'd1, 4'hF, 1'b0, 1'b0, 64'd0);
      hc = apply_addr_hole(hc, 1'b1, hs, he, modes[3], mem_bytes);
      chk(hc.resp == RESP_DECERR, "hole policy else");

      // resp_or: both operand orders for SLVERR and DECERR
      rsel[0][0] = RESP_OKAY;   rsel[0][1] = RESP_OKAY;   rexp[0] = RESP_OKAY;
      rsel[1][0] = RESP_SLVERR; rsel[1][1] = RESP_OKAY;   rexp[1] = RESP_SLVERR;
      rsel[2][0] = RESP_OKAY;   rsel[2][1] = RESP_SLVERR; rexp[2] = RESP_SLVERR;
      rsel[3][0] = RESP_DECERR; rsel[3][1] = RESP_OKAY;   rexp[3] = RESP_DECERR;
      rsel[4][0] = RESP_OKAY;   rsel[4][1] = RESP_DECERR; rexp[4] = RESP_DECERR;
      rsel[5][0] = RESP_DECERR; rsel[5][1] = RESP_SLVERR; rexp[5] = RESP_DECERR;
      for (int p = 0; p < 6; p++) begin
        rgot = resp_or(rsel[p][0], rsel[p][1]);
        if (rgot !== rexp[p]) begin
          errs++;
          $error("[ADDR] resp_or[%0d] got=%b exp=%b", p, rgot, rexp[p]);
        end
      end
    end


    if (errs == 0) begin
      $display("TEST all PASS");
      $finish;
    end else begin
      $display("TEST all FAIL errors=%0d", errs);
      $fatal(1, "addr unit test failed");
    end
  end
endmodule
