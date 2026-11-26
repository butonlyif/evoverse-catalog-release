[中文](compile_and_debug.md) | English

# proj Project Command-Line Compile / Programming / UART Debug Handbook

**Applies to**: `ddr_ctrl_model/proj/` (the TJ180 minimal DDR test project)
**Environment**: Efinity 2026.1.132, Windows, board connected through an FT4232H programmer (JTAG + CH343 UART)
**Measured**: the full flow was verified on 2026-10-22 (compile → programming → 93 frames all correct)

---

## 0. Environment Preconditions (must read, otherwise the tools will not start)

Efinity's interface/program Python flows depend on `PYTHONHOME=D:\Efinity\2026.1\python311` (set by `bin\setup.bat`).
`efx_run.bat` calls `setup.bat` **only when `EFINITY_HOME` is undefined** — if `EFINITY_HOME` is already defined in your system environment variables, `PYTHONHOME` will not be set and you will see:

```text
Fatal Python error: init_fs_encoding ... ModuleNotFoundError: No module named 'encodings'
```

**This is also the most common root cause of the GUI Interface Designer failing to open.** Fix it by any one of the following:

- Clear the session variable before every run (recommended; the command below already includes it):
  ```powershell
  Remove-Item Env:\EFINITY_HOME -ErrorAction SilentlyContinue
  ```
- Or set `PYTHONHOME = D:\Efinity\2026.1\python311` globally;
- Or delete `EFINITY_HOME` from the user environment variables and let the script initialize itself.

## 1. Compile (one command for the whole flow)

```powershell
cd d:\Projs\ws-e1-cam-ddr-csi2-demo\ddr_ctrl_model\proj
Remove-Item Env:\EFINITY_HOME -ErrorAction SilentlyContinue
& "D:\Efinity\2026.1\bin\efx_run.bat" ws-e1-ddr-test.xml --prj -f compile
```

The output has four steps, each printing PASS:

```text
map :        PASS      # RTL synthesis (efx_map)
interface :  PASS      # interface compile = command-line equivalent of the GUI Interface Designer
pnr :        PASS      # place and route (including IO insertion, DDR hard macro, timing analysis)
pgm :        PASS      # bitstream generation
```

Artifacts land in `outflow/`: `ws-e1-ddr-test.bit` (for JTAG programming), `ws-e1-ddr-test.hex` (for SPI flash), `ws-e1-ddr-test.interface.csv`, `ws-e1-ddr-test.pinout.csv`, timing reports, etc.

For step-by-step debugging you can re-run individual stages with `-f map` / `-f interface` / `-f pnr` / `-f pgm`.

### 1.1 Mandatory before compiling: remove the empty pll_ssc_info in peri.xml (tool bug)

**Symptom**: for a design without an MIPI block, if the top level of peri.xml contains the empty element `<efxpt:pll_ssc_info/>`, the interface compile crashes:

```text
File ".../tx180_device/mipi_dphy/design_service.py", line 220, in build
    assert curr_mipi is not None
```

**Trap**: after the interface compile passes, PT writes that element **back** into peri.xml, so it must be cleared once before every compile:

```powershell
(Get-Content ws-e1-ddr-test.peri.xml -Raw) -replace '\s*<efxpt:pll_ssc_info/>','' | Set-Content ws-e1-ddr-test.peri.xml -Encoding UTF8
```

The main project file `ws-e1-cam-ddr-csi2.peri.xml` (L852) has the same element; apply the same fix when running command-line interface compilation on the main project and hitting the same AssertionError.

## 2. Program the bitstream (JTAG, volatile)

```powershell
& "D:\Efinity\2026.1\bin\efx_run.bat" ws-e1-ddr-test.xml --prj -f program --pgm_opts mode=jtag
```

Normal output:

```text
Programming using Board Profile: Generic Board Profile Using FT4232H
Connecting to JTAG_TAP: efx_ti
Programming 'outflow\ws-e1-ddr-test.bit' via JTAG at freq 3.0 MHz
Device ID read from JTAG: 0x00690A79
... finished with JTAG programming
```

To burn SPI flash use `--pgm_opts mode=active` (corresponding to the .hex).

## 3. Read Data over the UART

### 3.1 Enumerate COM ports

```powershell
Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'COM\d+' } | ForEach-Object { $_.Name }
```

Measured on this board (2026-10-22):

```text
USB Serial Port (COM6)              # FT4232H empty channel, no data
USB Serial Port (COM7)              # FT4232H empty channel, no data
USB-Enhanced-SERIAL CH343 (COM8)    # on-board UART = ddr_status_uart output
```

### 3.2 Capture script (PowerShell, no terminal software needed)

The script is already in `proj/uart_read.ps1` (arguments: port, seconds), contents as follows:

```powershell
param([string]$Port = 'COM8', [int]$Seconds = 5)
$sp = New-Object System.IO.Ports.SerialPort($Port, 115200, 'None', 8, 'One')
$sp.ReadTimeout = 200
$sp.Open(); $sp.DiscardInBuffer()
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$sb = New-Object System.Text.StringBuilder
$buf = New-Object byte[] 1024
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
  try {
    $n = $sp.Read($buf, 0, $buf.Length)
    for ($i = 0; $i -lt $n; $i++) {
      $c = $buf[$i]
      if ($c -ge 32 -and $c -le 126) { [void]$sb.Append([char]$c) }
      elseif ($c -eq 10) { [void]$sb.Append("`n") }
      else { [void]$sb.Append('.') }
    }
  } catch { }
}
$sp.Close()
Write-Host $sb.ToString()
```

Run it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File uart_read.ps1 -Port COM8 -Seconds 5
```

