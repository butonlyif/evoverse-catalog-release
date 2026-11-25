[English](design-overview-4k60.en.md) | 中文
# 4K@60 摄像头 → DDR 帧缓存回放 → MIPI CSI-2 TX 系统设计总览

| 项 | 值 |
|---|---|
| 基线版本 | **v4.10c3m**（2026-10-22，板测可用，bitstream `outflow/ws-e1-cam-ddr-csi2.bit`） |
| 器件 / 工具链 | Efinix Titanium **TJ180A484S**，Efinity 2026.1 |
| 顶层 | `top_cam_demo`（[rtl/top_cam_demo.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/top_cam_demo.sv)） |
| 读者 | 接手本工程的工程师 / 协作团队 |
| 详细存档 | [milestone-v4.10c3m.md](milestone-v4.10c3m.md)（本总览的母本）、[ddr_interface.md](ddr_interface.md) |
| 状态说明 | cam0 = 4K@60 活动链路（本文主体）；cam1 = 1080p60 显示链外壳（**无 DDR 回放，黑场预留**，见 §2.3） |

---

## 1. 系统概览

双 IMX415 CSI-2 摄像头接入，cam0 通路实现 **4K@60（3840×2160）DDR 帧缓存乒乓回放**，经 ISP 链与 MIPI CSI-2 TX 输出到面板。显示帧率恒 60Hz，与传感器帧率解耦；源可随时在"摄像头 / 诊断图案"间无撕裂切换。

```
IMX415 ──CSI-2──> my_csi2_rx (64b Generic Frame Mode, RAW10 低 40b 有效)
                    │  sys_clk_200m 域
 pattern_gen ────────┤  top_cam 源 mux（CSR CTRL[2] pat_en）
                     │  + 切入门 sw_gate + 上电引导
                     v
               raw_2_axi4st (40b AXIS, 960 拍/行 = 3840px, 滑动窗/DT 门控)
                     │  {24'h0, tdata[39:0]} 零扩展（v4.10 接入约定）
                     v
               frame_writer (aclk = sys_clk_200m, 在 top_cam_demo)
                 64b 载体：8 拍 × 64b = 512b 整除打包
                 行 7680B = 120 字；AXI4 写 512b/beat，突发 64+56（各自 4KB 窗内）
                 8 行槽 + 8 深 desc 队列；整帧或全无
                     v
               LPDDR4X 双 bank 帧乒乓
                 FRAME_A = 0x0_0000_0000 / FRAME_B = 0x0_0200_0000
                 行槽 8KB × 2160 行 = 17.6MB/帧
                     v
               frame_reader (aclk = pixel_clk 148.5M)
                 每 512b 字 8 拍切片 [64k+63:64k]；行 967 发射拍 < 1100 行预算
                 帧级仲裁：disp_sof 锚 + ANCHOR_WAIT 锚窗口 + drop/repeat
                     │ 64b 直通（连线层切 [39:0]，与 reader 同钟无 CDC）
                     v
  top_cam 内联显示链（v4.10c3m 扁平化，camera_path 已删除）：
    demosaic (RAW10→RGB×4px) → wb → rgb2yuv (UYVY 64b)
                     │  shape_pat_gen 直注 mux（DBG_SHAPE_PAT + CSR CTRL[6]）
                     v
    tx_line_buf (DEPTH_WORDS=2048) → disp_timing (LINE_CLKS=1100, 2250 槽)
                     → my_csi2_tx → DPHY TX 桥片 → 面板
```

**ISP 全链（demosaic/wb/rgb2yuv/tx_line_buf/disp_timing）算法自 v4.9d 未动**。v4.10 系列只动了两处：① 40b→64b 载体重构（writer/reader）；② 源切换/复位体系（sw_gate + flush 链）+ reader 帧仲裁修正（c3g/c3h）+ DDR 基址修正（c3k）。

### 1.1 为什么是 64b 载体（v4.10 载体重构）

40b 载体时代 960 拍/行 × 40b 与 512b AXI beat 存在 LCM 组相位问题（2560b 组移位链），是 256px 竖线类缺陷的温床。v4.10 改为：raw 40b 流**零扩展为 64b**（`{24'h0, data[39:0]}`），8 拍 × 64b = 512b 整除打包，beat k 落 `[64k+63:64k]`（beat0 最低位），DDR 字节序 = 拍序升序，reader 按同序切片还原。**无任何 LCM 相位转换**——竖线类缺陷被构造性根除。代价：DDR 中每行存 7680B（含 24bit/拍 的 0 填充），带宽换正确性。

