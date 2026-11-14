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
description: 通过 Sapphire SoC (RISC-V) 的 I2C 总线读取板载 BMI088 六轴 IMU（加速度计 + 陀螺仪）数据，演示 SoC I2C 主机三态转换与传感器驱动。
---

[English](bmi088-imu.en.md) | 中文

# BMI088 6-Axis IMU (I2C)

## 来源 Demo
`demos/imu-bmi088-readout/`（原 `imu_bmi088/`）

## 硬核 IP 配置
- **soc** (Efinix EfxSapphireSoc) — VLNV: `efinixinc.com:soc:efx_soc:3.2.3`
  - 配置文件：`rtl/ip/soc/settings.json`
  - 内含 RISC-V SoC、on-chip 存储、I2C/UART/SPI/GPIO 外设

## RTL 文件
- `rtl/top_soc.v` — 顶层，含 I2C 三态转换（sda/scl writeEnable+write+read）、Si5338 时钟监测
- `rtl/soc_onchip.v` — SoC on-chip 存储实例
- `rtl/soc_onchip_define.vh` — on-chip 宏定义
- `rtl/design_modules.v` — 设计模块列表

## 固件
- `fw/bmi088_i2cMasterDemo_main.c` — BMI088 I2C 驱动主程序（i2cMasterDemo），读取加速度计(0x18)/陀螺仪(0x68)数据
- `fw/userDef.h` — 用户定义
- `fw/i2c.h` — I2C 驱动头文件

## 约束
- `constraints/constraints.sdc` — 时序约束
- `constraints/soc.peri.xml` — 外设/引脚约束

## 接口
- I2C 总线（接 BMI088）：`system_i2c_0_io_sda_writeEnable` / `system_i2c_0_io_sda_write` / `system_i2c_0_io_sda_read` / `system_i2c_0_io_scl_writeEnable` / `system_i2c_0_io_scl_write` / `system_i2c_0_io_scl_read`
- UART：`system_uart_0_io_txd` / `system_uart_0_io_rxd`
- SPI：`system_spi_0_io_*`
- GPIO：`system_gpio_0_io_read[3:0]` / `system_gpio_0_io_write[3:0]`
- 时钟/复位：`io_systemClk` / `systemClk_locked` / `arst_n` / `si5338_pll_clk_156m25`

## 应用场景
通过 SoC I2C 主机读取板载 BMI088 IMU 的加速度与角速度数据，是惯性测量、姿态感知等应用的基础外设驱动参考。
