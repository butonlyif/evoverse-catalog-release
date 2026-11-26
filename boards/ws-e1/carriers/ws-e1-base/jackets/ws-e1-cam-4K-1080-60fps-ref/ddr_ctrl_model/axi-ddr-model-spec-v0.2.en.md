[中文](axi-ddr-model-spec-v0.2.md) | English

# TJ Series DDR Hard IP Controller AXI Behavioral Model Design Specification

**Document ID**: SPEC-DDR-AXI-MODEL-v0.2  
**Applies to**: Efinix TJ series DDR DRAM hard IP controller (LPDDR4/LPDDR4x)  
**Model level**: AXI functional/transaction level + backpressure/arbitration/approximate latency  
**Reference document**: UG-DDR-DRAM-TI-v3.0 (May 2026)  
**Supersedes**: SPEC-DDR-AXI-MODEL-v0.1  
**Date**: 2026-10-21  
**Status**: Review revision draft (may enter functional model implementation)

---

## 1. Purpose, Scope and Normative Conventions

### 1.1 Purpose

This document defines the design specification of the AXI-side behavioral model of the TJ series DDR hard IP controller. The model is used for:

- SoC/FPGA system functional verification;
- software driver development and AXI interconnect debugging;
- providing manual-compliant AXI slave-side behavior when vendor RTL/simulation models are unavailable;
- approximating the real hard IP performance trend through parameterized queue depth, latency and outstanding, after measurement.

### 1.2 Scope

**In the modeling scope:**

- two AXI4 slave interfaces (target 0 / target 1);
- AXI read/write channels, bursts, narrow transfers, WSTRB, ID, responses;
- dual-port round-robin arbitration;
- command queue / write data queue / read data queue abstractions and backpressure;
- parameterized read latency, write response latency, arbitration latency, synchronization latency;
- configuration controller `CFG_*` handshake state machine;
- reset behavior;
- idealized DRAM storage array;
- address mapping, capacity conversion, rank/chip-select behavior;
- error/boundary checks explicitly stated in the manual.

**Out of the modeling scope:**

- DDR PHY electrical behavior (ODT, drive strength, VREF, ZQ, DBI, DM electrical);
- LPDDR4/LPDDR4x command timing (tRCD, tRP, tRAS, tFAW, refresh, bank conflicts);
- CA/DQ training, write leveling, read gate/eye training;
- precise cycle-level DRAM scheduling;
- configuration register address/field mapping (not published in the manual);
- performance sign-off level accuracy;
- the full semantics of AXI exclusive access (not supported by the model).

### 1.3 Normative conventions

This document uses the following marker for every key behavior:

| Marker | Meaning |
|---|---|
| `[UG]` | Explicitly stated in the manual. The implementation must follow it; if the manual contradicts itself, handle it as an erratum per Chapter 3 |
| `[AXI4]` | Not stated in the manual; modeled per the AMBA AXI4 specification |
| `[MODEL]` | A model implementation choice or assumption; it does not represent real hard IP behavior |
| `[CONFIRM]` | Requires measurement or vendor confirmation; it must not be treated as a verified premise during implementation |

**General principles:**

1. What the manual explicitly states takes precedence over AXI4 defaults; when the manual does not state something, model it per AXI4 and mark it `[AXI4]`.
2. When the manual contradicts itself, the signal names and the global signal table take precedence (see Chapter 3).
3. Any simplification made "to make the model work" must be marked `[MODEL]` and must not be written up as a hard IP guarantee in the verification report.

---

## 2. Terminology

| Term | Explanation |
|---|---|
| AXI target | The two AXI4 slave interfaces provided by the hard IP, denoted x=0/1 |
| controller clock / `ctrl_clk` | DDR controller clock, usually 1/4 of the PHY data rate |
| AXI clock / `ACLK_x` | AXI interface clock, may be asynchronous to `ctrl_clk` |
| CMD queue | Abstraction of the controller command queue |
| WD/RD queue | Abstraction of the write data / read data queues |
| OSTD | Outstanding, number of transactions in flight |
| CS | Chip Select, rank selection |
| ENG | Engineering estimate, an engineering approximation rather than a hard IP specification |
| P99 | 99th percentile of the samples; the definition is given in the test spec |
| DUT | Device under test; here the TJ DDR hard IP controller |
| SLVERR/DECERR | AXI response error types |
| EARLY_B | Write response mode where `BVALID` returns earlier than `WLAST` |

---

## 3. Manual Errata and Interpretation

UG-DDR-DRAM-TI-v3.0 contains several typographic/OCR/internal inconsistencies. The model implementation follows the table below; ambiguities not listed in the table are handled as `[AXI4]` or `[MODEL]`.

| # | Manual location | Problem | Model handling |
|---:|---|---|---|
| E1 | Table 6 vs Table 14 | The global signal table writes `ARSTN_x` as active-low; the Reset table writes `ARST_X` as active-high | `ARSTN_x` active-low asynchronous reset takes precedence; `ARST_X` is treated as a naming/polarity typo |
| E2 | Table 9 | The `BRESP_x[1:0]` description is written as “Read response ... status of the read transfer” | Understood as the write response; the model's `BRESP` returns the write transaction status |
| E3 | Table 8 / Table 10 | The Direction column is misaligned, making the direction of `WREADY`/`ARREADY` and similar signals hard to read | Implemented per AXI4 slave-side direction: `WREADY/ARREADY/RVALID/BVALID` are outputs, data/address/control are inputs |
| E4 | Table 7 `AWCOBUF` section | The paragraph layout is confused; the semantics of “AWCACHE_x must be set to 'b1111 for AWCOBUF_x” are incomplete | Interpret `AWCOBUF` only when `AWCACHE=4'b1111`; `AWCACHE=4'b0000` is defined separately; other encodings are handled as `[MODEL]` |
| E5 | Address Mapping | The field boundaries of the low-density example are easy to misread: `[27:26] Chip select` overlaps with `[26:12] Row`; the actual layout should be `[27]` CS, `[26:12]` Row | Functional access uses the linear byte address; field decode is used only for debugging, see 7.9 |
| E6 | Table 15 | “Memory Density” has no unit, only “per channel” | Interpreted as **Gbit per channel**; the model uses binary 2^30 conversion, see 6.2 |
| E7 | Figure 5 / Figure 6 | The `WSTRB` text and the byte lane positions are scrambled | The AXI4 lane rules take precedence: `WSTRB[n]` corresponds to `WDATA[8n+7:8n]`; the figures are examples only |
| E8 | Table 5 | Only the upper limits of SIZE=4/5/6 are listed, SIZE≤3 is not listed | The upper limit for SIZE≤3 is modeled as the AXI4 limit of 256 beats, marked `[AXI4]`, and added to the measurement-confirmation list |
| E9 | Table 6 | The Clock Domain column is misaligned | The clock domain of `ACLK_x` is N/A; `ARSTN_x` is synchronous to `ACLK_x` |
| E10 | AXI Interface features | Only “Incrementing and wrapping burst types” are listed, FIXED is not | The model does not support FIXED by default and returns SLVERR; `SUPPORT_FIXED_BURST=0` |

> Note: E1 already covers the naming/polarity conflict between `ARST_X` and `ARSTN_x`; all external interfaces use the `ARSTN_x` naming, active-low. The `AWCACHE=0000` combination of `AWCOBUF` is handled separately per 7.4 and is not asserted by `AWCOBUF_STRICT`.

---

## 4. Model Overview

### 4.1 Top-Level Architecture

```text
                 ┌──────────────────────────────────────────────┐
 AXI0 ──────────►│  AXI0 Channel Engine                         │
 (ACLK_0/ARSTN_0)│    ├─ AW/W/B ch (AWREADY dep WVALID)         │
                 │    ├─ AR/R channel                           │
                 │    ├─ legality checks                        │
                 │    └─ Outstanding/ID mgmt                    │
                 ├──────────────────────────────────────────────┞
 AXI1 ──────────►│  AXI1 Channel Engine (same as above)         │
 (ACLK_1/ARSTN_1)│                                              │
                 ├──────────────────────────────────────────────┞
                 │  Round-Robin Arbiter                         │
                 ├──────────────────────────────────────────────┞
                 │  Command Queue (param. depth)                │
                 ├──────────────────────────────────────────────┞
                 │  Write data queue / read data queue          │
                 ├──────────────────────────────────────────────┞
                 │  Latency model (read/write/arb/sync)         │
                 ├──────────────────────────────────────────────┞
                 │  Address Decoder + capacity/legality         │
                 ├──────────────────────────────────────────────┞
                 │  Ideal DRAM Storage Array                    │
                 │  (MEM_BYTES linear byte array)               │
                 ├──────────────────────────────────────────────┞
 CFG_* ─────────►│  Configuration Controller FSM                │
                 ├──────────────────────────────────────────────┞
                 │  Controller Status Generator (opt)           │
                 └──────────────────────────────────────────────┘
```

### 4.2 Model Boundaries

- **AXI side**: complete AXI4 slave-side behavior; exclusive access is not implemented.
- **DRAM side**: no real DQ/DQS pins are exposed, a linear byte storage array is used internally instead.
- **Configuration side**: only `CFG_RESET/CFG_START/CFG_DONE/CFG_SEL` are modeled, the configuration register bus is not modeled.
- **Status side**: abstract controller status signals are output, the concrete definitions are in Chapter 15, all of them `[MODEL]`.
- **Performance side**: latency/queue/arbitration are trend models, not cycle-accurate models.

---

## 5. Interface Definition

### 5.1 AXI Global Signals

The model provides two AXI4 slave interfaces, x = 0 or 1.

| Signal | Direction | Clock domain | Description |
|---|---|---|---|
| `ACLK_x` | Input | — | AXI clock, may be asynchronous to `ctrl_clk` `[UG]` |
| `ARSTN_x` | Input | `ACLK_x` | AXI interface active-low asynchronous reset `[UG]` |

> The polarity of `ARSTN_x` follows the signal name and Table 6; `ARST_X active-high` in Table 14 is erratum E1.