---

## 2. 模块地图（v4.10c3m）

### 2.1 现役文件

| 文件 | 职责 | 关键事实 |
|---|---|---|
| [rtl/top_cam.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/top_cam.sv) | 单摄像头通路的**扁平网表**（c3m 起 camera_path 层已删除、内联于此）：源 mux、切入门、raw_2_axi4st、ISP 链、tx_line_buf、disp_timing、my_csi2_tx 例化 | 每摄一个实例；显示几何/帧槽为参数 |
| [rtl/top_cam_demo.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/top_cam_demo.sv) | 系统顶层：PLL/复位、DDR CFG FSM、frame_writer/frame_reader 例化与跨域握手、CSR/APB、RISC-V 固件加载 | u_fw→DDR target0（写），u_rd→target1（读），两口物理隔离 |
| [rtl/frame_writer.v](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/frame_writer.v) | RAW10 64b 行流 → DDR 帧写入；整帧或全无；`frame_par` 唯一 bank 锚 | aclk=200M；行 120 字；burst 64+56 |
| [rtl/frame_reader.v](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/frame_reader.v) | DDR 帧回放读主控；帧级仲裁（锚 + drop/repeat）；64b 切片输出 | aclk=148.5M 显示域；ANCHOR_WAIT 锚窗口 |
| [rtl/raw_2_axi4st.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/raw_2_axi4st.sv) | CSI-2 RX 40b 像素流 → AXIS 40b 行流（滑动窗/DT 门控） | LINE_TOTAL_PIX 窗口裁剪 |
| [rtl/pattern_gen.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/pattern_gen.sv) | 诊断图案源（与面板 line_tick 同源推进） | pat_sel=2 = 全帧单调灰度 ramp |
| [rtl/demosaic.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/demosaic.sv) / [wb_axis.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/wb_axis.sv) / [rgb2yuv_axis.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/rgb2yuv_axis.sv) | ISP：去马赛克 → 白平衡 → UYVY 色彩转换 | 4 像素/拍 64b |
| [rtl/shape_pat_gen.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/shape_pat_gen.sv) | tlb 入口直注诊断源（编译期 DBG_SHAPE_PAT + 运行时 CTRL[6]） | 仅 4K 几何 |
| [rtl/tx_line_buf.v](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/tx_line_buf.v) | 行缓冲（**.v 文件**）+ 发射门水位 | DEPTH_WORDS=2048 |
| [rtl/disp_timing.v](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/disp_timing.v) | 显示时序唯一发生源：line_tick / disp_sof / GATE，行段和守卫 | LINE_CLKS=1100（4K@PPC4） |
| [rtl/apb_cam_ctrl.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/apb_cam_ctrl.sv) | CSR（APB）：CTRL 切源 / DIAG 读数 | UART 判读入口 |
| [rtl/reset_ctrl.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/reset_ctrl.sv) | 多域复位同步（CYCLE 参数防亚稳窗） | |

### 2.2 已删除文件（勿再引用）

`camera_path.sv`、`shape_video_axis.sv`、`async_path_fifo.v`、`replay_pat_gen.sv` —— v4.10c3m 扁平化时删除（DISP_V4=0 分支随退）。历史版本在 `backup/` 与 `design-package/materials/`。

### 2.3 cam1（1080p60）现状

u_cam_1 与 cam0 同构例化，但**只覆盖 `DISP_FRAME_SLOTS=1125`，无 DDR 回放**：top_cam_demo 中 cam1 的 `rd_t*` 输入 tie-off 恒 0（黑场），无 u_fw/u_rd 实例。cam1 显示链跑 37.125MHz（`pixel_clk_1080`）。**注意**：top_cam 内 disp_timing 例化的 `LINE_CLKS=1100` 目前是硬编码 4K 值，未随 cam1 参数化（1080p@PPC4 应为 550），cam1 时序自洽性待修复。

---

## 3. 时钟与复位域

