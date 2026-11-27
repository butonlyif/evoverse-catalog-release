[中文](user-guide.md) | English

# TJ DDR AXI Behavioral Model User Guide

**Document number**: UG-DDR-AXI-MODEL-v0.3
**Implementation baseline**: SPEC-DDR-AXI-MODEL-v0.2 (**v0.2e**, including correlation Phase 0-8 board calibration) / PLAN-DDR-AXI-MODEL-v0.1
**Simulator**: QuestaSim 2024.2
**Date**: 2026-10-21 (v0.2) / 2026-10-23 (v0.3, synchronized with the spec v0.2e baseline)
**Status**: v0.2 functional model (synchronous + asynchronous CDC, OOO, field decode/address holes), regression 60/60 passing (Phase 8 baseline frozen), random_stress 50 seeds passing; the parameter semantics of BVALID timing, latency, arbitration applicability domain etc. have been updated per the board calibration (v0.2a-e)

> **v0.3 revision highlights** (against spec v0.2a-e): `AWCACHE=0000` finalized as non-early, B timing = `AWCACHE[0]` bit0 rule; `READ_LATENCY_MIN/MAX`=191/492, `WRITE_DATA_TO_B_LATENCY`=451, `BVALID_CMD_QUEUE_DELAY`=28 backfilled from the board; `ARB_GRANT_INTERVAL`/`ARB_QUIET_FAST_PATH` annotated as effective only on the `CDC_ENABLE=0` path; the regression directory/run procedure updated to `tb/regress.sh` + `testlist.txt` (60 cases).

---

## 1. Overview

`model/` implements an AXI slave behavioral model of the TJ series DDR hard-core controller for SoC/FPGA system simulation. The model covers:

- 2 AXI4 slave interfaces (target 0/1), 33-bit address, 512-bit data, 64-bit WSTRB, 6-bit ID;
- AW/W/B/AR/R channels, INCR/WRAP bursts, narrow transfers, WSTRB;
- a shared command queue, dual-port round-robin arbitration, per-port outstanding limits;
- parameterized read latency, write response latency, BVALID timing;
- optional asynchronous CDC (1:1, 2:1, 4:1 and a slow ACLK), so the AXI ports and the controller core can run at different frequencies;
- optional out-of-order responses (`OUT_OF_ORDER_ENABLE`): reads return by deadline, the same port and same ID stay in order, and `R_INTERLEAVE_ENABLE` supports burst interleaving;
- address field decode debugging (`ADDR_MAP_MODE=1`) and address hole policy (DECERR / ALIAS);
- the CFG_RESET/CFG_START/CFG_SEL/CFG_DONE initialization handshake;
- a sparse byte storage array, capacity/rank decoding, address legality checking;
- a self-checking BFM, scoreboard, protocol assertions and directed regression.

The model **does not include** DDR PHY electrical behavior, LPDDR4 command timing, refresh/bank conflicts, training, or configuration register address mapping, and it does not guarantee cycle-level equivalence with the real hard core.

## 2. Directory and files

Actual layout of this project (`ddr_ctrl_model/`; the `model/sim/` of the original delivery plan has been replaced by `tb/`):

```text
ddr_ctrl_model/
├─ rtl/
│  ├─ ddr_model_pkg.sv        enums, structs, burst/4KB/lane/rank functions
│  ├─ ddr_model_if.sv         AXI interface (used by the TB)
│  ├─ ddr_fifo.sv             synchronous FIFO
│  ├─ ddr_async_fifo.sv       dual-clock gray-pointer asynchronous FIFO
│  ├─ mem_model.sv            sparse byte storage + back door
│  ├─ cfg_ctrl_fsm.sv         CFG initialization state machine
│  ├─ axi_port_shell.sv       per-port channel handshakes, W/B/R FIFOs, outstanding
│  ├─ axi_port_shell_cdc.sv   cross-clock port shell (used when CDC_ENABLE=1)
│  ├─ core_scheduler.sv       read/write command scheduling, storage access, B/R generation
│  ├─ ddr_axi_model_top.sv    flat-port top level (DUT)
│  └─ ddr_model_assertions.sv first batch of SVA
├─ tb/
│  ├─ tb_pkg.sv               data/address pattern functions
│  ├─ axi_master_bfm.sv       AXI master BFM (with outstanding/multi-command probes)
│  ├─ tb_scoreboard.sv        expected storage and read data checking
│  ├─ tb_top.sv               directed test mainbench (synchronous, 48 cases)
│  ├─ tb_top_cdc.sv           multi-clock testbench (CDC, 9 cases)
│  ├─ tb_unit_mem.sv          storage unit tests
│  ├─ tb_unit_addr.sv         address/burst/error unit tests
│  ├─ tb_unit_cfg.sv          CFG state machine unit tests
│  ├─ testlist.txt            baseline case table (top|test|-g parameter mapping, 60 entries)
│  └─ regress.sh              one-click regression (compile + all cases + summary exit code)
├─ proj/                      board project (Efinity project, frame capture/debug material)
└─ docs/
   ├─ user-guide.md           this file
   ├─ traceability.md         spec → RTL → test traceability
   └─ coverage/               merged.ucdb, HTML, text summaries
```

