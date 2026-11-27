---
ws_manifest_version: 1
kind: ip
id: ethernet-rgmii
display_name: Ethernet RGMII (TSE MAC)
version: 1.0.0
board: ws-e1
carrier: ws-e1-base
maintainer: evoverse
license: proprietary
description: Tri-Mode Ethernet MAC (TSE) with RGMII PHY interface, including packet generator and loopback logic.
---

English | [中文](ethernet-rgmii.md)

# Ethernet RGMII (TSE MAC)

## Source Demo
`demos/ethernet-tse-udp-test/` (formerly `TJ180A484_TSE/`)

## Hard IP Configuration
- **efx_tsemac** (Efinix Ethernet TSE MAC)
  - vendor: efinixinc.com, library: ethernet, name: efx_tsemac, version: 4.3
  - Efinity IP generation tool version: 2022.2.322
  - Configuration: TX/RX FIFO enabled (depth 2048), AXIS data width 8-bit, PHY interface mode 0
  - settings.json located at rtl/settings.json

## RTL Files
| File | Description |
|------|------|
| temac_ex.v | Top module - TEMAC example design integrating the TSE MAC + RGMII PHY interface |
| test_tse.v | Efinity TSE MAC IP core wrapper |
| test_tse_tmpl.v | TSE MAC IP template file |
| test_tse_define.vh | TSE MAC macro definitions |
| header.v | Global header include |
| DaulClkFifo.v | Dual-clock FIFO for clock domain crossing (CDC) data buffering |
| apb3_2_axi4_lite.v | APB3 to AXI4-Lite bridge |
| axi4_st_mux.v | AXI4-Stream multiplexer |
| mac_pat_gen.v | MAC-layer packet generator |
| udp_pat_gen.v | UDP packet generator |
| mac_rx2tx.v | MAC receive-to-transmit loopback logic |
| rgmii_2_rmii.v | RGMII to RMII conversion |
| reg_apb3.v | APB3 register interface |

## Constraints
| File | Description |
|------|------|
| temac_ex.peri.xml | Peripheral pin constraints (Interface Designer) |
| timing_Ti60.sdc | Timing constraint file |

## Interfaces
- **RGMII PHY**: rgmii_txd[3:0], rgmii_tx_ctl, rgmii_txc, rgmii_rxd[3:0], rgmii_rx_ctl, rgmii_rxc
- **PHY control**: phy_rstn, phy_mdc, phy_mdio
- **Clocks**: clk (system clock), clk_125m (RGMII 125MHz reference clock)
- **JTAG**: jtag_inst1_* (hard JTAG debug interface)
- **Reset**: pll_rstn, pll_0_locked

## Use Cases
Gigabit Ethernet interface on the ws-e1-base carrier board, connecting to an external PHY chip (e.g., RTL8211) over the RGMII protocol to implement network communication. Supports MAC/UDP packet generation and loopback testing.
