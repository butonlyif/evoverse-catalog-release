// TJ series DDR hard-controller AXI-side behavior model.
// Spec: SPEC-DDR-AXI-MODEL-v0.2
//
// CDC_ENABLE=0: ACLK_x is tied to ctrl_clk (by the testbench) and the port
// shells run synchronously. CDC_ENABLE=1: each AXI port runs in its ACLK_x
// domain and all payloads cross through dual-clock gray FIFOs.
module ddr_axi_model_top #(
  parameter int  DATA_WIDTH = 32,
  parameter int  AXI_DATA_WIDTH = 512,
  parameter int  AXI_ADDR_WIDTH = 33,
  parameter int  AXI_ID_WIDTH = 6,
  parameter int  MEM_DENSITY_GBIT = 4,
  parameter bit  GBIT_BINARY = 1'b1,
  parameter int  PHYSICAL_RANK = 1,
  parameter int  NUM_AXI_TARGETS = 2,
  parameter bit  SUPPORT_WRAP_BURST = 1'b1,
  parameter bit  SUPPORT_NARROW = 1'b1,
  parameter bit  SUPPORT_FIXED_BURST = 1'b0,
  parameter bit  SUPPORT_AWALLSTRB = 1'b1,
  parameter bit  SUPPORT_EXCLUSIVE = 1'b0,

  parameter int  RANK_MAP_MODE = 1,      // 0=SINGLE_RANK 1=CS_STRIDE 2=CS_BIT
  parameter int  CS_BIT_POS = -1,
  parameter int  ADDR_MAP_MODE = 0,      // 0=LINEAR 1=FIELD_DECODE_DEBUG
  parameter int  ADDR_CS_BIT_POS = 27,   // debug field decode only
  parameter int  ADDR_HOLE_POLICY = 0,   // 0=DECERR 1=ALIAS
  parameter longint unsigned ADDR_HOLE_START = 0,
  parameter longint unsigned ADDR_HOLE_END   = 0, // exclusive; no hole if <= start
  parameter int  MEM_INIT_MODE = 0,      // 0=ZERO 1=RANDOM 2=PATTERN
  parameter logic [31:0] MEM_INIT_SEED = 32'h1,

  parameter int  CMD_QUEUE_DEPTH = 8,
  parameter int  WRITE_DATA_QUEUE_DEPTH = 16,
  parameter int  READ_DATA_QUEUE_DEPTH = 16,
  parameter int  READ_OSTD_DEPTH = 8,
  parameter int  WRITE_OSTD_DEPTH = 8,
  parameter int  ARB_GRANT_INTERVAL = 2,
  parameter bit  ARB_QUIET_FAST_PATH = 1'b1,
  parameter bit  OUT_OF_ORDER_ENABLE = 1'b0,
  parameter bit  R_INTERLEAVE_ENABLE = 1'b0,
  parameter int  B_FIFO_DEPTH = 8,
  parameter bit  CDC_ENABLE = 1'b0,

  parameter int  SYNC_LATENCY = 2,
  parameter int  ARB_LATENCY = 0,
  // correlation Phase 2 回填（2026-10-22，板级 LEN=31 低负载 ×8 折 ctrl，见
  // proj/docs/correlation-plan.md §9）：原默认值留档于下方 _ENG localparam。
  // READ：板 24/61 ACLK → 192/488 ctrl；仿真观测偏移 +1/−4 已扣
  //（第一轮 188/483 实测 189/479）
  parameter int  READ_LATENCY_MIN = 191,
  parameter int  READ_LATENCY_MAX = 492,
  parameter int  R_BEAT_INTERVAL = 1,
  // correlation Phase 5 回填（2026-10-23，板级 9 块 B 时机矩阵，plan §9）：
  // B 时机由 AxCACHE[0]（Bufferable）单独决定——bit0=1 早返（板 T_AW_B
  // 4-5 ACLK×8=32-40 ctrl，模型 CDC 结构≈4 → delay=28 对齐 min，§7 门禁
  // ±2）；bit0=0 B 在写数据提交后。ENG 原值 2 留档于下方 localparam
  parameter int  BVALID_CMD_QUEUE_DELAY = 28,
  // WRITE_RESP_LATENCY（T_AW_B 数据提交路径）：保持 ENG 值——bit0=0 编码
  // B 时机由 WRITE_DATA_TO_B_LATENCY 支配（板级 WA 因 W-first 锚点几何
  // AW_acc≈WLAST_acc 与模型 WA 不可直接对比，标定口径用 WL，Phase 2 同）
  parameter int  WRITE_RESP_LATENCY_MIN = 8,
  parameter int  WRITE_RESP_LATENCY_MAX = 24,
  // WRITE_DATA_TO_B：板 WL(LEN=31) min 56 ACLK → 448 ctrl；仿真观测 −3 已扣
  //（第一轮 444 实测 441）
  parameter int  WRITE_DATA_TO_B_LATENCY = 451,
  // Phase 5：BVALID_CMD_QUEUE_DELAY 移至上方=28（ENG 原值 2）
  parameter int  BVALID_PHY_ISSUE_DELAY = 2,
  parameter int  W_ACCEPT_INTERVAL = 1,
  parameter int  LATENCY_MODE = 0,       // 0=UNIFORM 1=FIXED
  parameter int  LATENCY_SEED = 1,
  parameter int  ERR_INJECT_RATE = 0,    // percent of commands forced to SLVERR

  parameter int  BVALID_TIMING_MODE = 0, // 0=MANUAL_STRICT 1=MANUAL_PLUS_DEFAULT
  parameter int  OTHER_AWCACHE_POLICY = 0, // 0=DATA_DONE 1=CMD_QUEUE 2=PHY_ISSUE
  parameter bit  AWCOBUF_STRICT = 1'b1,

  parameter int  INIT_CYCLES = 1000,
  parameter bit  INIT_AXI_BLOCK = 1'b1,
  parameter int  INIT_AXI_RESP = 0,      // 0=BACKPRESSURE 1=SLVERR
  parameter bit  CFG_RESET_CLEAR_MEM = 1'b0,
  parameter bit  ENABLE_CTRL_STATUS = 1'b0
) (
  input  logic        ctrl_clk,

  // AXI target 0
  input  logic        ACLK_0,
  input  logic        ARSTN_0,
  input  logic [32:0] AWADDR_0,
  input  logic [1:0]  AWBURST_0,
  input  logic [5:0]  AWID_0,
  input  logic [7:0]  AWLEN_0,
  output logic        AWREADY_0,
  input  logic [2:0]  AWSIZE_0,
  input  logic        AWVALID_0,
  input  logic        AWLOCK_0,
  input  logic        AWAPCMD_0,
  input  logic [3:0]  AWQOS_0,
  input  logic [3:0]  AWCACHE_0,
  input  logic        AWALLSTRB_0,
  input  logic        AWCOBUF_0,
  input  logic [511:0] WDATA_0,
  input  logic        WLAST_0,
  output logic        WREADY_0,
  input  logic [63:0] WSTRB_0,
  input  logic        WVALID_0,
  output logic [5:0]  BID_0,
  input  logic        BREADY_0,
  output logic [1:0]  BRESP_0,
  output logic        BVALID_0,
  input  logic [32:0] ARADDR_0,
  input  logic [1:0]  ARBURST_0,
  input  logic [5:0]  ARID_0,
  input  logic [7:0]  ARLEN_0,
  output logic        ARREADY_0,
  input  logic [2:0]  ARSIZE_0,
  input  logic        ARVALID_0,
  input  logic        ARLOCK_0,
  input  logic        ARAPCMD_0,
  input  logic [3:0]  ARQOS_0,
  output logic [511:0] RDATA_0,
  output logic [5:0]  RID_0,
  output logic        RLAST_0,
  input  logic        RREADY_0,
  output logic [1:0]  RRESP_0,
  output logic        RVALID_0,

  // AXI target 1
  input  logic        ACLK_1,
  input  logic        ARSTN_1,
  input  logic [32:0] AWADDR_1,
  input  logic [1:0]  AWBURST_1,
  input  logic [5:0]  AWID_1,
  input  logic [7:0]  AWLEN_1,
  output logic        AWREADY_1,
  input  logic [2:0]  AWSIZE_1,
  input  logic        AWVALID_1,
  input  logic        AWLOCK_1,
  input  logic        AWAPCMD_1,
  input  logic [3:0]  AWQOS_1,
  input  logic [3:0]  AWCACHE_1,
  input  logic        AWALLSTRB_1,
  input  logic        AWCOBUF_1,
  input  logic [511:0] WDATA_1,
  input  logic        WLAST_1,
  output logic        WREADY_1,
  input  logic [63:0] WSTRB_1,
  input  logic        WVALID_1,
  output logic [5:0]  BID_1,
  input  logic        BREADY_1,
  output logic [1:0]  BRESP_1,
  output logic        BVALID_1,
  input  logic [32:0] ARADDR_1,
  input  logic [1:0]  ARBURST_1,
  input  logic [5:0]  ARID_1,
  input  logic [7:0]  ARLEN_1,
  output logic        ARREADY_1,
  input  logic [2:0]  ARSIZE_1,
  input  logic        ARVALID_1,
  input  logic        ARLOCK_1,
  input  logic        ARAPCMD_1,
  input  logic [3:0]  ARQOS_1,
  output logic [511:0] RDATA_1,
  output logic [5:0]  RID_1,
  output logic        RLAST_1,
  input  logic        RREADY_1,
  output logic [1:0]  RRESP_1,
  output logic        RVALID_1,

  // configuration controller
  input  logic        CFG_RESET,
  input  logic        CFG_START,
  input  logic        CFG_SEL,
  output logic        CFG_DONE,

  // abstract controller status [MODEL]
  output logic        CTRL_INIT_DONE,
  output logic        CTRL_READY,
  output logic        CTRL_ERR,
  output logic        CTRL_BUSY,

  // debug-only decoded fields of the last accepted command
  output logic [32:0] DBG_FIELDS,
  output logic [32:0] DBG_FIELDS_ADDR
);
  import ddr_model_pkg::*;

  // correlation Phase 2 前的引擎默认值留档（correlation-plan §7-1，模型 spec §6.3）
  localparam int READ_LATENCY_MIN_ENG = 10;
  localparam int READ_LATENCY_MAX_ENG = 30;
  localparam int WRITE_RESP_LATENCY_MIN_ENG = 8;
  localparam int WRITE_RESP_LATENCY_MAX_ENG = 24;
  localparam int WRITE_DATA_TO_B_LATENCY_ENG = 4;
  // correlation Phase 5 前的引擎默认值留档（plan §7-1）
  localparam int BVALID_CMD_QUEUE_DELAY_ENG = 2;

  localparam int NUM_CHANNELS = DATA_WIDTH / 16;
  localparam longint unsigned MEM_BYTES_PER_CHANNEL =
      calc_mem_bytes_per_channel(MEM_DENSITY_GBIT, GBIT_BINARY);
  localparam longint unsigned RANK_STRIDE_BYTES =
      MEM_BYTES_PER_CHANNEL * NUM_CHANNELS;
  localparam longint unsigned MEM_BYTES = RANK_STRIDE_BYTES * PHYSICAL_RANK;
  localparam int CS_BIT_EFF = (CS_BIT_POS >= 0) ? CS_BIT_POS
                                                 : $clog2(RANK_STRIDE_BYTES);
  localparam int CMD_W = $bits(ddr_cmd_t);

  function automatic ddr_cmd_t post_check(input ddr_cmd_t c);
    bit hole_en;
    hole_en = (ADDR_MAP_MODE == 1) && (ADDR_HOLE_END > ADDR_HOLE_START);
    return apply_addr_hole(c, hole_en, ADDR_HOLE_START, ADDR_HOLE_END,
                           ADDR_HOLE_POLICY, MEM_BYTES);
  endfunction

  // ------------------------------------------------------------------
  // configuration / reset
  // ------------------------------------------------------------------
  logic cfg_done;
  logic init_busy;
  logic init_block;
  logic init_slverr;
  logic core_rst_n;

  cfg_ctrl_fsm #(.INIT_CYCLES(INIT_CYCLES)) u_cfg (
    .clk        (ctrl_clk),
    .cfg_reset  (CFG_RESET),
    .cfg_start  (CFG_START),
    .cfg_sel    (CFG_SEL),
    .cfg_done   (cfg_done),
    .init_busy  (init_busy)
  );

  assign CFG_DONE = cfg_done;
  assign core_rst_n = !CFG_RESET;
  assign init_block = INIT_AXI_BLOCK && init_busy && (INIT_AXI_RESP == 0);
  assign init_slverr = init_busy && (INIT_AXI_RESP == 1);

  // ------------------------------------------------------------------
  // cycle counter (ctrl_clk)
  // ------------------------------------------------------------------
  logic [63:0] cycle_now;
  always_ff @(posedge ctrl_clk) begin
    if (CFG_RESET) cycle_now <= '0;
    else           cycle_now <= cycle_now + 1'b1;
  end

  // ------------------------------------------------------------------
  // shell/core interconnect
  // ------------------------------------------------------------------
  logic [1:0]  aw_req, ar_req;
  logic [1:0]  aw_grant, ar_grant;
  logic [1:0]  w_pop, w_empty, b_push, b_full, r_push, r_full;
  logic [640:0] w_head_0, w_head_1;
  logic [31:0] w_count_0, w_count_1;
  logic [7:0]  b_in_0, b_in_1;
  logic [520:0] r_in_0, r_in_1;
  logic [31:0] wr_ostd_0, wr_ostd_1, rd_ostd_0, rd_ostd_1;
  logic [31:0] wr_cmd_count, rd_cmd_count;
  logic        cmd_space;

  logic wr_cmd_push, rd_cmd_push;
  logic [CMD_W-1:0] wr_cmd_din, rd_cmd_din;
  logic [CMD_W-1:0] wr_cmd_head, rd_cmd_head;
  logic wr_cmd_empty, rd_cmd_empty;
  logic wr_cmd_pop, rd_cmd_pop;

  ddr_cmd_t c_new;

  // ------------------------------------------------------------------
  // latency / error RNG (ctrl_clk, common to both front ends)
  // ------------------------------------------------------------------
  function automatic logic [31:0] xs32(input logic [31:0] s);
    logic [31:0] t;
    t = s;
    t = t ^ (t << 13);
    t = t ^ (t >> 17);
    t = t ^ (t << 5);
    return t;
  endfunction

  function automatic logic [63:0] pick_lat(input logic [31:0] r,
                                           input int mn, input int mx);
    if ((LATENCY_MODE == 1) || (mx <= mn)) return 64'(mn);
    return 64'(mn) + (64'(r) % 64'(mx - mn + 1));
  endfunction

  logic [31:0] rng;
  logic [31:0] rng_new;
  assign rng_new = xs32(rng);

  always_ff @(posedge ctrl_clk) begin
    if (CFG_RESET) rng <= 32'(LATENCY_SEED);
    else if (wr_cmd_push || rd_cmd_push) rng <= rng_new;
  end

  logic [31:0] err_rng;
  logic        err_inject;
  assign err_inject = (ERR_INJECT_RATE > 0) &&
                      ((err_rng % 32'd100) < 32'(ERR_INJECT_RATE));

  always_ff @(posedge ctrl_clk) begin
    if (CFG_RESET) err_rng <= 32'(LATENCY_SEED) ^ 32'h9E37_79B9;
    else if (wr_cmd_push || rd_cmd_push) err_rng <= xs32(err_rng);
  end

  // ------------------------------------------------------------------
  // front end
  // ------------------------------------------------------------------
  generate
    if (!CDC_ENABLE) begin : g_sync
      assign cmd_space = (wr_cmd_count + rd_cmd_count) < 32'(CMD_QUEUE_DEPTH);

      axi_port_shell #(
        .PORT(0),
        .WRITE_OSTD_DEPTH(WRITE_OSTD_DEPTH),
        .READ_OSTD_DEPTH(READ_OSTD_DEPTH),
        .WRITE_DATA_QUEUE_DEPTH(WRITE_DATA_QUEUE_DEPTH),
        .READ_DATA_QUEUE_DEPTH(READ_DATA_QUEUE_DEPTH),
        .B_FIFO_DEPTH(B_FIFO_DEPTH),
        .W_ACCEPT_INTERVAL(W_ACCEPT_INTERVAL)
      ) u_port0 (
        .clk(ctrl_clk), .arstn(ARSTN_0), .init_block(init_block),
        .cycle_now(cycle_now),
        .awvalid(AWVALID_0), .awaddr(AWADDR_0), .awburst(AWBURST_0),
        .awid(AWID_0), .awlen(AWLEN_0), .awsize(AWSIZE_0), .awlock(AWLOCK_0),
        .awapcmd(AWAPCMD_0), .awqos(AWQOS_0), .awcache(AWCACHE_0),
        .awallstrb(AWALLSTRB_0), .awcobuf(AWCOBUF_0),
        .awready(AWREADY_0), .aw_req(aw_req[0]), .aw_grant(aw_grant[0]),
        .wdata(WDATA_0), .wlast(WLAST_0), .wstrb(WSTRB_0), .wvalid(WVALID_0),
        .wready(WREADY_0),
        .bvalid(BVALID_0), .bid(BID_0), .bresp(BRESP_0), .bready(BREADY_0),
        .arvalid(ARVALID_0), .araddr(ARADDR_0), .arburst(ARBURST_0),
        .arid(ARID_0), .arlen(ARLEN_0), .arsize(ARSIZE_0), .arlock(ARLOCK_0),
        .arapcmd(ARAPCMD_0), .arqos(ARQOS_0),
        .arready(ARREADY_0), .ar_req(ar_req[0]), .ar_grant(ar_grant[0]),
        .rdata(RDATA_0), .rid(RID_0), .rlast(RLAST_0), .rresp(RRESP_0),
        .rvalid(RVALID_0), .rready(RREADY_0),
        .cmd_space(cmd_space),
        .w_pop(w_pop[0]), .w_head(w_head_0), .w_empty(w_empty[0]),
        .w_count(w_count_0),
        .b_push(b_push[0]), .b_in(b_in_0), .b_full(b_full[0]),
        .r_push(r_push[0]), .r_in(r_in_0), .r_full(r_full[0]),
        .wr_ostd(wr_ostd_0), .rd_ostd(rd_ostd_0)
      );

      axi_port_shell #(
        .PORT(1),
        .WRITE_OSTD_DEPTH(WRITE_OSTD_DEPTH),
        .READ_OSTD_DEPTH(READ_OSTD_DEPTH),
        .WRITE_DATA_QUEUE_DEPTH(WRITE_DATA_QUEUE_DEPTH),
        .READ_DATA_QUEUE_DEPTH(READ_DATA_QUEUE_DEPTH),
        .B_FIFO_DEPTH(B_FIFO_DEPTH),
        .W_ACCEPT_INTERVAL(W_ACCEPT_INTERVAL)
      ) u_port1 (
        .clk(ctrl_clk), .arstn(ARSTN_1), .init_block(init_block),
        .cycle_now(cycle_now),
        .awvalid(AWVALID_1), .awaddr(AWADDR_1), .awburst(AWBURST_1),
        .awid(AWID_1), .awlen(AWLEN_1), .awsize(AWSIZE_1), .awlock(AWLOCK_1),
        .awapcmd(AWAPCMD_1), .awqos(AWQOS_1), .awcache(AWCACHE_1),
        .awallstrb(AWALLSTRB_1), .awcobuf(AWCOBUF_1),
        .awready(AWREADY_1), .aw_req(aw_req[1]), .aw_grant(aw_grant[1]),
        .wdata(WDATA_1), .wlast(WLAST_1), .wstrb(WSTRB_1), .wvalid(WVALID_1),
        .wready(WREADY_1),
        .bvalid(BVALID_1), .bid(BID_1), .bresp(BRESP_1), .bready(BREADY_1),
        .arvalid(ARVALID_1), .araddr(ARADDR_1), .arburst(ARBURST_1),
        .arid(ARID_1), .arlen(ARLEN_1), .arsize(ARSIZE_1), .arlock(ARLOCK_1),
        .arapcmd(ARAPCMD_1), .arqos(ARQOS_1),
        .arready(ARREADY_1), .ar_req(ar_req[1]), .ar_grant(ar_grant[1]),
        .rdata(RDATA_1), .rid(RID_1), .rlast(RLAST_1), .rresp(RRESP_1),
        .rvalid(RVALID_1), .rready(RREADY_1),
        .cmd_space(cmd_space),
        .w_pop(w_pop[1]), .w_head(w_head_1), .w_empty(w_empty[1]),
        .w_count(w_count_1),
        .b_push(b_push[1]), .b_in(b_in_1), .b_full(b_full[1]),
        .r_push(r_push[1]), .r_in(r_in_1), .r_full(r_full[1]),
        .wr_ostd(wr_ostd_1), .rd_ostd(rd_ostd_1)
      );

      // --------------------------------------------------------------
      // command arbiter: one shared command accepted per cycle
      // --------------------------------------------------------------
      logic req0, req1;
      assign req0 = aw_req[0] | ar_req[0];
      assign req1 = aw_req[1] | ar_req[1];

      logic        last_port;
      logic        last_dir_0, last_dir_1;
      logic [31:0] arb_cool;
      logic        grant_any;
      logic        sel_port;
      logic        sel_dir;

      always_comb begin
        aw_grant = '0;
        ar_grant = '0;
        grant_any = 1'b0;
        sel_port  = last_port;
        sel_dir   = 1'b0;

        if (req0 || req1) begin
          if ((arb_cool != 0) && ((req0 && req1) || !ARB_QUIET_FAST_PATH)) begin
            // arbitration hold
          end else begin
            if (req0 && req1) sel_port = ~last_port;
            else if (req0)    sel_port = 1'b0;
            else              sel_port = 1'b1;

            if (sel_port == 0) begin
              if (aw_req[0] && ar_req[0]) sel_dir = ~last_dir_0;
              else if (aw_req[0])         sel_dir = 1'b0;
              else                        sel_dir = 1'b1;
              if (sel_dir == 0) aw_grant[0] = 1'b1;
              else              ar_grant[0] = 1'b1;
            end else begin
              if (aw_req[1] && ar_req[1]) sel_dir = ~last_dir_1;
              else if (aw_req[1])         sel_dir = 1'b0;
              else                        sel_dir = 1'b1;
              if (sel_dir == 0) aw_grant[1] = 1'b1;
              else              ar_grant[1] = 1'b1;
            end
            grant_any = 1'b1;
          end
        end
      end

      always_ff @(posedge ctrl_clk) begin
        if (CFG_RESET) begin
          last_port  <= 1'b0;
          last_dir_0 <= 1'b0;
          last_dir_1 <= 1'b0;
          arb_cool   <= '0;
        end else if (grant_any) begin
          last_port <= sel_port;
          if (sel_port == 0) last_dir_0 <= sel_dir;
          else               last_dir_1 <= sel_dir;
          if ((req0 && req1) || !ARB_QUIET_FAST_PATH)
            arb_cool <= 32'((ARB_GRANT_INTERVAL > 1) ? ARB_GRANT_INTERVAL-1 : 0);
          else
            arb_cool <= '0;
        end else if (arb_cool != 0) begin
          arb_cool <= arb_cool - 1'b1;
        end
      end

      // --------------------------------------------------------------
      // command capture
      // --------------------------------------------------------------
      logic aw_hs_0, aw_hs_1, ar_hs_0, ar_hs_1;
      assign aw_hs_0 = aw_req[0] && aw_grant[0];
      assign aw_hs_1 = aw_req[1] && aw_grant[1];
      assign ar_hs_0 = ar_req[0] && ar_grant[0];
      assign ar_hs_1 = ar_req[1] && ar_grant[1];

      always_comb begin
        wr_cmd_push = aw_hs_0 | aw_hs_1;
        rd_cmd_push = ar_hs_0 | ar_hs_1;
        wr_cmd_din  = '0;
        rd_cmd_din  = '0;
        c_new       = '0;

        if (aw_hs_0) begin
          c_new = make_cmd(1'b1, 2'd0, AWADDR_0, AWLEN_0, AWSIZE_0, AWBURST_0,
                           AWID_0, AWCACHE_0, AWCOBUF_0, AWALLSTRB_0, cycle_now);
          c_new = post_check(check_cmd(c_new, MEM_BYTES, SUPPORT_FIXED_BURST,
                            SUPPORT_WRAP_BURST, SUPPORT_AWALLSTRB,
                            SUPPORT_NARROW, 1'b1));
          c_new.lat = pick_lat(rng_new, WRITE_RESP_LATENCY_MIN,
                               WRITE_RESP_LATENCY_MAX);
          if (init_slverr || err_inject) c_new.resp = RESP_SLVERR;
          wr_cmd_din = c_new;
        end else if (aw_hs_1) begin
          c_new = make_cmd(1'b1, 2'd1, AWADDR_1, AWLEN_1, AWSIZE_1, AWBURST_1,
                           AWID_1, AWCACHE_1, AWCOBUF_1, AWALLSTRB_1, cycle_now);
          c_new = post_check(check_cmd(c_new, MEM_BYTES, SUPPORT_FIXED_BURST,
                            SUPPORT_WRAP_BURST, SUPPORT_AWALLSTRB,
                            SUPPORT_NARROW, 1'b1));
          c_new.lat = pick_lat(rng_new, WRITE_RESP_LATENCY_MIN,
                               WRITE_RESP_LATENCY_MAX);
          if (init_slverr || err_inject) c_new.resp = RESP_SLVERR;
          wr_cmd_din = c_new;
        end

        if (ar_hs_0) begin
          c_new = make_cmd(1'b0, 2'd0, ARADDR_0, ARLEN_0, ARSIZE_0, ARBURST_0,
                           ARID_0, 4'b0000, 1'b0, 1'b0, cycle_now);
          c_new = post_check(check_cmd(c_new, MEM_BYTES, SUPPORT_FIXED_BURST,
                            SUPPORT_WRAP_BURST, SUPPORT_AWALLSTRB,
                            SUPPORT_NARROW, 1'b1));
          c_new.lat = pick_lat(rng_new, READ_LATENCY_MIN, READ_LATENCY_MAX);
          if (init_slverr || err_inject) c_new.resp = RESP_SLVERR;
          rd_cmd_din = c_new;
        end else if (ar_hs_1) begin
          c_new = make_cmd(1'b0, 2'd1, ARADDR_1, ARLEN_1, ARSIZE_1, ARBURST_1,
                           ARID_1, 4'b0000, 1'b0, 1'b0, cycle_now);
          c_new = post_check(check_cmd(c_new, MEM_BYTES, SUPPORT_FIXED_BURST,
                            SUPPORT_WRAP_BURST, SUPPORT_AWALLSTRB,
                            SUPPORT_NARROW, 1'b1));
          c_new.lat = pick_lat(rng_new, READ_LATENCY_MIN, READ_LATENCY_MAX);
          if (init_slverr || err_inject) c_new.resp = RESP_SLVERR;
          rd_cmd_din = c_new;
        end
      end

    end else begin : g_cdc
      // --------------------------------------------------------------
      // asynchronous port shells
      // --------------------------------------------------------------
      logic        aw_cmd_empty_0, aw_cmd_empty_1, ar_cmd_empty_0, ar_cmd_empty_1;
      ddr_req_t    aw_cmd_head_0, aw_cmd_head_1, ar_cmd_head_0, ar_cmd_head_1;
      logic        aw_cmd_pop_0, aw_cmd_pop_1, ar_cmd_pop_0, ar_cmd_pop_1;

      axi_port_shell_cdc #(
        .PORT(0),
        .WRITE_OSTD_DEPTH(WRITE_OSTD_DEPTH),
        .READ_OSTD_DEPTH(READ_OSTD_DEPTH),
        .WRITE_DATA_QUEUE_DEPTH(WRITE_DATA_QUEUE_DEPTH),
        .READ_DATA_QUEUE_DEPTH(READ_DATA_QUEUE_DEPTH),
        .B_FIFO_DEPTH(B_FIFO_DEPTH),
        .W_ACCEPT_INTERVAL(W_ACCEPT_INTERVAL)
      ) u_port0 (
        .aclk(ACLK_0), .ctrl_clk(ctrl_clk), .arstn(ARSTN_0),
        .init_block(init_block), .cycle_now(cycle_now),
        .awvalid(AWVALID_0), .awaddr(AWADDR_0), .awburst(AWBURST_0),
        .awid(AWID_0), .awlen(AWLEN_0), .awsize(AWSIZE_0), .awlock(AWLOCK_0),
        .awapcmd(AWAPCMD_0), .awqos(AWQOS_0), .awcache(AWCACHE_0),
        .awallstrb(AWALLSTRB_0), .awcobuf(AWCOBUF_0), .awready(AWREADY_0),
        .wdata(WDATA_0), .wlast(WLAST_0), .wstrb(WSTRB_0), .wvalid(WVALID_0),
        .wready(WREADY_0),
        .bvalid(BVALID_0), .bid(BID_0), .bresp(BRESP_0), .bready(BREADY_0),
        .arvalid(ARVALID_0), .araddr(ARADDR_0), .arburst(ARBURST_0),
        .arid(ARID_0), .arlen(ARLEN_0), .arsize(ARSIZE_0), .arlock(ARLOCK_0),
        .arapcmd(ARAPCMD_0), .arqos(ARQOS_0), .arready(ARREADY_0),
        .rdata(RDATA_0), .rid(RID_0), .rlast(RLAST_0), .rresp(RRESP_0),
        .rvalid(RVALID_0), .rready(RREADY_0),
        .aw_cmd_pop(aw_cmd_pop_0), .aw_cmd_empty(aw_cmd_empty_0),
        .aw_cmd_head(aw_cmd_head_0),
        .ar_cmd_pop(ar_cmd_pop_0), .ar_cmd_empty(ar_cmd_empty_0),
        .ar_cmd_head(ar_cmd_head_0),
        .w_pop(w_pop[0]), .w_head(w_head_0), .w_empty(w_empty[0]),
        .w_count(w_count_0),
        .b_push(b_push[0]), .b_in(b_in_0), .b_full(b_full[0]),
        .r_push(r_push[0]), .r_in(r_in_0), .r_full(r_full[0]),
        .wr_ostd(wr_ostd_0), .rd_ostd(rd_ostd_0)
      );

      axi_port_shell_cdc #(
        .PORT(1),
        .WRITE_OSTD_DEPTH(WRITE_OSTD_DEPTH),
        .READ_OSTD_DEPTH(READ_OSTD_DEPTH),
        .WRITE_DATA_QUEUE_DEPTH(WRITE_DATA_QUEUE_DEPTH),
        .READ_DATA_QUEUE_DEPTH(READ_DATA_QUEUE_DEPTH),
        .B_FIFO_DEPTH(B_FIFO_DEPTH),
        .W_ACCEPT_INTERVAL(W_ACCEPT_INTERVAL)
      ) u_port1 (
        .aclk(ACLK_1), .ctrl_clk(ctrl_clk), .arstn(ARSTN_1),
        .init_block(init_block), .cycle_now(cycle_now),
        .awvalid(AWVALID_1), .awaddr(AWADDR_1), .awburst(AWBURST_1),
        .awid(AWID_1), .awlen(AWLEN_1), .awsize(AWSIZE_1), .awlock(AWLOCK_1),
        .awapcmd(AWAPCMD_1), .awqos(AWQOS_1), .awcache(AWCACHE_1),
        .awallstrb(AWALLSTRB_1), .awcobuf(AWCOBUF_1), .awready(AWREADY_1),
        .wdata(WDATA_1), .wlast(WLAST_1), .wstrb(WSTRB_1), .wvalid(WVALID_1),
        .wready(WREADY_1),
        .bvalid(BVALID_1), .bid(BID_1), .bresp(BRESP_1), .bready(BREADY_1),
        .arvalid(ARVALID_1), .araddr(ARADDR_1), .arburst(ARBURST_1),
        .arid(ARID_1), .arlen(ARLEN_1), .arsize(ARSIZE_1), .arlock(ARLOCK_1),
        .arapcmd(ARAPCMD_1), .arqos(ARQOS_1), .arready(ARREADY_1),
        .rdata(RDATA_1), .rid(RID_1), .rlast(RLAST_1), .rresp(RRESP_1),
        .rvalid(RVALID_1), .rready(RREADY_1),
        .aw_cmd_pop(aw_cmd_pop_1), .aw_cmd_empty(aw_cmd_empty_1),
        .aw_cmd_head(aw_cmd_head_1),
        .ar_cmd_pop(ar_cmd_pop_1), .ar_cmd_empty(ar_cmd_empty_1),
        .ar_cmd_head(ar_cmd_head_1),
        .w_pop(w_pop[1]), .w_head(w_head_1), .w_empty(w_empty[1]),
        .w_count(w_count_1),
        .b_push(b_push[1]), .b_in(b_in_1), .b_full(b_full[1]),
        .r_push(r_push[1]), .r_in(r_in_1), .r_full(r_full[1]),
        .wr_ostd(wr_ostd_1), .rd_ostd(rd_ostd_1)
      );

      // --------------------------------------------------------------
      // collect port command FIFOs into the shared command queues
      // --------------------------------------------------------------
      logic aw_last, ar_last;
      logic cmd_room_w, cmd_room_r;
      logic [CMD_W-1:0] wr_din_mux, rd_din_mux;

      assign cmd_room_w = (wr_cmd_count < 32'(CMD_QUEUE_DEPTH)) &&
                          ((wr_cmd_count + rd_cmd_count) < 32'(CMD_QUEUE_DEPTH));
      assign cmd_room_r = (rd_cmd_count < 32'(CMD_QUEUE_DEPTH)) &&
                          ((wr_cmd_count + rd_cmd_count + 32'(wr_cmd_push))
                           < 32'(CMD_QUEUE_DEPTH));

      always_comb begin
        aw_cmd_pop_0 = 1'b0;
        aw_cmd_pop_1 = 1'b0;
        ar_cmd_pop_0 = 1'b0;
        ar_cmd_pop_1 = 1'b0;
        wr_cmd_push  = 1'b0;
        rd_cmd_push  = 1'b0;
        wr_din_mux   = '0;
        rd_din_mux   = '0;

        if (cmd_room_w) begin
          if (!aw_cmd_empty_0 && (aw_cmd_empty_1 || aw_last)) begin
            aw_cmd_pop_0 = 1'b1;
            wr_cmd_push  = 1'b1;
            c_new = make_cmd(1'b1, 2'd0, aw_cmd_head_0.addr, aw_cmd_head_0.len,
                             aw_cmd_head_0.size, aw_cmd_head_0.burst,
                             aw_cmd_head_0.id, aw_cmd_head_0.cache,
                             aw_cmd_head_0.cobuf, aw_cmd_head_0.allstrb,
                             cycle_now);
            c_new = post_check(check_cmd(c_new, MEM_BYTES,
                              SUPPORT_FIXED_BURST, SUPPORT_WRAP_BURST,
                              SUPPORT_AWALLSTRB, SUPPORT_NARROW, 1'b1));
            c_new.lat = pick_lat(rng_new, WRITE_RESP_LATENCY_MIN,
                                 WRITE_RESP_LATENCY_MAX);
            if (init_slverr || err_inject) c_new.resp = RESP_SLVERR;
            wr_din_mux = c_new;
          end else if (!aw_cmd_empty_1) begin
            aw_cmd_pop_1 = 1'b1;
            wr_cmd_push  = 1'b1;
            c_new = make_cmd(1'b1, 2'd1, aw_cmd_head_1.addr, aw_cmd_head_1.len,
                             aw_cmd_head_1.size, aw_cmd_head_1.burst,
                             aw_cmd_head_1.id, aw_cmd_head_1.cache,
                             aw_cmd_head_1.cobuf, aw_cmd_head_1.allstrb,
                             cycle_now);
            c_new = post_check(check_cmd(c_new, MEM_BYTES,
                              SUPPORT_FIXED_BURST, SUPPORT_WRAP_BURST,
                              SUPPORT_AWALLSTRB, SUPPORT_NARROW, 1'b1));
            c_new.lat = pick_lat(rng_new, WRITE_RESP_LATENCY_MIN,
                                 WRITE_RESP_LATENCY_MAX);
            if (init_slverr || err_inject) c_new.resp = RESP_SLVERR;
            wr_din_mux = c_new;
          end
        end

        if (cmd_room_r) begin
          if (!ar_cmd_empty_0 && (ar_cmd_empty_1 || ar_last)) begin
            ar_cmd_pop_0 = 1'b1;
            rd_cmd_push  = 1'b1;
            c_new = make_cmd(1'b0, 2'd0, ar_cmd_head_0.addr, ar_cmd_head_0.len,
                             ar_cmd_head_0.size, ar_cmd_head_0.burst,
                             ar_cmd_head_0.id, 4'b0000, 1'b0, 1'b0,
                             cycle_now);
            c_new = post_check(check_cmd(c_new, MEM_BYTES,
                              SUPPORT_FIXED_BURST, SUPPORT_WRAP_BURST,
                              SUPPORT_AWALLSTRB, SUPPORT_NARROW, 1'b1));
            c_new.lat = pick_lat(rng_new, READ_LATENCY_MIN, READ_LATENCY_MAX);
            if (init_slverr || err_inject) c_new.resp = RESP_SLVERR;
            rd_din_mux = c_new;
          end else if (!ar_cmd_empty_1) begin
            ar_cmd_pop_1 = 1'b1;
            rd_cmd_push  = 1'b1;
            c_new = make_cmd(1'b0, 2'd1, ar_cmd_head_1.addr, ar_cmd_head_1.len,
                             ar_cmd_head_1.size, ar_cmd_head_1.burst,
                             ar_cmd_head_1.id, 4'b0000, 1'b0, 1'b0,
                             cycle_now);
            c_new = post_check(check_cmd(c_new, MEM_BYTES,
                              SUPPORT_FIXED_BURST, SUPPORT_WRAP_BURST,
                              SUPPORT_AWALLSTRB, SUPPORT_NARROW, 1'b1));
            c_new.lat = pick_lat(rng_new, READ_LATENCY_MIN, READ_LATENCY_MAX);
            if (init_slverr || err_inject) c_new.resp = RESP_SLVERR;
            rd_din_mux = c_new;
          end
        end
      end

      assign wr_cmd_din = wr_din_mux;
      assign rd_cmd_din = rd_din_mux;
      assign cmd_space  = 1'b1;

      always_ff @(posedge ctrl_clk) begin
        if (CFG_RESET) begin
          aw_last <= 1'b0;
          ar_last <= 1'b0;
        end else begin
          if (aw_cmd_pop_0) aw_last <= 1'b0;
          if (aw_cmd_pop_1) aw_last <= 1'b1;
          if (ar_cmd_pop_0) ar_last <= 1'b0;
          if (ar_cmd_pop_1) ar_last <= 1'b1;
        end
      end

      // no shared arbiter in the CDC build; the bound assertions disable the
      // arbitration checks through arb_enable=0.
      assign aw_req = '0;
      assign ar_req = '0;
      assign aw_grant = '0;
      assign ar_grant = '0;
    end
  endgenerate

  // ------------------------------------------------------------------
  // shared command queues
  // ------------------------------------------------------------------
  ddr_fifo #(.DEPTH(CMD_QUEUE_DEPTH), .WIDTH(CMD_W)) u_wr_cmd_fifo (
    .clk   (ctrl_clk),
    .rst_n (core_rst_n),
    .push  (wr_cmd_push),
    .din   (wr_cmd_din),
    .pop   (wr_cmd_pop),
    .dout  (wr_cmd_head),
    .full  (),
    .empty (wr_cmd_empty),
    .count (wr_cmd_count)
  );

  ddr_fifo #(.DEPTH(CMD_QUEUE_DEPTH), .WIDTH(CMD_W)) u_rd_cmd_fifo (
    .clk   (ctrl_clk),
    .rst_n (core_rst_n),
    .push  (rd_cmd_push),
    .din   (rd_cmd_din),
    .pop   (rd_cmd_pop),
    .dout  (rd_cmd_head),
    .full  (),
    .empty (rd_cmd_empty),
    .count (rd_cmd_count)
  );

  // ------------------------------------------------------------------
  // core scheduler and memory
  // ------------------------------------------------------------------
  logic        core_busy, core_sticky;
  logic        mem_we, mem_re;
  logic [32:0] mem_waddr, mem_raddr;
  logic [511:0] mem_wdata, mem_rdata;
  logic [63:0] mem_wstrb;
  logic [2:0]  mem_rsize;

  core_scheduler #(
    .WRITE_DATA_TO_B_LATENCY(WRITE_DATA_TO_B_LATENCY),
    .BVALID_CMD_QUEUE_DELAY(BVALID_CMD_QUEUE_DELAY),
    .BVALID_PHY_ISSUE_DELAY(BVALID_PHY_ISSUE_DELAY),
    .OTHER_AWCACHE_POLICY(OTHER_AWCACHE_POLICY),
    .R_BEAT_INTERVAL(R_BEAT_INTERVAL),
    .AWCOBUF_STRICT(AWCOBUF_STRICT),
    .OUT_OF_ORDER_ENABLE(OUT_OF_ORDER_ENABLE),
    .R_INTERLEAVE_ENABLE(R_INTERLEAVE_ENABLE),
    .MAX_WRITE_CTX(2*WRITE_OSTD_DEPTH),
    .MAX_READ_CTX(2*READ_OSTD_DEPTH)
  ) u_core (
    .clk(ctrl_clk), .cfg_reset(CFG_RESET),
    .port_rstn({ARSTN_1, ARSTN_0}),
    .cycle_now(cycle_now),
    .wr_cmd_empty(wr_cmd_empty), .wr_cmd_head(wr_cmd_head),
    .wr_cmd_pop(wr_cmd_pop),
    .rd_cmd_empty(rd_cmd_empty), .rd_cmd_head(rd_cmd_head),
    .rd_cmd_pop(rd_cmd_pop),
    .w_pop(w_pop), .w_head_0(w_head_0), .w_head_1(w_head_1),
    .w_empty(w_empty),
    .b_push(b_push), .b_in_0(b_in_0), .b_in_1(b_in_1), .b_full(b_full),
    .r_push(r_push), .r_in_0(r_in_0), .r_in_1(r_in_1), .r_full(r_full),
    .mem_we(mem_we), .mem_waddr(mem_waddr), .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_re(mem_re), .mem_raddr(mem_raddr), .mem_rsize(mem_rsize),
    .mem_rdata(mem_rdata),
    .busy(core_busy), .sticky_err(core_sticky)
  );

  mem_model #(
    .MEM_BYTES(MEM_BYTES),
    .MEM_INIT_MODE(MEM_INIT_MODE),
    .MEM_INIT_SEED(MEM_INIT_SEED),
    .CFG_RESET_CLEAR_MEM(CFG_RESET_CLEAR_MEM)
  ) u_mem (
    .clk(ctrl_clk), .cfg_reset(CFG_RESET),
    .we(mem_we), .waddr(mem_waddr), .wdata(mem_wdata), .wstrb(mem_wstrb),
    .re(mem_re), .raddr(mem_raddr), .rsize(mem_rsize),
    .rdata(mem_rdata), .rvalid()
  );

  // ------------------------------------------------------------------
  // status
  // ------------------------------------------------------------------
  assign CTRL_INIT_DONE = ENABLE_CTRL_STATUS ? cfg_done : 1'b0;
  assign CTRL_READY     = ENABLE_CTRL_STATUS ? (cfg_done && !init_block) : 1'b0;
  assign CTRL_ERR       = ENABLE_CTRL_STATUS ? core_sticky : 1'b0;
  assign CTRL_BUSY      = ENABLE_CTRL_STATUS ? core_busy : 1'b0;

  // ------------------------------------------------------------------
  // debug field decode of the last accepted command
  // ------------------------------------------------------------------
  logic [32:0] dbg_fields_q, dbg_addr_q;
  ddr_cmd_t    wr_dbg_cmd, rd_dbg_cmd;

  always_comb begin
    wr_dbg_cmd = ddr_cmd_t'(wr_cmd_din);
    rd_dbg_cmd = ddr_cmd_t'(rd_cmd_din);
  end

  always_ff @(posedge ctrl_clk) begin
    if (CFG_RESET) begin
      dbg_fields_q <= '0;
      dbg_addr_q   <= '0;
    end else if (wr_cmd_push || rd_cmd_push) begin
      if (wr_cmd_push) dbg_addr_q <= wr_dbg_cmd.addr;
      else             dbg_addr_q <= rd_dbg_cmd.addr;
      if (ADDR_MAP_MODE == 1) begin
        if (wr_cmd_push)
          dbg_fields_q <= decode_addr_fields(wr_dbg_cmd.addr, ADDR_CS_BIT_POS);
        else
          dbg_fields_q <= decode_addr_fields(rd_dbg_cmd.addr, ADDR_CS_BIT_POS);
      end else begin
        dbg_fields_q <= '0;
      end
    end
  end

  assign DBG_FIELDS      = dbg_fields_q;
  assign DBG_FIELDS_ADDR = dbg_addr_q;

  // ------------------------------------------------------------------
  // elaboration checks
  // ------------------------------------------------------------------
  initial begin
    if (!(MEM_DENSITY_GBIT inside {2, 3, 4, 6, 8, 12, 16}))
      $fatal(1, "MEM_DENSITY_GBIT=%0d is not a supported TJ density",
             MEM_DENSITY_GBIT);
    if (!((DATA_WIDTH == 16) || (DATA_WIDTH == 32)))
      $fatal(1, "DATA_WIDTH must be 16 or 32");
    if (MEM_BYTES > 64'h2_0000_0000)
      $fatal(1, "MEM_BYTES=%0d exceeds 33-bit AXI address space", MEM_BYTES);
    if (RANK_MAP_MODE == 2) begin
      if ((RANK_STRIDE_BYTES & (RANK_STRIDE_BYTES - 1)) != 0)
        $fatal(1, "CS_BIT mode requires power-of-two RANK_STRIDE_BYTES");
      if (CS_BIT_EFF != $clog2(RANK_STRIDE_BYTES))
        $fatal(1, "CS_BIT_POS must equal log2(RANK_STRIDE_BYTES)");
    end
    if (ADDR_MAP_MODE == 1) begin
      if ((ADDR_CS_BIT_POS < 12) || (ADDR_CS_BIT_POS > 32))
        $warning("ADDR_CS_BIT_POS=%0d is outside the decodable range",
                 ADDR_CS_BIT_POS);
      else if ((64'(1) << ADDR_CS_BIT_POS) > MEM_BYTES)
        $warning("field-decode span exceeds MEM_BYTES; decode is debug-only");
    end
    if ((ADDR_HOLE_END > ADDR_HOLE_START) && (ADDR_HOLE_END > MEM_BYTES))
      $warning("address hole extends beyond MEM_BYTES");
  end

endmodule