## 3. Quick start

In the `ddr_ctrl_model/tb` directory (Questa `vlog/vsim` must be on PATH):

```bash
# Full regression (compile + 60 cases + PASS/FAIL summary, exit code is the gate)
bash regress.sh

# A single test (first compile the work library via regress.sh, then run alone; for cases with -g take the parameters from testlist.txt)
vsim -c +TEST=wr_single -do "run -all; quit -f" work.tb_top

# Multi-clock tests
vsim -c +TEST=cdc_smoke -do "run -all; quit -f" work.tb_top_cdc

# random_stress multi-seed corroboration (-sv_seed 2..51, 50 seeds)
bash seeds_stress.sh
```

`testlist.txt` has one line per case, `top|test|extra parameters`, and is the single authoritative baseline run procedure: the parameter mappings of the cases that take `-g` (e.g. `addr_hole` needs `-gADDR_MAP_MODE=1` + a window, `rdataq_full` needs `-gREAD_OSTD_DEPTH=32`, `init_slverr` needs `-gINIT_AXI_RESP=1`) are frozen, **do not re-derive them by hand from memory** (correlation Phase 8 lesson: hand re-derivation once introduced a 16× window value error and parameter semantic mismatches).

Each test prints `TEST <name> PASS` or `TEST <name> FAIL`, and on failure `$fatal` returns a non-zero exit code. Regression logs are stored in `tb/regress_logs/`.

## 4. Top-level interface

The top level `ddr_axi_model_top` uses flat ports, consistent with spec chapter 5 and the hard-core pins.

| Group | Signal | Description |
|---|---|---|
| Clock | `ctrl_clk` | core clock |
| | `ACLK_0/1` | AXI port clocks; with `CDC_ENABLE=0` they must be same-source same-frequency as `ctrl_clk`, with `CDC_ENABLE=1` they may be asynchronous (1:1/2:1/4:1 or a slow clock, see `tb_top_cdc`) |
| Reset | `ARSTN_0/1` | active-low asynchronous port reset; resets the port shell and FIFOs, storage is preserved |
| | `CFG_RESET` | active-high global reset, at least 5 `ctrl_clk` cycles |
| CFG | `CFG_START`, `CFG_SEL`, `CFG_DONE` | `CFG_SEL` is active low; after DONE, START must stay high |
| AXI0/1 | all AW/W/B/AR/R channels | 33-bit address, 512-bit data, 6-bit ID, 64-bit WSTRB |
| Status | `CTRL_INIT_DONE/READY/BUSY/ERR` | valid when `ENABLE_CTRL_STATUS=1`; ERR is sticky until CFG_RESET |

The AW sidebands (`AWLOCK/AWAPCMD/AWQOS/AWCACHE/AWALLSTRB/AWCOBUF`) and the AR sidebands (`ARLOCK/ARAPCMD/ARQOS`) all exist. In v0.2 `AWAPCMD/ARAPCMD/AWLOCK/ARLOCK/AWQOS/ARQOS` are accepted but do not affect behavior.

## 5. Main parameters

