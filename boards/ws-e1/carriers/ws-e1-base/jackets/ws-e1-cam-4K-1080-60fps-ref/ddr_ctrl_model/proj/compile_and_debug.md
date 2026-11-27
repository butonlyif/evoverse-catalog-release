[English](compile_and_debug.en.md) | 中文

# proj 工程命令行编译 / 下载 / 串口调试手册

**适用**：`ddr_ctrl_model/proj/`（TJ180 最小 DDR 测试工程）
**环境**：Efinity 2026.1.132，Windows，板卡经 FT4232H 下载器连接（JTAG + CH343 UART）
**实测**：2026-10-22 全流程验证通过（编译→烧写→93 帧全对）

---

## 0. 环境前提（必读，否则工具起不来）

Efinity 的 interface/program 等 Python 流程依赖 `PYTHONHOME=D:\Efinity\2026.1\python311`（由 `bin\setup.bat` 设置）。
`efx_run.bat` 只在 **`EFINITY_HOME` 未定义**时才调用 `setup.bat`——若你的系统环境变量里已定义 `EFINITY_HOME`，则 `PYTHONHOME` 不会被设置，报：

```text
Fatal Python error: init_fs_encoding ... ModuleNotFoundError: No module named 'encodings'
```

**这也是 GUI 的 Interface Designer 打不开的常见根因。** 任选其一修复：

- 每次运行前清掉会话变量（推荐，命令里已含）：
  ```powershell
  Remove-Item Env:\EFINITY_HOME -ErrorAction SilentlyContinue
  ```
- 或全局设 `PYTHONHOME = D:\Efinity\2026.1\python311`；
- 或从用户环境变量删除 `EFINITY_HOME`，让脚本自行初始化。

## 1. 编译（一条命令全流程）

```powershell
cd d:\Projs\ws-e1-cam-ddr-csi2-demo\ddr_ctrl_model\proj
Remove-Item Env:\EFINITY_HOME -ErrorAction SilentlyContinue
& "D:\Efinity\2026.1\bin\efx_run.bat" ws-e1-ddr-test.xml --prj -f compile
```

输出四步，各自打印 PASS：

```text
map :        PASS      # RTL 综合（efx_map）
interface :  PASS      # 接口编译 = GUI Interface Designer 的命令行等价物
pnr :        PASS      # 布局布线（含 IO 插入、DDR 硬宏、时序分析）
pgm :        PASS      # 位流生成
```

产物在 `outflow/`：`ws-e1-ddr-test.bit`（JTAG 烧写用）、`ws-e1-ddr-test.hex`（SPI flash 用）、`ws-e1-ddr-test.interface.csv`、`ws-e1-ddr-test.pinout.csv`、时序报告等。

分步调试可用 `-f map` / `-f interface` / `-f pnr` / `-f pgm` 单独重跑。

### 1.1 编译前必做：清掉 peri.xml 里的空 pll_ssc_info（工具 bug）

**现象**：无 MIPI 块的设计若 peri.xml 顶层存在空元素 `<efxpt:pll_ssc_info/>`，接口编译崩溃：

```text
File ".../tx180_device/mipi_dphy/design_service.py", line 220, in build
    assert curr_mipi is not None
```

**坑**：接口编译 PASS 后 PT 会把该元素**回写**进 peri.xml，所以每次编译前都要清一次：

```powershell
(Get-Content ws-e1-ddr-test.peri.xml -Raw) -replace '\s*<efxpt:pll_ssc_info/>','' | Set-Content ws-e1-ddr-test.peri.xml -Encoding UTF8
```

主工程 `ws-e1-cam-ddr-csi2.peri.xml`（L852）同样有该元素，将来对主工程跑命令行接口编译遇到同样 AssertionError 时同款修复。

## 2. 烧写 bit（JTAG，易失）

```powershell
& "D:\Efinity\2026.1\bin\efx_run.bat" ws-e1-ddr-test.xml --prj -f program --pgm_opts mode=jtag
```

正常输出：

```text
Programming using Board Profile: Generic Board Profile Using FT4232H
Connecting to JTAG_TAP: efx_ti
Programming 'outflow\ws-e1-ddr-test.bit' via JTAG at freq 3.0 MHz
Device ID read from JTAG: 0x00690A79
... finished with JTAG programming
```

烧 SPI flash 用 `--pgm_opts mode=active`（对应 .hex）。

## 3. 串口读数据

### 3.1 枚举 COM 口

```powershell
Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'COM\d+' } | ForEach-Object { $_.Name }
```

本板实测（2026-10-22）：

```text
USB Serial Port (COM6)              # FT4232H 空通道，无数据
USB Serial Port (COM7)              # FT4232H 空通道，无数据
USB-Enhanced-SERIAL CH343 (COM8)    # 板上 UART = ddr_status_uart 输出
```

### 3.2 抓帧脚本（PowerShell，无需装终端软件）

