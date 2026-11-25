[中文](phase4-summary.md) | English

# Phase 4 Summary — Top-Level Integration (reader domain change + toggle handshake + v4 display chain + toolchain PASS)

> Status: **RTL/toolchain completed (2026-10-21)** · Spec: SPEC-001 mod-top-v4 · Verification level: FPGA_INTEGRATION · Final: efx_run map/**pnr**/pgm **PASS** (slack +2.230ns within the v4 domain), the bitstream has been generated as `outflow/ws-e1-cam-ddr-csi2.bit` · **Board-level image verification awaits user execution**

## 1. Goal

Close out architecture v4: frame_writer (200M/raw domain) → DDR Port0; frame_reader (148.5M display domain = DDR ACLK_1, and Phase 0 has proven the hard core accepts it) → demosaic→wb→rgb2yuv→**tx_line_buf→disp_timing v2**→ CSI-2 TX. The display timing has a single source (R1), and the reader's slot cadence has zero deviation from the display timing.

## 2. RTL changes

### 2.1 rtl/camera_path.sv (v4 display chain branching)

- New parameters `DISP_V4` (default 0) / `FRAME_SLOTS` (2250) / `PAD_L` (90).
- New ports `rd_clk`/`rd_rstn` (the replay CDC write clock = the reader domain) and `disp_line_tick_o` (the display slot cadence output).
- The `u_cdc` write clock changes to `rd_clk` — after the reader changes domain the replay stream enters the FIFO from the same source (the replay_pat direct-injection source is still aclk, and the mux exclusion is harmless).
- The display tail is branched: with `DISP_V4=1` → yuv → **tx_line_buf → disp_timing** → TX (shape retires); with `=0` → the v3 shape_video_axis (cam1 keeps it).
- DIAG8 is remapped: under v4 it is disp_timing `{late_cnt, under_cnt}` (the DIAG9 shape snapshot retires and is set to 0).

### 2.2 rtl/top_cam.sv (pass-through)

- Parameters `DISP_V4`/`DISP_FRAME_SLOTS`/`DISP_PAD_L`; ports `rd_clk`/`rd_rstn`/`disp_line_tick_o`; passed through to u_path.

### 2.3 rtl/top_cam_demo.sv (the g_frame_writer branch is enabled)

- `FRAME_WRITER=1`, `DDR_P1_148=0` (the Phase 0 verification branch retires).
- **Frame handshake toggle scheme** (the closing of the ~25% loss risk of directly sampling a 200M single cycle at 148.5M recorded in Phase 2): `fw_frame_done`@200M toggles `tog200` → 2FF into the pixel_clk domain → an XOR restores the single cycle `fw_done_148`; `fw_par` is sampled directly as a level through 2FF.
- The 148.5M domain reset: `u_rd_rst_148` (`~ddr_cfg_ok` gated, the same CYCLE=4 style as the 200M-side mc_srstn).
- frame_reader: `.aclk(pixel_clk)`, `.line_tick(disp_line_tick)` (same source as disp_timing), `.rstn(rd_rstn_148)`.
- u_cam_0: `DISP_V4=1` plus the `rd_clk(pixel_clk)`/`rd_rstn`/`disp_line_tick_o` wiring; u_cam_1 keeps v3 (DISP_V4 defaults to 0).

### 2.4 SDC (ws-e1-cam-ddr-csi2.sdc)

- Added `set_clock_groups -asynchronous -group {sys_clk_200m} -group {pixel_clk}` — all cross-domain paths between 200M (writer/raw) and 148.5M (reader/disp_timing, = ACLK_1) are 2FF/toggle/asynchronous FIFO structures, exempted from STA.

### 2.5 Project files

- ws-e1-cam-ddr-csi2.xml gains `rtl/tx_line_buf.v` and `rtl/disp_timing.v`.

## 3. Toolchain verification (efx_run interface, map, pnr, pgm all PASS)

| Item | Result |
|---|---|
| interface | PASS (peri ACLK_1=pixel_clk keeps the Phase 0 form) |
| map | PASS: 17,555 LUT4 / 13,441 FF / 472 RAM10 / 25 DSP48+56 DSP24; tx_line_buf/disp_timing infer BRAM/FSM normally |
| pnr | PASS |
| pgm | PASS (`outflow/ws-e1-cam-ddr-csi2.bit` generated) |

**Timing attribution** (timing.rpt Clock Relationship Summary):

