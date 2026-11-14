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

[English](sdcard-host.en.md) | 中文

# SD Card Host Controller

## 来源 Demo
`demos/sdcard-powercycle-retention/`（原 `TJ180A484S_SDHOST/`）

## 硬核 IP 配置
- **efx_sd_host_controller** (SD Host 控制器)
  - vendor: efinixinc.com, library: memory_controller, name: efx_sd_host_controller, version: 6.0
  - Efinity IP 生成工具版本: 2025.1.110.4.9
  - 配置: DATA_BUFFER_DEPTH=512, ADMA_DATA_WIDTH=32
  - settings.json 位于 rtl/tj180a484s_sdhost.settings.json

- **efx_soc** (RISC-V SoC - soc_ti180)
  - vendor: efinixinc.com, library: soc, name: efx_soc, version: 3.2.3
  - 配置: 100MHz CPU, DDR 使能 (LPDDR4, 512-bit), AXI Master x2, APB Slave x4
  - settings.json 位于 rtl/soc_ti180.settings.json

- **efx_apb3_2_axi4_lite** (APB3 到 AXI4-Lite 桥接器)
  - vendor: efinixinc.com, library: bridges_and_adaptors, name: efx_apb3_2_axi4_lite, version: 5.2
  - 配置: ADDR_WTH=10
  - settings.json 位于 rtl/apb3_2_axi4_lite_sdhost.settings.json

## RTL 文件
| 文件 | 说明 |
|------|------|
| TJ180A484S.v | 板级顶层模块 - SOC + SD Host 集成 |
| top_soc_sd.v | SOC + SD Host 最小封装 ( Sapphire SoC + SDHC + APB 桥) |
| top_soc_oob.v | OOB (Out-of-Box) 模式顶层 |
| tj180a484s_sdhost.v | SD Host 控制器 IP 核 |
| tj180a484s_sdhost_tmpl.v | SD Host IP 模板 |
| tj180a484s_sdhost_define.vh | SD Host 宏定义 |
| apb3_2_axi4_lite_sdhost.v | APB3 到 AXI4-Lite 桥接 (SDHC 寄存器访问) |
| apb3_2_axi4_lite_sdhost_tmpl.v | APB3 桥接模板 |
| apb3_2_axi4_lite_sdhost_define.vh | APB3 桥接宏定义 |
| axi4_to_axi4l.v | AXI4 到 AXI4-Lite 转换器 |
| soc_ti180.v | RISC-V SoC IP 核 |
| soc_ti180_tmpl.v | SoC IP 模板 |
| soc_ti180_define.vh | SoC 宏定义 |

## 约束
| 文件 | 说明 |
|------|------|
| TJ180A484S.peri.xml | 外设引脚约束 (Interface Designer)，含 SD 卡引脚分配 |
| tj180a484.sdc | 时序约束文件 |

## 接口
- **SD 总线**: sd_cmd, sd_dat[3:0], sd_cd_n (卡检测), sd_clk
- **时钟**: clk_50M, i_soc_clk, i_sd_clk, i_axi0_mem_clk, i_axi1_mem_clk
- **DDR AXI**: ddr_inst_* (双端口 AXI4 DDR 接口, 512-bit)
- **UART**: system_uart_0 (调试串口)
- **SPI**: system_spi_0 (SPI Flash)
- **JTAG**: jtag_inst1_* (调试接口)

## 应用场景
用于 ws-e1-base 底板上的 SD 卡接口，通过 SD Host 控制器配合 RISC-V SoC 实现 SD/SDHC/SDXC 卡的读写访问，支持 ADMA2 传输和 SDIO 模式。适用于数据存储、日志记录和文件系统 (FatFs) 应用。
