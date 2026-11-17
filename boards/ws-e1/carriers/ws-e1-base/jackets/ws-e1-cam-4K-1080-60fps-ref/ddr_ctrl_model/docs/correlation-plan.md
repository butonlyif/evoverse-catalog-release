[English](correlation-plan.en.md) | 中文

# 模型 ↔ 板级 DDR 控制器 Correlation 方案

**目标**：用同一套流量生成（TG）与统计（APM）RTL，分别在仿真（`ddr_axi_model_top`）和板级（TJ180 DDR 硬核）上运行，对比行为并回填模型参数。
**依据**：`../ddr-test-spec-v0.2.md`（测试组件规格，下称"测试 spec"）、`../axi-ddr-model-spec-v0.2.md`（模型规格，下称"模型 spec"）
**关联工程**：`../proj/`（独立最小 DDR 测试工程，见 §5）
**日期**：2026-10-22

---

## 1. 核心方法学：一份 RTL 跑两边

传统做法是"板级测一组数、仿真另写一组 TB"，两边口径不同，对比结果不可信。本方案强制：

1. **TG/APM 只写一份 RTL**，参数化后同时例化在：
   - 仿真侧：新 TB `proj/sim/tb_corr.sv`（计划），DUT 为 `ddr_axi_model_top`；
   - 板级侧：`proj/rtl/ddr_test_top.sv`，DUT 为硬核 `ddr_inst`。
2. **流量参数表唯一**：每次实验的 TG 配置（burst len/size、地址步进、outstanding 目标、ID 策略、速率）写进同一份参数表，两边不得各自改。
3. **对比量在 AXI 边界定义**：`T_AR_FIRST_R`、`T_AW_B`、`T_WLAST_B`、`ostd_peak`、`bp_ratio`、`txn_issued/completed`（测试 spec §3.2/§3.3 口径），换算统一按 `CLK_RATIO_ACLK_PER_CTRL`（本项目 x16 器件理想值 0.125，实测频率覆盖）。
4. 差异不是失败，是产出：每条差异记录"现象/证据/处置"，进 §6 清单或直接回填参数。

## 2. 资产映射：测试 spec 组件 → 本项目现有资产

| 测试 spec 组件 | spec 章节 | 本项目对应 | 状态 |
|---|---|---|---|
| TG（流量生成） | §6 | `ddr_memcheck.v`（写 pattern→读回比对 FSM，已是合规 AXI master） | 骨架已有；需扩展 OSTD/ID/速率控制（§3.1） |
| APM（monitor 统计） | §5 | memcheck 内 err_cnt/mcst 计数 + `ddr_status_uart.sv` DIAG 读出 | 部分有；需扩展延迟时间戳/直方图（§3.2） |
| ILA | §7 | Efinity Logic Analyzer（板级专用） | 待配置 |
| 结果读出 | §5.8 | `ddr_status_uart.sv` 13 字节 UART 帧（115200，约 1.2 ms/帧） | 完成 |
| DUT 初始化 | §4 | `cfg_ctrl_fsm` v5（CFG_START 计 2^21 拍≈10.49 ms）+ `reset_ctrl` POR 256 拍 | 完成（照抄 top_cam_demo 板级时序） |
| 隔离工程 | — | `proj/`（peri.xml 裁剪版 + `ddr_test_top.sv`） | 完成，smoke 全绿 |

## 3. TG / APM 改造需求

### 3.1 TG（基于 ddr_memcheck.v）

| 需求 | 现状 | 改造 |
|---|---|---|
| 可编程 burst（LEN/SIZE/地址步进） | 参数 ALEN/ASIZE/START_ADDR/BURST_STEP 固定序列 | 已参数化，够用 |
| OSTD 控制（模式 A：TARGET_OSTD 递增） | 单发单收（arvalid 握手即撤） | 加发拍窗口：连续发 N 条 AR 再收，N 为扫描变量 |
| ID 策略（SINGLE/ROTATE） | 固定 ID | 加 ID 计数器，ID_COUNT 参数化（8.7 OOO 标定必需） |
| 速率控制（FIXED_OSTD/FIXED_RATE） | 背靠背 | 加 INTERVAL_CYCLES 发拍间隔计数器（8.4 扫描用） |
| 4KB 安全地址 | 仿真口径 MC_ALEN=63（64 beat×64B=4096B 压线） | 保留；地址步进生成需 `cross_4kb` 自检（模型 spec `make_cmd` 同款判式） |

### 3.2 APM（基于 memcheck/uart 扩展）

| 需求 | 现状 | 改造 |
|---|---|---|
| `T_AR_FIRST_R` / `T_AW_B` / `T_WLAST_B` 时间戳 | 无 | AXI 边界握手打拍采样，min/peak 累积 |
| 直方图（P50/P95/P99） | 无 | 测试 spec §5.5 bin 结构；**注意 13 字节 UART 帧装不下直方图**——直方图走 ILA 抓取或多帧分片读出，UART 帧只报 min/peak/计数 |
| bp 统计（`AWVALID&&WVALID&&!AWREADY` 真实反压） | 无 | 比特计数 / 窗口周期计数 |
| DIAG 位图（32 bit） | 已有（§5.3） | 复用；扩展统计分多帧轮发（帧内加 seq 字段） |

## 4. 标定流程映射（测试 spec §8 为骨架）

| Phase | spec | 板级操作 | 仿真操作 | 回填参数（模型 spec §6.3/6.4） |
|---|---|---|---|---|
| 0 基线 | §8.1 | 烧 `proj/` 位流，UART 等帧判 `DDR:0000907e`，ILA 旁听粗值 | `tb_proj_smoke.sv` 四项（已绿） | 初始化时序、AWREADY=WVALID 先行确认 |
| 1 OSTD | §8.2 | TG 模式 A，TARGET 1→2→4→8→…，找饱和点+bp>1% | 同参数跑模型 | `READ/WRITE_OSTD_DEPTH_ENG` |
| 2 延迟 | §8.3 | 低负载 min（丢前 100 warm-up）+ 高负载 P99，扫 LEN/SIZE | 同参数 | `READ_LATENCY_MIN/MAX`、`WRITE_RESP_LATENCY_MIN/MAX`、`WRITE_DATA_TO_B_LATENCY`、`SYNC_LATENCY`（多频点拟合，标注拟合值） |
| 3 队列深度 | §8.4 | TG_MODE=3 固定速率读扫描 9 档 ivl{256,128,64,32,16,8,4,2,1}×16 笔 4KB；板级 16 笔内无反压（bp 全 0）、if_peak 饱和=样本上限 16 → `CMD_QUEUE_DEPTH_ENG` 记下界 ≥16，无参数回填（§6-10/§9） | 同参数 tb_proj_qd ALL PASS：blk3(ivl=32) 首反压、if_peak 饱和 8=shell `READ_OSTD_DEPTH` | `CMD_QUEUE_DEPTH_ENG`=下界 ≥16（低置信）；`READ_OSTD_DEPTH` 维持 8（ENG 形态语义） |
| 4 仲裁 | §8.5 | 板级无 ILA → 缩范围对称流量对比：top 双 memcheck 同参 TG_MODE=1 OSTD 扫描（u_mc@target0 报告 + u_mc2@target1 地址错开 32MB 作负载），UART 单报告口（port0）出 16 档 rd_cyc 曲线，vs Phase 1 单口基线（首轮 2741、平台 2284~2317）→ 双口退化比 | tb_proj_arb（CDC_ENABLE=1，ARB_GRANT_INTERVAL=2）双口 16 档全表 ALL PASS：公平比 ≤1.075（门限 1.15）、饱和退化 1.17~1.34x；表征档 G=8 与 g_sync G=2/G=8 证明 `ARB_GRANT_INTERVAL` 在板级 CDC 形态**惰性**（top 仲裁器仅 g_sync 例化；CDC 路径=1:1 交替收集+core_scheduler，§9 Phase 4） | `ARB_GRANT_INTERVAL` 无参数可回填（CDC 形态不生效，spec §18 行已标注）；饱和吞吐板 1.00x vs 模型 1.19x、首轮板 1.72x vs 模型 1.03x → documented deviation（§9） |
| 5 B 时机 | §8.6 | 9 块 `(AWCACHE,AWCOBUF)` 矩阵（1111 裸值死锁不入阵，见 §6-6）：blk0-8 = 0000±cobuf、0001/0010/0011/0100/0111/1110±cobuf，全 LEN=31、ostd=1、×600 笔（丢 100 warm-up） | 同参跑模型（TB 显式 `AWCOBUF_STRICT=0`） | `BVALID_CMD_QUEUE_DELAY`=28（回填）、`OTHER_AWCACHE_POLICY`=bit0 规律+`DATA_DONE` 兜底、`BVALID_TIMING_MODE`=未使用（保留） |
| 6 OOO | §8.7 | TG_MODE=4 背靠背 16 笔×1MB 分散×9 轮，ID_COUNT=8 轮转（每 ID 2 笔）：板级 oo_cnt=0（1079/1081 票）→ 真核**按序完成**，`OUT_OF_ORDER_ENABLE=0` 维持（§9 Phase 6） | 双档：OOO=0 主档 oo_cnt=0 ALL PASS（同形门禁 ✓）；OOO=1 表征档 oo_cnt=12（检测器自证非假阴性） | `OUT_OF_ORDER_ENABLE`=0 维持（板/仿同形，高置信） |
| 7 地址/rank | §8.8 | 板级实锤单 rank 2Gb=256MB（peri.xml）→ rank 边界/CS_BIT/非 2 幂不适用，缩为容量边界+越界回绕探测：TG_MODE=5 九探针 {0, 256M-4K, 256M, 256M+4K, 512M, 1G, 2G, 4G-4K, 4G}，每轮 4 笔串行：写 Yi(=Xi mod 256M) 参考→写 Xi→读 Xi（hi_err）→读 Yi（比对 pattern(Xi)，alias_err==0=回绕污染实锤） | tb_proj_addr ALL PASS：合法探针 (0,0)；越界 2-8 hi=64（模型 SLVERR）、2-7 al=64（写丢弃无污染）、8 al=0（指纹退化） | 无参数可回填：真核越界**静默回绕**（除 1G 孤点 SLVERR）≠模型 DECERR 且模型无回绕模式（§9 Phase 7）；容量 256MB 实测确认 |
| 8 回填 | §8.10 | **完成**：Phase 1-7 逐项定稿（v0.2a-d），无新增 RTL 默认参数替换（延迟/B 时机 4 参数 v0.2a 已回填，其余维持 ENG 形态/惰性/deviation） | traceability 基线回归 **60/60 全绿**（tb_top 48 + tb_top_cdc 9 + tb_unit 3；跑法固化 `tb/regress.sh`+`testlist.txt` 含逐用例 -g 映射）；`random_stress` 追加 -sv_seed 2..51 共 50 seeds 全通过（§9 Phase 8） | spec §22 v0.2e（回归门禁闭环，无参数变更） |

