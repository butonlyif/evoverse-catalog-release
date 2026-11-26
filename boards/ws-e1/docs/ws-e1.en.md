---
ws_manifest_version: 2
kind: module
id: ws-e1
display_name: WS E1 Core Module
version: 1.0.0
status: active
fpga:
  vendor: elitestek
  family: Titanium
  part: TJ180A484S
  package: J484
  timing_model: C4
carriers:
  - ws-e1-base
constraint_owner: carrier
---
English | [中文](ws-e1.md)

# Core Board Specification

> **Applicable SDK Version**: v0.8.0 · 2026-07-30


| Property | Value |
|--------|------------|
| Version | v1.0.0     |
| Date | 2026-07-20 |
| Status | released   |


## 1. Product Overview

The WS core board is a flexible and versatile high-performance, low-power FPGA processing module. It natively integrates multiple MIPI D-PHY 2.5G transceiver ports, a USB 3.2 high-speed serial interface, and more, and can be flexibly configured via the FPGA to extend support for Ethernet, various sensor interfaces, industrial communication ports, and other interfaces. The WS core board is built on the Efinix Titanium™ series FPGA and is widely used across industrial fields such as video processing, data acquisition, robot control, and AI acceleration.

### 1.1 Version Description

The core board is offered in 4 variants, all built on the same core FPGA chip; the main difference lies in the USB controller configuration:


| Version | USB PHY Controller | Description |
|-----------|------------------|------------------------------------------------------------------|
| MC-00-U00 | None | Basic variant, no USB interface, uses schematic revision B |
| MC-00-U05 | EZ-USB™ FX5 | USB 3.2 Gen1×1, low-cost option, uses schematic revision A |
| MC-00-U10 | EZ-USB™ FX10 | USB 3.2 Gen2×1, standard option, uses schematic revision A |
| MC-00-U20 | EZ-USB™ FX20 | USB 3.2 Gen2×2, maximum bandwidth, uses schematic revision A |


**Compatibility Note**: All core board variants share the same connector and PCB layout design and interconnect seamlessly with the same base board. Schematic revision A does not have connector P4.

### 1.2 Core Board Architecture

%%KEEP_LINE_52%%

## 2. Hardware Specifications

### 2.1 Key Devices


| Device | Part Number | Description |
|------------------|------------------------------------|---|
| FPGA | TJ180A484S | Efinix Titanium™ Ti180, 484-FBGA SiP package |
| USB PHY Controller | EZ-USB™ FX5/FX10/FX20 | Infineon EZ-USB™ series with USB3.2 support, differing by core board variant. MC-00-U00: not installed; MC-00-U05: up to 5Gbps USB transfer; MC-00-U10: up to 10Gbps USB transfer; MC-00-U20: up to 20Gbps USB transfer |
| Flash | W25Q256JWPIQ | Winbond Electronics, QSPI 256Mb, stores the FPGA boot image |
| Clock | U13:50MHz, U14:33.33MHz, U15:27MHz | U13 connects to FPGA pin T18 as the main logic reference clock; U14 connects to FPGA pin Y14 as the DDR reference clock; U15 outputs connect to FPGA pins AA10 and AA15 as the MIPI interface reference clocks |
| Security Chip | RJGT05T3 | Provides security protection for the FPGA boot image |


### 2.2 Main Connectors


| Connector | Part Number | Description |
|-----------|-------------|---|
| P1 | DF40C-100DP | Provides 4 dedicated MIPI D-PHY 2.5Gbps 4-lane interfaces in total (2 TX + 2 RX; each group has 5 high-speed differential pairs: 1 clock + 4 data), plus 32 FPGA user IO pins |
| P2 | DF40C-120DP | USB PHY controller interface (including USB high-speed signals), plus 42 FPGA user IO pins |
| P3 | DF40C-120DP | 78 FPGA user IO pins, the 5V main power input of the core board, and the JTAG signals for FPGA configuration loading |
| P4 | (Reserved) | (Reserved) |
| P5 | DF40C-20DP | Integrates the JTAG programming port of the FPGA (and its internal soft-core CPU), the JTAG programming port of the EZ USB PHY controller, and the 5V core board power supply port (the board can be powered standalone when no base board is attached). Compact design; a dedicated adapter accessory is required to connect to the corresponding programmer |


