[English](arbiter.en.md) | 中文

# AXI 双主共享 DDR 端口仲裁器设计规格（axi_wr_arb / axi_rd_arb）

| 项 | 值 |
|---|---|
| 版本 | **v1.2**（v1.1 吸收 kimi3/ds 两评审；v1.2 修复用户复核发现的 P0×1/P1×3/P2×4，见 §12） |
| 日期 | 2026-10-23 |
| 关联 | [cam1-ddr-replay-plan.md](cam1-ddr-replay-plan.md) §2、[ddr_interface.md](ddr_interface.md)、[ddr-dram-controller-tj-ug-v3.0.md](ddr-dram-controller-tj-ug-v3.0.md)（TJ UG，DDR 控制器手册）、评审件 [kimi3-arb-feedback.md](kimi3-arb-feedback.md) / [ds-arb-feedback.md](ds-arb-feedback.md) |
| 状态 | **已冻结**（v1.2，2026-10-23 用户确认）；实施验证计划见 [arbiter-impl-plan.md](arbiter-impl-plan.md)；Q1~Q4 已关闭（§10） |

---

## 1. 背景与决策

原方案采用 Efinity AXI Interconnect IP 做 DDR 双口共享。经评估放弃，改自研：

1. IP 内部实现不透明，512b + 2-to-1 属非默认配置，**厂商只对默认参数做过验证**（UG v1.8 L427/L468）；
2. 参数受限：向导 ADDR 只给 32/64 档；Slave/Master 方向默认值反着（1/2），易错；
3. 需求极窄：**恒定 2→1、AXI4、512b、单目的地、无解码**——本质是"带 RR 仲裁的事务级 2 选 1 mux"，自研语义完全可控，诊断内建。

决策记录：2026-10-23 用户拍板弃用 IP、自研；仲裁策略定 **Round Robin**（弃固定优先级）。

**与 DDR 硬核内置仲裁器的关系（决策记录，kimi3-B4）**：硬核自带双接口 RR 仲裁（[ddr-dram-controller-tj-ug-v3.0.md](ddr-dram-controller-tj-ug-v3.0.md) 的 Features/Arbiter 章；"TJ UG" 即该 DDR 控制器手册的名称，非型号笔误）。本拓扑把写流量聚到 target0、读流量聚到 target1——**每个 target 恒被一个外部仲裁器独占，硬核内置仲裁退化为直通**。收益与代价：

1. 读写并行性保留（写 target0 / 读 target1，硬核内部读写队列独立）；
2. 每 target 单"虚拟 master"，行为可预测：行为模型侧 `ARB_*` 参数（`ARB_GRANT_INTERVAL` 等）及 ddr_ctrl_model 测试 spec 中双接口仲裁实测项**对最终系统不适用**，仅需对本仲裁器自测（连带收敛模型验证范围）；
3. 代价：单 target 无多 master 合并能力，单口峰值即硬顶——本设计占用率 <30%（§5.4），无影响。

## 2. 适用范围与实例化

| 实例 | 模块 | 时钟 | 上游（S 口） | 下游（M 口） |
|---|---|---|---|---|
| 写侧 | `axi_wr_arb`（rtl/axi_wr_arb.v） | sys_clk_200m | S1=cam0_fw，S0=cam1_fw（各 AW/W/B） | DDR target0 写口 |
| 读侧 | `axi_rd_arb`（rtl/axi_rd_arb.v） | pixel_clk 148.5M | S1=cam0_rd，S0=cam1_rd 经 `axi_rd_cdc`（各 AR/R） | DDR target1 读口 |

- **时钟域声明（ds-P1-2；v1.2 复核 P2-4 实证化表述）**：cam0_fw `aclk = sys_clk_200m`——RTL 实证：top_cam_demo.sv `u_fw` 例化 `.aclk(sys_clk_200m)`（注释"与 raw 源同钟，v2 零 CDC"）。cam1_fw 为阶段 5 新增实例（现状 u_cam_1 无 frame_writer），设计承诺接同一 `sys_clk_200m`（u_cam_1 已具备该时钟输入，camera_path 同构）——**写侧零 CDC**；读侧 cam1_rd 在 37.125M 域，经 axi_rd_cdc 接入。
- S 口编号即 bit 编号：S1=cam0（bit1），S0=cam1（bit0）。两模块结构同源、通道不同，各自独立小模块。
- `axi_rd_cdc`（AR/R 双异步 FIFO，37.125M→148.5M）另行详设，本规格只定契约（§4.3）。

