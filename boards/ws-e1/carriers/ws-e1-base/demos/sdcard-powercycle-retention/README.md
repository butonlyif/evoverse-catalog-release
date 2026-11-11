[English](README.en.md) | 中文
# sdcard-powercycle-retention — microSD 卡掉电保持读写校验

> 原目录：`TJ180A484S_SDHOST/TJ180A484S/`（原外层的 3 行 `SDHOST_readme.txt`
> 已并入本 README，原文件保留在目录内）

## 1. 概述

**SD 卡 Host 控制器 + 数据掉电保持**验证工程：Sapphire RISC-V 软核经 APB→AXI-Lite
桥控制 `efx_sd_host_controller` IP（SD/SDIO Host + ADMA2），对 microSD 卡执行
"写入 → 整板掉电 → 重新上电 → 读回校验"流程，全部匹配输出 **PASS**，用于验证
SD 卡写入的持久性与 Host 控制器驱动的完备性。

- 器件：Titanium **TJ180A484S**（timing model **I3**，注意与其它 demo 的 C4 不同）
- 工具链：Efinity 2025.1.110.4.9（pass，bitstream 已生成过，active 配置模式）
- 顶层模块：`TJ180A484S`（[TJ180A484S.v](TJ180A484S.v)，芯片级顶层）
- 核心软件：`embedded_sw/soc_ti180/software/standalone/TJ180A484S_SDHOST/src/main.c`
  （"EFX-SD Power-Cycle Retention Test"）

## 2. 硬件资源占用

| 资源 | 配置 |
| --- | --- |
| DDR 硬核 `ddr_inst`（DDR_0） | LPDDR4x、2Gb、x16、1 rank，双 AXI 端口（512-bit），ADMA 数据走 AXI 端口 1 |
| `pll_sys`（PLL_TL0） | → i_soc_clk / i_sd_clk / i_axi0_mem_clk 100MHz |
| `pll_ddr`（PLL_TL2） | 33.33MHz×4 → 133.3MHz（i_axi1_mem_clk） |
| 软核 | Sapphire SoC（`soc_ti180`，efx_soc v3.2.3）：单核 RISC-V，I/D-Cache 4KB，UART0+SPI0/1+I2C0+GPIO0，APB Slave 0–3，主频 100MHz |
| SD Host IP | `tj180a484s_sdhost`（efx_sd_host_controller v6.0，SD/SDIO + ADMA2） |
| 桥 | `apb3_2_axi4_lite_sdhost`（软核 APB slave2 → SDHC 寄存器，基址偏移 +0x100） |
| **SD 引脚（GPIO，3.3V）** | sd_clk=GPIOL_30、sd_cmd=GPIOL_03、sd_dat[0..3]=GPIOL_05/49/04/31、卡检测 sd_cd_n=GPIOL_10 |

板级外设：microSD 卡槽（J8，SDIO3.0，含卡检测）、LPDDR4x、UART。

## 3. 目录结构

```
sdcard-powercycle-retention/
├── TJ180A484S.xml / .peri.xml      # Efinity 工程（打开这个）
├── tj180a484.sdc                   # 时序约束
├── TJ180A484S.v                    # ★ 芯片顶层：DDR 配置 FSM + AXI 粘合 + 实例化 top_soc_sd
├── top_soc_sd.v                    # SoC + SD Host + 桥的系统集成层（引脚映射注释详细）
├── top_soc_oob.v                   # 旧 OOB 顶层（未被工程引用，遗留）
├── SDHOST_readme.txt               # 原始 3 行 readme（历史保留）
├── ip/
│   ├── tj180a484s_sdhost/          # SD Host IP
│   ├── apb3_2_axi4_lite_sdhost/    # APB3→AXI4-Lite 桥 IP
│   └── soc_ti180/                  # Sapphire SoC IP
└── embedded_sw/soc_ti180/
    ├── bsp/efinix/EfxSapphireSoc/
    ├── software/standalone/TJ180A484S_SDHOST/   # ★ 主应用
    │   └── src/{main.c, userDef.h, source.c, intc.c, efx_mmc_driver.c}
    ├── tool/bootloader/ + binGen.py
    └── cpu0.yaml
```

## 4. 工作原理

- **RTL**：`TJ180A484S.v` 完成 LPDDR4x 启动握手（io_memoryReset → CFG_START →
  CFG_DONE → 释放 ARSTN）、SoC `io_ddrA` ↔ DDR 硬核 AXI 端口 0 粘合（ID 位宽
  转换）；`top_soc_sd.v` 集成软核 + 桥 + SD Host，SDHC ADMA 数据经 SoC AXI
  master1 进 DDR。
- **软件**（main.c + userDef.h）：UART 输入 **W** → 擦除并按 LBA 模式写入
  （起始 LBA 0x1000，128 块，数据头 pattern `A9 A3 A6 A5`）；**掉电重启**后
  再运行程序输入 **R** → 逐块读回比对，全匹配输出 **PASS**。
  SD 控制器 50MHz、4-bit 模式，中断接 PLIC USER_INTERRUPT_B。

## 5. 运行与验证

1. Efinity 打开 `TJ180A484S.xml` 编译烧录（active 模式）；
2. 插入 microSD 卡，UART 终端连接；
3. 下载运行 `TJ180A484S_SDHOST` 程序，输入 `W` 写入测试数据；
4. **整板断电再上电**，重新下载运行程序，输入 `R`；
5. 终端输出 **PASS** = 数据保持与读写链路均正常。

## 6. 集成到客户系统的要点

- SD Host 三件套（`tj180a484s_sdhost` + `apb3_2_axi4_lite_sdhost` + 软核 APB
  slave2 挂载）是一个可整体搬移的子系统；SDHC 寄存器基址 = APB slave2 基址
  +0x100，软件 `main.c` 中有对应宏；
- ADMA 描述符走 SoC AXI master1 → DDR，若客户系统无 DDR，需改用 PIO 模式
  并调整 `efx_mmc_driver.c`；
- SD 引脚全部为 3.3V GPIO（bank 电压在 peri.xml 中声明），卡检测 `sd_cd_n`
  低有效；换引脚只改 peri.xml + sdc 约束；
- 写入参数（LBA 起点/块数/pattern）集中在 `userDef.h`，测试无需改代码主体；
- timing model 为 **I3**，与同板其它 demo（C4）不同；Efinity 版本也较旧
  （2025.1），迁移到新版本时注意 SD Host IP 重新生成。

## 7. 已知问题与注意事项

- `top_soc_oob.v` 未被工程引用（旧版 OOB 顶层），仅作参考；
- `TJ180A484S.v` 头注释引用的 `outflow/TJ180A484S_template.v` 模板路径在
  仓库中不存在；
- `top_soc_sd.v` 注释"i_sd_clk ~50MHz"与 SDC 100MHz 约束口径不一（SDHC 内部
  再分频至 50MHz，以 SDC 为准）；
- 本次整理已删除 `ip/` 下内嵌的 T120F576/Ti180J484 devkit 参考工程副本，
  工程不受影响。
