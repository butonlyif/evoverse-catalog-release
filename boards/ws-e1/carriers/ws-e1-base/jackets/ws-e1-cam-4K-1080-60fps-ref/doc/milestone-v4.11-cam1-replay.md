[English](milestone-v4.11-cam1-replay.en.md) | 中文
# 里程碑：v4.11 — cam1 1080p DDR 回放全链集成（双链板测出图）

日期：2026-10-24
状态：**板测可用（双链输出确认）**。cam0 4K60 与 cam1 1080p60 双 DDR 回放端到端
出图；仿真双回归全绿；efx map/pnr/pgm 全 PASS。遗留冷启动/温复位板级状态类偶发
（§8）。

本文档继 [milestone-v4.10c3m.md](milestone-v4.10c3m.md)（cam0 单链基线存档），
实施基准为 [cam1-ddr-replay-plan.md](cam1-ddr-replay-plan.md)（§4 阶段 0-6 全部走完）。
工程模块/时钟/数据路径速查见 [readme_4K_1K.md](readme_4K_1K.md)。

---

## 1. 版本标识

| 项 | 值 |
|---|---|
| 版本号 | v4.11（继 v4.10c3m） |
| bitstream | `outflow/ws-e1-cam-ddr-csi2.bit`（2026-10-24 07:56 编译，map 0 错 / PnR 时序全绿 / pgm PASS） |
| 固件 | `sw/top_demo` ELF（cam1 心跳诊断组，见 §6） |
| 顶层 | `top_cam_demo`（Titanium TJ180A484S，Efinity 2026.1） |
| 回归 | tb_phase4 r4 绿 + tb_phase4_ddrm r6 绿（4K）+ tb_phase5_cam1 r6 绿（1080）：P4C 内容 216000 拍 0 错、rd sol/tlast 90/90、SLOW-OK、ctrl_err=0 |
| 关键文件 | `rtl/top_cam_demo.sv`（fw/rd/arb/cdc 集成）`rtl/top_cam.sv`（u_dtg 参数化）`rtl/axi_wr_arb.v` `rtl/axi_rd_arb.v` `rtl/axi_rd_cdc.v`（新入工程）`sim/tb_phase5_cam1.sv` `sw/top_demo/src/main.c` |
| 板测 | cam1 1080p60 端到端（fw1/rd1 60fps 同步、err=0、df=180 live 满、90s+ 长跑）；cam0 4K60 上下电后确认出图（§7） |

---

## 2. 架构：v4 双 DDR 回放，同构双链

v3 起显示唯一来源 = DDR 回放，**无直通旁路**（shape_video_axis 已退役）。v4.11
将 cam0 的 v4.10 结构完整复刻到 cam1：两链同构，各占一个 DDR target 独立乒乓。

```
cam0（4K60，148.5M 显示域）                      cam1（1080p60，37.125M 显示域）
IMX415 → DPHY RX0 → my_csi2_rx → raw_2_axi4st    IMX415 → DPHY RX2 → my_csi2_rx → raw_2_axi4st
        │(cap_t*, 200M raw 域)                           │(cap_t*, 200M raw 域)
        u_fw0（整帧或全无，target0）                     u_fw1（整帧或全无，target1）
        └──────────────> axi_wr_arb <────────────────────┘
                              │
                        LPDDR4X 双 target 帧乒乓
                  target0: A=0x0000_0000/B=0x0200_0000   target1: A=0x0400_0000/B=0x0500_0000
                              │
        u_rd0（aclk=pixel_clk，同域）                   u_rd1（aclk=200M）→ axi_rd_cdc → 回放流
        └──────────────> axi_rd_arb <────────────────────┘
        │                                                │
u_cam_0 内（148.5M）：demosaic → wb → rgb2yuv   u_cam_1 内（37.125M）：demosaic → wb → rgb2yuv
  → tx_line_buf → disp_timing(u_dtg)              → tx_line_buf → disp_timing(u_dtg)
    1100 拍行 / 2250 槽帧 = 60Hz                     550 拍行 / 1125 槽帧 = 60Hz
  → my_csi2_tx → DPHY TX0 → GSV6172 → 面板        → my_csi2_tx → DPHY TX2 → GSV6172 → 面板
```

> 实际 TX 出口：**cam0→TX0、cam1→TX2**。readme/main.c 曾写反（cam0→TX2），
> 系 v3 时代遗留文档错误，2026-10-24 已勘误；接线自 v14c（10/14）至今从未改变。

---

## 3. 集成内容（阶段 1-5）

