English | [中文](README.md)
# mipi-loopback-test — MIPI CSI-2 On-Chip Self-Loopback Link Test (TX→loopback→RX verification)

> Original directory: `TJ180MIPI_loopback/Ti180MIPI/` (mixed TJ/Ti casing corrected)

## 1. Overview

A **MIPI CSI-2 TX→RX self-loopback link** is built inside a single FPGA: an on-chip test image
(default **4K60 RAW8**) → `hard_csi_tx` packing → **DPHY TX hard IP** → MIPI pins → (board
routing / external short loopback cable) → MIPI pins → **DPHY RX hard IP** → `hard_csi_rx`
unpacking → on-chip pixel-by-pixel comparison, with **LEDs directly indicating PASS/FAIL**.

This is the **only project among the 9 demos that uses both the DPHY TX and RX hard IPs**
simultaneously; it completes link-level verification of the MIPI hard IP and IPs without any
external equipment, and is well suited as the baseline project for MIPI hard-IP bring-up and
for comparing TX/RX IP configurations.

- Device: Titanium **TJ180A484S** (C4)
- Toolchain: Efinity 2025.2.288.4.15 (pass, bitstream generated)
- Top module: `Top` ([Top.v](Top.v), 1447 lines, **GBK-encoded Chinese comments**; the file
  header records a 2019-01~2020-02 modification history; ported from a Xilinx VIO/ILA-style
  project)

## 2. Hardware Resource Usage

| Resource | Configuration |
| --- | --- |
| **DPHY TX** (`mipi_dphy_tx_inst1`, MIPI_TX0) | 2.0Gbps/lane, 2 lane (MIPI_Parameter.v parameters) |
| **DPHY RX** (`mipi_dphy_rx_inst2`) | matching receive configuration |
| `hard_csi_tx` / `hard_csi_rx` IP | CSI-2 pack/unpack (AXI-Lite status interface) |
| `pll_inst1` | sourced from pll_inst2_CLKOUT2 50MHz → clk0, **pixel_clk 200MHz**, mipi_clk 100MHz |
| `pll_inst2` | → **cfg_clk 100MHz, esc_clk 20MHz**, CLKOUT2 50MHz, clk_25m |
| GPIO | CLK_50M (onboard 50MHz), MIPI_REF_CLK, 4×LED, 1 pushbutton (start_transfer_n) |
| Debugger | disabled (originally VIO MipiTx/MipiRx groups + ILA; must be re-enabled manually in the GUI) |

No soft core, no DDR.

## 3. Directory Structure

```
mipi-loopback-test/
├── Ti180MIPI.xml / .peri.xml      # Efinity 工程（打开这个）
├── Ti180_mipi_io.isf              # Interface Designer IO 约束文件
├── Top.v                          # ★ 顶层 Top：图案生成→TX→环回→RX→比对统计
├── top.sdc                        # 时序约束（pixel_clk 200M / mipi 100M / esc 20M…）
├── debug_profile.json / debug_top.v   # Debugger VIO/ILA 配置与插桩顶层（已禁用，未参与编译）
├── ip/
│   ├── hard_csi_tx/               # CSI-2 TX IP（settings.json/_define/_tmpl）
│   └── hard_csi_rx/               # CSI-2 RX IP
└── source/
    ├── reset.v                    # 复位同步（被 Top.v 实例化 ×3）
    ├── MIPI_Parameter.v           # ★ 全局参数（被 include：PHY 速率/像素时钟等）
    ├── MIPI_RAW/                  # 2019-2020 旧测试逻辑（在工程列表但未被实例化）
    │   ├── MIPITest.v / MIPITxProcess.v / MipiRxProcess.v / MipiPixelData.v / PRBS9.v
    │   └── MIPI_Parameter.v       # ⚠ 与上级目录重复的副本
    └── efx_csi2_tx.sv / efx_csi2_rx.sv / efx_csi_tx_define.vh / efx_ram_10k.v / mipi.sdc
                                   # 旧版 IP 封装残留（未入工程）
```

