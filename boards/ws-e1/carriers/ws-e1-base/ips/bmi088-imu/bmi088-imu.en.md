---
ws_manifest_version: 1
kind: ip
id: bmi088-imu
display_name: BMI088 6-Axis IMU (I2C)
version: 1.0.0
board: ws-e1
carrier: ws-e1-base
maintainer: evoverse
license: proprietary
description: Reads the on-board BMI088 6-axis IMU (accelerometer + gyroscope) data over the I2C bus of the Sapphire SoC (RISC-V), demonstrating SoC I2C master tri-state handling and sensor driver development.
---

English | [中文](bmi088-imu.md)

# BMI088 6-Axis IMU (I2C)

## Source Demo
`demos/imu-bmi088-readout/` (formerly `imu_bmi088/`)

## Hard IP Configuration
- **soc** (Efinix EfxSapphireSoc) — VLNV: `efinixinc.com:soc:efx_soc:3.2.3`
  - Configuration file: `rtl/ip/soc/settings.json`
  - Contains the RISC-V SoC, on-chip memories, and I2C/UART/SPI/GPIO peripherals

## RTL Files
- `rtl/top_soc.v` — top level, with I2C tri-state handling (sda/scl writeEnable+write+read) and Si5338 clock monitoring
- `rtl/soc_onchip.v` — SoC on-chip memory instance
- `rtl/soc_onchip_define.vh` — on-chip macro definitions
- `rtl/design_modules.v` — design module list

## Firmware
- `fw/bmi088_i2cMasterDemo_main.c` — BMI088 I2C driver main program (i2cMasterDemo), reads accelerometer (0x18) / gyroscope (0x68) data
- `fw/userDef.h` — user definitions
- `fw/i2c.h` — I2C driver header

## Constraints
- `constraints/constraints.sdc` — timing constraints
- `constraints/soc.peri.xml` — peripheral/pin constraints

## Interfaces
- I2C bus (to the BMI088): `system_i2c_0_io_sda_writeEnable` / `system_i2c_0_io_sda_write` / `system_i2c_0_io_sda_read` / `system_i2c_0_io_scl_writeEnable` / `system_i2c_0_io_scl_write` / `system_i2c_0_io_scl_read`
- UART: `system_uart_0_io_txd` / `system_uart_0_io_rxd`
- SPI: `system_spi_0_io_*`
- GPIO: `system_gpio_0_io_read[3:0]` / `system_gpio_0_io_write[3:0]`
- Clock/reset: `io_systemClk` / `systemClk_locked` / `arst_n` / `si5338_pll_clk_156m25`

## Use Cases
Reads acceleration and angular-rate data from the on-board BMI088 IMU through the SoC I2C master, serving as the reference peripheral driver for inertial measurement, attitude sensing, and similar applications.
