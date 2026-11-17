[中文](arbiter-impl-plan.md) | English

# AXI Arbiter Implementation and Verification Step Plan (axi_wr_arb / axi_rd_arb)

| Item | Value |
|---|---|
| Version | v1.0 |
| Date | 2026-10-23 |
| Basis | [arbiter.md](arbiter.md) **v1.2 (frozen)**; this document only lays out steps and pass criteria, and does not change design semantics |
| Related | [cam1-ddr-replay-plan.md](cam1-ddr-replay-plan.md) (task 2 phase 3/4 integration ownership), [ddr-dram-controller-tj-ug-v3.0.md](ddr-dram-controller-tj-ug-v3.0.md) (TJ UG) |
| Status | **Awaiting user review** |

---

## 1. Scope and Deliverables

| # | File | Type | Basis (arbiter.md) |
|---|---|---|---|
| D1 | `rtl/axi_wr_arb.v` | RTL, pure Verilog-2001, ≤400 lines | §4.1, §5, §6, §7 |
| D2 | `rtl/axi_rd_arb.v` | Same (same structure, different channels) | §4.2, §5, §6, §7 |
| D3 | `sim/axi_wr_arb_tb.sv` | Unit TB (SV + SVA hierarchical references) | §9 (T matrix / A1-A10) |
| D4 | `sim/axi_rd_arb_tb.sv` | Same | §9 |

**Boundaries (explicitly out of scope of this plan)**:

1. `axi_rd_cdc` detailed design and implementation — a separate detailed-design review will be produced before phase 4 starts (arbiter.md §4.3 only defines the contract);
2. top_cam integration and tb_phase4 regression — belongs to task 2 phase 3/4 (existing plan in cam1-ddr-replay-plan.md); this plan stops at **all-green unit verification**;
3. The unit TB **does not use** a DDR behavioral model (a memory slave with scoreboard suffices); per arbiter.md §9 the DDR behavioral model is used only for integration regression (tb_phase4, using `ddr_ctrl_model/`, run the same way as the existing sim/tb_phase4_ddrm.sv).

## 2. Implementation Steps (S1→S6 executed in order)

### S1 Implement rtl/axi_wr_arb.v

| Action | Key points (all quoted from arbiter.md; no new semantics introduced during implementation) |
|---|---|
| 1. RR1 arbitration core | `last` resets to 0 → first contention grants S1=cam0 (§5.1, intentionally arranged tie-break, pinned by comment); `gnt` one-hot latched; on the transaction-finalizing beat `last <= grant`, 1 idle beat between transactions |
| 2. Address channel | Beat 0 capture: register empty on the grant beat → `s_awready = gnt` constantly true, AW full payload latched in the same beat (§5.1 pipeline + §5.3 rule 3); 33-bit address passed through unspliced (§4.1); awqos=1 always delivered (§4.1) |
| 3. W half-buffer | §5.3 four rules: load = S handshake; clear = M handshake; load wins on same-beat load/clear conflict; `m_wvalid=valid_reg`; `s_wready = gnt_match && (!valid_reg \|\| m_wready)`; wstrb registered in the same beat as wdata |
| 4. B channel | Combinational mux by gnt (lock period covers the entire B, §5.5); idle-beat bready=1, bvalid appearing in an idle beat → discard + set stuck (§5.2/§5.5) |
| 5. Lock and violations | `w_done` internal RTL state; released at `b_fire && w_done`; `b_fire && !w_done` → do not release, set stuck; if W arrives late, release at the w_done beat; if W never arrives, hold until reset (§5.2) |
| 6. Watchdog | 4096 beats without M-port handshake progress (only W data / B response handshakes count as progress) → sticky `dbg_stuck` (§5.6) |
| 7. dbg | dbg_stuck + per-port txn/beat counters (§7) |
| 8. Reset | §6 always-in-reset policy; latches/counters/valid_reg all reset |

**Completion criteria**: verible-syntax check_verilog_syntax 0 errors + clean lint; ≤400 lines; V2001 synthesizable subset; all combinational always blocks have defaults (no latch).

### S2 Implement sim/axi_wr_arb_tb.sv

| Action | Key points |
|---|---|
| 1. Dual programmable master BFM | aw/w independently programmable: awlen ∈ {63, 55, 31, 27} (§4.1 cam0/cam1 presets), beat spacing, WVALID arriving 0/1/3/5 beats early (T9), **BFM built-in valid-hold self-check** (reports an error on DA1 violation, as a safety net) |
| 2. Memory slave + scoreboard | 512b model memory, AW/W collected in order and compared against the pattern; B response delay programmable 0~5000 beats (covers both T10 boundaries) |
| 3. SVA A1-A10 | All write-side assertions apply (including A9 `b_fire \|-> w_done`); hierarchical reference into RTL (Q3 decision: SVA stays out of .v) |
| 4. Test scheduling | T1-T11 all write-side applicable (§3 matrix); each test prints PASS/FAIL at the end + counter SUMMARY |

**Completion criteria**: vlog 0 Errors; vsim runs all tests in a single command with all PASS, 0 assertion firings, 0 scoreboard errors.

### S3 Implement rtl/axi_rd_arb.v

Structure identical to S1; differences:

- AR/R channels; read lock released at M-port RLAST handshake (§5.2), no W/B/w_done;
- R is a **1:2 demux**: `s{gnt}_rready = !valid_reg \|\| m_rready` (m_rready is a master-driven input, only sampled), `m_rvalid = valid_reg`, rresp/rid registered in the same beat as rdata (§5.3/§5.5);
- Watchdog progress = R data handshake (RLAST handshake release means completion, §5.6);
- Idle-beat m_rready=1 + idle rvalid violation detection (§5.2).

**Completion criteria**: same as S1.

### S4 Implement sim/axi_rd_arb_tb.sv

Structure identical to S2; differences:

- A9 not applicable (no B); A1-A8, A10 applicable;
- T10 boundary injection changed to holding off m_rready / delaying RLAST;
- T11 covers both directions: write-side wready arriving late (P0 original scenario) + read-side **m_rready late-arrival dual** (P0's same-type risk in the demux direction).

**Completion criteria**: same as S2.

### S5 Static cross-check review (results recorded in the delivery report; passes without code changes)

- §4.1/§4.2 interface tables checked signal by signal (name/width/direction);
- §5.3 three-channel formulas checked item by item against RTL assignments (including the `!valid_reg` term, same-beat load priority);
- §8 non-goal overreach check: no burst merging/splitting, no multi-outstanding, no address decoding, no ID tracking;
- Hard-discipline items: 33-bit pass-through unspliced, awqos=1 pass-through, reset tie-break comment in place.

### S6 Handoff and integration linkage

- S1-S5 all green → **unit verification frozen**; report: per-test beat/txn counters, 0 assertion firings, line counts of both RTL files;
- Handoff to task 2 phase 3 (write side into top_cam → tb_phase4 P4C unbroken); a separate `axi_rd_cdc` detailed-design review before phase 4 starts.

## 3. Verification Matrix

**T tests × applicability on both sides** (full criteria in arbiter.md §9):

| Test | wr_tb | rd_tb | Differences between the two sides |
|---|---|---|---|
| T1 single-port baseline | ✓ | ✓ | Latency measurement points: write = BVALID−AWVALID; read = first-beat RVALID−ARVALID |
| T2 dual-port contention RR alternation | ✓ | ✓ | — |
| T3 random backpressure | ✓ | ✓ | Write = hold off wready; read = hold off rready |
| T4 worst-case interleave | ✓ | ✓ | Write = cam1 burst wedged between two cam0 bursts; read = AR interleaving |
| T5 response routing | ✓ (bid) | ✓ (rid) | — |
| T6 long/short transaction bandwidth accounting | ✓ | ✓ | — |
| T7 reset first contention grants S1 | ✓ | ✓ | — |
| T8 handshake 1:1 (A6) | ✓ | ✓ | — |
| T9 W early arrival | ✓ | — | The read side has no independent data-request channel; the early-arrival scenario is covered on the read side by T11 |
| T10 watchdog dual boundary | ✓ (B delay) | ✓ (RLAST delay) | — |
| T11 WVALID-first / P0 special test | ✓ | ✓ | Read side is the m_rready late-arrival dual |

**Assertion applicability**: A1-A8, A10 shared by both sides; A9 write side only.

## 4. Toolchain and Acceptance Flow (applied uniformly at every step)

1. **verible-syntax MCP**: `check_verilog_syntax` → `check_verilog_lint` (both .v and .sv checked); 0 errors required before compiling;
2. **vlog** (in sim/, QuestaSim 2024.2): `vlog ../rtl/axi_wr_arb.v ../sim/axi_wr_arb_tb.sv`, criterion **0 Errors**;
3. **vsim**: `vsim -c axi_wr_arb_tb -do "run -all; quit -f"`, criteria = all tests PASS + 0 assertion firings + 0 scoreboard errors.

Integration phase additionally follows the existing tb_phase4 procedure (including the `ddr_ctrl_model/` model); not expanded in this plan.

## 5. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Combinational ready-mask path fMAX (ds-P2-5) | RTL mask path stays purely combinational with no intermediate registers; fMAX left to phase 3 efx_map measurement, not pre-set in this plan |
| DA1 (master valid-hold) assumption violated | RTL does not tolerate it; TB-side BFM valid-hold self-check reports as a safety net (§5.3) |
| Watchdog 4096 threshold margin insufficient | T10 dual-boundary tests; re-derive during integration per TJ UG response parameters (§5.6 already notes config changes require re-derivation) |
| RR1 alternation / reset-bias-to-S1 "optimized" by later maintainers | T2/T7 criteria pinned + RTL comment declaring "intentionally arranged" (§5.1) |
| Half-buffer same-beat clear/load implementation drifts (v1.2 P0 recurrence) | T11 bidirectional special test + S5 static item-by-item check against §5.3 |

## 6. Review and Execution Conventions

- This plan is executed per S1→S6 **after review passes**; each step reports its criteria result on completion without waiting for step-by-step confirmation; **S4 all green = unit verification frozen**, one consolidated report before entering integration (phase 3);
- If tests need to be added/removed or criteria changed during execution, modify this plan first with justification, then touch RTL/TB;
- Changes to the plan itself are recorded in the change log below.

## 7. Change Log

| Version | Date | Description |
|---|---|---|
| v1.0 | 2026-10-23 | Initial draft, awaiting user review |
