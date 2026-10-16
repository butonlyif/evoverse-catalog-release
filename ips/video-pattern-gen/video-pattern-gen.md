---
EvoVerse_manifest_version: 1
kind: ip
id: video-pattern-gen
display_name: Video Pattern Generator
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "Video test pattern generator producing color bars, gradients, or configurable test images for video pipeline debugging"
---

[English](video-pattern-gen.en.md) | 中文

# Video Pattern Generator

## 来源
从以下 demo 工程提取：
- MIPI_RX_sc850
- TJ180J484_CSI_4k_2370Ma

## 文件
- `rtl/pattern_gen.v` — 视频测试图案生成器（来自 MIPI_RX_sc850）
- `rtl/pattern_gen2.v` — 增强版图案生成器变体（来自 MIPI_RX_sc850）
- `rtl/video_pattern_gen.v` — 视频图案生成器（来自 TJ180J484_CSI_4k_2370Ma）
- `rtl/video_pattern_gen_gray.v` — 灰度图案生成器变体（来自 TJ180J484_CSI_4k_2370Ma）

## 接口
- `clk` / `rst` — 时钟 / 复位
- `hs` / `vs` / `de` — 行同步 / 场同步 / 数据使能
- `r` / `g` / `b` — RGB 视频数据输出

## 参数
- 分辨率、色深等见各源文件内的 parameter 声明。

## 使用示例
- MIPI_RX_sc850 — MIPI CSI 视频通测试图案源
- TJ180J484_CSI_4k_2370Ma — 4K 视频链路测试图案
