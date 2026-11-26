[中文](milestone-v4.10c3m.md) | English
# Milestone: v4.10c3m — problem B closed + camera_path flattening

Date: 2026-10-22
Status: **board-test usable baseline (output confirmed)**. Problem B (fixed offset + bottom flicker band) is closed on the board,
and after flattening the whole chain simulation/bitstream generation are all green. Outstanding: A (occasional switching tearing), D (top 2-line rolling, paused).

Purpose of this document: complete design archive, supersedes [milestone-v4.10c3f.md](milestone-v4.10c3f.md).
If a later change introduces a regression, roll back to this version per §10.

---

## 1. Version Identification

| Item | Value |
|---|---|
| Version | v4.10c3m |
| bitstream | `outflow/ws-e1-cam-ddr-csi2.bit` (built 2026-10-22, map/interface/pnr/pgm all PASS) |
| Top level | `top_cam_demo` (Titanium TJ180A484S, Efinity 2026.1) |
| Regression | `sim/v410c3m_reg.log`: P4-OK + P4C-OK + SLOW-OK all green, Errors=0 |
| Key files | `rtl/top_cam.sv` (flattened netlist) `rtl/top_cam_demo.sv` `rtl/frame_writer.v` `rtl/frame_reader.v` `rtl/pattern_gen.sv` `sim/tb_phase4.sv` |
| Deleted | `rtl/camera_path.sv` `rtl/shape_video_axis.sv` `rtl/async_path_fifo.v` `rtl/replay_pat_gen.sv` |

---

## 2. System Architecture and Data Flow

Dual IMX415 CSI-2 cameras → DDR frame-buffer replay → MIPI CSI-2 TX to the panel (4K@60).
cam0 = active chain (DDR replay), cam1 = passive reserve (rd input tied to 0).

**v4.10c3m flattening**: the camera_path layer is deleted, the former DISP_V4=1 netlist moves straight into top_cam.sv;
the DISP_V4=0 branch (shape_video_axis / async_path_fifo / replay_pat_gen) retires along with
its files. The only display-shaping path = tx_line_buf + disp_timing (v4 chain,
unified for cam0/cam1).

```
IMX415 ──CSI-2──> my_csi2_rx (64b Generic Frame Mode, RAW10 low 40b valid)
                    │
 pattern_gen ────────┤  top_cam source mux (CSR CTRL[2] pat_en)
                     │  + switch-in gate sw_gate (c3b) + power-on boot (c3d)
                     v
               raw_2_axi4st (40b AXIS, sliding window/DT gating)   [raw domain 200M]
                     │
                     │ {24'h0, tdata[39:0]} zero extension (cap assignment, v4.10 attach convention)
                     v
               frame_writer (top_cam_demo, aclk=200M)
                  512b integral packing; line 7680B = 64+56 two bursts; whole frame or nothing
                     v
               LPDDR4X dual-bank frame ping-pong
                 FRAME_A=0x0 / FRAME_B=0x0200_0000 (c3k fix); line slot 8KB
                     v
               frame_reader (top_cam_demo, aclk=pixel_clk 148.5M)
                  8-beat slice per word; c3g residual-frame abort + c3h anchor window (ANCHOR_WAIT=78)
                     │ rd_t* straight through (same clock as pixel_clk, no CDC; wiring layer slices [39:0])
                     v
  top_cam inline flattened netlist (c3m):
    demosaic (RAW10→RGB×4px) → wb → rgb2yuv (UYVY 64b)
                     │
    shape_pat_gen direct-injection mux (DBG_SHAPE_PAT compile-time + CSR CTRL[6] run-time)
                     v
    tx_line_buf (DEPTH_WORDS=2048) → disp_timing (LINE_CLKS=1100,
    FRAME_SLOTS=2250/1125) → my_csi2_tx → bridge chip → panel
```

- Two reset domains: raw domain `raw_aresetn = sys_clk_200m_rstn & sw_rstn`;
  pixel domain `pixel_rst_n = tx_pixel_clk_rstn & sw_rstn_tx`.
