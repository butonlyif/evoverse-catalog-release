[English](ddr-test-spec-v0.2.en.md) | 中文

# TJ 系列 DDR 控制器测试组件设计规格

**文档编号**：SPEC-DDR-TEST-v0.2  
**关联文档**：SPEC-DDR-AXI-MODEL-v0.2  
**适用对象**：易灵思 TJ 系列 DDR 硬核控制器（LPDDR4/LPDDR4x）  
**测试目标**：实测 `READ/WRITE_OSTD_DEPTH`、`READ/WRITE_LATENCY`、`CMD_QUEUE_DEPTH`、`ARB_GRANT_INTERVAL`、`BVALID` 时机等参数，回填 AXI 行为模型  
**日期**：2026-10-21  
**状态**：架构评审通过，可进入测试组件实现

---

## 1. 目的、范围与前提

### 1.1 目的

本文档定义 TJ DDR 硬核控制器参数标定所需的测试组件：AXI Performance Monitor（APM）、AXI Traffic Generator（TG）、ILA 探针与测试执行流程。

### 1.2 范围

- AXI 侧性能/行为测量，不测量 PHY 电气参数；
- 单端口/双端口、读/写/混合流量；
- outstanding、延迟、反压、仲裁、`BVALID` 时机、rank/CS 行为；
- 测试结果回填 SPEC-DDR-AXI-MODEL-v0.2。

**不在范围：**

- DDR PHY 电气、training、ODT/VREF；
- DRAM 命令时序和刷新；
- 性能签核；
- 生产测试。

### 1.3 关键前提

1. **APM 默认 monitor-only**：只旁听 AXI 信号，不驱动任何 AXI 输出，不插入转发路径。若目标板只能 pass-through，按 2.3 的受控流程处理。
2. **DUT 必须先完成配置/校准**：`CFG_DONE=1` 之前不发测量流量，见第 4 章。
3. **写通道必须 co-assert `AWVALID/WVALID`**：TJ 控制器的 `AWREADY` 在 `AWVALID && WVALID` 后才可能拉高（UG Figure 4 注）。TG 不得先等 `AWREADY` 再发 `WVALID`，否则死锁。
4. **标定写参数时固定 `AWCACHE=4'b1111, AWCOBUF=0`**：否则 `BVALID` 早返会让“写完成”语义错位。
5. **延迟分位数优先**：`*_LATENCY_MAX` 回填 P99（有直方图）或 P95（无直方图），绝对 max 只作为 outlier 记录。

### 1.4 规范性标记

- `[UG]`：手册明示；
- `[AXI4]`：AXI4 推断；
- `[MODEL]`：模型/测试实现选择；
- `[CONFIRM-EFINITY]`：依赖 Efinity IP 的实际能力，需确认；
- `[CONFIRM-DUT]`：依赖实测/厂商确认。

---

## 2. 测试架构

### 2.1 总览（默认：monitor-only）

```text
┌─────────────────┐          ┌─────────────────┐          ┌─────────────────┐
│  AXI Traffic    │  AXI0    │  AXI Interconnect│  AXI0    │  TJ DDR 硬核     │
│  Generator      │─────────►│  （可选 register  │─────────►│  控制器          │
│  (Master, x2)   │◄─────────│    slice）        │◄─────────│  (Slave, x2)    │
└─────────────────┘          └─────────────────┘          └─────────────────┘
         │                            │                            │
         │                            │ AXI 信号旁听                │
         │                            ▼                            │
         │                   ┌─────────────────┐                   │
         └──────────────────►│  APM (monitor)   │◄──────────────────┘
                             │  + ILA 旁路探针  │
                             └─────────────────┘
```

**连接原则：**

- APM 的输入直接连到 AXI 网络（TG 与 DUT 之间），**不驱动** `AWREADY/ARREADY/WREADY/RREADY/BREADY`，不串在数据/地址/响应通道中。
- APM 只使用 `ACLK` 采样；所有计数器/直方图属于 `ACLK` 域。
- ILA 可旁听 APM 内部状态和 AXI 信号；CFG 信号在 `ctrl_clk` 域单独采样（见 4.5）。
- 若 FPGA 布线无法直接旁听，使用互联的 monitor 端口或插入**独立于 APM 的** register slice；该 slice 的延迟必须计入标定，见 2.3。

### 2.2 组件职责

| 组件 | 职责 | 是否在数据通路 |
|---|---|---|
| APM | 统计 outstanding、延迟、反压、事务计数 | 否（默认） |
| TG | 产生可控 AXI 流量 | 是（Master） |
| ILA | 事件捕获、交叉验证、协议调试 | 否 |
| Register slice（可选） | 改善布线/时序 | 是；必须固定延迟并校正 |

### 2.3 Pass-through 受控备选

如果目标板只能把 APM 放在转发路径上：

1. 所有五个通道统一插入寄存器/skid buffer，不能用组合门控；
2. `VALID` 路径只允许打拍，不允许组合逻辑改变；
3. `READY` 路径的延迟必须固定且可测；
4. 必须做两组实验：无 APM 基线 vs 有 APM，差值作为修正项；
5. 报告中必须写明“测量值 = 控制器 + pass-through”；
6. pass-through 不得破坏 `AWREADY` 对 `AWVALID && WVALID` 的依赖；不得在 `WVALID` 路径上增加与 `AWREADY` 相关的组合逻辑。

> 不满足以上条件时，pass-through 数据不能用于回填模型参数。

### 2.4 仪表化原则

- 先测量、后插入：Phase 0 先做无仪表基线，再启用 APM（monitor-only 应无差异），最后才考虑 register slice。
- 任何仪表化改动都要有“改动前/改动后”对照。
- 所有测量窗口、时钟频率、复位序列、AXI 静态配置必须记录。

---

## 3. 测量定义与口径

### 3.1 时钟域

| 域 | 用途 | 说明 |
|---|---|---|
| `ACLK` | APM、TG、AXI 协议测量 | 延迟以 ACLK 周期计数 |
| `ctrl_clk` | 模型内部延迟参数、CFG 时序 | 通常为 PHY 数据率 1/4 |
| `ACLK:ctrl_clk` | 换算 | 必须实测并记录；不能用标称值代替 |

```text
CLK_RATIO_ACLK_PER_CTRL = f_ACLK / f_ctrl_clk
latency_ctrl_cycles = latency_aclk_cycles × f_ctrl_clk / f_ACLK
```

> `SYNC_LATENCY` 无法仅从 AXI 边界独立测量；它和读延迟、内部排队混在一起，只能通过多组时钟比实验拟合/分摊 `[MODEL]`。

### 3.2 延迟参考点

| 指标 | 起点 | 终点 | 说明 |
|---|---|---|---|
| `T_AR_FIRST_R` | `ARVALID && ARREADY` | 同 ID 首拍 `RVALID && RREADY` | 模型 `READ_LATENCY_*` 的口径 |
| `T_AR_RLAST` | `ARVALID && ARREADY` | 同 ID `RLAST && RREADY` | 可选，用于 burst 总延迟 |
| `T_AW_B` | `AWVALID && AWREADY` | 同 ID `BVALID && BREADY` | 模型 `WRITE_RESP_LATENCY_*` 的口径 |
| `T_WLAST_B` | `WLAST && WREADY` | 同 ID `BVALID && BREADY` | `AWCOBUF=0` 时的数据完成延迟；早返时可能为负 |
| `T_WFIRST_ACCEPT` | `WVALID && WREADY` 首拍 | — | 用于诊断写数据接受节奏 |