执行顺序建议：0 → 1 → 2 → 5（B 时机影响口径，宜早）→ 3 → 4 → 6 → 7 → 8。

## 5. proj/ 独立工程使用说明

`proj/` 是从 `ws-e1-cam-ddr-csi2-demo` 主工程裁剪出的最小 DDR 测试工程，只保留 DDR 硬核、时钟 PLL 与 UART 读出，目的是让标定 RTL 有一个不含摄像头/显示路径的干净宿主。

### 5.1 目录结构

```text
proj/
├── rtl/                     # 板级 RTL（6 文件）
│   ├── ddr_test_top.sv      # 顶层：POR + CFG FSM v5 + memcheck + UART
│   ├── ddr_memcheck.v       # TG 雏形：写 pattern → 读回比对（已修 ARVALID 握手 bug）
│   ├── ddr_status_uart.sv   # DIAG 读出：13 字节帧 'DDR:'+8hex+'\n'
│   ├── reset_ctrl.sv        # POR 复位链（拷贝自主工程）
│   └── frame_writer/reader  # 备用（未参与 smoke 编译）
├── sim/
│   └── tb_proj_smoke.sv     # 仿真冒烟：DUT=ddr_axi_model_top（口径翻译见 TB 头注释）
├── ws-e1-ddr-test.xml       # Efinity 工程（top=ddr_test_top，6 个设计文件）
├── ws-e1-ddr-test.peri.xml  # 裁剪版 Interface Designer（DDR_0 + 2 PLL + 时钟/GPIO/UART）
├── ws-e1-ddr-test.sdc       # 100M/200M/27M 三钟 + clock_groups
├── work_syn/run_efx_map.sh
└── work_pnr/run_efx_pnr.sh、run_efx_pgm.sh
```

### 5.2 构建与仿真

- **板级构建**：Efinity IDE 打开 `ws-e1-ddr-test.xml`；命令行按 `work_syn/run_efx_map.sh` → `work_pnr/run_efx_pnr.sh` → `work_pnr/run_efx_pgm.sh` 顺序执行。
- **仿真冒烟**（cwd=`proj/sim`，QuestaSim）：

```text
vlog -sv -work work ../../rtl/ddr_model_pkg.sv ../../rtl/ddr_fifo.sv \
     ../../rtl/ddr_async_fifo.sv ../../rtl/mem_model.sv \
     ../../rtl/core_scheduler.sv ../../rtl/cfg_ctrl_fsm.sv \
     ../../rtl/axi_port_shell.sv ../../rtl/axi_port_shell_cdc.sv \
     ../../rtl/ddr_model_assertions.sv ../../rtl/ddr_axi_model_top.sv \
     ../rtl/reset_ctrl.sv ../rtl/ddr_memcheck.v ../rtl/ddr_status_uart.sv \
     ../rtl/ddr_test_top.sv tb_proj_smoke.sv
vsim -c -voptargs="+acc" -do "run -all; quit -f" work.tb_proj_smoke -l tb_proj_smoke.log
```

- **smoke 四项判据**（当前全绿）：
  - P1：CFG_DONE=1，约 10.49 ms（2^21 拍 @200 MHz）；
  - P2：mc_done=1、fail=0、err=0（mcst=9 DONE）；
  - P3：CTRL_ERR=0（无 sticky 协议错误）；
  - P4：UART 连续两帧 `DDR:0000907e`。
- **`TB_DEBUG` 探针**：定义后开启 mem 事务对账与 ARpush/ARpop/RQ 三层字段级打印（correlation 排障用，日常回归不开）。

### 5.3 UART 读出口径（板级判据）

- 帧格式：`'DDR:' + 8 个 hex 字符 + '\n'`，共 13 字节；TX 每字节占 11 bit 时间（filler+start+8data+stop），115200 波特率下帧长 ≈1.128 ms，帧间隔由 `UART_REPORT_TICKS`（默认 2^23 拍 @100 MHz ≈ 84 ms）控制。
- DIAG 位图（32 bit，MSB→LSB）：`{err_cnt[15:0], mcst[3:0], 5'h0, done_raw, cfg_st[1:0], lock, cfg_ok, done, fail}`
  - `err_cnt`：memcheck 比对错误 beat 数；`mcst`：memcheck 状态（9=DONE）；
  - `done_raw`：硬核 `ddr_inst_CFG_DONE`；`cfg_st`：CFG FSM 状态；`lock/cfg_ok`：PLL 锁定/配置完成；`done/fail`：memcheck 完成/失败。
- 全通过帧 = `0x0000907e`（err=0，mcst=9，done_raw=1，cfg_st=3，lock=1，cfg_ok=1，done=1，fail=0）。**上板第一判据：连续多帧稳定输出 `DDR:0000907e`**。
- 注意：读 UART 必须整帧消费 13 字节（含尾 `\n`），否则下一帧错位——仿真 TB 已踩过此坑，上位机脚本同样要处理。
- TG 扫描帧（`UART_SCAN_MODE=1`，Phase 1 起）：8 hex 字符 = `{err_sat[7:0], rd_cyc[15:0], ostd[3:0], tgst[3:0]}`。`ostd` **4'h0=16**（第 16 轮，n6 位）；tgst：9=DONE、A=TG_RD_REQ、B=TG_ROUND_GAP、0=IDLE/CFG。样例 `DDR:0008FC09` = err=0、rd_cyc=2300、ostd=16、DONE（**n5 是 rd_cyc 低位，勿误读为 ostd**）。板级扫描全程 ~58ms 在 bit 加载后跑完，抓帧必须先开抓后烧写（proj 手册 §3.2/§4.1）。

## 6. 已实锤的模型/板级口径差异（首批标定输入）

以下 4 条在 `proj/` smoke 联仿中实证（2026-10-22），标定实验设计必须先消化，板上实验同时逐条验证：

