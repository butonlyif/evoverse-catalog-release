[English](axi-ddr-model-spec-v0.2.en.md) | 中文

# TJ 系列 DDR 硬核控制器 AXI 行为模型设计规格

**文档编号**：SPEC-DDR-AXI-MODEL-v0.2  
**适用对象**：易灵思 TJ 系列 DDR DRAM 硬核控制器（LPDDR4/LPDDR4x）  
**模型等级**：AXI 功能/事务级 + 背压/仲裁/近似延迟  
**依据文档**：UG-DDR-DRAM-TI-v3.0（May 2026）  
**替代文档**：SPEC-DDR-AXI-MODEL-v0.1  
**日期**：2026-10-21  
**状态**：评审修订稿（可进入功能模型实现）

---

## 1. 目的、范围与规范性约定

### 1.1 目的

本文档定义 TJ 系列 DDR 硬核控制器 AXI 侧行为模型的设计规格。模型用于：

- SoC/FPGA 系统功能验证；
- 软件驱动开发和 AXI 互联调试；
- 在缺少厂商 RTL/仿真模型时提供手册合规的 AXI 从端行为；
- 通过参数化队列深度、延迟、outstanding，在实测后逼近真实硬核性能趋势。

### 1.2 范围

**建模范围：**

- 两个 AXI4 从接口（target 0 / target 1）；
- AXI 读写通道、burst、narrow transfer、WSTRB、ID、响应；
- 双端口 round-robin 仲裁；
- 命令队列/写数据队列/读数据队列抽象与背压；
- 参数化读延迟、写响应延迟、仲裁延迟、同步延迟；
- 配置控制器 `CFG_*` 握手状态机；
- 复位行为；
- 理想化 DRAM 存储阵列；
- 地址映射、容量换算、rank/chip-select 行为；
- 手册明示的错误/边界检查。

**不在建模范围：**

- DDR PHY 电气行为（ODT、驱动强度、VREF、ZQ、DBI、DM 电气）；
- LPDDR4/LPDDR4x 命令时序（tRCD、tRP、tRAS、tFAW、刷新、bank 冲突）；
- CA/DQ training、write leveling、read gate/eye training；
- 精确周期级 DRAM 调度；
- 配置寄存器地址/字段映射（手册未公开）；
- 性能签核级精度；
- AXI exclusive access 的完整语义（模型不支持）。

### 1.3 规范性约定

本文档对每条关键行为使用以下标记：

| 标记 | 含义 |
|---|---|
| `[UG]` | 手册明示。实现必须遵循；如手册自身矛盾，按第 3 章勘误处理 |
| `[AXI4]` | 手册未明示，按 AMBA AXI4 规范建模 |
| `[MODEL]` | 模型实现选择或假设，不代表硬核真实行为 |
| `[CONFIRM]` | 需实测或向厂商确认，实现时不得当作已验证前提 |

**总原则：**

1. 手册明示优先于 AXI4 默认；手册未明示时按 AXI4 建模并标注 `[AXI4]`。
2. 手册内部矛盾时，以信号名和全局信号表为准（见第 3 章）。
3. 任何“为了让模型跑通”而做的简化，必须标记 `[MODEL]`，不得在验证报告中写成硬核保证。

---

## 2. 术语

| 术语 | 说明 |
|---|---|
| AXI target | 硬核提供的两个 AXI4 从接口，记为 x=0/1 |
| controller clock / `ctrl_clk` | DDR 控制器时钟，通常为 PHY 数据率的 1/4 |
| AXI clock / `ACLK_x` | AXI 接口时钟，可与 `ctrl_clk` 异步 |
| CMD queue | 控制器命令队列抽象 |
| WD/RD queue | 写数据/读数据队列抽象 |
| OSTD | Outstanding，未完成事务数 |
| CS | Chip Select，rank 选择 |
| ENG | Engineering estimate，工程近似值，不是硬核规格 |
| P99 | 样本的第 99 百分位；定义见测试 spec |
| DUT | 被测评测对象，本文指 TJ DDR 硬核控制器 |
| SLVERR/DECERR | AXI 响应错误类型 |
| EARLY_B | `BVALID` 早于 `WLAST` 返回的写响应模式 |

---

## 3. 手册勘误与解释

UG-DDR-DRAM-TI-v3.0 存在若干排版/OCR/内部不一致。模型实现以下表为准；表中未列的歧义按 `[AXI4]` 或 `[MODEL]` 处理。

| # | 手册位置 | 问题 | 模型处理 |
|---:|---|---|---|
| E1 | Table 6 vs Table 14 | 全局信号表写 `ARSTN_x` 低有效；Reset 表写 `ARST_X` 高有效 | 以 `ARSTN_x` 低有效异步复位为准；`ARST_X` 视为命名/极性笔误 |
| E2 | Table 9 | `BRESP_x[1:0]` 描述写成 “Read response ... status of the read transfer” | 按写响应理解；模型 `BRESP` 返回写事务状态 |
| E3 | Table 8 / Table 10 | Direction 列排版错位，`WREADY`/`ARREADY` 等方向不易读 | 按 AXI4 从端方向实现：`WREADY/ARREADY/RVALID/BVALID` 为输出，数据/地址/控制为输入 |
| E4 | Table 7 `AWCOBUF` 段 | 段落排版混乱；“AWCACHE_x must be set to 'b1111 for AWCOBUF_x” 语义不完整 | 仅当 `AWCACHE=4'b1111` 时解释 `AWCOBUF`；`AWCACHE=4'b0000` 单独定义；其他编码按 `[MODEL]` |
| E5 | Address Mapping | 低密度示例字段边界易误读：`[27:26] Chip select` 与 `[26:12] Row` 重叠；实际应为 `[27]` CS、`[26:12]` Row | 功能访问以线性字节地址为准；字段解码仅用于调试，见 7.9 |
| E6 | Table 15 | “Memory Density” 未写单位，仅写 per channel | 解释为 **Gbit per channel**；模型使用 2^30 二进制换算，见 6.2 |
| E7 | Figure 5 / Figure 6 | `WSTRB` 文本与字节 lane 位置错乱 | 以 AXI4 lane 规则为准：`WSTRB[n]` 对应 `WDATA[8n+7:8n]`；图仅作示例 |
| E8 | Table 5 | 只列出 SIZE=4/5/6 的上限，未列 SIZE≤3 | SIZE≤3 的上限按 AXI4 的 256 beat 建模，标记 `[AXI4]`，列入实测确认 |
| E9 | Table 6 | Clock Domain 列排版错位 | `ACLK_x` 的 clock domain 为 N/A；`ARSTN_x` 同步于 `ACLK_x` |
| E10 | AXI Interface 特性 | 只列 “Incrementing and wrapping burst types”，未列 FIXED | 模型默认不支持 FIXED，返回 SLVERR；`SUPPORT_FIXED_BURST=0` |

> 说明：E1 已覆盖 `ARST_X` 与 `ARSTN_x` 的命名/极性冲突；所有对外接口以 `ARSTN_x` 命名，低有效。`AWCOBUF` 的 `AWCACHE=0000` 组合按 7.4 单独处理，不按 `AWCOBUF_STRICT` 断言。

---

## 4. 模型概述

### 4.1 顶层架构

```text
                 ┌──────────────────────────────────────────────┐
 AXI0 ──────────►│  AXI0 Channel Engine                         │
 (ACLK_0/ARSTN_0)│    ├─ AW/W/B 通道（AWREADY 依赖 WVALID）      │
                 │    ├─ AR/R 通道                              │
                 │    ├─ 合法性检查                             │
                 │    └─ Outstanding/ID 管理                    │
                 ├──────────────────────────────────────────────┤
 AXI1 ──────────►│  AXI1 Channel Engine（同上）                  │
 (ACLK_1/ARSTN_1)│                                              │
                 ├──────────────────────────────────────────────┤
                 │  Round-Robin Arbiter                         │
                 ├──────────────────────────────────────────────┤
                 │  Command Queue（参数化深度）                  │
                 ├──────────────────────────────────────────────┤
                 │  写数据队列 / 读数据队列（参数化深度）         │
                 ├──────────────────────────────────────────────┤
                 │  延迟模型（读/写/仲裁/同步）                  │
                 ├──────────────────────────────────────────────┤
                 │  Address Decoder + 容量/合法性检查            │
                 ├──────────────────────────────────────────────┤
                 │  Ideal DRAM Storage Array                    │
                 │  （MEM_BYTES 线性字节数组）                   │
                 ├──────────────────────────────────────────────┤
 CFG_* ─────────►│  Configuration Controller FSM                │
                 ├──────────────────────────────────────────────┤
                 │  Controller Status Generator（可选）          │
                 └──────────────────────────────────────────────┘
```

### 4.2 模型边界

- **AXI 侧**：完整 AXI4 从端行为；不实现 exclusive access。
- **DRAM 侧**：不暴露真实 DQ/DQS 引脚，内部用线性字节存储阵列替代。
- **配置侧**：只建模 `CFG_RESET/CFG_START/CFG_DONE/CFG_SEL`，不建模配置寄存器总线。
- **状态侧**：输出抽象控制器状态信号，具体定义见第 15 章，均为 `[MODEL]`。
- **性能侧**：延迟/队列/仲裁为趋势模型，不是周期精确模型。

---

## 5. 接口定义

### 5.1 AXI 全局信号

模型提供两个 AXI4 从接口，x = 0 或 1。

| 信号 | 方向 | 时钟域 | 说明 |
|---|---|---|---|
| `ACLK_x` | 输入 | — | AXI 时钟，可与 `ctrl_clk` 异步 `[UG]` |
| `ARSTN_x` | 输入 | `ACLK_x` | AXI 接口低有效异步复位 `[UG]` |

> `ARSTN_x` 的极性以信号名和 Table 6 为准；Table 14 的 `ARST_X active-high` 是勘误 E1。

### 5.2 写地址通道