>
>
**User IO Breakout**: The FPGA breaks out a total of 73 HVIO pins and 124 HSIO (62 pairs) pins to the connectors.
>

### 2.3 Buttons/Switches


| Device | Description |
|---------------|---------------------------------------------------------------------------------|
| FX_RST(SW1) | USB PHY controller reset push-button switch |
| FPGA_RST(SW2) | FPGA reset push-button switch |
| SW3 | 2-bit DIP switch, boot image selection (CBSEL) when the FPGA actively loads from flash |


### 2.4 Indicators


| Device | Description |
|--------|----------------------------------------------------------|
| D2 | Green LED, EZ USB PHY controller indicator |
| D3 | Green LED, FPGA configuration-done indicator (CDONE) |
| D4 | Green LED, user-controllable indicator, connected to FPGA pin AA11 |


## 3. Power Requirements

### 3.1 Power Specifications


| Parameter | Value | Description |
|------------------------|----------|-----------------------|
| **Main supply voltage** | 5V DC | Core board operating voltage |
| **Theoretical maximum current** | < 3A | Peak current at full load |
| **Expected supply ripple** | ≤ 50mV | Power supply noise target |


### 3.2 Power Input Path

When the core board system is in operation, the power input path should go through **connector P3**
and be powered from the base board system.

### 3.3 Standalone Power Connector (P5) ⭐

The design reserves connector **P5** for powering up and configuring the core board independently when it is not attached to a base board.

>
> ⚠️ **Safety Warning**: **P5 and P3
must never be connected to other systems** (such as a base board or a programmer) at the same time. Connecting both simultaneously may cause power conflicts, circuit damage, or other unpredictable consequences.
>

## 4. Mechanical Specifications

As shown in the top view below, the physical planar dimensions of the core board are approximately **40mm ×
45mm**. With all components installed, the height difference between the highest and lowest points of the core board is approximately 6mm. When designing your own system, treat 6mm as the minimum physical height difference and leave ample margin to avoid conflicts with other structures.

Because the WS product comes in multiple variants, please contact your sales or customer service representative to confirm the latest information on mechanical dimension specifications and avoid improper losses.

%%KEEP_LINE_138%%

## 5. Ordering Information

### 5.1 Product Model Naming Rule (Preliminary)

```
WS-MA-XXXX
   │    │  
   │    └─ 版本代号  
   └─────── 产品系列
```

### 5.2 Standard Product List (Preliminary)


| Model | FPGA | USB PHY Controller | Description |
|--------------|------------|------------------|---------------------------|
| WS-MA-00 | TJ180A484S | None | FPGA core board |
| WS-MA-05 | TJ180A484S | EZ-USB™ FX5 | Up to USB3.2 5Gbps |
| WS-MA-10 | TJ180A484S | EZ-USB™ FX10 | Up to USB3.2 10Gbps |
| WS-MA-20 | TJ180A484S | EZ-USB™ FX20 | Up to USB3.2 20Gbps |


### 5.3 Contact

For more product information or to request a quotation, please contact our sales team.

## Appendix A. Connector Pin Assignment Tables

### A.1 Connector P1 Pin Assignment Table (Part Number: DF40C-100DP)


