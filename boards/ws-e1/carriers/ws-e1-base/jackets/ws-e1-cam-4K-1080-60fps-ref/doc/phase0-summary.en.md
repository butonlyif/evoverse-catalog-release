[中文](phase0-summary.md) | English

# Phase 0 Summary — DDR Dual Asynchronous Port Prerequisite Validation (Architecture v4)

> Status: **Completed (2026-10-20)** · Spec: SPEC-001 rev.1 APPROVED · Corresponding requirements: R6 / RK-1 boundary definition / EV-09 confirmation

## 1. Goal

Validate every prerequisite of architecture v4: **can the Efinity DDR hard IP core (LPDDR4x, ddr_inst single controller with dual AXI ports) accept Port1 (axi_target1) running on an independent 148.5MHz AXI clock** (Port0 keeps the 200MHz write port)? If this prerequisite does not hold, the entire v4 (moving the reader into the display domain, deleting the data-path CDC) does not hold.

## 2. Key findings

- A **148.5MHz output already exists in the platform**: in `peri.xml`, CLKOUT1 of `pll_csi` (PLL_BL0, 27M reference) is named `pixel_clk` (VCO 1485M ÷10), conn_type=gclk — exactly the CSI TX pixel clock source — **no new PLL is needed**.
- The board-level top level is in fact `top_cam_demo.sv` (where the fw/fr instances live); the DDR is a single hard core with a dual AXI port structure (`axi_target0` / `axi_target1`, each with its own independent ACLK pin).
- The existing `disp_timing_gen.v` / `disp_line_fifo.v` are the direct foundation for the new architecture's disp_timing / tx_line_buf (a separate benefit).

## 3. Change list

| File | Change |
|---|---|
| `ws-e1-cam-ddr-csi2.peri.xml` | The `ACLK_1` clock source of `axi_target1` changed from `sys_clk_200m` → `pixel_clk` (single-point rebinding, Port0 untouched) |
| `rtl/top_cam_demo.sv` | New localparam `DDR_P1_148=1`; `FRAME_WRITER` temporarily 0 (fw/fr returns to idle, revertible); new generate branch `g_ddr_memtest_148`: the ready-made `ddr_memcheck` is hooked entirely to **target1 @ pixel_clk** (read/write phase-offset self-check, reusing the Phase 0 board-test form), with a pixel_clk-domain `reset_ctrl` (u_mc_rst_148) |
| Acceptance readout | DIAG11 @0x2C: `{err_cnt, mcst, ..., done_raw, st, lock, cfg_ok, done, fail}` |

## 4. Verification results

| Gate | Result | Notes |
|---|---|---|
| `efx_run --flow interface` | **PASS** | The peri.xml rebinding was accepted by Efinity 2026.1 (RK-1 tool-side boundary ✓) |
| `--flow map` | **PASS** | The new branch synthesizes with zero errors |
| `--flow pnr` | **PASS** | Routing + STA: slack +2.006ns inside the 148.5M domain; zero violations from the new logic; the negative slack on the 200M↔148.5M crossings is an **existing** CDC path (SDC has no async group, the same existed in the previous bitstream, not introduced this time) |
| **Board level** (loading the new bitstream on the board) | **PASS** | `cam_show` reads DIAG11: **err=0 st=3 lock=1 cfg=1 done=1 fail=0** — the 148.5M memcheck wrote the whole region and read it back with zero mismatches (26MB / 3495 bursts) |

**Conclusion: EV-09 is upgraded from PROPOSED to CONFIRMED. The dual asynchronous port prerequisite holds.**

## 5. Environment notes (toolchain CLI)

```powershell
# EFINITY_HOME already points at the install root in the environment, which skips setup.bat and causes a PYTHONHOME error;
# use a cmd chained call of setup.bat to set the whole environment at once:
cmd.exe /v:on /c "call D:\Efinity\2026.1\bin\setup.bat && D:\Efinity\2026.1\bin\efx_run.bat <project.xml> --flow <interface|map|pnr>"
# flow names: interface (peri processing) / map (synthesis) / pnr (routing + STA)
```

## 6. Rollback point / outstanding items

- Rollback: setting `FRAME_WRITER=1` and `DDR_P1_148=0` restores the v3.4 board-test form.
- New bitstream: `outflow/ws-e1-cam-ddr-csi2.bit` (the `g_ddr_memtest_148` branch; a black display is expected — the playback chain is not connected).
- RK-2 (FRAME_B vs the 2Gb capacity boundary) mitigation: the current layout 2×17.6MB=35MB ≪ 256MB; the memtest covers the 0~26MB region, which already includes the area before the boundary, and the Phase 1 data comparison covers it further.
