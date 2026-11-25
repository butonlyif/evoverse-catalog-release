[English](phase3-summary.en.md) | 中文

# Phase 3 总结 — disp_timing v2 + tx_line_buf + 全链 TB（writer→DDR→reader→TX）

> 状态：**已完成并验收（2026-10-21）** · 规格：SPEC-001 mod-disp-timing / mod-tx-line-buf · 验证等级：FPGA_INTEGRATION（角色：main-flow / display-timing） · 终局回归：单元 TB `[DT-OK]`（864000 拍零错）+ 全链 TB `[FC-OK]`（6 显示帧指纹零错）

## 1. 目标

补齐显示域末端：**disp_timing v2**（显示时序唯一发生源：本地 h/v FSM + 行启动门控 + D8 TX 契约，line_tick 同源反哺 frame_reader）与 **tx_line_buf**（ISP 64b 拍流 8:1 聚合 512b BRAM / 64b 拉取 + 水位门控），并以**全链 TB** 首次打通 writer→DDR→reader→显示 TX 的端到端指纹验证。

## 2. RTL 交付（新建，v1 遗留模块不动）

### 2.1 rtl/tx_line_buf.v

- 写侧 AXIS-64（每行 960 拍）8:1 聚合 512b 写 BRAM（256×512b ≈ 2.1 行）；读侧 64b 拍 + 水位（64b 字口径）供门控；双侧同 CLK-DISP148（指针直通，gray 结构免）。
- 读管线 2 拍延迟（地址寄存 → BRAM 同步读 → 64b 通道组合选择），**三级必须同程**——lane 单寄存被下次发射覆盖导致组内通道旋转 1（TB 实锤后改 lane 双寄存同行）。
- 溢出防护：满即整组（8 拍）丢弃并 starve_events++；指针 12 位（区分满/空）。

### 2.2 rtl/disp_timing.v（v2）

- 本地 h/v FSM：行 = HSP44 + HBP75 + 门点1 + PREF2 + HACT960 + HFP18 = **1100 pclk**（守卫 FATAL 校验）；帧 = VSP10 + VBP72 + VACT2160 + VFP8 + PAD90 = **2250 槽**（TB 缩放 2/4/90/1/3 = 100）。
- **行启动门控（alg-line-gate，v4.3 语义）**：门点水位 < LINE_WORDS → 本行**跳槽**（照常走满 1100 拍空行结构，不拉取不发数，late_cnt++ 每跳槽行一次），**槽节拍永不停**。v4.2 初版的"h 冻结拉长行"会停发 line_tick——replay reader 的槽节拍同源于此，启动即死锁（全链 TB 实锤），故改为跳槽语义；Va 段跳槽不推进 v/line_num，帧在时间上拉长（行数不缺，R4；帧率下漂可观测，R1 与源零反馈）。
- PREF 2 拍预取对齐 tx_line_buf 读延迟：buf_valid#i 恰落 HACT 第 i 拍，valid 连续不断（R4）。
- TX 接口 1:1 同 shape_video_axis（D8）：hsync/vsync 低有效（寄存输出，shape hs_r/vs_r 同款）、datatype=6'h1E、haddr=3840、line_num/frame_num 递进、frame_open 为 VBP 末 1 拍脉冲。
- line_tick_o：行末 1 拍，周期恒 1100（跳槽不改变周期）——同域同源单向 disp→reader。

## 3. TB 交付

### 3.1 sim/tb_disp_timing.sv（单元）

- B0 tx_line_buf 独立子测：8:1 聚合位序 / 水位 2048 / 溢出 119 组 starve / 2 拍读延迟 / 排空归零。
- 主场景：快源 3 帧（late 增量=0）→ 慢源 5 帧（late 增长，帧率锁定供给率）；V1 突发恒 960 连续、V2 帧结构/行号、V4 数据逐拍（864000 拍）、V5 D8 契约、V6 零欠载。
- 结果：**[DT-OK] all checks passed**。

### 3.2 sim/tb_full_chain.sv（全链，新建）