### 5.2 Write Address Channel

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `AWADDR_x` | Input | 33 | Write address, `AWADDR[32:0]` `[UG]` |
| `AWBURST_x` | Input | 2 | Burst type: `01=INCR`, `10=WRAP`; `00=FIXED` unsupported by default `[UG][MODEL]` |
| `AWID_x` | Input | 6 | Write transaction ID `[UG]` |
| `AWLEN_x` | Input | 8 | Burst length encoding; the actual beat count = `AWLEN+1`, 1–256 `[UG]` |
| `AWREADY_x` | Output | 1 | Address ready; the conditions are in 7.2 `[UG]` |
| `AWSIZE_x` | Input | 3 | Bytes-per-beat encoding; 0–6 supported (1–64 bytes) `[UG]` |
| `AWVALID_x` | Input | 1 | Address valid `[UG]` |
| `AWLOCK_x` | Input | 1 | Lock type; accepted and ignored by the model, exclusive is not supported `[MODEL]` |
| `AWAPCMD_x` | Input | 1 | Write auto precharge; accepted and ignored by the model `[MODEL]` |
| `AWQOS_x` | Input | 4 | QoS; ignored by default, weighted arbitration is optional `[MODEL]` |
| `AWCACHE_x` | Input | 4 | Used by the manual to decide the `BVALID` timing; not modeled with AXI cache semantics `[UG]` |
| `AWALLSTRB_x` | Input | 1 | Write all-strobe; at most 16 AXI beats when this signal is used `[UG]` |
| `AWCOBUF_x` | Input | 1 | Write coherent-buffer selection; only defined when `AWCACHE=4'b1111` `[UG]` |

### 5.3 Write Data Channel

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `WDATA_x` | Input | 512 | Write data `[UG]` |
| `WLAST_x` | Input | 1 | Last beat of a write burst `[UG]` |
| `WREADY_x` | Output | 1 | Write data ready; depends only on reset and write data queue space, see 7.3 `[UG][MODEL]` |
| `WSTRB_x` | Input | 64 | Write byte strobes, one per 8 bits; `WSTRB[n]` corresponds to `WDATA[8n+7:8n]` `[UG][AXI4]` |
| `WVALID_x` | Input | 1 | Write data valid `[UG]` |

> The Direction column of Table 8 is misaligned; the table above implements the AXI4 slave-side direction (erratum E3).

### 5.4 Write Response Channel

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `BID_x` | Output | 6 | Write response ID, corresponds to `AWID_x` `[UG]` |
| `BREADY_x` | Input | 1 | Write response ready `[UG]` |
| `BRESP_x` | Output | 2 | Write response: `00=OKAY`, `10=SLVERR`, `11=DECERR` `[UG][AXI4]` |
| `BVALID_x` | Output | 1 | Write response valid `[UG]` |

> Table 9 describes `BRESP` as “Read response”; per erratum E2 it is understood as the write response.

### 5.5 Read Address Channel

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `ARADDR_x` | Input | 33 | Read address `[UG]` |
| `ARBURST_x` | Input | 2 | Burst type: `01=INCR`, `10=WRAP`; `00=FIXED` unsupported by default `[UG][MODEL]` |
| `ARID_x` | Input | 6 | Read transaction ID `[UG]` |
| `ARLEN_x` | Input | 8 | Burst length encoding; the actual beat count = `ARLEN+1`, 1–256 `[UG]` |
| `ARREADY_x` | Output | 1 | Address ready; the conditions are in 7.5 `[UG]` |
| `ARSIZE_x` | Input | 3 | Bytes-per-beat encoding; 0–6 supported `[UG]` |
| `ARVALID_x` | Input | 1 | Address valid `[UG]` |
| `ARLOCK_x` | Input | 1 | Lock type; accepted and ignored by the model `[MODEL]` |
| `ARAPCMD_x` | Input | 1 | Read auto precharge; accepted and ignored by the model `[MODEL]` |
| `ARQOS_x` | Input | 4 | QoS; ignored by default `[MODEL]` |

> **Important**: the read address interface of UG Table 10 has **no `ARCACHE_x` and no `ARPROT_x`**, but it does have `ARAPCMD_x`. The interface table of v0.1 was wrong; v0.2 has been corrected. During system integration do not connect non-existent signals to the hard IP.

### 5.6 Read Data Channel

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `RDATA_x` | Output | 512 | Read data `[UG]` |
| `RID_x` | Output | 6 | Read ID, corresponds to `ARID_x` `[UG]` |
| `RLAST_x` | Output | 1 | Last beat of a read burst `[UG]` |
| `RREADY_x` | Input | 1 | Read data ready `[UG]` |
| `RRESP_x` | Output | 2 | Read response `[UG][AXI4]` |
| `RVALID_x` | Output | 1 | Read data valid `[UG]` |

### 5.7 Configuration Controller Interface

| Signal | Direction | Description |
|---|---|---|
| `CFG_RESET` | Input | Active-high startup sequence reset; resets the configuration controller, the DDR controller, the PHY and the DRAM simultaneously `[UG]` |
| `CFG_START` | Input | Starts the configuration sequence; it must stay high after `CFG_DONE` goes high `[UG]` |
| `CFG_SEL` | Input | Tied low to enable the configuration controller `[UG]` |
| `CFG_DONE` | Output | Configuration/calibration sequence complete `[UG]` |

Constraints:

- `CFG_RESET` must be held for at least 5 `ctrl_clk` cycles `[UG]`;
- `CFG_START` must stay high after `CFG_DONE` goes high `[UG]`;
- `CFG_SEL` tied low enables the controller `[UG]`.

### 5.8 Controller Status Interface

The model outputs a set of abstract status signals; the names and widths are `[MODEL]`; the manual only mentions the existence of Controller Status Signals and does not give a complete list.

| Signal | Direction | Description |
|---|---|---|
| `CTRL_INIT_DONE` | Output | Initialization/calibration complete |
| `CTRL_READY` | Output | Able to accept AXI transactions |
| `CTRL_ERR` | Output | Aggregate flag for internal errors/illegal accesses |
| `CTRL_BUSY` | Output | Queue not empty or the arbiter is busy |

> These signals are disabled by default and controlled by `ENABLE_CTRL_STATUS`; they must not be treated as real hard IP pins defined by the manual.

### 5.9 Clock and Reset

| Signal | Description |
|---|---|
| `ACLK_0/1` | AXI clock, may be asynchronous `[UG]` |
| `ctrl_clk` | Controller clock, usually 1/4 of the PHY data rate `[UG]` |
| `ARSTN_x` | AXI interface active-low asynchronous reset `[UG]` |
| `CFG_RESET` | Active-high global startup sequence reset `[UG]` |

The model supports two clock modes:

1. **Dual-clock mode**: `ACLK_x` is asynchronous to `ctrl_clk`, with internal FIFO synchronization and a parameterized synchronization latency.
2. **Single-clock simplified mode**: `ACLK_x` and `ctrl_clk` share the same source and the synchronization latency parameter is set to 0.

**Clock ratio definition:**

```text
CLK_RATIO_ACLK_PER_CTRL = f_ACLK / f_ctrl_clk
```

Ideally (AXI bandwidth matches DDR bandwidth):

```text
f_ACLK = DDR_data_rate × DATA_WIDTH / AXI_DATA_WIDTH
f_ctrl_clk = DDR_data_rate / 4
CLK_RATIO_ACLK_PER_CTRL = 4 × DATA_WIDTH / AXI_DATA_WIDTH = DATA_WIDTH / 128
```

- x32: 0.25;
- x16: 0.125.

A real system may be above or below that ratio, and parameters override it. All cross-clock-domain latencies are converted with that ratio; the test report must record the actual frequency ratio.

---

## 6. Parameterization

### 6.1 Structural Parameters

| Parameter | Values | Default | Source | Description |
|---|---|---|---|---|
| `DATA_WIDTH` | 16, 32 | 32 | `[UG]` Table 15 | DRAM DQ width |
| `AXI_DATA_WIDTH` | 512 | 512 | `[UG]` Table 8 | AXI data width, fixed at 512 for the TJ hard IP |
| `AXI_ADDR_WIDTH` | 33 | 33 | `[UG]` Table 7/10 | AXI address width |
| `AXI_ID_WIDTH` | 6 | 6 | `[UG]` Table 7/10 | AXI ID width |
| `MEM_DENSITY_GBIT` | 2, 3, 4, 6, 8, 12, 16 | 4 | `[UG]` Table 15 | Density per channel, unit Gbit |
| `MEM_DENSITY_UNIT` | `GBIT_PER_CHANNEL` | Fixed | `[UG][MODEL]` | Unit interpretation; see 6.2 |
| `GBIT_DEFINITION` | `BINARY_2^30` | Fixed | `[MODEL]` | 1 Gbit = 2^30 bit |
| `NUM_CHANNELS` | `DATA_WIDTH/16` | Derived | `[UG]` | x16=1, x32=2 |
| `PHYSICAL_RANK` | 1, 2 | 1 | `[UG]` Table 15 | Number of ranks |
| `MEMORY_TYPE` | LPDDR4, LPDDR4x | LPDDR4 | `[UG]` Table 15 | The functional model only affects parameter labels |
| `NUM_AXI_TARGETS` | 1, 2 | 2 | `[UG]` | Number of AXI interfaces |
| `SUPPORT_WRAP_BURST` | 0, 1 | 1 | `[UG]` | Whether WRAP is supported |
| `SUPPORT_NARROW` | 0, 1 | 1 | `[UG]` | Whether narrow transfer is supported |
| `SUPPORT_FIXED_BURST` | 0, 1 | 0 | `[UG]`/`[MODEL]` | The manual lists only INCR/WRAP; FIXED is rejected by default |
| `SUPPORT_AWALLSTRB` | 0, 1 | 1 | `[UG]` | Whether `AWALLSTRB` is supported |
| `SUPPORT_EXCLUSIVE` | 0 | 0 | `[MODEL]` | Exclusive is not supported; `*LOCK` is ignored |
| `ADDR_MAP_MODE` | `LINEAR`, `FIELD_DECODE_DEBUG` | `LINEAR` | `[MODEL]` | Functional access uses the linear address; field decode is debug only |
| `RANK_MAP_MODE` | `CS_STRIDE`, `CS_BIT`, `SINGLE_RANK` | `CS_STRIDE` | `[MODEL]` | Rank selection method; see 7.9. Phase 7: single rank at board level, all modes behave equivalently with `PHYSICAL_RANK=1`, keep the default |
| `CS_BIT_POS` | 0–32 | Derived | `[UG][MODEL]` | Used only in `CS_BIT` mode; must equal `log2(RANK_STRIDE_BYTES)`. Phase 7: not applicable for single rank, keep the derived default |
| `ADDR_HOLE_POLICY` | `DECERR`, `ALIAS` | `DECERR` | `[MODEL]` | Handling of address holes for non-power-of-two densities. Phase 7: the real hard IP silently wraps out-of-range accesses (not DECERR), but `ALIAS` has only hole-window semantics and is banned as a default → keep `DECERR`, record the out-of-range behavior difference as a documented deviation (§18/plan §9 Phase 7) |
| `MEM_INIT_MODE` | `ZERO`, `RANDOM`, `PATTERN` | `ZERO` | `[MODEL]` | Memory initialization |
| `MEM_INIT_SEED` | Any 32-bit value | 1 | `[MODEL]` | Random initialization seed |

