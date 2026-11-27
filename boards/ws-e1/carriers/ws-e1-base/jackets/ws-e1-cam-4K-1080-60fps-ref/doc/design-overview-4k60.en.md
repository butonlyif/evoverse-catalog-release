[中文](design-overview-4k60.md) | English
# 4K@60 Camera → DDR Frame-Buffer Playback → MIPI CSI-2 TX System Design Overview

| Item | Value |
|---|---|
| Baseline version | **v4.10c3m** (2026-10-22, usable on the board, bitstream `outflow/ws-e1-cam-ddr-csi2.bit`) |
| Device / toolchain | Efinix Titanium **TJ180A484S**, Efinity 2026.1 |
| Top level | `top_cam_demo` ([rtl/top_cam_demo.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/top_cam_demo.sv)) |
| Audience | engineers / partner teams taking over this project |
| Detailed archive | [milestone-v4.10c3m.md](milestone-v4.10c3m.md) (the source document of this overview), [ddr_interface.md](ddr_interface.md) |
| Status note | cam0 = the 4K@60 active link (the main body of this document); cam1 = the 1080p60 display-chain shell (**no DDR playback, black field reserved**, see §2.3) |

---

## 1. System overview

Dual IMX415 CSI-2 cameras are attached; the cam0 path implements **4K@60 (3840×2160) DDR frame-buffer ping-pong playback**, output to the panel through the ISP chain and MIPI CSI-2 TX. The display frame rate is a constant 60Hz, decoupled from the sensor frame rate; the source can be switched between "camera / diagnostic pattern" at any time without tearing.

```
IMX415 ──CSI-2──> my_csi2_rx (64b Generic Frame Mode, RAW10 valid low 40b)
                    │  sys_clk_200m domain
 pattern_gen ────────┤  top_cam source mux (CSR CTRL[2] pat_en)
                     │  + switch-in gate sw_gate + power-on bootstrap
                     v
               raw_2_axi4st (40b AXIS, 960 beats/line = 3840px, sliding window/DT gating)
                     │  {24'h0, tdata[39:0]} zero extension (v4.10 attach convention)
                     v
               frame_writer (aclk = sys_clk_200m, inside top_cam_demo)
                 64b carrier: 8 beats × 64b = 512b exactly packed
                 line 7680B = 120 words; AXI4 write 512b/beat, bursts 64+56 (each within its 4KB window)
                 8 line slots + 8-deep desc queue; whole frame or nothing
                     v
               LPDDR4X dual-bank frame ping-pong
                 FRAME_A = 0x0_0000_0000 / FRAME_B = 0x0_0200_0000
                 line slot 8KB × 2160 lines = 17.6MB/frame
                     v
               frame_reader (aclk = pixel_clk 148.5M)
                 8-beat slice per 512b word [64k+63:64k]; line 967 issue beats < 1100 line budget
                 frame-level arbitration: disp_sof anchor + ANCHOR_WAIT anchor window + drop/repeat
                     │ 64b pass-through (wiring layer slices [39:0], same clock as reader, no CDC)
                     v
  top_cam inline display chain (v4.10c3m flattened, camera_path removed):
    demosaic (RAW10→RGB×4px) → wb → rgb2yuv (UYVY 64b)
                     │  shape_pat_gen direct-inject mux (DBG_SHAPE_PAT + CSR CTRL[6])
                     v
    tx_line_buf (DEPTH_WORDS=2048) → disp_timing (LINE_CLKS=1100, 2250 slots)
                     → my_csi2_tx → DPHY TX bridge chip → panel
```

**The whole ISP chain (demosaic/wb/rgb2yuv/tx_line_buf/disp_timing) is algorithmically untouched since v4.9d**. The v4.10 series changed only two things: ① the 40b→64b carrier restructuring (writer/reader); ② the source-switch/reset system (sw_gate + flush chain) + the reader frame arbitration fix (c3g/c3h) + the DDR base address fix (c3k).

### 1.1 Why a 64b carrier (v4.10 carrier restructuring)

In the 40b-carrier era, 960 beats/line × 40b against the 512b AXI beat had an LCM group-phase problem (a 2560b group shift chain), a breeding ground for 256px vertical-line defects. v4.10 changes to: the raw 40b stream is **zero-extended to 64b** (`{24'h0, data[39:0]}`), 8 beats × 64b = 512b exactly packed, beat k lands at `[64k+63:64k]` (beat0 at the least-significant position), the DDR byte order = ascending beat order, and the reader slices it back in the same order. **There is no LCM phase conversion at all** — vertical-line defects are eliminated constructively. Cost: each line occupies 7680B in DDR (including the 24bit/beat zero padding), trading bandwidth for correctness.

