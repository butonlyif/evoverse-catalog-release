[中文](milestone-v4.10c3f.md) | English
# Milestone: v4.10c3f — 64b carrier + full-path synchronized-reset switching

Date: 2026-10-22
Status: **superseded by v4.10c3m** (problem B closed by c3g/h/k + camera_path flattening),
see [milestone-v4.10c3m.md](milestone-v4.10c3m.md) for the latest baseline. This document is kept as
the c3f point-in-time archive; its §7 outstanding item B has since been closed at the root cause in c3k (FRAME_B out-of-range wraparound),
C has been transformed by the c3m DIAG16 dual-clock cross-check, and for the §11 plan the new document's §11 governs.

Purpose of this document: complete design archive. If a later change introduces a regression, roll back to this version per §10.

---

## 1. Version Identification

| Item | Value |
|---|---|
| Version | v4.10c3f |
| bitstream | `outflow/ws-e1-cam-ddr-csi2.bit` (built 2026-10-22, map/pnr/pgm all PASS) |
| Top level | `top_cam_demo` (Titanium TJ180A484S, Efinity 2026.1) |
| Regression | `sim/v410c3f_reg.log`: P4-OK + P4C-OK (content bit-identical) |
| Key files | `rtl/frame_writer.v` `rtl/frame_reader.v` `rtl/top_cam.sv` `rtl/top_cam_demo.sv` `rtl/camera_path.sv` |

---

## 2. System Architecture and Data Flow

Dual IMX415 CSI-2 cameras → DDR frame-buffer replay → MIPI CSI-2 TX to the panel (4K@60).
cam0 = active chain (DDR replay), cam1 = passive reserve (rd input tied to 0).

```
IMX415 ──CSI-2──> my_csi2_rx (64b Generic Frame Mode, RAW10 low 40b valid)
                     │
 pattern_gen ────────┤  top_cam source mux (CSR CTRL[2] pat_en)
                     │  + switch-in gate sw_gate (c3b) + power-on boot (c3d)
                     v
               raw_2_axi4st (40b AXIS, 960 beats/line=4800B, sliding window/DT gating)
                     │
                     │ {24'h0, tdata[39:0]} zero extension (v4.10 attach convention)
                     v
 camera_path[DISP_V4=1] ── straight through (no CDC, reader already in the display domain)
                     │
                     v
               frame_writer (aclk=200M)
                  input 64b × 8 beats = 512b integral packing (v4.10, no LCM phase conversion)
                 line 7680B = 120 words; AXI4 write 512b/beat, bursts 64+56 (4KB aligned)
                 8 line slots + 8-deep desc queue; whole frame or nothing
                     │
                     v
               LPDDR4X dual-bank frame ping-pong
                 FRAME_A=0x0 / FRAME_B=0x1100_0000; line slot 8KB×2160 lines=17.6MB/frame
                     │
                     v
               frame_reader (aclk=pixel_clk 148.5M, v4 domain change)
                 each 512b word sliced into 8 beats [64k+63:64k]; line 967 beats < 1100 line budget
                 dual-line RAM ping-pong, read always leads emission by 1 line
                     │ 64b straight through (wiring layer slices [39:0])
                     v
     demosaic (RAW10→RGB×4px) → wb → rgb2yuv (UYVY 64b)
                     │
     shape_video_axis (diagnostic direct-injection entry, CSR CTRL[6])
                     v
               tx_line_buf → disp_timing_gen → my_csi2_tx → bridge chip → panel
```

**The entire ISP chain (demosaic/wb/rgb2yuv/shape/tlb) is untouched since v4.9d** — v4.10 changes
only the carrier (writer/reader) and the switching/reset (top_cam*), shrinking the regression surface.

---

## 3. Key Parameters

| Parameter | Value | Note |
|---|---|---|
| Resolution/frame rate | 3840×2160 @ 60.000Hz | display is always 60Hz, decoupled from the source ppm |
| VACT / frame slots | 2160 / 2250 tick | 90 pad lines |
| RAW10 source line | 960 beats × 40b = 4800B | raw_2_axi4st output |
| 64b replay line | 120 words (7680B) = 967 emission beats | WB0=64 + WB1=56 beat |
| GROUPS_PER_LINE | 24 groups × 8 beats × 64b | no 2560b group phase (v4.10 eradicates the vertical line) |
| Frame layout | A=0x0, B=0x1100_0000 | line stride 8KB, B lies beyond A's frame tail |
| Clock domains | sys_clk_200m (raw/writer) / pixel_clk=148.5M (display/reader/ISP/TX) | reader v4 has changed domain, no CDC inside the chain |
| CSR default | 0xB4EBC814 (**power-on default = camera**) | for the lesson on instantiation-site parameters overriding defaults see §6 |
| CSR switching | 'c'=camera 'p'=pattern (UART command writes CTRL) | takes effect at the frame boundary, see §5.3 |