| # | 差异 | 证据 | 处置 | 板级待验证 |
|---|---|---|---|---|
| 1 | **AWCACHE=0000 → B 早返（PHY_ISSUE，AW 握手+2 拍）**：模型按手册实现早返 B；主工程 frame_writer 用 AWCACHE=0000 会比 WLAST 后返 B 的预期提前 | tb_phase4_ddrm 首轮死锁/时序不符 | TB 侧翻译为 AWCACHE=1111+COBUF=0（WLAST+4 基线口径）；板级 B 时机按 8.6 标定。**已闭环**：Phase 2 修为非早返、Phase 5 定稿（手册 PHY 语义与实测不符，见 §6-7/§9 Phase 5） | 已关闭（Phase 5 实测 0000 非早返，B 在数据提交后） |
| 2 | **4KB 规则强制**：模型 `cross_4kb`+`table5_ok` 违例即 SLVERR 且**写数据直接丢弃**（scheduler 仅 resp==OKAY 时 mem_we）；板级硬核对 memcheck 的 3495×7680B 跨 4KB 配置容忍 | smoke P2 err=480→改 MC_ALEN=63（64 beat×64B=4096B 压线）后 err=0 | 性能标定流量统一用 4KB 安全参数；跨 4KB 行为单独按 8.9（风险区）标定 | 硬核对跨 4KB burst 的真实响应（SLVERR？静默容忍？） |
| 3 | **QOS 位宽约定**：peri 接口 QOS 引脚为 1 位（top_cam_demo 隐式声明），模型为 4 位；TB 4 位线直连会高位悬空 | vsim-3015 端口宽度错 | 约定：板级 1 位零扩展 `{3'b000,qos}` 接模型；模型 `ARB_QOS_WEIGHT_EN=0` 下 qos 数值无功能影响 | 确认硬核是否消费 qos（预期否） |
| 4 | **ARVALID 握手纪律**：模型 `arready` 为组合电平（`arstn && arvalid && 未满` 恒可收），ARVALID 多保持 1 拍会被**合法重复接收**（每 AR 收 2 条）；真硬核 arready 握手后撤销，故板测不暴露 | smoke P2 err=192（读流整体错位一个命令）；ARpush 成对出现实锤 | proj 副本 `ddr_memcheck.v` 已修（READ_ADDR 态 `if (arvalid && arready) arvalid <= 1'b0;`）；`rtl/` 原版保留作对照证据；**所有标定 TG 必须遵守"握手完成次拍撤 VALID"** | 无需验证（纪律性问题），但提示模型口径比硬核更"急"，写 OSTD/队列标定时注意 |
| 5 | **理想带宽 vs 真实 DDR 效率**：模型饱和后 ~1046 ACLK/轮（8KB 读，≈1 beat/clk 理想服务），板级硬核饱和后 2300 ACLK/轮（同流量）——绝对吞吐 ~2.2× | 2026-10-22 板级 TG 扫描：ostd≥2 后 rd_cyc 平台 2284~2317（±0.7%），err 全 0（§9 记录） | OSTD 深度参数不背此差异（板/仿饱和点同为 2，门禁 PASS）；绝对吞吐归 Phase 2/3 延迟/效率参数标定 | Phase 2/3：读延迟分布、带宽效率实测 |
| 6 | **AWCACHE=1111 板级 AW/W 死锁**：真硬核对 cache=1111 写命令不完成 AW/W 握手 | Phase 2 首版 MODE2（§8.3-4 基线 1111）板级卡死 PRE_WRITE；`UART_SCAN_MODE=1` 诊断帧直报 mc_state：2933/2933 帧 mcst=2；改 0000 后 mcst=9 2933/2933 | MODE2 写基线定稿 **0000**（memcheck RTL 注，偏离 §8.3-4 已记录）；tb_proj_lat 翻译线改直通（模型与板级同 view） | 已关闭（Phase 5：1111 不入矩阵；`BVALID_TIMING_MODE` 实现未使用，bit0 规律内建） |
| 7 | **板级 B 在写数据提交之后（cache=0000，非早返）**：WA≈WL（±1 拍）且随 LEN 增长（21→57 ACLK），W-first（收完全部 W 才授 AWREADY，t_AW_acc≈t_WLAST_acc） | Phase 2 板级表：低负载 WA/WL 同涨；模型原 cache=0000→早返（PHY_ISSUE）与板级 B 符号相反 | 按 §7-4 B 时机门禁修模型：`cmd_is_early` cache=0000 → 非早返（core_scheduler，B=data_done+WDTB 路径）；写延迟标定口径定 **T_WLAST_B**（板 WA 退化为 ≈WL，模型 WA−WL≈30 拍为 shell 逐拍授 AW 几何差，不可直比） | 已关闭（Phase 5：bit0 规律定稿、`BVALID_CMD_QUEUE_DELAY`=28 回填，见 §9 Phase 5） |
| 8 | **高负载结构差**：板 RD 随 ostd 线性增长（ostd16 min/max 1033/1118 ACLK ≈ 17×64 拍/笔 = DDR 总线串行化），板 WL 随 LEN 增长（21→56 ACLK，PHY 提交 ∝ 数据量）；模型理想服务 + 常数 WDTB 均不可复现 | Phase 2 板/仿对照表（§9 Phase 2）；回填后模型侧 OSTD 饱和点 2→~6，与板级 2 的饱和点门禁和延迟门禁在当前模型结构下不可兼得 | 记录不回填：读排队/写提交时间建模属带宽效率相位（Phase 3 或专项）；`READ_OSTD_DEPTH` 维持 8（Phase 1 结论不受挑战） | 带宽效率相位：每笔 burst 总线占用模型 |
| 9 | **BB（B 早于 WLAST 笔数）口径架构差，不可跨侧对比**：板级 W-first（AWREADY≥WLAST 恒成立，§6-7 实锤）下 B 最早也在 AW 握手后 → BB 恒 0（含早返编码）；模型 shell 非 W-first（逐拍授 AW）→ BB 随早返延迟变化（ENG delay=2 时 bit0=1 块 BB=全部笔数；delay=28 标定形态 B 落 WLAST 后 → BB=0） | Phase 5 板级 9 块 BB 全 0（含 0001/0011/0111 早返块）；模型 delay=28 后 BB 同为 0 | BB 降级为纯记录证据（tb_proj_lat 不判 FAIL）；早返符号判据由 WA/WL 统计承担。**测试 spec §8.6-3 B_BEFORE_WLAST 判定在 W-first 宿主上恒 0，不可作符号判据**（对 §8.6 的偏离，§9 Phase 5 已记录） | 无需板级验证（架构属性，两侧实测已闭环） |
| 10 | **板级无 shell 门控层，OSTD/命令队列深度参数在真核侧无对应物**：板级 TG 直连硬核 peri 接口（`ddr_inst_*`，无 axi_port_shell_cdc），16 笔读全部接受无反压、if_peak 饱和 16=样本上限（TG_N_BURST）；模型 shell `READ_OSTD_DEPTH=8` 融合门控（rd_ostd<8 参与 arready）→ if_peak 封顶 8、blk3(ivl=32) 起反压可观测 | Phase 1 ≥16 并发无反压 + Phase 3 板级 9 档 bp 全 0/if_peak 饱和 16（§9 Phase 3）vs 模型 blk3+ bp 454-882/饱和 8 | `CMD_QUEUE_DEPTH_ENG` 记**下界 ≥16**（置信度低，样本仅 16 笔，§8.4 首反压判据板级不可定义）；`READ_OSTD_DEPTH=8`/`CMD_REQ_DEPTH=4` 维持 ENG 形态语义不回填（Phase 1/§6-8 结论不受挑战）；§7-4 门禁不过按"修口径"处置——参数属 shell/ENG 形态，非真核可观测参数 | 真核真实队列深度（需 TG_N_BURST>16 且大概率要 ILA 旁听 ARREADY，本期预算外） |

另有一条已知契约（非差异，设计依据）：硬核 WVALID-先于-AWREADY（awqos 写=1 读=0）。模型与 memcheck 均已遵守。

## 7. 参数回填表与门禁

目标参数即模型 spec §18/测试 spec §8.10 合集（见 §4 表"回填参数"列）。回填操作规则：

1. **保留原值**：所有被替换默认值改名 `<PARAM>_ENG` 留档（模型 spec §6.3 注）。
2. **换算**：板上测得 ACLK 周期数 → `× f_ctrl/f_ACLK` 折算 ctrl_clk 周期再回填；报告两个口径都给；频率比实测，与理想值偏差 >1% 判该窗口无效（测试 spec §10）。
3. **置信度标注**：按测试 spec §8.10 表（min 类=高、P99/饱和类=中、队列深度/SYNC_LATENCY=低）。
4. **回填门禁（建议阈值，首次标定后修订）**：
   - OSTD/队列深度类：板/仿饱和点差 ≤1；
   - 延迟类：`_MIN` 差 ≤2 ctrl_clk 周期；P99 相对差 ≤10%；
   - B 时机类：四个组合的先后符号（B 在 WLAST 前/后）必须一致，不一致即停，先查口径再回填；
   - 任何门禁不过 → 差异进 §6 清单，修模型或修口径，不允许"挑好看的数"。
5. 回填后模型回归（traceability 基线 59 用例 + smoke 四项）必须全绿才算完成。

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| `proj/ws-e1-ddr-test.peri.xml` 为手工文本裁剪，未经 Interface Designer 打开校验 | 首次构建前用 IDE 打开 peri 重存一次；详见可行性分析（对话记录） |
| UART 1.2 ms/帧带宽装不下直方图/延迟分布 | 直方图走 ILA 抓取；UART 只报 min/peak/计数；扩展统计多帧轮发 |
| TG 扩展（OSWD/ID/速率）引入新的协议 bug | TG 扩展版先在仿真对模型跑绿（smoke 同判据）再上板；ARVALID 纪律写进代码注释 |
| 板级 memcheck 3495 burst 配置在模型上不可复现（4KB 差异） | 仿真口径参数（4/63）与板级口径（3495/119）分列；correlation 实验统一用 4KB 安全配置 |
| 双端口仲裁标定需要第二个端口流量源 | proj peri 已保留双 target；TG 例化两份，端口 1 复用同 RTL |

## 9. 标定记录

### Phase 1：OSTD 饱和标定（2026-10-22，板级实测 vs 仿真）

**配置**（板=仿同参）：TG_MODE=1，TG_N_BURST=16（每轮 16×4KB AR），ALEN=63（64 beat），TG_OSTD_MAX=16，TG_ROUND_GAP_TICKS=400_000（2ms@200M），UART_REPORT_TICKS=320_000（1.6ms/帧）。板级先开抓 60s 后 JTAG 烧写，全窗口 20205 帧无丢。

**板级扫描表**（TG_ROUND_GAP 期间采样，rd_cyc=本轮读耗时 ACLK 拍，err_sat 全 0）：

| ostd | 1 | 2 | 4 | 5 | 6 | 8 | 9 | 10 | 12 | 13 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| rd_cyc | 2741 | 2317 | 2316 | 2306 | 2284 | 2285 | 2300 | 2315 | 2284 | 2308 | 2315 | 2300 |

（3/7/11/14 轮被 1.6ms 帧节拍跳过未采样；平台 ±0.7% 内视为饱和值）终态帧 `DDR:0008FC09`（ostd=16 即 4'h0、DONE）×14088 稳定。IDLE/CFG 期 ~25.6ms（16 帧）。

**仿真对照**（同参，Questa，`PROJ TG ALL PASS`）：rd_cyc 1412（ostd=1）→1046（ostd=2）→平台 1044~1061。

**判定**：

