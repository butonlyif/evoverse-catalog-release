[中文](traceability.md) | English

# Spec → RTL → Test Traceability Matrix

**Model spec**: SPEC-DDR-AXI-MODEL-v0.2
**Implementation plan**: PLAN-DDR-AXI-MODEL-v0.1
**Date**: 2026-10-21
**Regression baseline**: 60/60 passed (tb_top 48 + tb_top_cdc 9 + tb_unit 3; run procedure frozen in `tb/regress.sh` + `testlist.txt`, re-run in Phase 8 on 2026-10-23, plan §9); `random_stress` 50 seeds (-sv_seed 2..51) all passed; RTL branch 99.5%, statement 99.7%, FSM 100% (coverage is a development-time baseline, not re-collected in Phase 8)

Status legend: **Complete** = implemented and covered by a targeted test; **Partial** = implemented but testing or semantics incomplete; **Deviation** = explicitly not implemented / different semantics; **N/A** = outside the model scope.

---

## 1. Interfaces and Parameters (spec chapters 5, 6, 20)

| Spec item | RTL implementation | Test/check | Status |
|---|---|---|---|
| 5.1 AXI global signals (ACLK/ARSTN) | `ddr_axi_model_top` ports; synchronous/CDC dual port shells | `smoke_reset`, `port_reset`, `tb_top_cdc` (ratio 1/2/4) | Complete (ACLK may be asynchronous when CDC_ENABLE=1) |
| 5.2 Write address channel | Top-level AW ports; `axi_port_shell` AW handshake | `aw_waits_wvalid`, `wr_incr` | Complete |
| 5.3 Write data channel | Top-level W ports; W FIFO (641 bit) | `wr_wstrb`, `wr_w_before_aw` | Complete |
| 5.4 Write response channel | B FIFO; `core_scheduler` B generation | `wr_single`, `early_b` | Complete |
| 5.5 Read address channel | Top-level AR ports; `axi_port_shell` | `reads`, `ostd_rd` | Complete |
| 5.6 Read data channel | R FIFO; `core_scheduler` beat generation | `reads`, `rd_narrow` (within reads) | Complete |
| 5.7 Config controller interface | `cfg_ctrl_fsm` | `smoke_cfg`, `cfg_sel` | Complete |
| 5.8 Controller status interface | `ddr_axi_model_top` status outputs | `smoke` | Complete |
| 5.9 Clock and reset | Port reset + CFG reset; `ddr_async_fifo` gray-pointer CDC | `smoke_reset`, `port_reset`, `port_reset_mid`, `cfg_sel`, `tb_top_cdc` | Complete (1:1/2:1/4:1 verified) |
| 6.1 Structural parameters | Top-level parameter list | Elaboration check (density/width/address width/CS_BIT) | Complete |
| 6.2 Memory capacity derivation | `MEM_BYTES` localparam; `calc_mem_bytes_per_channel` | `tb_unit_addr` density cases | Complete |
| 6.3 Performance parameters | `ARB_GRANT_INTERVAL`, `W_ACCEPT_INTERVAL`; `SYNC_LATENCY/ARB_LATENCY` retained only | `latency`, `ostd_*` | Partial: SYNC/ARB latency not modeled |
| 6.4 Latency parameters | `pick_lat` (xorshift32), `READ_LATENCY_MIN/MAX`, `LATENCY_MODE` | `latency`, `lat_fixed` | Complete |
| 6.5 BVALID timing parameters | `core_scheduler` early-return/deadline logic | `early_b`, `bvalid_modes` | Complete |
| 6.6 Error and boundary parameters | `check_cmd`, `core_scheduler` sticky errors, `ERR_INJECT_RATE` injection | `wr_errors`, `allstrb`, `err_inject`, `tb_unit_addr` | Complete (injection granularity is the whole command) |
| 6.7 Config and reset parameters | `cfg_ctrl_fsm`, `mem_model` | `smoke_cfg`, `cfg_sel`, `cfg_clear_mem`, `tb_unit_mem` | Complete |
| 20 Default parameter summary | Top-level defaults match the spec table | Code review | Complete |

## 2. AXI Behavior (spec chapter 7)

