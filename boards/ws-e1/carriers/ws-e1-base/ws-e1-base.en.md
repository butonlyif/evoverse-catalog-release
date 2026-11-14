---
ws_manifest_version: 2
kind: carrier
id: ws-e1-base
display_name: WS E1 Base Board
version: 0.1.0
status: active
belongs_to_board: ws-e1
constraint_owner: carrier
pinout_csv: pinout/ws-e1-base.csv
jackets:
  - stage0
---
English | [中文](ws-e1-base.md)

# WS E1 Base Board (Carrier)

| Attribute | Value |
| --- | --- |
| Board ID | `ws-e1-base` |
| Type | carrier (base board) |
| Paired core module | `ws-e1` |
| Documentation baseline | Carrier schematic TJ180A484S_BASE_SCH_260323A0.pdf |

## 1. Product Overview

WS-E1-Base is the application carrier board paired with the WS-E1 core module. Through the
168-pin B2B connector P4 (mated with the core module's P10), the carrier expands the FPGA's
100 user IOs, JTAG, and power into standard interfaces:

- USB Type-C (PD sink + USB3.2 data)
- MIPI DSI / CSI (40-pin B2B × 2)
- FMC HPC (400-pin, passed through P4)
- Gigabit Ethernet (YT8512H PHY)
- microSD (SDIO3.0)
- Fan (4-pin PWM + tach)
- User pushbuttons × 4 / user LEDs × 2 / PMOD × 3
- IMU (BMI088 6-axis)
- Programmable clock (Si5338A, 4 differential outputs)
- eMMC 5.1 (32GB)
- JTAG / SWD debug

## 2. Key Devices

| Device | Part Number | Description |
| --- | --- | --- |
| Ethernet PHY | YT8512H-CA | Motorcomm 1000BASE-T, RGMII |
| eMMC | KLMBG2JETD-B041 | Samsung 32GB eMMC 5.1 |
| Clock generator | Si5338A | Programmable, 4 differential outputs, I²C configuration |
| IMU | BMI088 | Bosch 6-axis (accel + gyro) |
| PD controller | CH224Q | USB-C PD 12V sink negotiation |
| 5V/4A DC-DC | GM6503AA2.8R7 | 12V→5V |
| 1.8V/3A DC-DC | BL3315-1.5R2 | 5V→1.8V |
| 3.3V/3A DC-DC | BL3315-1.5R2 | 1.8V→3.3V |

## 3. Connectors

| Connector | Part Number | Description |
| --- | --- | --- |
| P4 | DF40C-100DS | 100-pin B2B → core module P10 (FX10A-168P) |
| J1 | PJ-102BH | 12V DC barrel |
| J2 | KH-TYPE-C-16P | USB-C PD 12V input |
| J4 | TYPE-C-16P | USB3.2 Type-C (connects to core FX10) |
| J5 | QSE-020-01-F-D-A | MIPI CSI-2 (40-pin B2B) |
| J6 | QSE-020-01-F-D-A | MIPI DSI (40-pin B2B) |
| J7 | 47053-1000 | Fan 4-pin |
| J8 | TF-01A | microSD |
| J9 | CN_2x6 | PMOD0 (12-pin) |
| J10 | CN_2x6 | PMOD1 (12-pin) |
| J11 | CN_2x6 | PMOD2 (12-pin, 2C bank) |
| J3 | ASP-134486-01 × 2 | FMC HPC (400-pin, passed through P4) |

## 4. Power Architecture

| Rail | Voltage | Source |
| --- | --- | --- |
| VIN12V | 12V | DC barrel (J1) or USB-C PD (J2) |
| VBUS | 5V (typ) | USB-C VBUS |
| VDD5V | 5V | GM6503 buck |
| D1V8 | 1.8V | BL3315 buck |
| D3V3 | 3.3V | BL3315 buck |

## 5. Bank Power

The authoritative source is `constraints/ws-e1-base.banks.isf` (`constraint_owner: carrier`),
consistent with the `*.peri.xml` bank-voltage declarations of the demo projects that have been
verified on this board (TJ180A484S_SDHOST, SI5338/soc_lpddr4, imu_bmi088,
TJ180J484_CSI_4k, etc.):

| Bank | Voltage | Description |
| --- | --- | --- |
| 2A_2B / 2C / 3A / 3B / 3C | 1.8 V | VDD18 rail |
| 4A / 4B / 4C | 1.8 V | VDD18 rail (LPDDR4 / config) |
| BL / BR / TL / TR | 3.3 V | VDD33 rail (four corners) |

> Note: some demo projects leave the **unused** corner banks at the Efinity default 1.8 V
> (e.g., TJ180MIPI_loopback sets all four corners to 1.8 V); this does not constitute a
> board-level power declaration. Every project that actually uses corner IOs sets 3.3 V.

## 6. Stage-0 Jacket Pin Mapping

| Signal | Ball | Bank | Bank Voltage | Board Side |
| --- | --- | --- | --- | --- |
| `clk_50m` (main_clock) | T18 | TL | 3.3V | Core module U13 50MHz OSC |
| `arst_n` (reset) | H21 | 2C | 1.8V | Carrier S1 pushbutton |
| `led_user` (user_led) | F21 | 2C | 1.8V | Carrier D25 user LED via Q4 |

> Note: the external circuits of the S1 pushbutton / D25 LED use a 3.3V pull-up (D3V3 rail),
> but the 2C bank VCCIO is fixed at 1.8 V by the core module's VDD18; the IO constraint for
> these signals must be written as 1.8 V LVCMOS, consistent with the demo projects
> (2C = 1.8 V).

For the complete pin mapping see [`pinout/ws-e1-base.csv`](pinout/ws-e1-base.csv)
(16 rows: 3 jacket + 2 LED + 3 pushbuttons + 8 PMOD2).