### 6.2 Memory Capacity and Derivation

`MEM_DENSITY_GBIT` is the DRAM density (Gbit) **per channel** `[UG]` Table 15. The model converts with binary arithmetic:

```text
MEM_BYTES_PER_CHANNEL = MEM_DENSITY_GBIT × 2^30 / 8
NUM_CHANNELS          = DATA_WIDTH / 16
RANK_STRIDE_BYTES     = MEM_BYTES_PER_CHANNEL × NUM_CHANNELS
MEM_BYTES             = RANK_STRIDE_BYTES × PHYSICAL_RANK
```

Examples:

| Configuration | Bytes per channel | Bytes per rank | Total bytes |
|---|---:|---:|---:|
| 4G, x16, 1 rank | 512 MiB | 512 MiB | 512 MiB |
| 4G, x32, 1 rank | 512 MiB | 1 GiB | 1 GiB |
| 16G, x32, 2 rank | 2 GiB | 4 GiB | 8 GiB |
| 3G, x32, 1 rank | 384 MiB | 768 MiB | 768 MiB |

Rules:

- The AXI addressable byte space is `[0, MEM_BYTES-1]`; `MEM_BYTES` does not have to be a power of two (3G/6G/12G).
- `MEM_BYTES` must be ≤ `2^AXI_ADDR_WIDTH`, otherwise the configuration is illegal.
- The storage array is allocated with `MEM_BYTES`; it must not be allocated over the whole AXI space.
- `CS_BIT` mode is not enabled for non-power-of-two densities; ranks are compared with a stride comparator.
- Every “address” in this document means an AXI byte address by default, not a DRAM word address.

### 6.3 Performance Parameters (pending measurement)

| Parameter | Default | Source | Description |
|---|---:|---|---|
| `CMD_QUEUE_DEPTH` | 8 | `[CONFIRM]` | Command queue depth, engineering initial value; Phase 3 board-level measurement accepted all 16 read transactions with no backpressure → real hard IP lower bound ≥16 (board-level TG connects directly to the real hard IP with no shell gating layer, see correlation-plan §6-10/§9) |
| `WRITE_DATA_QUEUE_DEPTH` | 16 | `[CONFIRM]` | Write data queue depth |
| `READ_DATA_QUEUE_DEPTH` | 16 | `[CONFIRM]` | Read data queue depth |
| `READ_OSTD_DEPTH` | 8 | `[CONFIRM]` | Read outstanding upper limit |
| `WRITE_OSTD_DEPTH` | 8 | `[CONFIRM]` | Write outstanding upper limit |
| `OUT_OF_ORDER_ENABLE` | 0 | `[CONFIRM]` | Whether different IDs may complete out-of-order |
| `R_INTERLEAVE_ENABLE` | 0 | `[MODEL]` | Whether read data beats of different IDs may interleave |
| `ARB_GRANT_INTERVAL` | 2 | `[UG]` | Round-robin can arbitrate once every two cycles. **Note: effective only on the g_sync path (CDC_ENABLE=0)**; the CDC topology measured in Phase 4 (the board-level equivalent) does not pass through this arbiter, dual-port scheduling = fixed 1:1 alternating collection + core_scheduler |
| `ARB_QUIET_FAST_PATH` | 1 | `[UG]` | When the other interface is idle it can be served every cycle (same g_sync-only) |
| `ARB_QOS_WEIGHT_EN` | 0 | `[MODEL]` | Whether QoS weighting is used; not defined in the manual |

> The `[CONFIRM]` defaults are engineering initial values, not manual values. After measurement they are back-filled per the test spec, and the original estimates keep the `_ENG` suffix in the report.

### 6.4 Latency Parameters

Unless explicitly stated otherwise, the unit of all model-internal latencies is a `ctrl_clk` cycle.

| Parameter | Default (ctrl_clk) | Description |
|---|---:|---|
| `SYNC_LATENCY` | 2 | AXI→controller clock domain synchronization; a fitted/apportionment parameter |
| `ARB_LATENCY` | 0–2 | Additional arbitration latency |
| `READ_LATENCY_MIN` | 10 | Minimum latency from the AR handshake to the first R beat |
| `READ_LATENCY_MAX` | 30 | Jitter upper bound from the AR handshake to the first R beat |
| `R_BEAT_INTERVAL` | 1 | Minimum interval between adjacent R beats of the same burst |
| `WRITE_RESP_LATENCY_MIN` | 8 `[ENG]` | Queueing jitter component from the AW handshake to B for non-early-return encodings (`AWCACHE[0]=0`); the actual `T_AW_B` is dominated by the data commit path (`WRITE_DATA_TO_B_LATENCY`) |
| `WRITE_RESP_LATENCY_MAX` | 24 `[ENG]` | Same as above (jitter upper bound) |
| `WRITE_DATA_TO_B_LATENCY` | 4 → **451** (calibrated) | Additional latency from the WLAST handshake to BVALID for non-early-return encodings; Phase 2 board-level back-fill (board WL 55-99 ACLK ×8, correlation-plan §9) |
| `BVALID_CMD_QUEUE_DELAY` | 2 → **28** (calibrated) | Delay from command acceptance to BVALID for early-return encodings (`AWCACHE[0]=1`, including `1111+cobuf`); Phase 5 board-level back-fill (board T_AW_B 4-5 ACLK ×8 = 32-40 ctrl, minus the model CDC structure ≈4) |
| `BVALID_PHY_ISSUE_DELAY` | 2 `[ENG]` | Used only by the `OTHER_AWCACHE_POLICY=PHY_ISSUE` fallback policy; after Phase 5 the default policy does not trigger it |
| `W_ACCEPT_INTERVAL` | 1 | Minimum acceptance interval between adjacent write data beats |
| `LATENCY_MODE` | `UNIFORM` | `FIXED` / `UNIFORM` |
| `LATENCY_SEED` | 1 | Random latency seed, guaranteeing reproducibility |
| `LATENCY_UNIT` | `CTRL_CLK` | Fixed; the test side converts with `CLK_RATIO_ACLK_PER_CTRL` |

Latency reference point definitions (aligned with the test spec):

```text
T_AR_FIRST_R : ARVALID&&ARREADY  ->  first RVALID&&RREADY beat of that transaction
T_AR_RLAST   : ARVALID&&ARREADY  ->  RLAST handshake of that transaction (optional statistic)
T_AW_B       : AWVALID&&AWREADY  ->  BVALID&&BREADY of that transaction
T_WLAST_B    : WLAST handshake    ->  BVALID&&BREADY of that transaction (AWCOBUF=0)
```

- `READ_LATENCY_MIN/MAX` correspond to `T_AR_FIRST_R`.
- `WRITE_RESP_LATENCY_MIN/MAX` are the queueing jitter components of the data commit path `T_AW_B` `[ENG values]`; for `AWCACHE[0]=0` encodings the actual `T_AW_B ≈ T_WLAST_B`, dominated by `WRITE_DATA_TO_B_LATENCY` (calibrated 451). The bare `AWCACHE=1111` value deadlocks AW/W at board level (correlation Phase 2) and is no longer used as a baseline combination.
- In early-return mode (`AWCACHE[0]=1`), `T_AW_B` is determined by `BVALID_CMD_QUEUE_DELAY` (calibrated 28); `BVALID_PHY_ISSUE_DELAY` is used only by the `OTHER_AWCACHE_POLICY=PHY_ISSUE` fallback policy and is not shared with the data commit path min/max.
- `SYNC_LATENCY` cannot be observed independently from the AXI boundary alone; it is fitted/apportioned from experiments with several `ACLK:ctrl_clk` ratios `[MODEL]`.

**Cross-clock-domain conversion:**

```text
latency_aclk_cycles = ceil( (latency_ctrl_cycles + sync_ctrl) × f_ctrl / f_ACLK )
```

The test report gives both the number of ACLK cycles and the converted ctrl_clk cycle count, and records the actual frequency.

### 6.5 BVALID Timing Parameters