| 时钟 | 频率 | 域内容 |
|---|---|---|
| `sys_clk_200m` | 200M | my_csi2_rx 像素输出、pattern_gen、raw_2_axi4st、**frame_writer**、DDR target0 ACLK |
| `pixel_clk`（pll_csi#1） | 148.5M | 显示流水线（demosaic~disp_timing/TX）、**frame_reader**、DDR target1 ACLK |
| `pixel_clk_1080`（pll_csi#2#1） | 37.125M | cam1 流水线/显示（1080p60@PPC4） |
| `sys_clk_100m` | 100M | my_csi2_rx 控制器时钟 |
| `i_clk_27m` / `esc_clk` / dphy 字钟 | — | TX 上电复位基准 / DPHY ESC / RX 恢复字钟 |

复位双域（源切换时序的核心）：

- raw 域：`raw_aresetn = sys_clk_200m_rstn & sw_rstn`（源切换帧界复位）
- pixel 域：`pixel_rst_n = tx_pixel_clk_rstn & sw_rstn_tx`（释放晚于 PLL 锁定 +~300µs +~600µs，保证"复位先于数据释放"冷启动锚定）
- 跨域握手：`wr_frame_done`（200M 单拍）→ 2FF + `syn_keep` → 148.5M 取沿；`frame_par` 电平 2FF 直采

---

## 4. 关键参数速查（cam0 4K）

| 参数 | 值 | 出处/说明 |
|---|---|---|
| RAW10 源窗口 | LINE_TOTAL_PIX=3864，LEAD/TRAIL=12，SKIP_FIRST=21，2160 行 | [top_cam_demo.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/rtl/top_cam_demo.sv) u_cam_0 例化 |
| 源行流 | 960 拍 × 40b = 3840px/行 | raw_2_axi4st 输出 |
| 64b 载体行 | 960 拍（零扩展）= 7680B = 120 字 | frame_writer/reader localparam（4K 专用，1080p 变体见 §9） |
| AXI 写形态 | 512b/beat，INCR，64+56 两突发（各落 4KB 窗）；awqos=1 | frame_writer drain 状态机 |
| 显示几何 | HACT=3840，VACT=2160，VSP10+VBP72+VFP8（CTA 4K60），2250 槽/帧 | disp_timing；PAD 由余项自洽推导 |
| 显示行拍 | LINE_CLKS=1100 = 44+75+1+2+960+18（@PPC4） | 行发射预算 967 拍 < 1100 |
| DDR 帧布局 | A=0x0_0000_0000，**B=0x0_0200_0000**（c3k），行槽 8KB | u_fw/u_rd 两处参数逐字一致 |
| ANCHOR_WAIT | 板 78 / tb 4（= VSP+VBP−余量4） | c3h 锚窗口 |
| CSR 默认 | `32'hB4EBC814`（上电=摄像头源，pat_en=0） | apb_cam_ctrl CTRL_RESET |
| 源切换 | UART 'c'=摄像头，'g/o/h/b'=图案（按键即使能+选型）；CTRL[6]=dbg 直注 | 帧界生效 |

---

## 5. 核心机制

### 5.1 frame_writer：整帧或全无（v2 架构）

- 数据缓冲 = 8 行槽 × 120 字（512b）+ 8 深 {par,line} 描述队列，单钟直通指针。
- **坏帧（队满污染 / 帧中 sof）→ 关帧不翻 par 不发布**：DDR 中永远只有完整帧，构造性消灭撕帧。所有丢弃路径有计数（ovf/pad/bad/drop）。
- 帧满（VACT-1 行 drain 完成）→ 翻 `frame_par` + 发布 `wr_frame_done` 单拍（200M 域，该帧全部落 DDR 后的 bvalid 完成拍）。
- **`frame_par` 是 writer/reader 唯一 bank 仲裁锚**：writer 恒写 par，reader 恒读 ~par。
- ppm/帧率差分工：writer 恒写活流（整帧或全无），reader 槽粒度 drop/repeat——不做行级补偿。

### 5.2 frame_reader：帧级仲裁 + 锚窗口（v4.9 + c3g/c3h）

- 帧请求 = `wr_frame_done` 跨域取沿；**起步门 `done_cnt>=2`**（读的 bank 不会被下一帧覆盖）。
- **授权锚 = `disp_sof` 下降沿**（Vs 起点，Va[0] 前 82 槽）。有请求沿 → 切最新完整帧；无沿 → 重读当前 bank（repeat）；沿堆积 → drop。
- **c3g 残帧放弃**：锚拍若 reader 还在发射上帧残行，单拍沿会被错过 → 修复为锚拍 `abort_frame` 回 IDLE + `pend_grant` 挂起本锚授权，读路径安静后立即受理。
- **c3h 锚窗口**：锚后空转 `ANCHOR_WAIT` 个 tick 再发行 0——供给起点对齐显示 Va 开拉点，发射与消费平行恒速。余量覆盖 grant+DDR 首字 ~0.2 行 + demosaic 3 行窗冲洗 2 行。
- 行不丢原则：tick 到而数据未就绪 → delayed 计数，就绪拍立即发射；断粮救援（tlb<1 行整）兜底。
- 双行 RAM 乒乓：读路径恒超前发射路径 1 行，DDR 延迟与发射期重叠。

