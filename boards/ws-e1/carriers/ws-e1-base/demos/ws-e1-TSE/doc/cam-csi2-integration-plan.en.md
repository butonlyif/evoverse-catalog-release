[中文](cam-csi2-integration-plan.md) | English

# ws_e1_tse Camera Integration: MIPI CSI-2 RX → RAW10 UDP Stream Implementation Plan

> Project baseline: ws_e1_tse (TJ180A484S / mytse + myriscv), G1–G7 all PASS,
> G7 = RAW10 1080p30 pattern stream at 622 Mbps with zero dropped frames (synthesized source udp_pat_gen_v2).
> **Goal of this plan: replace the synthesized source with a real IMX415 camera and reuse the entire remaining chain.**
> Reference project: `D:\Projs\ws-e1-cam-4K-1080-60fps-ref` (v4.11, dual-chain board-verified image output;
> its **cam1 = 1080p60 camera front end** is the porting blueprint for this plan).
> Authoritative status documents: reference project `doc/readme_4K_1K.md` + `doc/milestone-v4.11-cam1-replay.md`.

---

## 1. Goals and Acceptance Criteria (reusing G gating)

| Gate | Goal | Acceptance criteria (dual-side PC + UART evidence) |
|---|------|---------|
| G8 | CSI link established | After the IMX415 streams: my_csi2_rx probe valid-DT beat counter steps, SOT/ESC error counters stay 0, lock state printed on UART |
| G9 | Still-image capture | Single-frame dump from the raw_2_axi4st window output; PC-side comparison against the actual camera view (checkerboard/colored paper and other known scenes) matches |
| G10 | Live stream | All `test_raw10_rx` metrics: continuous frame numbers, 30.00fps ±0.1, payload 622±5 Mbps, pixel comparison PASS (same criteria as G7, with the source swapped to the real camera) |
| G11 | Stream+control coexistence | kill/software injection/t-v-n mode switching/0-3 pattern menu all regress PASS with the camera source |

**Evidence discipline**: compile PASS ≠ board-level PASS; sim PASS ≠ silicon PASS. Append every change to
`DAYLOG/2026-11.md`; milestones go through `project-review/<case>/review.md` with SHA-256.

---

## 2. Key Decision Records (2026-11-06, user confirmed)

### D1 Clocks: new PLL dual-channel 100M + 200M (the 50M/125M reuse scheme was vetoed by P0 evidence)

P0 verification (docs/efinity knowledge base + `D:\Efinity\2026.1` official docs + reference project facts):

| IP clock | Reference project | This plan | Official basis |
|---|---|---|---|
| `clk` (IP core clock) | 100M | **csi_clk_100m (new PLL channel)** | 2.5G CSI-2 RX UG: **IP Core Clock 40–100MHz**. Although 50M is within the IP range, the DPHY `CFG_CLK` officially requires **80–120MHz** (Titanium MIPI RX D-PHY doc, used for the time counter and EQ calibration); the reference project keeps both clocks on one net (sys_clk_100m) — keep the same-net topology, take 100M |
| `clk_byte_HS` | DPHY recovered word clock 111.375M | Same (hard-core output) | 1782Mbps÷16bit, no choice |
| `clk_pixel` (pixel output domain) | 200M | **csi_clk_200m (new PLL channel)** | UG lower bound 178.2 Mbeats/s (= 4lane×1782Mbps÷40bit). 125M is only 70%; although the FIFO math could absorb it (see below), it violates the documented lower bound by 30% — rejected |

Veto record for the 50M/125M reuse (archived to prevent re-proposal):
- 50M in place of IP `clk`: directly vetoed by the official CFG_CLK 80–120MHz constraint;
- 125M in place of `clk_pixel`: per-row burst 2.727µs, flooding in at 712.8Mpx/s while the 125M domain drains 500Mpx/s
  → per-row backlog 581px (< PIXEL_FIFO_DEPTH 1024; the blanking 4.68µs drains in only 1.16µs)
  — mathematically viable but violates the UG lower bound; a "violate-and-results-are-wrong" class risk, not acceptable.

**New PLL scheme**: Ti180 PLL resources TL0/TL1/TL2/TR0/BL0/BL1 (reference project facts prove
TL1/TL2/BL0/BL1 usable in this package); TSE already occupies TL0 (4 channels full: clk/clk_125m/clk_125m_90deg/
clk_25m feedback) + TR0 (rgmii). **The new PLL goes on a free slot (e.g. TL1)**,
`REFCLK_SOURCE=CORE` (the official attribute table supports EXTERNAL/CORE/DYNAMIC) multiplying an existing internal clock
into the dual channels 100M + 200M; CORE-mode feasibility is to be proven by import dry-run + compile,
with the fallback of switching slots or an external reference pin. No touching pll_0/pll_rgmii configuration in any way (zero-risk surface).
Accompanying SDC: add `create_clock` for 100M/200M + `set_clock_groups -asynchronous`.