**重要：**

- `T_AW_B` 的起点是 AW 握手。由于 `AWREADY` 依赖 `WVALID`，TG 必须把首拍 W 数据准备好；否则测到的是 TG 自己造成的等待。
- 早返模式（`AWCACHE=1111, AWCOBUF=1` 或 `AWCACHE=0000`）下，`BVALID` 可能早于 `WLAST`；`T_WLAST_B` 可能为负，APM 要单独计数 `B_BEFORE_WLAST`。
- 延迟样本按“完成时刻”落入采样窗口；时间戳可以早于窗口起点。

### 3.3 Outstanding 定义

```text
OSTD_RD = AR 握手累计数 − RLAST 握手累计数
OSTD_WR = AW 握手累计数 − B 握手累计数
```

- 写 outstanding 在 `BVALID && BREADY` 递减；早返模式下这会早于 WLAST，属于 AXI 语义，但标定 `WRITE_OSTD_DEPTH` 时必须用 `AWCOBUF=0`，使 B 与数据完成对齐。
- 每个端口的读/写分别计数；双端口例化两个 APM。
- 峰值是采样窗口内 `OSTD_*` 的最大值。

### 3.4 真实反压定义

由于 `AWREADY` 依赖 `AWVALID && WVALID`，不能把 `AWVALID && !AWREADY` 直接当反压。

| 指标 | 定义 | 含义 |
|---|---|---|
| `BP_AR` | `ARVALID && !ARREADY` | 真实读地址反压 |
| `BP_AW_TRUE` | `AWVALID && WVALID && !AWREADY` | 真实写命令反压（首拍 W 已提供） |
| `AW_WAIT_WVALID` | `AWVALID && !WVALID` | 等写数据，不是资源反压；用于诊断 TG/控制器时序 |
| `BP_W` | `WVALID && !WREADY` | 写数据反压 |
| `BP_R` | `RVALID && !RREADY` | 读数据反压（由 Master 造成） |

反压占空比：

```text
BP_*_RATIO = BP_*_CYCLES × 10000 / WINDOW_CYCLES   // 万分比，饱和到 10000
```

- 分母是采样窗口的 ACLK 周期数，不是 valid 周期数。
- 首次反压时间戳：窗口开始后第一次 `BP_AR` 或 `BP_AW_TRUE` 的全局周期计数；没有发生则为全 1。
- 同时记录 `AW_WAIT_WVALID`，避免把 TG 未给数据误判为控制器反压。

### 3.5 队列深度工程估计

```text
IN_FLIGHT_RD = TXN_ISSUED_AR − TXN_COMPLETED_RLAST
IN_FLIGHT_WR = TXN_ISSUED_AW − TXN_COMPLETED_B
CMD_QUEUE_DEPTH_ENG = max(IN_FLIGHT_* at first true backpressure)
```

- `CMD_QUEUE_DEPTH_ENG` 是**上界估计**：已发给 PHY 但未完成的事务仍计入 in-flight，但可能已离开命令队列。
- 若首次反压由 OSTD 限制而非队列限制，`CMD_QUEUE_DEPTH_ENG` 可能约等于 `OSTD_DEPTH_ENG`；报告必须说明是否可区分。
- 用单端口纯读、纯写、混合三种场景分别测；混合场景反映共享队列，纯读/纯写用于分离。
- 结果写 `CMD_QUEUE_DEPTH_ENG`，不要写成硬核规格。

### 3.6 延迟分位数

- 有直方图：`P99` = 累积计数达到 99% 的最小 bin 上界；同时报告 P50/P95/P99。
- 无直方图：只能报告 min/max/mean 和绝对 max；不得声称 P99。若必须给单值，用 P95（需要样本 FIFO），并标注。
- 绝对 max 作为 outlier 单独记录，不直接回填 `*_LATENCY_MAX`。
- 样本数少于 `MIN_SAMPLES`（默认 1000）时，分位数只作参考，报告中标注。

### 3.7 有效/无效运行

一次运行在以下任一情况下判为无效：

- APM `LAT_*_OVERFLOW` 非 0（per-ID FIFO 溢出或直方图溢出）；
- APM `LAT_ERR_COUNT` 非 0（完成事务找不到时间戳）；
- TG `timeout` 或 `error` 置位；
- ILA 捕获到 AXI 协议违例；
- DUT 卡死或需要复位恢复；
- 采样窗口内时钟频率变化超过 1%。

无效运行的数据不得进入回填表。

---

## 4. DUT 初始化与静态配置

### 4.1 时钟

- `ACLK` 由 PLL 产生，频率按系统需求；`ctrl_clk` 为 DDR 控制器时钟。
- 用频率计数器测量两者；记录 `CLK_RATIO_ACLK_PER_CTRL`。
- 若 `ACLK` 与 `ctrl_clk` 异步，APM 只在 `ACLK` 域；CFG 时序在 `ctrl_clk` 域检查。
- 改变 PLL 配置后必须重新标定，不得跨频点复用参数。

### 4.2 复位与配置序列

```text
1. CFG_SEL = 0
2. 断言 ARSTN_x = 0（至少 16 ACLK；异步断言/同步释放）
3. 断言 CFG_RESET = 1，保持 ≥ 5 个 ctrl_clk
4. 释放 ARSTN_x
5. 释放 CFG_RESET = 0
6. CFG_START = 1
7. 等待 CFG_DONE = 1
8. 保持 CFG_START = 1（不得在 CFG_DONE 后拉低）
9. 等待 CTRL_READY（若可用）或额外 INIT_CYCLES
10. 开始 AXI 流量
```

- `CFG_RESET` 至少 5 个 `ctrl_clk` `[UG]`。
- `CFG_START` 在 `CFG_DONE` 后保持高 `[UG]`。
- `CFG_SEL=0` 使能 `[UG]`。
- 手册建议所有复位在电源稳定后一起拉高；测试平台应遵循 `[UG]`。
- 若 `CFG_DONE` 长时间不拉高，先检查 `CFG_START/CFG_SEL/时钟`，不要继续发流量。

### 4.3 AXI 静态配置

| 信号 | 基线值 | 说明 |
|---|---|---|
| `AWCACHE` | `4'b1111` | 写延迟/OSTD 标定基线 |
| `AWCOBUF` | `1'b0` | 避免 B 早返 |
| `AWALLSTRB` | `1'b0` | 除非专门测 all-strobe |
| `AWLOCK/ARLOCK` | `1'b0` | 不支持 exclusive |
| `AWAPCMD/ARAPCMD` | `1'b0` | 模型/控制器接受并忽略 |
| `AWQOS/ARQOS` | `4'b0` | 默认不启用 QoS |
| `ARID/AWID` | 按 `ID_MODE` | 见 TG 参数 |
| `ARCACHE/ARPROT` | **不存在** | UG Table 10 没有这两个信号，不要连接 |

> `ARCACHE/ARPROT` 是 v0.1 的接口错误；v0.2 已删除。系统集成时以 UG Table 10 为准。

### 4.4 地址配置

- `BASE_ADDR` 必须在 `[0, MEM_BYTES - burst_bytes]` 内；
- `ADDR_RANGE` 不得跨越未使用的高位地址；
- 双 rank 时，地址扫描应覆盖 rank 边界；
- 非 2 的幂密度（3G/6G/12G）只做线性扫描，不假设 bit-field 地址映射；
- 4KB 安全地址生成见 6.4。