| Pin | Signal Name | Signal Description | Pin | Signal Name | Signal Description |
|-----------|-------------|------------------------|-----------|-------------|------------------------|
| 1 | MIPI0_TXDP0 | MIPI0 TX data positive | 2 | MIPI0_TXDN0 | MIPI0 TX data negative |
| 3 | MIPI0_TXDP1 | MIPI0 TX data positive | 4 | MIPI0_TXDN1 | MIPI0 TX data negative |
| 5 | MIPI0_TXDP2 | MIPI0 TX data positive | 6 | MIPI0_TXDN2 | MIPI0 TX data negative |
| 7 | MIPI0_TXDP3 | MIPI0 TX data positive | 8 | MIPI0_TXDN3 | MIPI0 TX data negative |
| 9 | MIPI0_TXDP4 | MIPI0 TX data positive | 10 | MIPI0_TXDN4 | MIPI0 TX data negative |
| 11 | MIPI0_RXDP0 | MIPI0 RX data positive | 12 | MIPI0_RXDN0 | MIPI0 RX data negative |
| 13 | MIPI0_RXDP1 | MIPI0 RX data positive | 14 | MIPI0_RXDN1 | MIPI0 RX data negative |
| 15 | MIPI0_RXDP2 | MIPI0 RX data positive | 16 | MIPI0_RXDN2 | MIPI0 RX data negative |
| 17 | MIPI0_RXDP3 | MIPI0 RX data positive | 18 | MIPI0_RXDN3 | MIPI0 RX data negative |
| 19 | MIPI0_RXDP4 | MIPI0 RX data positive | 20 | MIPI0_RXDN4 | MIPI0 RX data negative |
| 21 | MIPI2_TXDP0 | MIPI2 TX data positive | 22 | MIPI2_TXDN0 | MIPI2 TX data negative |
| 23 | MIPI2_TXDP1 | MIPI2 TX data positive | 24 | MIPI2_TXDN1 | MIPI2 TX data negative |
| 25 | MIPI2_TXDP2 | MIPI2 TX data positive | 26 | MIPI2_TXDN2 | MIPI2 TX data negative |
| 27 | MIPI2_TXDP3 | MIPI2 TX data positive | 28 | MIPI2_TXDN3 | MIPI2 TX data negative |
| 29 | MIPI2_TXDP4 | MIPI2 TX data positive | 30 | MIPI2_TXDN4 | MIPI2 TX data negative |
| 31 | MIPI2_RXDP0 | MIPI2 RX data positive | 32 | MIPI2_RXDN0 | MIPI2 RX data negative |
| 33 | MIPI2_RXDP1 | MIPI2 RX data positive | 34 | MIPI2_RXDN1 | MIPI2 RX data negative |
| 35 | MIPI2_RXDP2 | MIPI2 RX data positive | 36 | MIPI2_RXDN2 | MIPI2 RX data negative |
| 37 | MIPI2_RXDP3 | MIPI2 RX data positive | 38 | MIPI2_RXDN3 | MIPI2 RX data negative |
| 39 | MIPI2_RXDP4 | MIPI2 RX data positive | 40 | MIPI2_RXDN4 | MIPI2 RX data negative |
| 41 | GPIOL_4 | FPGA user IO | 42 | GPIOL_46 | FPGA user IO |
| 43 | GPIOL_31 | FPGA user IO | 44 | GPIOL_1 | FPGA user IO |
| 45 | GPIOL_3 | FPGA user IO | 46 | GPIOL_44 | FPGA user IO |
| 47 | GPIOL_30 | FPGA user IO | 48 | GPIOL_7 | FPGA user IO |
| 49 | GPIOL_5 | FPGA user IO | 50 | GPIOL_43 | FPGA user IO |
| 51 | GPIOL_49 | FPGA user IO | 52 | GPIOL_2 | FPGA user IO |
| 53 | GPIOL_10 | FPGA user IO | 54 | GPIOL_41 | FPGA user IO |
| 55 | GPIOL_38 | FPGA user IO | 56 | GPIOL_55 | FPGA user IO |
| 57 | GPIOL_40 | FPGA user IO | 58 | GPIOL_36 | FPGA user IO |
| 59 | GPIOL_50 | FPGA user IO | 60 | GPIOL_45 | FPGA user IO |
| 61 | GPIOL_42 | FPGA user IO | 62 | GPIOL_28 | FPGA user IO |
| 63 | GPIOL_29 | FPGA user IO | 64 | GPIOL_54 | FPGA user IO |
| 65 | GPIOL_37 | FPGA user IO | 66 | GPIOL_39 | FPGA user IO |
| 67 | GPIOL_51 | FPGA user IO | 68 | GPIOL_33 | FPGA user IO |
| 69 | GPIOL_52 | FPGA user IO | 70 | GPIOL_34 | FPGA user IO |
| 71 | GPIOL_35 | FPGA user IO | 72 | GPIOL_53 | FPGA user IO |
| 73 | VDD33 | 3.3V power | 74 | GND | Ground |
| 75 | VDD18 | 1.8V power | 76 | GND | Ground |
| 77 | VDD5V | 5V power | 78 | GND | Ground |
| 79 | VQPS | 1.8V power | 80 | GND | Ground |
| 81 | FX10_P100 | USB PHY controller signal | 82 | FX10_P83 | USB PHY controller signal |
| 83 | FX10_P101 | USB PHY controller signal | 84 | FX10_RST | USB PHY controller reset |
| 85 | CC2 | USB Type-C CC signal | 86 | CC1 | USB Type-C CC signal |
| 87 | CRESET_N | FPGA configuration reset | 88 | TDI | FPGA JTAG data input |
| 89 | TMS | FPGA JTAG mode select | 90 | TCK | FPGA JTAG clock |
| 91 | TDO | FPGA JTAG data output | 92 | VDD33 | 3.3V power |
| 93 | GND | Ground | 94 | VDD18 | 1.8V power |
| 95 | GND | Ground | 96 | VDD5V | 5V power |
| 97 | GND | Ground | 98 | VQPS | 1.8V power |
| 99 | GND | Ground | 100 | GND | Ground |