- **The entire ISP-chain algorithm (demosaic/wb/rgb2yuv/tlb/disp_timing) is untouched since v4.9d**;
  c3g~c3m touch only the reader grant/reset, the pattern diagnostic source, the DDR base addresses and the structural flattening.

---

## 3. Key Parameters

| Parameter | Value | Note |
|---|---|---|
| Resolution/frame rate | 3840×2160 @ 60Hz target | the display frame rate is affected by the supplied line count through the frame-head level gate (see §7-D) |
| cam0 display slots | DISP_FRAME_SLOTS=2250 | VSP10+VBP72+VACT2160+VFP8+pad0 (CTA 4K60 standard values) |
| cam1 display slots | DISP_FRAME_SLOTS=1125 | 1080p60 (parameterized from c3m on, overridden at the instantiation site) |
| RAW10 source line (cam0) | 960 beats × 40b = 3840px | LINE_TOTAL_PIX=3864, LEAD/TRAIL=12, SKIP_FIRST=21 |
| 64b replay line | 120 words (7680B) = 967 emission beats | WB0=64 + WB1=56 beat |
| Frame layout | A=0x0, **B=0x0200_0000** | c3k fix; word-for-word identical in both u_fw/u_rd; capacity accounting in ddr_interface.md §9 |
| ANCHOR_WAIT | 78 (board) / 4 (tb) | c3h anchor window = VSP+VBP(82) − margin 4 |
| Clock domains | sys_clk_200m (raw/writer) / pixel_clk=148.5M (display/reader/ISP/TX) | reader v4 has changed domain, no CDC inside the chain |
| CSR switching | 'c'=camera 'p'=pattern, CTRL[6]=dbg direct injection | takes effect at the frame boundary; a CTRL[6] change edge also triggers the source-switch soft reset |

---

## 4. Core Mechanisms

### 4.1 writer: whole frame or nothing (v2 architecture, unchanged)
- A bad frame is closed **without flipping par and without publishing**; frame full → flip par + publish `wr_frame_done` for a single beat.
- **frame_par is the only bank arbitration anchor between writer and reader**: the writer always writes par, the reader
  always reads ~par. Any logic that clears or alters par introduces a same-bank read/write conflict (c3d lesson).

