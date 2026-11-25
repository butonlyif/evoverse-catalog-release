[中文](review.md) | English

# Project Implementation Review: G7 RAW10 1080p@30fps UDP Video Stream Board-Level Acceptance

- Case ID: 2026-11-05-g7-raw10-udp-stream
- Created / last supplemented: 2026-11-05 (created)
- Environment: development + runtime (local PC 10.0.0.2 + the ws-e1-base board + TJ180A484S); Windows
- SDK version: Efinity 2026.1 (D:\efinity\2026.1, efx_run bootstrapped; the RiscFree toolchain
  D:\efinity\efinity-riscv-ide-2026.1\toolchain\bin); Questa (tb_udp_v2)
- Project revision: not under git (consistent with the DAYLOG 11-01 record); everything is uncommitted working-tree changes
- Requirement and outcome sources: session + user supplements (the Wireshark observation, the bit/hex download discipline)

## Goals and actual results

Goal: send the RAW10 1080p@30fps test video stream (udp_pat_gen_v2) through the TSE MAC→YT8531→network cable
to the PC, and perform the board-level acceptance with doc/pc_tools/test_raw10_rx.py (the G7 gate).

Actual result: **G7 board-level acceptance PASS** — 295 complete frames, 0 dropped frames, 0 duplicates/out-of-order, 30.00 fps,
622.1 Mbps, all-pixel comparison OK on 5 sampled frames (a 10s window, frame numbers 738..1037).

## Overall process and phenomena