**IP variant note**: must use the **2.5G variant (`efx_2p5g_csi2_rx`, generated module name still
`efx_csi2_rx_top`)** — the standard `efx_csi2_rx` caps the data rate at 1500Mbps < 1782Mbps.
The reference project's settings.json vlnv name=`efx_csi2_rx_top` is the 2.5G variant; its parameter table was
checked item by item against the official UG (4 lane / FIFO 1024 ≥ HACT×bpp/64=300 / GENERIC /
Pack_40 / tINIT=400000 / ASYNC=2 / AREGISTER=8 / PIXEL_SIDEBAND).

### D2 Frame-drop strategy: 30fps at the sensor (no frame dropping in RTL)

The user originally envisioned "skip-frame sending on the UDP side" (RTL drops odd frames). Veto math:

- Sending all of 60fps = 2.62MB/frame × 8 × 60 ≈ **1258 Mbps > 951 Mbps line-rate ceiling** → dropping is mandatory ✓
- But the buffering cost of RTL frame-skipping: even-frame pixels arrive within 16.67ms, sending spreads over the 33.3ms slot;
  backlog peak at the G7 622Mbps cadence ≈ **1.30MB ≈ 10.4Mb ≈ 95% of all Ti180 BRAM (not viable)**;
  bursting at 951Mbps ≈ 0.61MB ≈ 4.9Mb (barely viable but eats nearly half the BRAM and rides the line-rate ceiling)
- **30fps at the sensor**: IMX415 geo table VMAX 2250→**4500** (HMAX=550 unchanged;
  the rom already has a 30fps precedent with VMAX 6576), 4500×550/74.25MHz = 33.33ms = 30fps.
  Each frame arrives within 33.3ms = the send slot; line-by-line pipelined packetization; the CDC FIFO needs only ~2 rows (KB scale)
- Precondition confirmed: **bare IMX415, I2C-configurable mode** (user confirmed 2026-11-06)
- Benefit: fully overlaps the already-accepted G7 envelope; PC-side raw10.py / test_raw10_rx need zero changes;
  frame numbers are naturally continuous

**Register changes** (imx415_rom.sv geo1080 row, MODE_4K=0 branch):

```
VMAX: 0x30_24_CA / 0x30_25_08 (=2250)  →  0x30_24_11 / 0x30_25_94 (=4500)
HMAX: 0x30_28_26 / 0x30_29_02 (=550)   →  unchanged
```

(P1 must confirm against the IMX415 datasheet mode table that the VMAX 4500 + 2/2 binning + 1782Mbps combination is legal.)

---

## 3. Target Architecture

```
IMX415 (1080p30, 1782Mbps 4-lane, I2C RTL init, on-module crystal so no XCLK needed)
  → DPHY RX hard core MIPI_RX2 (= the same interface as the reference project's 1080 chain cam1, ISF bootstrap)
  → my_csi2_rx 2.5G variant (clk=csi_clk_100m / clk_byte_HS=recovered word clock / clk_pixel=csi_clk_200m)
  → raw_2_axi4st (200M domain, window 1944×1096 → 1920×1080, LEAD=6/TRAIL=18/SKIP=11)
  → async FIFO (40bit, ~2 rows deep)
  → udp_pat_gen_v2 RAW10 mode new external pixel port (125M-domain packetization; frame numbers re-assigned sequentially by the packer)
  → TSE MAC → RGMII → PHY → UDP 622Mbps (G7 envelope unchanged)

Control plane: a free bit at 0x208 gains cam_src_en (runtime camera/pattern source switch, UDP 10006 command);
cam_i2c_init instantiated in the csi_clk_200m domain (SYS_FREQ=200_000_000, reusing the reference project's
board-verified constants; I2C 50kHz, pads GPIOL_46=scl / GPIOL_01=sda /
cam_en=GPIOL_07 — all copied verbatim from the reference project's cam_1_* mapping)
```

**Porting list** (from the reference project):

