[English](milestone-v4.10c3m.en.md) | 中文
# 里程碑：v4.10c3m — B 问题闭环 + camera_path 扁平化

日期：2026-10-22
状态：**板测可用基线（有输出确认）**。B 问题（固定偏移+底部闪区）板测闭环，
整链扁平化后仿真/出片全绿。遗留 A（偶发切换撕裂）、D（顶部 2 行滚屏，暂停）。

本文档用途：完整设计存档，取代 [milestone-v4.10c3f.md](milestone-v4.10c3f.md)。
后续改动若引入回归，可按 §10 回退到本版本。

---

## 1. 版本标识

| 项 | 值 |
|---|---|
| 版本号 | v4.10c3m |
| bitstream | `outflow/ws-e1-cam-ddr-csi2.bit`（2026-10-22 编译，map/interface/pnr/pgm 全 PASS） |
| 顶层 | `top_cam_demo`（Titanium TJ180A484S，Efinity 2026.1） |
| 回归 | `sim/v410c3m_reg.log`：P4-OK + P4C-OK + SLOW-OK 全绿，Errors=0 |
| 关键文件 | `rtl/top_cam.sv`（扁平网表）`rtl/top_cam_demo.sv` `rtl/frame_writer.v` `rtl/frame_reader.v` `rtl/pattern_gen.sv` `sim/tb_phase4.sv` |
| 已删除 | `rtl/camera_path.sv` `rtl/shape_video_axis.sv` `rtl/async_path_fifo.v` `rtl/replay_pat_gen.sv` |

---

## 2. 系统架构与数据流

双 IMX415 CSI-2 摄像头 → DDR 帧缓存回放 → MIPI CSI-2 TX 出面板（4K@60）。
cam0 = 活动链路（DDR 回放），cam1 = 无源预留（rd 输入置 0）。

**v4.10c3m 扁平化**：camera_path 层删除，原 DISP_V4=1 网表直移 top_cam.sv；
DISP_V4=0 分支（shape_video_axis / async_path_fifo / replay_pat_gen）随
文件一并退役。显示成形唯一路径 = tx_line_buf + disp_timing（v4 链，
cam0/cam1 统一）。

```
IMX415 ──CSI-2──> my_csi2_rx (64b Generic Frame Mode, RAW10 低 40b 有效)
                    │
 pattern_gen ────────┤  top_cam 源 mux（CSR CTRL[2] pat_en）
                     │  + 切入门 sw_gate（c3b）+ 上电引导（c3d）
                     v
               raw_2_axi4st (40b AXIS, 滑动窗/DT 门控)   [raw 域 200M]
                     │
                     │ {24'h0, tdata[39:0]} 零扩展（cap 赋值，v4.10 接入约定）
                     v
               frame_writer (top_cam_demo, aclk=200M)
                 512b 整除打包；行 7680B = 64+56 两突发；整帧或全无
                     v
               LPDDR4X 双 bank 帧乒乓
                 FRAME_A=0x0 / FRAME_B=0x0200_0000（c3k 修正）；行槽 8KB
                     v
               frame_reader (top_cam_demo, aclk=pixel_clk 148.5M)
                 每字 8 拍切片；c3g 残帧放弃 + c3h 锚窗口（ANCHOR_WAIT=78）
                     │ rd_t* 直通（与 pixel_clk 同钟，无 CDC；连线层切 [39:0]）
                     v
  top_cam 内联扁平网表（c3m）：
    demosaic (RAW10→RGB×4px) → wb → rgb2yuv (UYVY 64b)
                     │
    shape_pat_gen 直注 mux（DBG_SHAPE_PAT 编译期 + CSR CTRL[6] 运行时）
                     v
    tx_line_buf (DEPTH_WORDS=2048) → disp_timing (LINE_CLKS=1100,
    FRAME_SLOTS=2250/1125) → my_csi2_tx → 桥片 → 面板
```

- 复位双域：raw 域 `raw_aresetn = sys_clk_200m_rstn & sw_rstn`；
  pixel 域 `pixel_rst_n = tx_pixel_clk_rstn & sw_rstn_tx`。