## 3. 总体架构

```
s1(AW/W/B) ──┐            ┌────────────────────────────┐
             ├────────────┤ RR1 grant 锁存（事务级锁定）│
s0(AW/W/B) ──┤            │ 载荷半缓冲寄存 + 2:1 mux    ├── m(AW/W/B) → DDR port
             └────────────┤ 响应按 gnt 归还             │
                          └────────────────────────────┘
   规则：grant 发出后锁定到该事务 M 口完整收尾（写 = B 握手且 W 已完成；
   读 = RLAST 握手）；锁定期间不发出第二个事务；事务间 1 拍再仲裁
```

核心取舍：**事务级锁定 + 每仲裁器单 outstanding**。不做地址先行/多 outstanding——换取无乱序、无 ID 跟踪、响应路由零查表。

## 4. 接口定义

命名沿用工程习惯：`sN_<chan>_<sig>`（N=0/1），M 口 `m_<chan>_<sig>`。位宽为 localparam 定值。

### 4.1 axi_wr_arb（写侧，200M）

| 方向 | 信号（每组 sN_） | 位宽 | 说明 |
|---|---|---|---|
| i/o | awvalid / awready | 1 | awready 为 **DDR→master 组合掩码回传**（§5.3）；master 保证 valid 保持 |
| i | awaddr | 33 | 33 位原样透传（两 master 的 bit32 本工程恒 0，**仲裁器不做任何拼接/裁剪**） |
| i | awlen / awsize / awburst | 8 / 3 / 2 | 突发参数随载荷寄存（cam0 awlen 编码 63/55 = 64/56 beat，cam1 31/27 = 32/28 beat；awsize=110，INCR） |
| i | awid | 6 | 随载荷寄存（两 master 恒 0） |
| i | awqos / awcache / awlock | 4 / 4 / 1 | 随载荷寄存（**awqos=1 必达 DDR**，写契约） |
| i/o | wvalid / wready | 1 | |
| i | wdata / wstrb / wlast | 512 / 64 / 1 | 半缓冲寄存（wstrb 与 wdata 同拍，§5.3） |
| o/i | bvalid / bready | 1 | B 按 gnt 归还（§5.5） |
| o | bresp / bid | 2 / 6 | 透传 |
| i | clk, rstn | 1 | 常在复位（§6） |
| o | dbg | 见 §7 | 诊断 |

### 4.2 axi_rd_arb（读侧，148.5M）

同构：AR 通道（arvalid/araddr[32:0]/arlen/arsize/arburst/arid[5:0]/arqos/arcache/arlock）随载荷寄存；R 通道（rvalid/rdata[511:0]/rresp/rlast/rid[5:0]）为 **1:2 demux + 半缓冲**（方向 M→S，P2-4）。

### 4.3 axi_rd_cdc 契约（另详设）

- 输入：cam1_rd 的 AXI4 读 master（37.125M）；输出：AXI4 读 slave 接口（148.5M）接 axi_rd_arb S0。
- AR 命令 FIFO（37→148）载荷 = araddr33 + arlen8 + arsize3 + arburst2 + arid6 + arqos4 + arcache4 + arlock1 = **61b**（+valid）；R 响应 FIFO（148→37）载荷 = rdata512 + rresp2 + rlast1 + rid6 = **521b**（ds-P2-1 核对值）。gray 指针，深度 4，参考 ddr_async_fifo。
- **反压链显式假设（kimi3-M1）**：硬核 R 通道满足 AXI valid-hold（AXI 规范保证）；CDC FIFO 满时反压贯穿至硬核读数据队列（深度 ≥16），不丢数。锁定期因此被拉长的场景计入 §5.4 最坏等待。