- 板级饱和点 = 2；仿真饱和点 = 2；**差 0 ≤ 1，§7 门禁 PASS**。
- 板级 16 轮在飞全部收完、err 全 0、rd_cyc 无抬头 → 硬核读接受并发 **≥16 且无可见反压**。
- **回填结论：`READ_OSTD_DEPTH` 维持默认 8，不替换**。理由：板级证据只给出接受深度下界（≥16）>8，现有默认不受挑战；饱和点由带宽瓶颈决定（板=真实 DDR 效率，仿=1 beat/clk 理想服务），把深度改成 2 反而会引入板上不存在的反压。按 §7-5，无参数替换即无需回归重跑。
- 置信度：饱和类=中（§7-3）。
- 绝对吞吐差 ~2.2×（平台 2300 vs 1046 ACLK/轮）→ 已记 §6 差异 5，归 Phase 2/3 延迟/效率标定。

**过程教训**（已固化进代码注释与 proj 手册）：终态帧 `0008FC09` 曾被误读为 ostd=12（n5 是 rd_cyc 低位）；"重烧不重启扫描"实为烧完才开抓错过 ~58ms 扫描窗；JTAG 易失，断电后 bit 丢失串口静默。

### Phase 2：延迟标定（2026-10-22，板级实测 vs 仿真）

**配置**（板=仿同参，TG_MODE=2）：9 测量块自动轮跑——块 0-4 低负载（ostd=1）LEN={1,3,7,15,31} beat；块 5-8 高负载 LEN=31、ostd={4,8,12,16}；每块先写后读各 N 笔（LOW_N=2000/HIGH_N=10000），每相丢前 100 warm-up；地址 4KB 页对齐 +0x1000/burst；口径 T_AR_FIRST_R / T_AW_B / T_WLAST_B；直方图 32bin×64 拍（量程 0..2047）。TG_ROUND_GAP=400_000（板 2ms@200M）/2000（仿 10µs）。读出：`UART_SCAN_MODE=2` lat_word 轮发帧 `{blk,set,kind,done,0,data}`，`uart_lat_decode.ps1` 多数票解码（注意：`.ps1` 必须 UTF-8 带 BOM，否则 PS5.1 按 GBK 解析中文注释会破坏 param 块）。

**过程要点**：

1. **板级 done=0 定位**（§6-6）：全帧 done=0 非慢而是卡死——临时改 `UART_SCAN_MODE=1` 出诊断 bit，SCAN 帧低 4 位直报 `mc_state`（2933 帧恒 mcst=2=PRE_WRITE）→ 隔离实验（awcache 1111→0000）→ mcst=9。两轮编译定位根因，方法沉淀：MODE2 帧不含 mc_state，卡死类问题优先出 SCAN_MODE=1 诊断 bit。
2. **口径修正**：tb_proj_lat 的 `0000→1111` 翻译线使模型从未见过板级基线（两轮仿真结果相同的异常由此而来）——改直通；smoke/tg 保留原翻译（各自口径独立）。
3. **B 时机符号修正**（§6-7）：板级 cache=0000 的 B 在数据后，模型原为早返——修 `cmd_is_early`；随后仿真写相耗时与板级同数量级（memcheck 写相单 burst 串行），tb_proj_lat `TMO_MEAS` 150→300ms。
4. **smoke 参数钉死**：top 默认 TG_MODE/UART_SCAN_MODE 演进为 2 后 smoke P2/P4 失判（跑了 MODE2 全量测量）——tb_proj_smoke 显式覆盖 `TG_MODE=0 / UART_SCAN_MODE=0` 钉死 Phase 0 形态。教训：TB 不应继承演进中的 top 默认参数。

**板级统计表**（`uart_p2_final.txt`，30s 抓 10996 帧 100% done=1、0 坏帧；fail=0、err_tot=0；cnt 全等 N−100、ovf=0；每格 52/53 票全一致。单位 ACLK 拍）：

| 块 | len | ostd | RD min/max | WA min/max | WL min/max | RD P50/P99（bin 界） |
|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 24/61 | 21/54 | 21/54 | 64/64 |
| 1 | 3 | 1 | 23/61 | 25/67 | 24/66 | 64/64 |
| 2 | 7 | 1 | 24/60 | 30/73 | 29/72 | 64/64 |
| 3 | 15 | 1 | 24/61 | 39/74 | 38/73 | 64/64 |
| 4 | 31 | 1 | 23/61 | 57/100 | 56/99 | 64/64 |
| 5 | 31 | 4 | 199/302 | 57/100 | 56/99 | 256/320 |
| 6 | 31 | 8 | 465/535 | 57/100 | 56/99 | 512/576 |
| 7 | 31 | 12 | 767/838 | 57/100 | 56/99 | 832/832 |
| 8 | 31 | 16 | 1033/1118 | 57/100 | 56/99 | 1088/1152 |

低负载 RD min/max 全 LEN 一致（读延迟与 burst 长度无关，首 beat 口径）；WA/WL 随 LEN 增长（B 等数据提交）；高负载 RD 线性于 ostd（§6-8）。

**仿真对照**（tb_proj_lat 回填后 ALL PASS，ctrl≈ACLK 口径）：RD 低负载 192/487-488（P99 bin 界 512）；高负载 blk8 219/488；WA 478/479；WL 448/449；miss=0、CTRL_ERR=0。

**回填**（`rtl/ddr_axi_model_top.sv`，换算 ×8 = 1/CLK_RATIO_ACLK_PER_CTRL 0.125，板 ACLK=200MHz；原值 `_ENG` localparam 留档）：

| 参数 | ENG 原值 | 回填值 | 板级依据 | 门禁（§7-4） |
|---|---|---|---|---|
| READ_LATENCY_MIN | 10 | **191** | 低负载 RD min 24 ACLK → 192 ctrl | 仿 192，差 0 ≤2 ✓ |
| READ_LATENCY_MAX | 30 | **492** | 低负载 RD max 61 ACLK → 488 ctrl | 仿 487-488，差 ≤1；P99 bin 界 512=512 ✓ |
| WRITE_RESP_LATENCY_MIN/MAX | 8/24 | 维持 | cache=0000 已非早返，B deadline 被数据路径支配；板 WA 因 W-first 锚点几何不可直比（§6-7） | — |
| WRITE_DATA_TO_B_LATENCY | 4 | **451** | WL(LEN=31) min 56 ACLK → 448 ctrl（blk4-8 min 一致） | 仿 448 精确 ✓ |

置信度（§7-3）：MIN 类=高（多 LEN 一致）；MAX/P99=中（bin 界量化）；WDTB=高（blk4-8 min 全 56）。

**对测试 spec §8.3 的偏离**（逐条记录，不"挑好看的数"）：
- §8.3-4 写基线 1111/COBUF=0 → 板级死锁，改 0000（§6-6）；
- §8.3-3 `READ_LATENCY_MAX` = 高负载 P99 → 不可行：均匀延迟 + 理想服务模型无法同时满足低负载 max 与高负载 P99（板级高负载 P99=1152 bin/9216 ctrl，模型同参数下仅 512 bin——§6-8 结构差）。以低负载 max 回填，高负载偏差记 §6-8；
- §8.3-1 BURST_SIZE 扫描（2,4,6）→ 明确不做：板级数据显示读延迟与 burst 长度无关（首 beat 口径），SIZE 维度预期同理且需新增扫描位，留待有需求时补；
- §8.3-6 SYNC_LATENCY 多频点拟合 → 按计划留后续相位（单频点 200MHz 下 READ 回填已含总延迟，频点分解需多频板测）。

**回归**（回填+模型修改后全绿）：tb_proj_smoke **ALL PASS**（P1-P4，`0000907e`×2）；tb_proj_tg **ALL PASS**（16 轮 err=0，CTRL_ERR=0；模型侧 OSTD 曲线随延迟回填整体抬升、饱和点 2→~6，§6-8 已记录）；tb_proj_lat **ALL PASS**（P1-P5，9 块 cnt=N−warmup、ovf=0、err=0）。

**traceability 59 用例回归**：待办（模型 spec 回归集，Phase 8 汇总前统一跑）。

### Phase 5：B 时机标定（2026-10-23，板级实测 vs 仿真）

**配置**（板=仿同参，TG_MODE=2 测量框架复用）：9 块 `(AWCACHE,AWCOBUF)` 矩阵——blk0=0000/0（Phase 2 基线复测）、blk1=0000/1（COBUF 核心增量）、blk2-6=0001/0010/0011/0100/0111/0、blk7-8=1110/0 与 1110/1；全 LEN=31、ostd=1 串行（B 归属无歧义）、每块 600 笔（丢前 100 warm-up → 500 样本）。`1111` 裸值板级 AW/W 死锁（§6-6）不入矩阵；TB 侧模型显式 `AWCOBUF_STRICT=0`（STRICT 为待验证假设，基线不预设拒绝）。读出：`UART_SCAN_MODE=2` lat_word，set=3 新增 BB（B 早于 WLAST 笔数）；`uart_lat_decode.ps1` 扩 cache/cobuf 矩阵表（注意 .ps1 必须 UTF-8 带 BOM，PS5.1 无 BOM 按 GBK 解析中文注释会吞字节）。

**决定性发现：B 时机由 AxCACHE[0]（Bufferable）单独决定**：

