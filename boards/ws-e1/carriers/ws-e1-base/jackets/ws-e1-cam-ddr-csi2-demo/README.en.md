English | [中文](README.md)

# ws-e1-cam-ddr-csi2-demo Jacket

WS-E1 (TJ180A484S) camera MIPI CSI-2 demo jacket: IMX415 sensor → CSI-2 RX → image processing → frames stored to DDR, with the RISC-V SoC (Sapphire) handling APB register control and IMX415 initialization (I2C).

## Structure

| Path | Contents |
|------|------|
| `ws-e1-cam-ddr-csi2.xml` | Efinity project (unified flow) |
| `ws-e1-cam-ddr-csi2.peri.xml` | PT-generated interface database (GPIO/bank/voltage) |
| `ws-e1-cam-ddr-csi2.sdc` | Timing constraints |
| `package_settings.xml` | Package settings |
| `rtl/` | `top_cam_demo.sv` top level + camera pipeline (`camera_path`, `apb_cam_ctrl`, `demosaic`, `raw_2_axi4st`, `rgb2yuv_axis`, `shape_video_axis`, etc.) |
| `ip/` | Hard IP sources: `my_csi2_rx`, `my_csi2_tx`, `riscv_soc` (including IP Manager projects) |
| `sw/` | `bsp/` (Sapphire BSP) + `top_demo/` (RISC-V bare-metal demo, `imx415_init.c` sensor initialization) |

## Building the FPGA

```
efx_run ws-e1-cam-ddr-csi2.xml --flow compile
```

map → interface(PT) → pnr → pgm in four stages; artifacts land in `outflow/` (build artifacts are not committed to the repository).

## Building the Software

`sw/top_demo` is an Eclipse project. Import it into the Efinity SDK / RISC-V GCC toolchain, run `make` to generate the ELF, then download and run it via JTAG (OpenOCD, see `sw/bsp/openocd`).

## History

2026-10-08: Removed the Efinity Debug section (la0 logic analyzer) and `debug_profile.wizard.json` from the project XML, restoring the standard compile flow.
