[English](traceability.en.md) | 中文

# Spec → RTL → 测试追溯矩阵

**模型 spec**：SPEC-DDR-AXI-MODEL-v0.2
**实现计划**：PLAN-DDR-AXI-MODEL-v0.1
**日期**：2026-10-21
**回归基线**：60/60 通过（tb_top 48 + tb_top_cdc 9 + tb_unit 3；跑法固化 `tb/regress.sh` + `testlist.txt`，Phase 8 重跑 2026-10-23，plan §9）；`random_stress` 50 seeds（-sv_seed 2..51）全通过；RTL 分支 99.5%，语句 99.7%，FSM 100%（覆盖率为开发期基线，Phase 8 未重收）

状态说明：**完成** = 已实现并有定向测试；**部分** = 有实现但测试或语义不完整；**偏差** = 明确不实现/不同语义；**N/A** = 不在模型范围。

---

## 1. 接口与参数（spec 第 5、6、20 章）

| Spec 条目 | RTL 实现 | 测试/检查 | 状态 |
|---|---|---|---|
| 5.1 AXI 全局信号（ACLK/ARSTN） | `ddr_axi_model_top` 端口；同步/CDC 两种端口外壳 | `smoke_reset`、`port_reset`、`tb_top_cdc`（ratio 1/2/4） | 完成（CDC_ENABLE=1 时 ACLK 可异步） |
| 5.2 写地址通道 | 顶层 AW 端口；`axi_port_shell` AW 握手 | `aw_waits_wvalid`、`wr_incr` | 完成 |
| 5.3 写数据通道 | 顶层 W 端口；W FIFO（641 bit） | `wr_wstrb`、`wr_w_before_aw` | 完成 |
| 5.4 写响应通道 | B FIFO；`core_scheduler` B 生成 | `wr_single`、`early_b` | 完成 |
| 5.5 读地址通道 | 顶层 AR 端口；`axi_port_shell` | `reads`、`ostd_rd` | 完成 |
| 5.6 读数据通道 | R FIFO；`core_scheduler` beat 生成 | `reads`、`rd_narrow`（reads 内） | 完成 |
| 5.7 配置控制器接口 | `cfg_ctrl_fsm` | `smoke_cfg`、`cfg_sel` | 完成 |
| 5.8 控制器状态接口 | `ddr_axi_model_top` 状态输出 | `smoke` | 完成 |
| 5.9 时钟与复位 | 端口复位 + CFG 复位；`ddr_async_fifo` 灰度指针 CDC | `smoke_reset`、`port_reset`、`port_reset_mid`、`cfg_sel`、`tb_top_cdc` | 完成（1:1/2:1/4:1 已验证） |
| 6.1 结构性参数 | 顶层 parameter 列表 | elaboration 检查（密度/位宽/地址宽度/CS_BIT） | 完成 |
| 6.2 存储容量推导 | `MEM_BYTES` localparam；`calc_mem_bytes_per_channel` | `tb_unit_addr` 密度用例 | 完成 |
| 6.3 性能参数 | `ARB_GRANT_INTERVAL`、`W_ACCEPT_INTERVAL`；`SYNC_LATENCY/ARB_LATENCY` 仅保留 | `latency`、`ostd_*` | 部分：SYNC/ARB latency 未建模 |
| 6.4 延迟参数 | `pick_lat`（xorshift32）、`READ_LATENCY_MIN/MAX`、`LATENCY_MODE` | `latency`、`lat_fixed` | 完成 |
| 6.5 BVALID 时机参数 | `core_scheduler` 早返/deadline 逻辑 | `early_b`、`bvalid_modes` | 完成 |
| 6.6 错误与边界参数 | `check_cmd`、`core_scheduler` 粘滞错误、`ERR_INJECT_RATE` 注入 | `wr_errors`、`allstrb`、`err_inject`、`tb_unit_addr` | 完成（注入粒度为整条命令） |
| 6.7 配置与复位参数 | `cfg_ctrl_fsm`、`mem_model` | `smoke_cfg`、`cfg_sel`、`cfg_clear_mem`、`tb_unit_mem` | 完成 |
| 20 默认参数汇总 | 顶层默认值与 spec 表一致 | 代码审查 | 完成 |