| File | Change |
|---|---|
| `ip/my_csi2_rx/` | Copy verbatim from the reference project (**2.5G variant**, `CLOCK_FREQ_MHZ=100` unchanged; cfg checked item by item against the official UG) |
| `rtl/raw_2_axi4st.sv` | Port verbatim (geometry parameters = 1080p defaults, already matched) |
| `rtl/cam_i2c_init.sv` + `rtl/imx415_rom.sv` | MODE=0; geo row VMAX changed to 4500 (§D2); instantiated in the csi_clk_200m domain (SYS_FREQ=200M reusing board-verified constants) |
| `rtl/i2c_master.sv` | Embedded dependency of cam_i2c_init (reference project P1-fixed version, incl. scl_timeout/CMD_RESET fixes); port verbatim |
| `rtl/reset_ctrl.sv` | Reference project version (multi-domain sync); merge approach decided after comparing with the existing TSE reset chain |
| DPHY RX hard core + new PLL | ISF bootstrap (applied via import_gpio, see P1-1); peri.xml produced by the tools, hand-writing forbidden |

**Not ported**: frame_writer/frame_reader/DDR ping-pong/demosaic/wb/rgb2yuv/CSI-2 TX/
disp_timing (TSE goes over UDP, no display domain); the my_csi2_tx/top_cam display chains are all unnecessary.

---

## 4. Phased Plan

### P0 Reconnaissance (**completed 2026-11-06**, conclusions below)

1. **Camera interface = the reference project's 1080 chain verbatim (cam1 resource group, user-designated)**:
   DPHY RX2 (peri.xml `dphy_rx2` / MIPI_RX2, data_rate=1782, 4 lane,
   data_width=16, cal_clk_freq=100, byte_clkout=gclk) + cam1 pin group
   (cam_1_en=GPIOL_07, cam_1_scl=GPIOL_46, cam_1_sda=GPIOL_01).
   Do not reference the sc850sl demo (user was explicit: different camera). Same-board corroboration (auxiliary only):
   uart GPIOR_70/72 and the 50M crystal GPIOL_26 match this project.
2. **Camera control**: single cam_en (GPIOL_07) power enable; the reference project's cam_i2c_init
   PWR_OFF(300ms)→SETTLE(12ms)→…→DISCHARGE(500ms) sequence already includes power management;
   the IMX415 module carries its own crystal (the reference project has no XCLK output).
   Lesson (v4.11c confirmed): a missed cam_en pad drive → sensor unpowered → all-I2C NACK;
   during integration the pad connections must be specially checked.
3. **Bank voltages: no 1.2V declaration needed**. The reference project (RX0+RX2 dual-camera board-verified) declares
   iobank voltages only 1.8/3.3V; TJ180 DPHY RX uses dedicated pads and occupies no GPIO bank. This project's
   existing bank declarations stay as-is.
4. **Official constraint verification**: CFG_CLK 80–120MHz; 2.5G CSI-2 RX IP core clock 40–100MHz,
   FIFO ≥ HACT×bpp/64; the standard IP's 1500Mbps cap means the 2.5G variant is mandatory (details in D1).
5. **Free PLL slots confirmed**: the reference project demonstrably occupies TL0/TL1/TL2/BL0/BL1; this project occupies TL0/TR0
   → free slots are ample (new PLL scheme in D1).
6. **IMX415 VMAX 4500 legality**: the rom's same-source history contains VMAX 6576 (old 30fps setting);
   4500 lies between the verified 2250 (60fps) and 6576; 4500×550/74.25M = 33.33ms
   = 30.00fps. G8 board-level pcnt/lcnt measurements close the loop on the actual frame rate.
