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

English | [中文](vga-timing-gen.md)

# VGA Timing Generator

## Source
Extracted from the following demo projects:
- MIPI_RX_sc850
- TJ180J484_CSI_4k_2370Ma

## Files
- `rtl/vga_gen.v` — VGA video timing generator (from MIPI_RX_sc850)
- `rtl/vga_gen_csi.v` — 4K CSI project timing generator variant (from TJ180J484_CSI_4k_2370Ma)

## Interface
| Signal | Direction | Description |
|------|------|------|
| `clk` / `rst` | input | Pixel clock / reset |
| `hs` / `vs` | output | Horizontal sync / vertical sync |
| `de` | output | Data enable (active display area) |
| `h_cnt` / `v_cnt` | output | Pixel X / Y coordinates |

## Parameters
- Resolution timing parameters (front porch / back porch / sync width / active area): see the parameter declarations in each source file.

## Usage Examples
- MIPI_RX_sc850 — MIPI video output timing generation
- TJ180J484_CSI_4k_2370Ma — 4K display timing generation
