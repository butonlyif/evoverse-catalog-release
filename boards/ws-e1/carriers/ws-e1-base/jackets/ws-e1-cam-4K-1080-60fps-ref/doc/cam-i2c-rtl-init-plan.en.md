[中文](cam-i2c-rtl-init-plan.md) | English

# IMX415 Power-On Self-Configuration in RTL (fabric I2C init) Implementation Plan

| Item | Value |
|---|---|
| Version | **v0.5 (P4 board-level troubleshooting complete, both channels outputting images)** |
| Date | 2026-10-24 |
| Goal | After bit download, without loading a firmware ELF, fabric RTL automatically completes sensor power-up sequencing + I2C configuration + stream-on and outputs images directly; **the data path stays silent until configuration completes** |
| Related | sw/top_demo/src/imx415_init.c (deleted as of v4.11; historical master in git; the ROM same-source register table has moved to embedded anchors in tools/gen_imx415_rom.py), [rtl/i2c_master.sv](../rtl/i2c_master.sv) (in-house, passed P1 simulation, not yet board-tested), [rtl/cam_i2c_init.sv](../rtl/cam_i2c_init.sv) (the initializer), [top_cam.sv](../rtl/top_cam.sv) (gate_ready/raw_aresetn hook points), [program.md](program.md), [readme_4K_1K.md](readme_4K_1K.md) §2.2 |
| Reviewer | User (2026-10-24 finalized Q1/Q3/Q4/Q6, see §8) |

---

## 1. Background and Goals

Current chain: after the bit is programmed, the SoC has no program (**the soft-core program is not embedded in the bitstream**, program.md §0); openocd must load the ELF, and firmware `imx415_init(0/1)` configures the sensors via the SoC I2C controller before images appear. This plan moves that configuration process into fabric:

- **P0 goal**: after JTAG programming the bit → both IMX415 channels auto-configure at power-up → panel outputs images, firmware-free throughout.
- **P1 goal**: firmware and I2C **fully decoupled** — delete all I2C configuration duties from firmware; the firmware binary becomes an optional debug tool (UART heartbeat + DIAG readouts only, see §4.6).
- **P2 goal**: **data path not working until configuration completes** (init_done gating, §4.5).

## 2. Current-State Inventory (factual basis for feasibility)

### 2.1 Firmware configuration flow (the minimal set the RTL must replicate)

Measured flow of `imx415_init_once()`:

| Step | Content | RTL decision |
|---|---|---|
| L0 power sequencing | cam_en low 300ms (hard reset/discharge) → high → I2C accessible only after 12ms | **must replicate** |
| L0 bus recovery | i2c_masterRecover (9 SCL pulses) + line-level check | V1 replaces it with cam_en power removal (sensor power-off necessarily releases the bus; board experience: wedged bus is cleared by power cycle) |
| L1a ID probe | CHIP_ID 0x3F12 read + bus scan (this sensor batch has SENSOR_INFO unprogrammed, always falls back) | **omit** (pure diagnostics) |
| L1b base table write | 109 entries (standby/format/SONY magic/legacy geometry/clock parameters), **order-sensitive** (the magic block must be written while VMAX/HMAX/clock are still at reset defaults) | **must replicate entry by entry** |
| Geometry block | cam0 geo4k 11 entries / cam1 geo1080 11 entries (the only per-channel difference: 0x3020/21/22 binning, 0x30D9/DA DIG_CLP, 5 entries with different values) | **must replicate**, table selected per channel |
| LANEMODE | 0x4001=0x03 + 0x4002=0x00 | **must replicate** |
| DPHY timing | 9 16-bit LE entries (0x4018..0x4028; TCLKZERO high byte 0x401F=0x01 must be written) | **must replicate** |
| L1c read-back verification | 9 key registers read back + one rewrite-reread | **not done** (review final decision Q3) |
| L1d stream-on | 0x3002=0 (written while in standby) → 0x3000=0 (release) → 220ms settle | **must replicate**; the 220ms settle is diagnostic only, non-blocking |
| Outer retry | 3 full rounds, 500ms discharge + 300ms power-off between rounds | **must replicate** |

