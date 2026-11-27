[English](cam-i2c-rtl-init-plan.en.md) | 中文
# IMX415 上电自配置 RTL 化（fabric I2C init）实施计划

| 项 | 值 |
|---|---|
| 版本 | **v0.5（P4 板级排障完成，双路出图）** |
| 日期 | 2026-10-24 |
| 目标 | bit 下载后无需加载固件 ELF，fabric RTL 自动完成传感器上电时序 + I2C 配置 + stream-on，直接出像；**配置完成前数据路径保持静默** |
| 关联 | sw/top_demo/src/imx415_init.c（v4.11 起删除，历史母本见 git；ROM 同源源表已迁 tools/gen_imx415_rom.py 内嵌锚点）、[rtl/i2c_master.sv](../rtl/i2c_master.sv)（自研，P1 仿真过、未上板）、[rtl/cam_i2c_init.sv](../rtl/cam_i2c_init.sv)（初始化器）、[top_cam.sv](../rtl/top_cam.sv)（gate_ready/raw_aresetn 挂钩点）、[program.md](program.md)、[readme_4K_1K.md](readme_4K_1K.md) §2.2 |
| 评审人 | 用户（2026-10-24 已定案 Q1/Q3/Q4/Q6，见 §8） |

---

## 1. 背景与目标

现行链路：bit 烧写后 SoC 无程序（**软核程序不入比特流**，program.md §0），必须
openocd 加载 ELF，由固件 `imx415_init(0/1)` 经 SoC I2C 控制器配置传感器后才出图。
本计划把该配置过程搬进 fabric：

- **P0 目标**：JTAG 烧完 bit → 上电自动配置两路 IMX415 → 面板出像，全程无固件。
- **P1 目标**：固件与 I2C **彻底解耦**——删除固件全部 I2C 配置职能；固件二进制
  变为可选调试工具（仅 UART 心跳 + DIAG 读数，见 §4.6）。
- **P2 目标**：**配置完成前数据路径不工作**（init_done 门控，§4.5）。

## 2. 现状盘点（可行性事实基础）

### 2.1 固件配置流程（RTL 需复刻的最小集）

`imx415_init_once()` 实测流程：

| 步骤 | 内容 | RTL 取舍 |
|---|---|---|
| L0 电源时序 | cam_en 低 300ms（硬复位/放电）→ 高 → 12ms 后才可访问 I2C | **必须复刻** |
| L0 总线恢复 | i2c_masterRecover（9 SCL 脉冲）+ 线电平检查 | V1 以 cam_en 断电替代（传感器掉电必释放总线，板级经验：楔死靠 power cycle 清） |
| L1a ID 探测 | CHIP_ID 0x3F12 读 + 总线扫描（本批次 SENSOR_INFO 未编程，恒走 fallback） | **省略**（纯诊断） |
| L1b 基表写入 | 109 条（standby/format/SONY magic/legacy 几何/时钟参数），**顺序敏感**（magic 块必须在 VMAX/HMAX/时钟仍是复位默认时写） | **必须逐条复刻** |
| 几何块 | cam0 geo4k 11 条 / cam1 geo1080 11 条（两路仅此不同：0x3020/21/22 binning、0x30D9/DA DIG_CLP，共 5 条值不同） | **必须复刻**，按路选表 |
| LANEMODE | 0x4001=0x03 + 0x4002=0x00 | **必须复刻** |
| DPHY 时序 | 9 条 16bit LE（0x4018..0x4028，TCLKZERO 高字节 0x401F=0x01 必写） | **必须复刻** |
| L1c 读回校验 | 9 个关键寄存器读回 + 一次重写重读 | **不做**（评审定案 Q3） |
| L1d stream-on | 0x3002=0（standby 中先写）→ 0x3000=0（释放）→ 220ms 稳定 | **必须复刻**，220ms settle 仅诊断不阻塞 |
| 外层重试 | 整轮 3 次，次间 500ms 放电 + 300ms 断电 | **必须复刻** |

表规模：109 + 11 + 2 + 18 + 2 = **142 条写事务/摄**。（P2 执行勘误：imx415_init.c 实测基表 109 条——format/magic 78 + legacy geo 19 + clock 12；文件头"107-entry"注释过时，生成器断言以 109 为准。）
每条写 = START + {0x34, regH, regL, val} 4 字节 + STOP，逐字节 ACK 校验，
单条 NACK 重试 ≤10 次（间隔 10ms）。