| Phase | What was done | Observed phenomena / manual intervention | Result and source |
|---|---|---|---|
| v2 integration | udp_pat_gen_v2 wired to the top level, the raw10_mode CSR bit, the full TB suite | An earlier version lacked the raw10_mode top-level wiring (fixed) | Simulation PASS (historical session) |
| Firmware | TEST_MODE=0 + PAT_TYPE=2, pulse timing 100µs | — | ELF produced |
| The "incremental stream" puzzle on the board | Multiple re-compiles / probe reads | The 'h83 magic case readback disagreed (a duplicate case item); the board had long been running an old netlist | Observation record |
| The old netlist proven | The 'h92 borrowed probe (pat_dbg_i stuffed into the top 9 bits of 0x092) | After reprogramming the .bit, D92=0x00700fff (raw10_r/pat_en/inf=1) → the earlier "programming had no effect" | Observation record (OpenOCD readback) |
| The programming discipline (explicit from the user) | .bit = JTAG direct configuration, effective immediately; .hex = updates the flash and needs a power cycle | The repeated "programming had no effect" was actually the hex not being power-cycled | User report |
| The last-packet loss isolation | On the wire 1787 packets/frame, no 858B last packet; the MAC OVF/CONT/ifOut counters had zero increments | MAC/FIFO/overflow all excluded | OpenOCD + PC sniffing |
| Root cause (the user's Wireshark) | The 900B last packet was captured on the wire: `[BAD UDP LENGTH 1466 > IP PAYLOAD LENGTH]` | The Windows stack silently drops UDP with mismatched lengths → the PC socket never receives the last packet | User report (decisive) |
| The RTL fix | The last packet's UDP len=866 / IP len=886 (previously the full-packet constants 1466/1486) | The pkt_is_last_w selection, with the empirical basis noted in the comment | rtl/udp_pat_gen_v2.v |
| Simulation | tb_udp_v2 synchronized the last-packet length expectations | 3 frames of 8,044,200 bytes verified byte by byte | ALL CHECKS PASSED (evidence E2) |
| Compile | efx_run --flow compile | map/interface/pnr/pgm all PASS | Evidence E3 |
| Download and load | ftdi_pgm .bit (JTAG, 0x00690A79) + OpenOCD loading the ELF | Firmware started | Observation |
| The G7 acceptance | test_raw10_rx.py --seconds 10 | All items PASS | Evidence E1 |

## Key products and evidence

| Evidence ID | Raw product/log | Version/input association | Fact supported | Location | Snapshot/SHA-256 | Capture time/copy type | Status |
|---|---|---|---|---|---|---|---|
| E1 | The test_raw10_rx.py output | this bit+ELF | G7 all items PASS | evidence/g7_acceptance_output.txt | a5c62279…16678 | 2026-11-05/transcribed | Snapshotted |
| E2 | The Questa TB log | the fixed RTL | The last-packet length check PASS | evidence/tb_v2_fix.log | 2b03f9bc…f95d | 2026-11-05/raw bytes | Snapshotted |
| E3 | The efx_run compile log | ws_e1_tse.xml | map/pnr/pgm PASS | evidence/g7_compile.log | e55513df…662b | 2026-11-05/raw bytes | Snapshotted |
| E4 | A single-line Wireshark capture | the pre-fix bitstream | BAD UDP LENGTH 1466>866 (captured on the user's PC) | — | — | 2026-11-05/user report | User report (no raw file kept) |
| E5 | ws_e1_tse.bit | this compile's product | The configuration running on the board | outflow/ws_e1_tse.bit | 7576bb41…a6bc | 2026-11-05/original | In the tree (may be overwritten by the next compile) |
| E6 | udp_pat_gen_v2.v | the fixed source | The last-packet length field fix | rtl/udp_pat_gen_v2.v | 1708e84b…65c5 | 2026-11-05/original | In the tree |

## The boundary the verification reached

- Simulation: tb_udp_v2 all PASS (including the 900B last-packet frame length, the IP/UDP lengths, the IP checksum, the MIPI packing, the pixel formula, the 30fps cadence).
- Build: efx_run compile (map→interface→pnr→pgm) all PASS.
- Programming: ftdi_pgm -m jtag downloaded the .bit successfully (Device ID 0x00690A79); OpenOCD loaded tseDemo.elf successfully.
- Board-level function: the G7 acceptance PASS (E1). This is a real hardware stream verification, not merely compile evidence.

## Project experience and SDK feedback

Project lessons:
1. **For debugging, always program the .bit (JTAG direct configuration)**; the .hex only updates the flash and needs a power cycle. The repeated "programming had no effect" all stemmed from this.
2. **The length fields of generated UDP/IP packets must be computed per packet**, and compile-time constants are forbidden for variable-length packets — the PC stack silently drops them, and even your own receiving tool will never notice if it does not check header consistency (found this time by the user's Wireshark).
3. A probe borrowed through an already-proven-readable CSR branch ('h92), combined with a bit design where "the old and new netlist readbacks are distinguishable", is a low-cost means of identifying an old netlist on the board.
4. The Efinity synthesizer does not support hierarchical references (cross-module probes must add ports); the debug read channel of reg_apb3 (JTAG mem2array) reading the MAC CSRs (0x68 etc.) is unreliable (a constant 0xffff), while the CPU firmware reading the same address works normally.
5. A duplicated case branch is silently resolved to the first by synthesis — check for address conflicts before adding a magic branch.

Candidates transferable to the SDK:
1. The PC-side validation tools for udp/pat-type generators should have a built-in check for **the consistency of the IP total length / UDP length with the actual payload** (the blind spot of this round's test_raw10_rx.py).
2. The EvoVerse programming step should explicitly distinguish and report .bit (direct configuration) vs .hex (flash, needs a power cycle).
3. The templated "CSR borrowed probe" method (stuffing 10 bits of internal state into the high bits of an already-verified CSR readback) could go into the debugging handbook.

Development intake location and status: not merged (a project-level record within this repo).

## Gaps and follow-ups

- The Wireshark raw capture file for E4 was not kept (a user-side observation; the line content has been transcribed into this review's process table).
- The pre-fix "last packet silently dropped by the OS" behaviour at the Windows stack level is a reasonable inference corroborated by the Wireshark annotation; no kernel-level behaviour experiment was done.
- The firmware [TXOK] arbitration print code is in main.c but produced no readback during the on-board flow (the root cause was closed by Wireshark; the print is kept for later reuse).
- The DAYLOG 2026-11 entry for this round was supplemented the same day.
- G6 (quantifying the incremental pattern mode throughput) and the G1/G2 switch-back re-test are still pending.

<!-- evoverse-project-review:evidence
{"hardwareStatus":"PASS_G7_UDP_RAW10_30FPS","evidence":[
{"category":"board_validation","path":"project-review/2026-11-05-g7-raw10-udp-stream/evidence/g7_acceptance_output.txt","digest":"a5c6227936862b778382e3703452d28a2b406ffbb1f9aad2b735b6e33e216678"},
{"category":"build_log","path":"project-review/2026-11-05-g7-raw10-udp-stream/evidence/g7_compile.log","digest":"e55513df19f880f25bee9d6e92ebc8b92edd86a48f2ba88fb1d41dbd834d662b"},
{"category":"simulation_log","path":"project-review/2026-11-05-g7-raw10-udp-stream/evidence/tb_v2_fix.log","digest":"2b03f9bc365fb194b26a4a1c1b91df27bd2bc1b9f716764b8421f7998a93f95d"},
{"category":"rtl_source","path":"rtl/udp_pat_gen_v2.v","digest":"1708e84b5d14c4e8fe07d59fe7480af11ebc2d7f879ce2b1a269174caa7d65c5"},
{"category":"bitstream","path":"outflow/ws_e1_tse.bit","digest":"7576bb412ca024307489094893b32ef4708749a37c089732c28556b4f7f5a6bc"}
]}
-->