### 5.3 源切换 = 上电复刻（v4.10c3b~c3f）

```
CSR 写 → sw_pending → 等当前源 vs 下降沿（VFP 间隙，帧界生效）
t0 生效拍：mux 翻转 + sw_gate 三断(valid/hs/vs) + raw 域复位 1µs
           + flush 链启动（tx 域此时不复位——继续消化旧重放流）
t0+1.25ms：flush 宽脉冲 1ms
   writer：drain 空闲拍清填充账本（frame_par 绝不清）
   reader：AXI 安全拍清发射/读路径 + m_axis_tvalid 同拍断流
             → tx 域复位 1.35µs（ISP/tlb/disp_timing 与 reader 停流同拍）
t0+2.25ms：flush_done → gate_ready=1
开门：新源首个 vs 上升沿 → 新流进 writer → 填 ≥2 帧 → reader 重新计满 → 按锚开读
```

黑屏 3~4 帧（50-67ms）一次性，零撕裂。上电引导（c3d）：上电 gate=0，首个源 vs 下降沿触发一次完全相同的复位+flush 链，上电到出画面 ≤2 帧。

### 5.4 硬纪律（历史板测实锤，**勿破**）

| # | 纪律 | 违反后果（实锤） |
|---|---|---|
| 1 | writer/reader 的 AXI 主口**不复位** | 复位掐断活跃写突发 → DDR 残留半截事务 → 8 行/帧爬行楔死 |
| 2 | `frame_par` 不进任何 flush/清零路径 | 乒乓锚被清 → 同 bank 读写冲突 → 50% 概率撕裂 |
| 3 | reader 节奏源 = disp_timing 本地 line_tick，源侧信号不得进节奏链 | v3.1~v3.3 三代死环 |
| 4 | 2FF 同步链寄存器必须 `syn_keep` | par_sync 被优化掉，前科 ×4 |
| 5 | 切换生效拍前不得动数据路径状态（等 VFP 间隙） | 帧中复位 → writer 收悬空流 → 切回黑屏 |
| 6 | DDR 基址改动必须 u_fw/u_rd **两处逐字同改** + 先对 256MB 容量界静态核算 | c3k：bit28 超界被硬核静默剥离回绕 → B 头 112 行与 A 尾重叠 → 底部闪区 |
| 7 | SV 乘法位宽 = max(操作数位宽)，大系数乘法用 32 位上下文 | pattern_gen 20 位直乘 → "半屏重新开始" |
| 8 | vlog 不容 wire/reg 先用后声明（efx_map 容忍） | 扁平化 top_cam.sv 首次入 vlog 清单暴露 4 错 |

---

## 6. DDR 接口契约摘要

详见 [ddr_interface.md](ddr_interface.md)（本节为速查）：

- 硬核 AXI 行为（板级实测）：**WVALID-先于-AWREADY 型**（AW 握手前必须拉起 WVALID，否则互等死锁）；PRE_WRITE 期间 W 传输必须计入 beat 记账；awqos=1 / arqos=0；WLAST 与段末 beat 同拍；awapcmd/awallstrb/awcobuf=0；bready/rready 提前置位。
- 端口分配：**target0 = cam0 写口**（ACLK=sys_clk_200m），**target1 = cam0 读口**（ACLK=pixel_clk 148.5M，硬核接受双异步端口时钟，Phase 0 已验证）。读写在物理口上隔离，避免小粒度写突发被大粒度读挤死。
- 地址映射与容量界（c3k 教训）：2Gb x16 → **256MB 有效地址 [27:0]**；超界位被硬核静默剥离回绕（AXI 层无感、无 SLVERR）。地址布局改动前必须静态核算，"计数全绿+数据探针干净"不能证明地址域无误。
- 布局：行槽 8KB stride（行号 << 13），行数据 7680B = 64+56 两突发各落 4KB 窗；一帧 2160×8KB = 17.6MB。A 帧 0..17.7MB，B 帧 32..49.7MB。
- 带宽账：4K@60 写侧 ≈ 1.06GB/s（LPDDR4x 峰值 ~16%），读写 turnaround 开销 ~1.6%。