- **ISP 全链（demosaic/wb/rgb2yuv/tlb/disp_timing）算法自 v4.9d 未动**；
  c3g~c3m 只动 reader 授权/复位、图案诊断源、DDR 基址与结构扁平化。

---

## 3. 关键参数

| 参数 | 值 | 说明 |
|---|---|---|
| 分辨率/帧率 | 3840×2160 @ 60Hz 目标 | 显示帧率受供给行数经帧首水位门影响（见 §7-D） |
| cam0 显示槽 | DISP_FRAME_SLOTS=2250 | VSP10+VBP72+VACT2160+VFP8+pad0（CTA 4K60 标准值） |
| cam1 显示槽 | DISP_FRAME_SLOTS=1125 | 1080p60（c3m 起参数化，例化点覆盖） |
| RAW10 源行（cam0） | 960 拍 × 40b = 3840px | LINE_TOTAL_PIX=3864，LEAD/TRAIL=12，SKIP_FIRST=21 |
| 64b 回放行 | 120 字（7680B）= 967 发射拍 | WB0=64 + WB1=56 beat |
| 帧布局 | A=0x0, **B=0x0200_0000** | c3k 修正；u_fw/u_rd 两处逐字一致；容量账见 ddr_interface.md §9 |
| ANCHOR_WAIT | 78（板级）/ 4（tb） | c3h 锚窗口 = VSP+VBP(82) − 余量 4 |
| 时钟域 | sys_clk_200m（raw/writer）/ pixel_clk=148.5M（显示/reader/ISP/TX） | reader v4 换域，链内无 CDC |
| CSR 切换 | 'c'=摄像头 'p'=图案，CTRL[6]=dbg 直注 | 帧界生效；CTRL[6] 变化沿亦触发源切换软复位 |

---

## 4. 核心机制

### 4.1 writer：整帧或全无（v2 架构，未改）
- 坏帧关帧**不翻 par 不发布**；帧满翻 par + 发布 `wr_frame_done` 单拍。
- **frame_par 是 writer/reader 唯一 bank 仲裁锚**：writer 恒写 par，reader
  恒读 ~par。任何清零/改动 par 的逻辑都会引入同 bank 读写冲突（c3d 教训）。

### 4.2 帧级仲裁（reader，v4.9 架构 + c3g/c3h 修正）
- `wr_frame_done` 2FF 取沿 = 帧请求；**起步门 done_cnt>=2** 才解禁。
- **授权锚 = disp_sof 下降沿**；沿堆积 → drop；无沿 → repeat。
- **c3g 残帧放弃**：锚拍 reader 若仍在发射上一帧残行（st!=S_IDLE），
  frame_grant 会因单拍沿被错过 → 等 disp_stall 救援才受理 → 新帧行 0 固定
  迟到 D 行 → 帧尾 GATE 冻结 D 行 = **固定偏移+底部闪区**（B 问题死锁结构，
  tb 实测锚后 94.6 行才发行 0 vs 显示 Va[0] 开拉 6 行）。修复：锚拍
  `abort_frame` 回 S_IDLE 断流 + `pend_grant` 挂起本锚授权，读路径安静
  （r_quiet）后立即受理 → 行 0 提前 ~90 行。在途旧突发自然收完（同 ID
  按序，grant 时旧数据已落 bank，新帧行 0 同址覆盖）。
- **c3h 锚窗口对齐**：锚后先空转 ANCHOR_WAIT 个 tick 再发行 0——供给起点
  对齐显示 Va 开拉点（VSP+VBP−余量），发射与消费平行恒速，消除 c3g 首版
  背压跟随态（帧尾滞后+abort 断流破坏 demosaic 3 行窗 = 板测顶+底恒闪）。
  余量须覆盖 grant+DDR 首字 ~0.2 行 + demosaic 3 行窗冲洗 2 行。
- 断粮救援（tlb<1 行整）保留兜底。

