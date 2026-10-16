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
description: Generates a video stream from a Pattern Generator, receives it through the MIPI CSI-2 hard IP with FIFO buffering and the UVC encryption IP, and outputs a 4K60 USB video stream over the FX10 GPIF LVDS interface.
---

English | [中文](uvc-usb-video.md)

# UVC USB Video (4K60 Pattern Generator)

## Source Demo
`demos/usb-uvc-4k60-pattern/` (project directory `patten_fx10_ency/`, formerly `Patten_uvc_4k60/`)

## Hard IP Configuration
- **csi2_hard_mipi_rx** (Efinix MIPI CSI-2 RX) — VLNV: `efinixinc.com:mipi:efx_csi2_rx_top:5.15`
  - Configuration: 4 data lanes, async stage 2, 100MHz clock, pixel FIFO depth 1024
  - Configuration file: `rtl/ip/csi2_hard_mipi_rx/settings.json`
- **y_data_fifo** (Efinix FIFO) — VLNV: `efinixinc.com:memory:efx_fifo_top:8.1`
  - Configuration file: `rtl/ip/y_data_fifo/settings.json`
- **uv_data_fifo** (Efinix FIFO) — VLNV: `efinixinc.com:memory:efx_fifo_top:8.1`
  - Configuration file: `rtl/ip/uv_data_fifo/settings.json`
- **slfifo_buffer** (Efinix FIFO) — VLNV: `efinixinc.com:memory:efx_fifo_top:8.1`
  - Configuration file: `rtl/ip/slfifo_buffer/settings.json`

## RTL Files
- `rtl/top.sv` — top level, containing the Pattern Generator, FX10 GPIF LVDS interface, and PLL
- `rtl/uvc_top_ency.v` — UVC encryption IP top level (uvc_top_ency, encryption IP)
- `rtl/ip/csi2_hard_mipi_rx/csi2_hard_mipi_rx.sv` — CSI-2 hard IP wrapper
- `rtl/ip/y_data_fifo/y_data_fifo.sv` — Y data FIFO wrapper
- `rtl/ip/uv_data_fifo/uv_data_fifo.sv` — UV data FIFO wrapper
- `rtl/ip/slfifo_buffer/slfifo_buffer.sv` — side-band FIFO wrapper

## Constraints
- `constraints/constrain.sdc` — timing constraints
- `constraints/cam_uvc.peri.xml` — peripheral/pin constraints

## Interfaces
- FX10 GPIF LVDS (USB video): `fx10_gpif_lvds0/1_pclk_data`, `fx10_gpif_lvds0/1_pdata0~7`, `fx10_gpif_lvds0/1_pctrl`, `fx10_gpif_lvds*_ctl0~6`
- FX10 control: `fx10_gpif_m_oe_n_o`, `fx10_gpif_m_pktend_n_o`, `fx10_gpif_m_addr_o[1:0]`, `fx10_gpif_m_rd_req_n_o`, `fx10_gpif_m_full_flag_i`
- FX3 SPI configuration: `fx10_spi_sck` / `fx10_spi_csn` / `fx10_spi_mosi` / `fx10_spi_miso`
- PLL: `pll0_locked` / `pll1_locked` / `clk_100m` / `pll0_rstn` / `pll1_rstn` / `pll_ddr_rstn`

## Use Cases
A video pattern generated inside the FPGA is received through the MIPI CSI-2 hard IP, buffered across clock domains by FIFOs, and processed by the UVC protocol, then output as a 4K60 UVC video stream over the FX10 (USB3 controller) GPIF LVDS interface. This is the core reference design for the board's USB camera / video output capability.
