---
kind: carrier
id: ws-e2-rk3588-mc
belongs_to_board: ws-e2
---

# WS-E2 RK3588 MC Carrier (SOM_NOR Variant)

[中文](ws-e2-rk3588-mc.md) | English

This document describes the `ws-e2-rk3588-mc` carrier (MC-V01, SOM_NOR boot
variant). The material was produced by the ws-e2 v2.0.1 material campaign and
re-checked under the v2.0.1 errata. Every field defers to the CONFIRMED facts in
`board.yaml` / `hardware.yaml` / `platforms/rk3588/platform.yaml`; this file is
an index and boundary note, not a new fact source.

## 1. Key confirmed facts (summary)

| Dimension | Confirmed value | Source |
|---|---|---|
| SoC | Rockchip RK3588J | `platforms/rk3588/platform.yaml` |
| DDR | 2x LPDDR4X ATL4X8G32M2D-46 IT (8 GB total, customer-confirmed 2026-11-10) | same file, `ddr` section (CUSTOMER_CONFIRMED_2026-11-10) |
| Boot | eMMC HS400 8-bit (SOM_NOR variant) | same file, `boot_storage` section |
| Debug UART | UART2_M0_DEBUG, 1500000 baud, ttyS2 | same file, `debug_uart` section |
| Expected DTB | `ws-e2-rk3588-mc.dtb` (source `platforms/rk3588/ws-e2-rk3588-mc.dts`) | same file, `expected_dtb` |
| Environment | Linux Environment Manager `rk3588-ai@2026.11.1` (contract environment-manager/v1, LINUX_ENVIRONMENT_MANAGER_SATISFIED) | same file, `environment` section |
| FPGA side | TJ375N1156X; Stage0 jacket and banks ISF under `jackets/stage0/`, `constraints/` | `board.yaml` artifacts |

## 2. Relationship to the rk3588j-evm carrier

Two carrier variants of the same WS-E2 SOM: `rk3588j-evm` (evaluation baseboard)
and this carrier (MC-V01, SOM_NOR). They share the same RK3588J device authority
(`devices/RK3588J.authority.json`, coverage: subset) and the same Linux
Environment Manager environment; DTS, boot storage and platform configuration are
independent, see each carrier's `platforms/rk3588/`.

## 3. Material boundary (as of 2026-11-14)

- The generation chain (`project.generate`) currently has full generation material
  only for `rk3588j-evm/minimal-linux`. This carrier's `reference-projects/` and
  `bsp/manifest.json` are not delivered yet: a generate call with
  `carrier=ws-e2-rk3588-mc` reports `RK_PROJECT_MATERIAL_MISSING` with the missing
  list instead of silently binding EVM material.
- The RK3588J authority covers a derived subset of the 350-ball package
  (coverage: subset); balls outside it report `AUTHORITY_COVERAGE_GAP` and must be
  confirmed against the full package map before release. See the version contract in
  [docs/release-README.en.md](../../../../docs/release-README.en.md).
