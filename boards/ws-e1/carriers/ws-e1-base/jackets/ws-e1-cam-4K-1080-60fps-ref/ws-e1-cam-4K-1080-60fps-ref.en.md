[中文](ws-e1-cam-4K-1080-60fps-ref.md) | English

# WS-E1 Base 4K / 1080p@60 Camera Reference

`ws-e1-cam-4K-1080-60fps-ref` is a camera reference jacket for ws-e1 + ws-e1-base: IMX415 MIPI capture → image processing → DDR buffering, supporting 4K and 1080p@60fps output.

## Hardware

- MIPI2 RX camera input (IMX415)
- Camera I2C control (`cam_1_scl` / `cam_1_sda` / `cam_1_en`)
- DDR3 buffering
- RISC-V SoC (`riscv_soc`)

## Project files

- `ws-e1-cam-ddr-csi2.xml` — Efinity project
- `rtl/` — RTL sources (`top_cam_demo.sv` etc.)
- `sw/` — firmware (including `imx415_init`)
