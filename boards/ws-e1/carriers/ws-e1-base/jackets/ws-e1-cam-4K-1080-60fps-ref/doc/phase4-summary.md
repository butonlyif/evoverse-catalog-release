[English](phase4-summary.en.md) | 中文

# Phase 4 总结 — 顶层集成（reader 换域 + toggle 握手 + v4 显示链接入 + 工具链 PASS）

> 状态：**RTL/工具链已完成（2026-10-21）** · 规格：SPEC-001 mod-top-v4 · 验证等级：FPGA_INTEGRATION · 终局：efx_run map/**pnr**/pgm **PASS**（v4 域内 slack +2.230ns），比特流已生成 `outflow/ws-e1-cam-ddr-csi2.bit` · **板级出图验证待用户执行**

## 1. 目标

架构 v4 收口：frame_writer（200M/raw 域）→ DDR Port0；frame_reader（148.5M 显示域 = DDR ACLK_1，Phase 0 已证硬核接受）→ demosaic→wb→rgb2yuv→**tx_line_buf→disp_timing v2**→ CSI-2 TX。显示时序唯一发生源（R1），reader 槽节拍与显示时序零偏差。

## 2. RTL 改动

### 2.1 rtl/camera_path.sv（v4 显示链分支化）

- 新参数 `DISP_V4`（默认 0）/`FRAME_SLOTS`（2250）/`PAD_L`（90）。
- 新端口 `rd_clk`/`rd_rstn`（回放 CDC 写钟 = reader 域）与 `disp_line_tick_o`（显示槽节拍输出）。
- `u_cdc` 写钟改 `rd_clk`——reader 换域后回放流同源入 FIFO（replay_pat 直注源仍 aclk，mux 互斥无害）。
- 显示尾分支化：`DISP_V4=1` → yuv → **tx_line_buf → disp_timing** → TX（shape 退役）；`=0` → v3 shape_video_axis（cam1 保持）。
- DIAG8 重映射：v4 下 = disp_timing `{late_cnt, under_cnt}`（DIAG9 shape 快照退役置 0）。

### 2.2 rtl/top_cam.sv（穿透）

- 参数 `DISP_V4`/`DISP_FRAME_SLOTS`/`DISP_PAD_L`；端口 `rd_clk`/`rd_rstn`/`disp_line_tick_o`；透传 u_path。

### 2.3 rtl/top_cam_demo.sv（g_frame_writer 分支启用）

- `FRAME_WRITER=1`、`DDR_P1_148=0`（Phase 0 验证分支退役）。
- **帧握手 toggle 方案**（Phase 2 记录的 200M 单拍直采 148.5M 丢失风险 ~25% 的收口）：`fw_frame_done`@200M 翻转 `tog200` → pixel_clk 域 2FF → 异或还原单拍 `fw_done_148`；`fw_par` 2FF 电平直采。
- 148.5M 域复位：`u_rd_rst_148`（`~ddr_cfg_ok` 门控，与 200M 侧 mc_srstn 同款 CYCLE=4）。
- frame_reader：`.aclk(pixel_clk)`、`.line_tick(disp_line_tick)`（disp_timing 同源）、`.rstn(rd_rstn_148)`。
- u_cam_0：`DISP_V4=1` + `rd_clk(pixel_clk)`/`rd_rstn`/`disp_line_tick_o` 接线；u_cam_1 保持 v3（DISP_V4 默认 0）。

### 2.4 SDC（ws-e1-cam-ddr-csi2.sdc）

- 新增 `set_clock_groups -asynchronous -group {sys_clk_200m} -group {pixel_clk}`——200M（writer/raw）↔ 148.5M（reader/disp_timing，= ACLK_1）全部跨域路径均为 2FF/toggle/异步 FIFO 结构，豁免 STA。

### 2.5 工程文件

- ws-e1-cam-ddr-csi2.xml 补 `rtl/tx_line_buf.v`、`rtl/disp_timing.v`。

## 3. 工具链验证（efx_run interface,map,pnr,pgm 全 PASS）

| 项 | 结果 |
|---|---|
| interface | PASS（peri ACLK_1=pixel_clk 维持 Phase 0 形态） |
| map | PASS：17,555 LUT4 / 13,441 FF / 472 RAM10 / 25 DSP48+56 DSP24；tx_line_buf/disp_timing 正常推断 BRAM/FSM |
| pnr | PASS |
| pgm | PASS（`outflow/ws-e1-cam-ddr-csi2.bit` 已生成） |

**时序归因**（timing.rpt Clock Relationship Summary）：

| 时钟对 | Slack | 判定 |
|---|---|---|
| **pixel_clk → pixel_clk（v4 全域：reader+disp 链）** | **+2.230 ns** | ✓ 收敛（优于 Phase 2 memcheck 形态 +2.006） |
| sys_clk_200m → sys_clk_200m | +0.095 ns | ✓ |
| pixel_clk hold | +0.029 ns | ✓ |
| sys_clk_200m ↔ pixel_clk（v4 新增跨域对） | 未出现 | ✓ async 组声明生效 |
| 200↔1080 / rx 字钟 / esc↔tx2 等负 slack | -0.7 ~ -2.9 | v3 遗留异步跨域对（cam1 FIFO/RX 字钟/TX IP 内部黑盒），STA 跨黑盒假路径，v3 板测出图已验证；**非本次引入，不属 mod-top-v4 职责** |

