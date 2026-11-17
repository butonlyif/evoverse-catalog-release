[中文](ddr_interface.md) | English

# DDR Interface Summary (ws-e1-cam-ddr-csi2)

> Device: Efinix Titanium **TJ180A484S** (DDR_0 hard core) + onboard **LPDDR4x 2Gb** (x16, 1 rank)
> Compiled 2026-10-18; **2026-10-22 added §9 (c3k out-of-range wraparound = root cause of the bottom flicker band, board-test closed)**.
> Phase 0 board-test acceptance criteria (all met):
> `ddr: lock=1 st=3 raw=1 cfg_ok=1 mcst=9 done=1 fail=0 err=0`

---

## 1. Hardware Configuration (peri, ws-e1-cam-ddr-csi2.peri.xml)

| Item | Value | Note |
| --- | --- | --- |
| Memory die | LPDDR4x, **2Gb**, x16, 1 rank | `mem_density="2G"`. The 4Gb noted in the EvoVerse reference design is wrong; this board governs |
| DDR reference clock | **GPIOL_32, 33.3333MHz**, 3.3V LVCMOS | onboard independent crystal (unrelated to Si5338, no software configuration needed) |
| DDR PLL | **PLL_TL2**: 33.3333MHz ×4 ÷(pre 1 × post 1) | VCO=133.33MHz, local feedback from CLKOUT0, ext_ref_clock_id=3 |
| CLKOUT0 (DDR clkin) | **out_divider=28, conn_type=gclk** → 4.762MHz | supplied to the hard core via `clkin_sel=2`. Aligned with the gmsl project (user-confirmed working) |
| CLKOUT4 | out_divider=5, gclk → 26.67MHz | same as gmsl |
| pll_ddr reset | `reset_name="pll_ddr_rstn"`, top level wired to `i_arstn` (released ~9.5µs after power-on) | |
| AXI ports | target0/target1 each 512b data, 64b strb, 33-bit address | ACLK_0 = `sys_clk_200m` (write port, frame_writer zero CDC); **ACLK_1 = `pixel_clk` 148.5M** (read port, the v4 reader display domain; the hard core accepts dual asynchronous port clocks, verified in Phase 0). 2026-10-23 erratum: the earlier note "ACLK_0/1 both bound to sys_clk_200m" was an early plan; the actual peri.xml binding is in ws-e1-cam-ddr-csi2.peri.xml |

Measured record: both PLL divider sets lock and complete training on this board —
gmsl (post=1/out=28 → 4.762MHz, currently adopted) and ori (post=2/out=20 → 3.333MHz, v3 board test lock=1 + training passed).
`conn_type` must be **gclk** (the lclk of the earliest failing version is the prime suspect). The hardware units (pin/EXT_REF/DDR macro configuration) are
identical to both reference projects, checked item by item.

## 2. Boot Sequencing Chain (v5 final form, verified level by level on the board)

```text
FPGA configuration done
 → i_clk_27m counts 256 beats (~9.5µs) → i_arstn released
 → five PLL resets released (including pll_ddr_rstn)
 → pll_ddr locked (pll_ddr_locked=1)
 → CFG FSM reset released (sys_clk_200m_rstn & pll_ddr_locked)
 → 2^21 beats (10.5ms @200MHz) settle period
 → CFG_START → hard-core Startup Sequencer training → CFG_DONE (raw=1 → cfg_ok=1)
 → ddr_inst_ARSTN_0/1 released (= ddr_cfg_ok)
 → checker reset released (reset_ctrl CYCLE=4) → start=mc_srstn=1
 → 3495 bursts × 120 beats write→read comparison (0x0 ~ 0x103F200 ≈ 26MB ≈ frame A/B ping-pong region)
 → done=1 fail=0 err=0 → CSR DIAG11 @0x2C → UART
```

Key point: **the FSM must start counting only after lock** (gated by
`cfg_fsm_rstn = sys_clk_200m_rstn & pll_ddr_locked`);
lock has been measured readable and lockable on this board (lock=1), so the gating is safe. Power-on to scan completion finishes within seconds.

## 3. Controller AXI Behavior Essentials (board-measured; frame_writer/frame_reader must obey)

1. **WVALID-before-AWREADY type** (most critical): AWREADY asserts only after both AWVALID && WVALID have been seen.
   - The write channel must raise WVALID **before** the AW handshake completes, otherwise it deadlocks in mutual waiting with the controller (board-test mcst=2 confirmed);
   - W beats may start flowing before this burst's AW handshake — legal and required;
   - Prerequisite: the previous burst's B response has been received (the controller fully retires the old burst before starting a new one).
