---
ws_manifest_version: 2
kind: module
id: ws-e2
fpga:
  vendor: elitestek
  family: Titanium
  part: TJ375N1156X
---

[English](ws-e2.en.md) | 中文

# WS-E2 — TJ375 核心模组（TBS2009）说明文档

Efinix **TJ375N1156X**（Trident-T，FCBGA1156，673 pads，Efinity 2026.1）+ Rockchip **RK3588J**
异构核心模组，板卡厂商深南电路（原理图 TBS2009_SOM_CAP/NOR，34 页）。FPGA 与 SoC 在模组内
直接互联（MIPI CSI / PCIe 3.0 / RGMII / SPI / I2C / GPIO），并通过 1280-pin BTB 连接器引出至
RK3588J EVM 底板。

## 1. 主要芯片

| 位号 | 型号 | 功能 | 原理图页 |
|------|------|------|---------|
| U1 | **RK3588J**（FCBGA1088） | SoC：4×Cortex-A76@2.4G + 4×A55、Mali-G610、6TOPS NPU、48MP ISP、HDMI2.1 TX×2/RX、PCIE3.0×2(4lane)、USB3×3、GMAC×2 | p4-p12（part A-Z） |
| U2 | **TJ375N1156X** | FPGA：MIPI 3×(TX+RX) D-PHY、QSE SERDES 2×x4（Q0/Q2，PCIe 3.0 硬核）、DDR 控制器、active-serial x4 配置 | p20-p22、p26-p29（part A-Z） |
| U2200 | **RK806-1** | Rockchip PMIC：14 路 BUCK/PLDO/ALDO，供 RK3588 全域（VDD_CPU_BIG 0.75V@3.5A、VDD_NPU、VDD_GPU 等）+ FPGA VCC_CORE | p13-14 |
| U3A/B… | **LPDDR4x 4GB**（Hynix H9 系列） | RK3588 DDR（64bit，p5）| p5 |
| U38xx | **LPDDR4x 4GB**（Hynix H9 系列） | TJ375 DDR（p24 DDR0_* 通道） | p24 |
| U5（p6） | eMMC（HS400，8bit + DATA_STROBE + RSTN） | RK3588 启动存储 | p6 |
| U3B | **W66DP2RQQAGJ**（Winbond SPI NAND 1Gb） | TJ375 数据存储（经 SPI/QSE） | p24 |
| U3800/U3801 | SPI FLASH（NOR，SOM_NOR 版本为 GD25LB512MEYIGR 512Mb） | TJ375 配置/启动源（active-serial x4：FPGA_CDI0-3/SS/CCK） | p15/p21 |
| X2 | 24MHz 晶振 | RK3588 XIN24M | p4 |
| Y 组 | 25MHz/100MHz 晶振 + **EZ8304A**×3（时钟 fanout） | SOM 本地时钟源：CLK_25MHz、CLK_100M_0/1；PCIe REFCLK 分配 | p19/p21/p30 |
| RJGT105T3 | 安全芯片 | RK 生态 Secure OTA/密钥 | p22 |

> SOM 有两个原理图版本：CAP（eMMC 大容量配置）与 NOR（GD25 启动），本工作区以 CAP 版为准。

## 2. 电源架构

- 输入 VCC_5V0（经 BTB 从 EVM 供入）
- **RK806-1**：RK3588 全部核压/IO 域 + FPGA VCC_CORE（0.95V SERDES/核压由 p30 独立 buck 补充）
- FPGA IO bank：HSIO（2A-2E、4A-4D）= 1.8 V，通用 IO（TL/TR/BL/BR）= 3.3 V，TL1_TL5 共享域 3.3 V
  （24 bank 全显式声明见 `jackets/stage0/constraints/banks.isf`，Efinity importer 自检通过）

## 3. TJ375（FPGA）管脚映射

### 3.1 功能域分布（319 pin，全量见 `jackets/stage0/func-pinout-fpga.csv`）

| 域 | 数量 | 去向 |
|----|------|------|
| MIPI（3×TX + 3×RX，每通道 CLK+D0-D3） | 60 | MIPI0/1_TX→RK CSI；其余 4 通道→BTB→EVM |
| QSE Q2（SERDES x4 + REFCLK×2 + CAL_RES） | 21 | →BTB→EVM（QSE3/4 高速扩展） |
| PCIe Q0（RXD0-3/TXD0-3） | 16 | →RK PCIE30（SOM 内直连） |
| BTB GPIO 直通（B/L/R bank + PERST） | 147 | →BTB→EVM（PHY/EtherCAT/SDI/SFP/FMC/UART/KEY…） |
| 时钟输入（PLLIN×18 + EXTFB + 晶振组） | 25 | SOM 晶振 + EVM 时钟 |
| GMAC0 RGMII | 12 | →RK（FPGA 作 RK 的以太网 PHY 侧） |
| RK GPIO/SPI/IIC | 10 | →RK |
| 配置链（JTAG 6 + CDI0-3/SS/CCK + NSTATUS/CBSEL×2） | 16 | SOM JTAG（EVM FT 桥）+ 配置 FLASH |
| REF_RES×3、其他 4 | — | 参考电阻/测试点 |

