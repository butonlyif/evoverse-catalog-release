[English](README.en.md) | 中文
# mipi-loopback-test — MIPI CSI-2 片内自环链路测试（TX→回环→RX 校验）

> 原目录：`TJ180MIPI_loopback/Ti180MIPI/`（TJ/Ti 大小写混用已纠正）

## 1. 概述

在同一颗 FPGA 内构建 **MIPI CSI-2 发送→接收自环链路**：片内生成测试图
（默认 **4K60 RAW8**）→ `hard_csi_tx` 打包 → **DPHY TX 硬核** →
MIPI 引脚 →（板级走线/外接短线回环）→ MIPI 引脚 → **DPHY RX 硬核** →
`hard_csi_rx` 解包 → 片内逐像素比对，**LED 直接指示 PASS/FAIL**。

这是 9 个 demo 中**唯一同时使用 DPHY TX + RX 双硬核**的工程，无需任何外部
设备即可完成 MIPI 硬核与 IP 的链路级验证，适合作为 MIPI 硬核 bring-up 与
TX/RX IP 配置对照的基准工程。

- 器件：Titanium **TJ180A484S**（C4）
- 工具链：Efinity 2025.2.288.4.15（pass，bitstream 已生成过）
- 顶层模块：`Top`（[Top.v](Top.v)，1447 行，**GBK 编码中文注释**，文件头含
  2019-01~2020-02 修改史，自 Xilinx VIO/ILA 风格工程移植而来）

## 2. 硬件资源占用

| 资源 | 配置 |
| --- | --- |
| **DPHY TX**（`mipi_dphy_tx_inst1`，MIPI_TX0） | 2.0Gbps/lane，2 lane（MIPI_Parameter.v 参数） |
| **DPHY RX**（`mipi_dphy_rx_inst2`） | 对应接收配置 |
| `hard_csi_tx` / `hard_csi_rx` IP | CSI-2 打包/解包（AXI-Lite 状态接口） |
| `pll_inst1` | 以 pll_inst2_CLKOUT2 50MHz 为源 → clk0、**pixel_clk 200MHz**、mipi_clk 100MHz |
| `pll_inst2` | → **cfg_clk 100MHz、esc_clk 20MHz**、CLKOUT2 50MHz、clk_25m |
| GPIO | CLK_50M（板载 50MHz）、MIPI_REF_CLK、4×LED、1 按键（start_transfer_n） |
| Debugger | 已关闭（原 VIO MipiTx/MipiRx 两组 + ILA，需 GUI 手动使能） |

无软核、无 DDR。

## 3. 目录结构

```
mipi-loopback-test/
├── Ti180MIPI.xml / .peri.xml      # Efinity 工程（打开这个）
├── Ti180_mipi_io.isf              # Interface Designer IO 约束文件
├── Top.v                          # ★ 顶层 Top：图案生成→TX→环回→RX→比对统计
├── top.sdc                        # 时序约束（pixel_clk 200M / mipi 100M / esc 20M…）
├── debug_profile.json / debug_top.v   # Debugger VIO/ILA 配置与插桩顶层（已禁用，未参与编译）
├── ip/
│   ├── hard_csi_tx/               # CSI-2 TX IP（settings.json/_define/_tmpl）
│   └── hard_csi_rx/               # CSI-2 RX IP
└── source/
    ├── reset.v                    # 复位同步（被 Top.v 实例化 ×3）
    ├── MIPI_Parameter.v           # ★ 全局参数（被 include：PHY 速率/像素时钟等）
    ├── MIPI_RAW/                  # 2019-2020 旧测试逻辑（在工程列表但未被实例化）
    │   ├── MIPITest.v / MIPITxProcess.v / MipiRxProcess.v / MipiPixelData.v / PRBS9.v
    │   └── MIPI_Parameter.v       # ⚠ 与上级目录重复的副本
    └── efx_csi2_tx.sv / efx_csi2_rx.sv / efx_csi_tx_define.vh / efx_ram_10k.v / mipi.sdc
                                   # 旧版 IP 封装残留（未入工程）
```

