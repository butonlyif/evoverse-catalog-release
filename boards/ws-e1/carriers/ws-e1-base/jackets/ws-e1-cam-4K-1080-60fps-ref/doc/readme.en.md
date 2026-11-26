[中文](readme.md) | English

# ws-e1-cam-4K-1080-60fps-ref Project Description

An Efinix Titanium FPGA camera-connected demo: IMX415 → CSI-2 RX → the image pipeline → CSI-2 TX → the panel.
**No DDR, no frame buffer**, and the display frame rate follows the sensor (1080p60 pass-through). It is currently a **dual camera** architecture (2 complete chains), and the RISC-V soft core only handles the sensor I2C configuration and the runtime CSR adjustment.

> Status (2026-09-27): the single chain has been verified at the board level (both the pattern and the camera display are correct); the dual camera changes (RTL + firmware) are complete but **have not been re-synthesized and re-tested on the board**.

## 1. Hardware architecture

```
Per chain top_cam (rtl/top_cam.sv):
  DPHY RX hard core → my_csi2_rx(raw IP) → RAW10 4px @sys_clk_200m
    → [mux: pattern_gen | sensor]  ← CSR pat_en software switch (the edge triggers a soft reset in both domains)
    → camera_path:
        raw_2_axi4st (unpack/window) → demosaic → wb_axis → rgb2yuv_axis
        → shape_video_axis (cross-domain aclk→pixel_clk + shaping + frame rate locking)
    → UYVY 4px @tx_pixel_clk → my_csi2_tx(raw IP) → DPHY TX hard core → panel

top_cam_demo (rtl/top_cam_demo.sv) = 2x top_cam + riscv_soc + an idle DDR + the PLL reset chain
```

Clocks: `sys_clk_200m` (the RX pixel output domain + the pipeline aclk + the APB pclk), `tx_pixel_clk` 37.125MHz (the panel pixels + TX + the pattern line cadence source), `sys_clk_100m` (the RX controller clock, the AXI tie off), `i_clk_27m` (the TX power-on self-reset reference), `esc_clk` (the DPHY TX), `dphy_rx*_clk_CLKOUT` (the RX recovery word clock, which keeps oscillating with no stream).

The DDR is not used, but the pin bindings are kept (peri.xml is untouched), and the CFG FSM still initializes the DDR hard core as usual.

## 2. The dual camera resource mapping

| | cam0 (u_cam_0) | cam1 (u_cam_1) |
|---|---|---|
| The data chain | DPHY RX0 → DPHY TX0 | DPHY RX2 → DPHY TX2 |
| APB (apb_cam_ctrl) | slave0 = 0xF810_0000 | slave1 = 0xF811_0000 |
| I2C (IMX415, 7bit 0x1A) | I2C0 = 0xF801_6000 | I2C1 = 0xF801_7000 |
| cam_en (a whole-word GPIO0 write) | bit0 | bit1 |

APB slave2/3 are dummy immediate-responders (a mis-access does not hang the CPU). The address macros are in `sw/bsp/include/soc.h`, and the firmware-side wrappers are in `sw/top_demo/src/userDef.h` (APB_0/APB_1).

## 3. Directory structure

- `rtl/` — all the RTL (see the table below)
- `ip/` — the Efinity raw IPs: `my_csi2_rx`, `my_csi2_tx`, `riscv_soc` (SaxonSoc/VexRiscv, BRAM firmware)
- `sw/top_demo/src/` — the firmware sources: `main.c`, `imx415_init.c/.h`, `userDef.h`
- `sw/bsp/` — the SaxonSoc BSP (the driver headers, the linker script, openocd)
- `sim/` — the QuestaSim TBs and the regression logs
- `work_syn/`, `work_pnr/`, `work_pt/`, `outflow/` — the Efinity synthesis/routing/programming scripts and products (`ws-e1-cam-ddr-csi2.bit/.hex`)
- `ws-e1-cam-ddr-csi2.peri.xml` — the peri subsystem pin bindings (the DPHY hard cores / the SOC peripherals; it is only touched when the pins change)

### The RTL modules

