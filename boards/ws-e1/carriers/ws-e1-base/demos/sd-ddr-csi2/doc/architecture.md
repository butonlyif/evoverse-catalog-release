[English](architecture.en.md) | 中文

# 架构说明

## 模块层次

```
top_demo                          (rtl/top_demo.v, 引脚来自 peri.xml)
├── reset_ctrl                    复位同步
├── top_soc_sd                    (rtl/top_soc_sd.v)
│   ├── riscv_soc                 Sapphire RISC-V SOC (IP, DDR AXI master 1 + APB x4 + userInt B)
│   ├── apb3_2_axi4_lite_sdhost   APB3 → AXI4-Lite 桥 (IP)
│   │   └── sdhost_ctrl           SD 主机控制器 SDIO + ADMA (IP)
│   └── [DDR port1 AR/R 仲裁 mux] OWN_P1 选择 video_reader 或 SOC
├── video_reader                  DDR port1 视频流 master
├── shape_video_data              异步 FIFO + 行/帧对齐
└── mipi_tx_top                   CSI-2 TX 打包发送
    └── mipi_csi_tx_2p5g          Efinity CSI-2 TX IP → DPHY TX2
```

## 时钟树（peri.xml PLL）

| 时钟 | 来源 | 用途 |
|---|---|---|
| 50 MHz | GPIOL_26 外部 | `pll_sys` 参考 |
| `sd_clk_100m` | PLL_TL0 CLKOUT0 | SD 基时钟（总线 = /2 = 50 MHz） |
| `sys_clk_125m` | PLL_TL0 CLKOUT1 | 整个 SOC + 两个 DDR AXI 口 |
| `i_clk_27m` / `pixel_clk` / `esc_clk` / `mipi_refclk_25m` | MIPI PLL 组 | CSI-2 TX / DPHY（720p60 像素率） |
| `pll_csi_locked` / `dphy_tx2_WORD_CLKOUT_HS` | — | CSI/DPHY 锁定与字时钟反馈 |

## 数据通路

```
                         ┌──────────────── SD 卡 ────────────────┐
                         │  8×720p 图案 + 签名块 (卡尾, ~14 MB)    │
                         └──────────────┬────────────────────────┘
                                        │ SDIO 4-bit @50 MHz
                                 ┌──────▼──────┐
                                 │ sdhost_ctrl │  ADMA
                                 └──────┬──────┘
                          APB3→AXI4-Lite │ 寄存器
                                 ┌──────▼──────┐
        riscv_soc (CPU) ────────►│    DDR      │◄──────── ddr_port1_reader
      io_ddrA / 固件<0x200000    │  (双口 AXI) │          (调试校验读, OWN_P1=0)
                                 └──┬───────┬──┘
                    port0 读写       │       │ port1 读 (ARSIZE=64B)
              0x01000000 帧 A/B     │  ┌────▼─────────────┐
              0x02000000 8×图案 ────┘  │ OWN_P1 mux       │
                                       │  0: SOC / 1: VR  │
                                       └────┬─────────────┘
                                   ┌────────▼────────┐
                                   │ video_reader    │  AXI 读 master, 8 图案
                                   └────────┬────────┘  轮换 180 帧/图案
                                   ┌────────▼────────┐
                                   │ shape_video_data│  异步 FIFO, 行/帧对齐
                                   └────────┬────────┘
                                   ┌────────▼────────┐
                                   │ mipi_tx_top     │  YUV422 → CSI-2 包
                                   └────────┬────────┘
                                   ┌────────▼────────┐
                                   │ CSI-2 TX IP     │  2 lane D-PHY TX2
                                   └────────┬────────┘
                                            ▼
                                     显示 / 采集端 (720p60)
```

### DDR 空间布局

| 地址 | 内容 |
|---|---|
| `0x00000000 - 0x001FFFFF` | 固件（RAM 镜像） |
| `0x01000000` | 帧保留测试区 A/B（frame_path_test 用） |
| `0x02000000` | 8×1.8 MB 图案流数组（每图案 1843200 B = 3600 块） |

## 关键设计点

### DDR port1 仲裁（OWN_P1）

SOC 的 `io_ddrA` 与 `video_reader` 都要当 DDR AXI port1 的 master。`top_soc_sd.v` 用
`video_reader CTRL.OWN_P1` 位做 AR/R 通道 mux：

- `OWN_P1=0`（默认）：port1 归 SOC，AR/R 通路与官方 OOB 工程逐位一致（回归安全态）；
- `OWN_P1=1`：port1 归 video_reader，SOC 读 port1 的通路被让出，此时 CPU 只用 port0。

测试时固件先在 `OWN_P1=0` 下用 `ddr_port1_reader` 做校验读（[5/5]），全部通过后再置
`OWN_P1=1` 交给 video_reader 起流（阶段 [6]）。

### 突发参数（板上验证值）

- `ARSIZE_1 = 3'b110`（64 B 突发），网表中位 [2:1] 接 VCC、位 [0] 接 GND；
- `ARLEN_1[7:1]` 由 LUT 动态驱动（video_reader 按行需求发突发），非常量。

### 工程约定（从调试教训固化）

1. **所有跨模块连线显式声明位宽**——历史上 `top_soc_sd.v` 曾因 `rdr_*` 连线漏 wire
   声明被截成 1-bit implicit net，导致 port1 读通路静默数据错（已修复并板上验证）。
2. **器件型号属性不可改**：XML `efx:device`、peri.xml `device_def`、
   package_settings `Device`、openocd `DEVICE=` 均为器件绑定属性。
3. 工程目录下只保留一个工程 XML（避免历史备份 XML 抢占设计文件清单）。
