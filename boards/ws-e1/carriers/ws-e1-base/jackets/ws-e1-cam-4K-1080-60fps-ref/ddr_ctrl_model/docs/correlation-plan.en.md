[中文](correlation-plan.md) | English

# Model ↔ Board-Level DDR Controller Correlation Plan

**Goal**: run the same traffic generation (TG) and statistics (APM) RTL on both simulation (`ddr_axi_model_top`) and the board (TJ180 DDR hard core), compare the behavior, and backfill the model parameters.
**Basis**: `../ddr-test-spec-v0.2.md` (test component spec, "test spec" below), `../axi-ddr-model-spec-v0.2.md` (model spec, "model spec" below)
**Related project**: `../proj/` (standalone minimal DDR test project, see §5)
**Date**: 2026-10-22

---

## 1. Core methodology: one RTL copy, run on both sides

The traditional approach is "measure one set of numbers on the board, write another set of TBs for simulation"; the two sides use different definitions, so the comparison is untrustworthy. This plan mandates:

1. **TG/APM are written as a single RTL copy**, parameterized and instantiated on both sides:
   - Simulation side: a new TB `proj/sim/tb_corr.sv` (planned), DUT = `ddr_axi_model_top`;
   - Board side: `proj/rtl/ddr_test_top.sv`, DUT = the hard core `ddr_inst`.