### 2.2 管脚与控制器现状（可行性的关键利好）

[top_cam_demo.sv](../rtl/top_cam_demo.sv) L431-508：

- `cam_x_scl/sda` 是 **peri 层开漏模拟 GPIO**（`syn_peri_port=0` 顶层端口
  i/o/oe 三线），**不是 SoC I2C 硬核专用焊球**。SoC I2C 控制器只通过
  `w_i2c_x_*_write` 一根线驱动 oe（`cam_*_oe = ~write`，drive-low/release
  语义）。→ **RTL 接管 = 只改顶层赋值源，peri.xml / interface designer 完全
  不动，板级接线不变。**
- `cam_x_en` = SoC GPIO0 `w_gpio_write[0/1]`，寄存器复位 0（传感器默认断电）。
  RTL 接管需改驱动源（见 §4.4）。
- [ws-e1-cam-ddr-csi2.sdc](../ws-e1-cam-ddr-csi2.sdc) L42-66 已有 cam_* 六组
  端口对 `sys_clk_200m` 的 input/output delay 约束——切换驱动源后约束仍适用，
  SDC 无需改动。
- wrapper 挂 **sys_clk_200m**（与 SoC 同钟同复位树 `sys_clk_200m_rstn`），
  全设计单域，**无 CDC**。
- SCL 速率沿用 **50kHz**（板级飞线总线实测结论 100k→50k→25k→10k→50k，
  勿改 i2c_master 默认 400k）。

### 2.3 i2c_master.sv 评估

**结论：可用作字节层引擎；系自研模块，仿真验证过、未上板——P1 功能验证为
强制前置门，通过前不进集成。允许修改。**（评审定案 Q6）

协议正确性（代码审阅 + verible-syntax 实测 2026-10-24 通过，exit 0 无语法错误）：

| 检查项 | 结果 |
|---|---|
| 开漏约定 | `pad_o=1` 释放 / `0` 拉低——与现有 pad 的 `oe=~write` 语义**精确同构**（`oe = ~pad_o` 即完成映射） |
| START/STOP 时序 | SDA 仅在 SCL 高时变化、STOP 前双保持、防幻影 STOP（ST_HOLD 桥接）——头注释逐条对齐 I2C 规范 |
| 重复 START | ST_START_PRE 专门给 slave 滤波器建立时间（读操作原语已具备；V1 无读用例，仍保留覆盖） |
| 时钟拉伸 | SCL_H 相等待 `scl_pad_i` 实际拉高 + SCL 看门狗（超时置 err、abort 回 IDLE） |
| 命令集 | START/TX(含 NACK 采样)/RX(含 ACK·NACK 发送)/STOP/RESET——覆盖 16bit 寄存器写与读全部原语 |
| 命令间协议 | 每命令 `go` 脉冲启动、`done` 单拍结束；字节间隙 FSM 停在 ST_HOLD（SCL 保持低、busy=0），wrapper 只需等 done 再发下一命令 |
| err 语义 | **sticky**，仅 CMD_RESET 或成功 STOP 清除——wrapper 错误路径必须先发 CMD_RESET |

差距与配套动作：

| # | 差距 | 动作 |
|---|---|---|
| G1 | 无 bus-recover（9 SCL 脉冲）原语 | V1 不做（cam_en 断电释放总线替代）；已获修改许可，CMD_RECOVER（约 40 行）作为 P2 可选加固 |
| G2 | 仓库内无其 TB（头注释提及的 testbench 不在库） | **P1 补 `sim/tb_i2c_master.sv`（强制前置，见 §6）** |
| G3 | 默认参数 100MHz/400kHz 不适用 | 例化 `SYS_FREQ=200_000_000, I2C_FREQ=50_000`；看门狗 SCL_TIMEOUT_CYCLES 复核（200M 下 20000 拍 = 100µs = 10 个半周期，对 50kHz 足够） |
| G4 | 尚未过 vlog/efx_map（仅 verible 过） | SV enum + always_ff/always_comb 混用在项目内有先例（*.sv 文件），P1 以 vlog 0 Error 为门 |
| G5 | 未在 XML 编译清单 | P3 登记进 `ws-e1-cam-ddr-csi2.xml` design_info（历史坑：milestone-v4.11 §5-#11） |

