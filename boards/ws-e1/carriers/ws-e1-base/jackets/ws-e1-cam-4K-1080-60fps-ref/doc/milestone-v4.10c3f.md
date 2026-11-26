[English](milestone-v4.10c3f.en.md) | 中文
# 里程碑：v4.10c3f — 64b 载体 + 全路径同步复位切换

日期：2026-10-22
状态：**已被 v4.10c3m 取代**（B 问题 c3g/h/k 闭环 + camera_path 扁平化），
最新基线见 [milestone-v4.10c3m.md](milestone-v4.10c3m.md)。本文保留为
c3f 时点存档；其中 §7 遗留问题 B 已在 c3k 根因闭环（FRAME_B 超界回绕），
C 已由 c3m DIAG16 双钟对照转化，§11 计划以新文档 §11 为准。

本文档用途：完整设计存档。后续改动若引入回归，可按 §10 回退到本版本。

---

## 1. 版本标识

| 项 | 值 |
|---|---|
| 版本号 | v4.10c3f |
| bitstream | `outflow/ws-e1-cam-ddr-csi2.bit`（2026-10-22 编译，map/pnr/pgm 全 PASS） |
| 顶层 | `top_cam_demo`（Titanium TJ180A484S，Efinity 2026.1） |
| 回归 | `sim/v410c3f_reg.log`：P4-OK + P4C-OK（内容比特一致） |
| 关键文件 | `rtl/frame_writer.v` `rtl/frame_reader.v` `rtl/top_cam.sv` `rtl/top_cam_demo.sv` `rtl/camera_path.sv` |

---

## 2. 系统架构与数据流

双 IMX415 CSI-2 摄像头 → DDR 帧缓存回放 → MIPI CSI-2 TX 出面板（4K@60）。
cam0 = 活动链路（DDR 回放），cam1 = 无源预留（rd 输入置 0）。

```
IMX415 ──CSI-2──> my_csi2_rx (64b Generic Frame Mode, RAW10 低 40b 有效)
                     │
 pattern_gen ────────┤  top_cam 源 mux（CSR CTRL[2] pat_en）
                     │  + 切入门 sw_gate（c3b）+ 上电引导（c3d）
                     v
               raw_2_axi4st (40b AXIS, 960 拍/行=4800B, 滑动窗/DT 门控)
                     │
                     │ {24'h0, tdata[39:0]} 零扩展（v4.10 接入约定）
                     v
 camera_path[DISP_V4=1] ── 直通（无 CDC，reader 已在显示域）
                     │
                     v
               frame_writer (aclk=200M)
                 输入 64b × 8 拍 = 512b 整除打包（v4.10，无 LCM 相位转换）
                 行 7680B = 120 字；AXI4 写 512b/beat，突发 64+56（4KB 对齐）
                 8 行槽 + 8 深 desc 队列；整帧或全无
                     │
                     v
               LPDDR4X 双 bank 帧乒乓
                 FRAME_A=0x0 / FRAME_B=0x1100_0000；行槽 8KB×2160 行=17.6MB/帧
                     │
                     v
               frame_reader (aclk=pixel_clk 148.5M, v4 换域)
                 每 512b 字 8 拍切片 [64k+63:64k]；行 967 拍 < 1100 行预算
                 双行 RAM 乒乓，读恒超前发射 1 行
                     │ 64b 直通（连线层切 [39:0]）
                     v
     demosaic (RAW10→RGB×4px) → wb → rgb2yuv (UYVY 64b)
                     │
     shape_video_axis（诊断直注入口，CSR CTRL[6]）
                     v
               tx_line_buf → disp_timing_gen → my_csi2_tx → 桥片 → 面板
```

**ISP 全链（demosaic/wb/rgb2yuv/shape/tlb）自 v4.9d 未动**——v4.10 只改
载体（writer/reader）与切换/复位（top_cam*），缩小回归面。

---

## 3. 关键参数

