[中文](udp_plan.md) | English
# ws_e1_tse UDP enhancement: receive path / ARP+ICMP / gigabit throughput implementation plan

> Engineering baseline: ws_e1_tse (TJ180A484S / C4, mytse 7.3 + myriscv); current on-board validation status:
> UDP one-way transmit 13k~23k pps @100B payload, no receive path, ARP/ICMP not implemented.
> **Final application goal: transport a 1080p RAW10 @30fps video stream over UDP (the stage 3 pattern is designed for exactly this).**
> This plan has 3 stages, each independently acceptable, and the order cannot be reversed (dependencies in §4.0).

---

## 1. Goals and acceptance criteria

| # | Goal | Acceptance criteria |
|---|------|---------|
| G1 | PC→board receive path | Firmware fully receives any frame sent by the PC (frame header printed over UART / payload read-back identical) |
| G2 | Software transmit path | Firmware can put any assembled frame onto the wire (visible in a PC capture) |
| G3 | ARP | Before `ping 10.0.0.8`, the PC's `arp -a` learns the board MAC (answers ARP requests) |
| G4 | ICMP | `ping 10.0.0.8` works, 0% packet loss (64B standard payload, ≥100 packets) |
| G5 | Software-configurable IP/MAC | IP/MAC changed over the UART command line take effect immediately (consistent in all three places: ARP/ICMP/pattern), no firmware rebuild needed |
| G6 | Gigabit throughput | UDP payload throughput ≥ **900 Mbps** (1500B frames, PC iperf-style stress for 60s, 0 packet loss, payload check passes) |
| G7 | **1080p RAW10 @30fps pattern stream** | RAW10-packed 1080p pattern video stream sent continuously: 30.00 frames/s ±0.1, PC-side per-pixel check against the pattern formula passes, frame numbers contiguous with no dropped frames, measured payload bandwidth ≈ 622 Mbps steady |

**Note on the physical ceiling of G6**: UDP payload bandwidth on a gigabit link has a
protocol-overhead ceiling; 1000 Mbps of user payload is physically unreachable:

```
wire rate 1 Gbps (includes 8B preamble + 12B IFG)
1500B frames: payload share = (1500-42)/(1500+20) ≈ 94.8% → ceiling ≈ 948 Mbps
64B  frames: payload share = (64-42)/(64+20)   ≈ 26.2% → ceiling ≈ 262 Mbps
```

So G6 uses 1500B frames ≥900 Mbps (≥95% of the theoretical ceiling) as the pass line.

> **Gate status 2026-11-06 (closeout)**: G1–G7 **all PASS**. G1/G2/G3/G4 board-level acceptance
> (ARP dynamic learning, ICMP 100 packets 0% loss, UDP echo 4/4); G5 PASS (UART runtime-configurable
> IP/MAC); G6 PASS (951.2–951.5 Mbps ≥900 pass, zero payload errors; the 0.012–0.016% packet loss
> is attributed to the PC-side USB gigabit NIC receive stack, the user confirmed closing it — the
> board-side TX is an all-hardware direct connection with no packet-loss mechanism in place,
> a strict 0-loss re-test requires a PCIe NIC); G7 PASS (RAW10 30fps zero dropped frames) + extra items closed out
> (S_IDLE mux injection so that the ping/ARP control plane coexists with the stream, 4 patterns + viewer menu).
> See project-review/2026-11-06-g3-g4-arp-icmp/ and DAYLOG/2026-11.md.
> First bring-up of the RX path on the board once lost everything because the yt8531 rgmii-id
> configuration was overwritten; that has been cured at the root (see the
> 2026-11-06 review).

---

## 2. Current state and bottleneck analysis

### 2.1 Data path as it stands

```
TX: udp_pat_gen ─┐
     mac_pat_gen ┴─[pat_mux]─[tx_mux]─→ mytse TX ─→ RGMII
                 rx2tx loopback ──┘
RX: RGMII ─→ mytse RX ─→ rx_axis ─→ loopback FIFO only (the CPU has no path at all)
```

