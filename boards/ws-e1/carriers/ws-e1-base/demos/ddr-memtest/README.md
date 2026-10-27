[English](README.en.md) | 中文
# ddr-memtest — LPDDR4x 内存读写比对测试

> 原目录：`DDR_TEST/DDR_TEST/`（双层嵌套已扁平化）

## 1. 概述

纯硬件（无软核）LPDDR4x 内存自测试工程：FPGA 内两组独立的 `memory_checker`
状态机分别经 DDR 硬核控制器的 **AXI target0 / target1 两个 512-bit 端口**，
对板载 LPDDR4x-2133 颗粒执行"先写后读回比对"，结果通过 6 位 LED 直接指示。
这是 9 个 demo 中结构最简单的一个，适合作为 **DDR 硬核集成 / LPDDR4x 引入的
最小参考工程**。

- 器件：Efinix Titanium **TJ180A484S**（timing model C4，484 封装）
- 工具链：Efinity 2025.2.288.4.15（`last_run_state=pass`，bitstream 已生成过）
- 顶层模块：`test_ddr_start`（[rtl/mem_test.v](rtl/mem_test.v)）
- 无软核、无 UART，验证完全靠 LED

## 2. 硬件资源占用

| 资源 | 配置 |
| --- | --- |
| DDR 硬核 `ddr_inst1`（DDR_0） | LPDDR4x、2Gb 密度、x16、1 rank，**AXI target0 + target1 双端口均使能**（512-bit 数据 / 64-bit strb） |
| `pll_inst1`（PLL_TL0） | 50MHz 参考 → CLKOUT0/i_sys_clk 及 `axi0_ACLK`/`axi1_ACLK`（250MHz，SDC 4.0ns） |
| `pll_inst2`（PLL_TL2） | 33.33MHz 参考 ×4 → DDR PHY 时钟 |
| GPIO | `sys_clk_ref`=GPIOL_26（50MHz，3.3V，pll_clkin）、`ddr_clk_ref`=GPIOL_32（33.33MHz） |
| IO bank | TL=3.3V LVCMOS，其余 1.8V |

板级外设：LPDDR4x-2133 颗粒、6 位 LED、2 位拨码开关（`i_sw[1:0]` 端口保留）。

## 3. 目录结构

```
ddr-memtest/
├── bsp/
│   └── tj180A484_lpddr4_2133M/   # Efinity 工程目录
│       ├── mem_test.xml          # 工程文件（打开这个）
│       ├── mem_test.peri.xml     # Interface Designer：DDR/PLL/GPIO 硬核配置
│       ├── constrain.sdc         # 时序约束（AXI 250MHz ×2）
│       ├── mem_test.hex          # bitstream HEX 编程文件（可直接烧录）
│       └── debug_profile.wizard.json  # Debugger 向导配置（已禁用，未引用）
└── rtl/
    ├── mem_test.v                # 顶层 test_ddr_start：启动 FSM + 双 checker
    ├── memory_checker.v          # 写→读→比对状态机（含 mark_debug 观测信号）
    └── reset.v                   # 异步复位、同步释放复位桥（CYCLE 参数化）
```

工程以 `bsp/tj180A484_lpddr4_2133M/` 为工程根，RTL 以相对路径 `../../rtl/` 引用，
目录可整体搬移，不影响工程打开。

## 4. 工作原理

1. 上电等待 `sys_pll_lock & ddr_pll_lock`；
2. 状态机 IDLE→CFG_START→CFG_DONE 驱动 **DDR Startup Sequencer**
   （CFG_RST/START/DONE/SEL 信号组）完成硬核内部配置；
3. `ddr_cfg_ok` 后释放 axi0/axi1 两套 AXI 复位；
4. 两个 `memory_checker` 并行运行：
   - checker0 覆盖地址 0 ~ 0x201900（约 2MB+）
   - checker1 覆盖默认 0x1900 区间
   - FSM：`IDLE→WRITE_ADDR→WRITE→READ_ADDR→READ_COMPARE→DONE`，输出 `fail`/`done`
     及 `rdata_obs`/`rdata_exp` 观测信号（已 mark_debug）。

## 5. 运行与验证（LED 含义）

| LED | 含义 |
| --- | --- |
| led5 | DDR 硬核配置完成（CFG_DONE） |
| led4 / led3 | checker0 / checker1 测试完成 |
| led2 / led1 | checker0 / checker1 通过（完成且无 fail） |
| led0 | 双端口全部通过（最终 PASS） |

全部点亮即 LPDDR4x 双 AXI 端口读写通路正常。若需深入调试，可在 Efinity GUI
中重新使能 Debugger 后抓取 `memory_checker` 的 mark-debug 信号观察读回/期望
数据。

## 6. 编译与烧录

1. Efinity 打开 `bsp/tj180A484_lpddr4_2133M/mem_test.xml`；
2. 直接 Run（bitstream flow），bitstream 选项：active x1、压缩开、同时产出 .bit/.hex；
3. 烧录 `mem_test.hex`（或重新生成的 bitstream）到 Flash / 直接配置。

## 7. 集成到客户系统的要点

- **DDR 硬核配置以 `mem_test.peri.xml` 为准**：LPDDR4x 2Gb x16 单 rank、双 target。
  换颗粒时改 `ddr_inst1` 的密度/位宽与 clkin_sel；
- AXI 位宽 512-bit、strb 64-bit，端口命名 `axi0_*`/`axi1_*` 可直接对接客户逻辑
  或替换 `memory_checker` 为业务模块；
- DDR Startup Sequencer 启动握手（等 lock → CFG_START → 等 CFG_DONE → 释放复位）
  是 Titanium DDR 硬核的必要流程，移植时保留 [rtl/mem_test.v](rtl/mem_test.v) 中
  这段 FSM；
- `reset.v` 复位桥按 AXI 时钟域各实例化一份，跨时钟域复位不要复用同一信号。

## 8. 已知问题与注意事项

- `constrain.sdc` 中大量 PLL/DDR AXI 接口 input/output delay 约束处于**注释状态**
  （Efinity 生成模板未启用），当前只约束了两个 250MHz AXI 时钟；高速时序收敛
  场景需按需启用；
- bsp 子目录名 `tj180A484_lpddr4_2133M` 沿用 Ti180 官方参考设计命名，
  与工程名 `mem_test`、顶层 `test_ddr_start` 三者名称互不一致（历史遗留，
  不影响使用）。