注：map 期发现并修复 disp_timing `under_cnt` 双驱动（主 FSM 复位分支与独立 always 同时赋值，VDB-1000/1001）——复位归独立块后过。

## 4. 仿真回归（Phase 3 全量重跑）

- tb_disp_timing：`[DT-OK]`（864000 拍零错）✓
- tb_full_chain：`[FC-OK]`（6 显示帧指纹零错，慢向 repeat 场景）✓

## 5. 板级验证清单（待执行）

1. 烧写 `outflow/ws-e1-cam-ddr-csi2.bit`。
2. `cam_show` 读 DIAG：
   - **DIAG11**：DDR cfg（lock=1 / cfg_ok=1 维持）。
   - **DIAG12**：`{fw_frame_cnt, fw_line_cnt}`——writer 帧计数随传感器流增长（相机 I2C 配置后）。
   - **DIAG14**：`{rd_frame_cnt, rd_state, rd_line}`——reader 回放帧计数随 slot 推进（rd_state 流转）。
   - **DIAG15**：rd_err `{late[7:0], miss[7:0], err[7:0]}`——预期 miss 小值（慢向 repeat）/err=0。
   - **DIAG8（重映射）**：disp_timing `{late[15:0], under[15:0]}`——under 恒 0（行预算生效）；late 为跳槽观测量，稳定后应趋稳。
3. 桥片出图：DIAG7（dbg_win）`df_win` 帧率观测（60fps 目标；慢向 repeat 下帧率锁定供给率 30fps——源 4K60 直通时源帧率=显示帧率，应 60）。

## 6. 板级首战（2026-10-21）与修复闭环

**首战数据**：fw frm/ln 增长、rd frm/ln 增长（grant/发射活）、`late=0 miss=0 err=0`，但 `dms_sol=0 / yuv_v=0 / DIAG17=0/0 / df=0 / live=0`——reader 输出未到达显示管线，全黑。

**定位**（新增 tb_phase4 板级拓扑仿真——camera_path 真链 cdc/demosaic/yuv/tlb/dtg 首次进仿真）：仿真复现后逐级探针，修复三处：

1. **同钟 async FIFO 综合病理（主嫌，已移除）**：v4 把 reader 换域后，回放 CDC 变成 wr=rd=pixel_clk 同钟拓扑——EFX 对同钟 async FIFO 的 gray 同步链推断有病理风险（2026-10-12 事故同款症状：empty 恒真、读侧永不消费）。修复：DISP_V4 下 reader 与流水线同域，**CDC 冗余，回放流直通**（generate 分支化，v3 路径保留 FIFO）。
2. **DIAG17 计数器时钟域**：原 aclk(200M) 采样换域后的 rd 流（跨域误采）→ 随 rd_clk。
3. **DIAG16 复用（0x40）**：rd 口节拍直证 `{rd_sol[15:0], rd_beat[15:0]}`（rd_clk 域自由跑）——与 DIAG17（帧锚定）互补，断通判据：滚动=通路活。

仿真最终态：**[P4-OK]**（6 显示帧、540×960 拍全量、DIAG17=90/90、late=253/under=0、cdc 零丢失）。工具链重跑 map/pnr/pgm PASS，pixel_clk 域 Fmax 204MHz，新 bit `outflow/ws-e1-cam-ddr-csi2.bit`（12:39）。

**板级判读补充**（cam_show 对照）：
- `fw: frm` = writer 输入帧计数（sof 计），非发布计数；发布证据看 reader 侧（rd frm 跟随）与 DIAG15。
- `shp: srch/lvl` 在 v4 = DIAG8 {late[15:8], late[7:0]}（拼回 16bit 为跳槽累计）。
- `cnt: df/live`（DIAG18）为 0.75s 绝对窗——40ms 仿真内恒 0 属伪影，板级真实。
- **DIAG16（新）**：beat/sol 持续滚动 = reader→camera_path 通路活；恒 0 = 断在顶层布线。

## 7. 遗留 / 风险

- **2-bank 包络契约**（Phase 3 记录）：源帧率 > 显示帧率时写侧会覆写在读 bank（真实相机 30fps < 60fps 满足包络）；板级需观测 DIAG15 miss 是否有界。
- v3 遗留异步跨域对负 slack（见 §3 归因）不在本次范围。
- CSR CTRL[7]/CTRL[6] 直注诊断入口在 v4 模式下：shape 直注仍可用（经 tx_line_buf）；replay_pat 直注随 CDC 退役。
- 同钟 FIFO 直通后 cam_show 的 `cdc: lvl` 恒 0（直通无水位），诊断语义变更。

## 8. 下一步

烧新 bit（12:39 版）板级复测：DIAG16 滚动性（通路直证）→ DIAG17=2160/2160（帧锚定）→ dms_sol/yuv_v 增长 → df/live 增长 → 桥片出图。
