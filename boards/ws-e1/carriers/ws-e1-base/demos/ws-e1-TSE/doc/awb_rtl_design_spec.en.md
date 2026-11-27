[中文](awb_rtl_design_spec.md) | English

# IMX415 Camera Link RTL Auto White Balance (AWB) Design Specification

Version v1.0 (2026-11-09) · Status: pending review · Constraint sources: `rules-rtl-style.md`, `rules-efinity-hard.md`

---

## 1. Overview

### 1.1 Background and Goals

White balance gains on the G11n17 camera link are currently computed per frame in software by the PC viewer's
`auto_gains` (doc/pc_tools/raw10_viewer.py); the board-side RTL chain (raw10 reassembly → in-group reverse ordering →
FIFO → UDP) is color-unaware. This design moves the AWB closed loop into the FPGA: **statistics, gain computation,
and gain application are all done in hardware**, converging automatically every frame, ready at power-on,
with no dependence on any CPU/software participation.

The algorithm baseline is the board-verified viewer `auto_gains` (neutral bright blocks as the primary criterion);
fixed-point and RTL simplifications are annotated item by item (§3.5).

### 1.2 Non-Goals

- No color-temperature prior (CCT curves), CCM, or full SoG(p=6) estimation — listed as v2 extensions (§9.2)
- No exposure control (AE) — SHR0/gain registers remain managed by the imx415_rom.sv sequence
- No changes to the UDP transmit chain or PC viewer (the viewer's --wb/--autowb are no longer necessary for the RTL
  version's picture, but manual override capability is retained)

## 2. System Position and External Interfaces

### 2.1 Position in the Data Flow

```
MIPI RX → raw_2_axi4st(40bit) → [in-group pixel reversal src mux (existing)] → ★AWB★ → column FPN (optional) → demosaic/direct-out
```

AWB operates in the **camera 200MHz pixel domain**, Bayer RAW10, 4 pixels/clock, 40-bit valid data.
The pattern stream (raw10_pat_src) bypasses AWB (`awb_bypass_i`; the patterns carry exact colors and need no correction).

### 2.2 Port Definition (top level `awb_top`, suggested instance name `u_awb`)

```systemverilog
module awb_top #(
    parameter int GAIN_FRAC = 12,      // gain Q4.12 fractional bits
    parameter int STAT_DECIM = 4       // statistics row decimation (sample every 4th row, same as viewer)
)(
    input  wire        cam_clk_i,      // 200MHz camera pixel domain
    input  wire        rst_n_i,        // async reset (in-domain sync release, reusing the link's existing rst_sync)
    input  wire [39:0] pix_i,          // {p3,p2,p1,p0}, 10bit each, after in-group reversal
    input  wire        pix_valid_i,    // 4 pixels per clock beat
    input  wire        frame_sync_i,   // frame-start pulse (1 clk, aligned to frame start)
    output wire [39:0] pix_o,          // 4 pixels after gain
    output wire        pix_valid_o,
    // CSR (reuses the link's existing register bus style)
    input  wire        csr_en_i,       // bit0: AWB enable; 0=bypass pix_i straight to pix_o
    input  wire        csr_manual_i,   // bit1: 1=manual gain mode (uses csr_gain_i)
    input  wire [47:0] csr_gain_i,     // 4×12bit manual gains {B,Gb,Gr,R}
    input  wire [3:0]  csr_speed_i,    // EMA convergence speed shift (default 4 → 1/16)
    input  wire [23:0] csr_thr_i,      // {bright_thr[11:0], min_blocks[11:0]}
    output wire [11:0] dbg_gain_r_o,   // debug readback: current 4-channel gains
    output wire [11:0] dbg_gain_gr_o,
    output wire [11:0] dbg_gain_gb_o,
    output wire [11:0] dbg_gain_b_o,
    output wire [1:0]  dbg_mode_o      // 0=idle 1=stats 2=compute 3=compute_ovf
);
```

Interface notes:
- `pix_i` must be the pixel sequence after in-group reversal repair (RGGB intrinsic phase: even rows {R,Gr}, odd rows {Gb,B});
  sub-plane attribution for statistics is located directly by (row parity, column parity)
- `frame_sync_i` is brought out from the link's existing frame-start alignment signal (a timing point already exists at
  the magic-number detection); if no ready-made signal exists, self-generate it with row/column counters at position (0,0); the spec is unchanged
