---
EvoVerse_manifest_version: 1
kind: ip
id: reset-sync
display_name: Reset Synchronizer
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "Asynchronous reset to synchronous reset converter with configurable active level and pipeline depth"
---

English | [中文](reset-sync.md)

# Reset Synchronizer

## Source
Extracted from the following demo projects:
- DDR_TEST
- TJ180MIPI_loopback
- TJ180J484_CSI_4k_2370Ma

## Files
- `rtl/reset.v` — Basic reset synchronization module (from DDR_TEST)
- `rtl/reset_mipi.v` — Reset synchronizer variant with the `async_reg` attribute (from TJ180MIPI_loopback)
- `rtl/reset_ctrl.v` — Multi-channel reset controller wrapping multiple reset instances (from TJ180J484_CSI_4k_2370Ma)

## Interface
| Signal | Direction | Description |
|------|------|------|
| `i_arst` | input | Asynchronous reset |
| `i_clk` | input | Clock |
| `o_srst` | output | Synchronous reset output |

The `reset_ctrl` module additionally supports `NUM_RST` parallel resets, exposed as a `[NUM_RST-1:0]` bus interface.

## Parameters
| Parameter | Default | Description |
|------|--------|------|
| `IN_RST_ACTIVE` | `"LOW"` | Input reset active level (`"LOW"` / `"HIGH"`) |
| `OUT_RST_ACTIVE` | `"HIGH"` | Output reset active level (`"LOW"` / `"HIGH"`) |
| `CYCLE` | `1` | Number of synchronization pipeline stages |
| `NUM_RST` (reset_ctrl only) | `1` | Number of parallel reset channels |

## Usage Examples
- DDR_TEST — DDR controller initialization reset
- TJ180MIPI_loopback — Reset synchronization for the MIPI data path
- TJ180J484_CSI_4k_2370Ma — Multi-clock-domain reset control
