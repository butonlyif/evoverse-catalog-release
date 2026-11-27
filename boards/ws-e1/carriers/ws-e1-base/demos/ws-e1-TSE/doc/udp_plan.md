[English](udp_plan.en.md) | 中文
# ws_e1_tse UDP 增强：接收路径 / ARP+ICMP / 千兆吞吐 实施计划

> 工程基线：ws_e1_tse（TJ180A484S / C4，mytse 7.3 + myriscv），当前板上验证状态：
> UDP 单向发包 13k~23k pps @100B 载荷，无接收路径，ARP/ICMP 未实现。
> **最终应用目标：通过 UDP 传输 1080p RAW10 @30fps 视频流（阶段 3 图案即按此设计）。**
> 本计划分 3 个阶段，每阶段独立可验收，顺序不可颠倒（依赖关系见 §4.0）。

---

## 1. 目标与验收标准

| # | 目标 | 验收标准 |
|---|------|---------|
| G1 | PC→板子接收路径 | 固件能完整收到 PC 发出的任意帧（帧头 UART 打印 / 载荷回读一致） |
| G2 | 软件发送通路 | 固件能把任意组好的帧发到线上（PC 抓包可见） |
| G3 | ARP | `ping 10.0.0.8` 前 PC `arp -a` 能学到板子 MAC（应答 ARP request） |
| G4 | ICMP | `ping 10.0.0.8` 通，丢包 0%（64B 标准载荷，≥100 包） |
| G5 | IP/MAC 软件可配 | UART 命令行修改 IP/MAC 后立即生效（ARP/ICMP/pattern 三处一致），无需重编固件 |
| G6 | 千兆吞吐 | UDP 载荷吞吐 ≥ **900 Mbps**（1500B 帧，PC iperf 风格压测 60s，丢包 0，载荷校验通过） |
| G7 | **1080p RAW10 @30fps 图案流** | RAW10 打包的 1080p 图案视频流持续发送：30.00 帧/秒 ±0.1，PC 端按像素图案公式逐像素校验通过，帧号连续无丢帧，实测载荷带宽 ≈ 622 Mbps 稳定 |

**关于 G6 的物理上限说明**：千兆链路上 UDP 载荷带宽存在协议开销上限，
1000 Mbps 用户载荷物理不可达：

```
线上速率 1 Gbps（含前导8B + IFG12B）
1500B 帧：载荷占比 = (1500-42)/(1500+20) ≈ 94.8% → 上限 ≈ 948 Mbps
64B  帧：载荷占比 = (64-42)/(64+20)   ≈ 26.2% → 上限 ≈ 262 Mbps
```

故 G6 以 1500B 帧 ≥900 Mbps（≥95% 理论上限）为达标线。

> **门控状态 2026-11-06（收官）**：G1–G7 **全部 PASS**。G1/G2/G3/G4 板级验收
> （ARP 动态学习、ICMP 100 包 0% 丢包、UDP echo 4/4）；G5 PASS（UART 运行时可配
> IP/MAC）；G6 PASS（951.2–951.5 Mbps ≥900 达标、载荷零误码；丢包 0.012–0.016%
> 归因 PC 侧 USB 千兆网卡接收栈，用户确认收口——板侧 TX 全硬件直连无丢包机制，
> 严格 0 丢包复测需 PCIe 网卡）；G7 PASS（RAW10 30fps 零丢帧）+ 附加项收官
> （mux S_IDLE 注入实现 ping/ARP 控制面与流共存、4 图案 + viewer 菜单）。
> 详见 project-review/2026-11-06-g3-g4-arp-icmp/ 与 DAYLOG/2026-11.md。
> RX 通路上板首验曾因 yt8531 rgmii-id 配置被覆盖而全丢，已根治（详见
> 2026-11-06 回顾）。

---

## 2. 现状与瓶颈分析

### 2.1 数据通路现状

```
TX: udp_pat_gen ─┐
     mac_pat_gen ┴─[pat_mux]─[tx_mux]─→ mytse TX ─→ RGMII
                 rx2tx loopback ──┘
RX: RGMII ─→ mytse RX ─→ rx_axis ─→ 仅回环 FIFO（CPU 无任何通路）
```

