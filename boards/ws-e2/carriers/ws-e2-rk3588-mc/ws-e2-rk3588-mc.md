---
kind: carrier
id: ws-e2-rk3588-mc
belongs_to_board: ws-e2
---

[English](ws-e2-rk3588-mc.en.md) | 中文

# WS-E2 RK3588 MC 载板（SOM_NOR 变体）说明文档

本文档描述 `ws-e2-rk3588-mc` 载板（MC-V01，SOM_NOR 启动变体）。物料由 ws-e2
v2.0.1 物料战役产出并经勘误复检（v2.0.1 勘误已应用）；所有字段以
`board.yaml` / `hardware.yaml` / `platforms/rk3588/platform.yaml` 的
CONFIRMED 事实为准，本文件是索引与边界说明，不引入新事实。

## 1. 关键已确认事实（摘要）

| 维度 | 已确认值 | 出处 |
|---|---|---|
| SoC | Rockchip RK3588J | `platforms/rk3588/platform.yaml` |
| DDR | 2x LPDDR4X ATL4X8G32M2D-46 IT（8GB 总量，客户确认 2026-11-10） | 同上 `ddr` 段（CUSTOMER_CONFIRMED_2026-11-10） |
| 启动 | eMMC HS400 8-bit（SOM_NOR 变体） | 同上 `boot_storage` 段 |
| 调试串口 | UART2_M0_DEBUG，1500000 波特，ttyS2 | 同上 `debug_uart` 段 |
| 期望设备树 | `ws-e2-rk3588-mc.dtb`（源 `platforms/rk3588/ws-e2-rk3588-mc.dts`） | 同上 `expected_dtb` |
| 环境 | Linux Environment Manager `rk3588-ai@2026.11.1`（contract environment-manager/v1，LINUX_ENVIRONMENT_MANAGER_SATISFIED） | 同上 `environment` 段 |
| FPGA 侧 | TJ375N1156X，Stage0 jacket 与 banks ISF 见 `jackets/stage0/`、`constraints/` | `board.yaml` artifacts |

## 2. 与 rk3588j-evm 载板的关系

同一 WS-E2 核心模组的两种载板变体：`rk3588j-evm`（评估底板，CAP 侧）与本
载板（MC-V01，SOM_NOR）。两者共享同一 RK3588J 设备权威
（`devices/RK3588J.authority.json`，coverage: subset）与同一 Linux
Environment Manager 环境；DTS、启动存储与平台配置彼此独立，见各自
`platforms/rk3588/`。

## 3. 材料边界（2026-11-14 时点）

- 生成链（`project.generate`）当前仅对 `rk3588j-evm/minimal-linux` 具备完整
  生成物料（reference-projects + BSP manifest）。本载板的
  `reference-projects/`、`bsp/manifest.json` 尚未落库：以
  `carrier=ws-e2-rk3588-mc` 发起生成会得到明确的 `RK_PROJECT_MATERIAL_MISSING`
  报告而非静默绑定 EVM 物料。
- RK3588J 权威覆盖 350-ball 中的推导子集（coverage: subset）；未收录 ball
  校验报 `AUTHORITY_COVERAGE_GAP`，发布前需对照完整封装图确认。版本契约见
  [docs/release-README.md](../../../../docs/release-README.md)。
