[English](README.en.md) | 中文
# mipi-csi-tx-4k-pattern — 4K YUV 图案 MIPI CSI-2 发送

> 原目录：`TJ180J484_CSI_4k_2370Ma/Ti180J484_CSI_4k_2370Ma/`（TJ/Ti 大小写混用已纠正；
> 目录名中的 2370Ma 指早期接 SC2370M 传感器的版本，当前工程已改为纯图案发送）

## 1. 概述

片内生成 **3840×2160 YUV422 彩条图案**，经 `mipi_csi_tx_2p5g` IP 打包为
CSI-2 流（datatype 0x1E，4 lane），由 **MIPI DPHY TX 硬核（MIPI_TX2）**发出，
用于验证 CSI-2 发送链路。接收端可为另一块板、MIPI 采集卡或协议分析仪。

> 工程演变说明：目录中保留了大量早期"SC2370M 传感器采集 + iPhone7P 屏显示"
> 版本的遗留文件（`rtl/mipi_csi/`、`rtl/panel/`、`rtl/vga/` 等），**当前顶层
> 不再实例化这些路径**，实际链路以 `rtl/top.sv` 为准。历史文件保留作参考。

- 器件：Titanium **TJ180A484S**（timing model **I3**）
- 工具链：Efinity 2026.1.132.1.15（pass，三者中最新；SDC 由旧版 2022.2 生成）
- 顶层模块：`top`（[rtl/top.sv](rtl/top.sv)，默认参数 4K，注释保留 1080p 备选）

## 2. 硬件资源占用

| 资源 | 配置 |
| --- | --- |
| **MIPI DPHY TX**（`mipi_dphy_tx_inst1`，MIPI_TX2） | 4 lane CSI-2 发送（无 RX 硬核） |
| `mipi_csi_tx_2p5g` IP | CSI-2 打包，AXI-Lite 状态接口 |
| `pll_inst2` | 27MHz → i_fb_clk、i_sysclk_div2（像素时钟域） |
| `mipi_tx_pll` | 50MHz → mipi_rx_cfg_clk、dphy_byte_clk（250MHz）、dbg_clk、CLK_5M |
| `pll_inst3` | → i_fb_50m、esc_clk、mipi_ref_clk |
| GPIO | 仅 3 个时钟输入：clk_27m、clk_50m、mipi2_refclk |
| Debugger | 已关闭（原自动插桩 ILA "la0" depth 2048，需 GUI 手动使能） |

无 DDR、无软核、无 MIPI RX。

## 3. 目录结构

```
mipi-csi-tx-4k-pattern/
├── project_new/                  # Efinity 工程目录（top.xml / top.peri.xml / constraints.sdc）
│   ├── debug_top.v               # Debugger 插桩顶层（已禁用，未参与编译）
│   └── ip/
│       ├── mipi_csi_tx_2p5g/     # ★ CSI-2 TX IP（被 top 实例化）
│       ├── Hard_csi_rx/          # 在 ip_info 中，顶层未实例化（残留）
│       └── async_fifo_16/        # 在 ip_info 中，顶层未实例化（残留）
├── source/
│   └── efx_dsi_tx_top.sv         # 在工程文件列表，顶层未实例化（DSI 版残留）
└── rtl/
    ├── top.sv                    # ★ 顶层：video_pattern_gen → mipi_csi_tx_2p5g → DPHY TX
    ├── reset_ctrl.v              # fb/esc/byte 时钟域复位同步
    ├── video_pattern_gen.v       # 3840×2160 YUV422 图案发生器
    ├── true_dual_port_ram.v / vid_info_det_v6.v
    ├── led_ctrl/led_ctrl.v       # 4 LED（check_pass/frame_stable 无驱动，见已知问题）
    ├── common/rst_n_piple.v
    ├── vga/                      # 【历史遗留】视频处理流水线（raw_to_rgb、line_buffer、
    │                             #   vga_gen、rgb_gain、data_pack/unpack…+ line_buffer_tb）
    ├── panel/                    # 【历史遗留】iPhone7P 屏初始化表 + panel_config.v
    │                             #   + DSI porch cal.xlsx（porch 计算表）
    ├── color_bar_v2.0/           # 【历史遗留】彩条发生器（含独立 md/svg 文档与 tb）
    └── mipi_csi/                 # 【历史遗留】传感器采集版顶层 + I2C sensor 配置
```

