[中文](phase1-summary.md) | English

# Phase 1 Summary — frame_writer v3 (Frame Handshake Output + Semantic Fix + Unit TB)

> Status: **Core completed (2026-10-21)** · Spec: SPEC-001 mod-frame-writer-v3 / alg-bank-handoff · Verification level: FPGA_INTEGRATION (roles: main-flow / protocol / cdc prerequisites)

## 1. Goal

Provide write-side support for the architecture v4 frame-level drop/repeat mechanism: frame_writer emits a **single-cycle frame publication pulse** (crossed through 2 FFs into the 148.5M display domain, serving as the reader's only frame request signal), and guarantees the pulse's **atomicity semantics** — at the pulse moment, that frame has been fully written into DDR.

## 2. RTL changes (rtl/frame_writer.v, minimally invasive)

### 2.1 New `wr_frame_done_o` (the core of v3)

- **Pulse position: the drain side**, emitted on the bvalid completion beat of the last line of the frame's desc (`drn_line==VACT-1`).
- **Why the frame pulse is not closed on the fill side**: when the frame is closed on the fill side, the drain queue (8 line slots) is still lagging by up to 8 lines, so a reader that takes the edge and reads the bank will read a frame that is not fully written → violates R3 (whole-frame atomicity). The drain-side pulse moment = the completion beat of the B response of that frame's last AXI write transaction, and the read side is safe at that moment.
- **Why the desc judgement is reliable**: bad frames (drop_mode) do not enter the desc queue → `drn_line==VACT-1` in desc necessarily belongs to a complete frame, occurring exactly once per complete frame.
- Implementation: inside the drain always block it is cleared to 0 by default each cycle; on the `b_cnt==1` dequeue beat of `D_POSTWR` it is set to 1 according to `drn_line`; reset clears it to 0.

### 2.2 Mid-frame sof semantics fix (a v2 leftover defect, required by the v4 discipline)

- **v2 behavior**: a mid-frame sof → restart in place as a new frame, but the sof line (new frame line 0) is dropped by drop_mode → the restarted frame lacks line 0 yet is published as usual → **the content is off by one frame, violating R3**.
- **v3 behavior**: the original frame's line ledger is rewritten in place (the original frame never has a VACT-1 completion beat → **it is naturally never published**); the sof line is received normally as the new frame's line 0 → the restarted frame is complete and publishable. `bad_cnt` still counts (kept for diagnostics).

### 2.3 Top-level wiring (rtl/top_cam_demo.sv)

- The `u_fw` instantiation gains `.wr_frame_done_o(fw_frame_done)`; the wire declaration gains a comment (the 2FF route into the 148.5M domain belongs to the Phase 4 integration).

## 3. Unit TB (sim/tb_frame_writer.sv, newly created)

- A shortened frame VACT=270 (the module is parameterized; the 960-beat line structure is unchanged); 8 frames + dead backpressure on the 3rd frame (manufacturing a q_full bad frame) + a mid-frame sof injection at line 100 of the 5th frame (the generator's line ledger restarts in sync + a one-shot guard).
- AXI slave: awready random delay 0~5 cycles, wready random backpressure, exactly 1 B response per burst (the cycle after the wlast handshake); an `mem_model[addr]` associative array records the data, and on frame publication every word is compared by fingerprint (`exp_word`: a fixed-slot stream-slice model, isomorphic to the packing code).
- The expected-value function is isomorphic to the DUT packing formula (beat0 is the LSB, word w = bitstream [512(w+1)-1 : 512w]).

## 4. Verification results

| Check | Result | Notes |
|---|---|---|
| V1 pulse count / single-cycle property | **PASS** | 7/7 (8 frames - 1 bad frame), no two consecutive cycles |
| V2 data integrity (mild backpressure form) | See §5 | Per-word fingerprint |
| V3 bad frames are not published | **PASS** | Dead backpressure → ovf=35/drop=178, that frame has no pulse, subsequent frames recover |
| V4 mid-frame sof restarted frame published atomically | **PASS** | bad_cnt=2 (1 injected + 1 bad frame), the restarted frame is published complete |
| V5 AXI contract | **PASS** | Bursts do not cross 4KB, awlen exact, awqos=1, wlast aligned |

## 5. Finding: an existing writer bug (burst1 data bit errors, TODO-419)

- **Symptom**: in every line, **burst1 (word64~74, the 704B line tail, 11 words) is deterministically entirely wrong**; burst0 (word0~63, 64 words) is entirely correct. The error distribution is 270 lines × 11 = 2970/frame, bit-for-bit identical frame after frame, **independent of backpressure strength** (the 20% strong backpressure and 2% mild backpressure forms produce exactly identical results).
- **Sample**: exp_hi=`10defeaa` / act_hi=`aa10deca` (a deterministic bit misalignment, not a dropped beat — the V5 counts are all correct).
- **Isolation**: the drain data path `D_PREWR → D_WADDR → D_PREWR` (burst1) has residual mem prefetch / rd advancement. v1.1 once fixed the D_WRITE missing advancement ("burst1 first word duplicated"); this bug is a **deterministic content misalignment** variant of the same family.
- **Why board testing did not expose it**: a real DDR controller hardly ever backpressures WREADY (in the board-test form wready≈constant 1), so the TB's random backpressure is the first to cover that path.
- **Impact assessment**: the board-level playback producing correct images shows that most data is correct in the real form (little backpressure) — but the bit errors are deterministic, so a waveform-level fix plus regression is required before delivery (TODO-419).
- **Unrelated to the v3 change**: v3 only adds the handshake output and the sof semantics, and does not touch the drain data advancement.

## 6. Rollback point / outstanding items

- The TB slave model carries two fixes of its own (extra B responses, AW bubble wrongly clearing in_burst) — AXI slave modelling notes are commented inside the code.
- `FRAME_WRITER=0` + `DDR_P1_148=1` still holds (the Phase 0 form); set it back to 1 at the Phase 4 integration.
- drop_cnt semantics clarification: the writer's `bad_cnt` (abandoned bad frames) is exactly the fw-side drop of spec R9; the reader side has its own drop/repeat (frame request arbitration), implemented in Phase 2.
