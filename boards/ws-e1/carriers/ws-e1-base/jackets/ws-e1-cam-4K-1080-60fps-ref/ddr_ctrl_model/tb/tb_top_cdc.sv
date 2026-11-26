// Multi-clock testbench: AXI ports run on aclk, the controller core on
// ctrl_clk. CDC_RATIO is the ACLK/ctrl_clk frequency ratio (1, 2 or 4);
// CDC_ACLK_SLOW=1 makes ACLK half the ctrl_clk rate instead.
module tb_top_cdc #(
  parameter int  CDC_RATIO = 1,
  parameter bit  CDC_ACLK_SLOW = 0,
  parameter int  READ_LATENCY_MIN = 10,
  parameter int  READ_LATENCY_MAX = 30,
  parameter int  WRITE_OSTD_DEPTH = 8,
  parameter int  READ_OSTD_DEPTH = 8,
  parameter int  CMD_QUEUE_DEPTH = 8,
  parameter int  B_FIFO_DEPTH = 8,
  parameter int  W_ACCEPT_INTERVAL = 1,
  parameter int  ERR_INJECT_RATE = 0
);
  import ddr_model_pkg::*;
  import tb_pkg::*;

  localparam int TB_INIT_CYCLES = 200;
  localparam real ACLK_HALF = CDC_ACLK_SLOW ? 10.0 : (5.0 / CDC_RATIO);

  logic ctrl_clk = 1'b0;
  always #5 ctrl_clk = ~ctrl_clk;

  logic aclk = 1'b0;
  always #(ACLK_HALF) aclk = ~aclk;

  ddr_model_if axi0();
  ddr_model_if axi1();

  logic cfg_reset, cfg_start, cfg_sel, cfg_done;
  logic ctrl_init_done, ctrl_ready, ctrl_err, ctrl_busy;

  logic [63:0] tb_cyc = 0;
  always @(posedge ctrl_clk) tb_cyc <= tb_cyc + 1'b1;
  int acyc = 0;
  always @(posedge aclk) acyc <= acyc + 1;

  int err_count;

  ddr_axi_model_top #(
    .INIT_CYCLES(TB_INIT_CYCLES),
    .ENABLE_CTRL_STATUS(1'b1),
    .CDC_ENABLE(1'b1),
    .WRITE_OSTD_DEPTH(WRITE_OSTD_DEPTH),
    .READ_OSTD_DEPTH(READ_OSTD_DEPTH),
    .READ_LATENCY_MIN(READ_LATENCY_MIN),
    .READ_LATENCY_MAX(READ_LATENCY_MAX),
    .CMD_QUEUE_DEPTH(CMD_QUEUE_DEPTH),
    .B_FIFO_DEPTH(B_FIFO_DEPTH),
    .W_ACCEPT_INTERVAL(W_ACCEPT_INTERVAL),
    .ERR_INJECT_RATE(ERR_INJECT_RATE)
  ) dut (
    .ctrl_clk(ctrl_clk),
    .ACLK_0(aclk), .ARSTN_0(axi0.ARSTN),
    .AWADDR_0(axi0.AWADDR), .AWBURST_0(axi0.AWBURST), .AWID_0(axi0.AWID),
    .AWLEN_0(axi0.AWLEN), .AWREADY_0(axi0.AWREADY), .AWSIZE_0(axi0.AWSIZE),
    .AWVALID_0(axi0.AWVALID), .AWLOCK_0(axi0.AWLOCK), .AWAPCMD_0(axi0.AWAPCMD),
    .AWQOS_0(axi0.AWQOS), .AWCACHE_0(axi0.AWCACHE),
    .AWALLSTRB_0(axi0.AWALLSTRB), .AWCOBUF_0(axi0.AWCOBUF),
    .WDATA_0(axi0.WDATA), .WLAST_0(axi0.WLAST), .WREADY_0(axi0.WREADY),
    .WSTRB_0(axi0.WSTRB), .WVALID_0(axi0.WVALID),
    .BID_0(axi0.BID), .BREADY_0(axi0.BREADY), .BRESP_0(axi0.BRESP),
    .BVALID_0(axi0.BVALID),
    .ARADDR_0(axi0.ARADDR), .ARBURST_0(axi0.ARBURST), .ARID_0(axi0.ARID),
    .ARLEN_0(axi0.ARLEN), .ARREADY_0(axi0.ARREADY), .ARSIZE_0(axi0.ARSIZE),
    .ARVALID_0(axi0.ARVALID), .ARLOCK_0(axi0.ARLOCK), .ARAPCMD_0(axi0.ARAPCMD),
    .ARQOS_0(axi0.ARQOS),
    .RDATA_0(axi0.RDATA), .RID_0(axi0.RID), .RLAST_0(axi0.RLAST),
    .RREADY_0(axi0.RREADY), .RRESP_0(axi0.RRESP), .RVALID_0(axi0.RVALID),

    .ACLK_1(aclk), .ARSTN_1(axi1.ARSTN),
    .AWADDR_1(axi1.AWADDR), .AWBURST_1(axi1.AWBURST), .AWID_1(axi1.AWID),
    .AWLEN_1(axi1.AWLEN), .AWREADY_1(axi1.AWREADY), .AWSIZE_1(axi1.AWSIZE),
    .AWVALID_1(axi1.AWVALID), .AWLOCK_1(axi1.AWLOCK), .AWAPCMD_1(axi1.AWAPCMD),
    .AWQOS_1(axi1.AWQOS), .AWCACHE_1(axi1.AWCACHE),
    .AWALLSTRB_1(axi1.AWALLSTRB), .AWCOBUF_1(axi1.AWCOBUF),
    .WDATA_1(axi1.WDATA), .WLAST_1(axi1.WLAST), .WREADY_1(axi1.WREADY),
    .WSTRB_1(axi1.WSTRB), .WVALID_1(axi1.WVALID),
    .BID_1(axi1.BID), .BREADY_1(axi1.BREADY), .BRESP_1(axi1.BRESP),
    .BVALID_1(axi1.BVALID),
    .ARADDR_1(axi1.ARADDR), .ARBURST_1(axi1.ARBURST), .ARID_1(axi1.ARID),
    .ARLEN_1(axi1.ARLEN), .ARREADY_1(axi1.ARREADY), .ARSIZE_1(axi1.ARSIZE),
    .ARVALID_1(axi1.ARVALID), .ARLOCK_1(axi1.ARLOCK), .ARAPCMD_1(axi1.ARAPCMD),
    .ARQOS_1(axi1.ARQOS),
    .RDATA_1(axi1.RDATA), .RID_1(axi1.RID), .RLAST_1(axi1.RLAST),
    .RREADY_1(axi1.RREADY), .RRESP_1(axi1.RRESP), .RVALID_1(axi1.RVALID),

    .CFG_RESET(cfg_reset), .CFG_START(cfg_start), .CFG_SEL(cfg_sel),
    .CFG_DONE(cfg_done),
    .CTRL_INIT_DONE(ctrl_init_done), .CTRL_READY(ctrl_ready),
    .CTRL_ERR(ctrl_err), .CTRL_BUSY(ctrl_busy)
  );

  axi_master_bfm bfm0 (.axi(axi0), .clk(aclk));
  axi_master_bfm bfm1 (.axi(axi1), .clk(aclk));
  tb_scoreboard sb ();

  ddr_model_assertions u_assert (
    .clk(aclk),
    .rstn0(axi0.ARSTN), .rstn1(axi1.ARSTN),
    .awvalid0(axi0.AWVALID), .awready0(axi0.AWREADY),
    .wvalid0(axi0.WVALID), .wready0(axi0.WREADY), .wlast0(axi0.WLAST),
    .bvalid0(axi0.BVALID), .bready0(axi0.BREADY),
    .arvalid0(axi0.ARVALID), .arready0(axi0.ARREADY),
    .rvalid0(axi0.RVALID), .rready0(axi0.RREADY), .rlast0(axi0.RLAST),
    .awvalid1(axi1.AWVALID), .awready1(axi1.AWREADY),
    .wvalid1(axi1.WVALID), .wready1(axi1.WREADY), .wlast1(axi1.WLAST),
    .bvalid1(axi1.BVALID), .bready1(axi1.BREADY),
    .arvalid1(axi1.ARVALID), .arready1(axi1.ARREADY),
    .rvalid1(axi1.RVALID), .rready1(axi1.RREADY), .rlast1(axi1.RLAST),
    .cfg_reset(cfg_reset), .cfg_start(cfg_start), .cfg_sel(cfg_sel),
    .cfg_done(cfg_done),
    .arb_req0(1'b0), .arb_req1(1'b0),
    .arb_grant0(1'b0), .arb_grant1(1'b0),
    .arb_enable(1'b0)
  );

  task automatic fail(input string msg);
    err_count++;
    $error("[TB-CDC] %s", msg);
  endtask

  task automatic check(input bit cond, input string msg);
    if (!cond) fail(msg);
  endtask

  task automatic expect_resp(input logic [1:0] got, input logic [1:0] exp,
                             input string what);
    if (got !== exp) fail($sformatf("%s: resp exp=%b got=%b", what, exp, got));
  endtask

  task automatic wait_cfg_done();
    int tmo;
    tmo = 0;
    while (!cfg_done && (tmo < 200000)) begin
      @(posedge ctrl_clk);
      tmo++;
    end
    if (!cfg_done) fail("CFG_DONE timeout");
  endtask

  task automatic do_write(input int port, input logic [32:0] addr,
                          input int len, input int size, input logic [5:0] id,
                          input int strb_mode, input bit wfirst,
                          input logic [1:0] exp_resp);
    logic [1:0] resp;
    if (port == 0)
      bfm0.wr_txn(.addr(addr), .len(len), .size(size), .burst(2'b01), .id(id),
                  .cache(4'hF), .strb_mode(strb_mode), .wfirst(wfirst),
                  .resp(resp));
    else
      bfm1.wr_txn(.addr(addr), .len(len), .size(size), .burst(2'b01), .id(id),
                  .cache(4'hF), .strb_mode(strb_mode), .wfirst(wfirst),
                  .resp(resp));
    expect_resp(resp, exp_resp, $sformatf("write p%0d 0x%0h", port, addr));
    if ((exp_resp == 2'b00) && (resp == 2'b00))
      sb.record_write(addr, len, size, 2'b01, strb_mode);
  endtask

  task automatic do_read(input int port, input logic [32:0] addr,
                         input int len, input int size, input logic [5:0] id);
    logic [511:0] data[];
    logic [1:0]   resp[];
    if (port == 0)
      bfm0.rd_txn(.addr(addr), .len(len), .size(size), .burst(2'b01), .id(id),
                  .data(data), .resp(resp));
    else
      bfm1.rd_txn(.addr(addr), .len(len), .size(size), .burst(2'b01), .id(id),
                  .data(data), .resp(resp));
    sb.check_read(addr, len, size, 2'b01, id, data, resp, 2'b00);
  endtask

  // ------------------------------------------------------------------
  // tests
  // ------------------------------------------------------------------
  task automatic check_idle(input string what);
    repeat (20) @(posedge ctrl_clk);
    check(ctrl_busy === 1'b0, $sformatf("%s: core busy after transactions", what));
  endtask

  task automatic test_cdc_smoke();
    do_write(0, 33'h0100_0000, 0, 6, 6'd1, 0, 0, 2'b00);
    do_read(0, 33'h0100_0000, 0, 6, 6'd1);
    do_write(0, 33'h0100_1000, 3, 6, 6'd2, 2, 1, 2'b00);
    do_read(0, 33'h0100_1000, 3, 6, 6'd2);
    do_write(1, 33'h0100_2000, 1, 5, 6'd3, 0, 0, 2'b00);
    do_read(1, 33'h0100_2000, 1, 5, 6'd3);
    check_idle("cdc_smoke");
  endtask

  task automatic test_cdc_dual();
    logic [1:0] r0, r1;
    fork
      bfm0.wr_txn(.addr(33'h0110_0000), .len(1), .size(6), .burst(2'b01),
                  .id(6'd10), .cache(4'hF), .resp(r0));
      bfm1.wr_txn(.addr(33'h0111_0000), .len(1), .size(6), .burst(2'b01),
                  .id(6'd11), .cache(4'hF), .resp(r1));
    join
    expect_resp(r0, 2'b00, "cdc_dual P0 write");
    expect_resp(r1, 2'b00, "cdc_dual P1 write");
    sb.record_write(33'h0110_0000, 1, 6, 2'b01, 0);
    sb.record_write(33'h0111_0000, 1, 6, 2'b01, 0);
    do_read(1, 33'h0110_0000, 1, 6, 6'd12);
    do_read(0, 33'h0111_0000, 1, 6, 6'd13);

    // concurrent reads on both ports
    fork
      do_read(0, 33'h0110_0000, 1, 6, 6'd14);
      do_read(1, 33'h0111_0000, 1, 6, 6'd15);
    join
  endtask

  task automatic test_cdc_ostd();
    int  accepted;
    bit  blocked;
    logic [32:0] a;
    bfm0.wr_ostd_probe(WRITE_OSTD_DEPTH, 33'h0120_0000, accepted, blocked);
    check(accepted == WRITE_OSTD_DEPTH + 1,
          $sformatf("cdc_ostd wr accepted=%0d", accepted));
    check(blocked, "cdc_ostd: AW was not blocked at the outstanding limit");
    for (int i = 0; i <= WRITE_OSTD_DEPTH; i++) begin
      a = 33'h0120_0000 + 33'(i * 64);
      sb.record_write(a, 0, 6, 2'b01, 0);
    end
    for (int i = 0; i <= WRITE_OSTD_DEPTH; i++) begin
      do_read(0, 33'h0120_0000 + 33'(i * 64), 0, 6, 6'(60 + i));
    end
  endtask

  task automatic test_cdc_stress();
    logic [32:0] ha[$];
    int          hl[$];
    int          hs[$];
    int          hp[$];
    int          len, size, off, idx, strb_mode, port;
    logic [32:0] a;
    longint unsigned span;
    for (int i = 0; i < 40; i++) begin
      if ((ha.size() == 0) || (($urandom % 100) < 55)) begin
        case ($urandom % 4)
          0: len = 0;
          1: len = 1;
          2: len = 3;
          default: len = 7;
        endcase
        size  = 3 + ($urandom % 4);
        strb_mode = $urandom % 4;
        port  = $urandom % 2;
        span  = longint'(len + 1) * (64'(1) << size);
        off   = ($urandom % 48) * 64;
        if ((longint'(off) + span) > 4096) off = 0;
        a = 33'h0140_0000 + 33'((i % 8) * 32'h2000 + off);
        do_write(port, a, len, size, 6'($urandom), strb_mode,
                 (($urandom % 4) == 0), 2'b00);
        ha.push_back(a);
        hl.push_back(len);
        hs.push_back(size);
        hp.push_back(port);
      end else begin
        idx  = $urandom % ha.size();
        a    = ha[idx];
        len  = hl[idx];
        size = hs[idx];
        port = hp[idx];
        do_read(port, a, len, size, 6'($urandom));
      end
    end
    $display("[TB-CDC] stress: %0d writes tracked", ha.size());
  endtask

  task automatic test_cdc_rst();
    logic [1:0] resp;
    axi0.ARSTN = 1'b0;
    repeat (10) @(posedge ctrl_clk);
    do_write(1, 33'h0150_0000, 1, 6, 6'd70, 0, 0, 2'b00);
    axi0.ARSTN = 1'b1;
    repeat (10) @(posedge ctrl_clk);
    do_write(0, 33'h0150_1000, 1, 6, 6'd71, 0, 0, 2'b00);
    do_read(1, 33'h0150_1000, 1, 6, 6'd72);
    do_read(0, 33'h0150_0000, 1, 6, 6'd73);
  endtask

  task automatic test_cdc_wgap();
    int gap_last, gap_min;
    bit mon;
    gap_last = -1; gap_min = 1_000_000; mon = 1'b1;
    fork
      begin : wgap_mon
        while (mon) begin
          @(posedge aclk);
          if (axi0.WVALID && axi0.WREADY) begin
            if ((gap_last >= 0) && ((acyc - gap_last) < gap_min))
              gap_min = acyc - gap_last;
            gap_last = acyc;
          end
        end
      end
      begin : wgap_traffic
        do_write(0, 33'h0160_0000, 1, 6, 6'd90, 0, 0, 2'b00);
        do_write(0, 33'h0160_1000, 0, 6, 6'd91, 0, 0, 2'b00);
        do_write(1, 33'h0160_2000, 1, 6, 6'd92, 0, 0, 2'b00);
        mon = 1'b0;
      end
    join
    if (W_ACCEPT_INTERVAL > 1) begin
      check(gap_min >= W_ACCEPT_INTERVAL,
            $sformatf("cdc_wgap: W gap %0d < interval %0d",
                      gap_min, W_ACCEPT_INTERVAL));
    end
    do_read(0, 33'h0160_0000, 1, 6, 6'd93);
    do_read(1, 33'h0160_2000, 1, 6, 6'd94);
  endtask

  task automatic test_cdc_contend();
    logic [32:0] a0[4], a1[4];
    logic [5:0]  ids0[4], ids1[4];
    int          d0[$], d1[$];
    bit          ok0, ok1;
    int           rdo0[$], rdo1[$];
    bit           il0, il1, inv0, inv1;
    int           beats0[64], beats1[64];
    int           lens0[4], lens1[4];
    for (int k = 0; k < 4; k++) begin
      a0[k]   = 33'h0170_0000 + 33'(k * 64);
      ids0[k] = 6'(k);
      a1[k]   = 33'h0171_0000 + 33'(k * 64);
      ids1[k] = 6'(16 + k);
      lens0[k] = 0;
      lens1[k] = 0;
    end
    fork
      bfm0.wr_multi_probe(4, a0, ids0, d0, ok0);
      bfm1.wr_multi_probe(4, a1, ids1, d1, ok1);
    join
    check(ok0 && ok1, "cdc_contend: write probe reported errors");
    check((d0.size() == 4) && (d1.size() == 4),
          $sformatf("cdc_contend: B responses p0=%0d p1=%0d", d0.size(), d1.size()));
    for (int k = 0; k < 4; k++) begin
      sb.record_write(a0[k], 0, 6, 2'b01, 0);
      sb.record_write(a1[k], 0, 6, 2'b01, 0);
    end
    // Concurrent multi-burst reads keep both AR FIFOs occupied.
    fork
      bfm0.rd_multi_probe(4, a0, lens0, ids0, rdo0, beats0, il0, inv0);
      bfm1.rd_multi_probe(4, a1, lens1, ids1, rdo1, beats1, il1, inv1);
    join
    check((rdo0.size() == 4) && (rdo1.size() == 4),
          $sformatf("cdc_contend: R responses p0=%0d p1=%0d",
                    rdo0.size(), rdo1.size()));
  endtask

  task automatic test_cdc_err();
    logic [1:0] resp;
    logic [511:0] data[];
    logic [1:0]   rsp[];
    bfm0.wr_txn(.addr(33'h0180_0000), .len(0), .size(6), .burst(2'b01),
                .id(6'd100), .cache(4'hF), .resp(resp));
    expect_resp(resp, 2'b10, "cdc_err P0 write");
    bfm1.wr_txn(.addr(33'h0181_0000), .len(1), .size(6), .burst(2'b01),
                .id(6'd101), .cache(4'hF), .resp(resp));
    expect_resp(resp, 2'b10, "cdc_err P1 write");
    bfm0.rd_txn(.addr(33'h0180_0000), .len(0), .size(6), .burst(2'b01),
                .id(6'd102), .data(data), .resp(rsp));
    check(rsp.size() == 1, "cdc_err: no response beat");
    expect_resp(rsp[0], 2'b10, "cdc_err P0 read");
    bfm1.rd_txn(.addr(33'h0181_0000), .len(1), .size(6), .burst(2'b01),
                .id(6'd103), .data(data), .resp(rsp));
    check(rsp.size() == 2, "cdc_err: wrong beat count");
    expect_resp(rsp[0], 2'b10, "cdc_err P1 read beat0");
    expect_resp(rsp[1], 2'b10, "cdc_err P1 read beat1");
    check(ctrl_err === 1'b1, "cdc_err: CTRL_ERR not latched");
  endtask

  // ------------------------------------------------------------------
  // main
  // ------------------------------------------------------------------
  initial begin
    string test;
    longint unsigned t_cfg_start;
    int total;

    if (!$value$plusargs("TEST=%s", test)) test = "cdc_smoke";
    err_count = 0;

    axi0.ARSTN = 1'b0;
    axi1.ARSTN = 1'b0;
    cfg_reset  = 1'b1;
    cfg_start  = 1'b0;
    cfg_sel    = 1'b0;

    $display("[TB-CDC] test=%s ratio=%0d slow=%0d aclk_half=%0.2f",
             test, CDC_RATIO, CDC_ACLK_SLOW, ACLK_HALF);

    repeat (10) @(posedge ctrl_clk);
    check(cfg_done === 1'b0, "CFG_DONE high during reset");

    cfg_reset = 1'b0;
    repeat (2) @(posedge ctrl_clk);
    axi0.ARSTN = 1'b1;
    axi1.ARSTN = 1'b1;
    repeat (4) @(posedge ctrl_clk);
    // Abort a partially completed init, then restart from IDLE.
    cfg_start = 1'b1;
    repeat (20) @(posedge ctrl_clk);
    cfg_start = 1'b0;
    repeat (4) @(posedge ctrl_clk);
    check(!cfg_done, "CFG_DONE after aborted init");
    cfg_start = 1'b1;
    t_cfg_start = tb_cyc;
    wait_cfg_done();

    if ((tb_cyc - t_cfg_start) < (TB_INIT_CYCLES - 3)) begin
      fail($sformatf("CFG_DONE too early: %0d cycles", tb_cyc - t_cfg_start));
    end
    repeat (10) @(posedge ctrl_clk);
    // A CFG_SEL pulse returns the FSM from DONE to IDLE; releasing it starts
    // a fresh initialization while CFG_START stays asserted.
    cfg_sel = 1'b1;
    repeat (4) @(posedge ctrl_clk);
    check(!cfg_done, "CFG_DONE during CFG_SEL");
    cfg_sel = 1'b0;
    repeat (4) @(posedge ctrl_clk);
    wait_cfg_done();
    repeat (10) @(posedge ctrl_clk);

    case (test)
      "cdc_smoke":  test_cdc_smoke();
      "cdc_dual":   test_cdc_dual();
      "cdc_ostd":   test_cdc_ostd();
      "cdc_stress": test_cdc_stress();
      "cdc_rst":    test_cdc_rst();
      "cdc_slow":   test_cdc_smoke();
      "cdc_wgap":   test_cdc_wgap();
      "cdc_contend": test_cdc_contend();
      "cdc_err":    test_cdc_err();
      default:      fail($sformatf("unknown TEST=%s", test));
    endcase

    repeat (50) @(posedge ctrl_clk);
    sb.report();
    total = err_count + bfm0.err_count + bfm1.err_count + sb.err_count;
    if (total == 0) begin
      $display("TEST %s PASS", test);
      $finish;
    end else begin
      $display("TEST %s FAIL errors=%0d (tb=%0d bfm0=%0d bfm1=%0d sb=%0d)",
               test, total, err_count, bfm0.err_count, bfm1.err_count,
               sb.err_count);
      $fatal(1, "test failed");
    end
  end

  initial begin
    #20ms;
    $fatal(1, "global watchdog timeout");
  end

endmodule