### 2.2 吞吐瓶颈（实测 13k~23k pps vs 千兆线速 ~814k pps@100B）

| 瓶颈 | 位置 | 量级 |
|------|------|------|
| AXI-Stream 时钟 50MHz | ws_e1_tse.v L194-195（官方示例妥协：pat_gen 组合逻辑 125M 时序不收敛） | 上限 400Mbps |
| 校验和串行计算 | udp_pat_gen.v L138-148，UDP_CHKSUM 逐 16bit 循环（100B 载荷约 60 拍）+ IP_CHKSUM 10 拍，每包重复 | 每包 ~70+ 拍 |
| 软件 IPG | pat_gen_ipg=100 拍（可配，但太小会撞 pat_gen 状态机裕量） | 每包 100 拍 |
| 包头 42B 组合译码 | udp_pat_gen.v L432-485 case(pat_cnt[5:0]) 同拍输出 | 时序压力根源 |

### 2.3 功能缺口

- 无接收路径（CPU 与 RX 数据流零通路）
- reg_apb3 地址空间尚有空闲（loc_addr 0x08D~0x0FF，paddr[9]=1 高半区）
- TX mux 仅 2 选 1（pattern / 回环），无"软件帧"入口

---

## 3. 总体架构（目标态）

```
                 ┌──────────── 125MHz 域 ────────────┐
 udp_pat_gen_v2 ─┐                                  │
  (流水线+闭式校验和) │                    mytse TX ←──┘
                  ├─[tx_mux 3选1]──────────────→（pat / 软件帧 / 回环）
 sw_tx_fifo ─────┤                                  │
  (APB 50M 写入)   │                                  │
 rx2tx loopback ─┘                                  │
                                                    │
 APB 50M 域 CPU ←─[rx_pkt_fifo CDC]←── rx_axis(125M) ┘
      │
      ├─ 轮询收帧 → ARP/ICMP 应答（软件协议栈）→ sw_tx_fifo 发送
      └─ net_config_t（IP/MAC 软件可配，UART 命令行）→ 统一供 ARP/ICMP/pattern 寄存器
```

关键决策：
- **数据面与控制面分离**：千兆数据流走硬件直通（pattern 或未来 DMA），ARP/ICMP/配置走
  CPU 软件路径（APB 轮询吞吐 ~MBs 级，对小包控制面足够，永远扛不住千兆数据面——
  这是架构约束，不是优化项）
- **AXI-Stream 提到 125MHz**（阶段 3），rx_axis_clk 用 mytse 输出的 rx_mac_aclk（恢复时钟），
  tx_axis_clk 用 clk_125m（PLL 90° 同源）
- mytse IP 保持 AXIS_DW=8 不重新生成（若阶段 3 后仍有更高需求再评估 32bit，见 §6）

---

## 4. 阶段计划

### 4.0 依赖关系

```
阶段1(收发通路) ──→ 阶段2(ARP/ICMP+可配IP) ──→ 阶段3(千兆吞吐)
     硬件为主              纯软件                  硬件为主
```

阶段 1、3 均动 RTL，但阶段 1 刻意不碰 pat_gen/时钟域（保持 50M 基线），
使阶段 2 有稳定的软件调试平台；阶段 3 的吞吐改造不改变阶段 1 的 CPU 通路结构。

---

### 阶段 1：接收路径 + 软件发送通路（G1、G2）

**改动文件**：`rtl/reg_apb3.v`（扩展）、`rtl/ws_e1_tse.v`（连线）、新增 `rtl/eth_pkt_fifo.v`、
固件 `efx_tse_mac.c/h`（新 API）、`tseDemo.c`

**硬件设计**：

1. 新模块 `eth_pkt_fifo`（复用现有 DaulClkFifo 做 CDC）：
   - RX 侧：`rx_axis(50M 域现状)` → `{tuser,tlast,tdata}` 10bit 宽 CDC FIFO（深度 4K）
   - TX 侧：APB 写入 10bit 字 → CDC FIFO → AXI-Stream 主接口
