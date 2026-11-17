---
ws_manifest_version: 1
kind: ip
id: si5338-clkgen
display_name: Si5338 Programmable Clock Generator
version: 1.0.0
board: ws-e1
carrier: ws-e1-base
maintainer: evoverse
license: proprietary
description: Configure the on-board Si5338A programmable clock chip via the I2C bus of the Sapphire SoC (RISC-V), demonstrating the complete SoC + DDR + I2C clock configuration flow.
---

English | [中文](si5338-clkgen.md)

# Si5338 Programmable Clock Generator

## Source Demo
`demos/si5338-clock-config/` (project files at the demo root; formerly `SI5338/SI5338/TJ180A484_soc_lpddr4/`)

## Hard IP Configuration
- **sapphire_soc** (Efinix EfxSapphireSoc) — VLNV: `efinixinc.com:soc:efx_soc:3.2.3`
  - Configuration file: `rtl/ip/sapphire_soc/settings.json`
  - Contains the RISC-V SoC, DDR controller, PLL, APB3 slave, I2C peripheral, etc.

## RTL Files
- `rtl/top_soc.v` — top level, containing the DDR configuration FSM, timer_start, apb3_slave, memory_checker, and I2C tri-state conversion (inlined)
- `rtl/sapphire_soc.v` — Sapphire SoC instance wrapper
- `rtl/sapphire_soc_define.vh` — SoC macro definitions
- `rtl/design_modules.v` — design module list

## Firmware
- `fw/main.c` — Si5338 I2C configuration main program (i2cCfgSi5338 demo)
- `fw/Si5338-RevB-Registers.h` — Si5338 RevB register map header file
- `fw/i2c.h` — I2C driver header file

## Constraints
- `constraints/constraints.sdc` — timing constraints
- `constraints/soc.peri.xml` — peripheral/pin constraints

## Interfaces
- I2C bus (configures the Si5338): `system_i2c_0_io_sda_writeEnable` / `system_i2c_0_io_sda_write` / `system_i2c_0_io_sda_read` / `system_i2c_0_io_scl_writeEnable` / `system_i2c_0_io_scl_write` / `system_i2c_0_io_scl_read`
- DDR AXI interface (`io_ddrA_*`, with the five ar/aw/w/b/r channels)
- JTAG debug (`jtag_inst1_*`), configuration (`cfg_*`)
- Memory verification: `io_memoryResetn` / `memoryCheckerPass` / `ddr_pll_locked`

## Use Cases
Initializes and configures the on-board Si5338A clock chip through the SoC's I2C interface to generate the various clock frequencies required by the FPGA and peripherals; serves as the standard reference for board clock tree configuration.