## 3. 总体架构

```
sys_clk_200m / sys_clk_200m_rstn
┌──────────────────────────── top_cam_demo ────────────────────────────┐
│  u_cam_0 (top_cam, 4K60)                    u_cam_1 (top_cam, 1080)   │
│  ┌─────────────────────────────────┐       ┌───────────────────────┐ │
│  │ u_i2c_init_0 (cam_i2c_init)     │       │ u_i2c_init_1          │ │
│  │  power FSM + walk FSM + ROM     │       │  start = u_i2c_init_0 │ │
│  │  done_ok ──→ 本路数据路径放行     │       │  .done_ok（错峰启动）   │ │
│  └──┬──────────────┬───────────────┘       └──┬──────────┬─────────┘ │
│     │ cam_en       │ scl/sda(i/o/oe)          │          │           │
│     ▼              ▼  [i2c_master ×1]        ▼          ▼           │
│  gate_ready   pad 直驱（开漏映射）       同构（晚 ~0.7s 启动）        │
│  &init_done   SoC I2C 写线撤除                                       │
└─────┬──────────────┬─────────────────────────────────────────────────┘
      ▼              ▼
   cam_0_en    cam_0_scl/sda → IMX415#0        cam_1_* → IMX415#1
```

**实例化位置：`cam_i2c_init` 放在 top_cam 内**（每摄一个，与 apb_cam_ctrl 同层）
——传感器 I2C/上电/放行是单摄内聚职能；top_cam 新增 pad 端口，top_cam_demo
只做端口转发与 SoC 写线撤除。

模块清单：

| 文件 | 新/改 | 职责 |
|---|---|---|
| rtl/i2c_master.sv | 已有（可选微改 G1） | 字节层引擎 |
| rtl/imx415_rom.sv | **新（生成）** | 寄存器表 ROM（`MODE_4K` 参数 = 4K/1080；case ROM，24b×142 条 + `last_idx` 表尾输出防双源漂移） |
| rtl/cam_i2c_init.sv | **新** | 上电时序 FSM + 走表 FSM + NACK/整轮重试 + init_done/状态输出 |
| rtl/top_cam.sv | **改** | 例化 u_i2c_init + pad/en 端口 + **gate_ready & init_done + raw_aresetn & init_done**（§4.5）+ DIAG3 布线 |
| rtl/top_cam_demo.sv | **改** | pad 端口转发到两路 top_cam；SoC I2C 写线与 w_gpio_write 撤除 |
| ws-e1-cam-ddr-csi2.xml | **改** | design_info 登记 2 个新文件 |
| sw/top_demo/src/main.c | **改** | 删除全部 I2C 配置职能（imx415_init/stream_on/off、I2C 菜单键）；保留 UART 心跳（读 DIAG 组，含 init 状态）——可选调试固件 |
| sim/tb_i2c_master.sv | **新** | 字节引擎单元 TB（P1 强制前置） |
| sim/tb_cam_i2c_init.sv | **新** | 序列 golden 比对 + 注错 + 错峰/放行联动 TB |
| tools/gen_imx415_rom.py | **新** | 从 imx415_init.c 表格生成 ROM 与 golden 序列文件（同源防抄错） |

资源预估：i2c_master ~300 LUT + wrapper ~400 LUT + ROM（140×24b case）×2 摄
≈ **合计 < 2k LUT**，TJ180 无压力。

## 4. 关键设计

### 4.1 cam_i2c_init 状态机

```
IDLE(等 start) ──→ PWR_OFF(300ms, cam_en=0) → PWR_SETTLE(12ms, cam_en=1)
  → BUS_CHK(采样线电平,仅记状态位)
  → WALK（逐条: LOAD_ROM → START → TX×4(等 done,查 nack) → STOP
           nack? → RETRY_ENTRY(≤10次, 间10ms) → 尽头? → FAIL_ROUND）
  →（末两条 = stream-on 0x3002/0x3000）
  → DONE_OK：init_done 置位（数据路径放行）；220ms settle 仅诊断计数
FAIL_ROUND → DISCHARGE(500ms) → PWR_OFF（≤3 轮）→ INIT_FAIL(sticky，init_done 恒 0)
```

- 计时基准 200M，长延时（300/500/220ms、10ms）用 32bit 分频计数器。
- **错峰**（评审定案 Q4）：cam0 上电即启动；cam1 `start` 接 cam0 `done_ok`
  ——cam1 在 cam0 配置完成后才开始上电时序，防双传感器同时上电浪涌。