| 信号 | 方向 | 位宽 | 说明 |
|---|---|---:|---|
| `AWADDR_x` | 输入 | 33 | 写地址，`AWADDR[32:0]` `[UG]` |
| `AWBURST_x` | 输入 | 2 | burst 类型：`01=INCR`、`10=WRAP`；`00=FIXED` 默认不支持 `[UG][MODEL]` |
| `AWID_x` | 输入 | 6 | 写事务 ID `[UG]` |
| `AWLEN_x` | 输入 | 8 | burst 长度编码；实际 beat 数 = `AWLEN+1`，1–256 `[UG]` |
| `AWREADY_x` | 输出 | 1 | 地址就绪；条件见 7.2 `[UG]` |
| `AWSIZE_x` | 输入 | 3 | 每 beat 字节数编码；支持 0–6（1–64 字节）`[UG]` |
| `AWVALID_x` | 输入 | 1 | 地址有效 `[UG]` |
| `AWLOCK_x` | 输入 | 1 | 锁定类型；模型接受并忽略，不支持 exclusive `[MODEL]` |
| `AWAPCMD_x` | 输入 | 1 | 写自动预充电；模型接受并忽略 `[MODEL]` |
| `AWQOS_x` | 输入 | 4 | QoS；默认忽略，可选加权仲裁 `[MODEL]` |
| `AWCACHE_x` | 输入 | 4 | 手册用于决定 `BVALID` 时机；不按 AXI cache 语义建模 `[UG]` |
| `AWALLSTRB_x` | 输入 | 1 | 写全选通；使用该信号时最多 16 个 AXI beat `[UG]` |
| `AWCOBUF_x` | 输入 | 1 | 写一致缓冲选择；仅 `AWCACHE=4'b1111` 时有定义 `[UG]` |

### 5.3 写数据通道

| 信号 | 方向 | 位宽 | 说明 |
|---|---|---:|---|
| `WDATA_x` | 输入 | 512 | 写数据 `[UG]` |
| `WLAST_x` | 输入 | 1 | 写 burst 最后一拍 `[UG]` |
| `WREADY_x` | 输出 | 1 | 写数据就绪；只取决于复位和写数据队列空间，见 7.3 `[UG][MODEL]` |
| `WSTRB_x` | 输入 | 64 | 写字节选通，每 8 bit 一个；`WSTRB[n]` 对应 `WDATA[8n+7:8n]` `[UG][AXI4]` |
| `WVALID_x` | 输入 | 1 | 写数据有效 `[UG]` |

> Table 8 的 Direction 列有排版错位；上表按 AXI4 从端方向实现（勘误 E3）。

### 5.4 写响应通道

| 信号 | 方向 | 位宽 | 说明 |
|---|---|---:|---|
| `BID_x` | 输出 | 6 | 写响应 ID，对应 `AWID_x` `[UG]` |
| `BREADY_x` | 输入 | 1 | 写响应就绪 `[UG]` |
| `BRESP_x` | 输出 | 2 | 写响应：`00=OKAY`、`10=SLVERR`、`11=DECERR` `[UG][AXI4]` |
| `BVALID_x` | 输出 | 1 | 写响应有效 `[UG]` |

> Table 9 把 `BRESP` 描述成 “Read response”，按勘误 E2 以写响应理解。

### 5.5 读地址通道

| 信号 | 方向 | 位宽 | 说明 |
|---|---|---:|---|
| `ARADDR_x` | 输入 | 33 | 读地址 `[UG]` |
| `ARBURST_x` | 输入 | 2 | burst 类型：`01=INCR`、`10=WRAP`；`00=FIXED` 默认不支持 `[UG][MODEL]` |
| `ARID_x` | 输入 | 6 | 读事务 ID `[UG]` |
| `ARLEN_x` | 输入 | 8 | burst 长度编码；实际 beat 数 = `ARLEN+1`，1–256 `[UG]` |
| `ARREADY_x` | 输出 | 1 | 地址就绪；条件见 7.5 `[UG]` |
| `ARSIZE_x` | 输入 | 3 | 每 beat 字节数编码；支持 0–6 `[UG]` |
| `ARVALID_x` | 输入 | 1 | 地址有效 `[UG]` |
| `ARLOCK_x` | 输入 | 1 | 锁定类型；模型接受并忽略 `[MODEL]` |
| `ARAPCMD_x` | 输入 | 1 | 读自动预充电；模型接受并忽略 `[MODEL]` |
| `ARQOS_x` | 输入 | 4 | QoS；默认忽略 `[MODEL]` |

> **重要**：UG Table 10 的读地址接口**没有 `ARCACHE_x` 和 `ARPROT_x`**，但有 `ARAPCMD_x`。v0.1 的接口表有误，v0.2 已修正。系统集成时不要把不存在的信号接到硬核。

### 5.6 读数据通道

| 信号 | 方向 | 位宽 | 说明 |
|---|---|---:|---|
| `RDATA_x` | 输出 | 512 | 读数据 `[UG]` |
| `RID_x` | 输出 | 6 | 读 ID，对应 `ARID_x` `[UG]` |
| `RLAST_x` | 输出 | 1 | 读 burst 最后一拍 `[UG]` |
| `RREADY_x` | 输入 | 1 | 读数据就绪 `[UG]` |
| `RRESP_x` | 输出 | 2 | 读响应 `[UG][AXI4]` |
| `RVALID_x` | 输出 | 1 | 读数据有效 `[UG]` |

### 5.7 配置控制器接口

| 信号 | 方向 | 说明 |
|---|---|---|
| `CFG_RESET` | 输入 | 高有效启动序列复位；同时复位配置控制器、DDR 控制器、PHY、DRAM `[UG]` |
| `CFG_START` | 输入 | 启动配置序列；`CFG_DONE` 拉高后仍需保持高 `[UG]` |
| `CFG_SEL` | 输入 | 接低使能配置控制器 `[UG]` |
| `CFG_DONE` | 输出 | 配置/校准序列完成 `[UG]` |

约束：

- `CFG_RESET` 至少保持 5 个 `ctrl_clk` `[UG]`；
- `CFG_START` 在 `CFG_DONE` 拉高后仍需保持高 `[UG]`；
- `CFG_SEL` 接低使能 `[UG]`。

### 5.8 控制器状态接口

模型输出一组抽象状态信号，名称和位宽为 `[MODEL]`；手册只说明存在 Controller Status Signals，未给完整列表。

| 信号 | 方向 | 说明 |
|---|---|---|
| `CTRL_INIT_DONE` | 输出 | 初始化/校准完成 |
| `CTRL_READY` | 输出 | 可接受 AXI 事务 |
| `CTRL_ERR` | 输出 | 内部错误/非法访问聚合标志 |
| `CTRL_BUSY` | 输出 | 队列非空或仲裁忙 |

> 这些信号默认关闭，由 `ENABLE_CTRL_STATUS` 控制；不得把它们当成手册定义的真实硬核引脚。

### 5.9 时钟与复位

| 信号 | 说明 |
|---|---|
| `ACLK_0/1` | AXI 时钟，可异步 `[UG]` |
| `ctrl_clk` | 控制器时钟，通常为 PHY 数据率的 1/4 `[UG]` |
| `ARSTN_x` | AXI 接口低有效异步复位 `[UG]` |
| `CFG_RESET` | 高有效全局启动序列复位 `[UG]` |

模型支持两种时钟模式：

1. **双时钟模式**：`ACLK_x` 与 `ctrl_clk` 异步，内部 FIFO 同步，参数化同步延迟。
2. **单时钟简化模式**：`ACLK_x` 与 `ctrl_clk` 同源，同步延迟参数设为 0。

**时钟比定义：**

```text
CLK_RATIO_ACLK_PER_CTRL = f_ACLK / f_ctrl_clk
```

理想情况下（AXI 带宽与 DDR 带宽匹配）：

```text
f_ACLK = DDR_data_rate × DATA_WIDTH / AXI_DATA_WIDTH
f_ctrl_clk = DDR_data_rate / 4
CLK_RATIO_ACLK_PER_CTRL = 4 × DATA_WIDTH / AXI_DATA_WIDTH = DATA_WIDTH / 128
```

- x32：0.25；
- x16：0.125。

实际系统可高于或低于该比例，由参数覆盖。所有跨时钟域延迟按该比例换算；测试报告必须记录实际频率比。

---

## 6. 参数化

### 6.1 结构性参数