### 5.1 Structure and capacity

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 32 | DRAM data width (x16/x32) |
| `AXI_DATA_WIDTH` | 512 | fixed |
| `MEM_DENSITY_GBIT` | 4 | density per channel (Gbit) |
| `GBIT_BINARY` | 1 | 1=2^30, 0=10^9 |
| `PHYSICAL_RANK` | 1 | number of ranks |
| `NUM_AXI_TARGETS` | 2 | fixed at 2 |
| `SUPPORT_WRAP_BURST` | 1 | WRAP support |
| `SUPPORT_NARROW` | 1 | narrow support |
| `SUPPORT_FIXED_BURST` | 0 | FIXED is rejected by default |
| `SUPPORT_AWALLSTRB` | 1 | AWALLSTRB 16-beat limit |
| `RANK_MAP_MODE` | 1 | 0=SINGLE_RANK, 1=CS_STRIDE, 2=CS_BIT |
| `CS_BIT_POS` | -1 | address bit in CS_BIT mode |
| `ADDR_MAP_MODE` | 0 | 0=LINEAR, 1=FIELD_DECODE_DEBUG (provides the `DBG_FIELDS` decode output) |
| `ADDR_CS_BIT_POS` | 27 | chip-select bit of the field decode, determines the row width |
| `ADDR_HOLE_POLICY` | 0 | address hole policy: 0=DECERR, 1=ALIAS into the linear space |
| `ADDR_HOLE_START/END` | 0/0 | hole window, half-open interval `[START, END)`; disabled when `END<=START` |
| `CDC_ENABLE` | 0 | 1=each AXI port gets its own clock domain through gray-pointer asynchronous FIFOs |
| `MEM_INIT_MODE` | 0 | 0=ZERO, 1=RANDOM, 2=PATTERN |
| `MEM_INIT_SEED` | 1 | RANDOM mode seed |

`MEM_BYTES = (MEM_DENSITY_GBIT × 2^30 / 8) × (DATA_WIDTH / 16) × PHYSICAL_RANK` (when `GBIT_BINARY=1`). The default 4Gbit × x32 × 1 rank = 1 GiB, matching the 33-bit address space.

### 5.2 Queues, arbitration and outstanding

| Parameter | Default | Description |
|---|---|---|
| `CMD_QUEUE_DEPTH` | 8 | command FIFO depth per direction (command entries) |
| `WRITE_DATA_QUEUE_DEPTH` | 16 | W beat FIFO depth per port |
| `READ_DATA_QUEUE_DEPTH` | 16 | R beat FIFO depth per port |
| `WRITE_OSTD_DEPTH` | 8 | write outstanding per port |
| `READ_OSTD_DEPTH` | 8 | read outstanding per port |
| `ARB_GRANT_INTERVAL` | 2 | minimum grant interval when ports contend; **effective only on the `CDC_ENABLE=0` (g_sync) path**, the CDC form is fixed 1:1 alternating collection (at most 1 command per direction per cycle into the shared queue), and the Phase 4 calibration G=2/G=8 characterization was bit-identical |
| `ARB_QUIET_FAST_PATH` | 1 | a single quiet port can be served every cycle; likewise effective only on the g_sync path |
| `B_FIFO_DEPTH` | 8 | write response FIFO depth per port |
| `OUT_OF_ORDER_ENABLE` | 0 | 1=allow B/R of different IDs to return out of order (same port same ID stays in order) |
| `R_INTERLEAVE_ENABLE` | 0 | 1=allow R beats of different read bursts to interleave (requires OOO enabled) |

### 5.3 Latency and BVALID

| Parameter | Default | Description |
|---|---|---|
| `LATENCY_MODE` | 0 | 0=UNIFORM, 1=FIXED (takes MIN) |
| `LATENCY_SEED` | 1 | xorshift32 seed, reloaded on CFG_RESET |
| `READ_LATENCY_MIN/MAX` | **191/492** (calibrated) | first-read-beat latency range; Phase 2 board backfill (original ENG 10/30) |
| `R_BEAT_INTERVAL` | 1 | minimum interval between adjacent R beats of the same burst |
| `WRITE_RESP_LATENCY_MIN/MAX` | 8/24 `[ENG]` | the `T_AW_B` queueing jitter component; for `AWCACHE[0]=0` encodings the actual timing is governed by `WRITE_DATA_TO_B_LATENCY` |
| `WRITE_DATA_TO_B_LATENCY` | **451** (calibrated) | extra delay from WLAST→B for non-early-return encodings; Phase 2 board backfill (original ENG 4) |
| `BVALID_CMD_QUEUE_DELAY` | **28** (calibrated) | command accept→BVALID delay for early-return encodings (`AWCACHE[0]=1`, including `1111+cobuf`); Phase 5 board backfill (original ENG 2) |
| `BVALID_PHY_ISSUE_DELAY` | 2 `[ENG]` | used only by the `OTHER_AWCACHE_POLICY=PHY_ISSUE` fallback policy; not triggered by the default policy |
| `W_ACCEPT_INTERVAL` | 1 | minimum W beat acceptance interval |
| `OTHER_AWCACHE_POLICY` | 0 | fallback policy, **effective only for `AWCACHE[0]=0` encodings**: 0=DATA_DONE (board-consistent, default), 1=CMD_QUEUE, 2=PHY_ISSUE (early return); `AWCACHE[0]=1` is always early and unaffected by this parameter |
| `AWCOBUF_STRICT` | 1 | sets a sticky error when the cache is neither 1111 nor 0000 and COBUF=1; Phase 5 measured that COBUF has no independent effect on B timing, STRICT is kept conservatively |
| `ERR_INJECT_RATE` | 0 | 0–100, force the whole command to SLVERR by percentage |

