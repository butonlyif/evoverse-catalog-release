[中文](ddr-test-spec-v0.2.md) | English

# TJ Series DDR Controller Test Component Design Specification

**Document ID**: SPEC-DDR-TEST-v0.2  
**Related document**: SPEC-DDR-AXI-MODEL-v0.2  
**Applies to**: Efinix TJ series DDR hard IP controller (LPDDR4/LPDDR4x)  
**Test objective**: measure the parameters `READ/WRITE_OSTD_DEPTH`, `READ/WRITE_LATENCY`, `CMD_QUEUE_DEPTH`, `ARB_GRANT_INTERVAL`, the `BVALID` timing and similar parameters, and back-fill them into the AXI behavioral model  
**Date**: 2026-10-21  
**Status**: architecture review passed, may enter test component implementation

---

## 1. Purpose, Scope and Premises

### 1.1 Purpose

This document defines the test components required for the parameter calibration of the TJ DDR hard IP controller: the AXI Performance Monitor (APM), the AXI Traffic Generator (TG), the ILA probes and the test execution flow.

### 1.2 Scope

- AXI-side performance/behavior measurement; no PHY electrical parameters are measured;
- single-port/dual-port, read/write/mixed traffic;
- outstanding, latency, backpressure, arbitration, `BVALID` timing, rank/CS behavior;
- the test results are back-filled into SPEC-DDR-AXI-MODEL-v0.2.

**Out of scope:**

- DDR PHY electrical behavior, training, ODT/VREF;
- DRAM command timing and refresh;
- performance sign-off;
- production test.

### 1.3 Key Premises

1. **The APM is monitor-only by default**: it only snoops the AXI signals, it drives no AXI output and it is not inserted into the forwarding path. If the target board only supports pass-through, handle it with the controlled flow of 2.3.
2. **The DUT must complete configuration/calibration first**: no measurement traffic is issued before `CFG_DONE=1`, see Chapter 4.
3. **The write channel must co-assert `AWVALID/WVALID`**: the `AWREADY` of the TJ controller can only be asserted after `AWVALID && WVALID` (UG Figure 4 note). The TG must not wait for `AWREADY` before issuing `WVALID`, otherwise it deadlocks.
4. **Fix `AWCACHE=4'b1111, AWCOBUF=0` when calibrating the write parameters**: otherwise the early return of `BVALID` shifts the "write completion" semantics.
5. **Latency quantiles first**: the `*_LATENCY_MAX` back-fill uses P99 (with a histogram) or P95 (without a histogram), the absolute max is only recorded as an outlier.

### 1.4 Normative Markers

- `[UG]`: explicitly stated in the manual;
- `[AXI4]`: inferred from AXI4;
- `[MODEL]`: a model/test implementation choice;
- `[CONFIRM-EFINITY]`: depends on the actual capability of the Efinity IP, confirmation required;
- `[CONFIRM-DUT]`: depends on measurement/vendor confirmation.

---

## 2. Test Architecture

### 2.1 Overview (default: monitor-only)

```text
┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┌──┐
│  AXI Traffic    │  AXI0    │ AXI Interconnect│  AXI0    │  TJ DDR hard IP │
│  Generator      │─│  Generator      │─│  Generator      │─│  Generator      │─│  Generator      │─│  Generator      │─│  Generator      │─│  Generator      │─│  Generator      │─►│  (optional      │─►│  (optional      │─►│  (optional      │─►│  (optional      │─►│  (optional      │─►│  (optional      │─►│  (optional      │─►│  (optional      │─►│  (optional      │─►│  controller     │
│  (Master, x2)   │▬─│  (Master, x2)   │▬─│  (Master, x2)   │▬─│  (Master, x2)   │▬─│  (Master, x2)   │▬─│  (Master, x2)   │▬─│  (Master, x2)   │▬─│  (Master, x2)   │▬─│  (Master, x2)   │▬─│   register      │▬─│   register      │▬─│   register      │▬─│   register      │▬─│   register      │▬─│   register      │▬─│   register      │▬─│   register      │▬─│   register      │▬─│  (Slave, x2)    │
│                 │          │   slice)        │          │                 │
└─└─└─└─└─└─└─└─└─└─└─└─└─└─└─└─└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──└──┘
         │                            │                            │
         │                            │ AXI signal snooping         │
         │                            ▼                            │
         │                   ┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌─┌──┐                   │
         └─└─└─└─└─└─└─└─└─└─└─└─└─└─└─└─└─└─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─►│  APM (monitor)  │▬─┘
                             │  + ILA bypass   │
                             │    probes       │
                             └─└─└─└─└─└─└─└─└─└─└─└─└─└─└─└─└──┘
```

