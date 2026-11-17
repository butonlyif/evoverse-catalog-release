[English](wb_design_spec.en.md) | 中文

# RAW10 域白平衡设计规格

| 项 | 值 |
|---|---|
| 版本 | **v0.2（实施完成，待板级验证）** |
| 日期 | 2026-10-24 |
| 状态 | RTL/CSR/固件/TB 已实现，板级 bring-up 待做 |
| 变更 | v0.1→v0.2：默认值改中性 1.0（R7 推翻，200/235/180 板级实证画面发绿）；wb_axis 退出路径改 rgb10_to_rgb8（Q3 落地）；接口补 bayer_phase；行奇偶改当拍组合生效（§3.2）；边带移位深度修正（§3.3） |
| 关联 | `rtl/raw_wb_axis.sv`（新建）、`rtl/rgb10_to_rgb8.sv`（新建）、`rtl/wb_axis.sv`（退役，仅 TB 保留）、`rtl/demosaic.sv`（下游）、`rtl/apb_cam_ctrl.sv`（CSR）、`sw/top_demo/src/main.c`（固件）、`doc/program.md`（部署/菜单） |

## 0. 背景与目标

v4 链（改动前）：

```
CSI -> raw_2_axi4st -> frame_writer -> DDR -> frame_reader 回放
     -> [demosaic] -> wb_axis(RGB10->RGB8) -> rgb2yuv -> shape -> 显示
```

现 WB 在 demosaic 之后（`wb_axis.sv`）：增益 8bit、隐含 ×4 编码（U2.6，
`0x40=1.0`），`(v10*g)>>8` 的移位同时吸收 RAW10->8bit 的 ÷4。板标默认
200/235/180 实测画面发绿（标定失效），白点需重标。

**本稿落地（v5 链）：WB 前移到 demosaic 之前的 RAW10 域，wb_axis 整体退出
路径**——回放流与 demosaic 之间插入新模块 `raw_wb_axis`，输出仍为 AXIS-40
RAW10；demosaic 之后的 10->8bit 量化由新纯量化器 `rgb10_to_rgb8` 接替
（`v8 = v10 >> 2`，与 wb_axis@0x40 位精确等价）：

```
CSI -> raw_2_axi4st -> frame_writer -> DDR -> frame_reader 回放
     -> [raw_wb_axis(RAW10 增益)] -> [demosaic] -> rgb10_to_rgb8
     -> rgb2yuv -> shape -> 显示
```

动因：

- D1 demosaic 引导插值（R/B 站点 G 方向判决）隐含"通道间增益已正确"假设
- D2 后级 CCM/色彩域约定在 WB 之后
- D3 每 beat 乘法 12 次（4px×3ch）降到 4 次（4px×1ch，Bayer 每像素仅属一个通道）
- D4 10bit 域处理：旧链 WB 后立刻量化 8bit，新链把增益放到量化之前
- D5 未来 AWB：通道统计天然在 RAW 域采集，增益源头即写入点

## 1. 需求

| # | 需求 |
|---|---|
| R1 | 逐通道增益 R/G/B 三路；Gr/Gb 共用 G（v1 不做绿不平衡拆分） |
| R2 | 增益定点格式 **U4.12**（16b = 4 整数 + 12 小数），量程 [0, 15.99976]，分辨率 1/4096 |
| R3 | 输出仍 RAW10 AXIS-40，位宽/握手/边带语义不变，demosaic 零改动 |
| R4 | 运行时可调：UART 菜单 `[q/a][w/s][e/d]` 键位、步长（±16 = ±0.25 增益）不变 |
| R5 | 通道判定与 demosaic 站类逐位一致（同一 `c_of` 函数；行奇偶真值当拍生效，见 §3.2） |
| R6 | `pat_en=1`（图案源）时全通道 unity，**位精确直通**（图案已按显示幅度编码，v4.10c 板级结论） |
| R7 | **复位默认 = 全通道中性 1.0（0x1000×3）**。旧板标 200/235/180 已废弃（板级实证画面发绿）；白点经菜单重标后由软件回写（§2.3） |
| R8 | 每路独立增益（复用 per-instance `apb_cam_ctrl`，cam0=APB0 / cam1=APB1 天然分离） |