| Parameter | Default | Description |
|---|---|---|
| `BVALID_TIMING_MODE` | `MANUAL_STRICT` | After Phase 5 the bit0 pattern is built into the B timing decision (`cmd_is_early`); the current implementation does not use this parameter (kept for compatibility) |
| `OTHER_AWCACHE_POLICY` | `DATA_DONE` | Fallback policy, effective only for `AWCACHE[0]=0` encodings: `DATA_DONE` (B after data completion, board-level consistent, default) / `CMD_QUEUE` / `PHY_ISSUE` (all early return). `AWCACHE[0]=1` is always early return and is not affected by this parameter |
| `AWCOBUF_STRICT` | 1 | Sets `CTRL_ERR` when `AWCOBUF=1` and `AWCACHE` is not in `{1111, 0000}`; `AWCOBUF` is ignored when `AWCACHE=0000`. Phase 5 measurement showed that COBUF has no independent effect on the B timing (0000/1110 × cobuf all have the same shape); STRICT is conservatively kept at the default 1; `1111+cobuf` is not measurable at board level (bare 1111 deadlocks) |

### 6.6 Error and Boundary Parameters

| Parameter | Default | Description |
|---|---|---|
| `ERR_CROSS_4KB` | `SLVERR` | Burst crosses 4KB |
| `ERR_BURST_LEN` | `SLVERR` | `AWLEN/ARLEN` exceeds the Table 5 upper limit |
| `ERR_BURST_SIZE` | `SLVERR` | `AWSIZE/ARSIZE > 6` (>64 bytes) |
| `ERR_FIXED_BURST` | `SLVERR` | FIXED burst and `SUPPORT_FIXED_BURST=0` |
| `ERR_ADDR_RANGE` | `DECERR` | Address ≥ `MEM_BYTES` |
| `ERR_ADDR_HOLE` | `DECERR` | Address hole only in field-decode/explicit hole-table mode |
| `ERR_WSTRB_INVALID` | `IGNORE` | Illegal WSTRB: `IGNORE`/`ASSERT`/`SLVERR` |
| `ERR_ALLSTRB_BEATS` | `SLVERR` | `AWALLSTRB=1` and the beat count > 16 |
| `ERR_ALLSTRB_WSTRB` | `SLVERR` | `AWALLSTRB=1` but WSTRB is not all 1 |
| `ERR_INJECT_RATE` | 0 | Random error injection probability, 0 disables it |
| `NARROW_READ_INVALID_LANE` | `ZERO` | Return value for invalid lanes of a narrow read: `ZERO`/`KEEP`/`X` |

### 6.7 Configuration and Reset Parameters

| Parameter | Default | Description |
|---|---|---|
| `INIT_CYCLES` | 1000 | Abstract initialization/calibration duration (ctrl_clk) |
| `INIT_AXI_BLOCK` | 1 | Whether AXI is blocked during initialization |
| `INIT_AXI_RESP` | `BACKPRESSURE` | AXI behavior during initialization: `BACKPRESSURE`/`SLVERR` |
| `CFG_RESET_CLEAR_MEM` | 0 | Whether `CFG_RESET` clears the storage |
| `ENABLE_CTRL_STATUS` | 0 | Whether the controller status signals are output |

---

## 7. AXI Behavior Specification

### 7.1 Global Rules

- The model conforms to AMBA AXI4 slave-side behavior `[AXI4]`.
- Once `*VALID` is asserted it must be held until `*READY` is asserted; `*VALID` must not be withdrawn before `*READY` `[AXI4]`.
- During reset all outputs are `VALID=0` `[AXI4]`.
- Transactions with the same ID respond in order `[AXI4]`.
- With `OUT_OF_ORDER_ENABLE=0` the model responds in the global AR/AW acceptance order; this is stricter than the AXI4 minimum requirement `[MODEL]`.
- With `OUT_OF_ORDER_ENABLE=1` different IDs may complete out-of-order, the same ID stays in order; by default read beats are not interleaved (`R_INTERLEAVE_ENABLE=0`) `[MODEL]`.
- FIXED burst is not supported (by default); exclusive access is not supported `[MODEL]`.
- `AWSIZE/ARSIZE` supports only 0–6 (1–64 bytes) `[UG]`.
- `AWLEN/ARLEN` encodes 0–255, the actual beat count is 1–256 `[UG]`.
- All addresses are 33-bit AXI byte addresses.

### 7.2 Write Address Channel

`AWREADY_x` is asserted when the following conditions are **all** met:

1. `ARSTN_x` is high;
2. `AWVALID_x && WVALID_x` (at least the first write data beat is already valid) `[UG]` Figure 4 note;
3. the write outstanding count has not reached `WRITE_OSTD_DEPTH`;
4. the command queue is not full;
5. the write address channel is idle.

> **Critical**: condition 2 comes from the note of UG Figure 4: “AWREADY is asserted after both AWVALID and WVALID are asserted.” The model must not assert `AWREADY` while `WVALID=0`. This differs from a general AXI4 slave `[UG]`.

After accepting `AW`, record: address, burst, length, size, ID, cache, cobuf, allstrb.

Check items (on failure the AW handshake still completes and the error is returned on the B channel; the write data must still be received to avoid deadlock):

| Check | Condition | Default response |
|---|---|---|
| burst size | `AWSIZE > 6` | `ERR_BURST_SIZE` |
| burst length | exceeds the Table 5 upper limit (see 7.7) | `ERR_BURST_LEN` |
| 4KB boundary | `start_addr + (AWLEN+1)×2^AWSIZE` crosses 4KB | `ERR_CROSS_4KB` |
| address range | `addr ≥ MEM_BYTES` | `ERR_ADDR_RANGE` |
| address hole | checked only in `FIELD_DECODE_DEBUG` when a hole table is configured | `ERR_ADDR_HOLE` |
| WRAP legality | the length is not 2/4/8/16 or the start address is not aligned | `ERR_CROSS_4KB`/`ERR_BURST_LEN` (depending on the specific check) |
| FIXED | `AWBURST=00` and `SUPPORT_FIXED_BURST=0` | `ERR_FIXED_BURST` |
| `AWALLSTRB` beat count | `AWALLSTRB=1` and `AWLEN+1 > 16` | `ERR_ALLSTRB_BEATS` |
| `AWCOBUF` semantics | `AWCOBUF=1` and `AWCACHE` not in `{1111,0000}` | asserted (`AWCOBUF_STRICT=1`); handled as ignored; `AWCOBUF` is ignored when `AWCACHE=0000` |

When `AWALLSTRB=1` the model handles it as “all-strobe”: the following `WSTRB` must be all 1, otherwise `ERR_ALLSTRB_WSTRB` applies. When `AWALLSTRB=0` the normal WSTRB handling applies.

### 7.3 Write Data Channel

- `WREADY_x` depends only on:
  1. `ARSTN_x` is high;
  2. the write data queue is not full.
- `WREADY_x` **does not depend** on whether `AW` has already been accepted. AXI allows the write data to arrive before the write address `[AXI4]`; the model allows the W data to be queued first and matches it once AW arrives.
- The write data updates the storage according to `WSTRB_x`; `WSTRB[n]=1` means `WDATA[8n+7:8n]` is valid `[AXI4]`.
- Narrow transfer is supported: only valid lanes update the storage; invalid lanes do not update it.
- A beat with an all-zero `WSTRB` is legal and does not update the storage `[AXI4]`.
- `WLAST_x` must match the beat count of `AWLEN` `[AXI4]`.
- When `AWALLSTRB=1`, `WSTRB` must be all 1, otherwise `ERR_ALLSTRB_WSTRB` applies.
- If the number of write data beats exceeds `AWLEN+1` or falls short of it, that is a protocol error; the model records it and asserts. If B has already returned early, `BRESP` cannot be retroactively modified, so only `CTRL_ERR`/the assertion is recorded `[MODEL]`.
- In early-return mode (`AWCACHE[0]=1`, Bufferable), B may precede `WLAST`; the model must still receive all W data `[UG][MODEL]`. Note that `AWCACHE=0000` was measured at board level as non-early-return (B after the data commit) and is not in this category.
- The write data may be accepted before AW; if the W data queue is full, `WREADY` is deasserted, but `AWREADY` may still be asserted when `AWVALID&&WVALID` and the command queue has space (the first WVALID already exists).

### 7.4 Write Response Channel

The `BVALID_x` timing follows `AWCACHE` / `AWCOBUF`:

| `AWCACHE` | `AWCOBUF` | BVALID timing | Source |
|---|---|---|---|
| `4'b1111` | 1 | after the command is accepted into the controller command queue; **may precede WLAST** (early-return delay `BVALID_CMD_QUEUE_DELAY`=28 ctrl calibrated) | `[UG][board Phase 5]` |
| `4'b1111` | 0 | unusable because of the board-level AW/W deadlock (correlation Phase 2); the model returns early following the `AWCACHE[0]=1` pattern | `[board Phase 2][MODEL]` |
| `4'b0000` | any | after all write data is committed (COBUF has no independent effect, board-level 0000±cobuf has the same shape, WA/WL 55-99 ACLK); **non-early-return**. The manual semantics of "after the command is issued to the PHY" do not match the measurement and have been corrected | `[board Phase 5][MODEL]` |
| other `AWCACHE[0]=1` (board-level measured `0001/0011/0111`) | any | early return: BVALID within `BVALID_CMD_QUEUE_DELAY` after command acceptance; board-level AW handshake +4-5 ACLK, all measured with the same shape | `[board Phase 5][MODEL]` |
| other `AWCACHE[0]=0` (board-level measured `0010/0100/1110`) | any | after the data commit: `WRITE_DATA_TO_B_LATENCY` dominates; the same shape as 0000 at board level (WA/WL 55-99 ACLK) | `[board Phase 5][MODEL]` |

> The conclusion of the 9-block matrix of correlation Phase 5 (2026-10-23) at board level: the B timing is determined solely by `AWCACHE[0]` (Bufferable), and `AWCOBUF` has no independent effect; 9 encodings were measured and the rest are extrapolated following the bit0 pattern, see correlation-plan §9.

- `BID_x` corresponds to `AWID_x`.
- `BRESP_x` is `OKAY` by default; on a failed check `SLVERR`/`DECERR` is returned per `ERR_*`.
- Write responses with the same ID are ordered `[AXI4]`.
- In early-return mode B may be issued before the W data completes; errors in the later W data cannot change the already issued `BRESP`, so the model records the error and asserts `[MODEL]`.
- `BVALID` must not be issued before the `AW` handshake.
- There is no fixed ordering between `BVALID` and `WREADY`/`WVALID`; this is especially true in early-return mode.