### 4.3 源切换 = 上电复刻（v4.10c3f 形态，未改）
```
CSR 写 → sw_pending → 等当前源 vs 下降沿（VFP 间隙）
t0 生效拍：mux 翻转 + sw_gate 三断(valid/hs/vs) + raw 域复位 1µs
           + flush 链启动（tx 域此时不复位——继续消化旧重放流）
t0+1.25ms：flush 宽脉冲 1ms 开始
   writer：drain 空闲拍清填充账本；frame_par 绝不清（乒乓锚）
   reader：AXI 安全拍清发射/读路径 + m_axis_tvalid 同拍断流
             → tx 域复位 1.35µs（demosaic/wb/yuv/shape/tlb/disp_timing，
               与 reader 停流严格同步）
t0+2.25ms：flush_done → gate_ready=1
开门：新源首个 vs 上升沿 → 新流进 writer → 填 ≥2 帧发布
     → reader done_cnt 重新计满 → 按锚开读
```
总切换黑屏 ~3-4 帧（50-67ms），一次性，零撕裂（稳态；偶发撕裂见 §7-A）。

### 4.4 上电引导（c3d，未改）
上电 gate=0，等首个源 vs 下降沿触发一次与切换完全相同的复位+flush 链。
上电到出画面 ≤2 帧。

### 4.5 硬纪律（历史板测实锤，勿破）
1. **writer/reader 的 AXI 主口不复位**——复位脉冲掐断活跃写突发 → DDR
   残留半截事务 → 楔死（2026-10-20 实锤）。
2. **frame_par 不进任何 flush/清零路径**。
3. **reader 节奏源 = disp_timing 本地 line_tick**，源侧信号不得进节奏链
   （v3.1~v3.3 三代死环教训）。
4. 2FF 同步链寄存器必须 `syn_keep`（par_sync 被优化掉的前科×4）。
5. 切换生效拍前不得动任何数据路径状态（等 VFP 间隙）。
6. **DDR 基址改动必须 u_fw/u_rd 两处逐字同改**，且先对 256MB 容量界
   （0x1000_0000）静态核算——超界位被硬核静默剥离回绕，AXI 协议层无感
   （c3k 教训，详见 doc/ddr_interface.md §9）。
7. **SV 乘法位宽 = max(操作数位宽)**：大系数乘法必须 32 位上下文
   （pattern_gen 单调 ramp 20 位直乘曾"半屏重新开始"，2026-10-22 实锤）。
8. **vlog 不容 wire/reg 先用后声明**（efx_map 容忍前向引用）——进 vlog
   清单的文件声明必须先于使用（c3m 扁平化时 top_cam.sv 首次入清单暴露）。

---

## 5. 诊断体系（UART COM8@115200，板测判读）

**c3m DIAG 重映射**（寄存器布局不变，语义更新；原 DIAG1 CDC FIFO 与
shape_video_axis 黑匣子随扁平化退役）：

| DIAG | 地址 | c3m 语义 | 健康值 |
|---|---|---|---|
| DIAG1 | 0x04 | **恒 0 占位**（CDC FIFO 退役） | 0/0 |
| DIAG4 | 0x10 | {fw_sof_free, dms_sol_free} 16bit 自由跑回绕 | fw_sof +60/s=满速；dms_sol 圈增量 ~1424 |
| DIAG5 | 0x14 | {yuv_v_cnt, frm_cnt}，frm=tx_vsync 沿（显示域） | frm 0.5s 窗 +30 = 60Hz |
| DIAG8 | 0x20 | disp_timing {late[31:16], under[15:0]} | 稳态 late 不增长、under=0（启动期可 +1~2） |
| DIAG9 | 0x24 | **指纹探针 B**（demosaic 入口，pixel 域）{err[31:16], delta[25:16], v[15]} | err=0 |
| DIAG11/12/13 | 0x2C~0x34 | DDR 状态 / fw 心跳（不变） | err=0 lock=1 cfg=1；frm 稳增 ovf=pad=0 |
| DIAG14/15 | 0x38/0x3C | rd 回放态（不变） | st=3，late/miss/err=0 |
| DIAG16 | 0x40 | **双钟对照**：{rd_sol（rd_clk 域）, beat_px（pixel_clk 域）} | beat_px 滚动 = 回放→显示通路活 |
| DIAG17 | 0x44 | **指纹探针 A**（writer 入口，raw 域）{err, delta, v}，格式同 DIAG9 | err=0 |
| DIAG18 | 0x48 | 0.75s 绝对窗 {df, live÷64}（不变） | df=45，live≈1,458,000 |
| DIAG19/20 | 0x4C/0x50 | reader drop/rpt / fw 帧纪律（不变） | drop/rpt 稳态 0 增长；fw2 全 0 |

