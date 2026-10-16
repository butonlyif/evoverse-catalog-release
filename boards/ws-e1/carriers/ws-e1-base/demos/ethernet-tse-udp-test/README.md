[English](README.en.md) | 中文
# ethernet-tse-udp-test — 千兆以太网 TSE MAC 测试帧发生 / 环回

> 原目录：`TJ180A484_TSE/TSE/`

## 1. 概述

基于 Titanium **TSE（Tri-Speed Ethernet）硬核 MAC** + Sapphire RISC-V 软核的
以太网测试平台：

- **测试帧发生**：RISC-V 经 APB3 配置参数后，FPGA 生成可配置的 **UDP 测试帧**
  （目的/源 MAC、IP、端口、包长、IPG、包数均可配）或裸 MAC 帧，经 RGMII PHY
  发出到网口，PC 用 Wireshark 抓包验证；
- **环回模式**：AXI4-Stream mux 切换后把 RX 流跨时钟域转发回 TX，对端发什么
  回什么，用于链路连通性测试。

本 demo **不使用 DDR**，是 TSE 硬核 + RGMII + MDIO 集成的直接参考。

- 器件：Titanium **TJ180A484S**（C4）
- 工具链：Efinity 2025.1.110.4.9（pass，bitstream 已生成过）
- 顶层模块：`temac_ex`（[temac_ex.v](temac_ex.v)）

## 2. 硬件资源占用

| 资源 | 配置 |
| --- | --- |
| **TSE MAC 硬核**（`test_tse`，efx_ipmgr 生成，IP v4.3） | 上行 AXI4-Stream RX/TX（8-bit）+ AXI4-Lite CSR + MDIO；下行 RGMII（DDIO 双沿 `_HI/_LO`）；`tx_mac_aclk=125MHz` |
| `pll_0`（PLL_TL0） | 50MHz → 50/125/125(90°，RGMII TXC)/25MHz 四路输出 |
| 软核 | Sapphire SoC（APB3 主）：`reg_apb3` 自定义 CSR + `apb3_2_axi4_lite` 桥访问 MAC CSR |
| RGMII GPIO（1.8V，DDIO） | rxc=GPIOL_29（+15delay）、rxd[3:0]、rx_ctl、txd[3:0]、tx_ctl、txc；MDIO：mdc/mdio=GPIOR_35 |
| UART | rxd/txd=GPIOL_01/02（3.3V） |

板级外设：**RTL8211FD 千兆 PHY**（RGMII + MDIO）、RJ45 网口、SW6 拨码（直接
复位 PHY：`phy_rstn = sw6`）、UART。

## 3. 目录结构

```
ethernet-tse-udp-test/
├── temac_ex.xml / temac_ex.peri.xml   # Efinity 工程（打开这个）
├── timing_Ti60.sdc                    # 时序约束（文件名沿用 Ti60 参考设计，实际约束 TJ180A484S 有效）
├── temac_ex.v                         # 顶层：mux/复位/模块例化
├── test_tse.v + test_tse_define.vh    # TSE 硬核 MAC wrapper
├── udp_pat_gen.v                      # UDP 测试帧发生器（参数全可配）
├── mac_pat_gen.v                      # 裸 MAC 帧发生器
├── mac_rx2tx.v                        # RX→TX 跨时钟域环回
├── axi4_st_mux.v                      # AXI4-Stream 2:1 复用器（两级级联）
├── reg_apb3.v                         # APB3 自定义 CSR（mux/pattern 控制，偏移 0x208~0x230）
├── apb3_2_axi4_lite.v                 # APB3→AXI4-Lite 桥（访问 MAC CSR）
├── rgmii_2_rmii.v                     # 【未实例化】备用模块
├── DaulClkFifo.v                      # 【未实例化】备用模块（Daul=Dual 拼写错误，历史遗留）
├── header.v                           # 仅 1 行：SOFT_TAP 宏开关
├── ip/
│   ├── sapphire/                      # Sapphire SoC IP（工程引用）
│   └── test_tse/                      # TSE 硬核 IP（工程引用）
└── embedded_sw/sapphire/
    └── software/standalone/tseDemo/   # ★ RISC-V 测试程序
        ├── main.c                     # CSR 配置 pattern 参数
        └── rtl8211fd_drv.c            # RTL8211FD PHY 驱动（#ifdef PHY8211 切换）
```

## 4. 工作原理

```
发送路径（两级 mux）：
  udp_pat_gen / mac_pat_gen ──(pat_mux_select)──▶ axi4_st_mux ──(axi4_st_mux_select)──▶ TSE MAC ──RGMII──▶ PHY ──▶ 网口
  mac_rx2tx（RX 环回）───────────────▲

控制路径：
  Sapphire(APB3) ──▶ reg_apb3（mux/pattern CSR） 
                 ──▶ apb3_2_axi4_lite ──▶ TSE MAC s_axi（MAC 自身 CSR，aclk=50MHz）
```

- `pat_mux_select`：0=UDP 帧、1=裸 MAC 帧；
- `axi4_st_mux_select`：0=测试帧、1=环回；
- SW6 拨码直接拉 `phy_rstn`，可现场复位 PHY 观察链路重建。

## 5. 运行与验证

1. Efinity 打开 `temac_ex.xml` 编译烧录；
2. 网口接 PC；运行 `tseDemo` 程序（UART 交互）配置帧参数并启动发送；
3. **Wireshark** 抓到指定参数的 UDP/MAC 测试帧即通过；
4. 环回验证：置 `axi4_st_mux_select=1`，PC 发包观察原样返回；
5. UART 控制台查看状态打印。

## 6. 集成到客户系统的要点

- **TSE 硬核配置以 `temac_ex.peri.xml` 为准**：RGMII 全部 1.8V DDIO、rxc 内部
  +15delay、TXC 用 125MHz 90° 移相时钟——这是 RGMII 时序的标准做法，移植时保持；
- `test_tse.v` 是 IP 生成物，改配置应在 Efinity IP 界面重生成而非手改；
- `reg_apb3`（CSR 偏移 TSEMAC_CSR+0x208~0x230）与两个 mux 构成最小可控发送
  框架，客户业务数据源替换 `udp_pat_gen` 位置即可；
- MDIO 读写 PHY 寄存器的驱动在软件侧 `rtl8211fd_drv.c`，换 PHY 改这个文件；
- 板上 PHY 为 RTL8211FD；若客户原理图换 PHY，注意 RGMII delay 模式（PHY 侧
  内部延迟 vs FPGA 侧 +15delay）需配套调整。

## 7. 已知问题与注意事项

- `rgmii_2_rmii.v`、`DaulClkFifo.v` 未被实例化，仍在工程 design_file 列表中
  参与综合（会被剪除，不影响功能，属历史遗留）；
- SDC 文件名 `timing_Ti60.sdc` 来自 Ti60 参考设计，内容对 TJ180A484S 有效，
  命名属误导性遗留；
- 本次整理已删除 `ip/` 下内嵌的 T120F324/Ti180M484/Ti60F225 devkit 参考工程
  副本，核心 IP 文件（settings.json、tmpl、顶层封装）保留，工程打开不受影响。
