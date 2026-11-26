[中文](readme_4K_1K.md) | English

# readme_4K_1K — Project Modules / Clocks / Data Path Quick Reference

Dual IMX415 CSI-2 cameras → LPDDR4X frame buffer ping-pong playback → MIPI CSI-2 TX panel output.
cam0 = **4K60** (148.5M display domain), cam1 = **1080p60** (37.125M display domain), the two chains are isomorphic
(v4 dual DDR playback, the sole source of the display = the DDR playback, no straight-through bypass).
Device Titanium **TJ180A484S**, Efinity **2026.1**. Top level `top_cam_demo`.

> This document is a project-level quick reference (modules/clocks/paths); for the milestones and the historical evolution see
> [milestone-v4.11-cam1-replay.md](milestone-v4.11-cam1-replay.md) and
> [milestone-v4.10c3m.md](milestone-v4.10c3m.md); for the programming/serial operations see
> [program.md](program.md).

---

## 1. Top-level block diagram

```
                 ┌────────────────────────── top_cam_demo ──────────────────────────┐
 IMX415#0 ─CSI-2→ DPHY RX0 ─→ my_csi2_rx ─→ raw_2_axi4st ──cap_t─→ u_fw0 ─┐         │
 IMX415#1 ─CSI-2→ DPHY RX2 ─→ my_csi2_rx ─→ raw_2_axi4st ──cap_t─→ u_fw1 ─┤         │
                                                                          axi_wr_arb│
                                                                    ┌──────────────┘
                                                              LPDDR4X hard core (dual target ping-pong)
                                                                    └──────────────┐
 u_cam_0 (148.5M)：u_rd0(ACLK=pixel_clk) ←──────── axi_rd_arb ←──────┤             │
   rd→demosaic→wb→rgb2yuv→tx_line_buf→disp_timing→my_csi2_tx→ DPHY TX0─→GSV6172→4K panel
 u_rd1 (200M) → axi_rd_cdc → replay stream (37.125M) → u_cam_1 ←──────────────┘             │
 u_cam_1 (37.125M)：rd→demosaic→wb→rgb2yuv→tx_line_buf→disp_timing→my_csi2_tx→DPHY TX2─→GSV6172→1080 panel
                                                                                    │
 riscv_soc(SaxonSoc/VexRiscv, sys_clk_100m):APB slave0/1=camc，I2C0/1=IMX415，     │
 GPIO0.bit0/1=cam_en，UART COM8@115200 ────────────────────────────────────────────┘
```

Each top_cam contains a source mux: pattern_gen (CSR `pat_en`) and shape_pat_gen 4K checkerboard
direct injection (compile-time DBG_SHAPE_PAT + CSR `dbg_sel`), used for isolation experiments; the replay stream goes straight into demosaic.

---

## 2. Clocks and reset

### 2.1 Clock table

| Clock | Source | Frequency | Use |
|---|---|---|---|
| `sys_clk_100m` | pll_sys | 100M | SoC/CPU bus; the my_csi2_rx control clock (AXI tie off) |
| `sys_clk_200m` | pll_sys | 200M | The RX pixel output domain (raw), u_fw0/u_fw1/u_rd1 aclk, the APB pclk, the DDR CFG/memcheck, the AXI arbitration |
| `pixel_clk` | pll_csi #1 | **148.5M** | cam0 display pixels + the TX pixel domain (pipeline/tlb/dtg); the u_rd0 aclk (peri ACLK_1 rebinding) |
| `pixel_clk_1080` | pll_csi2 #1 | **37.125M** | cam1 display pixels + the TX pixel domain |
| `i_clk_27m` | the board crystal | 27M | The TX power-on reset chain reference |
| `esc_clk` | periphery | — | DPHY TX ESC |
| `dphy_rx0/rx2_clk_CLKOUT` | RX recovery | word clock | The my_csi2_rx word domain (**it keeps oscillating with no stream**) |
| `dphy_tx0/tx2_WORD_CLKOUT_HS` | the TX periphery PLL | word clock | The my_csi2_tx word domain |