- **无读回校验**（评审定案 Q3）：NACK 尽头直接整轮重试（power cycle 兜底）。
- CSR 软复位位可重触发 INIT_FAIL 后的重跑（调试用）。

### 4.2 ROM

- 单条 24b = {reg[15:0], val[7:0]}；142 条 case ROM。
- **脚本生成** `imx415_rom.sv`（及 TB golden 序列文件）自 imx415_init.c 同源
  表格——杜绝手抄错误（风险 R4）。
- 两摄差异仅 geo 块 5 条值：ROM 带 `MODE` 参数（4K/1080）生成两套完整表，
  不做运行时 patch（简单直白，零逻辑）。
- **写入顺序即表序**，SONY magic 块顺序敏感不许重排（readme §7 / 表注释）。

### 4.3 状态诊断

每路挂自己 apb_cam_ctrl（top_cam 内嵌，两摄分别在 APB0/APB1 同地址）的退役
DIAG 槽（v0.4 勘误：**DIAG3 @0x0C**——原文 0x18 系笔误，word3=byte 0x0C，
raw 断流定位已退役）：

```
{fail[16], done[15], busy[14], round[13:12], retry[11:8], idx[7:0]}
```

另加 **rerun 软触发**（评审 Q2"RTL 软复位重跑"落地）：退役 DIAG7 槽
（**@0x1C**）复用为 RW sticky 位 `[1:0]`（bit0=本实例，写 1 置位；
top_cam 内打两拍沿检测接 `cam_i2c_init.start`，软件写 0 归位等下次）。

bit-only 无固件时不可读；排障时插"只读"固件经 UART 查询转印（§4.6，
main.c '0' 键状态 / 'y' 键 rerun 已实现）。

### 4.4 cam_en 归属与 I2C pad 接管（集成核心）

```systemverilog
// top_cam.sv 新增端口（每摄）：
//   output cam_en,  input scl_i, output scl_o/scl_oe, input sda_i, output sda_o/sda_oe
// top_cam_demo 端口转发 + SoC 写线撤除；开漏映射（约定同构）：
assign cam_0_scl_o  = 1'b0;
assign cam_0_scl_oe = ~u_cam_0_scl_pad_o;        // pad_o=1(释放) → oe=0
// cam_en：RTL 专责（u_i2c_init_x.cam_en 直驱），w_gpio_write 撤除
```

- SoC GPIO `w_gpio_write` 不再连 cam_en，固件 main.c 同步删 I2C/GPIO 相关
  调用——防双主冲突（风险 R6）。
- 复位释放前 cam_en 电平 = peri GPIO 复位默认输出值，**需板级确认**传感器
  en 脚外部默认为低（风险 R3；如 peri 复位态非 0，在 interface designer 设
  输出初值 0 或由 wrapper 上电即驱动 0 覆盖）。

### 4.5 配置完成 → 数据路径放行（评审新增需求）

[top_cam.sv](../rtl/top_cam.sv) L770/L802 现状：

```
gate_ready  = fw_flush_done                    // 开门条件
raw_aresetn = sys_clk_200m_rstn & sw_rstn      // raw 域复位
```

改为两处单行（init_done 为 cam_i2c_init DONE_OK，200M 同域直连，无 CDC）：

```systemverilog
assign gate_ready  = fw_flush_done & init_done;                    // 开门前置
assign raw_aresetn = sys_clk_200m_rstn & sw_rstn & init_done;      // raw 域等配置
```

语义与安全性论证：

- `sw_gate` 上电为 0 + 引导链不变：init_done 前传感器无流（cam_en 都没上电），
  引导链本就无触发；init_done 后传感器出流，首 vs 下降沿走既有 flush 引导 →
  gate_ready 齐备 → 下个帧头开门。**与现行上电引导时序完全同构，只多一个
  前置与项**，源切换路径零改动。
- **frame_writer / reader 的 AXI 主口永不复位**（硬纪律 #1）——"不工作"由
  无输入数据自然保证：writer 无流不发布（整帧或全无），reader 无请求沿不发射。
  两者不是被 init_done 门控的对象。
- INIT_FAIL 时 init_done 恒 0：该路数据路径永久静默（黑屏），经 CSR 软复位
  重跑或重烧 bit——符合"配置没完成就不给数据"。
