[English](readme_4K_1K.en.md) | 中文

# readme_4K_1K — 工程模块 / 时钟 / 数据路径速查

双 IMX415 CSI-2 摄像头 → LPDDR4X 帧缓存乒乓回放 → MIPI CSI-2 TX 面板输出。
cam0 = **4K60**（148.5M 显示域），cam1 = **1080p60**（37.125M 显示域），两链同构
（v4 双 DDR 回放，显示唯一来源 = DDR 回放，无直通旁路）。
器件 Titanium **TJ180A484S**，Efinity **2026.1**。顶层 `top_cam_demo`。

> 本文是工程级速查（模块/时钟/路径）；里程碑与历史沿革见
> [milestone-v4.11-cam1-replay.md](milestone-v4.11-cam1-replay.md) 与
> [milestone-v4.10c3m.md](milestone-v4.10c3m.md)；烧录/串口操作见
> [program.md](program.md)。

---

## 1. 顶层框图

```
                 ┌────────────────────────── top_cam_demo ──────────────────────────┐
 IMX415#0 ─CSI-2→ DPHY RX0 ─→ my_csi2_rx ─→ raw_2_axi4st ──cap_t─→ u_fw0 ─┐         │
 IMX415#1 ─CSI-2→ DPHY RX2 ─→ my_csi2_rx ─→ raw_2_axi4st ──cap_t─→ u_fw1 ─┤         │
                                                                          axi_wr_arb│
                                                                    ┌──────────────┘
                                                              LPDDR4X 硬核（双 target 乒乓）
                                                                    └──────────────┐
 u_cam_0 (148.5M)：u_rd0(ACLK=pixel_clk) ←──────── axi_rd_arb ←──────┤             │
   rd→demosaic→wb→rgb2yuv→tx_line_buf→disp_timing→my_csi2_tx→ DPHY TX0─→GSV6172→4K面板
 u_rd1 (200M) → axi_rd_cdc → 回放流(37.125M) → u_cam_1 ←──────────────┘             │
 u_cam_1 (37.125M)：rd→demosaic→wb→rgb2yuv→tx_line_buf→disp_timing→my_csi2_tx→DPHY TX2─→GSV6172→1080面板
                                                                                    │
 riscv_soc(SaxonSoc/VexRiscv, sys_clk_100m)：APB slave0/1=camc，I2C0/1=IMX415，     │
 GPIO0.bit0/1=cam_en，UART COM8@115200 ────────────────────────────────────────────┘
```

每路 top_cam 内含源 mux：pattern_gen（CSR `pat_en`）与 shape_pat_gen 4K 棋盘
直注（编译期 DBG_SHAPE_PAT + CSR `dbg_sel`），用于隔离实验；回放流直入 demosaic。

---

## 2. 时钟与复位

### 2.1 时钟总表

| 时钟 | 来源 | 频率 | 用途 |
|---|---|---|---|
| `sys_clk_100m` | pll_sys | 100M | SoC/CPU 总线；my_csi2_rx 控制钟（AXI tie off） |
| `sys_clk_200m` | pll_sys | 200M | RX 像素输出域（raw）、u_fw0/u_fw1/u_rd1 aclk、APB pclk、DDR CFG/memcheck、AXI 仲裁 |
| `pixel_clk` | pll_csi #1 | **148.5M** | cam0 显示像素 + TX 像素域（流水线/tlb/dtg）；u_rd0 aclk（peri ACLK_1 重绑） |
| `pixel_clk_1080` | pll_csi2 #1 | **37.125M** | cam1 显示像素 + TX 像素域 |
| `i_clk_27m` | 板晶 | 27M | TX 上电复位链基准 |
| `esc_clk` | periphery | — | DPHY TX ESC |
| `dphy_rx0/rx2_clk_CLKOUT` | RX 恢复 | 字钟 | my_csi2_rx 字域（**无流停振**） |
| `dphy_tx0/tx2_WORD_CLKOUT_HS` | TX periphery PLL | 字钟 | my_csi2_tx 字域 |

### 2.2 复位释放链

- `pll_sys_locked` → sys_clk_100m/200m_rstn（reset_ctrl 同步）。
- DDR CFG FSM 门控 = `sys_clk_200m_rstn & pll_ddr_locked`（等 PLL 锁 + ~10.5ms）。
- my_csi2_rx 复位随 sys_clk_100m 域释放（PLL 锁定前 DPHY RX 硬核保持复位）。
- **TX 链**（top_cam.sv）：`dphy_tx_RESET_N = pll_mipi_refclk_locked` → 27M 域
  8192 拍(~300us) → reset_esc_n/clk_byte_HS_n → 再 16384 拍(~600us) →
  reset_pixel_n → u_tx_reset_ctrl 产 {tx_pixel_clk_rstn, word_clk_arstn,
  esc_clk_arstn}。**不校验 word clk 活性**。
- 回放域复位：rd_rstn_148 / rd_rstn_1080（g_frame_writer 内 reset_ctrl 驱动，
  顶层声明）；flush_done 透传触发对应路 tx 域复位。