- No CDC: statistics, computation, and application all live in the `cam_clk_i` domain; **no cross-clock paths are introduced**

## 3. Algorithm Specification (fixed-point definitions)

### 3.1 Stage One: Per-Frame Statistics (STREAM state, accumulated live with the pixel stream)

For each 2×2 Bayer block (one beat = 4 pixels = exactly one complete block):

1. Luminance `L = (p0 + p1 + p2 + p3) >> 2`, where p is the 10-bit raw value (before gain multiplication)
2. Decimation: `STAT_DECIM=4`; only block rows with row number mod 4 == 0 are counted (consistent with the viewer's `f[::4]`;
   static statistics are insensitive to decimation, saving 3/4 of the adders/comparators)
3. **Neutral bright-block test** (RTL simplification: fixed threshold replacing the viewer's 85th percentile):
   - `THR_BRIGHT <= L < 1010` (upper bound excludes saturated blocks)
   - `max(p) - min(p) <= 20% × L` (chroma-neutral across the four channels; 12-bit comparator + barrel max/min)
4. Blocks judged neutral: the 4 channel accumulators accumulate p0..p3 respectively, neutral block counter `n_neutral++`
5. **Fallback statistics run in parallel** (unconditional accumulation, zero extra logic cost): 4 full-frame sub-plane
   accumulators + total block counter `n_total` — when neutral blocks are insufficient, switch the data source directly; no second pass

Accumulator width: max block count 1080/4×1920/4 = 129,600 (after decimation), 40×129,600 < 2²³,
so **24-bit accumulators** (with 4× headroom).

### 3.2 Stage Two: Gain Computation in the Frame Blanking Interval (COMPUTE state)

Trigger: end of frame (last-pixel beat + 1); serialized within the blanking interval (≥56 rows ≈ 107k clk):

1. **Data source selection**: `n_neutral >= MIN_BLOCKS` (default 1296, i.e. 1% of decimated blocks) → use the neutral-block
   means (true white-block criterion); otherwise use the full-frame sub-plane means (gray-world fallback, same as the viewer fallback logic)
2. **Means**: `mean_ch = acc_ch >> log2(n)`, with n approximated to a power of two (floor(log2) of n;
   error <2×, absorbed by the EMA — the first simplification replacing true division)
3. **Anchor on the brightest channel**: `target = max(mean_ch)`, others `gain_t_ch = target / mean_ch`
   — a 12bit/12bit restoring-division state machine; one divider computes serially 3 times (the brightest channel's gain is
   always Q4.12=4096); the blanking interval has ample time (1 bit per beat, 24 beats/run + shift alignment)
4. **Clamping**: 0.25..4.0 → Q4.12 [1024, 16384]
5. **EMA smoothing** (frame to frame): `gain_new = gain_old + (gain_t - gain_old) >> csr_speed_i`
   (default speed=4 = 1/16 per frame; converges to 90% in 0.33s at 30fps — magnitude equivalent to the viewer's speed=0.1)
6. **Fail-safe**: `n_total == 0` (black field) or mean < 1 → keep the old gains unchanged

### 3.3 Stage Three: Gain Application (along with the pixel stream)

Each pixel is multiplied by the gain of its sub-plane channel (4 DSPs, 10bit × 13bit → 23bit, take [21:12] = 10bit,
saturate/truncate to 1023). In manual mode (`csr_manual_i`) `csr_gain_i` is used directly; statistics/computation still run
but gains are not updated (for easy debug observation). `csr_en_i=0` fully bypasses (combinational passthrough + output register beat).

### 3.4 Fixed-Point Summary

| Quantity | Format | Range | Width |
|---|---|---|---|
| Channel gain | Q4.12 | 0.25..4.0 | 13b (1 sign bit always 0 + 4 integer + 12 fraction)|
| Pixel | u10 | 0..1023 | 10b |
| Product | u23 | — | truncate [21:12] back to u10 |
| Channel accumulator | u24 | ≤ 5.2M | 24b |
| Block count | u18 | ≤ 129,600 | 18b |
| EMA | Q4.12 | shift-implemented | 13b |

### 3.5 Divergences from the Viewer Algorithm (board-test regression risk points)

| Viewer behavior | RTL version | Risk and mitigation |
|---|---|---|
| Bright-region 85th-percentile adaptive threshold | Fixed THR_BRIGHT (CSR-configurable, default 700) | Dark scenes may never trigger neutral blocks→gray-world fallback; tune after board testing |
| EMA speed=0.1 floating point | Shift 1/16 (CSR 4..8 configurable) | Magnitude equivalent, low flicker risk |
| Gray-world fallback includes complementary-color bias | Also full-frame mean fallback | Known limitation (monochrome scenes), improved by v2 SoG |
| Gain white-block clamp/mask re-estimated per frame | Neutral test with fixed threshold | Grass/white-lamp scenes need board-test regression (§7 scenarios V3/V4)|

## 4. State Machine

```
STATS →(frame end)→ COMPUTE(division×3+EMA) →(done|blanking over)→ STATS
BYPASS(csr_en=0) and MANUAL do not change the state machine; only the output mux and gain-update gating change
```
One-hot encoding, `(* fsm_encoding = "one-hot" *)`; COMPUTE overflow protection: if not finished before the blanking
interval ends → discard this round's result and keep the old gains (reported as dbg_mode_o=3).

## 5. Reset and Attributes

- Reset: `rst_n_i` is the link's existing clock-domain sync-release reset (PLL lock gated; §4/§8 hard constraints
  already satisfied); no second sync chain inside the module; reset only for control logic, accumulators cleared at frame boundaries
- Accumulator/gain registers: no high-fanout risk (<50); the 4 gain DSP outputs are registered
- No BRAM / no divided clocks / no cross-domain paths

## 6. Resource and Timing Budget

| Item | Estimate |
|---|---|
| LUT | ~1.2k (statistics comparators + accumulation + division state machine + CSR)|
| DSP | 4 (gain multiplication; division implemented with shift-subtract, no DSP used)|
| FF | ~800 (accumulators + gains + state machine)|
| Timing | Critical path = gain multiply 10×13 DSP + saturation, registerable inside the DSP at 200MHz; statistics path max/min→compare→accumulate-enable, ≤ 8 LUT levels, no pressure |

## 7. Verification Specification

**Reference model**: Python/numpy (reusing the viewer `auto_gains` statistics criterion + this spec's §3 fixed-point
semantics); the testbench compares gains per frame (tolerance ±1/4096) and output pixels (tolerance ±1 LSB).

| ID | Scenario | Expected |
|---|---|---|
| V1 | 8 color bars (expected_image aligned to RGGB) + neutral white region | Converges to {R,B compensation}, matching the reference model |
| V2 | Full-frame gray gradient (no neutral blocks) | n_neutral=0 → gray-world fallback, gains≈all 1 |
| V3 | Synthetic "grass" monochrome stream (G dominant) | No divergence, clamping effective, color cast ≤ the fallback's inherent level |
| V4 | White-lamp scene frame sequence (recorded board-level RAW replay) | Convergence target differs from the viewer --autowb result by < 10% |
| V5 | Gain transient (WB ground truth changed artificially) | EMA converges in 0.33s, no overshoot oscillation |
| V6 | Black field / single-frame interruption | Gains held, dbg_mode_o correct |
| V7 | BYPASS/MANUAL mode switching | Pixel passthrough lossless, manual gains take effect immediately |

Suggested simulation level: FPGA_FUNCTIONAL (algorithm-class module, no hard-IP interaction); Native Build and board-level
verification proceed independently and are not waived by a simulation PASS.

## 8. Open Decision Items (to be decided at review)

| ID | Decision | Recommendation |
|---|---|---|
| D1 | Whether the fixed THR_BRIGHT of 700 covers the current indoor lighting | Decide after board test V4; if necessary upgrade to the 85th-percentile histogram version (+1 BRAM)|
| D2 | Whether the SoG(p=6) fallback enters v1 | No (^6 accumulation is 30bit×4 channels, low benefit/cost ratio); revisit in v2 depending on V3 board results |
| D3 | Frame sync signal source (reuse magic-number detection vs self-generated counter) | Self-generated (simpler to implement, spec unchanged)|
| D4 | Whether the pattern stream also passes through AWB | No (bypass); the pattern colors are the design ground truth |