### 7.5 Read Address Channel

`ARREADY_x` is asserted when the following conditions are met simultaneously:

1. `ARSTN_x` is high;
2. the read outstanding count has not reached `READ_OSTD_DEPTH`;
3. the command queue is not full;
4. the read address channel is idle.

The check items are the same as for the write address (length, size, 4KB, range, hole, WRAP, FIXED). On a failed check the error is recorded and an error response is returned on the R channel; the read data must still be returned according to the burst length (or terminated early per the `ERR_*` policy; by default the full burst is returned with an error response) `[MODEL]`.

- `ARAPCMD_x`, `ARLOCK_x`, `ARQOS_x` are accepted and ignored `[MODEL]`.
- The read address interface has no `ARCACHE/ARPROT`; do not connect those signals `[UG]`.

### 7.6 Read Data Channel

- `RVALID_x` is asserted after the `READ_LATENCY_*` delay; the delay is counted from the AR handshake and corresponds to `T_AR_FIRST_R`.
- The interval between R beats of the same burst is not smaller than `R_BEAT_INTERVAL`.
- Each beat returns data in the corresponding byte lane according to `ARSIZE` and the address.
- Narrow read: valid lanes return the stored data; invalid lanes return `0`/hold/`X` per `NARROW_READ_INVALID_LANE` `[MODEL]`.
- `RLAST_x` is asserted on the last beat.
- `RID_x` corresponds to `ARID_x`.
- `RRESP_x` is `OKAY` by default; on a failed check `ERR_*` applies.
- Read data with the same ID is ordered; with `OUT_OF_ORDER_ENABLE=0` the global order is preserved.
- With `R_INTERLEAVE_ENABLE=1` R beats of different IDs may interleave; the default is 0 (a whole burst stays contiguous) `[MODEL]`.
- When the read data queue is full, `RVALID` may be backpressured; the internal read command dequeue is paused and `ARREADY` may be deasserted.

### 7.7 Burst Rules

Supported types: INCR, WRAP; FIXED is not supported by default `[UG][MODEL]`.

**Maximum burst length `[UG]` Table 5:**

| `AWSIZE/ARSIZE` | Bytes | `AWLEN/ARLEN` upper limit | Source |
|---:|---:|---:|---|
| 6 | 64 | 63 | `[UG]` |
| 5 | 32 | 127 | `[UG]` |
| 4 | 16 | 255 | `[UG]` |
| ≤3 | ≤8 | 256 | `[AXI4]` (not listed in the manual, requires measurement) |

> The limit of 256 for `SIZE≤3` comes from the AXI4 256-beat upper limit, it is not stated explicitly in the manual. Whether `SIZE=3, LEN=256` is supported by the hard IP requires measurement `[CONFIRM]`.

**4KB boundary `[UG]`:**

- total burst bytes = `(AWLEN/ARLEN + 1) × 2^(AWSIZE/ARSIZE)`;
- the start address plus the total bytes must not cross a 4KB boundary;
- a boundary crossing is handled as `ERR_CROSS_4KB`.

**WRAP rules `[AXI4]`:**

- the length may only be 2/4/8/16;
- the start address must be aligned to `(length × 2^SIZE)`;
- the address wrap-around is computed inside the burst;
- the manual does not state the WRAP constraints explicitly, they are added to the measurement-confirmation list `[CONFIRM]`.

**Address increment:**

- INCR: the address of each beat increments by `2^SIZE`;
- for a narrow transfer it still increments by `2^SIZE`, and the lane position of WSTRB changes with the address `[AXI4]`.

### 7.8 Narrow Transfer and WSTRB

- `WSTRB_x[n]` corresponds to `WDATA_x[8n+7:8n]` `[AXI4]`.
- Write: only the byte lanes with `WSTRB=1` are written.
- Read: valid lanes return data, invalid lanes follow `NARROW_READ_INVALID_LANE`.
- The lane position of a narrow transfer is determined by `addr mod (AXI_DATA_WIDTH/8)`; the address increments by `2^SIZE` per beat `[AXI4]`.
- The model should validate the intent of Figure 5/6, but the text layout of the figures is unreliable; the AXI lane rules take precedence (erratum E7).
- When `AWALLSTRB=1` the WSTRB must be all 1, otherwise `ERR_ALLSTRB_WSTRB`.
- A beat with an all-zero `WSTRB` is legal and does not update the storage.

**Lane computation example (`AXI_DATA_WIDTH=512`, 64-byte bus):**

```text
bytes_per_beat = 1 << SIZE
lane_offset    = AXI_addr % 64
WSTRB          = ((1 << bytes_per_beat) - 1) << lane_offset
```

When `lane_offset + bytes_per_beat > 64`, a narrow INCR crosses the beat boundary; after the AXI address is incremented by the size it naturally falls into the next beat, and the model computes the lane from the actual address.

### 7.9 Address Mapping, Capacity and Rank/Chip-Select

#### 7.9.1 Authoritative Rules

- For the user, the AXI address is a contiguous byte space from 0 to `MEM_BYTES-1` `[UG]`.
- Functional access uses the linear byte address to index the storage array; it does not depend on DRAM bank/row/column fields.
- `MEM_BYTES` is computed per 6.2, out-of-range accesses are handled with `ERR_ADDR_RANGE`.
- The address width is 33, but the usable space is determined by `MEM_BYTES`; the whole 2^33 space must not be treated as valid storage.

#### 7.9.2 Manual Examples

**Maximum address space example `[UG]`:**

```text
[32]      Chip select
[31:15]   Row address
[14:12]   Bank address
[11:2]    Column address
[1:0]     Datapath
```

**Low-density example `[UG]`:**

```text
[32:28]   Not used
[27]      Chip select
[26:12]   Row address
[11:9]    Bank address
[8:2]     Column address
[1:0]     Datapath
```

> The layout of the low-density example in the manual is easily misread as `[27:26] Chip select`; the correct boundaries are `[27]` CS and `[26:12]` Row (erratum E5).
> The two examples show that the CS position changes with the address space per rank, it is **not a fixed bit32**.

#### 7.9.3 Rank Mapping Modes

| Mode | Behavior | Applicability |
|---|---|---|
| `CS_STRIDE` (default) | `rank = addr / RANK_STRIDE_BYTES`; `offset = addr % RANK_STRIDE_BYTES` | All densities; also applicable for non-powers of two |
| `CS_BIT` | `rank = addr[CS_BIT_POS]`; `offset` is interpreted from the low bits after the CS bit is cleared | Only for power-of-two rank stride; `CS_BIT_POS=log2(RANK_STRIDE_BYTES)` |
| `SINGLE_RANK` | ignores the rank, requires `PHYSICAL_RANK=1` | Simplified single rank |

- `CS_STRIDE` is equivalent to a bit32 CS under the maximum configuration (16G × x32 × 2 rank).
- Under a low-density configuration `CS_BIT_POS` is derived from `RANK_STRIDE_BYTES`, for example bit27 for 128MiB per rank.
- In `CS_BIT` mode the configuration is illegal if `RANK_STRIDE_BYTES` is not a power of two.
- With `PHYSICAL_RANK=1` the rank is always 0; addresses ≥ `MEM_BYTES` still follow `ERR_ADDR_RANGE`.

#### 7.9.4 Field Decode (debug only)

When `ADDR_MAP_MODE=FIELD_DECODE_DEBUG` the model may output the `cs/row/bank/column/datapath` fields per the selected profile for logging and checks; it is **not used for storage access**.

- `LINEAR` (default): no field decode; the address range check uses `MEM_BYTES`.
- `FIELD_DECODE_DEBUG`: the field widths may be configured; when the total field width does not match `MEM_BYTES` only a warning is recorded and functional access is not affected.
- Field decode is not enabled for non-power-of-two densities (3G/6G/12G); the linear space of 6.2 applies.
- Address hole: `ADDR_HOLE_POLICY=DECERR` returns `DECERR` only when `ADDR_MAP_MODE=FIELD_DECODE_DEBUG` and a hole table/profile is provided; the functional linear model does not simulate holes. `ALIAS` is for testing only and must not be the default.

#### 7.9.5 Controller Word Address (debug)

The controller address mapping of the manual:

```text
x32: controller_addr = AXI_addr >> 2
x16: controller_addr = AXI_addr >> 1
```

This is the DRAM word address conversion; the functional model does not need it to index storage, it is used only for debugging/logging `[UG][MODEL]`.

### 7.10 Error Responses

| Scenario | Default response | Note |
|---|---|---|
| burst crosses 4KB | `SLVERR` | `ERR_CROSS_4KB` |
| burst length exceeds the limit | `SLVERR` | `ERR_BURST_LEN` |
| `SIZE > 6` | `SLVERR` | `ERR_BURST_SIZE` |
| FIXED burst | `SLVERR` | `ERR_FIXED_BURST` |
| address out of range | `DECERR` | `ERR_ADDR_RANGE` |
| address hole | `DECERR` | `ERR_ADDR_HOLE` |
| illegal WRAP | `SLVERR` | the error code is selected per the specific check |
| `WLAST` does not match `AWLEN` | `SLVERR` + assertion | protocol error |
| illegal `WSTRB` | `IGNORE`/`ASSERT`/`SLVERR` | `ERR_WSTRB_INVALID` |
| `AWALLSTRB` beat >16 | `SLVERR` | `ERR_ALLSTRB_BEATS` |
| `AWALLSTRB` WSTRB not all 1 | `SLVERR` | `ERR_ALLSTRB_WSTRB` |

The error response is returned on the B channel or the R channel; the write data may still be received to avoid deadlock `[AXI4]`. In early-return mode an already issued `BRESP` cannot be retroactively modified.

### 7.11 Lock, Exclusive, QoS, Cache

