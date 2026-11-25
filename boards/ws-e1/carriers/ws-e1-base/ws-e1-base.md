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
[English](ws-e1-base.en.md) | 中文

# WS E1 Base Board (Carrier)

| 属性 | 值 |
| --- | --- |
| 板 ID | `ws-e1-base` |
| 类型 | carrier（底板） |
| 配对核心板 | `ws-e1` |
| 文档基线 | 底板原理图 TJ180A484S_BASE_SCH_260323A0.pdf |

## 1. 产品概述

WS-E1-Base 是与 WS-E1 核心板配对使用的应用底板。底板通过 168-pin B2B 连接器
P4（与核心板 P10 对接）将 FPGA 的 100 个用户 IO、JTAG、电源扩展为标准接口：

- USB Type-C（PD 受电 + USB3.2 数据）
- MIPI DSI / CSI（40-pin B2B × 2）
- FMC HPC（400-pin，通过 P4 透传）
- 千兆以太网（YT8512H PHY）
- microSD（SDIO3.0）
- 风扇（4-pin PWM + tach）
- 用户按键 × 4 / 用户 LED × 2 / PMOD × 3
- IMU（BMI088 6-axis）
- 可编程时钟（Si5338A，4 路差分输出）
- eMMC 5.1（32GB）
- JTAG / SWD 调试

## 2. 主要芯片

| 器件 | 型号 | 说明 |
| --- | --- | --- |
| 以太网 PHY | YT8512H-CA | Motorcomm 1000BASE-T，RGMII |
| eMMC | KLMBG2JETD-B041 | Samsung 32GB eMMC 5.1 |
| 时钟发生器 | Si5338A | 可编程 4 路差分输出，I²C 配置 |
| IMU | BMI088 | Bosch 6-axis（accel + gyro） |
| PD 控制器 | CH224Q | USB-C PD 12V 受电协商 |
| 5V/4A DC-DC | GM6503AA2.8R7 | 12V→5V |
| 1.8V/3A DC-DC | BL3315-1.5R2 | 5V→1.8V |
| 3.3V/3A DC-DC | BL3315-1.5R2 | 1.8V→3.3V |

## 3. 接插件

| 接插件 | 型号 | 说明 |
| --- | --- | --- |
| P4 | DF40C-100DS | 100-pin B2B → 核心板 P10（FX10A-168P） |
| J1 | PJ-102BH | 12V DC barrel |
| J2 | KH-TYPE-C-16P | USB-C PD 12V 输入 |
| J4 | TYPE-C-16P | USB3.2 Type-C（连接到核心 FX10） |
| J5 | QSE-020-01-F-D-A | MIPI CSI-2（40-pin B2B） |
| J6 | QSE-020-01-F-D-A | MIPI DSI（40-pin B2B） |
| J7 | 47053-1000 | 风扇 4-pin |
| J8 | TF-01A | microSD |
| J9 | CN_2x6 | PMOD0（12-pin） |
| J10 | CN_2x6 | PMOD1（12-pin） |
| J11 | CN_2x6 | PMOD2（12-pin，2C bank） |
| J3 | ASP-134486-01 × 2 | FMC HPC（400-pin，通过 P4 透传） |

## 4. 电源架构

| 轨 | 电压 | 来源 |
| --- | --- | --- |
| VIN12V | 12V | DC barrel (J1) 或 USB-C PD (J2) |
| VBUS | 5V (typ) | USB-C VBUS |
| VDD5V | 5V | GM6503 buck |
| D1V8 | 1.8V | BL3315 buck |
| D3V3 | 3.3V | BL3315 buck |

## 5. Bank 供电

权威源为 `constraints/ws-e1-base.banks.isf`（`constraint_owner: carrier`），
与板上跑通过的 demo 工程（TJ180A484S_SDHOST、SI5338/soc_lpddr4、imu_bmi088、
TJ180J484_CSI_4k 等）的 `*.peri.xml` bank 电压声明一致：

| Bank | 电压 | 说明 |
| --- | --- | --- |
| 2A_2B / 2C / 3A / 3B / 3C | 1.8 V | VDD18 轨 |
| 4A / 4B / 4C | 1.8 V | VDD18 轨（LPDDR4 / config） |
| BL / BR / TL / TR | 3.3 V | VDD33 轨（四角） |

> 注：部分 demo 工程将**未使用**的四角 bank 保留 Efinity 默认 1.8 V
> （如 TJ180MIPI_loopback 全部四角 1.8 V），这不构成板级供电声明；
> 凡实际使用四角 IO 的工程均设 3.3 V。

## 6. Stage-0 jacket 引脚映射

| Signal | Ball | Bank | Bank 电压 | 板卡端 |
| --- | --- | --- | --- | --- |
| `clk_50m` (main_clock) | T18 | TL | 3.3V | 核心板 U13 50MHz OSC |
| `arst_n` (reset) | H21 | 2C | 1.8V | 底板 S1 pushbutton |
| `led_user` (user_led) | F21 | 2C | 1.8V | 底板 D25 user LED via Q4 |

> 注：S1 按钮 / D25 LED 外部电路使用 3.3V 上拉（D3V3 轨），但 2C bank
> VCCIO 由核心板 VDD18 决定为 1.8 V；信号 IO 约束需按 1.8 V LVCMOS 走，
> 与 demo 工程（2C=1.8 V）一致。

完整管脚映射见 [`pinout/ws-e1-base.csv`](pinout/ws-e1-base.csv)（16 行：3 jacket + 2 LED + 3 按钮 + 8 PMOD2）。
