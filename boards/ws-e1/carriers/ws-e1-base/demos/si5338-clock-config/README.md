[English](README.en.md) | 中文
# si5338-clock-config — Si5338 可编程时钟配置与时钟质量验证

> 原目录：`SI5338/SI5338/TJ180A484_soc_lpddr4/`（三层嵌套已扁平化，工程文件现位于 demo 根目录）

## 1. 概述

在 WS-E1 平台上完成 **Si5338A 可编程时钟发生器的完整配置与验证闭环**：

1. **配置**：FPGA 内 Sapphire RISC-V 软核经 I2C0（7 位地址 **0x70**，100kHz）向
   Si5338 逐条写入寄存器表（`Si5338-RevB-Registers.h`），最后写寄存器 246=0x02
   软复位生效，全程 UART 打印读写日志；
2. **验证**：Si5338 输出的 156.25MHz 差分时钟经 **LVDS RX（GPIOB_PN_16）→ PLL_BL2**
   锁相恢复，`si5338_cnt[25]` 分频驱动 **LED0 以约 2.3Hz 闪烁**；同时该时钟经
   GPIOL_33（clkout）输出到引脚可供示波器复核。

工程同时是一个 **Sapphire SoC + LPDDR4x 单 AXI 端口** 的完整 SoC 参考设计
（含 FreeRTOS/lwIP/FatFS BSP 软件树）。

- 器件：Titanium **TJ180A484S**（C4）
- 工具链：Efinity 2026.1.132.1.15（pass，bitstream 已生成过）
- 顶层模块：`top_soc`（[top_soc.v](top_soc.v)）

## 2. 硬件资源占用

| 资源 | 配置 |
| --- | --- |
| DDR 硬核 `ddr_inst1` | LPDDR4x、2Gb、x16、1 rank，**仅 AXI target0 使能**（io_ddrA_*，512-bit） |
| `main_pll`（PLL_TL0） | 50MHz → io_systemClk 100MHz |
| `ddr_pll`（PLL_TL2） | 33.33MHz×4 → io_memoryClk 100MHz、133.3MHz DDR 时钟 |
| `pll_inst3`（**PLL_BL2**） | 参考 = Si5338 差分时钟 156.25MHz，`si5338_pll_locked` |
| **LVDS RX ×1** | `FPGA_SI5338_CLK_IN`（GPIOB_PN_16）接收 Si5338 输出差分时钟 |
| 软核 | **Sapphire SoC**（VexRiscv）：I2C0（GPIOL_42/50，3.3V）、SPI0、UART0（GPIOR_61/57）、GPIO0、双 JTAG |
| GPIO clkout | `si5338_pll_clk_156m25` @GPIOL_33（恢复时钟输出供测量） |

板级外设：Si5338A 时钟发生器、LPDDR4x、UART 串口、LED0、50/33.33MHz 晶振。

## 3. 目录结构

```
si5338-clock-config/
├── soc.xml / soc.peri.xml         # Efinity 工程（打开这个）
├── constraints.sdc                # 时序约束（Interface Designer 自动生成）
├── top_soc.v                      # 顶层 top_soc（SoC + DDR + Si5338 时钟链路）
├── design_modules.v               # Sapphire 配套模块
├── sapphire_soc.v / *_define.vh   # Sapphire SoC IP 生成代码
├── EfxSapphireSoc...ram_symbol*.bin  # SoC 片上 RAM 初始化镜像 ×4
└── embedded_sw/
    ├── sapphire_soc/              # 当前有效软件树（BSP + 全套例程，无 Si5338 程序）
    └── sapphire_soc_backup/       # 旧版 BSP —— ★ Si5338 配置程序只在这里
        └── software/standalone/i2cCfgSi5338/
            ├── src/main.c                      # I2C 写入 Si5338 寄存器表
            └── src/Si5338-RevB-Registers.h     # Si5338 寄存器配置表
```

> **重要**：`i2cCfgSi5338` 应用只存在于 `embedded_sw/sapphire_soc_backup/`
> 目录中，主软件树 `sapphire_soc/` 内没有。`sapphire_soc_backup` 虽为旧版 BSP
> 备份，但**不可删除**。

## 4. 工作原理

- **RTL**（top_soc.v）：Sapphire SoC 经 AXI 互连访问 LPDDR4x（含 ID 位宽适配、
  apcmd/allstrb/cobuf 等硬核专用信号处理）；DDR Startup Sequencer 握手后释放
  `io_memoryResetn`。Si5338 时钟链路：LVDS RX → PLL_BL2 → `si5338_cnt` 自由计数
  → `led0 = si5338_cnt[25]`；SoC 内置 memory checker 结果经 `memoryCheckerPass` 输出。
- **软件**（i2cCfgSi5338/src/main.c）：遍历 `Si5338-RevB-Registers.h` 寄存器表，
  `Reg_Mask=0xff` 直接写、否则读-改-写，最后写 246=0x02 软复位；每条读写经
  UART 打印。

## 5. 运行与验证

1. 烧录 bitstream（Efinity 打开 `soc.xml` 编译）；
2. 经 OpenOCD/JTAG 下载并运行 `i2cCfgSi5338` 程序（cpu0.yaml 构建）；
3. UART 终端看到 "I2C Cfg Si5338 Begin … Done" 及逐条寄存器日志；
4. 配置成功后 **LED0 约 2.3Hz 闪烁**（156.25MHz / 2^26）；
5. 可选：示波器测 GPIOL_33 上 156.25MHz 时钟。

## 6. 集成到客户系统的要点

- **Si5338 寄存器表**：换时钟方案时用 SiLabs ClockBuilder 重新生成
  `Si5338-RevB-Registers.h`，软件流程无需改动；
- **时钟回测链路**（LVDS RX → PLL_BL2 → 计数/clkout）可整体复用，作为任何
  外部差分时钟的"进 FPGA 后锁定验证"模板；
- DDR 侧为单 target0 配置，与双端口写法（见 ddr-memtest demo）可对照裁剪；
- 工程 `ip_info` 引用 `ip/sapphire_soc/settings.json`，但仓库内无 `ip/` 目录，
  打开工程时 Efinity 会按 settings 重新生成 Sapphire IP，属预期行为。

## 7. 已知问题与注意事项

- `sapphire_soc_backup/` 与 `sapphire_soc/` 两套 BSP 内容大面积重复（数百文件），
  因 Si5338 程序仅存于 backup 中而保留；如需统一，应先把 `i2cCfgSi5338`
  迁移到主树再清理；
- 目录名 `TJ180A484_soc_lpddr4` 与 demo 功能（Si5338）无关，为历史遗留，
  本次整理已将工程提升到 `si5338-clock-config/` 根目录。
