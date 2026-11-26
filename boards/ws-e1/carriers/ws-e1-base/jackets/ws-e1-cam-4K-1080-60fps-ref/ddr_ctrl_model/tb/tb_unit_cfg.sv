// Unit tests for the CFG_RESET/CFG_START/CFG_SEL controller.
module tb_unit_cfg;
  localparam int INIT_CYCLES = 5;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic cfg_reset, cfg_start, cfg_sel, cfg_done, init_busy;
  int   errs = 0;

  (* keep_hierarchy = "yes" *)
  cfg_ctrl_fsm #(.INIT_CYCLES(INIT_CYCLES)) dut (
    .clk(clk), .cfg_reset(cfg_reset), .cfg_start(cfg_start),
    .cfg_sel(cfg_sel), .cfg_done(cfg_done), .init_busy(init_busy)
  );

  task automatic chk(input bit cond, input string msg);
    if (!cond) begin
      errs++;
      $error("[CFG] %s", msg);
    end
  endtask

  task automatic expect_state(input int exp, input string msg);
    chk(int'(dut.state) == exp,
        $sformatf("%s: state=%0d exp=%0d", msg, int'(dut.state), exp));
  endtask

  task automatic wait_done();
    int tmo;
    tmo = 0;
    while (!cfg_done && (tmo < 100)) begin
      @(posedge clk);
      tmo++;
    end
    chk(cfg_done, "CFG_DONE timeout");
  endtask

  initial begin
    cfg_reset = 1'b1;
    cfg_start = 1'b0;
    cfg_sel   = 1'b0;
    repeat (3) @(posedge clk);
    expect_state(0, "reset idle");
    chk(!cfg_done && init_busy, "reset outputs");
    cfg_reset = 1'b0;

    // CFG_SEL masks the FSM even when CFG_START is high.
    cfg_sel = 1'b1;
    cfg_start = 1'b1;
    repeat (2) @(posedge clk);
    expect_state(0, "sel blocks start");
    chk(!cfg_done, "cfg_done while CFG_SEL asserted");

    // INIT -> IDLE when CFG_START drops before the initialization finishes.
    cfg_sel = 1'b0;
    repeat (2) @(posedge clk);
    expect_state(1, "init entered");
    cfg_start = 1'b0;
    @(posedge clk);
    #1;
    expect_state(0, "start abort returns to idle");
    chk(init_busy && !cfg_done, "abort outputs");

    // Normal INIT -> DONE.
    cfg_start = 1'b1;
    @(posedge clk);
    wait_done();
    expect_state(2, "done reached");
    chk(!init_busy, "init_busy in done");

    // Dropping CFG_START in DONE returns the FSM to IDLE.
    cfg_start = 1'b0;
    @(posedge clk);
    #1;
    expect_state(0, "done drop returns to idle");
    chk(!cfg_done, "cfg_done after drop");

    // Illegal state encoding is recovered by the default branch.
    force dut.state = 2'b11;
    @(posedge clk);
    release dut.state;
    @(posedge clk);
    #1;
    expect_state(0, "illegal state recovered");
    @(posedge clk);
    cfg_start = 1'b1;
    wait_done();
    cfg_reset = 1'b1;
    @(posedge clk);
    #1;
    expect_state(0, "reset from done");
    chk(!cfg_done, "cfg_done during reset");

    if (errs == 0) begin
      $display("TEST all PASS");
      $finish;
    end else begin
      $display("TEST all FAIL errors=%0d", errs);
      $fatal(1, "cfg unit test failed");
    end
  end
endmodule
