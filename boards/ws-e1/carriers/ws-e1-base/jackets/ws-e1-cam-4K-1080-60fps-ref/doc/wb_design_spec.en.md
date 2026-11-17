[中文](wb_design_spec.md) | English

# RAW10 Domain White Balance Design Specification

| Item | Value |
|---|---|
| Version | **v0.2 (implementation complete, board-level verification pending)** |
| Date | 2026-10-24 |
| Status | The RTL/CSR/firmware/TB are implemented; the board-level bring-up is pending |
| Changes | v0.1→v0.2: the default value changed to the neutral 1.0 (R7 overturned, the board-proven image with 200/235/180 turned green); the wb_axis exit path changed to rgb10_to_rgb8 (landed as Q3); the interface gained bayer_phase; the line parity now takes effect within the same beat (§3.2); the sideband shift depth was corrected (§3.3) |
| Related | `rtl/raw_wb_axis.sv` (newly created), `rtl/rgb10_to_rgb8.sv` (newly created), `rtl/wb_axis.sv` (retired, kept for the TB only), `rtl/demosaic.sv` (downstream), `rtl/apb_cam_ctrl.sv` (the CSR), `sw/top_demo/src/main.c` (the firmware), `doc/program.md` (deployment/menu) |

## 0. Background and goals

The v4 chain (before the change):

```
CSI -> raw_2_axi4st -> frame_writer -> DDR -> frame_reader playback
     -> [demosaic] -> wb_axis(RGB10->RGB8) -> rgb2yuv -> shape -> display
```

The current WB is after demosaic (`wb_axis.sv`): an 8bit gain with an implicit ×4 encoding (U2.6, `0x40=1.0`), and the `(v10*g)>>8` shift simultaneously absorbs the RAW10->8bit ÷4. The board-labelled default 200/235/180 produced a green image in measurement (the calibration failed), so the white point must be re-labelled.

**This document lands (the v5 chain): the WB moves ahead of demosaic into the RAW10 domain, and wb_axis exits the path entirely** — a new module `raw_wb_axis` is inserted between the replay stream and demosaic, and the output is still AXIS-40 RAW10; the 10->8bit quantization after demosaic is taken over by the new pure quantizer `rgb10_to_rgb8` (`v8 = v10 >> 2`, bit-exactly equivalent to wb_axis@0x40):

```
CSI -> raw_2_axi4st -> frame_writer -> DDR -> frame_reader playback
     -> [raw_wb_axis(RAW10 gain)] -> [demosaic] -> rgb10_to_rgb8
     -> rgb2yuv -> shape -> display
```

Motivations:

- D1 The demosaic guide interpolation (the G direction judgement at the R/B sites) implicitly assumes that the inter-channel gains are already correct
- D2 The downstream CCM / colour domain convention comes after the WB
- D3 The multiplications per beat drop from 12 (4px×3ch) to 4 (4px×1ch, since in Bayer each pixel belongs to exactly one channel)
- D4 A 10bit domain: the old chain quantized to 8bit immediately after the WB, and the new chain places the gain before the quantization
- D5 Future AWB: the channel statistics are naturally collected in the RAW domain, and the source of the gain is the write point

## 1. Requirements

| # | Requirement |
|---|---|
| R1 | Per-channel gains for the three R/G/B paths; Gr/Gb share G (v1 does not split the green imbalance) |
| R2 | The gain fixed-point format is **U4.12** (16b = 4 integer + 12 fractional bits), range [0, 15.99976], resolution 1/4096 |
| R3 | The output is still RAW10 AXIS-40; the bit width/handshake/sideband semantics are unchanged, and demosaic has zero changes |
| R4 | Runtime tunable: the UART menu keys `[q/a][w/s][e/d]` and the step (unchanged) (±16 = ±0.25 gain) |
| R5 | The channel determination is bit-for-bit identical to the demosaic site class (the same `c_of` function; the line parity truth takes effect within the same beat, see §3.2) |
| R6 | When `pat_en=1` (the pattern source) all channels are unity, a **bit-exact pass-through** (the pattern is already encoded in display amplitude, the v4.10c board conclusion) |
| R7 | **The reset default = neutral 1.0 on all channels (0x1000×3)**. The old board labels 200/235/180 are deprecated (the board-proven image turned green); after the white point is re-labelled through the menu the software writes it back (§2.3) |
| R8 | Independent gains per chain (reusing the per-instance `apb_cam_ctrl`, cam0=APB0 / cam1=APB1 are naturally separated) |