### 4.5 ILA 时钟域

| 探针组 | 采样时钟 | 说明 |
|---|---|---|
| AXI 通道/APM | `ACLK` | 与 APM 同域 |
| CFG_RESET/START/SEL/DONE | `ctrl_clk` | 不要用 ACLK 直接采样异步 CFG 信号 |
| 时钟比测量 | 两个时钟域各一个计数器 | 用 ILA 或 APM 的 cycle counter 读取 |

---

## 5. APM 设计规格

### 5.1 功能需求

APM 必须在不改变 AXI 行为的前提下统计：

| 类别 | 指标 | 用途 |
|---|---|---|
| Outstanding | 读/写实时值、峰值 | 标定 OSTD |
| 延迟 | min/max/分布/分位数 | 标定 latency |
| 反压 | 真实反压、等 WVALID、首次时刻、占空比 | 推断队列深度 |
| 事务 | 发出/完成计数 | 队列/OSTD 交叉检查 |
| BVALID | 早返计数、AW→B、WLAST→B | 标定 BVALID 时机 |

### 5.2 接口（monitor-only）

每个 APM 实例旁听 1 个 AXI 端口。**没有 AXI Master/Slave 转发端口。**

**AXI 旁听输入：**

```text
ACLK, ARESETN
AWVALID, AWREADY, AWADDR[32:0], AWLEN[7:0], AWSIZE[2:0], AWBURST[1:0], AWID[5:0],
AWCACHE[3:0], AWCOBUF, AWALLSTRB, AWQOS[3:0], AWLOCK
WVALID, WREADY, WLAST, WSTRB[63:0]
BVALID, BREADY, BID[5:0], BRESP[1:0]
ARVALID, ARREADY, ARADDR[32:0], ARLEN[7:0], ARSIZE[2:0], ARBURST[1:0], ARID[5:0],
ARQOS[3:0], ARLOCK, ARAPCMD
RVALID, RREADY, RLAST, RID[5:0], RRESP[1:0]
```

**控制/状态侧：**

| 信号 | 方向 | 说明 |
|---|---|---|
| `sample_interval[31:0]` | 输入 | 采样窗口 ACLK 周期数；0 = 连续自由运行 |
| `sample_start` | 输入 | 启动/重新装载窗口 |
| `sample_reset` | 输入 | 清空所有计数器和直方图 |
| `sample_done` | 输出 | 窗口结束脉冲 |
| `sample_cycles[31:0]` | 输出 | 本窗口实际周期数 |
| `ostd_rd_cur[15:0]` / `ostd_wr_cur[15:0]` | 输出 | 当前 outstanding |
| `ostd_rd_peak[15:0]` / `ostd_wr_peak[15:0]` | 输出 | 窗口内峰值（窗口结束时锁存） |
| `lat_rd_min[31:0]` / `lat_rd_max[31:0]` | 输出 | 读延迟 min/max（ACLK 周期） |
| `lat_wr_min[31:0]` / `lat_wr_max[31:0]` | 输出 | 写延迟 min/max（ACLK 周期） |
| `lat_rd_count[31:0]` / `lat_wr_count[31:0]` | 输出 | 有效延迟样本数 |
| `lat_rd_overflow` / `lat_wr_overflow` | 输出 | per-ID FIFO 溢出计数 |
| `lat_err_count` | 输出 | 完成事务找不到时间戳的次数 |
| `bp_ar_cycles[31:0]` / `bp_aw_cycles[31:0]` | 输出 | 真实反压周期数 |
| `bp_aw_wait_wvalid_cycles[31:0]` | 输出 | `AWVALID && !WVALID` 周期数（诊断，不是反压） |
| `bp_ar_ratio[15:0]` / `bp_aw_ratio[15:0]` | 输出 | 万分比 |
| `bp_ar_first_cycle[63:0]` / `bp_aw_first_cycle[63:0]` | 输出 | 首次真实反压的全局周期；无则全 1 |
| `txn_issued_ar[31:0]` / `txn_issued_aw[31:0]` | 输出 | 地址握手计数 |
| `txn_completed_r[31:0]` / `txn_completed_b[31:0]` | 输出 | RLAST/B 握手计数 |
| `b_before_wlast_count[31:0]` | 输出 | B 早于 WLAST 的计数 |
| `hist_rd_bin[i]` / `hist_wr_bin[i]` | 输出 | 直方图 bin，默认 64 个 |
| `hist_rd_overflow` / `hist_wr_overflow` | 输出 | 超出最高 bin 的样本数 |

### 5.3 Outstanding 统计

**读：**

- 递增：`ARVALID && ARREADY`；
- 递减：`RVALID && RREADY && RLAST`；
- 实时计数器每 ACLK 更新；峰值在窗口内跟踪，`sample_done` 时锁存。

**写：**

- 递增：`AWVALID && AWREADY`；
- 递减：`BVALID && BREADY`；
- 注意：由于 `AWREADY` 依赖 `WVALID`，递增时刻已经是“控制器接受了写命令”的时刻；不要再用 `AWVALID` 单独递增。
- 早返模式下递减早于 WLAST；这是 AXI 语义，但标定 `WRITE_OSTD_DEPTH` 时必须用 `AWCOBUF=0`。

**断言/检查：**

- 计数器不得下溢；下溢置 `lat_err`/`error`；
- 峰值不得超过 16 位范围（或按实际 OSTD 上限截断并报警）。

### 5.4 延迟测量

#### 5.4.1 推荐模式：per-ID 时间戳 FIFO

- 64 个 ID，每个 ID 一个时间戳 FIFO，深度 `LAT_FIFO_DEPTH`（默认 4，可配 2/4/8）。
- **读**：`ARVALID && ARREADY` 时，把 32-bit 自由运行 ACLK 时间戳压入 `fifo_rd[ARID]`。
  首拍 `RVALID && RREADY`（默认）时，从 `fifo_rd[RID]` 弹出并计算 `T_AR_FIRST_R`；可选终点 `RLAST`。
- **写**：`AWVALID && AWREADY` 时压入 `fifo_wr[AWID]`；`BVALID && BREADY` 时从 `fifo_wr[BID]` 弹出并计算 `T_AW_B`。
- 同 ID 按序保证 FIFO 顺序；不同 ID 乱序也能逐笔测量。
- 同时记录 `WLAST && WREADY` 时间戳（每 ID 一个，或复用 FIFO），用于 `T_WLAST_B`。
- FIFO 空时收到完成：`lat_err_count++`，丢弃该样本。
- FIFO 满：`lat_*_overflow++`，丢弃新样本；该运行判为无效（或至少该窗口无效）。
- `LAT_FIFO_DEPTH` 必须 ≥ 同一 ID 的最大 outstanding 数；否则高频同 ID 流量会溢出。建议先用 `ID_MODE=ROTATE` 降低同 ID 并发，再逐步验证深度。

**资源：**

```text
per-ID FIFO bits ≈ 64 × LAT_FIFO_DEPTH × 32 × 2（读+写）
```

默认深度 4：约 16 Kbit，约 1–2 个 BRAM18（取决于器件组织）。深度 8：约 32 Kbit。

#### 5.4.2 可选模式：单跟踪器

