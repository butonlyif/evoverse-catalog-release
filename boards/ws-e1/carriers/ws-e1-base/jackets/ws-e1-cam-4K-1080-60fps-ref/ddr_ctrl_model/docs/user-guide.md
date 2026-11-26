[English](user-guide.en.md) | 中文

# TJ DDR AXI 行为模型用户手册

**文档编号**：UG-DDR-AXI-MODEL-v0.3
**实现基线**：SPEC-DDR-AXI-MODEL-v0.2（**v0.2e**，含 correlation Phase 0-8 板级标定）/ PLAN-DDR-AXI-MODEL-v0.1
**仿真器**：QuestaSim 2024.2
**日期**：2026-10-21（v0.2）/ 2026-10-23（v0.3，与 spec v0.2e 基线同步）
**状态**：v0.2 功能模型（同步 + 异步 CDC、OOO、字段解码/地址空洞），回归 60/60 通过（Phase 8 基线固化），random_stress 50 seeds 通过；BVALID 时机、延迟、仲裁适用域等参数语义已按板级标定更新（v0.2a-e）

> **v0.3 修订要点**（对照 spec v0.2a-e）：`AWCACHE=0000` 非早返定稿、B 时机 = `AWCACHE[0]` bit0 规律；`READ_LATENCY_MIN/MAX`=191/492、`WRITE_DATA_TO_B_LATENCY`=451、`BVALID_CMD_QUEUE_DELAY`=28 板级回填；`ARB_GRANT_INTERVAL`/`ARB_QUIET_FAST_PATH` 标注仅 `CDC_ENABLE=0` 路径生效；回归目录/跑法更新为 `tb/regress.sh` + `testlist.txt`（60 用例）。

---

## 1. 概述

`model/` 实现了一个用于 SoC/FPGA 系统仿真的 TJ 系列 DDR 硬核控制器 AXI 从端行为模型。模型覆盖：

- 2 个 AXI4 从接口（target 0/1），33-bit 地址、512-bit 数据、64-bit WSTRB、6-bit ID；
- AW/W/B/AR/R 通道，INCR/WRAP burst、narrow transfer、WSTRB；
- 共享命令队列、双端口 round-robin 仲裁、每端口 outstanding 限制；
- 参数化读延迟、写响应延迟、BVALID 时机；
- 可选的异步 CDC（1:1、2:1、4:1 及 ACLK 慢时钟），AXI 端口与控制器核心可不同频；
- 可选的乱序响应（`OUT_OF_ORDER_ENABLE`）：读按 deadline 返回，同端口同 ID 保持顺序，`R_INTERLEAVE_ENABLE` 支持 burst 交织；
- 地址字段解码调试（`ADDR_MAP_MODE=1`）与地址空洞策略（DECERR / ALIAS）；
- CFG_RESET/CFG_START/CFG_SEL/CFG_DONE 初始化握手；
- 稀疏字节存储阵列、容量/rank 解码、地址合法性检查；
- 自检查 BFM、scoreboard、协议断言和定向回归。

模型**不包含** DDR PHY 电气行为、LPDDR4 命令时序、刷新/bank 冲突、training、配置寄存器地址映射，也不保证与真实硬核周期级等价。

## 2. 目录与文件

本项目实际布局（`ddr_ctrl_model/`；原交付规划中的 `model/sim/` 已由 `tb/` 取代）：

```text
ddr_ctrl_model/
├─ rtl/
│  ├─ ddr_model_pkg.sv        枚举、结构体、burst/4KB/lane/rank 函数
│  ├─ ddr_model_if.sv         AXI 接口（TB 使用）
│  ├─ ddr_fifo.sv             同步 FIFO
│  ├─ ddr_async_fifo.sv       双时钟 gray 指针异步 FIFO
│  ├─ mem_model.sv            稀疏字节存储 + 后门
│  ├─ cfg_ctrl_fsm.sv         CFG 初始化状态机
│  ├─ axi_port_shell.sv       每端口通道握手、W/B/R FIFO、outstanding
│  ├─ axi_port_shell_cdc.sv   跨时钟端口外壳（CDC_ENABLE=1 使用）
│  ├─ core_scheduler.sv       读写命令调度、存储访问、B/R 生成
│  ├─ ddr_axi_model_top.sv    扁平端口顶层（DUT）
│  └─ ddr_model_assertions.sv 第一批 SVA
├─ tb/
│  ├─ tb_pkg.sv               数据/地址 pattern 函数
│  ├─ axi_master_bfm.sv       AXI master BFM（含 outstanding/多命令探针）
│  ├─ tb_scoreboard.sv        期望存储与读数据检查
│  ├─ tb_top.sv               定向测试主平台（同步，48 用例）
│  ├─ tb_top_cdc.sv           多时钟测试平台（CDC，9 用例）
│  ├─ tb_unit_mem.sv          存储单元测试
│  ├─ tb_unit_addr.sv         地址/burst/错误单元测试
│  ├─ tb_unit_cfg.sv          CFG 状态机单元测试
│  ├─ testlist.txt            基线用例表（top|test|-g 参数映射，60 项）
│  └─ regress.sh              一键回归（编译 + 全量用例 + 汇总退出码）
├─ proj/                      板级工程（Efinity 项目、抓帧/调试资料）
└─ docs/
   ├─ user-guide.md           本文件
   ├─ traceability.md         spec → RTL → 测试追溯
   └─ coverage/               merged.ucdb、HTML、文本摘要
```

