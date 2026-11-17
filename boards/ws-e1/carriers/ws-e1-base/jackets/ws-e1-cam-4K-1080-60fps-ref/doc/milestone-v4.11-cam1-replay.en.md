[中文](milestone-v4.11-cam1-replay.md) | English
# Milestone: v4.11 — cam1 1080p DDR replay full-chain integration (both chains produce an image on the board)

Date: 2026-10-24
Status: **board-test usable (both-chain output confirmed)**. cam0 4K60 and cam1 1080p60 both produce an end-to-end DDR replay image;
both simulation regressions all green; efx map/pnr/pgm all PASS. Outstanding: board-level state-class intermittents on cold start/warm reset
(§8).

This document follows [milestone-v4.10c3m.md](milestone-v4.10c3m.md) (the cam0 single-chain baseline archive);
the implementation baseline is [cam1-ddr-replay-plan.md](cam1-ddr-replay-plan.md) (§4 phases 0-6 all completed).
For a quick reference of project modules/clocks/data paths see [readme_4K_1K.md](readme_4K_1K.md).

---

## 1. Version Identification

| Item | Value |
|---|---|
| Version | v4.11 (follows v4.10c3m) |
| bitstream | `outflow/ws-e1-cam-ddr-csi2.bit` (built 2026-10-24 07:56, map 0 errors / PnR timing all green / pgm PASS) |
| Firmware | `sw/top_demo` ELF (cam1 heartbeat diagnostic group, see §6) |
| Top level | `top_cam_demo` (Titanium TJ180A484S, Efinity 2026.1) |
| Regression | tb_phase4 r4 green + tb_phase4_ddrm r6 green (4K) + tb_phase5_cam1 r6 green (1080): P4C content 216000 beats 0 errors, rd sol/tlast 90/90, SLOW-OK, ctrl_err=0 |
| Key files | `rtl/top_cam_demo.sv` (fw/rd/arb/cdc integration) `rtl/top_cam.sv` (u_dtg parameterized) `rtl/axi_wr_arb.v` `rtl/axi_rd_arb.v` `rtl/axi_rd_cdc.v` (newly added to the project) `sim/tb_phase5_cam1.sv` `sw/top_demo/src/main.c` |
| Board test | cam1 1080p60 end-to-end (fw1/rd1 60fps synchronized, err=0, df=180 live full, 90s+ long run); cam0 4K60 confirmed to produce an image after a power cycle (§7) |

---

## 2. Architecture: v4 dual DDR replay, two isomorphic chains

Since v3 the only display source = DDR replay, **no straight-through bypass** (shape_video_axis has retired). v4.11
replicates cam0's v4.10 structure completely onto cam1: two isomorphic chains, each occupying one DDR target with independent ping-pong.

```
cam0 (4K60, 148.5M display domain)                cam1 (1080p60, 37.125M display domain)
IMX415 → DPHY RX0 → my_csi2_rx → raw_2_axi4st     IMX415 → DPHY RX2 → my_csi2_rx → raw_2_axi4st
        │(cap_t*, 200M raw domain)                │(cap_t*, 200M raw domain)
        u_fw0 (whole frame or nothing, target0)   u_fw1 (whole frame or nothing, target1)
        └──────────────> axi_wr_arb <────────────────────┘
                              │
                        LPDDR4X dual-target frame ping-pong
                  target0: A=0x0000_0000/B=0x0200_0000   target1: A=0x0400_0000/B=0x0500_0000
                              │
        u_rd0 (aclk=pixel_clk, same domain)      u_rd1 (aclk=200M) → axi_rd_cdc → replay stream
        └──────────────> axi_rd_arb <────────────────────┘
        │                                         │
inside u_cam_0 (148.5M): demosaic → wb → rgb2yuv  inside u_cam_1 (37.125M): demosaic → wb → rgb2yuv
  → tx_line_buf → disp_timing(u_dtg)              → tx_line_buf → disp_timing(u_dtg)
    1100 beats/line / 2250 slot frames = 60Hz     550 beats/line / 1125 slot frames = 60Hz
  → my_csi2_tx → DPHY TX0 → GSV6172 → panel       → my_csi2_tx → DPHY TX2 → GSV6172 → panel
```

> Actual TX outlets: **cam0→TX0, cam1→TX2**. readme/main.c once had them reversed (cam0→TX2),
> a documentation error left over from the v3 era, corrected on 2026-10-24; the wiring has never changed since v14c (10/14).

---

## 3. Integration Content (phases 1-5)

- **Write path**: u_fw1 (VACT=1080 / 60-word lines / 32+28 / 4KB line slot) → axi_wr_arb S1;
  u_fw0/u_fw1 two-port arbitration shares the DDR write port.