> Board 9-encoding matrix measurement (correlation Phase 5): **BVALID timing is determined solely by `AWCACHE[0]` (Bufferable)**, `AWCOBUF` has no independent effect; the raw `1111` value (COBUF=0) deadlocks board AW/W and is untestable, the model returns early per the bit0 rule. See spec §6.5 and correlation-plan §9.

### 5.4 CFG

| Parameter | Default | Description |
|---|---|---|
| `INIT_CYCLES` | 1000 | initialization count |
| `INIT_AXI_BLOCK` | 1 | block AXI during initialization |
| `INIT_AXI_RESP` | 0 | 0=BACKPRESSURE, 1=SLVERR; **only 0/1 are valid**, any other value (e.g. 2) disables both blocking and SLVERR and the transaction is accepted as a normal write (Phase 8 erratum) |
| `CFG_RESET_CLEAR_MEM` | 0 | whether CFG_RESET clears the storage |
| `ENABLE_CTRL_STATUS` | 0 | whether to drive the status outputs |

## 6. Behavior highlights

### 6.1 Write address and write data

- `AWREADY = ARSTN && !init_block && AWVALID && (WVALID || W FIFO not empty) && wr_ostd < depth && cmd_space`.
- The model requires AW and W to appear together, or that port's W data to have entered the FIFO in advance; with only `AWVALID`, `AWREADY` stays low (`aw_waits_wvalid`).
- W may precede AW; W beats are grouped by `WLAST` and matched in port order once the AW arrives.
- `WREADY` depends only on reset, initialization blocking and W FIFO space, not on AW.

### 6.2 BVALID timing

The timing is determined solely by `AWCACHE[0]` (Bufferable) bit0 (board 9-encoding matrix measurement, correlation Phase 5 finalization):

| Condition | BVALID timing |
|---|---|
| `AWCACHE[0]=1` (including `1111`±COBUF, `0001/0011/0111`) | early return: `AW_accept + BVALID_CMD_QUEUE_DELAY` (28, calibrated), **may precede WLAST**; COBUF has no independent effect |
| `AWCACHE[0]=0` (including `0000`, `0010/0100/1110`) | non-early: `max(AW_accept + lat, WLAST + WRITE_DATA_TO_B_LATENCY)` (451, calibrated); same shape as the board at 0000 (WA/WL 55-99 ACLK) |
| `AWCACHE[0]=0` and `OTHER_AWCACHE_POLICY=1/2` | early return (CMD_QUEUE 28 / PHY_ISSUE 2 fallback policies) |

> The v0.2 manual said "AWCACHE=0000 takes the PHY_ISSUE early return", which does not match the board measurement (0000 always returns after the write data commit); this has been corrected — a TB written to the old semantics gets the opposite result.

An early B does not affect the W channel: `WREADY` keeps accepting all beats until `WLAST`, and the storage commit happens after `WLAST`. Erroneous writes (response not OKAY) do not update the storage. The raw `AWCACHE=1111` value (COBUF=0) deadlocks board AW/W and cannot serve as a baseline combination (the model still returns early per the bit0 rule).

### 6.3 Read path

- `ARREADY` depends on `ARVALID`, reset, initialization, `rd_ostd < READ_OSTD_DEPTH` and command space.
- **Outstanding is released when RREADY consumes RLAST** (`rlast_hs`), not when the data enters the R FIFO: while the master holds `RREADY=0` outstanding only grows, so the AR acceptance cap is `READ_OSTD_DEPTH` — when long blocking of the read data queue is needed, AR throughput is constrained by that cap at the same time (`rdataq_full` calibration point, Phase 8).
- The first R beat appears after `AR_accept + lat`; the interval between beats of the same burst is not less than `R_BEAT_INTERVAL`.
- A narrow read selects the lane by byte address; invalid lanes return 0.
- An erroneous read still returns the full burst, with `RRESP` marked `SLVERR/DECERR`.
- `OUT_OF_ORDER_ENABLE=0` (default): read responses on the same port return in AR order.
- `OUT_OF_ORDER_ENABLE=1`: each command has its own completion deadline and R returns in deadline order; reads on the same port with the same ID still follow AR order (compared by `seq`). With `R_INTERLEAVE_ENABLE=1` the beats of different bursts may interleave, otherwise one burst's beats are output contiguously.