- `LAT_MODE=SINGLE_OLDEST`：只跟踪最老的一笔事务。
- 仅在 `OUT_OF_ORDER_ENABLE=0` 且全局按序时可用；乱序场景会漏样本。
- 资源最省，但不得用于 P99 标定；只能用于低负载 min 延迟。
- 报告中必须写明模式。

#### 5.4.3 时间戳与窗口

- 32-bit 自由运行 ACLK 计数器；采样窗口应小于回绕时间（500 MHz 约 8.6 s）。
- `sample_reset` 只清统计，不清自由运行时间戳；否则跨窗口事务无法计算。
- 延迟样本按“完成时刻”归属窗口。
- 记录 `MIN_SAMPLES`（默认 1000）；不足时报告标注。

### 5.5 延迟直方图

- 每个方向一个 BRAM/FIFO 直方图，默认 64 bin × 32 bit。
- `bin = latency >> HIST_SHIFT`；默认 `HIST_SHIFT=1`，覆盖 0–127 ACLK 周期。
- 若预期延迟更大，增大 `HIST_SHIFT`（如 2/3/4）；`HIST_SHIFT` 必须记录。
- 超出最高 bin：`hist_*_overflow++`，不要静默丢弃。
- `sample_reset` 清空直方图；`sample_done` 时锁存可选快照。
- P99 由主机读取 bin 后累积计算；bin 上界为 `(i+1)<<HIST_SHIFT - 1`。

### 5.6 反压统计

```text
bp_ar        = ARVALID && !ARREADY
bp_aw_true   = AWVALID && WVALID && !AWREADY
aw_wait_wvalid = AWVALID && !WVALID
bp_w         = WVALID && !WREADY
bp_r         = RVALID && !RREADY
```

- 首次反压时间戳分别记录 `bp_ar_first_cycle` 和 `bp_aw_first_cycle`；无发生则全 1。
- 占空比分母为 `sample_cycles`；四舍五入，饱和到 10000。
- `aw_wait_wvalid` 单独输出，不并入 `bp_aw_ratio`。
- 若 `AWVALID` 与 `WVALID` 不是同拍到达，`bp_aw_true` 从两者都有效的第一拍开始计数。
- `bp_w`/`bp_r` 反映 Master 侧反压，不是控制器内部队列；默认 TG 的 `WREADY/RREADY` 恒为 1，避免干扰。

### 5.7 BVALID 早返监测

- 每个 ID 维护一个“已收到 WLAST”标志（或 `WLAST` 计数）。
- `BVALID && BREADY` 时若该 ID 尚未收到 `WLAST`，`b_before_wlast_count++`。
- 同时记录 `T_AW_B` 和 `T_WLAST_B`；早返时 `T_WLAST_B` 为负，APM 用有符号/标志表示。
- 该计数用于验证 `AWCOBUF=1`/`AWCACHE=0000` 的早返语义，不用于基线写延迟。

### 5.8 寄存器映射（若 APM 作为可配置 IP）

| 偏移 | 名称 | 属性 | 说明 |
|---:|---|---|---|
| 0x00 | `APM_CONTROL` | RW | bit0 enable; bit1 hist_enable; bit2 lat_end_on_RLAST; bit3 per_id_mode; bit4 single_oldest |
| 0x04 | `SAMPLE_INTERVAL` | RW | 窗口周期数 |
| 0x08 | `SAMPLE_CONTROL` | RW | bit0 start; bit1 reset; bit2 auto_restart |
| 0x0C | `SAMPLE_STATUS` | RO | bit0 done; bit1 busy |
| 0x10 | `OSTD_RD_CUR` / `OSTD_WR_CUR` | RO | 当前 outstanding |
| 0x18 | `OSTD_RD_PEAK` / `OSTD_WR_PEAK` | RO | 峰值 |
| 0x20 | `LAT_RD_MIN` / `LAT_RD_MAX` | RO | 读延迟 |
| 0x28 | `LAT_WR_MIN` / `LAT_WR_MAX` | RO | 写延迟 |
| 0x30 | `LAT_RD_COUNT` / `LAT_WR_COUNT` | RO | 样本数 |
| 0x38 | `LAT_OVERFLOW` | RO | 读/写 FIFO 溢出、直方图溢出、lat_err |
| 0x40 | `BP_AR_CYCLES` / `BP_AW_CYCLES` | RO | 真实反压周期 |
| 0x48 | `BP_AW_WAIT_WVALID` | RO | 等 WVALID 周期（诊断） |
| 0x4C | `BP_AR_RATIO` / `BP_AW_RATIO` | RO | 万分比 |
| 0x50 | `BP_AR_FIRST_LO/HI`、`BP_AW_FIRST_LO/HI` | RO | 首次反压时间戳 |
| 0x60 | `TXN_ISSUED_AR/AW`、`TXN_COMPLETED_R/B` | RO | 事务计数 |
| 0x70 | `B_BEFORE_WLAST_COUNT` | RO | 早返计数 |
| 0x100+ | `HIST_RD` | RO | 读直方图 bin 0 起 |
| 0x200+ | `HIST_WR` | RO | 写直方图 bin 0 起 |

> 地址偏移是示例；实现时按总线位宽对齐。

### 5.9 资源估算

| 组件 | 估算 | 备注 |
|---|---|---|
| Outstanding/事务/反压计数器 | ~300–500 LUT + ~200 FF | 双方向 |
| per-ID 时间戳 FIFO | ~16 Kbit（深度 4） | 双方向；约 1–2 BRAM18 |
| 直方图 | 2 × 64 × 32 bit ≈ 4 Kbit | 约 1 BRAM18 |
| 控制/寄存器 | ~200 LUT | |
| **合计（默认）** | **~800–1200 LUT + 2–3 BRAM18** | 以综合报告为准 |

> 资源是估算，不是保证。若器件资源紧张，优先关闭直方图/缩短 per-ID FIFO；但 P99 标定需要直方图。

---

## 6. AXI Traffic Generator（TG）设计规格

### 6.1 功能需求

TG 必须产生可控、可重复的 AXI 流量，并严格遵守 TJ 控制器的写通道行为。

| 能力 | 用途 |
|---|---|
| 固定 outstanding 注入 | 测量延迟 vs outstanding，寻找饱和点 |
| 固定速率注入 | 找反压临界点 |
| Burst 参数扫描 | 覆盖 Table 5 边界 |
| 读写混合比例 | 观察读写仲裁/共享队列 |
| 双端口并发 | 验证 round-robin |
| 背压感知 | 尊重 `*READY`，不撤销 `VALID` |

### 6.2 强制 AXI Master 规则

1. **写地址与首拍写数据 co-assert**：`AWVALID` 与 `WVALID` 必须同拍有效，或 `WVALID` 更早。禁止“发 AWVALID → 等 AWREADY → 再发 WVALID” `[UG]`。
2. **W 数据可先于 AW**：写数据由独立 FIFO 驱动；`WVALID` 不依赖 `AWREADY` `[AXI4]`。
3. **B 早返不中止 W**：即使 `BVALID` 在 `WLAST` 前到达，TG 仍必须发完所有 W beat `[AXI4]`。
4. **VALID 不撤销**：`*VALID` 拉高后保持到 `*READY` `[AXI4]`。
5. **不跨 4KB**：地址生成必须保证 burst 不跨 4KB；除非显式开启错误注入。
6. **遵守 size/len 限制**：`AWSIZE/ARSIZE ≤ 6`；`AWLEN/ARLEN` 按 Table 5。
7. **超时保护**：任何通道等待超过 `TIMEOUT_CYCLES`，停止并置 `timeout`。

