---
ws_manifest_version: 1
kind: ip
id: ddr-bist
display_name: DDR BIST (Memory Built-In Self Test)
version: 1.0.0
board: ws-e1
carrier: ws-e1-base
maintainer: evoverse
license: proprietary
description: DDR LPDDR4 memory built-in self-test (BIST) logic with AXI4 traffic generator and memory checker, supporting both standalone and SoC-integrated APB-controllable modes.
---

[English](ddr-bist.en.md) | 中文

# DDR BIST (Memory Built-In Self Test)

## 来源 Demo
- `demos/ddr-memtest/`（原 DDR_TEST，独立 BIST 测试工程）
- `demos/si5338-clock-config/`（原 SI5338，SoC 集成 APB 可控版本）

## 硬核 IP 配置
- **DDR 控制器**: TJ180A484 LPDDR4 2133MHz (板级硬核，通过 peri.xml 配置)
  - 配置参数详见 constraints/mem_test.peri.xml

> 注：此 IP 为纯 RTL 逻辑层 BIST，不包含 DDR 控制器硬核本身。DDR 控制器由 Interface Designer (peri.xml) 配置生成。

## RTL 文件

### 来自 ddr-memtest（原 DDR_TEST，独立 BIST 版本）
| 文件 | 说明 |
|------|------|
| mem_test.v | 顶层模块 - DDR 内存测试启动逻辑，含双端口 AXI4 BIST 引擎 (test_ddr_start) |
| memory_checker_standalone.v | 独立版内存校验器 - 读写数据比对与错误检测 |
| reset.v | 复位同步逻辑 |

### 来自 si5338-clock-config（原 SI5338，SoC 集成 APB 可控版本）
| 文件 | 说明 |
|------|------|
| design_modules.v | SoC 配套 IP 库，内含多个模块： |
| | - `apb3_slave` - APB3 从设备接口 (BIST 寄存器控制) |
| | - `axi4_slave` - AXI4 从设备接口 |
| | - `memory_checker` - APB 可控版内存校验器 |
| | - `timer_start` - 测试定时器 |
| | - `ext_mem` - 外部存储接口 |
| | - `Asic256To512UpsizerAxi4*` - AXI4 数据宽度转换 (256→512) |
| top_soc_ddr.v | SoC 顶层，集成 Sapphire SoC + DDR BIST + LPDDR4 配置 FSM |

## 约束
| 文件 | 说明 |
|------|------|
| mem_test.peri.xml | 外设引脚约束，含 DDR LPDDR4 配置参数 (TJ180A484S, 2133MHz) |
| constrain.sdc | 时序约束文件 (LPDDR4 2133MHz) |

## 接口
- **AXI4 端口 0** (axi0_*): 512-bit 数据宽度，用于 BIST 写入测试
- **AXI4 端口 1** (axi1_*): 512-bit 数据宽度，用于 BIST 读取校验
- **时钟**: i_sys_clk (系统时钟), axi0_ACLK, axi1_ACLK (DDR 内存时钟)
- **LED/开关**: o_led[5:0] (测试状态指示), i_sw[1:0] (测试模式选择)
- **APB3** (design_modules.v): PSEL, PENABLE, PWRITE, PADDR, PWDATA, PRDATA (BIST 寄存器控制)

## 应用场景
用于 ws-e1-base 底板上的 LPDDR4 内存测试与验证。提供两种使用模式：
1. **独立模式**（ddr-memtest，原 DDR_TEST）：上电后自动执行 BIST 测试，通过 LED 显示通过/失败状态，适用于产线测试。
2. **SoC 集成模式**（si5338-clock-config，原 SI5338）：通过 APB3 寄存器由 RISC-V SoC 控制 BIST 启停和结果读取，适用于运行时内存诊断。
