English | [中文](README.md)
# WS-E1 / WS-E1-Base Board Demo Projects

A collection of verification demos for the **WS-E1 core module + WS-E1-Base carrier**
(Titanium TJ180A484S). Each demo has one top-level directory named after its function;
the entry documentation is uniformly the `README.md` inside each directory.

## Demo Overview

| Demo | Function in One Sentence | Hard IP / Soft Core | Soft-Core Program | Verification | timing model |
| --- | --- | --- | --- | --- | --- |
| [ddr-memtest](ddr-memtest/) | LPDDR4x dual-AXI-port write/read comparison | DDR hard IP ×2 ports, 2×PLL | none | 6×LED result indicators | C4 |
| [si5338-clock-config](si5338-clock-config/) | Configure the Si5338 clock generator via I2C and verify it back | DDR, 3×PLL, LVDS RX, Sapphire | i2cCfgSi5338 | UART log + LED blink + oscilloscope | C4 |
| [ethernet-tse-udp-test](ethernet-tse-udp-test/) | Gigabit TSE MAC, UDP test-frame generation/loopback | TSE MAC (RGMII+MDIO), PLL, Sapphire | tseDemo | Wireshark capture / loopback | C4 |
| [imu-bmi088-readout](imu-bmi088-readout/) | RISC-V reads the BMI088 6-axis IMU | Sapphire + 2×PLL | i2cMasterDemo | UART prints 6-axis data | C4 |
| [mipi-csi-rx-sc850sl](mipi-csi-rx-sc850sl/) | SC850SL camera CSI-2 reception (4lane@2G) | DPHY RX, CSI2 RX IP, 2×PLL | none (hardware I2C initialization) | No external output; enable the Debugger in the GUI to observe RX status/counters | C4 |
| [sdcard-powercycle-retention](sdcard-powercycle-retention/) | SD card write → power-cycle → read-back verification | DDR, 2×PLL, Sapphire, SD Host | TJ180A484S_SDHOST | UART input W/R, outputs PASS | **I3** |
| [usb-uvc-4k60-pattern](usb-uvc-4k60-pattern/) | 4K60 color bars enumerated by FX10 as a UVC camera | 18×LVDS TX, 3×PLL | FX10 firmware (UVC+UAC) | View the 4K60 color bars in a PC camera app | C4 |
| [mipi-csi-tx-4k-pattern](mipi-csi-tx-4k-pattern/) | On-chip 4K YUV pattern sent over CSI-2 TX | DPHY TX, CSI2 TX IP, 3×PLL | none | MIPI capture card / protocol analyzer | **I3** |
| [mipi-loopback-test](mipi-loopback-test/) | CSI-2 TX→loopback→RX on-chip self-loopback comparison | **DPHY TX+RX dual hard IP**, 2×PLL | none | LED PASS/FAIL | C4 |

## General Information

- **Device**: all demos target the Efinix Titanium TJ180A484S (484-package); the timing model
  follows each demo (mostly C4, two are I3).
- **Toolchain**: Efinity 2025.1 ~ 2026.1 (versions differ per demo, see each README);
  every project has `last_run_state=pass` and has successfully produced a bitstream.
- **Opening a project**: enter each demo directory and follow the README to open the
  corresponding `*.xml` project file for compilation.
- **Debugger**: the Debugger is disabled in all demos (`auto_instantiation=off`);
  CLI builds no longer depend on `debug_top.v`. To observe internal signals online,
  manually re-enable the Debugger wizard in the Efinity GUI.
- **Board documentation**: see the carrier documentation in the parent directory
  [`../ws-e1-base.md`](../ws-e1-base.md) (pins, bank power, connector list).

## Choosing a Demo by Use Case

| Requirement | Recommended Starting Point |
| --- | --- |
| LPDDR4x / DDR hard IP bring-up | ddr-memtest (dual-port) → si5338-clock-config / sdcard-powercycle-retention (SoC+DDR single-port) |
| Ethernet / RGMII / TSE MAC | ethernet-tse-udp-test |
| I2C sensor integration (soft-core approach) | imu-bmi088-readout |
| MIPI camera reception | mipi-csi-rx-sc850sl (sensor solution) / verify the hard-IP link first with mipi-loopback-test |
| MIPI image/video transmission | mipi-csi-tx-4k-pattern |
| USB camera (UVC) product form factor | usb-uvc-4k60-pattern |
| SD card storage / power-cycle reliability | sdcard-powercycle-retention |
| Programmable clock (Si5338) | si5338-clock-config |

## Directory Reorganization Notes (2026-08)

This reorganization completed:

1. **Flattening**: removed the redundant outer wrapper directory of each demo
   (previously `X/X/` double nesting; SI5338 was originally three levels deep);
2. **Renaming**: directory names unified to kebab-case and named after function,
   consistent with the SDK ecosystem naming;
3. **Slimming**: deleted the full devkit reference-project copies embedded in each IP
   directory (T120/Ti60/Ti180 and other device templates), the unrelated Xilinx Vivado
   IP tree, the unreferenced dsi_tx/soft_csi IPs, duplicate software trees, and leftover
   temporary files (`~$*.xlsx`, `*.pre_import.xml`, `debug_TEMPLATE.*`, `modelsim.ini_new`);
4. **Documentation**: wrote a detailed README for each demo (overview, resources,
   structure, working principle, build & programming, verification, integration notes,
   known issues).

Old name → new name mapping:

| Old Directory | New Directory |
| --- | --- |
| `DDR_TEST/DDR_TEST/` | `ddr-memtest/` |
| `SI5338/SI5338/TJ180A484_soc_lpddr4/` | `si5338-clock-config/` |
| `TJ180A484_TSE/TSE/` | `ethernet-tse-udp-test/` |
| `imu_bmi088/imu_bmi088/` | `imu-bmi088-readout/` |
| `MIPI_RX_sc850/MIPI_RX_sc535/` | `mipi-csi-rx-sc850sl/` |
| `TJ180A484S_SDHOST/TJ180A484S/` | `sdcard-powercycle-retention/` |
| `Patten_uvc_4k60/Patten_uvc_4k60/` | `usb-uvc-4k60-pattern/` |
| `TJ180J484_CSI_4k_2370Ma/Ti180J484_CSI_4k_2370Ma/` | `mipi-csi-tx-4k-pattern/` |
| `TJ180MIPI_loopback/Ti180MIPI/` | `mipi-loopback-test/` |

> Internal project directories (`bsp/`, `project_new/`, `rtl/`, `ip/`, etc.) remain
> unchanged; Efinity project files use relative-path references, so moving the tree does
> not affect opening or building.

## Restoration and Full Compile Verification (2026-10)

1. **Restored project files that had been trimmed** (accidentally deleted during the 2026-08
   slimming pass, now replenished from the original projects):
   `imu-bmi088-readout/ip/soc/soc.v` (Sapphire SoC generated wrapper RTL),
   `usb-uvc-4k60-pattern/patten_fx10_ency/cam_uvc/cam_uvc.xml` together with
   `cam_uvc.peri.xml` and `src/uvc_top_ency.v` (encrypted netlists);
2. **DDR density alignment**: in the `*.peri.xml` of ddr-memtest / si5338 / sdcard the DDR
   hard-core density was changed 4G → 2G to match the on-board LPDDR4x device;
3. **Full compile verification**: all 9 demos were built in their own project directories
   with `efx_run --flow compile`; every map / interface / pnr / pgm stage PASSed;
4. Intermediate artifacts from the verification (`outflow/`, `work_syn/`, `work_pnr/`,
   `work_dbg/`) were cleaned up afterwards — the catalog carries no bitstreams.
