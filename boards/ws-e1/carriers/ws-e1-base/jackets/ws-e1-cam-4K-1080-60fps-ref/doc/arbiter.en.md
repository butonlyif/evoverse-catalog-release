[中文](arbiter.md) | English

# AXI Dual-Master Shared DDR Port Arbiter Design Specification (axi_wr_arb / axi_rd_arb)

| Item | Value |
|---|---|
| Version | **v1.2** (v1.1 absorbed the two reviews kimi3/ds; v1.2 fixed P0×1/P1×3/P2×4 found during user re-review, see §12) |
| Date | 2026-10-23 |
| Related | [cam1-ddr-replay-plan.md](cam1-ddr-replay-plan.md) §2, [ddr_interface.md](ddr_interface.md), [ddr-dram-controller-tj-ug-v3.0.md](ddr-dram-controller-tj-ug-v3.0.md) (the TJ UG, DDR controller manual), review documents [kimi3-arb-feedback.md](kimi3-arb-feedback.md) / [ds-arb-feedback.md](ds-arb-feedback.md) |
| Status | **Frozen** (v1.2, user-confirmed 2026-10-23); implementation verification plan in [arbiter-impl-plan.md](arbiter-impl-plan.md); Q1~Q4 closed (§10) |

---

## 1. Background and Decision

The original plan used the Efinity AXI Interconnect IP for dual-port DDR sharing. After evaluation it was abandoned in favor of an in-house design:

1. The IP's internal implementation is opaque; 512b + 2-to-1 is a non-default configuration, and **the vendor has only validated the default parameters** (UG v1.8 L427/L468);
2. Restricted parameters: the wizard only offers 32/64 options for ADDR; the Slave/Master direction defaults are inverted (1/2), which is error-prone;
3. The requirement is extremely narrow: **constant 2→1, AXI4, 512b, single destination, no decoding** — essentially a "transaction-level 2-to-1 mux with RR arbitration"; an in-house design gives fully controllable semantics with built-in diagnostics.

Decision record: on 2026-10-23 the user decided to drop the IP and build in-house; the arbitration policy was set to **Round Robin** (fixed priority abandoned).

**Relationship with the DDR hard-core built-in arbiter (decision record, kimi3-B4)**: the hard core has its own dual-interface RR arbiter (Features/Arbiter chapters of [ddr-dram-controller-tj-ug-v3.0.md](ddr-dram-controller-tj-ug-v3.0.md); "TJ UG" is the name of that DDR controller manual, not a part-number typo). This topology aggregates write traffic to target0 and read traffic to target1 — **each target is permanently owned by a single external arbiter, so the hard-core built-in arbitration degenerates to pass-through**. Benefits and costs:

1. Read/write parallelism is preserved (writes to target0 / reads from target1, independent read/write queues inside the hard core);
2. One "virtual master" per target, predictable behavior: the `ARB_*` parameters (`ARB_GRANT_INTERVAL` etc.) in the behavioral model and the dual-interface arbitration measured items in the ddr_ctrl_model test spec **do not apply to the final system**; they only matter for self-testing this arbiter (which also shrinks the model-validation scope);
3. Cost: a single target loses multi-master merging capability; the single-port peak becomes the hard ceiling — this design's utilization is <30% (§5.4), so no impact.

## 2. Scope and Instantiation

| Instance | Module | Clock | Upstream (S ports) | Downstream (M port) |
|---|---|---|---|---|
| Write side | `axi_wr_arb` (rtl/axi_wr_arb.v) | sys_clk_200m | S1=cam0_fw, S0=cam1_fw (AW/W/B each) | DDR target0 write port |
| Read side | `axi_rd_arb` (rtl/axi_rd_arb.v) | pixel_clk 148.5M | S1=cam0_rd, S0=cam1_rd via `axi_rd_cdc` (AR/R each) | DDR target1 read port |