| 参数 | 值 | 说明 |
|---|---|---|
| 分辨率/帧率 | 3840×2160 @ 60.000Hz | 显示恒 60Hz，与源 ppm 解耦 |
| VACT / 帧槽 | 2160 / 2250 tick | 90 pad 行 |
| RAW10 源行 | 960 拍 × 40b = 4800B | raw_2_axi4st 输出 |
| 64b 回放行 | 120 字（7680B）= 967 发射拍 | WB0=64 + WB1=56 beat |
| GROUPS_PER_LINE | 24 组 × 8 拍 × 64b | 无 2560b 组相位（v4.10 根除竖线） |
| 帧布局 | A=0x0, B=0x1100_0000 | 行距 8KB，B 在 A 帧尾外 |
| 时钟域 | sys_clk_200m（raw/writer）/ pixel_clk=148.5M（显示/reader/ISP/TX） | reader v4 已换域，链内无 CDC |
| CSR 默认 | 0xB4EBC814（**上电默认摄像头**） | 例化点传参覆盖默认值的教训见 §6 |
| CSR 切换 | 'c'=摄像头 'p'=图案（UART 命令写 CTRL） | 帧界生效，见 §5.3 |

---

## 4. 核心机制

### 4.1 writer：整帧或全无（v2 架构，未改）
- 坏帧（队满污染/帧中 sof）关帧**不翻 par 不发布**——DDR 中永远只有完整帧。
- 帧满（VACT-1 行 drain 完成）翻 par + 发布 `wr_frame_done` 单拍（200M 域）。
- **frame_par 是 writer/reader 唯一 bank 仲裁锚**：writer 恒写 par，reader
  恒读 ~par。任何清零/改动 par 的逻辑都会引入同 bank 读写冲突（c3d 教训）。

### 4.2 帧级仲裁（reader，v4.9 架构）
- `wr_frame_done` 200M→148.5M 经 2FF+syn_keep 取沿 = 帧请求；par 电平 2FF。
- **起步门 done_cnt>=2** 才解禁（乒乓安全：读的 bank 不会被下一帧覆盖）。
- 有请求沿 → 切最新完整帧；无沿 → 重读当前 bank（repeat）；沿堆积 → drop。
- **授权锚 = disp_sof 下降沿**（Vs 起点 = Va[0] 前 41 行）——帧界相位钉扎
  （v4.6/4.8 无锚斜卷根除）。断粮救援（tlb<1 行整）兜底。

### 4.3 源切换 = 上电复刻（v4.10c3f 完整时序）
```
CSR 写 → sw_pending → 等当前源 vs 下降沿（VFP 间隙）
t0 生效拍：mux 翻转 + sw_gate 三断(valid/hs/vs) + raw 域复位 1µs
           + flush 链启动（tx 域此时不复位——继续消化旧重放流）
t0+1.25ms：flush 宽脉冲 1ms 开始
   writer：drain 空闲拍（d_st==D_SETUP && 队列空 && !awvalid && !wvalid）
           清填充账本；frame_par 绝不清（乒乓锚）
   reader：AXI 安全拍（R_IDLE/R_GAP/R_DONE 且 !arvalid）清发射/读路径
           + m_axis_tvalid 同拍断流 + flush_fire 单拍脉冲
             → tx 域复位 1.35µs（demosaic/wb/yuv/shape/tlb/disp_timing，
               与 reader 停流严格同步——c3f 核心修正）
t0+2.25ms：flush_done → gate_ready=1
开门：新源首个 vs 上升沿 → 新流进 writer → 填 ≥2 帧发布
     → reader done_cnt 从 0 重新计满 → 按 disp_sof 锚开读
```
总切换黑屏 ~3-4 帧（50-67ms），一次性，零撕裂。

### 4.4 上电引导（c3d）
- 上电 gate=0，等首个源 vs 下降沿触发一次与切换完全相同的复位+flush 链
  （boot_done 标记只做一次）。消除"上电杂散流污染 demosaic 数分钟"。
- 上电到出画面 ≤2 帧。

### 4.5 断流防护与冻帧
- 新源断流 → gate 恒 0 → reader 持续重读当前 bank（rpt++）→ 显示冻结不黑。
- raw 域 sw_rst 触发源 = 帧界生效拍（**绝不在 CSR 写时复位**——c3c 教训：
  帧中复位使 writer 收悬空流）。

### 4.6 硬纪律（历史板测实锤，勿破）
1. **writer/reader 的 AXI 主口不复位**（复位域仅 200M 系统复位）——2026-10-20
   实锤：复位脉冲掐断活跃写突发 → DDR port0 残留半截事务 → 8 行/帧爬行楔死。
2. **frame_par 不进任何 flush/清零路径**。
3. **reader 节奏源 = disp_timing 本地 line_tick**，任何源侧信号不得进入节奏链
   （v3.1~v3.3 三代死环教训）。
4. 2FF 同步链寄存器必须 `syn_keep`（par_sync 被优化掉的前科×4）。
5. 切换生效拍前不得动任何数据路径状态（等 VFP 间隙）。