## 3. 快速开始

在 `ddr_ctrl_model/tb` 目录下（Questa `vlog/vsim` 需在 PATH）：

```bash
# 全量回归（编译 + 60 用例 + PASS/FAIL 汇总，退出码即门禁）
bash regress.sh

# 单个测试（先经 regress.sh 编译出 work 库再单跑；带 -g 的用例从 testlist.txt 取参数）
vsim -c +TEST=wr_single -do "run -all; quit -f" work.tb_top

# 多时钟测试
vsim -c +TEST=cdc_smoke -do "run -all; quit -f" work.tb_top_cdc

# random_stress 多 seed 附证（-sv_seed 2..51 共 50 个）
bash seeds_stress.sh
```

`testlist.txt` 每行 `top|test|附加参数`，是基线唯一权威跑法：带 `-g` 的用例（如 `addr_hole` 需 `-gADDR_MAP_MODE=1` + 窗口、`rdataq_full` 需 `-gREAD_OSTD_DEPTH=32`、`init_slverr` 需 `-gINIT_AXI_RESP=1`）参数映射已固化，**勿凭记忆手工重推**（correlation Phase 8 教训：手工重推曾引入窗口值 16 倍偏差与参数语义错位）。

每个测试输出 `TEST <name> PASS` 或 `TEST <name> FAIL`，失败时 `$fatal` 返回非零退出码。回归日志保存在 `tb/regress_logs/`。

## 4. 顶层接口

顶层 `ddr_axi_model_top` 使用扁平端口，与 spec 第 5 章及硬核引脚一致。

| 组 | 信号 | 说明 |
|---|---|---|
| 时钟 | `ctrl_clk` | 核心时钟 |
| | `ACLK_0/1` | AXI 端口时钟；`CDC_ENABLE=0` 时必须与 `ctrl_clk` 同源同频，`CDC_ENABLE=1` 时可异步（1:1/2:1/4:1 或慢时钟，见 `tb_top_cdc`） |
| 复位 | `ARSTN_0/1` | 低有效异步端口复位，复位端口外壳与 FIFO，存储保留 |
| | `CFG_RESET` | 高有效全局复位，至少 5 个 `ctrl_clk` |
| CFG | `CFG_START`、`CFG_SEL`、`CFG_DONE` | `CFG_SEL` 低有效；DONE 后 START 必须保持高 |
| AXI0/1 | AW/W/B/AR/R 全通道 | 33-bit 地址、512-bit 数据、6-bit ID、64-bit WSTRB |
| 状态 | `CTRL_INIT_DONE/READY/BUSY/ERR` | `ENABLE_CTRL_STATUS=1` 时有效；ERR 粘滞到 CFG_RESET |

AW 侧边带（`AWLOCK/AWAPCMD/AWQOS/AWCACHE/AWALLSTRB/AWCOBUF`）与 AR 侧边带（`ARLOCK/ARAPCMD/ARQOS`）均存在。`AWAPCMD/ARAPCMD/AWLOCK/ARLOCK/AWQOS/ARQOS` 在 v0.2 中被接受但不影响行为。

## 5. 主要参数

### 5.1 结构与容量