- **Clock-domain statement (ds-P1-2; v1.2 re-review P2-4 evidence-based wording)**: cam0_fw `aclk = sys_clk_200m` — RTL evidence: top_cam_demo.sv instantiates `u_fw` with `.aclk(sys_clk_200m)` (comment "same clock as the raw source, v2 zero CDC"). cam1_fw is a new instance added in phase 5 (currently u_cam_1 has no frame_writer); the design commits to the same `sys_clk_200m` (u_cam_1 already has this clock input, camera_path is isomorphic) — **write side zero CDC**; on the read side cam1_rd is in the 37.125M domain and enters via axi_rd_cdc.
- S-port numbering equals bit numbering: S1=cam0 (bit1), S0=cam1 (bit0). The two modules are structurally identical with different channels; each is an independent small module.
- `axi_rd_cdc` (dual async FIFO for AR/R, 37.125M→148.5M) gets its own detailed design; this spec only defines the contract (§4.3).

## 3. Overall Architecture

```
s1(AW/W/B) ──┐            ┌────────────────────────────────────┐
             ├────────────┤ RR1 grant latch (transaction lock) │
s0(AW/W/B) ──┤            │ payload half-buffer regs + 2:1 mux ├── m(AW/W/B) → DDR port
             └────────────┤ responses returned per gnt         │
                          └────────────────────────────────────┘
   Rule: once granted, lock until the transaction fully completes on the M port
   (write = B handshake with W already done; read = RLAST handshake);
   no second transaction issued while locked; 1 idle beat of re-arbitration between transactions
```

Core trade-off: **transaction-level locking + single outstanding per arbiter**. No address-first / multi-outstanding — in exchange: no reordering, no ID tracking, zero lookup for response routing.

## 4. Interface Definition

Naming follows project convention: `sN_<chan>_<sig>` (N=0/1), M port `m_<chan>_<sig>`. Widths are localparam constants.

### 4.1 axi_wr_arb (write side, 200M)

| Direction | Signals (sN_ per group) | Width | Description |
|---|---|---|---|
| i/o | awvalid / awready | 1 | awready is the **DDR→master combinational masked return** (§5.3); master guarantees valid hold |
| i | awaddr | 33 | 33-bit pass-through as-is (bit32 of both masters is always 0 in this project; **the arbiter does no splicing/truncation**) |
| i | awlen / awsize / awburst | 8 / 3 / 2 | Burst parameters registered with payload (cam0 awlen codes 63/55 = 64/56 beats, cam1 31/27 = 32/28 beats; awsize=110, INCR) |
| i | awid | 6 | Registered with payload (both masters always 0) |
| i | awqos / awcache / awlock | 4 / 4 / 1 | Registered with payload (**awqos=1 must reach the DDR**, write contract) |
| i/o | wvalid / wready | 1 | |
| i | wdata / wstrb / wlast | 512 / 64 / 1 | Half-buffer registered (wstrb in the same beat as wdata, §5.3) |
| o/i | bvalid / bready | 1 | B returned per gnt (§5.5) |
| o | bresp / bid | 2 / 6 | Pass-through |
| i | clk, rstn | 1 | Normally out of reset (§6) |
| o | dbg | see §7 | Diagnostics |

### 4.2 axi_rd_arb (read side, 148.5M)

Isomorphic: AR channel (arvalid/araddr[32:0]/arlen/arsize/arburst/arid[5:0]/arqos/arcache/arlock) registered with payload; R channel (rvalid/rdata[511:0]/rresp/rlast/rid[5:0]) is a **1:2 demux + half buffer** (direction M→S, P2-4).

### 4.3 axi_rd_cdc contract (detailed design elsewhere)

- Input: cam1_rd's AXI4 read master (37.125M); output: an AXI4 read slave interface (148.5M) wired to axi_rd_arb S0.
- AR command FIFO (37→148) payload = araddr33 + arlen8 + arsize3 + arburst2 + arid6 + arqos4 + arcache4 + arlock1 = **61b** (+valid); R response FIFO (148→37) payload = rdata512 + rresp2 + rlast1 + rid6 = **521b** (ds-P2-1 verified values). Gray pointers, depth 4, modeled after ddr_async_fifo.
- **Explicit backpressure-chain assumption (kimi3-M1)**: the hard core's R channel satisfies AXI valid-hold (guaranteed by the AXI spec); when the CDC FIFO is full, backpressure propagates all the way to the hard core's read data queue (depth ≥16), no data loss. Scenarios where the lock is thereby extended are counted in §5.4 worst-case waiting.