### A.2 Connector P2 Pin Assignment Table (Part Number: DF40C-120DP)


| Pin | Signal Name | Signal Description | Pin | Signal Name | Signal Description |
|-----------|----------------|----------------------------------------|-----------|-----------------|---------------------------------|
| 1 | USB3RX1P | USB3.2 Gen2×1 RX data positive | 2 | USB3RX1N | USB3.2 Gen2×1 RX data negative |
| 3 | USB3RX2P | USB3.2 Gen2×1 RX data positive | 4 | USB3RX2N | USB3.2 Gen2×1 RX data negative |
| 5 | TX1+ | USB3.2 Gen2×1 TX data positive | 6 | TX1- | USB3.2 Gen2×1 TX data negative |
| 7 | TX2+ | USB3.2 Gen2×1 TX data positive | 8 | TX2- | USB3.2 Gen2×1 TX data negative |
| 9 | USB2DP1 | USB2.0 DP signal | 10 | USB2DN1 | USB2.0 DN signal |
| 11 | CC1 | USB Type-C CC signal | 12 | CC2 | USB Type-C CC signal |
| 13 | FX10_RST | USB PHY controller reset | 14 | FX10_TCK_SWDCLK | USB PHY controller SWD clock |
| 15 | FX10_TMS_SWDIO | USB PHY controller SWD data input/output | 16 | FX10_TDO | USB PHY controller SWD data output |
| 17 | FX10_TDI | USB PHY controller SWD data input | 18 | USBFSDP | USB FS DP signal |
| 19 | USBFSDN | USB FS DN signal | 20 | VDD33 | 3.3V power |
| 21 | GND | Ground | 22 | VDD18 | 1.8V power |
| 23 | GND | Ground | 24 | VDD5V | 5V power |
| 25 | GND | Ground | 26 | VQPS | 1.8V power |
| 27 | GND | Ground | 28 | VBUS | USB bus power |
| 29 | GND | Ground | 30 | FX10_P81 | USB PHY controller signal |
| 31 | FX10_P80 | USB PHY controller signal | 32 | GPIOR_64 | FPGA user IO |
| 33 | GPIOR_63 | FPGA user IO | 34 | GPIOR_60 | FPGA user IO |
| 35 | GPIOR_56 | FPGA user IO | 36 | GPIOR_68 | FPGA user IO |
| 37 | GPIOR_65 | FPGA user IO | 38 | GPIOR_72 | FPGA user IO |
| 39 | GPIOR_57 | FPGA user IO | 40 | GPIOR_69 | FPGA user IO |
| 41 | GPIOR_66 | FPGA user IO | 42 | GPIOR_71 | FPGA user IO |
| 43 | GPIOR_73 | FPGA user IO | 44 | GPIOR_58 | FPGA user IO |
| 45 | GPIOR_59 | FPGA user IO | 46 | GPIOR_70 | FPGA user IO |
| 47 | GPIOR_61 | FPGA user IO | 48 | FX10_P82 | USB PHY controller signal |
| 49 | FX10_P86 | USB PHY controller signal | 50 | FX10_P00 | USB PHY controller signal |
| 51 | FX10_P01 | USB PHY controller signal | 52 | 2C_GPIOT_N31 | FPGA user IO |
| 53 | 2C_GPIOT_P31 | FPGA user IO | 54 | 2C_GPIOT_P30 | FPGA user IO |
| 55 | 2C_GPIOT_N30 | FPGA user IO | 56 | 2C_GPIOT_P32 | FPGA user IO |
| 57 | 2C_GPIOT_N32 | FPGA user IO | 58 | GPIOL_4 | FPGA user IO |
| 59 | GPIOL_46 | FPGA user IO | 60 | GPIOL_31 | FPGA user IO |
| 61 | GPIOL_1 | FPGA user IO | 62 | GPIOL_3 | FPGA user IO |
| 63 | GPIOL_44 | FPGA user IO | 64 | GPIOL_30 | FPGA user IO |
| 65 | VDD33 | 3.3V power | 66 | GND | Ground |
| 67 | VDD18 | 1.8V power | 68 | GND | Ground |
| 69 | VDD5V | 5V power | 70 | GND | Ground |
| 71 | VQPS | 1.8V power | 72 | GND | Ground |
| 73 | VBUS | USB bus power | 74 | GND | Ground |
| 75 | FX10_P87 | USB PHY controller signal | 76 | GND | Ground |
| 77 | GPIOL_7 | FPGA user IO | 78 | GPIOL_5 | FPGA user IO |
| 79 | GPIOL_43 | FPGA user IO | 80 | GPIOL_49 | FPGA user IO |
| 81 | GPIOL_2 | FPGA user IO | 82 | GPIOL_10 | FPGA user IO |
| 83 | GPIOL_41 | FPGA user IO | 84 | GPIOL_38 | FPGA user IO |
| 85 | GPIOL_55 | FPGA user IO | 86 | GPIOL_40 | FPGA user IO |
| 87 | GPIOL_36 | FPGA user IO | 88 | GPIOL_50 | FPGA user IO |
| 89 | GPIOL_45 | FPGA user IO | 90 | GPIOL_42 | FPGA user IO |
| 91 | GPIOL_28 | FPGA user IO | 92 | GPIOL_29 | FPGA user IO |
| 93 | GPIOL_54 | FPGA user IO | 94 | GPIOL_37 | FPGA user IO |
| 95 | GPIOL_39 | FPGA user IO | 96 | GPIOL_51 | FPGA user IO |
| 97 | GPIOL_33 | FPGA user IO | 98 | GPIOL_52 | FPGA user IO |
| 99 | GPIOL_34 | FPGA user IO | 100 | GPIOL_35 | FPGA user IO |
| 101 | GPIOL_53 | FPGA user IO | 102 | VDD33 | 3.3V power |
| 103 | GND | Ground | 104 | VDD18 | 1.8V power |
| 105 | GND | Ground | 106 | VDD5V | 5V power |
| 107 | GND | Ground | 108 | VQPS | 1.8V power |
| 109 | GND | Ground | 110 | VBUS | USB bus power |
| 111 | GND | Ground | 112 | FX10_P84 | USB PHY controller signal |
| 113 | FX10_P85 | USB PHY controller signal | 114 | GPIOR_62 | FPGA user IO |
| 115 | GPIOR_67 | FPGA user IO | 116 | GPIOR_68 | FPGA user IO |
| 117 | GPIOR_69 | FPGA user IO | 118 | GPIOR_70 | FPGA user IO |
| 119 | GPIOR_71 | FPGA user IO | 120 | GPIOR_72 | FPGA user IO |