- 传感器：软件 I2C 配置完成后按 GPIO bit 时序上电（有界重试，一路重上电不误伤
  另一路出流）。

---

## 3. 模块清单（rtl/）

| 文件 | 功能 | 域/实例 | 状态 |
|---|---|---|---|
| top_cam_demo.sv | 顶层：双 top_cam + u_fw0/u_fw1/u_rd0/u_rd1 + arb/cdc + DDR CFG/memtest + SoC 挂接 | — | 活动 |
| top_cam.sv | 单相机链路外壳：rx→demosaic→wb→rgb2yuv→u_tlb→u_dtg→tx + CSR 例化 | ×2（u_cam_0/u_cam_1） | 活动 |
| apb_cam_ctrl.sv | 每路 CSR（CTRL/DIAG 组，白平衡/bayer 相位/图案源运行时调节） | pclk=200M，×2 | 活动 |
| frame_writer.v | 整帧或全无打包写 DDR（512b 打包，行 64+56 两突发） | aclk=200M，×2（u_fw0/u_fw1） | 活动 |
| frame_reader.v | 显示节拍门回放（帧槽节拍=disp_timing 同源；残帧放弃+锚窗口） | u_rd0 aclk=pixel_clk；u_rd1 aclk=200M | 活动 |
| demosaic.sv | RAW10→RGB（×4px，组计数 10bit） | tx_pixel_clk，×2 | 活动 |
| wb_axis.sv | 白平衡（生效值 = pat_en?0x40:CSR） | tx_pixel_clk，×2 | 活动 |
| rgb2yuv_axis.sv | RGB→UYVY 64b（blk_clip=!pat_en） | tx_pixel_clk，×2 | 活动 |
| raw_2_axi4st.sv | 40b AXIS 滑动窗/DT 门控 | raw 200M，×2 | 活动 |
| pattern_gen.sv | 内测图案源（CSR pat_en/pat_sel） | ×2 | 活动 |
| shape_pat_gen.sv | 4K UYVY 棋盘直注源（dbg_sel，4K 几何 SRC_LINES=2160） | tx pixel 域 | 活动 |
| tx_line_buf.v | TX 行缓冲（BRAM，DEPTH_WORDS=2048；写=回放域，读按 64b 拍供 HACT） | ×2（u_tlb） | 活动 |
| disp_timing.v | **显示时序发生器 v2**（本地时序唯一发生源；GATE(1)+PREF(2) 硬编码占 HFP 3 拍；line_room/stall/disp_sof/断粮预警） | tx_pixel_clk，×2（u_dtg） | 活动 |
| reset_ctrl.sv | 多域复位同步 | 全局 | 活动 |
| axi_wr_arb.v | 双 writer → DDR 写口仲裁 | 200M | 活动 |
| axi_rd_arb.v | 双 reader → DDR 读口仲裁 | — | 活动 |
| axi_rd_cdc.v | 读数据跨域 CDC（灰指针+2FF，cam1 回放流 200M→37.125M） | — | 活动 |
| ddr_memcheck.v | DDR 自检（DIAG11；仅 cam0 挂载，cam1 tie 0 恒 0） | 200M | 活动 |
| disp_timing_gen.v | 阶段 2 早期显示时序方案 | 无实例化 | **退役**（仍在 XML 编译，map 优化掉） |
| disp_line_fifo.v | 阶段 2 早期异步行缓存（axi_rd_cdc 结构参照它） | 无实例化 | **退役**（同上） |
| axis_frame_check.sv | AXIS 帧校验 | — | 仅 TB（不在 XML） |

---

## 4. 数据路径

### 4.1 cam0（4K60）链路参数

| 段 | 值 |
|---|---|
| CSI 行结构 | LINE_TOTAL_PIX=3864（WC=4830B）、LEAD/TRAIL=12/12、SKIP=21（36 行 OB + 21 行头部 2B + 2160 有效行） |
| 有效 | HACT 3840 / VACT 2160 / GW=960（PPC4） |
| DDR | target0：FRAME_A=0x0000_0000 / FRAME_B=0x0200_0000，行槽 8KB（行 7680B=64+56 两突发） |
| 显示行（148.5M） | 1100 拍 = HSP44 + HBP75 + GATE1 + PREF2 + HACT960 + HFP18（= c3m 板测出图基线） |
| 显示帧 | 2250 槽（VSP10+VBP72+VACT2160+VFP8+pad）= 60Hz |
| TX 出口 | my_csi2_tx（free-run streaming，AXI-Lite tie off）→ DPHY **TX0** → GSV6172 |
| 读域 | u_rd0 aclk=pixel_clk（同域，无 CDC） |

### 4.2 cam1（1080p60）链路参数