- `AWLOCK/ARLOCK`: accepted and ignored; the model does not support exclusive and the read response never returns `EXOKAY` `[MODEL]`.
- `AWQOS/ARQOS`: ignored by default; they may be used for arbitration weighting when `ARB_QOS_WEIGHT_EN=1`, but the manual does not define the weight semantics `[MODEL]`.
- `AWCACHE`: used only for the BVALID timing; do not map AXI cache semantics onto storage coherency `[UG][MODEL]`.
- `AWCOBUF`: only defined when `AWCACHE=4'b1111`; when `AWCACHE=4'b0000` the `AWCOBUF` is ignored; other combinations are handled per `AWCOBUF_STRICT` `[UG]`.
- `AWAPCMD/ARAPCMD`: accepted and ignored; the functional model has no bank precharge state `[MODEL]`.

---

## 8. Arbiter

### 8.1 Behavior `[UG]`

- The read/write requests of the two AXI interfaces share one round-robin arbiter (**only on the g_sync / CDC_ENABLE=0 path**; with CDC_ENABLE=1 the dual-port commands cross domains separately through axi_port_shell_cdc and then enter the shared command queue through a fixed 1:1 alternating collection logic (`aw/ar_last` anti-starvation, port0 first) with no grant-interval cooldown — confirmed by the Phase 4 RTL review and characterization measurement);
- arbitration can happen once every two cycles (`ARB_GRANT_INTERVAL=2`, g_sync);
- grant conditions:
  1. that interface has an active request;
  2. the command queue is not full;
- when it is the turn of an interface that has no request, that interface is skipped and the other one is checked;
- when the other interface is idle and the queue is not full, it can be served every cycle (`ARB_QUIET_FAST_PATH=1`);
- read and write requests enter the command queue according to the request type.

### 8.2 Parameters

| Parameter | Default | Description |
|---|---:|---|
| `ARB_GRANT_INTERVAL` | 2 | Arbitration period |
| `ARB_QUIET_FAST_PATH` | 1 | Single-interface fast path |
| `ARB_QOS_WEIGHT_EN` | 0 | Whether QoS weighting is used (not defined in the manual) |

### 8.3 Assertions

- Two interfaces must not be granted in the same cycle;
- no grant when the command queue is full;
- round-robin rotation fairness check (optional);
- the arbiter must not grant during an `ARSTN` reset.

---

## 9. Queue and Backpressure Model

### 9.1 Queue Abstraction

| Queue | Depth parameter | Backpressure signal |
|---|---|---|
| Command Queue | `CMD_QUEUE_DEPTH` | `AWREADY_x`/`ARREADY_x` |
| Write Data Queue | `WRITE_DATA_QUEUE_DEPTH` | `WREADY_x` |
| Read Data Queue | `READ_DATA_QUEUE_DEPTH` | internal backpressure of `RVALID_x` |

### 9.2 Backpressure Rules

- Command queue full: `AWREADY_x`/`ARREADY_x` are deasserted;
- Write data queue full: `WREADY_x` is deasserted;
- Read data queue full: the internal read command dequeue is paused and `ARREADY_x` may be deasserted;
- outstanding at the limit: the corresponding `AWREADY_x`/`ARREADY_x` are deasserted;
- `AWREADY_x` must additionally satisfy `AWVALID_x && WVALID_x` (7.2); `WREADY_x` does not depend on AW (7.3);
- after a queue slot is released, the recovery follows the latency parameters.

### 9.3 Differences from the Real Hard IP

The model does not simulate the real command scheduling, bank conflicts and refreshes. Queue occupancy is only used to generate backpressure and latency trends, it is not a cycle-accurate performance basis `[MODEL]`.

---

## 10. Latency Model

### 10.1 Latency Composition

```text
Read transaction:
  AR handshake
    + SYNC_LATENCY
    + ARB_LATENCY
    + READ_LATENCY (parameterized)
    + per-beat transfer interval (R_BEAT_INTERVAL)
    -> R beats

Non-early-return write transaction (`AWCACHE[0]=0`, calibrated form):
  AW handshake + W beats
    + WRITE_RESP_LATENCY (queueing jitter, ENG value)
    + WRITE_DATA_TO_B_LATENCY = 451 (after WLAST, Phase 2 calibration)
    -> BVALID

Early-return write transaction (`AWCACHE[0]=1`, Phase 5 calibration):
  AW handshake
    + BVALID_CMD_QUEUE_DELAY = 28 (after command acceptance)
    -> BVALID (may precede WLAST; the board-level equivalent is AW handshake +4-5 ACLK)
```

### 10.2 Latency Modes

| Mode | Description |
|---|---|
| `FIXED` | Fixed value; uses MIN |
| `UNIFORM` | Uniform random in `[MIN, MAX]`; uses `LATENCY_SEED` to guarantee reproducibility |

> The `LATENCY_RANGE` of v0.1 duplicates the `UNIFORM` semantics; v0.2 merges them into `FIXED`/`UNIFORM`.

### 10.3 Reference Points and Units

- The unit of the model-internal latency is a `ctrl_clk` cycle.
- On the test side the APM measures in the `ACLK` domain; when back-filling, convert with `CLK_RATIO_ACLK_PER_CTRL`.
- The definitions of `T_AR_FIRST_R`, `T_AW_B`, `T_WLAST_B` are in 6.4 and must be consistent with the test spec.
- The measured back-filled values of `READ_LATENCY_MAX` / `WRITE_RESP_LATENCY_MAX` should use P99 (with a histogram) or P95 (without a histogram), not the absolute max; the absolute max is recorded as an outlier.

### 10.4 No Latency Commitment

The model latency is only used for functional verification and trend simulation, not for performance sign-off `[MODEL]`.

---

## 11. Outstanding and ID Management

### 11.1 Outstanding Counting

- Read outstanding: from the AR handshake to the `RLAST` handshake of that transaction;
- Write outstanding: from the AW handshake to the `BVALID` handshake of that transaction;
- when the limit is reached, the corresponding address channel is backpressured;
- the counters are parameterized with `READ_OSTD_DEPTH`/`WRITE_OSTD_DEPTH`;
- in early-return mode the write outstanding count is decremented at the B handshake, which may precede WLAST; this is AXI semantics and does not mean the data phase has completed `[UG][MODEL]`.

### 11.2 ID Management

- The ID width is 6 bits, at most 64 IDs;
- transactions with the same ID respond in order `[AXI4]`;
- `OUT_OF_ORDER_ENABLE=0`: all transactions respond in the global acceptance order `[MODEL]`;
- `OUT_OF_ORDER_ENABLE=1`: different IDs may run in parallel/out-of-order, the same ID keeps its order; read beats are not interleaved by default `[MODEL]`;
- the model maintains an outstanding count and an ordering queue per ID;
- early-return write responses also obey the same-ID ordering.

### 11.3 Response Order Assertions

- the read response order of the same ID matches the AR order;
- the write response order of the same ID matches the AW order;
- with `OUT_OF_ORDER_ENABLE=0` different IDs are also ordered;
- with `OUT_OF_ORDER_ENABLE=1` different IDs may be out-of-order, but the same-ID order must not be violated.

---

## 12. Configuration Controller Model

### 12.1 State Machine

```text
IDLE
  │ CFG_RESET=0, CFG_SEL=0
  ▼
WAIT_START
  │ CFG_START=1
  ▼
INIT_SEQUENCE
  │ count INIT_CYCLES
  ▼
DONE
  │ CFG_DONE=1, held until CFG_RESET=1
  └─► IDLE (CFG_RESET asserted)
```

### 12.2 Behavior

- `CFG_RESET=1`: resets the internal state, `CFG_DONE=0`;
- `CFG_RESET` must be held for at least 5 `ctrl_clk` cycles (assertion check) `[UG]`;
- `CFG_SEL=0` enables, `CFG_SEL=1` disables and `CFG_DONE` stays low `[UG]`;
- the initialization sequence starts after `CFG_START=1`;
- `CFG_DONE=1` after the parameterized `INIT_CYCLES`;
- `CFG_START` must stay high after `CFG_DONE=1` (assertion check) `[UG]`;
- during initialization the AXI interface behavior is controlled by `INIT_AXI_BLOCK`/`INIT_AXI_RESP`:
  - `BACKPRESSURE`: `AWREADY/ARREADY/WREADY` are deasserted;
  - `SLVERR`: transactions are accepted and an error response is returned;
- `CFG_DONE` stays high until `CFG_RESET=1` `[MODEL]`.

### 12.3 Parameters

See 6.7.

---

## 13. Reset Model

| Reset | Effect |
|---|---|
| `ARSTN_x=0` | Resets the AXI x interface state machine and the channel outputs; does not affect the stored content; unfinished transactions are discarded `[AXI4][MODEL]` |
| `CFG_RESET=1` | Resets the configuration controller, the controller queues, the arbiter and the latency model; optionally clears the storage (`CFG_RESET_CLEAR_MEM`) `[UG][MODEL]` |

Rules:

- During reset all outputs are `VALID=0` `[AXI4]`;
- after `CFG_RESET` is asserted, `CFG_DONE=0` `[UG]`;
- it is recommended that all resets are asserted together after the power supply is stable (a manual recommendation, not enforced by the model) `[UG]`;
- `CFG_RESET` must be held for at least 5 `ctrl_clk` cycles `[UG]`;
- `ARSTN_x` is active-low; do not connect it inverted according to the `ARST_X active-high` of Table 14 (erratum E1);
- `ARSTN_x` and `CFG_RESET` may be used independently, but system integration recommends resetting them together `[UG]`.

---

## 14. Storage Array Model

### 14.1 Structure

- a linear byte array whose size = `MEM_BYTES` (6.2);
- supports zero initialization, random fill or a fixed pattern (`MEM_INIT_MODE`/`MEM_INIT_SEED`);
- the stored content is preserved during `ARSTN_x`; whether `CFG_RESET` clears it is controlled by `CFG_RESET_CLEAR_MEM`.

### 14.2 Access Rules