| Clock pair | Slack | Verdict |
|---|---|---|
| **pixel_clk → pixel_clk (the whole v4 domain: reader+disp chain)** | **+2.230 ns** | ✓ Converged (better than the Phase 2 memcheck form at +2.006) |
| sys_clk_200m → sys_clk_200m | +0.095 ns | ✓ |
| pixel_clk hold | +0.029 ns | ✓ |
| sys_clk_200m ↔ pixel_clk (the new cross-domain pair in v4) | does not appear | ✓ The async group declaration takes effect |
| 200↔1080 / rx word clock / esc↔tx2 and other negative slacks | -0.7 ~ -2.9 | The v3 leftover asynchronous cross-domain pairs (the cam1 FIFO / RX word clock / the TX IP's internal black box); STA treats the black boxes as false paths, and the v3 board-level image output has already been verified; **not introduced this time and outside the mod-top-v4 scope** |

Note: during map, disp_timing's `under_cnt` double-drive was found and fixed (the main FSM reset branch and a standalone always block assigned it simultaneously, VDB-1000/1001) — it passed after the reset was moved into a dedicated block.

## 4. Simulation regression (a full Phase 3 re-run)

- tb_disp_timing: `[DT-OK]` (864000 beats, zero errors) ✓
- tb_full_chain: `[FC-OK]` (6 display frames, fingerprint zero errors, slow-direction repeat scenario) ✓

## 5. Board-level verification checklist (to be executed)

1. Program `outflow/ws-e1-cam-ddr-csi2.bit`.
2. `cam_show` reads DIAG:
   - **DIAG11**: the DDR cfg (lock=1 / cfg_ok=1 maintained).
   - **DIAG12**: `{fw_frame_cnt, fw_line_cnt}` — the writer frame count grows with the sensor stream (after the camera I2C configuration).
   - **DIAG14**: `{rd_frame_cnt, rd_state, rd_line}` — the reader's playback frame count advances with the slots (the rd_state transitions).
   - **DIAG15**: rd_err `{late[7:0], miss[7:0], err[7:0]}` — expect a small miss value (slow-direction repeat) / err=0.
   - **DIAG8 (remapped)**: disp_timing `{late[15:0], under[15:0]}` — under is a constant 0 (the line budget takes effect); late is the skip observation value and should tend to stabilize.
3. Bridge chip image output: DIAG7 (dbg_win) `df_win` frame rate observation (the 60fps target; under slow-direction repeat the frame rate locks to the supply rate of 30fps — with a 4K60 source passed straight through the source frame rate equals the display frame rate, so it should be 60).

## 6. First board-level battle (2026-10-21) and the fix closure

**First-battle data**: fw frm/ln growing, rd frm/ln growing (grant/emission alive), `late=0 miss=0 err=0`, but `dms_sol=0 / yuv_v=0 / DIAG17=0/0 / df=0 / live=0` — the reader output did not reach the display pipeline, all black.

**Isolation** (a new tb_phase4 board-topology simulation — the camera_path real chain's cdc/demosaic/yuv/tlb/dtg entered simulation for the first time): after reproducing it in simulation, level-by-level probes found three problems:

1. **The same-clock async FIFO synthesis pathology (the prime suspect, now removed)**: after v4 moved the reader to another domain, the replay CDC became a wr=rd=pixel_clk same-clock topology — EFX has a pathological risk in inferring the Gray synchronization chain of a same-clock async FIFO (the same symptom as the 2026-10-12 incident: empty is permanently true and the read side never consumes). Fix: under DISP_V4 the reader and the pipeline are in the same domain, so the **CDC is redundant and the replay stream passes straight through** (generate branching, the v3 path keeps the FIFO).
2. **The DIAG17 counter clock domain**: the original aclk (200M) sampled the rd stream after the domain change (cross-domain mis-sampling) → it follows rd_clk.
3. **DIAG16 reuse (0x40)**: the rd port's beat cadence directly proves `{rd_sol[15:0], rd_beat[15:0]}` (running free in the rd_clk domain) — complementary to DIAG17 (frame anchoring); the break/pass criterion: scrolling = the path is alive.

Final simulation state: **[P4-OK]** (6 display frames, 540×960 beats in full, DIAG17=90/90, late=253/under=0, zero CDC loss). The toolchain re-ran map/pnr/pgm with PASS, the pixel_clk domain Fmax is 204MHz, and the new bitstream is `outflow/ws-e1-cam-ddr-csi2.bit` (12:39).

**Additional board-level readout notes** (compared via cam_show):
- `fw: frm` is the writer's input frame count (counted by sof), not the publication count; the publication evidence is on the reader side (rd frm following) and in DIAG15.
- `shp: srch/lvl` under v4 is DIAG8 {late[15:8], late[7:0]} (reassembled into 16 bits as the cumulative skip count).
- `cnt: df/live` (DIAG18) is a 0.75s absolute window — a constant 0 within a 40ms simulation is an artifact; on the board it is real.
- **DIAG16 (new)**: a continuously scrolling beat/sol means the reader→camera_path path is alive; a constant 0 means the break is in the top-level routing.

## 7. Outstanding items / risks

- **The 2-bank envelope contract** (recorded in Phase 3): when the source frame rate > the display frame rate, the write side overwrites the read bank (a real camera at 30fps < 60fps satisfies the envelope); at the board level it is necessary to observe whether the DIAG15 miss is bounded.
- The negative slack of the v3 leftover asynchronous cross-domain pairs (see the §3 attribution) is out of scope this time.
- The CSR CTRL[7]/CTRL[6] direct-injection diagnostic entry under v4 mode: the shape direct injection is still usable (via tx_line_buf); the replay_pat direct injection retires along with the CDC.
- After the same-clock FIFO straight-through, cam_show's `cdc: lvl` is a constant 0 (a straight-through has no level), which changes the diagnostic semantics.

## 8. Next step

Program the new bitstream (the 12:39 version) and re-test at the board level: DIAG16's scrolling behaviour (direct proof of the path) → DIAG17=2160/2160 (frame anchoring) → dms_sol/yuv_v growing → df/live growing → bridge chip image output.
