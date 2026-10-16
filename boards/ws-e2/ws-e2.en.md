---
ws_manifest_version: 2
kind: module
id: ws-e2
fpga:
  vendor: elitestek
  family: Titanium
  part: TJ375N1156X
---

English | [中文](ws-e2.md)

# WS-E2 — TJ375 Core Module (TBS2009) Documentation

Heterogeneous core module combining an Efinix **TJ375N1156X** (Trident-T, FCBGA1156, 673 pads, Efinity 2026.1) and a Rockchip **RK3588J**, manufactured by Shennan Circuits (schematics TBS2009_SOM_CAP/NOR, 34 pages). The FPGA and SoC interconnect directly on the module (MIPI CSI / PCIe 3.0 / RGMII / SPI / I2C / GPIO) and are brought out to the RK3588J EVM baseboard through a 1280-pin BTB connector.

## 1. Main Chips

| RefDes | Part | Function | Schematic Page |
|------|------|------|---------|
| U1 | **RK3588J** (FCBGA1088) | SoC: 4×Cortex-A76@2.4G + 4×A55, Mali-G610, 6TOPS NPU, 48MP ISP, HDMI2.1 TX×2/RX, PCIE3.0×2 (4 lanes), USB3×3, GMAC×2 | p4-p12 (part A-Z) |
| U2 | **TJ375N1156X** | FPGA: MIPI 3×(TX+RX) D-PHY, QSE SERDES 2×x4 (Q0/Q2, PCIe 3.0 hard core), DDR controller, active-serial x4 configuration | p20-p22, p26-p29 (part A-Z) |
| U2200 | **RK806-1** | Rockchip PMIC: 14 rails of BUCK/PLDO/ALDO, powering the entire RK3588 domain (VDD_CPU_BIG 0.75V@3.5A, VDD_NPU, VDD_GPU, etc.) + FPGA VCC_CORE | p13-14 |
| U3A/B… | **LPDDR4x 4GB** (Hynix H9 series) | RK3588 DDR (64bit, p5) | p5 |
| U38xx | **LPDDR4x 4GB** (Hynix H9 series) | TJ375 DDR (p24 DDR0_* channel) | p24 |
| U5 (p6) | eMMC (HS400, 8bit + DATA_STROBE + RSTN) | RK3588 boot storage | p6 |
| U3B | **W66DP2RQQAGJ** (Winbond SPI NAND 1Gb) | TJ375 data storage (via SPI/QSE) | p24 |
| U3800/U3801 | SPI FLASH (NOR; SOM_NOR variant uses GD25LB512MEYIGR 512Mb) | TJ375 configuration/boot source (active-serial x4: FPGA_CDI0-3/SS/CCK) | p15/p21 |
| X2 | 24MHz crystal | RK3588 XIN24M | p4 |
| Y group | 25MHz/100MHz crystals + **EZ8304A**×3 (clock fanout) | SOM local clock sources: CLK_25MHz, CLK_100M_0/1; PCIe REFCLK distribution | p19/p21/p30 |
| RJGT105T3 | Security chip | RK ecosystem secure OTA/keys | p22 |

> The SOM has two schematic variants: CAP (high-capacity eMMC configuration) and NOR (GD25 boot). This workspace is based on the CAP variant.

## 2. Power Architecture

- Input VCC_5V0 (supplied from the EVM through the BTB)
- **RK806-1**: all RK3588 core/IO rails + FPGA VCC_CORE (the 0.95V SERDES/core rail is supplemented by an independent buck on p30)
- FPGA IO banks: HSIO (2A-2E, 4A-4D) = 1.8 V, general-purpose IO (TL/TR/BL/BR) = 3.3 V, TL1_TL5 shared domain 3.3 V
  (all 24 banks explicitly declared in `jackets/stage0/constraints/banks.isf`, Efinity importer self-check passed)

## 3. TJ375 (FPGA) Pin Mapping

### 3.1 Functional Domain Distribution (319 pins; full list in `jackets/stage0/func-pinout-fpga.csv`)

| Domain | Count | Destination |
|----|------|------|
| MIPI (3×TX + 3×RX, CLK+D0-D3 per channel) | 60 | MIPI0/1_TX → RK CSI; the other 4 channels → BTB → EVM |
| QSE Q2 (SERDES x4 + REFCLK×2 + CAL_RES) | 21 | →BTB→EVM (QSE3/4 high-speed expansion) |
| PCIe Q0 (RXD0-3/TXD0-3) | 16 | →RK PCIE30 (direct connection inside the SOM) |
| BTB GPIO pass-through (B/L/R banks + PERST) | 147 | →BTB→EVM (PHY/EtherCAT/SDI/SFP/FMC/UART/KEY…) |
| Clock inputs (PLLIN×18 + EXTFB + crystal group) | 25 | SOM crystals + EVM clocks |
| GMAC0 RGMII | 12 | →RK (FPGA acts as the Ethernet PHY side of the RK) |
| RK GPIO/SPI/IIC | 10 | →RK |
| Configuration chain (JTAG 6 + CDI0-3/SS/CCK + NSTATUS/CBSEL×2) | 16 | SOM JTAG (EVM FT bridge) + configuration FLASH |
| REF_RES×3, other 4 | — | Reference resistors / test points |