| 参数 | 默认 | 说明 |
|---|---|---|
| `DATA_WIDTH` | 32 | DRAM 数据位宽（x16/x32） |
| `AXI_DATA_WIDTH` | 512 | 固定 |
| `MEM_DENSITY_GBIT` | 4 | 每通道密度（Gbit） |
| `GBIT_BINARY` | 1 | 1=2^30，0=10^9 |
| `PHYSICAL_RANK` | 1 | rank 数 |
| `NUM_AXI_TARGETS` | 2 | 固定 2 |
| `SUPPORT_WRAP_BURST` | 1 | WRAP 支持 |
| `SUPPORT_NARROW` | 1 | narrow 支持 |
| `SUPPORT_FIXED_BURST` | 0 | FIXED 默认拒绝 |
| `SUPPORT_AWALLSTRB` | 1 | AWALLSTRB 16-beat 限制 |
| `RANK_MAP_MODE` | 1 | 0=SINGLE_RANK，1=CS_STRIDE，2=CS_BIT |
| `CS_BIT_POS` | -1 | CS_BIT 模式下的地址位 |
| `ADDR_MAP_MODE` | 0 | 0=LINEAR，1=FIELD_DECODE_DEBUG（提供 `DBG_FIELDS` 解码输出） |
| `ADDR_CS_BIT_POS` | 27 | 字段解码的 chip-select 位，决定 row 宽度 |
| `ADDR_HOLE_POLICY` | 0 | 地址空洞策略：0=DECERR，1=ALIAS 到线性空间 |
| `ADDR_HOLE_START/END` | 0/0 | 空洞窗口，半开区间 `[START, END)`；`END<=START` 时关闭 |
| `CDC_ENABLE` | 0 | 1=每个 AXI 端口独立时钟域，经 gray 指针异步 FIFO |
| `MEM_INIT_MODE` | 0 | 0=ZERO，1=RANDOM，2=PATTERN |
| `MEM_INIT_SEED` | 1 | RANDOM 模式种子 |

`MEM_BYTES = (MEM_DENSITY_GBIT × 2^30 / 8) × (DATA_WIDTH / 16) × PHYSICAL_RANK`（`GBIT_BINARY=1` 时）。默认 4Gbit × x32 × 1 rank = 1 GiB，与 33-bit 地址空间匹配。

### 5.2 队列、仲裁与 outstanding

| 参数 | 默认 | 说明 |
|---|---|---|
| `CMD_QUEUE_DEPTH` | 8 | 每方向命令 FIFO 深度（命令条目） |
| `WRITE_DATA_QUEUE_DEPTH` | 16 | 每端口 W beat FIFO 深度 |
| `READ_DATA_QUEUE_DEPTH` | 16 | 每端口 R beat FIFO 深度 |
| `WRITE_OSTD_DEPTH` | 8 | 每端口写 outstanding |
| `READ_OSTD_DEPTH` | 8 | 每端口读 outstanding |
| `ARB_GRANT_INTERVAL` | 2 | 端口竞争时 grant 最小间隔；**仅 `CDC_ENABLE=0`（g_sync）路径生效**，CDC 形态为固定 1:1 交替收集（每方向每拍最多 1 条入共享队列），Phase 4 标定 G=2/G=8 表征逐位相同 |
| `ARB_QUIET_FAST_PATH` | 1 | 单端口安静时每周期可服务；同上仅 g_sync 路径生效 |
| `B_FIFO_DEPTH` | 8 | 每端口写响应 FIFO 深度 |
| `OUT_OF_ORDER_ENABLE` | 0 | 1=允许不同 ID 的 B/R 乱序返回（同端口同 ID 保序） |
| `R_INTERLEAVE_ENABLE` | 0 | 1=允许不同读 burst 的 R beat 交织（需 OOO 使能） |

### 5.3 延迟与 BVALID

| 参数 | 默认 | 说明 |
|---|---|---|
| `LATENCY_MODE` | 0 | 0=UNIFORM，1=FIXED（取 MIN） |
| `LATENCY_SEED` | 1 | xorshift32 种子，CFG_RESET 时重装 |
| `READ_LATENCY_MIN/MAX` | **191/492**（标定） | 读首拍延迟范围；Phase 2 板级回填（原 ENG 10/30） |
| `R_BEAT_INTERVAL` | 1 | 同 burst 相邻 R beat 最小间隔 |
| `WRITE_RESP_LATENCY_MIN/MAX` | 8/24 `[ENG]` | `T_AW_B` 排队抖动分量；`AWCACHE[0]=0` 编码实际由 `WRITE_DATA_TO_B_LATENCY` 支配 |
| `WRITE_DATA_TO_B_LATENCY` | **451**（标定） | 非早返编码下 WLAST→B 的附加延迟；Phase 2 板级回填（原 ENG 4） |
| `BVALID_CMD_QUEUE_DELAY` | **28**（标定） | 早返编码（`AWCACHE[0]=1`，含 `1111+cobuf`）命令接受→BVALID 延迟；Phase 5 板级回填（原 ENG 2） |
| `BVALID_PHY_ISSUE_DELAY` | 2 `[ENG]` | 仅 `OTHER_AWCACHE_POLICY=PHY_ISSUE` 兜底策略使用；默认策略不触发 |
| `W_ACCEPT_INTERVAL` | 1 | W beat 最小接受间隔 |
| `OTHER_AWCACHE_POLICY` | 0 | 兜底策略，**仅对 `AWCACHE[0]=0` 编码生效**：0=DATA_DONE（板级一致，默认），1=CMD_QUEUE，2=PHY_ISSUE（早返）；`AWCACHE[0]=1` 一律早返，不受此参数影响 |
| `AWCOBUF_STRICT` | 1 | 非 1111/0000 且 COBUF=1 时置粘滞错误；Phase 5 实测 COBUF 对 B 时机无独立效应，STRICT 保守保留 |
| `ERR_INJECT_RATE` | 0 | 0–100，按百分比把整条命令强制为 SLVERR |

