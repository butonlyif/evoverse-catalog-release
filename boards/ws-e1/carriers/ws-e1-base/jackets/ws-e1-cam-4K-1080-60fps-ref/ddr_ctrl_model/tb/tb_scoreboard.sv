// Expected-memory scoreboard for model-level verification.
module tb_scoreboard;
  import tb_pkg::*;

  byte unsigned exp_mem [longint unsigned];
  int           err_count;
  int           wr_count;
  int           rd_count;

  function automatic byte unsigned get_byte(input longint unsigned a);
    if (exp_mem.exists(a)) return exp_mem[a];
    return 8'h00;
  endfunction

  task automatic record_write(
    input logic [32:0] addr,
    input int          len,
    input int          size,
    input logic [1:0]  burst,
    input int          strb_mode = 0
  );
    longint unsigned ba;
    longint unsigned base;
    logic [63:0]     strb;
    logic [511:0]    d;
    for (int i = 0; i < len+1; i++) begin
      ba   = tbeat_addr(addr, i, len, size, burst);
      strb = tb_wstrb(ba, size, strb_mode);
      d    = tb_beat_data(ba);
      base = ba & ~64'h3F;
      for (int n = 0; n < 64; n++) begin
        if (strb[n]) exp_mem[base + longint'(n)] = d[8*n +: 8];
      end
    end
    wr_count++;
  endtask

  task automatic check_read(
    input logic [32:0] addr,
    input int          len,
    input int          size,
    input logic [1:0]  burst,
    input logic [5:0]  id,
    input logic [511:0] data[],
    input logic [1:0]   resp[],
    input logic [1:0]   exp_resp = 2'b00
  );
    longint unsigned ba;
    longint unsigned base;
    int              off;
    longint unsigned sb;
    logic [511:0]    expected;
    bit              lane_ok;
    int              mismatches;

    if (data.size() != len+1) begin
      err_count++;
      $error("[SB] read beat count exp=%0d got=%0d addr=0x%0h",
             len+1, data.size(), addr);
      return;
    end

    for (int i = 0; i < len+1; i++) begin
      if (resp[i] !== exp_resp) begin
        err_count++;
        $error("[SB] RRESP beat %0d exp=%b got=%b addr=0x%0h",
               i, exp_resp, resp[i], addr);
      end
      if (exp_resp == 2'b00) begin
        ba = tbeat_addr(addr, i, len, size, burst);
        base = ba & ~64'h3F;
        off  = int'(ba % 64);
        sb   = ddr_model_pkg::size_bytes(3'(size));
        expected = '0;
        for (int j = 0; j < 64; j++) begin
          lane_ok = (longint'(j) >= longint'(off)) &&
                    (longint'(j) < longint'(off) + sb);
          if (lane_ok) expected[8*j +: 8] = get_byte(base + longint'(j));
        end
        if (data[i] !== expected) begin
          err_count++;
          mismatches = 0;
          for (int j = 0; j < 64; j++) begin
            if (data[i][8*j +: 8] !== expected[8*j +: 8]) begin
              if (mismatches < 8) begin
                $error("[SB] data mismatch addr=0x%0h beat=%0d lane=%0d exp=%02h got=%02h",
                       ba, i, j, expected[8*j +: 8], data[i][8*j +: 8]);
              end
              mismatches++;
            end
          end
          $error("[SB] beat 0x%0h has %0d mismatching bytes", ba, mismatches);
        end
      end
    end
    rd_count++;
    if (id > 63) begin
      err_count++;
      $error("[SB] invalid ID %0d", id);
    end
  endtask

  task automatic report();
    $display("[SB] writes=%0d reads=%0d errors=%0d expected-bytes-used=%0d",
             wr_count, rd_count, err_count, exp_mem.num());
  endtask

endmodule
