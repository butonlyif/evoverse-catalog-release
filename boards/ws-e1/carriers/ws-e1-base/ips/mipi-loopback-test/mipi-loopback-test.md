---
ws_manifest_version: 1
kind: ip
id: mipi-loopback-test
display_name: MIPI CSI-2 Loopback Test (TX→RX BIST)
version: 1.0.0
board: ws-e1
carrier: ws-e1-base
maintainer: evoverse
license: proprietary
description: MIPI CSI-2 Loopback test IP for board-level TX→RX signal integrity verification. TX generates PRBS9 test patterns, RX receives and verifies data integrity. 2-lane configuration with debug enabled.
---

[English](mipi-loopback-test.en.md) | 中文

# MIPI CSI-2 Loopback Test (TX→RX BIST)

## 来源 Demo
`demos/mipi-loopback-test/`（原 `TJ180MIPI_loopback/`）

## 硬核 IP 配置
| IP 名称 | VLNV | 版本 | 关键参数 |
|---------|------|------|---------|
| hard_csi_rx | efinixinc.com:mipi:efx_csi2_rx_top | 5.15 | 2 data lanes, ASYNC_STAGE=2, CLOCK_FREQ=100MHz, PIXEL_FIFO_DEPTH=2048, DEBUG enabled |
| hard_csi_tx | efinixinc.com:mipi:efx_csi2_tx_top | 5.14 | 2 data lanes, HS_BYTECLK=60MHz, Continuous clock, PIXEL_FIFO_DEPTH=2048 |

- Efinity 工具链版本: 2025.2.288.4.15

## RTL 文件
| 文件 | 说明 |
|------|------|
| `rtl/Top.v` | 顶层模块 — MIPI loopback 测试平台 |
| `rtl/reset.v` | 参数化复位同步器 |
| `rtl/efx_csi2_rx.sv` | CSI-2 RX 控制器顶层 (软逻辑封装) |
| `rtl/efx_csi_tx.sv` | CSI-2 TX 控制器顶层 (软逻辑封装) |
| `rtl/efx_csi_tx_define.vh` | TX 控制器宏定义 |
| `rtl/efx_ram_10k.v` | Efinity 10Kb BRAM wrapper |
| `rtl/hard_csi_rx.sv` | MIPI CSI-2 RX DPHY 硬核 wrapper |
| `rtl/hard_csi_rx_define.svh` | RX wrapper 宏定义 (SystemVerilog) |
| `rtl/hard_csi_rx_define.vh` | RX wrapper 宏定义 (Verilog) |
| `rtl/hard_csi_tx.sv` | MIPI CSI-2 TX DPHY 硬核 wrapper |
| `rtl/hard_csi_tx_define.svh` | TX wrapper 宏定义 (SystemVerilog) |
| `rtl/hard_csi_tx_define.vh` | TX wrapper 宏定义 (Verilog) |
| `rtl/MIPI_Parameter.v` | MIPI 系统参数定义 |
| `rtl/MIPITest.v` | MIPI 测试控制 FSM |
| `rtl/MIPITxProcess.v` | MIPI TX 数据处理 |
| `rtl/MipiRxProcess.v` | MIPI RX 数据处理 |
| `rtl/MipiPixelData.v` | MIPI 像素数据生成/校验 |
| `rtl/PRBS9.v` | PRBS9 伪随机序列生成器 (BIST 测试图案) |
| `rtl/hard_csi_rx_settings.json` | RX IP 生成配置 |
| `rtl/hard_csi_tx_settings.json` | TX IP 生成配置 |

## 约束
| 文件 | 说明 |
|------|------|
| `constraints/top.sdc` | 顶层时序约束 |
| `constraints/mipi.sdc` | MIPI 专用时序约束 |
| `constraints/Ti180MIPI.peri.xml` | 外设/引脚约束 (MIPI DPHY TX/RX 引脚分配) |
| `constraints/Ti180_mipi_io.isf` | Efinity Interface Designer 文件 (I/O bank 配置) |

## 接口
- **时钟**: `MIPI_REF_CLK`
- **PLL**: `pll_inst1_LOCKED`, `pll_inst2_LOCKED`
- **MIPI DPHY RX (inst2)**: 2-lane HS data (16-bit per lane), ESC/LP/ULPS state, SKEWCAL, SYNC, error signals (ERR_CONTENTION, ERR_SOT_HS, SOTSYNC_ERROR, LINESTATE_ERROR)
- **MIPI DPHY TX (inst1)**: 2-lane HS data, STOPSTATE, TX_REQUEST_HS, ULPS control
- **BIST**: PRBS9 伪随机图案生成 + 校验，AXI4-Lite 轮询 FSM 控制测试流程

## 应用场景
用于 ws-e1-base 底板的 MIPI CSI-2 信号完整性测试。TX 发送 PRBS9 伪随机测试图案，通过板载 MIPI 走线环回到 RX，验证高速串行链路的信号质量。适用于生产测试、硬件 bring-up 和信号完整性调试。2-lane 配置，RX 端开启 debug 模式以采集完整错误信息。
