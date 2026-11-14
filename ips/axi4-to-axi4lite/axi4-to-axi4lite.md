---
EvoVerse_manifest_version: 1
kind: ip
id: axi4-to-axi4lite
display_name: AXI4 to AXI4-Lite Bridge
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "Protocol bridge down-converting full AXI4 transactions to AXI4-Lite single-beat transactions"
---

[English](axi4-to-axi4lite.en.md) | 中文

# AXI4 to AXI4-Lite Bridge

## 来源
从以下 demo 工程提取：
- TJ180A484S_SDHOST

## 文件
- `rtl/axi4_to_axi4l.v` — AXI4 转 AXI4-Lite 桥模块（来自 TJ180A484S_SDHOST）

## 接口
- **AXI4 Slave 侧**：完整 AXI4 通道（AW / W / B / AR / R），含 `AWLEN` / `AWSIZE` / `AWBURST` 等 burst 信号
- **AXI4-Lite Master 侧**：单拍 AXI4-Lite 通道（AW / W / B / AR / R），无 burst 信号

## 参数
- 见源文件内的 parameter 声明（地址/数据位宽等）。

## 使用示例
- TJ180A484S_SDHOST — SoC AXI4 总线连接 AXI4-Lite SD Host 控制器
