English | [中文](architecture.md)

# Architecture

## Module Hierarchy

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

## Clock Tree (peri.xml PLL)

| Clock | Source | Purpose |
|---|---|---|
| 50 MHz | GPIOL_26 external | `pll_sys` reference |
| `sd_clk_100m` | PLL_TL0 CLKOUT0 | SD base clock (bus = /2 = 50 MHz) |
| `sys_clk_125m` | PLL_TL0 CLKOUT1 | Entire SOC + both DDR AXI ports |
| `i_clk_27m` / `pixel_clk` / `esc_clk` / `mipi_refclk_25m` | MIPI PLL group | CSI-2 TX / DPHY (720p60 pixel rate) |
| `pll_csi_locked` / `dphy_tx2_WORD_CLKOUT_HS` | — | CSI/DPHY lock and word-clock feedback |

## Data Path

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

### DDR Memory Map

| Address | Content |
|---|---|
| `0x00000000 - 0x001FFFFF` | Firmware (RAM image) |
| `0x01000000` | Frame-retention test area A/B (used by frame_path_test) |
| `0x02000000` | 8 × 1.8 MB pattern stream array (1843200 B = 3600 blocks per pattern) |

## Key Design Points

### DDR port1 Arbitration (OWN_P1)

Both the SOC's `io_ddrA` and `video_reader` act as masters of DDR AXI port1. `top_soc_sd.v` uses
the `video_reader` CTRL.`OWN_P1` bit as the AR/R channel mux:

- `OWN_P1=0` (default): port1 belongs to the SOC; the AR/R path is bit-identical to the official OOB project (regression-safe state);
- `OWN_P1=1`: port1 belongs to video_reader; the SOC's read path to port1 is given up, and the CPU uses port0 only.

During testing, the firmware first performs a verification read with `ddr_port1_reader` under `OWN_P1=0` ([5/5]);
only after everything passes is `OWN_P1=1` set to hand port1 to video_reader to start streaming (stage [6]).

### Burst Parameters (board-verified values)

- `ARSIZE_1 = 3'b110` (64 B burst); in the netlist bits [2:1] tie to VCC and bit [0] ties to GND;
- `ARLEN_1[7:1]` is driven dynamically by LUTs (video_reader issues bursts per row demand), not a constant.

### Project Conventions (consolidated from debugging lessons)

1. **Declare the width of every inter-module connection explicitly** — historically `top_soc_sd.v` once had `rdr_*` connections
   missing wire declarations, so they were truncated to 1-bit implicit nets, silently corrupting data on the port1 read path
   (fixed and board-verified).
2. **Device-name attributes must not be changed**: the XML `efx:device`, peri.xml `device_def`,
   package_settings `Device`, and openocd `DEVICE=` are all device-bound attributes.
3. Keep exactly one project XML in the project directory (avoid stale backup XMLs competing for the design file list).
