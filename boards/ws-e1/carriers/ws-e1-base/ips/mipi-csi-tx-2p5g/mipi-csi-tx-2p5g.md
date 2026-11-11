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

[English](mipi-csi-tx-2p5g.en.md) | 中文

# MIPI CSI-2 TX 2.5Gbps (4K UHD)

## 来源 Demo
`demos/mipi-csi-tx-4k-pattern/`（原 `TJ180J484_CSI_4k_2370Ma/`）

## 硬核 IP 配置
| IP 名称 | VLNV | 版本 | 关键参数 |
|---------|------|------|---------|
| mipi_csi_tx_2p5g | efinixinc.com:mipi:efx_csi2_tx_top | 5.14 | 4 data lanes, HS_BYTECLK=125MHz, Continuous clock, PIXEL_FIFO_DEPTH=2048, SKEWCAL enabled |
| Hard_csi_rx | efinixinc.com:mipi:efx_csi2_rx_top | 5.15 | 4 data lanes, ASYNC_STAGE=2, CLOCK_FREQ=100MHz, PIXEL_FIFO_DEPTH=2048 |
| async_fifo_16 | Efinity Async FIFO | - | 16-bit async FIFO wrapper |
| dsi_tx | efinixinc.com:mipi:efx_dsi_tx_top | - | DSI TX wrapper (Ti60F225 reference) |

- Efinity 工具链版本: 2025.2.288.4.15

## RTL 文件
| 文件 | 说明 |
|------|------|
| `rtl/top.sv` | 顶层模块 — 4K CSI-2 TX + RX loopback 示例设计 |
| `rtl/mipi_csi_top.sv` | MIPI CSI 顶层封装 (TX + RX + pattern) |
| `rtl/reset_ctrl.v` | 复位控制 |
| `rtl/video_pattern_gen.v` | 视频测试图案生成器 |
| `rtl/video_pattern_gen_gray.v` | 灰度测试图案生成器 |
| `rtl/vid_info_det_v6.v` | 视频信息检测 v6 |
| `rtl/color_bar_checker.v` | 彩条检查器 |
| `rtl/led_ctrl.v` | LED 控制 |
| `rtl/mipi_csi_tx_2p5g.sv` | MIPI CSI-2 TX 2.5G 硬核 wrapper |
| `rtl/mipi_csi_tx_2p5g_define.svh` | TX wrapper 宏定义 |
| `rtl/Hard_csi_rx.sv` | MIPI CSI-2 RX 硬核 wrapper |
| `rtl/Hard_csi_rx_define.svh` | RX wrapper 宏定义 |
| `rtl/async_fifo_16.sv` | 异步 FIFO 16 wrapper |
| `rtl/dsi_tx.sv` | DSI TX wrapper |
| `rtl/efx_dsi_tx_top.sv` | DSI TX 顶层 |
| `rtl/i2c_master_top.v` | I2C 主控制器顶层 |
| `rtl/i2c_master_byte_ctrl.v` | I2C 字节控制 |
| `rtl/i2c_master_bit_ctrl.v` | I2C 位控制 |
| `rtl/oc_i2c_master.v` | 开漏 I2C 主控制器 |
| `rtl/data_pack.v` | 像素数据打包 (MIPI TX) |
| `rtl/data_unpack.v` | 像素数据解包 (MIPI RX) |
| `rtl/vga_gen.v` | VGA 时序生成 |
| `rtl/raw_to_rgb.v` | RAW 转 RGB |
| `rtl/yuv_gen.v` | YUV 生成器 |
| `rtl/yuv_64bit.v` | 64-bit YUV 处理 |
| `rtl/panel_config.v` | 面板配置 |
| `rtl/true_dual_port_ram.v` | 真双端口 RAM |
| `rtl/dual_clock_fifo.v` | 跨时钟域 FIFO |
| `rtl/line_buffer.v` | 行缓存 |
| `rtl/ser2par_pixel.v` | 串并转换像素 |
| `rtl/timing_detec.v` | 时序检测 |
| `rtl/*_settings.json` | 各 IP 生成配置 (4 个) |
| 其他 | 辅助模块 (color_bar, rgb_gain, vga_buffer, async_reset, rst_n_piple 等) |

## 约束
| 文件 | 说明 |
|------|------|
| `constraints/top.peri.xml` | 外设/引脚约束 (MIPI DPHY TX/RX 引脚分配) |
| `constraints/constraints.sdc` | 时序约束 (时钟定义、false path 等) |

## 接口
- **时钟**: `i_fb_clk`, `i_sysclk_div2`, `dphy_byte_clk` (312.5MHz), `mipi_rx_cfg_clk`, `CLK_5M`
- **PLL**: `pll0_locked`, `pll_mipi_locked`, `pll_byteclk_locked`
- **MIPI DPHY TX (inst1)**: 4-lane HS data (16-bit per lane), esc_clk (20MHz), ULPS/STOP state, SKEW_CAL
- **MIPI DPHY RX (inst2)**: 4-lane HS data, ULPS/ESC/STOP state
- **视频参数**: HACT=3840, VACT=2160, YUV422 (DATATYPE=0x1E), PACK_BIT=64
- **I2C**: 摄像头传感器寄存器配置接口

## 应用场景
用于 ws-e1-base 底板的 MIPI CSI-2 视频输出。生成 4K UHD 视频图案通过 MIPI CSI-2 TX 发送至显示面板，同时支持 MIPI CSI-2 RX 接收回环测试。包含完整的 I2C 摄像头控制、视频图案生成、彩条检测、RAW→RGB/YUV 转换等功能链。
