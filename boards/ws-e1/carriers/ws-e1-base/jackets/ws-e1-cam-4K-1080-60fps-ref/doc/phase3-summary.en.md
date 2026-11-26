[中文](phase3-summary.md) | English

# Phase 3 Summary — disp_timing v2 + tx_line_buf + Full-Chain TB (writer→DDR→reader→TX)

> Status: **Completed and accepted (2026-10-21)** · Spec: SPEC-001 mod-disp-timing / mod-tx-line-buf · Verification level: FPGA_INTEGRATION (roles: main-flow / display-timing) · Final regression: unit TB `[DT-OK]` (864000 beats, zero errors) + full-chain TB `[FC-OK]` (6 display frames, fingerprint zero errors)

## 1. Goal

Complete the tail of the display domain: **disp_timing v2** (the single source of display timing: a local h/v FSM + a line-start gate + the D8 TX contract, with line_tick feeding back to frame_reader from the same source) and **tx_line_buf** (aggregating the ISP 64b beat stream 8:1 into a 512b BRAM / 64b pull + level gating), and for the first time establish end-to-end fingerprint verification of writer→DDR→reader→display TX through a **full-chain TB**.

## 2. RTL deliverables (newly created; the v1 leftover modules are untouched)

### 2.1 rtl/tx_line_buf.v

- The write side is AXIS-64 (960 beats per line) aggregated 8:1 into a 512b write BRAM (256×512b ≈ 2.1 lines); the read side is a 64b beat + level (in 64b word units) for gating; both sides share CLK-DISP148 (pointer pass-through, so no Gray structure is needed).
- The read pipeline has a 2-cycle latency (address register → BRAM synchronous read → 64b channel mux select), and **the three stages must stay in lockstep** — a lane registered only once gets overwritten by the next emission, rotating the channel within a group by 1 (proven by the TB, then changed to register the lane twice within the same line).
- Overflow protection: when full, the whole group (8 beats) is dropped and starve_events++ is issued; the pointers are 12 bits (to distinguish full from empty).

### 2.2 rtl/disp_timing.v (v2)

- A local h/v FSM: a line = HSP44 + HBP75 + gate point 1 + PREF2 + HACT960 + HFP18 = **1100 pclk** (guarded by a FATAL check); a frame = VSP10 + VBP72 + VACT2160 + VFP8 + PAD90 = **2250 slots** (the TB scales 2/4/90/1/3 = 100).
- **Line-start gating (alg-line-gate, v4.3 semantics)**: when the gate point level < LINE_WORDS, that line **skips** (it still walks the full 1100-cycle empty line structure, pulling nothing and sending nothing, with late_cnt++ once per skipped line), while the **slot cadence never stops**. The v4.2 first version's "h freeze / stretched line" stopped emitting line_tick — the replay reader's slot cadence originates from the same source, so the start deadlocks (proven by the full-chain TB); hence the skip semantics. A skip in the Va segment does not advance v/line_num, so the frame is stretched in time (no lines are missing, R4; the frame rate drifts downward observably, R1 with zero feedback to the source).
- PREF 2-cycle prefetch aligns with the tx_line_buf read latency: buf_valid#i lands exactly on beat i of HACT, and valid is continuously unbroken (R4).
- The TX interface is 1:1 with shape_video_axis (D8): hsync/vsync are active low (registered outputs, same style as shape hs_r/vs_r), datatype=6'h1E, haddr=3840, line_num/frame_num increment, and frame_open is a single-cycle pulse at the end of VBP.
- line_tick_o: a single cycle at the end of a line, with a constant period of 1100 (a skip does not change the period) — a same-domain, same-source, one-way disp→reader path.

## 3. TB deliverables

### 3.1 sim/tb_disp_timing.sv (unit)

- B0 is an independent tx_line_buf sub-test: 8:1 aggregation bit order / level 2048 / overflow 119 groups starve / 2-cycle read latency / drain to zero.
- Main scenario: fast source 3 frames (late increment=0) → slow source 5 frames (late grows, the frame rate locks to the supply rate); V1 the burst is a constant 960 continuous, V2 frame structure / line numbers, V4 data cycle by cycle (864000 beats), V5 the D8 contract, V6 zero underrun.
- Result: **[DT-OK] all checks passed**.

### 3.2 sim/tb_full_chain.sv (full chain, newly created)