> 板级 9 编码矩阵实测（correlation Phase 5）：**BVALID 时机由 `AWCACHE[0]`（Bufferable）单独决定**，`AWCOBUF` 无独立效应；`1111` 裸值（COBUF=0）板级 AW/W 死锁不可测，模型按 bit0 规律早返。详见 spec §6.5 与 correlation-plan §9。

### 5.4 CFG

| 参数 | 默认 | 说明 |
|---|---|---|
| `INIT_CYCLES` | 1000 | 初始化计数 |
| `INIT_AXI_BLOCK` | 1 | 初始化期间阻塞 AXI |
| `INIT_AXI_RESP` | 0 | 0=BACKPRESSURE，1=SLVERR；**仅 0/1 有效**，其他值（如 2）使阻塞与 SLVERR 双双失效、事务被当普通写接受（Phase 8 勘误） |
| `CFG_RESET_CLEAR_MEM` | 0 | CFG_RESET 是否清空存储 |
| `ENABLE_CTRL_STATUS` | 0 | 是否驱动状态输出 |

## 6. 行为要点

### 6.1 写地址与写数据

- `AWREADY = ARSTN && !init_block && AWVALID && (WVALID || W FIFO 非空) && wr_ostd < 深度 && cmd_space`。
- 模型要求 AW 与 W 同时出现，或该端口的 W 数据已提前进入 FIFO；仅 `AWVALID` 时 `AWREADY` 保持低（`aw_waits_wvalid`）。
- W 可以先于 AW；W beat 以 `WLAST` 分组，AW 到达后按端口顺序匹配。
- `WREADY` 只依赖复位、初始化阻塞和 W FIFO 空间，不依赖 AW。

### 6.2 BVALID 时机

时机由 `AWCACHE[0]`（Bufferable）bit0 单独决定（板级 9 编码矩阵实测，correlation Phase 5 定稿）：

| 条件 | BVALID 时机 |
|---|---|
| `AWCACHE[0]=1`（含 `1111`±COBUF、`0001/0011/0111`） | 早返：`AW_accept + BVALID_CMD_QUEUE_DELAY`（28，标定），**可早于 WLAST**；COBUF 无独立效应 |
| `AWCACHE[0]=0`（含 `0000`、`0010/0100/1110`） | 非早返：`max(AW_accept + lat, WLAST + WRITE_DATA_TO_B_LATENCY)`（451，标定）；板级与 0000 同形（WA/WL 55-99 ACLK） |
| `AWCACHE[0]=0` 且 `OTHER_AWCACHE_POLICY=1/2` | 早返（CMD_QUEUE 28 / PHY_ISSUE 2 兜底策略） |

> v0.2 手册曾写"AWCACHE=0000 走 PHY_ISSUE 早返"，与板级实测不符（0000 全部写数据提交后才返回），已修正——照旧语义写 TB 预期会得到相反结果。

早返 B 不影响 W 通道：`WREADY` 继续接收全部 beat 直到 `WLAST`，存储在 `WLAST` 后提交。错误写（响应非 OKAY）不更新存储。`AWCACHE=1111` 裸值（COBUF=0）板级 AW/W 死锁不可作为基线组合（模型仍按 bit0 规律早返）。

### 6.3 读通路

- `ARREADY` 依赖 `ARVALID`、复位、初始化、`rd_ostd < READ_OSTD_DEPTH` 和命令空间。
- **outstanding 释放在 RREADY 消费 RLAST 时**（`rlast_hs`），不是数据进入 R FIFO 时：master 保持 `RREADY=0` 期间 outstanding 只增不减，AR 接受上限即 `READ_OSTD_DEPTH`——需要长阻塞读数据队列时，AR 吞吐同时受该上限约束（`rdataq_full` 标定要点，Phase 8）。
- 首个 R beat 在 `AR_accept + lat` 后出现；同 burst beat 间隔不小于 `R_BEAT_INTERVAL`。
- narrow 读按字节地址选择 lane，无效 lane 返回 0。
- 错误读仍返回完整 burst，`RRESP` 标记 `SLVERR/DECERR`。
- `OUT_OF_ORDER_ENABLE=0`（默认）：同端口读响应按 AR 顺序返回。
- `OUT_OF_ORDER_ENABLE=1`：每个命令有独立的完成 deadline，R 按 deadline 先后返回；同端口同 ID 的读仍按 AR 顺序（`seq` 比较）。`R_INTERLEAVE_ENABLE=1` 时不同 burst 的 beat 可交错，否则一个 burst 的 beat 连续输出。