## 5. Functional Specification

### 5.1 Arbitration policy (RR1, 2 ports = strict alternation)

- **Request definition (ds-P1-1)**: `req[N] = sN_awvalid` (write) / `sN_arvalid` (read). wvalid is not required to be present — W data may arrive after lock (AXI4 allows W before/after AW), covered by the forwarding semantics during lock (§5.3).
- State `last` (last served port). Idle-beat sampling: if `req[~last]` grant `~last`; else if `req[last]` grant `last`; else idle. When both ports request simultaneously the grant must flip (strict alternation, no starvation).
- **Reset-value tie-break (kimi3-M3, intentional)**: at reset `last=0` → the first contention grants S1=cam0 — cam0 is the main path, and biasing the first contention to cam0 is design intent; fixed by comments and the T7 criterion to prevent later "correction".
- On the transaction-completion beat `last <= grant`; re-arbitration begins in the same beat (next grant earliest +1 beat, 1 idle beat between transactions).

**Pipeline timing (ds-P1-7, total latency per this table)**:

```
beat0: idle sampling of req, grant latch + payload capture (req = s_awvalid/arvalid, latched in the same beat)
beat1: m_awvalid/arvalid=1 (valid-hold, held until the m handshake); s_ready = gnt & (!valid_reg | m_ready) combinational return (§5.3 v1.2 formula)
beat2+: DDR-side handshake; master view of handshake completion (at most 1~2 beats later than direct connection, depending on DDR ready timing)
     W/R data channels half-buffer-forward isomorphically during the lock, +1 more beat
```

Inherent overhead: address-channel M-port valid +1 beat (master handshake completes at most +2 beats); data +1 beat; +1 idle beat between transactions. The T1 criterion "latency ≤ direct connection +3 beats" is self-consistent with this (measurement-point definitions in §9).

### 5.2 Transaction Locking