### A.3 Connector P3 Pin Assignment Table (Part Number: DF40C-120DP)


| Pin | Signal Name | Signal Description | Pin | Signal Name | Signal Description |
|-----------|--------------|----------------------------------|-----------|--------------|-----------------------|
| 1 | GPIOR_P17 | FPGA user IO | 2 | GPIOB_N17 | FPGA user IO |
| 3 | 2C_GPIOT_P34 | FPGA user IO | 4 | 2C_GPIOT_N34 | FPGA user IO |
| 5 | 2C_GPIOT_P33 | FPGA user IO | 6 | 2C_GPIOT_N33 | FPGA user IO |
| 7 | 2C_GPIOT_P32 | FPGA user IO | 8 | 2C_GPIOT_N32 | FPGA user IO |
| 9 | 2C_GPIOT_P31 | FPGA user IO | 10 | 2C_GPIOT_N31 | FPGA user IO |
| 11 | 2C_GPIOT_P30 | FPGA user IO | 12 | 2C_GPIOT_N30 | FPGA user IO |
| 13 | 2C_GPIOT_P29 | FPGA user IO | 14 | 2C_GPIOT_N29 | FPGA user IO |
| 15 | 2C_GPIOT_P28 | FPGA user IO | 16 | 2C_GPIOT_N28 | FPGA user IO |
| 17 | 3A_GPIOR_P45 | FPGA user IO | 18 | 3A_GPIOR_N45 | FPGA user IO |
| 19 | 3A_GPIOR_P44 | FPGA user IO | 20 | 3A_GPIOR_N44 | FPGA user IO |
| 21 | 3A_GPIOR_P43 | FPGA user IO | 22 | 3A_GPIOR_N43 | FPGA user IO |
| 23 | 3A_GPIOR_P42 | FPGA user IO | 24 | 3A_GPIOR_N42 | FPGA user IO |
| 25 | 3A_GPIOR_P41 | FPGA user IO | 26 | 3A_GPIOR_N41 | FPGA user IO |
| 27 | 3A_GPIOR_P40 | FPGA user IO | 28 | 3A_GPIOR_N40 | FPGA user IO |
| 29 | 3A_GPIOR_P39 | FPGA user IO | 30 | 3A_GPIOR_N39 | FPGA user IO |
| 31 | 3A_GPIOR_P38 | FPGA user IO | 32 | 3A_GPIOR_N38 | FPGA user IO |
| 33 | 3A_GPIOR_P37 | FPGA user IO | 34 | 3A_GPIOR_N37 | FPGA user IO |
| 35 | 3A_GPIOR_P36 | FPGA user IO | 36 | 3A_GPIOR_N36 | FPGA user IO |
| 37 | 3A_GPIOR_P35 | FPGA user IO | 38 | 3A_GPIOR_N35 | FPGA user IO |
| 39 | 3A_GPIOR_P34 | FPGA user IO | 40 | 3A_GPIOR_N34 | FPGA user IO |
| 41 | 3A_GPIOR_P33 | FPGA user IO | 42 | 3A_GPIOR_N33 | FPGA user IO |
| 43 | 3A_GPIOR_P32 | FPGA user IO | 44 | 3A_GPIOR_N32 | FPGA user IO |
| 45 | 3C_GPIOR_P14 | FPGA user IO | 46 | 3C_GPIOR_N14 | FPGA user IO |
| 47 | 3C_GPIOR_P13 | FPGA user IO | 48 | 3C_GPIOR_N13 | FPGA user IO |
| 49 | 3C_GPIOR_P12 | FPGA user IO | 50 | 3C_GPIOR_N12 | FPGA user IO |
| 51 | 3C_GPIOR_P11 | FPGA user IO | 52 | 3C_GPIOR_N11 | FPGA user IO |
| 53 | 3C_GPIOR_P10 | FPGA user IO | 54 | 3C_GPIOR_N10 | FPGA user IO |
| 55 | 3C_GPIOR_P9 | FPGA user IO | 56 | 3C_GPIOR_N9 | FPGA user IO |
| 57 | 3C_GPIOR_P7 | FPGA user IO | 58 | 3C_GPIOR_N7 | FPGA user IO |
| 59 | 3C_GPIOR_P6 | FPGA user IO | 60 | 3C_GPIOR_N6 | FPGA user IO |
| 61 | 3C_GPIOR_P5 | FPGA user IO | 62 | 3C_GPIOR_N5 | FPGA user IO |
| 63 | 3C_GPIOR_P4 | FPGA user IO | 64 | 3C_GPIOR_N4 | FPGA user IO |
| 65 | 3C_GPIOR_P3 | FPGA user IO | 66 | 3C_GPIOR_N3 | FPGA user IO |
| 67 | TCK | FPGA JTAG clock | 68 | TMS | FPGA JTAG mode select |
| 69 | TDI | FPGA JTAG data input | 70 | TDO | FPGA JTAG data output |
| 71 | CRESET_N | FPGA JTAG reset | 72 | GND | Ground |
| 73 | VDD5V | 5V power (core board main power) | 74 | GND | Ground |
| 75 | VDD33 | 3.3V power | 76 | GND | Ground |
| 77 | VDD18 | 1.8V power | 78 | GND | Ground |
| 79 | VQPS | 1.8V power | 80 | GND | Ground |
| 81 | VDD11 | 1.1V power | 82 | GND | Ground |
| 83 | VDD095 | 0.95V power | 84 | GND | Ground |
| 85 | VDD085 | 0.85V power | 86 | GND | Ground |
| 87 | VDD06 | 0.6V power | 88 | GND | Ground |
| 89 | GPIOL_55 | FPGA user IO | 90 | GPIOR_73 | FPGA user IO |
| 91 | GPIOL_54 | FPGA user IO | 92 | GPIOR_72 | FPGA user IO |
| 93 | GPIOL_53 | FPGA user IO | 94 | GPIOR_71 | FPGA user IO |
| 95 | GPIOL_52 | FPGA user IO | 96 | GPIOR_70 | FPGA user IO |
| 97 | GPIOL_51 | FPGA user IO | 98 | GPIOR_69 | FPGA user IO |
| 99 | GPIOL_50 | FPGA user IO | 100 | GPIOR_68 | FPGA user IO |
| 101 | GPIOL_49 | FPGA user IO | 102 | GPIOR_67 | FPGA user IO |
| 103 | GPIOL_46 | FPGA user IO | 104 | GPIOR_66 | FPGA user IO |
| 105 | GPIOL_45 | FPGA user IO | 106 | GPIOR_65 | FPGA user IO |
| 107 | GPIOL_44 | FPGA user IO | 108 | GPIOR_64 | FPGA user IO |
| 109 | GND | Ground | 110 | VDD5V | 5V power |
| 111 | GND | Ground | 112 | VDD33 | 3.3V power |
| 113 | GND | Ground | 114 | VDD18 | 1.8V power |
| 115 | GND | Ground | 116 | VQPS | 1.8V power |
| 117 | GND | Ground | 118 | VDD11 | 1.1V power |
| 119 | GND | Ground | 120 | VDD095 | 0.95V power |