### 6.3 流量模式

**模式 A：固定 outstanding 注入（`FIXED_OSTD`）**

- 参数：`TARGET_OSTD`、`BURST_LEN`、`BURST_SIZE`、`DIRECTION`。
- 读：持续发 AR，直到 `OSTD_RD == TARGET_OSTD`；`RLAST` 后补充。
- 写：持续发 AW+首拍 W，直到 `OSTD_WR == TARGET_OSTD`；按 `WR_COMPLETE_MODE` 递减后补充。
- `WR_COMPLETE_MODE=B_HANDSHAKE`（默认）：B 握手完成；基线 `AWCOBUF=0`。
- `WR_COMPLETE_MODE=WLAST`：WLAST 完成；用于研究早返。
- 注意：若 B 早返且用 `B_HANDSHAKE`，TG 可能在新写还在发 W 时又发起下一笔；W FIFO 必须能容纳。
- 用途：延迟 vs outstanding 曲线；饱和点。

**模式 B：固定间隔注入（`FIXED_RATE`）**

- 参数：`INTERVAL_CYCLES`、`BURST_LEN`、`BURST_SIZE`、`DIRECTION`、`TOTAL_TXN`。
- 每 `INTERVAL_CYCLES` 发起一笔；若反压，保持 `VALID` 等待；实际速率可能低于设定。
- 写模式同样 co-assert AWVALID/WVALID。
- 用途：反压临界点、持续吸收速率。

**模式 C：地址扫描（`ADDR_SWEEP`）**

- 参数：起始地址、结束地址、步长、`BURST_LEN`、`BURST_SIZE`、`ADDR_ALIGN_MODE`。
- 顺序或伪随机遍历；必须 4KB 安全。
- 用途：地址局部性、rank 边界、bank/row 组合。

**模式 D：双端口竞争（`DUAL_PORT`）**

- 端口 0/1 各自独立配置 A/B/C。
- 用途：仲裁公平性、双端口延迟。

**模式 E：突发压力（`BURST_STRESS`）**

- 参数：`BURST_COUNT`、`BURST_LEN`、`BURST_SIZE`、`QUIET_CYCLES`。
- 连续发起 N 笔后静默；循环。
- 用途：峰值 outstanding、队列恢复。

### 6.4 4KB 安全地址生成

```text
burst_bytes = (BURST_LEN + 1) << BURST_SIZE
start_addr  = align_down(current_addr, burst_bytes)
if (start_addr % 4096) + burst_bytes > 4096:
    start_addr = align_up(current_addr, 4096)
```

- `ADDR_ALIGN_MODE=BURST_SAFE`（默认）：按上式计算；
- `ADDR_ALIGN_MODE=RAW`：按 `BASE_ADDR + n×step` 生成，可能跨 4KB；仅用于错误注入/模型测试；
- `ADDR_RANGE` 必须 ≥ `burst_bytes`，否则报配置错误；
- 双 rank/CS 边界由 `ADDR_RANGE` 覆盖，不假设 bit-field。

### 6.5 参数化

| 参数 | 默认 | 说明 |
|---|---:|---|
| `NUM_PORTS` | 2 | 1 或 2 |
| `AXI_DATA_WIDTH` | 512 | 与 TJ 控制器一致 |
| `AXI_ADDR_WIDTH` | 33 | |
| `AXI_ID_WIDTH` | 6 | |
| `TRAFFIC_MODE` | `FIXED_OSTD` | A/B/C/D/E |
| `TARGET_OSTD` | 8 | 模式 A |
| `INTERVAL_CYCLES` | 16 | 模式 B |
| `BURST_LEN` | 3 | 编码值；实际 beat = 值+1 |
| `BURST_SIZE` | 6 | 编码值；6=64 字节 |
| `DIRECTION` | `RD` | `RD`/`WR`/`BOTH` |
| `RD_WR_RATIO` | 50 | 模式 BOTH 的读占比 |
| `BASE_ADDR` | `0x0000_0000` | |
| `ADDR_RANGE` | `0x0100_0000` | |
| `ADDR_ALIGN_MODE` | `BURST_SAFE` | `BURST_SAFE`/`RAW` |
| `TOTAL_TXN` | 0 | 0=无限 |
| `ID_MODE` | `ROTATE` | `SINGLE`/`ROTATE` |
| `ID_BASE` | 0 | |
| `ID_COUNT` | 8 | ROTATE 使用 0..ID_COUNT-1 |
| `WR_COMPLETE_MODE` | `B_HANDSHAKE` | `B_HANDSHAKE`/`WLAST` |
| `ALLOW_BACKPRESSURE` | 1 | 保持 VALID |
| `RREADY_MODE` | `ALWAYS` | `ALWAYS`/`BACKPRESSURE` |
| `BREADY_MODE` | `ALWAYS` | `ALWAYS`/`BACKPRESSURE` |
| `AWCACHE` | `4'b1111` | 基线 |
| `AWCOBUF` | `1'b0` | 基线 |
| `AWALLSTRB` | `1'b0` | |
| `AWLOCK/ARLOCK` | `1'b0` | |
| `AWAPCMD/ARAPCMD` | `1'b0` | |
| `AWQOS/ARQOS` | `4'b0` | |
| `ERROR_INJECT_MODE` | `OFF` | 仅模型/厂商确认 |
| `CHECK_READ_DATA` | 0 | 1=启用读数据比对 |
| `TIMEOUT_CYCLES` | 1_000_000 | |
| `START`/`STOP` | — | 外部控制；`STOP` 进入 `DRAIN`，不中止 W |

### 6.6 数据生成

- **写数据模式**：`INCREMENT`、`PRBS`、`FIXED`、`ADDR_BASED`。
- `ADDR_BASED`：数据 = `f(addr)`，便于读回检查。
- **WSTRB**：默认全 1；`NARROW` 模式按 `BURST_SIZE` 和地址计算 lane；
- `AWALLSTRB=1` 时 WSTRB 必须全 1，且 beat 数 ≤16。
- 读数据：默认不比较；`CHECK_READ_DATA=1` 时用预置 pattern 或先写后读的 scoreboard 比对（需要额外存储/比较逻辑）。
- `RD_WR_RATIO` 只在 `DIRECTION=BOTH` 时生效；读写独立计数器，避免比值漂移。

### 6.7 状态与计数

| 信号 | 说明 |
|---|---|
| `txn_issued_aw[31:0]` / `txn_issued_ar[31:0]` | 地址事务发出数 |
| `txn_completed_b[31:0]` / `txn_completed_r[31:0]` | 响应完成数 |
| `ostd_cur[15:0]` | TG 自身未完成计数 |
| `bp_aw_cycles[31:0]` | `AWVALID&&WVALID&&!AWREADY` 周期数 |
| `aw_wait_wvalid_cycles[31:0]` | `AWVALID&&!WVALID` 周期数 |
| `bp_ar_cycles[31:0]` | `ARVALID&&!ARREADY` 周期数 |
| `first_bp_cycle[63:0]` | 首次反压全局周期 |
| `b_before_wlast_count[31:0]` | B 早返计数 |
| `timeout` / `error` | 超时/配置或协议错误 |
| `done` | `TOTAL_TXN` 完成或 `STOP` 完成 |

### 6.8 与 Efinity ATG 的关系 `[CONFIRM-EFINITY]`