### 3.2 FPGA↔RK3588 Interconnect Mapping (direct connections inside the SOM, 116 pin pairs)

**GMAC0 RGMII (12)**

| FPGA pin | ball | Signal | RK pin | RK ball |
|---|---|---|---|---|
| GPIOB_P_44_CLK11_P | M2 | GMAC0_TXCLK | GPIO2_B3_d | AE33 |
| GPIOB_N_36_CDI6 | P4 | GMAC0_RXD2 | GPIO2_A6_u | AC32 |
| GPIOB_P_36_CDI7 | P5 | GMAC0_RXDV_CRS | GPIO4_C2_d | AE31 |
| GPIOB_N_31 | U3 | GMAC0_TXEN | GPIO2_C0_d | AE34 |
| GPIOB_N_32 | T5 | GMAC0_RXD1 | GPIO2_C2_d | AD31 |
| GPIOB_N_34 | V1 | GMAC0_TXD2 | GPIO2_B1_u | AC33 |
| GPIOB_N_35 | U1 | GMAC0_TXD3 | GPIO2_B2_u | AC34 |
| GPIOB_P_31 | U4 | GMAC0_RXD0 | GPIO2_C1_d | AD32 |
| GPIOB_P_32 | R5 | GMAC0_RXD3 | GPIO2_A7_u | AC31 |
| GPIOB_P_33 | T4 | GMAC0_RXCLK | GPIO2_B0_u | AE32 |
| GPIOB_P_34 | V2 | GMAC0_TXD0 | GPIO2_B6_d | AD33 |
| GPIOB_P_35 | U2 | GMAC0_TXD1 | GPIO2_B7_d | AD34 |

**PCIe 3.0 QSE Q0 (2×2 mode: PORT0=lane0-1, PORT1=lane2-3, 16 lines)**

| FPGA pin | ball | Direction | RK port | RK ball |
|---|---|---|---|---|
| Q0_RXDN0/DP0 | B2/A2 | ← | PORT0_TX0N/P | D33/D32 |
| Q0_RXDN1/DP1 | B4/A4 | ← | PORT0_TX1N/P | C34/C33 |
| Q0_RXDN2/DP2 | B6/A6 | ← | PORT1_TX2N/P | E34/E33 |
| Q0_RXDN3/DP3 | B8/A8 | ← | PORT1_TX3N/P | D35/D34 |
| Q0_TXDN0/DP0 | D1/C1 | → | PORT0_RX0N/P | G34/G33 |
| Q0_TXDN1/DP1 | D3/C3 | → | PORT0_RX1N/P | F33/F32 |
| Q0_TXDN2/DP2 | D5/C5 | → | PORT1_RX2N/P | J34/J33 |
| Q0_TXDN3/DP3 | D7/C7 | → | PORT1_RX3N/P | K34/K33 |

Reference clock: Q0_REFCLK0 (F10/G10) → p19 clock buffer (PCIE30_REFCLK_SLOT) → RK PCIE30_REFCLK_IN;
Q0_CAL_RES@H9 connects to a 3.01K calibration resistor; Q0_REFCLK1 is left floating.

**MIPI CSI (FPGA TX → RK RX, 2 channels ×10)**

| FPGA channel | ball area | RK CSI0 | RK CSI1 |
|---|---|---|---|
| CLK0 P/N | AH6/AG6 (CSI0), AL32/AL31 (CSI1) | MIPI_CSI0_CLK0P/N @AJ33/AJ34 | MIPI_CSI1_CLK0P/N @AJ31/AJ32 |
| D0 P/N | AH2/AH1; AJ34/AJ33 | AG33/AG34 | AG31/AG32 |
| D1 P/N | AG3/AG2; AK33/AK32 | AH33/AH34 | AH31/AH32 |
| D2 P/N | AG4/AF4; AJ31/AK31 | AK33/AK34 | AK31/AK32 |
| D3 P/N | AH5/AH4; AL34/AL33 | AL33/AL34 | AL31/AL32 |

**GPIO / SPI / IIC (10)**

