[English](cam-csi2-integration-plan.en.md) | 中文
# ws_e1_tse 摄像头接入：MIPI CSI-2 RX → RAW10 UDP 流 实施计划

> 工程基线：ws_e1_tse（TJ180A484S / mytse + myriscv），G1–G7 全部 PASS，
> G7 = RAW10 1080p30 图案流 622 Mbps 零丢帧（合成源 udp_pat_gen_v2）。
> **本计划目标：用真实 IMX415 摄像头替换合成源，复用其余全链。**
> 参考工程：`D:\Projs\ws-e1-cam-4K-1080-60fps-ref`（v4.11，双链板测出图，
> 其中 **cam1 = 1080p60 路摄像头前端**是本计划的移植蓝本）。
> 权威现状文档：参考工程 `doc/readme_4K_1K.md` + `doc/milestone-v4.11-cam1-replay.md`。

---

## 1. 目标与验收标准（沿用 G 门控）

| 门 | 目标 | 验收标准（PC + UART 双侧证据） |
|---|------|---------|
| G8 | CSI 链路建立 | IMX415 出流后：my_csi2_rx 探针有效 DT 拍计数步进、SOT/ESC 错误计数恒 0、lock 状态 UART 打印 |
| G9 | 静图捕获 | raw_2_axi4st 窗口输出单帧 dump，PC 端与相机实际画面（棋盘/彩纸等已知场景）比对一致 |
| G10 | 实时流 | `test_raw10_rx` 全指标：帧号连续、30.00fps ±0.1、载荷 622±5 Mbps、像素比对 PASS（与 G7 同判据，源换真实相机） |
| G11 | 流+控制共存 | kill/软件注入/t-v-n 模式切换/0-3 图案菜单在相机源下全部回归 PASS |

**证据纪律**：编译 PASS ≠ 板级 PASS；sim PASS ≠ 硅 PASS。每步改动追加
`DAYLOG/2026-11.md`；里程碑走 `project-review/<case>/review.md` 带 SHA-256。

---

## 2. 关键决策记录（2026-11-06，用户已确认）

### D1 时钟：新 PLL 双通道 100M + 200M（50M/125M 复用方案已被 P0 证据否决）

P0 查证（docs/efinity 知识库 + `D:\Efinity\2026.1` 官方文档 + 参考工程实况）：

| IP 时钟 | 参考工程 | 本计划 | 官方依据 |
|---|---|---|---|
| `clk`（IP 核时钟） | 100M | **csi_clk_100m（新 PLL 通道）** | 2.5G CSI-2 RX UG：**IP Core Clock 40–100MHz**。50M 虽在 IP 范围内，但 DPHY `CFG_CLK` 官方要求 **80–120MHz**（Titanium MIPI RX D-PHY doc，用于 time counter 与 EQ 校准），参考工程两钟同网（sys_clk_100m）——维持同网拓扑，取 100M |
| `clk_byte_HS` | DPHY 恢复字钟 111.375M | 同左（硬核输出） | 1782Mbps÷16bit，无选择余地 |
| `clk_pixel`（像素输出域） | 200M | **csi_clk_200m（新 PLL 通道）** | UG 下限 178.2 M拍/s（= 4lane×1782Mbps÷40bit）。125M 仅 70%，虽 FIFO 数学可兜（见下），但违反文档下限 30%，弃用 |

50M/125M 复用否决记录（存档，防重提）：
- 50M 替 IP `clk`：CFG_CLK 80–120MHz 官方约束直接否决；
- 125M 替 `clk_pixel`：每行突发 2.727µs，涌入 712.8Mpx/s、125M 域排走 500Mpx/s
  → 每行积压 581px（< PIXEL_FIFO_DEPTH 1024，消隐 4.68µs 排空仅 1.16µs）
  ——数学成立但违反 UG 下限，属"违反即结果错误"类风险，不接受。

**新 PLL 方案**：Ti180 PLL 资源 TL0/TL1/TL2/TR0/BL0/BL1（参考工程实况证明
TL1/TL2/BL0/BL1 本封装可用）；TSE 已占 TL0（4 通道满：clk/clk_125m/clk_125m_90deg/
clk_25m 反馈）+ TR0（rgmii）。**新 PLL 挂空闲槽（如 TL1）**，
`REFCLK_SOURCE=CORE`（官方属性表支持 EXTERNAL/CORE/DYNAMIC）取内部现有时钟
倍频出 100M + 200M 双通道；CORE 模式可行性以 import dry-run + 编译实证，
退路为换槽或外部参考引脚。不触碰 pll_0/pll_rgmii 任何配置（零风险面）。
配套 SDC：100M/200M 各补 `create_clock` + `set_clock_groups -asynchronous`。