### 6.4 地址与 burst 检查

接受命令时组合检查，错误在 B/R 响应中返回：

| 检查 | 响应 |
|---|---|
| `SIZE > 6` | SLVERR |
| Table 5：SIZE=6/5/4 ≤64/128/256 beats；SIZE≤3 ≤256 beats | SLVERR |
| INCR 跨 4KB | SLVERR |
| 起始地址未按 SIZE 对齐 | SLVERR |
| WRAP 长度不是 2/4/8/16 或未对齐 | SLVERR |
| FIXED（默认不支持）或非法 burst 编码 | SLVERR |
| `addr + burst_bytes > MEM_BYTES` | DECERR |
| `AWALLSTRB=1` 且 beat 数 >16，或任一 WSTRB 非全 1 | SLVERR + 粘滞错误 |
| 字段解码窗口内（`ADDR_MAP_MODE=1` 且命令与 `[ADDR_HOLE_START, ADDR_HOLE_END)` 相交） | policy=0: DECERR；policy=1: 地址别名到线性空间 |

`AWLEN/ARLEN` 为 8 bit，最大 255（256 beats）。

字段解码模式（`ADDR_MAP_MODE=1`）把最后一条被接受命令的地址拆成
`CS[ADDR_CS_BIT_POS]`、`ROW[ADDR_CS_BIT_POS-1:12]`、`BANK[11:9]`、
`COLUMN[8:2]`、`DATAPATH[1:0]`，通过 `DBG_FIELDS`/`DBG_FIELDS_ADDR` 输出，仅用于调试，
不改变存储地址（除非命中地址空洞）。ALIAS 策略把 `addr >= hole_start` 的命令映射到
`addr - hole_start`，起点低于空洞的跨洞 burst 映射到 `addr % MEM_BYTES`。

### 6.5 CFG 初始化

`CFG_RESET` 有效时 `CFG_DONE=0`；释放后等待 `CFG_START=1`，计数 `INIT_CYCLES` 后 `CFG_DONE=1`。`CFG_SEL=1` 时 `CFG_DONE=0`，释放后重新初始化。`CFG_DONE` 有效期间 `CFG_START` 必须保持高。初始化期间 `INIT_AXI_BLOCK=1` 时 AXI 地址通道被反压（`INIT_AXI_RESP=0`）或返回 SLVERR（`INIT_AXI_RESP=1`）。

### 6.6 端口复位

`ARSTN_x=0` 复位该端口外壳、W/B/R FIFO 和 outstanding 计数；核心丢弃该端口未完成命令，存储内容保留。另一端口不受影响。

## 7. `[MODEL]` 偏差与已知限制

1. **时钟**：`CDC_ENABLE=0` 时所有逻辑运行在 `ctrl_clk`，`ACLK_0/1` 必须接同一时钟；`CDC_ENABLE=1` 时端口外壳在各自 `ACLK_x` 域，命令/数据/响应经双时钟 gray FIFO，CDC 模式下不使用共享命令 arbiter（每个端口各自维护队列）。
2. **OOO / 读交织**：`OUT_OF_ORDER_ENABLE=1` 时 B/R 按 deadline 乱序（同端口同 ID 保序）；`R_INTERLEAVE_ENABLE=1` 时 R beat 可跨 burst 交织。默认关闭，行为与硬核的按序模式一致。
3. **错误注入**：`ERR_INJECT_RATE` 在命令接受时按百分比注入 `SLVERR`（整条命令，含所有 beat），注入写不更新存储；`err_inject` 用 100% 验证。
4. **存储未写地址**：稀疏数组按 `MEM_INIT_MODE` 惰性返回 0 / hash / 地址 pattern；这不是真实 DRAM 上电内容，属于 `[MODEL]` 偏差。
5. **FIXED burst**：默认拒绝（SLVERR），与 UG 一致；不建模固定地址重复访问。
6. **Narrow 读无效 lane**：返回 0；真实硬核可能返回未定义/上一次数据。
7. **AWCOBUF 严格模式**：`AWCOBUF_STRICT=1` 时非 1111/0000 cache 的 COBUF 写会置粘滞 `CTRL_ERR`，用于捕获非法组合。
8. **初始化期间行为**：`INIT_AXI_BLOCK`/`INIT_AXI_RESP` 提供两种简化模型，未覆盖手册全部细节。
9. **字段解码**：`DBG_FIELDS` 是调试辅助，字段位宽随 `ADDR_CS_BIT_POS` 变化，不对应真实 DRAM 地址映射；地址空洞策略是显式的 `[MODEL]` 扩展。
10. **无 PHY 时序**：不建模 tRCD/tRP/刷新/bank 冲突，读写延迟由参数或 RNG 给出。
11. **状态输出**：`CTRL_BUSY` 为读写引擎活动指示，仅用于调试。
12. **越界地址行为（documented deviation，Phase 7）**：模型对 `addr + burst_bytes > MEM_BYTES` 返回 DECERR（保护方向）；板级真核实测为**静默回绕**（除 1 GiB 孤点）。以模型做越界防护检查会得到比真核更严格的结果。
13. **带宽效率（documented deviation，Phase 1/2/4）**：模型为理想服务时序，绝对吞吐与真核存在 ~2.2x 差（含 ACLK/ctrl 时钟比）；双口退化比在饱和档模型偏保守（1.19x vs 板 1.00x）、首轮瞬态偏乐观（1.03x vs 板 1.72x）。性能预测请以 correlation-plan §9 的标定数据为修正基准。