## 2. AXI 行为（spec 第 7 章）

| Spec 条目 | RTL 实现 | 测试 | 状态 |
|---|---|---|---|
| 7.1 全局规则（VALID/READY 握手） | `axi_port_shell`、`core_scheduler` | `ddr_model_assertions` 全部用例 | 完成（首批断言） |
| 7.2 AW 通道；AWREADY 依赖 WVALID | `axi_port_shell` 中 `aw_req`（`WVALID || !w_empty`） | `aw_waits_wvalid`、`wr_w_before_aw` | 完成（W-first 放宽，见 user-guide §7） |
| 7.3 W 通道；WREADY 独立于 AW | `axi_port_shell` W FIFO 与 `wready` | `wr_w_before_aw`、`wr_wstrb` | 完成 |
| 7.4 B 通道；BID/BRESP | `core_scheduler` B 生成、B FIFO | `wr_single`、`early_b`、`ostd_wr` | 完成 |
| 7.5 AR 通道 | `axi_port_shell` `ar_req` | `reads`、`ostd_rd` | 完成 |
| 7.6 R 通道；narrow lane | `core_scheduler` + `mem_model` | `reads`（narrow/WRAP/错误） | 完成 |
| 7.7 Burst 规则（Table 5/4KB/WRAP/FIXED） | `table5_ok`、`cross_4kb`、`wrap_len_ok`、`check_cmd` | `tb_unit_addr`、`wr_errors`、`reads` | 完成 |
| 7.8 Narrow 与 WSTRB | `lane_strobe`、`mem_model`、`tb_pkg::tb_wstrb` | `tb_unit_mem`、`wr_wstrb`、`reads` | 完成（无效 lane 返回 0 为 `[MODEL]`） |
| 7.9 地址映射/容量/rank | `rank_of`、`addr_field_decode`、`apply_addr_hole`、顶层 `MEM_BYTES` | `tb_unit_addr`、`field_decode`、`addr_hole`、`addr_alias`、`addr_alias_cross` | 完成（含 FIELD_DECODE_DEBUG、DECERR/ALIAS 空洞策略） |
| 7.10 错误响应 | `check_cmd`、`core_scheduler` 错误路径、`err_inject` | `wr_errors`、`reads` 越界/4KB、`allstrb`、`err_inject` | 完成 |
| 7.11 Lock/Exclusive/QoS/Cache | Cache 影响 B 时机；其余忽略 | `early_b`、`bvalid_modes` | 偏差：exclusive/QoS 未建模 |

## 3. 仲裁、队列、延迟、ID（spec 第 8–11 章）