Table size: 109 + 11 + 2 + 18 + 2 = **142 write transactions per camera**. (P2 execution erratum: the imx415_init.c base table measured 109 entries — format/magic 78 + legacy geo 19 + clock 12; the file-header "107-entry" comment is stale; the generator asserts on 109.)
Each write = START + {0x34, regH, regL, val} 4 bytes + STOP, byte-wise ACK checking,
per-entry NACK retry ≤10 times (10ms interval).

### 2.2 Pins and controller current state (the key feasibility windfall)

[top_cam_demo.sv](../rtl/top_cam_demo.sv) L431-508:

- `cam_x_scl/sda` are **peri-layer open-drain emulated GPIOs** (`syn_peri_port=0` top-level
  i/o/oe three-wire ports), **not SoC I2C hard-core dedicated balls**. The SoC I2C controller
  drives oe through a single line `w_i2c_x_*_write` (`cam_*_oe = ~write`, drive-low/release
  semantics). → **RTL takeover = only change the top-level assignment source; peri.xml / interface designer
  completely untouched, board wiring unchanged.**
- `cam_x_en` = SoC GPIO0 `w_gpio_write[0/1]`, register reset 0 (sensor default unpowered).
  RTL takeover requires changing the drive source (see §4.4).
- [ws-e1-cam-ddr-csi2.sdc](../ws-e1-cam-ddr-csi2.sdc) L42-66 already has input/output delay
  constraints to `sys_clk_200m` for the six cam_* port groups — after switching the drive source
  the constraints still apply; the SDC needs no change.
- The wrapper hangs off **sys_clk_200m** (same clock and same reset tree `sys_clk_200m_rstn` as the SoC);
  the whole design is single-domain, **no CDC**.
- SCL rate stays at **50kHz** (board-level flying-wire bus measured conclusion 100k→50k→25k→10k→50k;
  do not change the i2c_master default 400k).

### 2.3 i2c_master.sv assessment

**Conclusion: usable as the byte-layer engine; it is an in-house module, simulation-verified but never board-tested — P1 functional verification is a mandatory prerequisite gate; no integration until it passes. Modifying it is allowed.** (Review final decision Q6)

Protocol correctness (code review + verible-syntax measured 2026-10-24 passed, exit 0, no syntax errors):

| Check item | Result |
|---|---|
| Open-drain convention | `pad_o=1` release / `0` drive low — **exactly isomorphic** to the existing pad's `oe=~write` semantics (`oe = ~pad_o` completes the mapping) |
| START/STOP timing | SDA changes only while SCL is high, double-hold before STOP, phantom-STOP prevention (ST_HOLD bridging) — header comments align item by item with the I2C spec |
| Repeated START | ST_START_PRE gives the slave filter setup time (the read-op primitive already exists; V1 has no read use case, coverage retained) |
| Clock stretching | SCL_H waits for `scl_pad_i` to actually go high + SCL watchdog (timeout sets err, aborts back to IDLE) |
| Command set | START/TX (with NACK sampling)/RX (with ACK·NACK send)/STOP/RESET — covers all primitives of 16-bit register write and read |
| Inter-command protocol | each command starts on a `go` pulse, ends on a single-beat `done`; between bytes the FSM parks in ST_HOLD (SCL held low, busy=0); the wrapper only waits for done before issuing the next command |
| err semantics | **sticky**, cleared only by CMD_RESET or a successful STOP — the wrapper error path must issue CMD_RESET first |

Gaps and accompanying actions:

| # | Gap | Action |
|---|---|---|
| G1 | No bus-recover (9 SCL pulses) primitive | Not done in V1 (cam_en power removal releases the bus instead); modification already permitted, CMD_RECOVER (~40 lines) as optional P2 hardening |
| G2 | No TB of it in the repo (the testbench mentioned in the header comment is not in the library) | **P1 adds `sim/tb_i2c_master.sv` (mandatory prerequisite, see §6)** |
| G3 | Default parameters 100MHz/400kHz do not apply | Instantiate with `SYS_FREQ=200_000_000, I2C_FREQ=50_000`; re-check the watchdog SCL_TIMEOUT_CYCLES (at 200M, 20000 beats = 100µs = 10 half-periods, sufficient for 50kHz) |
| G4 | Not yet through vlog/efx_map (only verible) | Mixing SV enum + always_ff/always_comb has precedent in the project (*.sv files); P1 gates on vlog 0 Error |
| G5 | Not in the XML compile list | P3 registers it in `ws-e1-cam-ddr-csi2.xml` design_info (historical pitfall: milestone-v4.11 §5-#11) |

## 3. Overall Architecture

```
sys_clk_200m / sys_clk_200m_rstn
┌──────────────────────────── top_cam_demo ────────────────────────────┐
│  u_cam_0 (top_cam, 4K60)                    u_cam_1 (top_cam, 1080)   │
│  ┌─────────────────────────────────┐       ┌───────────────────────┐ │
│  │ u_i2c_init_0 (cam_i2c_init)     │       │ u_i2c_init_1          │ │
│  │  power FSM + walk FSM + ROM     │       │  start = u_i2c_init_0 │ │
│  │  done_ok ──→ this channel's data│       │  .done_ok (staggered)  │ │
│  │              path released      │       └──┬──────────┬─────────┘ │
│  └──┬──────────────┬───────────────┘          │          │           │
│     │ cam_en       │ scl/sda(i/o/oe)          │          │           │
│     ▼              ▼  [i2c_master ×1]        ▼          ▼           │
│  gate_ready   pad direct drive (open-drain map)   isomorphic (starts ~0.7s later)      │
│  &init_done   SoC I2C write line removed                             │
└─────┬──────────────┬─────────────────────────────────────────────────┘
      ▼              ▼
   cam_0_en    cam_0_scl/sda → IMX415#0        cam_1_* → IMX415#1
```

**Instantiation location: `cam_i2c_init` goes inside top_cam** (one per camera, same level as
apb_cam_ctrl) — sensor I2C/power-up/release is a single-camera cohesive duty; top_cam gains pad ports,
and top_cam_demo only forwards ports and removes the SoC write lines.

Module list:

| File | New/Mod | Duty |
|---|---|---|
| rtl/i2c_master.sv | existing (optional minor change G1) | byte-layer engine |
| rtl/imx415_rom.sv | **new (generated)** | register table ROM (`MODE_4K` parameter = 4K/1080; case ROM, 24b×142 entries + `last_idx` table-end output against dual-source drift) |
| rtl/cam_i2c_init.sv | **new** | power-up sequencing FSM + table-walk FSM + NACK/full-round retry + init_done/status outputs |
| rtl/top_cam.sv | **mod** | instantiate u_i2c_init + pad/en ports + **gate_ready & init_done + raw_aresetn & init_done** (§4.5) + DIAG3 routing |
| rtl/top_cam_demo.sv | **mod** | forward pad ports to both top_cam channels; remove SoC I2C write lines and w_gpio_write |
| ws-e1-cam-ddr-csi2.xml | **mod** | design_info registers the 2 new files |
| sw/top_demo/src/main.c | **mod** | delete all I2C configuration duties (imx415_init/stream_on/off, I2C menu keys); keep the UART heartbeat (reads the DIAG group, including init status) — optional debug firmware |
| sim/tb_i2c_master.sv | **new** | byte-engine unit TB (P1 mandatory prerequisite) |
| sim/tb_cam_i2c_init.sv | **new** | golden sequence comparison + fault injection + staggered-start/release coordination TB |
| tools/gen_imx415_rom.py | **new** | generate the ROM and golden sequence files from the imx415_init.c tables (same source, against transcription errors) |

Resource estimate: i2c_master ~300 LUT + wrapper ~400 LUT + ROM (140×24b case) ×2 cameras
≈ **total < 2k LUT**, no pressure on TJ180.

## 4. Key Design

### 4.1 cam_i2c_init state machine

```
IDLE(wait start) ──→ PWR_OFF(300ms, cam_en=0) → PWR_SETTLE(12ms, cam_en=1)
  → BUS_CHK(sample line levels, status bits only)
  → WALK (entry by entry: LOAD_ROM → START → TX×4(wait done, check nack) → STOP
           nack? → RETRY_ENTRY(≤10 times, 10ms apart) → exhausted? → FAIL_ROUND)
  → (last two entries = stream-on 0x3002/0x3000)
  → DONE_OK: init_done set (data path released); 220ms settle counted for diagnostics only
FAIL_ROUND → DISCHARGE(500ms) → PWR_OFF (≤3 rounds) → INIT_FAIL(sticky, init_done held 0)
```

- Timing base 200M; long delays (300/500/220ms, 10ms) use 32-bit divided counters.
- **Staggered start** (review final decision Q4): cam0 starts at power-up; cam1's `start` is wired to cam0's `done_ok`
  — cam1 begins its power-up sequence only after cam0's configuration completes, preventing a dual-sensor power-up inrush.
- **No read-back verification** (review final decision Q3): NACK exhaustion goes straight to a full-round retry (power cycle as backstop).
- The CSR soft-reset bit can re-trigger a rerun after INIT_FAIL (for debugging).

### 4.2 ROM

- One entry 24b = {reg[15:0], val[7:0]}; a 142-entry case ROM.
- **Script-generated** `imx415_rom.sv` (and the TB golden sequence files) from the same-source
  imx415_init.c tables — eliminating transcription errors (risk R4).
- The two cameras differ only in the 5 geo-block values: the ROM carries a `MODE` parameter (4K/1080)
  generating two complete tables; no runtime patching (simple and direct, zero logic).
- **Write order = table order**; the SONY magic block is order-sensitive and must not be reordered (readme §7 / table comments).

### 4.3 Status diagnostics

Each channel uses the retired DIAG slot of its own apb_cam_ctrl (embedded in top_cam, both cameras
at the same address in APB0/APB1) (v0.4 erratum: **DIAG3 @0x0C** — the original 0x18 was a typo;
word3=byte 0x0C; the raw stream-loss locator has been retired):

```
{fail[16], done[15], busy[14], round[13:12], retry[11:8], idx[7:0]}
```

Plus a **rerun soft trigger** (landing of review Q2 "RTL soft-reset rerun"): the retired DIAG7 slot
(**@0x1C**) is reused as an RW sticky `[1:0]` (bit0 = this instance, write 1 to set;
top_cam double-flops the edge detection into `cam_i2c_init.start`; software writes 0 to clear for next time).

In bit-only no-firmware mode it cannot be read; for troubleshooting, insert a "read-only" firmware that
queries and relays via UART (§4.6; main.c '0' status key / 'y' rerun key implemented).

### 4.4 cam_en ownership and I2C pad takeover (integration core)

```systemverilog
// top_cam.sv new ports (per camera):
//   output cam_en,  input scl_i, output scl_o/scl_oe, input sda_i, output sda_o/sda_oe
// top_cam_demo port forwarding + SoC write-line removal; open-drain mapping (isomorphic convention):
assign cam_0_scl_o  = 1'b0;
assign cam_0_scl_oe = ~u_cam_0_scl_pad_o;        // pad_o=1(release) → oe=0
// cam_en: RTL's exclusive duty (u_i2c_init_x.cam_en direct drive), w_gpio_write removed
```

- The SoC GPIO `w_gpio_write` no longer connects to cam_en; firmware main.c concurrently deletes I2C/GPIO-related
  calls — against dual-master conflicts (risk R6).
- Before reset release, the cam_en level = peri GPIO reset default output; **board-level confirmation needed** that the
  sensor en pin's external default is low (risk R3; if the peri reset state is not 0, set output initial value 0
  in the interface designer or have the wrapper drive 0 immediately at power-up to override).