## 5. 功能规格

### 5.1 仲裁策略（RR1，2 口 = 严格交替）

- **请求定义（ds-P1-1）**：`req[N] = sN_awvalid`（写）/ `sN_arvalid`（读）。不要求 wvalid 同在——W 数据可在锁定后到达（AXI4 允许 W 先于/后于 AW），由锁定期转发语义兜住（§5.3）。
- 状态 `last`（上次服务口）。空闲拍采样：`req[~last]` 授 `~last`；否则 `req[last]` 授 `last`；否则空闲。两口同请必翻转（严格交替，无饿死）。
- **复位值 tie-break（kimi3-M3，有意安排）**：复位 `last=0` → 首次争用授 S1=cam0——cam0 是主通路，首争用偏置 cam0 是设计意图，注释与 T7 判据固化，防后人"修正"。
- 事务收尾拍 `last <= grant`，同拍进入再仲裁（下一授予最早 +1 拍，事务间 1 空拍）。

**流水线时序（ds-P1-7，总延迟以此为准）**：

```
拍0: 空闲采样 req，grant 锁存 + 载荷捕获（req 即 s_awvalid/arvalid，同拍锁存）
拍1: m_awvalid/arvalid=1（valid-hold，保持到 m 握手）；s_ready = gnt & (!valid_reg | m_ready) 组合回传（§5.3 v1.2 公式）
拍2+: DDR 侧握手；master 视角握手完成（至多比直连晚 1~2 拍，取决于 DDR ready 时刻）
     W/R 数据通道在锁定期内同构半缓冲转发，再 +1 拍
```

固有开销：地址通道 M 口 valid +1 拍（master 完成握手至多 +2 拍）；数据 +1 拍；事务间 +1 空拍。T1 判据"延迟 ≤ 直连+3 拍"与此自洽（测量点定义见 §9）。

### 5.2 事务锁定

- **写锁**：授予拍起，至 `b_fire && w_done` 释放。`w_done` = M 口 `m_wvalid && m_wready && m_wlast` 置位的 RTL 内部状态（**ds-P1-4：违约检测进 RTL，不只靠 TB**）。若 `b_fire && !w_done`（B 先于 W 完成，契约违约）→ 不释放、置 `dbg_stuck`（显性暴露，防静默数据损坏）。**违约后锁生命周期（v1.2 复核 P1-1）**：W 数据后到 → `w_done` 置位拍锁即释放（`b_fire` 已成立，`b_fire && w_done` 当拍满足）；W 永不到达 → 锁保持至复位（人工干预），看门狗持续置 `dbg_stuck`。不做自动恢复/重试。
- **读锁**：授予拍起，至 M 口 `rvalid && rready && rlast` 握手完成释放。
- **锁定期地址通道行为（kimi3-B2，语义 A；信号方向已修正）**：锁定期内 M 口**只发出当前事务这一次地址握手**——载荷寄存器清除（m 握手）后 `m_awvalid/m_arvalid` 恒 0 直至锁释放。注：`m_awready/m_arready` 是 DDR 驱动的输入，不可门控；本设计以"不再发出第二个 valid"实现单 outstanding（kimi 原文写"m_awready=0"系方向笔误，按其语义 A 意图修正采纳）。
- 锁定期非授权口：所有 s ready 恒 0、b/r 响应对其恒 0（A4）。
- **空闲拍响应（ds-P1-5 修正采纳）**：空闲拍 `m_bready/m_rready = 1`（选择理由：不楔死 DDR 口）。基于"事务级锁定保证空闲期无响应"的契约，若空闲拍出现 `m_bvalid/m_rvalid` 即为 DDR 侧契约违约 → 应答丢弃 + 置 `dbg_stuck`（不静默）。断言 A8 覆盖。

### 5.3 数据通路（统一半缓冲规则，三通道同构；v1.2 修正 ready 公式——复核 P0）

每通道一级**载荷+valid 寄存器（1 深缓冲，无源直通）**，四条规则：