- bit0=1（0001/0011/0111 板级实测全同形）：**早返**，T_AW_B = AW 握手 +4-5 ACLK、WL=2 拍——B 远早于数据路径量级；
- bit0=0（0000/0010/0100/1110 实测全同形）：**非早返**，B 在写数据提交后（WA/WL 55-99 ACLK，与 Phase 2 LEN=31 块一致）；
- COBUF 无独立效应（blk1/blk8 与各自 cobuf=0 孪生块统计全同形）；
- 手册 `[UG]` 的 "0000 → B 命令发到 PHY 后（早返）" 语义被实测**证伪**（§6-1 闭环）。

**板级统计表**（`proj/uart_p5_final.txt`，4399 帧，多数票 15-16/15-16；fail=0、err_tot=0；cnt 全 500、ovf=0。单位 ACLK 拍）：

| blk | cache/cobuf | WA min/max | WL min/max | BB | 判读 |
|---|---|---|---|---|---|
| 0 | 0000/0 | 56/98 | 55/97 | 0 | 基线（Phase 2 一致） |
| 1 | 0000/1 | 56/98 | 55/97 | 0 | COBUF 无效应 |
| 2 | 0001/0 | **4/5** | **2/2** | 0 | 早返 |
| 3 | 0010/0 | 56/98 | 55/97 | 0 | 非早返 |
| 4 | 0011/0 | **4/5** | **2/2** | 0 | 早返 |
| 5 | 0100/0 | 56/99 | 55/98 | 0 | 非早返 |
| 6 | 0111/0 | **4/5** | **2/2** | 0 | 早返 |
| 7 | 1110/0 | 56/91 | 55/90 | 0 | 非早返 |
| 8 | 1110/1 | 56/91 | 55/90 | 0 | COBUF 无效应 |

RD 全块 min 23-24 / max 59-61（读不受写 cache 编码影响，Phase 2 口径复现）。BB 全 0 的解读见 §6-9：W-first 下早返 B 也不越过 WLAST（W 打完 → AW 握手 → B+2-4 拍），早返签名是 **WA 骤降**而非 BB>0。

**模型侧对照**（tb_proj_lat 回填后 ALL PASS，ctrl≈ACLK 1:1 口径，板值 ×8 折 ctrl 对照）：

- bit0=1 块（blk2/4/6）：WA 32/33（板 4-5 ACLK ×8 = 32-40，**差 ≤2 门禁 ✓**）、WL 1/3（板 2×8=16 量级差但同"远小于数据路径"符号，见偏离 3）、BB=0（与板同形）；
- bit0=0 块：WA 478/479、WL 448/449（Phase 2 回填口径保持，未受本相位影响）；
- P1/P2/P4/P5 全 PASS、miss=0、CTRL_ERR=0。

**回填**（`rtl/core_scheduler.sv` + `rtl/ddr_axi_model_top.sv`，ENG 原值 localparam 留档）：

| 项 | ENG 原值 | 定稿 | 板级依据 | 门禁（§7-4） |
|---|---|---|---|---|
| `cmd_is_early` 判据 | 手册组合（0000 早返） | **`AWCACHE[0]` bit0 规律**：bit0=1 早返；`OTHER_AWCACHE_POLICY!=DATA_DONE` 时 bit0=0 兜底早返；1111+cobuf 显式早返 | 9 块符号 100% 一致 | 四组合符号门禁 → 9 块符号门禁，全一致 ✓ |
| `BVALID_CMD_QUEUE_DELAY` | 2 | **28** | 板 T_AW_B 4-5 ACLK ×8 = 32-40 ctrl；模型 CDC 结构 ≈4 → 28+4≈32 对齐 min | 仿 WA min 32，差 0 ≤2 ✓ |
| `OTHER_AWCACHE_POLICY` | `DATA_DONE`（语义为"一律非早返"） | 默认维持 `DATA_DONE`，但语义改为**兜底**：仅对 bit0=0 编码生效；bit0=1 一律早返不受此参数影响 | bit0=1 块板级早返实证 | — |
| `BVALID_TIMING_MODE` | `MANUAL_STRICT` | 实现未使用（bit0 规律内建），参数保留兼容 | — | — |
| `AWCOBUF_STRICT` | 1 | 维持默认 1（保守）；blk1/blk8 证明 COBUF 对 B 时机无效应，STRICT 不影响行为；TB 标定流量显式覆盖 0 | 0000/1110 × cobuf 全同形 | — |
| `BVALID_PHY_ISSUE_DELAY` | 2 | 维持 ENG 值；仅 `PHY_ISSUE` 兜底策略使用，默认路径不触发 | — | — |

**对测试 spec §8.6 的偏离**（逐条记录）：

1. §8.6 四组合矩阵（1111/0000 × cobuf）→ 1111 裸值死锁不可测（§6-6），缩范围为 9 块矩阵（1111 仅以 1110+模型外推覆盖）；
2. §8.6-3 `B_BEFORE_WLAST` 作 B 早返符号判据 → **在 W-first 宿主上恒 0，不可用**（§6-9）；符号判据改由 WA/WL 统计承担，BB 降级为纯记录；
3. 板级早返块 WL=2 拍与模型 WL 1/3 ctrl 的量级差：模型 W-first 缺失导致 wl 锚点几何不同（模型 WA−WL≈31 为 shell 授 AW 几何差，§6-7 已记录），标定口径以 WA 为早返锚点，符号与量级（×8 后 ≤2 门禁）已对齐。

**覆盖范围**：16 编码中 7 个板级实测（0000/0001/0010/0011/0100/0111/1110，×cobuf 采样 9 块），9 个未测编码（0101/0110/1000/1001/1010/1011/1100/1101/1111）按 bit0 规律外推——bit0 已由 bit0=1（0001/0011/0111）与 bit0=0（0000/0010/0100/1110）双侧锚定，且高 3 位在实测中无效应（0100 vs 0000、0111 vs 0011、1110 vs 0010 同形），外推置信度中-高；`1111` 裸值死锁亦按 bit0=1 外推早返（仅模型语义，板级不可达）。

**回归**（Phase 5 模型修改后三 TB 全绿，2026-10-23）：tb_proj_smoke **ALL PASS**（P1-P4）；tb_proj_tg **ALL PASS**（16 轮 err=0）；tb_proj_lat **ALL PASS**（9 块矩阵 + bit0 规律 verdict 全对齐板级）。

**traceability 59 用例回归**：待办（Phase 8 汇总前统一跑）。

### Phase 3：队列深度标定（2026-10-23，板级实测 vs 仿真）

**配置**（板=仿同参，TG_MODE=3 新增固定速率读扫描；复用 MODE1 轮结构 + MODE2 lat_word 报告机构）：9 档注入间隔 ivl ∈ {256,128,64,32,16,8,4,2,1} ACLK（blk0-8），每轮 TG_N_BURST=16 笔 4KB 读（ALEN=63、RID=发射序号 0-15 轮转，等效 §8.4 `ID_MODE=ROTATE`），发侧无 OSTD 门控——qd_gap 分频到 0 才发下一笔（握手拍重装 ivl-1），不设在飞上限；写基线 AWCACHE=0000（§6-6，沿 MODE0/1 通路 POST_WRITE）；TG_ROUND_GAP=2000 拍换轮。每轮终锁存 rd_cyc/bp_cnt/if_peak/err 四字段，经 lat_word（set=0、kind 0-3 回绕）UART_SCAN_MODE=2 直发，`uart_lat_decode.ps1 -Phase 3` 多数票解码。板级 top 默认形态改 TG_MODE=3。

**抓帧时序教训**（§3.2/§4.1 纪律的量化复现）：首抓 30s 窗口 9835 帧全为旧 bit MODE2 终态帧（efx_run.bat PYTHON 初始化 + JTAG 编程 ~20s+ 耗尽窗口，set 位 0-3 均匀分布为 MODE2 特征实锤）；重抓 60s 窗口 + 烧写延后 3s 解决。终版 `proj/uart_p3_final.txt` 21991 帧，badfmt=0（set 位全部合法=MODE3 特征），各 key 550 票高度一致，fail=0、err_tot=0。

**板级统计表**（cyc 单位 ACLK@100MHz 拍；bp=AR 反压拍数、ifp=在飞峰值）：

| blk | ivl | cyc | bp | ifp | 判读 |
|---|---|---|---|---|---|
| 0 | 256 | 4021 | 0 | 1 | 注入受限（≈15×256+尾笔服务） |
| 1 | 128 | 2301 | 0 | 3 | 服务 144 拍/笔 > 128，已进平台并缓慢积压 |
| 2 | 64 | 2285 | 0 | 10 | 积压（注入 64 < 服务 144） |
| 3 | 32 | 2300 | 0 | 13 | 积压 |
| 4 | 16 | 2301 | 0 | 15 | 积压 |
| 5 | 8 | 2316 | 0 | 16 | 饱和=样本上限（TG_N_BURST） |
| 6 | 4 | 2299 | 0 | 16 | 同上 |
| 7 | 2 | 2300 | 0 | 16 | 同上 |
| 8 | 1 | 2284 | 0 | 16 | 同上（连续注入仍零反压） |

**模型侧对照**（tb_proj_qd 同参 ALL PASS，2026-10-23；cyc 单位 ctrl@200MHz 拍，TB 内 ACLK=ctrl=200MHz 异相 1:1）：

| blk | ivl | cyc | bp | ifp |
|---|---|---|---|---|
| 0 | 256 | 4356 | 0 | 3 |
| 1 | 128 | 2372 | 0 | 5 |
| 2 | 64 | 1476 | 0 | 8 |
| 3 | 32 | 1463 | 454 | 8 |
| 4 | 16 | 1459 | 656 | 8 |
| 5 | 8 | 1313 | 664 | 8 |
| 6 | 4 | 1420 | 801 | 8 |
| 7 | 2 | 1430 | 871 | 8 |
| 8 | 1 | 1455 | 882 | 8 |