---

## 2. Module map (v4.10c3m)

### 2.1 Active files

| File | Responsibility | Key facts |
|---|---|---|
| [rtl/top_cam.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/top_cam.sv) | **Flat netlist** of a single camera path (since c3m the camera_path layer is removed and inlined here): source mux, switch-in gate, raw_2_axi4st, ISP chain, tx_line_buf, disp_timing, my_csi2_tx instance | one instance per camera; display geometry/frame slots are parameters |
| [rtl/top_cam_demo.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/top_cam_demo.sv) | System top: PLL/reset, DDR CFG FSM, frame_writer/frame_reader instances and cross-domain handshakes, CSR/APB, RISC-V firmware load | u_fw→DDR target0 (write), u_rd→target1 (read), the two ports are physically isolated |
| [rtl/frame_writer.v](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/frame_writer.v) | RAW10 64b line stream → DDR frame write; whole frame or nothing; `frame_par` is the only bank anchor | aclk=200M; line 120 words; bursts 64+56 |
| [rtl/frame_reader.v](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/frame_reader.v) | DDR frame playback read master; frame-level arbitration (anchor + drop/repeat); 64b sliced output | aclk=148.5M display domain; ANCHOR_WAIT anchor window |
| [rtl/raw_2_axi4st.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/raw_2_axi4st.sv) | CSI-2 RX 40b pixel stream → AXIS 40b line stream (sliding window/DT gating) | LINE_TOTAL_PIX window cropping |
| [rtl/pattern_gen.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/pattern_gen.sv) | Diagnostic pattern source (advanced in step with the panel line_tick) | pat_sel=2 = full-frame monotonic gray ramp |
| [rtl/demosaic.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/demosaic.sv) / [wb_axis.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/wb_axis.sv) / [rgb2yuv_axis.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/rgb2yuv_axis.sv) | ISP: demosaic → white balance → UYVY colour conversion | 4 pixels/beat 64b |
| [rtl/shape_pat_gen.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/shape_pat_gen.sv) | tlb-entry direct-inject diagnostic source (compile-time DBG_SHAPE_PAT + runtime CTRL[6]) | 4K geometry only |
| [rtl/tx_line_buf.v](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/tx_line_buf.v) | Line buffer (**a .v file**) + issue gate watermark | DEPTH_WORDS=2048 |
| [rtl/disp_timing.v](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/disp_timing.v) | The single source of display timing: line_tick / disp_sof / GATE, line segments and guards | LINE_CLKS=1100 (4K@PPC4) |
| [rtl/apb_cam_ctrl.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/apb_cam_ctrl.sv) | CSR (APB): CTRL source switch / DIAG readout | UART readout entry point |
| [rtl/reset_ctrl.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/reset_ctrl.sv) | Multi-domain reset synchronization (CYCLE parameter guards the metastability window) | |

### 2.2 Deleted files (do not reference them again)

`camera_path.sv`, `shape_video_axis.sv`, `async_path_fifo.v`, `replay_pat_gen.sv` — deleted during the v4.10c3m flattening (the DISP_V4=0 branch retired with them). Historical versions live in `backup/` and `design-package/materials/`.

### 2.3 cam1 (1080p60) current state

u_cam_1 is instantiated isomorphically to cam0, but **only covers `DISP_FRAME_SLOTS=1125`, with no DDR playback**: cam1's `rd_t*` inputs are tied off to 0 (black field) in top_cam_demo, and there is no u_fw/u_rd instance. The cam1 display chain runs at 37.125MHz (`pixel_clk_1080`). **Note**: the `LINE_CLKS=1100` of the disp_timing instance inside top_cam is currently a hardcoded 4K value and is not parameterized for cam1 (1080p@PPC4 should be 550); cam1's timing self-consistency is yet to be fixed.

---

## 3. Clock and reset domains