非目标（v1）：AWB 自动增益环路、Gr/Gb 独立增益、增益 <1.0 的精度优化（允许写入，仅提示丢精度）。

## 2. 定点规格（U4.12）

### 2.1 编码

```
g_fp[15:0] = round(g × 4096)        // U4.12，无符号
1.0 = 0x1000    1.25 = 0x1400    15.99976 = 0xFFFF
```

### 2.2 数据通路数学

```
p    = pix[9:0] × g_fp[15:0]        // 26b 乘积（1023×65535 < 2^26）
q    = (p + 12'h800) >> 12          // +2048 四舍五入
out  = (q > 10'h3FF) ? 10'h3FF : q  // 饱和钳 1023
```

- 1.0 位精确直通：`(v×4096 + 2048) >> 12 = v`（v<<12 与 2048 无进位重叠）
- 饱和等价性：旧链钳 8bit 255 ⇔ 新链钳 10bit 1023，限幅膝点差 ≤1 LSB

### 2.3 复位默认值（R7，v0.2 改版）

**全通道中性 1.0（0x1000）**。v0.1 的"等效迁移"推导（旧板标 F={200,235,180}
U2.6 → g_fp={0x3200, 0x3AC0, 0x2D00}）**作废**：该组旧标定在本板上实测
画面发绿，等效迁移只会把错误标定原样搬进新域。v5 上电即中性白平衡，白点
经 UART 菜单（`q/a/w/s/e/d`，±0.25/键）重标后由软件回写 CSR。

固件影子里程保持 U2.6（1.0 = 0x40 = 64），写 CSR 时 `<<6` 升位 U4.12，
纯移位、键步长语义与旧版一致。

### 2.4 精度声明

像素 10bit（1024 级量化），增益分辨率超过 1/4096 后被像素量化噪声淹没；
U4.12 已是过量设计，更高格式（如 U16.16）在本通路无画质收益、只有乘法器
代价（评审结论 2026-10-24）。

## 3. 微架构（rtl/raw_wb_axis.sv，已实现）

### 3.1 接口

```systemverilog
module raw_wb_axis (
    input  logic         aclk,          // tx_pixel_clk（与 demosaic 同域）
    input  logic         aresetn,       // pixel_rst_n
    // RAW10 AXIS-40 从口（无 tready，气泡=行/帧消隐）
    input  logic [39:0]  s_axis_tdata,  // 4×RAW10，px0 在 LSB
    input  logic         s_axis_tvalid,
    input  logic         s_axis_tlast,  // EOL
    input  logic [2:0]   s_axis_tuser,  // {eof, sol, sof}
    // Bayer 相位（CSR 域，与 demosaic 同源同值 cp_bayer_phase）
    input  logic [1:0]   bayer_phase,   // 0=RGGB 1=GRBG 2=GBRG 3=BGGR
    // 增益（CSR 域准静态，同 wb_axis 惯例；U4.12，1.0=0x1000）
    input  logic [15:0]  wb_r, wb_g, wb_b,
    input  logic         pat_bypass,    // 1 = unity 直通（接 cp_pat_en）
    // RAW10 AXIS-40 主口
    output logic [39:0]  m_axis_tdata,
    output logic         m_axis_tvalid,
    output logic         m_axis_tlast,
    output logic [2:0]   m_axis_tuser,
    // 观测
    output logic [15:0]  dbg_sat        // 含饱和像素的拍计数（16b 自由计数，DIAG21）
);
```

无几何参数——纯逐拍处理，对 GW/LINES 无感知（几何由上游 `raw_2_axi4st`
参数化决定）。

### 3.2 相位生成（R5，与 demosaic 逐位一致）