Non-goals (v1): the AWB automatic gain loop, independent Gr/Gb gains, and precision optimization for gains <1.0 (writing them is allowed, with a note about the precision loss).

## 2. The fixed-point specification (U4.12)

### 2.1 Encoding

```
g_fp[15:0] = round(g × 4096)        // U4.12, unsigned
1.0 = 0x1000    1.25 = 0x1400    15.99976 = 0xFFFF
```

### 2.2 The data path mathematics

```
p    = pix[9:0] × g_fp[15:0]        // a 26b product (1023×65535 < 2^26)
q    = (p + 12'h800) >> 12          // +2048 for rounding
out  = (q > 10'h3FF) ? 10'h3FF : q  // saturate at 1023
```

- A bit-exact pass-through at 1.0: `(v×4096 + 2048) >> 12 = v` (v<<12 and 2048 have no carry overlap)
- Saturation equivalence: the old chain clamps 8bit 255 ⇔ the new chain clamps 10bit 1023, and the limiting knee differs by ≤1 LSB

### 2.3 The reset default (R7, the v0.2 revision)

**Neutral 1.0 on all channels (0x1000)**. The v0.1 "equivalent migration" derivation (the old board labels F={200,235,180} U2.6 → g_fp={0x3200, 0x3AC0, 0x2D00}) is **void**: that old calibration produces a green image in measurement on this board, and an equivalent migration would only carry the wrong calibration as-is into the new domain. The v5 comes up with a neutral white balance, and after the white point is re-labelled through the UART menu (`q/a/w/s/e/d`, ±0.25 per key) the software writes it back to the CSR.

The firmware shadow keeps U2.6 (1.0 = 0x40 = 64), and when writing the CSR it shifts up to U4.12 with `<<6` — a pure shift, with the same key step semantics as the old version.

### 2.4 Precision statement

The pixel is 10bit (1024 quantization levels), and a gain resolution beyond 1/4096 is drowned by the pixel quantization noise; U4.12 is already an over-design, and a higher format (such as U16.16) brings no image quality benefit on this path, only multiplier cost (the review conclusion of 2026-10-24).

## 3. The microarchitecture (rtl/raw_wb_axis.sv, implemented)

### 3.1 The interface

```systemverilog
module raw_wb_axis (
    input  logic         aclk,          // tx_pixel_clk (the same domain as demosaic)
    input  logic         aresetn,       // pixel_rst_n
    // RAW10 AXIS-40 slave port (no tready, bubbles = line/frame blanking)
    input  logic [39:0]  s_axis_tdata,  // 4×RAW10, px0 in the LSB
    input  logic         s_axis_tvalid,
    input  logic         s_axis_tlast,  // EOL
    input  logic [2:0]   s_axis_tuser,  // {eof, sol, sof}
    // Bayer phase (the CSR domain, the same source and value as demosaic's cp_bayer_phase)
    input  logic [1:0]   bayer_phase,   // 0=RGGB 1=GRBG 2=GBRG 3=BGGR
    // Gains (quasi-static in the CSR domain, following the wb_axis convention; U4.12, 1.0=0x1000)
    input  logic [15:0]  wb_r, wb_g, wb_b,
    input  logic         pat_bypass,    // 1 = unity pass-through (connected to cp_pat_en)
    // RAW10 AXIS-40 master port
    output logic [39:0]  m_axis_tdata,
    output logic         m_axis_tvalid,
    output logic         m_axis_tlast,
    output logic [2:0]   m_axis_tuser,
    // Observation
    output logic [15:0]  dbg_sat        // the beat count containing saturated pixels (a 16b free counter, DIAG21)
);
```

There are no geometry parameters — it is pure beat-by-beat processing and is insensitive to GW/LINES (the geometry is determined by the upstream `raw_2_axi4st` parameters).

### 3.2 The phase generation (R5, bit-for-bit identical to demosaic)