## 4. 工作原理

```
video_pattern_gen（3840×2160 YUV422，i_sysclk_div2 像素时钟域）
    ↓ w_vs/w_hs/w_valid + yuv_data[63:0]
mipi_csi_tx_2p5g IP（CSI-2 打包，datatype=0x1E YUV422 8bit，4 lane）
    ↓ PPI（TxDataHS0..7 / TxRequestHS / TxReadyHS / ULPS / ESC）
mipi_dphy_tx_inst1（MIPI_TX2）→ MIPI 连接器发出 4K CSI-2 流
```

顶层另有 AXI-Lite 只读 FSM 轮询 TX IP 状态（`r_tx_axi_araddr_1P`），
`reset_ctrl` 负责多时钟域复位同步。

## 5. 编译、烧录与验证

1. Efinity 打开 `project_new/top.xml` 编译烧录；
2. 验证方式（任选）：
   - MIPI 采集卡 / 另一块板（可参考 mipi-csi-rx-sc850sl demo 的 RX 工程）接收
     图案并检查 4K 分辨率与色彩条内容；
   - MIPI 协议分析仪检查 lane 速率、datatype 0x1E、帧时序；
   - Efinity Debugger ILA（la0）观察 w_r/w_g/w_b/w_vs/w_hs/w_valid 波形
     （需在 GUI 手动重新使能 Debugger）。

## 6. 集成到客户系统的要点

- **替换图案为真实数据源**：保持 `video_pattern_gen` 输出接口
  （w_vs/w_hs/w_valid + yuv_data[63:0]，i_sysclk_div2 域）不变，客户模块按同
  一接口送入 `mipi_csi_tx_2p5g` 即可；
- 分辨率/帧率：`top.sv` 顶层参数（HACT/VACT，默认 3840/2160，注释含 1080p）；
  修改后需同步 SDC 中像素时钟与 DPHY byte clk 约束；
- DPHY TX 配置（lane 数、速率）在 `top.peri.xml` 的 `mipi_dphy_tx_inst1`；
- `constraints.sdc` 由 Interface Designer 2022.2.317 生成，头部标注
  Ti180L484/C4 preliminary 与实际器件（TJ180A484S/I3）不符——约束值已按现板
  验证通过，迁移时建议在新工程中重新生成 SDC；
- 历史 RX/panel 路径若需启用（做 sensor→屏透传），参考 `rtl/mipi_csi/` 与
  `rtl/panel/`，并需在 peri 中补 MIPI RX 硬核与 GPIO。

## 7. 已知问题与注意事项

- `check_pass`/`frame_stable` 信号在 top.sv 中**只有声明无驱动**（接收链删除
  后残留），`led_ctrl` 的 LED 实际不反映测试结果，仅 en={00} 心跳可控；
- `w_mipi_rx_vs/hs/de/data` 4 个信号声明未使用；`led/irq/lcd_power_en/o_lcd_rstn`
  未在端口声明（隐式 wire，悬空）；
- `mipi_csi_top.sv`、`efx_dsi_tx_top.sv`、`vid_info_det_v6.v`、`Hard_csi_rx`、
  `async_fifo_16` 在工程列表中但未被顶层实例化（综合剪除，死代码保留作参考）；
- `rtl/vga/`、`rtl/panel/`、`rtl/color_bar_v2.0/`、`rtl/mipi_csi/cam_i2c_ctrl/`
  等整棵子树未入工程，属历史版本遗留；
- 本次整理已删除：`ip/dsi_tx/`、`ip/soft_csi/`（均不在工程 ip_info 中）、
  各 IP 内嵌 devkit 参考工程、`~$DSI porch cal.xlsx`（Excel 锁残留）、
  `modelsim.ini_new`（重复仿真配置）；`DSI porch cal.xlsx` 与
  `modelsim.ini/sim.do/wave.do` 保留。