**IP 变体注意**：必须用 **2.5G 变体（`efx_2p5g_csi2_rx`，生成模块名同为
`efx_csi2_rx_top`）**——标准版 `efx_csi2_rx` 数据率上限 1500Mbps < 1782Mbps。
参考工程 settings.json 的 vlnv name=`efx_csi2_rx_top` 即 2.5G 变体，参数表已
与官方 UG 逐项核对（4 lane / FIFO 1024 ≥ HACT×bpp/64=300 / GENERIC /
Pack_40 / tINIT=400000 / ASYNC=2 / AREGISTER=8 / PIXEL_SIDEBAND）。

### D2 丢帧策略：传感器侧 30fps（不在 RTL 丢帧）

用户最初设想"UDP 侧隔帧发送"（RTL 丢奇帧）。否决数学：

- 60fps 全发 = 2.62MB/帧 × 8 × 60 ≈ **1258 Mbps > 951 Mbps 线速上限** → 丢帧必须 ✓
- 但 RTL 隔帧的缓冲代价：偶帧像素 16.67ms 内到齐、发包摊进 33.3ms 槽，积压峰值
  按 G7 622Mbps 节奏 ≈ **1.30MB ≈ 10.4Mb ≈ 95% Ti180 全部 BRAM（不可行）**；
  按 951Mbps 全速突进 ≈ 0.61MB ≈ 4.9Mb（勉强可行但吃近半 BRAM 且贴线速顶）
- **传感器侧 30fps**：IMX415 geo 表 VMAX 2250→**4500**（HMAX=550 不动；
  rom 中本有 VMAX 6576 的 30fps 先例），4500×550/74.25MHz = 33.33ms = 30fps。
  每帧 33.3ms 到齐 = 发送槽，逐行流水打包，CDC FIFO 仅需 ~2 行（KB 级）
- 前提已确认：**裸 IMX415，I2C 可配模式**（用户 2026-11-06 确认）
- 收益：与 G7 已验收包络完全重合，PC 侧 raw10.py / test_raw10_rx 零改动，
  帧号天然连续

**寄存器改动**（imx415_rom.sv geo1080 行，MODE_4K=0 分支）：

```
VMAX: 0x30_24_CA / 0x30_25_08 (=2250)  →  0x30_24_11 / 0x30_25_94 (=4500)
HMAX: 0x30_28_26 / 0x30_29_02 (=550)   →  不变
```

（P1 须对 IMX415 datasheet 模式表确认 VMAX 4500 + 2/2 binning + 1782Mbps 组合合法。）

---

## 3. 目标架构

```
IMX415 (1080p30, 1782Mbps 4-lane, I2C RTL 初始化, 自带晶振无需 XCLK)
  → DPHY RX 硬核 MIPI_RX2（= 参考工程 1080 路 cam1 同一接口，ISF bootstrap）
  → my_csi2_rx 2.5G 变体（clk=csi_clk_100m / clk_byte_HS=恢复字钟 / clk_pixel=csi_clk_200m）
  → raw_2_axi4st（200M 域，窗口 1944×1096 → 1920×1080，LEAD=6/TRAIL=18/SKIP=11）
  → async FIFO（40bit，~2 行深）
  → udp_pat_gen_v2 RAW10 模式新外源像素口（125M 域打包，帧号由打包侧顺序重编）
  → TSE MAC → RGMII → PHY → UDP 622Mbps（G7 包络原样）

控制面：0x208 空闲 bit 加 cam_src_en（运行时切相机/图案源，UDP 10006 命令）；
cam_i2c_init 在 csi_clk_200m 域例化（SYS_FREQ=200_000_000 沿用参考工程
板级验证过的常数；I2C 50kHz，pad GPIOL_46=scl / GPIOL_01=sda /
cam_en=GPIOL_07——全部照搬参考工程 cam_1_* 映射）
```

**移植清单**（自参考工程）：

| 文件 | 改动 |
|---|---|
| `ip/my_csi2_rx/` | 从参考工程原样拷贝（**2.5G 变体**，`CLOCK_FREQ_MHZ=100` 不变，cfg 已与官方 UG 逐项核对） |
| `rtl/raw_2_axi4st.sv` | 原样移植（几何参数 = 1080p 默认，已匹配） |
| `rtl/cam_i2c_init.sv` + `rtl/imx415_rom.sv` | MODE=0；geo 行 VMAX 改 4500（§D2）；例化于 csi_clk_200m 域（SYS_FREQ=200M 沿用板级验证常数） |
| `rtl/i2c_master.sv` | cam_i2c_init 内嵌依赖（参考工程 P1 修复版，含 scl_timeout/CMD_RESET 修复），原样移植 |
| `rtl/reset_ctrl.sv` | 参考工程版（多域同步），TSE 现有复位链比较后决定并入方式 |
| DPHY RX 硬核 + 新 PLL | ISF bootstrap（import_gpio 应用，见 P1-1）；peri.xml 由工具产出，禁止手写 |