| FPGA pin | ball | Signal | RK pin | RK ball |
|---|---|---|---|---|
| GPIOB_P_47 | H1 | RK3588_GPIO01 | GPIO2_B4_u | AB31 |
| GPIOB_N_47 | H2 | RK3588_GPIO02 | GPIO2_B5_u | AB30 |
| GPIOB_P_48 | J2 | RK3588_GPIO03 | GPIO2_C3_d | AD30 |
| GPIOB_N_48 | J3 | RK3588_GPIO04 | GPIO2_C4_d | AC30 |
| GPIOB_P_49 | L3 | RK3588_SPI_CLK | GPIO4_C6_d | AF33 |
| GPIOB_N_49 | K3 | RK3588_SPI_MISO | GPIO4_C4_d | AB34 |
| GPIOB_P_50 | G1 | RK3588_SPI_MOSI | GPIO4_C5_d | AB33 |
| GPIOB_N_50 | G2 | RK3588_SPI_CS | GPIO4_C3_d | AF34 |
| GPIOB_P_51 | J4 | RK3588_IIC_SCL | GPIO1_C1_z | G27 |
| GPIOB_N_51 | H4 | RK3588_IIC_SDA | GPIO1_C0_z | G29 |

### 3.3 FPGA→EVM Interfaces (via BTB; net names prefixed TJ_ on the EVM side; full 164 nets in the func CSV)

| Interface | Signal count | EVM-side devices |
|------|--------|-----------|
| Second Ethernet RGMII (TJ_PHY0_*) | 16 | RTL8211FI PHY + RJ45 |
| EtherCAT slave (TJ_LAN9252_*: D0-D15 parallel bus + CS/A1-A4/SYNC/IRQ + TX/RX differential×2) | 25 | LAN9252 |
| SDI video ×2 (TX/RX differential + I2C) | 12 | SDI equalizer/driver + BNC |
| SFP optical ports ×2 (TX/RX + SCL/SDA + MOD_ABS/TX_DIS) | 16 | SFP cages |
| MIPI1_RX / MIPI2_RX / MIPI2_TX (HS pairs) | 60 | Camera connectors |
| UART×3 + FT debug serial port | 8 | MAX3232 / FT232 |
| JTAG (TCK/TMS/TDI/TDO/CRESET) + RISC-V JTAG | 9 | FT JTAG bridge |
| User buttons×4, DIP switches×2 | 6 | SKRPAME010 |
| QSE2/3/4 sideband GPIO | 15 | High-speed expansion |
| Clock group (TJ_GPIO L23/L25/L46/L52/R95/R97 ← EVM crystals) | 6 | EVM 25M/100M crystal group |

### 3.4 Configuration Chain (SOM local)

| Signal | FPGA pin | ball | Destination |
|------|----------|------|------|
| FPGA_CDI0-3 | GPIOB_N_40/P_38/N_39/P_40 | T1/P3/N4/R1 | Configuration FLASH (active-serial x4) |
| FPGA_SS | GPIOB_N_38_SSL_N | R3 | FLASH chip select |
| FPGA_CCK | GPIOB_P_39_CCK_PLLIN0 | N5 | Configuration clock |
| CFG_DONE | CDONE | F2 | Configuration done (pull-up) |
| CRESET_N | CRESET_N | G4 | Reset |
| TMS/TCK/TDI/TDO | — | JTAG | EVM FT bridge (via BTB) |
| NSTATUS | GPIOB_P_19_NSTATUS | — | Configuration status |
| CBSEL0/1 | GPIOB_N/P_23 | — | Boot mode selection |

## 4. RK3588 Pin Mapping

Full list in `jackets/stage0/func-pinout-rk3588.csv` (372 pins, cross-checked ball-by-ball
against the Rockchip RK3588 Datasheet V2.2 with 98.9% agreement).

| Domain | Count | Destination |
|----|------|------|
| FPGA direct connections (GMAC0 12 + CSI0/1 20 + PCIE30 16 + GPIO/SPI/IIC 10) | 58 | TJ375 (see table above) |
| eMMC (EMMC_D0-D7/CMD/CLKOUT/STROBE/RSTN) | 14 | SOM eMMC (Y33/W33/V32/AA33/Y32/AA32/W32/V33/W34/V34/Y34/AA34) |
| BTB→EVM (RK_GMAC1/USB3×2/TYPEC0/HDMI TX×2/HDMI RX/PCIe slot/SDMMC/UART DBG/I2S/SARADC…) | 184 | EVM peripherals |
| Power/clock (VCC/VDD/OSC/PMIC) | 50 | RK806-1 + 24M crystal |
| SOM local (KEY/BOOT/REXT/SARADC selection) | 46 | On-board resistors/buttons |

RK GMAC1 gigabit (RK_GMAC1_*_3V3, 16 nets) goes via BTB to the second RTL8211FI PHY on the EVM.

## 5. Directory

```
ws-e2/
├── ws-e2.md                 (this file)
├── pinout/ws-e2-module.csv  core module pinout (ball view, 302 unique balls)
└── carriers/rk3588j-evm/    baseboard (see rk3588j-evm.md)
```

Raw materials and extraction tools live at the workspace root: `SOM板原理图/`, `EVM板原理图/`, `_device/` (ballmap/extractor/verification reports), `tools/`. Verification results: FPGA usage 5 PASS/2 WARN; RK vs Rockchip datasheet 98.9%.