- v0.1 中关于 Efinity ATG 的具体能力（`READ_WRITE` 模式、数据位宽 32–1024、命令 RAM 128×512 等）不是 UG 内容，v0.2 全部标记为待确认。
- 若复用官方 ATG，必须额外确认：
  1. 能否 co-assert `AWVALID/WVALID`；
  2. 是否会在 `BVALID` 早返时继续发 W；
  3. 是否支持固定 outstanding/固定速率节流；
  4. 是否支持 `AWCACHE/AWCOBUF` 静态配置。
- 任何一项不满足，就不能只用“前端节流器”，需要自定义 TG 或修改 ATG 封装。

---

## 7. ILA 配置规格

### 7.1 探针分组

**组 1：地址/反压/写握手（必需，约 40–48 位）**

| 信号 | 位宽 | 说明 |
|---|---:|---|
| `ARVALID/ARREADY` | 2 | 读地址握手 |
| `AWVALID/AWREADY` | 2 | 写地址握手 |
| `WVALID/WREADY` | 2 | 写数据握手 |
| `ARLEN/AWLEN` | 16 | burst 长度 |
| `ARID/AWID` | 12 | ID |
| `AWCACHE` | 4 | BVALID 分类 |
| `AWCOBUF/AWALLSTRB` | 2 | 写响应/全选通 |
| `ARAPCMD/AWAPCMD` | 2 | 可 tie 0，可选 |

**组 2：数据/响应（可选，约 16–24 位）**

| 信号 | 位宽 | 说明 |
|---|---:|---|
| `RVALID/RREADY/RLAST` | 3 | 读完成 |
| `BVALID/BREADY` | 2 | 写完成 |
| `BRESP/RRESP` | 4 | 响应类型 |
| `BID/RID` | 12 | 可选 |

**组 3：APM 内部状态（可选，约 48 位）**

| 信号 | 位宽 | 说明 |
|---|---:|---|
| `ostd_rd_cur/ostd_wr_cur` | 32 | outstanding |
| `lat_rd_max/lat_wr_max` | 64（截断） | 延迟 |
| `bp_aw_true/bp_ar` | 2 | 反压 |
| `b_before_wlast_count` | 16（截断） | 早返 |

**组 4：CFG/时钟（可选，约 8 位）**

| 信号 | 位宽 | 说明 |
|---|---:|---|
| `CFG_RESET/CFG_START/CFG_SEL/CFG_DONE` | 4 | 初始化 |
| `ctrl_clk` / `ACLK` 计数 | 2 | 频率比 |

### 7.2 触发条件

| 目标 | 触发条件 | 用途 |
|---|---|---|
| 真实写反压 | `AWVALID && WVALID && !AWREADY` | 捕获写命令反压前后 |
| 等 WVALID | `AWVALID && !WVALID` | 诊断 TG 死锁/时序 |
| 真实读反压 | `ARVALID && !ARREADY` | 捕获读反压 |
| B 早返 | `BVALID && !wlast_seen[BID]` | 验证早返语义 |
| B 时机 | `BVALID` 且 `AWCACHE/AWCOBUF` 匹配配置 | 测 `T_AW_B`/`T_WLAST_B` |
| 最大延迟 | `lat_*_max > THRESHOLD` 或 `RLAST && latency_counter > THRESHOLD` | 定位长延迟 |
| 双端口同时请求 | `(AR0VALID||AW0VALID) && (AR1VALID||AW1VALID)` | 仲裁 |
| 协议异常 | `WLAST` 与 beat 计数不匹配、`BVALID` 早于 AW 等 | 调试 |
| CFG 完成 | `CFG_DONE` 上升沿 | 初始化验证 |

### 7.3 资源公式

```text
ILA_BRAM18 ≈ ceil(PROBE_BITS × DEPTH / 18000)
```

- Efinity 的 BRAM 可能按 18Kb/36Kb 组织；以工具报告为准。
- 例：104 位 × 1024 深 ≈ 106 Kbit ≈ 6 个 BRAM18；2048 深 ≈ 12 个。
- 不要同时启用所有组；典型用组 1 + 组 3，组 2 仅在验证 `RLAST/BVALID` 时启用。
- 组 4 的 CFG 探针用 `ctrl_clk` 采样，不能和 ACLK 探针混在同一 ILA 时钟域。

---

## 8. 测试执行计划

### 8.1 Phase 0：基线、仪表化与初始化

1. **0a 无仪表基线**：TG 直连 DUT，仅 ILA 旁听；记录 `T_AR_FIRST_R`、`T_AW_B`、`BP_*` 的粗略值。
2. **0b Register slice（如使用）**：插入 slice，测其固定延迟（可用已知地址/响应或单独 loopback）；记录修正项。
3. **0c 启用 APM（monitor-only）**：与 0a/0b 对比；APM 不应改变时序。若发现差异，先查 APM 是否误接到路径上。
4. **0d DUT 初始化**：按第 4 章完成 CFG；读 `CFG_DONE`；记录时钟频率比。
5. **0e 快速冒烟**：单拍读/写、burst 读/写；确认 `AWREADY` 在 `AWVALID&&WVALID` 后、`BVALID` 正常、无 timeout。
6. **0f 读数据一致性**：用已知 pattern 写后读，确认地址/lane/rank 映射正确（可选但推荐）。

### 8.2 标定 `READ_OSTD_DEPTH` / `WRITE_OSTD_DEPTH`

1. **配置**：`DIRECTION=RD`（或 `WR`）；`AWCACHE=4'b1111, AWCOBUF=0`；`ID_MODE=ROTATE`；`ID_COUNT ≥ TARGET_OSTD`；`BURST_LEN=3, BURST_SIZE=6`。
2. **TG**：模式 A，`TARGET_OSTD` 从 1 逐步增加（1,2,4,8,16,32…）；每点运行至少 3 个采样窗口。
3. **APM**：启用 outstanding 实时/峰值；窗口 10000 ACLK 周期；记录 `ostd_*_peak`、`bp_*_ratio`、`txn_*`。
4. **判定**：
   - `TARGET_OSTD ≤ 实际上限`：APM 峰值 ≈ `TARGET_OSTD`，真实反压占比接近 0；
   - `TARGET_OSTD > 实际上限`：峰值饱和，`bp_*_ratio` 明显非 0；
   - 饱和点取“峰值不再增加 + 反压占比 > 1%”的最低目标值。
5. **重复**：纯读、纯写分开；读写混合另做参考，不用于最终 OSTD 值。
6. **交叉验证**：ILA 触发 `ostd_*_cur >= TARGET_OSTD`，确认 APM 与 ILA 计数一致。
7. **结果**：`READ_OSTD_DEPTH_ENG`、`WRITE_OSTD_DEPTH_ENG`；记录置信度（饱和平台是否清晰）。

> 写 OSTD 必须用 `AWCOBUF=0`；若用 `AWCOBUF=1`，B 早返会让 APM 提前递减，测到的是“命令接受上限”而不是“数据完成上限”。

### 8.3 标定读/写延迟

1. **低负载 min**：
   - `FIXED_OSTD TARGET_OSTD=1` 或 `FIXED_RATE` 大间隔；`ID_MODE=SINGLE`；
   - `TOTAL_TXN≥1000`；先丢弃前 100 笔 warm-up；
   - 扫描 `BURST_LEN=1,3,7,15,31`，`BURST_SIZE=2,4,6`；
   - 记录 `T_AR_FIRST_R`、`T_AW_B`、`T_WLAST_B` 的 min/median。