模型侧结构：`arready = arstn && arvalid && (rd_ostd<8) && !ar_cmd_full`（shell 融合门控，rd_ostd RLAST 才递减）→ if_peak 封顶 8=READ_OSTD_DEPTH、blk3 起反压可观测；服务受限平台 ~1313-1463（8 笔并发理想服务）。

**对照判读**：

1. **定性同构**：cyc"注入受限（≈N×ivl+尾笔服务）→ 服务平台"两段形态、if_peak 单调爬升→饱和形态、err 全 0——两侧一致 ✓；
2. **结构差（§6-10 新立）**：板级 TG 直连 `ddr_inst_*` 硬核 peri，无 shell 门控层 → 16 笔内 AR 反压不存在，if_peak 饱和 16 是样本上限而非容量；模型经 shell（OSTD=8）→ 封顶 8 + 反压可观测。饱和点 16 vs 8 的差是**路径结构差**，不是参数错标；
3. **平台值**：板 ~2300 ACLK@100M ≈ 144 拍/笔，与 Phase 2 RD 平台 2284-2317（§6-5）独立复现一致 ✓；模型 ~1455 ctrl@200M ≈ 91 拍/笔（≈45.5 ACLK@100M 当量）——绝对时间比 ~3.1×，与 §6-5 的 2.2×（8KB 口径）同向，归 §6-8 带宽效率相位，本相位不处理。

**回填与门禁**：

- §8.4 目标参数 `CMD_QUEUE_DEPTH_ENG`：板级 16 笔内无任何反压 → "首反压 IN_FLIGHT"不可定义，记**下界 ≥16**（置信度低，§7-3；样本仅 16 笔/轮）；
- `READ_OSTD_DEPTH` 维持 8：板级不存在 OSTD 门控层，板 16 非容量实测，Phase 1/§6-8 结论不受挑战；shell `CMD_REQ_DEPTH=4`/`READ_OSTD_DEPTH=8` 保留 ENG 形态语义，无参数替换；
- §7-4 门禁"队列深度类板/仿饱和点差 ≤1"**不满足**（16 样本上限 vs 8 结构门）→ 差异 §6-10，按"修口径"处置（参数属 shell/ENG 形态，非真核可观测参数），不修模型。

**对测试 spec §8.4 的偏离**（逐条记录）：

1. §8.4-1 写基线 `AWCACHE=1111` → **0000**（§6-6 板级死锁实锤，沿 Phase 2/5 定稿）；
2. §8.4-1 `BURST_LEN=3` → ALEN=63（4KB 压线，§6-2 处置口径，与 Phase 1/2 一致）；
3. §8.4-1 `ID_MODE=ROTATE` → RID=发射序号 0-15（16 笔内轮转，等效）；
4. §8.4-1 纯读→纯写→混合 → 板级仅纯读：bp 全 0 下纯写预期同形（真核同队列无反压），信息增量低且 UART 预算有限；如 Phase 8 汇总要求数据分离再补；
5. §8.4-3 `bp_ratio`/`bp_first_cycle`/`ostd_peak` 多字段 → UART 带宽约束下 rd_cyc/bp/if_peak/err 四字段轮发（沿 Phase 2 lat_word 机构，§5.3 口径）；
6. §8.4-4 首反压点判据 → 板级无反压，判据退化为"16 笔内无反压"结论 + if_peak 饱和值口径；`CMD_QUEUE_DEPTH_ENG ≈ max(IN_FLIGHT at first true backpressure)` 在本宿主上只能取下界。

**覆盖范围**：ivl 维度 9 档全覆盖（256→1 逐半）；在飞维度受 TG_N_BURST=16 样本上限约束，>16 的队列深度不可观测（留待 Phase 8 评估是否加大 TG_N_BURST 复测，需同步评估 err 字段轮发带宽）。

**回归**（Phase 3 RTL 修改后三 TB 全绿，2026-10-23）：tb_proj_smoke **ALL PASS**（P1-P4）；tb_proj_tg **ALL PASS**（16 轮 err=0）；tb_proj_lat **ALL PASS**（9 块矩阵 verdict 不受 MODE3 影响）。MODE3 新增分支均为 `TG_MODE==3` 门控，MODE0/1/2 路径回归无变化，top 默认形态改 TG_MODE=3 不影响 TB 显式覆盖。

### Phase 6：OOO 标定（2026-10-23，板级实测 vs 仿真）

**配置**（板=仿同参，TG_MODE=4 新增 OOO 探测；复用 MODE3 qd_gap 发射机构）：首轮前写布置 16×4KB（ALEN=63，**地址 1MB 步长分散跨 bank/row**，§8.7-1），之后 9 轮只读：每轮 16 笔**背靠背**（qd_ivl=1，无在飞上限，制造最大并发），**ID_COUNT=8 轮转**——发射序 s 的 arid=s[2:0]（0..7,0..7，每 ID 2 笔，§8.7 `ID_MODE=ROTATE`）。完成侧：同 ID 保序（AXI 契约）→ per-ID 完成计数 `id_comp` 推导完成笔发射序（同 ID 两笔共用 rid 槽，数据比对 `rid_addr[seq]` 按序选前/后笔）；乱序判据（§8.7-3）：第 j 笔完成的 `rid[2:0] != j[2:0]` → 跨 ID 乱序，oo_cnt++，oo_first 锁存首错位 {rid,seq}。报告：lat_word blk 恒 0（9=状态字），kind 0=oo_cnt 1=oo_first 2=done 3=err；`uart_lat_decode.ps1 -Phase 6` 解码。

**附带修复**：top 例化 memcheck 的 `TG_MODE[1:0]` 截断为 2 位——MODE4(=4) 会变 MODE0 自检；改 `[2:0]`（Phase 6 编译前发现，未上过错误 bit）。

**模型侧双档**（tb_proj_ooo，`-gMODEL_OOO` 参数化模型 `OUT_OF_ORDER_ENABLE`，双档 ALL PASS，2026-10-23）：

| 档 | 模型 OOO | oo_cnt | oo_first | done | err | 判读 |
|---|---|---|---|---|---|---|
| 主档 | 0 | **0** | — | 16 | 0 | 模型按序完成（与参数一致） |
| 表征档 | 1 | **12** | {rid=2,seq=0} | 16 | 0 | 模型 OOO 路径乱序完成；**检测器自证可检出乱序**（非假阴性），且乱序下 per-ID 推导比对 err=0（推导正确性实证） |

**板级实测**（`proj/uart_p6_capture.txt`，20199 帧；前段 ~22s 为旧 MODE3 bit 终态帧（烧写完成前），blk1-8 被 Phase 6 过滤器计 badfmt=11536（预期）；有效 MODE4 段各 key **1079/1081 票**）：

| oo_cnt | oo_first | done | err | 状态字 |
|---|---|---|---|---|
| **0** | {0,0}（无错位，默认值） | 16 | 0 | fail=0 err_tot=0（4321 票） |

**对照判读**：板级真核**按序完成**（16 笔全并发下完成序=发射序），与模型主档（OOO=0）同形 → §7 门禁"板/仿同形" ✓，`OUT_OF_ORDER_ENABLE=0` 维持，无参数替换。

**对测试 spec §8.7 的偏离**（逐条记录）：

1. §8.7-1 `FIXED_OSTD, TARGET_OSTD=8` → 背靠背无在飞上限（并发 16 ≥ 8，观测力更强；Phase 3 已证真核 16 笔零反压全接受）；
2. §8.7-1 "读为主" → 纯读（写方向 BID 观察与混合流量 §8.7-4 未测，板级预算优先；读/写完成网络在真核内独立，读方向结论外推写方向置信中）；
3. §8.7-3 同 ID 保序检测 → 不设板级检测（AXI 契约强制保序，同 ID 两笔完成流无区分信息；模型侧乱序路径经 id_comp 推导保证数据比对正确）；
4. §8.7-5 覆盖注记：**"未观察到乱序"≠"绝不乱序"**——本实验覆盖单端口读、16 笔在飞、1MB 地址分散、同 ID 2 笔背靠背形态；更大在飞/跨端口/读写混合下的乱序可能性未排除，`OUT_OF_ORDER_ENABLE=0` 的适用域以此为界。

**覆盖范围**：读方向 16 笔 ×9 轮 ×板/仿两侧；地址分散 1MB 步长（bank/row 交错）；ID 拓扑 8 ID × 2 笔。写方向、双端口 OOO 未覆盖（§8.7-4 偏离）。

**回归**：tb_proj_ooo 双档 ALL PASS（2026-10-23）；smoke/tg/lat 三 TB 回归在 Phase 8 汇总统一重跑（memcheck MODE4 分支均 `TG_MODE==4` 门控，预期无影响）。

### Phase 7：地址/rank/容量标定（2026-10-23，板级实测 vs 仿真）

**范围收缩**（peri.xml L134 实锤 `physical_rank="1" mem_type="LPDDR4x" mem_density="2G"`）：单 rank 256MB 且 2 的幂 → 测试 spec §8.8 的 rank 边界扫描、`CS_BIT_POS`、非 2 幂密度线性扫描**全部不适用**，缩范围为**容量边界 + 越界回绕（别名）行为探测**。

