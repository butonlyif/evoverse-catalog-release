[中文](cam1-ddr-replay-plan.md) | English

# cam1 (1080p60) DDR Replay Chain Replication Plan (Frozen Draft)

Date: 2026-10-23
Status: **plan frozen** (user-confirmed: fully replicate the cam0 v4.10 design + dual AXI Interconnect sharing the DDR dual ports; implemented on the current project)
Baseline: v4.10c3m. This file is the implementation baseline for task 2; DDR layout accounting in [ddr_interface.md §10](ddr_interface.md).

---

## 1. Current State and Gap

cam1 (u_cam_1) currently has only the display-chain shell: the top_cam instantiation covers only `DISP_FRAME_SLOTS=1125`, the pipeline runs
`pixel_clk_1080` at 37.125MHz; **no DDR replay** (in top_cam_demo cam1's `rd_t*` tie-off yields a constant black field,
no u_fw/u_rd). There is also one **parameter inconsistency**: the u_dtg instantiation inside top_cam hard-codes `LINE_CLKS=1100` and
does not pass HSP/HBP/HFP_CLKS — a 1080p@PPC4 line should be 550 beats; the current state amounts to 30Hz and the line-segment sum 620≠1100
would trip the disp_timing structural guard (simulation FATAL).

Goal: cam1 replicates the full cam0 chain = 64b carrier writer/reader + LPDDR4X frame ping-pong + frame-level arbitration (disp_sof anchor
+ ANCHOR_WAIT) + source switching/power-on replication + diagnostics.

## 2. Topology (Frozen)

> **2026-10-23 change**: after review, the Efinity AXI Interconnect IP is **not used** (opaque internal implementation, 512b+2-to-1 non-default parameters without vendor validation, restricted ADDR options and S/M directions); replaced by the **in-house transaction-level arbiters** `axi_wr_arb` / `axi_rd_arb` (RR1, 2→1, 512b, 33-bit address pass-through); design specification in **[arbiter.md](arbiter.md)** (under review). "AXI IC" in the topology below refers to the in-house arbiters; the interconnect IP generation steps are void.

```
cam0_fw(200M) ─┐
               ├─ AXI IC write 2→1 @200M ──> DDR target0 (ACLK=sys_clk_200m, unchanged)
cam1_fw(200M) ─┘   ROUND_ROBIN_1

cam0_rd(148.5M) ─────────────┐
                             ├─ AXI IC read 2→1 @148.5M ──> DDR target1 (ACLK=pixel_clk, unchanged)
cam1_rd(37.125M) ─AXI CDC────┘   ROUND_ROBIN_1
                  (AR/R two-channel async FIFO, 37.125→148.5)
```

