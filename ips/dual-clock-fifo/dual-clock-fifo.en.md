---
EvoVerse_manifest_version: 1
kind: ip
id: dual-clock-fifo
display_name: Dual Clock FIFO
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "Dual-clock asynchronous FIFO with Gray-code pointer synchronization, supporting two independent implementations"
---

English | [中文](dual-clock-fifo.md)

# Dual Clock FIFO

## Source
Extracted from the following demo projects:
- TJ180A484_TSE (DaulClkFifo implementation)
- MIPI_RX_sc850 (dual_clock_fifo implementation + simple_dual_port_ram dependency)

## Files
- `rtl/DaulClkFifo.v` — Self-contained dual-clock FIFO (contains the DC_FIFO / FifoAddrCnt / GrayCnt / GrayDecode modules, from TJ180A484_TSE)
- `rtl/dual_clock_fifo.v` — Efinix-style dual-clock FIFO with wrapper (from MIPI_RX_sc850)
- `rtl/simple_dual_port_ram.v` — Dependency of `dual_clock_fifo`: a simple dual-port RAM

## Interface
**DaulClkFifo (DC_FIFO):**
| Signal | Direction | Description |
|------|------|------|
| `Reset` | input | System reset |
| `WrClk` / `WrEn` / `WrData` | input | Write clock / write enable / write data |
| `WrFull` / `WrDNum` | output | Write-full flag / write-side data count |
| `RdClk` / `RdEn` | input | Read clock / read enable |
| `RdData` / `RdEmpty` / `RdDNum` | output | Read data / read-empty flag / read-side data count |

**dual_clock_fifo:** The interface consists of `i_arst` / `i_wclk` / `i_we` / `i_wdata` / `i_rclk` / `i_re` / `o_full` / `o_empty` / `o_rdata`, plus almost-full/empty and read/write count signals.

## Parameters
| Parameter | Description |
|------|------|
| `DATA_WIDTH` | Data width |
| `FIFO_DEPTH` / `ADDR_WIDTH` | FIFO depth / address width |
| `FIFO_MODE` | `"Normal"` / `"ShowAhead"` (DaulClkFifo); `"STD_FIFO"` / `"BYPASS"` (dual_clock_fifo) |
| `LATENCY` | Output latency stage count (dual_clock_fifo only) |

## Usage Examples
- TJ180A484_TSE — Cross-clock-domain data buffering for Gigabit Ethernet
- MIPI_RX_sc850 — Cross-clock-domain video stream buffering for MIPI CSI reception