### 6.4 Address and burst checks

Checked combinationally when the command is accepted; errors are returned in the B/R response:

| Check | Response |
|---|---|
| `SIZE > 6` | SLVERR |
| Table 5: SIZE=6/5/4 ≤64/128/256 beats; SIZE≤3 ≤256 beats | SLVERR |
| INCR crossing 4KB | SLVERR |
| Start address not aligned to SIZE | SLVERR |
| WRAP length not 2/4/8/16 or unaligned | SLVERR |
| FIXED (unsupported by default) or an illegal burst encoding | SLVERR |
| `addr + burst_bytes > MEM_BYTES` | DECERR |
| `AWALLSTRB=1` and beat count >16, or any WSTRB not all 1 | SLVERR + sticky error |
| Inside the field decode window (`ADDR_MAP_MODE=1` and the command intersects `[ADDR_HOLE_START, ADDR_HOLE_END)`) | policy=0: DECERR; policy=1: alias the address into the linear space |

`AWLEN/ARLEN` are 8 bit, maximum 255 (256 beats).

Field decode mode (`ADDR_MAP_MODE=1`) splits the address of the last accepted command into
`CS[ADDR_CS_BIT_POS]`, `ROW[ADDR_CS_BIT_POS-1:12]`, `BANK[11:9]`,
`COLUMN[8:2]`, `DATAPATH[1:0]`, output through `DBG_FIELDS`/`DBG_FIELDS_ADDR`, for debugging only,
and does not change the storage address (unless an address hole is hit). The ALIAS policy maps commands with `addr >= hole_start` to
`addr - hole_start`, and a burst that starts below the hole and crosses into it is mapped to `addr % MEM_BYTES`.

### 6.5 CFG initialization

`CFG_DONE=0` while `CFG_RESET` is asserted; after release it waits for `CFG_START=1` and sets `CFG_DONE=1` after counting `INIT_CYCLES`. When `CFG_SEL=1`, `CFG_DONE=0`, and initialization restarts after release. While `CFG_DONE` is asserted, `CFG_START` must stay high. During initialization, with `INIT_AXI_BLOCK=1` the AXI address channels are backpressured (`INIT_AXI_RESP=0`) or return SLVERR (`INIT_AXI_RESP=1`).

### 6.6 Port reset

`ARSTN_x=0` resets that port's shell, W/B/R FIFOs and outstanding counters; the core discards that port's unfinished commands and the storage contents are preserved. The other port is unaffected.

## 7. `[MODEL]` deviations and known limitations

1. **Clocks**: with `CDC_ENABLE=0` all logic runs on `ctrl_clk`, and `ACLK_0/1` must be tied to the same clock; with `CDC_ENABLE=1` the port shells live in their own `ACLK_x` domains and commands/data/responses cross through dual-clock gray FIFOs, and in CDC mode the shared command arbiter is not used (each port maintains its own queue).
2. **OOO / read interleaving**: with `OUT_OF_ORDER_ENABLE=1` B/R are out of order by deadline (same port same ID preserved); with `R_INTERLEAVE_ENABLE=1` R beats may interleave across bursts. Disabled by default, matching the hard core's in-order mode.
3. **Error injection**: `ERR_INJECT_RATE` injects `SLVERR` by percentage at command acceptance (the whole command, all beats); injected writes do not update the storage; `err_inject` validates with 100%.
4. **Unwritten storage addresses**: the sparse array lazily returns 0 / hash / address pattern per `MEM_INIT_MODE`; this is not the real DRAM power-up content and is a `[MODEL]` deviation.
5. **FIXED burst**: rejected by default (SLVERR), consistent with the UG; repeated access to a fixed address is not modeled.
6. **Narrow read invalid lane**: returns 0; the real hard core may return undefined/last data.
7. **AWCOBUF strict mode**: with `AWCOBUF_STRICT=1`, a COBUF write with a cache other than 1111/0000 sets a sticky `CTRL_ERR`, to catch illegal combinations.
8. **Behavior during initialization**: `INIT_AXI_BLOCK`/`INIT_AXI_RESP` provide two simplified models and do not cover all manual details.
9. **Field decode**: `DBG_FIELDS` is a debugging aid, the field widths vary with `ADDR_CS_BIT_POS`, and it does not correspond to the real DRAM address mapping; the address hole policy is an explicit `[MODEL]` extension.
10. **No PHY timing**: tRCD/tRP/refresh/bank conflicts are not modeled; read/write latency comes from parameters or the RNG.
11. **Status outputs**: `CTRL_BUSY` is the read/write engine activity indicator, for debugging only.
12. **Out-of-range address behavior (documented deviation, Phase 7)**: the model returns DECERR for `addr + burst_bytes > MEM_BYTES` (protective direction); the board real core measured **silent wrap-around** (except one lone 1 GiB point). Using the model for out-of-range protection checks gives stricter results than the real core.
13. **Bandwidth efficiency (documented deviation, Phase 1/2/4)**: the model has ideal service timing, and its absolute throughput differs from the real core by ~2.2x (including the ACLK/ctrl clock ratio); the dual-port degradation ratio is conservative at the model's saturation points (1.19x vs board 1.00x) and optimistic in the first-round transient (1.03x vs board 1.72x). For performance prediction, use the calibration data in correlation-plan §9 as the correction baseline.

