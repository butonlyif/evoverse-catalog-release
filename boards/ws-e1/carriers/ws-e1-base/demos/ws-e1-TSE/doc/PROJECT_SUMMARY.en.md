[中文](PROJECT_SUMMARY.md) | English

# ws-e1-TSE Project Technical Summary (Oriented to Camera Feature Extension)

> Updated: 2026-11-06 (bit `4eba25c1…`, G1–G7 wrap-up + runtime mode switching + sw-TX deadlock fix)
> This document is a full-project snapshot taken before adding the camera (MIPI CSI-2 → RAW10 video stream replacement).
> Companion reading: `doc/efinity/` (authoritative toolchain knowledge), `DAYLOG/2026-11.md` (all debugging evidence),
> `project-review/2026-11-06-g3-g4-arp-icmp/review.md` (evidence chain and digests).

---

## 1. Project Positioning and Current Capabilities

Gigabit UDP system built on **Efinix Titanium TJ180A484S + SapphireSoC RISC-V + TSE MAC**.
The current "video source" is an **RTL-synthesized RAW10 sensor simulation stream** (the RAW10 mode of udp_pat_gen_v2);
adding a camera = replacing/bypassing this synthesized source with a real MIPI CSI-2 RX path, with the entire remaining chain reused.

Verified capabilities (all board-level measured):

| Capability | Metric |
|---|---|
| G6 line-rate stream | 1500B incremental UDP, **951 Mbps**, badpay=0 on the PC side |
| G7 video stream | RAW10 1080p at **30fps**, **622 Mbps**, 0 dropped frames, pixel comparison PASS |
| Network services | ICMP/ARP replies, UDP echo(10005), 1 Hz tick, UART-configured IP/MAC |
| Runtime switching | Single-byte UDP 10006 commands t/v/n/s/0-3, effective immediately without recompilation |
| Software stop | `pat_gen_kill` (0x208 bit3) clean stop at packet boundaries; for the inc infinite stream it is the only stopping mechanism |

## 2. Clocks and Reset

| Clock | Frequency | Domain | Purpose |
|---|---|---|---|
| `clk` (clk_50m) | 50 MHz | APB / CPU / FIFO write side | CSR, eth_pkt_fifo write port, RISC-V |
| `clk_125m` | 125 MHz | RGMII / tx_axis / FIFO read side | MAC TX, eth_pkt_fifo read port |
| rx_axis | 125 MHz | MAC RX domain | MAC→fifo RX tap |

- PLL is **created in ISF** (`design.create_block`, not instantiated in RTL); RTL only declares `pll_*_locked` ports
- Reset: `mac_reset = ~pll_0_locked & ~pll_rgmii_locked`; `mac_rstn = ~(mac_reset||proto_reset)`
- SDC: `create_clock` for every clock + `set_clock_groups -asynchronous`; `set_false_path` applied separately to CDC sync chains
- All CDC synchronizers carry `(* ASYNC_REG = "TRUE" *)`; **synchronizer/handshake registers must also carry `(* syn_keep = "true" *)`** (Lesson 1 in §6)

## 3. Address Map (APB3 CSR, rtl/reg_apb3.v)

| Address | R/W | Function |
|---|---|---|
| `0x204` | W | TX mux: 0=pattern generator → MAC; 0x10=CPU (eth_pkt_fifo) → MAC |
| `0x208` | R/W | bit0 `udp_pat_gen_en` start (parameter-load pulse); bit1 `raw10_mode`; bit2 `mac_pat_gen_en`; **bit3 `pat_gen_kill`**; bit[5:4] `pat_mode` (RAW10 display patterns 0-3) |
| `0x092` | R | `{pat_dbg[8:0], eth_tx_full, eth_tx_free_cnt[12:0]}` (free empty=4095; dbg[5:3]=pat_gen FSM state, dbg[6]=infinite_en) |
| `0x093` | W | `eth_tx_wr_en`: TX FIFO data port, 9bit `{tlast,tdata}`; write the frame's final byte with `|0x100` |
| `0x090` | R | RX FIFO status (rx_word_cnt / overflow sticky, write 1 to clear) |
| `0x091` | R | RX FIFO ShowAhead read port `{tuser,tlast,tdata}`, read pulse pops |
| `0x248` | R | MAC `ETH_TX_STATUS`: bit13 tx_full + bit[12:0] free (different source from 0x092) |
| `0x24C` | R/W | W=TX FIFO data (same path as 0x093); R=pat_dbg probe borrow |
| `0x68/0x6C` | R | MAC aFramesTransmittedOK / aFramesReceivedOK (32-bit counters) |

Key firmware functions (`embedded_sw/.../tseDemo/src/main.c`):
`PatGen()` (parameterized three-branch inc/old-MAC/RAW10; sets parameters + start pulse),
`StreamStop()` (kill → poll FSM back to S_IDLE → withdraw en → mux → CPU),
`MacTxSend()` (byte-by-byte writes to 0x24C, last byte |0x100; busy-wait free<len),
`ApplyMode()` (mode switch in main-loop context: stop stream → switch mux → restart),
`AppRun()` (RX dispatch + mode branching + control command PatCtrlCmd + three-state injection).