---

## 5. 诊断体系（UART COM8@115200，板测判读）

| 打印 | 含义 | 健康值 |
|---|---|---|
| `fw: frm/ln ovf pad` | writer 收帧/行进度；队满丢弃/pad 计数 | frm 稳增 ~32/窗；ovf=pad=0 |
| `fw2: bad drop last_line` | 坏帧关闭/丢行 | 全 0 |
| `rd: frm st ln late miss err req` | reader 回放态 | st=3，frm 稳增，late/miss/err=0 |
| `fr: rd=tlast/sol per frame` | 回放流帧锚定行数 | 2160/2160（注：c3f 探针域复位问题，恒 0/0——探针缺陷非链路缺陷，见 §7-C） |
| `v4: beat sol drop rpt` | 回放口节拍/帧仲裁 | drop/rpt 仅启动期 +1~2，稳态 0 增长 |
| `shp: srch lvl wdrop uflow df vfs vst fl gwait` | shape 门/tlb 水位 | uflow=wdrop=0 |
| `cnt: df/45 live/1458000` | 0.75s 绝对窗显示帧率/非零内容拍 | 45/45，live≈1.46M |
| `ddr: err st lock cfg` | 控制器状态 | err=0 lock=1 cfg=1 |

---

## 6. 版本演进（v4.9d → v4.10c3f）

| 版本 | 变更 | 教训/结果 |
|---|---|---|
| v4.9d | 40b 载体基线 | 60fps 稳；残留竖线+偏移+闪区 |
| v4.10a | **64b 载体重构**：writer 8拍×64b=512b 整除打包、reader 每字 8 拍切片 | 256px 竖线根除（LCM 组相位类）；首版 sr 打包 bug 致 24 个 128px 黑区，tb 校验器漏检后修复 |
| v4.10b | 行 0 抢跑（跳过 tick 门） | **证伪回退**：救援循环→频繁黑屏 |
| v4.10c2/c3 | CSR 默认源改摄像头 | 例化点 `.CTRL_RESET()` 覆盖模块默认值——改默认必须 Grep 全部例化点 |
| v4.10c3b | 切入门（三断 + 等新帧头） | 图案流中途接入 → raw 账本相位差 → 斜卷根除 |
| v4.10c3c | writer flush + 生效拍复位 | CSR 即时复位使 writer 收悬空流 → 切回黑屏；"整个路径复位"裁决起步 |
| v4.10c3d | 上电引导复位；flush 不清 frame_par | 上电黑屏数分钟根除；par 清零 = 50% 概率乒乓冲突撕裂根除 |
| v4.10c3e | reader flush（AXI 安全拍）+ 起步门归零 | 用户裁决落地：切换复刻上电，全路径复位 |
| **v4.10c3f** | **tx 域复位与 reader 停流同拍** | 显示链二次污染（复位后被旧重放流灌 1.25ms）根除；**当前版本** |

---

## 7. 板测状态

### 已解决（板测证据）
- 256px 竖线（v4.10a）、行 0 抢跑恶性回归（回退）、上电黑屏数分钟（c3d）、
  切换斜卷/黑屏/死桥片（c3b~c3f）、整屏周期性闪屏（c3f 后正常情况消失）、
  上电出画面慢（c3d 引导）。

### 遗留（当前活跃问题）
- **A. 偶发切换撕裂**：图案→摄像头偶发撕裂+闪屏，切回再切回即恢复
  （复位语义有效 → 判定仍有未清状态或时序窗口）。头号嫌疑：切换瞬间恰逢
  writer 帧发布沿，在途 done 脉冲与新流首发布的 bank 仲裁竞争。
- **B. 固定偏移 + 底部几十行闪区**（摄像头与垂直灰度可见，大小恒定，偶现
  顶部；用户点破：闪区=偏移部分）：reader 帧界相对显示帧界固定相位差
  （授权锚→实际首行进显示的延迟超 41 行窗口预算），帧尾溢出偏移行在
  "本帧尾/下帧头"间跳变 → 闪区；ppm 慢漂 → 抖动。v4.9d 遗留，与 64b
  重构无关。
- **C. 诊断探针缺陷**（不影响功能）：DIAG16 sol / DIAG17（fr: rd=0/0）的
  rd_clk 域复位（rd_rstn_148）未释放导致探针冻结恒 0；DIAG18 live 正常
  证明链路健康。待修：探针复位链。

---

## 8. 验证体系