1. **载入 = 源侧握手**（`s_valid && s_ready`，同拍锁存载荷并置 `valid_reg`）；
2. **清除 = 宿侧握手**（m 侧或 s 侧，按通道方向）；同拍既清又载时**载入优先**（保持满流水不断流）；
3. **源侧 ready（仅授权口）= `!valid_reg || 宿侧 ready`**（组合回传）——寄存器空时不等宿 ready 即可接收（预取）；满时须宿侧同拍腾空，否则 ready=0 令 master 等待（master 保证 valid 保持——设计假设 DA1，TB 兜底）；
4. **宿侧 valid = `valid_reg`**（寄存输出；置位后保持到宿握手，载荷不变）。

按通道展开：

- 地址/W（源=master，宿=DDR）：`sN_ready = gnt_match && (!valid_reg || m_ready)`；`m_awvalid/m_wvalid = valid_reg`；
- R（源=DDR，宿=master，1:2 demux）：`s{gnt}_rready = !valid_reg || m_rready`；`m_rvalid = valid_reg`（`m_rready` 是 master 驱动的输入，只可采样不可生成——v1.2 按信号方向修正）。

**为什么 ready 公式必须含 `!valid_reg` 项（v1.2 复核 P0，防 beat 重复）**：本项目 DDR 为 WVALID-first 契约（看到 `m_wvalid` 才拉 `m_wready`，见 [ddr_interface.md](ddr_interface.md)）。v1.1 公式（`gnt && m_ready`）缺该项时：拍0 寄存器空预取 beat1；拍1 `m_wready` 才拉高 → S/M 同拍握手，"宿握手同拍载入"会把 master **尚未推进的旧 beat1 再次载入**——M 口 beat1 发两拍，1:1 守恒（A6）破坏。修正后每 beat 恰载一次，推演（WVALID-first，稳态 1 beat/拍）：

| 拍 | s_wvalid | 寄存器 | m_wvalid | m_wready | s_ready | S 握手 | M 握手 | 载入 |
|---|---|---|---|---|---|---|---|---|
| 0 | beat1 | 空 | 0 | 0 | 1（`!valid_reg`） | beat1 | — | beat1 |
| 1 | beat2 | beat1 | 1 | 1 | 1 | beat2 | beat1 | beat2 |
| 2 | beat3 | beat2 | 1 | 1 | 1 | beat3 | beat2 | beat3 |

对 `m_ready` 恒高（组合 ready 早到）的时序同样成立——v1.1 公式仅在该时序下碰巧正确，v1.2 公式两种皆正确。T11 固化此场景。

随之满足（v1.2 公式下才真正成立）：

- **valid-hold（kimi3-B1）**：`m_*valid = valid_reg` 寄存输出，天然保持到宿握手，载荷绝不随源逐拍刷新；
- **W 门控不变式（kimi3-B3）**：非锁定期 `valid_reg` 强制清零 → `m_wvalid/m_awvalid/m_arvalid` 恒 0，未授予口早到的 WVALID 绝不出现在 M 口（A8）；
- **握手 1:1**：master 侧每次握手 ↔ M 侧恰好一次（A6）；稳态满流水 1 beat/拍，首 beat 多 1 拍缓冲延迟（即 §5.4"数据 +1 拍"）；
- **无死锁**：寄存器空时源侧不等宿 ready——m_valid 先行出现，DDR 据契约拉 ready，任意 DDR ready 时序下无死锁。

方向区分（ds-P2-4）：写侧 W = 2:1 **mux**；读侧 R = 1:2 **demux**。`wstrb` 随 `wdata` 同拍寄存；R 侧 `rresp/rid` 随 `rdata` 同拍寄存。

### 5.4 延迟与吞吐预算

