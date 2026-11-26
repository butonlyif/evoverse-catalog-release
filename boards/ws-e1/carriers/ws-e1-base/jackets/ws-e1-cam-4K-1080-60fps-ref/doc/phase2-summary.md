[English](phase2-summary.en.md) | 中文

# Phase 2 总结 — frame_reader v4.2（148.5M 显示域回放 + 帧级仲裁 + 单元 TB 全绿）

> 状态：**已完成并验收（2026-10-21）** · 规格：SPEC-001 mod-frame-reader-v3 / alg-bank-handoff · 验证等级：FPGA_INTEGRATION（角色：main-flow / arbiter / cdc 前置） · 终局回归：`tb_fr_final.log` **[FR-OK] all checks passed**

## 1. 目标

把回放后端整体搬入 148.5M 显示域（架构 v4 的"全显示域后端"）：reader 以**本地 disp_timing 节拍**自由发射（与源彻底解耦），源频偏用**帧级 drop/repeat** 吸收；输入侧消费 Phase 1 的 `wr_frame_done` 单拍脉冲 + `wr_frame_par` 电平（1bit 跨域帧握手），经 DDR 双异步端口（Port1 @148.5M，Phase 0 已确证）按行乒乓搬入 lram，40bit/拍直喂后级 demosaic。

## 2. RTL 改动（rtl/frame_reader.v，v4 → v4.1 → v4.2）

### 2.1 v4 主体（Phase 2 初版）

- **帧级仲裁**（alg-bank-handoff）：`wr_frame_done` 2FF 取沿为 `frame_req`；起步门 `done_cnt>=2`；请求粘滞（`req_pending`）；槽 fire 三态——有新沿切读最新完整帧（bank = `~par_sync[1]`）、沿堆积合并计 drop、无沿重读当前帧计 repeat。
- **行乒乓**：lram0/lram1 各 128 word（一行 75 word），`rdy[2]` 就绪位，发射消费 `r_sel`、读路径写 `w_sel`，`R_GAP` 行账本门控。
- **发射路径**：`S_FETCH` 5 字预取 → `sr <= {w4,w3,w2,w1,w0}` 2560bit 移位链 → `S_SHIFT` 每拍 `m_axis_tdata <= sr[39:0]`（1 fp40/拍）；sof/sol/eol tuser 本地生成。
- **参数化**：`FRAME_TICKS`（槽周期）、`FRAME_A/B` 基址；顶层 `top_cam_demo.sv` 同步例化（`u_fr`，148.5M 域）。

### 2.2 v4.1 — rready 常高缺陷（数据完整性，板上同病）

- **现象**：单元 TB V7 在每行 beat 819 起确定性错位，[W64CHK] 三方对拍实锤 `lram0[64]` 逐位等于 **word65** 的期望值（burst1 整体前移 1 word）。
- **根因**：`rready` 一旦在首个 `R_PRE` 拉高后**从不在突发间撤下**。burst1 的 AR 握手到 DUT 进 `R_RD` 之间 rready 恒 1，从机首拍（word64）在 `R_PRE` 窗口完成 AXI 握手被空耗，DUT 收到的首拍实为从机第 2 拍。burst0 幸免纯因复位后 rready=0 的时序巧合。
- **修复**：rready 默认拉低，仅 `R_PRE`/`R_RD` 为高。板级真实 DDR 控制器同样按 `rvalid&&rready` 完成传输——此缺陷上板必丢首拍，属 DUT 侧缺陷而非 TB 建模误差。

### 2.3 v4.2 — 行账本过严 + 仲裁同拍竞态

- **R_GAP 行账本**：`line_r == rdln + 1`（发射**完成**行 n 才许读 n+1）把 ~105 拍的双突发读延迟压进行尾→tick 的 ~50 拍窗口，必然错过 tick、逐行交替迟发——单元 TB 实锤 12 帧零漂耗 17.87ms（**2 槽/帧**）、drop=11。改为 `line_r == rdln`（发射**进入**行 n 即覆写安全：行 n+1 的目标 bank 与发射 bank 相异），读恒超前发射恰好 1 行，rdy 提前 ~945 拍就绪。
- **仲裁同拍竞态**：`frame_grant` 与 `frame_req` 同拍时原码 `else if (arm_fresh) req_pending<=1` 分支被 grant 抢走 → 新沿被静默丢弃（S0 起步丢 fid1）；且 grant 服务的是 `par_sync[1]`（滞后 2 拍）里的旧帧，本拍新沿必须顺延。修复：grant 时 `req_pending <= frame_req`（同拍新沿顺延），drop 只在"沿到且积压未被本拍受理"时计。

## 3. 单元 TB（sim/tb_frame_reader.sv）

