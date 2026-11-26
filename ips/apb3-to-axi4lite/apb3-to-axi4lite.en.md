---
EvoVerse_manifest_version: 1
kind: ip
id: apb3-to-axi4lite
display_name: APB3 to AXI4-Lite Bridge
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "Protocol bridge converting APB3 peripheral bus transactions to AXI4-Lite transactions"
---

English | [中文](apb3-to-axi4lite.md)

# APB3 to AXI4-Lite Bridge

## Source
Extracted from the following demo projects:
- TJ180A484_TSE
- TJ180A484S_SDHOST

## Files
- `rtl/apb3_2_axi4_lite.v` — General-purpose APB3-to-AXI4-Lite protocol bridge (from TJ180A484_TSE)
- `rtl/apb3_2_axi4_lite_sdhost.v` — SD-Host-specific APB3-to-AXI4-Lite protocol bridge variant (from TJ180A484S_SDHOST)

## Interface
- **APB3 slave side**: `PCLK` / `PRESETn` / `PSEL` / `PENABLE` / `PWRITE` / `PADDR` / `PWDATA` / `PRDATA` / `PREADY` / `PSLVERR`
- **AXI4-Lite master side**: `AWADDR` / `AWVALID` / `AWREADY` / `WDATA` / `WSTRB` / `WVALID` / `WREADY` / `BRESP` / `BVALID` / `ARADDR` / `ARVALID` / `ARREADY` / `RDATA` / `RRESP` / `RVALID` / `RREADY`

## Parameters
- Address and data widths are typically 32-bit; see the parameter declarations in each file for details.

## Usage Examples
- TJ180A484_TSE — APB3 SoC bus connected to an AXI4-Lite Ethernet MAC
- TJ180A484S_SDHOST — APB3 SoC bus connected to an AXI4-Lite SD Host controller