## 8. 测试平台

### 8.1 BFM 能力

`axi_master_bfm` 提供：

- `wr_txn(...)`：支持 cache/cobuf/allstrb/strb_mode/wfirst/pause_after_first，`wlast_mode` 可注入早/缺失 WLAST；
- `wr_aw_late_w(...)`：验证仅 AWVALID 时 AWREADY 为低；
- `rd_txn(addr, len, size, burst, id, data[], resp[])`；
- `wr_ostd_probe(depth, base, accepted, blocked)`：预装 W 数据、填满写 outstanding、检查 AW 阻塞和 BID 顺序；
- `rd_ostd_probe(depth, base, accepted, blocked)`：RREADY 保持低、填满读 outstanding、检查 AR 阻塞和 RID 顺序；
- `wr_multi_probe(n, addrs, ids, done_order, ok)` / `rd_multi_probe(...)`：一次发出多个命令，捕获 B/R 返回顺序，用于 OOO、同 ID 保序和多队列仲裁测试；
- `cmdq_probe(...)`、`wdataq_probe(...)`、`rdataq_probe(...)`：分别填满命令队列、W 数据队列、R 数据队列并检查反压与排空；
- `cg_wr`/`cg_rd` 功能 covergroup：burst 类型、len/size、响应、cache/cobuf、W-first、WSTRB、读 burst。

所有握手均有 20000 周期超时；`tb_top` 有 5 ms、`tb_top_cdc` 有 20 ms 全局 watchdog。

### 8.2 Scoreboard

- 维护稀疏期望存储；写事务在 B=OKAY 后按 beat/WSTRB 更新；
- 读事务按 64-byte 块和 lane 比较，无效 lane 期望 0；
- 检查 BID/BRESP、RID/RLAST/RRESP；
- 早返 B 以 WLAST 为提交点。

### 8.3 断言

`ddr_model_assertions` 覆盖：READY 必须伴随 VALID、VALID 保持到握手、B/R VALID 稳定、WLAST/RLAST 合法性、`CFG_DONE→CFG_START`、CFG_RESET 清 DONE、DONE 粘滞、CFG_RESET 最小宽度、B/R 不早于对应命令握手、仲裁器单 grant / 竞争间隔。断言失败会计入 Questa 错误数并使回归失败。

### 8.4 用例清单