### 2.2 Throughput bottleneck (measured 13k~23k pps vs gigabit line rate ~814k pps@100B)

| Bottleneck | Location | Magnitude |
|------|------|------|
| AXI-Stream clock 50MHz | ws_e1_tse.v L194-195 (an official-example compromise: pat_gen combinational logic does not close timing at 125M) | ceiling 400Mbps |
| Serial checksum computation | udp_pat_gen.v L138-148, UDP_CHKSUM loops over each 16bit (about 60 cycles for a 100B payload) + IP_CHKSUM 10 cycles, repeated per packet | ~70+ cycles per packet |
| Software IPG | pat_gen_ipg=100 cycles (configurable, but too small hits the pat_gen state machine margin) | 100 cycles per packet |
| 42B header combinational decode | udp_pat_gen.v L432-485 case(pat_cnt[5:0]) emitted in the same cycle | the root of the timing pressure |

### 2.3 Functional gaps

- No receive path (zero path between the CPU and the RX data stream)
- reg_apb3 address space still has free slots (loc_addr 0x08D~0x0FF, paddr[9]=1 upper half)
- TX mux is 2:1 only (pattern / loopback), there is no "software frame" entry

---

## 3. Overall architecture (target state)

```
                 ┌──────────── 125MHz domain ────────────┐
 udp_pat_gen_v2 ─┐                                     │
  (pipeline + closed-form checksum) │                  mytse TX ←──┘
                   ├─[tx_mux 3:1]───────────────→ (pat / software frame / loopback)
 sw_tx_fifo ─────┤                                     │
  (APB 50M writes)  │                                  │
 rx2tx loopback ─┘                                     │
                                                       │
 APB 50M domain CPU ←─[rx_pkt_fifo CDC]←── rx_axis(125M) ┘
      │
      ├─ poll frames → ARP/ICMP reply (software stack) → sw_tx_fifo send
      └─ net_config_t (IP/MAC software-configurable, UART command line) → drives ARP/ICMP/pattern registers uniformly
```

Key decisions:
- **Separate data plane and control plane**: the gigabit data stream goes through hardware
  direct paths (pattern, or DMA in the future), while ARP/ICMP/configuration use the CPU
  software path (APB polling throughput is ~MBs level, enough for small-packet control plane,
  and can never carry the gigabit data plane — this is an architectural constraint, not an
  optimization item)
- **Raise AXI-Stream to 125MHz** (stage 3), rx_axis_clk uses the rx_mac_aclk output by mytse
  (recovered clock), tx_axis_clk uses clk_125m (same PLL source with a 90° shift)
- Keep the mytse IP at AXIS_DW=8 without regenerating it (if higher demands remain after stage 3, evaluate 32bit, see §6)

---

## 4. Stage plan

### 4.0 Dependencies

```
Stage 1 (TX/RX path) ──→ Stage 2 (ARP/ICMP + configurable IP) ──→ Stage 3 (gigabit throughput)
     mostly hardware              pure software                    mostly hardware
```

Stages 1 and 3 both touch RTL, but stage 1 deliberately leaves pat_gen/clock domains alone
(keeping the 50M baseline) so that stage 2 has a stable software debugging platform; the
stage 3 throughput rework does not change the CPU path structure from stage 1.

---

### Stage 1: receive path + software transmit path (G1, G2)

**Files changed**: `rtl/reg_apb3.v` (extended), `rtl/ws_e1_tse.v` (wiring), new `rtl/eth_pkt_fifo.v`,
firmware `efx_tse_mac.c/h` (new API), `tseDemo.c`

**Hardware design**:

1. New module `eth_pkt_fifo` (reuses the existing DaulClkFifo for CDC):
   - RX side: `rx_axis (50M domain as it stands)` → `{tuser,tlast,tdata}` 10bit wide CDC FIFO (depth 4K)
   - TX side: APB writes 10bit words → CDC FIFO → AXI-Stream master interface
2. New reg_apb3 registers (from loc_addr 0x090, paddr from 0x240):

