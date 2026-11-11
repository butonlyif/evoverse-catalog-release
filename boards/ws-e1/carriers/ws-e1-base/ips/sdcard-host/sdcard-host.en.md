---
ws_manifest_version: 1
kind: ip
id: sdcard-host
display_name: SD Card Host Controller
version: 1.0.0
board: ws-e1
carrier: ws-e1-base
maintainer: evoverse
license: proprietary
description: SD Host controller integrated with RISC-V SoC, supporting SDIO and ADMA for SD/SDHC/SDXC card access.
---

English | [中文](sdcard-host.md)

# SD Card Host Controller

## Source Demo
`demos/sdcard-powercycle-retention/` (formerly `TJ180A484S_SDHOST/`)

## Hard IP Configuration
- **efx_sd_host_controller** (SD Host controller)
  - vendor: efinixinc.com, library: memory_controller, name: efx_sd_host_controller, version: 6.0
  - Efinity IP generation tool version: 2025.1.110.4.9
  - Configuration: DATA_BUFFER_DEPTH=512, ADMA_DATA_WIDTH=32
  - settings.json located at rtl/tj180a484s_sdhost.settings.json

- **efx_soc** (RISC-V SoC - soc_ti180)
  - vendor: efinixinc.com, library: soc, name: efx_soc, version: 3.2.3
  - Configuration: 100MHz CPU, DDR enabled (LPDDR4, 512-bit), AXI Master x2, APB Slave x4
  - settings.json located at rtl/soc_ti180.settings.json

- **efx_apb3_2_axi4_lite** (APB3 to AXI4-Lite bridge)
  - vendor: efinixinc.com, library: bridges_and_adaptors, name: efx_apb3_2_axi4_lite, version: 5.2
  - Configuration: ADDR_WTH=10
  - settings.json located at rtl/apb3_2_axi4_lite_sdhost.settings.json

## RTL Files
| File | Description |
|------|------|
| TJ180A484S.v | Board-level top module - SOC + SD Host integration |
| top_soc_sd.v | Minimal SOC + SD Host wrapper (Sapphire SoC + SDHC + APB bridge) |
| top_soc_oob.v | OOB (Out-of-Box) mode top level |
| tj180a484s_sdhost.v | SD Host controller IP core |
| tj180a484s_sdhost_tmpl.v | SD Host IP template |
| tj180a484s_sdhost_define.vh | SD Host macro definitions |
| apb3_2_axi4_lite_sdhost.v | APB3 to AXI4-Lite bridge (SDHC register access) |
| apb3_2_axi4_lite_sdhost_tmpl.v | APB3 bridge template |
| apb3_2_axi4_lite_sdhost_define.vh | APB3 bridge macro definitions |
| axi4_to_axi4l.v | AXI4 to AXI4-Lite converter |
| soc_ti180.v | RISC-V SoC IP core |
| soc_ti180_tmpl.v | SoC IP template |
| soc_ti180_define.vh | SoC macro definitions |

## Constraints
| File | Description |
|------|------|
| TJ180A484S.peri.xml | Peripheral pin constraints (Interface Designer), including SD card pin assignments |
| tj180a484.sdc | Timing constraint file |

## Interfaces
- **SD bus**: sd_cmd, sd_dat[3:0], sd_cd_n (card detect), sd_clk
- **Clocks**: clk_50M, i_soc_clk, i_sd_clk, i_axi0_mem_clk, i_axi1_mem_clk
- **DDR AXI**: ddr_inst_* (dual-port AXI4 DDR interface, 512-bit)
- **UART**: system_uart_0 (debug serial port)
- **SPI**: system_spi_0 (SPI Flash)
- **JTAG**: jtag_inst1_* (debug interface)

## Use Cases
Implements the SD card interface on the ws-e1-base carrier board. The SD Host controller works with the RISC-V SoC to provide read/write access to SD/SDHC/SDXC cards, supporting ADMA2 transfers and SDIO mode. Suitable for data storage, logging, and file system (FatFs) applications.