`c_of` is copied bit-for-bit from `demosaic.sv` (L417-426), with parity anchoring: the first line of each frame = the even line = the R line of RGGB (that convention has been confirmed on the board through the camera preview colours). Each beat's 4 pixels cover only 2 channel classes (`cp = the pixel bit within the beat`, px0/px2 share gA and px1/px3 share gB).

The line parity implementation (corrected in v0.2):

```systemverilog
// Registered state: cleared on the sof beat, flipped on the sol beat (sof wins if they coincide)
// Takes effect within the same beat: row_cur = the value after the sol/sof beat combination flips
wire row_cur = s_axis_tvalid ? (tuser[0] ? 1'b0 :
                                tuser[1] ? ~row_p : row_p) : row_p;
```

**The registered value is not used directly for the lookup** — the sideband and the data are in the same beat, and using `row_p` directly would make the first beat of each line use the previous line's parity (the first 4 pixels of a line would have the wrong colours). `row_cur` is consistent with demosaic's rp = the real content line parity.

### 3.3 The data path (an S0 multiplication + an output register, 2 stages in total)

- 4 lanes in parallel: `(pix × gX[15:0] + 2048) >> 12`, saturated at 1023, registered at S0
- `pat_bypass=1`: gX is forced to `0x1000` (a bit-exact pass-through, including the sideband)
- The sidebands tlast/tuser shift at the same depth as the data (**2 stages**); on bubble beats (tvalid=0) the sidebands are cleared and do not leak past the bubble — the original `wb_axis.sv` L88-114 (if the data is 2 stages then the sideband must also be 2 stages; the first version was misaligned by one beat and was corrected after the unit TB caught it)
- Resources: 4 × 10×16 multiplications @148.5MHz single-cycle, no RAM

### 3.4 The quasi-static gain CDC convention

The gains are multi-bit in the CSR domain (pclk) entering the tx_pixel_clk domain directly, following the existing `wb_axis` convention (a quasi-static signal that is not rewritten has no metastability window; at the instant the menu rewrites it a single-frame-level glitch is allowed, which is consistent with the current situation and no additional synchronizer is added).

## 4. The top-level integration (top_cam.sv, the tx_pixel_clk domain, implemented)

```
frame_reader playback -> rd_t*[39:0] slicing -> raw_wb_axis -> dms_in_t* -> demosaic
demosaic(RGB10) -> rgb10_to_rgb8(RGB8) -> rgb2yuv
```

- The insertion point: `dms_in_tdata / cdc_valid / dms_in_tlast / dms_in_tuser` are now driven by the `raw_wb_axis` master port (previously connected directly to the replay stream slicing); the fingerprint probe B (DIAG9, observing `dms_in_t*`) keeps its original wiring, and its semantics become "the data after the WB" (the continuity monitoring is unaffected)
- `pat_bypass = cp_pat_en` (the pattern source pass-through); `bayer_phase = cp_bayer_phase`
  (the same source as demosaic)
- **wb_axis retires**: top_cam no longer instantiates it; between demosaic -> rgb2yuv, `rgb10_to_rgb8` (AXIS-120 -> AXIS-96 pure quantization, `v10[9:2]`) takes over. The wb_axis.sv file is kept — the tb_phase4/tb_phase4_ddrm/tb_phase5_cam1/tb_dms_feed platform chains still reference it (those TBs build their own chain without top_cam and are decoupled from this change)
- The old CTRL[31:8] wb fields retire: the CSR fields/ports are kept (layout compatibility), both the reset and the software write 0x40, and there is no hardware consumer (`cp_wb_r/g/b` are dangling)

## 5. The CSR / firmware (implemented)

### 5.1 The registers (apb_cam_ctrl.sv, per-instance)

| Register | Address | Fields | Reset value |
|---|---|---|---|
| WB_RAW0 @0x54 (word 21, RW) | `[15:0]` wb_r_raw U4.12 | 0x1000 | `{wb_g, wb_r}` = 32'h1000_1000 |
| | `[31:16]` wb_g_raw U4.12 | 0x1000 | |
| WB_RAW1 @0x58 (word 22, RW) | `[15:0]` wb_b_raw U4.12 | 0x1000 | 32'h0000_1000 |
| | `[31:16]` reserved | 0 | |
| DIAG21 @0x5C (word 23, RO) | `[15:0]` the beat count containing saturated pixels (a 16b free wrap-around) | — | 0 |