| Clock | Frequency | Domain contents |
|---|---|---|
| `sys_clk_200m` | 200M | my_csi2_rx pixel output, pattern_gen, raw_2_axi4st, **frame_writer**, DDR target0 ACLK |
| `pixel_clk` (pll_csi#1) | 148.5M | display pipeline (demosaic~disp_timing/TX), **frame_reader**, DDR target1 ACLK |
| `pixel_clk_1080` (pll_csi#2#1) | 37.125M | cam1 pipeline/display (1080p60@PPC4) |
| `sys_clk_100m` | 100M | my_csi2_rx controller clock |
| `i_clk_27m` / `esc_clk` / dphy word clock | — | TX power-on reset reference / DPHY ESC / RX recovery word clock |

Reset dual domain (the core of the source-switch timing):

- raw domain: `raw_aresetn = sys_clk_200m_rstn & sw_rstn` (source-switch frame-boundary reset)
- pixel domain: `pixel_rst_n = tx_pixel_clk_rstn & sw_rstn_tx` (released later than PLL lock +~300µs +~600µs, guaranteeing "reset released before data" cold-start anchoring)
- cross-domain handshake: `wr_frame_done` (200M single cycle) → 2FF + `syn_keep` → 148.5M edge capture; the `frame_par` level is sampled directly through 2FF

---

## 4. Key parameter quick reference (cam0 4K)

| Parameter | Value | Source/notes |
|---|---|---|
| RAW10 source window | LINE_TOTAL_PIX=3864, LEAD/TRAIL=12, SKIP_FIRST=21, 2160 lines | [top_cam_demo.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/top_cam_demo.sv) u_cam_0 instance |
| Source line stream | 960 beats × 40b = 3840px/line | raw_2_axi4st output |
| 64b carrier line | 960 beats (zero-extended) = 7680B = 120 words | frame_writer/reader localparam (4K only, for the 1080p variant see §9) |
| AXI write form | 512b/beat, INCR, 64+56 two bursts (each in its 4KB window); awqos=1 | frame_writer drain state machine |
| Display geometry | HACT=3840, VACT=2160, VSP10+VBP72+VFP8 (CTA 4K60), 2250 slots/frame | disp_timing; PAD derived self-consistently from the remainder |
| Display line beats | LINE_CLKS=1100 = 44+75+1+2+960+18 (@PPC4) | line issue budget 967 beats < 1100 |
| DDR frame layout | A=0x0_0000_0000, **B=0x0_0200_0000** (c3k), line slot 8KB | the parameters are character-identical in u_fw/u_rd |
| ANCHOR_WAIT | board 78 / tb 4 (= VSP+VBP−margin4) | c3h anchor window |
| CSR default | `32'hB4EBC814` (power-up = camera source, pat_en=0) | apb_cam_ctrl CTRL_RESET |
| Source switch | UART 'c'=camera, 'g/o/h/b'=pattern (key press = enable + selection); CTRL[6]=dbg direct inject | takes effect at the frame boundary |

---

## 5. Core mechanisms

### 5.1 frame_writer: whole frame or nothing (v2 architecture)

- Data buffer = 8 line slots × 120 words (512b) + an 8-deep {par,line} descriptor queue, single-clock pass-through pointers.
- **Bad frame (queue-full pollution / mid-frame sof) → close the frame, do not flip par, do not publish**: DDR only ever holds complete frames, constructively eliminating torn frames. Every drop path has a counter (ovf/pad/bad/drop).
- Frame full (VACT-1 line drain complete) → flip `frame_par` + publish the `wr_frame_done` single cycle (200M domain, the bvalid completion cycle once the whole frame has landed in DDR).
- **`frame_par` is the only bank arbitration anchor for writer/reader**: the writer always writes par, the reader always reads ~par.
- ppm/frame-rate difference division of labour: the writer always writes the live stream (whole frame or nothing), the reader does slot-granular drop/repeat — no line-level compensation.

### 5.2 frame_reader: frame-level arbitration + anchor window (v4.9 + c3g/c3h)

- Frame request = `wr_frame_done` cross-domain edge capture; **start gate `done_cnt>=2`** (the bank being read will not be overwritten by the next frame).
- **Grant anchor = the falling edge of `disp_sof`** (the Vs start, 82 slots before Va[0]). On a request edge → switch to the newest complete frame; without an edge → re-read the current bank (repeat); edges piling up → drop.
- **c3g residual-frame abandonment**: if the reader is still issuing the previous frame's residual lines at the anchor cycle, the single-cycle edge is missed → fixed so that at the anchor cycle `abort_frame` returns to IDLE and `pend_grant` suspends the current anchor grant, accepting it as soon as the read path goes quiet.
- **c3h anchor window**: after the anchor, idle for `ANCHOR_WAIT` ticks before issuing line 0 — the supply start aligns with the display Va pull start, so issue and consumption run in parallel at a constant rate. The margin covers grant + DDR first word ~0.2 line + demosaic 3-line window flush of 2 lines.
- No-line-loss principle: if the tick arrives and the data is not ready → delayed counter increments and it is issued on the ready cycle; the starvation rescue (tlb<1 whole line) is the backstop.
- Dual-line RAM ping-pong: the read path always leads the issue path by 1 line, overlapping the DDR latency with the issue period.

### 5.3 Source switch = power-on replay (v4.10c3b~c3f)

```
CSR write → sw_pending → wait for the current source vs falling edge (VFP gap, takes effect at the frame boundary)
t0 effective cycle: mux flips + sw_gate triple cut (valid/hs/vs) + raw domain reset 1µs
           + flush chain starts (the tx domain is NOT reset at this point — it keeps draining the old replay stream)
t0+1.25ms: flush wide pulse 1ms
   writer: on idle drain cycles clears the fill ledger (frame_par is never cleared)
   reader: on AXI-safe cycles clears the issue/read paths + m_axis_tvalid breaks the stream on the same cycle
             → tx domain reset 1.35µs (ISP/tlb/disp_timing on the same cycle the reader stops streaming)
t0+2.25ms: flush_done → gate_ready=1
Open the gate: the new source's first vs rising edge → the new stream enters the writer → fill ≥2 frames → the reader re-counts full → start reading on the anchor
```

Black screen for 3~4 frames (50-67ms) once, zero tearing. Power-on bootstrap (c3d): gate=0 at power-up, the first source vs falling edge triggers an identical reset+flush chain, and power-up to a visible picture is ≤2 frames.

### 5.4 Hard disciplines (confirmed by board tests in the past, **do not break**)

| # | Discipline | Consequence of violation (confirmed) |
|---|---|---|
| 1 | The AXI master ports of writer/reader are **not reset** | a reset cuts an active write burst → half-finished transactions remain in DDR → an 8-line/frame creep wedges the system |
| 2 | `frame_par` must not enter any flush/clear path | the ping-pong anchor is cleared → read/write conflict on the same bank → 50% chance of tearing |
| 3 | The reader cadence source = disp_timing local line_tick, source-side signals must not enter the cadence chain | three generations of dead loops in v3.1~v3.3 |
| 4 | The 2FF synchronizer registers must carry `syn_keep` | par_sync optimized away, 4 prior incidents |
| 5 | Do not touch data-path state before the switch effective cycle (wait for the VFP gap) | mid-frame reset → the writer receives a dangling stream → switching back gives a black screen |
| 6 | A DDR base address change must be made **character-identically in both u_fw/u_rd** + a static check against the 256MB capacity limit first | c3k: bit28 out of range was silently stripped and wrapped by the hard core → the B head 112 lines overlapped the A tail → bottom flashing region |
| 7 | SV multiplication bit width = max(operand width); large-coefficient multiplications use a 32-bit context | pattern_gen 20-bit direct multiply → "half screen restarts" |
| 8 | vlog does not tolerate wire/reg used before declaration (efx_map does) | the flattened top_cam.sv exposed 4 errors when first added to the vlog list |

---

## 6. DDR interface contract summary

See [ddr_interface.md](ddr_interface.md) for details (this section is a quick reference):

- Hard-core AXI behavior (board measurement): **WVALID-before-AWREADY type** (WVALID must be raised before the AW handshake, otherwise both sides wait and deadlock); during PRE_WRITE the W transfers must be counted in the beat accounting; awqos=1 / arqos=0; WLAST on the same cycle as the last beat of the segment; awapcmd/awallstrb/awcobuf=0; bready/rready asserted in advance.
- Port allocation: **target0 = cam0 write port** (ACLK=sys_clk_200m), **target1 = cam0 read port** (ACLK=pixel_clk 148.5M, the hard core accepts two asynchronous port clocks, verified in Phase 0). Reads and writes are isolated on the physical ports, preventing small-granularity write bursts from being starved by large-granularity reads.
- Address mapping and capacity limit (c3k lesson): 2Gb x16 → **256MB of valid addresses [27:0]**; out-of-range bits are silently stripped and wrapped by the hard core (invisible at the AXI layer, no SLVERR). Any address layout change requires a static check first; "all counters green + clean data probes" does not prove the address domain is correct.
- Layout: line slot 8KB stride (line number << 13), line data 7680B = 64+56 two bursts, each in its 4KB window; one frame 2160×8KB = 17.6MB. Frame A 0..17.7MB, frame B 32..49.7MB.
- Bandwidth budget: 4K@60 write side ≈ 1.06GB/s (~16% of the LPDDR4x peak), read/write turnaround overhead ~1.6%.

## 7. Verification system

- **tb_phase4** ([sim/tb_phase4.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/sim/tb_phase4.sv), rewritten for c3m): instantiates the module chain directly (only DIAG wiring/DPHY/source switching differ from the board), frame-scaled VACT=90 / FRAME_SLOTS=100 / BEATS=960 / WORDS=120, 40ms full-chain simulation.
- Criteria: **P1** frame completion / **P2** TX bursts / **P3** rd 90/90 + dms_sol + frm growth / **P4** topology / **P4C content bit-exactness** (the fingerprint {f,l,b,16'hA5C3} is injected → writer → AXI → DDR model → reader zero-extension and compared beat by beat) / **SLOW** slow-source display period ≥ slot rate.
- c3m regression baseline (`sim/v410c3m_reg.log`, vsim 24s): `P4C-OK frames=7 cmp=432000 err=0`, `rd sol/tlast 90/90`, `late/under=00020000`, `P4-OK`, `SLOW-OK`, Errors=0.
- Regression command (in the sim/ directory):

```
vlog -sv ../rtl/top_cam.sv ../rtl/raw_2_axi4st.sv ../rtl/pattern_gen.sv
     ../rtl/demosaic.sv ../rtl/wb_axis.sv ../rtl/rgb2yuv_axis.sv
     ../rtl/shape_pat_gen.sv ../rtl/tx_line_buf.v ../rtl/disp_timing.v
     ../rtl/frame_writer.v ../rtl/frame_reader.v tb_phase4.sv
vsim -c -voptargs="+acc" -do "run 40 ms; quit -f" work.tb_phase4 -l <log>
```

- Verification discipline: **vsim is allowed only after vlog reports 0 Errors** (vlog errors were once swallowed by a pipe filter → a fake regression ran against an old library); passing verible-syntax MCP syntax still requires vlog/efx_map (declaration order/multiple drivers are only caught by the latter two layers); `tx_line_buf.v` is `.v`, not `.sv`.

---

## 8. Board test status and diagnostics

### 8.1 UART diagnostic quick reference (COM8@115200, after the c3m DIAG remap)

| DIAG | Address | Semantics | Healthy value |
|---|---|---|---|
| DIAG1 | 0x04 | constant 0 placeholder (CDC FIFO retired) | 0/0 |
| DIAG4 | 0x10 | {fw_sof_free, dms_sol_free} free-running | fw_sof +60/s; dms_sol increments ~1424 per wrap |
| DIAG5 | 0x14 | {yuv_v_cnt, frm_cnt=tx_vsync edges} | frm +30 per 0.5s window = 60Hz |
| DIAG8 | 0x20 | disp_timing {late, under} | late does not grow in steady state, under=0 |
| DIAG9 | 0x24 | **fingerprint probe B** (demosaic input) {err, delta, v} | err=0 |
| DIAG11 | 0x2C | DDR status {err,mcst,done,st,lock,cfg_ok,...} | err=0 lock=1 st=3 mcst=9 done=1 |
| DIAG14/15 | 0x38/0x3C | rd playback state / {late,miss,err} | st=3, all 0 |
| DIAG16 | 0x40 | **dual-clock cross-check** {rd_sol, beat_px} | beat_px rolling = the replay→display path is alive |
| DIAG17 | 0x44 | **fingerprint probe A** (writer input) {err, delta, v} | err=0 |
| DIAG18 | 0x48 | 0.75s absolute window {df, live÷64} | df=45, live≈1,458,000 |
| DIAG19/20 | 0x4C/0x50 | reader drop/repeat / fw frame discipline | 0 growth in steady state |

Fingerprint probes A/B: take data[39:30] as a 10-bit in-line incrementing fingerprint and check the +1 continuity across sol; A watches "source→writer input", B watches "reader playback→demosaic input", locating the misalignment segment by segment (c3j lesson: periodic patterns are doubly blind to δ aliasing, so a data-domain fingerprint + a monotonic ramp must be used).

### 8.2 Problem status

**Closed** (board evidence): 256px vertical lines (v4.10a carrier restructure), multi-minute black screen at power-up (c3d), switch diagonal rolling/black screen/dead bridge chip (c3b~c3f), full-screen periodic flashing (c3f), **B fixed offset + bottom flashing region (three-stage closure in c3g/h/k, physical root cause = FRAME_B out-of-range wrap-around)**.

**Remaining**:
- **A. Occasional switch tearing**: occasional on pattern→camera, recovers by switching back and forth; the prime suspect = the in-flight done pulse at the instant of the switch coinciding with the frame publish edge, competing with the new stream's first publish for bank arbitration.
- **D. Top 2-line slow scroll**: data-domain line phase misalignment, two formation paths appear together; the c3l compensation experiment was ineffective and has been reverted, **investigation paused** (user instruction).
- The semantics of the four firmware main.c print labels (fr:/shp:/cdc:/v4) were not updated with c3m — read per the §8.1 table, not per the old comments on the print labels.

---

## 9. Toolchain and deployment

- **Bitstream build** (project root, ~3 minutes): do not rely on the efx_run.bat automatic setup (it is skipped when EFINITY_HOME lingers in the terminal → a missing PYTHONHOME kills it outright). Set the full variable set explicitly and call the tools directly:

```
$env:EFINITY_HOME='D:/efinity/2026.1'
$env:PYTHONHOME='D:\efinity\2026.1\python311'
$env:EFINITY_USER_DIR_INI="$env:LOCALAPPDATA/efinity/user_dir.ini"
$env:EFXPT_HOME='D:/efinity/2026.1/pt'; $env:EFXPGM_HOME='D:/efinity/2026.1/pgm'
$env:PATH='D:\efinity\2026.1\python311\bin;D:\efinity\2026.1\bin;D:\efinity\2026.1\pgm\bin;' + $env:PATH
& 'D:\efinity\2026.1\python311\bin\python.exe' 'D:\efinity\2026.1\scripts\efx_run.py' --prj ws-e1-cam-ddr-csi2.xml -f compile
```

PASS criteria: map/interface/pnr/pgm all PASS. The cross-clock-domain WARNINGs (between pixel_1080/sys_200m/dphy) are asynchronous CDC unconstrained paths, always present, not a defect.

- **Deployment trio**: ① program the bit with `ftdi_pgm.bat`; ② load the ELF with openocd (cwd=sw); ③ read the counters on COM8@115200, 'c'/'p' to switch the source.
- Rollback: use the file anchor list in [milestone-v4.10c3m.md §10](milestone-v4.10c3m.md) as the authority.

---

## 10. Known outdated records (note when reading old documents, originals not changed)

| Location | Outdated content | Fact |
|---|---|---|
| readme.md | still describes the v3 pass-through demo era (no DDR, 37.125M panel clock) | the current architecture is v4.10c3m DDR playback |
| frame_writer.v header comment | "FRAME_B=0x1100_0000" (L18), "8 line slots x 75 words" (L22) | B has changed to 0x0200_0000 (overridden by the top level); the 64b carrier line slot is 120 words |
| ddr_interface.md §1 | "ACLK_0/1 both bound to sys_clk_200m" | ACLK_0=200M, **ACLK_1=pixel_clk 148.5M** (actually bound in peri.xml) |
| doc/shape_video_axis.md | pure 4K shape-chain document | the module was deleted with c3m, the document is archive-only |
| WORDS=75 in the various TBs | leftover from the 40b carrier era | 64b carrier = 120 words (tb_phase4 already updated) |

## 11. Document index

| Document | Content |
|---|---|
| [milestone-v4.10c3m.md](milestone-v4.10c3m.md) | complete archive of the current baseline (version evolution/rollback anchors/next steps) |
| [milestone-v4.10c3f.md](milestone-v4.10c3f.md) | snapshot at the c3f point in time (evolution history of the switch/reset mechanisms) |
| [ddr_interface.md](ddr_interface.md) | DDR hard-core interface contract + 6 rounds of debug history + the c3k capacity-limit lesson |
| [phase0~4-summary.md](phase4-summary.md) | summaries of the construction phases |
| `ddr_ctrl_model/docs/user-guide.md` | TJ DDR AXI behavioral model user guide (standalone simulation model, including board calibration parameters) |
| `axi-interconnect-core-ug-v1.8.md` | Efinity AXI Interconnect IP user guide (a candidate when multiple masters share a DDR port) |