## 4. Data Path (TX 3-to-1, controlled by 0x204)

```
                      ┌─[inc line-rate stream / RAW10 video / display patterns]─┐
 udp_pat_gen_v2 ──────┤                                                        │
 (AXI-Stream 8bit)    └────────────┐                                           ▼
                                   ├── axi4_st_mux3 ──► TSE MAC ──► RGMII ──► PHY
 eth_pkt_fifo(TX DC_FIFO 9bit) ────┘   (when 0x204=0x10)    (125MHz)      (YT8531)
 (CPU writes 0x24C/0x093)      ▲
                               │ apb_wr(0x093) — silicon-healthy after the 2026-11-06 syn_keep fix
 RISC-V firmware (50MHz APB) ──┘
```

RX side: MAC `rx_axis_mac` → `eth_pkt_fifo` RX tap (`rx_tready` **constantly 1**, backpressure forbidden by the UG)
→ CPU APB read window (0x091 ShowAhead + 0x090 level). Frame-granular admission (SOF checks level ≥1536 words);
on overflow the whole frame is dropped + sticky.

**Three sw frame-injection states** (inside AppRun, path selected by the current mode):
1. netsvc: direct `MacTxSend` (FIFO idle, no contention)
2. RAW10 stream: injection in the inter-frame S_IDLE window (v3 scheme; the inter-frame silent period is long enough)
3. inc line-rate stream: **kill injection with stop at packet boundary** (IPG=96ns leaves no free window; must stop then send, ≤12.2µs)

## 5. RAW10 Video Path (the core integration point for camera features)

### 5.1 Board side (rtl/udp_pat_gen_v2.v, RAW10 mode)

- With `raw10_mode=1`, frames are sent on the FRAME_PERIOD cadence; each frame has **1788 packets**, packet payload 1466B,
  last packet 900B; the packet header carries a **meta header (frame number + packet index idx)** — the format constants are
  defined by `doc/pc_tools/raw10.py` (`BYTES_PER_FRAME`/`PKTS_PER_FRAME`/`PAYLOAD_LAST`/`H`/`W`); the board-side RTL and the PC side
  must be modified in sync
- Display patterns 0-3 (color bars / horizontal gray / vertical gray / checkerboard) are switched live via `pat_mode[5:4]` (RMW preserves bit3)
- FSM: the RAW10 last packet of a frame goes through S_IDLE; the inc infinite stream loops S_DATA→S_IPG→S_HDR (**never returns to S_IDLE**;
  stopping relies entirely on the kill bit); kill semantics = clean return to S_IDLE at the current packet's tlast boundary +
  pat_en shut-off + start_pulse auto-clear
- RGGB phase is already modeled in the patterns (color bars arranged per the Bayer layout) — `raw10_viewer.py` board testing
  established `cv2.COLOR_BayerRG2RGB` as the correct demosaic constant (BGGB swaps yellow/cyan and red/blue)

### 5.2 PC side (doc/pc_tools/)

| File | Role |
|---|---|
| `raw10.py` | Protocol core: `FrameReassembler.feed(pkt)`→(fn, idx, done, frame); `frame_to_image`; out-of-range/resync protection |
| `tse_console.py` | All-in-one console (button control + Tk/PPM live video + OSD status bar) |
| `raw10_viewer.py` | Video only (OpenCV window); WB/demosaic: `apply_wb` → `cv2.cvtColor(demosaic)` → 10bit→8bit |
| `test_raw10_rx.py` | Headless acceptance: frame-number continuity / 30fps±0.1 / bandwidth 622±5 / pixel comparison |
| `mode_ctrl.py` / `mode_gui.py` | Control only (t/v/n/s/0-3) |

**Camera replacement point**: the RAW10 pixel stream decoded by the CSI-2 RX just has to converge into
"UDP frames that `FrameReassembler` can reassemble (frame number + idx meta, 1788 packets/frame)" —
the cheapest path is **replacing the RAW10 pixel source of udp_pat_gen_v2** (swap the pattern generator for a CSI pixel FIFO);
packetization / UDP encapsulation / PC display reuse the whole chain; `raw10.py` needs its constants changed in sync if the
camera resolution/bit depth differs.

## 6. Silicon-Level Defects and Established Rules (lessons from the past; required reading for camera development)

1. **DC_FIFO reset-handshake FFs dissolved by synthesis** (fixed 2026-11-06, root cause of the deadlock):
   `DaulClkFifo.v`'s `WrClkRstGen[1]/RdClkRstGen[1]` (cross-domain handshake `[1] <= &otherGen`)
   were dissolved by map into undriven wires, and the downstream registers' SR is **active-low** directly connected
   → permanently reset on silicon (TX FIFO always empty, wrcnt stuck at 0). Fix = add `(* syn_keep = "true" *)` to the handshake regs.
   **Rule: add syn_keep to all synchronizer/handshake/cross-domain sampling registers**; RTL health does not imply silicon health;
   every critical change must go through `tb_sw_path` regression + board-level verification.
