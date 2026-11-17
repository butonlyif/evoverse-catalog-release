[English](awb_rtl_design_spec.en.md) | 中文
# IMX415 相机链路 RTL 自动白平衡（AWB）设计规格

版本 v1.0（2026-11-09）· 状态：待评审 · 约束来源：`rules-rtl-style.md`、`rules-efinity-hard.md`

---

## 1. 概述

### 1.1 背景与目标

G11n17 相机链路的白平衡增益目前由 PC viewer 的 `auto_gains`（doc/pc_tools/raw10_viewer.py）
在软件里逐帧计算，板端 RTL 链路（raw10 重组 → 组内反序 → FIFO → UDP）不感知颜色。
本设计把 AWB 闭环搬进 FPGA：**统计、增益计算、增益施加全硬件完成**，每帧自动收敛，
上电即用，不依赖任何 CPU/软件参与。

算法基准为已板测验证的 viewer `auto_gains`（中性亮块主判据），固定点化与 RTL 化
简化之处逐条标注（§3.5）。

### 1.2 非目标

- 不做色温先验（CCT 曲线）、CCM、SoG(p=6) 完整估计——列为 v2 扩展（§9.2）
- 不做曝光控制（AE）——SHR0/增益寄存器仍由 imx415_rom.sv 序列管理
- 不改 UDP 发送链路与 PC viewer（viewer 的 --wb/--autowb 对 RTL 版画面不再必要，
  但保留手动覆盖能力）

## 2. 系统位置与外部接口

### 2.1 数据流位置

```
MIPI RX → raw_2_axi4st(40bit) → [组内像素反序 src mux（已有）] → ★AWB★ → 列FPN(可选) → demosaic/直出
```

AWB 工作在**相机 200MHz 像素域**，Bayer RAW10、4 像素/时钟、40bit 有效位。
图案流（raw10_pat_src）旁路 AWB（`awb_bypass_i`，图案自带精确色彩无需校正）。

### 2.2 端口定义（顶层 `awb_top`，例化名建议 `u_awb`）

```systemverilog
module awb_top #(
    parameter int GAIN_FRAC = 12,      // 增益 Q4.12 小数位
    parameter int STAT_DECIM = 4       // 统计抽行率（隔 4 行采样，同 viewer）
)(
    input  wire        cam_clk_i,      // 200MHz 相机像素域
    input  wire        rst_n_i,        // 异步复位（域内同步释放，复用链路现有 rst_sync）
    input  wire [39:0] pix_i,          // {p3,p2,p1,p0} 各 10bit，组内反序后
    input  wire        pix_valid_i,    // 每时钟一拍 4 像素
    input  wire        frame_sync_i,   // 帧起始脉冲（1 clk，帧首对齐）
    output wire [39:0] pix_o,          // 增益后 4 像素
    output wire        pix_valid_o,
    // CSR（复用链路现有寄存器总线风格）
    input  wire        csr_en_i,       // bit0: AWB 使能；0=旁路 pix_i 直通 pix_o
    input  wire        csr_manual_i,   // bit1: 1=手动增益模式（用 csr_gain_i）
    input  wire [47:0] csr_gain_i,     // 4×12bit 手动增益 {B,Gb,Gr,R}
    input  wire [3:0]  csr_speed_i,    // EMA 收敛速度移位量（默认 4 → 1/16）
    input  wire [23:0] csr_thr_i,      // {bright_thr[11:0], min_blocks[11:0]}
    output wire [11:0] dbg_gain_r_o,   // 调试读回：当前 4 通道增益
    output wire [11:0] dbg_gain_gr_o,
    output wire [11:0] dbg_gain_gb_o,
    output wire [11:0] dbg_gain_b_o,
    output wire [1:0]  dbg_mode_o      // 0=idle 1=stats 2=compute 3=compute_ovf
);
```

接口说明：
- `pix_i` 必须是组内反序修复后的像素序（RGGB 本征相位：行偶 {R,Gr} 行奇 {Gb,B}），
  子面归属统计直接按 (行奇偶, 列奇偶) 定位
