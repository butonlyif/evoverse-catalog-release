[中文](ws-e1-tse.md) | English

# WS-E1 Triple Speed Ethernet (RGMII) UDP Demo

`ws-e1-TSE` is a Triple Speed Ethernet (RGMII) UDP demo for the ws-e1 module + ws-e1-base carrier. It sends/echoes UDP frames over RGMII gigabit Ethernet and accepts a MIPI camera as a data source.

## Hardware

- RGMII gigabit PHY (MDC/MDIO + 12 RGMII signals, 3A bank 1.8 V)
- MIPI2 RX camera input (IMX415, 4 lanes + clock)
- Camera I2C control (`cam_1_scl` / `cam_1_sda` / `cam_1_en`)
- System UART (debug console)

## Project files

- `ws_e1_tse.xml` — Efinity project
- `ws_e1_tse.peri.xml` — interface / pin definition
- `rtl/` — RTL sources
- `embedded_sw/` — RISC-V firmware

## Known status

TX path verified on board (PC receives pattern frames). RX path is still under investigation due to the `rgmii_rxc` clock-connection limitation; see `DAYLOG/2026-11.md`.