| Spec 条目 | RTL 实现 | 测试 | 状态 |
|---|---|---|---|
| 8.1 双端口 round-robin | `ddr_axi_model_top` 仲裁组合/时序逻辑；CDC 模式每端口独立 FIFO | `dual_port`、`arb_fairness`、`dir_arb`、`contend_multi` | 完成（竞争时双端口均获 grant） |
| 8.2 仲裁参数 | `ARB_GRANT_INTERVAL`、`ARB_QUIET_FAST_PATH` | 所有用例；`arb_fairness` | 完成 |
| 8.3 仲裁断言 | `ddr_model_assertions` one-hot / grant-gap / 请求约束 | `arb_fairness` 及全部用例 | 完成 |
| 9.1 队列抽象 | 每方向命令 FIFO、每端口 W/B/R FIFO | `ostd_wr`、`ostd_rd` | 完成 |
| 9.2 背压规则 | `cmd_space`、FIFO full、outstanding 限制 | `ostd_*`、`cmdq_full`、`wdataq_full`、`rdataq_full` | 完成 |
| 9.3 与硬核差异 | 见 user-guide §7 | — | 记录 |
| 10.1–10.3 延迟模型 | `pick_lat`、`core_scheduler` deadline | `latency`、`lat_fixed` | 完成（未建模 SYNC/ARB latency） |
| 10.4 延迟不承诺 | 参数化/随机 | `latency` | 完成 |
| 11.1 Outstanding 计数 | `axi_port_shell` 计数器 | `ostd_wr`、`ostd_rd` | 完成 |
| 11.2 ID 管理 | `OUT_OF_ORDER_ENABLE` 按 deadline 调度；同端口同 ID 按 seq 保序；可选 R beat 交织 | `ooo_same_id`、`ooo_diff_id`、`ooo_interleave`、`ooo_b`、`ooo_b_same_id` | 完成（可选 OOO） |
| 11.3 响应顺序断言 | BFM/scoreboard 检查 BID/RID、同 ID 顺序与交织 | `ostd_*`、`reads`、`ooo_*` | 完成（BFM 检查） |

## 4. CFG、复位、存储、状态（spec 第 12–15 章）

| Spec 条目 | RTL 实现 | 测试 | 状态 |
|---|---|---|---|
| 12.1–12.2 CFG 状态机 | `cfg_ctrl_fsm`（IDLE/INIT/DONE） | `smoke_cfg`、`cfg_sel`、`tb_unit_cfg` | 完成（FSM 状态/迁移覆盖 100%） |
| 12.3 CFG 参数 | `INIT_CYCLES`、`INIT_AXI_*` | `smoke_cfg`、`init_block`、`init_slverr` | 完成 |
| 13 复位模型 | `ARSTN_x`、`CFG_RESET`；核心丢弃未完成命令 | `smoke_reset`、`port_reset`、`port_reset_mid`、`tb_top_cdc`（cdc_rst） | 完成 |
| 14.1 存储结构 | `mem_model` 稀疏字节数组 | `tb_unit_mem` | 完成 |
| 14.2 访问规则（WSTRB/窄读） | `mem_model` 写使能/lane 读 | `tb_unit_mem`、`wr_wstrb`、`reads` | 完成 |
| 14.3 后门 | `bd_write/bd_write64/bd_read/bd_clear/bd_used_bytes` | `tb_unit_mem` | 完成 |
| 15 状态信号 | 顶层 `CTRL_INIT_DONE/READY/BUSY/ERR` | `smoke` | 完成（BUSY/ERR 语义简化） |

## 5. 断言与验证计划（spec 第 16、17 章）

| Spec 条目 | 实现 | 状态 |
|---|---|---|
| 16.1 AXI 协议断言 | READY→VALID、VALID 保持、B/R 稳定、WLAST/RLAST 合法、B/R 不早于命令握手 | 部分（缺 WDATA 保持断言） |
| 16.2 手册规则断言 | `CFG_DONE→CFG_START`、CFG_RESET 清 DONE、DONE 粘滞、CFG_RESET 最小宽度 | 部分（缺 4KB/Table5/ALLSTRB 断言） |
| 16.3 仲裁断言 | `a_arb_onehot`、`a_arb_grant_gap`、请求与 grant 约束 | 完成 |
| 16.4 队列断言 | 无 SVA（FIFO 溢出 `$warning`）；队列满由 BFM 探针覆盖 | 部分 |
| 17.1 手册示例回归 | `wr_incr`、`reads`（Figure 3/4 语义）、`early_b` | 完成 |
| 17.2 功能用例 | 见 `tb_top`/`tb_top_cdc` 用例表 | 完成（队列满、初始化阻塞、OOO、CDC、端口复位中断均已覆盖） |
| 17.3 地址/容量用例 | `tb_unit_addr`、`wr_errors`、`reads`、`field_decode`、`addr_hole*` | 完成 |
| 17.4 性能趋势用例 | `latency`、`lat_fixed`、`r_gap`、`w_gap`、`cdc_wgap` | 部分（SYNC/ARB latency 未建模） |
| 17.5 覆盖点 | UCDB + 8 个功能 covergroup 实例 | 部分（cross 未裁剪，bins 40.7%） |

