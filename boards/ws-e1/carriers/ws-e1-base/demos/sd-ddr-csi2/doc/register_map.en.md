English | [中文](register_map.md)

# Register Map

Firmware definitions: see [sw/top_demo/src/userDef.h](../sw/top_demo/src/userDef.h); RTL implementations: see
[rtl/ddr_port1_reader.v](../rtl/ddr_port1_reader.v) and [rtl/video_reader.v](../rtl/video_reader.v).

## Bus Topology (Sapphire SOC APB space)

| Base Address | Peripheral | Description |
|---|---|---|
| `0xF8010000` | `system_uart_0` | UART 115200 8N1 |
| `0xF8100000` | `ddr_port1_reader` (P1R) | APB slave 0, port1 verification-read master |
| `0xF8110000` | `video_reader` (VR) | APB slave 1, port1 video-stream master |
| `0xF8120000` | SDHC (via APB3→AXI4-Lite bridge) | Register offset `+0x100` |

Usable DDR range: `0x01300000 - 0xF7FFFFFF`.

## ddr_port1_reader (P1R, base 0xF8100000)

Single-burst verification-read master: issues one AR, collects `BEATS` R beats, then sets DONE and returns the checksum plus the first and last words.
For debugging (the production video stream goes through video_reader).

| Offset | Name | Access | Fields |
|---|---|---|---|
| `0x00` | `REG_ID` | RO | Reads `0x50315231` ("P1R1") |
| `0x04` | `REG_CTRL` | RW | [0] START, [1] CLR_DONE, [2] ABORT |
| `0x08` | `REG_STATUS` | RO | [0] BUSY, [1] DONE, [2] SLVERR, [3] RVALID seen (sticky), [4] RLAST seen (sticky) |
| `0x0C` | `REG_ADDR` | RW | Read start address (byte) |
| `0x10` | `REG_LEN` | RW | Read length (byte) |
| `0x14` | `REG_BEATS` | RW | Expected number of R beats |
| `0x18` | `REG_SUM_LO` | RO | Low 32 bits of the 64-bit data checksum |
| `0x1C` | `REG_SUM_HI` | RO | High 32 bits of the checksum |
| `0x20` | `REG_FIRST_W0` | RO | Word0 of the first beat |
| `0x24` | `REG_LAST_W0` | RO | Word0 of the last beat |
| `0x28` | `REG_RLAST_BURST` | RO | Beats actually returned by the last burst (RLAST latched) |
| `0x2C` | `REG_RID_FIRST` | RO | RID of the first beat (ARID=0; non-zero means a ghost response) |
| `0x30` | `REG_RID_LAST` | RO | RID of the last beat |
| `0x34` | `REG_AR_DELAY` | RO | Cycles from AR issue to ARREADY (0xFF = never accepted) |
| `0x38` | `REG_IDLE_RV` | RO | RVALID rising edges during idle after DONE (>0 = the macro emits responses on its own) |

## video_reader (VR, base 0xF8110000)

Looping frame-read master: starting at `ADDR`, reads `NFRAME` frames of `FBYTES` bytes each continuously, switching to the next frame
address (i.e., the next pattern) every `NSWITCH` frames, in an endless loop.

| Offset | Name | Access | Fields |
|---|---|---|---|
| `0x00` | `REG_ID` | RO | Reads `0x56314452` ("V1DR") |
| `0x04` | `REG_CTRL` | RW | [0] RUN, [3] OWN_P1 |
| `0x08` | `REG_STATUS` | RO | [0] BUSY, [1] SLVERR |
| `0x0C` | `REG_ADDR` | RW | Frame array base address (`0x02000000` in this project) |
| `0x10` | `REG_FBYTES` | RW | Bytes per frame (1843200) |
| `0x14` | `REG_NFRAME` | RW | Frame count = pattern count (8) |
| `0x18` | `REG_NSWITCH` | RW | Frames per pattern (180 = 3 s @60 fps) |
| `0x1C` | `REG_PAT_IDX` | RO | Current pattern index 0..7 |
| `0x20` | `REG_FCNT` | RO | Cumulative frame count |

## Stream-Start Write Sequence (main.c stage [6])

```
VR_Wr(CTRL,   0x0);      // 停流, OWN_P1=0
VR_Wr(ADDR,   0x02000000);
VR_Wr(FBYTES, 1843200);
VR_Wr(NFRAME, 8);
VR_Wr(NSWITCH,180);
VR_Wr(CTRL,   0x8);      // OWN_P1=1  (port1 交给 video_reader)
VR_Wr(CTRL,   0x9);      // RUN=1    起流
```

Polling criterion: `(STATUS & 0x3) == 0x1` (RUN state, not busy, no SLVERR) and `FCNT > 100`.

## SD Card Data Layout (LBA, card-tail layout, avoids MBR/FAT)

```
sign_lba = pat_lba - 1                       签名块: magic "YUV8" + 几何 + 8×校验和
pat_lba  .. pat_lba+28799                    8 × 3600 块图案 (每图案 1843200 B)
frame_lba..(A/B 帧保留测试区, 3600 块)         frame_path_test 用
最后 0x100 块                                 保护边距
```

Pixel format note: the CSI-2 TX pack-64 uses a 16-bit slot per pixel `{Y[15:8], C[7:0]}`; with DDR little-endian, the byte order of two adjacent
pixels is `C Y C Y` (U Y V Y), **not** standard YUYV (Y U Y V).
