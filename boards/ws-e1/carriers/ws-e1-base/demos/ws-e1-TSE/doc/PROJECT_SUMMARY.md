[English](PROJECT_SUMMARY.en.md) | 中文
# ws-e1-TSE 工程技术总结（面向摄像头功能扩展）

> 更新：2026-11-06（bit `4eba25c1…`，G1–G7 收官 + 运行时模式切换 + sw-TX 死路修复）
> 本文是加摄像头（MIPI CSI-2 → RAW10 视频流替换）前的全工程快照说明。
> 配套阅读：`doc/efinity/`（工具链权威知识）、`DAYLOG/2026-11.md`（全部调试证据）、
> `project-review/2026-11-06-g3-g4-arp-icmp/review.md`（证据链与 digest）。

---

## 1. 工程定位与当前能力

**Efinix Titanium TJ180A484S + SapphireSoC RISC-V + TSE MAC** 的千兆 UDP 系统。
当前"视频源"是 **RTL 合成的 RAW10 传感器仿真流**（udp_pat_gen_v2 的 RAW10 模式）；
加摄像头 = 用真实 MIPI CSI-2 RX 通路替换/旁路这个合成源，其余链路全部复用。

已验证能力（全部板级实测）：

| 能力 | 指标 |
|---|---|
| G6 线速流 | 1500B 递增 UDP，**951 Mbps**，PC 侧 badpay=0 |
| G7 视频流 | RAW10 1080p**30fps**，**622 Mbps**，丢帧 0，像素比对 PASS |
| 网络服务 | ICMP/ARP 应答、UDP echo(10005)、1Hz tick、UART 配 IP/MAC |
| 运行时切换 | UDP 10006 单字节命令 t/v/n/s/0-3，即时生效免重编译 |
| 软件停车 | `pat_gen_kill`（0x208 bit3）包边界干净停车，inc 无限流唯一停车手段 |

## 2. 时钟与复位

| 时钟 | 频率 | 域 | 用途 |
|---|---|---|---|
| `clk` (clk_50m) | 50 MHz | APB / CPU / FIFO 写侧 | CSR、eth_pkt_fifo 写口、RISC-V |
| `clk_125m` | 125 MHz | RGMII / tx_axis / FIFO 读侧 | MAC TX、eth_pkt_fifo 读口 |
| rx_axis | 125 MHz | MAC RX 域 | MAC→fifo RX tap |

- PLL 在 **ISF 中创建**（`design.create_block`，不在 RTL 例化）；RTL 只声明 `pll_*_locked` 端口
- 复位：`mac_reset = ~pll_0_locked & ~pll_rgmii_locked`；`mac_rstn = ~(mac_reset||proto_reset)`
- SDC：每时钟 `create_clock` + `set_clock_groups -asynchronous`；CDC 同步链单独 `set_false_path`
- CDC 同步器全部带 `(* ASYNC_REG = "TRUE" *)`；**同步器/握手寄存器必须加 `(* syn_keep = "true" *)`**（§6 教训 1）

## 3. 地址映射（APB3 CSR，rtl/reg_apb3.v）

| 地址 | 读/写 | 功能 |
|---|---|---|
| `0x204` | W | TX mux：0=图案发生器 → MAC；0x10=CPU(eth_pkt_fifo) → MAC |
| `0x208` | R/W | bit0 `udp_pat_gen_en` 启动（脉冲装载参数）；bit1 `raw10_mode`；bit2 `mac_pat_gen_en`；**bit3 `pat_gen_kill`**；bit[5:4] `pat_mode`（RAW10 显示图案 0-3） |
| `0x092` | R | `{pat_dbg[8:0], eth_tx_full, eth_tx_free_cnt[12:0]}`（free 空=4095；dbg[5:3]=pat_gen FSM state，dbg[6]=infinite_en） |
| `0x093` | W | `eth_tx_wr_en`：TX FIFO 数据口，9bit `{tlast,tdata}`，帧末字节写 `|0x100` |
| `0x090` | R | RX FIFO 状态（rx_word_cnt / overflow sticky，写 1 清） |
| `0x091` | R | RX FIFO ShowAhead 读口 `{tuser,tlast,tdata}`，读脉冲弹出 |
| `0x248` | R | MAC `ETH_TX_STATUS`：bit13 tx_full + bit[12:0] free（与 0x092 不同源） |
| `0x24C` | R/W | W=TX FIFO 数据（同 0x093 通路）；R=pat_dbg 探针借用 |
| `0x68/0x6C` | R | MAC aFramesTransmittedOK / aFramesReceivedOK（32bit 计数） |

固件侧关键函数（`embedded_sw/.../tseDemo/src/main.c`）：
`PatGen()`（参数化三分支 inc/旧MAC/RAW10，置参数+脉冲启动）、
`StreamStop()`（kill→轮询 FSM 回 S_IDLE→撤 en→mux→CPU）、
`MacTxSend()`（逐字节写 0x24C，末字节 |0x100；忙等 free<len）、
`ApplyMode()`（主循环上下文切态：停流→切 mux→重启）、
`AppRun()`（RX 分发 + 模式分支 + 控制命令 PatCtrlCmd + 注入三态）。