- **tb_phase4**（sim/）：缩帧 VACT=90/FRAME_SLOTS=100，40ms 全链仿真。
  P1~P4 拓扑判据 + **P4C 内容比特一致**（源注入 ramp → writer→AXI→DDR
  模型→reader 逐拍比对，348480 拍 err=0）。
- **纪律**：vlog **0 Error 才允许 vsim**（vlog 错误曾被管道过滤吞掉，
  vsim 跑库里旧模块 → 假回归）。tx_line_buf 是 `.v` 不是 `.sv`。
- 回归命令（sim/ 目录）：
  ```
  vlog -sv ../rtl/frame_writer.v ../rtl/frame_reader.v ../rtl/camera_path.sv
       ../rtl/raw_2_axi4st.sv ../rtl/demosaic.sv ../rtl/wb_axis.sv
       ../rtl/rgb2yuv_axis.sv ../rtl/shape_video_axis.sv
       ../rtl/disp_timing_gen.v ../rtl/tx_line_buf.v tb_phase4.sv
  vsim -c -voptargs=+acc -do "run 40 ms; quit -f" work.tb_phase4
  ```

## 9. 工具链与部署

- **出片**（项目根）：显式小写环境直跑（绕开 WSL bash 陷阱——`bash` 解析到
  `WindowsApps\bash.exe` 不认 `D:/` 盘符路径；机器 EFINITY_HOME 曾为大写残留）：
  ```
  $env:EFINITY_HOME='D:/efinity/2026.1'; $env:PYTHONHOME='D:/efinity/2026.1/python311'
  $env:PATH='D:/efinity/2026.1/python311/bin;D:/efinity/2026.1/bin;...;' + $env:PATH
  # QT_PLUGIN_PATH / EFX*_HOME / EFINITY_USER_DIR_INI 等全套变量照 setup.bat
  python D:\efinity\2026.1\scripts\efx_run.py --prj ws-e1-cam-ddr-csi2.xml -f compile
  ```
  全程 ~5 分钟。PASS 判据：map/interface/pnr/pgm 全 PASS。
- **部署三连**：① `ftdi_pgm.bat` 烧 bit ② openocd 加载 ELF（cwd=sw）③
  COM8@115200 读计数，'c'/'p' 切源。
- **verible-syntax MCP**：Verilog/SV 改动后跑 check_verilog_syntax（注意：
  verible 不查声明顺序/多驱动，vlog/efx_map 才查——三层都要过）。

## 10. 回退指引

本版本 = 下列文件的全部当前内容。若后续改动引入回归，按此清单恢复：

| 文件 | 本版本关键锚点 |
|---|---|
| rtl/frame_writer.v | flush_i 端口 + drain 空闲拍 flush 分支（**不含 frame_par 赋值**）；d_st 声明前移至 desc_mem 后 |
| rtl/frame_reader.v | flush_i/flush_done_o 端口；flush_fire 安全拍清零（case 后最后赋值）；done_cnt/req_pending/boot_granted flush 清零分支 |
| rtl/top_cam.sv | 切入门 sw_gate 三断 + boot_done 引导 + fw_flush 时序链（1.25ms 延迟+1ms 宽）；tx_rst_cnt/tx_rst_act（disp_rst_req_i 触发，复位值 0）；raw_rst_trig=sw_eff_r |
| rtl/top_cam_demo.sv | u_fw.flush_i / u_rd.flush_i+flush_done_o / u_cam_0.disp_rst_req_i / u_cam_1.disp_rst_req_i(1'b0) |
| sim/tb_phase4.sv | u_fw/u_rd 例化的 flush_i(1'b0)/flush_done_o() |

建议：立即 `git add -A && git commit -m "milestone v4.10c3f"` 打锚点
（当前仓库无提交历史，文件级回退成本高）。

---

## 11. 下一步（遗留问题攻坚计划）

1. **A 偶发切换撕裂**：审 frame_reader 授权/next_par 逻辑（done 沿 2FF 滞留
   与 fire 清零的竞争窗口）；板测快速循环切换复现 + 计数快照。
2. **B 偏移+闪区**：量化"disp_sof 沿→首行进 tlb"延迟链（DDR 读首字延迟 +
   demosaic 冲洗 + tlb 水位门）对照 41 行预算；tb 加偏移测量；板测垂直灰度
   数闪区行数 = 偏移量交叉验证。
3. **C 探针修复**：DIAG16/17 rd_clk 域复位链（低优先级，不影响功能）。