**不移植**：frame_writer/frame_reader/DDR 乒乓/demosaic/wb/rgb2yuv/CSI-2 TX/
disp_timing（TSE 走 UDP，无显示域）；my_csi2_tx/top_cam 显示链全部不需要。

---

## 4. 分阶段计划

### P0 侦察（**已完成 2026-11-06**，结论如下）

1. **摄像头接口 = 参考工程 1080 路原样（cam1 资源组，用户指定）**：
   DPHY RX2（peri.xml `dphy_rx2` / MIPI_RX2，data_rate=1782、4 lane、
   data_width=16、cal_clk_freq=100、byte_clkout=gclk）+ cam1 引脚组
   （cam_1_en=GPIOL_07、cam_1_scl=GPIOL_46、cam_1_sda=GPIOL_01）。
   不参考 sc850sl demo（用户明确：摄像头不一样）。同板旁证（仅作辅助）：
   uart GPIOR_70/72、50M 晶振 GPIOL_26 与本工程一致。
2. **相机控制**：单 cam_en（GPIOL_07）上电使能，参考工程 cam_i2c_init
   PWR_OFF(300ms)→SETTLE(12ms)→…→DISCHARGE(500ms) 时序已含电源管理；
   IMX415 模组自带晶振（参考工程无 XCLK 输出）。
   教训（v4.11c 实锤）：cam_en pad 驱动漏接 → 传感器不上电 → I2C 全 NACK，
   集成时 pad 连接必须专项核对。
3. **bank 电压：无需 1.2V 声明**。参考工程（RX0+RX2 双摄板级验证）iobank
   声明仅 1.8/3.3V，TJ180 DPHY RX 走专用 pad 不占 GPIO bank。本工程现有
   bank 声明照旧。
4. **官方约束查证**：CFG_CLK 80–120MHz；2.5G CSI-2 RX IP 核钟 40–100MHz、
   FIFO ≥ HACT×bpp/64；标准版 IP 上限 1500Mbps 必须用 2.5G 变体（细节见 D1）。
5. **PLL 空闲槽确认**：参考工程实况占用 TL0/TL1/TL2/BL0/BL1，本工程占 TL0/TR0
   → 空闲槽充足（新 PLL 方案见 D1）。
6. **IMX415 VMAX 4500 合法性**：rom 同源历史含 VMAX 6576（30fps 旧档），
   4500 介于已验证的 2250（60fps）与 6576 之间；4500×550/74.25M = 33.33ms
   = 30.00fps。G8 板级 pcnt/lcnt 实测帧率收口。
7. **bootstrap 路径**：本工程 `unified_flow="false"` 且无 ISF 消费链（参考工程
   同构）→ ISF 经 `cli/import_gpio.bat` 消费：`--dry-run` 自检 → 去掉 dry-run
   实际应用到 peri.xml → ISF 中 `create_*` 注释（标注启用条件）+ peri.xml 一起
   入库（§15 契约的本工程适配版）。

出口判据：上表 5 项均有书面结论 ✅（记入本节 + DAYLOG）。

### P1 = G8 CSI 链路建立

1. ISF bootstrap（`cli/import_gpio.bat`，dry-run → 应用）：MIPI_RX2 硬核
   （照搬参考工程 `dphy_rx2`：data_rate=1782 / 4 lane / data_width=16 /
   cal_clk_freq=100 / byte_clkout=gclk，CFG_CLK=csi_clk_100m）+
   cam_en/GPIOL_07、scl/GPIOL_46、sda/GPIOL_01 GPIO + 新 PLL（空闲槽，
   CORE 参考，出 100M+200M）；create 一次性应用后注释；引导编译 + 重放编译
   两连 PASS；SDC 补 100M/200M `create_clock` 与异步 clock_groups
2. **`ip/my_csi2_rx/` 整目录从参考工程原样拷贝**（已是 2.5G 变体
   `efx_csi2_rx_top`，板级验证过，无需重新生成；"2.5G 变体"含义：IP Manager
   中 CSI-2 RX 分标准版（≤1500Mbps）与 2.5G 等级（≤2500Mbps），两变体生成
   的模块名相同，IMX415 1782Mbps 必须用 2.5G 等级，参考工程现成就是）；
   raw_2_axi4st + reset_ctrl 同步移植
