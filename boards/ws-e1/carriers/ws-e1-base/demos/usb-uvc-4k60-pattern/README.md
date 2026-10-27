[English](README.en.md) | 中文
# usb-uvc-4k60-pattern — 4K60 彩条 UVC USB 摄像头（FPGA + FX10）

> 原目录：`Patten_uvc_4k60/Patten_uvc_4k60/`（Patten 为 Pattern 拼写错误）

## 1. 概述

**FPGA 生成 4K60 彩条视频流，经 Cypress EZ-USB FX10 以 UVC 摄像头形式输出到
PC** 的完整方案，覆盖三部分：

1. **FPGA 工程**（Efinity）：片内生成 3840×2160 YUYV 六色彩条，打成 512-bit
   AXIS，经加密网表子系统 `uvc_top_ency` 缓存/流控后由 **18 组 LVDS TX**
   （双通道 GPIF，8:1 串化）送入 FX10 的 SIP 口；
2. **FX10 固件**（C 源码）：UVC 1.1 + UAC（PDM 麦克风）应用，USB3.2 Gen2
   Bulk 上传，PC 枚举为标准 UVC 摄像头；
3. **烧录工具**（OpenOCD）：KitProg3 + SWD 烧录 FX10 固件。

PC 端打开相机应用即可看到 4K60 彩条画面，无需安装驱动。

- 器件：Titanium **TJ180A484S**（C4）
- 工具链：Efinity 2025.2.288.3.8（pass）；固件 GNU ARM 11.3 / ModusToolBox
- FPGA 顶层：`top`（[patten_fx10_ency/src/top.sv](patten_fx10_ency/src/top.sv)）

## 2. 数据链路

```
FPGA top.sv：6+1 色彩条 YUYV（每行 3840 像素，120 × 512-bit beat/行，clk_100m）
   → uvc_top_ency.v（加密网表：例化 slfifo_buffer + y/uv_data_fifo + csi2_hard_mipi_rx，
      内部完成视频缓存与流控）
   → LVDS TX ×18（fx10_gpif_lvds0/1：各 8 数据 + 控制，75MHz pclk，8:1 串化，
      large VOD + medium-high pre-emphasis）
   → FX10 SIP → HBDMA → SRAM → USB3.2 Gen2 Bulk EP1-IN → PC（UVC 枚举）
FX10→FPGA：fx10_spi_*（增强模式命令/状态）+ fx10_gpif_m_*（GPIF 从机握手）
```

## 3. 目录结构

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

## 4. 关键配置

- **peri.xml**：3×PLL（27MHz→LVDS 串化时钟系；50MHz→clk_100m；33.33MHz→ddr_clk
  为残留，DDR 硬核未配置）；BL/TL bank 3.3V，其余 1.8V；`csi2_hard_mipi_rx` IP
  在工程 ip_info 中但 `mipi_info` 为空（未实际使用 MIPI 硬核）；
- **固件 Makefile**：默认 `LVCMOS_EN=0`（LVDS 模式）、`WL_EN=1`（WideLink）、
  `PORT1_EN=0`、`AUDIO_IF_EN=1`（PDM 麦克风 P4.1/P4.2）；
- **UVC 格式**：3840×2160 YUY2（USB3.2 下 4K@~60fps），另支持 720p/VGA；
  每 61440B 视频数据加 32B UVC 头（固件侧加头，`INMD_EN=0`）。

## 5. 编译、烧录与验证

**FPGA 侧**
1. Efinity 打开 `patten_fx10_ency/cam_uvc/cam_uvc.xml`（或直接运行 `efx_run.bat`）；
2. 编译生成 bitstream 烧录到 FPGA。

**FX10 固件侧**
1. 按 `fx10_fw/fx3g2_uvc/Readme.txt`：GNU ARM 11.3 环境下 `make`；
2. 烧录方式 A：OpenOCD —— 连接 KitProg3，运行 `OpenOCD/bin/download.bat <固件>`；
   烧录方式 B：`make BLENABLE=yes` 生成可经 EZ-USB Control Center 烧录的版本。

**验证**
1. USB-C（J4，USB3.2）连接 PC；
2. PC 相机应用（或 AMCap/PotPlayer）应枚举出 UVC 设备并显示 4K60 彩条；
3. FX10 P8.1 UART @921600 可看固件运行日志。

## 6. 集成到客户系统的要点

- **FPGA↔FX10 硬件接口**是集成核心：18 组 LVDS（双通道 8bit 数据 + 控制，
  pclk 75MHz）+ SPI 命令通道 + GPIF 从机握手（oe_n/pktend_n/addr/rd_req_n/
  full/par_flag），引脚与电气参数（VOD/pre-emphasis）都在 `cam_uvc.peri.xml`；
- **`uvc_top_ency.v` 为加密网表**（黑盒）：只能按端口行为集成，无法修改内部
  实现；替换真实视频源时应替换 `top.sv` 的彩条生成部分，保持送入
  `uvc_top_ency` 的 AXIS 接口（512-bit、3840 像素/行时序）不变；
- 固件侧改 UVC 分辨率/帧率需同步改描述符与 GPIF 头文件
  （`cy_gpif_header_lvds.h`），详见固件 Readme.txt；
- 如客户产品不需要音频，`AUDIO_IF_EN=0` 重编译固件即可；
- LVDS 电气参数经 75MHz pclk + 8:1 串化验证，改链路速率需同步 PLL 与 SDC。

## 7. 已知问题与注意事项

- `constrain.sdc` 含若干 `top.sv` 中不存在的时钟（S_AXI_CPU_ACLK/axi_m0_clk/
  mipi_pclk 等，SoC 版本残留），约束无效但不报错；
- `pll_ddr` 与 `csi2_hard_mipi_rx` IP 为残留配置（DDR/MIPI 硬核均未启用）；
- 加密网表注释中泄露原开发路径（`D:\J\...`），无功能影响；
- 本次整理已删除 `patten_fx10_ency/ips/`（Xilinx Vivado IP 树，Efinity 工程
  零引用）与各 IP 目录内嵌的 devkit 参考工程副本，工程不受影响。