| 参数 | 取值 | 默认 | 来源 | 说明 |
|---|---|---|---|---|
| `DATA_WIDTH` | 16, 32 | 32 | `[UG]` Table 15 | DRAM DQ 宽度 |
| `AXI_DATA_WIDTH` | 512 | 512 | `[UG]` Table 8 | AXI 数据位宽，TJ 硬核固定 512 |
| `AXI_ADDR_WIDTH` | 33 | 33 | `[UG]` Table 7/10 | AXI 地址位宽 |
| `AXI_ID_WIDTH` | 6 | 6 | `[UG]` Table 7/10 | AXI ID 位宽 |
| `MEM_DENSITY_GBIT` | 2, 3, 4, 6, 8, 12, 16 | 4 | `[UG]` Table 15 | 每 channel 密度，单位 Gbit |
| `MEM_DENSITY_UNIT` | `GBIT_PER_CHANNEL` | 固定 | `[UG][MODEL]` | 单位解释；见 6.2 |
| `GBIT_DEFINITION` | `BINARY_2^30` | 固定 | `[MODEL]` | 1 Gbit = 2^30 bit |
| `NUM_CHANNELS` | `DATA_WIDTH/16` | 推导 | `[UG]` | x16=1，x32=2 |
| `PHYSICAL_RANK` | 1, 2 | 1 | `[UG]` Table 15 | rank 数 |
| `MEMORY_TYPE` | LPDDR4, LPDDR4x | LPDDR4 | `[UG]` Table 15 | 功能模型仅影响参数标签 |
| `NUM_AXI_TARGETS` | 1, 2 | 2 | `[UG]` | AXI 接口数 |
| `SUPPORT_WRAP_BURST` | 0, 1 | 1 | `[UG]` | 是否支持 WRAP |
| `SUPPORT_NARROW` | 0, 1 | 1 | `[UG]` | 是否支持 narrow transfer |
| `SUPPORT_FIXED_BURST` | 0, 1 | 0 | `[UG]`/`[MODEL]` | 手册只列 INCR/WRAP；默认拒绝 FIXED |
| `SUPPORT_AWALLSTRB` | 0, 1 | 1 | `[UG]` | 是否支持 `AWALLSTRB` |
| `SUPPORT_EXCLUSIVE` | 0 | 0 | `[MODEL]` | 不支持 exclusive；`*LOCK` 忽略 |
| `ADDR_MAP_MODE` | `LINEAR`, `FIELD_DECODE_DEBUG` | `LINEAR` | `[MODEL]` | 功能访问用线性地址；字段解码仅调试 |
| `RANK_MAP_MODE` | `CS_STRIDE`, `CS_BIT`, `SINGLE_RANK` | `CS_STRIDE` | `[MODEL]` | rank 选择方式；见 7.9。Phase 7：板级单 rank，`PHYSICAL_RANK=1` 下各模式行为等价，维持默认 |
| `CS_BIT_POS` | 0–32 | 推导 | `[UG][MODEL]` | 仅 `CS_BIT` 模式使用；必须等于 `log2(RANK_STRIDE_BYTES)`。Phase 7：单 rank 不适用，维持推导默认 |
| `ADDR_HOLE_POLICY` | `DECERR`, `ALIAS` | `DECERR` | `[MODEL]` | 非 2 的幂密度地址空洞处理。Phase 7：真核越界为静默回绕（非 DECERR），但 `ALIAS` 仅空洞窗语义且禁默认 → 维持 `DECERR`，越界行为差异记 documented deviation（§18/plan §9 Phase 7） |
| `MEM_INIT_MODE` | `ZERO`, `RANDOM`, `PATTERN` | `ZERO` | `[MODEL]` | 存储初始化 |
| `MEM_INIT_SEED` | 任意 32 bit | 1 | `[MODEL]` | 随机初始化种子 |

### 6.2 存储容量与推导

`MEM_DENSITY_GBIT` 是**每 channel** 的 DRAM 密度（Gbit） `[UG]` Table 15。模型按二进制换算：

```text
MEM_BYTES_PER_CHANNEL = MEM_DENSITY_GBIT × 2^30 / 8
NUM_CHANNELS          = DATA_WIDTH / 16
RANK_STRIDE_BYTES     = MEM_BYTES_PER_CHANNEL × NUM_CHANNELS
MEM_BYTES             = RANK_STRIDE_BYTES × PHYSICAL_RANK
```

示例：

| 配置 | 每 channel 字节 | 每 rank 字节 | 总字节 |
|---|---:|---:|---:|
| 4G, x16, 1 rank | 512 MiB | 512 MiB | 512 MiB |
| 4G, x32, 1 rank | 512 MiB | 1 GiB | 1 GiB |
| 16G, x32, 2 rank | 2 GiB | 4 GiB | 8 GiB |
| 3G, x32, 1 rank | 384 MiB | 768 MiB | 768 MiB |

规则：

- AXI 可寻址字节空间为 `[0, MEM_BYTES-1]`；`MEM_BYTES` 可以不是 2 的幂（3G/6G/12G）。
- `MEM_BYTES` 必须 ≤ `2^AXI_ADDR_WIDTH`，否则配置非法。
- 存储阵列按 `MEM_BYTES` 分配；不得按 AXI 全空间分配。
- 非 2 的幂密度不启用 `CS_BIT` 模式；rank 用 stride 比较器。
- 文档中所有“地址”默认指 AXI 字节地址，不是 DRAM word 地址。

### 6.3 性能参数（待实测）

| 参数 | 默认 | 来源 | 说明 |
|---|---:|---|---|
| `CMD_QUEUE_DEPTH` | 8 | `[CONFIRM]` | 命令队列深度，工程初值；Phase 3 板级实测 16 笔读全部接受无反压 → 真核下界 ≥16（板级 TG 直连真核无 shell 门控层，见 correlation-plan §6-10/§9） |
| `WRITE_DATA_QUEUE_DEPTH` | 16 | `[CONFIRM]` | 写数据队列深度 |
| `READ_DATA_QUEUE_DEPTH` | 16 | `[CONFIRM]` | 读数据队列深度 |
| `READ_OSTD_DEPTH` | 8 | `[CONFIRM]` | 读 outstanding 上限 |
| `WRITE_OSTD_DEPTH` | 8 | `[CONFIRM]` | 写 outstanding 上限 |
| `OUT_OF_ORDER_ENABLE` | 0 | `[CONFIRM]` | 不同 ID 是否乱序 |
| `R_INTERLEAVE_ENABLE` | 0 | `[MODEL]` | 不同 ID 读数据是否允许 beat 交织 |
| `ARB_GRANT_INTERVAL` | 2 | `[UG]` | round-robin 每两周期可仲裁一次。**注意：仅 g_sync（CDC_ENABLE=0）路径生效**；Phase 4 实测 CDC 形态（板级对应）不经过该仲裁器，双口调度=固定 1:1 交替收集+core_scheduler |
| `ARB_QUIET_FAST_PATH` | 1 | `[UG]` | 另一接口安静时可每周期服务（同 g_sync-only） |
| `ARB_QOS_WEIGHT_EN` | 0 | `[MODEL]` | 是否用 QoS 加权；手册未定义 |

> `[CONFIRM]` 默认值是工程初值，不是手册值。实测后按测试 spec 回填，并在报告中保留 `_ENG` 后缀的原始估计。

### 6.4 延迟参数

所有模型内部延迟单位为 `ctrl_clk` 周期，除非显式说明。

| 参数 | 默认（ctrl_clk） | 说明 |
|---|---:|---|
| `SYNC_LATENCY` | 2 | AXI→controller 时钟域同步；拟合/分摊参数 |
| `ARB_LATENCY` | 0–2 | 仲裁额外延迟 |
| `READ_LATENCY_MIN` | 10 | AR 握手到首拍 R 的最小延迟 |
| `READ_LATENCY_MAX` | 30 | AR 握手到首拍 R 的抖动上限 |
| `R_BEAT_INTERVAL` | 1 | 同一 burst 相邻 R beat 的最小间隔 |
| `WRITE_RESP_LATENCY_MIN` | 8 `[ENG]` | 非早返编码（`AWCACHE[0]=0`）下 AW 握手到 B 的排队抖动分量；实际 `T_AW_B` 由数据提交路径（`WRITE_DATA_TO_B_LATENCY`）支配 |
| `WRITE_RESP_LATENCY_MAX` | 24 `[ENG]` | 同上（抖动上限） |
| `WRITE_DATA_TO_B_LATENCY` | 4 → **451**（标定） | 非早返编码下 WLAST 握手到 BVALID 的附加延迟；Phase 2 板级回填（板 WL 55-99 ACLK ×8，correlation-plan §9） |
| `BVALID_CMD_QUEUE_DELAY` | 2 → **28**（标定） | 早返编码（`AWCACHE[0]=1`，含 `1111+cobuf`）命令接受到 BVALID 延迟；Phase 5 板级回填（板 T_AW_B 4-5 ACLK ×8 = 32-40 ctrl，减模型 CDC 结构 ≈4） |
| `BVALID_PHY_ISSUE_DELAY` | 2 `[ENG]` | 仅 `OTHER_AWCACHE_POLICY=PHY_ISSUE` 兜底策略使用；Phase 5 后默认策略不触发 |
| `W_ACCEPT_INTERVAL` | 1 | 写数据相邻 beat 的最小接受间隔 |
| `LATENCY_MODE` | `UNIFORM` | `FIXED` / `UNIFORM` |
| `LATENCY_SEED` | 1 | 随机延迟种子，保证可复现 |
| `LATENCY_UNIT` | `CTRL_CLK` | 固定；测试侧按 `CLK_RATIO_ACLK_PER_CTRL` 换算 |

延迟参考点定义（与测试 spec 对齐）：

```text
T_AR_FIRST_R : ARVALID&&ARREADY  →  该事务首拍 RVALID&&RREADY
T_AR_RLAST   : ARVALID&&ARREADY  →  该事务 RLAST 握手（可选统计）
T_AW_B       : AWVALID&&AWREADY  →  该事务 BVALID&&BREADY
T_WLAST_B    : WLAST 握手         →  该事务 BVALID&&BREADY（AWCOBUF=0）
```

- `READ_LATENCY_MIN/MAX` 对应 `T_AR_FIRST_R`。
- `WRITE_RESP_LATENCY_MIN/MAX` 为数据提交路径 `T_AW_B` 的排队抖动分量 `[ENG 值]`；`AWCACHE[0]=0` 编码实际 `T_AW_B ≈ T_WLAST_B`，由 `WRITE_DATA_TO_B_LATENCY`（标定 451）支配。`AWCACHE=1111` 裸值板级 AW/W 死锁（correlation Phase 2），不再作为基线组合。
- 早返模式（`AWCACHE[0]=1`）下的 `T_AW_B` 由 `BVALID_CMD_QUEUE_DELAY`（标定 28）决定；`BVALID_PHY_ISSUE_DELAY` 仅 `OTHER_AWCACHE_POLICY=PHY_ISSUE` 兜底策略使用，不与数据提交路径共用 min/max。
- `SYNC_LATENCY` 无法仅从 AXI 边界独立观测；由多组 `ACLK:ctrl_clk` 实验拟合/分摊 `[MODEL]`。

**跨时钟域换算：**

```text
latency_aclk_cycles = ceil( (latency_ctrl_cycles + sync_ctrl) × f_ctrl / f_ACLK )
```

测试报告同时给出 ACLK 周期数和换算后的 ctrl_clk 周期数，并记录实际频率。