指纹探针 A/B 算法：对有效拍取 data[39:30] 为 10bit 行内递增指纹，跨 sol
检查 +1 连续性，破坏记 err + 锁存 delta（= 错位幅度）。A 看"源→writer
入口"段（err 增长 = 源侧错位），B 看"reader 回放→demosaic 入口"段
（err 增长而 A 干净 = DDR/reader 段错位）。

**固件 main.c 打印标签尚未跟随 c3m 更新**（待办）：`fr:`（读 DIAG17，
旧意 tlast/sol——现为探针 A）、`shp:`（DIAG8/9 旧意 shape 黑匣子——现为
dtg late/under + 探针 B）、`cdc:`（DIAG1 恒 0/0）、`v4:` 低位 beat 字段
现为 pixel 域 beat_px。板测判读按上表，勿按打印标签旧注释。

---

## 6. 版本演进（v4.10c3f → v4.10c3m）

| 版本 | 变更 | 教训/结果 |
|---|---|---|
| v4.10c3f | tx 域复位与 reader 停流同拍 | 显示链二次污染根除（c3f 基线，板测整屏闪屏根除） |
| v4.10c3g | reader 锚拍**残帧放弃**（abort_frame + pend_grant） | B 问题死锁结构定位（tb 锚后 94.6 行 vs 开拉 6 行）；首版引入背压跟随态：顶+底恒闪（abort 断流破坏 demosaic 3 行窗），板测实锤 |
| v4.10c3h | **锚窗口对齐**：ANCHOR_WAIT 空转（板 78/tb 4） | 供给起点对齐 Va 开拉点，发射消费平行恒速；c3g 背压跟随态根除——B 问题行为修复完成（物理根因未除，见 c3k） |
| v4.10c3i | 指纹图案 mod-256（pat_sel=2 诊断版） | 对 δ≡0(mod 256) 错位致盲——诊断武器第一代局限 |
| v4.10c3j | **指纹探针 A/B**（DIAG17/DIAG9）+ 图案 mod-1024 | δ=2048 地址别名令 mod-1024 图案完全失明（2048≡0 mod 1024）——"数据序列完美≠物理落点正确"，双重致盲教训 |
| **v4.10c3k** | **FRAME_B 0x1100_0000→0x0200_0000**（u_fw/u_rd 两处） | B 问题物理根因：B 基址 bit28 超 2Gb 器件 256MB 容量界，硬核剥离回绕落 A 帧行 2048 → B 头 112 行与 A 尾重叠读写竞态 = 底部闪区。板测闪区消失，**B 闭环**。图案 pat_sel=2 改全帧单调灰度 ramp（无周期，任意 δ≥1 可见 ~0.47δ 跳变；乘法 32 位位宽教训）。行为模型不建模容量回绕——仿真结构性不复现，只能静态核算+板测把守 |
| v4.10c3l | D 问题排查：试 VSP 8/VFP 10 + WAIT 76 | 板测无效（滚屏与 vsync↔数据相对时序无关，是数据域行相位错位），**已回退** CTA 标准值；排查暂停 |
| **v4.10c3m** | **camera_path 扁平化** | 删 DISP_V4=0 分支四文件，DISP_V4=1 网表内联 top_cam.sv；tb_phase4 重写直接例化链（判据不变）；sw_src 监视 3bit→2bit；DIAG1 退役、DIAG4/5/8/9/16/17 重映射；DISP_FRAME_SLOTS 参数化（2250/1125）。verible 0 错 / vlog 0 错 0 警（前向引用 4 错，声明前移修复）/ vsim 全绿 / 出片全 PASS / **板测有输出**。**当前版本** |