7. **Bootstrap path**: this project has `unified_flow="false"` and no ISF consumption chain (the
   reference project is isomorphic) → ISF is consumed via `cli/import_gpio.bat`: `--dry-run` self-check → remove dry-run and
   actually apply to peri.xml → comment out `create_*` in the ISF (annotating the enable condition) + commit peri.xml
   together (this project's adapted version of the §15 contract).

Exit criteria: all 5 items above have written conclusions ✅ (recorded in this section + DAYLOG).

### P1 = G8 CSI Link Establishment

1. ISF bootstrap (`cli/import_gpio.bat`, dry-run → apply): MIPI_RX2 hard core
   (copied from the reference project's `dphy_rx2`: data_rate=1782 / 4 lane / data_width=16 /
   cal_clk_freq=100 / byte_clkout=gclk, CFG_CLK=csi_clk_100m) +
   cam_en/GPIOL_07, scl/GPIOL_46, sda/GPIOL_01 GPIOs + new PLL (free slot,
   CORE reference, producing 100M+200M); create applied once then commented out; bootstrap compile + replay compile
   double PASS; SDC adds 100M/200M `create_clock` and asynchronous clock_groups
2. **`ip/my_csi2_rx/` whole directory copied verbatim from the reference project** (already the 2.5G variant
   `efx_csi2_rx_top`, board-verified, no regeneration needed; meaning of "2.5G variant": in IP Manager, CSI-2 RX comes in
   a standard grade (≤1500Mbps) and a 2.5G grade (≤2500Mbps); both variants generate
   the same module name; IMX415's 1782Mbps requires the 2.5G grade, and the reference project already has it);
   raw_2_axi4st + reset_ctrl ported in sync
3. cam_i2c_init + imx415_rom porting (MODE=0, geo row VMAX→4500 i.e. 0x30_24_11 /
   0x30_25_94); cam_i2c_init instantiated in the csi_clk_200m domain (SYS_FREQ=200M board-verified
   constant); the reference project ships `sim/tb_cam_i2c_init.sv` (C1–C4) for regression
4. Probes: DT-matched beat counter, SOT/ESC error counters, lock state on CSR (0x092 probe borrow or
   a new group), UART heartbeat prints
5. **G8 criteria**: after the sensor streams, the valid beat count ≥ the row-rate expectation (1944px×1091rows×30fps),
   error counters stay 0

### P2 = G9 Still-Image Capture

1. raw_2_axi4st window output feeds a single-frame capture path (decided in P2: borrow the CPU RX window for slow
   readback or a dedicated RAM dump)
2. PC-side dump comparison: aim the camera at a known pattern (checkerboard/color bars/screen), pixel-by-pixel verification
3. **G9 criteria**: the single-frame content matches the physical scene, no row/column shift or bit errors (direct proof of RAW10 unpack correctness)

### P3 = G10 Live Stream

1. async FIFO (200M→125M) + udp_pat_gen_v2 external pixel port (sof frame-boundary aligned packetization start;
   FIFO underflow aborts and resyncs the frame, no partial frames sent); frame numbers re-assigned sequentially at the packer
2. 0x208 cam_src_en bit + UDP 10006 command word + firmware ApplyMode extension
3. `test_raw10_rx` full-metric regression (frame-number continuity / 30fps±0.1 / 622±5 / pixel comparison)
4. **G10 criteria**: all criteria identical to G7 PASS, with source = real camera

### P4 = G11 Coexistence Regression

1. kill stop / software injection three-state / t-v-n mode switching / pattern menu regression under the camera source
2. ARP/ICMP/echo control-plane coexistence with the video stream retest (mux S_IDLE injection path)
3. **G11 criteria**: all G1–G7 regression items re-tested PASS while the camera source is running

---

## 5. Risks and Established Lessons (inherits PROJECT_SUMMARY §6)

| # | Risk | Mitigation |
|---|---|---|
| 1 | Synchronizer/handshake FFs dissolved by synthesis (DC_FIFO deadlock root cause) | Add `syn_keep` to all CDC/handshake registers; tb_sw_path regression + board-level verification |
| 2 | bins timing trap: map reads old firmware = fake compile | This plan does I2C via RTL init (cam_i2c_init), adding no firmware dependency; if firmware changes, still make→binGen→copy bins before map |
| 3 | MIPI pin/resource ownership (decided: copy the reference project's 1080-chain cam1 resource group RX2+GPIOL_07/46/01) | Copy the reference project's `dphy_rx2` peri config and cam_1_* pins wholesale; no invented mappings; special check of the cam_en pad connection (v4.11c lesson) |
| 4 | peri.xml is a PT artifact | Generated only via ISF/tools, hand-writing forbidden; after bootstrap comment out create_*, replay double PASS |
| 5 | IMX415 configuration order sensitivity ("SONY magic" block, TCLKZERO hi 0x401F=0x01) | Copy the reference project rom byte for byte; change only the geo-row VMAX two values |
| 6 | Reference project legacy: cold boot/warm reset occasionally locks the external chip (FPGA internals fine) | Full board power cycle before interpreting G8/G10 results; firmware watchdog listed as a future enhancement, not blocking this plan |
| 7 | RX has no backpressure (TSEMAC UG); the camera source likewise cannot be paused | The camera side only feeds the async FIFO + packetizer FSM frame-boundary alignment, no backpressure dependency |
| 8 | PC side: USB 3.0 NIC, dual-NIC bind 10.0.0.3, ARP aging | Reuse the G7 network-test conventions (project_memory board network-test conventions) |

---

## 6. Reference Documents

| Document | Content |
|---|---|
| Reference project `doc/readme_4K_1K.md` | Module/clock/data-path quick reference (cam1 1080 chain) |
| Reference project `doc/milestone-v4.11-cam1-replay.md` | Dual-chain integration archive (toolchain trap table §5) |
| Reference project `doc/cam-i2c-rtl-init-plan.md` | RTL I2C init design |
| This project `doc/PROJECT_SUMMARY.md` | Full TSE project snapshot (camera integration point §5.2) |
| This project `doc/udp_plan.md` | Original G1–G7 acceptance records |
| `docs/efinity/` | CSI-2 RX / DPHY UG (authoritative clock constraints, P0 verification) |