### 6.5 BVALID 时机参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `BVALID_TIMING_MODE` | `MANUAL_STRICT` | Phase 5 后 bit0 规律已内建于 B 时机判定（`cmd_is_early`），当前实现未使用此参数（保留兼容） |
| `OTHER_AWCACHE_POLICY` | `DATA_DONE` | 兜底策略，仅对 `AWCACHE[0]=0` 编码生效：`DATA_DONE`（数据完成后 B，板级一致，默认）/ `CMD_QUEUE` / `PHY_ISSUE`（均早返）。`AWCACHE[0]=1` 一律早返，不受此参数影响 |
| `AWCOBUF_STRICT` | 1 | `AWCOBUF=1` 且 `AWCACHE` 不属于 `{1111, 0000}` 时置 `CTRL_ERR`；`AWCACHE=0000` 时忽略 `AWCOBUF`。Phase 5 实测 COBUF 对 B 时机无独立效应（0000/1110 × cobuf 全同形），STRICT 保守保留默认 1；`1111+cobuf` 板级不可测（1111 裸值死锁） |

### 6.6 错误与边界参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `ERR_CROSS_4KB` | `SLVERR` | burst 跨 4KB |
| `ERR_BURST_LEN` | `SLVERR` | `AWLEN/ARLEN` 超过 Table 5 上限 |
| `ERR_BURST_SIZE` | `SLVERR` | `AWSIZE/ARSIZE > 6`（>64 字节） |
| `ERR_FIXED_BURST` | `SLVERR` | FIXED burst 且 `SUPPORT_FIXED_BURST=0` |
| `ERR_ADDR_RANGE` | `DECERR` | 地址 ≥ `MEM_BYTES` |
| `ERR_ADDR_HOLE` | `DECERR` | 仅字段解码/显式空洞表的地址空洞 |
| `ERR_WSTRB_INVALID` | `IGNORE` | 非法 WSTRB：`IGNORE`/`ASSERT`/`SLVERR` |
| `ERR_ALLSTRB_BEATS` | `SLVERR` | `AWALLSTRB=1` 且 beat 数 > 16 |
| `ERR_ALLSTRB_WSTRB` | `SLVERR` | `AWALLSTRB=1` 但 WSTRB 非全 1 |
| `ERR_INJECT_RATE` | 0 | 随机错误注入概率，0 关闭 |
| `NARROW_READ_INVALID_LANE` | `ZERO` | narrow read 无效 lane 返回值：`ZERO`/`KEEP`/`X` |

### 6.7 配置与复位参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `INIT_CYCLES` | 1000 | 初始化/校准抽象耗时（ctrl_clk） |
| `INIT_AXI_BLOCK` | 1 | 初始化期间是否阻塞 AXI |
| `INIT_AXI_RESP` | `BACKPRESSURE` | 初始化期间 AXI 行为：`BACKPRESSURE`/`SLVERR` |
| `CFG_RESET_CLEAR_MEM` | 0 | `CFG_RESET` 是否清空存储 |
| `ENABLE_CTRL_STATUS` | 0 | 是否输出控制器状态信号 |

---

## 7. AXI 行为规格

### 7.1 全局规则

- 模型符合 AMBA AXI4 从端行为 `[AXI4]`。
- `*VALID` 一旦拉高，必须保持到 `*READY` 拉高；`*VALID` 不得在 `*READY` 前撤销 `[AXI4]`。
- 复位期间所有输出 `VALID=0` `[AXI4]`。
- 同 ID 事务按序响应 `[AXI4]`。
- `OUT_OF_ORDER_ENABLE=0` 时，模型按全局 AR/AW 接受顺序响应；这严于 AXI4 最低要求 `[MODEL]`。
- `OUT_OF_ORDER_ENABLE=1` 时，不同 ID 可乱序完成，同 ID 仍按序；默认不交织读 beat（`R_INTERLEAVE_ENABLE=0`） `[MODEL]`。
- 不支持 FIXED burst（默认）；不支持 exclusive access `[MODEL]`。
- `AWSIZE/ARSIZE` 只支持 0–6（1–64 字节） `[UG]`。
- `AWLEN/ARLEN` 编码 0–255，实际 beat 数 1–256 `[UG]`。
- 所有地址为 33-bit AXI 字节地址。

### 7.2 写地址通道

`AWREADY_x` 在以下条件**同时**满足时拉高：

1. `ARSTN_x` 为高；
2. `AWVALID_x && WVALID_x`（至少首拍写数据已有效）`[UG]` Figure 4 注；
3. 写 outstanding 未达 `WRITE_OSTD_DEPTH`；
4. 命令队列未满；
5. 写地址通道空闲。

> **关键**：第 2 条来自 UG Figure 4 的注：“AWREADY is asserted after both AWVALID and WVALID are asserted.” 模型不得在 `WVALID=0` 时拉高 `AWREADY`。这与 AXI4 一般从端不同 `[UG]`。

接受 `AW` 后记录：地址、burst、长度、size、ID、cache、cobuf、allstrb。

检查项（检查失败时仍完成 AW 握手，在 B 通道返回错误；写数据仍需接收以避免死锁）：

| 检查 | 条件 | 默认响应 |
|---|---|---|
| burst size | `AWSIZE > 6` | `ERR_BURST_SIZE` |
| burst 长度 | 超过 Table 5 上限（见 7.7） | `ERR_BURST_LEN` |
| 4KB 边界 | `start_addr + (AWLEN+1)×2^AWSIZE` 跨 4KB | `ERR_CROSS_4KB` |
| 地址范围 | `addr ≥ MEM_BYTES` | `ERR_ADDR_RANGE` |
| 地址空洞 | 仅 `FIELD_DECODE_DEBUG` 且配置了空洞表时检查 | `ERR_ADDR_HOLE` |
| WRAP 合法性 | 长度不是 2/4/8/16 或起始地址未对齐 | `ERR_CROSS_4KB`/`ERR_BURST_LEN`（按具体检查） |
| FIXED | `AWBURST=00` 且 `SUPPORT_FIXED_BURST=0` | `ERR_FIXED_BURST` |
| `AWALLSTRB` beat 数 | `AWALLSTRB=1` 且 `AWLEN+1 > 16` | `ERR_ALLSTRB_BEATS` |
| `AWCOBUF` 语义 | `AWCOBUF=1` 且 `AWCACHE` 不属于 `{1111,0000}` | 断言（`AWCOBUF_STRICT=1`）；按忽略处理；`AWCACHE=0000` 时忽略 `AWCOBUF` |

`AWALLSTRB=1` 时，模型按“全选通”处理：要求后续 `WSTRB` 全 1；否则按 `ERR_ALLSTRB_WSTRB` 处理。`AWALLSTRB=0` 时按普通 WSTRB 处理。

### 7.3 写数据通道

- `WREADY_x` 只取决于：
  1. `ARSTN_x` 为高；
  2. 写数据队列未满。
- `WREADY_x` **不依赖**是否已经接受 `AW`。AXI 允许写数据先于写地址到达 `[AXI4]`；模型允许 W 数据先入队，待 AW 到达后匹配。
- 写数据按 `WSTRB_x` 更新存储；`WSTRB[n]=1` 表示 `WDATA[8n+7:8n]` 有效 `[AXI4]`。
- 支持 narrow transfer：只有有效 lane 更新存储；无效 lane 不更新。
- `WSTRB` 全 0 的 beat 合法，不更新存储 `[AXI4]`。
- `WLAST_x` 必须与 `AWLEN` 对应 beat 数一致 `[AXI4]`。
- `AWALLSTRB=1` 时，`WSTRB` 必须全 1；否则按 `ERR_ALLSTRB_WSTRB`。
- 写数据 beat 数超过 `AWLEN+1` 或不足：协议错误；模型记录并断言。若 B 已早返，不能追溯修改 `BRESP`，只能记录 `CTRL_ERR`/断言 `[MODEL]`。
- 早返模式（`AWCACHE[0]=1`，Bufferable）下，B 可能先于 `WLAST`；模型仍必须接收全部 W 数据 `[UG][MODEL]`。注意 `AWCACHE=0000` 板级实测为非早返（数据提交后 B），不在此列。
- 写数据可以早于 AW 被接收；如果 W 数据队列满，`WREADY` 拉低，但 `AWREADY` 仍可在 `AWVALID&&WVALID` 且命令队列有空间时拉高（首拍 WVALID 已经存在）。

### 7.4 写响应通道

`BVALID_x` 时机按 `AWCACHE` / `AWCOBUF`：

| `AWCACHE` | `AWCOBUF` | BVALID 时机 | 来源 |
|---|---|---|---|
| `4'b1111` | 1 | 命令被接受进 controller command queue 后；**可早于 WLAST**（早返延迟 `BVALID_CMD_QUEUE_DELAY`=28 ctrl 标定） | `[UG][板 Phase 5]` |
| `4'b1111` | 0 | 板级 AW/W 死锁不可用（correlation Phase 2）；模型按 `AWCACHE[0]=1` 规律早返 | `[板 Phase 2][MODEL]` |
| `4'b0000` | 任意 | 全部写数据提交后（COBUF 无独立效应，板级 0000±cobuf 同形，WA/WL 55-99 ACLK）；**非早返**。手册"命令发到 PHY 后"语义与实测不符，已修正 | `[板 Phase 5][MODEL]` |
| `AWCACHE[0]=1` 其他（板级实测 `0001/0011/0111`） | 任意 | 早返：命令接受后 `BVALID_CMD_QUEUE_DELAY` 内 BVALID；板级 AW 握手 +4-5 ACLK，实测全同形 | `[板 Phase 5][MODEL]` |
| `AWCACHE[0]=0` 其他（板级实测 `0010/0100/1110`） | 任意 | 数据提交后：`WRITE_DATA_TO_B_LATENCY` 支配；板级与 0000 同形（WA/WL 55-99 ACLK） | `[板 Phase 5][MODEL]` |

> correlation Phase 5（2026-10-23）板级 9 块矩阵结论：B 时机由 `AWCACHE[0]`（Bufferable）单独决定，`AWCOBUF` 无独立效应；覆盖 9 编码实测 + 其余按 bit0 规律外推，详见 correlation-plan §9。

