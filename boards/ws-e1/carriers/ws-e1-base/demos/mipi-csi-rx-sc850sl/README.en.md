English | [中文](README.md)
# mipi-csi-rx-sc850sl — MIPI CSI-2 Camera Reception (SC850SL, 8MP)

> Original directory: `MIPI_RX_sc850/MIPI_RX_sc535/` (the outer name sc850 and the inner name
> sc535 were mixed; this reorganization unified the name to SC850SL, the sensor model actually
> initialized)

## 1. Overview

A **MIPI CSI-2 camera reception link** verification project: after power-up the FPGA
automatically sends a 200-entry register initialization sequence to the SmartSens camera
module via I2C; then the DPHY RX (4 lane / 2.0Gbps per lane) receives the camera's CSI-2
stream, and the `hard_csi_rx` IP unpacks it into a pixel stream. The output side connects only
to internal row/pixel counters; the link status shows up in the CSI RX status registers,
datatype/word_count, pcnt/lcnt, and other internal signals. **This demo has no external
output such as UART/display; you must manually re-enable the Debugger in the Efinity GUI and
observe online** (see §5 for details).

> Naming clarification: modules/directories in the project are named `sc535` (e.g.,
> `sc535_init/`, `sc535_i2c_init.v`), but the register table actually loaded by the top level
> is `sc535_init/sc850sl_init.mem` (200 entries, 16bit address + 8bit data, I2C 8-bit write
> address 0x60) — **what is actually initialized is the SC850SL**. The SC535 and SC850SL are
> from the same vendor (SmartSens) with the same 0x60 write address; code reuse caused the
> mixed naming. Documentation and directory names follow the SC850SL.

- Device: Titanium **TJ180A484S** (C4)
- Toolchain: Efinity 2025.2.288.3.8 (pass, bitstream generated, passive configuration mode)
- Top module: `top` (file [top_2_5g.sv](top_2_5g.sv), comments keep 1080p example parameters)

## 2. Hardware Resource Usage

| Resource | Configuration |
| --- | --- |
| **MIPI DPHY RX** (`mipi_dphy_rx_inst2`, MIPI_RX0) | **2000 Mbps/lane, 4 lane**, data_width=16, cal_clk 100MHz |
| `hard_csi_rx` IP (efx_csi2_rx_top v5.5.1) | CSI-2 unpack/align/FIFO, AXI4-Lite register interface |
| `i2c_master` IP (efx_i2c_controller v5.0) | sensor register configuration channel (16bit register address width) |
| `pll_inst1` (PLL_BL1) | 50MHz → clk0 / pixel_clk / mipi_clk |
| `pll_inst2` (PLL_TL0) | 50MHz×2 → cfg_clk 100M / esc_clk 20M / clk_50M / **clk_24m (sensor reference clock output @GPIOL_46)** |
| GPIO | PLL_50M @GPIOL_26, scl @GPIOL_43, sda @GPIOL_02, trig_o @GPIOL_07, xshutdn @GPIOL_01 (tied vcc) |

No soft core, no DDR. Board-level peripheral: SmartSens SC850SL MIPI camera module (J5 CSI-2
connector).

## 3. Directory Structure

```
mipi-csi-rx-sc850sl/
├── Ti180_mipi.xml / .peri.xml / .sdc   # Efinity 工程（打开这个；工程名沿用 Ti180M484 devkit）
├── top_2_5g.sv                  # ★ 顶层 top：DPHY RX → hard_csi_rx → 计数器 + 调试状态机
├── reset.v / shift_reg.v        # 复位/移位寄存器（shift_reg 未被 top 实例化）
├── sc535_init/                  # sensor I2C 初始化
│   ├── smartsens_init.v         # 上电时序（6ms 复位→2ms→I2C 配置，含 XCLK 逻辑）
│   ├── sc535_i2c_init.v         # FSM：从 ROM 顺序写 200 条寄存器（写地址 0x60）
│   ├── single_port_rom.v
│   └── sc850sl_init.mem         # ★ 实际加载的 SC850SL 寄存器表
├── IP/                          # Efinity IP 目录（注意大写 IP，见"已知问题"）
│   ├── hard_csi_rx/             # CSI-2 RX IP（含 settings.json/_define.vh/_tmpl）
│   └── i2c_master/              # I2C 控制器 IP
├── data_unpack.v / datatype_gen.v / dual_clock_fifo.v / simple_dual_port_ram.v
├── efx_csi2_tx_top.sv / vga_gen.v / pattern_gen.v / pattern_gen2.v / lfsr.v
│        # ↑ 以上 9 个为 devkit 示例残留（TX/VGA/图卡路径），未被本工程引用
└── hard_csi_rx.sv / hard_csi_rx_define.vh   # 与 IP/ 下重复的副本（未引用）
```