| File | Responsibility |
|---|---|
| top_cam_demo.sv | The dual camera top level: 2x top_cam + soc (the I2C/GPIO/APB allocation) + an idle DDR |
| top_cam.sv | A single chain: CSI2 RX + pattern_gen + camera_path + CSI2 TX + apb_cam_ctrl + the line cadence generator + the source switch soft reset |
| camera_path.sv | The five-stage pipeline assembly (raw→demosaic→wb→rgb2yuv→shape), including the wb pass-through / blk_clip bypass mux for pat_en |
| raw_2_axi4st.sv | RAW10 4px unpacking + the sensor window geometry (1944x1096 with 1920x1080 active) |
| demosaic.sv | Bayer→RGB (RGGB by default, an optional adaptive G direction) |
| wb_axis.sv | The white balance gain, **encoded 0x40 = x1.0** (the implicit raw10→8bit x4) |
| rgb2yuv_axis.sv | BT.601 full-range YUV + the **black level clamp blk_clip** (Y<24→0 and U=V=128, dedicated to the camera domain) |
| shape_video_axis.sv | The cross-domain shaping: the FIFO level management + the frame rate locking + the whole-line drain during blanking |
| pattern_gen.sv | The self-diagnostic pattern (advanced by the pclk line cadence): a gray vertical ramp / red-blue vertical bars / a gray horizontal ramp / an 8x8 checkerboard |
| apb_cam_ctrl.sv | The APB CSR, a single register CTRL@0x00, whose reset value 0xB4EBC80C produces an image at power-up |
| reset_ctrl.sv | The multi-domain synchronized reset chain |

## 4. The CSR (apb_cam_ctrl CTRL@0x00, the same register group on both chains)

```
[1:0]  bayer_phase  0=RGGB 1=GRBG 2=GBRG 3=BGGR
[2]    adaptive     demosaic adaptive
[3]    pat_en       1=the pattern source 0=the sensor (a change edge triggers a soft reset in the two camera_path domains)
[5:4]  pat_sel      0=a gray vertical ramp 1=red-blue vertical bars 2=a gray horizontal ramp 3=a checkerboard
[15:8] wb_r  [23:16] wb_g  [31:24] wb_b     (0x40=x1.0)
The reset default 0xB4EBC80C = wb 200/235/180 + pat_en=1 (a gray ramp) + adaptive=1 + RGGB
```

The writes take effect beat by beat (they change within a frame, and a source switch tears at most 1 line).

## 5. The key design decisions (the 2026-09 board-level verification history, do not regress)

