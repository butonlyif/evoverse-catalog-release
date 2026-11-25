English | [中文](README.md)
# usb-uvc-4k60-pattern — 4K60 Color-Bar UVC USB Camera (FPGA + FX10)

> Original directory: `Patten_uvc_4k60/Patten_uvc_4k60/` (Patten is a misspelling of Pattern)

## 1. Overview

A complete solution in which the **FPGA generates a 4K60 color-bar video stream and outputs it
to the PC as a UVC camera through the Cypress EZ-USB FX10**, covering three parts:

1. **FPGA project** (Efinity): an on-chip 3840×2160 YUYV six-color color bar is packed into
   512-bit AXIS and, after buffering/flow control by the encrypted netlist subsystem
   `uvc_top_ency`, is sent to the FX10 SIP port via **18 LVDS TX groups** (dual-channel GPIF,
   8:1 serialization);
2. **FX10 firmware** (C source): a UVC 1.1 + UAC (PDM microphone) application uploading over
   USB3.2 Gen2 Bulk; the PC enumerates it as a standard UVC camera;
3. **Programming tool** (OpenOCD): KitProg3 + SWD programming of the FX10 firmware.

Open a camera app on the PC and the 4K60 color-bar picture appears — no driver installation
needed.

- Device: Titanium **TJ180A484S** (C4)
- Toolchain: Efinity 2025.2.288.3.8 (pass); firmware GNU ARM 11.3 / ModusToolBox
- FPGA top module: `top` ([patten_fx10_ency/src/top.sv](patten_fx10_ency/src/top.sv))

## 2. Data Link

```
FPGA top.sv：6+1 色彩条 YUYV（每行 3840 像素，120 × 512-bit beat/行，clk_100m）
   → uvc_top_ency.v（加密网表：例化 slfifo_buffer + y/uv_data_fifo + csi2_hard_mipi_rx，
      内部完成视频缓存与流控）
   → LVDS TX ×18（fx10_gpif_lvds0/1：各 8 数据 + 控制，75MHz pclk，8:1 串化，
      large VOD + medium-high pre-emphasis）
   → FX10 SIP → HBDMA → SRAM → USB3.2 Gen2 Bulk EP1-IN → PC（UVC 枚举）
FX10→FPGA：fx10_spi_*（增强模式命令/状态）+ fx10_gpif_m_*（GPIF 从机握手）
```

## 3. Directory Structure

```
usb-uvc-4k60-pattern/
├── OpenOCD/                      # FX10 固件烧录工具树
│   └── bin/download.bat          # openocd -f interface/kitprog3.cfg -f target/fx3g2.cfg "program <fw>"
├── fx10_fw/                      # Cypress FX10 固件源码
│   ├── Lib/                      # FreeRTOS、PDL(CAT1E)、hb_dma、lvds、fx3g2_usb_common 等
│   └── fx3g2_uvc/                # ★ UVC+UAC 应用（main.c、cy_usb_app.c、描述符、
│       │                         #   cy_gpif_header_lvds.h/lvcmos.h、链接脚本、Readme.txt）
│       └── Readme.txt            # 固件详细文档（226 行，含构建/烧录说明）
└── patten_fx10_ency/             # ★ Efinity FPGA 工程
    ├── cam_uvc/                  # 工程目录（cam_uvc.xml / .peri.xml / efx_run.bat）
    │   └── ip/                   # csi2_hard_mipi_rx + slfifo_buffer + y/uv_data_fifo
    ├── sdc/constrain.sdc
    └── src/
        ├── top.sv                # 顶层（明文）：彩条生成 + AXIS 打包
        └── uvc_top_ency.v        # 加密网表（Verific 导出，不可审查/修改）
```

## 4. Key Configuration

- **peri.xml**: 3×PLL (27MHz → LVDS serialization clock family; 50MHz → clk_100m; 33.33MHz →
  ddr_clk is a leftover — the DDR hard IP is not configured); BL/TL banks 3.3V, all others
  1.8V; the `csi2_hard_mipi_rx` IP is in the project ip_info but `mipi_info` is empty (the
  MIPI hard IP is not actually used);
- **Firmware Makefile**: defaults `LVCMOS_EN=0` (LVDS mode), `WL_EN=1` (WideLink),
  `PORT1_EN=0`, `AUDIO_IF_EN=1` (PDM microphone P4.1/P4.2);
- **UVC format**: 3840×2160 YUY2 (4K@~60fps over USB3.2), with 720p/VGA also supported;
  every 61440B of video data carries a 32B UVC header (header added firmware-side,
  `INMD_EN=0`).

## 5. Build, Program, and Verify

**FPGA side**
1. Open `patten_fx10_ency/cam_uvc/cam_uvc.xml` in Efinity (or run `efx_run.bat` directly);
2. Build to generate the bitstream and program the FPGA.

**FX10 firmware side**
1. Following `fx10_fw/fx3g2_uvc/Readme.txt`: run `make` in a GNU ARM 11.3 environment;
2. Programming option A: OpenOCD — connect KitProg3 and run
   `OpenOCD/bin/download.bat <firmware>`;
   programming option B: `make BLENABLE=yes` to build a version programmable via the
   EZ-USB Control Center.

**Verification**
1. Connect the USB-C (J4, USB3.2) port to the PC;
2. A PC camera app (or AMCap/PotPlayer) should enumerate the UVC device and display the 4K60
   color bars;
3. The FX10 P8.1 UART @921600 shows the firmware run log.

## 6. Integration Notes for Customer Systems

- The **FPGA↔FX10 hardware interface** is the integration core: 18 LVDS groups (dual-channel
  8bit data + control, pclk 75MHz) + SPI command channel + GPIF slave handshake
  (oe_n/pktend_n/addr/rd_req_n/full/par_flag); pins and electrical parameters
  (VOD/pre-emphasis) are all in `cam_uvc.peri.xml`;
- **`uvc_top_ency.v` is an encrypted netlist** (black box): it can only be integrated by port
  behavior and its internal implementation cannot be inspected or modified. To replace the
  real video source, replace the color-bar generation part of `top.sv` while keeping the AXIS
  interface into `uvc_top_ency` (512-bit, 3840 pixels/row timing) unchanged;
- Changing the UVC resolution/frame rate on the firmware side requires updating the
  descriptors and the GPIF header file (`cy_gpif_header_lvds.h`) in sync — see the firmware
  Readme.txt for details;
- If the customer product does not need audio, rebuild the firmware with `AUDIO_IF_EN=0`;
- The LVDS electrical parameters were validated at 75MHz pclk + 8:1 serialization; changing
  the link rate requires updating the PLL and SDC in sync.

## 7. Known Issues and Notes

- `constrain.sdc` contains several clocks that do not exist in `top.sv`
  (S_AXI_CPU_ACLK/axi_m0_clk/mipi_pclk, etc. — SoC-version leftovers); the constraints are
  ineffective but cause no errors;
- The `pll_ddr` and `csi2_hard_mipi_rx` IPs are leftover configurations (neither the DDR nor
  the MIPI hard IP is enabled);
- The encrypted netlist comments leak the original development path (`D:\J\...`); no
  functional impact;
- This reorganization removed `patten_fx10_ency/ips/` (a Xilinx Vivado IP tree with zero
  references from the Efinity project) and the devkit reference-project copies embedded in
  each IP directory; the project is unaffected.