2. **高负载分布**：
   - 用 8.2 得到的 OSTD 上限的 25%/50%/75%/100%；
   - `FIXED_OSTD` 或 `FIXED_RATE`，运行足够样本（≥10000 笔或 10 个窗口）；
   - 启用直方图；记录 P50/P95/P99 和绝对 max。
3. **读延迟**：`READ_LATENCY_MIN` = 低负载 min；`READ_LATENCY_MAX` = 高负载 P99。
4. **写延迟**：基线 `AWCACHE=1111, AWCOBUF=0`；`WRITE_RESP_LATENCY_MIN` = 低负载 `T_AW_B` min；`WRITE_RESP_LATENCY_MAX` = 高负载 `T_AW_B` P99；`WRITE_DATA_TO_B_LATENCY` 从 `T_WLAST_B` 统计。
5. **时钟换算**：报告同时给 ACLK 周期和 `latency × f_ctrl/f_ACLK` 的 ctrl_clk 周期；记录实际频率比。
6. **同步延迟拟合**：在保持 `ctrl_clk` 不变的前提下改变 `ACLK` 频率（至少 3 个频点），重复低负载测量；用 `T_AR_FIRST_R` 随频率比的变化拟合/分摊 `SYNC_LATENCY`。该值不是独立观测量，报告中标注为拟合值。
7. **无效条件**：FIFO 溢出、lat_err、timeout、直方图饱和未处理时，该窗口无效。

### 8.4 推断 `CMD_QUEUE_DEPTH`

1. **配置**：单端口；`FIXED_RATE`；先纯读，再纯写，再 50:50 混合；`AWCACHE=1111, AWCOBUF=0`；`BURST_LEN=3, BURST_SIZE=6`；`ID_MODE=ROTATE`。
2. **扫描**：`INTERVAL_CYCLES` 从 256 开始逐步减半（256,128,64,32,16,8…），每个间隔固定事务数。
3. **记录**：每个间隔的 `bp_ar_ratio`/`bp_aw_ratio`、`bp_*_first_cycle`、`ostd_*_peak`、`txn_issued`、`txn_completed`。
4. **判定**：
   - 真实反压占比从 0 跃变为非 0 的临界点；
   - 首次真实反压时的 `IN_FLIGHT = txn_issued - txn_completed`；
   - `CMD_QUEUE_DEPTH_ENG ≈ max(IN_FLIGHT at first true backpressure)`。
5. **注意**：
   - 不要用 `txn_issued` 单独作估计，它包含已完成事务；
   - 队列深度是上界，可能被 OSTD 限制掩盖；
   - 纯读/纯写用于分离共享队列影响；混合用于观察共享行为；
   - 报告 `CMD_QUEUE_DEPTH_ENG`，不写成硬核规格。

### 8.5 标定仲裁行为

1. **配置**：双端口；端口 0/1 均用 `FIXED_OSTD` 或 `FIXED_RATE` 饱和流量；`AWCACHE=1111, AWCOBUF=0`。
2. **APM**：两个实例分别记录 outstanding/延迟/反压。
3. **ILA**：触发 `(AR0/AW0 valid) && (AR1/AW1 valid)`，捕获 grant 序列。
4. **分析**：
   - 相邻 grant 的最小间隔 → `ARB_GRANT_INTERVAL`；
   - 一端持续请求时另一端的最大 grant 延迟 → 公平性；
   - 一端安静时的服务速率 → fast path；
   - 读写混合时的 grant 序列 → 共享仲裁。
5. **结果**：`ARB_GRANT_INTERVAL`、fast path 是否生效、公平性描述。

### 8.6 标定 `BVALID` 时机

1. **组合**：
   - `AWCACHE=4'b1111, AWCOBUF=0`（基线，B 应在 WLAST 后）；
   - `AWCACHE=4'b1111, AWCOBUF=1`（B 可在命令入队后，早于 WLAST）；
   - `AWCACHE=4'b0000, AWCOBUF=0/1`（B 可在命令发 PHY 后，早于 WLAST）；
   - 其他 `AWCACHE` 编码（每个编码单独跑，观察是否影响 B 时机）。
2. **TG**：`WR_COMPLETE_MODE=B_HANDSHAKE`；确保 B 早返时继续发 W；`BREADY_MODE=ALWAYS`。
3. **APM/ILA**：记录 `T_AW_B`、`T_WLAST_B`、`B_BEFORE_WLAST`、`BRESP`。
4. **判定**：
   - 基线组 `T_WLAST_B` 应为正；
   - 早返组 `B_BEFORE_WLAST` 应大于 0；
   - 其他 AWCACHE 的行为若与模型假设不同，记录并更新 `OTHER_AWCACHE_POLICY`。
5. **风险**：B 早返时若 TG 停止 W，会导致 W 通道挂起；用 timeout 和 ILA `AWVALID&&!WVALID` 监控。

### 8.7 标定 `OUT_OF_ORDER_ENABLE`

1. **配置**：`FIXED_OSTD`，`TARGET_OSTD=8`，`ID_MODE=ROTATE`，`ID_COUNT=8`，读为主；地址分散到不同 bank/row。
2. **记录**：每笔 AR 的 ID/时间戳和 RLAST 完成顺序。
3. **判定**：
   - 同 ID 完成顺序必须与 AR 顺序一致；
   - 不同 ID 若出现后发先完成，说明支持乱序 → `OUT_OF_ORDER_ENABLE=1`；
   - 若全部按序，保持 0。
4. **重复**：写方向用 BID 观察；混合流量观察读写交互。
5. **注意**：AXI 允许乱序但不要求；不要把“未观察到乱序”当成“绝不乱序”，报告中注明测试覆盖。

### 8.8 地址/rank/容量检查

1. **容量**：按配置计算 `MEM_BYTES`；访问 `MEM_BYTES-1` 和 `MEM_BYTES`（后者应错误或回绕，按 DUT 行为记录）。
2. **rank 边界**：双 rank 时在 `RANK_STRIDE_BYTES` 两侧写不同 pattern，读回确认 rank 映射；不要假设固定 bit32。
3. **非 2 的幂密度**：3G/6G/12G 只做线性扫描；观察是否存在地址空洞/别名。
4. **CS 模式**：若使用 `CS_BIT`，用配置的 `CS_BIT_POS` 生成地址；与 `CS_STRIDE` 结果对比。
5. **记录**：实际可访问空间、rank 映射、空洞/别名行为；回填模型 `RANK_MAP_MODE`/`ADDR_HOLE_POLICY`。

### 8.9 错误响应（可选，默认关闭）

- 仅在模型或厂商确认硬核可安全处理非法 burst 时开启。
- 模式：跨 4KB、`SIZE=7`、长度超限、FIXED、`AWALLSTRB` 17 beat、非法 WSTRB。
- 记录 `BRESP/RRESP`、是否挂死、是否需要复位。
- 真实硬核上非法 burst 可能导致未定义行为；不得把错误注入结果当成正常性能数据。

### 8.10 参数回填

