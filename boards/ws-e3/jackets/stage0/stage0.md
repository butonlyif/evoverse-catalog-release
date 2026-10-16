---
ws_manifest_version: 2
kind: jacket
id: stage0
display_name: WS E3 Stage-0 Skeleton
version: 1.0.0
status: active
belongs_to_board: ws-e3
delivery: project-snapshot
project_file: ws-e3-stage0.xml
---

[English](stage0.en.md) | 中文

# Stage-0 — ws-e3 骨架工程

`stage0` 是 EvoVerse SDK（`evoverse new-project`）为 [ws-e3](../../ws-e3.md) 独立板生成的最小可运行工程：一个 LED 闪烁设计，只占用时钟、复位、LED 三类骨架信号，用于打通「工程生成 → 综合 → 布局布线 → 烧录 → 板上观察」的完整链路。

## 硬件资源占用

| 信号 | 方向 | 管脚 | 电平 | 板上资源 |
|---|---|---|---|---|
| `clk_50m` | in | R3 | 1.8 V LVCMOS | 板载系统时钟 |
| `arst_n` | in | A3 | —（bank 默认） | 低有效复位按键 |
| `led_user` | out | C1 | —（bank 默认） | 用户 LED |

信号沿用了 SDK 的 `clk_50m` 命名约定；实际主频以板卡晶振为准，SDC 按 100 MHz（10 ns 周期）约束。管脚来自 [ws-e3.md](../../ws-e3.md) 板卡 pin map 的自动解析。电平方面，时钟以显式 IO_STANDARD `1.8 V LVCMOS` 约束，`arst_n` 与 `led_user` 未显式指定，继承所在 bank 的默认设置。

## 设计说明

`rtl/top.v`（顶层 `ws_e3_stage0`）为纯同步单域逻辑：

- 24 位计数器在时钟上升沿计数，`arst_n` 异步清零；
- 计数器最高位 `cnt[23]` 直接驱动 `led_user`，50 MHz 下约 0.34 s 完成一个闪烁周期；在 100 MHz 实际主频下闪烁频率相应加倍。

无 PLL、无其他 IP 依赖，是验证 ws-e3 板卡健康状态的最小负载。

## 文件清单与生成方式

```text
stage0/
├── rtl/top.v                       # 骨架 RTL（自动生成）
├── constraints/
│   ├── ws_e3_stage0.pins.isf       # 管脚与 bank 电压（自动生成）
│   └── ws_e3_stage0.sdc            # 主时钟约束（自动生成）
├── ws-e3-stage0.xml                # Efinity 2026.1 工程（自动生成）
└── ws-e3-stage0.peri.xml           # Interface Designer 数据库（生成物）
```

全部文件由 SDK 从板卡 pin map 生成，**不要手工编辑**。时序约束仅声明主时钟：`create_clock -name clk_50m -period 10.000 [get_ports clk_50m]`。

如需调整管脚，应修改板卡 pin map 后重新生成；如需承载真实功能，请新建 jacket，而不是修改 stage0。

## 编译与烧录

1. 使用 Efinity 2026.1 打开 `ws-e3-stage0.xml`（器件 TJ375N484X）。
2. 依次执行 Synthesis → Place & Route → Generate Bitstream。
3. 烧录后上电，观察到用户 LED 周期性闪烁即为通过；若 LED 不亮，优先核对 1.8 V bank 电平设置与复位极性。
