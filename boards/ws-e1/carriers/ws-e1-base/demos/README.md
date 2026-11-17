[English](README.en.md) | 中文
# WS-E1 / WS-E1-Base 板卡 Demo 工程

适用于 **WS-E1 核心板 + WS-E1-Base 底板**（Titanium TJ180A484S）的验证 demo
集合。每个 demo 一个顶层目录，目录名即功能，入口文档统一为目录内
`README.md`。

## Demo 一览

| Demo | 功能一句话 | 硬核 / 软核 | 软核程序 | 验证方式 | timing model |
| --- | --- | --- | --- | --- | --- |
| [ddr-memtest](ddr-memtest/) | LPDDR4x 双 AXI 端口写读比对 | DDR 硬核 ×2 端口、2×PLL | 无 | 6×LED 结果指示 | C4 |
| [si5338-clock-config](si5338-clock-config/) | I2C 配置 Si5338 时钟发生器并回测 | DDR、3×PLL、LVDS RX、Sapphire | i2cCfgSi5338 | UART 日志 + LED 闪烁 + 示波器 | C4 |
| [ethernet-tse-udp-test](ethernet-tse-udp-test/) | 千兆 TSE MAC，UDP 测试帧发生/环回 | TSE MAC（RGMII+MDIO）、PLL、Sapphire | tseDemo | Wireshark 抓包 / 环回 | C4 |
| [imu-bmi088-readout](imu-bmi088-readout/) | RISC-V 读 BMI088 六轴 IMU | Sapphire + 2×PLL | i2cMasterDemo | UART 打印六轴数据 | C4 |
| [mipi-csi-rx-sc850sl](mipi-csi-rx-sc850sl/) | SC850SL 摄像头 CSI-2 接收（4lane@2G） | DPHY RX、CSI2 RX IP、2×PLL | 无（硬件 I2C 初始化） | 无外部输出，需 GUI 使能 Debugger 观察 RX 状态/计数 | C4 |
| [sdcard-powercycle-retention](sdcard-powercycle-retention/) | SD 卡写入→掉电→读回校验 | DDR、2×PLL、Sapphire、SD Host | TJ180A484S_SDHOST | UART 输入 W/R，输出 PASS | **I3** |
| [usb-uvc-4k60-pattern](usb-uvc-4k60-pattern/) | 4K60 彩条经 FX10 枚举为 UVC 摄像头 | 18×LVDS TX、3×PLL | FX10 固件（UVC+UAC） | PC 相机应用看 4K60 彩条 | C4 |
| [mipi-csi-tx-4k-pattern](mipi-csi-tx-4k-pattern/) | 片内 4K YUV 图案经 CSI-2 TX 发出 | DPHY TX、CSI2 TX IP、3×PLL | 无 | MIPI 采集卡 / 协议分析仪 | **I3** |
| [mipi-loopback-test](mipi-loopback-test/) | CSI-2 TX→回环→RX 片内自环比对 | **DPHY TX+RX 双硬核**、2×PLL | 无 | LED PASS/FAIL | C4 |

## 通用信息

- **器件**：全部为 Efinix Titanium TJ180A484S（484 封装）；timing model 以
  各 demo 为准（多数 C4，两个为 I3）。
- **工具链**：Efinity 2025.1 ~ 2026.1（各 demo 版本不同，见各自 README）；
  每个工程 `last_run_state=pass`，bitstream 均成功生成过。
- **工程打开方式**：进入各 demo 目录，按 README 指引打开对应 `*.xml`
  工程文件编译。
- **Debugger**：所有 demo 的 Debugger 已关闭（`auto_instantiation=off`），
  CLI 编译不再依赖 `debug_top.v`；需在线观察内部信号时，在 Efinity GUI 中
  手动重新使能 Debugger 向导。
- **板卡资料**：底板文档见上级目录
  [`../ws-e1-base.md`](../ws-e1-base.md)（引脚、bank 供电、接插件清单）。

## 按应用场景选型

| 需求 | 推荐起点 |
| --- | --- |
| 引入 LPDDR4x / DDR 硬核 bring-up | ddr-memtest（双口）→ si5338-clock-config / sdcard-powercycle-retention（SoC+DDR 单口） |
| 以太网 / RGMII / TSE MAC | ethernet-tse-udp-test |
| I2C 传感器接入（软核方案） | imu-bmi088-readout |
| MIPI 摄像头接收 | mipi-csi-rx-sc850sl（sensor 方案）/ 硬核链路先用 mipi-loopback-test 验证 |
| MIPI 图像/视频发送 | mipi-csi-tx-4k-pattern |
| USB 摄像头（UVC）产品形态 | usb-uvc-4k60-pattern |
| SD 卡存储 / 掉电可靠性 | sdcard-powercycle-retention |
| 可编程时钟（Si5338） | si5338-clock-config |

## 目录整理说明（2026-08）

本次整理完成：

1. **扁平化**：去除每个 demo 的冗余外层包装目录（原为 `X/X/` 双层嵌套，
   SI5338 原为三层）；
2. **重命名**：目录名统一 kebab-case 并按功能命名，与 SDK 生态命名一致；
3. **瘦身**：删除各 IP 目录内嵌的整套 devkit 参考工程副本
   （T120/Ti60/Ti180 等其它器件模板）、Xilinx Vivado 无关 IP 树、未引用的
   dsi_tx/soft_csi IP、重复软件树、临时残留文件（`~$*.xlsx`、
   `*.pre_import.xml`、`debug_TEMPLATE.*`、`modelsim.ini_new`）；
4. **文档**：为每个 demo 编写详细 README（概述、资源、结构、原理、编译
   烧录、验证、集成要点、已知问题）。

原名 → 新名对照：

| 原目录 | 新目录 |
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

> 工程内部目录（`bsp/`、`project_new/`、`rtl/`、`ip/` 等）保持原样，
> Efinity 工程文件使用相对路径引用，整体搬移不影响打开编译。

## 恢复与全量编译验证（2026-10）

1. **恢复被裁剪的工程文件**（2026-08 瘦身误删，已从原始工程补齐）：
   `imu-bmi088-readout/ip/soc/soc.v`（Sapphire SoC 生成封装 RTL）、
   `usb-uvc-4k60-pattern/patten_fx10_ency/cam_uvc/cam_uvc.xml` 与
   `cam_uvc.peri.xml`、`src/uvc_top_ency.v`（加密网表）；
2. **DDR 密度对齐**：ddr-memtest / si5338 / sdcard 三个工程的
   `*.peri.xml` 中 DDR 硬核密度 4G→2G，与板载 LPDDR4x 颗粒一致；
3. **全量编译验证**：9 个 demo 全部在各自工程目录下执行
   `efx_run --flow compile`，map / interface / pnr / pgm 四段全部 PASS；
4. 验证所用中间产物（`outflow/`、`work_syn/`、`work_pnr/`、`work_dbg/`）
   已全部清理，物料库内不含 bitstream。
