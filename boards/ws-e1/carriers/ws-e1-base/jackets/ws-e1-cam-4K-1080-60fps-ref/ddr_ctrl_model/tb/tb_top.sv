module tb_top #(
  parameter int WRITE_OSTD_DEPTH = 8,
  parameter int READ_OSTD_DEPTH  = 8,
  parameter int LATENCY_MODE = 0,
  parameter int READ_LATENCY_MIN = 10,
  parameter int READ_LATENCY_MAX = 30,
  parameter int OTHER_AWCACHE_POLICY = 0,
  parameter int R_BEAT_INTERVAL = 1,
  parameter int INIT_AXI_BLOCK = 1,
  parameter int INIT_AXI_RESP = 0,
  parameter int CMD_QUEUE_DEPTH = 8,
  parameter int WRITE_DATA_QUEUE_DEPTH = 16,
  parameter int READ_DATA_QUEUE_DEPTH = 16,
  parameter int B_FIFO_DEPTH = 8,
  parameter int ARB_GRANT_INTERVAL = 2,
  parameter int ERR_INJECT_RATE = 0,
  parameter bit OUT_OF_ORDER_ENABLE = 1'b0,
  parameter bit R_INTERLEAVE_ENABLE = 1'b0,
  parameter int LATENCY_SEED = 1,
  parameter int W_ACCEPT_INTERVAL = 1,
  parameter int ADDR_MAP_MODE = 0,
  parameter int ADDR_CS_BIT_POS = 27,
  parameter int ADDR_HOLE_POLICY = 0,
  parameter longint unsigned ADDR_HOLE_START = 0,
  parameter longint unsigned ADDR_HOLE_END = 0,
  parameter bit CFG_RESET_CLEAR_MEM = 1'b0
);
  import ddr_model_pkg::*;
  import tb_pkg::*;

  localparam int TB_INIT_CYCLES = 200;
  localparam int RD_LAT_MIN = READ_LATENCY_MIN;
  localparam int RD_LAT_MAX = READ_LATENCY_MAX;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  ddr_model_if axi0();
  ddr_model_if axi1();

  logic cfg_reset;
  logic cfg_start;
  logic cfg_sel;
  logic cfg_done;
  logic ctrl_init_done;
  logic ctrl_ready;
  logic ctrl_err;
  logic ctrl_busy;
  logic [32:0] dbg_fields;
  logic [32:0] dbg_fields_addr;

  logic [63:0] tb_cyc = 0;
  always @(posedge clk) tb_cyc <= tb_cyc + 1'b1;

  int err_count;

  ddr_axi_model_top #(
    .INIT_CYCLES(TB_INIT_CYCLES),
    .ENABLE_CTRL_STATUS(1'b1),
    .WRITE_OSTD_DEPTH(WRITE_OSTD_DEPTH),
    .READ_OSTD_DEPTH(READ_OSTD_DEPTH),
    .LATENCY_MODE(LATENCY_MODE),
    .READ_LATENCY_MIN(READ_LATENCY_MIN),
    .READ_LATENCY_MAX(READ_LATENCY_MAX),
    .OTHER_AWCACHE_POLICY(OTHER_AWCACHE_POLICY),
    .R_BEAT_INTERVAL(R_BEAT_INTERVAL),
    .INIT_AXI_BLOCK(INIT_AXI_BLOCK != 0),
    .INIT_AXI_RESP(INIT_AXI_RESP),
    .CMD_QUEUE_DEPTH(CMD_QUEUE_DEPTH),
    .WRITE_DATA_QUEUE_DEPTH(WRITE_DATA_QUEUE_DEPTH),
    .READ_DATA_QUEUE_DEPTH(READ_DATA_QUEUE_DEPTH),
    .B_FIFO_DEPTH(B_FIFO_DEPTH),
    .ARB_GRANT_INTERVAL(ARB_GRANT_INTERVAL),
    .ERR_INJECT_RATE(ERR_INJECT_RATE),
    .OUT_OF_ORDER_ENABLE(OUT_OF_ORDER_ENABLE),
    .R_INTERLEAVE_ENABLE(R_INTERLEAVE_ENABLE),
    .LATENCY_SEED(LATENCY_SEED),
    .W_ACCEPT_INTERVAL(W_ACCEPT_INTERVAL),
    .ADDR_MAP_MODE(ADDR_MAP_MODE),
    .ADDR_CS_BIT_POS(ADDR_CS_BIT_POS),
    .ADDR_HOLE_POLICY(ADDR_HOLE_POLICY),
    .ADDR_HOLE_START(ADDR_HOLE_START),
    .ADDR_HOLE_END(ADDR_HOLE_END),
    .CFG_RESET_CLEAR_MEM(CFG_RESET_CLEAR_MEM)
  ) dut (
    .ctrl_clk(clk),
    .ACLK_0(clk), .ARSTN_0(axi0.ARSTN),
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

    .ACLK_1(clk), .ARSTN_1(axi1.ARSTN),
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
    .CTRL_ERR(ctrl_err), .CTRL_BUSY(ctrl_busy),
    .DBG_FIELDS(dbg_fields), .DBG_FIELDS_ADDR(dbg_fields_addr)
  );

  axi_master_bfm bfm0 (.axi(axi0), .clk(clk));
  axi_master_bfm bfm1 (.axi(axi1), .clk(clk));
  tb_scoreboard sb ();

  ddr_model_assertions u_assert (
    .clk(clk),
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
    .arb_req0(dut.aw_req[0] | dut.ar_req[0]),
    .arb_req1(dut.aw_req[1] | dut.ar_req[1]),
    .arb_grant0(dut.aw_grant[0] | dut.ar_grant[0]),
    .arb_grant1(dut.aw_grant[1] | dut.ar_grant[1]),
    .ARB_GRANT_INTERVAL(ARB_GRANT_INTERVAL)
  );

  // ------------------------------------------------------------------
  // interface pacing monitors
  // ------------------------------------------------------------------
  bit gap_mon_en = 1'b0;
  bit wgap_mon_en = 1'b0;
  int gap_last = -1;
  int gap_min = 1_000_000;
  int wgap_last = -1;
  int wgap_min = 1_000_000;

  always @(posedge clk) begin
    if (gap_mon_en && axi0.RVALID && axi0.RREADY) begin
      if ((gap_last >= 0) && ((int'(tb_cyc) - gap_last) < gap_min))
        gap_min = int'(tb_cyc) - gap_last;
      gap_last = int'(tb_cyc);
    end
    if (wgap_mon_en && axi0.WVALID && axi0.WREADY) begin
      if ((wgap_last >= 0) && ((int'(tb_cyc) - wgap_last) < wgap_min))
        wgap_min = int'(tb_cyc) - wgap_last;
      wgap_last = int'(tb_cyc);
    end
  end

  // ------------------------------------------------------------------
  // helpers
  // ------------------------------------------------------------------
  task automatic fail(input string msg);
    err_count++;
    $error("[TB] %s", msg);
  endtask

  task automatic check(input bit cond, input string msg);
    if (!cond) fail(msg);
  endtask

  task automatic expect_resp(input logic [1:0] got, input logic [1:0] exp,
                             input string what);
    if (got !== exp) begin
      fail($sformatf("%s: BRESP exp=%b got=%b", what, exp, got));
    end
  endtask

  task automatic wait_cfg_done();
    int tmo;
    tmo = 0;
    while (!cfg_done && (tmo < 20000)) begin
      @(posedge clk);
      tmo++;
    end
    if (!cfg_done) fail("CFG_DONE timeout");
  endtask

  task automatic check_reset_outputs();
    for (int i = 0; i < 5; i++) begin
      @(posedge clk);
      if (axi0.AWREADY || axi0.WREADY || axi0.ARREADY ||
          axi0.BVALID || axi0.RVALID ||
          axi1.AWREADY || axi1.WREADY || axi1.ARREADY ||
          axi1.BVALID || axi1.RVALID) begin
        fail("reset: a VALID/READY output is asserted");
      end
      if ((^{axi0.BID, axi0.BRESP, axi0.RDATA, axi0.RID,
             axi0.RLAST, axi0.RRESP}) === 1'bx) begin
        fail("reset: X on B/R output payload");
      end
    end
  endtask

  task automatic do_read_check(
    input int port,
    input logic [32:0] addr,
    input int len = 0,
    input int size = 6,
    input logic [1:0] burst = 2'b01,
    input logic [5:0] id = 0,
    input logic [1:0] exp_resp = 2'b00
  );
    logic [511:0] data[];
    logic [1:0]   resp[];
    if (port == 0) begin
      bfm0.rd_txn(.addr(addr), .len(len), .size(size), .burst(burst),
                  .id(id), .data(data), .resp(resp));
    end else begin
      bfm1.rd_txn(.addr(addr), .len(len), .size(size), .burst(burst),
                  .id(id), .data(data), .resp(resp));
    end
    sb.check_read(addr, len, size, burst, id, data, resp, exp_resp);
  endtask

  task automatic do_write_record(
    input int port,
    input logic [32:0] addr,
    input int len,
    input int size,
    input logic [1:0] burst,
    input logic [5:0] id,
    input logic [3:0] cache,
    input bit cobuf,
    input bit allstrb,
    input int strb_mode,
    input bit wfirst,
    input int pause_after_first,
    input logic [1:0] exp_resp
  );
    logic [1:0] resp;
    if (port == 0) begin
      bfm0.wr_txn(.addr(addr), .len(len), .size(size), .burst(burst), .id(id),
                  .cache(cache), .cobuf(cobuf), .allstrb(allstrb),
                  .strb_mode(strb_mode), .wfirst(wfirst),
                  .pause_after_first(pause_after_first), .resp(resp));
    end else begin
      bfm1.wr_txn(.addr(addr), .len(len), .size(size), .burst(burst), .id(id),
                  .cache(cache), .cobuf(cobuf), .allstrb(allstrb),
                  .strb_mode(strb_mode), .wfirst(wfirst),
                  .pause_after_first(pause_after_first), .resp(resp));
    end
    expect_resp(resp, exp_resp, $sformatf("write addr=0x%0h", addr));
    if ((exp_resp == 2'b00) && (resp == 2'b00)) begin
      sb.record_write(addr, len, size, burst, strb_mode);
    end
  endtask

  // ------------------------------------------------------------------
  // tests
  // ------------------------------------------------------------------
  task automatic test_init_early(input string test,
                                 input longint unsigned t_start);
    logic [1:0] resp;
    if (test == "init_block") begin
      // AWVALID is driven while init is still running; AWREADY must stay low
      // and the transaction must complete once CFG_DONE rises.
      bfm0.wr_aw_late_w(.addr(33'h000A_0000), .len(0), .size(6),
                        .id(6'd36), .resp(resp));
      expect_resp(resp, 2'b00, "init_block write");
      sb.record_write(33'h000A_0000, 0, 6, 2'b01, 0);
    end else begin
      bfm0.wr_txn(.addr(33'h000B_0000), .len(0), .size(6), .burst(2'b01),
                  .id(6'd37), .cache(4'hF), .resp(resp));
      expect_resp(resp, 2'b10, "init_slverr write");
      check((tb_cyc - t_start) < (TB_INIT_CYCLES - 10),
            "init_slverr transaction did not complete during init");
    end
  endtask

  task automatic test_init_late(input string test);
    repeat (10) @(posedge clk);
    if (test == "init_block") begin
      do_read_check(0, 33'h000A_0000, 0, 6, 2'b01, 6'd38);
    end else begin
      // The SLVERR write must not modify storage.
      do_read_check(0, 33'h000B_0000, 0, 6, 2'b01, 6'd39);
    end
  endtask

  task automatic test_smoke_reset();
    check(ctrl_init_done === 1'b1, "CTRL_INIT_DONE not asserted after CFG");
    check(ctrl_ready === 1'b1, "CTRL_READY not asserted after CFG");
    check(cfg_done === 1'b1, "CFG_DONE not asserted");
  endtask

  task automatic test_smoke_cfg();
    check(cfg_done === 1'b1, "CFG_DONE not asserted");
    check(ctrl_busy === 1'b0 || ctrl_busy === 1'b1, "CTRL_BUSY X");
    // CFG_DONE must remain high while CFG_START stays high.
    repeat (10) @(posedge clk);
    check(cfg_done === 1'b1, "CFG_DONE dropped while CFG_START high");
  endtask

  task automatic test_wr_single();
    do_write_record(0, 33'h0000_1000, 0, 6, 2'b01, 6'd1, 4'hF, 0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h0000_1000, 0, 6, 2'b01, 6'd1);
  endtask

  task automatic test_wr_incr();
    do_write_record(0, 33'h0000_2000, 3, 6, 2'b01, 6'd2, 4'hF, 0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h0000_2000, 3, 6, 2'b01, 6'd2);
  endtask

  task automatic test_wr_wstrb();
    do_write_record(0, 33'h0000_3000, 2, 6, 2'b01, 6'd3, 4'hF, 0, 0, 1, 0, 0, 2'b00);
    do_read_check(0, 33'h0000_3000, 2, 6, 2'b01, 6'd3);
    do_write_record(0, 33'h0000_3400, 2, 6, 2'b01, 6'd4, 4'hF, 0, 0, 2, 0, 0, 2'b00);
    do_read_check(0, 33'h0000_3400, 2, 6, 2'b01, 6'd4);
    do_write_record(0, 33'h0000_3800, 2, 6, 2'b01, 6'd5, 4'hF, 0, 0, 3, 0, 0, 2'b00);
    do_read_check(0, 33'h0000_3800, 2, 6, 2'b01, 6'd5);
  endtask

  task automatic test_wr_w_before_aw();
    do_write_record(0, 33'h0000_4000, 1, 6, 2'b01, 6'd6, 4'hF, 0, 0, 0, 1, 0, 2'b00);
    do_read_check(0, 33'h0000_4000, 1, 6, 2'b01, 6'd6);
  endtask

  task automatic test_aw_waits_wvalid();
    logic [1:0] resp;
    bfm0.wr_aw_late_w(.addr(33'h0000_5000), .len(1), .size(6), .id(6'd7),
                      .resp(resp));
    expect_resp(resp, 2'b00, "aw_waits_wvalid");
    sb.record_write(33'h0000_5000, 1, 6, 2'b01, 0);
    do_read_check(0, 33'h0000_5000, 1, 6, 2'b01, 6'd7);
  endtask

  task automatic test_early_b();
    do_write_record(0, 33'h0000_6000, 3, 6, 2'b01, 6'd8, 4'hF, 1, 0, 0, 0, 30, 2'b00);
    check(bfm0.last_b_before_wlast === 1'b1,
          "AWCOBUF=1: B did not return before WLAST");
    repeat (20) @(posedge clk);
    do_read_check(0, 33'h0000_6000, 3, 6, 2'b01, 6'd8);

    // v0.2a 板级定稿：B 时机=AWCACHE[0] bit0 规律，0000（bit0=0）非早返
    //（B 在 WLAST/数据提交后返回）——预期由早返改为非早返
    do_write_record(0, 33'h0000_6800, 3, 6, 2'b01, 6'd9, 4'h0, 0, 0, 0, 0, 30, 2'b00);
    check(bfm0.last_b_before_wlast === 1'b0,
          "AWCACHE=0000: B returned before WLAST (expect non-early per v0.2a)");
    repeat (20) @(posedge clk);
    do_read_check(0, 33'h0000_6800, 3, 6, 2'b01, 6'd9);
  endtask

  task automatic test_wlast_err();
    logic [1:0] resp;
    // WLAST on the first beat of a 4-beat burst and WLAST never asserted.
    bfm0.wr_txn(.addr(33'h00D0_0000), .len(3), .size(6), .burst(2'b01),
                .id(6'd24), .cache(4'hF), .wlast_mode(1), .resp(resp));
    expect_resp(resp, 2'b10, "early WLAST");
    bfm0.wr_txn(.addr(33'h00D0_1000), .len(1), .size(6), .burst(2'b01),
                .id(6'd25), .cache(4'hF), .wlast_mode(2), .resp(resp));
    expect_resp(resp, 2'b10, "missing WLAST");
    check(ctrl_err === 1'b1, "WLAST violation did not latch CTRL_ERR");
    // v0.2a 定稿：cache=0000 非早返，B 在 WLAST 违例检测后随响应返回
    //（resp=SLVERR），不再有"早 B 先行"相位
    bfm0.wr_txn(.addr(33'h00D0_2000), .len(3), .size(6), .burst(2'b01),
                .id(6'd50), .cache(4'h0), .cobuf(1'b0), .wlast_mode(2),
                .pause_after_first(30), .resp(resp));
    expect_resp(resp, 2'b10, "missing WLAST (non-early-B path)");
    // wlast_mode=2 时 WLAST 永不到来（wlast_sent 恒 0），B 先行标志平凡为 1——
    // 此 check 仅确认 0000 路径 B 确已随 SLVERR 返回，无"早/非早"语义可判
    check(bfm0.last_b_before_wlast === 1'b1,
          "wlast_err: B never returned (flag trivially 1 without WLAST)");
  endtask

  task automatic test_cobuf_strict();
    // AWCOBUF is only defined with AWCACHE=1111; with strict checking a
    // cobuf assertion on a middle cache value must be reported on CTRL_ERR.
    do_write_record(0, 33'h00D1_0000, 1, 6, 2'b01, 6'd26, 4'b0011,
                    1, 0, 0, 0, 0, 2'b00);
    check(ctrl_err === 1'b1, "AWCOBUF strict violation did not latch CTRL_ERR");
    do_read_check(0, 33'h00D1_0000, 1, 6, 2'b01, 6'd27);
  endtask

  task automatic test_allstrb_early();
    logic [1:0] resp;
    // v0.2a 定稿：cache=0000 非早返，坏 WSTRB beat 在 B 前已被检测 →
    // resp=SLVERR + CTRL_ERR latched（旧语义"早 B 保 OKAY"随 0000 非早返移除）
    bfm0.wr_txn(.addr(33'h00D2_0000), .len(3), .size(6), .burst(2'b01),
                .id(6'd28), .cache(4'h0), .cobuf(1'b0), .allstrb(1'b1),
                .strb_mode(4), .pause_after_first(30), .resp(resp));
    expect_resp(resp, 2'b10, "allstrb error on non-early-B path");
    check(bfm0.last_b_before_wlast === 1'b0,
          "allstrb_early: B returned before WLAST on 0000 (expect non-early)");
    check(ctrl_err === 1'b1, "allstrb error did not latch CTRL_ERR");
  endtask

  task automatic test_wr_errors();
    do_write_record(0, 33'h0000_0FF0, 4, 4, 2'b01, 6'd10, 4'hF, 0, 0, 0, 0, 0, 2'b10);
    do_write_record(0, 33'h0000_7000, 64, 6, 2'b01, 6'd11, 4'hF, 0, 0, 0, 0, 0, 2'b10);
    do_write_record(0, 33'h0000_8000, 0, 7, 2'b01, 6'd12, 4'hF, 0, 0, 0, 0, 0, 2'b10);
    do_write_record(0, 33'h0000_9000, 1, 6, 2'b00, 6'd13, 4'hF, 0, 0, 0, 0, 0, 2'b10);
  endtask

  task automatic test_allstrb();
    do_write_record(0, 33'h0000_A000, 15, 6, 2'b01, 6'd14, 4'hF, 0, 1, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h0000_A000, 15, 6, 2'b01, 6'd14);
    do_write_record(0, 33'h0000_C000, 16, 6, 2'b01, 6'd15, 4'hF, 0, 1, 0, 0, 0, 2'b10);
    do_write_record(0, 33'h0000_D000, 1, 6, 2'b01, 6'd16, 4'hF, 0, 1, 2, 0, 0, 2'b10);
  endtask

  task automatic test_reads();
    // single and incrementing
    do_write_record(0, 33'h0001_0000, 0, 6, 2'b01, 6'd20, 4'hF, 0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h0001_0000, 0, 6, 2'b01, 6'd20);
    do_write_record(0, 33'h0001_1000, 3, 6, 2'b01, 6'd21, 4'hF, 0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h0001_1000, 3, 6, 2'b01, 6'd21);

    // narrow read: fill 64 bytes, then read 4-byte beats
    do_write_record(0, 33'h0001_2000, 3, 6, 2'b01, 6'd22, 4'hF, 0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h0001_2000, 3, 2, 2'b01, 6'd23);

    // wrap read: fill a 64-byte aligned block, then wrap
    do_write_record(0, 33'h0001_3000, 3, 4, 2'b01, 6'd24, 4'hF, 0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h0001_3020, 3, 4, 2'b10, 6'd25);

    // error responses still return the complete burst
    do_read_check(0, 33'h0000_0FF0, 4, 4, 2'b01, 6'd26, 2'b10);
    do_read_check(0, 33'(dut.MEM_BYTES - 4), 1, 2, 2'b01, 6'd27, 2'b11);
  endtask

  task automatic test_dual_port();
    logic [1:0] r0, r1;
    fork
      bfm0.wr_txn(.addr(33'h0002_0000), .len(1), .size(6), .burst(2'b01),
                  .id(6'd30), .cache(4'hF), .resp(r0));
      bfm1.wr_txn(.addr(33'h0003_0000), .len(1), .size(6), .burst(2'b01),
                  .id(6'd31), .cache(4'hF), .resp(r1));
    join
    expect_resp(r0, 2'b00, "dual_port P0 write");
    expect_resp(r1, 2'b00, "dual_port P1 write");
    sb.record_write(33'h0002_0000, 1, 6, 2'b01, 0);
    sb.record_write(33'h0003_0000, 1, 6, 2'b01, 0);
    // cross-port reads
    do_read_check(1, 33'h0002_0000, 1, 6, 2'b01, 6'd32);
    do_read_check(0, 33'h0003_0000, 1, 6, 2'b01, 6'd33);
  endtask

  task automatic test_dual_multi();
    logic [1:0] r0, r1;
    // Two multi-beat writes in flight so both write contexts stay incomplete.
    fork
      bfm0.wr_txn(.addr(33'h00E0_0000), .len(15), .size(6), .burst(2'b01),
                  .id(6'd34), .cache(4'hF), .resp(r0));
      bfm1.wr_txn(.addr(33'h00E1_0000), .len(15), .size(6), .burst(2'b01),
                  .id(6'd35), .cache(4'hF), .resp(r1));
    join
    expect_resp(r0, 2'b00, "dual_multi P0 write");
    expect_resp(r1, 2'b00, "dual_multi P1 write");
    sb.record_write(33'h00E0_0000, 15, 6, 2'b01, 0);
    sb.record_write(33'h00E1_0000, 15, 6, 2'b01, 0);
    do_read_check(0, 33'h00E0_0000, 15, 6, 2'b01, 6'd34);
    do_read_check(1, 33'h00E1_0000, 15, 6, 2'b01, 6'd35);
  endtask

  task automatic test_dir_arb();
    logic [1:0]   rw0, rw1;
    logic [511:0] d0[], d1[];
    logic [1:0]   p0[], p1[];
    bit           both0, both1, done;
    both0 = 1'b0; both1 = 1'b0; done = 1'b0;
    do_write_record(0, 33'h00F0_0000, 1, 6, 2'b01, 6'd36, 4'hF,
                    0, 0, 0, 0, 0, 2'b00);
    do_write_record(1, 33'h00F1_0000, 1, 6, 2'b01, 6'd37, 4'hF,
                    0, 0, 0, 0, 0, 2'b00);
    fork
      begin : dir_mon
        while (!done) begin
          @(posedge clk);
          if (dut.aw_req[0] && dut.ar_req[0]) both0 = 1'b1;
          if (dut.aw_req[1] && dut.ar_req[1]) both1 = 1'b1;
        end
      end
      begin : dir_traffic
        fork
          bfm0.wr_txn(.addr(33'h00F0_1000), .len(1), .size(6), .burst(2'b01),
                      .id(6'd38), .cache(4'hF), .resp(rw0));
          bfm0.rd_txn(.addr(33'h00F0_0000), .len(1), .size(6), .burst(2'b01),
                      .id(6'd39), .data(d0), .resp(p0));
          bfm1.wr_txn(.addr(33'h00F1_1000), .len(1), .size(6), .burst(2'b01),
                      .id(6'd40), .cache(4'hF), .resp(rw1));
          bfm1.rd_txn(.addr(33'h00F1_0000), .len(1), .size(6), .burst(2'b01),
                      .id(6'd41), .data(d1), .resp(p1));
        join
        done = 1'b1;
      end
    join
    expect_resp(rw0, 2'b00, "dir_arb P0 write");
    expect_resp(rw1, 2'b00, "dir_arb P1 write");
    sb.record_write(33'h00F0_1000, 1, 6, 2'b01, 0);
    sb.record_write(33'h00F1_1000, 1, 6, 2'b01, 0);
    check(both0 && both1, "dir_arb: AW and AR never contended on a port");
    sb.check_read(33'h00F0_0000, 1, 6, 2'b01, 6'd39, d0, p0, 2'b00);
    sb.check_read(33'h00F1_0000, 1, 6, 2'b01, 6'd41, d1, p1, 2'b00);
  endtask

  task automatic test_latency();
    do_write_record(0, 33'h0004_0000, 0, 6, 2'b01, 6'd40, 4'hF, 0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h0004_0000, 0, 6, 2'b01, 6'd40);
    if ((bfm0.last_rd_lat < RD_LAT_MIN) || (bfm0.last_rd_lat > RD_LAT_MAX + 4)) begin
      fail($sformatf("read latency %0d outside [%0d,%0d]",
                     bfm0.last_rd_lat, RD_LAT_MIN, RD_LAT_MAX + 4));
    end else begin
      $display("[TB] read latency = %0d ctrl_clk", bfm0.last_rd_lat);
    end
  endtask

  task automatic test_ostd_wr();
    int  accepted;
    bit  blocked;
    logic [32:0] a;
    bfm0.wr_ostd_probe(WRITE_OSTD_DEPTH, 33'h0006_0000, accepted, blocked);
    check(accepted == WRITE_OSTD_DEPTH + 1,
          $sformatf("ostd_wr accepted=%0d exp=%0d", accepted,
                    WRITE_OSTD_DEPTH + 1));
    check(blocked, "ostd_wr: AW was not blocked at outstanding limit");
    for (int i = 0; i <= WRITE_OSTD_DEPTH; i++) begin
      a = 33'h0006_0000 + 33'(i * 64);
      sb.record_write(a, 0, 6, 2'b01, 0);
    end
    for (int i = 0; i <= WRITE_OSTD_DEPTH; i++) begin
      a = 33'h0006_0000 + 33'(i * 64);
      do_read_check(0, a, 0, 6, 2'b01, 6'(60 + i));
    end
  endtask

  task automatic test_ostd_rd();
    int  accepted;
    bit  blocked;
    logic [32:0] a;
    logic [1:0] resp;
    for (int i = 0; i <= READ_OSTD_DEPTH; i++) begin
      a = 33'h0007_0000 + 33'(i * 64);
      bfm0.wr_txn(.addr(a), .len(0), .size(6), .burst(2'b01),
                  .id(6'(70 + i)), .cache(4'hF), .resp(resp));
      expect_resp(resp, 2'b00, $sformatf("ostd_rd preload %0d", i));
      sb.record_write(a, 0, 6, 2'b01, 0);
    end
    bfm0.rd_ostd_probe(READ_OSTD_DEPTH, 33'h0007_0000, accepted, blocked);
    check(accepted == READ_OSTD_DEPTH + 1,
          $sformatf("ostd_rd accepted=%0d exp=%0d", accepted,
                    READ_OSTD_DEPTH + 1));
    check(blocked, "ostd_rd: AR was not blocked at outstanding limit");
    for (int i = 0; i <= READ_OSTD_DEPTH; i++) begin
      a = 33'h0007_0000 + 33'(i * 64);
      do_read_check(0, a, 0, 6, 2'b01, 6'(80 + i));
    end
  endtask

  task automatic test_bvalid_modes();
    do_write_record(0, 33'h0008_0000, 3, 6, 2'b01, 6'd90, 4'b0011,
                    0, 0, 0, 0, 30, 2'b00);
    if (OTHER_AWCACHE_POLICY == 0) begin
      check(bfm0.last_b_before_wlast === 1'b0,
            "DATA_DONE policy returned B before WLAST");
    end else begin
      check(bfm0.last_b_before_wlast === 1'b1,
            $sformatf("policy %0d did not return B before WLAST",
                      OTHER_AWCACHE_POLICY));
    end
    repeat (20) @(posedge clk);
    do_read_check(0, 33'h0008_0000, 3, 6, 2'b01, 6'd91);
  endtask

  task automatic test_lat_fixed();
    int lat0, lat1;
    do_write_record(0, 33'h0009_0000, 0, 6, 2'b01, 6'd92, 4'hF,
                    0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h0009_0000, 0, 6, 2'b01, 6'd92);
    lat0 = bfm0.last_rd_lat;
    do_read_check(0, 33'h0009_0000, 0, 6, 2'b01, 6'd93);
    lat1 = bfm0.last_rd_lat;
    check(lat0 == lat1,
          $sformatf("fixed latency not reproducible: %0d vs %0d", lat0, lat1));
    check((lat0 >= RD_LAT_MIN) && (lat0 <= RD_LAT_MIN + 6),
          $sformatf("fixed latency %0d outside [%0d,%0d]",
                    lat0, RD_LAT_MIN, RD_LAT_MIN + 6));
    $display("[TB] fixed read latency = %0d ctrl_clk", lat0);
  endtask

  task automatic test_cfg_sel();
    cfg_sel = 1'b1;
    repeat (3) @(posedge clk);
    check(cfg_done === 1'b0, "CFG_DONE still high when CFG_SEL=1");
    cfg_sel = 1'b0;
    wait_cfg_done();
    check(cfg_done === 1'b1, "CFG_DONE did not recover after CFG_SEL=0");
  endtask

  task automatic test_port_reset();
    logic [1:0] resp;
    axi0.ARSTN = 1'b0;
    repeat (5) @(posedge clk);
    bfm1.wr_txn(.addr(33'h0005_0000), .len(1), .size(6), .burst(2'b01),
                .id(6'd50), .cache(4'hF), .resp(resp));
    expect_resp(resp, 2'b00, "port1 transaction during port0 reset");
    sb.record_write(33'h0005_0000, 1, 6, 2'b01, 0);
    axi0.ARSTN = 1'b1;
    repeat (5) @(posedge clk);
    bfm0.wr_txn(.addr(33'h0005_1000), .len(1), .size(6), .burst(2'b01),
                .id(6'd51), .cache(4'hF), .resp(resp));
    expect_resp(resp, 2'b00, "port0 transaction after reset");
    sb.record_write(33'h0005_1000, 1, 6, 2'b01, 0);
    do_read_check(1, 33'h0005_1000, 1, 6, 2'b01, 6'd52);
  endtask

  task automatic test_cmdq_full();
    int accepted;
    bit blocked;
    logic [32:0] a;
    bfm0.cmdq_probe(20, 33'h0010_0000, accepted, blocked);
    check(blocked, "cmdq_full: AWREADY never dropped");
    check(accepted >= B_FIFO_DEPTH + 1,
          $sformatf("cmdq_full: only %0d commands accepted", accepted));
    $display("[TB] cmdq_full accepted=%0d", accepted);
    for (int i = 0; i < accepted; i++) begin
      a = 33'h0010_0000 + 33'(i * 64);
      sb.record_write(a, 0, 6, 2'b01, 0);
    end
    for (int i = 0; i < accepted; i++) begin
      a = 33'h0010_0000 + 33'(i * 64);
      do_read_check(0, a, 0, 6, 2'b01, 6'(i));
    end
  endtask

  task automatic test_wdataq_full();
    int accepted;
    bit blocked;
    bfm0.wdataq_probe(WRITE_DATA_QUEUE_DEPTH, 33'h0011_0000, accepted, blocked);
    check(blocked, "wdataq_full: WREADY never dropped");
    check(accepted == WRITE_DATA_QUEUE_DEPTH + 1,
          $sformatf("wdataq_full: accepted=%0d exp=%0d", accepted,
                    WRITE_DATA_QUEUE_DEPTH + 1));
    sb.record_write(33'h0011_0000, WRITE_DATA_QUEUE_DEPTH, 6, 2'b01, 0);
    do_read_check(0, 33'h0011_0000, WRITE_DATA_QUEUE_DEPTH, 6, 2'b01, 6'd60);
  endtask

  task automatic test_rdataq_full();
    int beats;
    bit blocked;
    bfm0.rdataq_probe(READ_DATA_QUEUE_DEPTH, CMD_QUEUE_DEPTH,
                      33'h0012_0000, beats, blocked);
    check(blocked, "rdataq_full: ARREADY never dropped");
    check(beats == READ_DATA_QUEUE_DEPTH + CMD_QUEUE_DEPTH + 3,
          $sformatf("rdataq_full: beats=%0d exp=%0d", beats,
                    READ_DATA_QUEUE_DEPTH + CMD_QUEUE_DEPTH + 3));
  endtask

  task automatic test_arb_fairness();
    logic [1:0] r0, r1;
    int g0, g1, both;
    bit done;
    logic [32:0] a0, a1;
    g0 = 0; g1 = 0; both = 0; done = 1'b0;
    fork
      begin : mon
        while (!done) begin
          @(posedge clk);
          if (dut.aw_req[0] && dut.aw_req[1]) both++;
          if (dut.aw_grant[0]) g0++;
          if (dut.aw_grant[1]) g1++;
        end
      end
      begin : traffic
        for (int i = 0; i < 8; i++) begin
          a0 = 33'h0020_0000 + 33'(i * 64);
          a1 = 33'h0021_0000 + 33'(i * 64);
          fork
            bfm0.wr_txn(.addr(a0), .len(0), .size(6), .burst(2'b01),
                        .id(6'(i)), .cache(4'hF), .resp(r0));
            bfm1.wr_txn(.addr(a1), .len(0), .size(6), .burst(2'b01),
                        .id(6'(i + 32)), .cache(4'hF), .resp(r1));
          join
          expect_resp(r0, 2'b00, $sformatf("arb P0 write %0d", i));
          expect_resp(r1, 2'b00, $sformatf("arb P1 write %0d", i));
          sb.record_write(a0, 0, 6, 2'b01, 0);
          sb.record_write(a1, 0, 6, 2'b01, 0);
        end
        done = 1'b1;
      end
    join
    check(both > 0, "arb_fairness: ports never contended");
    check((g0 > 0) && (g1 > 0),
          $sformatf("arb_fairness: starvation g0=%0d g1=%0d", g0, g1));
    $display("[TB] arb contention=%0d grants p0=%0d p1=%0d", both, g0, g1);
    do_read_check(0, 33'h0020_0000, 0, 6, 2'b01, 6'd55);
    do_read_check(1, 33'h0021_0000, 0, 6, 2'b01, 6'd56);
  endtask

  task automatic test_contend_multi();
    logic [32:0] a0[4], a1[4];
    logic [5:0]  ids0[4], ids1[4];
    int          d0[$], d1[$];
    bit          ok0, ok1;
    for (int k = 0; k < 4; k++) begin
      a0[k]   = 33'h00B0_0000 + 33'(k * 64);
      ids0[k] = 6'(k);
      a1[k]   = 33'h00B1_0000 + 33'(k * 64);
      ids1[k] = 6'(16 + k);
    end
    // Several queued commands per port keep both requests asserted across
    // the arbitration hold window.
    fork
      bfm0.wr_multi_probe(4, a0, ids0, d0, ok0);
      bfm1.wr_multi_probe(4, a1, ids1, d1, ok1);
    join
    check(ok0 && ok1, "contend_multi: probe reported errors");
    check((d0.size() == 4) && (d1.size() == 4),
          $sformatf("contend_multi: responses p0=%0d p1=%0d", d0.size(), d1.size()));
    for (int k = 0; k < 4; k++) begin
      sb.record_write(a0[k], 0, 6, 2'b01, 0);
      sb.record_write(a1[k], 0, 6, 2'b01, 0);
    end
    $display("[TB] contend_multi B order p0=%p p1=%p", d0, d1);
    do_read_check(0, a0[0], 0, 6, 2'b01, 6'd44);
    do_read_check(1, a1[3], 0, 6, 2'b01, 6'd45);
  endtask

  task automatic test_err_inject();
    byte unsigned b;
    dut.u_mem.bd_write(33'h0030_0000, 8'hA5);
    do_write_record(0, 33'h0030_0000, 0, 6, 2'b01, 6'd44, 4'hF,
                    0, 0, 0, 0, 0, 2'b10);
    dut.u_mem.bd_read(33'h0030_0000, b);
    check(b == 8'hA5, "err_inject: SLVERR write modified storage");
    do_read_check(0, 33'h0030_0000, 0, 6, 2'b01, 6'd45, 2'b10);
    do_read_check(0, 33'h0030_0000, 3, 6, 2'b01, 6'd46, 2'b10);
    do_write_record(0, 33'h0030_0100, 2, 5, 2'b01, 6'd47, 4'hF,
                    0, 0, 0, 0, 0, 2'b10);
    // Port 1 injection covers the second address-channel error path.
    do_write_record(1, 33'h0030_0200, 0, 6, 2'b01, 6'd48, 4'hF,
                    0, 0, 0, 0, 0, 2'b10);
    do_read_check(1, 33'h0030_0200, 0, 6, 2'b01, 6'd49, 2'b10);
  endtask

  task automatic test_ooo_same_id();
    logic [32:0] a[4];
    int          lens[4];
    int          done_lens[$];
    bit          ok;
    lens[0] = 3; lens[1] = 0; lens[2] = 2; lens[3] = 1;
    for (int k = 0; k < 4; k++) begin
      a[k] = 33'h0060_0000 + 33'(k * 32'h1000);
      do_write_record(0, a[k], lens[k], 6, 2'b01, 6'(k), 4'hF, 0, 0, 0, 0, 0,
                      2'b00);
    end
    bfm0.rd_same_id_probe(6'd5, a, lens, done_lens, ok);
    check(ok, "ooo_same_id: probe reported errors");
    check(done_lens.size() == 4,
          $sformatf("ooo_same_id: %0d bursts completed", done_lens.size()));
    for (int k = 0; k < done_lens.size(); k++) begin
      check(done_lens[k] == lens[k] + 1,
            $sformatf("ooo_same_id: burst %0d length=%0d exp=%0d",
                      k, done_lens[k], lens[k] + 1));
    end
  endtask

  task automatic test_ooo_diff_id();
    logic [32:0] a[8];
    int          lens[8];
    logic [5:0]  ids[8];
    int          done_order[$];
    int          beats[64];
    bit          il, inv;
    for (int k = 0; k < 8; k++) begin
      a[k]    = 33'h0070_0000 + 33'(k * 32'h1000);
      lens[k] = 0;
      ids[k]  = 6'(k);
      do_write_record(0, a[k], 0, 6, 2'b01, 6'(k), 4'hF, 0, 0, 0, 0, 0, 2'b00);
    end
    bfm0.rd_multi_probe(8, a, lens, ids, done_order, beats, il, inv);
    check(done_order.size() == 8,
          $sformatf("ooo_diff_id: %0d/8 reads completed", done_order.size()));
    check(inv, "ooo_diff_id: different-ID reads never completed out of order");
    for (int k = 0; k < 8; k++) begin
      check(beats[k] == 1, $sformatf("ooo_diff_id: ID %0d beats=%0d", k, beats[k]));
    end
    $display("[TB] ooo_diff_id completion order: %p", done_order);
  endtask

  task automatic test_ooo_interleave();
    logic [32:0] a[4];
    int          lens[4];
    logic [5:0]  ids[4];
    int          done_order[$];
    int          beats[64];
    bit          il, inv;
    for (int k = 0; k < 4; k++) begin
      a[k]    = 33'h0080_0000 + 33'(k * 32'h1000);
      lens[k] = 7;
      ids[k]  = 6'(16 + k);
      do_write_record(0, a[k], 7, 6, 2'b01, 6'(16 + k), 4'hF, 0, 0, 0, 0, 0,
                      2'b00);
    end
    bfm0.rd_multi_probe(4, a, lens, ids, done_order, beats, il, inv);
    check(done_order.size() == 4,
          $sformatf("ooo_interleave: %0d/4 reads completed", done_order.size()));
    check(il, "ooo_interleave: no R beat interleave observed");
    for (int k = 0; k < 4; k++) begin
      check(beats[16 + k] == 8,
            $sformatf("ooo_interleave: ID %0d beats=%0d", 16 + k, beats[16 + k]));
    end
  endtask

  task automatic test_ooo_b();
    logic [32:0] a[6];
    logic [5:0]  ids[6];
    int          done_order[$];
    bit          ok;
    for (int k = 0; k < 6; k++) begin
      a[k]   = 33'h0090_0000 + 33'(k * 64);
      ids[k] = 6'(32 + k);
    end
    bfm0.wr_multi_probe(6, a, ids, done_order, ok);
    check(ok, "ooo_b: probe reported errors");
    check(done_order.size() == 6,
          $sformatf("ooo_b: %0d/6 responses", done_order.size()));
    for (int i = 0; i < done_order.size(); i++) begin
      for (int j = i + 1; j < done_order.size(); j++) begin
        check(done_order[i] != done_order[j], "ooo_b: duplicate BID");
      end
      check(done_order[i] >= 32 && done_order[i] < 38,
            $sformatf("ooo_b: unexpected BID %0d", done_order[i]));
      sb.record_write(a[done_order[i] - 32], 0, 6, 2'b01, 0);
    end
    $display("[TB] ooo_b completion order: %p", done_order);
    for (int k = 0; k < 6; k++) begin
      do_read_check(0, a[k], 0, 6, 2'b01, 6'(40 + k));
    end
  endtask

  task automatic test_ooo_b_same_id();
    logic [32:0] a[4];
    logic [5:0]  ids[4];
    int          done_order[$];
    bit          ok;
    for (int k = 0; k < 4; k++) begin
      a[k]   = 33'h00A0_0000 + 33'(k * 64);
      ids[k] = 6'd21;
    end
    bfm0.wr_multi_probe(4, a, ids, done_order, ok);
    check(ok, "ooo_b_same_id: probe reported errors");
    check(done_order.size() == 4,
          $sformatf("ooo_b_same_id: %0d/4 responses", done_order.size()));
    for (int i = 0; i < done_order.size(); i++) begin
      check(done_order[i] == 21,
            $sformatf("ooo_b_same_id: unexpected BID %0d", done_order[i]));
      sb.record_write(a[i], 0, 6, 2'b01, 0);
    end
    for (int k = 0; k < 4; k++) begin
      do_read_check(0, a[k], 0, 6, 2'b01, 6'(50 + k));
    end
  endtask

  task automatic test_field_decode();
    ddr_addr_fields_t exp_f;
    logic [32:0]      a;
    a = 33'h0123_4040;
    do_write_record(0, a, 0, 6, 2'b01, 6'd60, 4'hF, 0, 0, 0, 0, 0, 2'b00);
    check(dbg_fields_addr === a,
          $sformatf("field_decode: latched addr=0x%0h exp=0x%0h",
                    dbg_fields_addr, a));
    exp_f = ddr_model_pkg::decode_addr_fields(a, ADDR_CS_BIT_POS);
    check(dbg_fields === 33'(exp_f),
          $sformatf("field_decode: fields=%h exp=%h", dbg_fields, 33'(exp_f)));

    a = 33'h0A5A_5A5A;
    exp_f = ddr_model_pkg::decode_addr_fields(a, ADDR_CS_BIT_POS);
    check(exp_f.cs === a[27], "field_decode: wrong CS bit");
    check(exp_f.row === a[26:12], "field_decode: wrong ROW field");
    check(exp_f.bank === a[11:9], "field_decode: wrong BANK field");
    check(exp_f.column === a[8:2], "field_decode: wrong COLUMN field");
    check(exp_f.datapath === a[1:0], "field_decode: wrong DATAPATH field");
    check(ddr_model_pkg::decode_addr_fields(33'h0040_0000, 27).cs === 1'b0,
          "field_decode: CS should be 0 below bit 27");
  endtask

  task automatic test_addr_hole();
    byte unsigned b;
    logic [1:0]   resp;
    // start address inside the hole
    do_write_record(0, 33'h0030_0040, 0, 6, 2'b01, 6'd61, 4'hF,
                    0, 0, 0, 0, 0, 2'b11);
    dut.u_mem.bd_write(33'h0030_0040, 8'h00);
    do_read_check(0, 33'h0030_0040, 0, 6, 2'b01, 6'd62, 2'b11);
    dut.u_mem.bd_read(33'h0030_0040, b);
    check(b == 8'h00, "addr_hole: DECERR write reached storage");
    // a burst that starts below the hole but crosses into it
    do_write_record(0, 33'h0030_0000, 1, 6, 2'b01, 6'd63, 4'hF,
                    0, 0, 0, 0, 0, 2'b11);
    // addresses immediately outside the hole still work
    do_write_record(0, 33'h002F_FFC0, 0, 6, 2'b01, 6'd64, 4'hF,
                    0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h002F_FFC0, 0, 6, 2'b01, 6'd65);
    do_write_record(0, 33'h0030_0100, 0, 6, 2'b01, 6'd66, 4'hF,
                    0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h0030_0100, 0, 6, 2'b01, 6'd67);
  endtask

  task automatic test_addr_alias();
    logic [511:0] d_hole[], d_lin[];
    logic [1:0]   r_hole[], r_lin[];
    logic [511:0] exp;
    logic [1:0]   resp;
    bfm0.wr_txn(.addr(33'h0030_0040), .len(0), .size(6), .burst(2'b01),
                .id(6'd68), .cache(4'hF), .strb_mode(0), .resp(resp));
    expect_resp(resp, 2'b00, "addr_alias write");
    bfm0.rd_txn(.addr(33'h0030_0040), .len(0), .size(6), .burst(2'b01),
                .id(6'd69), .data(d_hole), .resp(r_hole));
    bfm0.rd_txn(.addr(33'h0000_0000), .len(0), .size(6), .burst(2'b01),
                .id(6'd70), .data(d_lin), .resp(r_lin));
    exp = tb_beat_data(33'h0030_0040);
    expect_resp(r_hole[0], 2'b00, "addr_alias hole read");
    expect_resp(r_lin[0], 2'b00, "addr_alias linear read");
    check(d_hole[0] === exp, "addr_alias: hole read data mismatch");
    check(d_lin[0] === exp, "addr_alias: linear alias data mismatch");
  endtask

  task automatic test_addr_alias_cross();
    logic [511:0] d[];
    logic [1:0]   r[];
    // A 64B-aligned burst starts below the hole and crosses into it; ALIAS
    // remaps the start so both beats land in linear storage.
    do_write_record(0, 33'h0030_0000, 1, 6, 2'b01, 6'd74, 4'hF,
                    0, 0, 0, 0, 0, 2'b00);
    bfm0.rd_txn(.addr(33'h0030_0000), .len(1), .size(6), .burst(2'b01),
                .id(6'd75), .data(d), .resp(r));
    expect_resp(r[0], 2'b00, "addr_alias_cross read");
    check(d[0] === tb_beat_data(33'h0030_0000),
          "addr_alias_cross: beat0 data mismatch");
    check(d[1] === tb_beat_data(33'h0030_0040),
          "addr_alias_cross: beat1 data mismatch");
  endtask

  task automatic test_port_reset_mid();
    logic [1:0] resp;
    // abort a write after the first data beat
    fork : abort_wr
      bfm0.wr_txn(.addr(33'h00B0_0000), .len(7), .size(6), .burst(2'b01),
                  .id(6'd71), .cache(4'hF), .pause_after_first(40),
                  .resp(resp));
    join_none
    repeat (12) @(posedge clk);
    axi0.ARSTN = 1'b0;
    repeat (6) @(posedge clk);
    disable fork;
    axi0.ARSTN   = 1'b1;
    axi0.AWVALID = 1'b0;
    axi0.WVALID  = 1'b0;
    axi0.ARVALID = 1'b0;
    axi0.BREADY  = 1'b0;
    axi0.RREADY  = 1'b0;
    repeat (10) @(posedge clk);
    check(dut.g_sync.u_port0.wr_ostd == 0,
          $sformatf("port_reset_mid: wr_ostd=%0d after reset",
                    dut.g_sync.u_port0.wr_ostd));
    // abort a read while it is outstanding
    fork : abort_rd
      logic [511:0] dummy_d[];
      logic [1:0]   dummy_r[];
      bfm0.rd_txn(.addr(33'h00B0_1000), .len(7), .size(6), .burst(2'b01),
                  .id(6'd72), .data(dummy_d), .resp(dummy_r));
    join_none
    repeat (4) @(posedge clk);
    axi0.ARSTN = 1'b0;
    repeat (6) @(posedge clk);
    disable fork;
    axi0.ARSTN   = 1'b1;
    axi0.AWVALID = 1'b0;
    axi0.WVALID  = 1'b0;
    axi0.ARVALID = 1'b0;
    axi0.BREADY  = 1'b0;
    axi0.RREADY  = 1'b0;
    repeat (10) @(posedge clk);
    check(dut.g_sync.u_port0.rd_ostd == 0,
          $sformatf("port_reset_mid: rd_ostd=%0d after reset",
                    dut.g_sync.u_port0.rd_ostd));
    do_write_record(0, 33'h00B0_2000, 1, 6, 2'b01, 6'd73, 4'hF,
                    0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h00B0_2000, 1, 6, 2'b01, 6'd74);
    do_write_record(1, 33'h00B0_3000, 0, 6, 2'b01, 6'd75, 4'hF,
                    0, 0, 0, 0, 0, 2'b00);
    do_read_check(1, 33'h00B0_3000, 0, 6, 2'b01, 6'd76);
  endtask

  task automatic test_r_gap();
    gap_mon_en = 1'b1;
    gap_last   = -1;
    gap_min    = 1_000_000;
    do_read_check(0, 33'h00C0_0000, 7, 6, 2'b01, 6'd77);
    gap_mon_en = 1'b0;
    check(gap_min >= R_BEAT_INTERVAL,
          $sformatf("r_gap: min gap=%0d exp>=%0d", gap_min, R_BEAT_INTERVAL));
    $display("[TB] r_gap min=%0d (interval=%0d)", gap_min, R_BEAT_INTERVAL);
  endtask

  task automatic test_w_gap();
    wgap_mon_en = 1'b1;
    wgap_last   = -1;
    wgap_min    = 1_000_000;
    do_write_record(0, 33'h00C1_0000, 7, 6, 2'b01, 6'd78, 4'hF,
                    0, 0, 0, 0, 0, 2'b00);
    wgap_mon_en = 1'b0;
    check(wgap_min >= W_ACCEPT_INTERVAL,
          $sformatf("w_gap: min gap=%0d exp>=%0d", wgap_min, W_ACCEPT_INTERVAL));
    $display("[TB] w_gap min=%0d (interval=%0d)", wgap_min, W_ACCEPT_INTERVAL);
    do_read_check(0, 33'h00C1_0000, 7, 6, 2'b01, 6'd79);
  endtask

  task automatic test_cfg_clear_mem();
    logic [511:0] data[];
    logic [1:0]   resp[];
    int           nz;
    do_write_record(0, 33'h00A0_0000, 1, 6, 2'b01, 6'd80, 4'hF,
                    0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h00A0_0000, 1, 6, 2'b01, 6'd81);

    cfg_reset = 1'b1;
    repeat (6) @(posedge clk);
    check(cfg_done === 1'b0, "cfg_clear_mem: CFG_DONE high during CFG_RESET");
    cfg_reset = 1'b0;
    wait_cfg_done();
    repeat (5) @(posedge clk);

    bfm0.rd_txn(.addr(33'h00A0_0000), .len(1), .size(6), .burst(2'b01),
                .id(6'd82), .data(data), .resp(resp));
    nz = 0;
    for (int i = 0; i < data.size(); i++) begin
      if (data[i] !== '0) nz++;
      if (resp[i] !== 2'b00) nz++;
    end
    check(nz == 0, "cfg_clear_mem: storage not cleared (or response error)");
    // the port must accept fresh traffic after the config reset
    do_write_record(0, 33'h00A0_1000, 0, 6, 2'b01, 6'd83, 4'hF,
                    0, 0, 0, 0, 0, 2'b00);
    do_read_check(0, 33'h00A0_1000, 0, 6, 2'b01, 6'd84);
  endtask

  task automatic test_random_stress();
    logic [32:0] ha[$];
    int          hl[$];
    int          hs[$];
    int          len, size, off, idx, strb_mode;
    logic [5:0]  rid;
    logic [32:0] a;
    logic [1:0]  resp;
    bit          wf;
    longint unsigned span;
    for (int i = 0; i < 40; i++) begin
      if ((ha.size() == 0) || (($urandom % 100) < 55)) begin
        case ($urandom % 4)
          0: len = 0;
          1: len = 1;
          2: len = 3;
          default: len = 7;
        endcase
        size = 3 + ($urandom % 4);
        strb_mode = $urandom % 4;
        rid = 6'($urandom);
        wf = (($urandom % 4) == 0);
        span = longint'(len + 1) * (64'(1) << size);
        off = ($urandom % 56) * 64;
        if ((longint'(off) + span) > 4096) off = 0;
        a = 33'h0040_0000 + 33'(i % 16) * 33'h1000 + 33'(off);
        bfm0.wr_txn(.addr(a), .len(len), .size(size), .burst(2'b01),
                    .id(rid), .cache(4'hF), .strb_mode(strb_mode),
                    .wfirst(wf), .pause_after_first($urandom % 6),
                    .resp(resp));
        expect_resp(resp, 2'b00, $sformatf("random write %0d", i));
        sb.record_write(a, len, size, 2'b01, strb_mode);
        ha.push_back(a);
        hl.push_back(len);
        hs.push_back(size);
      end else begin
        idx = $urandom % ha.size();
        a = ha[idx];
        len = hl[idx];
        size = hs[idx];
        do_read_check(0, a, len, size, 2'b01, 6'(i));
      end
    end
    $display("[TB] random_stress: %0d writes tracked", ha.size());
  endtask

  // ------------------------------------------------------------------
  // main
  // ------------------------------------------------------------------
  initial begin
    string test;
    longint unsigned t_cfg_start;
    int total;

    if (!$value$plusargs("TEST=%s", test)) test = "smoke";
    err_count = 0;

    axi0.ARSTN = 1'b0;
    axi1.ARSTN = 1'b0;
    cfg_reset  = 1'b1;
    cfg_start  = 1'b0;
    cfg_sel    = 1'b0;

    $display("[TB] test=%s init_cycles=%0d mem_bytes=%0d",
             test, TB_INIT_CYCLES, dut.MEM_BYTES);
    $display("[TB] params wostd=%0d rostd=%0d lat_mode=%0d policy=%0d init_block=%0d init_resp=%0d",
             WRITE_OSTD_DEPTH, READ_OSTD_DEPTH, LATENCY_MODE,
             OTHER_AWCACHE_POLICY, INIT_AXI_BLOCK, INIT_AXI_RESP);

    repeat (10) @(posedge clk);
    check_reset_outputs();
    check(cfg_done === 1'b0, "CFG_DONE high during reset");
    check(ctrl_init_done === 1'b0, "CTRL_INIT_DONE high during reset");

    cfg_reset = 1'b0;
    repeat (2) @(posedge clk);
    axi0.ARSTN = 1'b1;
    axi1.ARSTN = 1'b1;
    repeat (2) @(posedge clk);
    // Abort a partially completed init, then restart from IDLE.
    cfg_start = 1'b1;
    repeat (20) @(posedge clk);
    cfg_start = 1'b0;
    repeat (4) @(posedge clk);
    check(cfg_done === 1'b0, "CFG_DONE after aborted init");
    cfg_start = 1'b1;
    t_cfg_start = tb_cyc;
    if ((test == "init_block") || (test == "init_slverr")) begin
      test_init_early(test, t_cfg_start);
    end
    wait_cfg_done();

    if ((tb_cyc - t_cfg_start) < (TB_INIT_CYCLES - 3)) begin
      fail($sformatf("CFG_DONE too early: %0d cycles (init=%0d)",
                     tb_cyc - t_cfg_start, TB_INIT_CYCLES));
    end
    $display("[TB] cfg done after %0d cycles", tb_cyc - t_cfg_start);

    case (test)
      "smoke", "smoke_reset": test_smoke_reset();
      "smoke_cfg":            test_smoke_cfg();
      "wr_single":            test_wr_single();
      "wr_incr":              test_wr_incr();
      "wr_wstrb":             test_wr_wstrb();
      "wr_w_before_aw":       test_wr_w_before_aw();
      "aw_waits_wvalid":      test_aw_waits_wvalid();
      "early_b":              test_early_b();
      "wlast_err":            test_wlast_err();
      "cobuf_strict":         test_cobuf_strict();
      "allstrb_early":        test_allstrb_early();
      "wr_errors":            test_wr_errors();
      "allstrb":              test_allstrb();
      "reads":                test_reads();
      "dual_port":            test_dual_port();
      "dual_multi":           test_dual_multi();
      "dir_arb":              test_dir_arb();
      "latency":              test_latency();
      "lat_equal":            test_latency();
      "lat_fixed":            test_lat_fixed();
      "ostd_wr":              test_ostd_wr();
      "ostd_rd":              test_ostd_rd();
      "bvalid_modes":         test_bvalid_modes();
      "init_block":           test_init_late(test);
      "init_slverr":          test_init_late(test);
      "cfg_sel":              test_cfg_sel();
      "port_reset":           test_port_reset();
      "cmdq_full":            test_cmdq_full();
      "wdataq_full":          test_wdataq_full();
      "rdataq_full":          test_rdataq_full();
      "arb_fairness":         test_arb_fairness();
      "contend_multi":        test_contend_multi();
      "err_inject":           test_err_inject();
      "ooo_same_id":          test_ooo_same_id();
      "ooo_diff_id":          test_ooo_diff_id();
      "ooo_interleave":       test_ooo_interleave();
      "ooo_b":                test_ooo_b();
      "ooo_b_same_id":        test_ooo_b_same_id();
      "random_stress":        test_random_stress();
      "field_decode":         test_field_decode();
      "addr_hole":            test_addr_hole();
      "addr_alias":           test_addr_alias();
      "addr_alias_cross":     test_addr_alias_cross();
      "port_reset_mid":       test_port_reset_mid();
      "r_gap":                test_r_gap();
      "w_gap":                test_w_gap();
      "cfg_clear_mem":        test_cfg_clear_mem();
      default: begin
        fail($sformatf("unknown TEST=%s", test));
      end
    endcase

    repeat (10) @(posedge clk);
    sb.report();
    $display("[COV] wr=%0.1f%% rd=%0.1f%%",
             bfm0.cov_wr.get_coverage(), bfm0.cov_rd.get_coverage());
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
    #5ms;
    $fatal(1, "global watchdog timeout");
  end

endmodule
