[English](phase1-summary.en.md) | 中文

# Phase 1 总结 — frame_writer v3（帧握手输出 + 语义修正 + 单元 TB）

> 状态：**核心已完成（2026-10-21）** · 规格：SPEC-001 mod-frame-writer-v3 / alg-bank-handoff · 验证等级：FPGA_INTEGRATION（角色：main-flow / protocol / cdc 前置）

## 1. 目标

为架构 v4 帧级 drop/repeat 机制提供写侧支撑：frame_writer 输出**帧发布单拍脉冲**（跨 2FF 送 148.5M 显示域，作为 reader 的唯一帧请求信号），并保证脉冲的**原子性语义**——脉冲时刻该帧已全部落 DDR。

## 2. RTL 改动（rtl/frame_writer.v，最小侵入）

### 2.1 新增 `wr_frame_done_o`（v3 核心）

- **脉冲位置：drain 侧**，帧末行 desc（`drn_line==VACT-1`）bvalid 完成拍发出。
- **为什么不在填充侧关帧拍**：填充侧关帧时 drain 队列（8 行槽）还落后最多 8 行，reader 收沿读 bank 会读到未写完的帧 → 违反 R3（整帧原子）。drain 侧脉冲时刻 = 该帧最后一个 AXI 写事务 B 响应完成拍，读侧此刻安全。
- **为什么 desc 判定可靠**：坏帧行（drop_mode）不入 desc 队列 → desc 中 `drn_line==VACT-1` 必属完整帧，每完整帧恰一次。
- 实现：drain always 内默认每拍清 0，`D_POSTWR` 的 `b_cnt==1` 出队拍按 `drn_line` 判定置 1；复位清 0。

### 2.2 帧中 sof 语义修正（v2 遗留缺陷，v4 纪律要求）

- **v2 行为**：帧中 sof → 原地重启为新帧，但 sof 行（新帧行 0）被 drop_mode 丢弃 → 重启帧缺行 0 却照常发布 → **内容错位一帧违反 R3**。
- **v3 行为**：原帧行账本就地重写（原帧永无 VACT-1 完成拍 → **天然不发布**）；sof 行即新帧行 0 正常收流 → 重启帧完整可发布。`bad_cnt` 仍计数（诊断保留）。

### 2.3 顶层接线（rtl/top_cam_demo.sv）

- `u_fw` 例化补 `.wr_frame_done_o(fw_frame_done)`；wire 声明加注释（2FF 到 148.5M 的布线属 Phase 4 集成）。

## 3. 单元 TB（sim/tb_frame_writer.sv，新建）

- 缩帧 VACT=270（模块参数化，行 960 拍结构不变）；8 帧 + 第 3 帧死反压（制造 q_full 坏帧）+ 第 5 帧行 100 帧中 sof 注入（生成器行账本同步重启 + 一次性守卫）。
- AXI 从机：awready 随机延迟 0~5 拍、wready 随机反压、每 burst 恰 1 个 B 响应（wlast 握手后下一拍）；`mem_model[addr]` 关联数组记录，帧发布时逐 word 指纹比对（`exp_word`：固定槽位流切片模型，与打包代码同构）。
- 期望值函数与 DUT 打包公式同构（beat0 最低位、word w = 位流 [512(w+1)-1 : 512w]）。

## 4. 验证结果

| 检查 | 结果 | 说明 |
|---|---|---|
| V1 脉冲计数/单拍性 | **PASS** | 7/7（8 帧 - 1 坏帧），无连续两拍 |
| V2 数据完整性（温和反压形态） | 见 §5 | 逐 word 指纹 |
| V3 坏帧不发布 | **PASS** | 死反压 → ovf=35/drop=178，该帧无脉冲，后续帧恢复 |
| V4 帧中 sof 重启帧原子发布 | **PASS** | bad_cnt=2（注入 1 + 坏帧 1），重启帧完整发布 |
| V5 AXI 契约 | **PASS** | burst 不跨 4KB、awlen 精确、awqos=1、wlast 对齐 |

## 5. 发现：writer 存量 bug（burst1 数据位错，TODO-419）

- **现象**：每行 **burst1（word64~74，行尾 704B，11 word）内容确定性全错**；burst0（word0~63，64 word）全对。错误分布 270 行 × 11 = 2970/帧，逐帧逐位相同，**与反压强度无关**（20% 强反压与 2% 温和反压结果完全一致）。
- **样本**：exp_hi=`10defeaa` / act_hi=`aa10deca`（确定性位错位，非丢拍——V5 计数全对）。
- **定位圈定**：drain 数据路径 `D_PREWR → D_WADDR → D_PREWR`（burst1）的 mem 预取/rd 推进残留。v1.1 曾修 D_WRITE 补推进（"burst1 首字重复"），本 bug 是同家族的**确定性内容错位**变体。
- **为何板测未暴露**：真实 DDR 控制器几乎不反压 WREADY（板测形态 wready≈恒 1），TB 随机反压首次覆盖该路径。
- **影响评估**：板测回放出图正常说明真实形态（少反压）下多数数据正确——但位错为确定性，需波形级修复后回归（TODO-419）。
- **与 v3 改动无关**：v3 仅加握手输出与 sof 语义，不触碰 drain 数据推进。

## 6. 回退点 / 遗留

- TB 从机模型自带两处修复（B 响应多发、AW 空窗误清 in_burst）——AXI 从机建模注意事项已注释在代码内。
- `FRAME_WRITER=0` + `DDR_P1_148=1` 仍生效（Phase 0 形态）；Phase 4 集成时回 1。
- drop_cnt 语义澄清：fw 的 `bad_cnt`（坏帧放弃）即规格 R9 的 fw 侧 drop；reader 侧另有 drop/repeat（帧请求仲裁），Phase 2 实现。