2. reg_apb3 新增寄存器（loc_addr 0x090 起，paddr = 0x240 起）：

| loc_addr | paddr | 名称 | 读/写 | 位定义 |
|----------|-------|------|-------|--------|
| 0x090 | 0x240 | RX_STATUS | R | [10:0] RX FIFO 字数；[11] 溢出标志（写1清）；[12] 帧进行中 |
| 0x091 | 0x244 | RX_DATA | R | [7:0] 数据；[8] tlast；[9] tuser（读弹出） |
| 0x092 | 0x248 | TX_STATUS | R | [10:0] TX FIFO 剩余空间；[11] 满 |
| 0x093 | 0x24C | TX_DATA | W | [7:0] 数据；[8] tlast（写入压入） |

3. TX mux 2 选 1 → 3 选 1：`axi4_st_mux` 扩展或新增 `axi4_st_mux3`；
   mux 控制位进 reg_apb3（0x081 寄存器扩展 bit[2]），软件帧优先级最高
4. RX FIFO 溢出策略（2026-11-02 按 TSEMAC UG v6.3 修正）：UG 明确
   rx_axis_mac_tready 背压不受支持（帧中拉低会静默损坏帧），故 tready 恒 1；
   溢出保护改为帧粒度准入——SOF 时剩余空间不足 FRAME_GUARD(1536字) 则整帧
   丢弃并置 sticky（toggle 同步到 APB 域），FIFO 中只有完整帧，软件写 1 清标志。
   mac_rx2tx 硬件回环同规则改造（2048 深 FIFO 原阈值背压在背靠背帧下必坏帧）

**固件 API**（`efx_tse_mac.c`）：

```c
int  mac_rx_poll(uint8_t *buf, int maxlen);   // 收一整帧（轮询 RX_STATUS→RX_DATA），返回帧长
int  mac_tx_send(const uint8_t *buf, int len); // 组帧写入 TX_DATA（含 tlast 标记）
void mac_set_loopback(int on);                 // 切 axi4_st_mux_select（收包时必须关闭回环）
```

**验收**：PC 用 scapy/python 发自定义帧 → 固件收帧并经 UART 打印前 64 字节 hex →
与 PC 端发送内容逐字节一致；固件回显帧（mac_tx_send）→ PC 抓包内容一致。

---

### 阶段 2：软件 ARP/ICMP + IP/MAC 软件可配（G3、G4、G5）

**改动文件**：新增固件 `net_config.c/h`、`arp.c/h`、`icmp.c/h`、`eth_frame.c/h`（解析/组帧/校验和）、
`tseDemo.c`（主循环 + UART 命令行）；RTL 不动

**软件设计**：

1. `net_config_t`（单一事实来源，所有协议代码只读它）：

```c
typedef struct {
    uint32_t local_ip;        // 默认 10.0.0.8
    uint32_t netmask;         // 默认 255.255.255.0（预留）
    uint32_t gateway_ip;      // 预留
    uint8_t  local_mac[6];    // 默认 ea:e8:5e:00:60:c8
} net_config_t;
extern volatile net_config_t g_net_cfg;
```

2. UART 命令行：`ip 10.0.0.8` / `mac ea:...` / `show`；写入后同步刷新
   pattern 寄存器（0x224/0x228/0x218）保证三处一致
3. ARP：主循环轮询 → 帧类型 0x0806 → opcode 1（request）且目标 IP==g_net_cfg.local_ip
   → 组 reply（硬件源 MAC 直接取自 mytse，或用 g_net_cfg.local_mac）经 mac_tx_send 发送
4. ICMP：帧类型 0x0800 → proto=1 → type=8（echo request）且 dst_ip 匹配 →
   复制载荷，type 改 0，重算 IP 头校验和（ICMP 校验和 = 载荷原样返回即合法）→ 回复
5. 与 pattern 的共存：ARP/ICMP 应答与 pat_gen 共用 TX mux，发送前短暂切换 mux
   （或 pattern 暂停——见风险 R3）

