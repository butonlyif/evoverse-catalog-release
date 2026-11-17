[中文](review.md) | English

# Project Implementation Review: G3+G4 ARP/ICMP reply board-level acceptance (plus G1 closeout, G2 re-test, and root-cause cure of the RX path death)

- Case ID: 2026-11-06-g3-g4-arp-icmp
- Created / last supplemented: 2026-11-06 (created)
- Environment: development + runtime (local PC 10.0.0.2 (Ethernet 5, plus a 10.0.0.3 NIC) + ws-e1-base board
  + TJ180A484S); Windows; RiscFree toolchain + Efinity 2026.1
- Project revision: not under git (all uncommitted working-tree changes)
- Upstream association: 2026-11-05-g7-raw10-udp-stream (the G1/G2 switch-back re-test in its "gaps and follow-ups" is completed by this case)

## Goals and actual results

Goal (the user-confirmed order): G3 (the PC's `arp -a` dynamically learns the board MAC before `ping 10.0.0.8`) →
G4 (ping 0% packet loss, ≥100 packets) → formal G1 closeout → subsequent G5/G6.

Actual results:
- **G3 PASS**: after deleting the static ARP, the first ping was 4/4, `arp -a` showed `10.0.0.8 ea-e8-5e-00-60-c8 dynamic` (evidence E1).
- **G4 PASS**: `ping -n 100` 100/100, 0% packet loss, avg 5ms, TTL=64 (evidence E2);
  board-side UART ICMP replies 100 times, strictly 1:1 with the requests (evidence E5).
- **G1 formally closed**: UDP echo with the bound-port method 4/4, payload byte-for-byte identical (evidence E3).
- **G2 re-test PASS** (the user explicitly asked for it to be tested first): on the new bit the tick frame was 13 packets/12s with a correct payload.
- **Bonus: root-cause cure of the RX path death** (the yt8531 rgmii-id configuration was overwritten by the reference-driver port, see below).

## Overall process and phenomena

| Stage | What was done | Observed phenomena / manual intervention | Outcome and source |
|---|---|---|---|
| Firmware implementation | Added the four modules net_config/eth_frame/arp/icmp (src/*.c enter the build automatically), main.c RX dispatch: ARP→reply, ICMP→reply, all other IPv4 keeps the L2/L3 symmetric echo; net_config_t single source of truth (G5 reserved); TEST_MODE=2 | — | make -B PASS |
| Getting onto the board | OpenOCD ELF load (it had worked on 11-05) **failed to reproduce** today: `Halt timed out` → after switching to a home-made cfg, tap/examine/soft_reset_halt worked, but `load_image` always stalls in `mpsse_flush()`; a small cfg (diag_lock) reads registers normally. Multiple instances contending for the FTDI made it worse. **Switched to binGen→symbol bin embedding→full compile→ftdi_pgm** (the path validated on 11-02) | OpenOCD root cause unknown (recorded for investigation); the binGen `-c` parameter takes no `.v` suffix (`-c myriscv`), the rom lands in cwd and must be copied to ip/myriscv | bit compile/download PASS |
| G2 re-test (user request) | PC receives tick on UDP 10005 | 13 packets/12s, payload "TSE-SW-TX-TICK-A" | PASS |
| First ping test | Delete the static ARP (`Remove-NetNeighbor` needs admin, ultimately deleted with an elevated `arp -d`) → ping | 100% packet loss; UART rx=0 and no RX dispatch print | FAIL (triggered the diagnosis) |
| RX diagnosis | Firmware [stat] extension: rx(0x6C)/ierr(0x88)/drop(0x9C)/all(0xB4)/rxst(RX_STATUS)/dbg94(rxc+pll probes)/lock/cfg | RXC clock toggling, PLL locked, MAC configuration correct, but **etherStatsPkts=0 (not even bad frames)** → the fault is upstream of the RGMII sampling point; software dispatch and the FIFO write side are excluded | Evidence E4 |
| Root cause | Comparing the PHY snapshots from the two boots: drv_init writes the PHY plain (8030/F0) every time, while the residual initial values on the board were 8130/F1 (rgmii-id from the echo era); peri.xml rgmii_rxc delay="0" | plain + zero delay = zero delay at both ends of 1G RGMII → sampling misaligned → RX loses everything; the yt8531fd.h reference-driver port (USE_PHY_RGMII_ID defaults to 0) overwrote the empirically working configuration | hypothesis→fix verification loop closed |
| Fix | yt8531fd.h: USE_PHY_RGMII_ID default 1 + restore the measured values (CHIP_CFG bit8 + RGMII_CFG1=0x00F1); rebuild firmware→embed→full compile→download | boot prints `YT8531 rgmii-id cfg=0x000000f1 chip=0x00008130` (bit-for-bit identical to the residual measured values) | bit compile/download PASS |
| G3/G4 acceptance | Delete the static ARP → `ping -S 10.0.0.2 10.0.0.8 -n 4` → `arp -a`; `-n 100` | dynamic learning + 100/100 0% + TTL=64; board side ARP=3/ICMP=100/rx+11 | PASS (E1/E2/E5) |
| G1 closeout | UDP echo: the temporary-port method received 0 (the board-side tx counter proves it was sent) → changed to binding port 10005 | 4/4 payload byte-for-byte identical; concluded that Windows does not deliver UDP replies to a temporary port (host side, not a board defect) | PASS (E3) |

Observation/report/hypothesis separation note: "Windows does not deliver UDP replies to a temporary port" is an **observation**
(MAC tx counter + bound-port comparison), the root cause (firewall state table) is an **unverified hypothesis**, no kernel-level
experiment was done; the OpenOCD mpsse hang is an **observation** with an unknown root cause.

## Key artifacts and evidence

| Evidence ID | Original artifact/log | Version/input linkage | Fact supported | Location | Snapshot/SHA-256 | Capture time/copy type | Status |
|---|---|---|---|---|---|---|---|
| E1 | G3 ping + arp -a output transcript | rgmii-id fix bit | ARP dynamic learning 4/4 | evidence/g3_ping_arp_dynamic.txt | fa6f552e…de1c | 2026-11-06/transcribed | Snapshotted |
| E2 | G4 ping 100 packets output transcript | same as above | 100/100 0% TTL=64 | evidence/g4_ping_100_0loss.txt | 99b5b85e…582c | 2026-11-06/transcribed | Snapshotted |
| E3 | G1 UDP echo output transcript | same as above | 4/4 payload identical + the Windows temporary-port observation | evidence/g1_udp_echo_10005.txt | 45df5867…9e5f | 2026-11-06/transcribed | Snapshotted |
| E4 | Pre-fix [stat] discriminator data transcript | pre-fix bit | RX death-cause discrimination chain (MAC zero frames / clocks normal / PHY config comparison) | evidence/rx_diag_before_fix.txt | 3e6f74c6…3905 | 2026-11-06/transcribed | Snapshotted |
| E5 | Post-fix boot + acceptance statistics transcript | fix bit | rgmii-id effective; ICMP 100/100 board side 1:1 | evidence/uart_after_fix_summary.txt | 98b48a8f…99f6 | 2026-11-06/transcribed | Snapshotted |
| E6 | yt8531fd.h fix-version source | rgmii-id restoration | USE_PHY_RGMII_ID=1 + 0xF1 configuration | embedded_sw/sapphire/software/standalone/driver/yt8531fd.h | e9e6d0b5…0bdb | 2026-11-06/original | In the tree |
| E7 | main.c (net service + [stat] diagnostics) | stage 2 firmware | ARP/ICMP/echo dispatch and discriminator counters | embedded_sw/sapphire/software/standalone/tseDemo/src/main.c | 59ec70e2…18a8 | 2026-11-06/original | In the tree |
| E8 | ws_e1_tse.bit | fix-version compile product | Configuration running on the board | outflow/ws_e1_tse.bit | 95407a37…265a | 2026-11-06/original | In the tree (may be overwritten by the next compile) |

## The boundary the verification reached

- Firmware: make -B PASS (arp/icmp/eth_frame/net_config all compile).
- Build: efx_run compile (map→interface→pnr→pgm) all PASS twice (diagnostic version + fix version).
- Programming: ftdi_pgm -m jtag succeeded twice (Device ID 0x00690A79). The OpenOCD ELF load path **was never made to work** (see observations).
- Board-level function: G1/G2/G3/G4 all PASS on real hardware; zero RTL changes this round (all fixes are at the firmware/PHY configuration layer).

## Project experience and SDK feedback

Project lessons:
1. **The PHY RGMII delay configuration must have an explicit owner on exactly one side, together with the FPGA-side delay**: the yt8531fd.h "plain" default
   assumes "peri rgmii_rxc delay=15", while peri actually has delay=0 — two defaults that are each "reasonable" stacked into a
   double-zero delay. Cross-layer default combinations must be pinned down by at least one board-level joint test.
2. **PHY registers persist across bit downloads**: comparing "the initial value before the write vs the value after the write" is a sharp tool for locating a configuration
   regression (this time the 8130/F1 residue directly handed over the empirically working values).
3. **A firmware [stat] full-chain discriminator counter** (MAC TX/RX counters + RX_STATUS + rxc/pll probes + COMMAND_CONFIG
   dumped in one go) cuts an RX fault down to a specific layer in a single board session, avoiding several rounds of guessing.
4. **Get firmware onto the board via binGen→symbol bin→recompile the bit→ftdi_pgm** (consistent with this project's BRAM initialization architecture);
   OpenOCD ELF loading depends on the debug tunnel and was less stable than the former that day.
5. **On Windows, UDP reply delivery must not rely on a temporary port**: UDP echo class tests must bind a fixed port on the PC;
   test_udp_rx.ps1 only receives frames one-way, bidirectional echo needs a dedicated script (to be added to doc/pc_tools).
6. `Remove-NetNeighbor` needs admin to delete a static ARP; `Remove-NetNeighbor -Force` reports a parameter error on this machine's PS5.1,
   so use an elevated `arp -d` or netsh. Two NICs on the same subnet (10.0.0.2/10.0.0.3) need `ping -S`.

Candidates transferable to the SDK:
1. The PHY driver template should explicitly assert the RGMII delay configuration strategy (phy-internal / fpga-peri / none),
   and check at compile time that the peri.xml delay and the macro default are a consistent combination.
2. The EvoVerse firmware template should have a built-in [stat] full-chain discriminator print (MAC counters + FIFO status + clock probes in one dump).
3. pc_tools should add a bidirectional UDP echo test script (bind a fixed port + payload check).

## Gaps and follow-ups

- Windows not delivering temporary-port UDP replies: the dropping layer was never confirmed by capture (pktmon elevated twice did not run successfully),
  the firewall state-table root cause is a hypothesis.
- OpenOCD ELF load mpsse_flush hang: root cause unknown (tap/examine/soft_reset_halt/register reads are all normal,
  only the load_image stage stalls), contradicting the 11-05 success record; reproduction conditions still to be analyzed.
- G5 (UART-configurable IP/MAC), G6 (≥900Mbps stress) still to be done; G7 extra items (ping control-plane coexistence + 10min viewer)
  still to be done.
- The diagnostic [stat] print (every 2s) is kept in the firmware and can go back to 8s when it becomes too much.
- The DAYLOG 2026-11-06 entry has been supplemented.

## 2026-11-06 follow-up: G5 PASS (UART command line runtime-configurable IP/MAC)

- Implementation: net_config_set_ip/mac/gw/mask + **net_config_apply()** (synchronously updates the MAC_ADDR_LO/HI
  filter registers + pattern source registers 0x218/0x21c/0x224); main.c adds a non-blocking UART command line
  CmdPoll() (ip/mac/gw/mask/show/help, 64B line buffer, echo+backspace), hooked into the network service main loop;
  ICMP/ARP/tick frames all read g_net_cfg (volatile). Firmware RAM 18KB/32KB (55%).
  Rebuild firmware → binGen embed → full compile → ftdi_pgm download.
- Acceptance (evidence/g5_uart_cfg_ip_mac.txt):
  - `ip 10.0.0.9`: ping .9 4/4, `arp -a` dynamically learns .9; pinging the old .8 → unreachable
    (a PC-local notice, the board no longer answers the old IP, proving the ICMP target match follows the configuration) ✓
  - `mac ...c9` + `ip 10.0.0.77` (a brand-new IP forces a fresh ARP): ping .77 3/3,
    `arp -a` → `10.0.0.77 ea-e8-5e-00-60-c9 dynamic` — IP/MAC both take effect immediately,
    consistent in the three places: protocol stack / MAC filter / pattern registers ✓
  - After restoring the defaults (.8 / ...c8), ping .8 4/4 ✓
- Observation (host-side behavior): after changing the MAC, if the ARP cache has not aged out, `arp -a` still shows the old MAC
  (the PC sends ICMP straight from the cache without re-ARPing); to verify that a MAC change took effect, use a brand-new IP to force a fresh ARP.
- No RTL changes; this case's gate coverage update is **G1–G5 all PASS**.

## 2026-11-06 follow-up 2: G7 video stream real-time display (the user asked to "show it")

- Background: the G7 board-level acceptance (2026-11-05) only did the test_raw10_rx.py pixel-level comparison (headless), and the user asked for the
  picture to actually be displayed. Firmware switched back to TEST_MODE=0 + PAT_TYPE=2 (the known G7 configuration, RAM 34.9%), rebuild
  → binGen embed → full compile → ftdi_pgm download.
- viewer session (raw10_viewer.py, BGGB, white balance gains all 1.0):
  - Screenshot OSD: **fps 29.0 / frame 954 / lost 0 / 626 Mbps / pkts 2796966** (bandwidth consistent with the
    622.1Mbps of the G7 headless acceptance, 30fps met, zero dropped frames)
  - Session summary: frames=1565 lost=0 last_fn=1798 pkts=2798885 (the viewer bound ~7.8s after the stream started,
    so the first 233 frames not being picked up is normal; zero dropped frames during viewing)
  - Picture content: the udp_pat_gen_v2 synthetic pattern rendered by demosaic into vertical color bars (a synthetic test pattern,
    not a real camera image); the user took 2 keypress screenshots
- Evidence: evidence/g7_viewer_frame_000000.png (f1fad57a…2acf),
  evidence/g7_viewer_frame_000001.png (10c77bf7…e05a); the originals are in doc/pc_tools/.
- Current board state: RAW10 stream mode (TEST_MODE=0) sending continuously; switching back to the G3–G5 network service mode requires
  setting TEST_MODE back to 2 and rebuilding onto the board (a firmware macro, not a runtime command).

## 2026-11-06 follow-up 3: G7 extra items closeout — control plane and stream coexist PASS + pattern generator v3

**Observation (user-driven)**: confirming that the future camera is RGGB → the pixel formula changed to a display-friendly pattern (RTL 4
modes: vertical color bars/horizontal grayscale/vertical grayscale/checkerboard, CSR 0x208 bit[4:3]), and the viewer gained a menu (select/cycle
/screenshot/exit). The user then reported that switching had no effect, and Wireshark captured a 11664B giant UDP packet
(11664=8×1458, exactly 8 standard pattern packets glued together — hard evidence of frame splicing).

**Hypothesis→evidence chain (three compile rounds)**:
1. viewer key routing bug: in the selecting state the digit keys were stolen by the main menu hotkeys → fixed the routing priority
   (the viewer session log confirms all 12 commands were sent correctly).
2. ARP replies in pattern mode cannot get onto the wire: the TX mux points at the pattern generator, sw frames in the FIFO cannot reach the MAC
   (UART has "reply sent", the PC ARP table is empty, the control UDP was not sent — a three-layer evidence loop).
3. mux injection iterations: v1 mid-frame switching → giant-frame splicing drops; v2 S_IDLE wait fails (the CSR
   address was mistakenly written as +0x093, an undefined address reads back as constant 0 → the polling spins forever on a false wait); v3 address corrected
   (+0x24C, same source as the PatGen PROBE) → injection succeeds.
   Lesson: RTL register names ≠ firmware address mapping; an undefined CSR reading constant 0 silently turns a wait into a busy-spin.

**Board-level validation (v3 on the board, PC+UART evidence on both sides)**:
- ARP coexistence: arp -a restores dynamic learning (ea-e8-5e-00-60-c8); 2 ARP injections during the stream
- ICMP coexistence: ping 3/5 (TTL=64; UART reply sent ×4 → 1 packet lost + 1 reply race,
  survival rate about 80%, listed as a known item for improvement)
- Menu loop: viewer 12 commands (4 manual selections + 8 cycles) map 12:12 to UART PAT MODE
- Stream integrity: viewer **1950 frames lost=0** throughout (including 2 ARP injection interleavings) — S_IDLE
  window injection does zero damage to the video stream; the giant glued packets have not reappeared after v3
- Pattern generator v3 (4 patterns + RGGB phase) displays correctly on the board, the user confirmed "displays correctly, as expected"

**Evidence**: evidence/g7x_uart_patmode_transcript.txt (UART+viewer transcript; the original log was cleaned up when the
listening window closed, the transcript is kept line by line within the session). The firmware main.c (S_IDLE injection version) and
this shift's bit new SHA256 have been updated in the evidence table below.

## 2026-11-06 evening 2: G6 PASS (throughput 951 Mbps; 0.015% packet loss attributed to the PC receive side, user confirmed closing)

**Changes**: zero RTL changes (v2 inc mode is naturally line rate); firmware macros PAT_TYPE 2→0, PAT_DLEN
1458, PAT_IPG 12, PAT_NUM=0; new PC tool doc/pc_tools/test_udp_thr.py.

**Payload regularity (decoded empirically)**: a UDP socket shows no IP header, but the v2 inc payload is a mod-256 incrementing
stream continuous across packets, advancing 1466 per packet (1458+8 meta jump) → the packet order can be recovered from the first payload
byte, so loss detection does not depend on the IP ID. Cross-validated on 3 packets on the board.

**Three 60s stress runs (same board, same bit)**:
| Run | Receive implementation | Throughput | Packet loss | badpay |
|---|---|---|---|---|
| 1 | per-packet on-the-fly template (bug: dragged down the receiver → 15k pps, data invalid) | - | - | - |
| 2 | precompiled template memcmp | 951.5 Mbps / 81.6k pps | 23 events ~609 packets (0.0125%) | 0 |
| 3 | recv_into + GC disabled | 951.2 Mbps | 28 events ~762 packets (0.0156%) | 0 |
| 4 | + HIGH_PRIORITY_CLASS | 951.3 Mbps | 28 events ~742 packets (0.0152%) | 0 |

**Attribution analysis (the evidence chain that clears the board side)**:
- Throughput stable at 951.x ≈ the theoretical ceiling (measured on-wire frame 1508B: 1458/12.224µs = 953.7Mbps theoretical,
  99.7% efficiency; 81.6k pps matches the 12.224µs frame period)
- Every received packet payload is error-free (any FPGA-side FIFO/timing fault would corrupt bytes rather than silently dropping whole packets)
- The FPGA TX path pattern FSM→mux3→MAC is an all-hardware same-clock direct connection with no FIFO that can overflow — what leaves
  on the wire arrives, so no board-side packet-loss mechanism exists architecturally
- The losses are randomly distributed at second scale and synchronized with a slight dip in the per-second rate (~80.9k vs 81.6k, ≈2.4ms stall);
  ±12% run-to-run fluctuation — typical host-side characteristics; ReceivedPacketErrors=0 (USB NIC counters have
  limited reliability)
- PC NIC = ASIX AX88179 USB3.0 gigabit (USB microframe 125µs budget + driver ring queue),
  32MB SO_RCVBUF rules out socket queue overflow → the drops are at the NIC/driver layer, unobservable by the application layer

**Final verdict (the user chose "accept the attribution and close")**: G6 **PASS** — throughput 951.2–951.5 Mbps
(≥900, i.e. 99.7% of the 953.7 theoretical) + byte-for-byte zero-error payload met; "zero packet loss" was not achieved in this environment
due to the PC-side USB gigabit NIC (ASIX AX88179) receive stack limit (0.012–0.016%, 609/762/742 packets over three runs),
attributed with the limitation noted: the FPGA TX all-hardware direct path has no loss mechanism, received packets have
zero byte corruption, and losses are synchronized with host scheduling stalls. For a strict zero-loss re-test later, a PCIe NIC
(Intel i210/i225 class) is recommended.

## 2026-11-06 evening 3: PC runtime mode switching (t/v/pattern board-level PASS; n mode sw-TX dead path awaiting evidence)

**Requirement (user question "can the test mode be changed from the PC? → choose to implement it now")**: UDP 10006 switches instantly between
t (inc line-rate stream)/v (RAW10)/n (network service)/s (restore the previous stream)/0-3 (display pattern),
saving a ~2-3 minute full compile and download every time.

**Implementation**:
- The only RTL change — pat_gen_kill (CSR 0x208 bit3): an RTL audit found that the inc infinite-stream
  FSM never returns to S_IDLE and pat_en does not gate tvalid, so dropping en does not stop the stream → there was no software stop
  mechanism at all, so a kill bit had to be added. Level-latched kill_r, a clean return to S_IDLE at the current packet's tlast boundary,
  start_pulse clears it automatically, pat_en goes out after the stop. lint 0 errors 0 warnings; tb_udp_v2 regression +
  tb_udp_v2_kill three targeted segments (kill mid-stream stops / restart after kill / RAW10 frame_tick
  does not re-ignite) ALL PASSED.
- Unified firmware application: TEST_MODE only decides the boot initial state, everything else is switched at runtime by UDP commands;
  PatGen parameterized (g_pat_type_rt); AppRun merges the stream and network service states. **inc-mode injection
  fix**: the evening-3 first version reused the v3 S_IDLE wait injection, which must time out at the inc line rate (IPG=96ns)
  → a bare mid-frame switch spliced the ARP reply into a giant frame that got dropped → the PC could not learn ARP → control plane dead
  (UART confirmed the board executed all 5 injections but the PC received none); after switching to kill-at-packet-boundary stop injection
  (stop ≤12.2µs → mux→sw direct send → PatGen restart) ping recovered.
- PC tools: mode_ctrl.py (an explicit bind of 10.0.0.3 fails loudly, preventing the double-NIC silent fallback
  route to the unconnected ASIX), uart_dump.py (UART capture + dump to disk).

**Correction of the on-board NIC facts (user interrupted: "10.0.0.3 went offline, do it again")**: the NIC connected
to the board is actually "Ethernet 6" (Realtek USB GbE #3, 10.0.0.3, 1Gbps); "Ethernet 5" (ASIX
AX88179, 10.0.0.2) is not connected to the board. **The NIC model in the evening-2 attribution is corrected from ASIX to Realtek**
(the "PC-side USB NIC receive stack limit" conclusion is unchanged). A one-off 0-packet/all-ping-failed event that evening
is attributed to a brief 10.0.0.3 NIC dropout (user report + normal service immediately after recovery), not a board-side fault.

**Board-level acceptance (PC+UART both sides, unified application version bit)**:
| Command | Result |
|---|---|
| boot default | inc line-rate stream 951.4–952.5 Mbps ✓ |
| t | inc line-rate stream 950.3 Mbps, zero payload errors ✓ |
| v | RAW10 30.00fps / 622.1Mbps / 0 dropped frames / 5-frame pixel comparison PASS ✓ |
| 2 | pattern 2 pixel comparison PASS ✓ |
| ping (mid-stream) | after kill-stop injection ping 2/2 + ARP dynamic learning ea-e8-5e-00-60-c8 ✓ |
| n | stream stops + main loop alive + RX frames received ✓, but **sw-TX dead path** ✗ |
| s | not tested that evening; supplemented in evening 4 the next evening, all PASS (see the next section) |

**sw-TX dead path (observation, unresolved)**: under netsvc MacTxSend writes 0x24C (the TX FIFO data port)
but wrcnt stays 0, TXOK=0, TXSTAT=0x100fff (free=4095 empty, bit13 full=0,
bits[22:14] dbg=0x40=infinite_en — all readings "healthy" and semantically self-consistent), MUX=0x10 correct,
CFG208=0x0 (stream stopped), main loop alive, **reproduces on the first n after a clean boot** (ruling out state pollution).
Excluded: reg_apb3 'h093 write-decode damage, tx_status readback corruption. Conclusion: the write
strobe is silently discarded by the TX DC_FIFO. The 11-02 silicon-level defect family (free/full 13-bit arithmetic synthesis sensitivity) is a
**hypothesis**, but the self-consistent readings make a simple recurrence explanation untenable. Evidence path (already written into the DAYLOG):
tb_reg_pkt replays the CPU write sequence to separate RTL from silicon → map.v cross-check of 'h093 wr_en→
DC_FIFO WrEn cone.

**Evidence boundary**: stream-to-stream switching (t/v/pattern/ping) is board-level measured PASS; n mode RX side is board-level
measured, TX side FAIL (dead path); s untested; the sw-TX dead path root cause is not located (the evidence plan is listed).
Current board state: after the OpenOCD probe resumes, the firmware returns to the boot state = inc line-rate stream.

## 2026-11-06 evening 4: s supplementary test all PASS + netsvc escape path + USB slot environment event

**Environment event (user report "I changed the USB NIC slot, switching it back to the original")**: during the USB 2.0 slot period there was a
chain of false impressions — throughput crushed to 342 Mbps (the USB2 effective ceiling), ping/ICMP small frames all lost,
mode_ctrl "sent" succeeded but the command never got onto the wire (connectionless UDP silently dropped, zero board-side UART
prints). Switching back to the original USB 3.0 slot immediately restored 951 Mbps. Lesson: for throughput anomalies check the PC-side
USB topology first; the board-side UART MODE REQ print is the only authoritative evidence that a command arrived. Evening 3's
"MODE -> raw10 print missing mystery" thus gains a new explanatory direction (at the time both command delivery and print capture
were disturbed by the same environment).

**JTAG reconfiguration escape + boot state observation**: the dead path + PC ARP table ageing left the UDP control plane one-way
locked → ftdi_pgm -m jtag re-download of the unified application version bit as an escape (Device ID 0x00690A79).
Observation: after reconfiguration the board was measured to be on the RAW10 stream (frame number 10165≈5.6min, raw10 all items PASS), inconsistent with the
compiled value of PAT_TYPE=0 (inc boot), origin undetermined (suspected a delayed v command from the USB2 period), the whole chain is
self-consistent afterwards, not investigated further.

**s supplementary test full sequence (PC+UART both sides, doc/pc_tools/uart_s_test.txt archived 02499567…ed4e)**:
| Step | PC side | Board-side UART |
|---|---|---|
| RAW10 baseline | 30.00fps/622.1Mbps/0 dropped frames/pixel PASS | - |
| s (during RAW10) | frame number 11148.. no interruption | MODE REQ -> stream (no-op as expected) |
| t (→inc) | 951.1 Mbps/81.6k pps | MODE REQ -> thruput + MODE -> thruput stream |
| s (during inc) | 949.9 Mbps maintained | MODE REQ -> stream (no-op) |
| n (→netsvc) | ping 2/2 lost (dead path reproduced) | MODE -> net service + [stat] tx=0 + ICMP reply sent×2 |
| s (netsvc escape) | **951.2 Mbps stream restored** | MODE REQ -> stream + MODE -> thruput stream |
| v (wrap-up) | - | MODE -> raw10 stream |

**Correction of the sw-TX dead path's scope of impact (important)**: the board-side hard evidence loop — under netsvc the rx counter increments
(rx=0→1→2, all requests arrive) + "ICMP: echo reply sent"×2 + **[stat] tx=00000000**
(MAC TXOK zero) → the reply CPU side says "sent" but the MAC TX counter does not move, so the write being swallowed is confirmed on the board.
**The dead path only locks the board→PC direction** (tick/ARP replies/echo); while the PC ARP table is intact, UDP commands
(PC→board) arrive as usual, as the s escape proves. The condition for fully locking the control plane = netsvc dead path + the PC ARP
table lacking the board MAC (after ageing) → the only escape = power cycle / JTAG reconfiguration. Usability conclusion: n mode
to be fixed (evidence path unchanged: tb_reg_pkt replay → map.v 'h093→WrEn cone); the full stream mode set
(t/v/s/0-3/ping mid-stream) is usable. Current board state: RAW10 video stream sending continuously.

## 2026-11-06 evening 5: sw-TX dead path root cause settled + syn_keep fix board-level acceptance PASS (dead path closed)

**Step one, tb_sw_path replay (separating RTL from silicon)**: rebuilt the Questa project (work_kill library), the
current RTL (including pat_gen_kill) **PASS: aFramesTxOK=3 / tx_beat=318 / ctl_frames=3 /
TX_STATUS=0x00000fff** — sw frame→'h093→TX FIFO→mux3→MAC→RGMII the whole chain consumes 3/3 frames,
so the RTL layer is completely healthy and the dead path is silicon-level.

**Step two, map.v netlist evidence (u_eth_pkt_fifo/u_tx_fifo)**: decoding the write-port cone LUTMASK one by one
(efx_lut4.v authoritative semantics) confirms n46=~full & loc_wr_vld & 'h093 matching is **completely correct**;
root cause = the DC_FIFO reset handshake `WrClkRstGen[1] <= &RdClkRstGen` whose two [1] FFs are
**resolved by map into undriven wires** ([1] reset-release end state constant 0 treated as a dead register; the identical FF in u_rx_fifo is
kept — inconsistent synthesis handling), while all downstream registers have SR set to **SR_POLARITY=1'b0 (active low,
efx_ff.v L67 semantics sr_int=~SR)** connected straight to that wire → on silicon it is a constant asynchronous reset: FullFlag constant 0,
FifoWrAddr constant 0, wrcnt constant 0, free constant 4095, read domain constantly empty → TX sends nothing. All board readings
match 100%. Characterization: **an Efinity map silicon-level defect, a close relative of the 11-02 defect family**.

**Fix**: add `(* syn_keep = "true" *)` to both handshake regs in rtl/DaulClkFifo.v (logically
identity). tb_sw_path regression PASS → full compile 5 steps PASS → the new netlist confirms both FFs are driven again
(L43537/L43547) → JTAG download and board verification.

**Board-level acceptance (fix version bit 4eba25c1…6c78e, PC+UART both sides, uart_fix_test.txt
60d10370…8688)**:
| Item | PC side | Board side |
|---|---|---|
| boot inc stream | 950.7 Mbps ✓ | - |
| ping mid-stream | 3/3 0% ✓ | ARP reply sent ✓ |
| n → netsvc ping | **5/5 0%** (2/2 all lost before the fix) ✓ | **[stat] tx=0x04→…→0x28 monotonically increasing** (constant 0 before the fix) + ICMP reply sent ×5 ✓ |
| n → tick | 5 packets/5s = 1Hz ✓ | tx counter stepping at 1Hz ✓ |
| s → restore stream | 948.6 Mbps ✓ | MODE -> thruput stream ✓ |

**The sw-TX dead path is formally closed**: runtime mode switching t/v/n/s/0-3 is fully usable, with no known remaining
defects. SDK candidate: DC_FIFO usage should check netlist handshake FF existence or ship a syn_keep
template (resolution + active-low SR constant reset is a systematic risk pattern). Current board state: RAW10 video stream.

<!-- evoverse-project-review:evidence
{"hardwareStatus":"PASS_G1-G7_GATES_PLUS_RUNTIME_MODE_SWITCH_ALL_MODES_t/v/n/s/pattern_swTX_DEADLOCK_ROOT_CAUSED_AND_FIXED_syn_keep","evidence":[
{"category":"board_validation","path":"doc/pc_tools/uart_fix_test.txt","digest":"60d10370c86a7e27380bb10a88728bdfda0ddd323cf1a89234365d535a028688","note":"Evening 5: UART archive of the fix-version board test ([stat] tx monotonically increasing + ICMP/ARP reply sent + tick + s restore)"},
{"category":"rtl_source","path":"rtl/DaulClkFifo.v","digest":"32b59b156c48c674ba531f67441bc0fc63373fddba0671a4efe103dbcaf8a8ce","note":"Evening 5 fix: syn_keep added to the DC_FIFO reset handshake FFs (logically identity); previously the original Efinity elaborated source"},
{"category":"simulation","path":"sim/tb_sw_path.v","digest":"0bb7ba5fecce022735ba59f86956d7e9100ded9a5b2ab0938160de3b1a9b4c1d","note":"Evening 5: RTL-vs-silicon discrimination replay TB, 3/3 frames consumed PASS (work_kill Questa library)"},
{"category":"board_validation","path":"doc/pc_tools/uart_s_test.txt","digest":"02499567029e584836133e6d366167c07919f7311b4d8209b360aa7b33efed4e","note":"Evening 4: board-side UART archive of the whole s supplementary test (full MODE REQ/MODE sequence + netsvc [stat] tx=0 hard evidence of the dead path + s escape prints)"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g3_ping_arp_dynamic.txt","digest":"fa6f552e1c2519d735fdf4441810a5394d74e91a8f82bbee3c44dc191fe9de1c"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g4_ping_100_0loss.txt","digest":"99b5b85e6628a587a84ffb3e9e8937907d266e5310cce5c2a62177317590582c"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g1_udp_echo_10005.txt","digest":"45df5867727ec77e4c1f81411fbf22e007749aeb1c34caa80ff81d55d7a89e5f"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/rx_diag_before_fix.txt","digest":"3e6f74c6a0599f96b6d0b069a1f917d148b23bf460bceb598955811c8ecb3905"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/uart_after_fix_summary.txt","digest":"98b48a8f7bb3d6ccbda44f3895b5a157010b28715235a198e2128bd09b9699f6"},
{"category":"firmware_source","path":"embedded_sw/sapphire/software/standalone/driver/yt8531fd.h","digest":"e9e6d0b528c85e2634d6ca1967554d13929c1eacb7d496429cba73f8bbe50bdb"},
{"category":"firmware_source","path":"embedded_sw/sapphire/software/standalone/tseDemo/src/main.c","digest":"6b173135b336abe6c81073dd9375001bacc25c45b64bf130731aa18bf8949110","note":"2026-11-06 evening 3 unified-application version: AppRun merged + kill-stop injection + t/v/n/s runtime switching; history: v3 S_IDLE injection version a3ad558d…, G3/G4 version 59ec70e2…"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g5_uart_cfg_ip_mac.txt","digest":"a8f2b9af3d57c9cfe60e728e065aa4354f62b814e77599f1e86cb99f3eee3ce5"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g7_viewer_frame_000000.png","digest":"f1fad57a03dbffb799c4c03298353fb41256695f26428a2030f90889a5252acf"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g7_viewer_frame_000001.png","digest":"10c77bf7327d2961de4e485b67902edf0c13b09596a9e2a23520bec013ffe05a"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g7x_uart_patmode_transcript.txt","digest":"5c140e49f692893673f71c68b4d20201122d0f9550c46d7a18884bcd1e6657bf","note":"Transcript (the original log was cleaned up with the window); PAT MODE 12:12 correspondence + lost=0"},
{"category":"rtl_source","path":"rtl/udp_pat_gen_v2.v","digest":"a6d968f16b36881273245962f0829bff345eb0fe138200d8730544363dceccfa","note":"2026-11-06 evening 3 kill version: pat_gen_kill packet-boundary stop + pat_en shut off; history: v3 pattern version aaf2dec9…"},
{"category":"rtl_source","path":"rtl/reg_apb3.v","digest":"e8992690eb89ffac5cf354607e116e86dbc0d800932c2f8743d9cd12814c4fac","note":"Evening 3: added 0x208 bit3 pat_gen_kill read/write"},
{"category":"rtl_source","path":"rtl/ws_e1_tse.v","digest":"3f023fdec1aa090d936d1617752890cf7c89dbb128fca81dcbea57df8fd458ad","note":"Evening 3: pat_gen_kill wiring (reg_apb3 → udp_pat_gen_v2)"},
{"category":"simulation","path":"sim/tb_udp_v2_kill.v","digest":"ac48b574ab5e13274a0430530e04a6dc08a82d4a65e9e5cf25f26692afdb378a","note":"kill-targeted TB: stop mid-stream / restart / RAW10 frame_tick does not re-ignite, ALL PASSED"},
{"category":"pc_tool","path":"doc/pc_tools/mode_ctrl.py","digest":"18ebac8f5b2db1edfb03ac1a04bf662adb2ae91c8139b74733c16e3d5425225f","note":"Evening 3: UDP 10006 runtime mode control (t/v/n/s/0-3), explicit bind 10.0.0.3"},
{"category":"pc_tool","path":"doc/pc_tools/uart_dump.py","digest":"0cc48c5602a346c1e0be57b6d3eff19385a271355d2f3590ef89d87f1119d6f0","note":"Evening 3: UART capture of prints + dump to disk"},
{"category":"bitstream","path":"outflow/ws_e1_tse.bit","digest":"4eba25c1df93736ba73453c44b1398777637217fab495b17f4323f3f1436c78e","note":"2026-11-06 evening 5 dead-path fix version (DaulClkFifo syn_keep); overwritten by this version: evening 3 unified-application version 75994359…, G6 version 7cc2c09c…, G7x pattern v3 version ca49ea67…, G3/G4 version 95407a37…"},
{"category":"firmware_source","path":"embedded_sw/sapphire/bsp/efinix/EfxSapphireSoc/app/tseDemo.h","digest":"e2571fe47640fbceefdae3bfbbfe514845625ddb21e641140240625c0a04f3b6","note":"Evening 3: TEST_MODE comment changed to the unified-application semantics (boot initial state); G6 version cc293572…"},
{"category":"pc_tool","path":"doc/pc_tools/test_udp_thr.py","digest":"7c9c922c600907984d8689f9467f60bd392ffb66892df501ba2e46e5066803b1","note":"G6 receive side: 1466-step sequence recovery for loss detection + 256 precompiled templates + recv_into + high priority"}
]}
-->