- **Write lock**: from the grant beat until `b_fire && w_done`. `w_done` is an internal RTL state set by the M port's `m_wvalid && m_wready && m_wlast` (**ds-P1-4: violation detection goes into RTL, not only the TB**). If `b_fire && !w_done` (B completes before W, contract violation) → do not release, set `dbg_stuck` (explicit exposure, preventing silent data corruption). **Lock lifetime after violation (v1.2 re-review P1-1)**: W data arriving late → the lock releases on the beat `w_done` sets (`b_fire` already holds, so `b_fire && w_done` is satisfied that beat); W never arrives → lock holds until reset (manual intervention), watchdog continuously sets `dbg_stuck`. No automatic recovery/retry.
- **Read lock**: from the grant beat until the M port's `rvalid && rready && rlast` handshake completes.
- **Address-channel behavior during lock (kimi3-B2, semantics A; signal direction corrected)**: during the lock the M port **issues only this one address handshake for the current transaction** — after the payload register clears (m handshake), `m_awvalid/m_arvalid` stay 0 until the lock releases. Note: `m_awready/m_arready` are DDR-driven inputs and cannot be gated; this design implements single-outstanding by "never issuing a second valid" (kimi's original text "m_awready=0" was a direction typo; adopted per the intent of its semantics A with the correction).
- Non-granted port during lock: all s ready held 0, b/r responses to it held 0 (A4).
- **Idle-beat responses (ds-P1-5 corrected adoption)**: in idle beats `m_bready/m_rready = 1` (rationale: don't wedge the DDR port). Based on the contract "transaction-level locking guarantees no responses during idle", any `m_bvalid/m_rvalid` in an idle beat is a DDR-side contract violation → response dropped + `dbg_stuck` set (not silent). Assertion A8 covers this.

### 5.3 Data Path (unified half-buffer rule, isomorphic across all three channels; v1.2 fixes the ready formula — re-review P0)

Each channel has one level of **payload+valid register (1-deep buffer, no source pass-through)**, four rules:

1. **Load = source-side handshake** (`s_valid && s_ready`, latch payload and set `valid_reg` in the same beat);
2. **Clear = sink-side handshake** (m side or s side, per channel direction); when clear and load coincide in one beat, **load wins** (keeps the pipeline full without gaps);
3. **Source-side ready (granted port only) = `!valid_reg || sink ready`** (combinational return) — when the register is empty, accept without waiting for sink ready (prefetch); when full, the sink must vacate in the same beat, otherwise ready=0 makes the master wait (master guarantees valid hold — design assumption DA1, backed by the TB);
4. **Sink-side valid = `valid_reg`** (registered output; once set, holds until the sink handshake with payload unchanged).

Expanded per channel:

- Address/W (source=master, sink=DDR): `sN_ready = gnt_match && (!valid_reg || m_ready)`; `m_awvalid/m_wvalid = valid_reg`;
- R (source=DDR, sink=master, 1:2 demux): `s{gnt}_rready = !valid_reg || m_rready`; `m_rvalid = valid_reg` (`m_rready` is a master-driven input, can only be sampled, never generated — v1.2 corrected per signal direction).

**Why the ready formula must contain the `!valid_reg` term (v1.2 re-review P0, prevents beat duplication)**: this project's DDR uses a WVALID-first contract (it raises `m_wready` only after seeing `m_wvalid`, see [ddr_interface.md](ddr_interface.md)). With the v1.1 formula (`gnt && m_ready`) lacking that term: beat0 register empty prefetches beat1; beat1 `m_wready` is raised → S and M handshake in the same beat, and "load on sink handshake in the same beat" would load the master's **not-yet-advanced old beat1 again** — beat1 transmitted twice on the M port, breaking 1:1 conservation (A6). After the fix, each beat loads exactly once. Walkthrough (WVALID-first, steady state 1 beat/beat):

| Beat | s_wvalid | Register | m_wvalid | m_wready | s_ready | S handshake | M handshake | Load |
|---|---|---|---|---|---|---|---|---|
| 0 | beat1 | empty | 0 | 0 | 1 (`!valid_reg`) | beat1 | — | beat1 |
| 1 | beat2 | beat1 | 1 | 1 | 1 | beat2 | beat1 | beat2 |
| 2 | beat3 | beat2 | 1 | 1 | 1 | beat3 | beat2 | beat3 |

The same holds for always-high `m_ready` (combinational ready arriving early) — the v1.1 formula was only accidentally correct under that timing; the v1.2 formula is correct under both. T11 pins this scenario.

Consequently satisfied (truly holds only under the v1.2 formula):

- **valid-hold (kimi3-B1)**: `m_*valid = valid_reg` registered output, naturally holds until the sink handshake, payload never refreshes with the source beat by beat;
- **W gating invariant (kimi3-B3)**: outside the lock `valid_reg` is forced to 0 → `m_wvalid/m_awvalid/m_arvalid` held 0; early WVALID from an ungranted port never appears on the M port (A8);
- **Handshake 1:1**: each master-side handshake ↔ exactly one M-side handshake (A6); steady-state full pipeline 1 beat/beat, first beat carries 1 extra beat of buffer delay (the §5.4 "data +1 beat");
- **No deadlock**: when the register is empty the source side doesn't wait for sink ready — m_valid appears first, the DDR raises ready per contract; no deadlock under any DDR ready timing.

Direction distinction (ds-P2-4): write side W = 2:1 **mux**; read side R = 1:2 **demux**. `wstrb` is registered in the same beat as `wdata`; on the R side `rresp/rid` are registered in the same beat as `rdata`.

### 5.4 Latency and Throughput Budget

| Item | Write side @200M | Read side @148.5M |
|---|---|---|
| cam0 per-line transactions | 2 bursts (64+56 beats) + overhead ≈ 128 beats | same 128 beats |
| cam0 line period / utilization | 960 beats / **13.3%** | 1100 beats / **11.6%** |
| cam1 per-line transactions | 2 bursts (32+28) ≈ 68 beats | same 68 beats |
| cam1 line period / utilization | 480 beats / 14.2% | 2200 ticks¹ / 3.1% |
| Total utilization | **< 30%** | **< 15%** |
| Worst-case contention wait (cam0 view) | ≤ cam1 single transaction ≈ 70 beats = 350ns | ≤ 70 beats = 470ns = **6.4% of line period** |
| Inherent overhead | address +1~2 beats, data +1 beat, +1 idle beat between transactions | same |

¹ tick = 37.125M-domain beat (550 ticks/line); conversion basis in ddr_interface.md.

The worst-case wait budget **includes the CDC-full backpressure scenario** (kimi3-M1): when cam1 R data is backpressured by the hard core due to a full CDC FIFO, the read lock lengthens; the "≤70 beats" row above already covers it by the per-transaction beat-count ceiling (cam1 single transaction ≤ 32+28+overhead ≈ 70 beats; backpressure only lengthens that transaction). The read-side worst 470ns is ample versus the ANCHOR_WAIT margin (c3h measured grant+first-word ~0.2 line = 220 ticks); phase 4 unit TB measures the first-word latency distribution for re-check (measurement point: read = first RVALID beat − ARVALID).

### 5.5 Signal Handling Summary (rewritten in v1.1, aligned with §5.3 — ds-P0-1)

| Signals | Handling |
|---|---|
| AW full payload: awaddr/awlen/awsize/awburst/awid/awqos/awcache/awlock | **Half-buffer register** (latched in the same beat as valid, valid-hold) |
| AR full payload: araddr/arlen/arsize/arburst/arid/arqos/arcache/arlock | same as above |
| W full payload: wdata/wstrb/wlast | half-buffer register 2:1 mux (+1 beat) |
| R full payload: rdata/rresp/rlast/rid | half-buffer register 1:2 demux (+1 beat, M→S) |
| bresp/bid | **combinational mux by gnt** (covers the entire B within the lock, no release race) |

**Why there is no cur_owner register (partial-adoption note on kimi3-M5)**: kimi suggested "when B/R come back, the grant may already be released, so ownership must be latched". This design's lock semantics guarantee that when the B handshake (read: RLAST handshake) occurs, the grant is still valid — the release beat is exactly that handshake beat, same-beat routing is still correct, and gnt clears only the next beat. So gnt itself is the ownership register; cur_owner is unnecessary. If a later change introduces "late-response release", this item must be re-examined.

### 5.6 Watchdog

- **Progress definition (ds-P1-6)**: `beat_progress` clears only on beats with **actual M-port handshakes** — W/R data handshakes or B/R response handshakes. A pending source-side valid does not count as progress.
- In lock for >4096 beats without progress → set sticky `dbg_stuck`, no automatic unlock (explicit exposure of contract breakage).
- **Threshold basis (kimi3-M4)**: longest transaction ≈128 beats × DDR max response latency (tens of ctrl_clk) × safety factor >10, rounded to a power of 2 = 4096. Must be re-derived when DDR frequency/configuration changes.
- Additional violation detections (§5.2): `b_fire && !w_done` and idle-beat responses (§5.2) both set `dbg_stuck` directly.

## 6. Reset Policy (rewritten per kimi3-M2)

`rstn` is driven exactly once by the **power-on initialization reset tree** (write = sys_clk_200m reset tree, read = tx_pixel_clk reset tree, active-low asynchronous); **never re-asserted during operation (including source switching, flush, DIAG reset)** — echoing hard rule #1 (writer/reader AXI ports never reset): the arbiter sits between the two masters and the DDR ports, and any runtime reset would sever in-flight transactions. On source switching, the master-side flush chain guarantees action only after drain reaches idle; the arbiter need not be aware.

If a master valid happens to be high on the reset-release beat (possible during power-on boot), it is handled normally by §5.1 idle sampling, no special case; T7 covers "reset release coinciding with the first request".

Reset values: grant empty, last=0, all output valid/ready 0, counters and sticky cleared.

## 7. Diagnostics (Q4 final decision: add per-port beat counters)

```
dbg = { gnt_active, gnt[1:0] (one-hot, ds-P2-2), lock (this module's lock flag),
        watchdog_stuck (sticky),
        txn_cnt[1:0]  completed transactions per port (16bit saturating),
        beat_cnt[1:0] completed beats per port (16bit saturating; write = W data handshake, read = R data handshake) }
```

- Beat counters detect **partial-completion** contract breakage (W stream breaking mid-burst without watchdog timeout, R short of beats) — consistent with the "explicit exposure of contract breakage" philosophy (consensus of both reviews).
- Healthy reading: steady-state gnt alternation, stuck=0, txn/beat growth rates reconciled against frame rate × beats per line (T6 uses the same accounting).

## 8. Non-Goals

Address decoding/multi-destination, AXI3 (WID), AXI4-Lite bridging, multi-outstanding, out-of-order responses, bandwidth QoS, misorder reordering, width conversion, **burst merging/splitting** (kimi3-Minor5, preventing scope creep). Each RTL file ≤ 400 lines (raised in v1.1: half-buffer payload registers add implementation volume).

## 9. Verification Plan

Unit TBs (sim/axi_wr_arb_tb.sv, sim/axi_rd_arb_tb.sv; 2 programmable master BFMs + a 512b memory slave scoreboard; **the RTL is pure Verilog-2001 `.v`, all SVA placed in the TB `.sv` hierarchy references** — Q3 final decision):

| Case | Content | Criterion |
|---|---|---|
| T1 | Single-port baseline (cam0 traffic only) | scoreboard 0 errors; latency ≤ direct connection +3 beats (write = BVALID−AWVALID; read = first RVALID beat − ARVALID) |
| T2 | Dual-port concurrent contention | RR strict alternation (A5); both scoreboards 0 errors |
| T3 | Random backpressure (DDR wready/rready randomly deasserted) | no deadlock; watchdog not triggered |
| T4 | Worst interleaving (cam1 burst wedged between cam0's two bursts) | burst atomicity (A2); scoreboard 0 errors |
| T5 | Response routing | all bid/rid ownership correct |
| T6 | Mixed long/short transaction bandwidth accounting | txn/beat counter readouts = expected values |
| T7 | First contention after reset (including reset release coinciding with the first request) | first contention must grant S1=cam0 (§5.1 reset tie-break) |
| T8 | Handshake consistency | master-side handshake count == M-side handshake count (A6) |
| T9 | **W early arrival (kimi3-B3)** | randomly raise WVALID on the ungranted port 1/3/5 beats before grant: no W leak on the M port before grant (A8); after grant data is 1:1 without duplication (A6) |
| T10 | **Watchdog boundary (kimi3-B4/M4)** | inject DDR B delays slightly below/above 4096 beats | no trigger below threshold, sticky triggered above; after trigger no auto-unlock, counters readable |
| T11 | **WVALID-first timing special case (v1.2 re-review P0)** | m_wready held 0 before m_wvalid asserts (this project's DDR contract); construct a continuous S/M same-beat handshake stream | scoreboard 0 errors; no beat duplication/loss (A6); steady state 1 beat/beat |

SVA assertion list (renumbered in v1.1):

| # | Assertion |
|---|---|
| A1 | M-port payload always belongs to the currently granted port |
| A2 | Bursts of the two ports have zero overlap on the M port (lock semantics) |
| A3 | Per-port B/R count == its completed AW/AR count (no leaks) |
| A4 | During lock, non-granted port s ready / b·r responses held 0 |
| A5 | Successive contentions flip the grant (RR) |
| A6 | Handshake 1:1 conservation |
| A7 | valid-hold: `m_*valid && !m_*ready` → next beat valid holds and payload unchanged (kimi3-B1) |
| A8 | Outside lock, M-port aw/w/ar valid held 0; no b/r responses in idle beats (violation → dbg_stuck) |
| A9 | `b_fire |-> w_done` (ds-P1-4; also detected inside the RTL, §5.2) |
| A10 | During lock, gnt/ownership stable (kimi3-A9) |

Integration gates: phase 3 write side into tb_phase4 → P4C unbroken; phase 4 read side into the chain → P4C unbroken + cam1 CDC unit loopback. Flow: verible-syntax → vlog 0 Error → vsim criteria. **DDR behavioral-model convention**: wherever a DDR controller simulation model is needed (integration regression, arbiter timing reproduction), uniformly use the model in the `ddr_ctrl_model/` directory (behavior aligned to the TJ UG, with ARB_* parameters and a regress system); do not build another model.

## 10. Open Questions → Closed

Q1~Q4 were closed with consistent positions from both reviews: **Q1** transaction-level locking + single outstanding (the only mode; the address channel issues no second transaction during lock); **Q2** address/W/R full payload registered (half buffer, §5.3); **Q3** `axi_wr_arb.v`/`axi_rd_arb.v` pure Verilog-2001, all SVA in the TB; **Q4** dbg adds per-port beat counters (§7).

## 11. Resource and Timing Estimates (corrected in v1.1 — ds-P0-2)

| Item | Estimate | Basis |
|---|---|---|
| Write side axi_wr_arb | ~750 LUT / ~750 FF | W payload 577b (512+64+1) + AW 62b + B 8b + FSM/counters ~100 |
| Read side axi_rd_arb | ~700 LUT / ~700 FF | R payload 521b + AR 62b + FSM/counters ~100 (read side has no B channel; v1.2 re-review P1-2 removed the typo) |
| axi_rd_cdc | ~150 LUT; R FIFO in BRAM (521b×4, roughly 8~15 20Kb blocks depending on width mode); AR FIFO (61b×4) distributed RAM or FF | v1.2 re-review P1-3: an FF-based R FIFO would need thousands of FFs, more than the two arbiter bodies combined; phase 4 detailed design finalizes |
| **Total** | **~1.6k LUT / ~1.6k FF**; arbiter bodies 0 BRAM | Efinix LUT4 2:1 mux ≈ 1 LUT/bit, no compression headroom |

Timing: targets 200M/148.5M with margin; the `m_awready → s_awready` combinational masked path is the potential critical path; the fMAX ceiling defers to phase 3 efx_map measurements (ds-P2-5, no 300M presupposition).

## 12. Review Comment Handling Record

| Source | Item | Handling |
|---|---|---|
| kimi3 | B1 valid hold semantics | adopted → §5.3 half-buffer rules + A7 |
| kimi3 | B2 address channel of the granted port during lock | adopted semantics A; **signal direction corrected** (m_awready is a DDR input and cannot be gated; implemented as "no second valid issued during lock") → §5.2 |
| kimi3 | B3 W early-arrival gating | adopted → §5.3 invariant + A8 + T9 |
| kimi3 | B4 hard-core built-in arbiter pass-through decision | adopted → §1 decision record, with the model-validation scope shrunk accordingly |
| kimi3 | M1 CDC backpressure assumption | adopted → §4.3 + §5.4 |
| kimi3 | M2 reset wording contradiction | adopted → §6 rewritten |
| kimi3 | M3 reset tie-break pinned | adopted (intentional) → §5.1 + T7 |
| kimi3 | M4 watchdog threshold basis | adopted → §5.6 |
| kimi3 | M5 cur_owner | **partially adopted**: contradictory wording fixed; cur_owner not needed — lock semantics keep gnt valid through the response period, rationale in §5.5 |
| kimi3 | Minor1-5 / T9 T10 / Q1-4 positions | all adopted (awlen encoding footnote, tick footnote, T1 measurement points, resources include CDC, §8 adds the burst-merge prohibition) |
| ds | P0-1 §5.5 vs §5.3 contradiction | adopted → §5.5 rewritten (address/W/R full payload registered, bresp/bid combinational by gnt) |
| ds | P0-2 resource underestimate | adopted → §11 recomputed (~1.6k LUT total) |
| ds | P1-1 req definition | adopted → §5.1 (req = awvalid/arvalid, W may arrive late) |
| ds | P1-2 cam1_fw clock domain | adopted → §2 (both cameras' raw domain is sys_clk_200m, write side zero CDC) |
| ds | P1-3 data-path backpressure | adopted → §5.3 (half-buffer load/clear/ready made explicit; v1.2 re-review further corrected the ready formula, see below) |
| ds | P1-4 w_done protection | adopted and strengthened: internal RTL state + violation sets stuck, not only the TB → §5.2/§5.6 + A9 |
| ds | P1-5 idle bready logic | **partially adopted**: idle bready=1 kept (don't wedge the DDR port), but A8 violation detection added → response dropped + stuck set, not silent |
| ds | P1-6 progress definition | adopted → §5.6 (only M-port handshake beats count as progress) |
| ds | P1-7 pipeline beat-count ambiguity | adopted → §5.1 pipeline sketch (address M port +1 beat, master completion at most +2 beats) |
| ds | P2-1~P2-5 | all adopted (CDC 61b/521b, gnt one-hot, beat counters, demux wording, bit32 wording unified/id register alignment/T7 made explicit/300M presupposition withdrawn) |
| User re-review (after v1.1) | P0 ready formula missing the `!valid_reg` term | adopted → §5.3 rewritten: load = S handshake, ready = `!valid_reg \|\| sink ready`, same-beat load takes priority over clear; R row corrected per signal direction to generate `s{gnt}_rready` (m_rready is a master input and cannot be generated); T11 added |
| User re-review (after v1.1) | P1-1 post-violation lock lifetime unspecified | adopted → §5.2 (release as soon as w_done arrives late; W never arriving holds until reset, watchdog stuck) |
| User re-review (after v1.1) | P1-2 read-side "B 8b" typo | adopted → §11 removed (read side has no B channel) |
| User re-review (after v1.1) | P1-3 CDC R FIFO storage medium ambiguous | adopted → §11 (R FIFO in BRAM roughly 8~15 blocks, AR FIFO distributed RAM/FF) |
| User re-review (after v1.1) | P2-1 "TJ UG" reference unclear | clarified and corrected: "TJ UG" is not a part-number typo; it is [ddr-dram-controller-tj-ug-v3.0.md](ddr-dram-controller-tj-ug-v3.0.md) (the DDR controller manual) → §1 links the document directly; the previous version of this row, "changed to the Titanium Ti180 device UG", was a misjudgment and has been withdrawn |
| User re-review (after v1.1) | P2-2 T10 table column misalignment | adopted → §9 table corrected |
| User re-review (after v1.1) | P2-3 "clt"→"clr" | adopted → wording corrected in this table |
| User re-review (after v1.1) | P2-4 cam1_fw clock-domain statement depended on instantiation | adopted → §2 (cam0 stated with RTL evidence; cam1_fw does not exist yet, reworded as a phase 5 design commitment) |

## 13. Change Log

| Version | Date | Description |
|---|---|---|
| v1.0 | 2026-10-23 | Initial draft |
| v1.1 | 2026-10-23 | Absorbed the two reviews kimi3/ds: unified half-buffer rules, locked-period address-channel semantics, w_done violation detection, resource recomputation, assertion/case expansion (A1-A10/T1-T10), Q1-Q4 closed |
| v1.2 | 2026-10-23 | Fixed P0 found in the v1.1 re-review: §5.3 ready formula adds the `!valid_reg` term, load reworded as "S handshake" (prevents beat duplication under WVALID-first timing); P1×3 (post-violation lock lifetime, read-side B 8b typo, CDC storage medium); P2×4 (TJ UG reference re-linked to ddr-dram-controller-tj-ug-v3.0.md, T10 table, clt typo, evidence-based clock-domain wording); T11 added |