- TB 对接：现行 TB（tb_phase4 系）若绕过 top_cam 直连模块链，则 init_done
  端口接常量 1（等效"配置已完成"稳态），既有用例零改动；门控联动行为由
  tb_cam_i2c_init 集成用例 + 板级 bring-up 覆盖。
- **上电默认源 = 摄像头（已 RTL 实证）**：CTRL_RESET=32'hB4EB_C814
  （apb_cam_ctrl.sv L36，pat_en=0）+ pat_sel_eff 复位 0 → 源 mux 走传感器
  直通，wb/blk_clip 为相机域行为。bit-only 配置完成后**无需任何 CSR 写**即
  出图；图案源仅 UART 'p' 显式切换（需固件）。附带发现两处 v3 过时注释
  （apb_cam_ctrl.sv L9-10"复位默认 1"、top_cam.sv L566-567 sw_src_q 复位
  2'b10 及注释）——值不影响功能（上电 1 拍假沿被 c3c 帧界触发机制吸收，
  c3m/v4.11 板测双绿），P3 顺手改正注释与复位值。

### 4.6 固件定位（评审定案 Q1）

**I2C 相关固件职能全部删除，调试通道保留：**

- main.c 删除：`imx415_init(0/1)` 调用、stream_on/off、I2C 菜单键、cam_en
  GPIO 操作。固件不再触碰 I2C 控制器与 cam_en。
- main.c 保留：UART 心跳（0.5s DIAG 组打印，**新增 init 状态字段**）、CSR
  运行时调节键（白平衡/相位/切源/图案）。
- 部署形态：日常 = **bit-only 出图，不加载固件**；排障 = 按需插入该"只读"
  ELF（openocd 加载，与 bit 独立，program.md §2）。

### 4.7 时钟域与 SDC

单域 200M；SDC cam_* 约束沿用；50kHz SCL 全局慢信号，无新增约束需求
（PnR 时序全绿为准）。

### 4.8 时间预算（50kHz，错峰）

| 项 | 耗时 |
|---|---|
| 单字节（9 SCL @50k） | 180µs |
| 单条写事务（START+4B+STOP） | ~0.78ms |
| 142 条全表 | ~111ms |
| 电源时序（300ms 断 + 12ms 稳） | 312ms |
| **cam0 名义出图**（含 reader 门控 ~35ms） | **~0.7s** |
| cam1（错峰，等 cam0 done_ok 后重新走全流程） | **~1.4s** |
| 最坏（某路 3 轮重试） | +~2.5s |

## 5. 验证计划

| 层 | TB | 用例 |
|---|---|---|
| 字节引擎（**P1 强制前置**） | tb_i2c_master.sv（新） | 单字节写/读、重复 START、NACK 捕获、时钟拉伸、SCL 看门狗 err→CMD_RESET 恢复、STOP 后真空闲、复位释放期行为 |
| 初始化器 | tb_cam_i2c_init.sv（新） | golden 序列全比对（顺序+值，与 ROM 同源生成）；恒 NACK→3 轮重试→INIT_FAIL；SCL 卡低→err 重试；中途恢复→重试成功；**init_done 仅在 stream-on 两条写完后置位**；**错峰：cam1 start 不得早于 cam0 done_ok** |
| 全项目 | 现行回归 | verible → vlog 0 Error → tb_phase4 / tb_phase4_ddrm / tb_phase5_cam1 全绿（init_done 接常量 1，既有用例零改动）→ efx_map 编译过（XML 登记生效） |
| 板级 | bit-only bring-up | ① 烧 bit 不插 ELF，量出图时间（预期 cam0 ~0.7s / cam1 ~1.4s）；② 插只读 ELF 判读 DIAG3/nack_cnt；③ 异常演练：一路传感器断电→观察 3 轮重试→确认另一路不受扰、配置失败路保持黑屏 |

流程纪律沿用：vlog 0 Error 才允许 vsim；efx_map/vlog 查声明顺序与多驱动（verible 不过这些）。

## 6. 分阶段实施

