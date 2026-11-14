---
ws_manifest_version: 1
kind: ip
id: uvc-usb-video
display_name: UVC USB Video (4K60 Pattern Generator)
version: 1.0.0
board: ws-e1
carrier: ws-e1-base
maintainer: evoverse
license: proprietary
description: 基于 Pattern Generator 产生视频流，经 MIPI CSI-2 硬核接收、FIFO 缓冲与 UVC 加密 IP，通过 FX10 GPIF LVDS 接口输出 4K60 USB 视频流。
---

[English](uvc-usb-video.en.md) | 中文

# UVC USB Video (4K60 Pattern Generator)

## 来源 Demo
`demos/usb-uvc-4k60-pattern/`（工程目录 `patten_fx10_ency/`，原 `Patten_uvc_4k60/`）

## 硬核 IP 配置
- **csi2_hard_mipi_rx** (Efinix MIPI CSI-2 RX) — VLNV: `efinixinc.com:mipi:efx_csi2_rx_top:5.15`
  - 配置：4 data lane，async stage 2，100MHz 时钟，pixel FIFO depth 1024
  - 配置文件：`rtl/ip/csi2_hard_mipi_rx/settings.json`
- **y_data_fifo** (Efinix FIFO) — VLNV: `efinixinc.com:memory:efx_fifo_top:8.1`
  - 配置文件：`rtl/ip/y_data_fifo/settings.json`
- **uv_data_fifo** (Efinix FIFO) — VLNV: `efinixinc.com:memory:efx_fifo_top:8.1`
  - 配置文件：`rtl/ip/uv_data_fifo/settings.json`
- **slfifo_buffer** (Efinix FIFO) — VLNV: `efinixinc.com:memory:efx_fifo_top:8.1`
  - 配置文件：`rtl/ip/slfifo_buffer/settings.json`

## RTL 文件
- `rtl/top.sv` — 顶层，含 Pattern Generator、FX10 GPIF LVDS 接口、PLL
- `rtl/uvc_top_ency.v` — UVC 加密 IP 顶层（uvc_top_ency，加密 IP）
- `rtl/ip/csi2_hard_mipi_rx/csi2_hard_mipi_rx.sv` — CSI-2 硬核 wrapper
- `rtl/ip/y_data_fifo/y_data_fifo.sv` — Y 数据 FIFO wrapper
- `rtl/ip/uv_data_fifo/uv_data_fifo.sv` — UV 数据 FIFO wrapper
- `rtl/ip/slfifo_buffer/slfifo_buffer.sv` — 侧线 FIFO wrapper

## 约束
- `constraints/constrain.sdc` — 时序约束
- `constraints/cam_uvc.peri.xml` — 外设/引脚约束

## 接口
- FX10 GPIF LVDS（USB 视频）：`fx10_gpif_lvds0/1_pclk_data`、`fx10_gpif_lvds0/1_pdata0~7`、`fx10_gpif_lvds0/1_pctrl`、`fx10_gpif_lvds*_ctl0~6`
- FX10 控制：`fx10_gpif_m_oe_n_o`、`fx10_gpif_m_pktend_n_o`、`fx10_gpif_m_addr_o[1:0]`、`fx10_gpif_m_rd_req_n_o`、`fx10_gpif_m_full_flag_i`
- FX3 SPI 配置：`fx10_spi_sck` / `fx10_spi_csn` / `fx10_spi_mosi` / `fx10_spi_miso`
- PLL：`pll0_locked` / `pll1_locked` / `clk_100m` / `pll0_rstn` / `pll1_rstn` / `pll_ddr_rstn`

## 应用场景
FPGA 内部 Pattern Generator 生成视频，通过 MIPI CSI-2 硬核接收、FIFO 跨时钟域缓冲与 UVC 协议处理，经 FX10（USB3 控制器）GPIF LVDS 接口输出 4K60 UVC 视频流，是板卡 USB 摄像头/视频输出能力的核心参考设计。