| Spec item | RTL implementation | Test | Status |
|---|---|---|---|
| 7.1 Global rules (VALID/READY handshake) | `axi_port_shell`, `core_scheduler` | All `ddr_model_assertions` cases | Complete (first assertion batch) |
| 7.2 AW channel; AWREADY depends on WVALID | `aw_req` in `axi_port_shell` (`WVALID \|\| !w_empty`) | `aw_waits_wvalid`, `wr_w_before_aw` | Complete (W-first relaxed, see user-guide §7) |
| 7.3 W channel; WREADY independent of AW | W FIFO and `wready` in `axi_port_shell` | `wr_w_before_aw`, `wr_wstrb` | Complete |
| 7.4 B channel; BID/BRESP | `core_scheduler` B generation, B FIFO | `wr_single`, `early_b`, `ostd_wr` | Complete |
| 7.5 AR channel | `ar_req` in `axi_port_shell` | `reads`, `ostd_rd` | Complete |
| 7.6 R channel; narrow lane | `core_scheduler` + `mem_model` | `reads` (narrow/WRAP/error) | Complete |
| 7.7 Burst rules (Table 5/4KB/WRAP/FIXED) | `table5_ok`, `cross_4kb`, `wrap_len_ok`, `check_cmd` | `tb_unit_addr`, `wr_errors`, `reads` | Complete |
| 7.8 Narrow and WSTRB | `lane_strobe`, `mem_model`, `tb_pkg::tb_wstrb` | `tb_unit_mem`, `wr_wstrb`, `reads` | Complete (invalid lane returns 0 as `[MODEL]`) |
| 7.9 Address mapping/capacity/rank | `rank_of`, `addr_field_decode`, `apply_addr_hole`, top-level `MEM_BYTES` | `tb_unit_addr`, `field_decode`, `addr_hole`, `addr_alias`, `addr_alias_cross` | Complete (includes FIELD_DECODE_DEBUG, DECERR/ALIAS address-hole policy) |
| 7.10 Error responses | `check_cmd`, `core_scheduler` error path, `err_inject` | `wr_errors`, out-of-range/4KB in `reads`, `allstrb`, `err_inject` | Complete |
| 7.11 Lock/Exclusive/QoS/Cache | Cache affects B timing; the rest ignored | `early_b`, `bvalid_modes` | Deviation: exclusive/QoS not modeled |

## 3. Arbitration, Queues, Latency, ID (spec chapters 8–11)

| Spec item | RTL implementation | Test | Status |
|---|---|---|---|
| 8.1 Dual-port round-robin | Arbitration combinational/sequential logic in `ddr_axi_model_top`; each port has an independent FIFO in CDC mode | `dual_port`, `arb_fairness`, `dir_arb`, `contend_multi` | Complete (both ports get a grant under contention) |
| 8.2 Arbitration parameters | `ARB_GRANT_INTERVAL`, `ARB_QUIET_FAST_PATH` | All cases; `arb_fairness` | Complete |
| 8.3 Arbitration assertions | `ddr_model_assertions` one-hot / grant-gap / request constraints | `arb_fairness` and all cases | Complete |
| 9.1 Queue abstraction | Per-direction command FIFO, per-port W/B/R FIFOs | `ostd_wr`, `ostd_rd` | Complete |
| 9.2 Backpressure rules | `cmd_space`, FIFO full, outstanding limits | `ostd_*`, `cmdq_full`, `wdataq_full`, `rdataq_full` | Complete |
| 9.3 Difference from the hard IP core | See user-guide §7 | — | Recorded |
| 10.1–10.3 Latency model | `pick_lat`, `core_scheduler` deadline | `latency`, `lat_fixed` | Complete (SYNC/ARB latency not modeled) |
| 10.4 Latency non-commitment | Parameterized/random | `latency` | Complete |
| 11.1 Outstanding counting | Counters in `axi_port_shell` | `ostd_wr`, `ostd_rd` | Complete |
| 11.2 ID management | `OUT_OF_ORDER_ENABLE` schedules by deadline; same port + same ID preserves sequence; optional R beat interleaving | `ooo_same_id`, `ooo_diff_id`, `ooo_interleave`, `ooo_b`, `ooo_b_same_id` | Complete (optional OOO) |
| 11.3 Response order assertions | BFM/scoreboard check BID/RID, same-ID order and interleaving | `ostd_*`, `reads`, `ooo_*` | Complete (BFM checks) |

## 4. CFG, Reset, Memory, Status (spec chapters 12–15)

| Spec item | RTL implementation | Test | Status |
|---|---|---|---|
| 12.1–12.2 CFG state machine | `cfg_ctrl_fsm` (IDLE/INIT/DONE) | `smoke_cfg`, `cfg_sel`, `tb_unit_cfg` | Complete (FSM state/transition coverage 100%) |
| 12.3 CFG parameters | `INIT_CYCLES`, `INIT_AXI_*` | `smoke_cfg`, `init_block`, `init_slverr` | Complete |
| 13 Reset model | `ARSTN_x`, `CFG_RESET`; the core discards unfinished commands | `smoke_reset`, `port_reset`, `port_reset_mid`, `tb_top_cdc` (cdc_rst) | Complete |
| 14.1 Memory structure | Sparse byte array in `mem_model` | `tb_unit_mem` | Complete |
| 14.2 Access rules (WSTRB/narrow read) | `mem_model` write enable/lane read | `tb_unit_mem`, `wr_wstrb`, `reads` | Complete |
| 14.3 Back door | `bd_write/bd_write64/bd_read/bd_clear/bd_used_bytes` | `tb_unit_mem` | Complete |
| 15 Status signals | Top-level `CTRL_INIT_DONE/READY/BUSY/ERR` | `smoke` | Complete (BUSY/ERR semantics simplified) |

## 5. Assertions and Verification Plan (spec chapters 16, 17)

