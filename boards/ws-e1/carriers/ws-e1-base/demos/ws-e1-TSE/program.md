[English](program.en.md) | 中文
# program.md — CLI 烧写 / 固件加载 / UART 收发速查（Phase 4，2026-10-21）

> 全流程已实测打通。硬件：FTDI FT4232H JTAG 下载器（Quad RS232-HS）+ CH343 USB-UART（COM8）。
> 宿主为 Windows PowerShell；Efinity 工具链在 `D:\efinity\2026.1`。

## 0. 出片（RTL 变更后）

```powershell
# Efinity compile = interface + map + pnr + pgm（生成 outflow\ws-e1-cam-ddr-csi2.bit）
$env:EFINITY_HOME = $null     # 关键：清除预置 EFINITY_HOME，让工具自举 python 环境
& D:\efinity\2026.1\bin\efx_run.bat --prj ws-e1-cam-ddr-csi2.xml -f compile
```

产物：`outflow\ws-e1-cam-ddr-csi2.bit`（含 Sapphire SoC 固件 RAM 初始化镜像，
但 **软核程序不入比特流**——ELF 需单独加载，见 §2）。

## 1. 烧写 bit（JTAG，active 模式，断电丢失）

```powershell
$env:EFINITY_HOME = $null
D:\efinity\2026.1\pgm\bin\ftdi_pgm.bat -m jtag `
    -b "Generic Board Profile Using FT4232H" `
    outflow\ws-e1-cam-ddr-csi2.bit
```

成功标志（约 5~10s）：
```
Connecting to JTAG_TAP: efx_ti
Device ID read from JTAG: 0x00690A79     # TJ180
... finished with JTAG programming
```

辅助命令：
```powershell
D:\efinity\2026.1\pgm\bin\ftdi_pgm.bat --scan_usb     # 枚举 FTDI 下载器（含 IDCODE）
```

## 2. 加载 ELF（OpenOCD → vexriscv 软核，每次烧 bit 后必须重做）

前提文件（已入库）：
- `sw/bsp/openocd/ftdi_ti.cfg` — FTDI/TAP 配置（官方模板描述串与本板不符）
- `sw/openocd_pre.cfg` — 描述串覆盖 `"Quad RS232-HS"` + `bsp_loc` 指向 `sw/`
- `sw/bsp/openocd/debug_load_ti.cfg` — vexriscv target 创建 + 软复位停机
- `sw/openocd_post.cfg` — `load_image` + `resume 0xF9000000` + shutdown

```powershell
$env:EFINITY_HOME = $null
& D:\efinity\2026.1\debugger\openocd\bin\openocd.exe `
    -f D:/Projs/ws-e1-cam-4K-1080-60fps-ref/sw/bsp/openocd/ftdi_ti.cfg `
    -f D:/Projs/ws-e1-cam-4K-1080-60fps-ref/sw/openocd_pre.cfg `
    -f D:/Projs/ws-e1-cam-4K-1080-60fps-ref/sw/bsp/openocd/debug_load_ti.cfg `
    -f D:/Projs/ws-e1-cam-4K-1080-60fps-ref/sw/openocd_post.cfg
```

成功标志：
```
JTAG tap: fpga_spinal.bridge tap/device found: 0x00690a79
[fpga_spinal.cpu0] Target successfully examined.
requesting target halt and executing a soft reset
shutdown command invoked
```

注意：
- `resume 0xF9000000` = 程序 RAM 首址（`sw/bsp/linker/default.ld`，ENTRY(_start)）。
- 若改了 main.c：需先用 Sapphire SDK 工具链重编 `sw/top_demo/build/top_demo.elf` 再加载。
- ELF 加载后软核立即运行；重新烧 bit 后 RAM 镜像清零，**必须重新执行本步**。

## 3. UART 直读/发送（COM8 @115200）

固件 `sw/top_demo/src/main.c`：每 0.5s 心跳打印全套 DIAG（fw/rd/fr/fw2/ddr/rate/
yuv/cnt/cdc/shp 各行）；按键即时生效并回显。

### 3.1 收（读心跳）

```powershell
$sp = New-Object System.IO.Ports.SerialPort('COM8',115200,'None',8,'One')
$sp.ReadTimeout = 6000; $sp.Open()
$buf = @()
try { while ($buf.Count -lt 40) {
    $line = $sp.ReadLine(); if ($line.Trim().Length -gt 0) { $buf += $line }
} } catch {}
$sp.Close(); $buf | Select-Object -Last 30
```

### 3.2 发（按键控制，等效 cam_show 菜单键）

```powershell
$sp = New-Object System.IO.Ports.SerialPort('COM8',115200,'None',8,'One')
$sp.ReadTimeout = 5000; $sp.Open(); $sp.Write('c')   # 例：切相机预览
# ... 读回同 3.1 ...
$sp.Close()
```

常用键：`c`=相机预览 `p`=图案 `g/o/h/b`=四种图案 `[`/`]`=选目标路
`v`=shape 直注 `r`=CDC 直注 `u/j n/m`=桥片 gap 扫频 `1-4`=拜耳相位
`q/a w/s e/d`=白平衡 `x`=恢复默认 `i`=读 CSR `?`=菜单。

## 4. 板级健康判读（心跳各字段）

| 字段 | 健康值 | 异常含义 |
|---|---|---|
| `fw: frm/ln` | 持续增长 / 0..2159 循环 | 停走 = raw 源断（输入帧 sof 计，非发布计） |
| `fw: ovf` | 0 | 增长 = 写吞吐不足 |
| `rd: frm/st/ln` | 跟随 fw frm / st 流转 / ln 循环 | 停走 = 授权/读路径问题 |
| `rd: late/miss/err` | late 小值、miss 缓增、**err=0** | err≠0 = 总线层问题 |
| `fr: rd` | **2160/2160** | 非 0 非 2160 = 回放行数残缺；0/0 = sof 锚定缺失（待查项） |
| `fw2: bad` | 0（源切换瞬态可 +1） | 持续增长 = 帧纪律问题 |
| `ddr: lock/cfg/st` | 1 / 1 / 3 | 其余位（done/fail/err）本形态恒 0（memcheck 未挂） |
| `rate: dms_sol/fw_sof` | 混叠噪声但在变 | 恒 0 = 对应级断流 |
| `cnt: df/live` | ≈42~45 / ≈1458000 | df=0 = 显示无帧；live=0 = 全黑内容（0.75s 绝对窗） |
| `cdc: lost/lvl` | 0 / 0（v4 直通无水位） | lost 增长 = 行流被毁 |
| `shp: srch/lvl`（v4=late 字节） | 缓增（跳槽吸收） | 具体语义见 phase4-summary §6 |

## 5. 历史坑位备忘

1. **EFINITY_HOME 预置会导致工具链 python 环境不自举**——调用前 `$env:EFINITY_HOME = $null`。
2. FTDI 官方 cfg 描述串是开发板名，本板实际描述为 `Quad RS232-HS`——必须用
   `sw/openocd_pre.cfg` 覆盖。
3. Efinity Studio 重新保存工程会丢手工加进 XML 的 design_file 条目
   （tx_line_buf.v / disp_timing.v），CLI 编译前检查 XML。
4. `fw: frm` 是输入 sof 计数；发布与否看 reader 侧跟随（rd frm）。
5. 相机/图案源切换（`c`/`p`）会有 1 个瞬态坏帧（fw2: bad +1）+ 约 2~3 个心跳窗
   的流水重建（df/live 短暂归零后自愈），属预期行为。