- 双时钟（200M writer 域 / 148.5M 显示域）；真 frame_writer + AXI 从机（共享 mem_model）+ 真 frame_reader + 40b→64b 适配（1:1 拍数守恒，{24'h0, fp40} 直映 stand-in demosaic 路径）+ tx_line_buf + disp_timing v2 + TX 流校验器。
- 帧握手跨域用 **toggle 方案**（done 翻转 → 2FF → 边沿还原）——Phase 2 记录的 200M 单拍直采 148M 丢失风险在本 TB 即按 Phase 4 目标形态规避。
- 检查：C1 每数据行恒 960 拍连续；C2 line_num/frame_num 账本；C3 抽查行（0/1/88/89）逐 word exp64 + 每行首拍 fid 字段；C4 显示帧 fid 序列非递减（慢向 repeat 允许）；C5 缓冲零欠载/零溢出；C6 writer 发布沿 bank 抽查。
- 源模型入包络：帧周期 ~2ms（慢向）。结果：**[FC-OK] all checks passed（disp_frames=6）**。

## 4. 本阶段发现并修复的缺陷

| # | 层 | 缺陷 | 实锤 | 修复 |
|---|---|---|---|---|
| 1 | RTL | tx_line_buf mem 地址误用 64b 指针低 8 位（应 512b 粒度 [10:3]） | B0 读出组错位 | 地址改 [10:3]，指针扩 12 位 |
| 2 | RTL | 指针 11 位不区分满/空，回卷后水位误读、溢出防护失效 | level=952/starve=0 | 12 位指针，level 0..2048 |
| 3 | RTL | 读管线 stage 混用本级新值，组边界地址回退上一组 | rd[8k] 系统性错 1 组 | 各级只采样上一级寄存器 |
| 4 | RTL | lane 单寄存被下次发射覆盖，组内通道旋转 1 | rd[8k+1] 全错 | lane 双寄存与 mem_q 同程 |
| 5 | RTL | disp_timing 门控"h 冻结"停发 line_tick，replay 源（tick 同源）启动死锁 | 全链 disp=0 | v4.3 跳槽语义：门点失败走空 HACT，槽节拍恒流 |
| 6 | RTL | 空白行绕过门点少 1 拍（行周期 1099） | vsync 窗 2198 | 空白/数据行统一过门点，行恒 1100 |
| 7 | TB | 源模型 ppm 死逻辑 / set_phase 符号被 always 覆盖（Phase 2 顺带） | 段方向颠倒 | 符号统一取负 |
| 8 | TB | 全链源超包络（快于显示），写侧 2 帧后覆写在读 bank | 显示帧内 fid 5→7 撕裂 | 源帧周期 ~2ms 入包络（慢向） |

## 5. 已知代价 / 遗留（Phase 4 输入）

- **2-bank 乒乓包络契约**：源帧率不得高于显示帧率（真实相机 30fps < 60fps 满足）；超包络时写侧会在读侧排空前以 N+2 帧覆写同 bank（TB 实锤撕裂形态）。Phase 4 板级若需抗超包络，需写侧/仲裁侧加滞后丢弃（当前以包络约束 + TB 慢向验证交付）。
- 全链 TB 的 40b→64b 适配为 {24'h0, beat} 直映 stand-in；真实 demosaic→rgb2yuv 路径接入后拍数守恒不变（960→960），内容校验需换 yuv 域期望模型。
- 跳槽语义下 late_cnt 为帧率下漂观测量（R9），Phase 4 板测对照 fw 侧 bad_cnt。
- 跨域 toggle 握手已在全链 TB 验证，Phase 4 顶层按同款落地（替代单拍直采）。

## 6. 下一步（Phase 4）

顶层集成：ACLK_1=pixel_clk 148.5M、reader 实例换域、wr_frame_done/par toggle 2FF 布线、disp_timing v2 + tx_line_buf 接入（demosaic→rgb2yuv→tx_line_buf→disp_timing→shape TX 口）、SDC 双域约束、板级 replay 出图 + DIAG 观测（late/under/drop/repeat/fr_cnt）。