### A.4 Connector P4 Pin Assignment Table (Part Number: Reserved)


| Pin | Signal Name | Signal Description |
|-----------|-----------|--------------|
| 1 | - | Reserved |
| 2 | - | Reserved |
| 3 | - | Reserved |
| 4 | - | Reserved |
| 5 | - | Reserved |
| 6 | - | Reserved |
| 7 | - | Reserved |
| 8 | - | Reserved |
| 9 | - | Reserved |
| 10 | - | Reserved |
| 11 | - | Reserved |
| 12 | - | Reserved |
| 13 | - | Reserved |
| 14 | - | Reserved |
| 15 | - | Reserved |
| 16 | - | Reserved |
| 17 | - | Reserved |
| 18 | - | Reserved |
| 19 | - | Reserved |
| 20 | - | Reserved |


### A.5 Connector P5 Pin Assignment Table (Part Number: DF40C-20DP)


| Pin | Signal Name | Signal Description |
|-----------|-----------------|-------------------------------------------|
| 1 | VDD5V | 5V power input |
| 2 | GND | Ground |
| 3 | TCK | FPGA JTAG test clock |
| 4 | GND | Ground |
| 5 | TMS | FPGA JTAG test mode select |
| 6 | GND | Ground |
| 7 | TDI | FPGA JTAG test data input |
| 8 | GND | Ground |
| 9 | TDO | FPGA JTAG test data output |
| 10 | GND | Ground |
| 11 | CRESET_N | FPGA JTAG test reset |
| 12 | GND | Ground |
| 13 | FX10_TCK_SWDCLK | EZ USB PHY controller SWD clock |
| 14 | GND | Ground |
| 15 | FX10_TMS_SWDIO | EZ USB PHY controller SWD data input/output |
| 16 | GND | Ground |
| 17 | FX10_TDO | EZ USB PHY controller SWD data output |
| 18 | GND | Ground |
| 19 | FX10_TDI | EZ USB PHY controller SWD data input |
| 20 | GND | Ground |

 