**Connection principles:**

- The APM inputs connect directly to the AXI network (between the TG and the DUT); they **do not drive** `AWREADY/ARREADY/WREADY/RREADY/BREADY` and are not inserted into the data/address/response channels.
- The APM only samples with `ACLK`; all counters/histograms belong to the `ACLK` domain.
- The ILA may snoop the internal APM state and the AXI signals; the CFG signals are sampled separately in the `ctrl_clk` domain (see 4.5).
- If the FPGA routing cannot snoop directly, use the monitor port of the interconnect or insert a register slice **independent of the APM**; the latency of that slice must be included in the calibration, see 2.3.

### 2.2 Component Responsibilities

| Component | Responsibility | In the data path |
|---|---|---|
| APM | counts the outstanding transactions, latency, backpressure and transaction counts | No (by default) |
| TG | generates controllable AXI traffic | Yes (Master) |
| ILA | event capture, cross-validation, protocol debugging | No |
| Register slice (optional) | improves routing/timing | Yes; the latency must be fixed and corrected |

### 2.3 Controlled Pass-Through Alternative

If the target board can only place the APM in the forwarding path:

1. Insert a register/skid buffer uniformly into all five channels, no combinational gating may be used;
2. The `VALID` path only allows pipelining, no combinational logic may change it;
3. The latency of the `READY` path must be fixed and measurable;
4. Two experiments must be performed: the baseline without the APM vs the one with the APM, the difference is used as the correction term;
5. The report must state "measured value = controller + pass-through";
6. The pass-through must not break the dependency of `AWREADY` on `AWVALID && WVALID`; no combinational logic related to `AWREADY` may be added to the `WVALID` path.

> If the above conditions are not met, the pass-through data must not be used to back-fill the model parameters.

### 2.4 Instrumentation Principles

- Measure first, instrument afterwards: Phase 0 first establishes an uninstrumented baseline, then the APM is enabled (monitor-only should show no difference), and only afterwards a register slice is considered.
- Every instrumentation change must have a "before/after" comparison.
- All measurement windows, clock frequencies, reset sequences and AXI static configurations must be recorded.

---

## 3. Measurement Definitions and Conventions

### 3.1 Clock Domains

| Domain | Purpose | Description |
|---|---|---|
| `ACLK` | APM, TG, AXI protocol measurement | the latency is counted in ACLK cycles |
| `ctrl_clk` | model-internal latency parameters, CFG timing | usually 1/4 of the PHY data rate |
| `ACLK:ctrl_clk` | conversion | must be measured and recorded; the nominal value must not be substituted |

```text
CLK_RATIO_ACLK_PER_CTRL = f_ACLK / f_ctrl_clk
latency_ctrl_cycles = latency_aclk_cycles × f_ctrl_clk / f_ACLK
```

> `SYNC_LATENCY` cannot be measured independently from the AXI boundary alone; it is mixed with the read latency and the internal queueing and can only be fitted/apportioned through experiments with several clock ratios `[MODEL]`.

### 3.2 Latency Reference Points

| Metric | Start | End | Description |
|---|---|---|---|
| `T_AR_FIRST_R` | `ARVALID && ARREADY` | first `RVALID && RREADY` of the same ID | the convention of the model `READ_LATENCY_*` |
| `T_AR_RLAST` | `ARVALID && ARREADY` | `RLAST && RREADY` of the same ID | optional, for the total burst latency |
| `T_AW_B` | `AWVALID && AWREADY` | `BVALID && BREADY` of the same ID | the convention of the model `WRITE_RESP_LATENCY_*` |
| `T_WLAST_B` | `WLAST && WREADY` | `BVALID && BREADY` of the same ID | the data completion latency when `AWCOBUF=0`; it may be negative with early return |
| `T_WFIRST_ACCEPT` | first `WVALID && WREADY` beat | — | used to diagnose the write data acceptance rhythm |

**Important:**