---

## 7. 验证体系

- **tb_phase4**（[sim/tb_phase4.sv](file:///D:/Projs/ws-e1-cam-4K-1080-60fps-ref/sim/tb_phase4.sv)，c3m 重写）：直接例化模块链（与板级差异仅剩 DIAG 布线/DPHY/源切换），缩帧 VACT=90 / FRAME_SLOTS=100 / BEATS=960 / WORDS=120，40ms 全链仿真。
- 判据：**P1** 帧完成 / **P2** TX 突发 / **P3** rd 90/90 + dms_sol + frm 增长 / **P4** 拓扑 / **P4C 内容比特一致**（指纹 {f,l,b,16'hA5C3} 注入 → writer → AXI → DDR 模型 → reader 零扩展逐拍比对）/ **SLOW** 慢源显示周期 ≥ 槽速率。
- c3m 回归基线（`sim/v410c3m_reg.log`，vsim 24s）：`P4C-OK frames=7 cmp=432000 err=0`、`rd sol/tlast 90/90`、`late/under=00020000`、`P4-OK`、`SLOW-OK`、Errors=0。
- 回归命令（sim/ 目录）：

```
vlog -sv ../rtl/top_cam.sv ../rtl/raw_2_axi4st.sv ../rtl/pattern_gen.sv
     ../rtl/demosaic.sv ../rtl/wb_axis.sv ../rtl/rgb2yuv_axis.sv
     ../rtl/shape_pat_gen.sv ../rtl/tx_line_buf.v ../rtl/disp_timing.v
     ../rtl/frame_writer.v ../rtl/frame_reader.v tb_phase4.sv
vsim -c -voptargs="+acc" -do "run 40 ms; quit -f" work.tb_phase4 -l <log>
```

- 验证纪律：**vlog 0 Error 才允许 vsim**（vlog 错误曾被管道过滤吞掉 → 跑旧库假回归）；verible-syntax MCP 过 syntax 后仍须 vlog/efx_map（声明顺序/多驱动只有后两层查）；`tx_line_buf.v` 是 `.v` 不是 `.sv`。

---

## 8. 板测状态与诊断

### 8.1 UART 诊断速查（COM8@115200，c3m DIAG 重映射后）

| DIAG | 地址 | 语义 | 健康值 |
|---|---|---|---|
| DIAG1 | 0x04 | 恒 0 占位（CDC FIFO 退役） | 0/0 |
| DIAG4 | 0x10 | {fw_sof_free, dms_sol_free} 自由跑 | fw_sof +60/s；dms_sol 圈增 ~1424 |
| DIAG5 | 0x14 | {yuv_v_cnt, frm_cnt=tx_vsync 沿} | frm 0.5s 窗 +30 = 60Hz |
| DIAG8 | 0x20 | disp_timing {late, under} | 稳态 late 不增长、under=0 |
| DIAG9 | 0x24 | **指纹探针 B**（demosaic 入口）{err, delta, v} | err=0 |
| DIAG11 | 0x2C | DDR 状态 {err,mcst,done,st,lock,cfg_ok,...} | err=0 lock=1 st=3 mcst=9 done=1 |
| DIAG14/15 | 0x38/0x3C | rd 回放态 / {late,miss,err} | st=3，全 0 |
| DIAG16 | 0x40 | **双钟对照** {rd_sol, beat_px} | beat_px 滚动 = 回放→显示通路活 |
| DIAG17 | 0x44 | **指纹探针 A**（writer 入口）{err, delta, v} | err=0 |
| DIAG18 | 0x48 | 0.75s 绝对窗 {df, live÷64} | df=45，live≈1,458,000 |
| DIAG19/20 | 0x4C/0x50 | reader drop/repeat / fw 帧纪律 | 稳态 0 增长 |

指纹探针 A/B：取 data[39:30] 作 10bit 行内递增指纹，跨 sol 查 +1 连续性；A 看"源→writer 入口"，B 看"reader 回放→demosaic 入口"，分段定位错位（c3j 教训：周期图案对 δ 别名双重致盲，必须用数据域指纹 + 单调 ramp）。

### 8.2 问题状态

**已闭环**（板测证据）：256px 竖线（v4.10a 载体重构）、上电黑屏数分钟（c3d）、切换斜卷/黑屏/死桥片（c3b~c3f）、整屏周期性闪屏（c3f）、**B 固定偏移+底部闪区（c3g/h/k 三段闭环，物理根因 = FRAME_B 超界回绕）**。

**遗留**：
- **A. 偶发切换撕裂**：图案→摄像头偶发，切回再切回即恢复；头号嫌疑 = 切换瞬间恰逢 writer 帧发布沿的在途 done 脉冲与新流首发布的 bank 仲裁竞争。
- **D. 顶部 2 行滚屏**（慢爬）：数据域行相位错位，两条成形路径同现；c3l 补偿实验无效已回退，**排查暂停**（用户指示）。
- 固件 main.c 四个打印标签（fr:/shp:/cdc:/v4）语义未随 c3m 更新——判读按 §8.1 表，勿按打印标签旧注释。

---

## 9. 工具链与部署

- **出片**（项目根，~3 分钟）：不要依赖 efx_run.bat 自动 setup（终端残留 EFINITY_HOME 时会跳过 → PYTHONHOME 缺失直接死）。显式全套变量直调：

```
$env:EFINITY_HOME='D:/efinity/2026.1'
$env:PYTHONHOME='D:\efinity\2026.1\python311'
$env:EFINITY_USER_DIR_INI="$env:LOCALAPPDATA/efinity/user_dir.ini"
$env:EFXPT_HOME='D:/efinity/2026.1/pt'; $env:EFXPGM_HOME='D:/efinity/2026.1/pgm'
$env:PATH='D:\efinity\2026.1\python311\bin;D:\efinity\2026.1\bin;D:\efinity\2026.1\pgm\bin;' + $env:PATH
& 'D:\efinity\2026.1\python311\bin\python.exe' 'D:\efinity\2026.1\scripts\efx_run.py' --prj ws-e1-cam-ddr-csi2.xml -f compile
```

PASS 判据：map/interface/pnr/pgm 全 PASS。跨时钟域 WARNING（pixel_1080/sys_200m/dphy 之间）为异步 CDC 未约束路径，历来同源，非缺陷。

- **部署三连**：① `ftdi_pgm.bat` 烧 bit；② openocd 加载 ELF（cwd=sw）；③ COM8@115200 读计数，'c'/'p' 切源。
- 回退：以 [milestone-v4.10c3m.md §10](milestone-v4.10c3m.md) 的文件锚点清单为准。

---

## 10. 已知过时记载（阅读旧文档时注意，未改原文）

| 位置 | 过时内容 | 事实 |
|---|---|---|
| readme.md | 仍是 v3 直通 demo 时代描述（无 DDR、37.125M 面板钟） | 当前为 v4.10c3m DDR 回放架构 |
| frame_writer.v 头注 | "FRAME_B=0x1100_0000"（L18）、"8 行槽 x 75 字"（L22） | B 已改 0x0200_0000（顶层覆盖）；64b 载体行槽为 120 字 |
| ddr_interface.md §1 | "ACLK_0/1 均绑 sys_clk_200m" | ACLK_0=200M，**ACLK_1=pixel_clk 148.5M**（peri.xml 实绑） |
| doc/shape_video_axis.md | 纯 4K shape 链文档 | 模块已随 c3m 删除，文档仅存档 |
| 各 TB 中 WORDS=75 | 40b 载体时代遗留 | 64b 载体 = 120 字（tb_phase4 已更新） |

## 11. 文档索引

| 文档 | 内容 |
|---|---|
| [milestone-v4.10c3m.md](milestone-v4.10c3m.md) | 当前基线完整存档（版本演进/回退锚点/下一步计划） |
| [milestone-v4.10c3f.md](milestone-v4.10c3f.md) | c3f 时点存档（切换/复位机制演进史） |
| [ddr_interface.md](ddr_interface.md) | DDR 硬核接口契约 + 6 轮调试史 + c3k 容量界教训 |
| [phase0~4-summary.md](phase4-summary.md) | 各建设阶段总结 |
| `ddr_ctrl_model/docs/user-guide.md` | TJ DDR AXI 行为模型用户手册（独立仿真模型，含板级标定参数） |
| `axi-interconnect-core-ug-v1.8.md` | Efinity AXI Interconnect IP 用户指南（多主共享 DDR 口时的候选方案） |
