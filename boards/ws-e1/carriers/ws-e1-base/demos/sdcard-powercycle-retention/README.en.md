English | [中文](README.md)
# sdcard-powercycle-retention — microSD Card Power-Cycle Retention Write/Read Verification

> Original directory: `TJ180A484S_SDHOST/TJ180A484S/` (the original outer 3-line
> `SDHOST_readme.txt` has been merged into this README; the original file is kept in the
> directory)

## 1. Overview

An **SD card Host controller + data power-cycle retention** verification project: a Sapphire
RISC-V soft core drives the `efx_sd_host_controller` IP (SD/SDIO Host + ADMA2) through an
APB→AXI-Lite bridge and runs the "write → whole-board power-off → power on again → read-back
verification" flow against a microSD card; an all-match result outputs **PASS**, verifying
both the persistence of SD card writes and the completeness of the Host-controller driver.

- Device: Titanium **TJ180A484S** (timing model **I3**; note this differs from the other
  demos' C4)
- Toolchain: Efinity 2025.1.110.4.9 (pass, bitstream generated, active configuration mode)
- Top module: `TJ180A484S` ([TJ180A484S.v](TJ180A484S.v), chip-level top)
- Core software: `embedded_sw/soc_ti180/software/standalone/TJ180A484S_SDHOST/src/main.c`
  ("EFX-SD Power-Cycle Retention Test")

## 2. Hardware Resource Usage

| Resource | Configuration |
| --- | --- |
| DDR hard IP `ddr_inst` (DDR_0) | LPDDR4x, 2Gb, x16, 1 rank, dual AXI ports (512-bit); ADMA data uses AXI port 1 |
| `pll_sys` (PLL_TL0) | → i_soc_clk / i_sd_clk / i_axi0_mem_clk 100MHz |
| `pll_ddr` (PLL_TL2) | 33.33MHz×4 → 133.3MHz (i_axi1_mem_clk) |
| Soft core | Sapphire SoC (`soc_ti180`, efx_soc v3.2.3): single-core RISC-V, I/D-Cache 4KB, UART0+SPI0/1+I2C0+GPIO0, APB Slaves 0–3, 100MHz |
| SD Host IP | `tj180a484s_sdhost` (efx_sd_host_controller v6.0, SD/SDIO + ADMA2) |
| Bridge | `apb3_2_axi4_lite_sdhost` (soft-core APB slave2 → SDHC registers, base offset +0x100) |
| **SD pins (GPIO, 3.3V)** | sd_clk=GPIOL_30, sd_cmd=GPIOL_03, sd_dat[0..3]=GPIOL_05/49/04/31, card detect sd_cd_n=GPIOL_10 |

Board-level peripherals: microSD card slot (J8, SDIO3.0, with card detect), LPDDR4x, UART.

## 3. Directory Structure

```
sdcard-powercycle-retention/
├── TJ180A484S.xml / .peri.xml      # Efinity 工程（打开这个）
├── tj180a484.sdc                   # 时序约束
├── TJ180A484S.v                    # ★ 芯片顶层：DDR 配置 FSM + AXI 粘合 + 实例化 top_soc_sd
├── top_soc_sd.v                    # SoC + SD Host + 桥的系统集成层（引脚映射注释详细）
├── top_soc_oob.v                   # 旧 OOB 顶层（未被工程引用，遗留）
├── SDHOST_readme.txt               # 原始 3 行 readme（历史保留）
├── ip/
│   ├── tj180a484s_sdhost/          # SD Host IP
│   ├── apb3_2_axi4_lite_sdhost/    # APB3→AXI4-Lite 桥 IP
│   └── soc_ti180/                  # Sapphire SoC IP
└── embedded_sw/soc_ti180/
    ├── bsp/efinix/EfxSapphireSoc/
    ├── software/standalone/TJ180A484S_SDHOST/   # ★ 主应用
    │   └── src/{main.c, userDef.h, source.c, intc.c, efx_mmc_driver.c}
    ├── tool/bootloader/ + binGen.py
    └── cpu0.yaml
```

## 4. Working Principle

- **RTL**: `TJ180A484S.v` performs the LPDDR4x startup handshake (io_memoryReset → CFG_START →
  CFG_DONE → release ARSTN) and the SoC `io_ddrA` ↔ DDR hard-IP AXI port 0 glue (ID width
  conversion); `top_soc_sd.v` integrates the soft core + bridge + SD Host, with SDHC ADMA data
  entering DDR through SoC AXI master1.
- **Software** (main.c + userDef.h): UART input **W** → erase and write an LBA pattern
  (start LBA 0x1000, 128 blocks, data-header pattern `A9 A3 A6 A5`); after a **power-cycle
  restart**, run the program again and input **R** → read back and compare block by block;
  an all-match result outputs **PASS**. The SD controller runs at 50MHz in 4-bit mode, with
  interrupts wired to PLIC USER_INTERRUPT_B.

## 5. Run and Verify

1. Open `TJ180A484S.xml` in Efinity, build, and program (active mode);
2. Insert the microSD card and connect the UART terminal;
3. Download and run the `TJ180A484S_SDHOST` program; input `W` to write the test data;
4. **Power the whole board off and on again**, then download and run the program again and
   input `R`;
5. The terminal printing **PASS** means both data retention and the read/write path are
   working.

## 6. Integration Notes for Customer Systems

- The SD Host trio (`tj180a484s_sdhost` + `apb3_2_axi4_lite_sdhost` + soft-core APB slave2
  attachment) is a subsystem that can be moved as a whole; the SDHC register base = APB slave2
  base +0x100, with the matching macro in software `main.c`;
- ADMA descriptors go through SoC AXI master1 → DDR; if the customer system has no DDR,
  switch to PIO mode and adapt `efx_mmc_driver.c`;
- All SD pins are 3.3V GPIOs (bank voltage declared in peri.xml); card detect `sd_cd_n` is
  active-low; changing pins only requires editing peri.xml + the SDC constraints;
- The write parameters (LBA start / block count / pattern) are centralized in `userDef.h`;
  the test needs no changes to the code body;
- The timing model is **I3**, different from the other demos on this board (C4); the Efinity
  version is also older (2025.1). When migrating to a newer version, watch for SD Host IP
  regeneration.

## 7. Known Issues and Notes

- `top_soc_oob.v` is not referenced by the project (old OOB top); kept as a reference;
- The `outflow/TJ180A484S_template.v` template path referenced in the `TJ180A484S.v` header
  comment does not exist in the repository;
- The `top_soc_sd.v` comment "i_sd_clk ~50MHz" disagrees with the 100MHz SDC constraint (the
  SDHC divides it down to 50MHz internally; the SDC is authoritative);
- This reorganization removed the embedded T120F576/Ti180J484 devkit reference-project copies
  under `ip/`; the project is unaffected.