- `BID_x` 对应 `AWID_x`。
- `BRESP_x` 默认 `OKAY`；检查失败按 `ERR_*` 返回 `SLVERR`/`DECERR`。
- 同 ID 写响应按序 `[AXI4]`。
- 早返模式下，B 可能在 W 数据完成前发出；此时后续 W 数据错误不能改变已发出的 `BRESP`，模型记录错误并断言 `[MODEL]`。
- `BVALID` 不得在 `AW` 握手前发出。
- `BVALID` 与 `WREADY`/`WVALID` 无固定先后关系；早返模式尤其如此。

### 7.5 读地址通道

`ARREADY_x` 在以下条件同时满足时拉高：

1. `ARSTN_x` 为高；
2. 读 outstanding 未达 `READ_OSTD_DEPTH`；
3. 命令队列未满；
4. 读地址通道空闲。

检查项同写地址（长度、size、4KB、范围、空洞、WRAP、FIXED）。检查失败时记录错误，在 R 通道返回错误响应；读数据仍需按 burst 长度返回（或按 `ERR_*` 策略提前结束，默认按完整 burst 返回错误响应） `[MODEL]`。

- `ARAPCMD_x`、`ARLOCK_x`、`ARQOS_x` 接受并忽略 `[MODEL]`。
- 读地址接口没有 `ARCACHE/ARPROT`；不要连接这些信号 `[UG]`。

### 7.6 读数据通道

- `RVALID_x` 按 `READ_LATENCY_*` 延迟后拉高；延迟从 AR 握手算起，对应 `T_AR_FIRST_R`。
- 同一 burst 的 R beat 间隔不小于 `R_BEAT_INTERVAL`。
- 每拍按 `ARSIZE` 和地址在对应 byte lane 返回数据。
- narrow read：有效 lane 返回存储数据；无效 lane 按 `NARROW_READ_INVALID_LANE` 返回 `0`/保持/`X` `[MODEL]`。
- `RLAST_x` 在最后一拍拉高。
- `RID_x` 对应 `ARID_x`。
- `RRESP_x` 默认 `OKAY`；检查失败按 `ERR_*`。
- 同 ID 读数据按序；`OUT_OF_ORDER_ENABLE=0` 时全局按序。
- `R_INTERLEAVE_ENABLE=1` 时允许不同 ID 的 R beat 交织；默认 0（整 burst 连续） `[MODEL]`。
- 读数据队列满时，`RVALID` 可被反压；内部暂停读命令出队，`ARREADY` 可拉低。

### 7.7 Burst 规则

支持类型：INCR、WRAP；FIXED 默认不支持 `[UG][MODEL]`。

**最大 burst 长度 `[UG]` Table 5：**

| `AWSIZE/ARSIZE` | 字节数 | `AWLEN/ARLEN` 上限 | 来源 |
|---:|---:|---:|---|
| 6 | 64 | 63 | `[UG]` |
| 5 | 32 | 127 | `[UG]` |
| 4 | 16 | 255 | `[UG]` |
| ≤3 | ≤8 | 256 | `[AXI4]`（手册未列，需实测） |

> `SIZE≤3` 的 256 上限来自 AXI4 的 256-beat 上限，不是手册明示。`SIZE=3, LEN=256` 是否被硬核支持需实测 `[CONFIRM]`。

**4KB 边界 `[UG]`：**

- burst 总字节数 = `(AWLEN/ARLEN + 1) × 2^(AWSIZE/ARSIZE)`；
- 起始地址 + 总字节数不得跨 4KB 边界；
- 跨边界按 `ERR_CROSS_4KB` 处理。

**WRAP 规则 `[AXI4]`：**

- 长度只能是 2/4/8/16；
- 起始地址必须对齐到 `(长度 × 2^SIZE)`；
- 地址回绕在 burst 内计算；
- 手册未明示 WRAP 约束，列入实测确认 `[CONFIRM]`。

**地址递增：**

- INCR：每个 beat 地址递增 `2^SIZE`；
- narrow transfer 时仍按 `2^SIZE` 递增，WSTRB 的 lane 位置随地址变化 `[AXI4]`。

### 7.8 Narrow Transfer 与 WSTRB

- `WSTRB_x[n]` 对应 `WDATA_x[8n+7:8n]` `[AXI4]`。
- 写：仅 `WSTRB=1` 的 byte lane 写入。
- 读：有效 lane 返回数据，无效 lane 按 `NARROW_READ_INVALID_LANE`。
- narrow transfer 的 lane 位置由 `addr mod (AXI_DATA_WIDTH/8)` 决定；每 beat 地址按 `2^SIZE` 递增 `[AXI4]`。
- 模型应按 Figure 5/6 的意图验证，但图的文本排版不可靠；以 AXI lane 规则为准（勘误 E7）。
- `AWALLSTRB=1` 时 WSTRB 必须全 1；否则 `ERR_ALLSTRB_WSTRB`。
- `WSTRB` 全 0 beat 合法，不更新存储。

**lane 计算示例（`AXI_DATA_WIDTH=512`，64 字节 bus）：**

```text
bytes_per_beat = 1 << SIZE
lane_offset    = AXI_addr % 64
WSTRB          = ((1 << bytes_per_beat) - 1) << lane_offset
```

当 `lane_offset + bytes_per_beat > 64` 时，narrow INCR 会跨 beat 边界；AXI 地址按 size 递增后自然落入下一拍，模型按实际地址计算 lane。

### 7.9 地址映射、容量与 rank/chip-select

#### 7.9.1 权威规则

- 对用户而言，AXI 地址是从 0 到 `MEM_BYTES-1` 的连续字节空间 `[UG]`。
- 功能访问使用线性字节地址索引存储阵列；不依赖 DRAM bank/row/column 字段。
- `MEM_BYTES` 按 6.2 计算，越界按 `ERR_ADDR_RANGE`。
- 地址位宽 33，但可用空间由 `MEM_BYTES` 决定；不得把 2^33 全空间当作有效存储。

#### 7.9.2 手册示例

**最大地址空间示例 `[UG]`：**

```text
[32]      Chip select
[31:15]   Row address
[14:12]   Bank address
[11:2]    Column address
[1:0]     Datapath
```

**低密度示例 `[UG]`：**

```text
[32:28]   Not used
[27]      Chip select
[26:12]   Row address
[11:9]    Bank address
[8:2]     Column address
[1:0]     Datapath
```

> 手册低密度示例的排版容易误读为 `[27:26] Chip select`；正确边界是 `[27]` CS、`[26:12]` Row（勘误 E5）。
> 两个示例说明 CS 位置随每 rank 地址空间变化，**不是固定 bit32**。

#### 7.9.3 rank 映射模式

| 模式 | 行为 | 适用 |
|---|---|---|
| `CS_STRIDE`（默认） | `rank = addr / RANK_STRIDE_BYTES`；`offset = addr % RANK_STRIDE_BYTES` | 所有密度；非 2 的幂也适用 |
| `CS_BIT` | `rank = addr[CS_BIT_POS]`；`offset` 按 CS bit 清除后的低位解释 | 仅 2 的幂 rank stride；`CS_BIT_POS=log2(RANK_STRIDE_BYTES)` |
| `SINGLE_RANK` | 忽略 rank，要求 `PHYSICAL_RANK=1` | 单 rank 简化 |

- `CS_STRIDE` 在最大配置（16G × x32 × 2 rank）下等价于 bit32 CS。
- 低密度配置下 `CS_BIT_POS` 由 `RANK_STRIDE_BYTES` 推导，例如每 rank 128MiB 时为 bit27。
- `CS_BIT` 模式下若 `RANK_STRIDE_BYTES` 不是 2 的幂，配置非法。
- `PHYSICAL_RANK=1` 时 rank 恒为 0；地址 ≥ `MEM_BYTES` 仍按 `ERR_ADDR_RANGE`。

#### 7.9.4 字段解码（仅调试）

`ADDR_MAP_MODE=FIELD_DECODE_DEBUG` 时，模型可按选定 profile 输出 `cs/row/bank/column/datapath` 字段，用于日志和检查；**不用于存储访问**。

- `LINEAR`（默认）：不做字段解码；地址范围检查用 `MEM_BYTES`。
- `FIELD_DECODE_DEBUG`：允许配置字段宽度；字段总宽与 `MEM_BYTES` 不一致时只记录警告，不影响功能访问。
- 非 2 的幂密度（3G/6G/12G）不启用字段解码；按 6.2 的线性空间处理。
- 地址空洞：仅当 `ADDR_MAP_MODE=FIELD_DECODE_DEBUG` 且提供了空洞表/profile 时，`ADDR_HOLE_POLICY=DECERR` 才返回 `DECERR`；功能线性模型不模拟空洞。`ALIAS` 仅用于测试，不得作为默认。

#### 7.9.5 controller word 地址（调试）

手册的 controller 地址映射：

```text
x32: controller_addr = AXI_addr >> 2
x16: controller_addr = AXI_addr >> 1
```

这是 DRAM word 地址换算，功能模型不需要用它索引存储；只在调试/日志中使用 `[UG][MODEL]`。

### 7.10 错误响应

| 场景 | 默认响应 | 备注 |
|---|---|---|
| burst 跨 4KB | `SLVERR` | `ERR_CROSS_4KB` |
| burst 长度超限 | `SLVERR` | `ERR_BURST_LEN` |
| `SIZE > 6` | `SLVERR` | `ERR_BURST_SIZE` |
| FIXED burst | `SLVERR` | `ERR_FIXED_BURST` |
| 地址越界 | `DECERR` | `ERR_ADDR_RANGE` |
| 地址空洞 | `DECERR` | `ERR_ADDR_HOLE` |
| WRAP 非法 | `SLVERR` | 按具体检查选用错误码 |
| `WLAST` 与 `AWLEN` 不匹配 | `SLVERR` + 断言 | 协议错误 |
| `WSTRB` 非法 | `IGNORE`/`ASSERT`/`SLVERR` | `ERR_WSTRB_INVALID` |
| `AWALLSTRB` beat >16 | `SLVERR` | `ERR_ALLSTRB_BEATS` |
| `AWALLSTRB` WSTRB 非全 1 | `SLVERR` | `ERR_ALLSTRB_WSTRB` |

