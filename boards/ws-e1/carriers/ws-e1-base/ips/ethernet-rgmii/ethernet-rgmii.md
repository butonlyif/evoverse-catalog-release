---
ws_manifest_version: 1
kind: ip
id: ethernet-rgmii
display_name: Ethernet RGMII (TSE MAC)
version: 1.0.0
board: ws-e1
carrier: ws-e1-base
maintainer: evoverse
license: proprietary
description: Tri-Mode Ethernet MAC (TSE) with RGMII PHY interface, including packet generator and loopback logic.
---

[English](ethernet-rgmii.en.md) | 中文

# Ethernet RGMII (TSE MAC)

## 来源 Demo
`demos/ethernet-tse-udp-test/`（原 `TJ180A484_TSE/`）

## 硬核 IP 配置
- **efx_tsemac** (Efinix Ethernet TSE MAC)
  - vendor: efinixinc.com, library: ethernet, name: efx_tsemac, version: 4.3
  - Efinity IP 生成工具版本: 2022.2.322
  - 配置: TX/RX FIFO 使能 (depth 2048), AXIS 数据宽度 8-bit, PHY 接口模式 0
  - settings.json 位于 rtl/settings.json

## RTL 文件
| 文件 | 说明 |
|------|------|
| temac_ex.v | 顶层模块 - TEMAC 示例设计，集成 TSE MAC + RGMII PHY 接口 |
| test_tse.v | Efinity TSE MAC IP 核封装 |
| test_tse_tmpl.v | TSE MAC IP 模板文件 |
| test_tse_define.vh | TSE MAC 宏定义 |
| header.v | 全局头文件包含 |
| DaulClkFifo.v | 双时钟 FIFO，用于跨时钟域数据缓冲 |
| apb3_2_axi4_lite.v | APB3 到 AXI4-Lite 桥接器 |
| axi4_st_mux.v | AXI4-Stream 多路复用器 |
| mac_pat_gen.v | MAC 层数据包生成器 |
| udp_pat_gen.v | UDP 数据包生成器 |
| mac_rx2tx.v | MAC 接收到发送环回逻辑 |
| rgmii_2_rmii.v | RGMII 到 RMII 转换 |
| reg_apb3.v | APB3 寄存器接口 |

## 约束
| 文件 | 说明 |
|------|------|
| temac_ex.peri.xml | 外设引脚约束 (Interface Designer) |
| timing_Ti60.sdc | 时序约束文件 |

## 接口
- **RGMII PHY**: rgmii_txd[3:0], rgmii_tx_ctl, rgmii_txc, rgmii_rxd[3:0], rgmii_rx_ctl, rgmii_rxc
- **PHY 控制**: phy_rstn, phy_mdc, phy_mdio
- **时钟**: clk (系统时钟), clk_125m (RGMII 125MHz 参考时钟)
- **JTAG**: jtag_inst1_* (硬核 JTAG 调试接口)
- **复位**: pll_rstn, pll_0_locked

## 应用场景
用于 ws-e1-base 底板上的千兆以太网接口，通过 RGMII 协议连接外部 PHY 芯片（如 RTL8211），实现网络通信功能。支持 MAC/UDP 数据包生成与环回测试。