**配置**（板=仿同参，TG_MODE=5 新增容量/别名探测）：九探针 blk0-8 = {0, 256M-4K, 256M, 256M+4K, 512M, 1G, 2G, 4G-4K, 4G(bit32)}；每轮 4 笔**串行**（ostd=1，消除并发干扰）：写 Yi(=Xi mod 256M=Xi&0x0FFF_FFFF) 参考（pattern(Yi)）→ 写 Xi 探针 → 读 Xi（比对 pattern(Xi)；hi_err>0=不可存储/SLVERR）→ 读 Yi（**rid_addr[1] 存 Xi 使比对基准仍为 pattern(Xi)**；读回 pattern(Xi)=Xi 高位被模掉、写落 Yi 污染参考的实锤，alias_err==0）。探针 0/1（Xi==Yi）alias 检测退化，以 hi_err 为准；探针 8 指纹退化（pat 只取地址低 32 位，pat(4G)==pat(0)），alias 位只记录。MODE5 不置全局 fail（越界 err 是预期观测）；报告 lat_word blk=探针号（9=状态字），kind 0=hi_err 1=alias_err 2=addr[15:0] 3=addr[31:16]（bit32 不入 16 位报告，探针 8 地址显示低 32 位）；`uart_lat_decode.ps1 -Phase 7` 解码。

**模型侧**（tb_proj_addr ALL PASS，2026-10-23；模型行为已知=越界 SLVERR+写丢弃，core_scheduler L314 `resp==RESP_OKAY` 才存储、mem_model 稀疏数组无掩码）：

| 探针 | 地址 | hi_err | alias_err | 判读 |
|---|---|---|---|---|
| 0/1（合法） | 0 / 256M-4K | 0 | 0 | accessible（容量 ≥256M-4K） |
| 2-7（越界） | 256M~4G-4K | 64 | 64 | SLVERR，写丢弃 Yi 无污染 |
| 8（bit32） | 4G | 64 | 0 | SLVERR；alias 指纹退化只记录 |

P4 互证：CTRL_ERR=1（SLVERR sticky）+ bresp!=OK=7（每越界写 1 B）+ rresp!=OK=448（7 探针×64 beat）。

**板级实测**（`proj/uart_p7_capture.txt` 20205 帧；前段 ~25s 旧 MODE3 bit 终态帧与 MODE5 帧同为 blk 0-9/kind 0-3 形态、Phase 7 过滤器无法区分 → 取烧写后纯段 `proj/uart_p7_pure.txt` 12000 行解码，每 key **300/300 票全一致**、9 轮重复扫描稳定无翻转）：

| 探针 | 地址 | hi_err | alias_err | 判读 |
|---|---|---|---|---|
| 0/1（合法） | 0 / 256M-4K | 0 | 0 | accessible |
| 2（256M） | 0x1000_0000 | 0 | 0 | **回绕别名**（写落 Yi 污染、读回 pattern(Xi) 全匹配） |
| 3（256M+4K） | 0x1000_1000 | 0 | 0 | 回绕别名 |
| 4（512M） | 0x2000_0000 | 0 | 0 | 回绕别名 |
| 5（1G） | 0x4000_0000 | **64** | **64** | **SLVERR（全表唯一报错点）** |
| 6（2G） | 0x8000_0000 | 0 | 0 | 回绕别名 |
| 7（4G-4K） | 0xFFFF_F000 | 0 | 0 | 回绕别名（模 256MB=Yi 精确吻合，纯低位截断） |
| 8（4G） | 0x1_0000_0000 | 0 | 0 | 回绕别名（bit32 疑似端口截断） |

**对照判读**：板/仿**不同形**（唯一一相）——模型越界=SLVERR+写丢弃，真核越界=**静默回绕**（除 1G 孤点）。要点：

1. **容量硬边界 256MB 实测确认**：末合法页 256M-4K 可访问（hi=0），256M 起高位被模（探针 7 的 4G-4K 精确回绕到 Yi=256M-4K），与 peri.xml 2Gb 单 rank 一致 → `RANK_MAP_MODE`/`CS_BIT_POS`/`PHYSICAL_RANK` 无需变更。
2. **回绕模数=256MB**（探针 7/8 数据实锤 [27:0] 低位截断语义），真核对越界访问**无保护**。
3. **1G 孤点 SLVERR 机制未解**：非单调（2G/4G 均回绕），排除纯截断模型；板级无 ILA 无法深挖，如实记录观测。9 轮 300/300 票稳定排除偶发。
4. **回填决策：无参数可替换**。模型 spec `ADDR_HOLE_POLICY=ALIAS` 语义不匹配（仅 FIELD_DECODE_DEBUG+显式空洞窗生效，ddr_model_pkg apply_addr_hole；spec 明言"ALIAS 仅用于测试，不得作为默认"），且容量越界路径（check_cmd ERR_ADDR_RANGE）硬编码 SLVERR 无开关。**维持 `ADDR_HOLE_POLICY=DECERR`**，记 documented deviation：越界行为模型=显式报错（保护方向，能暴露测试程序 bug），真核=静默别名（假阴性方向）——对合法区（<256MB）行为无影响；凡在本项目跑的 TG/应用地址均 <256MB，偏差不触达。

**对测试 spec §8.8 的偏离**（逐条记录）：

1. §8.8-2 rank 边界扫描 → 不适用（单 rank 板配置，peri.xml 实锤）；
2. §8.8-3 非 2 幂密度 → 不适用（2G 颗粒天然 2 的幂）；
3. §8.8-4 CS 模式 → 不适用（单 rank 无 CS 交错可测）；
4. §8.8-1 "后者应错误或回绕，按 DUT 行为记录" → 按 DUT 行为记录完成（回绕为主+1G 孤点）；
5. §8.8-5 回填 `RANK_MAP_MODE`/`ADDR_HOLE_POLICY` → 均维持原值（前者配置已符，后者无匹配语义），无参数替换。

**覆盖范围**：单端口串行 4KB 突发 ×9 探针 ×9 轮 ×板/仿两侧；容量边界精确到页粒度。越界粒度仅 4KB 对齐探针（非逐地址扫描）；1G 孤点机制、写方向独立验证（读回依赖写落位，间接覆盖写）、双端口越界未覆盖。

**回归**：tb_proj_addr ALL PASS（2026-10-23）；smoke/tg/lat 三 TB 回归在 Phase 8 汇总统一重跑（memcheck MODE5 分支均 `TG_MODE==5` 门控，其余模式路径仅发射门控条件等价改写（`TG_MODE>=3` 收窄为 `==3||==4`），MODE0-4 行为不变，预期无影响）。

### Phase 4：双端口仲裁标定（2026-10-23，板级实测 vs 仿真）

**范围收缩**（测试 spec §8.5 原设 ILA 抓 grant 序列）：板级无 ILA 探针 → 缩范围为**对称流量完成速率对比**。top 改双 memcheck 形态：u_mc@target0（报告口）+ u_mc2@target1（`START_ADDR=0x0200_0000` 错开 32MB，纯负载），同参 TG_MODE=1 OSTD 扫描 16 档×16 笔 4KB，地址布置对称；UART 单报告口（port0 视角）出扫描帧（`UART_SCAN_MODE=1`，1.6ms/帧）→ port0 每档 rd_cyc vs Phase 1 单口基线（首轮 2741、平台 2284~2317，同参同口径）→ **双口退化比**。

**模型侧**（tb_proj_arb，CDC_ENABLE=1 板级对应形态，`ARB_GRANT_INTERVAL=2` 默认主档；ALL PASS 2026-10-23）：

- 主档 16 档全表：P1 CFG_DONE、P2 双口 done=1 fail=0（err 全 0）、P3 CTRL_ERR=0、**P4 公平性 PASS**（饱和档 ostd 8-15 双口比值 ≤1.075，门限 1.15）。饱和档 rd_cyc0=1729/rd_cyc1=1662，**双口/单口退化 1.17~1.34x**（单口基线 1293~1483）。曲线形状：首轮 ostd=1 双口 6649/6818（vs 单口 6442 = **1.03~1.06x**）→ ostd=4 后进入平台 1978~2339。
- **ARB_GRANT_INTERVAL 表征（关键结构性发现）**：`-gARB_G=8` 表征档与主档 **逐位相同**。RTL 审查实锤：该参数所属的双口仲裁器（round-robin+冷却）只在 `g_sync`（CDC_ENABLE=0）generate 分支例化（ddr_axi_model_top L307-441）；**板级对应的 CDC 形态（CDC_ENABLE=1）不经过该仲裁器**——CDC 收集逻辑为固定 1:1 交替（`ar_last/aw_last` anti-starvation，port0 优先+last 翻转，L591-664），每方向每拍最多一条入共享 cmd 队列，唯一节流是 `CMD_QUEUE_DEPTH`。g_sync 形态表征档（时钟改同源 200MHz 后 G=2/G=8）亦逐位相同 → 参数在本 TB 流量下两形态均不影响结果。**结论：`ARB_GRANT_INTERVAL` 对本项目使用形态为惰性参数，无参数可回填；CDC 双口调度同形性判据落在"1:1 交替+公平比"上**。
- TB 采样修正：饱和档（ostd=16→4'h0）无 ostd 递增边沿（memcheck 到 MAX 直接 DONE），done 上升沿补存；`tab_vld` 初值改 1（ostd 复位值=1，首个边沿即第 1 轮完成）修复 ostd=1 档丢样。

**板级实测**（2026-10-23，3 次烧写抓帧；先开抓后烧写纪律）：