| loc_addr | paddr | Name | R/W | Bit definition |
|----------|-------|------|-------|--------|
| 0x090 | 0x240 | RX_STATUS | R | [10:0] RX FIFO word count; [11] overflow flag (write 1 to clear); [12] frame in progress |
| 0x091 | 0x244 | RX_DATA | R | [7:0] data; [8] tlast; [9] tuser (read pops) |
| 0x092 | 0x248 | TX_STATUS | R | [10:0] TX FIFO free space; [11] full |
| 0x093 | 0x24C | TX_DATA | W | [7:0] data; [8] tlast (write pushes) |

3. TX mux 2:1 → 3:1: extend `axi4_st_mux` or add `axi4_st_mux3`;
   the mux control bit goes into reg_apb3 (0x081 register extension bit[2]), software frames have the highest priority
4. RX FIFO overflow policy (revised 2026-11-02 per TSEMAC UG v6.3): the UG states explicitly that
   rx_axis_mac_tready backpressure is not supported (pulling it low mid-frame silently corrupts the frame), so tready is tied to 1;
   overflow protection becomes frame-granular admission — at SOF, if the free space is less than FRAME_GUARD (1536 words) the whole frame
   is dropped and a sticky flag is set (toggle synchronized into the APB domain); the FIFO then only ever holds complete frames, and software writes 1 to clear the flag.
   The mac_rx2tx hardware loopback is reworked under the same rule (the 2048-deep FIFO's old threshold backpressure is bound to corrupt frames under back-to-back frames)

**Firmware API** (`efx_tse_mac.c`):

```c
int  mac_rx_poll(uint8_t *buf, int maxlen);   // receive one whole frame (poll RX_STATUS→RX_DATA), returns the frame length
int  mac_tx_send(const uint8_t *buf, int len); // assemble a frame and write it into TX_DATA (including the tlast marker)
void mac_set_loopback(int on);                 // switch axi4_st_mux_select (loopback must be off while receiving)
```

**Acceptance**: the PC sends custom frames with scapy/python → the firmware receives the frame and prints the first 64 bytes in hex over UART →
byte-for-byte identical to what the PC sent; the firmware echoes the frame (mac_tx_send) → the PC capture content is identical.

---

### Stage 2: software ARP/ICMP + IP/MAC software-configurable (G3, G4, G5)

**Files changed**: new firmware `net_config.c/h`, `arp.c/h`, `icmp.c/h`, `eth_frame.c/h` (parsing/frame assembly/checksum),
`tseDemo.c` (main loop + UART command line); RTL untouched

**Software design**:

1. `net_config_t` (single source of truth, all protocol code only reads it):

```c
typedef struct {
    uint32_t local_ip;        // default 10.0.0.8
    uint32_t netmask;         // default 255.255.255.0 (reserved)
    uint32_t gateway_ip;      // reserved
    uint8_t  local_mac[6];    // default ea:e8:5e:00:60:c8
} net_config_t;
extern volatile net_config_t g_net_cfg;
```

2. UART command line: `ip 10.0.0.8` / `mac ea:...` / `show`; after a write, refresh the
   pattern registers (0x224/0x228/0x218) in step to guarantee consistency across the three places
3. ARP: main-loop polling → frame type 0x0806 → opcode 1 (request) and target IP==g_net_cfg.local_ip
   → assemble a reply (the hardware source MAC is taken directly from mytse, or use g_net_cfg.local_mac) and send it via mac_tx_send
4. ICMP: frame type 0x0800 → proto=1 → type=8 (echo request) and dst_ip matches →
   copy the payload, change type to 0, recompute the IP header checksum (the ICMP checksum is legal as-is when the payload is returned unchanged) → reply
5. Coexistence with pattern: ARP/ICMP replies share the TX mux with pat_gen, so switch the mux briefly before
   sending (or pause the pattern — see risk R3)

**Acceptance**: `ping 10.0.0.8 -t` works with 0 packet loss; `arp -a` shows the board MAC;
after UART `ip 10.0.0.88` and moving the PC to the same subnet, pinging the new address works.

---

### Stage 3: gigabit throughput rework (G6, G7)

**Files changed**: rewrite `rtl/udp_pat_gen.v` → `udp_pat_gen_v2.v` (keep the old version for rollback),
new `rtl/raw10_pat_gen.v` (RAW10 video pattern engine),
`rtl/ws_e1_tse.v` (clock domains), `rtl/reg_apb3.v` (control-signal CDC handshake + pattern mode select bits),
**PC-side Python toolchain `doc/pc_tools/` (uv-managed: receive statistics + real-time demosaic display)**, firmware parameter adaptation

**Hardware design points**:

1. **Clock domain migration**: `tx_axis_clk` → `clk_125m`, `rx_axis_clk` → `rx_mac_aclk` (the mytse recovered clock output).
   pat_gen, the tx mux and the RX write side of eth_pkt_fifo all move with it; APB control signals go through two-stage
   synchronization + an "update only while idle" handshake (a parameter write only takes effect once the pattern is in IDLE)
2. **Closed-form checksum to eliminate the serial loop** (key): when the payload is a fixed incrementing pattern, the
   payload part of the UDP checksum is the complement sum of an arithmetic 16bit sequence, which has a closed form — computed once
   in the header assembly stage, no per-byte loop needed; the IP checksum only depends on the header (10 terms as before). Arbitrary payloads keep a streaming interface (§6 open)
3. **Header pipeline**: split the 42B header case decode into 3~4 stages (14B ETH / 12B IP first half / 8B IP second half + 8B UDP),
   compare tlast against a precomputed frame-length register (removing the 16bit adder from the tlast combinational path)
4. **IPG fixed to the line-rate minimum**: 12 bytes of time = 96 cycles (8bit@125M), the register can still be raised
5. **Timing closure verification**: pnr target 0 violation in the 125M domain; critical paths are expected in the header pipeline
   stage-to-stage and the checksum carry chain, and a seed sweep is reserved

**Performance budget** (1500B frames @125MHz 8bit):

```
per-frame wire time = (8 preamble + 1500 + 12 IFG) × 8ns = 12.16 μs → line rate 82.2k pps
UDP payload throughput = 1458B / 12.16μs ≈ 959 Mbps ≥ 900 ✓
pat_gen added overhead = 4 header pipeline cycles per frame (negligible)
```

**Acceptance**:
- Firmware PAT_DLEN=1458 (1500B frames) sends continuously, `doc/test_udp_rx.ps1 -Seconds 60` statistics
  ≥900 Mbps with the incrementing payload check passing and 0 packet loss
- Timing report 0 violation in the 125M domain; ARP/ping are unaffected during the throughput stress (control plane alive)

#### 3.4 RAW10 1080p@30fps pattern engine (G7)

On top of the incrementing pattern of pat_gen_v2, the payload content is replaced by a RAW10 video stream packing engine (the
`raw10_pat_gen` submodule, selected by register against the incrementing pattern, reserving the same interface for a future real image source):

**RAW10 packing format** (aligned with the MIPI CSI-2 RAW10 convention):

```
4 pixels = 5 bytes: P1[9:0] P2[9:0] P3[9:0] P4[9:0]
  → byte stream: P1[9:2] P1[1:0]+P2[7:2] P2[1:0]+P3[7:2] P3[1:0]+P4[7:2] P4[1:0]
1920 px per line = 480 groups × 5B = 2400 B; 1080 lines per frame = 2,592,000 B ≈ 2.47 MB
```

**UDP carriage and framing**:

```
payload per packet = 8B metadata header + 1450B RAW10 data (1500B frames)
metadata: frame number 32bit + byte offset within the frame 32bit (the basis for receiver-side rebuild/check/dropped-frame statistics)
packets per frame = ceil(2592000/1450) = 1788 packets
packet rate   = 1788 × 30 ≈ 53.6k pps (< line rate 82.2k pps @1500B, 65% of it)
```

**Bandwidth and frame rate accounting**:

```
RAW10 pixel bandwidth   = 1920×1080×30×10bit = 622.08 Mbps
UDP payload per frame    = 2,592,000B data + 1788×8B metadata = 2,606,304B
30fps payload bandwidth   = 2,606,304 × 8 × 30 ≈ 625.5 Mbps < gigabit ceiling 948 Mbps (66%) ✓
per-frame transmit time     = 2,606,304 × 8ns×8bit/line rate → at 959 Mbps line rate only ≈ 21.7ms
frame period 33.33ms, duty cycle 65%; the remaining ≈11.6ms is the inter-frame gap (the natural margin for the frame count to align at 30.00fps)
```

**Pattern definition** (deterministic, verifiable per pixel on the PC):

```
pixel(row, col) = (row×1920 + col) mod 1024   // 10bit sawtooth, independent of the frame number within a frame
the frame number increments with the UDP metadata; the PC check script compares every pixel with the same formula
```

**Acceptance (G7)**: ≥300 consecutive frames (10s): PC-side script checks — frame numbers contiguous (dropped frames=0),
per-packet metadata offsets strictly increasing, sampled full-pixel comparison passes, measured frame rate 30.00±0.1 fps,
payload bandwidth 622±5 Mbps; ping stays up throughout (control plane coexistence).

**Interface to a future real image source**: `raw10_pat_gen` presents externally as an "AXI-Stream payload data source",
generated internally in pattern mode; once real camera data arrives it is replaced behind the same interface (identical valid/ready backpressure),
and only the source of the UDP metadata frame number changes to the external SOF.

#### 3.5 PC-side verification toolchain: Python (uv-managed) + real-time demosaic display

Per-pixel script comparison alone makes image alignment/screen garbage hard to judge by eye, so the PC side needs a complete RAW→RGB display pipeline.
The PC already has uv installed, so dependencies and execution are managed with uv.

**Directory structure** (new):

```
doc/pc_tools/
├── pyproject.toml        # uv project: deps = numpy, opencv-python
├── raw10_viewer.py       # main tool: capture→unpack→reassemble→demosaic→real-time display
└── test_raw10_rx.py      # headless check: pure statistics (frame rate/dropped frames/per-pixel comparison), reuses the same unpack library
```

**Processing pipeline**:

```
UDP capture (53.6k pps) → strip 8B metadata (frame number/offset) → RAW10 unpack (5B→4px)
  → reassemble the frame buffer by frame number + offset (1920×1080 uint16)
  → white balance (CFA channel gains, before demosaic) → demosaic (cv2 Bayer)
  → real-time display (OSD: fps / frame number / dropped frames / bandwidth) + keypress screenshot
```

**Key implementation points**:

1. **White balance (RAW-domain channel gains before demosaic)**: in Bayer, the G channel accounts for half the pixels, so
   unless R/B are compensated the picture looks green. Multiply the four R/Gr/Gb/B channels by their gains according to CFA position:
   `raw[cfa_mask_R] = clip(raw * gain_R, 0, 1023)` (numpy masked multiply, uint16 does not overflow)
   - Gain parameters: `--wb R,Gr,Gb,B` (e.g. `--wb 2.1,1.0,1.0,1.6`), all 1.0 by default
   - At the grayscale test-pattern stage white balance degenerates to a pass-through (gain 1.0 does not change the picture);
     once a real camera is connected, use gray-world/color-chart calibration for fixed gains so the preview is not green
2. **Use OpenCV for demosaic**: `cv2.cvtColor(raw, cv2.COLOR_BayerXX2RGB)`
   - The test pattern is a grayscale sawtooth (no Bayer color), so any Bayer mode displays it and still verifies the
     pipeline and pixel alignment — misalignment/lost packets show up as tearing/garbage that the eye catches immediately
   - Once a real camera is connected, pick BGGB/RGGB etc. according to the sensor CFA layout (as a command-line parameter)
3. **Reassembly strategy**: `dict[frame number] → numpy preallocated buffer + bitmap of received offsets`;
   only complete frames are displayed, residual frames are counted and reported (dropped frames localized to a packet offset)
4. **Performance budget**: capture 53.6k pps + unpack/reassemble 2.5MB/frame×30fps — vectorized numpy unpack
   (`np.frombuffer` + bitwise reassembly, <5ms per frame); OpenCV displays 30fps 1080p with no strain,
   the capture thread and the display thread are separate (queue-decoupled, preventing GUI stalls from dropping UDP packets in the kernel)
5. **socket buffer**: raise `SO_RCVBUF` (≥8MB) to prevent burst loss; bind 10.0.0.2:10005

**How to run**:

```
cd doc\pc_tools
uv sync                                   # install dependencies the first time
uv run raw10_viewer.py --bind 10.0.0.2 --port 10005 --cfa BGGB --wb 2.1,1.0,1.0,1.6
uv run test_raw10_rx.py --seconds 10      # headless statistical check (the RAW10 counterpart of doc/test_udp_rx.ps1)
```

**Acceptance (supplementary G7)**: raw10_viewer displays continuously for 10 minutes: the picture is a stable diagonal-stripe
pattern with no garbage and no tearing, OSD frame rate 30.00±0.1, 0 dropped frames; screenshots compared against the pattern formula pass;
test_raw10_rx.py statistics agree with the viewer OSD.

**Significance for a real camera**: this toolchain is the prototype of the future PC-side debug host — after switching data sources
only the packing format stays the same, and adding image parameters (exposure/gain/white balance) and an ISP tuning panel is enough.

---

## 5. Risks and countermeasures

| # | Risk | Impact | Countermeasure |
|---|------|------|------|
| R1 | pat_gen_v2 does not close timing at 125M (precedent: v1 was dropped to 50M for exactly this) | stage 3 delay | Pipelined design + early single-module synthesis trial; keep the old 50M version for one-key rollback (the mux still points at the old version) |
| R2 | CDC errors (125M↔50M control parameters, cross-domain FIFOs) | occasional configuration failure/data corruption | FIFOs use the ready-made DaulClkFifo (already contains Gray synchronization); control signals double-synchronized + idle-period handshake; ASYNC_REG constraints |
| R3 | ARP replies contend with the pattern for the TX mux, replies drown in the pattern | ping packet loss | During a reply the firmware first pauses the pattern (write 0x082 register), then switches the mux and sends, and restores afterwards; reply latency is acceptable |
| R4 | After the receive path disables loopback, the existing loopback test function is affected | functional regression | The 3:1 mux keeps the loopback path, switched explicitly by register, old usage unchanged |
| R5 | mytse 7.3 and the firmware CSR offsets do not match (upgrade legacy) | everything from stage 1 on is blocked | Do a CSR smoke test before stage 1 starts (read/write the TX_ENA/RX_ENA bits and cross-check) |
| R6 | 8bit AXIS@125M against the CPU APB read rate (1500B frame = 375 word reads @50M APB) | software frame reception cannot keep up with line rate | The control plane only receives small ARP/ICMP packets (<100B), the data plane never crosses the CPU — architecturally avoided |
| R7 | During long RAW10 stream runs at 53.6k pps, the RX loopback FIFO is enabled by mistake or the pattern state machine stalls a frame | unstable frame rate/dropped frames | Frame count watchdog (auto-reset the engine when there is no tlast for >2 frame periods); state self-check during inter-frame gaps; PC-side frame number continuity monitoring as a backstop |

---

## 6. Open decisions (confirmed during implementation)

| # | Item | Current leaning |
|---|------|---------|
| D1 | Streaming UDP checksum for arbitrary (non-pattern) payloads | The RAW10 pattern is deterministic data, each packet's content is predictable — the checksum still uses precomputation, no streaming needed; streaming checksum will be done when truly arbitrary data (a real camera) is connected, the interface is already reserved in pat_gen_v2 |
| D2 | Regenerating mytse with AXIS_DW 8→32bit | Not doing it (8bit@125M is already enough for 1Gbps); 32bit is evaluated when moving to DMA |
| D3 | IP configuration retention across power cycles (SPI Flash config area) | First version uses RAM variables + UART commands; Flash persistence added later as needed |
| D4 | Whether the MAC source address comes from the mytse hardware or g_net_cfg | Use g_net_cfg (consistent with the configurability goal), program the mytse MAC filter registers in step |