| 用例 | 覆盖点 |
|---|---|
| `smoke` / `smoke_reset` | 复位输出、CFG 完成、状态信号 |
| `smoke_cfg` | CFG_DONE 保持 |
| `init_block` | 初始化期间 AWREADY 反压，CFG_DONE 后完成写 |
| `init_slverr` | `INIT_AXI_RESP=1` 时初始化期间写返回 SLVERR 且不改存储 |
| `cfg_sel` | CFG_SEL 拉高清除 DONE、释放后恢复 |
| `wr_single` | 单 beat 写 + 回读 |
| `wr_incr` | 4 beat INCR 写 |
| `wr_wstrb` | 0x55/0xAA、全 0、部分字节 strobe |
| `wr_w_before_aw` | W 先于 AW |
| `aw_waits_wvalid` | 仅 AWVALID 时 AWREADY 低 |
| `early_b` | `1111`+COBUF 早返 B（`AWCACHE[0]=1`），W 数据完整；`0000` 验证**非早返**（v0.2a 定稿） |
| `bvalid_modes` | 其他 cache + policy=1 早返；DATA_DONE 不早返 |
| `wr_errors` | 4KB、Table 5、SIZE=7、FIXED 错误响应 |
| `allstrb` | 16 beat 通过、17 beat 错误、全 0 WSTRB 错误 |
| `reads` | 单拍/INCR/narrow/WRAP/4KB/越界错误读 |
| `dual_port` | 双端口并发写、交叉读 |
| `ostd_wr` | 写 outstanding=2 时 AW 阻塞、B 顺序 |
| `ostd_rd` | 读 outstanding=2 时 AR 阻塞、R 顺序 |
| `latency` | 读延迟落在参数范围 |
| `lat_equal` | 固定读延迟 6 时双端口读延迟一致 |
| `lat_fixed` | FIXED 模式延迟可复现 |
| `r_gap` / `w_gap` | `R_BEAT_INTERVAL>1` / `W_ACCEPT_INTERVAL>1` 的 beat 间隔 |
| `port_reset` | 端口 0 复位隔离、恢复后读写 |
| `port_reset_mid` | 进行中事务被端口复位中断，另一端口与存储不受影响 |
| `cfg_clear_mem` | `CFG_RESET_CLEAR_MEM=1` 时 CFG_RESET 清空存储 |
| `cmdq_full` | 命令队列满时 AWREADY 反压、排空后继续、B 顺序 |
| `wdataq_full` | W 数据 FIFO 满时 WREADY 反压、AW 后续匹配 |
| `rdataq_full` | R 数据 FIFO 满时读停顿、读命令队列满时 ARREADY 反压 |
| `arb_fairness` | 双端口竞争时双方均获 grant、单 grant 断言、竞争间隔 |
| `err_inject` | `ERR_INJECT_RATE=100` 时双端口读写均 SLVERR、写不改存储 |
| `random_stress` | 40 笔随机读写（随机 len/size/strobe/W-first/暂停）+ scoreboard |
| `wlast_err` | 早 WLAST / 缺失 WLAST → SLVERR + 粘滞错误；`0000`（非早返路径）缺失 WLAST 时 B 随 SLVERR 返回 |
| `cobuf_strict` | 非 1111/0000 cache + COBUF → 粘滞错误，数据仍写入 |
| `allstrb_early` | `0000` 非早返路径：坏 WSTRB → **SLVERR + CTRL_ERR 粘滞**（v0.2a 定稿后与旧"早 B 保持 OKAY"语义相反） |
| `dual_multi` | 双端口同时长 burst 写，两个未完成写上下文并存 |
| `dir_arb` | 同端口 AW+AR 同时请求，双向仲裁轮转 |
| `contend_multi` | 双端口各排 4 条命令，验证 grant 间隔与逐条服务 |
| `ooo_same_id` / `ooo_diff_id` / `ooo_interleave` | OOO 读调度：同 ID 保序、不同 ID 按 deadline、R beat 交织 |
| `ooo_b_same_id` | OOO 下同端口同 ID 写保序，BID 正确 |
| `field_decode` | FIELD_DECODE_DEBUG：CS bit 与 row 字段解码 |
| `addr_hole` | 地址空洞 DECERR 策略 |
| `addr_alias` | 地址空洞 ALIAS 映射与回读 |
| `addr_alias_cross` | 起点低于空洞、跨入空洞的 burst 按 ALIAS 映射并回读 |
| `cdc_smoke` / `cdc_dual` / `cdc_ostd` / `cdc_stress` / `cdc_rst` | CDC 时钟比 1:1/2:1/4:1：读写、outstanding、双端口并发、端口复位隔离 |
| `cdc_slow` | ACLK 慢于 ctrl_clk（`CDC_ACLK_SLOW=1`）下的基本读写 |
| `cdc_wgap` | 异步 CDC 下 `W_ACCEPT_INTERVAL` 在 ACLK 域生效 |
| `cdc_contend` | 异步 CDC 下双端口各 4 条读写命令并发完成 |
| `cdc_err` | 异步 CDC 下错误注入的 SLVERR 传播和 CTRL_ERR |
| `tb_unit_cfg` | CFG FSM：初始化中止、DONE 后 START 撤销、非法状态恢复、复位 |
| `tb_unit_addr` | burst/Table5/4KB/WRAP/对齐/rank/check_cmd |
| `tb_unit_mem` | 字节 strobe、narrow lane、init 模式、后门、清空 |

## 9. 回归与覆盖率结果

**Phase 8 基线（2026-10-23，`bash regress.sh` 一键复现）**：

```
Regression: 60 passed, 0 failed (tb_top 48 + tb_top_cdc 9 + tb_unit 3；跑法固化 tb/regress.sh + testlist.txt)
Stress: 50/50 seeds passed (random_stress, -sv_seed 2..51)
```

覆盖率（开发期基线，2026-10-21 收取；Phase 8 未重收，`COV=1` 入口已随 regress.sh 重写移除，重收方法见 §11）：