**验收**：`ping 10.0.0.8 -t` 通且 0 丢包；`arp -a` 显示板子 MAC；
UART `ip 10.0.0.88` 后改 PC 同网段再 ping 新地址通。

---

### 阶段 3：千兆吞吐改造（G6、G7）

**改动文件**：重写 `rtl/udp_pat_gen.v` → `udp_pat_gen_v2.v`（保留旧版便于回退）、
新增 `rtl/raw10_pat_gen.v`（RAW10 视频图案引擎）、
`rtl/ws_e1_tse.v`（时钟域）、`rtl/reg_apb3.v`（控制信号 CDC 握手 + 图案模式选择位）、
**PC 侧 Python 工具链 `doc/pc_tools/`（uv 管理：收包统计 + demosaic 实时显示）**、固件参数适配

**硬件设计要点**：

1. **时钟域迁移**：`tx_axis_clk` → `clk_125m`，`rx_axis_clk` → `rx_mac_aclk`（mytse 恢复时钟输出）。
   pat_gen、tx mux、eth_pkt_fifo 的 RX 写侧全部随迁；APB 控制信号经两级同步 +
   "仅静止期更新"握手（参数写入后 pattern 处于 IDLE 才生效）
2. **闭式校验和消除串行循环**（关键）：载荷为固定递增图案时，UDP 校验和的
   载荷部分是等差 16bit 序列的反码累加和，存在闭式解——包头组包阶段一次算出，
   无需逐字节循环；IP 校验和只依赖包头（本就 10 项）。任意载荷场景留流式接口（§6 待定）
3. **包头流水线**：42B 包头 case 译码拆 3~4 级流水（14B ETH / 12B IP 前 / 8B IP 后+8B UDP），
   tlast 用预计算帧长寄存器比较（消除 16bit 加法进 tlast 组合路径）
4. **IPG 固定为线速最小值**：12 字节时间 = 96 拍（8bit@125M），寄存器仍可调大
5. **时序收敛验证**：pnr 目标 125M 域 0 violation；关键路径预判在包头流水线级间与
   校验和进位链，预留 seed 扫描

**性能预算**（1500B 帧 @125MHz 8bit）：

```
每帧线上时间 = (8前导+1500+12IFG) × 8ns = 12.16 μs → 线速 82.2k pps
UDP 载荷吞吐 = 1458B / 12.16μs ≈ 959 Mbps ≥ 900 ✓
pat_gen 附加开销 = 包头流水 4 拍/帧（可忽略）
```

**验收**：
- 固件 PAT_DLEN=1458（1500B 帧）持续发包，`doc/test_udp_rx.ps1 -Seconds 60` 统计
  ≥900 Mbps 且载荷递增校验通过、丢包 0
- 时序报告 125M 域 0 violation；ARP/ping 在吞吐压测同时不受影响（控制面存活）

#### 3.4 RAW10 1080p@30fps 图案引擎（G7）

在 pat_gen_v2 的递增图案之上，将载荷内容替换为 RAW10 视频流打包引擎（`raw10_pat_gen` 子模块，
与递增图案经寄存器二选一，为将来接真实图像源预留同款接口）：

**RAW10 打包格式**（对齐 MIPI CSI-2 RAW10 惯例）：

```
4 像素 = 5 字节：P1[9:0] P2[9:0] P3[9:0] P4[9:0]
  → 字节流：P1[9:2] P1[1:0]+P2[7:2] P2[1:0]+P3[7:2] P3[1:0]+P4[7:2] P4[1:0]
每行 1920 px = 480 组 × 5B = 2400 B；每帧 1080 行 = 2,592,000 B ≈ 2.47 MB
```

**UDP 承载与分帧**：

```
每包载荷 = 8B 元数据头 + 1450B RAW10 数据（1500B 帧）
元数据：帧号 32bit + 帧内字节偏移 32bit（接收端重建/校验/统计丢帧的依据）
每帧包数 = ceil(2592000/1450) = 1788 包
包速率   = 1788 × 30 ≈ 53.6k pps（< 线速 82.2k pps @1500B，占比 65%）
```

**带宽与帧率核算**：

