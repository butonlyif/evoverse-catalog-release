---
EvoVerse_manifest_version: 1
kind: ip
id: axi4-stream-mux
display_name: AXI4-Stream Multiplexer
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "AXI4-Stream bus multiplexer that selects between multiple streaming data sources"
---

[English](axi4-stream-mux.en.md) | 中文

# AXI4-Stream Multiplexer

## 来源
从以下 demo 工程提取：
- TJ180A484_TSE

## 文件
- `rtl/axi4_st_mux.v` — AXI4-Stream 多路选择器（来自 TJ180A484_TSE）

## 接口
- **多路 AXI4-Stream Slave 输入**：`S_AXIS_*_TDATA` / `S_AXIS_*_TVALID` / `S_AXIS_*_TREADY` 等
- **单路 AXI4-Stream Master 输出**：`M_AXIS_TDATA` / `M_AXIS_TVALID` / `M_AXIS_TREADY`
- 选择信号用于切换当前活跃的数据源通道

## 参数
- 见源文件内的 parameter 声明（通道数、数据位宽等）。

## 使用示例
- TJ180A484_TSE — 千兆以太网多路 AXI-Stream 数据流选择
