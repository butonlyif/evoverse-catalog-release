---
ws_manifest_version: 2
kind: jacket
id: cam-4k-1080-60fps-ref
display_name: WS-E1 Base 4K / 1080p@60 Camera Reference
version: 0.9.5
status: active
belongs_to_board: ws-e1
fits_carrier: ws-e1-base
delivery: project-snapshot
project_file: ws-e1-cam-ddr-csi2.xml
---

[English](ws-e1-cam-4K-1080-60fps-ref.en.md) | 中文

# WS-E1 Base 4K / 1080p@60 相机参考设计

`ws-e1-cam-4K-1080-60fps-ref` 是 ws-e1 + ws-e1-base 的相机参考 jacket：IMX415 MIPI 相机采集 → 图像处理 → DDR 缓存，支持 4K 与 1080p@60fps 输出。

## 硬件资源

- MIPI2 RX 相机输入（IMX415）
- 相机 I2C 控制（`cam_1_scl` / `cam_1_sda` / `cam_1_en`）
- DDR3 缓存
- RISC-V SoC（`riscv_soc`）

## 工程文件

- `ws-e1-cam-ddr-csi2.xml` — Efinity 工程
- `rtl/` — RTL 源码（`top_cam_demo.sv` 等）
- `sw/` — 固件（含 `imx415_init`）
