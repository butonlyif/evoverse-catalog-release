[中文](csi_bridge_gap_sweep.md) | English

# CSI-2→HDMI Bridge Line/Frame Gap Acceptance-Window Sweep Experiment Plan

(Initiated 2026-10-19; gap injection via shape_pat_gen, implemented on the 'v' direct-injection path)

## 1. Background and Motivation

- In the v3 DDR replay architecture, camera mode made the monitor report "no input signal". Measured with the
  DIAG18 window version, the display frame rate was 55.4Hz (df/fw = 28.8/31.3 = 0.92, strictly constant across
  11 windows) — a non-standard frame rate → the bridge chip refuses to lock. Root cause located: frame_reader's
  dos_seen level latch made the reader lock to the camera's rhythm (60fps) instead of the display rhythm (60.000Hz),
  feeding ~8 extra lines per frame; the shape-gate backlog stretched frames to a self-sustaining equilibrium of
  2250+~190 ticks (fixed to dos_pulse edge-based release, awaiting board test).
- Open question: **what timing does the bridge actually accept?** Where is the Vtotal (frame rate) lower bound?
  Where is the Htotal (line period) upper bound? A fully controlled stimulus source is needed to sweep these two dimensions directly.
- The 'v' direct-injection path (shape_pat_gen → shape → TX → bridge) has been proven to output 60.000Hz;
  it is a clean stimulus point: injecting controlled gaps at the source means the bridge sees pure gap variables.

## 2. Experiment Principle

### 2.1 Mapping from knobs to bridge-visible quantities

| Knob | Unit | Line/frame period | Where the gap lands | Bridge-visible quantity |
|---|---|---|---|---|
| line gap g_l | beats (1 beat = 1 pixel_clk = **4 px**) | line period = (1100+g_l) beats | HBP stretched | **Htotal = 4×(1100+g_l) px** |
| frame gap g_f | ticks (1 tick = 1100 beats = 1 line) | frame period = 2160×line period + (90+g_f) ticks | VBP dwell stretched | **Vtotal = 2250+g_f lines** |

### 2.2 Structural guarantee of Htotal ÷4

The whole TX-side pipeline runs 4 pixels/clock (shape counts by clock, TX sends 4px per clock);
gaps are in units of clocks ⇒ **Htotal(px) = 4×clock count is always divisible by 4**, independent of
parameter values. The beat is the finest granularity physically realizable in a 4px pipeline (finer gaps do not exist).

### 2.3 Line-continuity contract not broken

The 960 in-line data beats remain back-to-back unchanged (a hard contract of shape_video_axis line emission); all
gaps land in blanking: line gaps in Hback (HBP), frame gaps in the Vback dwell (VBP).

### 2.4 Line-period uniformity (key implementation detail)

Do not "wait N ticks then wait G beats" — tick phase is fixed, and drift of the line start relative to ticks
would sawtooth the line period (1100+G alternating with 2200+G), and the bridge would see jittering Htotal.
The line-end wait uses a dual condition:

```
line-end wait state: if ((line_elapsed >= 1100 + line_gap) && tick_seen) start a new line
```

- g_l=0: degenerates to "elapsed≥1100 and a tick seen" = beat-for-beat equivalent to the current tick-anchored
  behavior, **zero regression on the 60.000Hz baseline**
- g_l>0: a window >1100 beats must contain at least one tick; the elapsed condition dominates, and the line
  period is strictly uniform = 1100+g_l beats

### 2.5 Frame-rate conversion

```
frame period(beats) = 2160×(1100+g_l) + (90+g_f)×1100
fps                 = 148.5e6 / frame period
```

Frame gap vs frame rate at g_l=0 (sweep quick reference):

| g_f (tick) | fps    | g_f | fps    | g_f | fps    |
|---|---|---|---|---|---|
| 0   | 60.000 | 100 | 57.447 | 185 | **55.428** (reproduces the lock-refusal point) |
| 25  | 59.341 | 125 | 56.842 | 200 | 55.100 |
| 50  | 58.696 | 150 | 56.250 | 250 | 54.000 |
| 75  | 58.065 | 175 | 55.670 | 300 | 52.941 |

Board reading: DIAG18 `cnt: df` (0.75s fixed window) should ≈ 0.75×fps (60Hz=45).

## 3. Design Specification (RTL)

### 3.1 shape_pat_gen.sv

- New ports: `line_gap[15:0]` (beats), `frame_gap[15:0]` (ticks)
- Line-end wait state changed to the dual condition (see 2.4); `line_elapsed` 11bit, cleared at reset,
  recounting after each `tick_seen` evaluation
- pad-segment counter 8bit→17bit: count ticks to `(90 + frame_gap)` then dispatch line 0
  (keeping the pad off-by-one-beat fix semantics: dispatch on the tick after the count completes, frame length exactly per the formula)
- Range: g_l up to 65535 beats → line period 493µs; g_f up to 65535 ticks → frame period
  ~0.5s (about 2Hz)

### 3.2 shape_video_axis.sv

- `SOF_WAIT_TIMEOUT_LINES` 90 → **1023**, `gate_wait_lines` 8→10bit
- Reason: with g_f>90, sof arrives late beyond the window every frame → timeout+fifo_flush trigger every frame,
  polluting the timing and destroying content; the experiment fails entirely below 57.7Hz. After widening, g_f≤1023 stays clean throughout
- Side effect on the abnormal path only: on true stream loss, flush recovery goes from 1.2ms to 17ms

### 3.3 apb_cam_ctrl.sv

- Adds **CTRL2 @0x08** (reusing the retired DIAG2 slot, read/write, reset 0):
  - `[15:0]` line_gap (beats)
  - `[31:16]` frame_gap (ticks)