---

## 7. 板测状态

### 已解决（板测证据）
- 256px 竖线（v4.10a）、行 0 抢跑（回退）、上电黑屏数分钟（c3d）、切换
  斜卷/黑屏/死桥片（c3b~c3f）、整屏周期性闪屏（c3f）。
- **B 固定偏移+底部闪区（c3g/h/k 三段闭环）**：行为层残帧放弃+锚窗口
  （c3g/h）先消除症状，物理根因 FRAME_B 超界回绕（c3k）板测根除。
  诊断武器演化：mod-256 → mod-1024（均被 δ 别名致盲）→ 单调 ramp + 数据域
  指纹探针 A/B。

### 遗留（当前活跃问题）
- **A. 偶发切换撕裂**：图案→摄像头偶发撕裂+闪屏，切回再切回即恢复
  （c3f 遗留，头号嫌疑：切换瞬间恰逢 writer 帧发布沿的在途 done 脉冲
  与新流首发布的 bank 仲裁竞争）。
- **D. 顶部 2 行滚屏**（慢速爬行）：数据域行相位错位——两条成形路径
  （disp_timing 回放 / 直注）同现，与 vsync↔数据相对时序无关（c3l
  VSP/ANCHOR 补偿无效已回退）。**排查暂停**（用户指示先不管）。
- **C→已转化**：c3f 时代"探针冻结恒 0"（rd_clk 域复位未释放）由 c3m
  DIAG16 双钟对照绕开（beat_px 不依赖 rd_rstn）；**固件 main.c 4 个打印
  标签/判读过时**（fr:/shp:/cdc:/v4，见 §5），待更新。

---

## 8. 验证体系