| 烧写 | REPORT_TICKS | 扫描窗帧 | 覆盖 ostd |
|---|---|---|---|
| 1/2（bit 相同） | 320_000 | 各 12 帧 | 1-7,10,12,13,15,16 |
| 3（340_000 移采样相位补档） | 340_000 | 12 帧 | 1,2,3,4,5,7,9,10,12,13,15,16 |

烧写→复位→CFG IDLE 帧（`00000010`）→ 扫描帧 → 终态（`0008FC09`/`0008ED09`）序列确定，两次同参数烧写缺档模式相同（帧-轮相位确定性）。合并 **13/16 档**，恒缺 8/11/14——三次采样相位均未落入，位于平台区（邻居 6/7/9/10/12/13/15 全部 2284~2315 平坦），对判据无影响，如实记录。全部帧 err=0、终态 done fail=0。

**板级 port0 曲线**（rd_cyc，拍）与退化比：

| ostd | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 9 | 10 | 12 | 13 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| rd_cyc | 4707/4738 | 4326/4310 | 3893/3909 | 3732/3720 | 3320/3159 | 2300/2284 | 2300/2315 | 2284 | 2300/2315 | 2285/2284 | 2300/2299 | 2300/2315 | 2300/2285 |
| 双/单（vs 2741/平台） | **1.72** | 1.58 | 1.42 | 1.36 | 1.21 | 1.00 | 1.01 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |

**板/仿对照判读**（退化比口径，双口 vs 单口同 ostd）：

1. **饱和档不同形**：板级双口饱和**零退化**（2300 vs 单口平台 2284~2317，DDR 带宽足够双口并发）；模型 CDC 双口退化 1.17~1.34x。**模型偏保守**（悲观方向，预测带宽下界，工程安全侧）——记 documented deviation。机理：模型 CDC 收集每方向每拍 1 条+共享队列竞争在 core_scheduler 排队；真核双口调度对饱和对称流量做了更充分的并发。
2. **首轮/低档不同形（反向）**：板级双口首轮 1.72x（冷启动/刷新对齐等真核因素叠加双口竞争）；模型 1.03x（mem_model 无刷新/功耗管理干扰，首轮惩罚被两端口并行抵消）。**模型偏乐观**（非保守方向）；首轮为瞬态非收敛带宽，对带宽预测影响限于启动段。
3. **公平性判据（P4 等价物）**：模型饱和档双口比 ≤1.075；板级单报告口无法直接测公平比，但双口饱和零退化本身说明无端口饿死（若一 port 被饿死，port0 退化应 ≥2x）→ 板级公平性由退化比间接佐证，与模型公平性结论相容。
4. **回填决策：无参数可替换**。`ARB_GRANT_INTERVAL` 维持 2（g_sync-only 语义，spec §18 行标注"CDC_ENABLE=1 时不参与仲裁，已实测"）；`ARB_QUIET_FAST_PATH` 维持（fast path 单口零冷却已由 Phase 1/3 单口全吞吐间接佐证）。

**对测试 spec §8.5 的偏离**（逐条记录）：

1. §8.5-1 ILA 抓 grant 序列 → 不适用（板级无 ILA），缩范围为对称流量退化比（本记录）；
2. §8.5-2 `ARB_GRANT_INTERVAL` 扫描回填 → 参数在 CDC 形态惰性（结构性），无扫描意义，记 g_sync-only；
3. §8.5-3 公平性直测 → 板级无第二报告口，改由"双口零退化⇒无饿死"间接佐证；
4. §8.5-4 板/仿同形门禁 → 退化比不同形（饱和/首轮反向），按 documented deviation 记录（保守/乐观方向各异、绝对量小、瞬态为主）。

**覆盖范围**：双口对称读流量（同参 16 档 OSTD）板/仿两侧；写方向未单独扫（MODE1 轮内含写布置，写竞争被读主导掩盖）；非对称负载（一口重压一口轻载）、QOS 差异化仲裁、g_sync 形态双口真实竞争（表征档显示该形态仲裁器未被触发）未覆盖。

**回归**：tb_proj_arb 四档（CDC G=2 主档、CDC G=8、g_sync G=2/G=8）ALL PASS（2026-10-23）；top 双 memcheck 改动经 tb_proj_arb 板级形态仿真验证（MODE1 路径）；smoke/tg/lat 三 TB 回归在 Phase 8 汇总统一重跑（top 加 u_mc2 为加法改动，单口 TB 用各自 TB 顶层例化不受影响）。

### Phase 8：回填汇总与基线回归（2026-10-23）

**范围**：执行 §7-5 回归门禁（traceability 基线全量 + smoke 四项），汇总 Phase 1-7 回填决议，固化基线跑法（原 regress.sh/testlist.txt 已丢失，本轮重建）。

**汇总结论**：Phase 1-7 逐项定稿于 spec §22 v0.2a-d——v0.2a 已回填 `READ_LATENCY_MIN/MAX`（191/492）、`WRITE_DATA_TO_B_LATENCY`（451）、`BVALID_CMD_QUEUE_DELAY`（28）并修正 core_scheduler 0000 非早返；其余参数经板级实测维持 ENG 形态/默认值（Phase 1/3/6/7）或记惰性/deviation（Phase 4/7）。**Phase 8 无新增 RTL 参数替换**，门禁动作即全量回归验证。

**回归过程**（tb/ 主环境，Questa 2024.2）：

- 首跑 46/60：14 fail 归因两组——A 组 11 个为基线 -g 参数映射丢失（regress.sh 佚失后逐用例重推）；B 组 3 个（early_b/wlast_err/allstrb_early）为 v0.2a"AWCACHE=0000 非早返"定稿后的 TB 预期漂移，更新预期后全过。
- 5 个顽固 fail 的根因（修复后全绿，记录备查）：
  1. **wlast_err**：TB check 逻辑缺陷——`wlast_mode=2` 时 WLAST 永不到来，BFM `last_b_before_wlast = !wlast_sent`（axi_master_bfm L231）平凡为 1，原 check 期待 0 恒假。改为期待 1（语义=确认 0000 路径 B 确已随 SLVERR 返回，无早/非早判别意义）。
  2. **init_slverr**：`INIT_AXI_RESP` 语义为 **0=BACKPRESSURE、1=SLVERR**（ddr_axi_model_top L79/L233-234），误传 2 时 init_block 与 init_slverr 双双失效（写被当普通写接受并入库、返回 OKAY）。正确跑法 `-gINIT_AXI_RESP=1`。
  3. **addr_hole**：三重叠加——①hole 功能仅在 `ADDR_MAP_MODE=1`（FIELD_DECODE_DEBUG）下激活（`hole_en = (ADDR_MAP_MODE==1) && END>START`，ddr_axi_model_top L208）；②上轮窗口值算错 16 倍（0x300_0000 vs 测试激励所在 0x030_0000 段）；③`ADDR_HOLE_POLICY` 语义 **0=DECERR、1=ALIAS**（ddr_model_pkg L349）。正确跑法 `-gADDR_MAP_MODE=1 -gADDR_HOLE_START=3145728 -gADDR_HOLE_END=3145984`（POLICY 默认 0）。
  4. **addr_alias**：同上且窗口设计为单条 64B（START=0x0300_0040，END=+0x40）——alias 把写入重映射到线性 0x0000_0000，由第二条线性读验证 alias 落点（tb_byte 仅低 8 位地址敏感）。正确跑法追加 `-gADDR_HOLE_POLICY=1`。
  5. **rdataq_full**：真瓶颈是 shell 读 OSTD 而非命令队列——RREADY=0 期间 `rd_ostd` 只增不减（`rlast_hs` 需 RREADY 消费，axi_port_shell L220），AR 接受上限=READ_OSTD_DEPTH=8，与上轮日志"第 9 个 AR 超时+8 次 R drain 超时"逐位吻合。正确跑法 `-gCMD_QUEUE_DEPTH=16 -gREAD_OSTD_DEPTH=32`。
- **"vsim -g 失效"之谜澄清**：-g/-G 从未失效（INIT_AXI_RESP/OUT_OF_ORDER_ENABLE/ERR_INJECT_RATE/ADDR_MAP_MODE 等同批参数全部生效）。全部 4 个"失效"用例的根因均为配套参数缺失或参数值语义错误。教训入册：**多参数 -g 映射必须脚本化固化，禁止手工重推**——已执行（见下）。

**基线固化**（防再佚失）：

- `tb/testlist.txt`：60 项用例表（top|test|-g 参数三列），含全部逐用例参数映射与窗口值注释；
- `tb/regress.sh`：全量编译 + 按 testlist 逐用例仿真 + PASS/FAIL 汇总（退出码门禁）；支持 Git Bash/WSL（Questa PATH 自寻 + `.exe` 包装），stdin 已隔离（vsim 吞食 testlist 坑）；
- 复现验证：**60/60 全绿**（2026-10-23 11:57，一键重跑）；
- `tb/seeds_stress.sh`：random_stress 多 seed 扫描，`-sv_seed 2..51` 共 50 seeds 全 PASS（激励真实变化：writes 21~29、时长 14565~15675ns）。

**门禁判定**：§7-5 满足——60 项全绿 + smoke 四项此前已绿（proj/sim tb_proj_smoke，Phase 0）。TB 侧修改仅三用例预期更新与一处 check 修正，**无 RTL 改动**；traceability.md 基线行同步更新（59→60 项口径：48+9+3）。

**遗留**：tb_top_cdc 4 处 vlog-2600 RDGN 告警（数字字面量冗余位宽，tb_top_cdc L358-368，无害未动）；覆盖率数据为开发期基线（99.5%/99.7%/100%），Phase 8 未重收。