---

## 4. Core Mechanisms

### 4.1 writer: whole frame or nothing (v2 architecture, unchanged)
- A bad frame (queue-full contamination / mid-frame sof) is closed **without flipping par and without publishing** — DDR only ever holds complete frames.
- Frame full (VACT-1 line drain complete) → flip par + publish `wr_frame_done` for a single beat (200M domain).
- **frame_par is the only bank arbitration anchor between writer and reader**: the writer always writes par, the reader
  always reads ~par. Any logic that clears or alters par introduces a same-bank read/write conflict (c3d lesson).

### 4.2 Frame-level arbitration (reader, v4.9 architecture)
- `wr_frame_done` 200M→148.5M via 2FF+syn_keep, edge-taken = frame request; the par level goes through 2FF.
- **Start gate done_cnt>=2** before it is released (ping-pong safety: the bank being read will not be overwritten by the next frame).
- Request edge present → switch to the newest complete frame; no edge → re-read the current bank (repeat); edges piling up → drop.
- **Grant anchor = disp_sof falling edge** (Vs start = 41 lines before Va[0]) — frame-boundary phase pinning
  (v4.6/4.8 anchorless diagonal roll eradicated). Starvation rescue (tlb<1 full line) as the fallback.

### 4.3 Source switching = power-on replication (complete v4.10c3f sequence)
```
CSR write → sw_pending → wait for the current source's vs falling edge (VFP gap)
t0 effective beat: mux flip + sw_gate triple cut (valid/hs/vs) + raw-domain reset 1µs
           + flush chain start (the tx domain is not reset at this point — it keeps draining the old replay stream)
t0+1.25ms: the 1ms wide flush pulse starts
   writer: drain idle beat (d_st==D_SETUP && queue empty && !awvalid && !wvalid)
           clears the fill ledger; frame_par is never cleared (ping-pong anchor)
   reader: AXI safe beat (R_IDLE/R_GAP/R_DONE and !arvalid) clears the emission/read path
           + m_axis_tvalid cut on the same beat + flush_fire single-beat pulse
             → tx-domain reset 1.35µs (demosaic/wb/yuv/shape/tlb/disp_timing,
               strictly synchronized with the reader stopping its stream — the core c3f fix)
t0+2.25ms: flush_done → gate_ready=1
gate open: new source's first vs rising edge → new stream enters the writer → fills ≥2 frames and publishes
     → reader done_cnt counts back up from 0 → reading starts on the disp_sof anchor
```
Total switching blackout ~3-4 frames (50-67ms), one-off, zero tearing.

### 4.4 Power-on boot (c3d)
- At power-up gate=0; the first source vs falling edge triggers once the exact same reset+flush chain as a switch
  (the boot_done flag makes it happen only once). Eliminates "power-on spurious stream contaminating demosaic for minutes".
- Power-up to image ≤2 frames.

### 4.5 Stream-loss protection and frozen frame
- New source loses its stream → gate stuck at 0 → reader keeps re-reading the current bank (rpt++) → the display freezes instead of going black.
- The raw-domain sw_rst trigger = the frame-boundary effective beat (**never reset on the CSR write** — c3c lesson:
  a mid-frame reset makes the writer receive a dangling stream).

### 4.6 Hard discipline (board-test hammered history, do not break)
1. **The writer/reader AXI master ports are not reset** (the reset domain covers only the 200M system reset) — 2026-10-20
   hard evidence: the reset pulse cut an active write burst → a half transaction left in DDR port0 → 8 lines/frame crawl, wedged.
2. **frame_par enters no flush/clear path**.
3. **The reader cadence source = disp_timing's local line_tick**; no source-side signal may enter the cadence chain
   (v3.1~v3.3 three generations of dead loop lessons).
4. 2FF synchronization-chain registers must be `syn_keep` (par_sync was optimized away 4 times before).
5. No data-path state may be touched before the switching effective beat (wait for the VFP gap).

---

## 5. Diagnostic System (UART COM8@115200, board-test readout)

