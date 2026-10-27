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
description: 通过 Sapphire SoC (RISC-V) 的 I2C 总线配置板载 Si5338A 可编程时钟芯片，演示 SoC + DDR + I2C 时钟配置完整流程。
---

[English](si5338-clkgen.en.md) | 中文

# Si5338 Programmable Clock Generator

## 来源 Demo
`demos/si5338-clock-config/`（工程文件位于 demo 根目录，原 `SI5338/SI5338/TJ180A484_soc_lpddr4/`）

## 硬核 IP 配置
- **sapphire_soc** (Efinix EfxSapphireSoc) — VLNV: `efinixinc.com:soc:efx_soc:3.2.3`
  - 配置文件：`rtl/ip/sapphire_soc/settings.json`
  - 内含 RISC-V SoC、DDR 控制器、PLL、APB3 slave、I2C 外设等

## RTL 文件
- `rtl/top_soc.v` — 顶层，包含 DDR 配置 FSM、timer_start、apb3_slave、memory_checker、I2C 三态转换（内联）
- `rtl/sapphire_soc.v` — Sapphire SoC 实例 wrapper
- `rtl/sapphire_soc_define.vh` — SoC 宏定义
- `rtl/design_modules.v` — 设计模块列表

## 固件
- `fw/main.c` — Si5338 I2C 配置主程序（i2cCfgSi5338 demo）
- `fw/Si5338-RevB-Registers.h` — Si5338 RevB 寄存器映射头文件
- `fw/i2c.h` — I2C 驱动头文件

## 约束
- `constraints/constraints.sdc` — 时序约束
- `constraints/soc.peri.xml` — 外设/引脚约束

## 接口
- I2C 总线（配置 Si5338）：`system_i2c_0_io_sda_writeEnable` / `system_i2c_0_io_sda_write` / `system_i2c_0_io_sda_read` / `system_i2c_0_io_scl_writeEnable` / `system_i2c_0_io_scl_write` / `system_i2c_0_io_scl_read`
- DDR AXI 接口（`io_ddrA_*`，含 ar/aw/w/b/r 五通道）
- JTAG 调试（`jtag_inst1_*`）、配置（`cfg_*`）
- 内存校验：`io_memoryResetn` / `memoryCheckerPass` / `ddr_pll_locked`

## 应用场景
通过 SoC 的 I2C 接口对板载 Si5338A 时钟芯片进行初始化配置，生成 FPGA 与外设所需的多种时钟频率，是板卡时钟树配置的标准参考。
