[中文](program.md) | English
# program.md — CLI Programming / Firmware Loading / UART Send & Receive Quick Reference (Phase 4, 2026-10-21)

> The whole flow has been validated end to end. Hardware: an FTDI FT4232H JTAG programmer (Quad RS232-HS) + a CH343 USB-UART (COM8).
> The host is Windows PowerShell; the Efinity toolchain is at `D:\efinity\2026.1`.

## 0. Bitstream generation (after an RTL change)

```powershell
# Efinity compile = interface + map + pnr + pgm (produces outflow\ws-e1-cam-ddr-csi2.bit)
$env:EFINITY_HOME = $null     # Key: clear the preset EFINITY_HOME so the tool bootstraps its own python environment
& D:\efinity\2026.1\bin\efx_run.bat --prj ws-e1-cam-ddr-csi2.xml -f compile
```

Product: `outflow\ws-e1-cam-ddr-csi2.bit` (it contains the Sapphire SoC firmware RAM initialization image,
but **the soft-core program is not in the bitstream** — the ELF must be loaded separately, see §2).

## 1. Programming the bitstream (JTAG, active mode, lost on power cycle)

```powershell
$env:EFINITY_HOME = $null
D:\efinity\2026.1\pgm\bin\ftdi_pgm.bat -m jtag `
    -b "Generic Board Profile Using FT4232H" `
    outflow\ws-e1-cam-ddr-csi2.bit
```

Success sign (about 5~10s):
```
Connecting to JTAG_TAP: efx_ti
Device ID read from JTAG: 0x00690A79     # TJ180
... finished with JTAG programming
```

Auxiliary command:
```powershell
D:\efinity\2026.1\pgm\bin\ftdi_pgm.bat --scan_usb     # enumerate the FTDI programmers (including the IDCODE)
```

## 2. Loading the ELF (OpenOCD → the vexriscv soft core; must be redone after every bitstream programming)

Prerequisite files (already in the repository):
- `sw/bsp/openocd/ftdi_ti.cfg` — the FTDI/TAP configuration (the official template descriptor string does not match this board)
- `sw/openocd_pre.cfg` — the descriptor string override `"Quad RS232-HS"` + `bsp_loc` pointing at `sw/`
- `sw/bsp/openocd/debug_load_ti.cfg` — the vexriscv target creation + a soft reset halt
- `sw/openocd_post.cfg` — `load_image` + `resume 0xF9000000` + shutdown

```powershell
$env:EFINITY_HOME = $null
& D:\efinity\2026.1\debugger\openocd\bin\openocd.exe `
    -f D:/Projs/ws-e1-cam-4K-1080-60fps-ref/sw/bsp/openocd/ftdi_ti.cfg `
    -f D:/Projs/ws-e1-cam-4K-1080-60fps-ref/sw/openocd_pre.cfg `
    -f D:/Projs/ws-e1-cam-4K-1080-60fps-ref/sw/bsp/openocd/debug_load_ti.cfg `
    -f D:/Projs/ws-e1-cam-4K-1080-60fps-ref/sw/openocd_post.cfg
```

Success sign:
```
JTAG tap: fpga_spinal.bridge tap/device found: 0x00690a79
[fpga_spinal.cpu0] Target successfully examined.
requesting target halt and executing a soft reset
shutdown command invoked
```

Notes:
- `resume 0xF9000000` = the program RAM base address (`sw/bsp/linker/default.ld`, ENTRY(_start)).
- If main.c was changed: first rebuild `sw/top_demo/build/top_demo.elf` with the Sapphire SDK toolchain, then load it.
- After the ELF is loaded the soft core runs immediately; reprogramming the bitstream zeroes the RAM image, so **this step must be repeated**.

## 3. Direct UART read/send (COM8 @115200)

Firmware `sw/top_demo/src/main.c`: every 0.5s the heartbeat prints the full DIAG set (the fw/rd/fr/fw2/ddr/rate/
yuv/cnt/cdc/shp lines); keystrokes take effect immediately and are echoed.

### 3.1 Receive (reading the heartbeat)

```powershell
$sp = New-Object System.IO.Ports.SerialPort('COM8',115200,'None',8,'One')
$sp.ReadTimeout = 6000; $sp.Open()
$buf = @()
try { while ($buf.Count -lt 40) {
    $line = $sp.ReadLine(); if ($line.Trim().Length -gt 0) { $buf += $line }
} } catch {}
$sp.Close(); $buf | Select-Object -Last 30
```

### 3.2 Send (key control, equivalent to the cam_show menu keys)

```powershell
$sp = New-Object System.IO.Ports.SerialPort('COM8',115200,'None',8,'One')
$sp.ReadTimeout = 5000; $sp.Open(); $sp.Write('c')   # e.g. switch to the camera preview
# ... read back as in 3.1 ...
$sp.Close()
```

Common keys: `c`=camera preview `p`=pattern `g/o/h/b`=the four patterns `[`/`]`=select the target chain
`v`=shape direct injection `r`=CDC direct injection `u/j n/m`=bridge chip gap sweep `1-4`=Bayer phase
`q/a w/s e/d`=white balance `x`=restore the defaults `i`=read the CSR `?`=menu.

## 4. Board-level health readout (the heartbeat fields)

| Field | Healthy value | Meaning when abnormal |
|---|---|---|
| `fw: frm/ln` | continuously growing / cycling 0..2159 | Stopped = the raw source is broken (the input frame sof count, not the publication count) |
| `fw: ovf` | 0 | Growing = insufficient write throughput |
| `rd: frm/st/ln` | following the fw frm / st transitions / ln cycling | Stopped = an authorization or read path problem |
| `rd: late/miss/err` | a small late value, a slowly growing miss, **err=0** | err≠0 = a bus level problem |
| `fr: rd` | **2160/2160** | Neither 0 nor 2160 = the playback line count is incomplete; 0/0 = the sof anchoring is missing (an open investigation item) |
| `fw2: bad` | 0 (+1 is possible in the source-switch transient) | Continuously growing = a frame discipline problem |
| `ddr: lock/cfg/st` | 1 / 1 / 3 | The other bits (done/fail/err) are a constant 0 in this form (memcheck is not hooked up) |
| `rate: dms_sol/fw_sof` | aliased noise but changing | A constant 0 = the corresponding stage has stopped flowing |
| `cnt: df/live` | ≈42~45 / ≈1458000 | df=0 = no display frames; live=0 = all-black content (a 0.75s absolute window) |
| `cdc: lost/lvl` | 0 / 0 (v4 straight-through has no level) | A growing lost = the line stream is corrupted |
| `shp: srch/lvl` (in v4 the late bytes) | slowly growing (absorbed by skips) | The exact semantics are in phase4-summary §6 |

## 5. Historical pitfall notes

1. **A preset EFINITY_HOME prevents the toolchain python environment from bootstrapping** — set `$env:EFINITY_HOME = $null` before invoking it.
2. The FTDI official cfg descriptor string is the development board name, while this board's actual descriptor is `Quad RS232-HS` — it must be overridden with
   `sw/openocd_pre.cfg`.
3. Re-saving the project in Efinity Studio loses the design_file entries manually added to the XML
   (tx_line_buf.v / disp_timing.v), so check the XML before a CLI compile.
4. `fw: frm` is the input sof count; whether a frame is published is seen from the reader side following along (rd frm).
5. A camera/pattern source switch (`c`/`p`) causes 1 transient bad frame (fw2: bad +1) plus about 2~3 heartbeat windows of pipeline rebuilding (df/live briefly zero then self-heals), which is expected behaviour.
