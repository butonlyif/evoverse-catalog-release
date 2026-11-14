---
EvoVerse_manifest_version: 1
kind: ip
id: axi4-to-axi4lite
display_name: AXI4 to AXI4-Lite Bridge
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "Protocol bridge down-converting full AXI4 transactions to AXI4-Lite single-beat transactions"
---

English | [中文](axi4-to-axi4lite.md)

# AXI4 to AXI4-Lite Bridge

## Source
Extracted from the following demo projects:
- TJ180A484S_SDHOST

## Files
- `rtl/axi4_to_axi4l.v` — AXI4-to-AXI4-Lite protocol bridge module (from TJ180A484S_SDHOST)

## Interface
- **AXI4 slave side**: Full AXI4 channels (AW / W / B / AR / R), including burst signals such as `AWLEN` / `AWSIZE` / `AWBURST`
- **AXI4-Lite master side**: Single-beat AXI4-Lite channels (AW / W / B / AR / R), no burst signals

## Parameters
- See the parameter declarations in the source file (address/data widths, etc.).

## Usage Examples
- TJ180A484S_SDHOST — SoC AXI4 bus connected to an AXI4-Lite SD Host controller
