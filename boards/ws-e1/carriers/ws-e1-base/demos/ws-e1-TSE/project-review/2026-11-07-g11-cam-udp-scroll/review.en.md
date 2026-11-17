[中文](review.md) | English

# G11 camera RAW10 UDP direct push scrolling localization and root-cause cure (G11n6~n13 localization / G11n14 multi-bank stitching fix / G11n15 frame boundary alignment)

- Case ID: 2026-11-07-g11-cam-udp-scroll
- Created / last supplemented: 2026-11-07 / 2026-11-08 (G11n15, G11n15b)
- Environment: runtime (TJ180A484S carrier board + FTDI downloader + PC gigabit Ethernet port); Windows host
- SDK version / Adapter / toolchain: Efinity 2026.1 (efinity-riscv-ide-2026.1); QuestaSim vlog/vsim; firmware riscv sapphire standalone
- Project revision: no Git (the project is not under version control; the DAYLOG is the factual record)
- Requirement and outcome sources: session (user) + DAYLOG/2026-11.md G11 series + board-test UART readback (pasted by the user)

## Goals and actual results

Goal: fix the picture scrolling (group-level loss → group phase slip) of IMX415 1080p30 RAW10 over gigabit UDP to the PC.
Actual result: **fixed, with the board test closed (2026-11-08 G11n14 follow-up, see the end of the document)** — after the
DDR pivot decision the user redirected to "increase the FIFO depth to absorb the net accumulation": multi-bank stitching of 163,840 groups
(cam_fifo_bank mod-5 interleaved routing) + single-threshold flow control achieving zero rejection, the picture is stable at 30fps without scrolling.
The original final analysis (in-segment instantaneous bandwidth 1.30Gbps > the gigabit limit) is unchanged; deep buffering makes it absorbable.

## Overall process and phenomena