Note: close any other program that occupies that COM port before capturing (otherwise `UnauthorizedAccessException`).

**Capture timing (must read for TG scans)**: JTAG programming resets and restarts the design, and the scan finishes within about 58 ms after the bitstream is loaded (IDLE/CFG ≈25.6 ms + 16 rounds × 2 ms round gap). **You must start the capture first and only then program**, otherwise you will only see the terminal-state frame repeated. JTAG programming is volatile: after a power cycle the bitstream is lost and the UART produces no output, so it must be programmed again.

## 4. Pass Criteria: Decoding the UART Frame

The frame format is 13 bytes `'DDR:' + 8 hex + '\n'`, with the DIAG bitmap (MSB→LSB):

| Field | Bits | Meaning | PASS value |
|---|---|---|---|
| err_cnt | [31:16] | Number of memcheck compare-error beats | 0x0000 |
| mcst | [15:12] | memcheck state machine (9=DONE) | 0x9 |
| (reserved) | [11:7] | — | 0 |
| done_raw | [6] | Hard IP core ddr_inst_CFG_DONE | 1 |
| cfg_st | [5:4] | CFG FSM state (3=complete) | 0b11 |
| lock | [3] | DDR PLL locked | 1 |
| cfg_ok | [2] | DDR configuration complete | 1 |
| done | [1] | memcheck complete | 1 |
| fail | [0] | memcheck failed | 0 |

**The all-pass frame is `DDR:0000907E`**; a stable output of this frame over consecutive frames means Phase 0 passes.

The theoretical frame rate is: `UART_REPORT_TICKS = 2^23` @200 MHz ≈ 41.9 ms + frame length 1.13 ms (115200 baud, 13 bytes × 11 bit times) ≈ **43.1 ms/frame**; the measured 93 frames/4 s ≈ 42.9 ms/frame agrees.

### 4.1 TG Scan Frame (TG_MODE=1 + UART_SCAN_MODE=1, correlation Phase 1)

The 8 hex characters (n0..n7) = `{err_sat[7:0], rd_cyc[15:0], ostd[3:0], tgst[3:0]}`:

| Character | Field | Meaning |
|---|---|---|
| n0,n1 | err_sat | Number of compare-error beats in this round (saturates at 0xFF above 255), cleared each round |
| n2..n5 | rd_cyc | Read duration of this round (ACLK cycles: counted from TG_RD_REQ until all 16 bursts are received) |
| n6 | ostd | In-flight limit of the current round 1..16; **4'h0 means 16** (the 16th round) |
| n7 | tgst | memcheck state: 0=IDLE/CFG, 9=DONE, A=TG_RD_REQ, B=TG_ROUND_GAP |

Example: `DDR:0008FC09` = err=0, rd_cyc=2300, **ostd=16 (4'h0), DONE**.
**⚠ Real trap**: n5 is the least significant bit of rd_cyc — do not misread the `C` in `…FC09` as ostd=12; this project lost a whole day to the false conclusion "the scan stalled at round 12".

During the scan the vast majority of frames have tgst=B (the 2 ms round gap has a 99.4% duty cycle, and the scan round itself lasts only ~11.5 µs), so during each gap the ostd field is the round index, and the scan table can be read out directly.

### Measured Records

| Date | Result |
|---|---|
| 2026-10-22 | COM8 produced 93 consecutive frames, all `DDR:0000907E`, err=0, mcst=9, hard IP core and memcheck both complete |
| 2026-10-22 | TG Phase 1: capture opened for 60 s before JTAG programming, 20205 frames in total: IDLE×16 (CFG ~25.6 ms) → all 16 scan rounds ran to completion (err all 0; rd_cyc 2741@ostd=1 → plateau 2284~2317) → terminal state `DDR:0008FC09` (ostd=16, DONE)×14088. See the scan table and comparison conclusions in `docs/correlation-plan.md` §9 |

## 5. Quick Troubleshooting

| Symptom | Cause / remedy |
|---|---|
| `No module named 'encodings'` | `EFINITY_HOME` is defined so setup.bat is skipped → see §0 |
| Interface compile `assert curr_mipi is not None` | peri.xml was written back with an empty `pll_ssc_info` → see §1.1, clear it once before compiling |
| The serial port cannot be opened (access violation) | Close other serial terminal programs |
| COM6/COM7 produce no data | They are empty channels; the UART is on COM8 (CH343) |
| Frames arrive but `err_cnt ≠ 0` | The 16-bit error count is the number of failing beats; capture u_mc internals with the ILA to locate them (the simulation-side TB_DEBUG probe method has the same origin) |
| No frames at all | First confirm that the programmed bitstream is this project's (JTAG success message printed); then confirm the UART lines are connected to GPIOR_70/72 |
| pnr reports the SDC `No valid pin(s) found: sys_clk_100m` | Known harmless warning; the constraint is commented out in the sdc (the port is removed after synthesis) |