`c_of` 逐位拷贝 `demosaic.sv`（L417-426），奇偶锚定：每帧首行 = 偶行 =
RGGB 的 R 行（板上相机预览颜色已实证该约定）。每拍 4 像素仅 2 个通道类
（`cp = 拍内像素位`，px0/px2 共用 gA、px1/px3 共用 gB）。

行奇偶实现（v0.2 修正）：

```systemverilog
// 寄存状态：sof 拍清 0，sol 拍翻转（sof/sol 同拍 sof 优先）
// 当拍生效：row_cur = sol/sof 拍组合翻转后的值
wire row_cur = s_axis_tvalid ? (tuser[0] ? 1'b0 :
                                tuser[1] ? ~row_p : row_p) : row_p;
```

**不用寄存值直接查表**——边带与数据同拍，若直接用 `row_p`，每行首拍会错
用上一行奇偶（行首 4px 异色）。`row_cur` 与 demosaic 的 rp=真实内容行奇偶
一致。

### 3.3 数据路（S0 乘法 + 输出寄存，共 2 级）

- 4 lane 并行：`(pix × gX[15:0] + 2048) >> 12`，饱和钳 1023，S0 寄存
- `pat_bypass=1`：gX 强制 `0x1000`（位精确直通，含边带）
- 边带 tlast/tuser 与数据同深度（**2 级**）移位；气泡拍（tvalid=0）边带
  清零，不向气泡后泄漏——`wb_axis.sv` L88-114 原款（数据 2 级则边带必须
  2 级；首版 1 级错位一拍，单元 TB 抓出后修正）
- 资源：4 × 10×16 乘法 @148.5MHz 单周期，无 RAM

### 3.4 准静态增益 CDC 约定

增益为 CSR 域（pclk）多位直入 tx_pixel_clk 域，沿用 `wb_axis` 现行惯例
（准静态信号不改写中无亚稳态窗口；菜单改写瞬间允许单帧级毛刺，与现状
一致，不另加同步器）。

## 4. 顶层集成（top_cam.sv，tx_pixel_clk 域，已实现）

```
frame_reader 回放 -> rd_t*[39:0] 切片 -> raw_wb_axis -> dms_in_t* -> demosaic
demosaic(RGB10) -> rgb10_to_rgb8(RGB8) -> rgb2yuv
```

- 插入点：`dms_in_tdata / cdc_valid / dms_in_tlast / dms_in_tuser` 改由
  `raw_wb_axis` 主口驱动（原直连回放流切片）；指纹探针 B（DIAG9，观测
  `dms_in_t*`）保留原连线，语义变为"WB 后"数据（连续性监测不受影响）
- `pat_bypass = cp_pat_en`（图案源直通）；`bayer_phase = cp_bayer_phase`
  （与 demosaic 同源）
- **wb_axis 退役**：top_cam 不再例化；demosaic -> rgb2yuv 之间由
  `rgb10_to_rgb8`（AXIS-120 -> AXIS-96 纯量化，`v10[9:2]`）接替。wb_axis.sv
  文件保留——tb_phase4/tb_phase4_ddrm/tb_phase5_cam1/tb_dms_feed 平台链
  仍引用（TB 自建链不含 top_cam，与本次改动解耦）
- CTRL[31:8] 老 wb 字段退役：CSR 字段/端口保留（布局兼容），复位与软件
  均写 0x40，硬件无消费者（`cp_wb_r/g/b` 悬空）

## 5. CSR / 固件（已实现）

### 5.1 寄存器（apb_cam_ctrl.sv，per-instance）

| 寄存器 | 地址 | 字段 | 复位值 |
|---|---|---|---|
| WB_RAW0 @0x54（word 21，RW） | `[15:0]` wb_r_raw U4.12 | 0x1000 | `{wb_g, wb_r}` = 32'h1000_1000 |
| | `[31:16]` wb_g_raw U4.12 | 0x1000 | |
| WB_RAW1 @0x58（word 22，RW） | `[15:0]` wb_b_raw U4.12 | 0x1000 | 32'h0000_1000 |
| | `[31:16]` 保留 | 0 | |
| DIAG21 @0x5C（word 23，RO） | `[15:0]` 含饱和像素的拍计数（16b 自由回绕） | — | 0 |