## 8. Testbench

### 8.1 BFM capabilities

`axi_master_bfm` provides:

- `wr_txn(...)`: supports cache/cobuf/allstrb/strb_mode/wfirst/pause_after_first, and `wlast_mode` can inject an early/missing WLAST;
- `wr_aw_late_w(...)`: verifies that AWREADY is low with only AWVALID;
- `rd_txn(addr, len, size, burst, id, data[], resp[])`;
- `wr_ostd_probe(depth, base, accepted, blocked)`: preloads W data, fills write outstanding, checks AW blocking and BID order;
- `rd_ostd_probe(depth, base, accepted, blocked)`: holds RREADY low, fills read outstanding, checks AR blocking and RID order;
- `wr_multi_probe(n, addrs, ids, done_order, ok)` / `rd_multi_probe(...)`: issue several commands at once and capture the B/R return order, for OOO, same-ID ordering and multi-queue arbitration tests;
- `cmdq_probe(...)`, `wdataq_probe(...)`, `rdataq_probe(...)`: fill the command queue, W data queue and R data queue respectively and check backpressure and draining;
- `cg_wr`/`cg_rd` functional covergroups: burst type, len/size, response, cache/cobuf, W-first, WSTRB, read burst.

All handshakes have a 20000-cycle timeout; `tb_top` has a 5 ms and `tb_top_cdc` a 20 ms global watchdog.

### 8.2 Scoreboard

- Maintains sparse expected storage; write transactions update it by beat/WSTRB after B=OKAY;
- Read transactions are compared in 64-byte blocks and by lane, invalid lanes expected 0;
- Checks BID/BRESP, RID/RLAST/RRESP;
- An early B uses WLAST as the commit point.

### 8.3 Assertions

`ddr_model_assertions` covers: READY must accompany VALID, VALID held until the handshake, B/R VALID stability, WLAST/RLAST legality, `CFG_DONE→CFG_START`, CFG_RESET clearing DONE, DONE stickiness, CFG_RESET minimum width, B/R not earlier than the corresponding command handshake, arbiter single grant / contention interval. Assertion failures count toward the Questa error count and fail the regression.

### 8.4 Case list