### 2.2 Reset release chain

- `pll_sys_locked` → sys_clk_100m/200m_rstn (reset_ctrl synchronized).
- The DDR CFG FSM gate = `sys_clk_200m_rstn & pll_ddr_locked` (waits for the PLL lock + ~10.5ms).
- The my_csi2_rx reset is released with the sys_clk_100m domain (before the PLL locks, the DPHY RX hard core stays in reset).
- **The TX chain** (top_cam.sv): `dphy_tx_RESET_N = pll_mipi_refclk_locked` → 8192 cycles in the 27M domain
  (~300us) → reset_esc_n/clk_byte_HS_n → then another 16384 cycles (~600us) →
  reset_pixel_n → u_tx_reset_ctrl produces {tx_pixel_clk_rstn, word_clk_arstn,
  esc_clk_arstn}. **The word clock activity is not verified.**
- The replay domain reset: rd_rstn_148 / rd_rstn_1080 (driven by the reset_ctrl inside g_frame_writer,
  declared at the top level); flush_done is passed through to trigger the corresponding chain's TX domain reset.
- The sensors: powered up by GPIO bit timing after the software I2C configuration completes (bounded retries, re-powering one chain does not disturb the other chain that is already streaming).

---

## 3. Module list (rtl/)

| File | Function | Domain/instance | Status |
|---|---|---|---|
| top_cam_demo.sv | Top level: dual top_cam + u_fw0/u_fw1/u_rd0/u_rd1 + arb/cdc + DDR CFG/memtest + the SoC hookup | — | Active |
| top_cam.sv | The single camera chain shell: rx→demosaic→wb→rgb2yuv→u_tlb→u_dtg→tx + CSR instantiation | ×2 (u_cam_0/u_cam_1) | Active |
| apb_cam_ctrl.sv | The per-chain CSR (the CTRL/DIAG groups, white balance/Bayer phase/pattern source runtime tuning) | pclk=200M, ×2 | Active |
| frame_writer.v | Packs a whole frame or nothing into DDR (512b packing, a line in two bursts of 64+56) | aclk=200M, ×2 (u_fw0/u_fw1) | Active |
| frame_reader.v | Display-cadence-gated playback (the frame slot cadence = the same source as disp_timing; residual frames are abandoned + an anchor window) | u_rd0 aclk=pixel_clk; u_rd1 aclk=200M | Active |
| demosaic.sv | RAW10→RGB (×4px, a 10-bit group counter) | tx_pixel_clk, ×2 | Active |
| wb_axis.sv | White balance (the effective value = pat_en?0x40:CSR) | tx_pixel_clk, ×2 | Active |
| rgb2yuv_axis.sv | RGB→UYVY 64b (blk_clip=!pat_en) | tx_pixel_clk, ×2 | Active |
| raw_2_axi4st.sv | A 40b AXIS sliding window / DT gating | raw 200M, ×2 | Active |
| pattern_gen.sv | The built-in test pattern source (CSR pat_en/pat_sel) | ×2 | Active |
| shape_pat_gen.sv | The 4K UYVY checkerboard direct injection source (dbg_sel, 4K geometry SRC_LINES=2160) | the tx pixel domain | Active |
| tx_line_buf.v | The TX line buffer (BRAM, DEPTH_WORDS=2048; the write is in the replay domain, the read supplies HACT in 64b beats) | ×2 (u_tlb) | Active |
| disp_timing.v | **The display timing generator v2** (the sole local source of the display timing; GATE(1)+PREF(2) hardcoded into the HFP 3 beats; line_room/stall/disp_sof/out-of-food warning) | tx_pixel_clk, ×2 (u_dtg) | Active |
| reset_ctrl.sv | Multi-domain reset synchronization | global | Active |
| axi_wr_arb.v | Arbitration of the dual writers → the DDR write port | 200M | Active |
| axi_rd_arb.v | Arbitration of the dual readers → the DDR read port | — | Active |
| axi_rd_cdc.v | The read data cross-domain CDC (a Gray pointer + 2FF, the cam1 replay stream 200M→37.125M) | — | Active |
| ddr_memcheck.v | The DDR self-check (DIAG11; hooked only on cam0, cam1 is tied to a constant 0) | 200M | Active |
| disp_timing_gen.v | The early Phase 2 display timing scheme | not instantiated | **Retired** (still compiled in the XML, optimized away by map) |
| disp_line_fifo.v | The early Phase 2 asynchronous line buffer (axi_rd_cdc is structurally modelled on it) | not instantiated | **Retired** (same) |
| axis_frame_check.sv | AXIS frame checking | — | TB only (not in the XML) |

