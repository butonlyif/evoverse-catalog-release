---
EvoVerse_manifest_version: 1
kind: ip
id: reset-sync
display_name: Reset Synchronizer
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "Asynchronous reset to synchronous reset converter with configurable active level and pipeline depth"
---

[English](reset-sync.en.md) | 中文

# Reset Synchronizer

## 来源
从以下 demo 工程提取：
- DDR_TEST
- TJ180MIPI_loopback
- TJ180J484_CSI_4k_2370Ma

## 文件
- `rtl/reset.v` — 基础复位同步器模块（来自 DDR_TEST）
- `rtl/reset_mipi.v` — 带 `async_reg` 属性的复位同步器变体（来自 TJ180MIPI_loopback）
- `rtl/reset_ctrl.v` — 多路复位控制器，封装多个 reset 实例（来自 TJ180J484_CSI_4k_2370Ma）

## 接口
| 信号 | 方向 | 说明 |
|------|------|------|
| `i_arst` | input | 异步复位 |
| `i_clk` | input | 时钟 |
| `o_srst` | output | 同步复位输出 |

`reset_ctrl` 模块额外支持 `NUM_RST` 路并行复位，接口为总线形式 `[NUM_RST-1:0]`。

## 参数
| 参数 | 默认值 | 说明 |
|------|--------|------|
| `IN_RST_ACTIVE` | `"LOW"` | 输入复位有效电平（`"LOW"` / `"HIGH"`） |
| `OUT_RST_ACTIVE` | `"HIGH"` | 输出复位有效电平（`"LOW"` / `"HIGH"`） |
| `CYCLE` | `1` | 同步流水级数 |
| `NUM_RST`（仅 reset_ctrl） | `1` | 并行复位通道数 |

## 使用示例
- DDR_TEST — DDR 控制器初始化复位
- TJ180MIPI_loopback — MIPI 通复位同步
- TJ180J484_CSI_4k_2370Ma — 多时钟域复位控制