| 项 | 写侧 @200M | 读侧 @148.5M |
|---|---|---|
| cam0 每行事务 | 2 burst（64+56 beat）+ 开销 ≈ 128 拍 | 同 128 拍 |
| cam0 行周期 / 占用 | 960 拍 / **13.3%** | 1100 拍 / **11.6%** |
| cam1 每行事务 | 2 burst（32+28）≈ 68 拍 | 同 68 拍 |
| cam1 行周期 / 占用 | 480 拍 / 14.2% | 2200 拍¹ / 3.1% |
| 合计占用 | **< 30%** | **< 15%** |
| 最坏竞争等待（cam0 视角） | ≤ cam1 单事务 ≈ 70 拍 = 350ns | ≤ 70 拍 = 470ns = **6.4% 行周期** |
| 固有开销 | 地址 +1~2 拍、数据 +1 拍、事务间 +1 空拍 | 同 |

¹ tick = 37.125M 域拍（550 tick/行），换算依据见 ddr_interface.md。

最坏等待预算**含 CDC 满反压场景**（kimi3-M1）：cam1 R 数据因 CDC FIFO 满被硬核反压时，读锁拉长，上表"≤70 拍"按事务拍数上限计已覆盖（cam1 单事务 ≤ 32+28+开销 ≈ 70 拍，反压只是拉长该事务）。读侧最坏 470ns 对比 ANCHOR_WAIT 余量（c3h 实测 grant+首字 ~0.2 行 = 220 tick）充裕；阶段 4 单元 TB 实测首字延迟分布复核（测量点：读 = 首拍 RVALID − ARVALID）。

### 5.5 信号处理总表（v1.1 重写，与 §5.3 对齐——ds-P0-1）

| 信号 | 处理 |
|---|---|
| AW 全载荷：awaddr/awlen/awsize/awburst/awid/awqos/awcache/awlock | **半缓冲寄存**（与 valid 同拍锁存，valid-hold） |
| AR 全载荷：araddr/arlen/arsize/arburst/arid/arqos/arcache/arlock | 同上 |
| W 全载荷：wdata/wstrb/wlast | 半缓冲寄存 2:1 mux（+1 拍） |
| R 全载荷：rdata/rresp/rlast/rid | 半缓冲寄存 1:2 demux（+1 拍，M→S） |
| bresp/bid | **组合 mux by gnt**（锁定期覆盖 B 全程，无释放竞态） |

**为什么不设 cur_owner 寄存器（对 kimi3-M5 的部分采纳说明）**：kimi 建议"B/R 回来时 grant 可能已释放，需锁存归属"。本设计锁语义保证 B 握手（读：RLAST 握手）发生时 grant 仍有效——释放拍即该握手拍，同拍路由仍正确，下一拍 gnt 才清除。故 gnt 本身就是归属寄存器，无需 cur_owner。若后续引入"响应迟到释放"类变更，须重审本条。

### 5.6 看门狗

- **进展定义（ds-P1-6）**：`beat_progress` 只在 **M 口实际握手拍**清零——W/R 数据握手或 B/R 响应握手。源侧 valid 挂起不算进展。
- 锁定期持续 >4096 拍无进展 → 置 sticky `dbg_stuck`，不自动解锁（契约破坏显性暴露）。
- **阈值依据（kimi3-M4）**：最长事务 ≈128 拍 × DDR 最大响应延迟（数十 ctrl_clk）× 安全系数 >10，取 2 的幂 = 4096。改 DDR 频率/配置时须重推。
- 附加违约检测（§5.2）：`b_fire && !w_done`、空闲拍响应（§5.2）均直置 `dbg_stuck`。

## 6. 复位策略（kimi3-M2 改写）

`rstn` 仅由**上电初始化复位树**驱动一次（写=sys_clk_200m 复位树，读=tx_pixel_clk 复位树，低有效异步）；**运行期（含源切换、flush、DIAG 复位）永不重新置位**——呼应硬纪律 #1（writer/reader AXI 口不复位）：仲裁器位于两 master 与 DDR 口之间，任何运行期复位都会掐断在途事务。源切换时 master 侧 flush 链保证 drain 空闲后才动作，仲裁器无需感知。

复位释放拍若恰有 master valid 高（上电引导期可能），按 §5.1 空闲采样正常处理，无 special case；T7 覆盖"复位释放与首请求同拍"。

复位值：grant 空、last=0、全部输出 valid/ready 0、计数器与 sticky 清零。

