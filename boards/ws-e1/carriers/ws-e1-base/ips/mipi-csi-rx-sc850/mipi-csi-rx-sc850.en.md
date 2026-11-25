---
ws_manifest_version: 1
kind: ip
id: mipi-csi-rx-sc850
display_name: MIPI CSI-2 RX (SC850SL 4-Lane 1.4Gbps)
version: 1.0.0
board: ws-e1
carrier: ws-e1-base
maintainer: evoverse
license: proprietary
description: MIPI CSI-2 Receiver IP for SmartSens SC850SL sensor (3840x2160@60fps, 4-lane, 1404Mbps/lane, 10-bit RAW). Includes I2C sensor initialization and data unpack logic.
---

English | [中文](mipi-csi-rx-sc850.md)

# MIPI CSI-2 RX (SC850SL 4-Lane 1.4Gbps)

## Source Demo
`demos/mipi-csi-rx-sc850sl/` (formerly `MIPI_RX_sc850/MIPI_RX_sc535/`)

## Hard IP Configuration
| IP name | VLNV | Version | Key parameters |
|---------|------|------|---------|
| hard_csi_rx | efinixinc.com:mipi:efx_csi2_rx_top | 5.5.1 | 4 data lanes, ASYNC_STAGE=2, CLOCK_FREQ=100MHz, PIXEL_FIFO_DEPTH=1024, GENERIC frame mode |

- Efinity toolchain version: 2023.2.307

## RTL Files
| File | Description |
|------|------|
| `rtl/top_2_5g.sv` | Top module — MIPI CSI-2 RX example design |
| `rtl/hard_csi_rx.sv` | Efinity MIPI CSI-2 RX hard IP wrapper |
| `rtl/hard_csi_rx_define.vh` | Hard IP wrapper macro definitions |
| `rtl/hard_csi_rx_tmpl.v` | Hard IP wrapper template (Verilog) |
| `rtl/efx_csi2_tx_top.sv` | CSI-2 TX top level (for loopback testing) |
| `rtl/data_unpack.v` | MIPI pixel data unpacking |
| `rtl/datatype_gen.v` | Data type generation |
| `rtl/dual_clock_fifo.v` | Clock domain crossing (CDC) FIFO |
| `rtl/simple_dual_port_ram.v` | Dual-port RAM |
| `rtl/shift_reg.v` | Shift register |
| `rtl/lfsr.v` | Linear feedback shift register (PRBS) |
| `rtl/pattern_gen.v` | Test pattern generator |
| `rtl/pattern_gen2.v` | Test pattern generator v2 |
| `rtl/vga_gen.v` | VGA timing generator |
| `rtl/reset.v` | Reset synchronizer |
| `rtl/smartsens_init.v` | SmartSens sensor I2C initialization top level |
| `rtl/sc535_i2c_init.v` | SC850SL I2C initialization sequence |
| `rtl/single_port_rom.v` | Single-port ROM (stores register configuration) |
| `rtl/sc850sl_init.mem` | SC850SL register initialization data |
| `rtl/settings.json` | Efinity IP generation configuration |

## Constraints
| File | Description |
|------|------|
| `constraints/Ti180_mipi.sdc` | Timing constraints (clock definitions, false paths, etc.) |
| `constraints/Ti180_mipi.peri.xml` | Peripheral/pin constraints (MIPI DPHY RX pin assignment) |

## Interfaces
- **Clocks**: `mipi_clk` (100MHz), `pixel_clk` (50MHz), `cfg_clk`, `mipi_dphy_rx_clk_CLKOUT` (312.5MHz HS byte clock)
- **PLLs**: `pll0_locked`, `pll1_locked`
- **MIPI DPHY RX**: 4-lane HS data (16-bit per lane), ULPS/ESC/STOP state signals, SKEWCAL, SYNC
- **Sensor initialization**: I2C interface (SCL/SDA) for SC850SL register configuration
- **Video output**: unpacked pixel data + sync signals (hsync/vsync/data_enable)

## Use Cases
MIPI CSI-2 camera input on the ws-e1-base carrier board. Receives the 4K@60fps RAW10 video stream from the SmartSens SC850SL sensor, decodes it through the hardware MIPI DPHY RX and CSI-2 controller, and outputs parallel pixel data for downstream image-processing modules.