- **peri.xml zero changes**: target0 ACLK_0=200M, target1 ACLK_1=148.5M bindings kept as-is.
- Both write-side masters are in the 200M domain (the raw domain shares sys_clk_200m); the interconnect is single-clock direct, **zero CDC**.
- The read-side interconnect clock = 148.5M (cam0_rd's original clock); cam1_rd enters via a 2-channel AXI CDC; the cam0_rd protocol is unchanged,
  only the wiring changes (through the interconnect, address channel +1 beat).
- cam1 replay bandwidth ~0.5GB/s (write 0.26 + read 0.26), ~3% of each of the read/write interconnects; arbitration impact negligible.
- Interconnect IP configuration (Efinity IP Manager, AXI Interconnect, two instances; finalized 2026-10-23 per UG v1.8 Table 16/17 and wizard measurements):

| Wizard parameter | Write-side IC (axi_xbar_wr) | Read-side IC (axi_xbar_rd) |
|---|---|---|
| Protocol | AXI4 | AXI4 |
| Arbitration Mode | ROUND_ROBIN_1 | ROUND_ROBIN_1 |
| **Number of Slave Interfaces** | **2** (S0=cam1_fw, S1=cam0_fw) | **2** (S0=cam1_rd_cdc, S1=cam0_rd) |
| **Number of Master Interfaces** | **1** → target0 | **1** → target1 |
| AXI Address Width | 32 | 32 |
| AXI Data Width | 512 | 512 |
| AXI ID Width | 6 (aligned to the DDR port; writer drives awid=0) | 6 |
| AXI User Width | 1 | 1 |
| AXI Tab: Destination Address Space / Offset (M=1 single row) | 28 / 0x0000_0000 | 28 / 0x0000_0000 |
| Clock (wired at instantiation) | 200M | 148.5M |

Wizard notes:
1. The wizard opens with the example-design direction Slave=1/Master=2; **must be changed to 2/1** — s_axi_* is the upstream camera master entry, m_axi_* is the exit toward the DDR slave.
2. The AXI Address Width wizard only offers 32/64 (the UG text says 12-64); take 32: the highest frame address bit is bit26; bit [32] of the writers'/readers' internal 33-bit address is always 0 — the interconnect S port takes [31:0], and the M port pads [32] with 1'b0 toward the DDR.
3. Arbitration drops PRIORITY for RR1 (user decision): 2 ports = strict alternation; per-channel utilization ~8% write / ~14% read; no starvation, no perceptible latency.
4. The vendor testbench deliverable was tested only with default parameters (UG L468); reference only; regression relies on the in-house unit TBs.

- **cam0 path change statement**: write/read AXI wiring now goes through the interconnect (protocol semantics unchanged, address channel +1 beat @200M/148.5M,
  ~0.1% of the 1100-beat line budget; the ANCHOR_WAIT margin is not hurt — phases 3/4 prove it with the P4C criterion).
- Fallback: if the 512b interconnect fails to converge in resources/timing on TJ180 (UG reference: 2→1@128b=910 LUT / fMAX 315MHz,
  512b roughly ×4), the fallback = a hand-built lightweight read arbiter (AR 2-to-1 + R dispatched by grant, single outstanding/port),
  requiring a new review.

## 3. cam1 Key Parameters (Frozen)

| Parameter | Value | Note |
|---|---|---|
| Source window | LINE_TOTAL_PIX=1944 / SKIP_FIRST=11 / 1080 lines / GW=480 | top_cam default group (already 1080p) |
| Carrier line | 480 beats (64b) = 3840B = 60 words | passed in after writer/reader parameterization |
| AXI bursts | 32+28 two bursts (within the 4KB window) | dual-burst structure kept; drain FSM unchanged |
| DDR layout | A1=0x0400_0000 / B1=0x0500_0000, line slot 4KB | ddr_interface.md §10 static accounting |
| Display timing | LINE_CLKS=550 (HSP11+HBP37+2+LINE_WORDS480+HFP22), FRAME_SLOTS=1125 | CTA 1080p60, VSP5+VBP36+VACT1080+VFP4 |
| ANCHOR_WAIT | 37 (= VSP+VBP 41 − margin 4) | board value; the tb's shortened-frame value to be defined separately |
| reader clock | pixel_clk_1080 37.125M | frame handshake toggle 200M→37.125M (replicating the tog200/tog148 structure) |
| flush chain | cam1-independent cam1_fw_flush / cam1_rd_flush | cam0 chains untouched |

## 4. Implementation Phases and Verification Gates

| Phase | Content | Verification gate |
|---|---|---|
| 0 (this document) | plan/layout freeze + ddr_interface §1 erratum + §10 accounting | document review |
| 1 | frame_writer/frame_reader line geometry localparam→parameter (defaults = current 4K, behavior unchanged); tb_frame_writer/tb_frame_reader add 1080 geometry cases (480 beats/60 words/32+28) | 4K regression unbroken + verible/vlog 0 errors |
| 2 | top_cam u_dtg instantiation parameterized: LINE_CLKS, HSP/HBP/HFP_CLKS passed as parameters (cam0=1100/44/75/18, cam1=550/11/37/22); tb_disp_timing adds a 1080 case | line-segment-sum guard self-consistent + 4K regression unbroken |
| 3 | Write-side interconnect integration: both IC IPs generated into the project; cam0_fw/cam1_fw → IC-write → target0 (cam1_fw attached but not yet enabled) | tb_phase4 P4C unbroken through the interconnect |
| 4 | Read side: axi_rd_cdc wrapper (AR/R async FIFO, modeled on the ddr_async_fifo gray pointers) + cam0_rd/cam1_rd_cdc → IC-read → target1 | CDC unit TB loopback comparison + P4C |
| 5 | cam1 full chain: top_cam brings out cap_t*/line_tick/disp_sof/disp_stall; u_fw1/u_rd1 instantiated (VACT=1080/60 words/A1B1/WAIT37); frame handshake cross-domain; per-cam flush; cam1 diagnostics CSR | 1080 shortened-frame full-chain TB (replicating the P4C criterion) |
| 6 | 4K+1080 dual regression → efx compile all PASS → board test (pattern first → camera source) | map/interface/pnr/pgm all PASS; board-test readout |

## 5. Risks and Countermeasures

1. **512b interconnect resources/timing**: phase 3 maps first to see LUT/fMAX; if not converging, switch to the fallback arbiter (§2 fallback).
2. **cam1_rd CDC latency eating the ANCHOR_WAIT margin**: CDC FIFO first-word latency + interconnect 1 beat must be < the 4-slot margin;
   phase 4 TB quantifies first-word latency; adjust WAIT=37→35 if necessary.
3. **Interconnect IP generation**: IP Manager is a GUI operation; configure per the §2 table; after generation `<module>_define.vh` parameters enter
   the project file list.
4. **DBG_SHAPE_PAT direct injection source is 4K geometry** (shape_pat_gen SRC_LINES=2160 hard-coded): cam1 instantiation keeps
   DBG_SHAPE_PAT=0 disabled; if 1080 direct-injection diagnostics are needed, parameterize separately later (out of scope for this task).
5. **cam0 regression protection**: the phase 1/2 parameterization defaults must be word-for-word equal to current values; run the tb_phase4 criteria +
   vlog 0 Error at each phase; verible-syntax MCP first.
6. **Firmware main.c**: cam1 diagnostic prints to be updated in sync once the DIAG channels are finalized (end of phase 5).