3. cam_i2c_init + imx415_rom 移植（MODE=0，geo 行 VMAX→4500 即 0x30_24_11 /
   0x30_25_94）；cam_i2c_init 例化于 csi_clk_200m 域（SYS_FREQ=200M 板级验证
   常数）；参考工程自带 `sim/tb_cam_i2c_init.sv`（C1–C4）回归
4. 探针：DT 匹配拍计数、SOT/ESC 错误计数、lock 状态挂 CSR（0x092 探针借用或
   新组），UART 心跳打印
5. **G8 判据**：传感器出流后有效拍计数 ≥ 行速率预期（1944px×1091行×30fps），
   错误计数恒 0

### P2 = G9 静图捕获

1. raw_2_axi4st 窗口输出接单帧捕获通路（方案 P2 定：借 CPU RX 窗口慢速回传或
   专用 RAM dump）
2. PC 端 dump 比对：相机对准已知图案（棋盘/彩条/屏幕），逐像素核对
3. **G9 判据**：单帧内容与实物一致，无行列错位/位错（RAW10 解包正确性直证）

### P3 = G10 实时流

1. async FIFO（200M→125M）+ udp_pat_gen_v2 外源像素口（sof 帧界对齐启动打包；
   FIFO underflow 帧中止重同步，不发残帧）；帧号打包侧顺序重编
2. 0x208 cam_src_en 位 + UDP 10006 命令字 + 固件 ApplyMode 扩展
3. `test_raw10_rx` 全指标回归（帧号连续 / 30fps±0.1 / 622±5 / 像素比对）
4. **G10 判据**：与 G7 同判据全 PASS，源 = 真实相机

### P4 = G11 共存回归

1. kill 停车 / 软件注入三态 / t-v-n 模式切换 / 图案菜单在相机源下回归
2. ARP/ICMP/echo 控制面与视频流共存复测（mux S_IDLE 注入路径）
3. **G11 判据**：G1–G7 全部回归项在相机源在跑的前提下复测 PASS

---

## 5. 风险与既定教训（继承 PROJECT_SUMMARY §6）

| # | 风险 | 对策 |
|---|---|---|
| 1 | 同步器/握手 FF 被综合消解（DC_FIFO 死路根因） | 所有 CDC/握手寄存器加 `syn_keep`；tb_sw_path 回归 + 板级验证 |
| 2 | bins 时序陷阱：map 读旧固件 = 假编译 | 本计划 I2C 走 RTL init（cam_i2c_init），不新增固件依赖；若固件改动仍须 make→binGen→拷 bins 先于 map |
| 3 | MIPI 引脚/资源归属（已定：照搬参考工程 1080 路 cam1 资源组 RX2+GPIOL_07/46/01） | 全部照搬参考工程 `dphy_rx2` peri 配置与 cam_1_* 引脚，不自创映射；cam_en pad 连接专项核对（v4.11c 教训） |
| 4 | peri.xml 是 PT 产物 | 只经 ISF/工具生成，禁止手写；引导后 create_* 注释，重放两连 PASS |
| 5 | IMX415 配置顺序敏感（"SONY magic" 块、TCLKZERO hi 0x401F=0x01） | 逐字节照搬参考工程 rom；只改 geo 行 VMAX 两个值 |
| 6 | 参考工程遗留：冷启动/温复位外部芯片偶发锁卡（FPGA 内部正常） | G8/G10 判读前先整板上下电排除；固件 watchdog 列为后续增强，不阻塞本计划 |
| 7 | RX 无背压（TSEMAC UG）；相机源同样不可暂停 | 相机侧只进 async FIFO + 打包 FSM 帧界对齐，无背压依赖 |
| 8 | PC 侧：USB 3.0 网卡、双网卡 bind 10.0.0.3、ARP 老化 | 沿用 G7 网测约定（project_memory 板级网测约定） |

---

## 6. 参考文档

| 文档 | 内容 |
|---|---|
| 参考工程 `doc/readme_4K_1K.md` | 模块/时钟/数据路径速查（cam1 1080 链） |
| 参考工程 `doc/milestone-v4.11-cam1-replay.md` | 双链集成存档（工具链陷阱表 §5） |
| 参考工程 `doc/cam-i2c-rtl-init-plan.md` | RTL I2C 初始化设计 |
| 本工程 `doc/PROJECT_SUMMARY.md` | TSE 全工程快照（摄像头对接点 §5.2） |
| 本工程 `doc/udp_plan.md` | G1–G7 原始验收记录 |
| `docs/efinity/` | CSI-2 RX / DPHY UG（时钟约束权威，P0 查证） |