- Write: the byte lanes are updated according to `WSTRB`;
- Read: the valid lanes are returned according to `ARSIZE` and the address, invalid lanes follow `NARROW_READ_INVALID_LANE`;
- out-of-range/holes follow `ERR_ADDR_RANGE`/`ERR_ADDR_HOLE`;
- DRAM refresh/bank timing is not supported; the stored content is preserved between resets;
- non-power-of-two densities use a linear array of `MEM_BYTES`, the functional model does not simulate address holes. If field decode is enabled and a hole table is explicitly configured, `ADDR_HOLE_POLICY` applies.

### 14.3 Optional Backdoor

- a backdoor read/write interface is provided for the testbench to preload/inspect the stored content;
- the backdoor interface does not take part in the AXI protocol;
- backdoor access is not affected by `ARSTN_x`, but it is affected by `CFG_RESET_CLEAR_MEM` (if enabled).

---

## 15. Controller Status Signals

| Signal | Condition |
|---|---|
| `CTRL_INIT_DONE` | `CFG_DONE=1` and the internal initialization is complete |
| `CTRL_READY` | Able to accept AXI transactions (queues not full, not in reset, initialization complete) |
| `CTRL_BUSY` | The command queue is not empty or the arbiter is busy |
| `CTRL_ERR` | An illegal access or protocol error has occurred (sticky, until `CFG_RESET`) |

The status signals are `[MODEL]`, disabled by default and controlled by `ENABLE_CTRL_STATUS`.

---

## 16. Assertions and Checks

### 16.1 AXI Protocol Assertions

- `*VALID` is held until `*READY` after being asserted;
- `WLAST` matches `AWLEN`;
- `RLAST` matches `ARLEN`;
- the response order of the same ID;
- `VALID=0` during reset;
- `WSTRB` corresponds to the `WDATA` lanes;
- `BVALID` must not occur before the AW handshake;
- `RVALID` must not occur before the AR handshake.

### 16.2 Manual Rule Assertions

- `AWREADY` must not be asserted before `AWVALID && WVALID` `[UG]`;
- a burst does not cross 4KB `[UG]`;
- `AWLEN/ARLEN` does not exceed the Table 5 upper limit `[UG]`;
- `AWSIZE/ARSIZE ≤ 6` `[UG]`;
- when `AWALLSTRB=1` the beat count ≤ 16 and WSTRB is all 1 `[UG]`;
- the WRAP length and alignment are legal `[AXI4]`;
- a FIXED burst returns an error when `SUPPORT_FIXED_BURST=0` `[MODEL]`;
- `CFG_RESET` is held for at least 5 `ctrl_clk` cycles `[UG]`;
- `CFG_START` stays high after `CFG_DONE` `[UG]`;
- `CFG_SEL=0` enables `[UG]`.

### 16.3 Arbitration Assertions

- two interfaces are not granted in the same cycle;
- no grant when the queue is full;
- round-robin fairness (optional).

### 16.4 Queue Assertions

- the outstanding count does not exceed the limit;
- the queue depth does not overflow;
- the backpressure signals are consistent with the queue state;
- `WREADY` does not depend on AW (W may precede AW);
- in early-return mode, when B precedes WLAST the W data is still received.

---

## 17. Verification Plan

### 17.1 Manual Example Regression

| Test case | Reference | Check point |
|---|---|---|
| Read operation | Figure 3 | `ARLEN=3, ARSIZE=6`, INCR, 4 R beats, `RLAST` correct |
| Write operation | Figure 4 | 4 W beats, `WLAST`, `BVALID`; `AWREADY` after `AWVALID && WVALID` |
| Address mapping | Table 4 | AXI beat to DQ mapping |
| Maximum burst | Table 5 | the length limits for SIZE=6/5/4 |
| 8-bit on 32-bit | Figure 5 | WSTRB one-hot rotation (per the AXI lane rules) |
| 32-bit on 64-bit | Figure 6 | WSTRB combinations |
| CFG waveform | Figure 7 | the `CFG_RESET/START/SEL/DONE` timing |

### 17.2 Functional Test Cases

- single-beat/multi-beat reads and writes;
- INCR/WRAP;
- FIXED burst rejection;
- narrow transfer;
- the 4KB boundary;
- burst length/size exceeding the limits;
- address out of range, address hole;
- `WSTRB` all 0/part/all 1;
- `AWALLSTRB` with 16/17 beats, WSTRB all 1/not all 1;
- the BVALID timing for `AWCOBUF=0/1` and `AWCACHE=1111/0000/other`;
- the W data is still received when B precedes WLAST;
- the W data precedes AW;
- `AWREADY` stays low when only `AWVALID` is present without `WVALID`;
- the ordering of the same ID;
- parallelism of different IDs (`OUT_OF_ORDER_ENABLE=1`);
- arbitration of simultaneous reads and writes on the dual ports;
- backpressure on a full queue;
- backpressure when the outstanding limit is reached;
- `CFG_RESET` reset;
- `ARSTN_x` reset alone;
- AXI blocking/error during initialization;
- error injection.

### 17.3 Address/Capacity Test Cases

- `MEM_BYTES` for 2G/4G/16G × x16/x32 × 1/2 rank;
- 16G × x32 × 2 rank: the CS stride is equivalent to bit32;
- low density: the CS bit position is derived from `RANK_STRIDE_BYTES`;
- 3G/6G/12G non-power-of-two densities: linear addressing, no bit-field decode;
- address equal to `MEM_BYTES-1` / `MEM_BYTES` / non-zero high bits;
- rejection of an illegal configuration in `CS_BIT` mode (stride not a power of two);
- in `SINGLE_RANK` mode the rank is always 0.

### 17.4 Performance Trend Test Cases

- continuous reads on a single port, observing the throughput and the latency distribution;
- mixed reads/writes on the dual ports, observing the round-robin fairness;
- the throughput change under different `CMD_QUEUE_DEPTH`/`OSTD`;
- a comparison of the latency mode switches;
- the latency/throughput difference between early-return mode and the baseline mode.

### 17.5 Coverage Points

- all AXI channel handshake combinations;
- all burst types/lengths/sizes;
- all response types;
- all reset combinations;
- the full/empty/intermediate queue states;
- the arbitration rotation states;
- early-return/non-early-return BVALID;
- the address mapping modes.

---

## 18. Obtaining the Parameters by Measurement

| Parameter | Measurement method | Priority |
|---|---|---|
| `CMD_QUEUE_DEPTH` | the first-backpressure critical point of the fixed-rate sweep in test spec 8.4; the result is recorded as `CMD_QUEUE_DEPTH_ENG`. Phase 3 measurement: the board-level TG connects directly to the real hard IP with no backpressure within 16 transactions, so the **lower bound ≥16** is recorded (low confidence); the model shell `CMD_REQ_DEPTH=4` keeps the ENG value and is not back-filled | Low |
| `READ_OSTD_DEPTH` | the saturation point of test spec 8.1; the result is recorded as `READ_OSTD_DEPTH_ENG` | High |
| `WRITE_OSTD_DEPTH` | test spec 8.1; force `AWCACHE=1111, AWCOBUF=0` | High |
| `READ_LATENCY_MIN/MAX` | test spec 8.2; MAX takes P99 | High |
| `WRITE_RESP_LATENCY_MIN/MAX` | test spec 8.2; baseline configuration; MAX takes P99 | Medium |
| `WRITE_DATA_TO_B_LATENCY` | the WLAST→B of test spec 8.2 | Medium |
| `SYNC_LATENCY` | fitted/apportioned from experiments with several `ACLK:ctrl_clk` ratios; it cannot be measured independently | Medium |
| `ARB_GRANT_INTERVAL` | the minimum grant interval of the dual-port ILA of test spec 8.4. **Phase 4 conclusion: no parameter back-fill** — the parameter is effective only on the g_sync (CDC_ENABLE=0) path, and the board-level CDC topology does not pass through this arbiter (the G=2/G=8 characterizations are bit-identical); the default 2 is kept and marked g_sync-only. The board/simulation degradation ratio is a documented deviation: the saturated model 1.17~1.34x vs the board-level 1.00x (the model is conservative), the first round model 1.03x vs the board-level 1.72x (the model is optimistic, transient) (plan §9 Phase 4) | Medium |
| `OUT_OF_ORDER_ENABLE` | the multi-ID completion order of test spec 8.7. Phase 6 measurement: the real hard IP completed 16 fully concurrent reads in order (the board-level oo_cnt=0 has the same shape as the model OOO=0 setting) → 0 is kept; the applicable domain is 16 single-port reads in flight spread over 1MB (the write direction/dual-port were not measured) | Medium |
| `BVALID` timing | the `AWCACHE/AWCOBUF` combinations of test spec 8.5 | Medium |
| rank/CS mapping | test spec 8.8. Phase 7 measurement: the board-level single rank 2Gb=256MB (peri.xml), the last page 256M-4K is accessible and accesses from 256M on are out of range with **silent wrap-around** (modulo 256MB, [27:0] truncation semantics; except for the isolated 1G=0x4000_0000 point which returns SLVERR) → the capacity configuration is confirmed; no parameter is available for the out-of-range back-fill (`ADDR_HOLE_POLICY=ALIAS` has only the FIELD_DECODE_DEBUG hole-window semantics and is banned as a default) → `ADDR_HOLE_POLICY=DECERR` is kept and the out-of-range difference is recorded as a documented deviation (the model reports an out-of-range error = the safe direction, the real hard IP silently aliases = the false-negative direction; the legal region <256MB is not affected) | Medium |

After the measurement, the defaults of 6.3/6.4 are replaced and the model parameter table version is upgraded. The report keeps the original `_ENG` estimates and the confidence.

