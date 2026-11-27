---
ws_manifest_version: 2
kind: module
id: ws-e2
material_version: 2.0.1
fpga:
  vendor: efinix
  family: Titanium
  part: TJ375N1156X
soc:
  vendor: rockchip
  part: RK3588J
carriers:
  - ws-e2-rk3588-mc
---

[English](ws-e2.en.md) | 中文

# WS-E2 — TJ375 + RK3588J 异构核心模组（SOM_NOR）

Efinix **TJ375N1156X**（Titanium，FCBGA1156）+ Rockchip **RK3588J**（FCBGA1088）异构模组，
模组原理图权威为 **TBS2009_SOM_NOR**（深南电路 V1.0，34 页，2026-09-18）；载板为
**WS-E2-RK3588-MC-V01**（易灵思 V1.0，25 页，2026-10-14）。FPGA 与 SoC 模组内直连
（MIPI DPHY0/1/2、RGMII、SPI/I2C/GPIO），经 4× 66B2 BTB 连接器引出至 MC-V01 载板。

## 关键存储与启动（NOR 变体权威）

| 器件 | 角色 | 说明 |
|---|---|---|
| GD25LB512MEYIGR | TJ375 配置源 | QSPI NOR 512Mb，active-serial x4（FPGA_CDI0-3/SS/CCK），som p21-22 |
| W66DP2RQQAGJ | TJ375 LPDDR4/4X DRAM | 32bit 单通道，U2 贴装 / U3 DNP（som p24 标题 `24.TJ375_DDR0&1`） |
| FEMDRW128G-88A19 | RK3588 启动 eMMC | HS400 8bit+DS（som p16） |
| FEMDRW032G ×2 | FPGA eMMC（载板侧） | 终接模组 F_EMMC_* 网络（mc p15） |
| RK806-1 | PMIC | RK3588 全域供电（som p13-14） |

> 勘误（2026-11-13）：W66DP2RQQAGJ 角色由「串行 NAND」更正为 FPGA LPDDR4/4X DRAM；
> RTL8111HS 降级为 UNVERIFIED（仅注释可见），实装 PCIe GbE 网卡为 YT6801SH（mc p10）。

## 载板（ws-e2-rk3588-mc V01）

- RK 侧：RJ45（RTL8211FI-CG PHY）、YT6801SH PCIe 网卡、ES8388 音频、USB2/TypeC0-1、
  HDMI 收发、SD（LCK-TF-01AH1809-YLG）、PCIe30X1_0/1 + PCIe20_0/1/2（SATA 复用）、
  Maskrom 键（SARADC_IN0）、FT232RL 调试。
- FPGA 侧：FMC-A HPC、SFP+ ×2、SDI（LMH1218/1219 + LMKDB1202）、CAN ×2（TJA1051T）、
  RS485（CMT83085）、RS232、EtherCAT（LAN9252I + RTL8211FI）、按键/LED/DIP、风扇（PWM）。
- 电源：DC 12V 输入（XDJK-060B-055）→ TPS 系列 5.0/3.318/2.544/1.8/1.2V + VCC_5V0_SOM
  （TPS548A28）+ FMC_VADJ 可选；INA226 功耗监测；SOM_PWR_GOOD。

## 状态

- 物料版本 **2.0.1**（勘误版）；生成器裁定 `INCOMPLETE`：58 条 rk3588 BTB 行
  `FINAL_ENDPOINT_REQUIRED`（连接器引脚号需图形层/用户提供）+ 1 条构建环境源未选。
- Stage0 jacket：`NATIVE_BUILD_NOT_RUN`（未做 Efinity 编译）。
- 完整手册：`carriers/ws-e2-rk3588-mc/docs/generated/board-manual.md`。
- 遗留 BSP 身份（rk3588j-evm，2026-11-11 组装）：`carriers/rk3588j-evm/bsp/manifest.json`，
  已物化于 `<EVOVERSE_HOME>/bsp/ws-e2/99a56fe7`。
