---
EvoVerse_manifest_version: 1
kind: ip
id: i2c-master-rtl
display_name: I2C Master Controller (RTL)
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "Pure-RTL I2C master controller with two independent implementations: a compact Efinix-style master and a full OpenCores-style byte/bit controller"
---

English | [中文](i2c-master-rtl.md)

# I2C Master Controller (RTL)

## Source
Extracted from the following demo projects:
- MIPI_RX_sc850 (Efinix i2c_master IP)
- TJ180J484_CSI_4k_2370Ma (cam_i2c_ctrl / OpenCores-style i2c_master)

## Files
**Efinix style (from MIPI_RX_sc850):**
- `rtl/i2c_master.v` — Compact I2C master controller

**OpenCores style (from TJ180J484_CSI_4k_2370Ma cam_i2c_ctrl):**
- `rtl/i2c_master_top.v` — I2C master controller top level
- `rtl/i2c_master_byte_ctrl.v` — Byte-level control
- `rtl/i2c_master_bit_ctrl.v` — Bit-level control
- `rtl/i2c_master_defines.v` — Macro definitions
- `rtl/i2c_master_ctrl_top.v` — Camera I2C control top level
- `rtl/i2c_master_reg_rom.v` — Register configuration ROM
- `rtl/i2c_master_reg_set.v` — Register configuration sequence

## Interface
- **Efinix style**: `clk` / `rst` / `scl` / `sda` + APB/register configuration interface
- **OpenCores style**: `clk` / `rst` / `scl_i/o` / `sda_i/o` + Wishbone register interface

## Parameters
- Clock dividers, address widths, etc.: see the parameter / localparam declarations in each source file.

## Usage Examples
- MIPI_RX_sc850 — I2C initialization for SC850/SC535 camera sensors
- TJ180J484_CSI_4k_2370Ma — Register configuration sequence for a 4K MIPI camera
