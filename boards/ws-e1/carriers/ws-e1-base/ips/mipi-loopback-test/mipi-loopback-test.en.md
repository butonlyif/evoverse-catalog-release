---
ws_manifest_version: 1
kind: ip
id: mipi-loopback-test
display_name: MIPI CSI-2 Loopback Test (TX→RX BIST)
version: 1.0.0
board: ws-e1
carrier: ws-e1-base
maintainer: evoverse
license: proprietary
description: MIPI CSI-2 Loopback test IP for board-level TX→RX signal integrity verification. TX generates PRBS9 test patterns, RX receives and verifies data integrity. 2-lane configuration with debug enabled.
---

English | [中文](mipi-loopback-test.md)

# MIPI CSI-2 Loopback Test (TX→RX BIST)

## Source Demo
`demos/mipi-loopback-test/` (formerly `TJ180MIPI_loopback/`)

## Hard IP Configuration
| IP name | VLNV | Version | Key parameters |
|---------|------|------|---------|
| hard_csi_rx | efinixinc.com:mipi:efx_csi2_rx_top | 5.15 | 2 data lanes, ASYNC_STAGE=2, CLOCK_FREQ=100MHz, PIXEL_FIFO_DEPTH=2048, DEBUG enabled |
| hard_csi_tx | efinixinc.com:mipi:efx_csi2_tx_top | 5.14 | 2 data lanes, HS_BYTECLK=60MHz, Continuous clock, PIXEL_FIFO_DEPTH=2048 |

- Efinity toolchain version: 2025.2.288.4.15

## RTL Files
| File | Description |
|------|------|
| `rtl/Top.v` | Top module — MIPI loopback test platform |
| `rtl/reset.v` | Parameterized reset synchronizer |
| `rtl/efx_csi2_rx.sv` | CSI-2 RX controller top level (soft-logic wrapper) |
| `rtl/efx_csi_tx.sv` | CSI-2 TX controller top level (soft-logic wrapper) |
| `rtl/efx_csi_tx_define.vh` | TX controller macro definitions |
| `rtl/efx_ram_10k.v` | Efinity 10Kb BRAM wrapper |
| `rtl/hard_csi_rx.sv` | MIPI CSI-2 RX DPHY hard IP wrapper |
| `rtl/hard_csi_rx_define.svh` | RX wrapper macro definitions (SystemVerilog) |
| `rtl/hard_csi_rx_define.vh` | RX wrapper macro definitions (Verilog) |
| `rtl/hard_csi_tx.sv` | MIPI CSI-2 TX DPHY hard IP wrapper |
| `rtl/hard_csi_tx_define.svh` | TX wrapper macro definitions (SystemVerilog) |
| `rtl/hard_csi_tx_define.vh` | TX wrapper macro definitions (Verilog) |
| `rtl/MIPI_Parameter.v` | MIPI system parameter definitions |
| `rtl/MIPITest.v` | MIPI test control FSM |
| `rtl/MIPITxProcess.v` | MIPI TX data processing |
| `rtl/MipiRxProcess.v` | MIPI RX data processing |
| `rtl/MipiPixelData.v` | MIPI pixel data generation/verification |
| `rtl/PRBS9.v` | PRBS9 pseudo-random sequence generator (BIST test pattern) |
| `rtl/hard_csi_rx_settings.json` | RX IP generation configuration |
| `rtl/hard_csi_tx_settings.json` | TX IP generation configuration |

## Constraints
| File | Description |
|------|------|
| `constraints/top.sdc` | Top-level timing constraints |
| `constraints/mipi.sdc` | MIPI-specific timing constraints |
| `constraints/Ti180MIPI.peri.xml` | Peripheral/pin constraints (MIPI DPHY TX/RX pin assignment) |
| `constraints/Ti180_mipi_io.isf` | Efinity Interface Designer file (I/O bank configuration) |

## Interfaces
- **Clock**: `MIPI_REF_CLK`
- **PLLs**: `pll_inst1_LOCKED`, `pll_inst2_LOCKED`
- **MIPI DPHY RX (inst2)**: 2-lane HS data (16-bit per lane), ESC/LP/ULPS state, SKEWCAL, SYNC, error signals (ERR_CONTENTION, ERR_SOT_HS, SOTSYNC_ERROR, LINESTATE_ERROR)
- **MIPI DPHY TX (inst1)**: 2-lane HS data, STOPSTATE, TX_REQUEST_HS, ULPS control
- **BIST**: PRBS9 pseudo-random pattern generation + verification, with an AXI4-Lite polling FSM controlling the test flow

## Use Cases
MIPI CSI-2 signal integrity testing on the ws-e1-base carrier board. The TX sends PRBS9 pseudo-random test patterns that loop back to the RX through the on-board MIPI traces, verifying the signal quality of the high-speed serial link. Suitable for production testing, hardware bring-up, and signal integrity debugging. 2-lane configuration, with the RX in debug mode to capture full error information.