错误响应在 B 通道或 R 通道返回；写数据仍可接收以避免死锁 `[AXI4]`。早返模式下已经发出的 `BRESP` 不可追溯修改。

### 7.11 Lock、Exclusive、QoS、Cache

- `AWLOCK/ARLOCK`：接受并忽略；模型不支持 exclusive，读响应不返回 `EXOKAY` `[MODEL]`。
- `AWQOS/ARQOS`：默认忽略；`ARB_QOS_WEIGHT_EN=1` 时可用于仲裁加权，但手册未定义权重语义 `[MODEL]`。
- `AWCACHE`：仅用于 BVALID 时机；不要把 AXI cache 语义映射到存储一致性 `[UG][MODEL]`。
- `AWCOBUF`：仅在 `AWCACHE=4'b1111` 时有定义；`AWCACHE=4'b0000` 时忽略 `AWCOBUF`；其他组合按 `AWCOBUF_STRICT` 处理 `[UG]`。
- `AWAPCMD/ARAPCMD`：接受并忽略；功能模型没有 bank 预充电状态 `[MODEL]`。

---

## 8. 仲裁器

### 8.1 行为 `[UG]`

- 两个 AXI 接口的读写请求共享一个 round-robin 仲裁器（**仅 g_sync / CDC_ENABLE=0 路径**；CDC_ENABLE=1 时双口命令经 axi_port_shell_cdc 各自跨域后由固定 1:1 交替收集逻辑（`aw/ar_last` anti-starvation，port0 优先）汇入共享命令队列，无 grant-interval 冷却——Phase 4 RTL 审查+表征实测确认）；
- 每两周期可仲裁一次（`ARB_GRANT_INTERVAL=2`，g_sync）；
- 授予条件：
  1. 该接口有 active request；
  2. 命令队列未满；
- 轮到某接口但无请求时跳过，检查另一接口；
- 另一接口安静且队列未满时，可每周期服务（`ARB_QUIET_FAST_PATH=1`）；
- 读写请求按请求类型进入命令队列。

### 8.2 参数

| 参数 | 默认 | 说明 |
|---|---:|---|
| `ARB_GRANT_INTERVAL` | 2 | 仲裁周期 |
| `ARB_QUIET_FAST_PATH` | 1 | 单接口快速路径 |
| `ARB_QOS_WEIGHT_EN` | 0 | 是否用 QoS 加权（手册未定义） |

### 8.3 断言

- 同一周期不应同时授予两个接口；
- 命令队列满时不应授予；
- 仲裁轮转公平性检查（可选）；
- 仲裁器不得在 `ARSTN` 复位期间授予。

---

## 9. 队列与背压模型

### 9.1 队列抽象

| 队列 | 深度参数 | 反压信号 |
|---|---|---|
| Command Queue | `CMD_QUEUE_DEPTH` | `AWREADY_x`/`ARREADY_x` |
| Write Data Queue | `WRITE_DATA_QUEUE_DEPTH` | `WREADY_x` |
| Read Data Queue | `READ_DATA_QUEUE_DEPTH` | `RVALID_x` 内部反压 |

### 9.2 背压规则

- 命令队列满：`AWREADY_x`/`ARREADY_x` 拉低；
- 写数据队列满：`WREADY_x` 拉低；
- 读数据队列满：内部暂停读命令出队，`ARREADY_x` 可拉低；
- outstanding 达上限：对应 `AWREADY_x`/`ARREADY_x` 拉低；
- `AWREADY_x` 还必须满足 `AWVALID_x && WVALID_x`（7.2）；`WREADY_x` 不依赖 AW（7.3）；
- 队列释放后按延迟参数恢复。

### 9.3 与真实硬核的差异

模型不模拟真实命令调度、bank 冲突和刷新。队列占用仅用于产生背压和延迟趋势，不作为周期精确性能依据 `[MODEL]`。

---

## 10. 延迟模型

### 10.1 延迟组成

```text
读事务：
  AR 握手
    + SYNC_LATENCY
    + ARB_LATENCY
    + READ_LATENCY（参数化）
    + 每 beat 传输间隔（R_BEAT_INTERVAL）
    -> R beats

非早返写事务（`AWCACHE[0]=0`，标定形态）：
  AW 握手 + W beats
    + WRITE_RESP_LATENCY（排队抖动，ENG 值）
    + WRITE_DATA_TO_B_LATENCY = 451（WLAST 后，Phase 2 标定）
    -> BVALID

早返写事务（`AWCACHE[0]=1`，Phase 5 标定）：
  AW 握手
    + BVALID_CMD_QUEUE_DELAY = 28（命令接受后）
    -> BVALID（可早于 WLAST；板级对应 AW 握手 +4-5 ACLK）
```

### 10.2 延迟模式

| 模式 | 说明 |
|---|---|
| `FIXED` | 固定值；使用 MIN |
| `UNIFORM` | `[MIN, MAX]` 均匀随机；使用 `LATENCY_SEED` 保证可复现 |

> v0.1 的 `LATENCY_RANGE` 与 `UNIFORM` 语义重复，v0.2 合并为 `FIXED`/`UNIFORM`。

### 10.3 参考点与单位

- 模型内部延迟单位为 `ctrl_clk` 周期。
- 测试侧 APM 在 `ACLK` 域测量；回填时按 `CLK_RATIO_ACLK_PER_CTRL` 换算。
- `T_AR_FIRST_R`、`T_AW_B`、`T_WLAST_B` 的定义见 6.4，必须与测试 spec 一致。
- `READ_LATENCY_MAX` / `WRITE_RESP_LATENCY_MAX` 的实测回填值应使用 P99（有直方图）或 P95（无直方图），不是绝对 max；绝对 max 作为 outlier 记录。

### 10.4 延迟不承诺

模型延迟仅用于功能验证和趋势模拟，不用于性能签核 `[MODEL]`。

---

## 11. Outstanding 与 ID 管理

### 11.1 Outstanding 计数

- 读 outstanding：从 AR 握手到该事务 `RLAST` 握手；
- 写 outstanding：从 AW 握手到该事务 `BVALID` 握手；
- 达上限时反压对应地址通道；
- 计数器参数化 `READ_OSTD_DEPTH`/`WRITE_OSTD_DEPTH`；
- 早返模式下，写 outstanding 在 B 握手时递减，可能早于 WLAST；这是 AXI 语义，不代表数据阶段完成 `[UG][MODEL]`。

### 11.2 ID 管理

- ID 宽度 6 位，最多 64 个 ID；
- 同 ID 事务按序响应 `[AXI4]`；
- `OUT_OF_ORDER_ENABLE=0`：所有事务按全局接受顺序响应 `[MODEL]`；
- `OUT_OF_ORDER_ENABLE=1`：不同 ID 可并行/乱序，同 ID 保持顺序；默认不交织读 beat `[MODEL]`；
- 模型维护每 ID 的 outstanding 计数和顺序队列；
- 早返写响应也遵守同 ID 顺序。

### 11.3 响应顺序断言

- 同 ID 读响应顺序与 AR 顺序一致；
- 同 ID 写响应顺序与 AW 顺序一致；
- `OUT_OF_ORDER_ENABLE=0` 时不同 ID 也按序；
- `OUT_OF_ORDER_ENABLE=1` 时不同 ID 可乱序，但不得违反同 ID 顺序。

---

## 12. 配置控制器模型

### 12.1 状态机

```text
IDLE
  │ CFG_RESET=0, CFG_SEL=0
  ▼
WAIT_START
  │ CFG_START=1
  ▼
INIT_SEQUENCE
  │ 计数 INIT_CYCLES
  ▼
DONE
  │ CFG_DONE=1，保持到 CFG_RESET=1
  └─► IDLE（CFG_RESET 拉高）
```

### 12.2 行为

- `CFG_RESET=1`：复位内部状态，`CFG_DONE=0`；
- `CFG_RESET` 至少保持 5 个 `ctrl_clk`（断言检查） `[UG]`；
- `CFG_SEL=0` 使能；`CFG_SEL=1` 禁用，`CFG_DONE` 保持低 `[UG]`；
- `CFG_START=1` 后启动初始化序列；
- 参数化 `INIT_CYCLES` 后 `CFG_DONE=1`；
- `CFG_START` 在 `CFG_DONE=1` 后仍需保持高（断言检查） `[UG]`；
- 初始化期间 AXI 接口行为由 `INIT_AXI_BLOCK`/`INIT_AXI_RESP` 控制：
  - `BACKPRESSURE`：`AWREADY/ARREADY/WREADY` 拉低；
  - `SLVERR`：接受事务并返回错误响应；
- `CFG_DONE` 在 `CFG_RESET=1` 前保持高 `[MODEL]`。

### 12.3 参数

见 6.7。

---

## 13. 复位模型

| 复位 | 作用 |
|---|---|
| `ARSTN_x=0` | 复位 AXI x 接口状态机、通道输出；不影响存储内容；未完成事务丢弃 `[AXI4][MODEL]` |
| `CFG_RESET=1` | 复位配置控制器、控制器队列、仲裁器、延迟模型；可选清空存储（`CFG_RESET_CLEAR_MEM`） `[UG][MODEL]` |

规则：

- 复位期间所有输出 `VALID=0` `[AXI4]`；
- `CFG_RESET` 拉高后 `CFG_DONE=0` `[UG]`；
- 建议所有复位在电源稳定后一起拉高（手册建议，模型不强制） `[UG]`；
- `CFG_RESET` 至少 5 个 `ctrl_clk` `[UG]`；
- `ARSTN_x` 是低有效；不要按 Table 14 的 `ARST_X active-high` 接反（勘误 E1）；
- `ARSTN_x` 与 `CFG_RESET` 可独立使用，但系统集成建议同时复位 `[UG]`。

---

## 14. 存储阵列模型

### 14.1 结构

