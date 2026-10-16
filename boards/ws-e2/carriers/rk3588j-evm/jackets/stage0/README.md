[English](README.en.md) | 中文

# Stage0 Jacket — TJ375 SOM (TBS2009) + Carrier (TJ375_RK3588J_EVM)

TJ375N1156X（Efinix Trident-T，Efinity 2026.1）pinout 信息集。目标：从原理图 PDF 矢量源直接
重建引脚映射，经三方交叉验证后产出 Efinity 可消费的约束与 CSV。

> 目录布局对齐 SDK 板卡结构（ws-e1 同款）：本文件位于
> `boards/ws-e2/carriers/rk3588j-evm/jackets/stage0/`；文内 `_device/`、`tools/` 等路径均相对
> 工作区根 `d:\work\ws-e2\`。

## 数据来源

| 来源 | 内容 | 证据 |
|------|------|------|
| SOM 原理图（TBS2009，深南电路，34 页） | p32 RK3588-BTB-CONN（RK 侧/电源/GND）、p33 U9B HDMI/EDP | PDF 矢量提取 |
| Carrier 原理图（TJ375_RK3588J_EVM，易灵思，25 页） | p23 BTB 连接器 | PDF 矢量提取 |
| 器件 pinout CSV（`_device/`） | ball ↔ pin_name ↔ bank ↔ 电压 权威表 | Efinity 导出 |
| `TJ375N1156X.peri.xml` | 器件 bank 权威清单 + 电压（`efxpt:design_db`） | Efinity PT 产出 |

## 交付物

| 文件 | 内容 | 规模 |
|------|------|------|
| `boards/ws-e2/pinout/ws-e2-module.csv` | ball 视角：ball, pin_name, bank, io_bank_voltage, function, som_net, btb_refdes, btb_pin, evm_net, evidence, remark | 302 唯一 ball |
| `boards/ws-e2/carriers/rk3588j-evm/pinout/rk3588j-evm.csv` | 位号视角：BTB 1280 pin 全覆盖，SOM/EVM 网络名对齐 | 1280 行 |
| `constraints/banks.isf` | 24 bank 电压全显式声明（ISF = Python API 源码） | 24 条 `set_iobank_voltage` |
| `_device/rail_nets.json` | SOM∪EVM 电源/GND rail 网络名 → bank 映射 | 24 rail |

## Bank 电压定案

- **HSIO 1.8 V**：`2A 2B 2C 2D 2E 4A 4B 4C 4D`
- **通用 IO 3.3 V**：`TL0 TR0 TR1 TR2 TR3 TR5 BL0 BL1 BL2 BL3 BR0 BR1 BR3 BR4`
- **共享域**：`TL1_TL5`（peri.xml 合并名，一个电压域覆盖 TL1+TL5）= 3.3 V

依据：peri.xml iobank_info 权威结构 + 连接器 rail 网络名（`VCCIO33_*` / `BANK2_VCC_2*_OUT` /
`BANK4D_VCC_ADJ`）+ verify D 项无电压混装。

## 交叉验证裁决（verify_xcheck.py，181 issue → PASS）

- **B2 最强背书**：提取链 net→ball ↔ xlsx'0920' 301/301 零冲突。
- **fmt=31**：纯方括号格式差（`DDR0_DQ31` vs `DDR0_DQ[30]`），ball 一致，非错误。
- **func=11**：功能名约定差（CFG_DONE↔CDONE、RK3588_SPI_*/GPIO*/IIC_* ↔ GPIOB_P/N_47..51），ball 一致。
- **mismatch=137**：编号/命名约定差（DDR 字节通道局部编号 vs Efinity 全局编号；GMAC0_*→Q0_RXDP*；
  MIPI_CSI0_RX_*→MIPI0_TXDP*），无真错位。
- **唯一原理图笔误（AA1）**：网络标号 `GPIOB_P_16_CLK3_N` 应为 `GPIOB_N_16_CLK3_N`（N 侧 ball，
  bank 4D；器件 CSV Y1=P 侧佐证）。`gen_stage0_csv.py` 内置 ALIAS 字典裁决，csv remark 已标注。

## banks.isf 自检（Efinity 官方 importer）

```
EFXPT_HOME=C:/Efinity/2026.1/pt
python311/bin/python.exe  _device/isftest/run_import.py   # 复刻 efx_run_pt_import_isf.py 逻辑
```

- 24 条命令逐行 `INFO: Import` 通过，`Import ISF '...jackets\stage0\constraints\banks.isf'...DONE`，EXIT=0。
- `banks_import_issue.csv`（本 jacket 目录）仅表头（零 issue）。
- 合并结果 `isftest/TJ375N1156X.peri.merged.xml` 抽查：全部 24 bank iostd 与上表一致。

注：官方 `efx_run_pt_import_isf.py --isf_files`（nargs='+' + append）存在嵌套列表 bug，
wrapper `run_import.py` 调用同一 `DesignAPI.import_design()`，仅 flatten 参数。

## 功能视角 pinout（func-view，忽略 BTB 连接器）

按用户指令重构：直接给出 **FPGA / RK3588 各自到器件/接口**的管脚映射与**相互互联**，BTB 连接器仅作
路径标注（`page_ref=/32/,/33/`）不再作为视角主体。

### 交付物

| 文件 | 内容 | 规模 |
|------|------|------|
| `func-pinout-fpga.csv` | FPGA 功能域 pinout：domain/pin/ball/net/page_ref/peer + RK 对端 + EVM 功能标签 | 319 行 |
| `func-pinout-rk3588.csv` | RK3588 功能域 pinout：domain/sch_page/pin/ball/net/peer + FPGA 对端 | 372 行 |
| `_device/func_pinout_fpga.json` | 同上结构化源（含 mipi_channels/qse_channels 独立分节） | — |
| `_device/func_pinout_rk.json` | 同上结构化源 | — |
| `_device/verify_fpga_func.json` | FPGA 用法一致性验证 | 5 PASS / 2 WARN / 0 FAIL |
| `_device/verify_rk_func.json` | RK vs Rockchip datasheet 验证 | 7 PASS |

### FPGA（TJ375）功能域分布（319 pin）

| 域 | 数量 | 对端 |
|----|------|------|
| MIPI 6 通道（MIPI0/1_TX + MIPI0/1/2_RX + MIPI2_TX） | 60 | MIPI0/1_TX→RK CSI0/1_RX（SOM 内直连）；其余 4 通道走 BTB→EVM |
| QSE_Q2_BTB（Q2 SERDES 全通道 + REFCLK×2 对 + CAL_RES） | 21 | BTB→EVM |
| BTB_EVM（GPIOB/L/R 直通 + PCIE PERST） | 147 | BTB→EVM（EVM 功能标签见 CSV） |
| **PCIE30_Q0（Q0_RXD0-3←RK TX、Q0_TXD0-3→RK RX，2×2 模式）** | 16 | **RK3588 PCIE30 PORT0(lane0-1)+PORT1(lane2-3)（SOM 内直连，p27）** |
| CLK_INPUT（PLLIN×18 + EXTFB） | 25 | SOM 时钟源（CLK_25MHz/100M_0/1 落 PLLIN；25M_0/1/3 落普通 GPIO，见观察项） |
| QSE_REFCLK_SLOT（Q0_REFCLK0 对） | 2 | p19 时钟 buffer（PCIE30_REFCLK_SLOT→RK REFCLK_IN） |
| QSE_CLK（Q0_REFCLK1 对 + CAL_RES 未用） | 3 | SOM（REFCLK1 悬空） |
| GMAC0_RGMII（RXD0-3/TXD0-3/RXCLK/TXCLK/TXEN/RXDV） | 12 | RK3588 GPIO2 复用脚（SOM 内直连） |
| RK_GPIO_SPI_IIC（GPIO01-04 + SPI4 + IIC1） | 10 | RK3588（SOM 内直连） |
| CONFIG_JTAG（CDONE/CRESET/NSTATUS/CBSEL/TMS/TCK/TDI/TDO/JTAG_VCCIO_SEL） | 10 | SOM JTAG/BOOT |
| CONFIG_FLASH（FPGA_CDI0-3/SS/CCK，active-serial x4） | 6 | SOM 配置 FLASH |
| REF_RES（4A/4B/4D 参考电阻） | 3 | SOM |
| OTHER（页引用缺失：TEST_N/CLK10_N/PERST_Q0/GPIO_RSD） | 4 | 见观察项 |

### RK3588 功能域分布（372 pin）

FPGA_DIRECT 58（GMAC 12 + CSI 20 + GPIO/SPI/IIC 10 + **PCIE30 数据 16**）· BTB_EVM 各子类 184（MIPI/QSE 56、PCIE 21、
USB/TypeC 21、HDMI/eDP 19、ETH 13 …）· PWR_CLK 50 · SOM_LOCAL 46 · EMMC 14 · NO_NET 19（电源/空脚）。

### FPGA↔RK3588 互联总览（SOM 板内直连，共 116 pin 对）

| 通道 | FPGA 侧 | RK 侧 | 信号数 |
|------|---------|-------|--------|
| MIPI CSI0/1 | MIPI0/1_TX（p26） | MIPI_CSI0/1_RX | 2×10 |
| GMAC0 RGMII | GPIOB_31-35（p21） | GPIO2/4 复用 | 12 |
| **PCIe 3.0（QSE Q0，2×2）** | **Q0_RXD0-3/Q0_TXD0-3（p27）** | **PCIE30_PORT0+PORT1** | **16** |
| GPIO/SPI/IIC | GPIOB_47-51（p21） | GPIO1/2/4 | 10 |
| PCIe REFCLK | Q0_REFCLK0（p27→p19 buffer） | PCIE30_PORT0/1_REFCLK_IN | 2（经 buffer） |

### FPGA 侧验证结论（verify_fpga_func.py）

- **V1 MIPI**：6 通道 × 10 lane（D0-D3 + CLK，P/N 成对）完整。
- **V2 PLLIN**：CLK_25MHz→GPIOR_140_PLLIN1、CLK_100M_0/1→GPIOL_25/52_PLLIN1 正确；⚠ CLK_25M_0/1/3
  落普通 GPIO（GPIOR_97/GPIOL_46/GPIOL_23）——**已复核球号 y 对齐（功能网名与球号 dy∈[-1,0]），归属正确**，
  属设计选择（EVM 25M 时钟进普通 IO）；若用作 PLL 参考需确认 TJ375 允许非专用 pad 输入。
- **V3 配置链**：active-serial x4 六线 + JTAG 六信号 + NSTATUS + CBSEL×2 完整。
- **V4 RGMII**：12 信号齐全，对端 RK 球号经 datasheet 复用链验证。
- **V5 差分对**：BTB 直通 34 对 P/N 完整；⚠ GPIOB_33/44 为 RGMII RXCLK/TXCLK 拆用 P 脚（合法单端
  用法）；GPIOB_43 对 **已复核**：P=CSO_CLK10_P（走 /32/）与 N=CSI_CLK10_N 功能后缀不同，实为两个
  独立单端信号，N 侧本地网 + DNP 电阻 = 预留脚，非标注缺失。
- **V6/V7**：REF_RES 三 pad 无信号网；319 pin（含 QSE 42）球号唯一且全部与 Efinity 权威 ballmap 一致。
- **V8 QSE/PCIe（新增）**：Q0↔RK PCIE30 16 条数据线 lane/极性确定性配对（2×2 模式）；Q0_REFCLK0 经
  p19 buffer；Q2 全通道走 BTB；CAL_RES 接 3.01K。

### RK3588 侧验证结论（parse_rk3588_datasheet.py）

对 Rockchip **RK3588 Datasheet V2.2**（FCBGA1088）Table 2-1 逐球对账：**363/367 = 98.9% 精确/复用链
匹配**。eMMC 13 球（Y33/W33/V32/AA33/Y32/AA32/W32/V33/W34/V34/Y34/AA34）、GMAC0 RGMII 12 脚、
MIPI CSI0/1、GPIO01-04/SPI/IIC 全部一致。4 个差异为 `USB30_2_SSTXN` vs datasheet `USB30_SSTXN`
命名差异（球号与 PCIE20_2/SATA30_2 功能段完全正确，良性）。AD4=NC 与原理图 "Must floating" 标注一致。

## Stage0 Efinity 工程（可编译最小骨架）

在 pinout 信息集之上新建的最小可编译工程，验证「工程 XML → RTL → ISF → 比特流」全链路在
TJ375N1156X（family=**Titanium**，timing model **C4**）上可用。

### 文件清单

| 文件 | 作用 |
|------|------|
| `ws-e2-stage0.xml` | Efinity 工程 XML（`enf_proj` namespace，unified_flow=true，sdc/isf 路径相对 XML） |
| `rtl/top.v` | 最小组合逻辑：`assign led_user = ~user_sw;`（避免 VDB-9009 全常量优化） |
| `constraints/banks.isf` | 24 bank 电压声明（工程 XML 引用） |
| `constraints/ws_e2_stage0.pins.isf` | stage0 GPIO：bank 电压 + 引脚分配 + IO_STANDARD + PULL_OPTION |
| `constraints/ws_e2_stage0.sdc` | 纯组合无时钟，暂仅注释（加时钟后必须补 create_clock） |
| `compile.bat` | 一键 `efx_run.bat --flow compile`（内置正确环境变量） |

### 引脚分配（来源：pinout/ws-e2-module.csv）

| RTL 端口 | 器件 pin | 球号 | bank | 方向 | 属性 |
|----------|----------|------|------|------|------|
| `user_sw` | GPIOR_150 | R11 | TR1 (3.3 V) | input | WEAK_PULLUP（开关断开=高） |
| `led_user` | GPIOR_98 | M25 | TR1 (3.3 V) | output | —（拉低点亮） |

### 编译证据（2026-09-21）

```
map : PASS  →  interface : PASS  →  pnr : PASS  →  pgm : PASS   (EXIT=0)
产物: outflow/ws-e2-stage0.bit (23 MB) / .hex / .lpf / .pinout.rpt
```

ISF importer 自检（`_device/isftest/run_import.py`，复刻 `efx_run_pt_import_isf.py`）EXIT=0。

### Unified flow 三个关键坑（后续 jacket 必读）

1. **残留 `ws-e2-stage0.peri.xml` 会导致 GPIO 同名创建冲突**
   （`Fail to create gpio. Instance with the same name has been created`）。peri.xml 是 PT 流程
   生成物；早期实验残留的旧实例（含标量/总线双实例）会让重生成的 `unified.isf` 的
   `create_*_gpio` 撞名。清除 outflow 时必须连工程根目录的 peri.xml 一起删。
2. **CLI 纯流程必须显式 `set_property("x","IO_STANDARD","3.3 V LVCMOS","GPIO")`**。
   官方样例不写是靠 GUI peri.xml 的默认值兜底；纯 CLI 新建设计默认 1.8 V，与 3.3 V bank 冲突，
   Design Check 报 `gpio_rule_io_standard_bank`。
3. **`EFINITY_HOME` 必须是正斜杠**（对齐官方 `setup.bat` 的 `%EFINITY_HOME:\=/%`）。
   系统环境变量是反斜杠时 `efx_run.bat` 跳过 setup.bat，反斜杠进入 efx_pnr 的 Tcl `source`
   被当转义符（`C:\Efinity\2026.1` → `C:Efinity6.1`）→ `Failed to load timing modules`。
   compile.bat 已内置正确值。

## 范围与限制

- Bank 电压全显式声明；GPIO 分配仅 stage0 骨架两脚（user_sw/led_user），后续设计阶段按 pinout CSV 追加。
- EVM 侧 16 个 SOM 空标号位从 EVM 网络名兜底解析，均已落入 pinout-carrier.csv。
- `_device/isftest/` 保留自检证据（peri 副本 + wrapper + merged XML），勿作工程输入。