- **Read path**: u_rd1 (200M) → axi_rd_arb S1 → axi_rd_cdc (gray pointers + 2FF, modeled on
  the disp_line_fifo structure) → cam1 replay stream (37.125M) straight into u_cam_1 ahead of demosaic;
  u_rd0 stays in the same domain (aclk=pixel_clk, peri ACLK_1 rebound to 148.5M).
- **Display gating**: cam1 line cadence/frame boundary/starvation are all supplied same-source by disp_timing inside u_cam_1
  (37.125M), consistent with the cam0 structure.
- **Reset**: the replay-domain reset lines rd_rstn_148 / rd_rstn_1080 are driven by the reset_ctrl inside the g_frame_writer
  block and declared at the top level (cross-scope, see §5 item 6); flush_done is passed back to
  u_cam_x to trigger the tx-domain reset.
- **u_dtg parameterization** (phase 2): LINE_CLKS / HSP/HBP/HFP_CLKS become top_cam parameters.
  cam0 passing nothing means the default **1100/44/75/18** (= the c3m board-test image baseline, line sum
  44+75+1+2+960+18=1100, guard self-consistent); cam1 passes 550/11/37/19.
- **Diagnostics**: u_cam_1 hosts the ddr_diag2~7/19 group (DIAG12/13 fw, DIAG14/15 rd, DIAG17
  replay anchor, DIAG19 drop/rpt); **DIAG11 tied to 0** (cam1 does not host the DDR self-check; a constant 0 is
  by design).

---

## 4. Verification

| TB | Coverage | Result |
|---|---|---|
| tb_phase4 r4 | 4K display chain (stimulus wired directly into the display domain, no DDR) | green |
| tb_phase4_ddrm r6 | 4K + DDR model full chain | green |
| tb_phase5_cam1 r6 | cam1 dual DDR replay full chain (P4C content comparison 216000 beats 0 errors, rd sol/tlast 90/90, SLOW rate change, ctrl_err=0) | green |

TB debugging notes (details in §5): the cam1 source anchor line (2962 beats) once ran ~800-1000 beats faster than the DDR write line,
which caused an 8-slot queue overflow, dropped lines and deadlock; the main case was changed to src_gap_beats=2476 (source line 14.8us, the same rate as the display line);
a real board camera line period of ~26us has no such problem.

---

## 5. Toolchain and Implementation Fix Record (ebbing trap archive)

| # | Problem | Fix |
|---|---|---|
| 1 | tb_phase5 vopt-8884: output port connected to a literal | `.DBG_FIELDS_ADDR()` left dangling |
| 2 | u_dtg h-segment guard FATAL: HSP/HBP/HFP not passed (default 44/75/18 → 620≠550) | TB passes 11/37/19 |
| 3 | TB timescale distortion → DDR write port backlog → q_full dropped lines → 63 frames all bad, deadlock | src_gap_beats=2476 (§4) |
| 4 | efx_map "Input source file is not specified" / EFX-0008 wrong top level selected | `--project-xml` + `--root top_cam_demo` (`--project` is naming only) |
| 5 | .v parsed as Verilog-2001: `parameter int`, `12'()` report errors (disp_line_fifo/disp_timing_gen, both retired files still in the compile list) | remove the SV syntax; incidentally noted: the two files can be moved out of the XML |
| 6 | **VERI-2561 ×11 (a functional hazard, not lint)**: rd_rstn_148/rd_rstn_1080 declared inside the block + referenced as top-level ports → implicit dangling wire (reset chain broken); fw1_* declared after use → implicit 1-bit truncation | reset lines hoisted to top-level declarations; fw1 nets moved ahead |
| 7 | efx_pnr Tcl init path broken / timing module load failure | `EFINITY_HOME=D:/Efinity/2026.1` **forward slashes**; add bin to PATH |
| 8 | PnR negative slack (-0.7~-3.2, 0.001ns false window on cross-clock pairs) | SDC gains 6 asynchronous clock_groups (pixel_clk_1080/esc/27m ↔ dphy_tx2 etc.) |
| 9 | efx_pgm does not accept --circuit | `--project-xml --family --device` |
| 10 | riscv-none-elf-gcc not on PATH | `D:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin` (readme §103) |
| 11 | XML design_info missing 3 source files | added axi_wr_arb/axi_rd_arb/axi_rd_cdc |
| 12 | Firmware readout conventions: the BSP printf has no %u (it takes the float branch and misaligns arguments, %d is mandatory); DIAG11 cam1 constant 0 is by design; the DIAG18 0.75s window is hard-coded for 148.5M, so df reading ×4 in the 37.125M domain | main.c heartbeat group prints per these conventions |