- 线性 byte array，大小 = `MEM_BYTES`（6.2）；
- 支持初始化清零、随机填充或固定 pattern（`MEM_INIT_MODE`/`MEM_INIT_SEED`）；
- 存储内容在 `ARSTN_x` 期间保持；`CFG_RESET` 是否清空由 `CFG_RESET_CLEAR_MEM` 控制。

### 14.2 访问规则

- 写：按 `WSTRB` 更新 byte lane；
- 读：按 `ARSIZE` 和地址返回有效 lane，无效 lane 按 `NARROW_READ_INVALID_LANE`；
- 越界/空洞按 `ERR_ADDR_RANGE`/`ERR_ADDR_HOLE`；
- 不支持 DRAM 刷新/bank 时序；存储内容在复位之间保持；
- 非 2 的幂密度按 `MEM_BYTES` 线性数组，功能模型不模拟地址空洞。若启用字段解码并显式配置空洞表，按 `ADDR_HOLE_POLICY` 处理。

### 14.3 可选后门

- 提供后门读写接口用于测试平台预载/检查存储内容；
- 后门接口不参与 AXI 协议；
- 后门访问不受 `ARSTN_x` 影响，但受 `CFG_RESET_CLEAR_MEM` 影响（如启用）。

---

## 15. 控制器状态信号

| 信号 | 条件 |
|---|---|
| `CTRL_INIT_DONE` | `CFG_DONE=1` 且内部初始化完成 |
| `CTRL_READY` | 可接受 AXI 事务（队列未满、非复位、初始化完成） |
| `CTRL_BUSY` | 命令队列非空或仲裁忙 |
| `CTRL_ERR` | 发生过非法访问或协议错误（粘滞，直到 `CFG_RESET`） |

状态信号为 `[MODEL]`，默认关闭，由 `ENABLE_CTRL_STATUS` 控制。

---

## 16. 断言与检查

### 16.1 AXI 协议断言

- `*VALID` 拉高后保持到 `*READY`；
- `WLAST` 与 `AWLEN` 匹配；
- `RLAST` 与 `ARLEN` 匹配；
- 同 ID 响应顺序；
- 复位期间 `VALID=0`；
- `WSTRB` 与 `WDATA` lane 对应；
- `BVALID` 不得在 AW 握手前；
- `RVALID` 不得在 AR 握手前。

### 16.2 手册规则断言

- `AWREADY` 不得在 `AWVALID && WVALID` 之前拉高 `[UG]`；
- burst 不跨 4KB `[UG]`；
- `AWLEN/ARLEN` 不超过 Table 5 上限 `[UG]`；
- `AWSIZE/ARSIZE ≤ 6` `[UG]`；
- `AWALLSTRB=1` 时 beat 数 ≤ 16，WSTRB 全 1 `[UG]`；
- WRAP 长度和对齐合法 `[AXI4]`；
- FIXED burst 在 `SUPPORT_FIXED_BURST=0` 时返回错误 `[MODEL]`；
- `CFG_RESET` 至少 5 个 `ctrl_clk` `[UG]`；
- `CFG_START` 在 `CFG_DONE` 后保持高 `[UG]`；
- `CFG_SEL=0` 使能 `[UG]`。

### 16.3 仲裁断言

- 同一周期不授予两个接口；
- 队列满时不授予；
- round-robin 公平性（可选）。

### 16.4 队列断言

- outstanding 不超过上限；
- 队列深度不溢出；
- 反压信号与队列状态一致；
- `WREADY` 不依赖 AW（允许 W 先于 AW）；
- 早返模式下 B 早于 WLAST 时，W 数据仍被接收。

---

## 17. 验证计划

### 17.1 手册示例回归

| 用例 | 依据 | 检查点 |
|---|---|---|
| 读操作 | Figure 3 | `ARLEN=3, ARSIZE=6`，INCR，4 拍 R，`RLAST` 正确 |
| 写操作 | Figure 4 | 4 拍 W，`WLAST`，`BVALID`；`AWREADY` 在 `AWVALID && WVALID` 后 |
| 地址映射 | Table 4 | AXI beat 到 DQ 映射 |
| 最大 burst | Table 5 | SIZE=6/5/4 的长度上限 |
| 8-bit on 32-bit | Figure 5 | WSTRB one-hot 轮转（按 AXI lane 规则） |
| 32-bit on 64-bit | Figure 6 | WSTRB 组合 |
| CFG 波形 | Figure 7 | `CFG_RESET/START/SEL/DONE` 时序 |

### 17.2 功能用例

- 单拍/多拍读写；
- INCR/WRAP；
- FIXED burst 拒绝；
- narrow transfer；
- 4KB 边界；
- burst 长度/size 超限；
- 地址越界、地址空洞；
- `WSTRB` 全 0/部分/全 1；
- `AWALLSTRB` 16/17 beat、WSTRB 全 1/非全 1；
- `AWCOBUF=0/1`、`AWCACHE=1111/0000/其他` 的 BVALID 时机；
- B 早于 WLAST 时仍接收 W 数据；
- W 数据先于 AW；
- `AWREADY` 在只有 `AWVALID` 无 `WVALID` 时保持低；
- 同 ID 顺序；
- 不同 ID 并行（`OUT_OF_ORDER_ENABLE=1`）；
- 双端口同时读写仲裁；
- 队列满背压；
- outstanding 达上限背压；
- `CFG_RESET` 复位；
- `ARSTN_x` 单独复位；
- 初始化期间 AXI 阻塞/错误；
- 错误注入。

### 17.3 地址/容量用例

- 2G/4G/16G × x16/x32 × 1/2 rank 的 `MEM_BYTES`；
- 16G × x32 × 2 rank：CS stride 等价于 bit32；
- 低密度：CS bit 位置按 `RANK_STRIDE_BYTES` 推导；
- 3G/6G/12G 非 2 的幂密度：线性寻址、无 bit-field 解码；
- 地址等于 `MEM_BYTES-1` / `MEM_BYTES` / 高位非零；
- `CS_BIT` 模式非法配置（stride 非 2 的幂）拒绝；
- `SINGLE_RANK` 模式下 rank 恒 0。

### 17.4 性能趋势用例

- 单端口连续读，观察吞吐和延迟分布；
- 双端口读写混合，观察 round-robin 公平性；
- 不同 `CMD_QUEUE_DEPTH`/`OSTD` 下吞吐变化；
- 延迟模式切换对比；
- 早返模式与基线模式的延迟/吞吐差异。

### 17.5 覆盖点

- 所有 AXI 通道握手组合；
- 所有 burst 类型/长度/size；
- 所有响应类型；
- 所有复位组合；
- 队列满/空/中间状态；
- 仲裁轮转状态；
- BVALID 早返/非早返；
- 地址映射模式。

---

## 18. 后续实测参数获取

| 参数 | 实测方法 | 优先级 |
|---|---|---|
| `CMD_QUEUE_DEPTH` | 测试 spec 8.4 固定速率扫描的首反压临界点；结果记为 `CMD_QUEUE_DEPTH_ENG`。Phase 3 实测：板级 TG 直连真核 16 笔内无反压，记**下界 ≥16**（置信度低）；模型 shell `CMD_REQ_DEPTH=4` 维持 ENG 值不回填 | 低 |
| `READ_OSTD_DEPTH` | 测试 spec 8.1 的饱和点；结果记为 `READ_OSTD_DEPTH_ENG` | 高 |
| `WRITE_OSTD_DEPTH` | 测试 spec 8.1；强制 `AWCACHE=1111, AWCOBUF=0` | 高 |
| `READ_LATENCY_MIN/MAX` | 测试 spec 8.2；MAX 取 P99 | 高 |
| `WRITE_RESP_LATENCY_MIN/MAX` | 测试 spec 8.2；基线配置；MAX 取 P99 | 中 |
| `WRITE_DATA_TO_B_LATENCY` | 测试 spec 8.2 的 WLAST→B | 中 |
| `SYNC_LATENCY` | 多组 `ACLK:ctrl_clk` 实验拟合/分摊；不能直接独立测量 | 中 |
| `ARB_GRANT_INTERVAL` | 测试 spec 8.4 双端口 ILA 最小 grant 间隔。**Phase 4 结论：无参数回填**——参数仅 g_sync（CDC_ENABLE=0）路径生效，板级 CDC 形态不经过该仲裁器（G=2/G=8 表征逐位相同）；维持默认 2 并标注 g_sync-only。板/仿退化比 documented deviation：饱和档模型 1.17~1.34x vs 板级 1.00x（模型保守）、首轮模型 1.03x vs 板级 1.72x（模型乐观，瞬态）（plan §9 Phase 4） | 中 |
| `OUT_OF_ORDER_ENABLE` | 测试 spec 8.7 多 ID 完成顺序。Phase 6 实测：真核 16 笔全并发读按序完成（板 oo_cnt=0 = 模型 OOO=0 档同形）→ 维持 0；适用域=单端口读 16 笔在飞 1MB 分散（写向/双端口未测） | 中 |
| `BVALID` 时机 | 测试 spec 8.5 `AWCACHE/AWCOBUF` 组合 | 中 |
| rank/CS 映射 | 测试 spec 8.8。Phase 7 实测：板级单 rank 2Gb=256MB（peri.xml），末页 256M-4K 可访问、256M 起越界**静默回绕**（模 256MB，[27:0] 截断语义；除 1G=0x4000_0000 孤点 SLVERR）→ 容量配置实锤维持；越界回填无参数可用（`ADDR_HOLE_POLICY=ALIAS` 仅 FIELD_DECODE_DEBUG 空洞窗语义，禁默认）→ `ADDR_HOLE_POLICY=DECERR` 维持，记 documented deviation（模型越界报错=保护方向，真核静默别名=假阴性方向；合法区 <256MB 不触达） | 中 |

实测后替换 6.3/6.4 默认值，模型参数表版本升级。报告中保留 `_ENG` 原始估计和置信度。

