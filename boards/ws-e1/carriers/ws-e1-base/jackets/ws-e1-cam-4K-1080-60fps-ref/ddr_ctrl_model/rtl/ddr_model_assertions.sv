// First batch of protocol assertions (PLAN P2/P3/P4).
// Port-level checks shared by both AXI targets; bound through tb_top.
module ddr_model_assertions (
  input logic clk,
  input logic rstn0, rstn1,
  input logic awvalid0, awready0,
  input logic wvalid0,  wready0,
  input logic wlast0,
  input logic bvalid0,  bready0,
  input logic arvalid0, arready0,
  input logic rvalid0,  rready0, rlast0,
  input logic awvalid1, awready1,
  input logic wvalid1,  wready1,
  input logic wlast1,
  input logic bvalid1,  bready1,
  input logic arvalid1, arready1,
  input logic rvalid1,  rready1, rlast1,
  input logic cfg_reset, cfg_start, cfg_sel, cfg_done,
  input logic arb_req0, arb_req1, arb_grant0, arb_grant1,
  input int   ARB_GRANT_INTERVAL = 2,
  input logic arb_enable = 1'b1
);

  // READY may only be asserted together with the matching VALID.
  a_awready_needs_valid0: assert property (
    @(posedge clk) disable iff (!rstn0) awready0 |-> awvalid0);
  a_awready_needs_valid1: assert property (
    @(posedge clk) disable iff (!rstn1) awready1 |-> awvalid1);
  a_arready_needs_valid0: assert property (
    @(posedge clk) disable iff (!rstn0) arready0 |-> arvalid0);
  a_arready_needs_valid1: assert property (
    @(posedge clk) disable iff (!rstn1) arready1 |-> arvalid1);

  // VALID must remain asserted until the handshake (AXI4 handshake rule).
  a_aw_hold0: assert property (
    @(posedge clk) disable iff (!rstn0) (awvalid0 && !awready0) |=> awvalid0);
  a_aw_hold1: assert property (
    @(posedge clk) disable iff (!rstn1) (awvalid1 && !awready1) |=> awvalid1);
  a_w_hold0: assert property (
    @(posedge clk) disable iff (!rstn0) (wvalid0 && !wready0) |=> wvalid0);
  a_w_hold1: assert property (
    @(posedge clk) disable iff (!rstn1) (wvalid1 && !wready1) |=> wvalid1);
  a_ar_hold0: assert property (
    @(posedge clk) disable iff (!rstn0) (arvalid0 && !arready0) |=> arvalid0);
  a_ar_hold1: assert property (
    @(posedge clk) disable iff (!rstn1) (arvalid1 && !arready1) |=> arvalid1);

  // Slave-side VALID must also remain stable until READY.
  a_b_hold0: assert property (
    @(posedge clk) disable iff (!rstn0) (bvalid0 && !bready0) |=> bvalid0);
  a_b_hold1: assert property (
    @(posedge clk) disable iff (!rstn1) (bvalid1 && !bready1) |=> bvalid1);
  a_r_hold0: assert property (
    @(posedge clk) disable iff (!rstn0) (rvalid0 && !rready0) |=> rvalid0);
  a_r_hold1: assert property (
    @(posedge clk) disable iff (!rstn1) (rvalid1 && !rready1) |=> rvalid1);

  // LLAST can only qualify a valid beat.
  a_wlast_needs_wvalid0: assert property (
    @(posedge clk) disable iff (!rstn0) wlast0 |-> wvalid0);
  a_wlast_needs_wvalid1: assert property (
    @(posedge clk) disable iff (!rstn1) wlast1 |-> wvalid1);
  a_rlast_needs_rvalid0: assert property (
    @(posedge clk) disable iff (!rstn0) rlast0 |-> rvalid0);
  a_rlast_needs_rvalid1: assert property (
    @(posedge clk) disable iff (!rstn1) rlast1 |-> rvalid1);

  // CFG rules: Figure 7 / [UG].
  a_cfg_done_requires_start: assert property (
    @(posedge clk) disable iff (cfg_reset) cfg_done |-> cfg_start);
  a_cfg_reset_clears_done: assert property (
    @(posedge clk) cfg_reset |-> !cfg_done);
  a_cfg_done_sticky: assert property (
    @(posedge clk) disable iff (cfg_reset)
      (cfg_done && cfg_start && !cfg_sel) |=> (cfg_sel || cfg_done));
  a_cfg_reset_min_width: assert property (
    @(posedge clk) $rose(cfg_reset) |-> cfg_reset[*5]);

  // Responses must not precede the command handshake that created them.
  int aw_cnt0, b_cnt0, ar_cnt0, rlast_cnt0;
  int aw_cnt1, b_cnt1, ar_cnt1, rlast_cnt1;

  always_ff @(posedge clk) begin
    if (!rstn0) begin
      aw_cnt0 <= 0; b_cnt0 <= 0; ar_cnt0 <= 0; rlast_cnt0 <= 0;
    end else begin
      if (awvalid0 && awready0) aw_cnt0 <= aw_cnt0 + 1;
      if (bvalid0 && bready0)   b_cnt0  <= b_cnt0 + 1;
      if (arvalid0 && arready0) ar_cnt0 <= ar_cnt0 + 1;
      if (rvalid0 && rready0 && rlast0) rlast_cnt0 <= rlast_cnt0 + 1;
    end
  end

  always_ff @(posedge clk) begin
    if (!rstn1) begin
      aw_cnt1 <= 0; b_cnt1 <= 0; ar_cnt1 <= 0; rlast_cnt1 <= 0;
    end else begin
      if (awvalid1 && awready1) aw_cnt1 <= aw_cnt1 + 1;
      if (bvalid1 && bready1)   b_cnt1  <= b_cnt1 + 1;
      if (arvalid1 && arready1) ar_cnt1 <= ar_cnt1 + 1;
      if (rvalid1 && rready1 && rlast1) rlast_cnt1 <= rlast_cnt1 + 1;
    end
  end

  a_b_not_before_aw0: assert property (
    @(posedge clk) disable iff (!rstn0) bvalid0 |-> (b_cnt0 < aw_cnt0));
  a_b_not_before_aw1: assert property (
    @(posedge clk) disable iff (!rstn1) bvalid1 |-> (b_cnt1 < aw_cnt1));
  a_r_not_before_ar0: assert property (
    @(posedge clk) disable iff (!rstn0) rvalid0 |-> (rlast_cnt0 < ar_cnt0));
  a_r_not_before_ar1: assert property (
    @(posedge clk) disable iff (!rstn1) rvalid1 |-> (rlast_cnt1 < ar_cnt1));

  // Shared command arbiter: at most one grant per cycle and the configured
  // spacing is honoured while both ports contend.
  a_arb_onehot: assert property (
    @(posedge clk) disable iff (cfg_reset)
      arb_enable |-> ($countones({arb_grant0, arb_grant1}) <= 1));

  logic [31:0] arb_gap;
  always_ff @(posedge clk) begin
    if (cfg_reset) arb_gap <= '0;
    else if (arb_grant0 || arb_grant1)
      arb_gap <= (arb_req0 && arb_req1) ? 32'(ARB_GRANT_INTERVAL-1) : '0;
    else if (arb_gap != 0) arb_gap <= arb_gap - 1;
  end

  // The spacing only applies while both ports contend; the quiet fast path
  // intentionally allows back-to-back grants once the other port goes idle.
  a_arb_grant_gap: assert property (
    @(posedge clk) disable iff (cfg_reset)
      (arb_enable && arb_req0 && arb_req1 && (arb_grant0 || arb_grant1))
      |-> (arb_gap == 0));

endmodule
