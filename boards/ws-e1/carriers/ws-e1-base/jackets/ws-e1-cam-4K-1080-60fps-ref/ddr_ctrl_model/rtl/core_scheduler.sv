// Command execution engines.
// OUT_OF_ORDER_ENABLE=0 keeps one context per direction, reproducing the
// global in-order model. With it enabled, multiple write/read contexts are
// active; completions may pass each other across different (port, ID) pairs.
// Same-(port,ID) ordering is always preserved. R beats from different
// contexts are interleaved only when R_INTERLEAVE_ENABLE=1.
module core_scheduler #(
  parameter int  WRITE_DATA_TO_B_LATENCY = 4,
  parameter int  BVALID_CMD_QUEUE_DELAY = 2,
  parameter int  BVALID_PHY_ISSUE_DELAY = 2,
  parameter int  OTHER_AWCACHE_POLICY = 0, // 0=DATA_DONE 1=CMD_QUEUE 2=PHY_ISSUE
  parameter int  R_BEAT_INTERVAL = 1,
  parameter bit AWCOBUF_STRICT = 1,
  parameter bit OUT_OF_ORDER_ENABLE = 1'b0,
  parameter bit R_INTERLEAVE_ENABLE = 1'b0,
  parameter int  MAX_WRITE_CTX = 16,
  parameter int  MAX_READ_CTX = 16
) (
  input  logic        clk,
  input  logic        cfg_reset,
  input  logic [1:0]  port_rstn,
  input  logic [63:0] cycle_now,

  // shared command queues
  input  logic        wr_cmd_empty,
  input  logic [270:0] wr_cmd_head,
  output logic        wr_cmd_pop,
  input  logic        rd_cmd_empty,
  input  logic [270:0] rd_cmd_head,
  output logic        rd_cmd_pop,

  // W beat FIFOs (one per port)
  output logic [1:0]        w_pop,
  input  logic [640:0]      w_head_0,
  input  logic [640:0]      w_head_1,
  input  logic [1:0]        w_empty,

  // B response FIFOs (one per port)
  output logic [1:0]        b_push,
  output logic [7:0]        b_in_0,
  output logic [7:0]        b_in_1,
  input  logic [1:0]        b_full,

  // R response FIFOs (one per port)
  output logic [1:0]        r_push,
  output logic [520:0]      r_in_0,
  output logic [520:0]      r_in_1,
  input  logic [1:0]        r_full,

  // memory
  output logic        mem_we,
  output logic [32:0] mem_waddr,
  output logic [511:0] mem_wdata,
  output logic [63:0] mem_wstrb,
  output logic        mem_re,
  output logic [32:0] mem_raddr,
  output logic [2:0]  mem_rsize,
  input  logic [511:0] mem_rdata,

  output logic        busy,
  output logic        sticky_err
);
  import ddr_model_pkg::*;

  localparam int CMD_W = $bits(ddr_cmd_t); // 271
  localparam int NW = OUT_OF_ORDER_ENABLE ? MAX_WRITE_CTX : 1;
  localparam int NR = OUT_OF_ORDER_ENABLE ? MAX_READ_CTX : 1;

  ddr_cmd_t wr_cmd_view;
  ddr_cmd_t rd_cmd_view;
  assign wr_cmd_view = ddr_cmd_t'(wr_cmd_head);
  assign rd_cmd_view = ddr_cmd_t'(rd_cmd_head);

  typedef struct {
    logic        valid;
    logic [31:0] seq;
    ddr_cmd_t    cmd;
    logic [31:0] beat_idx;
    logic        data_done;
    logic        b_sent;
    logic        is_early;
    logic [63:0] deadline;
    logic [63:0] last_time;
  } wctx_t;

  typedef struct {
    logic        valid;
    logic [31:0] seq;
    ddr_cmd_t    cmd;
    logic [31:0] beat_idx;
    logic [31:0] gap;
    logic [63:0] deadline;
  } rctx_t;

  wctx_t       wctx [NW];
  rctx_t       rctx [NR];
  logic [31:0] w_seq, r_seq;
  logic [31:0] r_rr;

  // ------------------------------------------------------------------
  // helpers
  // ------------------------------------------------------------------
  function automatic bit cmd_is_early(input ddr_cmd_t c, input int policy);
    if ((c.cache == 4'b1111) && c.cobuf) return 1'b1;
    // correlation Phase 5 板级实测（2026-10-23，plan §9）：B 时机由
    // AxCACHE[0]（Bufferable）单独决定——bit0=1 早返（B≈AW 握手+2-4 ACLK，
    // 实测 0001/0011/0111 全同形），bit0=0 B 在写数据提交后（WA≈WL 55-99
    // ACLK，实测 0000/0010/0100/1110 全同形）。COBUF 无独立效应（0000/1110
    // × cobuf 同形）；1111 裸值 AW/W 死锁（Phase 2），按 bit0 规律外推早返。
    // 原 OTHER_AWCACHE_POLICY=DATA_DONE 对 bit0=1 编码与板级符号相反，已改。
    if (c.cache[0]) return 1'b1;
    if (policy != 0) return 1'b1;   // 兜底策略（policy=DATA_DONE=一律非早返）
    return 1'b0;
  endfunction

  function automatic logic [63:0] cmd_early_delay(input ddr_cmd_t c, input int policy);
    if ((c.cache == 4'b1111) && c.cobuf) return 64'(BVALID_CMD_QUEUE_DELAY);
    // Phase 5：bit0=1 早返为 bufferable 写入 buffer 即确认（命令队列语义），
    // 延迟回填 BVALID_CMD_QUEUE_DELAY；BVALID_PHY_ISSUE_DELAY 仅 policy=2 兜底
    return (policy == 2) ? 64'(BVALID_PHY_ISSUE_DELAY)
                         : 64'(BVALID_CMD_QUEUE_DELAY);
  endfunction

  function automatic bit same_origin(input ddr_cmd_t a, input ddr_cmd_t b);
    return (a.port == b.port) && (a.id == b.id);
  endfunction

  // ------------------------------------------------------------------
  // write-side context selection
  // ------------------------------------------------------------------
  int          w_free_idx;
  int          w_data_idx;
  int          w_b_sel;
  logic [63:0] w_b_deadline;
  ddr_wbeat_t  wb;
  logic        w_consume;
  logic        w_allstrb_bad;
  logic        w_wlast_bad;
  logic [63:0] w_beat_addr;

  always_comb begin
    w_free_idx = -1;
    for (int i = 0; i < NW; i++) begin
      if (!wctx[i].valid) begin
        w_free_idx = i;
        break;
      end
    end
  end

  always_comb begin
    w_data_idx = -1;
    for (int i = 0; i < NW; i++) begin
      if (wctx[i].valid && !wctx[i].data_done) begin
        if ((w_data_idx < 0) || (wctx[i].seq < wctx[w_data_idx].seq))
          w_data_idx = i;
      end
    end
  end

  always_comb begin
    w_b_sel      = -1;
    w_b_deadline = '1;
    for (int i = 0; i < NW; i++) begin
      bit blocked;
      blocked = 1'b0;
      if (wctx[i].valid && !wctx[i].b_sent) begin
        for (int j = 0; j < NW; j++) begin
          if (wctx[j].valid && !wctx[j].b_sent && (wctx[j].seq < wctx[i].seq) &&
              same_origin(wctx[j].cmd, wctx[i].cmd))
            blocked = 1'b1;
        end
        if (!blocked && port_rstn[wctx[i].cmd.port] &&
            !b_full[wctx[i].cmd.port] && (cycle_now >= wctx[i].deadline) &&
            (wctx[i].is_early ||
             (wctx[i].data_done &&
              (cycle_now >= wctx[i].last_time + 64'(WRITE_DATA_TO_B_LATENCY))))) begin
          if ((w_b_sel < 0) || (wctx[i].deadline < w_b_deadline) ||
              ((wctx[i].deadline == w_b_deadline) &&
               (wctx[i].seq < wctx[w_b_sel].seq))) begin
            w_b_sel      = i;
            w_b_deadline = wctx[i].deadline;
          end
        end
      end
    end
  end

  // ------------------------------------------------------------------
  // read-side context selection
  // ------------------------------------------------------------------
  int r_free_idx;
  int r_emit_idx;
  int r_started_idx;

  function automatic bit r_candidate(input int i);
    bit blocked;
    blocked = 1'b0;
    for (int j = 0; j < NR; j++) begin
      if (rctx[j].valid && (rctx[j].seq < rctx[i].seq) &&
          same_origin(rctx[j].cmd, rctx[i].cmd))
        blocked = 1'b1;
    end
    return rctx[i].valid && !blocked && port_rstn[rctx[i].cmd.port] &&
           (cycle_now >= rctx[i].deadline) && (rctx[i].gap == 0) &&
           !r_full[rctx[i].cmd.port];
  endfunction

  always_comb begin
    r_free_idx = -1;
    for (int i = 0; i < NR; i++) begin
      if (!rctx[i].valid) begin
        r_free_idx = i;
        break;
      end
    end
  end

  always_comb begin
    r_emit_idx    = -1;
    r_started_idx = -1;

    for (int i = 0; i < NR; i++) begin
      if (rctx[i].valid && (rctx[i].beat_idx != 0)) r_started_idx = i;
    end

    if (R_INTERLEAVE_ENABLE) begin
      for (int k = 0; k < NR; k++) begin
        int idx;
        idx = (int'(r_rr) + k) % NR;
        if (r_candidate(idx)) begin
          r_emit_idx = idx;
          break;
        end
      end
    end else if (r_started_idx >= 0) begin
      if (r_candidate(r_started_idx)) r_emit_idx = r_started_idx;
    end else begin
      for (int i = 0; i < NR; i++) begin
        if (r_candidate(i)) begin
          if ((r_emit_idx < 0) ||
              (rctx[i].deadline < rctx[r_emit_idx].deadline) ||
              ((rctx[i].deadline == rctx[r_emit_idx].deadline) &&
               (rctx[i].seq < rctx[r_emit_idx].seq)))
            r_emit_idx = i;
        end
      end
    end
  end

  // ------------------------------------------------------------------
  // datapath / handshake pulses
  // ------------------------------------------------------------------
  logic        b_can_send;
  logic [7:0]  b_word;
  ddr_rbeat_t  rb;
  logic [520:0] r_word;
  logic [63:0] r_beat_addr;
  logic        wr_sticky;
  logic        rd_sticky;

  assign sticky_err = wr_sticky | rd_sticky;

  always_comb begin
    wr_cmd_pop = 1'b0;
    rd_cmd_pop = 1'b0;
    w_pop      = '0;
    b_push     = '0;
    b_in_0     = '0;
    b_in_1     = '0;
    r_push     = '0;
    r_in_0     = '0;
    r_in_1     = '0;
    mem_we     = 1'b0;
    mem_waddr  = '0;
    mem_wdata  = '0;
    mem_wstrb  = '0;
    mem_re     = 1'b0;
    mem_raddr  = '0;
    mem_rsize  = '0;

    w_consume     = 1'b0;
    w_allstrb_bad = 1'b0;
    w_wlast_bad   = 1'b0;
    w_beat_addr   = '0;
    wb            = '0;
    b_can_send    = 1'b0;
    b_word        = '0;
    r_beat_addr   = '0;
    rb            = '0;
    r_word        = '0;

    // ---------------- command dispatch ----------------
    if ((w_free_idx >= 0) && !wr_cmd_empty && port_rstn[wr_cmd_view.port])
      wr_cmd_pop = 1'b1;
    if ((r_free_idx >= 0) && !rd_cmd_empty && port_rstn[rd_cmd_view.port])
      rd_cmd_pop = 1'b1;

    // ---------------- write data consume / memory write ----------------
    if ((w_data_idx >= 0) && port_rstn[wctx[w_data_idx].cmd.port] &&
        !w_empty[wctx[w_data_idx].cmd.port]) begin
      wb = (wctx[w_data_idx].cmd.port == 0) ? ddr_wbeat_t'(w_head_0)
                                           : ddr_wbeat_t'(w_head_1);
      w_consume = 1'b1;
      w_pop[wctx[w_data_idx].cmd.port] = 1'b1;
      w_beat_addr = beat_addr(wctx[w_data_idx].cmd.addr,
                              int'(wctx[w_data_idx].beat_idx),
                              wctx[w_data_idx].cmd.len,
                              wctx[w_data_idx].cmd.size,
                              wctx[w_data_idx].cmd.burst);
      w_allstrb_bad = wctx[w_data_idx].cmd.allstrb && (wb.strb != '1);
      w_wlast_bad   = (wctx[w_data_idx].beat_idx ==
                       wctx[w_data_idx].cmd.beats - 1) ? !wb.last : wb.last;
      if ((wctx[w_data_idx].cmd.resp == RESP_OKAY) && !w_allstrb_bad) begin
        mem_we    = 1'b1;
        mem_waddr = w_beat_addr[32:0];
        mem_wdata = wb.data;
        mem_wstrb = wb.strb;
      end
    end

    // ---------------- B scheduling ----------------
    if (w_b_sel >= 0) begin
      b_can_send = 1'b1;
      b_word = {wctx[w_b_sel].cmd.id, wctx[w_b_sel].cmd.resp};
      b_push[wctx[w_b_sel].cmd.port] = 1'b1;
      if (wctx[w_b_sel].cmd.port == 0) b_in_0 = b_word;
      else                             b_in_1 = b_word;
    end

    // ---------------- read data emit ----------------
    if (r_emit_idx >= 0) begin
      r_beat_addr = beat_addr(rctx[r_emit_idx].cmd.addr,
                              int'(rctx[r_emit_idx].beat_idx),
                              rctx[r_emit_idx].cmd.len,
                              rctx[r_emit_idx].cmd.size,
                              rctx[r_emit_idx].cmd.burst);
      mem_re    = 1'b1;
      mem_raddr = r_beat_addr[32:0];
      mem_rsize = rctx[r_emit_idx].cmd.size;
      rb.data   = mem_rdata;
      rb.id     = rctx[r_emit_idx].cmd.id;
      rb.last   = (rctx[r_emit_idx].beat_idx ==
                   rctx[r_emit_idx].cmd.beats - 1);
      rb.resp   = rctx[r_emit_idx].cmd.resp;
      r_word    = rb;
      r_push[rctx[r_emit_idx].cmd.port] = 1'b1;
      if (rctx[r_emit_idx].cmd.port == 0) r_in_0 = r_word;
      else                                r_in_1 = r_word;
    end
  end

  // ------------------------------------------------------------------
  // write contexts
  // ------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (cfg_reset) begin
      for (int i = 0; i < NW; i++) begin
        wctx[i].valid     <= 1'b0;
        wctx[i].seq       <= '0;
        wctx[i].cmd       <= '0;
        wctx[i].beat_idx  <= '0;
        wctx[i].data_done <= 1'b0;
        wctx[i].b_sent    <= 1'b0;
        wctx[i].is_early  <= 1'b0;
        wctx[i].deadline  <= '0;
        wctx[i].last_time <= '0;
      end
      w_seq     <= '0;
      wr_sticky <= 1'b0;
    end else begin
      for (int i = 0; i < NW; i++) begin
        if (wctx[i].valid && !port_rstn[wctx[i].cmd.port]) begin
          wctx[i].valid <= 1'b0;
        end else if (wctx[i].valid && wctx[i].data_done &&
                     (wctx[i].b_sent || (w_b_sel == i))) begin
          wctx[i].valid <= 1'b0;
        end else if (wctx[i].valid) begin
          if (w_consume && (w_data_idx == i)) begin
            if (w_wlast_bad) begin
              if (!wctx[i].b_sent) wctx[i].cmd.resp <= RESP_SLVERR;
              wr_sticky <= 1'b1;
            end
            if (w_allstrb_bad) begin
              if (!wctx[i].b_sent) wctx[i].cmd.resp <= RESP_SLVERR;
              wr_sticky <= 1'b1;
            end
            wctx[i].beat_idx <= wctx[i].beat_idx + 1'b1;
            if (wctx[i].beat_idx == wctx[i].cmd.beats - 1) begin
              wctx[i].data_done <= 1'b1;
              wctx[i].last_time <= wb.t_accept;
            end
          end
          if (w_b_sel == i) wctx[i].b_sent <= 1'b1;
        end
      end

      if (wr_cmd_pop) begin
        wctx[w_free_idx].valid     <= 1'b1;
        wctx[w_free_idx].seq       <= w_seq;
        wctx[w_free_idx].cmd       <= ddr_cmd_t'(wr_cmd_head);
        wctx[w_free_idx].beat_idx  <= '0;
        wctx[w_free_idx].data_done <= 1'b0;
        wctx[w_free_idx].b_sent    <= 1'b0;
        wctx[w_free_idx].is_early  <=
            cmd_is_early(ddr_cmd_t'(wr_cmd_head), OTHER_AWCACHE_POLICY);
        wctx[w_free_idx].deadline  <=
            wr_cmd_view.t_accept +
            (cmd_is_early(ddr_cmd_t'(wr_cmd_head), OTHER_AWCACHE_POLICY)
             ? cmd_early_delay(ddr_cmd_t'(wr_cmd_head), OTHER_AWCACHE_POLICY)
             : wr_cmd_view.lat);
        wctx[w_free_idx].last_time <= '0;
        w_seq <= w_seq + 1'b1;
        if (wr_cmd_view.resp != RESP_OKAY) wr_sticky <= 1'b1;
        if (AWCOBUF_STRICT && wr_cmd_view.cobuf &&
            (wr_cmd_view.cache != 4'b1111) &&
            (wr_cmd_view.cache != 4'b0000)) wr_sticky <= 1'b1;
      end
    end
  end

  // ------------------------------------------------------------------
  // read contexts
  // ------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (cfg_reset) begin
      for (int i = 0; i < NR; i++) begin
        rctx[i].valid    <= 1'b0;
        rctx[i].seq      <= '0;
        rctx[i].cmd      <= '0;
        rctx[i].beat_idx <= '0;
        rctx[i].gap      <= '0;
        rctx[i].deadline <= '0;
      end
      r_seq  <= '0;
      r_rr   <= '0;
      rd_sticky <= 1'b0;
    end else begin
      for (int i = 0; i < NR; i++) begin
        if (rctx[i].valid && !port_rstn[rctx[i].cmd.port]) begin
          rctx[i].valid <= 1'b0;
        end else if (rctx[i].valid && (rctx[i].gap != 0) && (r_emit_idx != i)) begin
          rctx[i].gap <= rctx[i].gap - 1'b1;
        end
      end

      if (r_emit_idx >= 0) begin
        if (rctx[r_emit_idx].beat_idx == rctx[r_emit_idx].cmd.beats - 1) begin
          rctx[r_emit_idx].valid <= 1'b0;
        end else begin
          rctx[r_emit_idx].beat_idx <= rctx[r_emit_idx].beat_idx + 1'b1;
          rctx[r_emit_idx].gap      <=
              (R_BEAT_INTERVAL > 1) ? 32'(R_BEAT_INTERVAL-1) : '0;
        end
        if (rctx[r_emit_idx].cmd.resp != RESP_OKAY) rd_sticky <= 1'b1;
        r_rr <= (r_emit_idx == NR-1) ? '0 : 32'(r_emit_idx + 1);
      end

      if (rd_cmd_pop) begin
        rctx[r_free_idx].valid    <= 1'b1;
        rctx[r_free_idx].seq      <= r_seq;
        rctx[r_free_idx].cmd      <= ddr_cmd_t'(rd_cmd_head);
        rctx[r_free_idx].beat_idx <= '0;
        rctx[r_free_idx].gap      <= '0;
        rctx[r_free_idx].deadline <= rd_cmd_view.t_accept + rd_cmd_view.lat;
        r_seq <= r_seq + 1'b1;
        if (rd_cmd_view.resp != RESP_OKAY) rd_sticky <= 1'b1;
      end
    end
  end

  logic w_any, r_any;
  always_comb begin
    w_any = 1'b0;
    r_any = 1'b0;
    for (int i = 0; i < NW; i++) if (wctx[i].valid) w_any = 1'b1;
    for (int i = 0; i < NR; i++) if (rctx[i].valid) r_any = 1'b1;
  end

  assign busy = w_any || r_any || !wr_cmd_empty || !rd_cmd_empty;

endmodule