- `frame_sync_i` 由链路现有帧首对齐信号引出（魔数检测处已有时序点）；若无现成信号，
  用行/列计数器在 (0,0) 位置自生成，规格不变
- 无 CDC：统计、计算、施加同在 `cam_clk_i` 域，**不引入任何跨时钟路径**

## 3. 算法规格（固定点定义）

### 3.1 阶段一：逐帧统计（STREAM 态，随像素流实时累加）

对每个 2×2 Bayer 块（一拍 4 像素恰为一完整块）：

1. 亮度 `L = (p0 + p1 + p2 + p3) >> 2`，p 为 10bit 原值（未乘增益）
2. 抽样：`STAT_DECIM=4`，仅统计行号 mod 4 == 0 的块行（与 viewer `f[::4]` 一致，
   静态统计对抽样不敏感，省 3/4 加法器/比较器）
3. **中性亮块判定**（RTL 简化：固定阈值替代 viewer 的 85 分位）：
   - `THR_BRIGHT <= L < 1010`（上界防饱和块）
   - `max(p) - min(p) <= 20% × L`（四通道色度中性；12bit 比较器 + 桶形 max/min）
4. 判定为中性的块：4 个通道累加器分别累加 p0..p3，中性块计数 `n_neutral++`
5. **回退统计并行进行**（无条件累加，零额外逻辑成本）：4 个全帧子面累加器 +
   总块计数 `n_total`——中性块不足时直接切换数据源，无第二遍扫描

累加器宽度：块数上限 1080/4×1920/4 = 129,600（抽样后），40×129,600 < 2²³，
取 **24bit 累加器**（含 4× 余量）。

### 3.2 阶段二：帧消隐期增益计算（COMPUTE 态）

触发：帧尾（最后一像素拍 + 1），利用消隐期（≥56 行 ≈ 107k clk）串行完成：

1. **数据源选择**：`n_neutral >= MIN_BLOCKS`（默认 1296，即抽样块 1%）→ 用中性块
   均值（真白块判据）；否则用全帧子面均值（灰世界回退，同 viewer 回退逻辑）
2. **均值**：`mean_ch = acc_ch >> log2(n)`，n 为 2 的幂近似（对 n 取 floor(log2)，
   误差 <2×，EMA 会吸收——替代真除法的第一处简化）
3. **锚定最亮通道**：`target = max(mean_ch)`，其余 `gain_t_ch = target / mean_ch`
   —— 12bit/12bit 恢复除法状态机，一个除法器串行算 3 次（最亮通道增益恒 Q4.12=4096）；
   消隐期时间充裕（每拍 1 bit，24 拍/次 + 移位对齐）
4. **限幅**：0.25..4.0 → Q4.12 [1024, 16384]
5. **EMA 平滑**（帧间）：`gain_new = gain_old + (gain_t - gain_old) >> csr_speed_i`
   （默认 speed=4 即 1/16/帧，30fps 下 0.33s 收敛到 90%——与 viewer speed=0.1 等效量级）
6. **失效保护**：`n_total == 0`（黑场）或均值 < 1 → 保持旧增益不变

### 3.3 阶段三：增益施加（随像素流）

每像素按其子面通道乘对应增益（4 个 DSP，10bit × 13bit → 23bit 取 [21:12] 即 10bit，
饱和截断到 1023）。手动模式（`csr_manual_i`）直接用 `csr_gain_i`，统计/计算照跑
只不更新（便于调试观察）。`csr_en_i=0` 完全旁路（组合直通 + 输出寄存器拍）。

### 3.4 固定点汇总

| 量 | 格式 | 范围 | 位宽 |
|---|---|---|---|
| 通道增益 | Q4.12 | 0.25..4.0 | 13b（1 符号位恒 0 + 4 整数 + 12 小数）|
| 像素 | u10 | 0..1023 | 10b |
| 乘积 | u23 | — | 截 [21:12] 回 u10 |
| 通道累加器 | u24 | ≤ 5.2M | 24b |
| 块计数 | u18 | ≤ 129,600 | 18b |
| EMA | Q4.12 | 移位实现 | 13b |

### 3.5 与 viewer 算法的差异清单（板测回归风险点）