### 4.5 Configuration complete → data path release (review-added requirement)

[top_cam.sv](../rtl/top_cam.sv) L770/L802 current state:

```
gate_ready  = fw_flush_done                    // gate-open condition
raw_aresetn = sys_clk_200m_rstn & sw_rstn      // raw-domain reset
```

Change to two single lines (init_done is cam_i2c_init DONE_OK; 200M same-domain direct connection, no CDC):

```systemverilog
assign gate_ready  = fw_flush_done & init_done;                    // gate-open precondition
assign raw_aresetn = sys_clk_200m_rstn & sw_rstn & init_done;      // raw domain waits for configuration
```

Semantics and safety argument:

- `sw_gate` is 0 at power-up + the boot chain is unchanged: before init_done the sensor has no stream (cam_en not even powered),
  so the boot chain has no trigger anyway; after init_done the sensor streams, and the first vs falling edge goes through the
  existing flush boot → gate_ready ready → gate opens at the next frame header. **Fully isomorphic to the current
  power-on boot timing, with only one extra precondition AND term**; the source-switching path is untouched.
- **frame_writer / reader AXI master ports never reset** (hard rule #1) — "not working" is naturally guaranteed
  by the absence of input data: the writer publishes nothing without a stream (whole frame or nothing), and the reader
  emits nothing without a request edge. They are not the objects gated by init_done.
- On INIT_FAIL, init_done stays 0: that channel's data path is permanently silent (black screen); recover via the CSR
  soft-reset rerun or by re-programming the bit — consistent with "no data until configuration completes".
- TB interfacing: if the current TBs (the tb_phase4 family) bypass top_cam and connect module chains directly, the init_done
  port is tied to constant 1 (equivalent to the "configuration complete" steady state) and existing cases need zero changes;
  the gating coordination behavior is covered by tb_cam_i2c_init integration cases + board-level bring-up.
- **Power-on default source = camera (RTL-verified)**: CTRL_RESET=32'hB4EB_C814
  (apb_cam_ctrl.sv L36, pat_en=0) + pat_sel_eff reset 0 → the source mux goes straight to the sensor, and wb/blk_clip
  are camera-domain behavior. After bit-only configuration completes, images appear **without any CSR writes**;
  the pattern source is selected only by explicit UART 'p' (needs firmware). Incidental finding of two stale v3 comments
  (apb_cam_ctrl.sv L9-10 "reset default 1"; top_cam.sv L566-567 sw_src_q reset 2'b10 and comment) — the values do not affect
  function (the 1-beat false edge at power-up is absorbed by the c3c frame-boundary trigger mechanism;
  c3m/v4.11 board tests both green); P3 fixes the comments and reset values in passing.

### 4.6 Firmware positioning (review final decision Q1)

**All I2C-related firmware duties deleted; the debug channel is retained:**

- main.c deletes: `imx415_init(0/1)` calls, stream_on/off, the I2C menu keys, cam_en
  GPIO operations. Firmware no longer touches the I2C controller or cam_en.
- main.c keeps: the UART heartbeat (0.5s DIAG group print, **new init status field**), CSR
  runtime adjustment keys (white balance/phase/source switch/pattern).
- Deployment form: daily = **bit-only imaging, no firmware loaded**; troubleshooting = insert this "read-only"
  ELF on demand (openocd load, independent of the bit, program.md §2).

### 4.7 Clock domain and SDC

Single domain 200M; the SDC cam_* constraints carry over; 50kHz SCL is a globally slow signal, no new
constraint needs (PnR timing all green is the criterion).

### 4.8 Time budget (50kHz, staggered)

| Item | Duration |
|---|---|
| Single byte (9 SCL @50k) | 180µs |
| Single write transaction (START+4B+STOP) | ~0.78ms |
| Full 142-entry table | ~111ms |
| Power sequencing (300ms off + 12ms settle) | 312ms |
| **cam0 nominal imaging** (including reader gating ~35ms) | **~0.7s** |
| cam1 (staggered, restarts the full flow after cam0 done_ok) | **~1.4s** |
| Worst case (one channel 3 retry rounds) | +~2.5s |

## 5. Verification Plan

| Layer | TB | Cases |
|---|---|---|
| Byte engine (**P1 mandatory prerequisite**) | tb_i2c_master.sv (new) | single-byte write/read, repeated START, NACK capture, clock stretching, SCL watchdog err→CMD_RESET recovery, true idle after STOP, behavior during reset release |
| Initializer | tb_cam_i2c_init.sv (new) | full golden sequence comparison (order+values, generated from the same source as the ROM); constant NACK→3 retry rounds→INIT_FAIL; SCL stuck low→err retry; mid-run recovery→retry success; **init_done set only after the two stream-on writes complete**; **staggering: cam1 start must not precede cam0 done_ok** |
| Whole project | current regression | verible → vlog 0 Error → tb_phase4 / tb_phase4_ddrm / tb_phase5_cam1 all green (init_done tied to constant 1, existing cases zero-change) → efx_map compile passes (XML registration in effect) |
| Board | bit-only bring-up | ① program the bit without an ELF, measure imaging time (expect cam0 ~0.7s / cam1 ~1.4s); ② insert the read-only ELF to read DIAG3/nack_cnt; ③ fault drills: one sensor unpowered→observe 3 retry rounds→confirm the other channel is undisturbed and the failed channel stays black |

Flow discipline carries over: vsim only after vlog 0 Error; efx_map/vlog check declaration order and multiple drivers (verible does not).

## 6. Phased Implementation

| Phase | Content | Exit criterion |
|---|---|---|
| **P1 byte-engine functional verification (mandatory prerequisite gate)** | tb_i2c_master all cases + G3 parameter re-check + (optional) CMD_RECOVER retrofit | vsim all green; **no integration until this gate passes** |
| P2 initializer | gen script → ROM + cam_i2c_init + tb_cam_i2c_init | vsim golden 0 errors + fault-injection/staggered/release cases all pass |
| P3 integration | top_cam hookup + gate release + top_cam_demo port forwarding + XML registration + main.c de-I2C + full regression + bitstream | three TBs green + map/pnr/pgm PASS |
| P4 board | bit-only imaging + timing + DIAG readout + fault drills + cam_en reset level confirmation | firmware-free dual-channel imaging; retry/release paths confirmed on hardware |
| P5 docs | readme_4K_1K / program.md / milestone archive | — |

Change boundary: the display chain/DDR/replay gain only a single `& init_done` AND term (§4.5), everything else
untouched; board regression risk concentrates in the I2C bring-up itself.

### 6.1 Execution Record

| Phase | Status | Record |
|---|---|---|
| P1 | **complete (2026-10-24)** | `sim/tb_i2c_master.sv` created (open-drain bus + slave BFM + T0~T8: idle levels/full write/continuous write/repeated START read/address NACK/clock stretching/watchdog err+CMD_RESET recovery/new transaction after err/200M·50k real-parameter smoke test); vlog 0 Error, vsim **PASS errors=0**. **i2c_master.sv got 3 fixes**: ① `scl_timeout` driven by two processes (vopt-7061, iverilog doesn't flag it) — the clear path merged into the watchdog's single process; ② a real bug: CMD_RESET did not actually clear `scl_timeout` (comment claimed it did), so after a watchdog abort the module wedged permanently (every STOP state aborted on seeing the flag, never reaching STOP_B where the flag could be cleared) — fixed together with ①; ③ `CNT_LOW_END/CNT_HIGH_END` declarations moved ahead of the watchdog process. **G3 conclusion**: with 200M/50k real parameters the measured SCL half-period is exactly 10µs, watchdog 100µs = 10 half-periods is sufficient; instantiation must explicitly pass `SYS_FREQ=200_000_000, I2C_FREQ=50_000`. TB-layer lessons: the slave BFM's `sda_pull` polarity (1 = drive low = ACK); the command `go` pulse must be negedge-anchored for a full beat (issuing right after posedge covers only half a beat, the master misses the sample and parks forever in ST_HOLD). |
| P2 | **complete (2026-10-24)** | **P2-1**: slave BFM split out as `sim/i2c_slave_bfm.sv` (reused by multiple TBs), adding a `cap_list[$]` capture queue and `n_stop` counter (hierarchical access); P1 regression PASS. **P2-2**: `tools/gen_imx415_rom.py` same-source parsing of imx415_init.c → `rtl/imx415_rom.sv` (142-entry case ROM, `MODE_4K` dual-geo branch, `last_idx` output against dual-source drift) + `sim/imx415_seq_cam{0,1}.hex` golden; **erratum: the base table is actually 109 entries** (format/magic 78 + legacy geo 19 + clock 12; the source file's "107-entry" comment is stale); the script has built-in assertions (entry count/standby first entry/TXCLKESC last entry/geo 11 entries with VMAX·HMAX values/DPHY 9 rows with TCLKZERO hi=0x01/stream-on order/LANE_MAP_TEST=0 takes the #else branch values). **P2-3**: `rtl/cam_i2c_init.sv` — FSM: IDLE→PWR_OFF(300ms)→SETTLE(12ms)→LOAD→START/TX×4/STOP→NEXT…; NACK/err uniformly CMD_RESET back to place + RETRY_GAP(10ms) retry ≤10 times/entry → DISCHARGE(500ms power-off) full round ≤3 rounds → DONE(init_done held)/FAIL(sticky); start triggers on **rising edge** (not re-triggered by residual level after completing back to IDLE; staggered start wires cam0's init_done level); period constants `(SYS_FREQ/1000)*MS` (200M·500ms=1e8, no 32-bit overflow); embeds i2c_master + imx415_rom, pad-level interface (pad_o=1 release). **P2-4**: `sim/tb_cam_i2c_init.sv` three instances (cam0/cam1 staggered slave/camf fault-injected) four cases all pass **PASS errors=0**: C1 cam0 full-sequence golden comparison 142/142 + power sequencing; C2 cam1 auto-started by cam0 init_done, golden(cam1/geo1080) 142/142; C3 constant address NACK → 3 retry rounds (round=3) → init_fail sticky, init_done=0, cam_en held; C4 rerun clears sticky and the full sequence succeeds again 142/142. Debug records: ref actual argument incompatible with fork (vlog-13219, wait_flag changed to polling); TB instantiation SYS_FREQ mistakenly 10k causing `T_SCL=0→CNT_W=0→[CNT_W-1:0]` reversal (vopt-3373); added `SYS_FREQ/I2C_FREQ<2` $fatal guard. |
| P3 | **complete (2026-10-24)** | **P3-1a** `apb_cam_ctrl.sv`: retired DIAG3 slot (@**0x0C**, word3) reused as a read-only observation `{fail[16],done[15],busy[14],round[13:12],retry[11:8],idx[7:0]}` (the §4.3 original 0x18 was a typo, corrected with this version); retired DIAG7 slot (@0x1C, word7) reused as RW rerun sticky `[1:0]` (write decode extended to word7, same CTRL2 reuse pattern). **P3-1b** `top_cam.sv`: +`MODE_4K` parameter and the 7-wire cam_i2c port group (cam_en/cam_scl/sda pad i+o/cam_i2c_start/cam_init_done); u_cam_ctrl +2 ports; rerun sticky double-flop edge detection (pclk=sys_clk_200m same domain) into `start = cam_i2c_start \| rerun_pe`; `u_i2c_init` instantiation (SYS_FREQ=200M/I2C_FREQ=50k/MODE_4K passed through, reset excludes init_done against self-lock); **the two §4.5 AND terms landed**: `gate_ready = fw_flush_done & i2c_init_done`, `raw_aresetn = sys_clk_200m_rstn & sw_rstn & i2c_init_done`; incidentally corrected the sw_src_q reset value 2'b10→2'b00 + comment (left over after CTRL_RESET changed pat_en=0; sw_src_chg has no consumers so historically harmless). **P3-2** `top_cam_demo.sv`: cam_en and pad oe drive sources switched to the init modules (`oe=~pad_o`), SoC I2C write lines left floating, read lines retained for bus observation (Q1); staggered chain: u_cam_0 `start=1'b1` (a natural edge at reset release), u_cam_1 `start=cam0_i2c_done`; `MODE_4K` 1/0 passed through; u_cam_1 cam_init_done left floating for TB probing (observation goes through APB1 DIAG3). **P3-3** firmware de-I2C: `imx415_init.c/h` deleted (makefile wildcard has no reference); main.c removed the imx415_init call and the rc fallback block, added `cam_i2c_show` (DIAG3 decode) and `cam_i2c_rerun` (DIAG7 write 1→delay→write 0), menu +`[0]` status/`[y]` rerun (target channel) keys; userDef.h DIAG3/7 comments updated. **Semantic change**: init FAIL no longer auto-switches to a pattern fallback (firmware boots in seconds while init takes 0.7~1.4s; the terminal state cannot be reliably judged during startup) — the FAIL channel goes black; 'p' manual pattern fallback / 'y' rerun recovery. **P3-4 regression**: verible OK on the three modified files; vlog over all 24 rtl files **0 Error 0 Warning**; 5 TBs all green: tb_i2c_master PASS errors=0, tb_cam_i2c_init PASS (C1~C4), tb_phase4 [P4-OK], tb_phase4_ddrm [P4C-OK]+[P4-OK]+[SLOW-OK] (ddr_ctrl_model model library compiled into work), tb_phase5_cam1 [P4C-OK]+[P5-OK]+[SLOW-OK] (neither TB instantiates top_cam; the port change has zero ripple, empirically confirming the §4.5 "init_done tied to constant 1" prediction was unnecessary). **P3-5 bitstream**: XML registers the three files i2c_master/imx415_rom/cam_i2c_init; efx_run compile **map/interface/pnr/pgm all PASS** (~4min), err.log empty, no timing violated, warns contain no new module entries. |

## 7. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | i2c_master in-house, simulation-passed but **never board-tested** (review-confirmed) | P1 set as a mandatory prerequisite gate: integration allowed only after full unit-TB coverage; staged board bring-up (single-byte probe first, then the full table) |
| R2 | No firmware = no heartbeat; nothing to read when the screen is black | Deployment form = bit-only imaging; insert the "read-only" ELF to see DIAG3 when troubleshooting |
| R3 | cam_en reset default level unconfirmed (peri GPIO reset state) | First item measured in P4; set the initial value in the interface designer if needed |
| R4 | Table transcription error → sensor wedge | Script same-source generation + TB golden comparison |
| R5 | Dual-camera simultaneous power-up inrush | Staggered start (Q4 final decision) |
| R6 | Firmware residual I2C/GPIO operations conflicting with RTL | P3 concurrently deletes all I2C duties from main.c; audit `imx415_*`, `cam_gpio_*`, `i2c_*` references down to zero |

## 8. Review Final-Decision Record (2026-10-24)

| # | Question | Decision |
|---|---|---|
| Q1 | What "firmware removal" means | Whether the firmware binary stays is optional; **the I2C configuration duty is removed from firmware entirely** (bit-only imaging no longer depends on firmware); a "read-only observation" firmware is inserted on demand for debugging (§4.6) |
| Q3 | Read-back verification | **not done** (NACK retry + full-round power-cycle backstop) |
| Q4 | Dual-camera parallel/staggered | **staggered**: cam1 waits for cam0 done_ok |
| Q6 | i2c_master origin and permission | user-authored, simulation-verified, **never board-tested**; **P1 functional verification is a mandatory prerequisite**; modification allowed |
| Q2 | Firmware I2C fallback path (pad mux) | no objection, executed as suggested: not done in V1; replaced by the "RTL soft-reset rerun" for troubleshooting |
| Q5 | i2c_master CMD_RECOVER | no objection, executed as suggested: as optional P2 hardening given modification is allowed |

## 9. Change Log

| Version | Date | Description |
|---|---|---|
| v0.1 | 2026-10-24 | Initial draft (feasibility + architecture + open questions) |
| v0.2 | 2026-10-24 | Absorbed review decisions: Q1 firmware de-I2C (§4.6 rewritten), Q3 read-back verification dropped, Q4 staggered start, Q6 P1 mandatory prerequisite gate; **added the "configuration complete → data path release" mechanism (§4.5: gate_ready/raw_aresetn with init_done)**; instantiation location fixed inside top_cam; verification plan gained release/staggering criteria |
| v0.3 | 2026-10-24 | P1, P2 executed (§6.1); erratum: the base table measured 109 entries (not 107), full sequence 142 entries/camera (not 140); ROM gained the `last_idx` output; cam_i2c_init start fixed as rising-edge triggered |
| v0.4 | 2026-10-24 | **P3 integration complete (§6.1)**: top_cam hookup (gate_ready/raw_aresetn two AND terms) + top_cam_demo pad/cam_en takeover and staggered chain + XML registration of three files + main.c de-I2C (imx415_init.c/h deleted, '0' status/'y' rerun keys); erratum: DIAG3 address 0x18→**0x0C** (§4.3); rerun soft trigger landed as DIAG7@0x1C RW sticky (Q2); semantic change: init FAIL no longer auto-switches to the pattern fallback (terminal state cannot be reliably judged during startup), 'p' manual fallback / 'y' rerun; full regression 5 TBs green + compile map/interface/pnr/pgm all PASS |
| v0.5 | 2026-10-24 | **P4 board-level troubleshooting complete, both channels imaging**: ① v4.11b fixed ST_DISCHARGE missing the retry clear (board retry=12=10+1+1 root cause); ② DIAG3[19:17] packed with pad observation {cam_en, sda_i, scl_i}, the '0' print changed to four-state labels (FAIL/done/busy/idle); ③ **v4.11c root-cause fix**: when top_cam_demo P3-2 pad takeover deleted the old SoC GPIO0.bit0 → cam_0_en/1_en path it **missed wiring the new source**, leaving the pad ports zero-driven across the file → sensor never powered → all I2C NACKs (DIAG3 en=1 reads the init module's internal signal, not the pad — misleading); added `assign cam_0_en=cam0_en / cam_1_en=cam1_en`. Board-test evidence: cam0/cam1 both done idx=141 retry=0 round=0 (142 entries in one pass, zero retries), fw frm≈1996 / fw1 frm≈1968, cnt df=45/45 full frame rate zero dropped frames, yuv streaming continuously |
