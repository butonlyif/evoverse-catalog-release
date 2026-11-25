English | [中文](README.md)
# si5338-clock-config — Si5338 Programmable Clock Configuration and Clock-Quality Verification

> Original directory: `SI5338/SI5338/TJ180A484_soc_lpddr4/` (triple nesting flattened; the
> project files now live in the demo root directory)

## 1. Overview

This project completes the **full configure-and-verify loop for the Si5338A programmable
clock generator** on the WS-E1 platform:

1. **Configuration**: the Sapphire RISC-V soft core inside the FPGA writes the register table
   (`Si5338-RevB-Registers.h`) to the Si5338 entry by entry via I2C0 (7-bit address **0x70**,
   100kHz), finishing with register 246=0x02 to apply the soft reset; read/write logs are
   printed over UART throughout;
2. **Verification**: the 156.25MHz differential clock output by the Si5338 is recovered via
   **LVDS RX (GPIOB_PN_16) → PLL_BL2** phase locking; the divided `si5338_cnt[25]` drives
   **LED0 blinking at about 2.3Hz**; the same clock is also output on GPIOL_33 (clkout) for
   oscilloscope cross-checking.

The project is also a complete **Sapphire SoC + LPDDR4x single-AXI-port** SoC reference design
(including the FreeRTOS/lwIP/FatFS BSP software tree).

- Device: Titanium **TJ180A484S** (C4)
- Toolchain: Efinity 2026.1.132.1.15 (pass, bitstream generated)
- Top module: `top_soc` ([top_soc.v](top_soc.v))

## 2. Hardware Resource Usage

| Resource | Configuration |
| --- | --- |
| DDR hard IP `ddr_inst1` | LPDDR4x, 2Gb, x16, 1 rank, **only AXI target0 enabled** (io_ddrA_*, 512-bit) |
| `main_pll` (PLL_TL0) | 50MHz → io_systemClk 100MHz |
| `ddr_pll` (PLL_TL2) | 33.33MHz×4 → io_memoryClk 100MHz, 133.3MHz DDR clock |
| `pll_inst3` (**PLL_BL2**) | reference = Si5338 differential clock 156.25MHz, `si5338_pll_locked` |
| **LVDS RX ×1** | `FPGA_SI5338_CLK_IN` (GPIOB_PN_16) receives the Si5338 output differential clock |
| Soft core | **Sapphire SoC** (VexRiscv): I2C0 (GPIOL_42/50, 3.3V), SPI0, UART0 (GPIOR_61/57), GPIO0, dual JTAG |
| GPIO clkout | `si5338_pll_clk_156m25` @GPIOL_33 (recovered clock output for measurement) |

Board-level peripherals: Si5338A clock generator, LPDDR4x, UART serial port, LED0, 50/33.33MHz
crystals.

## 3. Directory Structure

```
si5338-clock-config/
├── soc.xml / soc.peri.xml         # Efinity 工程（打开这个）
├── constraints.sdc                # 时序约束（Interface Designer 自动生成）
├── top_soc.v                      # 顶层 top_soc（SoC + DDR + Si5338 时钟链路）
├── design_modules.v               # Sapphire 配套模块
├── sapphire_soc.v / *_define.vh   # Sapphire SoC IP 生成代码
├── EfxSapphireSoc...ram_symbol*.bin  # SoC 片上 RAM 初始化镜像 ×4
└── embedded_sw/
    ├── sapphire_soc/              # 当前有效软件树（BSP + 全套例程，无 Si5338 程序）
    └── sapphire_soc_backup/       # 旧版 BSP —— ★ Si5338 配置程序只在这里
        └── software/standalone/i2cCfgSi5338/
            ├── src/main.c                      # I2C 写入 Si5338 寄存器表
            └── src/Si5338-RevB-Registers.h     # Si5338 寄存器配置表
```

> **Important**: the `i2cCfgSi5338` application exists only under
> `embedded_sw/sapphire_soc_backup/`; it is not in the main software tree `sapphire_soc/`.
> Although `sapphire_soc_backup` is an old-BSP backup, it **must not be deleted**.

## 4. Working Principle

- **RTL** (top_soc.v): the Sapphire SoC accesses LPDDR4x through the AXI interconnect
  (including ID width adaptation and hard-IP-specific signal handling such as
  apcmd/allstrb/cobuf); after the DDR Startup Sequencer handshake, `io_memoryResetn` is
  released. Si5338 clock chain: LVDS RX → PLL_BL2 → free-running `si5338_cnt` →
  `led0 = si5338_cnt[25]`; the SoC's built-in memory checker result is output via
  `memoryCheckerPass`.
- **Software** (i2cCfgSi5338/src/main.c): walks the `Si5338-RevB-Registers.h` register table,
  writing directly when `Reg_Mask=0xff`, otherwise doing read-modify-write; finally writes
  246=0x02 for the soft reset; every read/write is printed over UART.

## 5. Run and Verify

1. Program the bitstream (build `soc.xml` in Efinity);
2. Download and run the `i2cCfgSi5338` program (built from cpu0.yaml) via OpenOCD/JTAG;
3. On the UART terminal, observe "I2C Cfg Si5338 Begin … Done" plus per-register logs;
4. After successful configuration, **LED0 blinks at about 2.3Hz** (156.25MHz / 2^26);
5. Optional: measure the 156.25MHz clock on GPIOL_33 with an oscilloscope.

## 6. Integration Notes for Customer Systems

- **Si5338 register table**: when changing the clock scheme, regenerate
  `Si5338-RevB-Registers.h` with SiLabs ClockBuilder; the software flow needs no changes;
- The **clock back-check chain** (LVDS RX → PLL_BL2 → counter/clkout) is reusable as a whole
  and serves as a template for "locked-in-FPGA verification" of any external differential
  clock;
- The DDR side is a single-target0 configuration and can be compared with / trimmed against
  the dual-port arrangement (see the ddr-memtest demo);
- The project `ip_info` references `ip/sapphire_soc/settings.json`, but there is no `ip/`
  directory in the repository; when opening the project, Efinity regenerates the Sapphire IP
  according to the settings — this is expected behavior.

## 7. Known Issues and Notes

- The two BSP trees `sapphire_soc_backup/` and `sapphire_soc/` duplicate each other at large
  scale (hundreds of files); they are kept because the Si5338 program exists only in backup.
  To unify them, migrate `i2cCfgSi5338` into the main tree first, then clean up;
- The directory name `TJ180A484_soc_lpddr4` has nothing to do with the demo function
  (Si5338) — historical legacy; this reorganization promoted the project to the
  `si5338-clock-config/` root directory.