- Write decode changed from `~paddr[2]` to `paddr[6:2] ∈ {5'd0, 5'd2}`

### 3.4 camera_path.sv / top_cam.sv

- camera_path new ports `pat_line_gap/pat_frame_gap` straight through to u_shape_pat
  (inside the DBG_SHAPE_PAT generate); top_cam brings two wires from the APB

## 4. Firmware (sw/top_demo/src/main.c + userDef.h)

- `userDef.h`: `#define CAMC_REG_CTRL2 0x08` (DIAG2 retired and promoted)
- Keys (acting on the target channel selected by `[`/`]`):

| Key | Function | Step | Granularity |
|---|---|---|---|
| `u` / `j` | frame gap +/− | GAP_FRAME_STEP = **10 ticks** | 0.267Hz per press |
| `n` / `m` | line gap +/− | GAP_LINE_STEP = **10 beats** | 40px = 0.9% of line period per press |

- Steps are `#define`s at the top of main.c; changeable and recompiled during the sweep
- Each press prints: `gap: line=%d(%dus,%dpx) frame=%d fps~%d` (line period µs,
  Htotal px, estimated fps)
- The `x` key resets defaults and clears both gaps; the CTRL2 write happens inside cam_apply,
  does not trigger the sw_src soft reset, and a mid-run value change takes effect at the next line/frame boundary
- Affects only the 'v' direct-injection source; the camera/pattern paths are untouched

## 5. Procedure (SOP)

1. Re-synthesize (RTL: shape_pat_gen/shape_video_axis/apb_cam_ctrl/
   camera_path/top_cam) + recompile firmware, power up to show the pattern
2. Press `v` to open the direct-injection source, confirm imaging (baseline 60.000Hz, `cnt: df=45`)
3. **Frame-domain sweep**: press `u` repeatedly to increase g_f; after each press observe the screen + `cnt: df`; record the blackout
   critical g_f* → the bridge's frame-rate lower bound = 148.5e6/(2475000+1100×g_f*)
4. **Adjudicate the 55.4Hz case**: if the critical frame rate >55.4Hz, it confirms camera-mode lock refusal was purely frame rate
   (the reader edge-release fix direction is correct); the g_f=185 step is exactly 55.43Hz, precisely
   reproducing the lock-refusal condition for A/B testing
5. **Line-domain sweep**: return g_f to 0, press `n` to increase g_l, record the blackout critical g_l* →
   Htotal upper bound = 4×(1100+g_l*); note the frame rate drops in sync; if the critical frame rate is still above
   the step-3 lower bound, the blackout is attributed to the H factor
6. **Combined domain (optional)**: fix a small g_l then sweep g_f to see whether the frame-rate boundary moves with Htotal
   (H/V interaction term)

## 6. Readout Table

**2026-10-19 board-test boundary determined**: step reduced to 1 tick and measured step by step —
g_f=0/1/2 (Vtotal 2250/2251/2252, 60.000/59.973/59.947Hz) **all locked**;
g_f=3 (Vtotal 2253, 59.920Hz) **no signal**. During each step df=45/45,
uflow=+1/frame (g_f lines arriving late dwelling at the sof gate), srch frozen, lost=0.
**Bridge tolerance = +2 lines = +0.089% (frame-rate lower bound 59.947Hz); the 3rd line is refused.**
=> the frame_reader edge-release fix (residual stretch ~0.1~1.4 lines) is within budget;
camera mode should lock directly.

**2026-10-19 board-test first point**: one `u` press (g_f=10 → Vtotal 2260, 59.729Hz)
already black-screened with no signal; **pressing `j` back to g_f=0 restored imaging immediately** (blackout is not sticky; the bridge
re-locks at 60.000Hz instantly, so the sweep can iterate fast). The board-side evidence chain is fully self-consistent: df=45,45,
45,44,44 per 0.75s window (=44.78 frames, exact against theory), uflow+31 per 0.5s window (1 gate dwell per frame
= sof 10 lines late), srch frozen (line alignment zero damage), lost=0 (the FPGA
sent a clean complete stream).

| Observation | Conclusion | Next step |
|---|---|---|
| g_f* corresponds to ~55-56Hz | lock refusal purely frame rate, matching the 55.4Hz measurement | board-test camera mode (after edge release it should lock at 59.95+) |
| g_f* very small (1~10) | tolerance extremely tight (<1%), doubt on the 59.95Hz fix margin | g_f=1 passes => reader fix suffices; black => reader needs pre-dispatch (blanking-start pulse + reader de-ticked follow) |
| black screen as g_l grows while frame rate still sufficient | bridge does not tolerate Htotal stretch | archive; check current timing H margin (HBP=296px fixed, no stretch risk) |
| large g_l acceptable | bridge H tolerance wide | archive the boundary values |
| any g_f>0 black-screens immediately | bridge, once locked, tolerates no frame-rate drift, or no VBP stretch | re-test with g_f injected on the VFP side (Vfront segment) |

## 7. Known Limitations

- As the line gap grows the frame rate drops in sync (2160 lines × per-line increment); the H dimension is not independent —
  interpretation must be cross-checked against the frame-rate lower bound obtained in step 3
- With the gate-dwell timeout widened to 1023 lines, display recovery from true stream loss slows (17ms);
  only the abnormal path is affected
- This experiment sweeps only the "steady-state acceptance window"; it does not cover jitter/phase/per-frame drift lock-refusal mechanisms
  (that class is judged separately by the stability of DIAG18 df window readings)
- Gap changes during run take effect from the next line/frame boundary, no soft reset, no tearing at the switch instant
