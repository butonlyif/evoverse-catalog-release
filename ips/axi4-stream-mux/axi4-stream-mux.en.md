---
EvoVerse_manifest_version: 1
kind: ip
id: axi4-stream-mux
display_name: AXI4-Stream Multiplexer
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "AXI4-Stream bus multiplexer that selects between multiple streaming data sources"
---

English | [中文](axi4-stream-mux.md)

# AXI4-Stream Multiplexer

## Source
Extracted from the following demo projects:
- TJ180A484_TSE

## Files
- `rtl/axi4_st_mux.v` — AXI4-Stream multiplexer (from TJ180A484_TSE)

## Interface
- **Multi-channel AXI4-Stream slave inputs**: `S_AXIS_*_TDATA` / `S_AXIS_*_TVALID` / `S_AXIS_*_TREADY`, etc.
- **Single-channel AXI4-Stream master output**: `M_AXIS_TDATA` / `M_AXIS_TVALID` / `M_AXIS_TREADY`
- A select signal switches the currently active data source channel

## Parameters
- See the parameter declarations in the source file (channel count, data width, etc.).

## Usage Examples
- TJ180A484_TSE — Multi-channel AXI-Stream data stream selection for Gigabit Ethernet