## 4. 数据通路（TX 三选一，0x204 控制）

```
                      ┌─[inc 线速流 / RAW10 视频 / 显示图案]─┐
 udp_pat_gen_v2 ──────┤                                      │
 (AXI-Stream 8bit)    └────────────┐                          ▼
                                   ├── axi4_st_mux3 ──► TSE MAC ──► RGMII ──► PHY
 eth_pkt_fifo(TX DC_FIFO 9bit) ────┘   (0x204=0x10 时)   (125MHz)    (YT8531)
 (CPU 写 0x24C/0x093)      ▲
                           │ apb_wr(0x093) —— 2026-11-06 syn_keep 修复后硅级健康
 RISC-V 固件 (50MHz APB) ──┘
```

RX 侧：MAC `rx_axis_mac` → `eth_pkt_fifo` RX tap（`rx_tready` **恒 1**，UG 禁背压）
→ CPU APB 读窗口（0x091 ShowAhead + 0x090 水位）。帧粒度准入（SOF 判水位 ≥1536 字），
溢出整帧丢弃 + sticky。

**sw 帧注入三态**（AppRun 内，按当前模式选路）：
1. netsvc：直接 `MacTxSend`（FIFO 空闲，无竞争）
2. RAW10 流：S_IDLE 帧间窗口注入（v3 方案，帧间静默期足够）
3. inc 线速流：**kill 包边界停车注入**（IPG=96ns 无空窗，必须停车再发，≤12.2µs）

## 5. RAW10 视频通路（摄像头功能的核心对接点）

### 5.1 板侧（rtl/udp_pat_gen_v2.v，RAW10 模式）

- `raw10_mode=1` 时按 FRAME_PERIOD 节拍发帧；每帧 **1788 包**，包 payload 1466B，
  末包 900B；包头带 **meta 头（帧号 + 包序 idx）**——格式常量以 `doc/pc_tools/raw10.py`
  （`BYTES_PER_FRAME`/`PKTS_PER_FRAME`/`PAYLOAD_LAST`/`H`/`W`）为准，板侧 RTL 与 PC 侧
  必须同步修改
- 显示图案 0-3（彩条/横灰/纵灰/棋盘）由 `pat_mode[5:4]` 即时切换（RMW 保留 bit3）
- FSM：RAW10 帧末包走 S_IDLE；inc 无限流 S_DATA→S_IPG→S_HDR 环（**永不回 S_IDLE**，
  停车全靠 kill 位）；kill 语义 = 当前包 tlast 边界干净回 S_IDLE + pat_en 熄火 +
  start_pulse 自动清除
- RGGB 相位已在图案中建模（彩条按 Bayer 排列排布）——`raw10_viewer.py` 实测确定
  `cv2.COLOR_BayerRG2RGB` 为正确 demosaic 常量（BGGB 会黄青/红蓝互换）

### 5.2 PC 侧（doc/pc_tools/）

| 文件 | 角色 |
|---|---|
| `raw10.py` | 协议核心：`FrameReassembler.feed(pkt)`→(fn, idx, done, frame)；`frame_to_image`；越界/重同步保护 |
| `tse_console.py` | 一体化控制台（按钮控制 + Tk/PPM 实时视频 + OSD 状态栏） |
| `raw10_viewer.py` | 纯视频（OpenCV 窗口）；WB/demosaic：`apply_wb` → `cv2.cvtColor(demosaic)` → 10bit→8bit |
| `test_raw10_rx.py` | 无头验收：帧号连续性/30fps±0.1/带宽 622±5/像素比对 |
| `mode_ctrl.py` / `mode_gui.py` | 纯控制（t/v/n/s/0-3） |

**摄像头替换点**：CSI-2 RX 解出来的 RAW10 像素流，最终汇聚成
"`FrameReassembler` 可重组的 UDP 帧（帧号+idx meta，1788 包/帧）"即可——
最省路径是**替换 udp_pat_gen_v2 的 RAW10 像素源**（把图案生成器换成 CSI 像素 FIFO），
包化/UDP 封装/PC 显示全链复用；`raw10.py` 若相机分辨率/位深不同需同步改常量。

## 6. 硅级病灶与既定规则（前车之鉴，摄像头开发必读）

1. **DC_FIFO 复位握手 FF 被综合消解**（2026-11-06 修复，死路根因）：
   `DaulClkFifo.v` 的 `WrClkRstGen[1]/RdClkRstGen[1]`（跨域握手 `[1] <= &对方Gen`）
   被 map 消解为无驱动 wire，下游寄存器 SR 为**低有效**直连 → 硅上恒复位
   （TX FIFO 永空、wrcnt 恒 0）。修复 = 握手 reg 加 `(* syn_keep = "true" *)`。
   **规则：所有同步器/握手/跨域采样寄存器加 syn_keep**；RTL 健康不代表硅健康，
   关键改动必须 `tb_sw_path` 回归 + 板级验证。
