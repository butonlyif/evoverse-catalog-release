[English](arbiter-impl-plan.en.md) | 中文

# AXI 仲裁器实现与验证步骤计划（axi_wr_arb / axi_rd_arb）

| 项 | 值 |
|---|---|
| 版本 | v1.0 |
| 日期 | 2026-10-23 |
| 依据 | [arbiter.md](arbiter.md) **v1.2（已冻结）**，本文只排步骤与判据，不改设计语义 |
| 关联 | [cam1-ddr-replay-plan.md](cam1-ddr-replay-plan.md)（任务 2 阶段 3/4 集成归属）、[ddr-dram-controller-tj-ug-v3.0.md](ddr-dram-controller-tj-ug-v3.0.md)（TJ UG） |
| 状态 | **待用户 review** |

---

## 1. 范围与交付物

| # | 文件 | 类型 | 依据（arbiter.md） |
|---|---|---|---|
| D1 | `rtl/axi_wr_arb.v` | RTL，纯 Verilog-2001，≤400 行 | §4.1、§5、§6、§7 |
| D2 | `rtl/axi_rd_arb.v` | 同上（结构同源、通道不同） | §4.2、§5、§6、§7 |
| D3 | `sim/axi_wr_arb_tb.sv` | 单元 TB（SV + SVA 层次引用） | §9（T 矩阵 / A1-A10） |
| D4 | `sim/axi_rd_arb_tb.sv` | 同上 | §9 |

**边界（明确不在本计划内）**：

1. `axi_rd_cdc` 详设与实现——阶段 4 开工前另行出详设文档评审（arbiter.md §4.3 只定契约）；
2. top_cam 集成与 tb_phase4 回归——归任务 2 阶段 3/4（cam1-ddr-replay-plan.md 既有计划）；本计划止于**单元验证全绿**；
3. 单元 TB **不使用** DDR 行为模型（存储从端记分板即可）；DDR 行为模型按 arbiter.md §9 约定仅用于集成回归（tb_phase4，用 `ddr_ctrl_model/`，跑法参照现有 sim/tb_phase4_ddrm.sv）。

## 2. 实施步骤（S1→S6 顺序执行）

### S1 实现 rtl/axi_wr_arb.v

| 动作 | 要点（均引自 arbiter.md，实现时不引入新语义） |
|---|---|
| 1. RR1 仲裁核心 | `last` 复位 0 → 首争用授 S1=cam0（§5.1，tie-break 有意安排，注释固化）；`gnt` one-hot 锁存；事务收尾拍 `last <= grant`，事务间 1 空拍 |
| 2. 地址通道 | 拍0 捕获：授予拍寄存器空 → `s_awready = gnt` 恒真，同拍锁存 AW 全载荷（§5.1 流水线 + §5.3 规则 3）；33 位地址原样透传不拼接（§4.1）；awqos=1 必达（§4.1） |
| 3. W 半缓冲 | §5.3 四规则：载入=S 握手；清除=M 握手；同拍载入优先；`m_wvalid=valid_reg`；`s_wready = gnt_match && (!valid_reg \|\| m_wready)`；wstrb 与 wdata 同拍寄存 |
| 4. B 通道 | 组合 mux by gnt（锁定期覆盖 B 全程，§5.5）；空闲拍 bready=1，空闲拍出现 bvalid → 丢弃 + 置 stuck（§5.2/§5.5） |
| 5. 锁与违约 | `w_done` RTL 内部状态；`b_fire && w_done` 释放；`b_fire && !w_done` → 不释放置 stuck，W 后到则 w_done 拍释放、永不到达保持至复位（§5.2） |
| 6. 看门狗 | 4096 拍无 M 口握手进展（W 数据/B 响应握手才算进展）→ sticky `dbg_stuck`（§5.6） |
| 7. dbg | dbg_stuck + 每口 txn/beat 计数（§7） |
| 8. 复位 | §6 常在复位策略；锁存/计数/valid_reg 全部复位 |

**完成判据**：verible-syntax check_verilog_syntax 0 error + lint 干净；≤400 行；V2001 可综合子集；组合 always 全 default（无 latch）。

### S2 实现 sim/axi_wr_arb_tb.sv

| 动作 | 要点 |
|---|---|
| 1. 双可编程 master BFM | aw/w 参数独立可编程：awlen ∈ {63, 55, 31, 27}（§4.1 cam0/cam1 档位）、beat 间隔、WVALID 早到 0/1/3/5 拍（T9）、**BFM 自带 valid-hold 自检**（违反 DA1 即报错，兜底） |
| 2. 存储从端 + 记分板 | 512b 模型内存，AW/W 按序收数比对图形；B 应答延迟可编程 0~5000 拍（覆盖 T10 双边界） |
| 3. SVA A1-A10 | 写侧全适用（含 A9 `b_fire \|-> w_done`）；层次引用 RTL（Q3 定案：SVA 不进 .v） |
| 4. 用例调度 | T1-T11 写侧全适用（§3 矩阵）；每用例结束打印 PASS/FAIL + 计数 SUMMARY |

**完成判据**：vlog 0 Error；vsim 单命令跑完全部用例全 PASS、断言 0 触发、记分板 0 错。

### S3 实现 rtl/axi_rd_arb.v

结构同源 S1，差异点：

