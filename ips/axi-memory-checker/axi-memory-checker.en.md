---
EvoVerse_manifest_version: 1
kind: ip
id: axi-memory-checker
display_name: AXI Memory Checker
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "AXI bus master BFM that writes test patterns to memory then reads back and verifies, reporting mismatches"
---

English | [中文](axi-memory-checker.md)

# AXI Memory Checker

## Source
Extracted from the following demo projects:
- DDR_TEST

> Note: No standalone memory_checker / apb3_slave / timer_start source files were found in the SI5338 demo (it contains only the SoC netlist), so only the DDR_TEST version was extracted.

## Files
- `rtl/memory_checker.v` — AXI memory checker (from DDR_TEST)

## Interface
| Signal | Direction | Description |
|------|------|------|
| `axi_clk` / `rstn` | input | Clock / active-low reset |
| `start` | input | Starts the memory check |
| `aw*` / `w*` / `b*` | AXI write channels | AWADDR / WDATA(512-bit) / BRESP, etc. |
| `ar*` / `r*` | AXI read channels | ARADDR / RDATA(512-bit) / RRESP, etc. |
| `fail` / `done` | output | Verification failure / completion flags |
| `rdata_obs` / `rdata_exp` | output | Actual read data / expected data |

## Parameters
| Parameter | Default | Description |
|------|--------|------|
| `ALEN` | `5` | AXI burst length |
| `ASIZE` | `6` | AXI burst size (log2 of bytes per beat) |
| `START_ADDR` | `33'h000000000` | Start address |
| `STOP_ADDR` | `33'h000001900` | End address |

## Usage Examples
- DDR_TEST — DDR memory read/write verification and stress testing