**Phase 8 汇总（2026-10-23，correlation 闭环）**：标定流程 Phase 0-8 全部执行完毕。v0.2a 已回填 `READ_LATENCY_MIN/MAX`、`WRITE_DATA_TO_B_LATENCY`、`BVALID_CMD_QUEUE_DELAY`（并修 core_scheduler 0000 非早返语义）；其余参数经板级实测维持 ENG 形态/默认值或记惰性/deviation（逐项见上表注与 plan §9）。回归门禁（plan §7-5）：traceability 基线 **60/60 全绿**（tb_top 48 + tb_top_cdc 9 + tb_unit 3，跑法固化 `tb/regress.sh` + `testlist.txt`，含逐用例 -g 参数映射）；`random_stress` 50 seeds（-sv_seed 2..51）全通过。无新增 RTL 参数替换（spec §22 v0.2e）。

---

## 19. 交付物

1. 模型 RTL/SystemVerilog 或 C++ TLM 源码；
2. 参数配置文件；
3. 测试平台和回归用例；
4. 断言/覆盖报告；
5. 用户手册（参数说明、接口连接、限制）；
6. 实测参数替换指南；
7. 手册假设/勘误清单（本章第 3 章）。

---

## 20. 附录：默认参数汇总

```text
DATA_WIDTH              = 32
AXI_DATA_WIDTH          = 512
AXI_ADDR_WIDTH          = 33
AXI_ID_WIDTH            = 6
MEM_DENSITY_GBIT        = 4
MEM_DENSITY_UNIT        = GBIT_PER_CHANNEL
GBIT_DEFINITION         = BINARY_2^30
NUM_CHANNELS            = 2            // DATA_WIDTH/16
PHYSICAL_RANK           = 1
MEMORY_TYPE             = LPDDR4
NUM_AXI_TARGETS         = 2
SUPPORT_WRAP_BURST      = 1
SUPPORT_NARROW          = 1
SUPPORT_FIXED_BURST     = 0
SUPPORT_AWALLSTRB       = 1
SUPPORT_EXCLUSIVE       = 0
ADDR_MAP_MODE           = LINEAR
RANK_MAP_MODE           = CS_STRIDE
CS_BIT_POS              = derived
ADDR_HOLE_POLICY        = DECERR
MEM_INIT_MODE           = ZERO
MEM_INIT_SEED           = 1

CMD_QUEUE_DEPTH         = 8        // 待实测
WRITE_DATA_QUEUE_DEPTH  = 16       // 待实测
READ_DATA_QUEUE_DEPTH   = 16       // 待实测
READ_OSTD_DEPTH         = 8        // 待实测
WRITE_OSTD_DEPTH        = 8        // 待实测
OUT_OF_ORDER_ENABLE     = 0        // 待实测
R_INTERLEAVE_ENABLE     = 0
ARB_GRANT_INTERVAL      = 2
ARB_QUIET_FAST_PATH     = 1
ARB_QOS_WEIGHT_EN       = 0

CLK_RATIO_ACLK_PER_CTRL = 0.25     // x32 理想值；实测覆盖
SYNC_LATENCY            = 2        // 待拟合
READ_LATENCY_MIN        = 191      // Phase 2 板级标定（板 24/61 ACLK ×8，观测偏移已扣）
READ_LATENCY_MAX        = 492      // Phase 2 板级标定
R_BEAT_INTERVAL         = 1
WRITE_RESP_LATENCY_MIN  = 8        // ENG 值（数据提交路径抖动分量）
WRITE_RESP_LATENCY_MAX  = 24       // ENG 值
WRITE_DATA_TO_B_LATENCY = 451      // Phase 2 板级标定（板 WL 55-99 ACLK ×8）
BVALID_CMD_QUEUE_DELAY  = 28       // Phase 5 板级标定（板 T_AW_B 4-5 ACLK ×8）
BVALID_PHY_ISSUE_DELAY  = 2        // ENG 值；仅 PHY_ISSUE 兜底策略使用
W_ACCEPT_INTERVAL       = 1
LATENCY_MODE            = UNIFORM
LATENCY_SEED            = 1
LATENCY_UNIT            = CTRL_CLK

BVALID_TIMING_MODE      = MANUAL_STRICT
OTHER_AWCACHE_POLICY    = DATA_DONE
AWCOBUF_STRICT          = 1

ERR_CROSS_4KB           = SLVERR
ERR_BURST_LEN           = SLVERR
ERR_BURST_SIZE          = SLVERR
ERR_FIXED_BURST         = SLVERR
ERR_ADDR_RANGE          = DECERR
ERR_ADDR_HOLE           = DECERR
ERR_WSTRB_INVALID       = IGNORE
ERR_ALLSTRB_BEATS       = SLVERR
ERR_ALLSTRB_WSTRB       = SLVERR
ERR_INJECT_RATE         = 0
NARROW_READ_INVALID_LANE = ZERO

INIT_CYCLES             = 1000
INIT_AXI_BLOCK          = 1
INIT_AXI_RESP           = BACKPRESSURE
CFG_RESET_CLEAR_MEM     = 0
ENABLE_CTRL_STATUS      = 0
```

---

## 21. 假设与待确认项

| 项 | 标记 | 说明 |
|---|---|---|
| `AWCACHE` 其他编码对 BVALID 的影响 | 已板级确认（Phase 5，2026-10-23） | `AWCACHE[0]` 单独决定：bit0=1 早返（0001/0011/0111 实测同形），bit0=0 数据提交后（0000/0010/0100/1110 实测同形）；见 correlation-plan §9 |
| `AWCOBUF=1` 时 B 早于 WLAST 的具体时序 | 已板级确认（Phase 5，2026-10-23） | 早返时机由 `AWCACHE[0]` 决定，COBUF 无独立效应；早返延迟以 `BVALID_CMD_QUEUE_DELAY`=28 ctrl 标定（板 T_AW_B 4-5 ACLK ×8 = 32-40 ctrl） |
| FIXED burst 响应 | `[CONFIRM]` | 模型默认 SLVERR |
| WRAP 长度/对齐 | `[CONFIRM]` | 按 AXI4 |
| `SIZE≤3, LEN=256` | `[CONFIRM]` | 按 AXI4；需实测 |
| 非 2 的幂密度地址映射/空洞 | `[CONFIRM]` | 模型线性寻址 |
| `SYNC_LATENCY` 的可观测性 | `[MODEL]` | 无法从 AXI 边界独立测量，只能拟合 |
| 真实 OSTD/队列深度 | `[CONFIRM]` | 只做工程估计，保留 `_ENG` |
| `AWALLSTRB` 的具体语义 | `[CONFIRM]` | 手册只说全选通和 16 beat 上限；WSTRB 全 1 是模型解释 |
| 读数据不同 ID 交织 | `[MODEL]` | 默认不交织；需实测 |

---

## 22. 修订历史

| 版本 | 日期 | 说明 |
|---|---|---|
| v0.1 | 2026-10-21 | 初稿 |
| v0.2 | 2026-10-21 | 根据 kimi3/豆包反馈和手册复核修订：修复 `AWREADY` 依赖 `WVALID`、读地址信号、`AWALLSTRB` 16 beat、地址容量/rank、BVALID 语义、延迟口径；新增勘误表、monitor-only 测试前提、默认全局按序、早返 W 数据规则等 |
| v0.2a | 2026-10-23 | correlation Phase 2/5 板级标定回填：READ_LATENCY 191/492、WRITE_DATA_TO_B_LATENCY 451、BVALID_CMD_QUEUE_DELAY 28；B 时机改 `AWCACHE[0]` bit0 规律（§6.4/§6.5/§7.4/§10.1），0000 非早返定稿，`BVALID_TIMING_MODE` 标记未使用，§21 两项 `[CONFIRM]` 关闭 |
| v0.2b | 2026-10-23 | correlation Phase 3 队列深度标定：板级 TG 直连真核无 shell 门控层，16 笔内零反压 → `CMD_QUEUE_DEPTH` 真核下界 ≥16（§6.3/§18 注），`CMD_QUEUE_DEPTH_ENG` 板级不可精测、shell `CMD_REQ_DEPTH=4` 维持 ENG 值；无 RTL 参数替换 |
| v0.2c | 2026-10-23 | correlation Phase 6/7 标定：OOO 探测真核按序完成 → `OUT_OF_ORDER_ENABLE=0` 维持（§18）；地址/rank 探测板级单 rank 256MB 容量实锤、越界静默回绕（除 1G 孤点）→ `RANK_MAP_MODE`/`CS_BIT_POS`/`ADDR_HOLE_POLICY` 均维持，越界差异记 documented deviation（§6.1/§18/plan §9 Phase 6/7）；无 RTL 参数替换 |
| v0.2d | 2026-10-23 | correlation Phase 4 双口仲裁标定：`ARB_GRANT_INTERVAL` 仅 g_sync 路径生效（CDC 形态 1:1 交替收集，G=2/G=8 表征逐位相同）→ 无参数回填、维持 2 并标注适用域（§6.3/§8.1/§18）；板/仿退化比 documented deviation（饱和模型 1.19x vs 板 1.00x 保守、首轮模型 1.03x vs 板 1.72x 乐观瞬态）（plan §9 Phase 4） |
| v0.2e | 2026-10-23 | correlation Phase 8 回归门禁闭环：traceability 基线回归 **60/60 全绿**（tb_top 48 + tb_top_cdc 9 + tb_unit 3；跑法固化 `tb/regress.sh` + `testlist.txt`，含逐用例 -g 映射与 INIT_AXI_RESP/ADDR_HOLE_POLICY 等参数语义勘误，plan §9 Phase 8）；`random_stress` 50 seeds（-sv_seed 2..51）全通过；tb_top 三用例预期随 v0.2a「0000 非早返」语义更新（early_b/wlast_err/allstrb_early，TB 侧）；无 RTL 参数替换 |

---

**文档状态**：评审修订稿，可进入功能模型实现；`[CONFIRM]` 项需实测/厂商确认。  
**后续动作**：按第 17 章建立回归；按测试 spec v0.2 标定 6.3/6.4 参数；发布 v0.3 时更新实测值。