| viewer 行为 | RTL 版 | 风险与对策 |
|---|---|---|
| 亮区 85 分位自适应阈值 | 固定 THR_BRIGHT（CSR 可配，默认 700） | 暗场可能永不触发中性块→回退灰世界；板测观察后调 |
| EMA speed=0.1 浮点 | 移位 1/16（CSR 4..8 可配） | 等效量级，闪烁风险低 |
| 灰世界回退含互补色偏 | 同为全帧均值回退 | 已知局限（单色场景），v2 SoG 改善 |
| 增益白块限幅/掩膜逐帧重估 | 中性判定固定阈值版 | 草地/白灯场景需板测回归（§7 场景 V3/V4）|

## 4. 状态机

```
STATS →(帧尾)→ COMPUTE(除法×3+EMA) →(完成|消隐结束)→ STATS
BYPASS(csr_en=0) 与 MANUAL 不改状态机，仅改输出 mux 与增益更新门控
```
One-hot 编码，`(* fsm_encoding = "one-hot" *)`；COMPUTE 溢出保护：消隐期结束前
未算完 → 丢弃本轮结果用旧增益（dbg_mode_o=3 上报）。

## 5. 复位与属性

- 复位：`rst_n_i` 为链路现有时钟域同步释放复位（PLL lock 门控，§4/§8 硬约束已满足）；
  模块内不再建第二套同步链，仅控制逻辑用复位，累加器靠帧边界清零
- 累加器/增益寄存器：无高扇出风险（<50）；增益 4 路 DSP 输出寄存器化
- 无 BRAM/无分频时钟/无跨域路径

## 6. 资源与时序预算

| 项 | 估算 |
|---|---|
| LUT | ~1.2k（统计比较器+累加+除法状态机+CSR）|
| DSP | 4（增益乘法；除法用移位减实现不占 DSP）|
| FF | ~800（累加器+增益+状态机）|
| 时序 | 关键路径 = 增益乘法 10×13 DSP + 饱和，200MHz 下 DSP 内寄存即可；统计路径 max/min→比较→累加使能，≤ 8 级 LUT，无压力 |

## 7. 验证规格

**参考模型**：Python/numpy（复用 viewer `auto_gains` 统计判据 + 本规格 §3 固定点
语义），testbench 逐帧比对增益（容差 ±1/4096）与输出像素（容差 ±1 LSB）。

| ID | 场景 | 预期 |
|---|---|---|
| V1 | 8 彩条（expected_image 对齐 RGGB）+ 白区中性 | 收敛到 {R,B 补偿}，与参考模型一致 |
| V2 | 全帧灰阶渐变（无中性块） | n_neutral=0 → 回退灰世界，增益≈全 1 |
| V3 | 合成"草地"单色流（G 主导） | 不发散、限幅生效、偏色 ≤ 回退固有水平 |
| V4 | 白灯场景帧序列（录制的板级 RAW 回放） | 收敛目标与 viewer --autowb 结果差 < 10% |
| V5 | 增益瞬变（人为改 WB 真值） | EMA 0.33s 收敛、无过冲振荡 |
| V6 | 黑场/单帧中断 | 增益保持，dbg_mode_o 正确 |
| V7 | BYPASS/MANUAL 模式切换 | 像素直通无损、手动增益立即生效 |

仿真等级建议 FPGA_FUNCTIONAL（算法类模块，无硬 IP 交互）；Native Build 与板级
验证独立进行，不因仿真 PASS 免除。

## 8. 开放决策项（评审时定）

| ID | 决策 | 建议 |
|---|---|---|
| D1 | THR_BRIGHT 固定 700 是否覆盖当前室内灯光照 | 板测 V4 后定；必要时升 85 分位直方图版（+1 BRAM）|
| D2 | SoG(p=6) 回退是否进 v1 | 不进（^6 累加 30bit×4 路，收益/成本比低）；v2 视 V3 板测结果 |
| D3 | 帧同步信号来源（复用魔数检测 vs 自生成计数器） | 自生成（实现简单，规格不变）|
| D4 | 图案流是否也过 AWB | 不过（bypass），图案色彩为设计真值 |