### 3.2 FPGA↔RK3588 互联映射（SOM 板内直连，116 pin 对）

**GMAC0 RGMII（12）**

| FPGA pin | ball | 信号 | RK pin | RK ball |
|---|---|---|---|---|
| GPIOB_P_44_CLK11_P | M2 | GMAC0_TXCLK | GPIO2_B3_d | AE33 |
| GPIOB_N_36_CDI6 | P4 | GMAC0_RXD2 | GPIO2_A6_u | AC32 |
| GPIOB_P_36_CDI7 | P5 | GMAC0_RXDV_CRS | GPIO4_C2_d | AE31 |
| GPIOB_N_31 | U3 | GMAC0_TXEN | GPIO2_C0_d | AE34 |
| GPIOB_N_32 | T5 | GMAC0_RXD1 | GPIO2_C2_d | AD31 |
| GPIOB_N_34 | V1 | GMAC0_TXD2 | GPIO2_B1_u | AC33 |
| GPIOB_N_35 | U1 | GMAC0_TXD3 | GPIO2_B2_u | AC34 |
| GPIOB_P_31 | U4 | GMAC0_RXD0 | GPIO2_C1_d | AD32 |
| GPIOB_P_32 | R5 | GMAC0_RXD3 | GPIO2_A7_u | AC31 |
| GPIOB_P_33 | T4 | GMAC0_RXCLK | GPIO2_B0_u | AE32 |
| GPIOB_P_34 | V2 | GMAC0_TXD0 | GPIO2_B6_d | AD33 |
| GPIOB_P_35 | U2 | GMAC0_TXD1 | GPIO2_B7_d | AD34 |

**PCIe 3.0 QSE Q0（2×2 模式：PORT0=lane0-1、PORT1=lane2-3，16 线）**

| FPGA pin | ball | 方向 | RK 端口 | RK ball |
|---|---|---|---|---|
| Q0_RXDN0/DP0 | B2/A2 | ← | PORT0_TX0N/P | D33/D32 |
| Q0_RXDN1/DP1 | B4/A4 | ← | PORT0_TX1N/P | C34/C33 |
| Q0_RXDN2/DP2 | B6/A6 | ← | PORT1_TX2N/P | E34/E33 |
| Q0_RXDN3/DP3 | B8/A8 | ← | PORT1_TX3N/P | D35/D34 |
| Q0_TXDN0/DP0 | D1/C1 | → | PORT0_RX0N/P | G34/G33 |
| Q0_TXDN1/DP1 | D3/C3 | → | PORT0_RX1N/P | F33/F32 |
| Q0_TXDN2/DP2 | D5/C5 | → | PORT1_RX2N/P | J34/J33 |
| Q0_TXDN3/DP3 | D7/C7 | → | PORT1_RX3N/P | K34/K33 |

参考时钟：Q0_REFCLK0（F10/G10）→ p19 时钟 buffer（PCIE30_REFCLK_SLOT）→ RK PCIE30_REFCLK_IN；
Q0_CAL_RES@H9 接 3.01K 校准电阻；Q0_REFCLK1 悬空。

**MIPI CSI（FPGA TX → RK RX，2 通道 ×10）**

| FPGA 通道 | ball 区 | RK CSI0 | RK CSI1 |
|---|---|---|---|
| CLK0 P/N | AH6/AG6（CSI0）、AL32/AL31（CSI1） | MIPI_CSI0_CLK0P/N @AJ33/AJ34 | MIPI_CSI1_CLK0P/N @AJ31/AJ32 |
| D0 P/N | AH2/AH1；AJ34/AJ33 | AG33/AG34 | AG31/AG32 |
| D1 P/N | AG3/AG2；AK33/AK32 | AH33/AH34 | AH31/AH32 |
| D2 P/N | AG4/AF4；AJ31/AK31 | AK33/AK34 | AK31/AK32 |
| D3 P/N | AH5/AH4；AL34/AL33 | AL33/AL34 | AL31/AL32 |

**GPIO / SPI / IIC（10）**