## 4. Working Principle

```
Top.v 片内测试图生成（MipiTx_DATA，RAW8，分辨率/帧率由参数固定）
  → hard_csi_tx（CSI-2 打包，AXI-Lite 只读状态）
  → mipi_dphy_tx_inst1 → MIPI 引脚 →（板级回环/外接短线）→ RX 引脚
  → mipi_dphy_rx_inst2 → hard_csi_rx
  → MipiRx_DATA/VALID/word_count/datatype → Top.v 比对统计
      （RxErrCnt、每秒 TxDataRate 吞吐、MiPiRxRight/MipiRxError 判决）
```

- Default parameters (the original VIO initial values recorded in debug_profile.json):
  `ConfigTxVertPixelNumber=2160`, `ConfigTxHoriPixelNumber=3840`, `ConfigTxFrameRate=60` —
  4K60 RAW8;
- The `start_transfer_n` pushbutton starts one transfer; lanes/VC/resolution/reset and other
  parameters are fixed by Top.v/MIPI_Parameter.v (online modification requires re-enabling the
  Debugger in the GUI).

## 5. Run and Verify

| LED | Meaning |
| --- | --- |
| led[0] | heartbeat (toggled by count_led[21] division) |
| **led[1]** | **FAIL** (r_fail, RX comparison error) |
| **led[2]** | **PASS** (r_pass, RX verification passed) |
| led[3] | transfer activity indicator (flash_cnt[12]) |

1. Program the bitstream; press the `start_transfer_n` pushbutton to start;
2. **led[2] lit and led[1] off = self-loopback link PASS**;
3. For details, re-enable the Efinity Debugger in the GUI: adjust parameters with VIO (e.g.,
   lower the resolution to troubleshoot), capture TX/RX data and comparison results with ILA,
   and watch the TxDataRate throughput statistics.

## 6. Integration Notes for Customer Systems

- **TX-side reuse** (for image transmission): take the "pattern generation → hard_csi_tx →
  DPHY TX" section of Top.v plus the `ip/hard_csi_tx` configuration; the AXI-Lite read-only
  status polling FSM can be taken as-is;
- **RX-side reuse** (for camera reception): take the "DPHY RX → hard_csi_rx → comparison/
  statistics" section and replace the comparator with the customer's processing logic;
  the word_count/datatype checks are key signals for link debugging;
- For the dual-hard-IP peri configuration (TX0+RX coexisting), refer to `Ti180MIPI.peri.xml`,
  including the cal_clk and esc_clk allocation; the full bidirectional TX/RX IO delay
  constraints in the SDC are a key reference for timing closure;
- Global rate parameters are centralized in `source/MIPI_Parameter.v` (PHY 2.0G, pixel
  200MHz, esc 20MHz); when changing the rate, update three places in sync: the parameter
  file, the peri data_rate, and the SDC clock periods;
- **Watch the encoding**: Top.v and MIPI_Parameter.v use GBK Chinese comments and appear as
  mojibake in UTF-8 editors; when modifying these files, keep the original encoding or convert
  everything to UTF-8 (consistently across the whole project).

## 7. Known Issues and Notes

- `source/MIPI_Parameter.v` and `source/MIPI_RAW/MIPI_Parameter.v` duplicate each other; the
  version actually included is the one under `source/MIPI_RAW/` (per the project file list);
- The 5 MIPI_RAW modules in the project list (MIPITest/MIPITxProcess/MipiRxProcess/
  MipiPixelData/PRBS9) are **not instantiated** in Top.v (the logic was inlined); they are
  dead code;
- The synthesis code retains `#TCo_C` simulation delay statements (synthesizable, but a
  simulation-style leftover);
- This reorganization removed `Ti180MIPI.peri.pre_import.xml` (pre-import backup) and
  `debug_TEMPLATE.v/.vhd` (template leftovers).