```
RAW10 像素带宽   = 1920×1080×30×10bit = 622.08 Mbps
每帧 UDP 载荷    = 2,592,000B 数据 + 1788×8B 元数据 = 2,606,304B
30fps 载荷带宽   = 2,606,304 × 8 × 30 ≈ 625.5 Mbps < 千兆上限 948 Mbps（占比 66%）✓
每帧发送时间     = 2,606,304 × 8ns×8bit/线速 → 按线速 959 Mbps 仅需 ≈ 21.7ms
帧周期 33.33ms，占空比 65%；剩余 ≈11.6ms 为帧间空隙（帧计数对齐 30.00fps 的自然余量）
```

**图案定义**（确定性、PC 可逐像素校验）：

```
pixel(row, col) = (row×1920 + col) mod 1024   // 10bit 锯齿波，帧内与帧号无关
帧号随 UDP 元数据递增；PC 校验脚本按同公式比对每个像素
```

**验收（G7）**：连续发送 ≥300 帧（10s）：PC 端脚本校验——帧号连续（丢帧数=0）、
每包元数据偏移严格递增、抽样全像素比对通过、实测帧率 30.00±0.1 fps、
载荷带宽 622±5 Mbps；同时 ping 持续不断（控制面共存）。

**与未来真实图像源的接口**：`raw10_pat_gen` 对外表现为"AXI-Stream 载荷数据源"，
图案模式内部生成；真实相机数据到达后以同接口替换（valid/ready 背压一致），
仅 UDP 元数据的帧号来源改为外部 SOF。

#### 3.5 PC 侧验证工具链：Python（uv 管理）+ demosaic 实时显示

仅靠逐像素脚本比对难以直观判断图像对齐/花屏，PC 侧需完整 RAW→RGB 显示管线。
PC 已安装 uv，以 uv 管理依赖与运行。

**目录结构**（新增）：

```
doc/pc_tools/
├── pyproject.toml        # uv 项目：deps = numpy, opencv-python
├── raw10_viewer.py       # 主工具：收包→解包→重组→demosaic→实时显示
└── test_raw10_rx.py      # 无头校验：纯统计（帧率/丢帧/逐像素比对），复用同一解包库
```

**处理管线**：

```
UDP 收包(53.6k pps) → 剥 8B 元数据(帧号/偏移) → RAW10 解包(5B→4px)
  → 按帧号+偏移重组帧缓冲(1920×1080 uint16)
  → 白平衡(CFA 通道增益，demosaic 之前) → demosaic(cv2 Bayer)
  → 实时显示(OSD: fps / 帧号 / 丢帧数 / 带宽) + 按键截图
```

**关键实现点**：

1. **白平衡（demosaic 之前的 RAW 域通道增益）**：Bayer 中 G 通道占一半像素，
   R/B 不补偿则画面偏绿。按 CFA 位置对 R/Gr/Gb/B 四通道分别乘增益：
   `raw[cfa_mask_R] = clip(raw * gain_R, 0, 1023)`（numpy 掩码乘法，uint16 不溢出）
   - 增益参数：`--wb R,Gr,Gb,B`（如 `--wb 2.1,1.0,1.0,1.6`），默认全 1.0
   - 灰度测试图案阶段白平衡退化为直通（增益 1.0 不改变画面），
     真实相机接入后配合灰世界/色卡标定出固定增益，预览不偏绿
2. **demosaic 用 OpenCV**：`cv2.cvtColor(raw, cv2.COLOR_BayerXX2RGB)`
   - 测试图案是灰度锯齿波（无 Bayer 色彩），任意 Bayer 模式显示均可验证
     管线与像素对齐——错位/丢包表现为撕裂/花屏，人眼立即可见
   - 真实相机接入后按传感器 CFA 排列选定 BGGB/RGGB 等模式（做成命令行参数）
3. **重组策略**：`dict[帧号] → numpy 预分配缓冲 + 已收偏移 bitmap`；
   只显示完整帧，残帧计数上报（丢帧定位到包偏移）