| 模型参数 | 测试来源 | 置信度 | 备注 |
|---|---|---|---|
| `READ_OSTD_DEPTH` | 8.2 饱和点 | 中 | 记 `READ_OSTD_DEPTH_ENG` |
| `WRITE_OSTD_DEPTH` | 8.2；`AWCOBUF=0` | 中 | 记 `WRITE_OSTD_DEPTH_ENG` |
| `READ_LATENCY_MIN` | 8.3 低负载 min | 高 | ACLK→ctrl_clk 换算 |
| `READ_LATENCY_MAX` | 8.3 高负载 P99 | 中 | 非绝对 max |
| `WRITE_RESP_LATENCY_MIN` | 8.3 低负载 `T_AW_B` min | 高 | 基线配置 |
| `WRITE_RESP_LATENCY_MAX` | 8.3 高负载 P99 | 中 | 非绝对 max |
| `WRITE_DATA_TO_B_LATENCY` | 8.3 `T_WLAST_B` | 中 | `AWCOBUF=0` |
| `CMD_QUEUE_DEPTH` | 8.4 `CMD_QUEUE_DEPTH_ENG` | 低 | 上界估计 |
| `ARB_GRANT_INTERVAL` | 8.5 最小 grant 间隔 | 中 | 双端口 |
| `BVALID_TIMING_MODE` / `OTHER_AWCACHE_POLICY` | 8.6 | 中 | 其他 AWCACHE 行为 |
| `OUT_OF_ORDER_ENABLE` | 8.7 | 中 | 多 ID |
| `RANK_MAP_MODE` / `CS_BIT_POS` | 8.8 | 中 | 双 rank/容量 |
| `SYNC_LATENCY` | 多频点 8.3 拟合 | 低 | 不能直接独立测量 |
| `LATENCY_MODE` | 8.3 分布形状 | 中 | 固定/均匀/其他 |

---

## 9. 资源与工具约束

### 9.1 资源估算

| 组件 | 估算 | 备注 |
|---|---|---|
| APM（双方向，per-ID FIFO，直方图） | ~800–1200 LUT + 2–3 BRAM18 | 以综合报告为准 |
| TG（双端口，模式 A–E） | ~1500–2500 LUT | 自定义；复用 ATG 另算 |
| ILA（组 1+组 3，深 1024） | ~6 BRAM18 | 公式见 7.3 |
| **合计** | **~3–5K LUT + 8–12 BRAM** | 需目标器件余量 |

> v0.1 的“~2–3K LUT + 8–10 BRAM”和豆包的“~1.7K LUT”都缺少综合依据。v0.2 给范围，并要求以目标器件综合报告为准。

### 9.2 工具流程

- **APM**：优先自定义（monitor-only）；若使用厂商 APM，确认它是否真的旁听而不串在路径上。
- **TG**：优先自定义或修改官方 ATG 封装；`[CONFIRM-EFINITY]` 项见 6.8。
- **ILA**：Efinity Logic Analyzer；按 7.1 分组，按 7.2 触发；CFG 组用 `ctrl_clk`。
- **时序收敛**：APM 输入打一拍再进计数器，避免长组合路径；不要在数据路径上插入组合逻辑。若需要 register slice，用标准 AXI skid buffer 并固定延迟。

### 9.3 目标器件

- 确认目标 TJ 器件（如 Ti60/Ti90/Ti180/TJ375 等）的 LUT/BRAM 余量；
- 资源不足时优先级：关闭直方图 → 缩短 per-ID FIFO → 单跟踪器 → 减少 ILA 组/深度；
- 任何降级都要在报告中标注对测量精度的影响。

---

## 10. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| `AWREADY` 等 `WVALID` 导致 TG 死锁 | 测试挂死 | TG 强制 co-assert；ILA 触发 `AWVALID&&!WVALID`；timeout |
| APM pass-through 改变时序 | 延迟/队列深度失真 | 默认 monitor-only；pass-through 做有/无基线校正 |
| APM 反压误判 | 队列深度估计错误 | 用 `AWVALID&&WVALID&&!AWREADY`；单独统计等 WVALID |
| `BVALID` 早返 | 写 OSTD/延迟口径错位 | 标定固定 `AWCOBUF=0`；早返单独实验 |
| B 早返后 TG 停 W | W 通道挂起/协议违例 | TG `DRAIN`；B 早返不中止 W；timeout |
| per-ID 时间戳 FIFO 溢出 | 延迟样本缺失 | 增大深度；溢出判无效；监控 |
| 直方图 bin 饱和 | P99 偏低 | 增大 `HIST_SHIFT`；溢出计数 |
| 非 2 的幂密度地址空洞 | 访问错误/别名 | 线性扫描；记录空洞；不启用 bit-field |
| 非法 burst 挂死真实硬核 | 需要复位/损坏 | 错误注入仅模型/厂商确认；默认关闭 |
| 时钟比变化 | 参数换算错误 | 每次运行测频率；变化 >1% 判无效 |
| Efinity IP 能力不符 | 复用失败 | `[CONFIRM-EFINITY]`；准备自定义 TG/APM |
| 仪表化资源不足 | 无法全功能 | 按 9.3 降级；记录精度影响 |

---

## 11. 交付物

1. APM RTL（monitor-only，per-ID 时间戳 FIFO + 直方图）；
2. TG RTL（co-assert 写路径、模式 A–E、4KB 安全地址）；
3. ILA 调试配置文件（`debug_profile.json` 或 Efinity Debugger 等效配置）；
4. 测试脚本/流程文档（覆盖第 8 章序列和判据）；
5. 标定结果记录表（含原始直方图、无效运行、时钟比、配置快照）；
6. 回填后的模型参数文件；
7. 风险/待确认项清单（`[CONFIRM-EFINITY]`、`[CONFIRM-DUT]`）。

---

## 12. 附录：标定记录模板

| 字段 | 示例/说明 |
|---|---|
| 日期/操作者 | |
| 目标器件/板卡 | |
| DDR 类型/密度/rank/DQ 宽度 | LPDDR4x, 4G, 1 rank, x32 |
| `ACLK` / `ctrl_clk` 频率 | 166.6 MHz / 666.5 MHz |
| `CLK_RATIO_ACLK_PER_CTRL` | 0.25 |
| `CFG_RESET` 宽度（ctrl_clk） | ≥5 |
| `CFG_DONE` 等待时间 | |
| `AWCACHE/AWCOBUF` | 1111 / 0 |
| `ID_MODE` / `ID_COUNT` | ROTATE / 8 |
| `TRAFFIC_MODE` / 参数 | FIXED_OSTD, TARGET=8 |
| 采样窗口 / 样本数 | 10000 ACLK / 10000 |
| `OSTD_*_PEAK` | |
| `BP_*_RATIO` | |
| `LAT_*_MIN/MAX/P99`（ACLK） | |
| 换算后 ctrl_clk 延迟 | |
| 直方图/overflow | |
| 无效标志/原因 | |
| 结论/置信度 | |

---

## 13. 修订历史

| 版本 | 日期 | 说明 |
|---|---|---|
| v0.1 | 2026-10-21 | 初稿 |
| v0.2 | 2026-10-21 | 根据 kimi3/豆包反馈和手册复核修订：APM 默认 monitor-only；per-ID 延迟跟踪；真实反压定义；TG 写通道 co-assert/W 先于 AW/B 早返不中止；DUT CFG 初始化；BVALID 时序表征；P99 口径；资源/风险/待确认项 |

---

**文档状态**：架构评审通过，可进入测试组件实现。  
**前置依赖**：确认目标器件资源；确认 Efinity APM/ATG 实际能力；确认 DUT 的 CFG/复位/时钟连接。
