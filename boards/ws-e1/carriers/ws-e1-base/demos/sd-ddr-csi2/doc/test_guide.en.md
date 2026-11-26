English | [中文](test_guide.md)

# Test Guide

## Hardware Preparation

1. TJ180A484S board with JTAG + USB serial cables connected.
2. SD card (≥ 32 MB, with ~17 MB of writable space at the card tail; MBR/FAT untouched).
3. MIPI CSI-2 receiver (DPI adapter board / panel / protocol analyzer), 2-lane D-PHY, 720p60.
4. Serial terminal at 115200 8N1.

## Procedure

1. Flash the FPGA bitstream `outflow\ws-e1-sd-ddr-csi2.bit`.
2. Load the firmware `sw\top_demo\build\top_demo.elf` (Eclipse `top_demo_ti.launch`, or openocd
   `sw\bsp\openocd\flash_ti.cfg`).
3. Power on / reset and observe the UART output.

## UART Output Interpretation

### Boot Section

```
--- top_demo: SD -> DDR dual-port -> CSI-2 path test ---

Initialize...Done

Card: xxxx MByte, yyyyyy blocks, bus 4-bit
```

If the card capacity is insufficient, it prints `ERROR: card too small ...` and halts—swap the card.

### Stage 1: Frame Retention / Dual-Port Path Test (frame_path_test)

Performs SD read/write on the card-tail A/B frame areas plus bidirectional verification over DDR port0/port1, and finally prints:

```
PASS: SD -> DMA -> DDR port0 write -> DDR port1 read verified.
```

The subsequent `[5b] port1 address probe`, `[6] filled 0x00200000...` etc. are non-destructive diagnostics
(they overwrite the test-area data); refer to them only when troubleshooting—they do not affect the final verdict.

### Stage 2: 8-Pattern MIPI Stream Test (pattern_path_test)

| UART line | Meaning |
|---|---|
| `video_reader ID ok (APB1)` | VR register interface works |
| `[1/5] patterns already on card ... skip` / `no valid signature -> generate ...` | First run generates the patterns and writes them to the card (tens of seconds); later runs skip this |
| `[2/5] SD write 28800 blocks ...` | Appears on the first run only |
| `[3/5] SD read 28800 blocks -> DDR 0x2000000` | ADMA loads the patterns via port0 |
| `[4/5] CPU port0 checksum: 8/8 ok` | port0 data intact from the CPU's perspective |
| `[5/5] DDR port1 hardware checksum: 8/8 ok` | port1 data intact from the hardware read master's perspective |
| `starting MIPI CSI-2 TX stream (8 patterns x 180 frames, 3 s each)...` | Stream starts |
| `  t=0s: status=0x1 pat=0 frames=..` (one line every 2 s) | RUN-state monitoring |
| **`PASS: SD -> DDR -> MIPI CSI-2 TX streaming (check display).`** | **Final verdict** |

Meanwhile the screen should cycle through the patterns, 3 s each:

| Index | Pattern |
|---|---|
| 0 | Color bars |
| 1 | Gradient background + crosshair |
| 2 | Horizontal gradient |
| 3 | Vertical gradient |
| 4 | Solid red |
| 5 | Solid green |
| 6 | Solid blue |
| 7 | 32x32 checkerboard |

The UART `pat=` value maps one-to-one to the on-screen pattern index.

## Failure Mode Troubleshooting

| Symptom | Diagnosis |
|---|---|
| `ERROR: video_reader not found` / `P1Reader ... != 0x50315231` | Bitstream and firmware mismatch (old bitstream / wrong APB address); re-flash the matching bitstream |
| `ERROR: LBA 0x.. holds boot/FS data, abort` | The card-tail signature area holds file-system data; use another card or repartition |
| `[4/5]` (CPU verification) fails | SD read / port0 write path: check sdhost_ctrl interrupts and ADMA |
| `[5/5]` (hardware read verification) fails while [4/5] passes | port1 read path: inspect the RID/AR_DELAY/IDLE_RV reported by `P1Reader_Diag` (ghost-response signature) |
| `FAIL: video_reader stalled (status 0x..)` | No frame progress after stream start: OWN_P1 not in effect / CSI-2 TX not ready / DPHY not locked (check `dphy_tx2_STOPSTATE_*`) |
| UART PASS but no picture on the display | Receiver configuration: lane count, 720p60 timing, YUV422 format, byte order (see the pixel-format note in register_map.md) |
| One pattern torn/misaligned on the display | That pattern's data is intact (checksums passed); usually a receiver line-sync issue; use the pat index to locate it |

## Regression Notes

- The test never changes FPGA-side state; a re-run only needs a CPU reset to reload the firmware.
- Pattern data persists on the card (signature-block verified); re-running with a new firmware version does not require rewriting the card.
- `OWN_P1` arbitration: during verification (before [5/5]) port1 belongs to the SOC/debug master, and after stream start it belongs to video_reader;
  resetting the CPU does not return it automatically—reloading the firmware restarts from OWN_P1=0.
