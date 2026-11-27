[中文](phase2-summary.md) | English

# Phase 2 Summary — frame_reader v4.2 (148.5M Display-Domain Playback + Frame-Level Arbitration + Unit TB All Green)

> Status: **Completed and accepted (2026-10-21)** · Spec: SPEC-001 mod-frame-reader-v3 / alg-bank-handoff · Verification level: FPGA_INTEGRATION (roles: main-flow / arbiter / cdc prerequisites) · Final regression: `tb_fr_final.log` **[FR-OK] all checks passed**

## 1. Goal

Move the whole playback backend into the 148.5M display domain (architecture v4's "all-display-domain backend"): the reader emits freely at the **local disp_timing cadence** (fully decoupled from the source), and source frequency drift is absorbed by **frame-level drop/repeat**; on the input side it consumes Phase 1's `wr_frame_done` single-cycle pulse + `wr_frame_par` level (a 1-bit cross-domain frame handshake), moves the data line-by-line in a ping-pong fashion into lram through the DDR dual asynchronous ports (Port1 @148.5M, confirmed in Phase 0), and feeds the downstream demosaic directly at 40bit/beat.

## 2. RTL changes (rtl/frame_reader.v, v4 → v4.1 → v4.2)

### 2.1 The v4 body (the Phase 2 first version)

- **Frame-level arbitration** (alg-bank-handoff): `wr_frame_done` is taken as an edge through 2 FFs into `frame_req`; the start gate is `done_cnt>=2`; the request is sticky (`req_pending`); the slot fire is a three-state affair — with a new edge, switch to read the newest complete frame (bank = `~par_sync[1]`); with edges piling up, merge and count a drop; with no edge, re-read the current frame and count a repeat.
- **Line ping-pong**: lram0/lram1 hold 128 words each (one line is 75 words), `rdy[2]` are the ready bits, the emission consumes `r_sel`, the read path writes `w_sel`, and `R_GAP` gates the line ledger.
- **Emission path**: `S_FETCH` prefetches 5 words → `sr <= {w4,w3,w2,w1,w0}` a 2560bit shift chain → `S_SHIFT` does `m_axis_tdata <= sr[39:0]` every cycle (1 fp40/cycle); sof/sol/eol tuser are generated locally.
- **Parameterization**: `FRAME_TICKS` (slot period), `FRAME_A/B` base addresses; the top level `top_cam_demo.sv` instantiates it accordingly (`u_fr`, in the 148.5M domain).

### 2.2 v4.1 — the rready stuck-high defect (data integrity, the same disease on the board)

- **Symptom**: unit TB V7 shows a deterministic misalignment starting at beat 819 of each line; the [W64CHK] three-way comparison proves that `lram0[64]` is bit-for-bit equal to the expected value of **word65** (burst1 as a whole shifted forward by 1 word).
- **Root cause**: once `rready` is pulled high at the first `R_PRE` it is **never withdrawn between bursts**. Between the AR handshake of burst1 and the DUT entering `R_RD`, rready stays at 1, so the slave's first beat (word64) completes its AXI handshake inside the `R_PRE` window and is wasted; the first beat the DUT actually receives is the slave's 2nd beat. burst0 escapes purely by the timing coincidence of rready=0 after reset.
- **Fix**: rready is low by default and high only during `R_PRE`/`R_RD`. A real board-level DDR controller likewise completes a transfer on `rvalid&&rready` — this defect would inevitably lose the first beat on the board, so it is a DUT-side defect rather than a TB modelling error.

### 2.3 v4.2 — the over-strict line ledger + the arbitration same-cycle race

- **R_GAP line ledger**: `line_r == rdln + 1` (only after line n **completes** emission may line n+1 be read) compresses the ~105-cycle dual-burst read latency into the ~50-cycle window between the line tail and the tick, necessarily missing the tick and emitting alternately late line by line — the unit TB proves 12 frames with zero drift consume 17.87ms (**2 slots/frame**) and drop=11. Changed to `line_r == rdln` (once line n **enters** emission, overwriting is safe: the target bank of line n+1 differs from the emission bank), so the read always leads the emission by exactly 1 line and rdy is ready ~945 cycles earlier.
- **Arbitration same-cycle race**: when `frame_grant` and `frame_req` occur in the same cycle, the original code's `else if (arm_fresh) req_pending<=1` branch is preempted by the grant → the new edge is silently dropped (S0 start loses fid1); moreover the grant serves the old frame inside `par_sync[1]` (2 cycles stale), so a new edge in this cycle must be deferred. Fix: on grant, `req_pending <= frame_req` (a same-cycle new edge is deferred), and a drop is counted only when "an edge arrived while the backlog was not accepted in this cycle".

## 3. Unit TB (sim/tb_frame_reader.sv)

- Shortened frame `VACT=90`, `FRAME_TICKS=100` (the 960-beat line / 1100-beat tick structure is unchanged); four scenarios: **zero-drift 12 frames → +2% 60 frames → −2% 60 frames → +100ppm 30 frames** (162 frames ≈121ms, watchdog 140ms).
- **Source model**: an abstracted writer — on frame completion it emits a `wr_frame_done` single cycle + a `wr_par` toggle, and an associative array `mem_model` is filled word by word with fingerprints (`exp_word_rw`, a continuously packed bitstream, isomorphic to the writer's packing); the frame period is `P = FTICKS*TICK_CLKS − 11*ppm_x100` (+ppm = source faster = shorter period, the sign is uniformly taken negative in the source period block).
- **AXI slave**: arready has a fixed 10-cycle delay (an abstraction of DDR read latency), rdata is read out of mem_model sequentially, and a miss returns 512'hx.
- **V7 contract (finalized in v4.3)**: `m_axis_tdata` is 40bit/cycle = 1 fp40, and the expectation is `fp40(fid, l, b)` compared cycle by cycle (negedge sampling + blocking-assignment position tracking).
- **FIDSEQ stream-level audit (added in v4.2, the judgement baseline)**: measure drop (jumps) / repeat (duplicates) directly from the frame-number sequence carried by sof; the V2/V3/V4/V6 judgements now use the stream truth, and the DUT's `dbg_fr_cnt` self-counting is demoted to a reconciliation print — after the fix, both match one-for-one in all four scenarios.

## 4. Verification results (final regression tb_fr_final.log)

| Check | Result | cnt(d,r) | stream(d,r) | Notes |
|---|---|---|---|---|
| V2 zero-drift 12 frames | **OK** | 0,1 | 1,0 | The start release window (done_cnt>=2) structurally merges 1 frame, tolerance ≤1; the steady state is clean |
| V3 +2% (fast source) 60 frames | **OK** | 1,0 | 1,0 | The drop direction is correct, repeat=0 |
| V4 −2% (slow source) 60 frames | **OK** | 0,1 | 0,1 | The repeat direction is correct, drop=0 |
| V6 +100ppm 30 frames | **OK** | 0,0 | 0,0 | Sub-arbitration confirmed: a 0.3 tick drift does not trigger arbitration |
| V5/V7 fingerprint / atomicity | **OK** | — | — | 162 frames with cycle-by-cycle fingerprints all correct, no tearing |
| Count reconciliation | **OK** | — | — | cnt and stream are identical one-for-one across the four scenarios (the arbitration bookkeeping is provably correct) |

Criterion: `[FR-OK] all checks passed`, `fail_cnt=0`. V1 (the slot cadence is a constant FRAME_TICKS) is guaranteed by the emission FSM structure and re-checked via the segment boundary timestamps (S0 12 frames 9.64ms, S1 60 frames 44.44ms, both ~740.7µs/frame).

## 5. Defects found and fixed in this phase (regression assets)

| # | Layer | Defect | Hard proof | Fix |
|---|---|---|---|---|
| 1 | DUT | `rready` stays high between bursts, the first beat of burst1 is wasted in the R_PRE window | [W64CHK] lram0[64]=word65 bit-for-bit | v4.1: rready high only during PRE/R_RD |
| 2 | DUT | The R_GAP line ledger `line_r==rdln+1` is over-strict, the read latency does not fit in the inter-line window | S0 12 frames consume 17.87ms, drop=11 | v4.2: change to `line_r==rdln`, the read always leads by 1 line |
| 3 | DUT | A new edge in the same cycle as the arbitration grant is silently dropped, drop/repeat counting is distorted | cnt and stream disagree at segment level | v4.2: defer with `req_pending <= frame_req` + tighten the drop condition |
| 4 | TB | The source model's ppm is dead logic (rem only enters the accumulator, the period is constant) | The ±2% segment cadence is indistinguishable from zero drift | v4.2: `src_wait <= src_per_int + src_per_rem - 1` |
| 5 | TB | The signed rem preset by `set_phase` is overwritten every cycle by the always block using the old convention | The +2% segment measures a slow source (direction inverted) | v4.2: the sign is uniformly taken negative in the source period block, set_phase only sets ppm |
| 6 | TB | The V7 expected-value contract takes a detour: the exp64 bitstream-slice model does not apply to the 40bit/cycle emission domain | act=fp40(0,208,51) misjudges cross-cycle fragments | v4.3 final: the fp40 cycle-by-cycle model ([SR12]/[W64CHK] three-way comparison settles it) |

Debugging methodology distilled: **three-way comparison** (exp = the fingerprint function's theoretical value / mem = the slave's storage / lram = the DUT's landing point) locates the error layer in one shot, avoiding endless backtracking from the output end.

## 6. Known costs / outstanding items (Phase 4 inputs)

- **The S0 start release window merges ≤1 frame**: the `done_cnt>=2` gate folds the first two requests into the first emission; this is a structural cost, and V2 tolerates it while printing the actual value.
- **Cross-domain pulse width risk (must be re-checked in Phase 4)**: `wr_frame_done_o` is a single-cycle pulse in the 200M domain (≈5ns), while the reader's 2FF sampling period is 6.734ns — the same-domain TB is lossless, but on the board there is a risk of the whole pulse falling between two sampling edges (on the order of ~25%). At the Phase 4 integration the pulse must be widened (≥2 148.5M cycles) or changed to a toggle handshake, and the drop/repeat counts must be re-measured on the board.
- The observation points `rd_frame_cnt/rd_line/rd_state/rd_err/dbg_fr_cnt` are kept (the core of R9 board testing).
- The writer-side TODO-419 (burst1 bit errors) was fixed at the beginning of this phase and the regression is all green (see phase1-summary §5 → closed).

## 7. Next step (Phase 3)

disp_timing v2 (100% local display timing, 2250 slots/frame with real parameters) + tx_line_buf (emission line buffer) + a full-chain TB (writer→DDR→reader→disp pixel stream); Phase 4 board integration (including the §6 pulse widening).
