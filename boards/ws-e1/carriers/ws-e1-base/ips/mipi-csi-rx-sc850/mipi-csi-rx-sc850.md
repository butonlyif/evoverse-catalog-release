---
ws_manifest_version: 1
kind: ip
id: mipi-csi-rx-sc850
display_name: MIPI CSI-2 RX (SC850SL 4-Lane 1.4Gbps)
version: 1.0.0
board: ws-e1
carrier: ws-e1-base
maintainer: evoverse
license: proprietary
description: MIPI CSI-2 Receiver IP for SmartSens SC850SL sensor (3840x2160@60fps, 4-lane, 1404Mbps/lane, 10-bit RAW). Includes I2C sensor initialization and data unpack logic.
---

[English](mipi-csi-rx-sc850.en.md) | 中文

# MIPI CSI-2 RX (SC850SL 4-Lane 1.4Gbps)

## 来源 Demo
`demos/mipi-csi-rx-sc850sl/`（原 `MIPI_RX_sc850/MIPI_RX_sc535/`）

## 硬核 IP 配置
| IP 名称 | VLNV | 版本 | 关键参数 |
|---------|------|------|---------|
| hard_csi_rx | efinixinc.com:mipi:efx_csi2_rx_top | 5.5.1 | 4 data lanes, ASYNC_STAGE=2, CLOCK_FREQ=100MHz, PIXEL_FIFO_DEPTH=1024, GENERIC frame mode |

- Efinity 工具链版本: 2023.2.307

## RTL 文件
| 文件 | 说明 |
|------|------|
| `rtl/top_2_5g.sv` | 顶层模块 — MIPI CSI-2 RX 示例设计 |
| `rtl/hard_csi_rx.sv` | Efinity MIPI CSI-2 RX 硬核 wrapper |
| `rtl/hard_csi_rx_define.vh` | 硬核 wrapper 宏定义 |
| `rtl/hard_csi_rx_tmpl.v` | 硬核 wrapper 模板 (Verilog) |
| `rtl/efx_csi2_tx_top.sv` | CSI-2 TX 顶层 (loopback 测试用) |
| `rtl/data_unpack.v` | MIPI 像素数据解包 |
| `rtl/datatype_gen.v` | 数据类型生成 |
| `rtl/dual_clock_fifo.v` | 跨时钟域 FIFO |
| `rtl/simple_dual_port_ram.v` | 双端口 RAM |
| `rtl/shift_reg.v` | 移位寄存器 |
| `rtl/lfsr.v` | 线性反馈移位寄存器 (PRBS) |
| `rtl/pattern_gen.v` | 测试图案生成器 |
| `rtl/pattern_gen2.v` | 测试图案生成器 v2 |
| `rtl/vga_gen.v` | VGA 时序生成器 |
| `rtl/reset.v` | 复位同步器 |
| `rtl/smartsens_init.v` | SmartSens 传感器 I2C 初始化顶层 |
| `rtl/sc535_i2c_init.v` | SC850SL I2C 初始化序列 |
| `rtl/single_port_rom.v` | 单端口 ROM (存储寄存器配置) |
| `rtl/sc850sl_init.mem` | SC850SL 寄存器初始化数据 |
| `rtl/settings.json` | Efinity IP 生成配置 |

## 约束
| 文件 | 说明 |
|------|------|
| `constraints/Ti180_mipi.sdc` | 时序约束 (时钟定义、false path 等) |
| `constraints/Ti180_mipi.peri.xml` | 外设/引脚约束 (MIPI DPHY RX 引脚分配) |

## 接口
- **时钟**: `mipi_clk` (100MHz), `pixel_clk` (50MHz), `cfg_clk`, `mipi_dphy_rx_clk_CLKOUT` (312.5MHz HS byte clock)
- **PLL**: `pll0_locked`, `pll1_locked`
- **MIPI DPHY RX**: 4-lane HS data (16-bit per lane), ULPS/ESC/STOP state signals, SKEWCAL, SYNC
- **传感器初始化**: I2C 接口 (SCL/SDA) 用于 SC850SL 寄存器配置
- **视频输出**: 解包后的像素数据 + 同步信号 (hsync/vsync/data_enable)

## 应用场景
用于 ws-e1-base 底板的 MIPI CSI-2 摄像头输入。接收 SmartSens SC850SL 传感器的 4K@60fps RAW10 视频流，通过硬件 MIPI DPHY RX 和 CSI-2 控制器解码，输出并行像素数据供后续图像处理模块使用。