## 7. 诊断（Q4 定案：加每口 beat 计数）

```
dbg = { gnt_active, gnt[1:0]（one-hot，ds-P2-2）, lock（本模块锁标志）,
        watchdog_stuck（sticky）,
        txn_cnt[1:0]  每口完成事务数（16bit 饱和）,
        beat_cnt[1:0] 每口完成 beat 数（16bit 饱和；写=W 数据握手，读=R 数据握手） }
```

- beat 计数用于发现**部分完成**类契约破坏（W 中途断流但看门狗未超时、R 少拍）——与"契约破坏显性暴露"哲学一致（两评审共识）。
- 健康判读：稳态 gnt 交替、stuck=0、txn/beat 增速与帧率×每行拍数对账（T6 用同一口径）。

## 8. 非目标

地址解码/多目的地、AXI3（WID）、AXI4-Lite 桥接、多 outstanding、乱序响应、带宽 QoS、错序重排、宽窄转换、**burst 合并/拆分**（kimi3-Minor5，防范围蔓延）。每片 RTL ≤ 400 行（v1.1 上调：半缓冲载荷寄存实现量增加）。

## 9. 验证计划

单元 TB（sim/axi_wr_arb_tb.sv、sim/axi_rd_arb_tb.sv；2 个可编程 master BFM + 512b 存储从端记分板；**RTL 为纯 Verilog-2001 `.v`，全部 SVA 放 TB `.sv` 层次引用**——Q3 定案）：

| 用例 | 内容 | 判据 |
|---|---|---|
| T1 | 单口基线（仅 cam0 流） | 记分板 0 错；延迟 ≤ 直连+3 拍（写=BVALID−AWVALID；读=首拍 RVALID−ARVALID） |
| T2 | 双口并发争用 | RR 严格交替（A5）；两路记分板 0 错 |
| T3 | 随机背压（DDR wready/rready 随机拉低） | 无死锁；看门狗不触发 |
| T4 | 最坏交错（cam1 burst 嵌入 cam0 两 burst 之间） | 突发原子性（A2）；记分板 0 错 |
| T5 | 响应路由 | bid/rid 全部归属正确 |
| T6 | 混合长短事务带宽核算 | txn/beat 计数器读出 = 期望值 |
| T7 | 复位后首争用（含复位释放与首请求同拍） | 首争用必授 S1=cam0（§5.1 复位 tie-break） |
| T8 | 握手一致性 | master 侧握手数 == M 侧握手数（A6） |
| T9 | **W 早到（kimi3-B3）** | 授予前 1/3/5 拍随机拉高未授予口 WVALID：授予前 M 口无 W 泄漏（A8）；授予后数据 1:1 不重复（A6） |
| T10 | **看门狗边界（kimi3-B4/M4）** | 注入 DDR B 延迟略低于/高于 4096 拍 | 阈值下不触发、上触发 sticky；触发后不自动解锁、计数可读 |
| T11 | **WVALID-first 时序专项（v1.2 复核 P0）** | m_wready 在 m_wvalid 置位前恒 0（本项目 DDR 契约）；构造 S/M 同拍握手连续流 | 记分板 0 错；无 beat 重复/丢失（A6）；稳态 1 beat/拍 |

SVA 断言清单（v1.1 重编号）：

| # | 断言 |
|---|---|
| A1 | M 口载荷恒属当前授权口 |
| A2 | 异口突发在 M 口零交叠（锁语义） |
| A3 | 每口 B/R 数 == 其完成 AW/AR 数（无泄漏） |
| A4 | 锁定期非授权口 s ready / b·r 响应恒 0 |
| A5 | 连续争用 grant 翻转（RR） |
| A6 | 握手 1:1 守恒 |
| A7 | valid-hold：`m_*valid && !m_*ready` → 次拍 valid 保持且载荷不变（kimi3-B1） |
| A8 | 非锁定期 M 口 aw/w/ar valid 恒 0；空闲拍无 b/r 响应（违约 → dbg_stuck） |
| A9 | `b_fire |-> w_done`（ds-P1-4；RTL 内亦检测，§5.2） |
| A10 | 锁定期 gnt/归属稳定（kimi3-A9） |