1. **The pattern pclk line cadence**: the pattern_gen line advance waits for `line_tick` (tx_pixel_clk counts 550 beats then flips → an edge is taken through 2FF CDC). Each frame has 1091 lines + 34 padding beats = 618,750 pclk = exactly 60fps. The old free-running aclk had a 37ppm two-clock difference → the content drifted 2.5 lines/s = a slow scroll of the board-level pattern, which has been eradicated.
2. **The wb pass-through**: when pat_en=1 the wb is forced to 0x40. The sensor-calibration gains (200/235/180 ≈ x3.1/3.7/2.8) would turn a pattern that is encoded in display amplitude into a saturated colour cast (orange shows as yellow, blue shows as cyan, and the gray ramp turns green).
3. **The blk_clip bypass**: the rgb2yuv black level clamp (Y<24→0, UV→128) is the camera-domain FPN / dark current noise governance, and it would crush the exact code values of the dark parts of the pattern into solid black (a ~10% black plateau before the gradient). `blk_clip = !pat_en`: clamped in the camera domain, bypassed in the pattern domain.
4. **The red-blue vertical bars** (pat_sel=1): a single-channel full-amplitude 0x3C0 clamped at 255; a zero-valued station multiplied by any gain stays 0, so it is naturally immune to the wb.
5. **The three inter-frame adjustments of the shaping**: `DRAIN_CAP_LINES=54` (the whole-line drain cap during blanking) / `VFRONT_WAIT_LINES=4` (the low-level gate at the start of a frame) / `HIGH_LINES=60` (the whole-frame drop fallback). The display Vblank (45 lines) and the supply padding (34 lines) drift in phase freely, and the worst in-frame jaggedness is 79 lines > the FIFO capacity of 68.27 lines, so any fixed level band will collide — the level is nailed to the [9,55] lines and the PPM frame rate difference is absorbed frame by frame by the drained line count.
6. **The source switch soft reset**: a pat_en change edge → a ~1µs two-domain pulse reset of camera_path (the shape read/write pointers are cleared and it waits for the new source's SOF), eliminating the vertical offset of the image after a switch.
7. **The IMX415 configuration points** (imx415_init.c, with per-byte ACK checking + bounded waits):
   - The outflow order: 0x3002=0 (master start, still written first while in standby) → 0x3000=0 (release standby) → ~220ms
   - 1080p60 = VMAX 2250 / HMAX 550 / all pixels + 2/2 binning; BLKLEVEL=50
   - The 1782Mbps DPHY timing table: **the TCLKZERO high byte 0x401F=0x01 must be written**; LANEMODE 0x4001=0x03 (4-lane)
   - The "SONY magic" block must be written when VMAX/HMAX/the clock registers are still at their reset defaults (the wrong order wedges the sensor, which was observed at 0x3736)
   - The bitstream must be built with data_rate=1782 (peri.xml is already set)
8. **All the firmware I2C waits are bounded**: the BSP's `i2c_*Blocking` waits forever when the bus hangs and must not be used (the root cause frozen during the first-board bring-up); before retrying cam_en there is a 300ms hard reset + a 500ms discharge.

## 6. The firmware (sw/top_demo)

The boot flow: the self-check of both APB chains (read back 0xB4EBC80C) → `imx415_init(0)` → `imx415_init(1)` → the UART menu polling (a 0.5s tick, a 5s heartbeat printing both chains' CSRs). At power-up both chains send a gray pattern, and once the sensors are ready a key switches to the camera.

The UART menu (the BSP UART TERMINAL): `[` / `]` select the target chain cam0/cam1, and the remaining keys act only on the target chain: `c` camera / `p` pattern / `g` `o` `h` `b` select the pattern / `1-4` the Bayer phase / `z` adaptive / `q a w s e d` the wb ±16 / `x` restore the defaults / `i` echo both chains.

The key dual camera implementation: `imx415_init(id)` switches the I2C base address + the cam_en bit at runtime; the **GPIO read-modify-write is isolated per bit** (GPIO OUTPUT is a whole-word write, and writing a whole word of zeros would cut power to the other chain that is already streaming). Both chains share one I2C timing configuration (50kHz).

The build (Windows, verified):

```
Add D:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin to PATH (riscv-none-elf-gcc 13.4.0)
cd sw\top_demo && make
The product build/top_demo.hex —— loaded into the BRAM via JTAG UPDATE/RESET (this path cannot be changed)
```

## 7. The simulation and regression status

- The TB: `sim/tb_top_cam_demo.v` instantiates **top_cam (a single chain)** and includes a reference chain (raw→demosaic→wb→rgb2yuv, compared beat by beat against the DUT with `===`) + five anchors (the pattern frame period 16,666,650ns / the red-blue bar absolute value / the gray ramp R≈G≈B±3 / the wb pass-through / the blk_clip bypass).
- The latest regression logs (all **TB_PASS**): `sim/sim_pclktick.log`, `sim_redblue.log`, `sim_wbbypass.log`, `sim_blkclip.log`.
- Simulation notes: when vlog compiles everything, **the stubs use the .sv suffix** (except stub_riscv_soc.v); a full vsim regression takes ~15 minutes.
- **The dual camera top level top_cam_demo has no dedicated TB**; the u_cam_1 wiring (dphy_rx2/dphy_tx0/apb1/i2c1) has only been reviewed in code so far — it has not been simulated and has not been put on the board.

## 8. The build / programming flow

```
1. Synthesis + routing (bash): work_syn/run_efx_map.sh → work_pnr/run_efx_pnr.sh → work_pnr/run_efx_pgm.sh
   The products outflow/ws-e1-cam-ddr-csi2.bit / .hex
2. Firmware: sw/top_demo make → build/top_demo.hex → load the BRAM via JTAG UPDATE/RESET
3. On-board order: program the bitstream → the firmware runs automatically (the pattern produces the image first) → watch the UART → 'c' switches to the camera preview
```

After an RTL change a re-synthesis is required; after a firmware change only the hex has to be reprogrammed.

## 9. The current to-dos / known pitfalls

- [ ] Re-synthesize the dual camera changes + reprogram the firmware, and verify both chains on the board
- [ ] I2C1 is a fly-wire for the new chain: if cam1 gets no ACK / occasional NACK, check the pull-ups and the wire length first, and give cam1 its own `I2c_Config` if needed
- [ ] The TB is still the single chain top_cam; regressing the dual camera top level needs a new TB (the stubs + two reference chains can be reused)
- [ ] The camera mode (pat_en=0) behaves bit-for-bit identically to the old version (the wb uses the CSR values, blk_clip is enabled), so the single-chain on-board conclusion still holds
- Historical pitfalls: when vlog compiles the stub files the name needs the `.sv` suffix; the wb_axis gain 0x40=x1.0 must not be understood as a percentage; the pattern values are encoded in display amplitude (0x3C0=full amplitude) and will always saturate after the wb — which is exactly why there is a pass-through mux.