| Case | Coverage point |
|---|---|
| `smoke` / `smoke_reset` | reset outputs, CFG completion, status signals |
| `smoke_cfg` | CFG_DONE held |
| `init_block` | AWREADY backpressure during initialization, write completes after CFG_DONE |
| `init_slverr` | with `INIT_AXI_RESP=1` a write during initialization returns SLVERR and does not change the storage |
| `cfg_sel` | pulling CFG_SEL high clears DONE, restored after release |
| `wr_single` | single-beat write + read-back |
| `wr_incr` | 4-beat INCR write |
| `wr_wstrb` | 0x55/0xAA, all 0, partial byte strobes |
| `wr_w_before_aw` | W before AW |
| `aw_waits_wvalid` | AWREADY low with only AWVALID |
| `early_b` | `1111`+COBUF early B (`AWCACHE[0]=1`), W data complete; `0000` verifies **non-early** (v0.2a finalization) |
| `bvalid_modes` | other cache + policy=1 early return; DATA_DONE non-early |
| `wr_errors` | 4KB, Table 5, SIZE=7, FIXED error responses |
| `allstrb` | 16 beats pass, 17 beats error, all-0 WSTRB error |
| `reads` | single beat/INCR/narrow/WRAP/4KB/out-of-range error read |
| `dual_port` | dual-port concurrent writes, cross reads |
| `ostd_wr` | AW blocking with write outstanding=2, B order |
| `ostd_rd` | AR blocking with read outstanding=2, R order |
| `latency` | read latency falls within the parameter range |
| `lat_equal` | identical dual-port read latency with a fixed read latency of 6 |
| `lat_fixed` | FIXED mode latency reproducible |
| `r_gap` / `w_gap` | beat interval with `R_BEAT_INTERVAL>1` / `W_ACCEPT_INTERVAL>1` |
| `port_reset` | port 0 reset isolation, read/write after recovery |
| `port_reset_mid` | an in-progress transaction interrupted by a port reset, the other port and the storage unaffected |
| `cfg_clear_mem` | CFG_RESET clears the storage when `CFG_RESET_CLEAR_MEM=1` |
| `cmdq_full` | AWREADY backpressure when the command queue is full, continues after draining, B order |
| `wdataq_full` | WREADY backpressure when the W data FIFO is full, subsequent AW matching |
| `rdataq_full` | read stalls when the R data FIFO is full, ARREADY backpressure when the read command queue is full |
| `arb_fairness` | both sides get grants under dual-port contention, single-grant assertion, contention interval |
| `err_inject` | with `ERR_INJECT_RATE=100` both dual-port reads and writes return SLVERR, writes do not change the storage |
| `random_stress` | 40 random read/write transactions (random len/size/strobe/W-first/pause) + scoreboard |
| `wlast_err` | early WLAST / missing WLAST → SLVERR + sticky error; on `0000` (non-early path) with a missing WLAST, B returns together with SLVERR |
| `cobuf_strict` | non-1111/0000 cache + COBUF → sticky error, the data is still written |
| `allstrb_early` | `0000` non-early path: bad WSTRB → **SLVERR + CTRL_ERR sticky** (opposite to the old "early B stays OKAY" semantics after the v0.2a finalization) |
| `dual_multi` | dual-port simultaneous long burst writes, two unfinished write contexts coexist |
| `dir_arb` | AW+AR requested simultaneously on the same port, bidirectional arbitration rotates |
| `contend_multi` | 4 commands queued on each port, verifying the grant interval and one-by-one service |
| `ooo_same_id` / `ooo_diff_id` / `ooo_interleave` | OOO read scheduling: same ID order preserved, different IDs by deadline, R beat interleaving |
| `ooo_b_same_id` | under OOO, same-port same-ID writes preserve order and BID is correct |
| `field_decode` | FIELD_DECODE_DEBUG: CS bit and row field decode |
| `addr_hole` | address hole DECERR policy |
| `addr_alias` | address hole ALIAS mapping and read-back |
| `addr_alias_cross` | a burst starting below the hole and crossing into it is ALIAS-mapped and read back |
| `cdc_smoke` / `cdc_dual` / `cdc_ostd` / `cdc_stress` / `cdc_rst` | CDC clock ratios 1:1/2:1/4:1: read/write, outstanding, dual-port concurrency, port reset isolation |
| `cdc_slow` | basic read/write with ACLK slower than ctrl_clk (`CDC_ACLK_SLOW=1`) |
| `cdc_wgap` | `W_ACCEPT_INTERVAL` effective in the ACLK domain under asynchronous CDC |
| `cdc_contend` | 4 read/write commands on each port complete concurrently under asynchronous CDC |
| `cdc_err` | SLVERR propagation and CTRL_ERR of error injection under asynchronous CDC |
| `tb_unit_cfg` | CFG FSM: initialization abort, START deasserted after DONE, illegal state recovery, reset |
| `tb_unit_addr` | burst/Table5/4KB/WRAP/alignment/rank/check_cmd |
| `tb_unit_mem` | byte strobe, narrow lane, init modes, back door, clear |

## 9. Regression and coverage results

**Phase 8 baseline (2026-10-23, reproducible one-click with `bash regress.sh`)**:

```
Regression: 60 passed, 0 failed (tb_top 48 + tb_top_cdc 9 + tb_unit 3; run procedure frozen in tb/regress.sh + testlist.txt)
Stress: 50/50 seeds passed (random_stress, -sv_seed 2..51)
```

Coverage (development-time baseline, collected 2026-10-21; not re-collected in Phase 8, the `COV=1` entry point was removed with the regress.sh rewrite, for the re-collection method see §11):

| Scope | Branch | Condition | Statement |
|---|---|---|---|
| Top level `ddr_axi_model_top` | 86/86 = 100% | 36/43 = 83.7% | 135/135 = 100% |
| RTL source files total (10 files) | 374/376 = 99.47% | 164/197 = 83.25% | 597/599 = 99.67% |
| All instances (including TB/interface/assertions) | 1190/1767 = 67.34% | 340/1310 = 25.95% | 3885/5479 = 70.90% |