| 阶段 | 内容 | 出口判据 |
|---|---|---|
| **P1 字节引擎功能验证（强制前置门）** | tb_i2c_master 全用例 + G3 参数复核 +（可选）CMD_RECOVER 改造 | vsim 全绿；**未过此门不进任何集成** |
| P2 初始化器 | gen 脚本 → ROM + cam_i2c_init + tb_cam_i2c_init | vsim golden 0 错 + 注错/错峰/放行用例全过 |
| P3 集成 | top_cam 挂接 + gate 放行 + top_cam_demo 端口转发 + XML 登记 + main.c 去 I2C 化 + 全回归 + 出片 | 三 TB 绿 + map/pnr/pgm PASS |
| P4 板级 | bit-only 出图 + 计时 + DIAG 判读 + 异常演练 + cam_en 复位电平确认 | 无固件双路出图；重试/放行路径实锤 |
| P5 文档 | readme_4K_1K / program.md / 里程碑存档 | — |

改动边界：显示链/DDR/回放仅增加 `& init_done` 一个与项（§4.5），其余零触碰；
板级回归风险集中在 I2C bring-up 本身。

### 6.1 执行记录

| 阶段 | 状态 | 记录 |
|---|---|---|
| P1 | **完成（2026-10-24）** | `sim/tb_i2c_master.sv` 新建（开漏总线 + slave BFM + T0~T8：空闲电平/完整写/连续写/重复 START 读/地址 NACK/时钟拉伸/看门狗 err+CMD_RESET 恢复/err 后新事务/200M·50k 实参数冒烟）；vlog 0 Error，vsim **PASS errors=0**。**i2c_master.sv 修复 3 处**：① `scl_timeout` 双进程驱动（vopt-7061，iverilog 不报）——清除路径并入看门狗唯一进程；② 真 bug：CMD_RESET 实际不清 `scl_timeout`（注释声称清除），看门狗 abort 后模块永久卡死（STOP 各态见 flag 即 abort，永远到不了能清 flag 的 STOP_B）——随 ① 一并修复落实；③ `CNT_LOW_END/CNT_HIGH_END` 声明前移到看门狗进程之前。**G3 结论**：200M/50k 实参数实测 SCL 半周期恰 10µs、看门狗 100µs=10 个半周期足够；例化必须显式传 `SYS_FREQ=200_000_000, I2C_FREQ=50_000`。TB 层教训：slave BFM 的 `sda_pull` 极性（1=拉低=ACK）；命令 `go` 脉冲必须 negedge 锚定整拍（posedge 后直发只覆盖半拍，master 采样不到会永久停在 ST_HOLD）。 |
| P2 | **完成（2026-10-24）** | **P2-1**：slave BFM 拆出 `sim/i2c_slave_bfm.sv`（多 TB 复用），新增 `cap_list[$]` 捕获队列与 `n_stop` 计数（层次化访问）；P1 回归 PASS。**P2-2**：`tools/gen_imx415_rom.py` 同源解析 imx415_init.c → `rtl/imx415_rom.sv`（142 条 case ROM，`MODE_4K` 双 geo 分支，`last_idx` 输出防双源漂移）+ `sim/imx415_seq_cam{0,1}.hex` golden；**勘误：基表实为 109 条**（format/magic 78 + legacy geo 19 + clock 12，源文件"107-entry"注释过时）；脚本内建断言（条数/standby 首条/TXCLKESC 尾条/geo 11 条与 VMAX·HMAX 值/DPHY 9 行与 TCLKZERO hi=0x01/stream-on 顺序/LANE_MAP_TEST=0 取 #else 分支值）。**P2-3**：`rtl/cam_i2c_init.sv`——FSM：IDLE→PWR_OFF(300ms)→SETTLE(12ms)→LOAD→START/TX×4/STOP→NEXT…；NACK/err 统一 CMD_RESET 归位 + RETRY_GAP(10ms) 重试 ≤10 次/条 → DISCHARGE(500ms 断电) 整轮 ≤3 轮 → DONE(init_done 保持)/FAIL(sticky)；start **上升沿**触发（完成回 IDLE 后不被残留电平重复触发，错峰接 cam0 init_done 电平）；周期常数 `(SYS_FREQ/1000)*MS`（200M·500ms=1e8，32bit 无溢出）；内嵌 i2c_master + imx415_rom，pad 级接口（pad_o=1 释放）。**P2-4**：`sim/tb_cam_i2c_init.sv` 三实例（cam0/cam1 错峰从机/camf 注错）四用例全过 **PASS errors=0**：C1 cam0 全序列 golden 比对 142/142 + 电源时序；C2 cam1 由 cam0 init_done 自动启动、golden(cam1/geo1080) 142/142；C3 地址恒 NACK → 3 轮重试（round=3）→ init_fail sticky、init_done=0、cam_en 保持；C4 rerun 清 sticky 全序列再成功 142/142。调试记录：ref 实参与 fork 不兼容（vlog-13219，wait_flag 改轮询）；TB 例化 SYS_FREQ 误写 10k 致 `T_SCL=0→CNT_W=0→[CNT_W-1:0]` 反向（vopt-3373），已加 `SYS_FREQ/I2C_FREQ<2` $fatal 防呆。 |
| P3 | **完成（2026-10-24）** | **P3-1a** `apb_cam_ctrl.sv`：退役 DIAG3 槽（@**0x0C**，word3）复用为只读观测 `{fail[16],done[15],busy[14],round[13:12],retry[11:8],idx[7:0]}`（§4.3 原文 0x18 系笔误，随本版勘误）；退役 DIAG7 槽（@0x1C，word7）复用为 RW rerun sticky `[1:0]`（写译码扩 word7，同 CTRL2 复用模式）。**P3-1b** `top_cam.sv`：+`MODE_4K` 参数与 cam_i2c 端口组 7 根（cam_en/cam_scl/sda pad i+o/cam_i2c_start/cam_init_done）；u_cam_ctrl +2 端口；rerun sticky 打两拍沿检测（pclk=sys_clk_200m 同域）接 `start = cam_i2c_start \| rerun_pe`；`u_i2c_init` 例化（SYS_FREQ=200M/I2C_FREQ=50k/MODE_4K 透传，复位不含 init_done 防自锁）；**§4.5 两处与项落地**：`gate_ready = fw_flush_done & i2c_init_done`、`raw_aresetn = sys_clk_200m_rstn & sw_rstn & i2c_init_done`；顺手勘正 sw_src_q 复位值 2'b10→2'b00 + 注释（CTRL_RESET 改 pat_en=0 后遗留，sw_src_chg 无消费者故历史无害）。**P3-2** `top_cam_demo.sv`：cam_en 与 pad oe 驱动源切 init 模块（`oe=~pad_o`），SoC I2C write 线悬空、read 线保留作总线观测（Q1）；错峰链：u_cam_0 `start=1'b1`（复位释放自然出沿）、u_cam_1 `start=cam0_i2c_done`；`MODE_4K` 1/0 透传；u_cam_1 cam_init_done 悬空留 TB 探测（观测走 APB1 DIAG3）。**P3-3** 固件去 I2C 化：`imx415_init.c/h` 删除（makefile wildcard 无引用）；main.c 删 imx415_init 调用与 rc 兜底块，新增 `cam_i2c_show`（DIAG3 解码）与 `cam_i2c_rerun`（DIAG7 写 1→延时→写 0），菜单 +`[0]` 状态/`[y]` rerun（目标路）键；userDef.h DIAG3/7 注释更新。**语义变化**：init FAIL 不再自动切图案兜底（固件启动秒级、init 0.7~1.4s，启动期无法可靠判定终态）——FAIL 路黑屏，'p' 手动图案兜底 / 'y' rerun 恢复。**P3-4 回归**：verible 三改动文件 OK；vlog 全 rtl 24 文件 **0 Error 0 Warning**；5 TB 全绿：tb_i2c_master PASS errors=0、tb_cam_i2c_init PASS（C1~C4）、tb_phase4 [P4-OK]、tb_phase4_ddrm [P4C-OK]+[P4-OK]+[SLOW-OK]（补编 ddr_ctrl_model 模型库进 work）、tb_phase5_cam1 [P4C-OK]+[P5-OK]+[SLOW-OK]（TB 均不例化 top_cam，端口变更零波及，实证 §4.5 "init_done 接常量 1" 预判不需要）。**P3-5 出片**：XML 登记 i2c_master/imx415_rom/cam_i2c_init 三文件；efx_run compile **map/interface/pnr/pgm 全 PASS**（~4min），err.log 空、无 timing violated、warn 无新模块条目。 |