## 4. Working Principle

```
上电：smartsens_init（6ms 复位时序）→ sc535_i2c_init FSM 逐条写 ROM
      （sc850sl_init.mem）→ i2c_master → sensor（0x60）
数据：sensor CSI-2 4lane@2G → mipi_dphy_rx_inst2（PPI）→ hard_csi_rx
      → pixel_data/hs/vs → pcnt/lcnt 行/像素计数器
触发：trig_o 产生 30fps 触发脉冲；clk_24m 输出 sensor 参考时钟
调试：r_rx_dbg_fsm_1P 在 mipi_clk 域循环 AXI-Lite 读 hard_csi_rx 寄存器
      0x00–0x28 存入 r_rx_dbg_reg_1P[0:15]（供 GUI Debugger 在线观察）
```

## 5. Run and Verify

This demo has **no UART, no display, no external output of any kind**; link status can only be
observed through internal signals. The Debugger is disabled in the current project, so
verification requires manually re-enabling the Debugger wizard in the Efinity GUI, then:

1. Program the bitstream (passive mode) and connect the camera module;
2. Re-enable and open the Efinity Debugger and observe:
   - `init_done` (I2C initialization complete);
   - the hard_csi_rx status registers (RX FSM state, whether **datatype / word_count** matches
     the sensor configuration, e.g., 0x2B/RAW10 or the configured format);
   - whether the `pcnt/lcnt` row/pixel counters roll according to the resolution.
3. Counters rolling steadily means the CSI-2 link is receiving images correctly.

> If the customer wants Debugger-free automatic verification, follow mipi-loopback-test by
> adding a comparator on the output side with LED/GPIO PASS/FAIL indication.

## 6. Integration Notes for Customer Systems

- **Changing the sensor model**: regenerate the register table with the vendor's tool and
  replace `sc850sl_init.mem` (format: each line 24bit = 16bit address + 8bit data); the FSM in
  `sc535_i2c_init.v` and the I2C address parameters need no change (same-vendor compatible);
  for a sensor from a different vendor, change the write address and the smartsens_init power
  sequencing accordingly;
- **DPHY rate**: adjust `data_rate=2000` (Mbps/lane) in peri.xml to the sensor output rate,
  and change the corresponding byte clk (156.25MHz) constraint in the SDC at the same time;
- The pixel output interface (`pixel_data/hs/vs` + counters) is the attach point for customer
  image-processing logic; the unreferenced `data_unpack.v` and similar examples can be used
  as references to extend into a frame-buffer/display path;
- The `IP/` directory vs. the project include spelling (lowercase `ip/`) only works on
  case-insensitive Windows; unify the casing before migrating to Linux builds.

## 7. Known Issues and Notes

- The 11 unreferenced files in the root directory (TX/VGA/pattern examples and duplicate IP
  copies) are kept as references; they do not participate in synthesis (not in the project
  design_file list);
- `Ti180_mipi.sdc` contains a full set of DPHY **TX** constraints although the peri has no TX
  instance (stale constraints); the header comment still carries 2022-era
  `Ti180F484 / new_csi` information;
- The base_path inside the IP settings.json points to the original developer's machine path
  (`D:\J\...`); when opening on another machine Efinity will prompt for relocation — just
  ignore it;
- This reorganization removed the embedded Ti180M484/T20F256/Ti60F225 devkit reference-project
  copies under `IP/`; the project is unaffected.
