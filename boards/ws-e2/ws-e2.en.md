---
ws_manifest_version: 2
kind: module
id: ws-e2
material_version: 2.0.1
fpga:
  vendor: efinix
  family: Titanium
  part: TJ375N1156X
soc:
  vendor: rockchip
  part: RK3588J
carriers:
  - ws-e2-rk3588-mc
---

[中文](ws-e2.md) | English

# WS-E2 — TJ375 + RK3588J Heterogeneous SOM (SOM_NOR)

Efinix **TJ375N1156X** (Titanium, FCBGA1156) + Rockchip **RK3588J** (FCBGA1088) heterogeneous
system-on-module. Module schematic authority: **TBS2009_SOM_NOR** (Shennan Circuits V1.0,
34 pages, 2026-09-18); carrier: **WS-E2-RK3588-MC-V01** (Elitestek V1.0, 25 pages, 2026-10-14).
FPGA and SoC are directly linked in-module (MIPI DPHY0/1/2, RGMII, SPI/I2C/GPIO) and exit
through 4x 66B2 BTB connectors to the MC-V01 baseboard.

## Storage and boot (NOR variant authority)

| Device | Role | Notes |
|---|---|---|
| GD25LB512MEYIGR | TJ375 configuration flash | QSPI NOR 512Mb, active-serial x4 (FPGA_CDI0-3/SS/CCK), som p21-22 |
| W66DP2RQQAGJ | TJ375 LPDDR4/4X DRAM | 32-bit single channel, U2 fitted / U3 DNP (som p24 title `24.TJ375_DDR0&1`) |
| FEMDRW128G-88A19 | RK3588 boot eMMC | HS400 8-bit+DS (som p16) |
| FEMDRW032G x2 | FPGA eMMC (carrier-side) | terminates module F_EMMC_* nets (mc p15) |
| RK806-1 | PMIC | RK3588 domain supplies (som p13-14) |

> Errata (2026-11-13): W66DP2RQQAGJ role corrected from "serial NAND" to FPGA LPDDR4/4X DRAM;
> RTL8111HS downgraded to UNVERIFIED (comment-only), the fitted PCIe GbE NIC is YT6801SH (mc p10).

## Carrier (ws-e2-rk3588-mc V01)

- RK side: RJ45 (RTL8211FI-CG PHY), YT6801SH PCIe NIC, ES8388 audio, USB2/TypeC0-1, HDMI
  TX/RX, microSD, PCIe30X1_0/1 + PCIe20_0/1/2 (SATA muxing), Maskrom button (SARADC_IN0),
  FT232RL debug UART.
- FPGA side: FMC-A HPC, SFP+ x2, SDI (LMH1218/1219 + LMKDB1202), CAN x2 (TJA1051T),
  RS485 (CMT83085), RS232, EtherCAT (LAN9252I + RTL8211FI), keys/LEDs/DIP, PWM fan.
- Power: DC 12 V input (XDJK-060B-055) -> TPS family 5.0/3.318/2.544/1.8/1.2 V +
  VCC_5V0_SOM (TPS548A28) + selectable FMC_VADJ; INA226 power monitor; SOM_PWR_GOOD.

## Status

- Material version **2.0.1** (errata); generator verdict `INCOMPLETE`: 58 rk3588 BTB rows
  `FINAL_ENDPOINT_REQUIRED` (connector pin numbers need graphical/user input) + 1 unresolved
  official build environment source.
- Stage0 jacket: `NATIVE_BUILD_NOT_RUN`.
- Full manual: `carriers/ws-e2-rk3588-mc/docs/generated/board-manual.md`.
- Legacy BSP identity (rk3588j-evm, assembled 2026-11-11): `carriers/rk3588j-evm/bsp/manifest.json`,
  materialized at `<EVOVERSE_HOME>/bsp/ws-e2/99a56fe7`.