Words 21-23 were previously idle (the highest decoded word was 20 @0x50), the write decoding is extended with `paddr[6:2] == 5'd21/5'd22`, and the read decoding gains three lines. The CTRL_RESET parameter changes to `32'h4040_4014` (the retired wb fields occupy 0x40×3; pat_sel=01, pat_en=0, adaptive=1 and phase=0 are unchanged). Under a neutral gain DIAG21 should be near 0; a continuous growth = the gain is too high and clamps at 1023.

### 5.2 The firmware (userDef.h + main.c, implemented)

- The shadow variables keep the 8bit U2.6 domain: `clamp8` and the `±16` step (= ±0.25 gain) are unchanged; `CAMC_DEFAULT_WB_*` changes to **64** (= 1.0)
- The conversion when writing the CSR (`cam_apply`): `WB_RAW0 = {wb_g<<6, wb_r<<6}`, `WB_RAW1 = wb_b<<6` (U2.6 × 64 = U4.12, a pure shift)
- `cam_pack`: the CTRL wb fields always write 0x40 (`CAMC_WB_RETIRED`, the retired fields have no consumer)
- The self-check print expectation changes to `0x40404014`; `cam_show` gains wb_raw0/1 and DIAG21 readback

## 6. Verification (the part already executed)

| # | Item | Status |
|---|---|---|
| V1 | Unit TB `sim/raw_wb_tb.sv`: a cycle-by-cycle comparison against an independent reference model (a standard Bayer 2x2 position table + the spec formula). T1 unity bit-exact + random bubbles, T2 four phases × different gains, T3 saturation clamping + dbg_sat accounting, T4 rounding boundary points (0.5x/1.00024x), T5 pat_bypass forcing unity; the sidebands are aligned cycle by cycle including no leakage past bubbles | **PASS (8/8 cases, errors=0)** |
| V2 | The channel assignment cross-check: the T2 reference model uses an independently written {row,col} position table (not a transcription of c_of), including the first beat of a line — preventing a line parity polarity drift | **Merged into T2, PASS** |
| V3 | Regression: tb_phase4 is all green (P4-OK/P4C-OK/SLOW-OK, the content is bit-identical with err=0); that TB family builds its own chain and instantiates wb_axis directly, without top_cam/raw_wb, so the nature of the regression is "the platform chain was not collaterally damaged". tb_phase4_ddrm / tb_phase5_cam1 are isomorphic and were not run, so the risk is low | **phase4 PASS** |
| V4 | Board level: ① the power-up neutral white balance produces an image (no colour cast); ② the menu ± tuning and 'x' reset back to neutral; ③ the 'g' pattern path shows no change at all (pat_bypass); ④ under neutral DIAG21 is near 0, and after adding gain it agrees with the highlight distribution | **Pending the board level** |

## 7. The settled questions (the v0.1 review conclusions)

| # | Question | Conclusion |
|---|---|---|
| Q1 | The default value strategy | **Neutral 1.0** (the v0.1 equivalent migration plan is void: the old labels 200/235/180 produce a green image in board measurement, and the white point is re-labelled through the menu) |
| Q2 | The DIAG21 saturation count | **Included in this version** (observing the highlight clipping after writing a large WB_RAW gain is useful; the unit TB T3 reconciles it) |
| Q3 | The retirement form of the old CTRL[31:8] wb fields | **The fields are kept, the software always writes 0x40, and the RTL consumer is removed** (wb_axis exits the path and the quantization role is split out to rgb10_to_rgb8; this is more thorough than the v0.1 "bind 0x40 and keep it in the path" — there is no surface for double gain stacking) |
| Q4 | The V3 regression baseline | **No golden impact** (the phase4 TB family builds its own chain and instantiates wb_axis, without top_cam; phase4 has already been run and confirmed all green) |
| Q5 | The U16.16 control plane | Not introduced for now; the CSR directly accepts U4.12, and a future AWB can quantize with `>>4` at the CPU boundary |