脚本已在 `proj/uart_read.ps1`（参数：口、秒数），内容如下：

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

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File uart_read.ps1 -Port COM8 -Seconds 5
```

注意：抓帧前关闭其他占用该 COM 口的程序（否则 `UnauthorizedAccessException`）。

**抓帧时机（TG 扫描必读）**：JTAG 烧写会复位重启设计，扫描在 bit 加载后约 58ms 内跑完（IDLE/CFG ≈25.6ms + 16 轮 ×2ms 轮间隔）。**必须先启动抓帧、再执行烧写**，才能看到扫描全过程；烧完再开抓只能看到终态帧反复输出。JTAG 是易失烧写，板卡断电重启后 bit 丢失、串口无输出，需重新烧写。

## 4. 判据：UART 帧解读

帧格式 13 字节 `'DDR:' + 8 hex + '\n'`，DIAG 位图（MSB→LSB）：

| 字段 | 位 | 含义 | PASS 值 |
|---|---|---|---|
| err_cnt | [31:16] | memcheck 比对错误 beat 数 | 0x0000 |
| mcst | [15:12] | memcheck 状态机（9=DONE） | 0x9 |
| （保留） | [11:7] | — | 0 |
| done_raw | [6] | 硬核 ddr_inst_CFG_DONE | 1 |
| cfg_st | [5:4] | CFG FSM 状态（3=完成） | 0b11 |
| lock | [3] | DDR PLL 锁定 | 1 |
| cfg_ok | [2] | DDR 配置完成 | 1 |
| done | [1] | memcheck 完成 | 1 |
| fail | [0] | memcheck 失败 | 0 |

**全通过帧 = `DDR:0000907E`，连续多帧稳定输出即 Phase 0 通过。**

帧速率理论值：`UART_REPORT_TICKS = 2^23` @200MHz ≈ 41.9ms + 帧长 1.13ms（115200 波特率 13 字节×11bit 时间）≈ **43.1ms/帧**；实测 93 帧/4s ≈ 42.9ms/帧，吻合。

### 4.1 TG 扫描帧（TG_MODE=1 + UART_SCAN_MODE=1，correlation Phase 1）

8 个 hex 字符（n0..n7）= `{err_sat[7:0], rd_cyc[15:0], ostd[3:0], tgst[3:0]}`：

| 字符 | 字段 | 含义 |
|---|---|---|
| n0,n1 | err_sat | 本轮比对错误 beat 数（>255 饱和 0xFF），每轮清零 |
| n2..n5 | rd_cyc | 本轮读耗时（ACLK 拍：进 TG_RD_REQ 起计到 16 burst 全部收完） |
| n6 | ostd | 当前轮在飞上限 1..16；**4'h0 表示 16**（第 16 轮） |
| n7 | tgst | memcheck 状态：0=IDLE/CFG，9=DONE，A=TG_RD_REQ，B=TG_ROUND_GAP |

例：`DDR:0008FC09` = err=0、rd_cyc=2300、**ostd=16（4'h0）、DONE**。
**⚠ 实坑**：n5 是 rd_cyc 的最低位，别把 `…FC09` 里的 `C` 误读成 ostd=12——本项目因此误判"扫描卡在第 12 轮"一天。

扫描中绝大多数帧 tgst=B（轮间隔 2ms 占空比 99.4%，扫描轮本身仅 ~11.5µs），每轮 gap 期间 ostd 字段即轮序号，直接读出扫描表。

### 实测记录

| 日期 | 结果 |
|---|---|
| 2026-10-22 | COM8 连续 93 帧全部 `DDR:0000907E`，err=0、mcst=9、硬核与 memcheck 全部完成 |
| 2026-10-22 | TG Phase 1：先开抓 60s 后 JTAG 烧写，共 20205 帧：IDLE×16（CFG ~25.6ms）→ 16 轮扫描全跑满（err 全 0；rd_cyc 2741@ostd=1 → 平台 2284~2317）→ 终态 `DDR:0008FC09`（ostd=16、DONE）×14088。扫描表与对比结论见 `docs/correlation-plan.md` §9 |

## 5. 故障速查

| 症状 | 原因 / 处理 |
|---|---|
| `No module named 'encodings'` | `EFINITY_HOME` 已定义导致 setup.bat 被跳过 → 见 §0 |
| 接口编译 `assert curr_mipi is not None` | peri.xml 被回写了空 `pll_ssc_info` → 见 §1.1，编译前清一次 |
| 串口打不开（占用异常） | 关掉其他串口终端 |
| COM6/COM7 无数据 | 空通道，UART 在 COM8（CH343） |
| 有帧但 `err_cnt ≠ 0` | 16 位错误计数 = 失败 beat 数；用 ILA 抓 u_mc 内部定位（仿真侧 TB_DEBUG 探针方法同源） |
| 完全无帧 | 先确认烧写的是本工程 bit（JTAG 成功打印）；再确认 UART 线接 GPIOR_70/72 |
| pnr 报 SDC `No valid pin(s) found: sys_clk_100m` | 已知无害警告；sdc 中该约束已注释（端口综合后被移除） |