| Print | Meaning | Healthy value |
|---|---|---|
| `fw: frm/ln ovf pad` | writer receive frame/line progress; queue-full drops / pad count | frm grows steadily ~32/window; ovf=pad=0 |
| `fw2: bad drop last_line` | bad-frame closes / dropped lines | all 0 |
| `rd: frm st ln late miss err req` | reader replay state | st=3, frm grows steadily, late/miss/err=0 |
| `fr: rd=tlast/sol per frame` | replay-stream frame-anchored line count | 2160/2160 (note: c3f probe domain reset issue, stuck 0/0 — a probe defect, not a link defect, see §7-C) |
| `v4: beat sol drop rpt` | replay port beats / frame arbitration | drop/rpt only +1~2 during startup, no growth in steady state |
| `shp: srch lvl wdrop uflow df vfs vst fl gwait` | shape gate / tlb level | uflow=wdrop=0 |
| `cnt: df/45 live/1458000` | 0.75s absolute-window display frame rate / non-zero content beats | 45/45, live≈1.46M |
| `ddr: err st lock cfg` | controller status | err=0 lock=1 cfg=1 |

---

## 6. Version Evolution (v4.9d → v4.10c3f)

| Version | Change | Lesson/Result |
|---|---|---|
| v4.9d | 40b carrier baseline | 60fps stable; residual vertical line + offset + flicker band |
| v4.10a | **64b carrier rebuild**: writer 8 beats×64b=512b integral packing, reader 8-beat slice per word | 256px vertical line eradicated (LCM group-phase class); the first version's sr packing bug caused 24 black 128px regions, missed by the tb checker and fixed afterwards |
| v4.10b | Line-0 run-ahead (skipping the tick gate) | **disproved and reverted**: rescue loop → frequent blackouts |
| v4.10c2/c3 | CSR default source changed to camera | the instantiation site `.CTRL_RESET()` overrode the module default — changing a default requires Grep over every instantiation site |
| v4.10c3b | Switch-in gate (triple cut + wait for the new frame header) | pattern stream attached mid-way → raw ledger phase difference → diagonal roll eradicated |
| v4.10c3c | writer flush + reset on the effective beat | an immediate CSR reset made the writer receive a dangling stream → back-switch blackout; the "reset the whole path" decision started here |
| v4.10c3d | Power-on boot reset; flush does not clear frame_par | power-on blackout for minutes eradicated; par clear = 50% probability of ping-pong conflict tearing eradicated |
| v4.10c3e | reader flush (AXI safe beat) + start gate zeroed | user decision landed: a switch replicates power-on, full-path reset |
| **v4.10c3f** | **tx-domain reset on the same beat as the reader stream stop** | display-chain secondary contamination (flooded with the old replay stream for 1.25ms after reset) eradicated; **current version** |

---

## 7. Board-Test Status

### Resolved (board-test evidence)
- 256px vertical line (v4.10a), line-0 run-ahead malignant regression (reverted), power-on blackout for minutes (c3d),
  switching diagonal roll/blackout/dead bridge chip (c3b~c3f), full-screen periodic flicker (gone under normal conditions after c3f),
  slow image appearance at power-up (c3d boot).

### Outstanding (currently active problems)
- **A. Occasional switching tearing**: pattern→camera occasionally tears + flickers, and switching back and forth restores it
  (the reset semantics work → judged to be either uncleared state or a timing window). Prime suspect: the switch instant
  coincides with the writer's frame publish edge, so the in-flight done pulse and the bank arbitration for the new stream's first publication compete.