| 段 | 值 |
|---|---|
| CSI 行结构 | LINE_TOTAL_PIX=1944、SKIP=11、1080 有效行、GW=480（PPC4） |
| 有效 | HACT 1920 / VACT 1080 |
| DDR | target1：FRAME_A=0x0400_0000 / FRAME_B=0x0500_0000，行槽 4KB（ddr_interface §10） |
| 显示行（37.125M） | 550 拍 = HSP11 + HBP37 + GATE1 + PREF2 + HACT480 + HFP19（CEA 2200px÷4） |
| 显示帧 | 1125 槽（VSP5+VBP36+VACT1080+VFP4）= 60Hz |
| TX 出口 | my_csi2_tx → DPHY **TX2** → GSV6172 |
| 读域 | u_rd1 aclk=200M → axi_rd_cdc → 回放流 37.125M 直入 demosaic 前 |

### 4.3 AXI 拓扑与仲裁

- 写：u_fw0(S0) + u_fw1(S1) → axi_wr_arb → DDR 写端口。
- 读：u_rd0(S0) + u_rd1(S1) → axi_rd_arb → DDR 读端口；cam0 读数据同域直用，
  cam1 经 axi_rd_cdc 跨到 37.125M。
- 流控模型：writer 整帧或全无（吸收源/显示 ppm 差），reader 显示节拍门 +
  帧界锚（源快向帧界跳帧）；tx_line_buf 水位回授 reader 发射门（line_room），
  断粮预警水位 < 1 行。

### 4.4 控制面与软件资源

| 资源 | cam0 | cam1 |
|---|---|---|
| APB camc | slave0 = 0xF810_0000 | slave1 = 0xF811_0000 |
| I2C（IMX415，7bit 0x1A） | I2C0 = 0xF801_6000 | I2C1 = 0xF801_7000 |
| cam_en（GPIO0 整字写） | bit0 | bit1 |
| DPHY | RX0 → TX0 | RX2 → TX2 |

APB slave2/3 为 dummy 即答（误访问不挂 CPU）。地址宏在 `sw/bsp/include/soc.h`，
固件封装在 `sw/top_demo/src/userDef.h`。UART COM8@115200：'[' / ']' 选目标路，
'g/o/h/b' 切图案（按键即使能）、'c' 切相机，其余键作用于目标路（白平衡/相位/间隙扫频等）。

---

## 5. 诊断 CSR 速查（每路各自 APB base + 0x??）

| CSR | 内容 | 判读 |
|---|---|---|
| DIAG4 | {fw_sof_free, dms_sol_free} 自由跑 | fw_sof +60/s=满速 |
| DIAG5 | {yuv_v_cnt, frm_cnt} | yuv/帧计数 |
| DIAG8 | {late, under}（disp_timing dtg） | 跳槽累计；under 应恒 0 |
| DIAG9 | 指纹探针 B（demosaic 入口） | 摄像头自然图像下 err 增长为预期误报 |
| DIAG11 | DDR 自检（ddr_memcheck） | **cam0 专挂；cam1 tie 0 恒 0 是设计** |
| DIAG12/13 | fw 计数（frm/line/ovf/pad） | frm +60/s、ovf=0 |
| DIAG14/15 | rd 计数（frm/st/ln；late/miss/err/req） | err=0 |
| DIAG16 | {beat_rd, beat_px} | 通路直证 |
| DIAG17 | 探针 A / 回放流锚（rd sol/tlast） | cam0 expect 2160/2160，cam1 1080/1080 |
| DIAG18 | df/live（0.75s 窗按 148.5M 硬编码） | cam0 df≈45；cam1 读数 ×4 → df=180；live 满=60Hz |
| DIAG19 | {drop, rpt} | 应不动 |
| DIAG20 | ← ddr_diag7 | cam1 诊断组 |

固件心跳打印：cam0 `fw0/rd0/fr0/rate0`，cam1 `fw1/rd1/fr1/rate1`（v4.11 新增）。
注意 BSP printf 无 %u，一律 %d。细则见 program.md 与 milestone-v4.10c3m §5。

---

## 6. 板级操作

烧 bit（ftdi_pgm.bat，JTAG）→ openocd 四段 cfg 加载 ELF（resume 0xF9000000）→
COM8 串口判读。完整命令与判读表见 [program.md](program.md)。
固件工具链：`D:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin`。
已知板级事项：冷启动/温复位后外部芯片（桥片/DPHY 外围）偶发锁卡，FPGA 内部
指标正常但面板黑/断流——先整板上下电或重烧 bit 再排查（v4.11 两起实锤，
详见 milestone-v4.11 §7/§8）。

---

## 7. 相关文档

| 文档 | 内容 |
|---|---|
| [milestone-v4.11-cam1-replay.md](milestone-v4.11-cam1-replay.md) | 本里程碑（cam1 集成）完整存档 |
| [milestone-v4.10c3m.md](milestone-v4.10c3m.md) | cam0 单链基线（诊断体系/历史教训详表） |
| [cam1-ddr-replay-plan.md](cam1-ddr-replay-plan.md) | cam1 集成实施方案（冻结稿） |
| [ddr_interface.md](ddr_interface.md) | DDR 布局核算（§10 双 target） |
| [program.md](program.md) | 烧录/ELF/串口实测手册 |
| [csi_bridge_gap_sweep.md](csi_bridge_gap_sweep.md) | 桥片时序容差扫频（GSV6172） |