### 4.2 Frame-level arbitration (reader, v4.9 architecture + c3g/c3h fixes)
- `wr_frame_done` 2FF edge-taken = frame request; **start gate done_cnt>=2** before release.
- **Grant anchor = disp_sof falling edge**; edges piling up → drop; no edge → repeat.
- **c3g residual-frame abort**: if at the anchor beat the reader is still emitting the previous frame's residual lines (st!=S_IDLE),
  the frame_grant would be missed because the edge lasts only one beat → it is accepted only after the disp_stall rescue → the new frame's line 0 is consistently
  late by D lines → the frame-tail GATE freezes D lines = **fixed offset + bottom flicker band** (the deadlock structure of problem B;
  tb measured line 0 issued only 94.6 lines after the anchor, vs 6 lines when the display starts pulling Va[0]). Fix: at the anchor beat
  `abort_frame` returns to S_IDLE and cuts the stream + `pend_grant` parks this anchor's grant, then the grant is accepted as soon as the read path is quiet
  (r_quiet) → line 0 comes ~90 lines earlier. In-flight old bursts finish naturally (same ID
  in order; at grant time the old data has already landed in the bank, and the new frame's line 0 overwrites the same addresses).
- **c3h anchor-window alignment**: after the anchor, idle for ANCHOR_WAIT ticks before issuing line 0 — the supply start
  is aligned to the point where the display starts pulling Va (VSP+VBP−margin), emission and consumption run in parallel at constant rate, eliminating the c3g first version's
  backpressure-following state (frame-tail lag + abort stream cut breaking the demosaic 3-line window = constant top+bottom flicker on the board).
  The margin must cover grant+DDR first word ~0.2 line + the demosaic 3-line-window flush of 2 lines.
- The starvation rescue (tlb<1 full line) is kept as the fallback.

### 4.3 Source switching = power-on replication (v4.10c3f form, unchanged)
```
CSR write → sw_pending → wait for the current source's vs falling edge (VFP gap)
t0 effective beat: mux flip + sw_gate triple cut (valid/hs/vs) + raw-domain reset 1µs
           + flush chain start (the tx domain is not reset at this point — it keeps draining the old replay stream)
t0+1.25ms: the 1ms wide flush pulse starts
   writer: drain idle beat clears the fill ledger; frame_par is never cleared (ping-pong anchor)
   reader: AXI safe beat clears the emission/read path + m_axis_tvalid cut on the same beat
             → tx-domain reset 1.35µs (demosaic/wb/yuv/shape/tlb/disp_timing,
               strictly synchronized with the reader stopping its stream)
t0+2.25ms: flush_done → gate_ready=1
gate open: new source's first vs rising edge → new stream enters the writer → fills ≥2 frames and publishes
     → reader done_cnt counts back up → reading starts on the anchor
```
Total switching blackout ~3-4 frames (50-67ms), one-off, zero tearing (steady state; for occasional tearing see §7-A).

### 4.4 Power-on boot (c3d, unchanged)
At power-up gate=0; the first source vs falling edge triggers once the exact same reset+flush chain as a switch.
Power-up to image ≤2 frames.

### 4.5 Hard discipline (board-test hammered history, do not break)
1. **The writer/reader AXI master ports are not reset** — the reset pulse cuts an active write burst → a leftover
   half transaction in DDR → wedged (2026-10-20 hard evidence).
2. **frame_par enters no flush/clear path**.
3. **The reader cadence source = disp_timing's local line_tick**; no source-side signal may enter the cadence chain
   (v3.1~v3.3 three generations of dead loop lessons).
4. 2FF synchronization-chain registers must be `syn_keep` (par_sync was optimized away 4 times before).
5. No data-path state may be touched before the switching effective beat (wait for the VFP gap).
6. **A DDR base-address change must be made word-for-word at both u_fw/u_rd sites**, and the 256MB capacity boundary
   (0x1000_0000) must be statically accounted first — out-of-range bits are silently stripped and wrapped by the hard core, invisibly to the AXI
   protocol layer (c3k lesson, see doc/ddr_interface.md §9).
7. **SV multiplication width = max(operand widths)**: large-coefficient multiplications need a 32-bit context
   (in pattern_gen the 20-bit direct multiply of the monotonic ramp once "restarted halfway up the screen", 2026-10-22 hard evidence).
8. **vlog does not tolerate wire/reg declared after use** (efx_map tolerates forward references) — files entering the vlog
   list must declare before use (exposed when top_cam.sv first entered the list during the c3m flattening).

---

## 5. Diagnostic System (UART COM8@115200, board-test readout)

**c3m DIAG remapping** (register layout unchanged, semantics updated; the former DIAG1 CDC FIFO and the
shape_video_axis black box retire with the flattening):

| DIAG | Address | c3m semantics | Healthy value |
|---|---|---|---|
| DIAG1 | 0x04 | **constant-0 placeholder** (CDC FIFO retired) | 0/0 |
| DIAG4 | 0x10 | {fw_sof_free, dms_sol_free} 16-bit free-running with wraparound | fw_sof +60/s = full rate; dms_sol wrap increment ~1424 |
| DIAG5 | 0x14 | {yuv_v_cnt, frm_cnt}, frm = tx_vsync edge (display domain) | frm +30 per 0.5s window = 60Hz |
| DIAG8 | 0x20 | disp_timing {late[31:16], under[15:0]} | late does not grow in steady state, under=0 (+1~2 allowed during startup) |
| DIAG9 | 0x24 | **fingerprint probe B** (demosaic input, pixel domain) {err[31:16], delta[25:16], v[15]} | err=0 |
| DIAG11/12/13 | 0x2C~0x34 | DDR status / fw heartbeat (unchanged) | err=0 lock=1 cfg=1; frm grows steadily ovf=pad=0 |
| DIAG14/15 | 0x38/0x3C | rd replay state (unchanged) | st=3, late/miss/err=0 |
| DIAG16 | 0x40 | **dual-clock cross-check**: {rd_sol (rd_clk domain), beat_px (pixel_clk domain)} | beat_px scrolling = replay→display path alive |
| DIAG17 | 0x44 | **fingerprint probe A** (writer input, raw domain) {err, delta, v}, same format as DIAG9 | err=0 |
| DIAG18 | 0x48 | 0.75s absolute window {df, live÷64} (unchanged) | df=45, live≈1,458,000 |
| DIAG19/20 | 0x4C/0x50 | reader drop/rpt / fw frame discipline (unchanged) | drop/rpt no growth in steady state; fw2 all 0 |

Fingerprint probe A/B algorithm: for valid beats take data[39:30] as a 10-bit within-line incrementing fingerprint, check +1 continuity
across sol, and on a break record err + latch delta (= the misalignment magnitude). A watches the "source→writer
input" segment (err growth = source-side misalignment), B watches the "reader replay→demosaic input" segment
(err growth while A stays clean = DDR/reader-segment misalignment).

**The firmware main.c print labels have not yet followed c3m** (to do): `fr:` (reads DIAG17,
old meaning tlast/sol — now probe A), `shp:` (DIAG8/9 old meaning shape black box — now
dtg late/under + probe B), `cdc:` (DIAG1 constant 0/0), `v4:` the low-order beat field
is now the pixel-domain beat_px. For board readout follow the table above, not the old comments on the print labels.

---

## 6. Version Evolution (v4.10c3f → v4.10c3m)

| Version | Change | Lesson/Result |
|---|---|---|
| v4.10c3f | tx-domain reset on the same beat as the reader stream stop | display-chain secondary contamination eradicated (c3f baseline, full-screen flicker eradicated on the board) |
| v4.10c3g | reader anchor-beat **residual-frame abort** (abort_frame + pend_grant) | the deadlock structure of problem B was located (tb 94.6 lines after the anchor vs 6 lines when pulling starts); the first version introduced a backpressure-following state: constant top+bottom flicker (the abort stream cut broke the demosaic 3-line window), board-test hard evidence |
| v4.10c3h | **anchor-window alignment**: ANCHOR_WAIT idle ticks (board 78/tb 4) | the supply start is aligned to the Va pull point, emission and consumption parallel at constant rate; the c3g backpressure-following state eradicated — the behavioural fix of problem B is complete (physical root cause not yet removed, see c3k) |
| v4.10c3i | fingerprint pattern mod-256 (pat_sel=2 diagnostic version) | blind to δ≡0(mod 256) misalignment — the limitation of the first-generation diagnostic weapon |
| v4.10c3j | **fingerprint probes A/B** (DIAG17/DIAG9) + pattern mod-1024 | the δ=2048 address alias made the mod-1024 pattern completely blind (2048≡0 mod 1024) — "a perfect data sequence ≠ the correct physical landing point", the double-blinding lesson |
| **v4.10c3k** | **FRAME_B 0x1100_0000→0x0200_0000** (both u_fw/u_rd) | the physical root cause of problem B: B's base address bit28 exceeded the 256MB capacity boundary of the 2Gb device, the hard core stripped it and wrapped onto frame A line 2048 → B's first 112 lines overlapped A's tail in a read/write race = bottom flicker band. The flicker band disappeared on the board, **B closed**. Pattern pat_sel=2 changed to a full-frame monotonic grayscale ramp (no period, any δ≥1 visible as a ~0.47δ jump; the 32-bit multiplication width lesson). The behavioural model does not model capacity wraparound — simulation structurally cannot reproduce it, so only static accounting + board test can guard it |
| v4.10c3l | D problem investigation: tried VSP 8/VFP 10 + WAIT 76 | ineffective on the board (the rolling is unrelated to the vsync↔data relative timing; it is a data-domain line-phase misalignment), **reverted** to the CTA standard values; investigation paused |
| **v4.10c3m** | **camera_path flattening** | deleted the four DISP_V4=0 branch files, inlined the DISP_V4=1 netlist into top_cam.sv; tb_phase4 rewritten to instantiate the chain directly (criteria unchanged); sw_src monitor 3bit→2bit; DIAG1 retired, DIAG4/5/8/9/16/17 remapped; DISP_FRAME_SLOTS parameterized (2250/1125). verible 0 errors / vlog 0 errors 0 warnings (4 forward-reference errors, fixed by moving declarations earlier) / vsim all green / bitstream all PASS / **board test has output**. **Current version** |

---

## 7. Board-Test Status

### Resolved (board-test evidence)
- 256px vertical line (v4.10a), line-0 run-ahead (reverted), power-on blackout for minutes (c3d), switching
  diagonal roll/blackout/dead bridge chip (c3b~c3f), full-screen periodic flicker (c3f).
- **B fixed offset + bottom flicker band (closed in three stages c3g/h/k)**: the behavioural layer's residual-frame abort + anchor window
  (c3g/h) removed the symptom first, and the physical root cause FRAME_B out-of-range wraparound (c3k) was eradicated on the board.
  Diagnostic-weapon evolution: mod-256 → mod-1024 (both blinded by the δ alias) → monotonic ramp + data-domain
  fingerprint probes A/B.

### Outstanding (currently active problems)
- **A. Occasional switching tearing**: pattern→camera occasionally tears + flickers, and switching back and forth restores it
  (c3f leftover; prime suspect: the in-flight done pulse when the switch instant coincides with the writer's frame publish edge
  competes with the bank arbitration for the new stream's first publication).
- **D. Top 2-line rolling** (slow crawl): data-domain line-phase misalignment — it appears on both shaping paths
  (disp_timing replay / direct injection) and is unrelated to the vsync↔data relative timing (c3l
  VSP/ANCHOR compensation was ineffective and has been reverted). **Investigation paused** (the user instructed to leave it aside for now).
- **C→transformed**: the c3f-era "probe frozen at constant 0" (rd_clk-domain reset not released) is bypassed by the c3m
  DIAG16 dual-clock cross-check (beat_px does not depend on rd_rstn); **4 print labels/readout in the firmware main.c
  are outdated** (fr:/shp:/cdc:/v4, see §5), to be updated.

---

## 8. Verification System

- **tb_phase4** (sim/, rewritten for c3m): instantiates the module chain directly (the only remaining difference from the board is the DIAG
  wiring/DPHY/source switching), shortened frame VACT=90/FRAME_SLOTS=100, 40ms full-chain simulation.
  Criteria: P1 frame complete / P2 TX burst / P3 rd 90/90 + dms_sol + frm growth /
  P4 topology / **P4C content bit-identical** (fingerprint {f,l,b,16'hA5C3} injected→writer→AXI→
  DDR model→reader zero-extension beat-by-beat comparison) / SLOW slow-source display period ≥ slot rate.
- **c3m regression results** (v410c3m_reg.log, vsim 24s):
  `P4C-OK frames=7 cmp=432000 err=0`, `rd sol/tlast 90/90`,
  `dms_sol=542 yuv_v=520320 frm=7`, `late/under=00020000`,
  `P4-OK`, `SLOW-OK late_delta=0 drop=3 rpt=4`, Errors=0.
- **Discipline**: vsim is allowed **only after vlog reports 0 Error** (vlog errors were once swallowed by a pipe filter →
  false regression); even after verible-syntax MCP passes the syntax, vlog/efx_map are still required (declaration order/
  multiple drivers are only checked by the latter two layers). tx_line_buf is `.v`.
- Regression commands (sim/ directory, from c3m on):
  ```
  vlog -sv ../rtl/top_cam.sv ../rtl/raw_2_axi4st.sv ../rtl/pattern_gen.sv
       ../rtl/demosaic.sv ../rtl/wb_axis.sv ../rtl/rgb2yuv_axis.sv
       ../rtl/shape_pat_gen.sv ../rtl/tx_line_buf.v ../rtl/disp_timing.v
       ../rtl/frame_writer.v ../rtl/frame_reader.v tb_phase4.sv
  vsim -c -voptargs="+acc" -do "run 40 ms; quit -f" work.tb_phase4 -l <log>
  ```

## 9. Toolchain and Deployment

- **Bitstream generation** (project root, ~3 minutes end to end): **do not rely on efx_run.bat's automatic setup** —
  when EFINITY_HOME is left over in the terminal it skips setup.bat → PYTHONHOME missing → Python
  dies immediately with `No module named 'encodings'`. Call it directly with the explicit full variable set (per setup.bat):
  ```
  $env:EFINITY_HOME='D:/efinity/2026.1'
  $env:PYTHONHOME='D:\efinity\2026.1\python311'
  $env:EFINITY_USER_DIR_INI="$env:LOCALAPPDATA/efinity/user_dir.ini"
  $env:EFXPT_HOME='D:/efinity/2026.1/pt'; $env:EFXPGM_HOME='D:/efinity/2026.1/pgm'
  $env:PATH='D:\efinity\2026.1\python311\bin;D:\efinity\2026.1\bin;D:\efinity\2026.1\pgm\bin;' + $env:PATH
  & 'D:\efinity\2026.1\python311\bin\python.exe' 'D:\efinity\2026.1\scripts\efx_run.py' --prj ws-e1-cam-ddr-csi2.xml -f compile
  ```
  PASS criterion: map/interface/pnr/pgm all PASS. The cross-clock-domain WARNINGs (between pixel_1080/
  sys_200m/dphy) are unconstrained asynchronous CDC paths, always of the same origin, not a defect.
- **Three-step deployment**: ① ftdi_pgm.bat burns the bit ② openocd loads the ELF (cwd=sw) ③
  read the counters on COM8@115200, 'c'/'p' switches the source.

## 10. Rollback Guide

This version = the complete current contents of the following files. If a later change introduces a regression, restore per this list:

| File | Key anchors of this version |
|---|---|
| rtl/top_cam.sv | flattened netlist: cap zero-extension assignment + u_raw/u_demosaic/u_wb/u_rgb2yuv/g_shape_pat/mux/u_tlb/u_dtg inline direct wiring; declaration block before use (forward references); path_diag constant 0; probes A/B; DIAG16 dual clock; sw_src 2bit {dbg_sel,pat_en}; wb effective = pat_en?0x40:CSR; rgb2yuv blk_clip=!pat_en |
| rtl/top_cam_demo.sv | u_cam_0: LINE_SKIP_FIRST=21/DBG_SHAPE_PAT(1)/DISP_FRAME_SLOTS(2250)/VSP10+VFP8; u_cam_1: DISP_FRAME_SLOTS(1125); u_fw/u_rd **FRAME_B=33'h0_0200_0000 changed at both sites**; u_rd ANCHOR_WAIT(12'd78) |
| rtl/frame_reader.v | c3g residual-frame abort (abort_frame/pend_grant/r_quiet, pend_grant single-driver); c3h ANCHOR_WAIT anchor window (S_WAIT idle + anchor_cnt) |
| rtl/frame_writer.v | c3f form unchanged: flush_i + drain-idle-beat flush branch (no frame_par assignment) |
| rtl/pattern_gen.sv | pat_sel=2 monotonic grayscale ramp: `10'((32'(live_ln)*32'(MONO_COEF))>>11)` (do not revert to the 20-bit direct multiply) |
| rtl/disp_timing.v | LINE_CLKS=1100 / PAD_L derived self-consistently from the slot-structure remainder (the c3l trial change was reverted, do not touch VSP/VFP compensation again) |
| sim/tb_phase4.sv | direct chain instantiation + explicit raw_t*[39:0] declarations; criteria P4C/rd90/P4/SLOW |
| ws-e1-cam-ddr-csi2.xml | without the four lines camera_path/shape_video_axis/async_path_fifo/replay_pat_gen |

Suggestion: immediately git commit to set an anchor (file-level rollback is expensive).

---

## 11. Next Steps (plan for attacking the outstanding problems)

1. **A occasional switching tearing**: review the frame_reader grant/next_par logic (the race window between the done edge
   lingering in the 2FF and the fire clear); reproduce with fast cyclic switching on the board + counter snapshots.
2. **D top 2-line rolling** (paused): data-domain line-phase misalignment direction — compare the probe A/B
   delta against the DIAG8 late line-phase ledger; alternative: a custom Vtotal to pull the rate back to 60.00.
3. **main.c DIAG prints aligned to c3m semantics**: update the four labels and their readout, fr:/shp:/cdc:/v4
   (low risk, firmware only).
4. (Optional) address-sequence probe (awaddr/araddr sampling) — the last gate on the address domain recommended in
   ddr_interface.md §9.4 after c3k.
