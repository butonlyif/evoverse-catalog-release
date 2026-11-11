[English](README.en.md) | 中文

# ws-e1-cam-ddr-csi2-demo Jacket

WS-E1（TJ180A484S）摄像头 MIPI CSI-2 演示 jacket：IMX415 传感器 → CSI-2 RX → 图像处理 → DDR 存储帧，RISC-V SoC（Sapphire）负责 APB 寄存器控制与 IMX415 初始化（I2C）。

## 结构

| 路径 | 内容 |
|------|------|
| `ws-e1-cam-ddr-csi2.xml` | Efinity 工程（unified flow） |
| `ws-e1-cam-ddr-csi2.peri.xml` | PT 产出的接口数据库（GPIO/bank/电压） |
| `ws-e1-cam-ddr-csi2.sdc` | 时序约束 |
| `package_settings.xml` | 封装设置 |
| `rtl/` | `top_cam_demo.sv` 顶层 + 摄像头通路（`camera_path`、`apb_cam_ctrl`、`demosaic`、`raw_2_axi4st`、`rgb2yuv_axis`、`shape_video_axis` 等） |
| `ip/` | 硬核 IP 源：`my_csi2_rx`、`my_csi2_tx`、`riscv_soc`（含 IP Manager 工程） |
| `sw/` | `bsp/`（Sapphire BSP）+ `top_demo/`（RISC-V 裸机 demo，`imx415_init.c` 传感器初始化） |

## 构建 FPGA

```
efx_run ws-e1-cam-ddr-csi2.xml --flow compile
```

map → interface(PT) → pnr → pgm 四段，产物在 `outflow/`（构建产物不入库）。

## 构建软件

`sw/top_demo` 为 Eclipse 工程，导入 Efinity SDK / RISC-V GCC 工具链后 `make` 生成 ELF，经 JTAG（OpenOCD，见 `sw/bsp/openocd`）下载运行。

## 历史说明

2026-10-08：移除工程 XML 中的 Efinity Debug 段（la0 逻辑分析仪）与 `debug_profile.wizard.json`，恢复标准编译流程。