| FPGA pin | ball | 信号 | RK pin | RK ball |
|---|---|---|---|---|
| GPIOB_P_47 | H1 | RK3588_GPIO01 | GPIO2_B4_u | AB31 |
| GPIOB_N_47 | H2 | RK3588_GPIO02 | GPIO2_B5_u | AB30 |
| GPIOB_P_48 | J2 | RK3588_GPIO03 | GPIO2_C3_d | AD30 |
| GPIOB_N_48 | J3 | RK3588_GPIO04 | GPIO2_C4_d | AC30 |
| GPIOB_P_49 | L3 | RK3588_SPI_CLK | GPIO4_C6_d | AF33 |
| GPIOB_N_49 | K3 | RK3588_SPI_MISO | GPIO4_C4_d | AB34 |
| GPIOB_P_50 | G1 | RK3588_SPI_MOSI | GPIO4_C5_d | AB33 |
| GPIOB_N_50 | G2 | RK3588_SPI_CS | GPIO4_C3_d | AF34 |
| GPIOB_P_51 | J4 | RK3588_IIC_SCL | GPIO1_C1_z | G27 |
| GPIOB_N_51 | H4 | RK3588_IIC_SDA | GPIO1_C0_z | G29 |

### 3.3 FPGA→EVM 接口（经 BTB，EVM 侧网名前缀 TJ_，全量 164 网见 func CSV）

| 接口 | 信号数 | EVM 侧器件 |
|------|--------|-----------|
| 第二以太网 RGMII（TJ_PHY0_*） | 16 | RTL8211FI PHY + RJ45 |
| EtherCAT 从站（TJ_LAN9252_*：D0-D15 并行总线 + CS/A1-A4/SYNC/IRQ + TX/RX 差分×2） | 25 | LAN9252 |
| SDI 视频 ×2（TX/RX 差分 + I2C） | 12 | SDI 均衡/驱动 + BNC |
| SFP 光口 ×2（TX/RX + SCL/SDA + MOD_ABS/TX_DIS） | 16 | SFP 笼座 |
| MIPI1_RX / MIPI2_RX / MIPI2_TX（HS 对） | 60 | 摄像头连接器 |
| UART×3 + FT 调试串口 | 8 | MAX3232 / FT232 |
| JTAG（TCK/TMS/TDI/TDO/CRESET）+ RISC-V JTAG | 9 | FT JTAG 桥 |
| 用户按键×4、拨码开关×2 | 6 | SKRPAME010 |
| QSE2/3/4 sideband GPIO | 15 | 高速扩展 |
| 时钟组（TJ_GPIO L23/L25/L46/L52/R95/R97 ← EVM 晶振） | 6 | EVM 25M/100M 晶振组 |

### 3.4 配置链（SOM 本地）

| 信号 | FPGA pin | ball | 去向 |
|------|----------|------|------|
| FPGA_CDI0-3 | GPIOB_N_40/P_38/N_39/P_40 | T1/P3/N4/R1 | 配置 FLASH（active-serial x4） |
| FPGA_SS | GPIOB_N_38_SSL_N | R3 | FLASH 片选 |
| FPGA_CCK | GPIOB_P_39_CCK_PLLIN0 | N5 | 配置时钟 |
| CFG_DONE | CDONE | F2 | 配置完成（上拉） |
| CRESET_N | CRESET_N | G4 | 复位 |
| TMS/TCK/TDI/TDO | — | JTAG | EVM FT 桥（经 BTB） |
| NSTATUS | GPIOB_P_19_NSTATUS | — | 配置状态 |
| CBSEL0/1 | GPIOB_N/P_23 | — | 启动模式选择 |

## 4. RK3588 管脚映射

全量见 `jackets/stage0/func-pinout-rk3588.csv`（372 pin，已与 Rockchip RK3588 Datasheet V2.2
逐球对账 98.9% 一致）。

| 域 | 数量 | 去向 |
|----|------|------|
| FPGA 直连（GMAC0 12 + CSI0/1 20 + PCIE30 16 + GPIO/SPI/IIC 10） | 58 | TJ375（见上表） |
| eMMC（EMMC_D0-D7/CMD/CLKOUT/STROBE/RSTN） | 14 | SOM eMMC（Y33/W33/V32/AA33/Y32/AA32/W32/V33/W34/V34/Y34/AA34） |
| BTB→EVM（RK_GMAC1/USB3×2/TYPEC0/HDMI TX×2/HDMI RX/PCIE 插槽/SDMMC/UART DBG/I2S/SARADC…） | 184 | EVM 外设 |
| 电源/时钟（VCC/VDD/OSC/PMIC） | 50 | RK806-1 + 24M 晶振 |
| SOM 本地（KEY/BOOT/REXT/SARADC 选择） | 46 | 板内电阻/按键 |

RK GMAC1 千兆（RK_GMAC1_*_3V3 16 网）经 BTB 至 EVM 第二颗 RTL8211FI PHY。

## 5. 目录

```
ws-e2/
├── ws-e2.md                 (本文件)
├── pinout/ws-e2-module.csv  核心模组 pinout（ball 视角，302 唯一 ball）
└── carriers/rk3588j-evm/    底板（见 rk3588j-evm.md）
```

原始资料与提取工具在工作区根：`SOM板原理图/`、`EVM板原理图/`、`_device/`（ballmap/提取器/
验证报告）、`tools/`。验证结论：FPGA 用法 5 PASS/2 WARN；RK vs Rockchip datasheet 98.9%。