| Stage | What was done | Observed / manual interventions | Outcome and source |
|---|---|---|---|
| G11n6 | Dual-threshold + deep FIFO (8192) board test | rej 21%, occ pinned at 8000, consumption 74% | DAYLOG G11n6 |
| G11n7 | map.v netlist static evidence, ten cones 0 mismatch + timing closure | the RTL≠silicon hypothesis rejected; the [300]/[304] CSR direct-read tearing settled | DAYLOG G11n7 |
| G11n8 | Single-threshold flow control refactor (user's choice), regression PASS | every board-test metric unchanged (3rd time) | DAYLOG G11n8 + user readback |
| G11n9 | Observation probe round (fullhi/fullrise/rejrun/tvrun/occ min-peak) | full-hit 820k times/s, longest rej segment 48 cycles, tvrun 51 cycles | user readback CAMDBG9/10 |
| G11n10 | Threshold 300→2048 (it once did not take effect because an instantiation override was missed → corrected and reflashed) | threshold effective but rej/full-hit/white-wait all unchanged → the threshold-phase-lock model falsified | user readback + DAYLOG |
| G11n11/13 | hsgap min/max + line-gap 4-bucket histogram probe | **min=2961 cycles, bucket A 1086/frame, B/C=0, D 1.04/frame** → the truth about the frame structure | user readback CAMDBG11/12 |
| ILA user measurement | Single-line waveform: 633 cycles/line, 480 active, long line header + 90% duty | user domain knowledge: frame structure 30 OB + 1080 active + 6 tail; raw_2_axi4st outputs only active lines | session |
| Final analysis | Full-chain numbers closed (this review §How far) | user decision: DDR frame buffering (copy ws-e1-cam-4K-1080-60fps-ref) | session |

## Key artifacts and evidence

| Evidence ID | Original artifact path | Version / linkage | Supported fact | Ref | Snapshot | Status |
|---|---|---|---|---|---|---|
| E1 histogram readback | session paste (CAMDBG12 two rounds) | G11n13 bit | A=1086/frame, B=C=0, D=1.04/frame → 14.8µs back-to-back lines + 17.35ms frame-tail gap | see evidence/g11n13_camdbg.txt | raw paste under evidence/ | present |
| E2 board-test macro data | session paste (four rounds of cam readback) | G11n8/n10 bit | rej 21.5%, consumption 74%, white-wait 50%, packet period ~24.9µs constant | evidence/g11_board_macro.txt | same as above | present |
| E3 ILA waveform | user ILA capture (no file) | — | line 633 cycles, 480 active, long line header + 90% duty | session | — | user-reported |
| E4 BFM cadence regression | sim/tb_cam_udp.sv + run log | ILA cadence parameters | under a uniform line cadence the RTL path has fullrej=0 (rej is not a logic bug) | DAYLOG G11n12 section | sim/ sources in the tree | present |
| E5 final accounting script | .tools/g11n13_decode.py | input=E1 | full-chain closure: 32.43M groups/s=1.30Gbps vs gen 24M; net accumulation 135K=16×FIFO | script in the project | present |
| E6 new project spec | D:\Projs\ws-e1-ddr-ge\SPEC-udp-from-ddr.md | 2026-11-07 | the complete DDR rework spec (entry point for later work) | external path | present |

## How far validation reached

- Simulation: tb_cam_udp (real ILA cadence BFM) PASS — proving **the RTL data path has no rej under a uniform cadence**;
  the rej comes from the board-level real write cadence exceeding it (the cadence exceptionality is substantiated by the E1 histogram).
- Build: several rounds of GUI compile and board flash (user-executed), map/pnr PASS (G11n7 slack +1.377, no violation).
- Board level: four rounds of pacing schemes + three rounds of probe readings (user UART readback) — **scrolling not fixed** (structural root cause),
  but the localization chain is fully closed. hardwareStatus: the scrolling issue is NOT_FIXED (root cause localized, the fix moved to the DDR project).

## Problems and improvement candidates

| Candidate | Expected / phenomenon / impact | Evidence | Root cause | Suggestion | Scope |
|---|---|---|---|---|---|
| C1 CSR tearing read | a 125M-domain counter read directly from the 50M APB shows non-physical values | G11n7 | no synchronized snapshot (settled) | new project CSRs add double-consistent reads/snapshot registers | ws-e1-ddr-ge |
| C2 parameter override pitfall | a default change was not grepped against instantiation overrides → the threshold never reached the board (the G11n10 mix-up) | DAYLOG | instantiations explicitly override the module defaults | changing a parameter requires checking every instantiation point | project convention |
| C3 frame-structure probing | a wrong sensor cadence assumption consumed four board-test rounds | E1/E3 | missing cadence histogram probe (it should have been deployed on day one) | template the long-duration statistics histogram probe | SDK candidate |

## Project lessons and SDK feedback

- Lesson 1: **measure the distribution before building a model** — the "uniform lines" assumption drove all the pacing reasoning; a single 4-bucket histogram
  probe (one board flash) would have overturned it and directly shown the root-cause shape.
- Lesson 2: the board-test macro metrics staying constant across four rounds (rej/consumption/packet period) is itself a strong signal of a "systematic constant",
  and the shift from "tuning parameters" to "measuring cadence" should have come earlier.
- Lesson 3: a single ILA window can only prove a local cadence; cross-line/cross-frame scales need long-duration statistical probes.
- SDK candidate: an inter-arrival histogram probe template (min/max/N buckets, parameterized signal and bucket boundaries).

Development intake: not merged (candidate C3 can be taken in at the SDK repo).

## Material gaps and later follow-ups

- The original ILA waveform image was not archived (user-reported); the full text of the cam readbacks for the G11n9~n13 rounds is in evidence/.
- The sensor line-gap ≥21.6µs alternative (another route to 30fps rej=0) is archived in SPEC §0, unverified.
- The DDR approach (D:\Projs\ws-e1-ddr-ge + SPEC-udp-from-ddr.md) is kept on file as a fallback, not executed;
  the actual route was G11n14 multi-bank stitching (closed within this project).
- G11n14 simulation occ_diff_max=98311 (tb monitor semantics doubt, the same value in two rounds) not investigated — not blocking,
  the board test shows no such phenomenon.

## Follow-up 2026-11-08: G11n14 multi-bank stitching FIFO — scrolling cured, zero rejection

- Route change (user decision): the DDR pivot fallback is shelved; switch to "increase the FIFO depth to absorb the net accumulation".
  The user derived the capacity and corrected the Efinix BRAM=10Kb/block assumption; 2^18 exceeds 46 blocks, 2^17 is 8.9 lines short
  → the user proposed multi-FIFO stitching → bank0(2^17)+bank1(2^15)=163,840 groups (640 blocks).
- Implementation: cam_fifo_bank.sv (new, externally isomorphic to async_fifo) + pacer fifo_occ fed directly
  (18bit) + top-level instantiation/CSR/mirror block rework + tb real cadence BFM (line period 2961 cycles,
  frame tail 17.35ms, Bresenham 74% duty) + exp_q ring 262144.
- First-version defect (run1 simulation hard evidence, full_rej=73600/frame): the bit-test routing wcnt[17] collapses the capacity
  — the read/write window can fall entirely inside the bank0 range, leaving bank0 locally full while bank1 is empty → write rejection.
  Fix = mod-5 interleaved routing (163840=5×32768 exactly divisible, 4:1 capacity ratio, the same rule on both sides preserving order,
  so under any accumulation b0=4/5·P is exactly full and b1=1/5·P is exactly full, the whole capacity usable).
- Simulation after the fix (tb_g11n14_run2.log): three frames fullrej=0/mism=0/drain=0, occ at frame end
  137031/142933/142865 ≈ the theoretical net accumulation 135,351+threshold ✓.
- Board test (evidence/g11n14_camdbg.txt, after re-downloading): fullhi/fullrise/rejrun all 0
  = zero rejection; occ_min=1908 (≈threshold 2048 minus), occ_peak=139,944 (=theoretical
  135,351+2048+in-flight, closed exactly); hsgap_min=2961/hsgap_max=3469632, the frame structure re-substantiated at board level; the picture is stable
  at 30fps without scrolling. **The G11 scrolling issue is closed.**
- Follow-ups: IMX415 Bayer layout re-determination (--cfa four phases); the occ_diff_max=98311 tb monitor doubt to be
  investigated when convenient.

## Follow-up 2026-11-08: G11n15 frame boundary alignment — deep-FIFO frames out of phase residual defect (simulation closed, board test pending)

- Board-test residual (user-confirmed): the picture as a whole shifted left, purple on the left/green on the right + a vertical shift; the PC side
  reports no dropped frames. User self-diagnosis: the write FIFO provides no frame information, so the read side does not know the frame start; pattern↔camera switching needs
  the frame number recomputed. The Bayer layout is confirmed as RGGB (pattern mode colors are correct → the PC-side CFA parameters are right,
  the color cast is column-phase false color from a misaligned frame boundary, not a Bayer phase error).
- Root cause: the gen transmit window and the frames read out of the deep FIFO buffer are out of phase (lagging by ~0.45 frame of net accumulation),
  so when the PC reassembles by (fn, off) metadata the frame boundary is misaligned → the whole frame's pixels shift + column-phase color cast.
- Scheme (user-approved magic-number framing, PC scripts inside the repo are changeable): a four-layer chain rework —
  ① the write side inserts 2 magic groups at the frame start, 40'hFFFFFFFFFF + 40'h0000000000 (in RAW10,
    the probability of "an all-white group immediately followed by an all-black group" is very low; data/gating are each delayed
    3 cycles, the sof cycle drives ins_cnt 1→2→3→0, M1@t+2/M2@t+3/frame-start group@t+4, wr_en in phase with dat_d3);
  ② the pacer becomes purely streaming (delete START_THR/QUADS_LAST/QUADS_FRAME, req/go = cam_en &&
    occ>0, dynamic packet length min(290,occ) fed straight to gen via pkt_len_o; a threshold would leave 2047 groups
    glued to the next frame's magic numbers → pure streaming + dynamic short packets drain precisely);
  ③ gen dynamic packet length (latch grp_len_r on the S_IDLE grant cycle; cam returns to S_IDLE every packet;
    the packet-end group disables b3 pre-read/b4 load to avoid conflicting with the grant-cycle rd);
  ④ PC raw10.py FrameReassembler dual-mode reassembler (the magic number = a frame start marker; after consuming it, count bytes
    to fill 2,592,000B and a frame is complete, with no dependency on the next frame; the sticky _meta_mode falls back to the
    pattern metadata stream, and when the magic number reappears at the head of the data segment it automatically switches back to camera mode; residual data before the magic number is accounted
    as a short frame and self-heals; re-alignment every frame → pattern↔camera switching is plug and play).
- Two defect rounds in simulation + run3 PASS (tb_g11n15_run3.log):
  run1 FAIL (full_rej=5174): the S_IPG→S_HDR packet-chain path bypasses S_IDLE, so grp_len_r
  sticks for the whole first packet → the read side starves → FIFO backlog → the frame tail is not drained → the magic numbers get pushed out; fix =
  cam mode returns to S_IDLE every packet. run2 FAIL (stream misalignment, M2 missing throughout): the packet-tail b3 pre-read +
  b4 load put the next packet's first group into p, and after returning to S_IDLE each packet the grant-cycle rd read one more group and the S_ARM reload
  overwrote it → 1 group net loss per packet; fix = suppress pre-read/load on the packet-end group (pay_left==2/1).
  run3 PASS: frm=3, mism=0, drain=0, fullrej=0, MAGICCHK m1=3 m2=3 (exactly one magic pair per frame
  = hard evidence of exact FIFO draining between frames), exp_wr=exp_rd=1,555,206
  (3×518,402 balanced), the tail packet pkt5369 grp=91 proving dynamic draining.
- Top-level smoke: vlog Errors=6 all the historical vlog-2388 (consistent with the G11n6 baseline), zero new.
- PC-side self-check: 6 temporary-script tests all PASS (complete frame/magic number across packets/short frame not displayed/resync
  self-heal/pattern stream fallback/mode alternation).
- Files changed: rtl/ws_e1_tse.v (write-side magic number insertion + instantiation wiring), rtl/cam_udp_pacer.v
  (pure streaming), rtl/udp_pat_gen_v2.v (dynamic packet length), doc/pc_tools/raw10.py,
  sim/tb_cam_udp.sv (mirrored magic numbers + MAGICCHK).
- Todo: user GUI compile and board flash + new raw10.py viewer board test (criteria: no left/right or up/down
  shift in the picture, normal RGGB colors, pattern↔camera switching plug and play, fn contiguous with no persistent dropped frames,
  CSR [2EC] fullrej=0); the SDC L21 -exclusive → -asynchronous minor fix not done.

### G11n15b fix round (2026-11-08, the first board test exposed two defects)

- Board-test phenomenon: in camera mode "the frame number is rising, dropped frames 0, packet count rising, fps=0, picture frozen"; and "switching
  is broken, it cannot switch to the pattern and other modes". Restarting tse_console and the board changed nothing.
- Diagnostic method (PC-side capture probes eliminating layer by layer, all real local captures): ① stream health (4s:
  621.9Mbps, 53,688 packets/s, fn wrapped 120 times=30fps, off zero jumps zero loss) → ② magic number
  per-packet scan (39-42 per 4s, misjudged as "a magic number is inserted only every 3 frames" — lesson: **a per-packet scan cannot see
  magic numbers split across packets**, under occ=1 contention M1/M2 split across two packets + a dlen=10 magic-only packet under occ=2 contention)
  → ③ continuous byte stream + cross-packet carry full detection (120 per 4s = one pair per frame, median spacing
  2,592,010B = exactly one frame, the ±1 group jitter being occ read-domain synchronization stickiness, not a defect) → ④ real capture
  (107,302 packets written to disk) replayed through the repo reassembler → 57 complete frames/28.5fps → **the stream is healthy, the PC code
  has a real bug**, decisive discrimination.
- Defect 1 (PC raw10.py): the _meta_mode→camera switching path fails to set _pending=True after consuming the magic number
  → buf passes the frame length and triggers the "over frame length without a magic number" judgment back to meta_mode → infinite oscillation back to legacy
  (legacy reassembles the camera stream by (fn,off), and since the frame-start short packet's off is offset from the byte position → it never forms a frame).
  The "frame number rising (meta fn +1 per frame)/dropped frames 0/fps=0" triple profile matches exactly. Fix: set
  _pending=True.
- Defect 2 (RTL udp_pat_gen_v2): G11n15 pure streaming drains the FIFO to 0 during frame gaps →
  occ_ready=0 → cam_pkt_go=0; gen's S_IPG ipg_exit=(ipg_cnt>=lim && (!cam_r ||
  cam_pkt_go)) is never satisfied → stuck in S_IPG → the start_pulse for switching to the pattern/other modes cannot get in.
  In the G11n14 threshold era occ_ready was constantly 1 (START_THR=2048), masking this path. Fix: the S_IPG exit
  adds `kill_r || !cam_en → S_IDLE` (abort by returning to S_IDLE, must not go ipg_exit→S_HDR:
  cam_r=1 would send phantom packets out of nowhere, bypassing the pacer grant protocol).
- Verification: ① PC three-phase scenario replay (synthetic pattern stream→real camera stream→switch back to pattern): switching to the camera gives 57
  complete frames (0 before the fix); ② tb_cam_udp regression PASS (frm=3 mism=0 drain=0 fullrej=0
  m1=3 m2=3, the cam path unaffected by the gen change); ③ top-level smoke Errors=6 all historical, zero new.
- Files changed: doc/pc_tools/raw10.py (1 place), rtl/udp_pat_gen_v2.v (1 place).
- Awaiting board test (user): GUI recompile and board flash (one gen change) + restart tse_console (new
  raw10.py). Criteria: camera ~28fps smooth, pattern↔camera bidirectional switching plug and play,
  CSR [2EC] fullrej=0.

### G11n15c correction round (2026-11-08, the G11n15b RTL change disproven and reverted)

- New symptoms on the G11n15b bit board test: after downloading the bit no data flows by default, it can only switch to the camera, and cannot switch to the
  pattern/other modes → the G11n15b RTL change is disproven.
- Re-reading the FSM gives hard evidence: in cam mode each packet returns from S_DATA directly to S_IDLE (L566 cam_r branch),
  it never enters S_IPG at all → the G11n15b premise "cam is stuck in S_IPG" does not hold; the original "cannot switch to the pattern"
  was really the single root cause of the PC raw10.py `_pending`. G11n15b's `!cam_en → S_IDLE` in pattern/
  inc mode (cam_en=0 being the norm) hijacked each packet's return to S_IDLE, breaking the in-packet chain S_IPG→S_HDR →
  the pattern stream sent only 1 packet per frame_tick (a 1788× slowdown) → precisely explaining the new symptoms. The blind spot of G11n15b
  passing regression: tb PHASE3/PHASE4 did not cover the pattern mode's multi-packet chain.
- Fix: revert S_IPG to the G11n15 original `if (ipg_exit) → S_HDR`; the raw10.py `_pending` fix is kept.
  Regression PASS (tb_g11n15c_run1.log: PHASE3 mismatch=0, BACKPRESSURE
  frm=3 mism=0 drain=0 fullrej=0, m1=3 m2=3); smoke Errors=6 zero new.
- Lesson: before changing an FSM exit, enumerate every path that enters that state; paths the tb does not cover will not guard.
- Awaiting board test (user): recompile and board flash + restart tse_console. Criteria: ① after downloading the bit the pattern
  streams by default ② pattern↔camera bidirectional switching plug and play ③ camera ~28fps ④ [2EC] fullrej=0.

<!-- evoverse-project-review:evidence
{"hardwareStatus":"BOARD_OBSERVED_PASS","note":"G11 scrolling = board-test closed loop (G11n14); G11n15 frame alignment = G11n15c simulation closed loop, board test awaiting user execution (the G11n15b RTL change has been disproven and reverted, the PC _pending fix kept)","evidence":[{"category":"board-observation","path":"project-review/2026-11-07-g11-cam-udp-scroll/evidence/g11n13_camdbg.txt","digest":"see-file"},{"category":"board-observation","path":"project-review/2026-11-07-g11-cam-udp-scroll/evidence/g11n14_camdbg.txt","digest":"see-file"},{"category":"board-observation","path":"project-review/2026-11-07-g11-cam-udp-scroll/evidence/g11_board_macro.txt","digest":"see-file"},{"category":"simulation-log","path":"sim/tb_g11n14_run2.log","digest":"see-file"},{"category":"simulation-log","path":"sim/tb_g11n15_run3.log","digest":"see-file"},{"category":"simulation-log","path":"sim/tb_g11n15c_run1.log","digest":"see-file"},{"category":"rtl","path":"rtl/cam_fifo_bank.sv","digest":"see-file"},{"category":"rtl","path":"rtl/cam_udp_pacer.v","digest":"see-file"},{"category":"rtl","path":"rtl/udp_pat_gen_v2.v","digest":"see-file"},{"category":"pc-tool","path":"doc/pc_tools/raw10.py","digest":"see-file"},{"category":"analysis","path":".tools/g11n13_decode.py","digest":"see-file"},{"category":"spec","path":"../ws-e1-ddr-ge/SPEC-udp-from-ddr.md","digest":"see-file"}]}
-->

### G11n16 refactor round (2026-11-08, pattern source moved into the 200M domain unified FIFO chain)

- Architecture conclusion (the core of this round): the root of the G11n15 series switching defects (camera→pattern cannot switch, line rate→pattern anomaly)
  and of the G11n15b mis-fix is **two coexisting stream paths** — the camera goes 200M write side→cam_fifo_bank→
  pacer→gen cam mode, while the pattern is sent directly inside the gen 125M domain (pattern_quad+frame_tick); the two
  have independent start/stop/gating semantics each, and the switching combinations explode. User decision to refactor: move pattern
  generation into the 200M camera domain, writing the same FIFO chain at the camera cadence; degrade inc line rate to debug; default boot to the network service.
- Changes: new rtl/raw10_pat_src.v (200M free-running pattern source, interface replicating the camera window stream,
  30fps=6,666,667 cycles/frame, 518,400 groups/frame, 1 group/12 cycles, frame-tail gap 2.23ms); reg_apb3
  0x208 bit7 fifo_src_sel; ws_e1_tse source mux + sof-cycle latch (frame-boundary switching, ruling out intra-frame
  splicing); udp_pat_gen_v2 deletes the pattern direct path (raw10_r implies cam_r); main.c defaults to
  RMODE_NETSVC, CamGen(sel) parameterized ('c'=camera 'v'=pattern source, the only difference being 0x208 bit7).
  PC raw10.py magic-number framing automatically applies to the pattern stream, zero functional change.
- Evidence:
  - tb_raw10_pat_src PASS (sim/tb_g11n16_patsrc_run2.log): 4 frames with per-group independent expected comparison
    mism=0 (four patterns + group-boundary switching taking effect during a run), sof period 6,666,667 exactly, group spacing
    12 cycles, 518,400 groups/frame, sof/eof/sol/tlast structure zero errors.
  - tb_cam_udp PASS (sim/tb_g11n16_camudp_run1.log): PHASE3 mismatch=0;
    PHASE5 after frame 3, fifo_src_sel 0→1 frame-boundary switching takes effect, pattern frames go through the same chain;
    MAGICCHK m1=m2=237 (frm=236 + a truncated frame magic pair at the switching instant, as expected);
    G11K-BACKPRESSURE PASS (last_mism=0 drain=0 fullrej=0, exp_wr==exp_rd
    exactly drained).
  - Top-level smoke Errors=6 all historical vlog-2388 baseline, zero new.
- Lesson: formulas transcribed across files must be re-checked expression by expression against the PC reference implementation (never summarize from comments); when the tb
  chain uses reduced geometry, choose pat_mode=1 to avoid confusing the color-bar white/black bar groups with the magic numbers M1/M2.
- Awaiting board test (user): GUI recompile and board flash + restart tse_console. Criteria: ① no stream at boot (ping
  works, 'i' snapshot) ② 't' debug line rate ③ 'v' pattern four modes ④ 'c' camera ~28fps
  ⑤ pattern↔camera bidirectional switching plug and play ⑥ [2EC] fullrej=0.

### G11n16b board-test defect round (2026-11-08, uniform thin stream→533k pps small-packet storm→line burst fix)

- Board test (G11n16 flash): 'v' switching to the pattern prints normally but the PC has no image. Dump decoding localization (spacing
  ~1.567s, two samples): [2CC] armed=1/sof_cnt+48 (30fps pattern sof normal),
  [2E4]/[2E8] wcnt/rq each +26,145,545 (mod-163840 exactly 159 laps) = 16.68M groups/s =
  the exact pattern source rate (FIFO balanced, the whole chain alive), [2F0] 533k pps, [31C] occ peak
  ×4=40 → only min(290,occ)≈40 groups per packet. Note: occ_dbg is packed >>2, readings must be ×4.
- Root cause: the pattern source's "1 group/12 cycles uniform thin stream" coupled with the pacer's pure streaming (send whenever occ>0) → occ
  balanced at ~40 → a 533k pps small-packet storm (camera mode relies on whole-line 480-group bursts to push occ up to
  82~500 → 290-group large packets at ~33-66k pps). The PC UDP stack drops under overload; header overhead of 21~29% pushes
  line rate to ~0.9Gbit. Simulation did not cover it (the tb does not model PC-side pps capacity).
- Fix (rtl/raw10_pat_src.v cadence rework): line bursts mirroring the camera's microscopic cadence — 480 groups per line
  back-to-back (1 group/cycle) + line period 3100 cycles (isomorphic to the camera hs→hs main band) + frame-tail vblank
  3,318,667 cycles (≈16.6ms, the same as camera blanking, guaranteeing frame-tail draining/magic number alignment); frame period still
  6,666,667 cycles=30fps; LINES=GRP_TOTAL/480 derived (still holds with tb reduction).
- Evidence: tb_raw10_pat_src PASS (sim/tb_g11n16b_patsrc_run1.log, 4 frames mism=0,
  spacing_err=0, sof_period exact); tb_cam_udp PASS (sim/tb_g11n16b_camudp_run1.log,
  PHASE3 mismatch=0, PHASE5 pattern frames occ≈770 steady sawtooth/fullrej=0, MAGICCHK
  m1=m2=237 consistent with the baseline, G11K-BACKPRESSURE PASS); top-level smoke Errors=6 baseline zero
  new (vlog -sv +define+SIM_MODE +incdir+..).
- Lessons: ① flow-control policy and source cadence are a coupled contract — the pacer's "send on arrival" implicitly assumes writes are bursty,
  so changing the source cadence requires re-reviewing the minimum packet length; ② rate-shape class defects (pps/packet length distribution) are beyond what functional-correctness
  tb criteria cover, and need explicit assertions or a board test; ③ probe interpretation must first check the packing granularity.
- Awaiting board test (user): 'v' pattern four-mode picture restored; pattern↔camera bidirectional switching; [2EC] fullrej=0;
  expected [31C] occ peak×4 ≈ 500-800, pps back to the camera order of magnitude.