集成门：阶段 3 写侧入 tb_phase4 → P4C 不破；阶段 4 读侧入链 → P4C 不破 + cam1 CDC 单元回环。流程 verible-syntax → vlog 0 Error → vsim 判据。**DDR 行为模型约定**：凡需 DDR 控制器仿真模型处（集成回归、仲裁时序复现），统一使用 `ddr_ctrl_model/` 目录模型（行为对齐 TJ UG，含 ARB_* 参数与 regress 体系），不另建模型。

## 10. 开放问题 → 已关闭

Q1~Q4 经两份评审表态一致，定案关闭：**Q1** 事务级锁定 + 单 outstanding（唯一模式，锁定期地址通道不再发出第二事务）；**Q2** 地址/W/R 全载荷寄存（半缓冲，§5.3）；**Q3** `axi_wr_arb.v`/`axi_rd_arb.v` 纯 Verilog-2001，SVA 全放 TB；**Q4** dbg 增加每口 beat 计数（§7）。

## 11. 资源与时序预估（v1.1 修正——ds-P0-2）

| 项 | 估算 | 依据 |
|---|---|---|
| 写侧 axi_wr_arb | ~750 LUT / ~750 FF | W 载荷 577b（512+64+1）+ AW 62b + B 8b + FSM/计数 ~100 |
| 读侧 axi_rd_arb | ~700 LUT / ~700 FF | R 载荷 521b + AR 62b + FSM/计数 ~100（读侧无 B 通道，v1.2 复核 P1-2 删笔误） |
| axi_rd_cdc | ~150 LUT；R FIFO 用 BRAM（521b×4，约 8~15 块 20Kb 块，视宽度模式）；AR FIFO（61b×4）分布式 RAM 或 FF | v1.2 复核 P1-3：R FIFO 用 FF 需数千 FF，比两片仲裁器本体还费；阶段 4 详设定案 |
| **合计** | **~1.6k LUT / ~1.6k FF**；仲裁器本体 0 BRAM | Efinix LUT4 2:1 mux ≈ 1 LUT/位，无压缩空间 |

时序：目标 200M/148.5M 有余量；`m_awready → s_awready` 组合掩码路径为潜在关键路径，fMAX 上限以阶段 3 efx_map 实测为准（ds-P2-5，不预设 300M）。

## 12. 评审意见处理记录