4. **性能预算**：收包 53.6k pps + 解包/重组 2.5MB/帧×30fps——numpy 向量化解包
   （`np.frombuffer` + 位运算重组，单帧 <5ms）；OpenCV 显示 30fps 1080p 无压力，
   收包线程与显示线程分离（queue 解耦，防 GUI 阻塞导致内核丢 UDP 包）
5. **socket 缓冲**：`SO_RCVBUF` 调大（≥8MB）防突发丢包；绑定 10.0.0.2:10005

**运行方式**：

```
cd doc\pc_tools
uv sync                                   # 首次安装依赖
uv run raw10_viewer.py --bind 10.0.0.2 --port 10005 --cfa BGGB --wb 2.1,1.0,1.0,1.6
uv run test_raw10_rx.py --seconds 10      # 无头统计校验（对应 doc/test_udp_rx.ps1 的 RAW10 版）
```

**验收（补充 G7）**：raw10_viewer 实时显示连续 10 分钟：画面为稳定斜纹图案无花屏
无撕裂、OSD 帧率 30.00±0.1、丢帧 0；截图与图案公式比对通过；
test_raw10_rx.py 统计结果与 viewer OSD 一致。

**对真实相机的意义**：此工具链即未来 PC 端调试上位机的雏形——换数据源后
仅打包格式不变，增加图像参数（曝光/增益/白平衡）与 ISP 调节面板即可。

---

## 5. 风险与对策

| # | 风险 | 影响 | 对策 |
|---|------|------|------|
| R1 | pat_gen_v2 125M 时序不收敛（历史前科：v1 就是因此被降到 50M） | 阶段 3 延期 | 流水线设计+提前单模块综合摸底；保留 50M 旧版一键回退（mux 仍指向旧版） |
| R2 | CDC 错误（125M↔50M 控制参数、跨域 FIFO） | 偶发配置失效/数据损坏 | FIFO 用现成 DaulClkFifo（已含 Gray 同步）；控制信号双同步 + 静止期握手；ASYNC_REG 约束 |
| R3 | ARP 应答与 pattern 抢 TX mux，应答被 pattern 淹没 | ping 丢包 | 应答期间固件先暂停 pattern（写 0x082 寄存器）再切 mux 发送，完成后恢复；应答延迟可接受 |
| R4 | 收包路径关闭回环后，既有回环测试功能受影响 | 功能回归 | mux 3 选 1 保留回环通路，由寄存器显式切换，旧用法不变 |
| R5 | mytse 7.3 与固件 CSR 偏移不匹配（升级遗留） | 阶段 1 起全部受阻 | 阶段 1 开工前先做 CSR 冒烟（读写 TX_ENA/RX_ENA 位核对） |
| R6 | 8bit AXIS@125M 对 CPU APB 读取速率要求（1500B 帧 = 375 次字读 @50M APB） | 软件收帧赶不上线速 | 控制面只收 ARP/ICMP 小包（<100B），数据面不过 CPU——架构上已规避 |
| R7 | RAW10 流 53.6k pps 长稳运行时 RX 回环 FIFO 误开或 pattern 状态机卡帧 | 帧率不稳/丢帧 | 帧计数看门狗（>2 帧周期无 tlast 自动复位引擎）；帧间空隙期做状态自检；PC 帧号连续性监控兜底 |

---

## 6. 待定决策（实施中确认）

| # | 事项 | 当前倾向 |
|---|------|---------|
| D1 | 任意载荷（非图案）的流式 UDP 校验和 | RAW10 图案是确定性数据，每包内容可预知——校验和仍走预计算，无需流式；真正任意数据（真实相机）接入时再做流式校验和，接口已在 pat_gen_v2 预留 |
| D2 | mytse AXIS_DW 8→32bit 重新生成 | 不做（8bit@125M 已够 1Gbps）；32bit 是 DMA 化时再评估 |
| D3 | IP 配置掉电保持（SPI Flash 配置区） | 第一版 RAM 变量 + UART 命令；Flash 持久化按需后补 |
| D4 | MAC 源地址用 mytse 硬件自带还是 g_net_cfg | 用 g_net_cfg（与可配目标一致），mytse MAC 过滤寄存器同步编程 |
