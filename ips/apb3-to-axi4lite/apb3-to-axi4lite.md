---
EvoVerse_manifest_version: 1
kind: ip
id: apb3-to-axi4lite
display_name: APB3 to AXI4-Lite Bridge
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "Protocol bridge converting APB3 peripheral bus transactions to AXI4-Lite transactions"
---

[English](apb3-to-axi4lite.en.md) | 中文

# APB3 to AXI4-Lite Bridge

## 来源
从以下 demo 工程提取：
- TJ180A484_TSE
- TJ180A484S_SDHOST

## 文件
- `rtl/apb3_2_axi4_lite.v` — 通用 APB3 转 AXI4-Lite 桥（来自 TJ180A484_TSE）
- `rtl/apb3_2_axi4_lite_sdhost.v` — SD Host 专用 APB3 转 AXI4-Lite 桥变体（来自 TJ180A484S_SDHOST）

## 接口
- **APB3 Slave 侧**：`PCLK` / `PRESETn` / `PSEL` / `PENABLE` / `PWRITE` / `PADDR` / `PWDATA` / `PRDATA` / `PREADY` / `PSLVERR`
- **AXI4-Lite Master 侧**：`AWADDR` / `AWVALID` / `AWREADY` / `WDATA` / `WSTRB` / `WVALID` / `WREADY` / `BRESP` / `BVALID` / `ARADDR` / `ARVALID` / `ARREADY` / `RDATA` / `RRESP` / `RVALID` / `RREADY`

## 参数
- 地址位宽和数据位宽通常为 32-bit，具体见各文件内的 parameter 声明。

## 使用示例
- TJ180A484_TSE — APB3 SoC 总线连接 AXI4-Lite 以太网 MAC
- TJ180A484S_SDHOST — APB3 SoC 总线连接 AXI4-Lite SD Host 控制器
