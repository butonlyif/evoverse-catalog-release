---
EvoVerse_manifest_version: 1
kind: ip
id: vga-timing-gen
display_name: VGA Timing Generator
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "VGA/video timing generator producing horizontal sync, vertical sync, data enable, and pixel coordinates for standard display resolutions"
---

[English](vga-timing-gen.en.md) | 中文

# VGA Timing Generator

## 来源
从以下 demo 工程提取：
- MIPI_RX_sc850
- TJ180J484_CSI_4k_2370Ma

## 文件
- `rtl/vga_gen.v` — VGA 时序生成器（来自 MIPI_RX_sc850）
- `rtl/vga_gen_csi.v` — 4K CSI 工程时序生成器变体（来自 TJ180J484_CSI_4k_2370Ma）

## 接口
| 信号 | 方向 | 说明 |
|------|------|------|
| `clk` / `rst` | input | 像素时钟 / 复位 |
| `hs` / `vs` | output | 行同步 / 场同步 |
| `de` | output | 数据使能（有效显示区） |
| `h_cnt` / `v_cnt` | output | 像素 X / Y 坐标 |

## 参数
- 分辨率时序参数（前肩 / 后肩 / 同步宽度 / 有效区）见各源文件内的 parameter 声明。

## 使用示例
- MIPI_RX_sc850 — MIPI 视频输出时序生成
- TJ180J484_CSI_4k_2370Ma — 4K 显示时序生成
