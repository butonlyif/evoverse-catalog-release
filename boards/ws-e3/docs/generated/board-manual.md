# WS-E3 Titanium TJ375N484X Module board manual

Revision `1` · material `1.0.0` · composition `standalone`.

This combined manual presents the resolved product while preserving module and carrier facts as separate machine-owned layers.

## Architecture

```mermaid
flowchart LR
  n_fpga["fpga: Efinix TJ375N484X"]
  n_tj375n484x["tj375n484x: TJ375N484X"]
  n_qspi_flash["qspi_flash"]
  n_jtag_chain["jtag_chain"]
```

## Development targets

| Target | Type | Adapter | Exact device | State |
| --- | --- | --- | --- | --- |
| fpga | fpga | efinity | Efinix TJ375N484X | CONFIRMED |

## Pin coverage

| Target | Coverage | Evidence |
| --- | --- | --- |
| fpga | FUNCTIONAL_PINOUT_ONLY | pinout/ws-e3-v1.csv |

## Hardware

Facts below are rendered once from the resolved module/carrier layers. Intermediate board-to-board connector positions are intentionally excluded.

| ID | Category/Purpose | Manufacturer | Part | State | Sources |
| --- | --- | --- | --- | --- | --- |
| tj375n484x | — | — | TJ375N484X | CONFIRMED | ws-e3-schematic, ws-e3-stage0-isf |
| qspi_flash | — | — | — | CONFIRMED | ws-e3-schematic |
| jtag_chain | — | — | — | CONFIRMED | ws-e3-schematic |
| m2_conn_gpio | — | — | — | CONFIRMED | ws-e3-schematic |
| mipi2_tx_4lane | — | — | — | CONFIRMED | ws-e3-schematic |
| pcie_x4_m2 | — | — | — | CONFIRMED | ws-e3-schematic |
| user_led_d6 | — | — | — | CONFIRMED | ws-e3-schematic |

## Board interfaces

| ID | Protocol | Direction | Endpoints | State | Sources |
| --- | --- | --- | --- | --- | --- |

## Final cross-chip interface contract

| ID | Protocol | Direction | Final endpoints | Clock | Reset | State |
| --- | --- | --- | --- | --- | --- | --- |

## Power

| ID | Voltage | Consumers | State | Sources |
| --- | --- | --- | --- | --- |

## Clocks

| ID | Frequency | Consumers | State | Sources |
| --- | --- | --- | --- | --- |
| clk_100m_osc | 100000000 | — | CONFIRMED | ws-e3-schematic |
| pcie_refclk0_osc | 100000000 | — | CONFIRMED | ws-e3-schematic |

## Bring-up and development

### Bring-up

1. Review every `UNVERIFIED` or `CONFLICT` item before power-up.
2. Confirm rails, clock frequency, reset polarity, boot mode, and debug path from controlled sources.
3. Run the FPGA native unified compile; record compile evidence separately from programming and hardware evidence.
4. Bind the RK3588 profile to a real pinned BSP before any build claim.
5. Program, boot, and board-test only with their own evidence receipts.

### Development guide

| Target | Type | Adapter | Exact device | State |
| --- | --- | --- | --- | --- |
| fpga | fpga | efinity | Efinix TJ375N484X | CONFIRMED |

- FPGA Stage0 is generated from confirmed `main_clock`, `reset`, and `user_led` facts. A generated project is not a native-build PASS.
- RK3588 remains `PROFILE_READY` until a real source root, pinned BSP commit, build environment, loader, partition layout, and artifacts are explicitly bound.
- Use the System project when both targets and their interface contract must be developed together.

## Uncertainty and conflicts

No unresolved or conflicting facts are declared.

## Evidence sources

| ID | Type | Owner | Location | Observed | State |
| --- | --- | --- | --- | --- | --- |
| ws-e3-schematic | board_document | wsmicro | boards/ws-e3/ws-e3.md | 2026-09-22 | CONFIRMED |
| ws-e3-stage0-isf | toolchain_document | wsmicro | boards/ws-e3/jackets/stage0/constraints/ws_e3_stage0.pins.isf | 2026-09-22 | CONFIRMED |

Distributor and community pages are discovery-only and cannot confirm electrical or functional facts.