- **tb_phase4**（sim/，c3m 重写）：直接例化模块链（与板级差异仅剩 DIAG
  布线/DPHY/源切换），缩帧 VACT=90/FRAME_SLOTS=100，40ms 全链仿真。
  判据：P1 帧完成 / P2 TX 突发 / P3 rd 90/90 + dms_sol + frm 增长 /
  P4 拓扑 / **P4C 内容比特一致**（指纹 {f,l,b,16'hA5C3} 注入→writer→AXI→
  DDR 模型→reader 零扩展逐拍比对）/ SLOW 慢源显示周期 ≥ 槽速率。
- **c3m 回归结果**（v410c3m_reg.log，vsim 24s）：
  `P4C-OK frames=7 cmp=432000 err=0`、`rd sol/tlast 90/90`、
  `dms_sol=542 yuv_v=520320 frm=7`、`late/under=00020000`、
  `P4-OK`、`SLOW-OK late_delta=0 drop=3 rpt=4`、Errors=0。
- **纪律**：vlog **0 Error 才允许 vsim**（vlog 错误曾被管道过滤吞掉 →
  假回归）；verible-syntax MCP 过 syntax 后仍须 vlog/efx_map（声明顺序/
  多驱动只有后两层查）。tx_line_buf 是 `.v`。
- 回归命令（sim/ 目录，c3m 起）：
  ```
  vlog -sv ../rtl/top_cam.sv ../rtl/raw_2_axi4st.sv ../rtl/pattern_gen.sv
       ../rtl/demosaic.sv ../rtl/wb_axis.sv ../rtl/rgb2yuv_axis.sv
       ../rtl/shape_pat_gen.sv ../rtl/tx_line_buf.v ../rtl/disp_timing.v
       ../rtl/frame_writer.v ../rtl/frame_reader.v tb_phase4.sv
  vsim -c -voptargs="+acc" -do "run 40 ms; quit -f" work.tb_phase4 -l <log>
  ```

## 9. 工具链与部署

- **出片**（项目根，全程 ~3 分钟）：**不要依赖 efx_run.bat 自动 setup**——
  终端残留 EFINITY_HOME 时它跳过 setup.bat → PYTHONHOME 缺失 → Python
  `No module named 'encodings'` 直接死。显式全套变量直调（照 setup.bat）：
  ```
  $env:EFINITY_HOME='D:/efinity/2026.1'
  $env:PYTHONHOME='D:\efinity\2026.1\python311'
  $env:EFINITY_USER_DIR_INI="$env:LOCALAPPDATA/efinity/user_dir.ini"
  $env:EFXPT_HOME='D:/efinity/2026.1/pt'; $env:EFXPGM_HOME='D:/efinity/2026.1/pgm'
  $env:PATH='D:\efinity\2026.1\python311\bin;D:\efinity\2026.1\bin;D:\efinity\2026.1\pgm\bin;' + $env:PATH
  & 'D:\efinity\2026.1\python311\bin\python.exe' 'D:\efinity\2026.1\scripts\efx_run.py' --prj ws-e1-cam-ddr-csi2.xml -f compile
  ```
  PASS 判据：map/interface/pnr/pgm 全 PASS。跨时钟域 WARNING（pixel_1080/
  sys_200m/dphy 之间）为异步 CDC 未约束路径，历来同源，非缺陷。
- **部署三连**：① ftdi_pgm.bat 烧 bit ② openocd 加载 ELF（cwd=sw）③
  COM8@115200 读计数，'c'/'p' 切源。

## 10. 回退指引

本版本 = 下列文件的全部当前内容。若后续改动引入回归，按此清单恢复：

| 文件 | 本版本关键锚点 |
|---|---|
| rtl/top_cam.sv | 扁平网表：cap 零扩展赋值 + u_raw/u_demosaic/u_wb/u_rgb2yuv/g_shape_pat/mux/u_tlb/u_dtg 内联直连；声明块先于使用（前向引用）；path_diag 恒 0；探针 A/B；DIAG16 双钟；sw_src 2bit {dbg_sel,pat_en}；wb 生效 = pat_en?0x40:CSR；rgb2yuv blk_clip=!pat_en |
| rtl/top_cam_demo.sv | u_cam_0：LINE_SKIP_FIRST=21/DBG_SHAPE_PAT(1)/DISP_FRAME_SLOTS(2250)/VSP10+VFP8；u_cam_1：DISP_FRAME_SLOTS(1125)；u_fw/u_rd **FRAME_B=33'h0_0200_0000 两处同改**；u_rd ANCHOR_WAIT(12'd78) |
| rtl/frame_reader.v | c3g 残帧放弃（abort_frame/pend_grant/r_quiet，pend_grant 单驱动）；c3h ANCHOR_WAIT 锚窗口（S_WAIT 空转 + anchor_cnt） |
| rtl/frame_writer.v | c3f 形态不变：flush_i + drain 空闲拍 flush 分支（不含 frame_par 赋值） |
| rtl/pattern_gen.sv | pat_sel=2 单调灰度 ramp：`10'((32'(live_ln)*32'(MONO_COEF))>>11)`（勿回退 20 位直乘） |
| rtl/disp_timing.v | LINE_CLKS=1100 / PAD_L 由槽结构余项自洽推导（c3l 试改已回退，勿再动 VSP/VFP 补偿） |
| sim/tb_phase4.sv | 直接例化链 + raw_t*[39:0] 显式声明；判据 P4C/rd90/P4/SLOW |
| ws-e1-cam-ddr-csi2.xml | 无 camera_path/shape_video_axis/async_path_fifo/replay_pat_gen 四行 |

建议：立即 git commit 打锚点（文件级回退成本高）。

---

## 11. 下一步（遗留问题攻坚计划）

1. **A 偶发切换撕裂**：审 frame_reader 授权/next_par 逻辑（done 沿 2FF
   滞留与 fire 清零的竞争窗口）；板测快速循环切换复现 + 计数快照。
2. **D 顶部 2 行滚屏**（暂停中）：数据域行相位错位方向——对照探针 A/B
   delta 与 DIAG8 late 的行相位账；备选：定制 Vtotal 拉回 60.00。
3. **main.c DIAG 打印对齐 c3m 语义**：fr:/shp:/cdc:/v4 四处标签与判读
   更新（低风险，纯固件）。
4. （可选）地址序列探针（awaddr/araddr 采样）——c3k 后 ddr_interface.md
   §9.4 建议的地址域最后一道闸。