| 来源 | 项 | 处理 |
|---|---|---|
| kimi3 | B1 valid 保持语义 | 采纳 → §5.3 半缓冲规则 + A7 |
| kimi3 | B2 锁定期授权口地址通道 | 采纳语义 A；**修正信号方向**（m_awready 是 DDR 输入不可门控，以"锁定期不发出第二个 valid"实现）→ §5.2 |
| kimi3 | B3 W 早到门控 | 采纳 → §5.3 不变式 + A8 + T9 |
| kimi3 | B4 硬核内置仲裁直通决策 | 采纳 → §1 决策记录，连带收敛模型验证范围 |
| kimi3 | M1 CDC 反压假设 | 采纳 → §4.3 + §5.4 |
| kimi3 | M2 复位表述矛盾 | 采纳 → §6 改写 |
| kimi3 | M3 复位 tie-break 钉死 | 采纳（有意安排）→ §5.1 + T7 |
| kimi3 | M4 看门狗阈值依据 | 采纳 → §5.6 |
| kimi3 | M5 cur_owner | **部分采纳**：措辞矛盾已修；cur_owner 不需要——锁语义保证响应期 gnt 有效，理由见 §5.5 |
| kimi3 | Minor1-5 / T9 T10 / Q1-4 表态 | 全部采纳（awlen 编码值脚注、tick 脚注、T1 测量点、资源含 CDC、§8 加 burst 合并禁项） |
| ds | P0-1 §5.5 与 §5.3 矛盾 | 采纳 → §5.5 重写（地址/W/R 全载荷寄存，bresp/bid 组合 by gnt） |
| ds | P0-2 资源低估 | 采纳 → §11 重算（~1.6k LUT 总量） |
| ds | P1-1 req 定义 | 采纳 → §5.1（req = awvalid/arvalid，W 可后到） |
| ds | P1-2 cam1_fw 时钟域 | 采纳 → §2（两摄 raw 域同为 sys_clk_200m，写侧零 CDC） |
| ds | P1-3 数据通道反压 | 采纳 → §5.3（半缓冲载入/清除/ready 显式化；v1.2 复核又修正 ready 公式，见下） |
| ds | P1-4 w_done 保护 | 采纳并加强：RTL 内部状态 + 违约置 stuck，不只 TB → §5.2/§5.6 + A9 |
| ds | P1-5 空闲 bready 逻辑 | **部分采纳**：保留空闲 bready=1（不楔死 DDR 口），但补 A8 违约检测 → 应答丢弃 + stuck 置位，不静默 |
| ds | P1-6 进展定义 | 采纳 → §5.6（仅 M 口握手拍算进展） |
| ds | P1-7 流水线拍数歧义 | 采纳 → §5.1 流水线示意（地址 M 口 +1 拍，master 完成至多 +2 拍） |
| ds | P2-1~P2-5 | 全部采纳（CDC 61b/521b、gnt one-hot、beat 计数、demux 措辞、bit32 措辞统一/id 寄存对齐/T7 明写/撤 300M 预设） |
| 用户复核（v1.1 后） | P0 ready 公式漏 `!valid_reg` 项 | 采纳 → §5.3 重写：载入=S 握手、ready=`!valid_reg \|\| 宿侧 ready`、同拍载入优先于清除；R 行按信号方向修正为生成 `s{gnt}_rready`（m_rready 是 master 输入不可生成）；新增 T11 |
| 用户复核（v1.1 后） | P1-1 违约后锁生命周期未写明 | 采纳 → §5.2（w_done 后到即释放；W 永不到达保持至复位，看门狗 stuck） |
| 用户复核（v1.1 后） | P1-2 读侧"B 8b"笔误 | 采纳 → §11 删（读侧无 B 通道） |
| 用户复核（v1.1 后） | P1-3 CDC R FIFO 存储介质模糊 | 采纳 → §11（R FIFO 用 BRAM 约 8~15 块，AR FIFO 分布式 RAM/FF） |
| 用户复核（v1.1 后） | P2-1 "TJ UG" 引用不明 | 澄清后修正："TJ UG" 非型号笔误，即 [ddr-dram-controller-tj-ug-v3.0.md](ddr-dram-controller-tj-ug-v3.0.md)（DDR 控制器手册）→ §1 直接链接该文档；本行前版"改 Titanium Ti180 器件 UG"系误判，已撤 |
| 用户复核（v1.1 后） | P2-2 T10 表列错位 | 采纳 → §9 表格修正 |
| 用户复核（v1.1 后） | P2-3 "clt"→"clr" | 采纳 → 本表措辞修正 |
| 用户复核（v1.1 后） | P2-4 cam1_fw 时钟域引用依赖例化 | 采纳 → §2（cam0 以 RTL 实证表述；cam1_fw 现状不存在，改为阶段 5 设计承诺） |

## 13. 变更记录

| 版本 | 日期 | 说明 |
|---|---|---|
| v1.0 | 2026-10-23 | 初稿 |
| v1.1 | 2026-10-23 | 吸收 kimi3/ds 两份评审：半缓冲统一规则、锁定期地址通道语义、w_done 违约检测、资源重算、断言/用例扩充（A1-A10/T1-T10）、Q1-Q4 关闭 |
| v1.2 | 2026-10-23 | 修复 v1.1 复核发现的 P0：§5.3 ready 公式补 `!valid_reg` 项、载入改"S 握手"表述（防 WVALID-first 时序 beat 重复）；P1×3（违约后锁生命周期、读侧 B 8b 笔误、CDC 存储介质）；P2×4（TJ UG 引用改链 ddr-dram-controller-tj-ug-v3.0.md、T10 表格、clt 笔误、时钟域实证表述）；新增 T11 |
