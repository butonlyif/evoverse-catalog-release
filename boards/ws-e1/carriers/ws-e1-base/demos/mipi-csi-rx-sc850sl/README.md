[English](README.en.md) | 中文
# mipi-csi-rx-sc850sl — MIPI CSI-2 摄像头接收（SC850SL，8MP）

> 原目录：`MIPI_RX_sc850/MIPI_RX_sc535/`（外层 sc850 / 内层 sc535 双名混用，
> 本次统一按实际初始化的传感器型号 SC850SL 命名）

## 1. 概述

**MIPI CSI-2 摄像头接收链路**验证工程：FPGA 上电后自动经 I2C 向 SmartSens
摄像头模块下发 200 条寄存器初始化序列，随后 DPHY RX（4 lane / 2.0Gbps per
lane）接收摄像头 CSI-2 数据流，`hard_csi_rx` IP 解包输出像素流。输出侧仅接
内部行/像素计数器，链路状态反映在 CSI RX 状态寄存器、datatype/word_count、
pcnt/lcnt 等内部信号上；**本 demo 无 UART/显示等外部输出，需在 Efinity GUI
手动重新使能 Debugger 后在线观察**（详见 §5）。

> 命名澄清：工程内模块/目录名为 `sc535`（如 `sc535_init/`、`sc535_i2c_init.v`），
> 但顶层实际加载的寄存器表是 `sc535_init/sc850sl_init.mem`（200 条，
> 16bit 地址 + 8bit 数据，I2C 8-bit 写地址 0x60）——**实际初始化的是
> SC850SL**。SC535 与 SC850SL 同厂（SmartSens）、同 0x60 写地址，代码复用导致
> 混名。文档与目录名以 SC850SL 为准。

- 器件：Titanium **TJ180A484S**（C4）
- 工具链：Efinity 2025.2.288.3.8（pass，bitstream 已生成过，passive 配置模式）
- 顶层模块：`top`（文件名 [top_2_5g.sv](top_2_5g.sv)，注释保留 1080p 示例参数）

## 2. 硬件资源占用

| 资源 | 配置 |
| --- | --- |
| **MIPI DPHY RX**（`mipi_dphy_rx_inst2`，MIPI_RX0） | **2000 Mbps/lane，4 lane**，data_width=16，cal_clk 100MHz |
| `hard_csi_rx` IP（efx_csi2_rx_top v5.5.1） | CSI-2 解包/对齐/FIFO，AXI4-Lite 寄存器接口 |
| `i2c_master` IP（efx_i2c_controller v5.0） | sensor 寄存器配置通道（16bit 寄存器地址宽度） |
| `pll_inst1`（PLL_BL1） | 50MHz → clk0 / pixel_clk / mipi_clk |
| `pll_inst2`（PLL_TL0） | 50MHz×2 → cfg_clk 100M / esc_clk 20M / clk_50M / **clk_24m（sensor 参考时钟输出 @GPIOL_46）** |
| GPIO | PLL_50M @GPIOL_26、scl @GPIOL_43、sda @GPIOL_02、trig_o @GPIOL_07、xshutdn @GPIOL_01（tied vcc） |

无软核、无 DDR。板级外设：SmartSens SC850SL MIPI 摄像头模块（J5 CSI-2 连接器）。

## 3. 目录结构

```
mipi-csi-rx-sc850sl/
├── Ti180_mipi.xml / .peri.xml / .sdc   # Efinity 工程（打开这个；工程名沿用 Ti180M484 devkit）
├── top_2_5g.sv                  # ★ 顶层 top：DPHY RX → hard_csi_rx → 计数器 + 调试状态机
├── reset.v / shift_reg.v        # 复位/移位寄存器（shift_reg 未被 top 实例化）
├── sc535_init/                  # sensor I2C 初始化
│   ├── smartsens_init.v         # 上电时序（6ms 复位→2ms→I2C 配置，含 XCLK 逻辑）
│   ├── sc535_i2c_init.v         # FSM：从 ROM 顺序写 200 条寄存器（写地址 0x60）
│   ├── single_port_rom.v
│   └── sc850sl_init.mem         # ★ 实际加载的 SC850SL 寄存器表
├── IP/                          # Efinity IP 目录（注意大写 IP，见"已知问题"）
│   ├── hard_csi_rx/             # CSI-2 RX IP（含 settings.json/_define.vh/_tmpl）
│   └── i2c_master/              # I2C 控制器 IP
├── data_unpack.v / datatype_gen.v / dual_clock_fifo.v / simple_dual_port_ram.v
├── efx_csi2_tx_top.sv / vga_gen.v / pattern_gen.v / pattern_gen2.v / lfsr.v
│        # ↑ 以上 9 个为 devkit 示例残留（TX/VGA/图卡路径），未被本工程引用
└── hard_csi_rx.sv / hard_csi_rx_define.vh   # 与 IP/ 下重复的副本（未引用）
```

