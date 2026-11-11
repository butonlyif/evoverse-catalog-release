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

English | [中文](video-pattern-gen.md)

# Video Pattern Generator

## Source
Extracted from the following demo projects:
- MIPI_RX_sc850
- TJ180J484_CSI_4k_2370Ma

## Files
- `rtl/pattern_gen.v` — Video test pattern generator (from MIPI_RX_sc850)
- `rtl/pattern_gen2.v` — Enhanced pattern generator variant (from MIPI_RX_sc850)
- `rtl/video_pattern_gen.v` — Video pattern generator (from TJ180J484_CSI_4k_2370Ma)
- `rtl/video_pattern_gen_gray.v` — Grayscale pattern generator variant (from TJ180J484_CSI_4k_2370Ma)

## Interface
- `clk` / `rst` — Clock / reset
- `hs` / `vs` / `de` — Horizontal sync / vertical sync / data enable
- `r` / `g` / `b` — RGB video data output

## Parameters
- Resolution, color depth, etc.: see the parameter declarations in each source file.

## Usage Examples
- MIPI_RX_sc850 — Test pattern source for the MIPI CSI video path
- TJ180J484_CSI_4k_2370Ma — Test patterns for a 4K video link
