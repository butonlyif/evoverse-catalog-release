---
EvoVerse_manifest_version: 1
kind: demo
id: ws-e1-tse
display_name: WS-E1 Triple Speed Ethernet (RGMII) UDP Demo
version: 0.9.0
maintainer: EvoVerse
license: proprietary
belongs_to_board: ws-e1
description: "Triple Speed Ethernet (RGMII) UDP demo with MIPI camera input for the WS-E1 platform"
---

[English](ws-e1-tse.en.md) | 中文

# WS-E1 TSE 千兆以太网 UDP Demo

`ws-e1-TSE` 是 ws-e1 模块板 + ws-e1-base 载板上的 Triple Speed Ethernet（RGMII）UDP 演示工程：通过 RGMII 千兆以太网发送 / 回显 UDP 数据，并接入 MIPI 相机作为数据源。

## 硬件资源

- RGMII 千兆以太网 PHY（MDC / MDIO + 12 路 RGMII 信号，3A bank 1.8 V）
- MIPI2 RX 相机输入（IMX415，4 lane + clock）
- 相机 I2C 控制（`cam_1_scl` / `cam_1_sda` / `cam_1_en`）
- 系统 UART（调试控制台）

## 工程文件

- `ws_e1_tse.xml` — Efinity 工程
- `ws_e1_tse.peri.xml` — 接口 / 管脚定义
- `rtl/` — RTL 源码
- `embedded_sw/` — RISC-V 固件

## 已知状态

TX 通路实测通过（PC 收到 pattern 包）；RX 通路受 `rgmii_rxc` 时钟连接限制仍在排查，详见 `DAYLOG/2026-11.md`。