- 缩帧 `VACT=90`、`FRAME_TICKS=100`（行 960 拍 / tick 1100 拍结构不变）；场景四段：**零漂 12 帧 → +2% 60 帧 → −2% 60 帧 → +100ppm 30 帧**（162 帧 ≈121ms，看门狗 140ms）。
- **源模型**：writer 抽象——帧完成发 `wr_frame_done` 单拍 + `wr_par` 翻转 + 关联数组 `mem_model` 逐 word 填充指纹（`exp_word_rw` 位流连续打包，与 writer 打包同构）；帧周期 `P = FTICKS*TICK_CLKS − 11*ppm_x100`（+ppm=源快=周期缩短，符号统一在源周期块取负）。
- **AXI 从机**：arready 固定 10 拍延迟（DDR 读延迟抽象），rdata 从 mem_model 顺序读出，miss 返回 512'hx。
- **V7 契约（v4.3 定版）**：`m_axis_tdata` 为 40bit/拍 = 1 fp40，期望即 `fp40(fid, l, b)` 逐拍比对（negedge 采样 + 阻塞赋值位置跟踪）。
- **FIDSEQ 流级审计（v4.2 新增，判定基准）**：从 sof 携带帧号序列直接测 drop（跳变）/repeat（重复），V2/V3/V4/V6 判定改用流真值；DUT `dbg_fr_cnt` 自计数降级为对账打印——修复后两者四段逐一相同。

## 4. 验证结果（终局回归 tb_fr_final.log）

| 检查 | 结果 | cnt(d,r) | stream(d,r) | 说明 |
|---|---|---|---|---|
| V2 零漂 12 帧 | **OK** | 0,1 | 1,0 | 起步解禁窗（done_cnt>=2）结构性合并 1 帧，容忍 ≤1；稳态干净 |
| V3 +2%（源快）60 帧 | **OK** | 1,0 | 1,0 | drop 方向性正确，repeat=0 |
| V4 −2%（源慢）60 帧 | **OK** | 0,1 | 0,1 | repeat 方向性正确，drop=0 |
| V6 +100ppm 30 帧 | **OK** | 0,0 | 0,0 | 亚仲裁确认：0.3 tick 漂移不触发仲裁 |
| V5/V7 指纹/原子性 | **OK** | — | — | 162 帧逐拍指纹零错、无撕裂 |
| 计数对账 | **OK** | — | — | cnt 与 stream 四段逐一相同（仲裁记账可证正确） |

判据：`[FR-OK] all checks passed`，`fail_cnt=0`。V1（槽节拍恒 FRAME_TICKS）由发射 FSM 结构保证并经段边界时间戳复核（S0 12 帧 9.64ms、S1 60 帧 44.44ms，均 ~740.7µs/帧）。

## 5. 本阶段发现并修复的缺陷（回归资产）

| # | 层 | 缺陷 | 实锤 | 修复 |
|---|---|---|---|---|
| 1 | DUT | `rready` 突发间常高，burst1 首拍在 R_PRE 窗被空耗 | [W64CHK] lram0[64]=word65 逐位 | v4.1：rready 仅 PRE/R_RD 为高 |
| 2 | DUT | R_GAP 行账本 `line_r==rdln+1` 过严，读延迟挤不进行间窗口 | S0 12 帧耗 17.87ms、drop=11 | v4.2：改 `line_r==rdln`，读恒超前 1 行 |
| 3 | DUT | 仲裁 grant 同拍新沿被静默丢弃、drop/repeat 计数失真 | cnt 与 stream 段级不一致 | v4.2：`req_pending <= frame_req` 顺延 + drop 条件收紧 |
| 4 | TB | 源模型 ppm 死逻辑（rem 只进累加器，周期恒定） | ±2% 段节拍与零漂无异 | v4.2：`src_wait <= src_per_int + src_per_rem - 1` |
| 5 | TB | `set_phase` 预置的带符号 rem 被 always 块每拍用旧约定覆盖 | +2% 段实测源慢（方向颠倒） | v4.2：符号统一在源周期块取负，set_phase 只设 ppm |
| 6 | TB | V7 期望契约弯路：exp64 位流切片模型不适用于 40bit/拍发射域 | act=fp40(0,208,51) 误判跨拍碎片 | v4.3 定版：fp40 逐拍模型（[SR12]/[W64CHK] 三方对拍定案） |

调试方法论沉淀：**三方对拍**（exp=指纹函数理论值 / mem=从机存储 / lram=DUT 落点）一次定位错误层级，避免输出端无限回溯。

## 6. 已知代价 / 遗留（Phase 4 输入）

- **S0 起步解禁窗合并 ≤1 帧**：`done_cnt>=2` 门使前两个请求并入首发，属结构性代价，V2 容忍并打印实际值。
- **跨域脉冲宽度风险（Phase 4 必须复核）**：`wr_frame_done_o` 为 200M 域单拍（≈5ns），reader 侧 2FF 采样周期 6.734ns——同域 TB 无损，板级存在脉冲整体落在两采样沿之间的丢失风险（量级 ~25%）。Phase 4 集成时须将脉冲展宽（≥2 个 148.5M 周期）或改 toggle 握手，并板级复测 drop/repeat 计数。
- `rd_frame_cnt/rd_line/rd_state/rd_err/dbg_fr_cnt` 观测点保留（R9 板测核心）。
- writer 侧 TODO-419（burst1 位错）已于本阶段初修复并回归全绿（见 phase1-summary §5 → 关闭）。

## 7. 下一步（Phase 3）

disp_timing v2（100% 本地显示时序，2250 槽/帧真参数）+ tx_line_buf（发射行缓冲）+ 全链 TB（writer→DDR→reader→disp 像素流）；Phase 4 板级集成（含 §6 脉冲展宽）。