word 21-23 此前空闲（原译码最高 word 20 @0x50），写译码扩展
`paddr[6:2] == 5'd21/5'd22`，读译码加三行。CTRL_RESET 参数改为
`32'h4040_4014`（wb 退役字段 0x40×3 占位；pat_sel=01、pat_en=0、
adaptive=1、phase=0 不变）。中性增益下 DIAG21 应近 0，持续增长 = 增益
过高钳 1023。

### 5.2 固件（userDef.h + main.c，已实现）

- 影子变量沿用 8bit U2.6 域：`clamp8`、`±16` 步（= ±0.25 增益）不变；
  `CAMC_DEFAULT_WB_*` 改 **64**（= 1.0）
- 写 CSR 时换算（`cam_apply`）：`WB_RAW0 = {wb_g<<6, wb_r<<6}`、
  `WB_RAW1 = wb_b<<6`（U2.6 × 64 = U4.12，纯移位）
- `cam_pack`：CTRL wb 字段固定写 0x40（`CAMC_WB_RETIRED`，退役字段无消费者）
- 自检打印期望值改 `0x40404014`；`cam_show` 增加 wb_raw0/1 与 DIAG21 读回

## 6. 验证（已执行部分）

| # | 项 | 状态 |
|---|---|---|
| V1 | 单元 TB `sim/raw_wb_tb.sv`：独立参考模型（标准 Bayer 2x2 位置表 + 规格公式）逐拍比对。T1 unity 位精确+随机气泡、T2 四相位×异增益对照、T3 饱和钳位+dbg_sat 累计对账、T4 舍入边界点（0.5x/1.00024x）、T5 pat_bypass 强制 unity；边带逐拍对齐含气泡不泄漏 | **PASS（8/8 用例，errors=0）** |
| V2 | 通道指派对照：T2 参考模型用独立写的 {row,col} 位置表（非 c_of 转录），行首拍含在内——防行奇偶极性漂移 | **并入 T2，PASS** |
| V3 | 回归：tb_phase4 全绿（P4-OK/P4C-OK/SLOW-OK，内容比特一致 err=0）；该 TB 系自建链直接例化 wb_axis，不含 top_cam/raw_wb，回归性质为"平台链未被误伤"。tb_phase4_ddrm / tb_phase5_cam1 同构未跑，风险低 | **phase4 PASS** |
| V4 | 板级：① 上电中性白平衡出图（不偏色）；② 菜单 ±可调、'x' 复位回中性；③ 'g' 图案路径无任何变化（pat_bypass）；④ DIAG21 中性下近 0、加增益后与高光分布一致 | **待板级** |

## 7. 已决问题（v0.1 review 结论）

| # | 问题 | 结论 |
|---|---|---|
| Q1 | 默认值策略 | **中性 1.0**（v0.1 等效迁移方案作废：旧标 200/235/180 板级实证画面发绿，白点菜单重标） |
| Q2 | DIAG21 饱和计数 | **进本版**（WB_RAW 增益写大后高光削顶观测有用；单元 TB T3 对账） |
| Q3 | 老 CTRL[31:8] wb 字段退役形式 | **字段保留、软件固定 0x40、RTL 消费者拆除**（wb_axis 退出路径，量化职能拆给 rgb10_to_rgb8；比 v0.1 的"绑 0x40 保留在路径"更彻底——无双增益叠加面） |
| Q4 | V3 回归基线 | **无 golden 影响**（phase4 系 TB 自建链例化 wb_axis，不含 top_cam；已跑 phase4 确认全绿） |
| Q5 | U16.16 控制面 | 暂不引入；CSR 直收 U4.12，将来 AWB 在 CPU 边界 `>>4` 量化即可 |