---

## 4. Data path

### 4.1 cam0 (4K60) chain parameters

| Segment | Value |
|---|---|
| CSI line structure | LINE_TOTAL_PIX=3864 (WC=4830B), LEAD/TRAIL=12/12, SKIP=21 (36 OB lines + 21 header lines of 2B + 2160 active lines) |
| Active | HACT 3840 / VACT 2160 / GW=960 (PPC4) |
| DDR | target0: FRAME_A=0x0000_0000 / FRAME_B=0x0200_0000, a line slot of 8KB (a line of 7680B = two bursts of 64+56) |
| The display line (148.5M) | 1100 beats = HSP44 + HBP75 + GATE1 + PREF2 + HACT960 + HFP18 (= the c3m board-tested image baseline) |
| The display frame | 2250 slots (VSP10+VBP72+VACT2160+VFP8+pad) = 60Hz |
| The TX output | my_csi2_tx (free-run streaming, AXI-Lite tie off) → DPHY **TX0** → GSV6172 |
| The read domain | the u_rd0 aclk=pixel_clk (the same domain, no CDC) |

### 4.2 cam1 (1080p60) chain parameters

| Segment | Value |
|---|---|
| CSI line structure | LINE_TOTAL_PIX=1944, SKIP=11, 1080 active lines, GW=480 (PPC4) |
| Active | HACT 1920 / VACT 1080 |
| DDR | target1: FRAME_A=0x0400_0000 / FRAME_B=0x0500_0000, a line slot of 4KB (ddr_interface §10) |
| The display line (37.125M) | 550 beats = HSP11 + HBP37 + GATE1 + PREF2 + HACT480 + HFP19 (CEA 2200px÷4) |
| The display frame | 1125 slots (VSP5+VBP36+VACT1080+VFP4) = 60Hz |
| The TX output | my_csi2_tx → DPHY **TX2** → GSV6172 |
| The read domain | the u_rd1 aclk=200M → axi_rd_cdc → the replay stream 37.125M goes straight in before demosaic |

### 4.3 The AXI topology and arbitration

- Write: u_fw0(S0) + u_fw1(S1) → axi_wr_arb → the DDR write port.
- Read: u_rd0(S0) + u_rd1(S1) → axi_rd_arb → the DDR read port; the cam0 read data is used directly in the same domain,
  and cam1 is crossed to 37.125M through axi_rd_cdc.
- The flow-control model: the writer is all-or-nothing per frame (absorbing the source/display ppm difference), the reader has a display-cadence gate +
  a frame-boundary anchor (skipping frames in the fast-source direction); the tx_line_buf level feeds back to the reader's emission gate (line_room),
  and the out-of-food warning level is < 1 line.

### 4.4 The control plane and software resources