## 4. 工作原理

```
上电：smartsens_init（6ms 复位时序）→ sc535_i2c_init FSM 逐条写 ROM
      （sc850sl_init.mem）→ i2c_master → sensor（0x60）
数据：sensor CSI-2 4lane@2G → mipi_dphy_rx_inst2（PPI）→ hard_csi_rx
      → pixel_data/hs/vs → pcnt/lcnt 行/像素计数器
触发：trig_o 产生 30fps 触发脉冲；clk_24m 输出 sensor 参考时钟
调试：r_rx_dbg_fsm_1P 在 mipi_clk 域循环 AXI-Lite 读 hard_csi_rx 寄存器
      0x00–0x28 存入 r_rx_dbg_reg_1P[0:15]（供 GUI Debugger 在线观察）
```

## 5. 运行与验证

本 demo **无 UART、无显示等外部输出**，链路状态只能通过内部信号观察。当前
工程的 Debugger 已关闭，验证需在 Efinity GUI 中手动重新使能 Debugger 向导后：

1. 烧录 bitstream（passive 模式）后接好摄像头模块；
2. 重新使能并打开 Efinity Debugger，观察：
   - `init_done`（I2C 初始化完成）；
   - hard_csi_rx 状态寄存器（RX FSM 状态、**datatype / word_count** 是否与
     sensor 配置一致，如 0x2B/RAW10 或配置的格式）；
   - `pcnt/lcnt` 行/像素计数是否按分辨率滚动。
3. 计数稳定滚动即 CSI-2 链路正常收图。

> 若客户希望做免 Debugger 的自动校验，可仿照 mipi-loopback-test 在输出侧加
> 入比对器并以 LED/GPIO 指示 PASS/FAIL。

## 6. 集成到客户系统的要点

- **换 sensor 型号**：用厂商工具重新生成寄存器表替换 `sc850sl_init.mem`
  （格式：每行 24bit = 16bit 地址 + 8bit 数据），`sc535_i2c_init.v` 的 FSM 与
  I2C 地址参数无需改动（同厂兼容）；换异厂 sensor 需同步改写地址与
  smartsens_init 上电时序；
- **DPHY 速率**：peri.xml 中 `data_rate=2000`（Mbps/lane）按 sensor 输出速率
  调整，SDC 中对应 byte clk（156.25MHz）约束同步改；
- 像素输出接口（`pixel_data/hs/vs` + 计数器）是客户图像处理逻辑的接入点，
  参考未引用的 `data_unpack.v` 等示例可扩展为帧缓存/显示路径；
- `IP/` 目录与工程 include 写法（小写 `ip/`）仅 Windows 大小写不敏感下可用，
  迁移 Linux 构建前需统一大小写。

## 7. 已知问题与注意事项

- 根目录 11 个未引用文件（TX/VGA/pattern 示例与重复 IP 副本）保留作参考，
  不参与综合（不在工程 design_file 列表）；
- `Ti180_mipi.sdc` 含 DPHY **TX** 全套约束但 peri 中无 TX 实例（陈旧约束），
  头注释还是 2022 年 `Ti180F484 / new_csi` 旧信息；
- IP 的 settings.json 内 base_path 指向原开发者机器路径（`D:\J\...`），
  跨机器打开时 Efinity 会提示重定位，忽略即可；
- 本次整理已删除 `IP/` 下内嵌的 Ti180M484/T20F256/Ti60F225 devkit 参考工程
  副本，工程不受影响。
