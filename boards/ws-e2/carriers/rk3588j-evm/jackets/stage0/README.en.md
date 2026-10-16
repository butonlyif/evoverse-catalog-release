English | [中文](README.md)

# Stage0 Jacket — TJ375 SOM (TBS2009) + Carrier (TJ375_RK3588J_EVM)

Pinout information set for the TJ375N1156X (Efinix Trident-T, Efinity 2026.1). Goal: rebuild the pin
mapping directly from the schematic PDF vector sources, cross-validate it three ways, and produce
Efinity-consumable constraints and CSVs.

> The directory layout follows the SDK board structure (same as ws-e1): this file lives in
> `boards/ws-e2/carriers/rk3588j-evm/jackets/stage0/`; paths such as `_device/` and `tools/` in this
> document are relative to the workspace root `d:\work\ws-e2\`.

## Data Sources

| Source | Content | Evidence |
|------|------|------|
| SOM schematic (TBS2009, Shennan Circuits, 34 pages) | p32 RK3588-BTB-CONN (RK side/power/GND), p33 U9B HDMI/EDP | PDF vector extraction |
| Carrier schematic (TJ375_RK3588J_EVM, Efinix, 25 pages) | p23 BTB connector | PDF vector extraction |
| Device pinout CSV (`_device/`) | authoritative ball ↔ pin_name ↔ bank ↔ voltage table | Efinity export |
| `TJ375N1156X.peri.xml` | authoritative device bank list + voltages (`efxpt:design_db`) | Efinity PT output |

## Deliverables

| File | Content | Scale |
|------|------|------|
| `boards/ws-e2/pinout/ws-e2-module.csv` | ball view: ball, pin_name, bank, io_bank_voltage, function, som_net, btb_refdes, btb_pin, evm_net, evidence, remark | 302 unique balls |
| `boards/ws-e2/carriers/rk3588j-evm/pinout/rk3588j-evm.csv` | RefDes view: full BTB 1280-pin coverage, SOM/EVM net names aligned | 1280 rows |
| `constraints/banks.isf` | all 24 bank voltages explicitly declared (ISF = Python API source) | 24 `set_iobank_voltage` entries |
| `_device/rail_nets.json` | SOM∪EVM power/GND rail net names → bank mapping | 24 rails |

## Bank Voltage Decisions

- **HSIO 1.8 V**: `2A 2B 2C 2D 2E 4A 4B 4C 4D`
- **General-purpose IO 3.3 V**: `TL0 TR0 TR1 TR2 TR3 TR5 BL0 BL1 BL2 BL3 BR0 BR1 BR3 BR4`
- **Shared domain**: `TL1_TL5` (merged peri.xml name; one voltage domain covering TL1+TL5) = 3.3 V

Basis: the authoritative peri.xml iobank_info structure + connector rail net names (`VCCIO33_*` /
`BANK2_VCC_2*_OUT` / `BANK4D_VCC_ADJ`) + verify item D showing no voltage mixing.

## Cross-Validation Verdict (verify_xcross.py, 181 issues → PASS)

- **B2 strongest endorsement**: extraction chain net→ball ↔ xlsx'0920' 301/301 with zero conflicts.
- **fmt=31**: pure bracket-format differences (`DDR0_DQ31` vs `DDR0_DQ[30]`), balls identical, not errors.
- **func=11**: functional naming convention differences (CFG_DONE↔CDONE, RK3588_SPI_*/GPIO*/IIC_* ↔ GPIOB_P/N_47..51), balls identical.
- **mismatch=137**: numbering/naming convention differences (DDR byte-lane local numbering vs Efinity global numbering; GMAC0_*→Q0_RXDP*;
  MIPI_CSI0_RX_*→MIPI0_TXDP*), no real misplacements.
- **The only schematic typo (AA1)**: net label `GPIOB_P_16_CLK3_N` should be `GPIOB_N_16_CLK3_N` (N-side ball,
  bank 4D; the device CSV's Y1=P side corroborates). `gen_stage0_csv.py` has a built-in ALIAS dictionary for the
  verdict, and the csv remark is annotated.

## banks.isf Self-Check (official Efinity importer)

```
EFXPT_HOME=C:/Efinity/2026.1/pt
python311/bin/python.exe  _device/isftest/run_import.py   # replicates efx_run_pt_import_isf.py logic
```

- All 24 commands pass line by line with `INFO: Import`,
  `Import ISF '...jackets\stage0\constraints\banks.isf'...DONE`, EXIT=0.
- `banks_import_issue.csv` (in this jacket directory) contains only the header (zero issues).
- Spot check of the merged result `isftest/TJ375N1156X.peri.merged.xml`: all 24 bank iostd values match the table above.

Note: the official `efx_run_pt_import_isf.py --isf_files` (nargs='+' + append) has a nested-list bug;
the wrapper `run_import.py` calls the same `DesignAPI.import_design()` and only flattens the arguments.

## Functional-View Pinout (func-view, BTB connector ignored)

Restructured per user instruction: directly provide the pin mappings of **FPGA / RK3588 each to
devices/interfaces** and their **mutual interconnects**; the BTB connector serves only as a path
annotation (`page_ref=/32/,/33/`) and is no longer the primary view.

### Deliverables

| File | Content | Scale |
|------|------|------|
| `func-pinout-fpga.csv` | FPGA functional-domain pinout: domain/pin/ball/net/page_ref/peer + RK peer + EVM function tag | 319 rows |
| `func-pinout-rk3588.csv` | RK3588 functional-domain pinout: domain/sch_page/pin/ball/net/peer + FPGA peer | 372 rows |
| `_device/func_pinout_fpga.json` | structured source of the above (with separate mipi_channels/qse_channels sections) | — |
| `_device/func_pinout_rk.json` | structured source of the above | — |
| `_device/verify_fpga_func.json` | FPGA usage consistency verification | 5 PASS / 2 WARN / 0 FAIL |
| `_device/verify_rk_func.json` | RK vs Rockchip datasheet verification | 7 PASS |

### FPGA (TJ375) Functional Domain Distribution (319 pins)

| Domain | Count | Peer |
|----|------|------|
| MIPI 6 channels (MIPI0/1_TX + MIPI0/1/2_RX + MIPI2_TX) | 60 | MIPI0/1_TX→RK CSI0/1_RX (direct inside SOM); the other 4 channels via BTB→EVM |
| QSE_Q2_BTB (Q2 SERDES all channels + REFCLK×2 pairs + CAL_RES) | 21 | BTB→EVM |
| BTB_EVM (GPIOB/L/R pass-through + PCIE PERST) | 147 | BTB→EVM (EVM function tags in the CSV) |
| **PCIE30_Q0 (Q0_RXD0-3←RK TX, Q0_TXD0-3→RK RX, 2×2 mode)** | 16 | **RK3588 PCIE30 PORT0(lane0-1)+PORT1(lane2-3) (direct inside SOM, p27)** |
| CLK_INPUT (PLLIN×18 + EXTFB) | 25 | SOM clock sources (CLK_25MHz/100M_0/1 land on PLLIN; 25M_0/1/3 land on ordinary GPIO, see observations) |
| QSE_REFCLK_SLOT (Q0_REFCLK0 pair) | 2 | p19 clock buffer (PCIE30_REFCLK_SLOT→RK REFCLK_IN) |
| QSE_CLK (Q0_REFCLK1 pair + CAL_RES unused) | 3 | SOM (REFCLK1 floating) |
| GMAC0_RGMII (RXD0-3/TXD0-3/RXCLK/TXCLK/TXEN/RXDV) | 12 | RK3588 GPIO2 multiplexed pins (direct inside SOM) |
| RK_GPIO_SPI_IIC (GPIO01-04 + SPI4 + IIC1) | 10 | RK3588 (direct inside SOM) |
| CONFIG_JTAG (CDONE/CRESET/NSTATUS/CBSEL/TMS/TCK/TDI/TDO/JTAG_VCCIO_SEL) | 10 | SOM JTAG/BOOT |
| CONFIG_FLASH (FPGA_CDI0-3/SS/CCK, active-serial x4) | 6 | SOM configuration FLASH |
| REF_RES (4A/4B/4D reference resistors) | 3 | SOM |
| OTHER (missing page refs: TEST_N/CLK10_N/PERST_Q0/GPIO_RSD) | 4 | see observations |

### RK3588 Functional Domain Distribution (372 pins)

FPGA_DIRECT 58 (GMAC 12 + CSI 20 + GPIO/SPI/IIC 10 + **PCIE30 data 16**) · BTB_EVM subcategories 184
(MIPI/QSE 56, PCIE 21, USB/TypeC 21, HDMI/eDP 19, ETH 13 …) · PWR_CLK 50 · SOM_LOCAL 46 · EMMC 14 ·
NO_NET 19 (power/no-connect).

### FPGA↔RK3588 Interconnect Overview (direct inside the SOM, 116 pin pairs total)

| Channel | FPGA side | RK side | Signal count |
|------|---------|-------|--------|
| MIPI CSI0/1 | MIPI0/1_TX (p26) | MIPI_CSI0/1_RX | 2×10 |
| GMAC0 RGMII | GPIOB_31-35 (p21) | GPIO2/4 multiplexed | 12 |
| **PCIe 3.0 (QSE Q0, 2×2)** | **Q0_RXD0-3/Q0_TXD0-3 (p27)** | **PCIE30_PORT0+PORT1** | **16** |
| GPIO/SPI/IIC | GPIOB_47-51 (p21) | GPIO1/2/4 | 10 |
| PCIe REFCLK | Q0_REFCLK0 (p27→p19 buffer) | PCIE30_PORT0/1_REFCLK_IN | 2 (via buffer) |

### FPGA-Side Verification Conclusions (verify_fpga_func.py)

- **V1 MIPI**: 6 channels × 10 lanes (D0-D3 + CLK, P/N paired) complete.
- **V2 PLLIN**: CLK_25MHz→GPIOR_140_PLLIN1, CLK_100M_0/1→GPIOL_25/52_PLLIN1 correct; ⚠ CLK_25M_0/1/3
  land on ordinary GPIO (GPIOR_97/GPIOL_46/GPIOL_23) — **re-checked: ball numbers y-aligned (functional net
  name vs ball number dy∈[-1,0]), attribution correct**; this is a design choice (the EVM 25M clocks enter
  ordinary IO); if used as a PLL reference, confirm the TJ375 allows non-dedicated pad inputs.
- **V3 configuration chain**: active-serial x4 six wires + six JTAG signals + NSTATUS + CBSEL×2 complete.
- **V4 RGMII**: all 12 signals present; the RK peer ball numbers verified via the datasheet mux chain.
- **V5 differential pairs**: 34 BTB pass-through P/N pairs complete; ⚠ GPIOB_33/44 are RGMII RXCLK/TXCLK
  using only the P pin (a legal single-ended use); GPIOB_43 pair **re-checked**: P=CSO_CLK10_P (routed on
  /32/) and N=CSI_CLK10_N have different function suffixes — they are actually two independent single-ended
  signals; the N side's local net + DNP resistor = a reserved pin, not a missing label.
- **V6/V7**: the three REF_RES pads have no signal nets; the 319 pins (including QSE 42) have unique ball
  numbers and all match the authoritative Efinity ballmap.
- **V8 QSE/PCIe (new)**: Q0↔RK PCIE30 16 data lines paired deterministically by lane/polarity (2×2 mode);
  Q0_REFCLK0 via the p19 buffer; all Q2 channels go through BTB; CAL_RES connects to 3.01K.

### RK3588-Side Verification Conclusions (parse_rk3588_datasheet.py)

Cross-checked ball-by-ball against Table 2-1 of the Rockchip **RK3588 Datasheet V2.2** (FCBGA1088):
**363/367 = 98.9% exact/mux-chain match**. The eMMC 13 balls
(Y33/W33/V32/AA33/Y32/AA32/W32/V33/W34/V34/Y34/AA34), GMAC0 RGMII 12 pins, MIPI CSI0/1, and
GPIO01-04/SPI/IIC all agree. The 4 differences are naming deltas of `USB30_2_SSTXN` vs datasheet
`USB30_SSTXN` (ball numbers and the PCIE20_2/SATA30_2 function segments fully correct, benign).
AD4=NC matches the schematic's "Must floating" annotation.

## Stage0 Efinity Project (compilable minimal skeleton)

A minimal compilable project created on top of the pinout information set, verifying that the full
"project XML → RTL → ISF → bitstream" chain works on the TJ375N1156X (family=**Titanium**, timing
model **C4**).

### File List

| File | Purpose |
|------|------|
| `ws-e2-stage0.xml` | Efinity project XML (`enf_proj` namespace, unified_flow=true, sdc/isf paths relative to the XML) |
| `rtl/top.v` | Minimal combinational logic: `assign led_user = ~user_sw;` (avoids the VDB-9009 all-constant optimization) |
| `constraints/banks.isf` | 24 bank voltage declarations (referenced by the project XML) |
| `constraints/ws_e2_stage0.pins.isf` | stage0 GPIOs: bank voltage + pin assignment + IO_STANDARD + PULL_OPTION |
| `constraints/ws_e2_stage0.sdc` | Purely combinational with no clock; comments only for now (a create_clock must be added once a clock exists) |
| `compile.bat` | One-click `efx_run.bat --flow compile` (with the correct environment variables built in) |

### Pin Assignment (source: pinout/ws-e2-module.csv)

| RTL port | Device pin | Ball | Bank | Direction | Attributes |
|----------|----------|------|------|------|------|
| `user_sw` | GPIOR_150 | R11 | TR1 (3.3 V) | input | WEAK_PULLUP (switch open = high) |
| `led_user` | GPIOR_98 | M25 | TR1 (3.3 V) | output | — (lit when driven low) |

### Compile Evidence (2026-09-21)

```
map : PASS  →  interface : PASS  →  pnr : PASS  →  pgm : PASS   (EXIT=0)
Artifacts: outflow/ws-e2-stage0.bit (23 MB) / .hex / .lpf / .pinout.rpt
```

ISF importer self-check (`_device/isftest/run_import.py`, replicating `efx_run_pt_import_isf.py`) EXIT=0.

### Three Key Pitfalls of the Unified Flow (required reading for later jackets)

1. **A leftover `ws-e2-stage0.peri.xml` causes GPIO same-name creation conflicts**
   (`Fail to create gpio. Instance with the same name has been created`). peri.xml is a PT-flow
   artifact; stale instances from early experiments (including scalar/bus dual instances) make the
   regenerated `unified.isf`'s `create_*_gpio` collide on names. When cleaning outflow, the peri.xml in
   the project root must be deleted as well.
2. **A pure-CLI flow must explicitly call `set_property("x","IO_STANDARD","3.3 V LVCMOS","GPIO")`**.
   The official samples omit it because the GUI peri.xml defaults cover it; a new pure-CLI design
   defaults to 1.8 V, which conflicts with a 3.3 V bank, and Design Check reports
   `gpio_rule_io_standard_bank`.
3. **`EFINITY_HOME` must use forward slashes** (matching the official `setup.bat`'s
   `%EFINITY_HOME:\=/%`). When the system environment variable uses backslashes, `efx_run.bat` skips
   setup.bat, and the backslashes entering efx_pnr's Tcl `source` are treated as escapes
   (`C:\Efinity\2026.1` → `C:Efinity6.1`) → `Failed to load timing modules`.
   compile.bat has the correct value built in.

## Scope and Limitations

- All bank voltages are explicitly declared; GPIO assignment covers only the two stage0 skeleton pins
  (user_sw/led_user); later design stages append per the pinout CSV.
- The 16 SOM no-label positions on the EVM side were resolved via fallback parsing from EVM net names
  and all landed in pinout-carrier.csv.
- `_device/isftest/` keeps the self-check evidence (peri copy + wrapper + merged XML); do not use it
  as project input.