**Phase 8 summary (2026-10-23, correlation closure)**: the whole calibration flow of Phases 0-8 has been executed. v0.2a has back-filled `READ_LATENCY_MIN/MAX`, `WRITE_DATA_TO_B_LATENCY` and `BVALID_CMD_QUEUE_DELAY` (and fixed the core_scheduler 0000 non-early-return semantics); the remaining parameters keep the ENG form/defaults after the board-level measurement or are recorded as inert/deviations (item by item see the notes in the table above and plan §9). The regression gate (plan §7-5): the traceability baseline is **60/60 all green** (tb_top 48 + tb_top_cdc 9 + tb_unit 3, the run method is fixed in `tb/regress.sh` + `testlist.txt`, including the per-test-case -g parameter mapping); `random_stress` passes with 50 seeds (-sv_seed 2..51). No new RTL parameter replacement (spec §22 v0.2e).

---

## 19. Deliverables

1. Model RTL/SystemVerilog or C++ TLM source code;
2. Parameter configuration file;
3. Testbench and regression test cases;
4. Assertion/coverage report;
5. User manual (parameter description, interface connection, restrictions);
6. Guide for replacing the parameters with the measured values;
7. List of manual assumptions/errata (Chapter 3 of this document).

---

## 20. Appendix: Summary of the Default Parameters

```text
DATA_WIDTH              = 32
AXI_DATA_WIDTH          = 512
AXI_ADDR_WIDTH          = 33
AXI_ID_WIDTH            = 6
MEM_DENSITY_GBIT        = 4
MEM_DENSITY_UNIT        = GBIT_PER_CHANNEL
GBIT_DEFINITION         = BINARY_2^30
NUM_CHANNELS            = 2            // DATA_WIDTH/16
PHYSICAL_RANK           = 1
MEMORY_TYPE             = LPDDR4
NUM_AXI_TARGETS         = 2
SUPPORT_WRAP_BURST      = 1
SUPPORT_NARROW          = 1
SUPPORT_FIXED_BURST     = 0
SUPPORT_AWALLSTRB       = 1
SUPPORT_EXCLUSIVE       = 0
ADDR_MAP_MODE           = LINEAR
RANK_MAP_MODE           = CS_STRIDE
CS_BIT_POS              = derived
ADDR_HOLE_POLICY        = DECERR
MEM_INIT_MODE           = ZERO
MEM_INIT_SEED           = 1

CMD_QUEUE_DEPTH         = 8        // pending measurement
WRITE_DATA_QUEUE_DEPTH  = 16       // pending measurement
READ_DATA_QUEUE_DEPTH   = 16       // pending measurement
READ_OSTD_DEPTH         = 8        // pending measurement
WRITE_OSTD_DEPTH        = 8        // pending measurement
OUT_OF_ORDER_ENABLE     = 0        // pending measurement
R_INTERLEAVE_ENABLE     = 0
ARB_GRANT_INTERVAL      = 2
ARB_QUIET_FAST_PATH     = 1
ARB_QOS_WEIGHT_EN       = 0

CLK_RATIO_ACLK_PER_CTRL = 0.25     // x32 ideal value; overridden by measurement
SYNC_LATENCY            = 2        // pending fit
READ_LATENCY_MIN        = 191      // Phase 2 board-level calibration (board 24/61 ACLK x8, observed offset deducted)
READ_LATENCY_MAX        = 492      // Phase 2 board-level calibration
R_BEAT_INTERVAL         = 1
WRITE_RESP_LATENCY_MIN  = 8        // ENG value (jitter component of the data commit path)
WRITE_RESP_LATENCY_MAX  = 24       // ENG value
WRITE_DATA_TO_B_LATENCY = 451      // Phase 2 board-level calibration (board WL 55-99 ACLK x8)
BVALID_CMD_QUEUE_DELAY  = 28       // Phase 5 board-level calibration (board T_AW_B 4-5 ACLK x8)
BVALID_PHY_ISSUE_DELAY  = 2        // ENG value; used only by the PHY_ISSUE fallback policy
W_ACCEPT_INTERVAL       = 1
LATENCY_MODE            = UNIFORM
LATENCY_SEED            = 1
LATENCY_UNIT            = CTRL_CLK

BVALID_TIMING_MODE      = MANUAL_STRICT
OTHER_AWCACHE_POLICY    = DATA_DONE
AWCOBUF_STRICT          = 1

ERR_CROSS_4KB           = SLVERR
ERR_BURST_LEN           = SLVERR
ERR_BURST_SIZE          = SLVERR
ERR_FIXED_BURST         = SLVERR
ERR_ADDR_RANGE          = DECERR
ERR_ADDR_HOLE           = DECERR
ERR_WSTRB_INVALID       = IGNORE
ERR_ALLSTRB_BEATS       = SLVERR
ERR_ALLSTRB_WSTRB       = SLVERR
ERR_INJECT_RATE         = 0
NARROW_READ_INVALID_LANE = ZERO

INIT_CYCLES             = 1000
INIT_AXI_BLOCK          = 1
INIT_AXI_RESP           = BACKPRESSURE
CFG_RESET_CLEAR_MEM     = 0
ENABLE_CTRL_STATUS      = 0
```

---

## 21. Assumptions and Items to Confirm

| Item | Marker | Description |
|---|---|---|
| the influence of the other `AWCACHE` encodings on BVALID | confirmed at board level (Phase 5, 2026-10-23) | `AWCACHE[0]` alone decides: bit0=1 early return (0001/0011/0111 measured with the same shape), bit0=0 after the data commit (0000/0010/0100/1110 measured with the same shape); see correlation-plan §9 |
| the exact timing of B preceding WLAST when `AWCOBUF=1` | confirmed at board level (Phase 5, 2026-10-23) | the early-return timing is decided by `AWCACHE[0]`, COBUF has no independent effect; the early-return delay is calibrated with `BVALID_CMD_QUEUE_DELAY`=28 ctrl (board T_AW_B 4-5 ACLK ×8 = 32-40 ctrl) |
| FIXED burst response | `[CONFIRM]` | SLVERR by default in the model |
| WRAP length/alignment | `[CONFIRM]` | per AXI4 |
| `SIZE≤3, LEN=256` | `[CONFIRM]` | per AXI4; requires measurement |
| address mapping/holes for non-power-of-two densities | `[CONFIRM]` | the model uses linear addressing |
| the observability of `SYNC_LATENCY` | `[MODEL]` | it cannot be measured independently from the AXI boundary, it can only be fitted |
| the real OSTD/queue depth | `[CONFIRM]` | only an engineering estimate, `_ENG` is kept |
| the exact semantics of `AWALLSTRB` | `[CONFIRM]` | the manual only states the all-strobe and the 16-beat limit; "WSTRB all 1" is a model interpretation |
| interleaving of read data of different IDs | `[MODEL]` | not interleaved by default; requires measurement |

---

## 22. Revision History

| Version | Date | Description |
|---|---|---|
| v0.1 | 2026-10-21 | Initial draft |
| v0.2 | 2026-10-21 | Revised based on the kimi3/Doubao feedback and a manual re-check: fixed the `AWREADY` dependency on `WVALID`, the read address signals, `AWALLSTRB` 16 beats, the address capacity/rank, the BVALID semantics and the latency definitions; added the errata table, the monitor-only test premise, the default global ordering, the early-return W data rules, etc. |
| v0.2a | 2026-10-23 | correlation Phase 2/5 board-level calibration back-fill: READ_LATENCY 191/492, WRITE_DATA_TO_B_LATENCY 451, BVALID_CMD_QUEUE_DELAY 28; the B timing changed to the `AWCACHE[0]` bit0 pattern (§6.4/§6.5/§7.4/§10.1), the 0000 non-early-return case was finalized, `BVALID_TIMING_MODE` is marked as unused, and the two `[CONFIRM]` items of §21 were closed |
| v0.2b | 2026-10-23 | correlation Phase 3 queue depth calibration: the board-level TG connects directly to the real hard IP with no shell gating layer and shows zero backpressure within 16 transactions → the real hard IP lower bound of `CMD_QUEUE_DEPTH` is ≥16 (§6.3/§18 note), `CMD_QUEUE_DEPTH_ENG` cannot be measured precisely at board level and the shell `CMD_REQ_DEPTH=4` keeps the ENG value; no RTL parameter replacement |
| v0.2c | 2026-10-23 | correlation Phase 6/7 calibration: the OOO probe showed the real hard IP completing in order → `OUT_OF_ORDER_ENABLE=0` is kept (§18); the address/rank probe confirmed the board-level single-rank 256MB capacity and the silent out-of-range wrap-around (except for the isolated 1G point) → `RANK_MAP_MODE`/`CS_BIT_POS`/`ADDR_HOLE_POLICY` are all kept and the out-of-range difference is recorded as a documented deviation (§6.1/§18/plan §9 Phase 6/7); no RTL parameter replacement |
| v0.2d | 2026-10-23 | correlation Phase 4 dual-port arbitration calibration: `ARB_GRANT_INTERVAL` is effective only on the g_sync path (the CDC topology uses 1:1 alternating collection, and the G=2/G=8 characterizations are bit-identical) → no parameter back-fill, the default 2 is kept and the applicable domain is marked (§6.3/§8.1/§18); the board/simulation degradation ratio is a documented deviation (saturated model 1.19x vs board 1.00x conservative, first round model 1.03x vs board 1.72x optimistic transient) (plan §9 Phase 4) |
| v0.2e | 2026-10-23 | correlation Phase 8 regression gate closure: the traceability baseline regression is **60/60 all green** (tb_top 48 + tb_top_cdc 9 + tb_unit 3; the run method is fixed in `tb/regress.sh` + `testlist.txt`, including the per-test-case -g mapping and the parameter semantics errata such as INIT_AXI_RESP/ADDR_HOLE_POLICY, plan §9 Phase 8); `random_stress` passes with 50 seeds (-sv_seed 2..51); the expectations of the three tb_top test cases were updated following the v0.2a "0000 non-early-return" semantics (early_b/wlast_err/allstrb_early, on the TB side); no RTL parameter replacement |

---

**Document status**: review revision draft, may enter functional model implementation; the `[CONFIRM]` items require measurement/vendor confirmation.  
**Next actions**: build the regression per Chapter 17; calibrate the parameters of 6.3/6.4 per test spec v0.2; update the measured values when releasing v0.3.