- **写路径**：u_fw1（VACT=1080 / 60 字行 / 32+28 / 4KB 行槽）→ axi_wr_arb S1；
  u_fw0/u_fw1 双口仲裁共享 DDR 写端口。
- **读路径**：u_rd1（200M）→ axi_rd_arb S1 → axi_rd_cdc（灰指针 + 2FF，参照
  disp_line_fifo 结构）→ cam1 回放流（37.125M）直入 u_cam_1 demosaic 前；
  u_rd0 保持同域（aclk=pixel_clk，peri ACLK_1 重绑 148.5M）。
- **显示门控**：cam1 行节拍/帧界/断粮全部由 u_cam_1 内 disp_timing 同源提供
  （37.125M），与 cam0 结构一致。
- **复位**：回放域复位线 rd_rstn_148 / rd_rstn_1080 由 g_frame_writer 块内
  reset_ctrl 驱动、顶层声明（跨作用域，见 §5 第 6 条）；flush_done 透传回
  u_cam_x 触发 tx 域复位。
- **u_dtg 参数化**（阶段 2）：LINE_CLKS / HSP/HBP/HFP_CLKS 改为 top_cam 参数。
  cam0 不传即默认 **1100/44/75/18**（= c3m 板测出图基线，行和
  44+75+1+2+960+18=1100 守卫自洽）；cam1 传 550/11/37/19。
- **诊断**：u_cam_1 挂 ddr_diag2~7/19 组（DIAG12/13 fw、DIAG14/15 rd、DIAG17
  回放锚、DIAG19 drop/rpt）；**DIAG11 tie 0**（cam1 不挂 DDR 自检，恒 0 是
  设计如此）。

---

## 4. 验证

| TB | 覆盖 | 结果 |
|---|---|---|
| tb_phase4 r4 | 4K 显示链（激励直连显示域，不含 DDR） | 绿 |
| tb_phase4_ddrm r6 | 4K + DDR 模型全链 | 绿 |
| tb_phase5_cam1 r6 | cam1 双 DDR 回放全链（P4C 内容比对 216000 拍 0 错、rd sol/tlast 90/90、SLOW 变速、ctrl_err=0） | 绿 |

TB 调试要点（详表见 §5）：cam1 源锚行 2962 拍快于 DDR 写行 ~800-1000 拍曾致
8 槽队列溢出丢行死锁，主用例改 src_gap_beats=2476（源行 14.8us 与显示行同速）；
板级真实相机行周期 ~26us 无此问题。

---

## 5. 工具链与实现修复记录（ebbing 陷阱存档）

| # | 问题 | 修复 |
|---|---|---|
| 1 | tb_phase5 vopt-8884：输出端口接字面量 | `.DBG_FIELDS_ADDR()` 悬空 |
| 2 | u_dtg h 段守卫 FATAL：未传 HSP/HBP/HFP（默认 44/75/18 → 620≠550） | TB 补 11/37/19 |
| 3 | TB 时标失真 → DDR 写口积压 → q_full 丢行 → 63 帧全 bad 死锁 | src_gap_beats=2476（§4） |
| 4 | efx_map "Input source file is not specified" / EFX-0008 顶层选错 | `--project-xml` + `--root top_cam_demo`（`--project` 仅命名） |
| 5 | .v 按 Verilog-2001 解析：`parameter int`、`12'()` 报错（disp_line_fifo/disp_timing_gen，均为退役文件仍在编译清单） | 去 SV 语法；顺手备忘：两文件可移出 XML |
| 6 | **VERI-2561 ×11（功能性隐患，非 lint）**：rd_rstn_148/rd_rstn_1080 块内声明+顶层端口引用 → 隐式悬空 wire（复位链断）；fw1_* 后置声明 → 1 位隐式截断 | 复位线提升顶层声明；fw1 线网前置 |
| 7 | efx_pnr Tcl init 路径损坏 / timing 模块加载失败 | `EFINITY_HOME=D:/Efinity/2026.1` **正斜杠**；PATH 加 bin |
| 8 | PnR 负 slack（-0.7~-3.2，异钟对 0.001ns 假窗口） | SDC 补 6 组异步 clock_groups（pixel_clk_1080/esc/27m ↔ dphy_tx2 等） |
| 9 | efx_pgm 不认 --circuit | `--project-xml --family --device` |
| 10 | riscv-none-elf-gcc 不在 PATH | `D:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin`（readme §103） |
| 11 | XML design_info 缺 3 源文件 | 补 axi_wr_arb/axi_rd_arb/axi_rd_cdc |
| 12 | 固件判读口径：BSP printf 无 %u（走浮点分支参数错位，必须 %d）；DIAG11 cam1 恒 0 是设计；DIAG18 0.75s 窗按 148.5M 硬编码，37.125M 域 df 读数 ×4 | main.c 心跳组按此口径打印 |

