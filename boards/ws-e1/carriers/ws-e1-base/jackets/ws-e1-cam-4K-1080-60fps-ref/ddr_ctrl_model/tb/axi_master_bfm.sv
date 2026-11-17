// Self-checking AXI4 master BFM for the DDR model testbench.
module axi_master_bfm #(
  parameter int ID_W = 6
) (
  ddr_model_if axi,
  input logic  clk
);
  import tb_pkg::*;

  int                err_count;
  longint unsigned   cyc;
  longint unsigned   t_aw, t_wlast, t_b;
  longint unsigned   t_ar, t_rfirst;
  logic [1:0]        last_resp;
  bit                last_b_before_wlast;
  int                last_rd_lat;
  int                last_wr_lat;
  int                last_wlast_b_lat;

  // current transaction context
  logic [32:0] cur_addr;
  int          cur_len;
  int          cur_size;
  logic [1:0]  cur_burst;
  logic [5:0]  cur_id;
  logic [3:0]  cur_cache;
  bit          cur_cobuf;
  bit          cur_allstrb;
  bit          cur_wfirst;
  int          cur_strb_mode;
  int          cur_pause;
  int          cur_wlast_mode;   // 0=normal 1=WLAST on first beat 2=WLAST never

  bit          exp_bid_valid;
  logic [5:0]  exp_bid;
  bit          wlast_sent;
  bit          b_captured;
  logic [1:0]  b_resp_captured;

  localparam int TMO = 20000;

  covergroup cg_wr;
    cp_len: coverpoint cur_len {
      bins single = {0};
      bins short_b = {[1:3]};
      bins mid = {[4:15]};
      bins long_b = {[16:254]};
      bins max = {255};
    }
    cp_size: coverpoint cur_size {
      bins s1 = {0};
      bins s2 = {1};
      bins s4 = {2};
      bins s8 = {3};
      bins s16 = {4};
      bins s32 = {5};
      bins s64 = {6};
      bins illegal = {7};
    }
    cp_burst: coverpoint cur_burst {
      bins fixed = {0};
      bins incr = {1};
      bins wrap = {2};
    }
    cp_resp: coverpoint last_resp {
      bins okay = {2'b00};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }
    cp_cache: coverpoint cur_cache {
      bins early_cobuf = {4'b1111};
      bins early_zero = {4'b0000};
      bins other = {[1:14]};
    }
    cp_cobuf: coverpoint cur_cobuf;
    cp_wfirst: coverpoint cur_wfirst;
    cp_strb: coverpoint cur_strb_mode {
      bins full = {0};
      bins partial = {1};
      bins zero = {2};
      bins alt_bits = {3};
    }
    cx_size_burst: cross cp_size, cp_burst;
  endgroup

  covergroup cg_rd;
    cp_len: coverpoint cur_len {
      bins single = {0};
      bins short_b = {[1:3]};
      bins mid = {[4:15]};
      bins max = {255};
    }
    cp_size: coverpoint cur_size {
      bins s1 = {0};
      bins s2 = {1};
      bins s4 = {2};
      bins s8 = {3};
      bins s32 = {5};
      bins s64 = {6};
    }
    cp_burst: coverpoint cur_burst {
      bins incr = {1};
      bins wrap = {2};
    }
    cp_resp: coverpoint last_resp {
      bins okay = {2'b00};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }
    cx_size_burst: cross cp_size, cp_burst;
  endgroup

  cg_wr cov_wr = new;
  cg_rd cov_rd = new;

  always @(posedge clk) cyc <= cyc + 1'b1;

  initial begin
    cyc = 0;
    err_count = 0;
    axi.AWADDR = '0;
    axi.AWBURST = '0;
    axi.AWID = '0;
    axi.AWLEN = '0;
    axi.AWSIZE = '0;
    axi.AWVALID = 1'b0;
    axi.AWLOCK = 1'b0;
    axi.AWAPCMD = 1'b0;
    axi.AWQOS = '0;
    axi.AWCACHE = 4'hF;
    axi.AWALLSTRB = 1'b0;
    axi.AWCOBUF = 1'b0;
    axi.WDATA = '0;
    axi.WLAST = 1'b0;
    axi.WSTRB = '0;
    axi.WVALID = 1'b0;
    axi.BREADY = 1'b0;
    axi.ARADDR = '0;
    axi.ARBURST = '0;
    axi.ARID = '0;
    axi.ARLEN = '0;
    axi.ARSIZE = '0;
    axi.ARVALID = 1'b0;
    axi.ARLOCK = 1'b0;
    axi.ARAPCMD = 1'b0;
    axi.ARQOS = '0;
    axi.RREADY = 1'b0;
  end

  task automatic fail(input string msg);
    err_count++;
    $error("[BFM] %s (t=%0t)", msg, $time);
  endtask

  // ------------------------------------------------------------------
  // drivers
  // ------------------------------------------------------------------
  task automatic aw_driver();
    int tmo;
    @(posedge clk);
    axi.AWADDR    <= cur_addr;
    axi.AWBURST   <= cur_burst;
    axi.AWID      <= cur_id;
    axi.AWLEN     <= 8'(cur_len);
    axi.AWSIZE    <= 3'(cur_size);
    axi.AWCACHE   <= cur_cache;
    axi.AWCOBUF   <= cur_cobuf;
    axi.AWALLSTRB <= cur_allstrb;
    axi.AWLOCK    <= 1'b0;
    axi.AWAPCMD   <= 1'b0;
    axi.AWQOS     <= '0;
    axi.AWVALID   <= 1'b1;
    tmo = 0;
    do begin
      @(posedge clk);
      tmo++;
    end while (!(axi.AWVALID && axi.AWREADY) && (tmo < TMO));
    if (axi.AWVALID && axi.AWREADY) begin
      t_aw = cyc;
    end else begin
      fail($sformatf("AW handshake timeout addr=0x%0h", cur_addr));
    end
    axi.AWVALID <= 1'b0;
  endtask

  task automatic w_driver();
    int tmo;
    longint unsigned ba;
    logic wlast_beat;
    for (int i = 0; i < cur_len+1; i++) begin
      @(posedge clk);
      ba = tbeat_addr(cur_addr, i, cur_len, cur_size, cur_burst);
      wlast_beat = (cur_wlast_mode == 1) ? (i == 0) :
                   (cur_wlast_mode == 2) ? 1'b0 : (i == cur_len);
      axi.WDATA  <= tb_beat_data(ba);
      axi.WSTRB  <= tb_wstrb(ba, cur_size, cur_strb_mode);
      axi.WLAST  <= wlast_beat;
      axi.WVALID <= 1'b1;
      tmo = 0;
      do begin
        @(posedge clk);
        tmo++;
      end while (!(axi.WVALID && axi.WREADY) && (tmo < TMO));
      if (axi.WVALID && axi.WREADY) begin
        if (wlast_beat) begin
          t_wlast = cyc;
          wlast_sent = 1'b1;
        end
      end else begin
        fail($sformatf("W handshake timeout beat=%0d", i));
      end
      axi.WVALID <= 1'b0;
      axi.WLAST  <= 1'b0;
      if ((i == 0) && (cur_pause > 0)) begin
        repeat (cur_pause) @(posedge clk);
      end
    end
  endtask

  task automatic b_monitor();
    int tmo;
    axi.BREADY <= 1'b1;
    tmo = 0;
    do begin
      @(posedge clk);
      tmo++;
    end while (!(axi.BVALID && axi.BREADY) && (tmo < TMO));
    if (axi.BVALID && axi.BREADY) begin
      b_resp_captured = axi.BRESP;
      t_b = cyc;
      last_b_before_wlast = !wlast_sent;
      if (exp_bid_valid && (axi.BID !== exp_bid)) begin
        fail($sformatf("BID mismatch exp=%0d got=%0d", exp_bid, axi.BID));
      end
      if ((axi.BRESP !== 2'b00) && (axi.BRESP !== 2'b10) &&
          (axi.BRESP !== 2'b11)) begin
        fail($sformatf("invalid BRESP=%b", axi.BRESP));
      end
      b_captured = 1'b1;
    end else begin
      fail("B handshake timeout");
      b_resp_captured = 2'bxx;
    end
    axi.BREADY <= 1'b0;
  endtask

  // ------------------------------------------------------------------
  // write transaction
  // ------------------------------------------------------------------
  task automatic wr_txn(
    input logic [32:0] addr,
    input int          len = 0,
    input int          size = 6,
    input logic [1:0]  burst = 2'b01,
    input logic [5:0]  id = 0,
    input logic [3:0]  cache = 4'hF,
    input bit          cobuf = 1'b0,
    input bit          allstrb = 1'b0,
    input int          strb_mode = 0,
    input bit          wfirst = 1'b0,
    input int          pause_after_first = 0,
    input int          wlast_mode = 0,
    output logic [1:0] resp
  );
    cur_addr       = addr;
    cur_len        = len;
    cur_size       = size;
    cur_burst      = burst;
    cur_id         = id;
    cur_cache      = cache;
    cur_cobuf      = cobuf;
    cur_allstrb    = allstrb;
    cur_wfirst     = wfirst;
    cur_strb_mode  = strb_mode;
    cur_pause      = pause_after_first;
    cur_wlast_mode = wlast_mode;

    exp_bid_valid  = 1'b1;
    exp_bid        = id;
    wlast_sent     = 1'b0;
    b_captured     = 1'b0;
    b_resp_captured = 2'bxx;
    t_aw = 0; t_wlast = 0; t_b = 0;

    if (wfirst) begin
      w_driver();
      fork
        aw_driver();
        b_monitor();
      join
    end else begin
      fork
        aw_driver();
        w_driver();
        b_monitor();
      join
    end

    if (!b_captured) begin
      fail("write transaction completed without B");
      resp = 2'bxx;
    end else begin
      resp = b_resp_captured;
    end
    last_resp = resp;
    last_wr_lat = int'(t_b - t_aw);
    if (wlast_sent) last_wlast_b_lat = int'(t_b - t_wlast);
    cov_wr.sample();
  endtask

  // AWVALID-only probe: verifies AWREADY stays low until WVALID appears.
  task automatic wr_aw_late_w(
    input logic [32:0] addr,
    input int          len = 0,
    input int          size = 6,
    input logic [5:0]  id = 0,
    output logic [1:0] resp
  );
    int tmo;
    cur_addr = addr; cur_len = len; cur_size = size; cur_burst = 2'b01;
    cur_id = id; cur_cache = 4'hF; cur_cobuf = 0; cur_allstrb = 0;
    cur_strb_mode = 0; cur_pause = 0; cur_wlast_mode = 0;
    exp_bid_valid = 1; exp_bid = id; wlast_sent = 0;
    b_captured = 0; b_resp_captured = 2'bxx;

    @(posedge clk);
    axi.AWADDR  <= addr;
    axi.AWBURST <= 2'b01;
    axi.AWID    <= id;
    axi.AWLEN   <= 8'(len);
    axi.AWSIZE  <= 3'(size);
    axi.AWCACHE <= 4'hF;
    axi.AWCOBUF <= 1'b0;
    axi.AWALLSTRB <= 1'b0;
    axi.AWVALID <= 1'b1;

    for (int i = 0; i < 20; i++) begin
      @(posedge clk);
      if (axi.AWREADY) begin
        fail("AWREADY asserted with AWVALID only (WVALID=0)");
      end
    end

    fork
      begin : aw_wait
        tmo = 0;
        do begin
          @(posedge clk);
          tmo++;
        end while (!(axi.AWVALID && axi.AWREADY) && (tmo < TMO));
        if (!(axi.AWVALID && axi.AWREADY)) fail("AW handshake timeout (late W)");
        else t_aw = cyc;
        axi.AWVALID <= 1'b0;
      end
      w_driver();
      b_monitor();
    join

    resp = b_captured ? b_resp_captured : 2'bxx;
    last_resp = resp;
  endtask

  // ------------------------------------------------------------------
  // outstanding / backpressure probes (PLAN P5)
  // ------------------------------------------------------------------
  // Preloads depth+1 single-beat W bursts, then accepts AW commands until
  // the configured write-outstanding limit blocks the next AW.
  task automatic wr_ostd_probe(
    input  int         depth,
    input  logic [32:0] base_addr,
    output int         accepted,
    output bit         blocked
  );
    int tmo;
    logic [32:0] a;
    accepted = 0;
    blocked  = 1'b0;

    // W data first: AWREADY accepts it from the W FIFO without an AW.
    for (int i = 0; i <= depth; i++) begin
      a = base_addr + 33'(i * 64);
      @(posedge clk);
      axi.WDATA  <= tb_beat_data(a);
      axi.WSTRB  <= tb_wstrb(a, 6, 0);
      axi.WLAST  <= 1'b1;
      axi.WVALID <= 1'b1;
      tmo = 0;
      do begin
        @(posedge clk);
        tmo++;
      end while (!(axi.WVALID && axi.WREADY) && (tmo < TMO));
      if (!(axi.WVALID && axi.WREADY)) fail("W preload timeout");
      axi.WVALID <= 1'b0;
      axi.WLAST  <= 1'b0;
    end

    axi.BREADY <= 1'b0;

    for (int i = 0; i < depth; i++) begin
      a = base_addr + 33'(i * 64);
      @(posedge clk);
      axi.AWADDR  <= a;
      axi.AWBURST <= 2'b01;
      axi.AWID    <= 6'(i);
      axi.AWLEN   <= 8'd0;
      axi.AWSIZE  <= 3'd6;
      axi.AWCACHE <= 4'hF;
      axi.AWCOBUF <= 1'b0;
      axi.AWALLSTRB <= 1'b0;
      axi.AWVALID <= 1'b1;
      tmo = 0;
      do begin
        @(posedge clk);
        tmo++;
      end while (!(axi.AWVALID && axi.AWREADY) && (tmo < TMO));
      if (axi.AWVALID && axi.AWREADY) accepted++;
      else fail("AW handshake timeout during ostd fill");
      axi.AWVALID <= 1'b0;
    end

    // Next AW must be blocked by the outstanding limit.
    a = base_addr + 33'(depth * 64);
    @(posedge clk);
    axi.AWADDR  <= a;
    axi.AWBURST <= 2'b01;
    axi.AWID    <= 6'(depth);
    axi.AWLEN   <= 8'd0;
    axi.AWSIZE  <= 3'd6;
    axi.AWCACHE <= 4'hF;
    axi.AWVALID <= 1'b1;
    for (int i = 0; i < 20; i++) begin
      @(posedge clk);
      if (axi.AWREADY) begin
        fail("AWREADY asserted while write outstanding limit reached");
        blocked = 1'b0;
      end
    end
    if (accepted == depth) blocked = 1'b1;

    // Drain outstanding responses while the blocked AW waits. A dedicated
    // thread deasserts AWVALID on the handshake so it cannot be accepted twice.
    fork
      begin : blocked_aw
        tmo = 0;
        do begin
          @(posedge clk);
          tmo++;
        end while (!(axi.AWVALID && axi.AWREADY) && (tmo < TMO));
        if (axi.AWVALID && axi.AWREADY) accepted++;
        else fail("blocked AW never accepted after B drain");
        axi.AWVALID <= 1'b0;
      end
      begin : b_drain
        axi.BREADY <= 1'b1;
        for (int i = 0; i < depth; i++) begin
          tmo = 0;
          do begin
            @(posedge clk);
            tmo++;
          end while (!(axi.BVALID && axi.BREADY) && (tmo < TMO));
          if (!(axi.BVALID && axi.BREADY)) begin
            fail("B drain timeout during ostd probe");
          end else if (axi.BID !== 6'(i)) begin
            fail($sformatf("B out-of-order in ostd probe: exp=%0d got=%0d",
                           i, axi.BID));
          end
        end
      end
    join

    tmo = 0;
    do begin
      @(posedge clk);
      tmo++;
    end while (!(axi.BVALID && axi.BREADY) && (tmo < TMO));
    if (!(axi.BVALID && axi.BREADY)) fail("final B timeout in ostd probe");
    axi.BREADY <= 1'b0;
  endtask

  // Same idea for reads; RREADY is held low so RLAST cannot retire.
  task automatic rd_ostd_probe(
    input  int         depth,
    input  logic [32:0] base_addr,
    output int         accepted,
    output bit         blocked
  );
    int tmo;
    logic [32:0] a;
    accepted = 0;
    blocked  = 1'b0;

    axi.RREADY <= 1'b0;

    for (int i = 0; i < depth; i++) begin
      a = base_addr + 33'(i * 64);
      @(posedge clk);
      axi.ARADDR  <= a;
      axi.ARBURST <= 2'b01;
      axi.ARID    <= 6'(i);
      axi.ARLEN   <= 8'd0;
      axi.ARSIZE  <= 3'd6;
      axi.ARVALID <= 1'b1;
      tmo = 0;
      do begin
        @(posedge clk);
        tmo++;
      end while (!(axi.ARVALID && axi.ARREADY) && (tmo < TMO));
      if (axi.ARVALID && axi.ARREADY) accepted++;
      else fail("AR handshake timeout during ostd fill");
      axi.ARVALID <= 1'b0;
    end

    a = base_addr + 33'(depth * 64);
    @(posedge clk);
    axi.ARADDR  <= a;
    axi.ARBURST <= 2'b01;
    axi.ARID    <= 6'(depth);
    axi.ARLEN   <= 8'd0;
    axi.ARSIZE  <= 3'd6;
    axi.ARVALID <= 1'b1;
    for (int i = 0; i < 20; i++) begin
      @(posedge clk);
      if (axi.ARREADY) begin
        fail("ARREADY asserted while read outstanding limit reached");
        blocked = 1'b0;
      end
    end
    if (accepted == depth) blocked = 1'b1;

    fork
      begin : blocked_ar
        tmo = 0;
        do begin
          @(posedge clk);
          tmo++;
        end while (!(axi.ARVALID && axi.ARREADY) && (tmo < TMO));
        if (axi.ARVALID && axi.ARREADY) accepted++;
        else fail("blocked AR never accepted after R drain");
        axi.ARVALID <= 1'b0;
      end
      begin : r_drain
        axi.RREADY <= 1'b1;
        for (int i = 0; i < depth; i++) begin
          tmo = 0;
          do begin
            @(posedge clk);
            tmo++;
          end while (!(axi.RVALID && axi.RREADY) && (tmo < TMO));
          if (!(axi.RVALID && axi.RREADY)) begin
            fail("R drain timeout during ostd probe");
          end else if (axi.RID !== 6'(i)) begin
            fail($sformatf("R out-of-order in ostd probe: exp=%0d got=%0d",
                           i, axi.RID));
          end
        end
      end
    join

    tmo = 0;
    do begin
      @(posedge clk);
      tmo++;
    end while (!(axi.RVALID && axi.RREADY) && (tmo < TMO));
    if (!(axi.RVALID && axi.RREADY)) fail("final R timeout in ostd probe");
    axi.RREADY <= 1'b0;
  endtask

  // ------------------------------------------------------------------
  // queue-full probes (PLAN P5)
  // ------------------------------------------------------------------
  task automatic ar_send(
    input  logic [32:0] addr,
    input  int          len,
    input  int          size,
    input  logic [5:0]  id,
    output bit          ok
  );
    int tmo;
    @(posedge clk);
    axi.ARADDR  <= addr;
    axi.ARBURST <= 2'b01;
    axi.ARID    <= id;
    axi.ARLEN   <= 8'(len);
    axi.ARSIZE  <= 3'(size);
    axi.ARVALID <= 1'b1;
    tmo = 0;
    do begin
      @(posedge clk);
      tmo++;
    end while (!(axi.ARVALID && axi.ARREADY) && (tmo < TMO));
    ok = axi.ARVALID && axi.ARREADY;
    axi.ARVALID <= 1'b0;
  endtask

  // W-first burst: the data FIFO accepts `depth` beats and must then deassert
  // WREADY while WVALID stays high. AW is issued only after the stall is seen.
  task automatic wdataq_probe(
    input  int          depth,
    input  logic [32:0] base_addr,
    output int          accepted,
    output bit          blocked
  );
    int tmo;
    longint unsigned ba;
    accepted = 0;
    blocked  = 1'b0;

    axi.BREADY  <= 1'b0;
    axi.AWVALID <= 1'b0;

    for (int i = 0; i <= depth; i++) begin
      ba = tbeat_addr(base_addr, i, depth, 6, 2'b01);
      @(posedge clk);
      axi.WDATA  <= tb_beat_data(ba);
      axi.WSTRB  <= '1;
      axi.WLAST  <= (i == depth);
      axi.WVALID <= 1'b1;
      if (i < depth) begin
        tmo = 0;
        do begin
          @(posedge clk);
          tmo++;
        end while (!(axi.WVALID && axi.WREADY) && (tmo < TMO));
        if (!(axi.WVALID && axi.WREADY)) fail("W preload timeout (wdataq)");
        else accepted++;
        axi.WVALID <= 1'b0;
        axi.WLAST  <= 1'b0;
      end
    end

    for (int i = 0; i < 20; i++) begin
      @(posedge clk);
      if (axi.WREADY) fail("WREADY asserted while write-data FIFO is full");
    end
    blocked = 1'b1;

    fork
      begin : wq_aw
        tmo = 0;
        @(posedge clk);
        axi.AWADDR  <= base_addr;
        axi.AWBURST <= 2'b01;
        axi.AWID    <= 6'h3E;
        axi.AWLEN   <= 8'(depth);
        axi.AWSIZE  <= 3'd6;
        axi.AWCACHE <= 4'hF;
        axi.AWVALID <= 1'b1;
        do begin
          @(posedge clk);
          tmo++;
        end while (!(axi.AWVALID && axi.AWREADY) && (tmo < TMO));
        if (!(axi.AWVALID && axi.AWREADY)) fail("AW timeout (wdataq)");
        axi.AWVALID <= 1'b0;
      end
      begin : wq_wlast
        tmo = 0;
        do begin
          @(posedge clk);
          tmo++;
        end while (!(axi.WVALID && axi.WREADY) && (tmo < TMO));
        if (!(axi.WVALID && axi.WREADY)) fail("last W beat timeout (wdataq)");
        else accepted++;
        axi.WVALID <= 1'b0;
        axi.WLAST  <= 1'b0;
      end
      b_monitor();
    join
  endtask

  // Fills the per-port B FIFO with BREADY low, then keeps issuing single-beat
  // writes until the shared command queue is full and AWREADY drops.
  task automatic cmdq_probe(
    input  int          max_cmds,
    input  logic [32:0] base_addr,
    output int          accepted,
    output bit          blocked
  );
    int  tmo;
    bit  aw_done, w_done;
    int  n_pre;
    logic [32:0] a;
    longint unsigned ba;
    accepted = 0;
    blocked  = 1'b0;
    axi.BREADY <= 1'b0;

    for (int i = 0; i < max_cmds; i++) begin
      a  = base_addr + 33'(i * 64);
      ba = tbeat_addr(a, 0, 0, 6, 2'b01);
      @(posedge clk);
      axi.AWADDR  <= a;
      axi.AWBURST <= 2'b01;
      axi.AWID    <= 6'(i);
      axi.AWLEN   <= 8'd0;
      axi.AWSIZE  <= 3'd6;
      axi.AWCACHE <= 4'hF;
      axi.AWVALID <= 1'b1;
      axi.WDATA  <= tb_beat_data(ba);
      axi.WSTRB  <= '1;
      axi.WLAST  <= 1'b1;
      axi.WVALID <= 1'b1;

      aw_done = 1'b0;
      w_done  = 1'b0;
      tmo     = 0;
      while (!(aw_done && w_done) && (tmo < 20)) begin
        @(posedge clk);
        if (!aw_done && axi.AWVALID && axi.AWREADY) begin
          aw_done = 1'b1;
          accepted++;
          axi.AWVALID <= 1'b0;
        end
        if (!w_done && axi.WVALID && axi.WREADY) begin
          w_done = 1'b1;
          axi.WVALID <= 1'b0;
          axi.WLAST  <= 1'b0;
        end
        tmo++;
      end

      if (!aw_done) begin
        blocked = 1'b1;
        if (!w_done) begin
          tmo = 0;
          do begin
            @(posedge clk);
            tmo++;
          end while (!(axi.WVALID && axi.WREADY) && (tmo < TMO));
          if (!(axi.WVALID && axi.WREADY)) fail("W timeout with blocked AW");
          axi.WVALID <= 1'b0;
          axi.WLAST  <= 1'b0;
        end
        break;
      end
      if (!w_done) begin
        fail("W not accepted before AW in cmdq probe");
        break;
      end
    end
    if (!blocked) fail("command queue never applied AW backpressure");

    n_pre = accepted;
    fork
      begin : blocked_aw
        tmo = 0;
        do begin
          @(posedge clk);
          tmo++;
        end while (!(axi.AWVALID && axi.AWREADY) && (tmo < TMO));
        if (axi.AWVALID && axi.AWREADY) accepted++;
        else fail("blocked AW never accepted after B drain");
        axi.AWVALID <= 1'b0;
      end
      begin : b_drain
        axi.BREADY <= 1'b1;
        for (int k = 0; k < n_pre; k++) begin
          tmo = 0;
          do begin
            @(posedge clk);
            tmo++;
          end while (!(axi.BVALID && axi.BREADY) && (tmo < TMO));
          if (!(axi.BVALID && axi.BREADY)) fail("B drain timeout (cmdq)");
          else if (axi.BID !== 6'(k)) begin
            fail($sformatf("B order in cmdq: exp=%0d got=%0d", k, axi.BID));
          end
        end
      end
    join

    tmo = 0;
    do begin
      @(posedge clk);
      tmo++;
    end while (!(axi.BVALID && axi.BREADY) && (tmo < TMO));
    if (!(axi.BVALID && axi.BREADY)) fail("final B timeout (cmdq)");
    else if (axi.BID !== 6'(n_pre)) fail("final B ID mismatch (cmdq)");
    axi.BREADY <= 1'b0;
  endtask

  // One long read stalls on the full R FIFO; extra reads fill the command
  // queue, after which ARREADY must drop until responses are drained.
  task automatic rdataq_probe(
    input  int          depth,
    input  int          cmd_depth,
    input  logic [32:0] base_addr,
    output int          beats_seen,
    output bit          blocked
  );
    int  tmo;
    int  first_beats;
    int  n_ar;
    bit  ok;
    logic [32:0] a;
    beats_seen = 0;
    blocked    = 1'b0;

    axi.RREADY <= 1'b0;
    first_beats = depth + 2;

    ar_send(base_addr, first_beats - 1, 6, 6'd0, ok);
    if (!ok) fail("first AR timeout (rdataq)");
    n_ar = 1;

    for (int i = 1; i <= cmd_depth; i++) begin
      ar_send(base_addr + 33'(i) * 33'h1000, 0, 6, 6'(i), ok);
      if (!ok) fail($sformatf("queued AR %0d timeout (rdataq)", i));
      n_ar++;
    end

    tmo = 0;
    while (!axi.RVALID && (tmo < TMO)) begin
      @(posedge clk);
      tmo++;
    end
    if (!axi.RVALID) fail("RVALID low with queued read-data beats");

    a = base_addr + 33'(cmd_depth + 1) * 33'h1000;
    @(posedge clk);
    axi.ARADDR  <= a;
    axi.ARBURST <= 2'b01;
    axi.ARID    <= 6'(cmd_depth + 1);
    axi.ARLEN   <= 8'd0;
    axi.ARSIZE  <= 3'd6;
    axi.ARVALID <= 1'b1;
    for (int i = 0; i < 20; i++) begin
      @(posedge clk);
      if (axi.ARREADY) fail("ARREADY asserted while read command queue is full");
    end
    blocked = !axi.ARREADY;

    fork
      begin : blocked_ar
        tmo = 0;
        do begin
          @(posedge clk);
          tmo++;
        end while (!(axi.ARVALID && axi.ARREADY) && (tmo < TMO));
        if (!(axi.ARVALID && axi.ARREADY)) fail("blocked AR never accepted (rdataq)");
        else n_ar++;
        axi.ARVALID <= 1'b0;
      end
      begin : r_drain
        axi.RREADY <= 1'b1;
        for (int i = 0; i < first_beats; i++) begin
          tmo = 0;
          do begin
            @(posedge clk);
            tmo++;
          end while (!(axi.RVALID && axi.RREADY) && (tmo < TMO));
          if (!(axi.RVALID && axi.RREADY)) fail("R drain timeout (rdataq)");
          else if (axi.RID !== 6'd0) fail("RID order in rdataq burst");
          else if (axi.RLAST !== ((i == first_beats - 1)))
            fail("RLAST mismatch in rdataq burst");
          beats_seen++;
        end
        for (int i = 1; i <= cmd_depth; i++) begin
          tmo = 0;
          do begin
            @(posedge clk);
            tmo++;
          end while (!(axi.RVALID && axi.RREADY) && (tmo < TMO));
          if (!(axi.RVALID && axi.RREADY)) fail("R drain timeout (rdataq queued)");
          else if (axi.RID !== 6'(i)) fail("RID order in rdataq queued read");
          else if (axi.RLAST !== 1'b1) fail("RLAST missing in rdataq queued read");
          beats_seen++;
        end
      end
    join

    tmo = 0;
    do begin
      @(posedge clk);
      tmo++;
    end while (!(axi.RVALID && axi.RREADY) && (tmo < TMO));
    if (!(axi.RVALID && axi.RREADY)) fail("final R timeout (rdataq)");
    else if (axi.RID !== 6'(cmd_depth + 1)) fail("final RID mismatch (rdataq)");
    else if (axi.RLAST !== 1'b1) fail("final RLAST missing (rdataq)");
    beats_seen++;
    if (n_ar != cmd_depth + 2) fail("AR count mismatch (rdataq)");
    axi.RREADY <= 1'b0;
  endtask

  // ------------------------------------------------------------------
  // multi-outstanding probes (OOO / R interleave)
  // ------------------------------------------------------------------
  // Issues n reads with distinct IDs while RREADY is low, then drains all
  // beats. Each burst's data is checked against its own address, so a
  // cross-ID data swap or a same-ID reorder is caught.
  task automatic rd_multi_probe(
    input  int          n,
    input  logic [32:0] addrs[],
    input  int          lens[],
    input  logic [5:0]  ids[],
    output int          done_order[$],
    output int          beats_by_id[64],
    output bit          interleaved,
    output bit          saw_invert
  );
    int  tmo, total, got;
    int  id_idx[64];
    int  idx[64];
    int  issued[64];
    bit  done[64];
    int  k, last_id;
    bit  last_valid;
    longint unsigned ba;
    logic [511:0] exp;
    logic [32:0] a;

    done_order.delete();
    interleaved = 1'b0;
    saw_invert  = 1'b0;
    total = 0;
    got   = 0;
    last_valid = 1'b0;
    last_id = 0;
    for (int i = 0; i < 64; i++) begin
      id_idx[i]    = -1;
      idx[i]       = 0;
      issued[i]    = 0;
      done[i]      = 1'b0;
      beats_by_id[i] = 0;
    end
    for (int i = 0; i < n; i++) begin
      id_idx[ids[i]] = i;
      issued[ids[i]] = i;
      total += lens[i] + 1;
    end

    axi.RREADY <= 1'b0;
    for (int i = 0; i < n; i++) begin
      a = addrs[i];
      @(posedge clk);
      axi.ARADDR  <= a;
      axi.ARBURST <= 2'b01;
      axi.ARID    <= ids[i];
      axi.ARLEN   <= 8'(lens[i]);
      axi.ARSIZE  <= 3'd6;
      axi.ARVALID <= 1'b1;
      tmo = 0;
      do begin
        @(posedge clk);
        tmo++;
      end while (!(axi.ARVALID && axi.ARREADY) && (tmo < TMO));
      if (!(axi.ARVALID && axi.ARREADY))
        fail($sformatf("rd_multi AR %0d timeout", i));
      axi.ARVALID <= 1'b0;
    end

    axi.RREADY <= 1'b1;
    tmo = 0;
    while ((got < total) && (tmo < TMO)) begin
      @(posedge clk);
      tmo++;
      if (axi.RVALID && axi.RREADY) begin
        k = (axi.RID < 64) ? id_idx[axi.RID] : -1;
        if (k < 0) begin
          fail($sformatf("rd_multi unexpected RID=%0d", axi.RID));
        end else begin
          if (idx[k] > lens[k]) begin
            fail($sformatf("rd_multi ID %0d extra beat", axi.RID));
          end else begin
            ba  = tbeat_addr(addrs[k], idx[k], lens[k], 6, 2'b01);
            exp = tb_beat_data(ba);
            if (axi.RDATA !== exp)
              fail($sformatf("rd_multi data mismatch ID=%0d beat=%0d addr=0x%0h",
                             axi.RID, idx[k], ba));
            if (axi.RLAST !== (idx[k] == lens[k]))
              fail($sformatf("rd_multi RLAST mismatch ID=%0d beat=%0d",
                             axi.RID, idx[k]));
          end
          if (last_valid && (last_id != axi.RID) && !done[last_id])
            interleaved = 1'b1;
          last_valid = 1'b1;
          last_id    = axi.RID;
          idx[k]++;
          got++;
          if (axi.RLAST) begin
            done[k] = 1'b1;
            beats_by_id[axi.RID] = idx[k];
            done_order.push_back(axi.RID);
          end
        end
      end
    end
    if (got != total)
      fail($sformatf("rd_multi drained %0d/%0d beats", got, total));
    axi.RREADY <= 1'b0;

    for (int i = 0; i < done_order.size(); i++) begin
      for (int j = i+1; j < done_order.size(); j++) begin
        if (issued[done_order[j]] < issued[done_order[i]]) saw_invert = 1'b1;
      end
    end
  endtask

  // All commands share one ID; completions must follow AR order. The data
  // check uses the next expected command's address, so a reorder also shows
  // up as a data mismatch.
  task automatic rd_same_id_probe(
    input  logic [5:0]  id,
    input  logic [32:0] addrs[],
    input  int          lens[],
    output int          done_lens[$],
    output bit          ok
  );
    int  tmo, total, got, cur, beat;
    longint unsigned ba;
    logic [511:0] exp;
    logic [32:0] a;

    done_lens.delete();
    ok = 1'b1;
    total = 0;
    got   = 0;
    cur   = 0;
    beat  = 0;
    for (int i = 0; i < addrs.size(); i++) total += lens[i] + 1;

    axi.RREADY <= 1'b0;
    for (int i = 0; i < addrs.size(); i++) begin
      a = addrs[i];
      @(posedge clk);
      axi.ARADDR  <= a;
      axi.ARBURST <= 2'b01;
      axi.ARID    <= id;
      axi.ARLEN   <= 8'(lens[i]);
      axi.ARSIZE  <= 3'd6;
      axi.ARVALID <= 1'b1;
      tmo = 0;
      do begin
        @(posedge clk);
        tmo++;
      end while (!(axi.ARVALID && axi.ARREADY) && (tmo < TMO));
      if (!(axi.ARVALID && axi.ARREADY)) begin
        fail($sformatf("rd_same_id AR %0d timeout", i));
        ok = 1'b0;
      end
      axi.ARVALID <= 1'b0;
    end

    axi.RREADY <= 1'b1;
    tmo = 0;
    while ((got < total) && (tmo < TMO)) begin
      @(posedge clk);
      tmo++;
      if (axi.RVALID && axi.RREADY) begin
        if (axi.RID !== id) begin
          fail($sformatf("rd_same_id RID exp=%0d got=%0d", id, axi.RID));
          ok = 1'b0;
        end
        if (cur >= addrs.size()) begin
          fail("rd_same_id extra burst");
          ok = 1'b0;
        end else begin
          ba  = tbeat_addr(addrs[cur], beat, lens[cur], 6, 2'b01);
          exp = tb_beat_data(ba);
          if (axi.RDATA !== exp) begin
            fail($sformatf("rd_same_id data mismatch burst=%0d beat=%0d", cur, beat));
            ok = 1'b0;
          end
          if (axi.RLAST !== (beat == lens[cur])) begin
            fail($sformatf("rd_same_id RLAST mismatch burst=%0d beat=%0d", cur, beat));
            ok = 1'b0;
          end
          got++;
          if (axi.RLAST) begin
            done_lens.push_back(beat + 1);
            cur++;
            beat = 0;
          end else begin
            beat++;
          end
        end
      end
    end
    if (got != total) begin
      fail($sformatf("rd_same_id drained %0d/%0d beats", got, total));
      ok = 1'b0;
    end
    if (cur != addrs.size()) begin
      fail($sformatf("rd_same_id completed %0d/%0d bursts", cur, addrs.size()));
      ok = 1'b0;
    end
    axi.RREADY <= 1'b0;
  endtask

  // Issues n single-beat writes with BREADY low, then records B completion
  // order. Used to observe out-of-order B responses across IDs.
  task automatic wr_multi_probe(
    input  int          n,
    input  logic [32:0] addrs[],
    input  logic [5:0]  ids[],
    output int          done_order[$],
    output bit          ok
  );
    int tmo;
    bit aw_done, w_done;
    longint unsigned ba;
    logic [32:0] a;

    done_order.delete();
    ok = 1'b1;
    axi.BREADY <= 1'b0;

    for (int i = 0; i < n; i++) begin
      a  = addrs[i];
      ba = tbeat_addr(a, 0, 0, 6, 2'b01);
      @(posedge clk);
      axi.AWADDR  <= a;
      axi.AWBURST <= 2'b01;
      axi.AWID    <= ids[i];
      axi.AWLEN   <= 8'd0;
      axi.AWSIZE  <= 3'd6;
      axi.AWCACHE <= 4'hF;
      axi.AWVALID <= 1'b1;
      axi.WDATA  <= tb_beat_data(ba);
      axi.WSTRB  <= '1;
      axi.WLAST  <= 1'b1;
      axi.WVALID <= 1'b1;
      aw_done = 1'b0;
      w_done  = 1'b0;
      tmo     = 0;
      while (!(aw_done && w_done) && (tmo < TMO)) begin
        @(posedge clk);
        if (!aw_done && axi.AWVALID && axi.AWREADY) begin
          aw_done = 1'b1;
          axi.AWVALID <= 1'b0;
        end
        if (!w_done && axi.WVALID && axi.WREADY) begin
          w_done = 1'b1;
          axi.WVALID <= 1'b0;
          axi.WLAST  <= 1'b0;
        end
        tmo++;
      end
      if (!(aw_done && w_done)) begin
        fail($sformatf("wr_multi command %0d timeout aw=%0b w=%0b", i, aw_done, w_done));
        ok = 1'b0;
      end
    end

    axi.BREADY <= 1'b1;
    for (int i = 0; i < n; i++) begin
      tmo = 0;
      do begin
        @(posedge clk);
        tmo++;
      end while (!(axi.BVALID && axi.BREADY) && (tmo < TMO));
      if (axi.BVALID && axi.BREADY) done_order.push_back(axi.BID);
      else begin
        fail($sformatf("wr_multi B %0d timeout", i));
        ok = 1'b0;
      end
    end
    axi.BREADY <= 1'b0;
  endtask

  // ------------------------------------------------------------------
  // read transaction
  // ------------------------------------------------------------------
  task automatic rd_txn(
    input logic [32:0] addr,
    input int          len = 0,
    input int          size = 6,
    input logic [1:0]  burst = 2'b01,
    input logic [5:0]  id = 0,
    output logic [511:0] data[],
    output logic [1:0]   resp[]
  );
    int tmo;
    data = new[len+1];
    resp = new[len+1];

    @(posedge clk);
    axi.ARADDR  <= addr;
    axi.ARBURST <= burst;
    axi.ARID    <= id;
    axi.ARLEN   <= 8'(len);
    axi.ARSIZE  <= 3'(size);
    axi.ARVALID <= 1'b1;
    tmo = 0;
    do begin
      @(posedge clk);
      tmo++;
    end while (!(axi.ARVALID && axi.ARREADY) && (tmo < TMO));
    if (axi.ARVALID && axi.ARREADY) begin
      t_ar = cyc;
    end else begin
      fail($sformatf("AR handshake timeout addr=0x%0h", addr));
    end
    axi.ARVALID <= 1'b0;
    axi.RREADY  <= 1'b1;

    for (int i = 0; i < len+1; i++) begin
      tmo = 0;
      do begin
        @(posedge clk);
        tmo++;
      end while (!(axi.RVALID && axi.RREADY) && (tmo < TMO));
      if (!(axi.RVALID && axi.RREADY)) begin
        fail($sformatf("R handshake timeout beat=%0d", i));
        data[i] = 'x;
        resp[i] = 2'bxx;
      end else begin
        if (i == 0) begin
          t_rfirst = cyc;
          last_rd_lat = int'(t_rfirst - t_ar);
        end
        if (axi.RID !== id) begin
          fail($sformatf("RID mismatch exp=%0d got=%0d", id, axi.RID));
        end
        if (axi.RLAST !== ((i == len))) begin
          fail($sformatf("RLAST mismatch at beat %0d: %b", i, axi.RLAST));
        end
        data[i] = axi.RDATA;
        resp[i] = axi.RRESP;
      end
    end
    axi.RREADY <= 1'b0;
    last_resp = resp[0];
    cov_rd.sample();
  endtask

endmodule