- Dual clocks (200M writer domain / 148.5M display domain); a real frame_writer + AXI slave (sharing mem_model) + a real frame_reader + a 40b→64b adaptation (1:1 beat-count conservation, {24'h0, fp40} directly mapped as a stand-in demosaic path) + tx_line_buf + disp_timing v2 + a TX stream checker.
- The frame handshake across domains uses the **toggle scheme** (done toggles → 2FF → edge restore) — the 200M single-cycle direct sampling loss risk recorded in Phase 2 is avoided in this TB in the Phase 4 target form.
- Checks: C1 every data line is a constant 960 continuous beats; C2 the line_num/frame_num ledger; C3 spot-checked lines (0/1/88/89) word-by-word exp64 + the fid field of each line's first beat; C4 the display frame fid sequence is non-decreasing (slow-direction repeats allowed); C5 zero underrun / zero overflow of the buffer; C6 spot-check the bank of the writer publication edge.
- The source model is brought into the envelope: the frame period is ~2ms (slow direction). Result: **[FC-OK] all checks passed (disp_frames=6)**.

## 4. Defects found and fixed in this phase

| # | Layer | Defect | Hard proof | Fix |
|---|---|---|---|---|
| 1 | RTL | tx_line_buf uses the low 8 bits of the 64b pointer as the mem address (should be 512b granularity [10:3]) | B0 reads out groups misaligned | The address becomes [10:3], the pointer is extended to 12 bits |
| 2 | RTL | An 11-bit pointer does not distinguish full from empty; after wrap-around the level is misread and the overflow protection fails | level=952/starve=0 | 12-bit pointer, level 0..2048 |
| 3 | RTL | The read pipeline stages mix in this stage's new value, so the group boundary address falls back to the previous group | rd[8k] systematically off by one group | Each stage only samples the previous stage's register |
| 4 | RTL | The lane is registered only once and is overwritten by the next emission, rotating the channel within the group by 1 | rd[8k+1] all wrong | The lane is registered twice and travels in lockstep with mem_q |
| 5 | RTL | The disp_timing gating "h freeze" stops emitting line_tick, so the replay source (same-source tick) deadlocks at start | Full-chain disp=0 | v4.3 skip semantics: a failed gate point walks an empty HACT, the slot cadence stays continuous |
| 6 | RTL | A blank line bypassed the gate point by one beat (line period 1099) | vsync window 2198 | Blank/data lines uniformly pass the gate point, the line is a constant 1100 |
| 7 | TB | The source model's ppm is dead logic / the set_phase sign is overwritten by the always block (carried over from Phase 2) | The segment direction is inverted | The sign is uniformly taken negative |
| 8 | TB | The full-chain source exceeded the envelope (faster than the display), so the write side overwrote the read bank 2 frames later | fid 5→7 tearing within a display frame | The source frame period ~2ms is brought into the envelope (slow direction) |

## 5. Known costs / outstanding items (Phase 4 inputs)

- **The 2-bank ping-pong envelope contract**: the source frame rate must not exceed the display frame rate (a real camera at 30fps < 60fps satisfies this); when the envelope is exceeded, the write side overwrites the same bank with frame N+2 before the read side has drained it (the TB proves this tearing form). If Phase 4 board testing needs resistance to envelope overrun, a lagged drop must be added on the write/arbitration side (currently delivered with the envelope constraint + TB slow-direction validation).
- The full-chain TB's 40b→64b adaptation is a direct {24'h0, beat} mapping stand-in; after the real demosaic→rgb2yuv path is connected the beat-count conservation stays the same (960→960), and the content check must switch to a YUV-domain expected model.
- Under the skip semantics, late_cnt is the observable measure of the downward frame rate drift (R9); in Phase 4 board testing it is compared against the fw-side bad_cnt.
- The cross-domain toggle handshake is verified in the full-chain TB, and Phase 4 implements the same form at the top level (replacing the single-cycle direct sampling).

## 6. Next step (Phase 4)

Top-level integration: ACLK_1=pixel_clk 148.5M, the reader instance changes domain, the wr_frame_done/par toggle 2FF routing, disp_timing v2 + tx_line_buf are connected (demosaic→rgb2yuv→tx_line_buf→disp_timing→shape TX port), SDC dual-domain constraints, and board-level replay output + DIAG observation (late/under/drop/repeat/fr_cnt).
