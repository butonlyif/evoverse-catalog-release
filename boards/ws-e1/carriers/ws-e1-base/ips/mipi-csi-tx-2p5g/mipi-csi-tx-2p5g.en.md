---
ws_manifest_version: 1
kind: ip
id: mipi-csi-tx-2p5g
display_name: MIPI CSI-2 TX 2.5Gbps (4K UHD)
version: 1.0.0
board: ws-e1
carrier: ws-e1-base
maintainer: evoverse
license: proprietary
description: MIPI CSI-2 Transmitter IP for 4K UHD video output (3840x2160, 4-lane, 2.5Gbps/lane, YUV422). Includes video pattern generator, camera I2C control, color bar checker, and DSI TX wrapper.
---

English | [中文](mipi-csi-tx-2p5g.md)

# MIPI CSI-2 TX 2.5Gbps (4K UHD)

## Source Demo
`demos/mipi-csi-tx-4k-pattern/` (formerly `TJ180J484_CSI_4k_2370Ma/`)

## Hard IP Configuration
| IP name | VLNV | Version | Key parameters |
|---------|------|------|---------|
| mipi_csi_tx_2p5g | efinixinc.com:mipi:efx_csi2_tx_top | 5.14 | 4 data lanes, HS_BYTECLK=125MHz, Continuous clock, PIXEL_FIFO_DEPTH=2048, SKEWCAL enabled |
| Hard_csi_rx | efinixinc.com:mipi:efx_csi2_rx_top | 5.15 | 4 data lanes, ASYNC_STAGE=2, CLOCK_FREQ=100MHz, PIXEL_FIFO_DEPTH=2048 |
| async_fifo_16 | Efinity Async FIFO | - | 16-bit async FIFO wrapper |
| dsi_tx | efinixinc.com:mipi:efx_dsi_tx_top | - | DSI TX wrapper (Ti60F225 reference) |

- Efinity toolchain version: 2025.2.288.4.15

## RTL Files
| File | Description |
|------|------|
| `rtl/top.sv` | Top module — 4K CSI-2 TX + RX loopback example design |
| `rtl/mipi_csi_top.sv` | MIPI CSI top-level wrapper (TX + RX + pattern) |
| `rtl/reset_ctrl.v` | Reset control |
| `rtl/video_pattern_gen.v` | Video test pattern generator |
| `rtl/video_pattern_gen_gray.v` | Grayscale test pattern generator |
| `rtl/vid_info_det_v6.v` | Video information detector v6 |
| `rtl/color_bar_checker.v` | Color bar checker |
| `rtl/led_ctrl.v` | LED control |
| `rtl/mipi_csi_tx_2p5g.sv` | MIPI CSI-2 TX 2.5G hard IP wrapper |
| `rtl/mipi_csi_tx_2p5g_define.svh` | TX wrapper macro definitions |
| `rtl/Hard_csi_rx.sv` | MIPI CSI-2 RX hard IP wrapper |
| `rtl/Hard_csi_rx_define.svh` | RX wrapper macro definitions |
| `rtl/async_fifo_16.sv` | Async FIFO 16 wrapper |
| `rtl/dsi_tx.sv` | DSI TX wrapper |
| `rtl/efx_dsi_tx_top.sv` | DSI TX top level |
| `rtl/i2c_master_top.v` | I2C master top level |
| `rtl/i2c_master_byte_ctrl.v` | I2C byte controller |
| `rtl/i2c_master_bit_ctrl.v` | I2C bit controller |
| `rtl/oc_i2c_master.v` | Open-drain I2C master |
| `rtl/data_pack.v` | Pixel data packing (MIPI TX) |
| `rtl/data_unpack.v` | Pixel data unpacking (MIPI RX) |
| `rtl/vga_gen.v` | VGA timing generation |
| `rtl/raw_to_rgb.v` | RAW to RGB conversion |
| `rtl/yuv_gen.v` | YUV generator |
| `rtl/yuv_64bit.v` | 64-bit YUV processing |
| `rtl/panel_config.v` | Panel configuration |
| `rtl/true_dual_port_ram.v` | True dual-port RAM |
| `rtl/dual_clock_fifo.v` | Clock domain crossing (CDC) FIFO |
| `rtl/line_buffer.v` | Line buffer |
| `rtl/ser2par_pixel.v` | Pixel serial-to-parallel conversion |
| `rtl/timing_detec.v` | Timing detection |
| `rtl/*_settings.json` | Per-IP generation configurations (4 files) |
| Others | Auxiliary modules (color_bar, rgb_gain, vga_buffer, async_reset, rst_n_piple, etc.) |

## Constraints
| File | Description |
|------|------|
| `constraints/top.peri.xml` | Peripheral/pin constraints (MIPI DPHY TX/RX pin assignment) |
| `constraints/constraints.sdc` | Timing constraints (clock definitions, false paths, etc.) |

## Interfaces
- **Clocks**: `i_fb_clk`, `i_sysclk_div2`, `dphy_byte_clk` (312.5MHz), `mipi_rx_cfg_clk`, `CLK_5M`
- **PLLs**: `pll0_locked`, `pll_mipi_locked`, `pll_byteclk_locked`
- **MIPI DPHY TX (inst1)**: 4-lane HS data (16-bit per lane), esc_clk (20MHz), ULPS/STOP state, SKEW_CAL
- **MIPI DPHY RX (inst2)**: 4-lane HS data, ULPS/ESC/STOP state
- **Video parameters**: HACT=3840, VACT=2160, YUV422 (DATATYPE=0x1E), PACK_BIT=64
- **I2C**: camera sensor register configuration interface

## Use Cases
MIPI CSI-2 video output on the ws-e1-base carrier board. Generates a 4K UHD video pattern and sends it to a display panel through the MIPI CSI-2 TX, while also supporting MIPI CSI-2 RX receive loopback testing. Includes a complete function chain of I2C camera control, video pattern generation, color bar checking, and RAW→RGB/YUV conversion.