- AR/R 通道；读锁至 M 口 RLAST 握手释放（§5.2），无 W/B/w_done；
- R 为 **1:2 demux**：`s{gnt}_rready = !valid_reg \|\| m_rready`（m_rready 是 master 输入只采样）、`m_rvalid = valid_reg`、rresp/rid 随 rdata 同拍寄存（§5.3/§5.5）；
- 看门狗进展 = R 数据握手（RLAST 握手释放即完成，§5.6）；
- 空闲拍 m_rready=1 + 空闲 rvalid 违约检测（§5.2）。

**完成判据**：同 S1。

### S4 实现 sim/axi_rd_arb_tb.sv

结构同源 S2，差异点：

- A9 不适用（无 B）；A1-A8、A10 适用；
- T10 边界注入改为扣住 m_rready / 拖延 RLAST；
- T11 覆盖双向：写侧 wready 晚到（P0 原场景）+ 读侧 **m_rready 晚到对偶**（P0 在 demux 方向的同型风险）。

**完成判据**：同 S2。

### S5 静态对照审查（结果记入交付汇报，不改码即过）

- §4.1/§4.2 接口表逐信号核对（名称/位宽/方向）；
- §5.3 三通道公式逐条对照 RTL 赋值（含 `!valid_reg` 项、同拍载入优先）；
- §8 非目标越界检查：无 burst 拆并、无多 outstanding、无地址解码、无 ID 跟踪；
- 硬纪律相关：33 位透传不拼接、awqos=1 透传、复位值 tie-break 注释在位。

### S6 交接与集成衔接

- S1-S5 全绿 → **单元验证冻结**，汇报：各用例 beat/txn 计数、断言触发数 0、两 RTL 行数；
- 交棒任务 2 阶段 3（写侧入 top_cam → tb_phase4 P4C 不破）；阶段 4 开工前另出 `axi_rd_cdc` 详设评审。

## 3. 验证矩阵

**T 用例 × 两侧适用**（判据全文见 arbiter.md §9）：

| 用例 | wr_tb | rd_tb | 两侧差异 |
|---|---|---|---|
| T1 单口基线 | ✓ | ✓ | 延迟测量点：写=BVALID−AWVALID；读=首拍 RVALID−ARVALID |
| T2 双口争用 RR 交替 | ✓ | ✓ | — |
| T3 随机背压 | ✓ | ✓ | 写=扣 wready；读=扣 rready |
| T4 最坏交错 | ✓ | ✓ | 写=cam1 burst 嵌 cam0 两 burst 间；读=AR 交错 |
| T5 响应路由 | ✓（bid） | ✓（rid） | — |
| T6 长短事务带宽核算 | ✓ | ✓ | — |
| T7 复位首争用授 S1 | ✓ | ✓ | — |
| T8 握手 1:1（A6） | ✓ | ✓ | — |
| T9 W 早到 | ✓ | — | 读侧无独立数据请求通道，早到场景由 T11 读向覆盖 |
| T10 看门狗双边界 | ✓（B 延迟） | ✓（RLAST 延迟） | — |
| T11 WVALID-first / P0 专项 | ✓ | ✓ | 读侧为 m_rready 晚到对偶 |

**断言适用**：A1-A8、A10 两侧共用；A9 仅写侧。

## 4. 工具链与验收流程（每步统一执行）

1. **verible-syntax MCP**：`check_verilog_syntax` → `check_verilog_lint`（.v 与 .sv 都查），0 error 才进编译；
2. **vlog**（sim/ 下，QuestaSim 2024.2）：`vlog ../rtl/axi_wr_arb.v ../sim/axi_wr_arb_tb.sv`，判据 **0 Error**；
3. **vsim**：`vsim -c axi_wr_arb_tb -do "run -all; quit -f"`，判据 = 全用例 PASS + 断言 0 触发 + 记分板 0 错。

集成阶段另按 tb_phase4 既有跑法执行（含 `ddr_ctrl_model/` 模型），不在本计划展开。

## 5. 风险与对策

| 风险 | 对策 |
|---|---|
| 组合 ready 掩码路径 fMAX（ds-P2-5） | RTL 掩码路径保持纯组合、无中间寄存；fMAX 留阶段 3 efx_map 实测，本计划不预设 |
| DA1（master valid-hold）假设被违反 | RTL 不做容忍；TB 侧 BFM valid-hold 自检兜底报错（§5.3） |
| 看门狗 4096 阈值余量不足 | T10 双边界用例；集成阶段按 TJ UG 响应参数复推（§5.6 已注明改配置须重推） |
| RR1 交替 / 复位偏 S1 被后人"优化" | T2/T7 判据固化 + RTL 注释声明"有意安排"（§5.1） |
| 半缓冲同拍清/载实现走样（v1.2 P0 复发） | T11 双向专项 + S5 静态逐条对照 §5.3 |

## 6. 评审与执行约定

- 本计划 **review 通过后**依 S1→S6 执行；每步完成报判据结果，不逐步等确认；**S4 全绿 = 单元验证冻结**，进入集成（阶段 3）前再整体汇报一次；
- 执行中若需增删用例或改判据，先改本计划并说明理由，再动 RTL/TB；
- 计划自身变更记入下方变更记录。

## 7. 变更记录

| 版本 | 日期 | 说明 |
|---|---|---|
| v1.0 | 2026-10-23 | 初稿，待用户 review |