---

## 6. 板测与固件

流程按 [program.md](program.md)：ftdi_pgm.bat JTAG 烧 bit → openocd 四段 cfg 加载
ELF（resume 0xF9000000）→ COM8@115200 判读。

固件新增 cam1 心跳诊断组（全部读 APB slave1=0xF811_0000）：
`fw1`（DIAG12/13）、`rd1`（DIAG14/15）、`fr1`（DIAG17 锚，expect 1080/1080）、
`rate1`（DIAG4/5/18）。cam1 判据：fw1 frm +60/s 且 ovf=0、rd1 err=0、fr1
1080/1080、df=180（×4 口径）live 满 → 60Hz。cam0 判据不变（program.md 健康表）。

**cam1 板级结果**：fw1/rd1 60fps 同步、err=0、显示 60Hz live 满，90 秒+ 长跑无
断流，图案与摄像头画面均确认。

---

## 7. 4K 黑屏事件（已结案：板级状态类，非 RTL 缺陷）

- **现象**：10/24 bit 板测，cam1 1080 出图，cam0 4K 黑。
- **内部证据**：cam0 串口指标全绿（fw/rd/ddr、df=45/45、live 满、yuv 活）——
  显示管线在跑，面板黑。
- **排除三连**（静态证据）：
  1. TX 接线自 v14c（10/14）未变（cam0→TX0），阶段 5 未换线；
  2. 外围配置（peri.cdo/interface.csv）停在 10/22 15:11（c3m 好 bit 编译），
     本次编译未再生成，TX0 PLL 配置与好 bit 相同；
  3. cam0 显示参数 = c3m 基线（1100/44/75/18，2250 槽）。活动 u_dtg =
     `disp_timing.v`（c3m 即用）；`disp_timing_gen.v`/`disp_line_fifo.v` 为
     阶段 2 早期方案已退役（仅编译未实例化），不构成本次回归。
- **恢复**：用户整板重新上下电后 4K 出图。
- **结论**：桥片/DPHY 外围在温复位（JTAG 重配）后偶发锁卡，FPGA 内部一切正常。
  与 cam1 77s 断流（§8）同类。附带勘误：readme.md:30 与 main.c 头注释 TX 映射
  写反（见 §2 注）。

---

## 8. 遗留

| 项 | 说明 | 方向 |
|---|---|---|
| 冷启动/温复位板级状态类偶发 | 两起实锤：cam1 源 77s 断流（重烧 bit 恢复）、4K 黑屏（上下电恢复）；FPGA 内部正常，外部芯片异常后无自恢复 | 固件看门狗：df 计数停走检测 → 对应路重初始化（TX 复位链重放 / GPIO 重新上电） |
| fr1 锚跨域读撕裂 | DIAG17 锚跨域读无握手，偶发脏读；仅诊断口径问题，非功能缺陷 | 后续加格雷同步或按多次采样取多数 |
| 退役文件仍在编译清单 | disp_timing_gen.v / disp_line_fifo.v 无实例化，本次曾因 SV 语法报错干扰 | 可移出 XML design_info |

---

## 9. 复现与回退

```tcl
# 综合（map）
efx_map --project-xml ws-e1-cam-ddr-csi2.xml --root top_cam_demo --project ws-e1-cam-ddr-csi2 --work-dir work_syn --output-dir outflow
# PnR / 出片（PowerShell，EFINITY_HOME 必须正斜杠）
$env:EFINITY_HOME = "D:/Efinity/2026.1"
efx_pnr / efx_pgm --project-xml ws-e1-cam-ddr-csi2.xml --family Titanium --device Ti180A484S ...
```

- 固件：`D:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin`（riscv-none-elf-gcc），
  sw/top_demo 工程，ELF 经 openocd 加载。
- 仿真：tb_phase4 / tb_phase4_ddrm / tb_phase5_cam1（判据见 §4）。
- 回退：本工程无 git；backup/ 内为 v14c/v15 更早基线（含 shape 时代）。
  v4.10c3m 无源码快照，如需回退须从 top_cam_demo.sv 手工摘除 cam1 集成
  （u_fw1/u_rd1/arb/cdc 挂接、u_cam_1 显示门控、rd_rstn_1080），不推荐；
  cam1 链异常时可直接用 'p'/'c' 软切换隔离定位。