## 4. 工作原理

```
Top.v 片内测试图生成（MipiTx_DATA，RAW8，分辨率/帧率由参数固定）
  → hard_csi_tx（CSI-2 打包，AXI-Lite 只读状态）
  → mipi_dphy_tx_inst1 → MIPI 引脚 →（板级回环/外接短线）→ RX 引脚
  → mipi_dphy_rx_inst2 → hard_csi_rx
  → MipiRx_DATA/VALID/word_count/datatype → Top.v 比对统计
      （RxErrCnt、每秒 TxDataRate 吞吐、MiPiRxRight/MipiRxError 判决）
```

- 默认参数（原 VIO 初值记录于 debug_profile.json）：`ConfigTxVertPixelNumber=2160`、
  `ConfigTxHoriPixelNumber=3840`、`ConfigTxFrameRate=60` —— 4K60 RAW8；
- `start_transfer_n` 按键启动一次传输；lanes/VC/分辨率/复位等参数由
  Top.v/MIPI_Parameter.v 固定（在线修改需在 GUI 重新使能 Debugger）。

## 5. 运行与验证

| LED | 含义 |
| --- | --- |
| led[0] | 心跳（count_led[21] 分频翻转） |
| **led[1]** | **FAIL**（r_fail，RX 比对出错） |
| **led[2]** | **PASS**（r_pass，RX 校验通过） |
| led[3] | 传输活动指示（flash_cnt[12]） |

1. 烧录 bitstream；按 `start_transfer_n` 按键启动；
2. **led[2] 亮且 led[1] 灭 = 自环链路 PASS**；
3. 需要细节时，可在 GUI 重新使能 Efinity Debugger：VIO 调整参数（如降分辨率
   排查）、ILA 抓 TX/RX 数据与比对结果、观察 TxDataRate 吞吐统计。

## 6. 集成到客户系统的要点

- **TX 侧复用**（做图像发送）：取 Top.v 中"图案生成→hard_csi_tx→DPHY TX"
  段落 + `ip/hard_csi_tx` 配置；AXI-Lite 只读状态轮询 FSM 可直接搬；
- **RX 侧复用**（做摄像头接收）：取"DPHY RX→hard_csi_rx→比对/统计"段落，
  把比对器替换为客户处理逻辑；word_count/datatype 检查是链路调试关键信号；
- 双硬核 peri 配置（TX0+RX 同时存在）参考 `Ti180MIPI.peri.xml`，包括
  cal_clk、esc_clk 分配；SDC 中 TX 与 RX 双向全套 IO delay 约束是时序收敛
  的关键参考；
- 全局速率参数集中在 `source/MIPI_Parameter.v`（PHY 2.0G、pixel 200MHz、
  esc 20MHz），改速率三处同步：参数文件、peri 的 data_rate、SDC 时钟周期；
- **注意编码**：Top.v、MIPI_Parameter.v 为 GBK 中文注释，UTF-8 编辑器中乱码；
  修改文件时保持原编码或统一转 UTF-8（需全工程一致）。

## 7. 已知问题与注意事项

- `source/MIPI_Parameter.v` 与 `source/MIPI_RAW/MIPI_Parameter.v` 内容重复，
  实际 include 的是 `source/MIPI_RAW/` 下版本（以工程文件列表为准）；
- 工程列表中的 5 个 MIPI_RAW 模块（MIPITest/MIPITxProcess/MipiRxProcess/
  MipiPixelData/PRBS9）在 Top.v 中**未被实例化**（逻辑已内联），属死代码；
- 综合代码中保留 `#TCo_C` 仿真延迟语句（可综合但属仿真风格遗留）；
- 本次整理已删除 `Ti180MIPI.peri.pre_import.xml`（导入前备份）与
  `debug_TEMPLATE.v/.vhd`（模板残留）。