## 7. 风险

| # | 风险 | 缓解 |
|---|---|---|
| R1 | i2c_master 自研、仿真过但**未上板**（评审确认） | P1 设为强制前置门：单元 TB 全覆盖后才允许集成；板级分步 bring-up（先单字节 probe 再放全表） |
| R2 | 无固件 = 无心跳，黑屏时无从判读 | 部署形态 = bit-only 出图；排障插"只读" ELF 看 DIAG3 |
| R3 | cam_en 复位默认电平未确认（peri GPIO 复位态） | P4 首项实测；必要时 interface designer 设初值 |
| R4 | 表格转写错误 → 传感器 wedge | 脚本同源生成 + TB golden 比对 |
| R5 | 双摄同时上电浪涌 | 错峰启动（Q4 定案） |
| R6 | 固件残留 I2C/GPIO 操作与 RTL 冲突 | P3 同步删 main.c 全部 I2C 职能，审计 `imx415_*`、`cam_gpio_*`、`i2c_*` 引用清零 |

## 8. 评审定案记录（2026-10-24）

| # | 问题 | 定案 |
|---|---|---|
| Q1 | 固件去留含义 | 固件二进制去留本身可选；**I2C 配置职能从固件中彻底删除**（bit-only 出图不再依赖固件），调试时按需插入"只读观测"固件（§4.6） |
| Q3 | 读回校验 | **不做**（NACK 重试 + 整轮 power-cycle 兜底） |
| Q4 | 双摄并行/错峰 | **错峰**：cam1 等 cam0 done_ok |
| Q6 | i2c_master 来源与许可 | 用户自研，仿真验证过、**未上板**；**P1 功能验证为强制前置**；允许修改 |
| Q2 | 固件 I2C 后备通路（pad mux） | 未反对，按建议执行：V1 不做，排障用"RTL 软复位重跑"替代 |
| Q5 | i2c_master 加 CMD_RECOVER | 未反对，按建议执行：允许修改前提下作为 P2 可选加固 |