Per file (`docs/coverage/rtl_summary.txt`):

| File | Branch | Condition | Statement |
|---|---|---|---|
| `axi_port_shell` | 16/16 | 1/1 | 23/23 |
| `axi_port_shell_cdc` | 18/18 | 1/1 | 27/27 |
| `cfg_ctrl_fsm` | 14/14 | 1/1 | 16/16 |
| `core_scheduler` | 107/109 | 64/81 | 190/190 |
| `ddr_async_fifo` | 16/16 | — | 41/41 |
| `ddr_axi_model_top` | 86/86 | 36/43 | 135/135 |
| `ddr_fifo` | 10/10 | 2/2 | 10/12 |
| `ddr_model_assertions` | 26/26 | 21/23 | 22/22 |
| `ddr_model_pkg` | 68/68 | 36/42 | 107/107 |
| `mem_model` | 13/13 | 2/3 | 26/26 |

FSM: `tb_top/dut/u_cfg`, `tb_top_cdc/dut/u_cfg`, `tb_unit_cfg/dut` each 3/3 states and 4/4 transitions, total 9/9 + 12/12 = 100% (see `docs/coverage/fsm.txt`).

Functional coverage: 8 BFM covergroup instances, 132/324 bins = 40.74% (many unreachable cross combinations were not pruned).

Assertions: 28 concurrent assertions, 0 failures; after instantiation expansion 43 of 56 bins were triggered and 13 preconditions were not hit (vacuous success). Covered: READY→VALID, VALID hold, B/R stability, WLAST/RLAST, CFG_DONE→START, CFG_RESET clearing DONE/minimum width, B/R not earlier than the command handshake, arbitration one-hot and the grant interval.

**The PLAN P7 target (branch/statement ≥95%) has been met**: RTL source files total branch 99.47%, statement 99.67%. The remaining 2 branches are the tie-break redundant scan paths at `core_scheduler.sv:148/171`, which no legal stimulus hits and which do not affect functionality; the 2 `ddr_fifo` statements are a counting artifact of the `full`/`empty` continuous assignments. See `model/docs/traceability.md` §8. The all-instances definition includes the TB/interface/assertions and cannot be compared directly with the RTL target.

## 10. Known issues and follow-up work

- The two tie-break redundant scan branches at `core_scheduler.sv:148/171` are hit by no legal stimulus (2/376 branch), do not affect functionality, and are kept as an exemption or for later formal proof;
- The `full`/`empty` continuous assignments of `ddr_fifo` are not triggered in some instances; the statement count 10/12 is a tool counting artifact;
- The cross of the functional covergroups is not pruned (132/324 bins = 40.7%), which can be improved by deleting unreachable combinations;
- Add SVA for WDATA hold and 4KB/Table5/ALLSTRB (currently checked by directed tests);
- The `SYNC_LATENCY`/`ARB_LATENCY` parameters are retained but not modeled;
- ~~Board calibration of `READ_LATENCY`, `WRITE_RESP_LATENCY`, BVALID delay~~ **Done** (correlation Phase 0-8, 2026-10-23): `READ_LATENCY_MIN/MAX`=191/492, `WRITE_DATA_TO_B_LATENCY`=451, `BVALID_CMD_QUEUE_DELAY`=28 have been backfilled into the RTL; the measured conclusions on `CMD_QUEUE_DEPTH`/OOO/address mapping/arbitration applicability domain are in spec §18 and correlation-plan §9.

## 11. Reproduction information

- QuestaSim 2024.2 (`vlog`/`vsim`/`vcover` available; `tb/regress.sh` runs under Git Bash/WSL);
- Regression entry: `cd ddr_ctrl_model/tb && bash regress.sh` (per-file `vlog -sv -work work` compile, equivalent to the old `-f filelist.f`);
- Randomness baseline: TB `$urandom` unseeded (Questa default seed) + model `LATENCY_SEED=1`; for multiple seeds use `vsim -sv_seed <n>` (`bash seeds_stress.sh` sweeps 50);
- The `-g` mapping of parameterized cases uses `tb/testlist.txt` as the single authority;
- Logs: `tb/regress_logs/`;
- Coverage database: `docs/coverage/merged.ucdb` (development-time baseline). Re-collection method: compile with `vlog -sv -lint -cover bcsxf`, drop a UCDB per case with vsim, then `vcover merge -out merged.ucdb tb runs/*.ucdb` followed by `vcover report -html`.