2. **free/full 13 位算术综合敏感**（2026-11-02）：`4096-wrcnt` 形式硅上出错，
   已改 `13'd4095 - fill` 并满时强制 0（`eth_pkt_fifo.v`）。类似边界算术勿随意改写。
3. **bins 时序陷阱**：map 阶段读 `ip/myriscv/*.bin`——改固件后必须先完成
   make→binGen→拷 bins，再启动编译，否则嵌旧固件（板上行为不变的"假编译"）。
4. **RX 背压禁用**：TSEMAC `rx_axis_mac_tready` 拉低会静默损坏帧（UG 明文），
   恒 1 + 帧粒度准入。摄像头高带宽下 RX tap 若接 CPU 通路同样无背压，注意 FIFO 深度。
5. **`ws_e1_tse.peri.xml` 是工程源文件**（PT 产物，禁止手写/删除）；ISF 重放安全
   （只有 set_property/assign_*，`create_*` 仅一次性 bootstrap 且已注释）。
   **MIPI CSI RX 硬 IP 同样在 ISF 创建**，注意：
   - MIPI bank 必须 **1.2V**，MIPI 与 LVDS **不能共 bank**
   - HSIO bank 内 GPIO/LVDS/MIPI 之间须留至少一对未分配 IO 隔离
   - 任何 ISF 修改后必须过 `cli/import_gpio.bat --dry-run` 自检
6. **Efinity dbg 步骤复用 `work_dbg\`**（debug_top.v 等）——迁移/共享工程必须带上，
   否则编译在 dbg 报 `No such file`。
7. **PC 侧环境**：USB 网卡必须 USB 3.0（2.0 上限 ~342 Mbps 且丢小帧）；双网卡同网段
   时控制工具显式 bind 10.0.0.3；ARP 表老化后 UDP 控制面锁死（netsvc 死路时唯一
   逃生 = 重上电/JTAG，平时 `s` 可逃生）。

## 7. 验收方法论（G1–G7 门控，摄像头沿用）

每个新能力拆成可独立验收的门，**PC+UART 双侧证据**，PASS 才进下一门：

| 门 | 内容 | PC 工具 | 板侧证据 |
|---|---|---|---|
| G1 | UDP echo 10005 | test_udp_echo | UART [stat] |
| G2 | tick / netsvc 循环 | 1Hz 收包 | [stat] tx 1Hz 步进 |
| G3 | ARP 动态学习 | ping / arp -a | `ARP: reply sent` |
| G4 | ICMP 0% 丢包 | ping -S | `ICMP: echo reply sent` |
| G5 | UART 配置 IP/MAC | 串口命令 | banner |
| G6 | 千兆压测 | test_udp_thr --seconds 60 | dbg 探针 |
| G7 | RAW10 视频 | test_raw10_rx + viewer | PPS 计数 |

摄像头建议门控草案：G8 CSI 链路建立（lock/ICLK 校准/UART 打印）→ G9 静图捕获
（单帧 RAM dump 与相机图案比对）→ G10 实时流（raw10.py 全指标，用真实源替换
合成源后 G7 全项重跑）→ G11 流+控制共存（kill/注入路径回归）。

**证据纪律**：编译 PASS ≠ 板级 PASS；sim PASS ≠ 硅 PASS（两次死路都是 RTL PASS
硅 FAIL）；每次仓库改动追加 `DAYLOG/YYYY-MM.md`；里程碑更新
`project-review/<case>/review.md` 并带 SHA-256 证据。

## 8. 开发流程速查

```powershell
# 固件（RISC-V）
cd embedded_sw\sapphire\software\standalone\tseDemo
$env:PATH = "D:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin;" + $env:PATH
make clean; make
# bins（陷阱 §6.3：必须先于下次 map 完成）
$env:EFINITY_HOME = "D:\Efinity\2026.1"
# FPGA 全编译（~3 分钟）
D:\Efinity\2026.1\bin\efx_run.bat ws_e1_tse.xml -f compile
# 烧写
D:\Efinity\2026.1\pgm\bin\ftdi_pgm.bat -m jtag -b "Generic Board Profile Using FT4232H" outflow\ws_e1_tse.bit
# 仿真（Questa 2024.2，判据见 sim/tb_sw_path.v 头注释）
cd sim   # 编译清单 + -suppress 3009 见 USER_MANUAL §5
# OpenOCD 探针（cwd 必须是 embedded_sw\sapphire）
..\..\sw\diag_txtx.cfg   # halt 读 TXSTAT/MUX/CFG 后 resume（resume 回 boot 态）
# PC 一体化控制台
cd doc\pc_tools; uv run tse_console.py
```

工程共享副本：`D:\Projs\ws-e1-ge-test`（含 README/USER_MANUAL，拷贝时**必须带
work_dbg/**）。板子当前状态：RAW10 视频流持续发送。
