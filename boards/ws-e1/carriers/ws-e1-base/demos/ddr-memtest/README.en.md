English | [中文](README.md)
# ddr-memtest — LPDDR4x Memory Write/Read Comparison Test

> Original directory: `DDR_TEST/DDR_TEST/` (double nesting flattened)

## 1. Overview

A pure-hardware (no soft core) LPDDR4x memory self-test project: two independent `memory_checker`
state machines inside the FPGA write to, then read back and compare, the onboard LPDDR4x-2133
memory through the **AXI target0 / target1 dual 512-bit ports** of the DDR hard-IP controller;
results are indicated directly by 6 LEDs. This is the structurally simplest of the 9 demos and
serves as the **minimal reference project for DDR hard-IP integration / LPDDR4x bring-up**.

- Device: Efinix Titanium **TJ180A484S** (timing model C4, 484-package)
- Toolchain: Efinity 2025.2.288.4.15 (`last_run_state=pass`, bitstream generated)
- Top module: `test_ddr_start` ([rtl/mem_test.v](rtl/mem_test.v))
- No soft core, no UART; verification relies entirely on LEDs

## 2. Hardware Resource Usage

| Resource | Configuration |
| --- | --- |
| DDR hard IP `ddr_inst1` (DDR_0) | LPDDR4x, 2Gb density, x16, 1 rank, **both AXI target0 + target1 ports enabled** (512-bit data / 64-bit strb) |
| `pll_inst1` (PLL_TL0) | 50MHz reference → CLKOUT0/i_sys_clk and `axi0_ACLK`/`axi1_ACLK` (250MHz, SDC 4.0ns) |
| `pll_inst2` (PLL_TL2) | 33.33MHz reference ×4 → DDR PHY clock |
| GPIO | `sys_clk_ref`=GPIOL_26 (50MHz, 3.3V, pll_clkin), `ddr_clk_ref`=GPIOL_32 (33.33MHz) |
| IO bank | TL=3.3V LVCMOS, all others 1.8V |

Board-level peripherals: LPDDR4x-2133 memory, 6 LEDs, 2 DIP switches (`i_sw[1:0]` port reserved).

## 3. Directory Structure

```
ddr-memtest/
├── bsp/
│   └── tj180A484_lpddr4_2133M/   # Efinity 工程目录
│       ├── mem_test.xml          # 工程文件（打开这个）
│       ├── mem_test.peri.xml     # Interface Designer：DDR/PLL/GPIO 硬核配置
│       ├── constrain.sdc         # 时序约束（AXI 250MHz ×2）
│       ├── mem_test.hex          # bitstream HEX 编程文件（可直接烧录）
│       └── debug_profile.wizard.json  # Debugger 向导配置（已禁用，未引用）
└── rtl/
    ├── mem_test.v                # 顶层 test_ddr_start：启动 FSM + 双 checker
    ├── memory_checker.v          # 写→读→比对状态机（含 mark_debug 观测信号）
    └── reset.v                   # 异步复位、同步释放复位桥（CYCLE 参数化）
```

The project root is `bsp/tj180A484_lpddr4_2133M/`; RTL is referenced via the relative path
`../../rtl/`, so the directory can be moved as a whole without affecting opening the project.

## 4. Working Principle

1. After power-up, wait for `sys_pll_lock & ddr_pll_lock`;
2. The IDLE→CFG_START→CFG_DONE state machine drives the **DDR Startup Sequencer**
   (CFG_RST/START/DONE/SEL signal group) to complete the hard-IP internal configuration;
3. After `ddr_cfg_ok`, the axi0/axi1 AXI resets are released;
4. The two `memory_checker`s run in parallel:
   - checker0 covers addresses 0 ~ 0x201900 (about 2MB+)
   - checker1 covers the default 0x1900 region
   - FSM: `IDLE→WRITE_ADDR→WRITE→READ_ADDR→READ_COMPARE→DONE`, outputting `fail`/`done`
     plus the `rdata_obs`/`rdata_exp` observation signals (mark_debug applied).

## 5. Run and Verify (LED Meaning)

| LED | Meaning |
| --- | --- |
| led5 | DDR hard-IP configuration complete (CFG_DONE) |
| led4 / led3 | checker0 / checker1 test complete |
| led2 / led1 | checker0 / checker1 passed (done with no fail) |
| led0 | Both ports passed (final PASS) |

All LEDs lit means the LPDDR4x dual-AXI-port read/write path is working. For deeper debugging,
re-enable the Debugger in the Efinity GUI and capture the `memory_checker` mark-debug signals to
observe the read-back vs. expected data.

## 6. Build and Program

1. Open `bsp/tj180A484_lpddr4_2133M/mem_test.xml` in Efinity;
2. Run directly (bitstream flow); bitstream options: active x1, compression on, produce .bit/.hex;
3. Program `mem_test.hex` (or the regenerated bitstream) to Flash / configure directly.

## 7. Integration Notes for Customer Systems

- **The DDR hard-IP configuration is defined by `mem_test.peri.xml`**: LPDDR4x 2Gb x16 single
  rank, dual targets. When changing memory devices, adjust the density/width of `ddr_inst1`
  and clkin_sel;
- The AXI width is 512-bit with 64-bit strb; the port names `axi0_*`/`axi1_*` connect directly
  to customer logic, or replace `memory_checker` with the business module;
- The DDR Startup Sequencer handshake (wait lock → CFG_START → wait CFG_DONE → release reset)
  is mandatory for the Titanium DDR hard IP; keep this FSM section when porting
  ([rtl/mem_test.v](rtl/mem_test.v));
- Instantiate one `reset.v` reset bridge per AXI clock domain; do not reuse the same reset
  signal across clock domains.

## 8. Known Issues and Notes

- Many PLL/DDR AXI input/output delay constraints in `constrain.sdc` remain **commented out**
  (Efinity-generated template, not enabled); currently only the two 250MHz AXI clocks are
  constrained. Enable them as needed for high-speed timing closure;
- The bsp subdirectory name `tj180A484_lpddr4_2133M` follows the Ti180 official reference-design
  naming and matches neither the project name `mem_test` nor the top module `test_ddr_start`
  (historical legacy, does not affect usage).