2. **free/full 13-bit arithmetic is synthesis-sensitive** (2026-11-02): the `4096-wrcnt` form breaks on silicon;
   replaced with `13'd4095 - fill` and forced to 0 when full (`eth_pkt_fifo.v`). Do not casually rewrite similar boundary arithmetic.
3. **bins timing trap**: map reads `ip/myriscv/*.bin` — after changing firmware you must complete make→binGen→copy bins
   before starting compilation, otherwise the old firmware gets embedded (a "fake compile" with unchanged board behavior).
4. **RX backpressure forbidden**: asserting TSEMAC `rx_axis_mac_tready` low silently corrupts frames (explicit in the UG);
   keep it constantly 1 + frame-granular admission. Under camera high bandwidth, if the RX tap feeds the CPU path there is likewise no backpressure; watch FIFO depth.
5. **`ws_e1_tse.peri.xml` is a project source file** (PT artifact; hand-writing/deletion forbidden); ISF is replay-safe
   (only set_property/assign_*; `create_*` was one-shot bootstrap and is commented out).
   **The MIPI CSI RX hard IP is likewise created in ISF**; note:
   - MIPI banks must be **1.2V**; MIPI and LVDS **must not share a bank**
   - Inside an HSIO bank, keep at least one unassigned IO pair as isolation between GPIO/LVDS/MIPI
   - Every ISF change must pass the `cli/import_gpio.bat --dry-run` self-check
6. **The Efinity dbg step reuses `work_dbg\`** (debug_top.v etc.) — migrations/shared projects must carry it along,
   otherwise compilation fails at the dbg step with `No such file`.
7. **PC-side environment**: the USB NIC must be USB 3.0 (2.0 caps at ~342 Mbps and drops small frames); with two NICs on the same
   subnet the control tool must explicitly bind 10.0.0.3; after ARP table aging the UDP control plane deadlocks (when netsvc deadlocks,
   the only escapes are power cycle / JTAG; normally `s` provides an escape).

## 7. Acceptance Methodology (G1–G7 gates, reused for the camera)

Each new capability is split into independently acceptable gates with **dual-side PC+UART evidence**; PASS is required before entering the next gate:

| Gate | Content | PC tool | Board-side evidence |
|---|---|---|---|
| G1 | UDP echo 10005 | test_udp_echo | UART [stat] |
| G2 | tick / netsvc loop | 1Hz packet reception | [stat] tx stepping at 1Hz |
| G3 | ARP dynamic learning | ping / arp -a | `ARP: reply sent` |
| G4 | ICMP 0% loss | ping -S | `ICMP: echo reply sent` |
| G5 | UART-configured IP/MAC | serial commands | banner |
| G6 | Gigabit stress test | test_udp_thr --seconds 60 | dbg probes |
| G7 | RAW10 video | test_raw10_rx + viewer | PPS counters |

Draft camera gate proposal: G8 CSI link establishment (lock/ICLK calibration/UART print) → G9 still-image capture
(single-frame RAM dump compared against a camera pattern) → G10 live stream (all raw10.py metrics, re-run the full
G7 suite after replacing the synthesized source with the real one) → G11 stream+control coexistence (kill/injection path regression).

**Evidence discipline**: compile PASS ≠ board-level PASS; sim PASS ≠ silicon PASS (both deadlocks had RTL PASS
but silicon FAIL); append every repo change to `DAYLOG/YYYY-MM.md`; milestone updates go to
`project-review/<case>/review.md` with SHA-256 evidence.

## 8. Development Workflow Quick Reference

```powershell
# Firmware (RISC-V)
cd embedded_sw\sapphire\software\standalone\tseDemo
$env:PATH = "D:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin;" + $env:PATH
make clean; make
# bins (trap §6.3: must complete before the next map)
$env:EFINITY_HOME = "D:\Efinity\2026.1"
# FPGA full compile (~3 minutes)
D:\Efinity\2026.1\bin\efx_run.bat ws_e1_tse.xml -f compile
# Programming
D:\Efinity\2026.1\pgm\bin\ftdi_pgm.bat -m jtag -b "Generic Board Profile Using FT4232H" outflow\ws_e1_tse.bit
# Simulation (Questa 2024.2; pass criteria in sim/tb_sw_path.v header comments)
cd sim   # compile list + -suppress 3009, see USER_MANUAL §5
# OpenOCD probes (cwd must be embedded_sw\sapphire)
..\..\sw\diag_txtx.cfg   # halt, read TXSTAT/MUX/CFG, then resume (resume returns to boot state)
# PC all-in-one console
cd doc\pc_tools; uv run tse_console.py
```

Shared project copy: `D:\Projs\ws-e1-ge-test` (includes README/USER_MANUAL; when copying you **must include
work_dbg/**). Current board state: RAW10 video stream transmitting continuously.