---

## 6. Board Test and Firmware

Flow per [program.md](program.md): ftdi_pgm.bat JTAG-programs the bit → openocd loads the
ELF with the four-section cfg (resume 0xF9000000) → readout on COM8@115200.

New cam1 heartbeat diagnostic group in the firmware (all read APB slave1=0xF811_0000):
`fw1` (DIAG12/13), `rd1` (DIAG14/15), `fr1` (DIAG17 anchor, expect 1080/1080),
`rate1` (DIAG4/5/18). cam1 criteria: fw1 frm +60/s with ovf=0, rd1 err=0, fr1
1080/1080, df=180 (×4 convention) live full → 60Hz. cam0 criteria unchanged (program.md health table).

**cam1 board-level result**: fw1/rd1 60fps synchronized, err=0, display 60Hz live full, 90 seconds+ long run without
stream loss, both the pattern and the camera image confirmed.

---

## 7. 4K Black-Screen Incident (closed: board-level state class, not an RTL defect)

- **Symptom**: on the 10/24 bit board test, cam1 1080 produced an image, cam0 4K was black.
- **Internal evidence**: cam0 serial metrics all green (fw/rd/ddr, df=45/45, live full, yuv alive) —
  the display pipeline was running, the panel was black.
- **Three-way exclusion** (static evidence):
  1. The TX wiring is unchanged since v14c (10/14) (cam0→TX0); phase 5 did not rewire;
  2. The peripheral configuration (peri.cdo/interface.csv) is frozen at 10/22 15:11 (the good c3m bit build),
     was not regenerated by this compile, and the TX0 PLL configuration is identical to the good bit;
  3. cam0 display parameters = the c3m baseline (1100/44/75/18, 2250 slots). The active u_dtg =
     `disp_timing.v` (already used by c3m); `disp_timing_gen.v`/`disp_line_fifo.v` are early phase-2
     schemes that have retired (compiled but not instantiated) and do not constitute this regression.
- **Recovery**: 4K produced an image after the user power-cycled the whole board.
- **Conclusion**: the bridge chip/DPHY peripherals occasionally lock up after a warm reset (JTAG reconfiguration), while everything inside the FPGA is normal.
  Same class as the cam1 77s stream loss (§8). Incidental erratum: readme.md:30 and the main.c header comment reverse the TX mapping
  (see the §2 note).

---

## 8. Outstanding

| Item | Description | Direction |
|---|---|---|
| Cold-start/warm-reset board-level state-class intermittents | Two hard instances: cam1 source stream loss at 77s (recovered by re-burning the bit), 4K black screen (recovered by a power cycle); the FPGA internals are normal, the external chip does not self-recover after an anomaly | Firmware watchdog: detect a stalled df counter → re-initialize the corresponding path (replay the TX reset chain / power-cycle the GPIO) |
| fr1 anchor cross-domain read tearing | The DIAG17 anchor cross-domain read has no handshake and occasionally reads dirty; a diagnostic-convention issue only, not a functional defect | Add gray synchronization later, or take the majority of several samples |
| Retired files still in the compile list | disp_timing_gen.v / disp_line_fifo.v are not instantiated; this time they interfered via SV syntax errors | Can be moved out of the XML design_info |

---

## 9. Reproduction and Rollback

```tcl
# synthesis (map)
efx_map --project-xml ws-e1-cam-ddr-csi2.xml --root top_cam_demo --project ws-e1-cam-ddr-csi2 --work-dir work_syn --output-dir outflow
# PnR / bitstream generation (PowerShell, EFINITY_HOME must use forward slashes)
$env:EFINITY_HOME = "D:/Efinity/2026.1"
efx_pnr / efx_pgm --project-xml ws-e1-cam-ddr-csi2.xml --family Titanium --device Ti180A484S ...
```

- Firmware: `D:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin` (riscv-none-elf-gcc),
  sw/top_demo project, the ELF loaded via openocd.
- Simulation: tb_phase4 / tb_phase4_ddrm / tb_phase5_cam1 (criteria in §4).
- Rollback: this project has no git; backup/ holds the earlier v14c/v15 baselines (including the shape era).
  There is no v4.10c3m source snapshot, so rolling back requires manually removing the cam1 integration from top_cam_demo.sv
  (u_fw1/u_rd1/arb/cdc hookup, u_cam_1 display gating, rd_rstn_1080), not recommended;
  when the cam1 chain misbehaves, isolating it directly with the 'p'/'c' soft switch is enough.