| Spec item | Implementation | Status |
|---|---|---|
| 16.1 AXI protocol assertions | READY→VALID, VALID hold, B/R stability, WLAST/RLAST legality, B/R not earlier than command handshake | Partial (missing WDATA hold assertion) |
| 16.2 Manual rule assertions | `CFG_DONE→CFG_START`, CFG_RESET clears DONE, DONE sticky, CFG_RESET minimum width | Partial (missing 4KB/Table5/ALLSTRB assertions) |
| 16.3 Arbitration assertions | `a_arb_onehot`, `a_arb_grant_gap`, request and grant constraints | Complete |
| 16.4 Queue assertions | No SVA (FIFO overflow `$warning`); queue-full covered by BFM probes | Partial |
| 17.1 Manual example regression | `wr_incr`, `reads` (Figure 3/4 semantics), `early_b` | Complete |
| 17.2 Functional cases | See the `tb_top`/`tb_top_cdc` case tables | Complete (queue full, initialization blocking, OOO, CDC, port-reset interruption all covered) |
| 17.3 Address/capacity cases | `tb_unit_addr`, `wr_errors`, `reads`, `field_decode`, `addr_hole*` | Complete |
| 17.4 Performance trend cases | `latency`, `lat_fixed`, `r_gap`, `w_gap`, `cdc_wgap` | Partial (SYNC/ARB latency not modeled) |
| 17.5 Coverage points | UCDB + 8 functional covergroup instances | Partial (cross not pruned, bins 40.7%) |

## 6. Unit Test Mapping

| Function/module | Test | Key cases |
|---|---|---|
| `burst_bytes` / `table5_ok` / `cross_4kb` | `tb_unit_addr` | Boundary len/size, 4KB offsets 0xFF0/0xFF8/0xFFC |
| `wrap_len_ok` / `aligned_to_size` / `beat_addr` | `tb_unit_addr` | WRAP 2/4/8/16, wrap-around addresses, INCR/FIXED |
| `lane_strobe` | `tb_unit_addr` | Offsets 0/4/60/63 |
| `rank_of` / `calc_mem_bytes_per_channel` | `tb_unit_addr` | CS_STRIDE/CS_BIT/SINGLE, 2/4/16 Gbit |
| `make_cmd` / `check_cmd` / `resp_or` | `tb_unit_addr` | Legal, size7, len64, 4KB, FIXED, WRAP, alignment, out-of-range, ALLSTRB, narrow |
| `mem_model` write/read/back door/clear/init | `tb_unit_mem` | Full-block/partial strobe, narrow lane, RANDOM/PATTERN, CFG_RESET_CLEAR_MEM |
| `cfg_ctrl_fsm` | `tb_unit_cfg` | Initialization abort, START withdrawal after DONE, CFG_SEL, illegal state recovery, reset (FSM 100%) |
| `addr_field_decode` / `apply_addr_hole` | `tb_unit_addr`, `field_decode`, `addr_hole`, `addr_alias*` | CS bit, row fields, DECERR/ALIAS address hole |
| `ddr_async_fifo` / `axi_port_shell_cdc` | `tb_top_cdc` (ratio 1/2/4) | CDC read/write, outstanding, W gap, dual-port concurrency, SLVERR propagation, reset isolation |

## 7. Spec Chapters 18, 19, 21

| Item | Status |
|---|---|
| 18 Later measured parameters | N/A (board-level calibration, outside the simulation model scope) |
| 19 Deliverables | RTL, TB, sim scripts, docs, coverage reports all provided |
| 21 Assumptions and open items | See `user-guide.md` §7 and `plan.md` §10 |

---

## 8. Uncovered / To-Do List

1. The scheduler tie-break redundant scan branches at `core_scheduler.sv:148`/`:171` have no legal stimulus hit (2/376 branch), which does not affect functionality; keep the exemption or prove them formally later;
2. `ddr_fifo.sv:26/27` (continuous assignments of `full`/`empty`) are not triggered in some instances, statement 10/12, a tool-counting false gap;
3. `SYNC_LATENCY`/`ARB_LATENCY` are not modeled (the spec explicitly marks them as reference values);
4. Functional covergroup crosses are not pruned (132/324 bins = 40.7%); the ratio improves after removing unreachable combinations;
5. SVA for WDATA hold and 4KB/Table5/ALLSTRB is still missing (currently checked by targeted tests);
6. Board-level calibration of read/write/BVALID latency (per `ddr-test-spec-v0.2.md`).

Already added: asynchronous CDC (1:1/2:1/4:1), OOO read responses with same-ID ordering, R beat interleaving, address field decoding and address-hole policy, CFG FSM unit tests, port-reset interruption transactions, targeted cases for `R_BEAT_INTERVAL`/`W_ACCEPT_INTERVAL`, system-level `CFG_RESET_CLEAR_MEM`, arbitration one-hot/interval SVA, ERR_INJECT on both ports, WLAST early-return errors, 50-seed random stress.
