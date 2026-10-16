---
ws_manifest_version: 2
kind: jacket
id: stage0
display_name: WS E1 Base Stage-0 Skeleton
version: 1.0.0
status: active
belongs_to_board: ws-e1
fits_carrier: ws-e1-base
delivery: project-snapshot
project_file: ws-e1-base-stage0.xml
---

[English](stage0.en.md) | 中文

# Stage-0 — ws-e1 + ws-e1-base 骨架工程

`stage0` 是 EvoVerse SDK（`evoverse new-project`）为 `ws-e1` 模块板 + [ws-e1-base](../../ws-e1-base.md) 载板组合生成的最小可运行工程：一个 LED 闪烁设计，只占用时钟、复位、LED 三类骨架信号，用于打通「选板选载板 → 工程生成 → 综合 → 烧录 → 板上观察」的完整链路。

本文件同时是该 jacket 的 item manifest：`jacket.ws-e1-base.stage0` 在初始导入时曾因缺少 manifest 被隔离，自 0.9.1 起提升为 `active`。

## 硬件资源占用

骨架信号从载板 pin map 解析：

| 信号 | 方向 | 管脚 | Bank | 电平 | 板上资源 |
|---|---|---|---|---|---|
| `clk_50m` | in | T18 | TL | 3.3 V LVCMOS | 50 MHz 系统时钟 |
| `arst_n` | in | H21 | 2C | 1.8 V（bank 默认） | 低有效复位按键 |
| `led_user` | out | F21 | 2C | 1.8 V（bank 默认） | 用户 LED |

注意电压是混合的：时钟位于 3.3 V 的 TL bank（显式 `3.3 V LVCMOS`），复位与 LED 位于 1.8 V 的 2C bank（ISF 未显式指定 IO_STANDARD，继承 bank 1.8 V 默认值）。载板各 bank 电压定义：2A_2B、2C、3A、3B、3C、4A、4B、4C 为 1.8 V，BL、BR、TL、TR 为 3.3 V。

## 设计说明

`rtl/top.v`（顶层 `ws_e1_base_stage0`）为纯同步单域逻辑：

- 24 位计数器在 `clk_50m` 上升沿计数，`arst_n` 异步清零；
- 计数器最高位 `cnt[23]` 直接驱动 `led_user`，50 MHz 下约 0.34 s 完成一个闪烁周期。

无 PLL、无其他 IP 依赖，是验证 ws-e1 核心板与 ws-e1-base 载板组合健康状态的最小负载。

## 文件清单与生成方式

```text
stage0/
├── rtl/top.v                         # 骨架 RTL（自动生成）
├── constraints/
│   ├── ws_e1_base_stage0.pins.isf    # 管脚与 bank 电压（自动生成）
│   └── ws_e1_base_stage0.sdc         # 主时钟约束（自动生成）
└── ws-e1-base-stage0.xml             # Efinity 2026.1 工程（自动生成）
```

全部文件由 SDK 从载板 pin map 生成，**不要手工编辑**。时序约束仅声明主时钟：`create_clock -name clk_50m -period 20.000 [get_ports clk_50m]`。

如需调整管脚，应修改载板 pin map 后重新生成；如需承载真实功能，请使用 [golden-top](../golden-top/golden-top.md)、[sensor-fusion](../sensor-fusion/sensor-fusion.md) 或载板下的 demo 工程，而不是修改 stage0。

## 编译与烧录

1. 使用 Efinity 2026.1 打开 `ws-e1-base-stage0.xml`。
2. 依次执行 Synthesis → Place & Route → Generate Bitstream。
3. 烧录后上电，观察到用户 LED 以约 0.34 s 周期闪烁即为通过；若 LED 不亮，优先核对核心板插接方向、时钟 bank 电平与复位极性。