| 范围 | Branch | Condition | Statement |
|---|---|---|---|
| 顶层 `ddr_axi_model_top` | 86/86 = 100% | 36/43 = 83.7% | 135/135 = 100% |
| RTL 源文件合计（10 个文件） | 374/376 = 99.47% | 164/197 = 83.25% | 597/599 = 99.67% |
| 全部实例（含 TB/接口/断言） | 1190/1767 = 67.34% | 340/1310 = 25.95% | 3885/5479 = 70.90% |

逐文件（`docs/coverage/rtl_summary.txt`）：

| 文件 | Branch | Condition | Statement |
|---|---|---|---|
| `axi_port_shell` | 16/16 | 1/1 | 23/23 |
| `axi_port_shell_cdc` | 18/18 | 1/1 | 27/27 |
| `cfg_ctrl_fsm` | 14/14 | 1/1 | 16/16 |
| `core_scheduler` | 107/109 | 64/81 | 190/190 |
| `ddr_async_fifo` | 16/16 | — | 41/41 |
| `ddr_axi_model_top` | 86/86 | 36/43 | 135/135 |
| `ddr_fifo` | 10/10 | 2/2 | 10/12 |
| `ddr_model_assertions` | 26/26 | 21/23 | 22/22 |
| `ddr_model_pkg` | 68/68 | 36/42 | 107/107 |
| `mem_model` | 13/13 | 2/3 | 26/26 |

FSM：`tb_top/dut/u_cfg`、`tb_top_cdc/dut/u_cfg`、`tb_unit_cfg/dut` 各 3/3 状态、4/4 迁移，合计 9/9 + 12/12 = 100%（见 `docs/coverage/fsm.txt`）。

功能覆盖：8 个 BFM covergroup 实例，132/324 bins = 40.74%（cross 中大量不可达组合未裁剪）。

断言：28 个并发断言，0 failure；实例化展开后 56 个 bin 中 43 个触发，13 个前置条件未命中（真空成功）。覆盖 READY→VALID、VALID 保持、B/R 稳定、WLAST/RLAST、CFG_DONE→START、CFG_RESET 清 DONE/最小宽度、B/R 不早于命令握手、仲裁 one-hot 和 grant 间隔。

**PLAN P7 目标（branch/statement ≥95%）已达成**：RTL 源文件合计 branch 99.47%、statement 99.67%。剩余 2 个 branch 为 `core_scheduler.sv:148/171` 的 tie-break 冗余扫描路径，无合法激励命中且不影响功能；`ddr_fifo` 2 个 statement 为 `full`/`empty` 连续赋值的计数伪缺口。见 `model/docs/traceability.md` §8。全部实例口径包含 TB/接口/断言，不能直接与 RTL 目标比较。

## 10. 已知问题与后续工作

- `core_scheduler.sv:148/171` 的两个 tie-break 冗余扫描分支无合法激励命中（2/376 branch），不影响功能，保留豁免或后续形式化证明；
- `ddr_fifo` 的 `full`/`empty` 连续赋值在部分实例中未触发，statement 10/12 属工具计数伪缺口；
- 功能 covergroup 的 cross 未裁剪（132/324 bins = 40.7%），可删除不可达组合后提升；
- 补充 WDATA 保持、4KB/Table5/ALLSTRB 的 SVA（当前由定向测试检查）；
- `SYNC_LATENCY`/`ARB_LATENCY` 参数保留但未建模；
- ~~板级标定 `READ_LATENCY`、`WRITE_RESP_LATENCY`、BVALID 延迟~~ **已完成**（correlation Phase 0-8，2026-10-23）：`READ_LATENCY_MIN/MAX`=191/492、`WRITE_DATA_TO_B_LATENCY`=451、`BVALID_CMD_QUEUE_DELAY`=28 已回填 RTL；`CMD_QUEUE_DEPTH`/OOO/地址映射/仲裁适用域实测结论见 spec §18 与 correlation-plan §9。

## 11. 复现信息

- QuestaSim 2024.2（`vlog`/`vsim`/`vcover` 可用；Git Bash/WSL 均可跑 `tb/regress.sh`）；
- 回归入口：`cd ddr_ctrl_model/tb && bash regress.sh`（逐文件 `vlog -sv -work work` 编译，等价旧 `-f filelist.f`）；
- 随机性基线：TB `$urandom` 未播种（Questa 默认 seed）+ 模型 `LATENCY_SEED=1`；多 seed 用 `vsim -sv_seed <n>`（`bash seeds_stress.sh` 扫 50 个）；
- 带参数用例的 `-g` 映射以 `tb/testlist.txt` 为唯一权威；
- 日志：`tb/regress_logs/`；
- 覆盖率数据库：`docs/coverage/merged.ucdb`（开发期基线）。重收方法：`vlog -sv -lint -cover bcsxf` 编译、逐用例 vsim 落 UCDB、`vcover merge -out merged.ucdb tb runs/*.ucdb` 后 `vcover report -html`。