## 6. 单元测试映射

| 函数/模块 | 测试 | 关键用例 |
|---|---|---|
| `burst_bytes` / `table5_ok` / `cross_4kb` | `tb_unit_addr` | 边界 len/size、4KB 偏移 0xFF0/0xFF8/0xFFC |
| `wrap_len_ok` / `aligned_to_size` / `beat_addr` | `tb_unit_addr` | WRAP 2/4/8/16、回绕地址、INCR/FIXED |
| `lane_strobe` | `tb_unit_addr` | 偏移 0/4/60/63 |
| `rank_of` / `calc_mem_bytes_per_channel` | `tb_unit_addr` | CS_STRIDE/CS_BIT/SINGLE、2/4/16 Gbit |
| `make_cmd` / `check_cmd` / `resp_or` | `tb_unit_addr` | 合法、size7、len64、4KB、FIXED、WRAP、对齐、越界、ALLSTRB、narrow |
| `mem_model` 写/读/后门/清空/init | `tb_unit_mem` | 全块/部分 strobe、narrow lane、RANDOM/PATTERN、CFG_RESET_CLEAR_MEM |
| `cfg_ctrl_fsm` | `tb_unit_cfg` | 初始化中止、DONE 后撤销、CFG_SEL、非法状态恢复、复位（FSM 100%） |
| `addr_field_decode` / `apply_addr_hole` | `tb_unit_addr`、`field_decode`、`addr_hole`、`addr_alias*` | CS bit、row 字段、DECERR/ALIAS 空洞 |
| `ddr_async_fifo` / `axi_port_shell_cdc` | `tb_top_cdc`（ratio 1/2/4） | CDC 读写、outstanding、W gap、双端口并发、SLVERR 传播、复位隔离 |

## 7. Spec 第 18、19、21 章

| 条目 | 状态 |
|---|---|
| 18 后续实测参数 | N/A（板级标定，不在仿真模型范围） |
| 19 交付物 | RTL、TB、sim 脚本、docs、覆盖率报告均已提供 |
| 21 假设与待确认项 | 见 `user-guide.md` §7 与 `plan.md` §10 |

---

## 8. 未覆盖/待补清单

1. `core_scheduler.sv:148`/`:171` 的调度器 tie-break 冗余扫描分支无合法激励命中（2/376 branch），不影响功能；保留豁免或后续用形式化证明；
2. `ddr_fifo.sv:26/27`（`full`/`empty` 连续赋值）在部分实例中未触发，statement 10/12，属工具计数伪缺口；
3. `SYNC_LATENCY`/`ARB_LATENCY` 未建模（spec 明确为参考值）；
4. 功能 covergroup cross 未裁剪（132/324 bins = 40.7%），可删除不可达组合后提升；
5. WDATA 保持、4KB/Table5/ALLSTRB 的 SVA 尚未补齐（当前由定向测试检查）；
6. 板级标定读/写/BVALID 延迟（按 `ddr-test-spec-v0.2.md`）。

已补齐：异步 CDC（1:1/2:1/4:1）、OOO 读响应与同 ID 保序、R beat 交织、地址字段解码与空洞策略、CFG FSM 单元测试、端口复位中断事务、`R_BEAT_INTERVAL`/`W_ACCEPT_INTERVAL` 定向用例、系统级 `CFG_RESET_CLEAR_MEM`、仲裁 one-hot/间隔 SVA、ERR_INJECT 双端口、WLAST 早返错误、50-seed 随机压力。