| Resource | cam0 | cam1 |
|---|---|---|
| APB camc | slave0 = 0xF810_0000 | slave1 = 0xF811_0000 |
| I2C (IMX415, 7bit 0x1A) | I2C0 = 0xF801_6000 | I2C1 = 0xF801_7000 |
| cam_en (GPIO0 whole-word write) | bit0 | bit1 |
| DPHY | RX0 → TX0 | RX2 → TX2 |

APB slave2/3 are dummy immediate-responders (a mis-access does not hang the CPU). The address macros are in `sw/bsp/include/soc.h`,
and the firmware wrappers are in `sw/top_demo/src/userDef.h`. UART COM8@115200: '[' / ']' select the target chain,
'g/o/h/b' switch the pattern (the keypress takes effect even when disabled), 'c' switches to the camera, and the remaining keys act on the target chain (white balance/phase/gap sweep, etc.).

---

## 5. Diagnostic CSR quick reference (each chain has its own APB base + 0x??)

| CSR | Content | Readout |
|---|---|---|
| DIAG4 | {fw_sof_free, dms_sol_free} running free | fw_sof +60/s = full speed |
| DIAG5 | {yuv_v_cnt, frm_cnt} | the yuv/frame counts |
| DIAG8 | {late, under} (disp_timing dtg) | the cumulative skips; under should be a constant 0 |
| DIAG9 | Fingerprint probe B (the demosaic entry) | With a natural camera image a growing err is an expected false positive |
| DIAG11 | The DDR self-check (ddr_memcheck) | **Hooked on cam0 only; cam1 tied to a constant 0 is by design** |
| DIAG12/13 | The fw counts (frm/line/ovf/pad) | frm +60/s, ovf=0 |
| DIAG14/15 | The rd counts (frm/st/ln; late/miss/err/req) | err=0 |
| DIAG16 | {beat_rd, beat_px} | direct proof of the path |
| DIAG17 | Probe A / the replay stream anchor (rd sol/tlast) | cam0 expects 2160/2160, cam1 1080/1080 |
| DIAG18 | df/live (the 0.75s window hardcoded at 148.5M) | cam0 df≈45; the cam1 reading ×4 → df=180; a full live=60Hz |
| DIAG19 | {drop, rpt} | should not move |
| DIAG20 | ← ddr_diag7 | the cam1 diagnostic group |

The firmware heartbeat prints: cam0 `fw0/rd0/fr0/rate0`, cam1 `fw1/rd1/fr1/rate1` (new in v4.11).
Note that the BSP printf has no %u, always use %d. The details are in program.md and milestone-v4.10c3m §5.

---

## 6. Board-level operation

Program the bitstream (ftdi_pgm.bat, JTAG) → load the ELF with the four-stage openocd cfg (resume 0xF9000000) →
read the judgement on COM8. The complete commands and the readout table are in [program.md](program.md).
Firmware toolchain: `D:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin`.
Known board-level items: after a cold start / warm reset the external chips (the bridge chip / the DPHY periphery) occasionally lock up, while the FPGA's internal
metrics are normal but the panel is black / the stream is broken — first power the whole board down and up or reprogram the bitstream, then investigate (two proven cases in v4.11,
detailed in milestone-v4.11 §7/§8).

---

## 7. Related documents

| Document | Content |
|---|---|
| [milestone-v4.11-cam1-replay.md](milestone-v4.11-cam1-replay.md) | The complete archive of this milestone (the cam1 integration) |
| [milestone-v4.10c3m.md](milestone-v4.10c3m.md) | The cam0 single-chain baseline (the diagnostic system / the detailed historical lessons table) |
| [cam1-ddr-replay-plan.md](cam1-ddr-replay-plan.md) | The cam1 integration implementation plan (the frozen version) |
| [ddr_interface.md](ddr_interface.md) | The DDR layout accounting (§10 dual target) |
| [program.md](program.md) | The programming/ELF/serial measured handbook |
| [csi_bridge_gap_sweep.md](csi_bridge_gap_sweep.md) | The bridge chip timing tolerance sweep (GSV6172) |