- The start of `T_AW_B` is the AW handshake. Because `AWREADY` depends on `WVALID`, the TG must have the first W data beat ready; otherwise what is measured is the wait caused by the TG itself.
- In early-return mode (`AWCACHE=1111, AWCOBUF=1` or `AWCACHE=0000`), `BVALID` may precede `WLAST`; `T_WLAST_B` may be negative and the APM must count `B_BEFORE_WLAST` separately.
- Latency samples fall into the sampling window at their "completion moment"; the timestamp may be earlier than the start of the window.

### 3.3 Outstanding Definition

```text
OSTD_RD = cumulative AR handshakes − cumulative RLAST handshakes
OSTD_WR = cumulative AW handshakes − cumulative B handshakes
```

- The write outstanding is decremented at `BVALID && BREADY`; in early-return mode this happens before WLAST, which is AXI semantics, but when calibrating `WRITE_OSTD_DEPTH` `AWCOBUF=0` must be used so that B aligns with the data completion.
- The read/write are counted separately per port; the dual-port case instantiates two APMs.
- The peak is the maximum value of `OSTD_*` within the sampling window.

### 3.4 Real Backpressure Definition

Because `AWREADY` depends on `AWVALID && WVALID`, `AWVALID && !AWREADY` must not be treated directly as backpressure.

| Metric | Definition | Meaning |
|---|---|---|
| `BP_AR` | `ARVALID && !ARREADY` | real read address backpressure |
| `BP_AW_TRUE` | `AWVALID && WVALID && !AWREADY` | real write command backpressure (the first W beat is provided) |
| `AW_WAIT_WVALID` | `AWVALID && !WVALID` | waiting for the write data, not resource backpressure; used to diagnose the TG/controller timing |
| `BP_W` | `WVALID && !WREADY` | write data backpressure |
| `BP_R` | `RVALID && !RREADY` | read data backpressure (caused by the Master) |

Backpressure duty cycle:

```text
BP_*_RATIO = BP_*_CYCLES × 10000 / WINDOW_CYCLES   // per ten-thousand, saturated to 10000
```

- The denominator is the number of ACLK cycles of the sampling window, not the number of valid cycles.
- First backpressure timestamp: the global cycle count of the first `BP_AR` or `BP_AW_TRUE` after the start of the window; if it never occurs it is all 1s.
- `AW_WAIT_WVALID` is recorded at the same time so that a TG that did not provide data is not misjudged as controller backpressure.

### 3.5 Queue Depth Engineering Estimate

```text
IN_FLIGHT_RD = TXN_ISSUED_AR − TXN_COMPLETED_RLAST
IN_FLIGHT_WR = TXN_ISSUED_AW − TXN_COMPLETED_B
CMD_QUEUE_DEPTH_ENG = max(IN_FLIGHT_* at first true backpressure)
```

- `CMD_QUEUE_DEPTH_ENG` is an **upper bound estimate**: transactions that were already sent to the PHY but have not completed still count as in-flight, but they may already have left the command queue.
- If the first backpressure is limited by OSTD rather than by the queue, `CMD_QUEUE_DEPTH_ENG` may be approximately equal to `OSTD_DEPTH_ENG`; the report must state whether the two can be distinguished.
- Measure the single-port read-only, write-only and mixed scenarios separately; the mixed scenario reflects the shared queue, the read-only/write-only cases are used for separation.
- Record the result as `CMD_QUEUE_DEPTH_ENG`, do not write it as a hard IP specification.

### 3.6 Latency Quantiles

- With a histogram: `P99` = the smallest bin upper bound whose cumulative count reaches 99%; also report P50/P95/P99.
- Without a histogram: only min/max/mean and the absolute max may be reported; P99 must not be claimed. If a single value must be given, use P95 (which requires a sample FIFO) and mark it as such.
- The absolute max is recorded separately as an outlier and is not back-filled directly into `*_LATENCY_MAX`.
- When the number of samples is less than `MIN_SAMPLES` (default 1000), the quantiles are for reference only and this is marked in the report.

### 3.7 Valid/Invalid Runs

A run is judged invalid if any of the following occurs:

- the APM `LAT_*_OVERFLOW` is not 0 (per-ID FIFO overflow or histogram overflow);
- the APM `LAT_ERR_COUNT` is not 0 (a completed transaction has no timestamp);
- the TG `timeout` or `error` is set;
- the ILA captures an AXI protocol violation;
- the DUT hangs or needs a reset to recover;
- the clock frequency changes by more than 1% within the sampling window.

The data of an invalid run must not enter the back-fill table.
