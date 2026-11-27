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

[English](i2c-master-rtl.en.md) | 中文

# I2C Master Controller (RTL)

## 来源
从以下 demo 工程提取：
- MIPI_RX_sc850（Efinix i2c_master IP）
- TJ180J484_CSI_4k_2370Ma（cam_i2c_ctrl / OpenCores 风格 i2c_master）

## 文件
**Efinix 风格（来自 MIPI_RX_sc850）：**
- `rtl/i2c_master.v` — 紧凑型 I2C 主控制器

**OpenCores 风格（来自 TJ180J484_CSI_4k_2370Ma cam_i2c_ctrl）：**
- `rtl/i2c_master_top.v` — I2C 主控制器顶层
- `rtl/i2c_master_byte_ctrl.v` — 字节级控制
- `rtl/i2c_master_bit_ctrl.v` — 位级控制
- `rtl/i2c_master_defines.v` — 宏定义
- `rtl/i2c_master_ctrl_top.v` — 摄像头 I2C 控制顶层
- `rtl/i2c_master_reg_rom.v` — 寄存器配置 ROM
- `rtl/i2c_master_reg_set.v` — 寄存器配置序列

## 接口
- **Efinix 风格**：`clk` / `rst` / `scl` / `sda` + APB/寄存器配置接口
- **OpenCores 风格**：`clk` / `rst` / `scl_i/o` / `sda_i/o` + Wishbone 寄存器接口

## 参数
- 时钟分频、地址宽度等见各源文件内的 parameter / localparam 声明。

## 使用示例
- MIPI_RX_sc850 — SC850/SC535 摄像头传感器 I2C 初始化
- TJ180J484_CSI_4k_2370Ma — 4K MIPI 摄像头寄存器配置序列