2. **W transfers occurring during PRE_WRITE must be counted in beat accounting** (same as the checker's), otherwise wlast lands on the wrong beat and, the controller never receiving LEN in full, never gives B.
3. **awqos=1** (arqos=0), same as the checker.
4. Burst shape: AWLEN=119 (120 beats) × AWSIZE=6 (64B/beat) = **7680B = one UYVY line**, INCR; WLAST strictly in the same beat as the last beat; burst boundaries delimited by WLAST. (This is the memcheck self-check shape; the application-side frame_writer v2 actually splits a line into **64+56 two bursts**, each within a single 4KB window, see §9.3.)
5. bready/rready in place before the handshake (asserted during PRE_WRITE/PRE_READ); controller ready has random backpressure (modeled in the TB).
6. Hard-core dedicated pins held 0: awapcmd / awallstrb / awcobuf / arapcmd.

## 4. Debug History (all 6 board-test pitfall rounds)

| # | Symptom | Root cause | Fix |
| --- | --- | --- | --- |
| 1 | cfg_ok=0 (first run) | PLL `conn_type=lclk` (the only difference from the working config) + training after only 256 beats | changed to gclk; extended the wait |
| 2 | lock=0 (illusion) | **the print read cam1's CSR** (cam1's DIAG11 is always 32'h0) — both rounds of "failure" readings were contaminated | DIAG11 changed to read cam0 (`CamDiag11_Rd(0)`) |
| 3 | st always 0 | v3 had removed the lock gating; v5 restored the gating (after lock measured trustworthy) | `cfg_fsm_rstn = sys reset release & lock` |
| 4 | training wouldn't start | PLL dividers accidentally changed (out_div=28→1 etc.) | training passed after aligning to gmsl (lock=1 st=3 raw=1) |
| 5 | done=0, no start | checker `.start(~mc_srstn)` polarity inverted, start=0 after reset release | `.start(mc_srstn)` |
| 6 | mcst=2 stuck on AW | "W waits for AW" fix deadlocked with the controller's WVALID-first mutual wait | raise W from PRE_WRITE + count transfers during it |

## 5. Diagnostic Bitmap (DIAG11 @0x2C, **read cam0 CSR**)

```text
{err_cnt[15:0], mcst[15:12], 5'h0, done_raw[6], st[5:4], lock[3], cfg_ok[2], done[1], fail[0]}
```

- `st` (CFG FSM): 0=IDLE, 1=training, 3=done
- `mcst` (checker): 0=IDLE, 1=WR_ADDR, 2=PRE_WR, 3=WR, 4=POST_WR(waiting B),
  5=RD_ADDR, 6=PRE_RD, 7=RD_CMP, 8=POST_RD, 9=DONE
- Software print (in cam_show; the DDR line reads cam0 for both cameras):

```text
ddr: lock=%d st=%d raw=%d cfg_ok=%d mcst=%d done=%d fail=%d err=%d
```

Quick readout: lock=0 → st stays 0 (check PLL/reset); st=1 raw=0 → training doesn't accept the reference clock;
mcst=2 → write channel deadlock; mcst=4 → write done but no B; mcst=9 with done=1 fail=0 → path healthy.

## 6. Verification Status

- **TB** (sim/tb_ddr_memcheck.sv): AW model = WVALID-first (AWREADY asserts only after both VALIDs) + random backpressure;
  R channel ~12% random gaps; protocol assertions (wlast/rlast positions, LEN match, WSTRB always full);
  burst accounting delimited by wlast. Result `[DDR-MC-PASS] done=1 fail=0 err=0 | bursts=4 w_beats=480 r_beats=480 proto_err=0`.
- **Board test**: 3495 bursts × 120 beats over the whole region (26MB) write-read comparison with zero errors.
- The TB's AXI slave memory model is private to this project (the official Efinity EFX_LPDDR4_16_V1.v is a placeholder model with no behavior).

## 7. Key Files

| File | Role |
| --- | --- |
| rtl/ddr_memcheck.v | line-burst write-read comparison (ALEN=119, TOTAL_BURSTS=3495, fixed-count scheme against overrun) |
| rtl/top_cam_demo.sv | CFG FSM (~L510) + checker instantiation + DIAG11 packing (~L757) |
| rtl/apb_cam_ctrl.sv | CSR DIAG11 @0x2C |
| sim/tb_ddr_memcheck.sv | closed-loop TB (with the WVALID-first AW model) |
| sw/top_demo/src/main.c | cam_show's DDR print (reads cam0) |
| sw/top_demo/src/userDef.h | CAMC_REG_DIAG11 bitmap comments |
| ws-e1-cam-ddr-csi2.peri.xml | pll_ddr / ddr_inst configuration (§1) |
| References (read-only) | EvoVerse `ddr-memtest/rtl/memory_checker.v` (handshake structure), `si5338-clock-config/top_soc.v` (same-board FSM), gmsl project peri (PLL parameters) |

## 8. Interface Contract for Phases 1/2 (frame_writer / frame_reader)

- Address layout (**v4.10c3k corrected**, details in §9): frame A @ 0x0_0000_0000, frame B @ **0x0_2000_0000**; line slots 8KB stride (line number << 13), line data 7680B = 64+56 two bursts each within a single 4KB window; one frame = 2160 lines × 8KB = 17.6MB. Frame A occupies 0..17.7MB, frame B 32..49.7MB, all within the 2Gb device's 256MB capacity bound.
- Frame writes: obey all §3 essentials (especially WVALID-first and PRE_WRITE counting).
- The self-check burst shape (120-beat single burst) now differs from the application burst shape (64+56 two bursts), but both are 64B-beat INCR and obey the same §3 handshake rules; phase 0 verified the path with the same beat width; the burst-split difference does not affect protocol behavior (burst boundaries delimited by WLAST).
- Bus utilization estimate: 4K@60 write side ≈ 1.06GB/s, ~16% of the LPDDR4x-2133 peak; read/write line-by-line alternation turnaround overhead ~1.6%.

## 9. AXI Address Mapping and Capacity Constraint (v4.10c3k board-test lesson, 2026-10-22)

### 9.1 Hard-core address mapping rule (Efinity "Address Mapping" document)

AXI byte address → DRAM row/bank/column is a **fixed-field concatenation**, field widths determined by device capacity.
Largest-space example (33 bits) and the low-density example:

| [32] | [31:15] | [14:12] | [11:2] | [1:0] |
| --- | --- | --- | --- | --- |
| Chip select | Row | Bank | Column | Datapath |

| [32:28] | [27] | [26:12] | [11:9] | [8:2] | [1:0] |
| --- | --- | --- | --- | --- | --- |
| Not used | Chip select | Row | Bank | Column | Datapath |

- x32 devices: the controller address LSB = AXI bit2; **x16 devices: the controller address LSB = AXI bit1** (Datapath bit0 always 0).
- **"Unused MSBs must be driven 0" is a hard constraint**: address bits beyond the capacity fields are **silently stripped** by the hard core, equivalent to the address wrapping modulo the capacity — no AXI protocol error, no SLVERR, RESP=OKAY, and all protocol counters are oblivious.

### 9.2 This board's capacity account

LPDDR4x 2Gb x16 1 rank: 2^31 bit ÷ 8 ÷ 2B/word = 2^27 words → AXI byte space **256MB = 0x1000_0000**,
valid address **[27:0]**. bit28 (0x1000_0000) and above, once set, exceed the bound and are stripped/wrapped by the hard core.

### 9.3 The c3k root-cause case (the B problem: bottom 112-line flicker band in camera mode)

- Symptom: the diagnostic pattern (mod-1024 grayscale ramp) mode is stable without flicker; in camera mode the bottom 112 lines (lines 2048..2159) flicker.
- Layout: line slots 8KB (data 7680B = 64+56 two bursts, each within a 4KB window), frame A @ 0x0 (occupies 0..0x10E1600 ≈ 17.7MB), frame B @ **0x1100_0000** (272MB, out of range).
- Root cause: 0x1100_0000 = bit28+bit24; bit28 is stripped by the hard core → frame B effectively lands at **0x0100_0000 = 2048 lines × 8KB = exactly frame A's line 2048** → frame B's first 112 lines overlap frame A's last 112 lines. Ping-pong semantics broken: while the reader reads A's tail, the writer writes B's head to the same addresses → read/write race on the bottom 112 lines = flicker band.
- Closed evidence chain (why 6+ earlier probe/counter rounds "cleared" the DDR segment yet it failed here):
  - Write and read sides' FRAME_B parameters word-for-word identical → the address ledger self-consistent → rd late/miss/err, ddr err all green;
  - Probes A/B (c3j) are data-domain fingerprints → the data sequence is perfect, physical placement errors invisible;
  - mod-1024 diagnostic pattern: lines 2048..2159 have the same grayscale as lines 0..111 (2048 ≡ 0 mod 1024) → after misaligned content overwrites, the display is unchanged → pattern mode stable (doubly blinded to address aliasing with δ≡0 mod 1024);
  - The behavioral simulation model (ddr_ctrl_model) defaults to a 4Gb=1GiB linear mapping → 0x1100_0000 is legal in the model → **structurally unreproducible in simulation**; tb_phase4's VACT=90 frame is only 720KB with no overlap against the B base — a double-blind spot.
- Fix: FRAME_B of u_fw (top_cam_demo ~L661) and u_rd (~L754) → **0x0200_0000** (frame B 32..49.7MB, 14MB from frame A, 4KB alignment unchanged; bit25 lands within the Row field, legal). Both parameters must be changed together (write/read symmetry).
- Acceptance: 2026-10-22 board test, the camera-mode bottom flicker band disappeared, **the B problem closed**. Regression P4C-OK / rd 90/90 / P4-OK / SLOW-OK all green; bitstream map/interface/pnr/pgm all PASS.

### 9.4 DDR Address Layout Rules (mandatory reading for future changes)

1. Before any DDR address/layout change, do a static check against the **256MB (0x1000_0000) capacity bound**: highest occupied address = base + 2160×8192 − 1, must be < 0x1000_0000.
2. The behavioral simulation model does not model capacity wraparound — out-of-range defects can only be guarded by static review + board test; for simulation coverage, configure ddr_ctrl_model with `MEM_DENSITY_GBIT=2` and enable range_check.
3. **"All counters green + clean data probes" cannot prove the DDR segment is correct**: address-domain errors (aliasing/overlap/wraparound) are doubly invisible to data-domain fingerprints and self-consistency counters — only an address-sequence check (such as the optional post-c3k awaddr/araddr probes) or the displayed content can expose them.
4. Frame base selection: besides the capacity bound, confirm the base's most significant bit lands within the Row field (avoiding the Chip-select/Datapath boundary ambiguity bits); keep the A/B frame bases word-for-word identical in both u_fw and u_rd.

## 10. cam1 (1080p60) Frame Layout Budget (2026-10-23 task 2 phase 0 freeze, re-check before implementation)

Static accounting for the cam1 replay chain per the §9.4 rules (1080p = 1920×1080 RAW10, 64b carrier isomorphic to cam0):

| Item | Value | Derivation |
| --- | --- | --- |
| Line data | 3840B/line | source 480 beats×40b = 2400B; 64b zero-extended carrier 480 beats×8B = 3840B |
| AXI write shape | 512b/beat, 32+28 two bursts (each within a 4KB window) | 32×64B=2048B + 28×64B=1792B, sum 3840B ≤ 4096B |
| Line slot stride | 4KB (line number << 12) | 3840B ≤ 4096B, no overlap between lines, and each line slot 4KB aligned |
| One frame | 4KB × 1080 lines = 4.32MB | |
| cam1 FRAME_A1 | **0x0_0400_0000** (64MB) | occupies 64..68.32MB; MSB=bit26 lands in the Row field ✓; 14.3MB from cam0's frame B (32..49.7MB) |
| cam1 FRAME_B1 | **0x0_0500_0000** (80MB) | occupies 80..84.32MB; MSB=bit26 lands in the Row field ✓ (**not 0x0600_0000** — its bit27 lands in the Chip-select field, violating rule 4); 11.68MB from A1 |
| Capacity bound | highest occupancy 84.32MB < 256MB (0x1000_0000) ✓ | all address bits within [27:0] |
| Overlap check with cam0 regions | cam0 A(0..17.7M) / B(32..49.7M) vs cam1 A1/B1: zero overlap ✓ | |

Total bandwidth account (after 4-port convergence): cam0 write 1.06 + cam0 read ~1.06 + cam1 write ~0.26 + cam1 read ~0.26 ≈ **2.6GB/s**, ~16% → ~20% of the LPDDR4x peak, ample.

Simulation note: behavioral models / self-built TB DDR models do not model capacity wraparound (§9.3 lesson); although the cam1 layout is within bounds, the ddr_ctrl_model route is still advised to set `MEM_DENSITY_GBIT=2` and enable range_check as a double safeguard.
