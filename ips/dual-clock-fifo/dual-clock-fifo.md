---
EvoVerse_manifest_version: 1
kind: ip
id: dual-clock-fifo
display_name: Dual Clock FIFO
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "Dual-clock asynchronous FIFO with Gray-code pointer synchronization, supporting two independent implementations"
---

[English](dual-clock-fifo.en.md) | 中文

# Dual Clock FIFO

## 来源
从以下 demo 工程提取：
- TJ180A484_TSE（DaulClkFifo 实现）
- MIPI_RX_sc850（dual_clock_fifo 实现 + simple_dual_port_ram 依赖）

## 文件
- `rtl/DaulClkFifo.v` — 自包含双时钟 FIFO（含 DC_FIFO / FifoAddrCnt / GrayCnt / GrayDecode 模块，来自 TJ180A484_TSE）
- `rtl/dual_clock_fifo.v` — Efinix 风格双时钟 FIFO 含 wrapper（来自 MIPI_RX_sc850）
- `rtl/simple_dual_port_ram.v` — `dual_clock_fifo` 的依赖模块：简单双端口 RAM

## 接口
**DaulClkFifo (DC_FIFO):**
| 信号 | 方向 | 说明 |
|------|------|------|
| `Reset` | input | 系统复位 |
| `WrClk` / `WrEn` / `WrData` | input | 写时钟 / 写使能 / 写数据 |
| `WrFull` / `WrDNum` | output | 写满标志 / 写侧数据计数 |
| `RdClk` / `RdEn` | input | 读时钟 / 读使能 |
| `RdData` / `RdEmpty` / `RdDNum` | output | 读数据 / 读空标志 / 读侧数据计数 |

**dual_clock_fifo:** 接口为 `i_arst` / `i_wclk` / `i_we` / `i_wdata` / `i_rclk` / `i_re` / `o_full` / `o_empty` / `o_rdata`，并附加 almost-full/empty 和读写计数信号。

## 参数
| 参数 | 说明 |
|------|------|
| `DATA_WIDTH` | 数据位宽 |
| `FIFO_DEPTH` / `ADDR_WIDTH` | FIFO 深度 / 地址位宽 |
| `FIFO_MODE` | `"Normal"` / `"ShowAhead"`（DaulClkFifo）；`"STD_FIFO"` / `"BYPASS"`（dual_clock_fifo） |
| `LATENCY` | 输出延迟级数（仅 dual_clock_fifo） |

## 使用示例
- TJ180A484_TSE — 千兆以太网跨时钟域数据缓冲
- MIPI_RX_sc850 — MIPI CSI 接收跨时钟域视频流缓冲