- **B. Fixed offset + bottom flicker band spanning tens of lines** (visible with camera and with the vertical grayscale, constant size, occasionally
  at the top; the user's insight: the flicker band = the offset part): the reader frame boundary has a fixed phase difference relative to the display frame boundary
  (the delay from the grant anchor to the first line actually entering the display exceeds the 41-line window budget); the frame-tail overflow offset line jumps between
  "this frame's tail / next frame's head" → flicker band; ppm slow drift → jitter. Left over from v4.9d, unrelated to the 64b
  rebuild.
- **C. Diagnostic probe defect** (does not affect function): the rd_clk-domain reset (rd_rstn_148) of DIAG16 sol / DIAG17 (fr: rd=0/0)
  is not released, which freezes the probes at a constant 0; DIAG18 live being normal
  proves the chain is healthy. To fix: the probe reset chain.

---

## 8. Verification System

- **tb_phase4** (sim/): shortened frame VACT=90/FRAME_SLOTS=100, 40ms full-chain simulation.
  P1~P4 topology criteria + **P4C content bit-identical** (source-injected ramp → writer→AXI→DDR
  model→reader, beat-by-beat comparison, 348480 beats err=0).
- **Discipline**: vsim is allowed **only after vlog reports 0 Error** (vlog errors were once swallowed by a pipe filter,
  so vsim ran an old module from the library → false regression). tx_line_buf is `.v`, not `.sv`.
- Regression commands (sim/ directory):
  ```
  vlog -sv ../rtl/frame_writer.v ../rtl/frame_reader.v ../rtl/camera_path.sv
       ../rtl/raw_2_axi4st.sv ../rtl/demosaic.sv ../rtl/wb_axis.sv
       ../rtl/rgb2yuv_axis.sv ../rtl/shape_video_axis.sv
       ../rtl/disp_timing_gen.v ../rtl/tx_line_buf.v tb_phase4.sv
  vsim -c -voptargs=+acc -do "run 40 ms; quit -f" work.tb_phase4
  ```

## 9. Toolchain and Deployment

- **Bitstream generation** (project root): run directly with the explicit lowercase environment (bypassing the WSL bash trap — `bash` resolves to
  `WindowsApps\bash.exe`, which does not accept `D:/` drive paths; this machine's EFINITY_HOME once held an uppercase leftover):
  ```
  $env:EFINITY_HOME='D:/efinity/2026.1'; $env:PYTHONHOME='D:/efinity/2026.1/python311'
  $env:PATH='D:/efinity/2026.1/python311/bin;D:/efinity/2026.1/bin;...;' + $env:PATH
  # the full variable set (QT_PLUGIN_PATH / EFX*_HOME / EFINITY_USER_DIR_INI etc.) follows setup.bat
  python D:\efinity\2026.1\scripts\efx_run.py --prj ws-e1-cam-ddr-csi2.xml -f compile
  ```
  ~5 minutes end to end. PASS criterion: map/interface/pnr/pgm all PASS.
- **Three-step deployment**: ① `ftdi_pgm.bat` burns the bit ② openocd loads the ELF (cwd=sw) ③
  read the counters on COM8@115200, 'c'/'p' switches the source.
- **verible-syntax MCP**: after any Verilog/SV change run check_verilog_syntax (note:
  verible does not check declaration order/multiple drivers, only vlog/efx_map do — all three layers must pass).

## 10. Rollback Guide

This version = the complete current contents of the following files. If a later change introduces a regression, restore per this list:

| File | Key anchors of this version |
|---|---|
| rtl/frame_writer.v | flush_i port + drain-idle-beat flush branch (**no frame_par assignment**); d_st declaration moved ahead to after desc_mem |
| rtl/frame_reader.v | flush_i/flush_done_o ports; flush_fire safe-beat clear (last assignment after the case); done_cnt/req_pending/boot_granted flush clear branches |
| rtl/top_cam.sv | switch-in gate sw_gate triple cut + boot_done boot + fw_flush timing chain (1.25ms delay + 1ms width); tx_rst_cnt/tx_rst_act (triggered by disp_rst_req_i, reset value 0); raw_rst_trig=sw_eff_r |
| rtl/top_cam_demo.sv | u_fw.flush_i / u_rd.flush_i+flush_done_o / u_cam_0.disp_rst_req_i / u_cam_1.disp_rst_req_i(1'b0) |
| sim/tb_phase4.sv | flush_i(1'b0)/flush_done_o() in the u_fw/u_rd instantiations |

Suggestion: immediately `git add -A && git commit -m "milestone v4.10c3f"` to set an anchor
(the repository currently has no commit history, so file-level rollback is expensive).

---

## 11. Next Steps (plan for attacking the outstanding problems)

1. **A occasional switching tearing**: review the frame_reader grant/next_par logic (the race window between the done edge
   lingering in the 2FF and the fire clear); reproduce with fast cyclic switching on the board + counter snapshots.
2. **B offset + flicker band**: quantify the "disp_sof edge→first line enters tlb" delay chain (DDR first-word read latency +
   demosaic flush + tlb level gate) against the 41-line budget; add offset measurement to the tb; cross-check on the board by counting the flicker-band lines
   over the vertical grayscale = the offset amount.
3. **C probe fix**: DIAG16/17 rd_clk-domain reset chain (low priority, does not affect function).