## 9. 变更记录

| 版本 | 日期 | 说明 |
|---|---|---|
| v0.1 | 2026-10-24 | 初稿（可行性 + 架构 + 开放问题） |
| v0.2 | 2026-10-24 | 吸收评审定案：Q1 固件去 I2C 化（§4.6 重写）、Q3 删读回校验、Q4 错峰启动、Q6 P1 强制前置门；**新增"配置完成→数据路径放行"机制（§4.5：gate_ready/raw_aresetn 与 init_done）**；实例化位置定 top_cam 内；验证计划补放行/错峰判据 |
| v0.3 | 2026-10-24 | P1、P2 执行完成（§6.1）；勘误：基表实测 109 条（非 107），全序列 142 条/摄（非 140）；ROM 增加 `last_idx` 输出；cam_i2c_init start 定为上升沿触发 |
| v0.4 | 2026-10-24 | **P3 集成完成（§6.1）**：top_cam 挂接（gate_ready/raw_aresetn 两处与项）+ top_cam_demo pad/cam_en 接管与错峰链 + XML 登记三文件 + main.c 去 I2C 化（imx415_init.c/h 删除，'0' 状态/'y' rerun 键）；勘误：DIAG3 地址 0x18→**0x0C**（§4.3）；rerun 软触发落地为 DIAG7@0x1C RW sticky（Q2）；语义变化：init FAIL 不再自动切图案兜底（启动期无法可靠判定终态），'p' 手动兜底 / 'y' rerun；全回归 5 TB 绿 + compile map/interface/pnr/pgm 全 PASS |
| v0.5 | 2026-10-24 | **P4 板级排障完成，双路出图**：① v4.11b 修 ST_DISCHARGE 漏清 retry（板测 retry=12=10+1+1 根因）；② DIAG3[19:17] 塞 pad 观测 {cam_en, sda_i, scl_i}，'0' 打印改四态标签（FAIL/done/busy/idle）；③ **v4.11c 根因修复**：top_cam_demo P3-2 pad 接管时删除旧 SoC GPIO0.bit0 → cam_0_en/1_en 路径后**漏接新源**，pad 端口全文件零驱动 -> 传感器不上电 -> I2C 全 NACK（DIAG3 en=1 读的是 init 模块内部信号，非 pad，具有迷惑性）；补 `assign cam_0_en=cam0_en / cam_1_en=cam1_en`。板测实证：cam0/cam1 均 done idx=141 retry=0 round=0（142 条一次通过零重试），fw frm≈1996 / fw1 frm≈1968，cnt df=45/45 满帧率零丢帧，yuv 持续出帧 |