2. **One authoritative traffic parameter table**: the TG configuration of each experiment (burst len/size, address stride, outstanding target, ID policy, rate) goes into the same parameter table, and neither side may change it on its own.
3. **Comparison quantities are defined at the AXI boundary**: `T_AR_FIRST_R`, `T_AW_B`, `T_WLAST_B`, `ostd_peak`, `bp_ratio`, `txn_issued/completed` (test spec §3.2/§3.3 definitions); all conversions use `CLK_RATIO_ACLK_PER_CTRL` (ideal value 0.125 for this project's x16 device, with measured frequency coverage).
4. Differences are not failures, they are outputs: each difference records "phenomenon/evidence/disposition" and goes into the §6 list or directly backfills a parameter.

## 2. Asset mapping: test spec components → existing assets in this project

| Test spec component | Spec chapter | Counterpart in this project | Status |
|---|---|---|---|
| TG (traffic generation) | §6 | `ddr_memcheck.v` (write pattern → read back and compare FSM, already a compliant AXI master) | Skeleton exists; needs OSTD/ID/rate control (§3.1) |
| APM (monitor statistics) | §5 | err_cnt/mcst counters inside memcheck + DIAG readout in `ddr_status_uart.sv` | Partly there; needs latency timestamps/histograms (§3.2) |
| ILA | §7 | Efinity Logic Analyzer (board only) | To be configured |
| Result readout | §5.8 | `ddr_status_uart.sv` 13-byte UART frame (115200, ~1.2 ms/frame) | Done |
| DUT initialization | §4 | `cfg_ctrl_fsm` v5 (CFG_START counts 2^21 cycles ≈10.49 ms) + `reset_ctrl` POR 256 cycles | Done (copied from the top_cam_demo board timing) |
| Isolated project | — | `proj/` (trimmed peri.xml + `ddr_test_top.sv`) | Done, smoke all green |

## 3. TG / APM modification requirements

### 3.1 TG (based on ddr_memcheck.v)

| Requirement | Current state | Modification |
|---|---|---|
| Programmable burst (LEN/SIZE/address stride) | Fixed sequence via the ALEN/ASIZE/START_ADDR/BURST_STEP parameters | Already parameterized, sufficient |
| OSTD control (mode A: incrementing TARGET_OSTD) | One issue, one collect (ARVALID deasserts right after the handshake) | Add an issue window: issue N ARs back-to-back, then collect; N is the sweep variable |
| ID policy (SINGLE/ROTATE) | Fixed ID | Add an ID counter, parameterize ID_COUNT (required for the 8.7 OOO calibration) |
| Rate control (FIXED_OSTD/FIXED_RATE) | Back-to-back | Add an INTERVAL_CYCLES issue-interval counter (for the 8.4 sweep) |
| 4KB safe address | Simulation definition MC_ALEN=63 (64 beat×64B=4096B, right at the limit) | Keep; the address stride generation needs a `cross_4kb` self-check (same predicate as `make_cmd` in the model spec) |

### 3.2 APM (based on memcheck/uart extensions)

| Requirement | Current state | Modification |
|---|---|---|
| `T_AR_FIRST_R` / `T_AW_B` / `T_WLAST_B` timestamps | None | Sample the AXI boundary handshakes into registers, accumulate min/peak |
| Histogram (P50/P95/P99) | None | Test spec §5.5 bin structure; **note that the 13-byte UART frame cannot hold a histogram** — histograms go through ILA capture or multi-frame fragmented readout; the UART frame reports only min/peak/counts |
| bp statistics (`AWVALID&&WVALID&&!AWREADY` real backpressure) | None | Bit counting / window cycle counting |
| DIAG bitmap (32 bit) | Exists (§5.3) | Reuse; spread the extended statistics over several frames in rotation (add a seq field inside the frame) |

## 4. Calibration flow mapping (test spec §8 as the skeleton)

| Phase | spec | Board operation | Simulation operation | Backfilled parameters (model spec §6.3/6.4) |
|---|---|---|---|---|
| 0 Baseline | §8.1 | Program the `proj/` bitstream, watch the UART until a frame reads `DDR:0000907e`, listen to the ILA for coarse values | `tb_proj_smoke.sv` four items (already green) | Initialization timing, AWREADY=WVALID precedence confirmed |
| 1 OSTD | §8.2 | TG mode A, TARGET 1→2→4→8→…, find the saturation point + bp>1% | Run the model with identical parameters | `READ/WRITE_OSTD_DEPTH_ENG` |
| 2 Latency | §8.3 | Low-load min (discard the first 100 warm-up) + high-load P99, sweep LEN/SIZE | Identical parameters | `READ_LATENCY_MIN/MAX`, `WRITE_RESP_LATENCY_MIN/MAX`, `WRITE_DATA_TO_B_LATENCY`, `SYNC_LATENCY` (multi-frequency fit, mark the fitted values) |
| 3 Queue depth | §8.4 | TG_MODE=3 fixed-rate read sweep over 9 levels ivl{256,128,64,32,16,8,4,2,1}×16 × 4KB transactions; on the board no backpressure within 16 transactions (bp all 0), if_peak saturation = sample cap 16 → record `CMD_QUEUE_DEPTH_ENG` as a lower bound ≥16, no parameter backfill (§6-10/§9) | Identical parameters, tb_proj_qd ALL PASS: blk3 (ivl=32) first backpressure, if_peak saturation 8 = shell `READ_OSTD_DEPTH` | `CMD_QUEUE_DEPTH_ENG`=lower bound ≥16 (low confidence); `READ_OSTD_DEPTH` stays 8 (ENG-form semantics) |
| 4 Arbitration | §8.5 | No ILA on the board → narrow the scope to a symmetric-traffic comparison: top with dual memcheck, identical parameters, TG_MODE=1 OSTD sweep (u_mc@target0 reports + u_mc2@target1 with the address offset by 32MB as load), single UART report port (port0) produces a 16-point rd_cyc curve, vs the Phase 1 single-port baseline (first round 2741, plateau 2284~2317) → dual-port degradation ratio | tb_proj_arb (CDC_ENABLE=1, ARB_GRANT_INTERVAL=2) dual-port 16-point full table ALL PASS: fairness ratio ≤1.075 (threshold 1.15), saturation degradation 1.17~1.34x; the characterization point G=8 and g_sync G=2/G=8 prove that `ARB_GRANT_INTERVAL` is **inert** in the board-level CDC form (the top arbiter is instantiated only for g_sync; the CDC path = 1:1 alternating collection + core_scheduler, §9 Phase 4) | `ARB_GRANT_INTERVAL` has no parameter to backfill (does not take effect in the CDC form, already noted in the spec §18 row); saturated throughput board 1.00x vs model 1.19x, first round board 1.72x vs model 1.03x → documented deviation (§9) |
| 5 B timing | §8.6 | 9-block `(AWCACHE,AWCOBUF)` matrix (the raw `1111` value deadlocks and is excluded from the matrix, see §6-6): blk0-8 = 0000±cobuf, 0001/0010/0011/0100/0111/1110±cobuf, all LEN=31, ostd=1, ×600 transactions (discard 100 warm-up) | Run the model with the same parameters (the TB explicitly sets `AWCOBUF_STRICT=0`) | `BVALID_CMD_QUEUE_DELAY`=28 (backfilled), `OTHER_AWCACHE_POLICY`=bit0 rule + `DATA_DONE` fallback, `BVALID_TIMING_MODE`=unused (retained) |
| 6 OOO | §8.7 | TG_MODE=4 back-to-back 16 transactions ×1MB scattered ×9 rounds, ID_COUNT=8 rotation (2 transactions per ID): board oo_cnt=0 (1079/1081 votes) → the real core **completes in order**, `OUT_OF_ORDER_ENABLE=0` retained (§9 Phase 6) | Two settings: OOO=0 main setting oo_cnt=0 ALL PASS (same-shape gate ✓); OOO=1 characterization setting oo_cnt=12 (the detector proves itself free of false negatives) | `OUT_OF_ORDER_ENABLE`=0 retained (board/sim same shape, high confidence) |
| 7 Address/rank | §8.8 | The board is confirmed to be a single rank 2Gb=256MB (peri.xml) → rank boundary/CS_BIT/non-power-of-2 are not applicable; narrowed to capacity boundary + out-of-range wrap-around probing: TG_MODE=5 nine probes {0, 256M-4K, 256M, 256M+4K, 512M, 1G, 2G, 4G-4K, 4G}, 4 serial transactions per round: write the Yi(=Xi mod 256M) reference → write Xi → read Xi (hi_err) → read Yi (compare against pattern(Xi), alias_err==0 = wrap-around pollution confirmed) | tb_proj_addr ALL PASS: legal probes (0,0); out-of-range 2-8 hi=64 (model SLVERR), 2-7 al=64 (write discarded, no pollution), 8 al=0 (fingerprint degenerates) | No parameter to backfill: the real core **silently wraps around** out of range (except the lone 1G point, which reports SLVERR) ≠ the model's DECERR, and the model has no wrap-around mode (§9 Phase 7); the 256MB capacity is confirmed by measurement |
| 8 Backfill | §8.10 | **Done**: Phases 1-7 finalized item by item (v0.2a-d), no new RTL default parameter replacements (the 4 latency/B-timing parameters were already backfilled in v0.2a, the rest keep the ENG form/inert/deviation) | traceability baseline regression **60/60 all green** (tb_top 48 + tb_top_cdc 9 + tb_unit 3; the run procedure is frozen in `tb/regress.sh`+`testlist.txt` with the per-case -g mapping); `random_stress` additionally run with -sv_seed 2..51, 50 seeds all passing (§9 Phase 8) | spec §22 v0.2e (regression gate closed, no parameter changes) |

Suggested execution order: 0 → 1 → 2 → 5 (B timing affects the definitions, better early) → 3 → 4 → 6 → 7 → 8.

## 5. Using the standalone proj/ project

`proj/` is a minimal DDR test project trimmed from the `ws-e1-cam-ddr-csi2-demo` main project. It keeps only the DDR hard core, the clock PLL and the UART readout, so that the calibration RTL has a clean host without the camera/display path.

### 5.1 Directory structure

```text
proj/
├── rtl/                     # Board-level RTL (6 files)
│   ├── ddr_test_top.sv      # Top level: POR + CFG FSM v5 + memcheck + UART
│   ├── ddr_memcheck.v       # TG prototype: write pattern → read back and compare (ARVALID handshake bug fixed)
│   ├── ddr_status_uart.sv   # DIAG readout: 13-byte frame 'DDR:'+8hex+'\n'
│   ├── reset_ctrl.sv        # POR reset chain (copied from the main project)
│   └── frame_writer/reader  # Spare (not part of the smoke compile)
├── sim/
│   └── tb_proj_smoke.sv     # Simulation smoke: DUT=ddr_axi_model_top (definition translation in the TB header comment)
├── ws-e1-ddr-test.xml       # Efinity project (top=ddr_test_top, 6 design files)
├── ws-e1-ddr-test.peri.xml  # Trimmed Interface Designer (DDR_0 + 2 PLL + clocks/GPIO/UART)
├── ws-e1-ddr-test.sdc       # 100M/200M/27M three clocks + clock_groups
├── work_syn/run_efx_map.sh
└── work_pnr/run_efx_pnr.sh, run_efx_pgm.sh
```

### 5.2 Build and simulation

- **Board build**: open `ws-e1-ddr-test.xml` in the Efinity IDE; from the command line run `work_syn/run_efx_map.sh` → `work_pnr/run_efx_pnr.sh` → `work_pnr/run_efx_pgm.sh` in that order.
- **Simulation smoke** (cwd=`proj/sim`, QuestaSim):

```text
vlog -sv -work work ../../rtl/ddr_model_pkg.sv ../../rtl/ddr_fifo.sv \
     ../../rtl/ddr_async_fifo.sv ../../rtl/mem_model.sv \
     ../../rtl/core_scheduler.sv ../../rtl/cfg_ctrl_fsm.sv \
     ../../rtl/axi_port_shell.sv ../../rtl/axi_port_shell_cdc.sv \
     ../../rtl/ddr_model_assertions.sv ../../rtl/ddr_axi_model_top.sv \
     ../rtl/reset_ctrl.sv ../rtl/ddr_memcheck.v ../rtl/ddr_status_uart.sv \
     ../rtl/ddr_test_top.sv tb_proj_smoke.sv
vsim -c -voptargs="+acc" -do "run -all; quit -f" work.tb_proj_smoke -l tb_proj_smoke.log
```

- **smoke four criteria** (currently all green):
  - P1: CFG_DONE=1, about 10.49 ms (2^21 cycles @200 MHz);
  - P2: mc_done=1, fail=0, err=0 (mcst=9 DONE);
  - P3: CTRL_ERR=0 (no sticky protocol errors);
  - P4: two consecutive UART frames `DDR:0000907e`.
- **`TB_DEBUG` probes**: when defined, enables memory transaction reconciliation and field-level ARpush/ARpop/RQ three-layer printing (for correlation debugging; off in daily regression).

### 5.3 UART readout definitions (board criteria)

- Frame format: `'DDR:' + 8 hex characters + '\n'`, 13 bytes total; each TX byte occupies 11 bit times (filler+start+8data+stop); at 115200 baud the frame length is ≈1.128 ms, and the frame interval is controlled by `UART_REPORT_TICKS` (default 2^23 cycles @100 MHz ≈ 84 ms).
- DIAG bitmap (32 bit, MSB→LSB): `{err_cnt[15:0], mcst[3:0], 5'h0, done_raw, cfg_st[1:0], lock, cfg_ok, done, fail}`
  - `err_cnt`: number of mismatch beats in the memcheck comparison; `mcst`: memcheck state (9=DONE);
  - `done_raw`: hard core `ddr_inst_CFG_DONE`; `cfg_st`: CFG FSM state; `lock/cfg_ok`: PLL lock/configuration done; `done/fail`: memcheck done/failed.
- All-pass frame = `0x0000907e` (err=0, mcst=9, done_raw=1, cfg_st=3, lock=1, cfg_ok=1, done=1, fail=0). **First board criterion: several consecutive frames stably output `DDR:0000907e`**.
- Note: reading the UART must consume all 13 bytes of a frame (including the trailing `\n`), otherwise the next frame is misaligned — the simulation TB has already been bitten by this, and host scripts must handle it too.
- TG sweep frame (`UART_SCAN_MODE=1`, from Phase 1 on): 8 hex characters = `{err_sat[7:0], rd_cyc[15:0], ostd[3:0], tgst[3:0]}`. `ostd` **4'h0=16** (the 16th round, the n6 bit); tgst: 9=DONE, A=TG_RD_REQ, B=TG_ROUND_GAP, 0=IDLE/CFG. Example `DDR:0008FC09` = err=0, rd_cyc=2300, ostd=16, DONE (**n5 is the low bit of rd_cyc, do not misread it as ostd**). The board sweep completes in ~58ms after bit loading, so frame capture must be started before programming (proj manual §3.2/§4.1).

## 6. Confirmed model/board definition differences (first batch of calibration inputs)

The following 4 entries were demonstrated in the `proj/` smoke co-simulation (2026-10-22); the calibration experiment design must digest them first, and the board experiments verify them one by one:

| # | Difference | Evidence | Disposition | Board verification pending |
|---|---|---|---|---|
| 1 | **AWCACHE=0000 → early B return (PHY_ISSUE, AW handshake+2 cycles)**: the model implements early B return as described in the manual; the main project's frame_writer with AWCACHE=0000 returns earlier than the expected B-after-WLAST | tb_phase4_ddrm first round deadlock/timing mismatch | On the TB side translate to AWCACHE=1111+COBUF=0 (WLAST+4 baseline definition); board B timing calibrated per 8.6. **Closed**: Phase 2 changed it to non-early return, Phase 5 finalized (the manual PHY semantics do not match the measurement, see §6-7/§9 Phase 5) | Closed (Phase 5 measured 0000 as non-early; B comes after the data commit) |
| 2 | **4KB rule enforced**: a model `cross_4kb`+`table5_ok` violation gives SLVERR and the **write data is dropped outright** (the scheduler does mem_we only when resp==OKAY); the board hard core tolerates memcheck's 3495×7680B 4KB-crossing configuration | smoke P2 err=480 → after changing to MC_ALEN=63 (64 beat×64B=4096B, right at the limit) err=0 | Performance-calibration traffic uniformly uses 4KB-safe parameters; 4KB-crossing behavior is calibrated separately per 8.9 (risk area) | The hard core's real response to 4KB-crossing bursts (SLVERR? silently tolerated?) |
| 3 | **QOS width convention**: the peri interface QOS pin is 1 bit (implicitly declared in top_cam_demo), the model takes 4 bits; wiring the TB's 4-bit line directly leaves the high bits floating | vsim-3015 port width error | Convention: the board's 1 bit is zero-extended `{3'b000,qos}` into the model; with model `ARB_QOS_WEIGHT_EN=0` the qos value has no functional effect | Confirm whether the hard core consumes qos (expected: no) |
| 4 | **ARVALID handshake discipline**: the model's `arready` is a combinational level (`arstn && arvalid && not full` always accepts), so an ARVALID held 1 extra cycle is **legally accepted twice** (2 commands per AR); the real hard core deasserts arready after the handshake, so board tests do not expose it | smoke P2 err=192 (the read stream is shifted by one whole command); ARpush appears in pairs | The proj copy of `ddr_memcheck.v` is fixed (in the READ_ADDR state `if (arvalid && arready) arvalid <= 1'b0;`); the original in `rtl/` is kept as reference evidence; **all calibration TGs must obey "deassert VALID the cycle after the handshake completes"** | No verification needed (a discipline issue), but note that the model is "more eager" than the hard core when calibrating OSTD/queue depth |
| 5 | **Ideal bandwidth vs real DDR efficiency**: once saturated the model needs ~1046 ACLK/round (8KB read, ≈1 beat/clk ideal service), while the board hard core needs 2300 ACLK/round once saturated (same traffic) — absolute throughput ~2.2× | 2026-10-22 board TG sweep: after ostd≥2 the rd_cyc plateau is 2284~2317 (±0.7%), err all 0 (§9 record) | The OSTD depth parameters do not carry this difference (board/sim saturation point both 2, gate PASS); absolute throughput belongs to the Phase 2/3 latency/efficiency calibration | Phase 2/3: read latency distribution, bandwidth efficiency measurement |
| 6 | **AWCACHE=1111 board AW/W deadlock**: the real hard core never completes the AW/W handshake for cache=1111 write commands | Phase 2 first version MODE2 (§8.3-4 baseline 1111) hangs the board at PRE_WRITE; `UART_SCAN_MODE=1` diagnostic frames report mc_state directly: 2933/2933 frames mcst=2; after changing to 0000, mcst=9 in 2933/2933 | MODE2 write baseline finalized at **0000** (annotated in the memcheck RTL; the deviation from §8.3-4 is recorded); the tb_proj_lat translation line changed to pass-through (model and board share one view) | Closed (Phase 5: 1111 is not in the matrix; the `BVALID_TIMING_MODE` implementation is unused, the bit0 rule is built in) |
| 7 | **On the board B comes after the write data commit (cache=0000, not early)**: WA≈WL (±1 cycle) and grows with LEN (21→57 ACLK), W-first (AWREADY granted only after all W is received, t_AW_acc≈t_WLAST_acc) | Phase 2 board table: at low load WA/WL grow together; the model's original cache=0000→early return (PHY_ISSUE) has the opposite sign to board B | Fix the model per the §7-4 B-timing gate: `cmd_is_early` cache=0000 → non-early (core_scheduler, B=data_done+WDTB path); write latency calibration definition set to **T_WLAST_B** (board WA degenerates to ≈WL, while model WA−WL≈30 cycles is the shell's per-cycle AW grant geometry difference and is not directly comparable) | Closed (Phase 5: bit0 rule finalized, `BVALID_CMD_QUEUE_DELAY`=28 backfilled, see §9 Phase 5) |
| 8 | **High-load structural difference**: board RD grows linearly with ostd (ostd16 min/max 1033/1118 ACLK ≈ 17×64 cycles/transaction = DDR bus serialization), board WL grows with LEN (21→56 ACLK, PHY commit ∝ data volume); the model's ideal service + constant WDTB can reproduce neither | Phase 2 board/sim comparison table (§9 Phase 2); after backfill the model-side OSTD saturation point moves 2→~6, so the board's saturation point 2 gate and the latency gate cannot both be satisfied under the current model structure | Record without backfill: read queueing/write commit time modeling belongs to the bandwidth-efficiency phase (Phase 3 or a dedicated task); `READ_OSTD_DEPTH` stays 8 (the Phase 1 conclusion is not challenged) | Bandwidth-efficiency phase: per-burst bus occupancy model |
| 9 | **The BB (count of B before WLAST) definition is an architectural difference, not comparable across sides**: on the board with W-first (AWREADY≥WLAST always holds, confirmed in §6-7) B can at the earliest come after the AW handshake → BB is always 0 (including the early-return encodings); the model shell is not W-first (grants AW per cycle) → BB varies with the early-return delay (with ENG delay=2, bit0=1 blocks have BB = all transactions; with the delay=28 calibration form B falls after WLAST → BB=0) | Phase 5 board 9 blocks BB all 0 (including the 0001/0011/0111 early blocks); model after delay=28 also BB 0 | BB is downgraded to pure recorded evidence (tb_proj_lat does not judge FAIL); the early-return sign criterion is carried by WA/WL statistics. **Test spec §8.6-3 B_BEFORE_WLAST judgment is always 0 on a W-first host and cannot serve as a sign criterion** (deviation from §8.6, recorded in §9 Phase 5) | No board verification needed (architectural property, already closed by measurement on both sides) |
| 10 | **The board has no shell gating layer, so the OSTD/command queue depth parameters have no counterpart on the real core side**: the board TG connects directly to the hard core peri interface (`ddr_inst_*`, no axi_port_shell_cdc), all 16 reads are accepted without backpressure, if_peak saturates at 16 = sample cap (TG_N_BURST); the model shell `READ_OSTD_DEPTH=8` fused gating (rd_ostd<8 participates in arready) → if_peak is capped at 8 and backpressure becomes observable from blk3 (ivl=32) | Phase 1 ≥16 concurrent with no backpressure + Phase 3 board 9 levels bp all 0/if_peak saturated 16 (§9 Phase 3) vs model blk3+ bp 454-882/saturation 8 | `CMD_QUEUE_DEPTH_ENG` is recorded as a **lower bound ≥16** (low confidence, the sample is only 16 transactions, the §8.4 first-backpressure criterion is undefinable on the board); `READ_OSTD_DEPTH=8`/`CMD_REQ_DEPTH=4` keep the ENG-form semantics without backfill (the Phase 1/§6-8 conclusions are not challenged); the §7-4 gate is not met and is handled as a "definition fix" — the parameters are shell/ENG-form, not real-core observable parameters | The real core's actual queue depth (needs TG_N_BURST>16 and most likely ILA to watch ARREADY, outside this period's budget) |

There is also a known contract (not a difference, a design basis): the hard core is WVALID-before-AWREADY (awqos write=1 read=0). Both the model and memcheck comply.

## 7. Parameter backfill table and gates

The target parameters are the union of model spec §18/test spec §8.10 (see the "Backfilled parameters" column of the §4 table). Backfill rules:

1. **Keep the original value**: rename every replaced default to `<PARAM>_ENG` and keep it on record (model spec §6.3 note).
2. **Conversion**: board-measured ACLK cycles → `× f_ctrl/f_ACLK` converted to ctrl_clk cycles before backfilling; report both definitions; the frequency ratio is measured, and a deviation from the ideal value >1% invalidates that window (test spec §10).
3. **Confidence annotation**: per the test spec §8.10 table (min class=high, P99/saturation class=medium, queue depth/SYNC_LATENCY=low).
4. **Backfill gates (suggested thresholds, revised after the first calibration)**:
   - OSTD/queue-depth class: board/sim saturation point difference ≤1;
   - Latency class: `_MIN` difference ≤2 ctrl_clk cycles; P99 relative difference ≤10%;
   - B-timing class: the order sign (B before/after WLAST) must agree for all four combinations; if not, stop and check the definitions before backfilling;
   - Any gate failure → the difference goes into the §6 list, fix the model or fix the definition; "cherry-picking the good numbers" is not allowed.
5. After backfilling, the model regression (traceability baseline 59 cases + smoke four items) must be all green before the work counts as done.

## 8. Risks and mitigation

| Risk | Mitigation |
|---|---|
| `proj/ws-e1-ddr-test.peri.xml` is a manual text trim, never opened and validated in Interface Designer | Open the peri in the IDE and re-save once before the first build; see the feasibility analysis (conversation record) |
| The UART at 1.2 ms/frame cannot carry histograms/latency distributions | Histograms go through ILA capture; the UART reports only min/peak/counts; extended statistics are sent over several frames in rotation |
| The TG extensions (OSWD/ID/rate) introduce new protocol bugs | Run the extended TG against the model in simulation first (same smoke criteria), then go to the board; write the ARVALID discipline into the code comments |
| The board memcheck 3495 burst configuration cannot be reproduced on the model (4KB difference) | List the simulation-definition parameters (4/63) and the board definition (3495/119) separately; correlation experiments uniformly use the 4KB-safe configuration |
| Dual-port arbitration calibration needs a second port traffic source | The proj peri already keeps dual target; instantiate the TG twice and reuse the same RTL on port 1 |

## 9. Calibration record

### Phase 1: OSTD saturation calibration (2026-10-22, board measurement vs simulation)

**Configuration** (board=sim, same parameters): TG_MODE=1, TG_N_BURST=16 (16×4KB AR per round), ALEN=63 (64 beats), TG_OSTD_MAX=16, TG_ROUND_GAP_TICKS=400_000 (2ms@200M), UART_REPORT_TICKS=320_000 (1.6ms/frame). On the board, capture is started 60s before JTAG programming; the whole window had 20205 frames with no loss.

**Board sweep table** (sampled during TG_ROUND_GAP, rd_cyc = read time of this round in ACLK cycles, err_sat all 0):

| ostd | 1 | 2 | 4 | 5 | 6 | 8 | 9 | 10 | 12 | 13 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| rd_cyc | 2741 | 2317 | 2316 | 2306 | 2284 | 2285 | 2300 | 2315 | 2284 | 2308 | 2315 | 2300 |

(Rounds 3/7/11/14 were skipped by the 1.6ms frame cadence and not sampled; the plateau within ±0.7% is taken as the saturation value.) The final-state frame `DDR:0008FC09` (ostd=16 i.e. 4'h0, DONE) is stable ×14088. The IDLE/CFG period is ~25.6ms (16 frames).

**Simulation comparison** (same parameters, Questa, `PROJ TG ALL PASS`): rd_cyc 1412 (ostd=1) → 1046 (ostd=2) → plateau 1044~1061.

**Verdict**:

- Board saturation point = 2; simulation saturation point = 2; **difference 0 ≤ 1, §7 gate PASS**.
- All 16 board rounds completed in flight, err all 0, rd_cyc showed no rise → the hard core's read acceptance concurrency is **≥16 with no visible backpressure**.
- **Backfill conclusion: `READ_OSTD_DEPTH` keeps the default 8, not replaced**. Rationale: the board evidence only gives an acceptance depth lower bound (≥16) > 8, so the existing default is not challenged; the saturation point is set by the bandwidth bottleneck (board = real DDR efficiency, sim = 1 beat/clk ideal service), and changing the depth to 2 would introduce backpressure that does not exist on the board. Per §7-5, no parameter replacement means no regression re-run is required.
- Confidence: saturation class = medium (§7-3).
- Absolute throughput difference ~2.2× (plateau 2300 vs 1046 ACLK/round) → recorded as §6 difference 5, assigned to the Phase 2/3 latency/efficiency calibration.

**Process lessons** (now frozen into the code comments and the proj manual): the final-state frame `0008FC09` was once misread as ostd=12 (n5 is the low bit of rd_cyc); "reprogramming without restarting the sweep" actually means capture was started only after programming, missing the ~58ms sweep window; JTAG is volatile, so after a power cycle the bit is gone and the serial port stays silent.

### Phase 2: Latency calibration (2026-10-22, board measurement vs simulation)

**Configuration** (board=sim, same parameters, TG_MODE=2): 9 measurement blocks run automatically in rotation — blocks 0-4 low load (ostd=1) LEN={1,3,7,15,31} beats; blocks 5-8 high load LEN=31, ostd={4,8,12,16}; each block writes then reads N transactions (LOW_N=2000/HIGH_N=10000), discarding the first 100 of each phase as warm-up; addresses 4KB page aligned +0x1000/burst; definitions T_AR_FIRST_R / T_AW_B / T_WLAST_B; histogram 32bin×64 cycles (range 0..2047). TG_ROUND_GAP=400_000 (board 2ms@200M)/2000 (sim 10µs). Readout: `UART_SCAN_MODE=2` lat_word rotating frames `{blk,set,kind,done,0,data}`, majority-vote decoding with `uart_lat_decode.ps1` (note: the `.ps1` must be UTF-8 with BOM, otherwise PS5.1 parses the Chinese comments as GBK and corrupts the param block).

**Process points**:

1. **Board done=0 diagnosis** (§6-6): all frames done=0 is not slowness but a hang — temporarily switch to `UART_SCAN_MODE=1` to output a diagnostic bit; the low 4 bits of the SCAN frame report `mc_state` directly (2933 frames constantly mcst=2=PRE_WRITE) → isolation experiment (awcache 1111→0000) → mcst=9. Two compile rounds located the root cause; lesson recorded: MODE2 frames do not contain mc_state, so for hang-type problems output the SCAN_MODE=1 diagnostic bit first.
2. **Definition fix**: tb_proj_lat's `0000→1111` translation line meant the model never saw the board baseline (hence the anomaly of two simulation rounds with identical results) — changed to pass-through; smoke/tg keep the original translation (their definitions are independent).
3. **B-timing sign fix** (§6-7): on the board the cache=0000 B comes after the data, while the model had early return — fixed `cmd_is_early`; afterwards the simulation write-phase duration is of the same order as the board (memcheck write phase serial per burst), tb_proj_lat `TMO_MEAS` 150→300ms.
4. **smoke parameters pinned**: as the top defaults evolved TG_MODE/UART_SCAN_MODE to 2, smoke P2/P4 mis-judged (it ran the full MODE2 measurement) — tb_proj_smoke explicitly overrides `TG_MODE=0 / UART_SCAN_MODE=0` to pin the Phase 0 form. Lesson: a TB should not inherit evolving top default parameters.

**Board statistics table** (`uart_p2_final.txt`, 30s capture, 10996 frames 100% done=1, 0 bad frames; fail=0, err_tot=0; cnt all equal N−100, ovf=0; every cell 52/53 votes fully consistent. Unit ACLK cycles):

| Block | len | ostd | RD min/max | WA min/max | WL min/max | RD P50/P99 (bin bounds) |
|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 24/61 | 21/54 | 21/54 | 64/64 |
| 1 | 3 | 1 | 23/61 | 25/67 | 24/66 | 64/64 |
| 2 | 7 | 1 | 24/60 | 30/73 | 29/72 | 64/64 |
| 3 | 15 | 1 | 24/61 | 39/74 | 38/73 | 64/64 |
| 4 | 31 | 1 | 23/61 | 57/100 | 56/99 | 64/64 |
| 5 | 31 | 4 | 199/302 | 57/100 | 56/99 | 256/320 |
| 6 | 31 | 8 | 465/535 | 57/100 | 56/99 | 512/576 |
| 7 | 31 | 12 | 767/838 | 57/100 | 56/99 | 832/832 |
| 8 | 31 | 16 | 1033/1118 | 57/100 | 56/99 | 1088/1152 |

Low-load RD min/max is identical across all LEN (read latency is independent of burst length, first-beat definition); WA/WL grow with LEN (B waits for the data commit); high-load RD is linear in ostd (§6-8).

**Simulation comparison** (tb_proj_lat ALL PASS after backfill, ctrl≈ACLK definition): RD low load 192/487-488 (P99 bin boundary 512); high load blk8 219/488; WA 478/479; WL 448/449; miss=0, CTRL_ERR=0.

**Backfill** (`rtl/ddr_axi_model_top.sv`, conversion ×8 = 1/CLK_RATIO_ACLK_PER_CTRL 0.125, board ACLK=200MHz; original values kept as `_ENG` localparam):

| Parameter | Original ENG value | Backfilled value | Board basis | Gate (§7-4) |
|---|---|---|---|---|
| READ_LATENCY_MIN | 10 | **191** | low-load RD min 24 ACLK → 192 ctrl | sim 192, difference 0 ≤2 ✓ |
| READ_LATENCY_MAX | 30 | **492** | low-load RD max 61 ACLK → 488 ctrl | sim 487-488, difference ≤1; P99 bin boundary 512=512 ✓ |
| WRITE_RESP_LATENCY_MIN/MAX | 8/24 | retained | cache=0000 is no longer early-return, the B deadline is dominated by the data path; board WA is not directly comparable because of the W-first anchor geometry (§6-7) | — |
| WRITE_DATA_TO_B_LATENCY | 4 | **451** | WL(LEN=31) min 56 ACLK → 448 ctrl (blk4-8 min identical) | sim 448 exact ✓ |

Confidence (§7-3): MIN class=high (consistent across LEN); MAX/P99=medium (bin-boundary quantization); WDTB=high (blk4-8 min all 56).

**Deviations from test spec §8.3** (recorded item by item, no cherry-picking):
- §8.3-4 write baseline 1111/COBUF=0 → board deadlock, changed to 0000 (§6-6);
- §8.3-3 `READ_LATENCY_MAX` = high-load P99 → infeasible: a uniform latency + ideal service model cannot satisfy the low-load max and the high-load P99 at the same time (board high-load P99=1152 bin/9216 ctrl, model only 512 bin with the same parameters — §6-8 structural difference). Backfilled with the low-load max, the high-load deviation is recorded in §6-8;
- §8.3-1 BURST_SIZE sweep (2,4,6) → explicitly not done: the board data shows read latency is independent of burst length (first-beat definition); the SIZE dimension is expected to behave analogously and would require new sweep bits, deferred until there is a need;
- §8.3-6 SYNC_LATENCY multi-frequency fit → deferred to a later phase as planned (at the single 200MHz point the READ backfill already includes the total latency; frequency decomposition needs multi-frequency board measurement).

**Regression** (all green after backfill + model changes): tb_proj_smoke **ALL PASS** (P1-P4, `0000907e`×2); tb_proj_tg **ALL PASS** (16 rounds err=0, CTRL_ERR=0; the model-side OSTD curve rises overall with the latency backfill, saturation point 2→~6, recorded in §6-8); tb_proj_lat **ALL PASS** (P1-P5, 9 blocks cnt=N−warmup, ovf=0, err=0).

**traceability 59-case regression**: to do (model spec regression set, run together before the Phase 8 summary).

### Phase 5: B timing calibration (2026-10-23, board measurement vs simulation)

**Configuration** (board=sim, same parameters, TG_MODE=2 measurement framework reused): 9-block `(AWCACHE,AWCOBUF)` matrix — blk0=0000/0 (Phase 2 baseline re-test), blk1=0000/1 (the core COBUF increment), blk2-6=0001/0010/0011/0100/0111/0, blk7-8=1110/0 and 1110/1; all LEN=31, ostd=1 serial (unambiguous B attribution), 600 transactions per block (discard the first 100 warm-up → 500 samples). The raw `1111` value deadlocks board AW/W (§6-6) and is not in the matrix; the TB-side model explicitly sets `AWCOBUF_STRICT=0` (STRICT is an unverified hypothesis; the baseline does not presume rejection). Readout: `UART_SCAN_MODE=2` lat_word, set=3 adds BB (count of B before WLAST); `uart_lat_decode.ps1` extended with the cache/cobuf matrix table (note the .ps1 must be UTF-8 with BOM; without BOM PS5.1 parses the Chinese comments as GBK and swallows bytes).

**Decisive finding: B timing is determined solely by AxCACHE[0] (Bufferable)**:

- bit0=1 (0001/0011/0111 measured identical on the board): **early return**, T_AW_B = AW handshake +4-5 ACLK, WL=2 cycles — B is far earlier than the data-path scale;
- bit0=0 (0000/0010/0100/1110 measured identical): **non-early return**, B comes after the write data commit (WA/WL 55-99 ACLK, consistent with the Phase 2 LEN=31 blocks);
- COBUF has no independent effect (blk1/blk8 statistics are identical to their cobuf=0 twin blocks);
- The manual's `[UG]` semantics "0000 → B after the command is sent to the PHY (early return)" is **disproved** by measurement (§6-1 closed).

**Board statistics table** (`proj/uart_p5_final.txt`, 4399 frames, majority votes 15-16/15-16; fail=0, err_tot=0; cnt all 500, ovf=0. Unit ACLK cycles):

| blk | cache/cobuf | WA min/max | WL min/max | BB | Reading |
|---|---|---|---|---|---|
| 0 | 0000/0 | 56/98 | 55/97 | 0 | baseline (consistent with Phase 2) |
| 1 | 0000/1 | 56/98 | 55/97 | 0 | COBUF has no effect |
| 2 | 0001/0 | **4/5** | **2/2** | 0 | early return |
| 3 | 0010/0 | 56/98 | 55/97 | 0 | non-early |
| 4 | 0011/0 | **4/5** | **2/2** | 0 | early return |
| 5 | 0100/0 | 56/99 | 55/98 | 0 | non-early |
| 6 | 0111/0 | **4/5** | **2/2** | 0 | early return |
| 7 | 1110/0 | 56/91 | 55/90 | 0 | non-early |
| 8 | 1110/1 | 56/91 | 55/90 | 0 | COBUF has no effect |

RD across all blocks min 23-24 / max 59-61 (reads are unaffected by the write cache encoding, the Phase 2 definition reproduces). For the BB-all-0 reading see §6-9: under W-first even an early B does not cross WLAST (W finishes → AW handshake → B+2-4 cycles), so the early-return signature is a **sharp drop in WA**, not BB>0.

**Model-side comparison** (tb_proj_lat ALL PASS after backfill, ctrl≈ACLK 1:1 definition, board values ×8 converted to ctrl for comparison):

- bit0=1 blocks (blk2/4/6): WA 32/33 (board 4-5 ACLK ×8 = 32-40, **difference ≤2 gate ✓**), WL 1/3 (board 2×8=16 is an order-of-magnitude difference but the same "far smaller than the data path" sign, see deviation 3), BB=0 (same shape as the board);
- bit0=0 blocks: WA 478/479, WL 448/449 (the Phase 2 backfill definition is retained, unaffected by this phase);
- P1/P2/P4/P5 all PASS, miss=0, CTRL_ERR=0.

**Backfill** (`rtl/core_scheduler.sv` + `rtl/ddr_axi_model_top.sv`, original ENG values kept as localparam):

| Item | Original ENG value | Final | Board basis | Gate (§7-4) |
|---|---|---|---|---|
| `cmd_is_early` criterion | manual combination (0000 early) | **`AWCACHE[0]` bit0 rule**: bit0=1 early; with `OTHER_AWCACHE_POLICY!=DATA_DONE`, bit0=0 falls back to early; 1111+cobuf explicitly early | 9-block sign 100% consistent | four-combination sign gate → 9-block sign gate, fully consistent ✓ |
| `BVALID_CMD_QUEUE_DELAY` | 2 | **28** | board T_AW_B 4-5 ACLK ×8 = 32-40 ctrl; model CDC structure ≈4 → 28+4≈32 aligns the min | sim WA min 32, difference 0 ≤2 ✓ |
| `OTHER_AWCACHE_POLICY` | `DATA_DONE` (semantics "always non-early") | default keeps `DATA_DONE`, but the semantics change to **fallback**: it applies only to bit0=0 encodings; bit0=1 is always early and unaffected by this parameter | bit0=1 blocks measured early on the board | — |
| `BVALID_TIMING_MODE` | `MANUAL_STRICT` | implementation unused (the bit0 rule is built in), parameter retained for compatibility | — | — |
| `AWCOBUF_STRICT` | 1 | keeps the default 1 (conservative); blk1/blk8 prove COBUF has no effect on B timing and STRICT does not affect behavior; TB calibration traffic explicitly overrides to 0 | 0000/1110 × cobuf all identical | — |
| `BVALID_PHY_ISSUE_DELAY` | 2 | keeps the ENG value; used only by the `PHY_ISSUE` fallback policy, not triggered on the default path | — | — |

**Deviations from test spec §8.6** (recorded item by item):

1. §8.6 four-combination matrix (1111/0000 × cobuf) → raw 1111 deadlocks and is untestable (§6-6), scope narrowed to a 9-block matrix (1111 covered only by 1110 + model extrapolation);
2. §8.6-3 `B_BEFORE_WLAST` as the B early-return sign criterion → **always 0 on a W-first host, unusable** (§6-9); the sign criterion moves to WA/WL statistics and BB is downgraded to pure recording;
3. Board early blocks have WL=2 cycles vs the model's WL 1/3 ctrl: the missing W-first in the model makes the wl anchor geometry different (model WA−WL≈31 is the shell's AW grant geometry difference, recorded in §6-7); the calibration definition uses WA as the early-return anchor, and the sign and magnitude (within the ≤2 gate after ×8) are already aligned.

**Coverage**: 7 of the 16 encodings measured on the board (0000/0001/0010/0011/0100/0111/1110, ×cobuf taking 9 blocks), 9 untested encodings (0101/0110/1000/1001/1010/1011/1100/1101/1111) extrapolated by the bit0 rule — bit0 is anchored on both sides by bit0=1 (0001/0011/0111) and bit0=0 (0000/0010/0100/1110), and the upper 3 bits show no effect in the measurements (0100 vs 0000, 0111 vs 0011, 1110 vs 0010 identical), so the extrapolation confidence is medium-high; the raw `1111` deadlock is likewise extrapolated to early return by bit0=1 (model semantics only, unreachable on the board).

**Regression** (all three TBs green after the Phase 5 model changes, 2026-10-23): tb_proj_smoke **ALL PASS** (P1-P4); tb_proj_tg **ALL PASS** (16 rounds err=0); tb_proj_lat **ALL PASS** (9-block matrix + bit0 rule verdict fully aligned with the board).

**traceability 59-case regression**: to do (run together before the Phase 8 summary).

### Phase 3: Queue depth calibration (2026-10-23, board measurement vs simulation)

**Configuration** (board=sim, same parameters, TG_MODE=3 adds a fixed-rate read sweep; reuses the MODE1 round structure + the MODE2 lat_word report mechanism): 9 injection-interval levels ivl ∈ {256,128,64,32,16,8,4,2,1} ACLK (blk0-8), each round TG_N_BURST=16 4KB reads (ALEN=63, RID=issue sequence number 0-15 rotating, equivalent to §8.4 `ID_MODE=ROTATE`), no OSTD gating on the issue side — the next transaction is issued only after the qd_gap divider reaches 0 (reload ivl-1 on the handshake cycle), with no in-flight cap; write baseline AWCACHE=0000 (§6-6, POST_WRITE path along MODE0/1); TG_ROUND_GAP=2000 cycles to change rounds. Each round finally latches the four fields rd_cyc/bp_cnt/if_peak/err, sent directly through lat_word (set=0, kind 0-3 rotating) with UART_SCAN_MODE=2, decoded by `uart_lat_decode.ps1 -Phase 3` majority vote. The board top default form changed to TG_MODE=3.

**Frame-capture timing lesson** (quantified reproduction of the §3.2/§4.1 discipline): the first 30s window of 9835 frames were all old-bit MODE2 final-state frames (efx_run.bat PYTHON initialization + JTAG programming ~20s+ exhausted the window; set bits uniformly distributed over 0-3 is the confirmed MODE2 signature); a 60s window with programming delayed by 3s fixed it. The final `proj/uart_p3_final.txt` has 21991 frames, badfmt=0 (all set bits legal = MODE3 signature), each key 550 votes highly consistent, fail=0, err_tot=0.

**Board statistics table** (cyc unit ACLK@100MHz cycles; bp=AR backpressure cycles, ifp=in-flight peak):

| blk | ivl | cyc | bp | ifp | Reading |
|---|---|---|---|---|---|
| 0 | 256 | 4021 | 0 | 1 | injection-limited (≈15×256 + tail transaction service) |
| 1 | 128 | 2301 | 0 | 3 | service 144 cycles/transaction > 128, already on the plateau and slowly backing up |
| 2 | 64 | 2285 | 0 | 10 | backing up (injection 64 < service 144) |
| 3 | 32 | 2300 | 0 | 13 | backing up |
| 4 | 16 | 2301 | 0 | 15 | backing up |
| 5 | 8 | 2316 | 0 | 16 | saturated = sample cap (TG_N_BURST) |
| 6 | 4 | 2299 | 0 | 16 | same as above |
| 7 | 2 | 2300 | 0 | 16 | same as above |
| 8 | 1 | 2284 | 0 | 16 | same as above (continuous injection still zero backpressure) |

**Model-side comparison** (tb_proj_qd same parameters ALL PASS, 2026-10-23; cyc unit ctrl@200MHz cycles, in the TB ACLK=ctrl=200MHz out of phase 1:1):

| blk | ivl | cyc | bp | ifp |
|---|---|---|---|---|
| 0 | 256 | 4356 | 0 | 3 |
| 1 | 128 | 2372 | 0 | 5 |
| 2 | 64 | 1476 | 0 | 8 |
| 3 | 32 | 1463 | 454 | 8 |
| 4 | 16 | 1459 | 656 | 8 |
| 5 | 8 | 1313 | 664 | 8 |
| 6 | 4 | 1420 | 801 | 8 |
| 7 | 2 | 1430 | 871 | 8 |
| 8 | 1 | 1455 | 882 | 8 |

Model-side structure: `arready = arstn && arvalid && (rd_ostd<8) && !ar_cmd_full` (shell fused gating, rd_ostd decrements only on RLAST) → if_peak capped at 8=READ_OSTD_DEPTH, backpressure observable from blk3; service-limited plateau ~1313-1463 (8 concurrent ideal service).

**Comparison reading**:

1. **Qualitatively isomorphic**: the cyc "injection-limited (≈N×ivl + tail transaction service) → service plateau" two-segment shape, if_peak climbing monotonically → saturation shape, err all 0 — both sides agree ✓;
2. **Structural difference (new in §6-10)**: the board TG connects directly to the `ddr_inst_*` hard core peri with no shell gating layer → no AR backpressure within 16 transactions, and the if_peak saturation of 16 is the sample cap rather than capacity; the model goes through the shell (OSTD=8) → capped at 8 + observable backpressure. The 16 vs 8 saturation difference is a **path structural difference**, not a parameter mis-calibration;
3. **Plateau values**: board ~2300 ACLK@100M ≈ 144 cycles/transaction, independently reproduced consistent with the Phase 2 RD plateau 2284-2317 (§6-5) ✓; model ~1455 ctrl@200M ≈ 91 cycles/transaction (≈45.5 ACLK@100M equivalent) — an absolute time ratio of ~3.1×, in the same direction as §6-5's 2.2× (8KB definition), assigned to the §6-8 bandwidth-efficiency phase and not handled here.

**Backfill and gates**:

- §8.4 target parameter `CMD_QUEUE_DEPTH_ENG`: no backpressure at all within 16 board transactions → "first backpressure IN_FLIGHT" is undefinable, recorded as a **lower bound ≥16** (low confidence, §7-3; the sample is only 16 transactions/round);
- `READ_OSTD_DEPTH` stays 8: there is no OSTD gating layer on the board and board 16 is not a capacity measurement, so the Phase 1/§6-8 conclusions are not challenged; the shell `CMD_REQ_DEPTH=4`/`READ_OSTD_DEPTH=8` keep the ENG-form semantics, no parameter replacement;
- The §7-4 gate "queue-depth class board/sim saturation point difference ≤1" is **not met** (16 sample cap vs 8 structural gate) → difference §6-10, handled as a "definition fix" (the parameters are shell/ENG form, not real-core observable parameters), the model is not modified.

**Deviations from test spec §8.4** (recorded item by item):

1. §8.4-1 write baseline `AWCACHE=1111` → **0000** (§6-6 board deadlock confirmed, following the Phase 2/5 finalization);
2. §8.4-1 `BURST_LEN=3` → ALEN=63 (4KB at the limit, §6-2 disposition, consistent with Phase 1/2);
3. §8.4-1 `ID_MODE=ROTATE` → RID=issue sequence number 0-15 (rotation within 16 transactions, equivalent);
4. §8.4-1 read-only→write-only→mixed → board read-only only: with bp all 0, write-only is expected to be the same shape (the real core has the same queue without backpressure), the information gain is low and the UART budget is limited; add it later if the Phase 8 summary requires data separation;
5. §8.4-3 `bp_ratio`/`bp_first_cycle`/`ostd_peak` multiple fields → under the UART bandwidth constraint the four fields rd_cyc/bp/if_peak/err are sent in rotation (following the Phase 2 lat_word mechanism, §5.3 definition);
6. §8.4-4 first-backpressure criterion → there is no backpressure on the board, so the criterion degenerates to the "no backpressure within 16 transactions" conclusion + the if_peak saturation value definition; `CMD_QUEUE_DEPTH_ENG ≈ max(IN_FLIGHT at first true backpressure)` can only take a lower bound on this host.

**Coverage**: the ivl dimension is fully covered with 9 levels (256→1 halving); the in-flight dimension is limited by the TG_N_BURST=16 sample cap, so queue depths >16 are unobservable (leave to Phase 8 to evaluate whether to raise TG_N_BURST for a re-test, which requires evaluating the err field rotation bandwidth at the same time).

**Regression** (all three TBs green after the Phase 3 RTL changes, 2026-10-23): tb_proj_smoke **ALL PASS** (P1-P4); tb_proj_tg **ALL PASS** (16 rounds err=0); tb_proj_lat **ALL PASS** (9-block matrix verdict unaffected by MODE3). The MODE3-added branches are all `TG_MODE==3` gated, the MODE0/1/2 paths show no regression change, and changing the top default form to TG_MODE=3 does not affect the explicit TB overrides.

### Phase 6: OOO calibration (2026-10-23, board measurement vs simulation)

**Configuration** (board=sim, same parameters, TG_MODE=4 adds OOO probing; reuses the MODE3 qd_gap issue mechanism): before the first round, write 16×4KB (ALEN=63, **addresses spread with a 1MB stride across banks/rows**, §8.7-1), then 9 read-only rounds: each round 16 **back-to-back** transactions (qd_ivl=1, no in-flight cap, creating maximum concurrency), **ID_COUNT=8 rotation** — issue order s has arid=s[2:0] (0..7,0..7, 2 transactions per ID, §8.7 `ID_MODE=ROTATE`). Completion side: same-ID order is preserved (AXI contract) → the per-ID completion counter `id_comp` derives the completion issue sequence (two transactions with the same ID share the rid slot; the data comparison picks the earlier/later transaction in order via `rid_addr[seq]`); out-of-order criterion (§8.7-3): the j-th completed transaction has `rid[2:0] != j[2:0]` → cross-ID out-of-order, oo_cnt++, oo_first latches the first mismatch {rid,seq}. Report: lat_word blk always 0 (9=status word), kind 0=oo_cnt 1=oo_first 2=done 3=err; `uart_lat_decode.ps1 -Phase 6` decodes.

**Incidental fix**: the top's memcheck instantiation truncated `TG_MODE[1:0]` to 2 bits — MODE4(=4) would have become a MODE0 self-test; changed to `[2:0]` (found before the Phase 6 compile, the wrong bit was never programmed).

**Model-side two settings** (tb_proj_ooo, `-gMODEL_OOO` parameterizes the model `OUT_OF_ORDER_ENABLE`, both settings ALL PASS, 2026-10-23):

| Setting | Model OOO | oo_cnt | oo_first | done | err | Reading |
|---|---|---|---|---|---|---|
| Main | 0 | **0** | — | 16 | 0 | the model completes in order (consistent with the parameter) |
| Characterization | 1 | **12** | {rid=2,seq=0} | 16 | 0 | the model's OOO path completes out of order; **the detector proves it can detect out-of-order** (no false negative), and with out-of-order the per-ID derived comparison has err=0 (proof of derivation correctness) |

**Board measurement** (`proj/uart_p6_capture.txt`, 20199 frames; the first ~22s are old MODE3 bit final-state frames (before programming completed), blk1-8 counted by the Phase 6 filter as badfmt=11536 (expected); the valid MODE4 segment has **1079/1081 votes** per key):

| oo_cnt | oo_first | done | err | Status word |
|---|---|---|---|---|
| **0** | {0,0} (no mismatch, default value) | 16 | 0 | fail=0 err_tot=0 (4321 votes) |

**Comparison reading**: the board real core **completes in order** (with all 16 concurrent, completion order = issue order), the same shape as the model main setting (OOO=0) → §7 gate "board/sim same shape" ✓, `OUT_OF_ORDER_ENABLE=0` retained, no parameter replacement.

**Deviations from test spec §8.7** (recorded item by item):

1. §8.7-1 `FIXED_OSTD, TARGET_OSTD=8` → back-to-back with no in-flight cap (concurrency 16 ≥ 8, stronger observability; Phase 3 already proved the real core accepts all 16 with zero backpressure);
2. §8.7-1 "read-dominated" → read-only (the write-direction BID observation and the mixed traffic §8.7-4 were not tested, board budget prioritized; the read/write completion networks are independent inside the real core, so the read-direction conclusion extrapolates to the write direction with medium confidence);
3. §8.7-3 same-ID order detection → no board-side detection (the AXI contract enforces order; two completed same-ID transactions carry no distinguishing information; the model-side out-of-order path guarantees correct data comparison via id_comp derivation);
4. §8.7-5 coverage note: **"no out-of-order observed" ≠ "never out of order"** — this experiment covers single-port read, 16 in flight, 1MB address spread, 2 same-ID transactions back-to-back; the possibility of out-of-order under larger in-flight/cross-port/mixed read-write is not excluded, and the applicability domain of `OUT_OF_ORDER_ENABLE=0` is bounded by this.

**Coverage**: read direction 16 transactions ×9 rounds ×board/sim sides; address spread 1MB stride (bank/row interleaving); ID topology 8 IDs × 2 transactions. The write direction and dual-port OOO are not covered (§8.7-4 deviation).

**Regression**: tb_proj_ooo both settings ALL PASS (2026-10-23); the smoke/tg/lat three TBs are re-run together in the Phase 8 summary (the memcheck MODE4 branch is all `TG_MODE==4` gated, expected to be unaffected).

### Phase 7: Address/rank/capacity calibration (2026-10-23, board measurement vs simulation)

**Scope reduction** (peri.xml L134 confirms `physical_rank="1" mem_type="LPDDR4x" mem_density="2G"`): single rank, 256MB, and a power of two → the test spec §8.8 rank boundary sweep, `CS_BIT_POS`, and non-power-of-2 density linear sweep are **all not applicable**; narrowed to **capacity boundary + out-of-range wrap-around (aliasing) behavior probing**.

**Configuration** (board=sim, same parameters, TG_MODE=5 adds capacity/alias probing): nine probes blk0-8 = {0, 256M-4K, 256M, 256M+4K, 512M, 1G, 2G, 4G-4K, 4G(bit32)}; 4 **serial** transactions per round (ostd=1, eliminating concurrency interference): write the Yi(=Xi mod 256M=Xi&0x0FFF_FFFF) reference (pattern(Yi)) → write the Xi probe → read Xi (compare pattern(Xi); hi_err>0 = not storable/SLVERR) → read Yi (**rid_addr[1] stores Xi so the comparison basis stays pattern(Xi)**; reading back pattern(Xi) proves the Xi high bits were masked off and the write landed at Yi, polluting the reference, alias_err==0). Probes 0/1 (Xi==Yi) degenerate the alias detection, so hi_err decides; probe 8 degenerates the fingerprint (pat takes only the low 32 address bits, pat(4G)==pat(0)), the alias bit is only recorded. MODE5 does not set the global fail (an out-of-range err is an expected observation); report lat_word blk=probe number (9=status word), kind 0=hi_err 1=alias_err 2=addr[15:0] 3=addr[31:16] (bit32 does not fit the 16-bit report, probe 8 address shows the low 32 bits); `uart_lat_decode.ps1 -Phase 7` decodes.

**Model side** (tb_proj_addr ALL PASS, 2026-10-23; the known model behavior = out-of-range SLVERR + write discard, core_scheduler L314 stores only when `resp==RESP_OKAY`, the mem_model sparse array has no mask):

| Probe | Address | hi_err | alias_err | Reading |
|---|---|---|---|---|
| 0/1 (legal) | 0 / 256M-4K | 0 | 0 | accessible (capacity ≥256M-4K) |
| 2-7 (out of range) | 256M~4G-4K | 64 | 64 | SLVERR, the write is dropped and Yi is not polluted |
| 8 (bit32) | 4G | 64 | 0 | SLVERR; the alias fingerprint degenerates, only recorded |

P4 cross-check: CTRL_ERR=1 (SLVERR sticky) + bresp!=OK=7 (1 B per out-of-range write) + rresp!=OK=448 (7 probes×64 beats).

**Board measurement** (`proj/uart_p7_capture.txt` 20205 frames; the first ~25s of old MODE3 bit final-state frames and the MODE5 frames share the blk 0-9/kind 0-3 shape, so the Phase 7 filter cannot distinguish them → decode the pure post-programming segment `proj/uart_p7_pure.txt` 12000 lines, every key **300/300 votes fully consistent**, 9 repeated sweeps stable with no flips):

| Probe | Address | hi_err | alias_err | Reading |
|---|---|---|---|---|
| 0/1 (legal) | 0 / 256M-4K | 0 | 0 | accessible |
| 2 (256M) | 0x1000_0000 | 0 | 0 | **wrap-around alias** (the write lands at Yi and pollutes it; the read-back pattern(Xi) matches completely) |
| 3 (256M+4K) | 0x1000_1000 | 0 | 0 | wrap-around alias |
| 4 (512M) | 0x2000_0000 | 0 | 0 | wrap-around alias |
| 5 (1G) | 0x4000_0000 | **64** | **64** | **SLVERR (the only error point in the whole table)** |
| 6 (2G) | 0x8000_0000 | 0 | 0 | wrap-around alias |
| 7 (4G-4K) | 0xFFFF_F000 | 0 | 0 | wrap-around alias (modulo 256MB = Yi exactly, pure low-bit truncation) |
| 8 (4G) | 0x1_0000_0000 | 0 | 0 | wrap-around alias (bit32 presumably truncated at the port) |

**Comparison reading**: board/sim **not the same shape** (the only such phase) — the model's out-of-range = SLVERR + write discard, the real core's out-of-range = **silent wrap-around** (except the lone 1G point). Key points:

1. **The 256MB hard capacity boundary is confirmed by measurement**: the last legal page 256M-4K is accessible (hi=0), from 256M upward the high bits are masked (probe 7's 4G-4K wraps exactly to Yi=256M-4K), consistent with peri.xml's 2Gb single rank → `RANK_MAP_MODE`/`CS_BIT_POS`/`PHYSICAL_RANK` need no change.
2. **Wrap modulus = 256MB** (probes 7/8 confirm [27:0] low-bit truncation semantics), and the real core has **no protection** for out-of-range access.
3. **The mechanism of the lone 1G SLVERR is unresolved**: non-monotonic (2G/4G both wrap), which rules out a pure truncation model; without an ILA on the board it cannot be dug deeper, so the observation is recorded as is. 300/300 votes over 9 rounds stably rule out a sporadic event.
4. **Backfill decision: no parameter to replace**. The model spec `ADDR_HOLE_POLICY=ALIAS` semantics do not match (effective only with FIELD_DECODE_DEBUG + an explicit hole window, ddr_model_pkg apply_addr_hole; the spec states "ALIAS is for testing only and must not be the default"), and the capacity out-of-range path (check_cmd ERR_ADDR_RANGE) hardcodes SLVERR with no switch. **Keep `ADDR_HOLE_POLICY=DECERR`**, and record a documented deviation: out-of-range behavior model = explicit error (protective direction, can expose test program bugs), real core = silent aliasing (false-negative direction) — no effect on the legal region (<256MB) behavior; all TG/application addresses run in this project are <256MB, so the deviation is never reached.

**Deviations from test spec §8.8** (recorded item by item):

1. §8.8-2 rank boundary sweep → not applicable (single-rank board configuration, confirmed by peri.xml);
2. §8.8-3 non-power-of-2 density → not applicable (a 2G die is naturally a power of two);
3. §8.8-4 CS modes → not applicable (single rank, no CS interleaving to test);
4. §8.8-1 "the latter should either error or wrap, record the DUT behavior" → completed as DUT behavior recording (mostly wrap-around + one lone 1G point);
5. §8.8-5 backfill `RANK_MAP_MODE`/`ADDR_HOLE_POLICY` → both keep their original values (the former configuration already matches, the latter has no matching semantics), no parameter replacement.

**Coverage**: single-port serial 4KB bursts ×9 probes ×9 rounds ×board/sim sides; the capacity boundary is accurate to page granularity. The out-of-range granularity is only 4KB-aligned probes (not a per-address sweep); the 1G lone-point mechanism, an independent write-direction verification (the read-back depends on the write landing, indirectly covering writes), and dual-port out-of-range are not covered.

**Regression**: tb_proj_addr ALL PASS (2026-10-23); the smoke/tg/lat three TBs are re-run together in the Phase 8 summary (the memcheck MODE5 branch is all `TG_MODE==5` gated; the other mode paths only had the issue gating condition equivalently rewritten (`TG_MODE>=3` narrowed to `==3||==4`), MODE0-4 behavior unchanged, expected to be unaffected).

### Phase 4: Dual-port arbitration calibration (2026-10-23, board measurement vs simulation)

**Scope reduction** (test spec §8.5 originally assumed ILA capture of the grant sequence): there is no ILA probe on the board → narrowed to a **symmetric-traffic completion rate comparison**. The top changes to a dual memcheck form: u_mc@target0 (report port) + u_mc2@target1 (`START_ADDR=0x0200_0000` offset by 32MB, pure load), same-parameter TG_MODE=1 OSTD sweep 16 points×16 4KB transactions, symmetric address layout; the single UART report port (port0 view) outputs sweep frames (`UART_SCAN_MODE=1`, 1.6ms/frame) → port0 rd_cyc per point vs the Phase 1 single-port baseline (first round 2741, plateau 2284~2317, same parameters same definition) → **dual-port degradation ratio**.

**Model side** (tb_proj_arb, CDC_ENABLE=1, the board-corresponding form, `ARB_GRANT_INTERVAL=2` default main setting; ALL PASS 2026-10-23):

- Main setting 16-point full table: P1 CFG_DONE, P2 dual-port done=1 fail=0 (err all 0), P3 CTRL_ERR=0, **P4 fairness PASS** (saturation points ostd 8-15 dual-port ratio ≤1.075, threshold 1.15). Saturation points rd_cyc0=1729/rd_cyc1=1662, **dual/single degradation 1.17~1.34x** (single-port baseline 1293~1483). Curve shape: first round ostd=1 dual-port 6649/6818 (vs single-port 6442 = **1.03~1.06x**) → after ostd=4 into the plateau 1978~2339.
- **ARB_GRANT_INTERVAL characterization (key structural finding)**: the `-gARB_G=8` characterization setting is **bit-identical** to the main setting. RTL review confirms: the dual-port arbiter (round-robin + cooldown) this parameter belongs to is instantiated only in the `g_sync` (CDC_ENABLE=0) generate branch (ddr_axi_model_top L307-441); **the board-corresponding CDC form (CDC_ENABLE=1) does not pass through that arbiter** — the CDC collection logic is a fixed 1:1 alternation (`ar_last/aw_last` anti-starvation, port0 priority + last toggle, L591-664), at most one command per direction per cycle enters the shared cmd queue, and the only throttle is `CMD_QUEUE_DEPTH`. The g_sync-form characterization setting (clocks changed to same-source 200MHz, G=2/G=8) is likewise bit-identical → under this TB's traffic the parameter affects neither form's result. **Conclusion: `ARB_GRANT_INTERVAL` is an inert parameter for this project's usage form, with no parameter to backfill; the CDC dual-port scheduling same-shape criterion rests on "1:1 alternation + fairness ratio"**.
- TB sampling fix: the saturation point (ostd=16→4'h0) has no ostd incrementing edge (memcheck goes straight to DONE at MAX), so the done rising edge is stored additionally; the `tab_vld` initial value changed to 1 (ostd reset value=1, the first edge is the 1st round completion), fixing the lost sample at the ostd=1 point.

**Board measurement** (2026-10-23, 3 programming runs capturing frames; start capture before programming):

| Programming | REPORT_TICKS | Sweep-window frames | ostd covered |
|---|---|---|---|
| 1/2 (identical bit) | 320_000 | 12 frames each | 1-7,10,12,13,15,16 |
| 3 (340_000 shifts the sampling phase to fill points) | 340_000 | 12 frames | 1,2,3,4,5,7,9,10,12,13,15,16 |

The programming→reset→CFG IDLE frame (`00000010`)→sweep frames→final state (`0008FC09`/`0008ED09`) sequence is deterministic, and two programming runs with the same parameters miss the same points (frame-round phase determinism). Merged **13/16 points**, always missing 8/11/14 — none of the three sampling phases landed on them, they sit in the plateau region (the neighbors 6/7/9/10/12/13/15 are all flat at 2284~2315), no impact on the criterion, recorded as is. All frames err=0, final state done fail=0.

**Board port0 curve** (rd_cyc, cycles) and degradation ratio:

| ostd | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 9 | 10 | 12 | 13 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| rd_cyc | 4707/4738 | 4326/4310 | 3893/3909 | 3732/3720 | 3320/3159 | 2300/2284 | 2300/2315 | 2284 | 2300/2315 | 2285/2284 | 2300/2299 | 2300/2315 | 2300/2285 |
| dual/single (vs 2741/plateau) | **1.72** | 1.58 | 1.42 | 1.36 | 1.21 | 1.00 | 1.01 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |

**Board/sim comparison reading** (degradation ratio definition, dual vs single at the same ostd):

1. **Saturation points not the same shape**: board dual-port saturation shows **zero degradation** (2300 vs the single-port plateau 2284~2317, DDR bandwidth is enough for dual-port concurrency); the model CDC dual-port degradation is 1.17~1.34x. **The model is conservative** (pessimistic direction, predicts a bandwidth lower bound, the safe side for engineering) — recorded as a documented deviation. Mechanism: the model CDC collects 1 command per direction per cycle + shared-queue contention queues in core_scheduler; the real core's dual-port scheduling is more fully concurrent for saturated symmetric traffic.
2. **First round/low points not the same shape (reverse)**: board dual-port first round 1.72x (cold start/refresh alignment and other real-core factors stack with dual-port contention); model 1.03x (mem_model has no refresh/power-management interference, so the first-round penalty is cancelled by the two ports running in parallel). **The model is optimistic** (the non-conservative direction); the first round is transient rather than converged bandwidth, so its impact on bandwidth prediction is confined to the startup segment.
3. **Fairness criterion (P4 equivalent)**: model saturation dual-port ratio ≤1.075; the board's single report port cannot measure the fairness ratio directly, but dual-port zero degradation at saturation itself shows no port starvation (if one port were starved, port0 degradation should be ≥2x) → board fairness is indirectly evidenced by the degradation ratio, compatible with the model fairness conclusion.
4. **Backfill decision: no parameter to replace**. `ARB_GRANT_INTERVAL` stays 2 (g_sync-only semantics, the spec §18 row annotated "does not participate in arbitration when CDC_ENABLE=1, measured"); `ARB_QUIET_FAST_PATH` is retained (the fast path's zero cooldown for a single port is already indirectly evidenced by the Phase 1/3 single-port full throughput).

**Deviations from test spec §8.5** (recorded item by item):

1. §8.5-1 ILA capture of the grant sequence → not applicable (no ILA on the board), scope narrowed to the symmetric-traffic degradation ratio (this record);
2. §8.5-2 `ARB_GRANT_INTERVAL` sweep and backfill → the parameter is inert in the CDC form (structural), a sweep is meaningless, recorded as g_sync-only;
3. §8.5-3 direct fairness measurement → the board has no second report port, replaced by the indirect evidence "dual-port zero degradation ⇒ no starvation";
4. §8.5-4 board/sim same-shape gate → the degradation ratios are not the same shape (saturation/first round are reversed), recorded as a documented deviation (the conservative/optimistic directions differ, the absolute magnitudes are small, mostly transient).

**Coverage**: dual-port symmetric read traffic (same-parameter 16-point OSTD) on both sides; the write direction was not swept separately (the MODE1 round includes a write setup and write contention is masked by read dominance); asymmetric load (one port heavily loaded, one lightly), QOS-differentiated arbitration, and real g_sync-form dual-port contention (the characterization setting shows that form's arbiter was not triggered) are not covered.

**Regression**: tb_proj_arb four settings (CDC G=2 main, CDC G=8, g_sync G=2/G=8) ALL PASS (2026-10-23); the top dual memcheck change was verified by tb_proj_arb board-form simulation (MODE1 path); the smoke/tg/lat three TBs are re-run together in the Phase 8 summary (adding u_mc2 to the top is an additive change, single-port TBs instantiate their own top and are unaffected).

### Phase 8: Backfill summary and baseline regression (2026-10-23)

**Scope**: execute the §7-5 regression gate (full traceability baseline + smoke four items), consolidate the Phase 1-7 backfill decisions, and freeze the baseline run procedure (the original regress.sh/testlist.txt were lost; rebuilt in this round).

**Summary conclusion**: Phases 1-7 were finalized item by item in spec §22 v0.2a-d — v0.2a already backfilled `READ_LATENCY_MIN/MAX` (191/492), `WRITE_DATA_TO_B_LATENCY` (451), `BVALID_CMD_QUEUE_DELAY` (28) and fixed core_scheduler's 0000 non-early return; the remaining parameters keep the ENG form/defaults after board measurement (Phase 1/3/6/7) or are recorded as inert/deviation (Phase 4/7). **Phase 8 has no new RTL parameter replacements**; the gate action is full regression verification.

**Regression process** (tb/ main environment, Questa 2024.2):

- First run 46/60: the 14 fails were attributed to two groups — group A, 11 cases, lost baseline -g parameter mappings (re-derived case by case after regress.sh was lost); group B, 3 cases (early_b/wlast_err/allstrb_early), TB expectation drift after the v0.2a "AWCACHE=0000 non-early" finalization, all passing after the expectations were updated.
- Root causes of the 5 stubborn fails (all green after the fix, recorded for reference):
  1. **wlast_err**: a TB check logic defect — with `wlast_mode=2` WLAST never arrives, BFM `last_b_before_wlast = !wlast_sent` (axi_master_bfm L231) is trivially 1, and the original check expecting 0 was always false. Changed to expect 1 (semantics = confirm that on the 0000 path B did return with SLVERR; early/non-early discrimination is meaningless here).
  2. **init_slverr**: `INIT_AXI_RESP` semantics are **0=BACKPRESSURE, 1=SLVERR** (ddr_axi_model_top L79/L233-234); passing 2 disabled both init_block and init_slverr (the write was accepted as a normal write, stored, and returned OKAY). Correct run: `-gINIT_AXI_RESP=1`.
  3. **addr_hole**: three overlapping causes — ① the hole feature is active only under `ADDR_MAP_MODE=1` (FIELD_DECODE_DEBUG) (`hole_en = (ADDR_MAP_MODE==1) && END>START`, ddr_axi_model_top L208); ② the previous round's window value was off by 16× (0x300_0000 vs the 0x030_0000 segment where the test stimulus lives); ③ `ADDR_HOLE_POLICY` semantics **0=DECERR, 1=ALIAS** (ddr_model_pkg L349). Correct run: `-gADDR_MAP_MODE=1 -gADDR_HOLE_START=3145728 -gADDR_HOLE_END=3145984` (POLICY defaults to 0).
  4. **addr_alias**: same as above, and the window is designed as a single 64B (START=0x0300_0040, END=+0x40) — alias remaps the write to linear 0x0000_0000, and a second linear read verifies the alias landing point (tb_byte is sensitive only to the low 8 address bits). Correct run additionally sets `-gADDR_HOLE_POLICY=1`.
  5. **rdataq_full**: the real bottleneck is the shell read OSTD, not the command queue — while RREADY=0, `rd_ostd` only grows (`rlast_hs` needs RREADY consumption, axi_port_shell L220), so the AR acceptance cap = READ_OSTD_DEPTH=8, matching bit for bit the previous log's "9th AR timeout + 8 R drain timeouts". Correct run: `-gCMD_QUEUE_DEPTH=16 -gREAD_OSTD_DEPTH=32`.
- **The "vsim -g does not work" mystery clarified**: -g/-G never stopped working (INIT_AXI_RESP/OUT_OF_ORDER_ENABLE/ERR_INJECT_RATE/ADDR_MAP_MODE and the same batch of parameters all took effect). The root cause of all 4 "ineffective" cases was a missing companion parameter or wrong parameter-value semantics. Lesson recorded: **multi-parameter -g mappings must be scripted and frozen; hand re-derivation is forbidden** — executed (see below).

**Baseline freeze** (to prevent another loss):

- `tb/testlist.txt`: 60-case table (top|test|-g parameter three columns), including all per-case parameter mappings and window value comments;
- `tb/regress.sh`: full compile + per-case simulation per the testlist + PASS/FAIL summary (exit code gate); supports Git Bash/WSL (Questa PATH auto-discovery + `.exe` wrapper), stdin isolated (the vsim swallowing the testlist pitfall);
- Reproduction verification: **60/60 all green** (2026-10-23 11:57, one-click re-run);
- `tb/seeds_stress.sh`: random_stress multi-seed sweep, `-sv_seed 2..51`, 50 seeds all PASS (the stimulus genuinely varies: writes 21~29, duration 14565~15675ns).

**Gate verdict**: §7-5 satisfied — 60 cases all green + the smoke four items already green earlier (proj/sim tb_proj_smoke, Phase 0). TB-side changes are only three case expectation updates and one check fix, **no RTL changes**; the traceability.md baseline row is updated accordingly (59→60 count: 48+9+3).

**Remaining**: 4 vlog-2600 RDGN warnings in tb_top_cdc (redundant literal width, tb_top_cdc L358-368, harmless, left alone); the coverage data is the development-time baseline (99.5%/99.7%/100%), not re-collected in Phase 8.
