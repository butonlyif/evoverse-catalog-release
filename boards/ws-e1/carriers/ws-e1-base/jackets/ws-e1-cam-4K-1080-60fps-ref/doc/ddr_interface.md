[English](ddr_interface.en.md) | 中文
# DDR 接口总结（ws-e1-cam-ddr-csi2）

> 器件：Efinix Titanium **TJ180A484S**（DDR_0 硬核）+ 板载 **LPDDR4x 2Gb**（x16、1 rank）
> 整理时间：2026-10-18；**2026-10-22 增补 §9（c3k 超界回绕 = 底部闪区根因，板测闭环）**。
> 阶段 0 板测验收判据（全部满足）：
> `ddr: lock=1 st=3 raw=1 cfg_ok=1 mcst=9 done=1 fail=0 err=0`

---

## 1. 硬件配置（peri，ws-e1-cam-ddr-csi2.peri.xml）

| 项 | 值 | 说明 |
| --- | --- | --- |
| 颗粒 | LPDDR4x、**2Gb**、x16、1 rank | `mem_density="2G"`。EvoVerse 参考设计标注的 4Gb 是错的，以本板为准 |
| DDR 参考时钟 | **GPIOL_32，33.3333MHz**，3.3V LVCMOS | 板载独立晶振（与 Si5338 无关，无需软件配置） |
| DDR PLL | **PLL_TL2**：33.3333MHz ×4 ÷(pre 1 × post 1) | VCO=133.33MHz，local 反馈自 CLKOUT0，ext_ref_clock_id=3 |
| CLKOUT0（DDR clkin） | **out_divider=28，conn_type=gclk** → 4.762MHz | 经 `clkin_sel=2` 供硬核。对齐 gmsl 工程（用户确认工作） |
| CLKOUT4 | out_divider=5，gclk → 26.67MHz | 与 gmsl 相同 |
| pll_ddr 复位 | `reset_name="pll_ddr_rstn"`，顶层接 `i_arstn`（上电 ~9.5µs 释放） | |
| AXI 端口 | target0/target1 各 512b 数据、64b strb、33 位地址 | ACLK_0 = `sys_clk_200m`（写口，frame_writer 零 CDC）；**ACLK_1 = `pixel_clk` 148.5M**（读口，v4 reader 显示域；硬核接受双异步端口时钟，Phase 0 已验证）。2026-10-23 勘误：原记载"ACLK_0/1 均绑 sys_clk_200m"为早期方案，peri.xml 实绑见 ws-e1-cam-ddr-csi2.peri.xml |

实测记录：两套 PLL 分频在本板均可锁定并完成训练——
gmsl（post=1/out=28 → 4.762MHz，当前采用）与 ori（post=2/out=20 → 3.333MHz，v3 板测 lock=1+训练通）。
`conn_type` 必须是 **gclk**（最早失败版本的 lclk 是头号嫌疑）。硬件单元（pin/EXT_REF/DDR 宏配置）与
两参考工程完全一致，已逐项核对。

## 2. 启动时序链（v5 最终形态，逐级板测验证）

```text
FPGA 配置完成
 → i_clk_27m 计 256 拍（~9.5µs）→ i_arstn 释放
 → 五个 PLL 复位释放（含 pll_ddr_rstn）
 → pll_ddr 锁定（pll_ddr_locked=1）
 → CFG FSM 复位释放（sys_clk_200m_rstn & pll_ddr_locked）
 → 2^21 拍（10.5ms @200MHz）稳定期
 → CFG_START → 硬核 Startup Sequencer 训练 → CFG_DONE（raw=1 → cfg_ok=1）
 → ddr_inst_ARSTN_0/1 释放（= ddr_cfg_ok）
 → checker 复位释放（reset_ctrl CYCLE=4）→ start=mc_srstn=1
 → 3495 突发 × 120 beat 写→读比对（0x0 ~ 0x103F200 ≈ 26MB ≈ 帧 A/B 乒乓区）
 → done=1 fail=0 err=0 → CSR DIAG11 @0x2C → UART
```

要点：**FSM 必须等 lock 后才开始计时**（门控 `cfg_fsm_rstn = sys_clk_200m_rstn & pll_ddr_locked`）；
lock 已实测在本板可读可锁（lock=1），门控安全。上电到扫描完成秒级内结束。

## 3. 控制器 AXI 行为要点（板级实测，frame_writer/frame_reader 必须遵守）

1. **WVALID-先于-AWREADY 型**（最关键）：AWREADY 在 AWVALID && WVALID 都被见过之后才断言。
   - 写通道必须在 AW 握手完成**前**拉起 WVALID，否则与控制器互等组合死锁（板测 mcst=2 实锤）；
   - W beat 会先于本 burst 的 AW 握手开始流动——合法且必须；
   - 前提：上一 burst 的 B 响应已收到（控制器完全退休旧 burst 后再开新的）。
2. **PRE_WRITE 期间发生的 W 传输必须计入 beat 记账**（参考 checker 同款），否则 wlast 打错拍、控制器等不满 LEN 永不给 B。
3. **awqos=1**（arqos=0），参考 checker 同款。
4. burst 形态：AWLEN=119（120 beat）× AWSIZE=6（64B/beat）= **7680B = 一行 UYVY**，INCR；WLAST 与末 beat 严格同拍；burst 边界以 WLAST 划分。（此为 memcheck 自检形态；应用侧 frame_writer v2 实际一行拆 **64+56 两突发**，各自落在单个 4KB 窗内，见 §9.3。）
5. bready/rready 在握手前就位（PRE_WRITE/PRE_READ 置位）；控制器 ready 有随机反压（TB 已建模）。
6. 硬核专用口恒 0：awapcmd / awallstrb / awcobuf / arapcmd。

## 4. 调试史（6 轮板测踩坑全记录）

| # | 现象 | 根因 | 修正 |
| --- | --- | --- | --- |
| 1 | cfg_ok=0（首次） | PLL `conn_type=lclk`（唯一与工作配置的差异）+ 256 拍即训 | 改 gclk；等待加长 |
| 2 | lock=0（假象） | **打印读的是 cam1 的 CSR**（cam1 的 DIAG11 恒 32'h0）——两轮"失败"判读全被污染 | DIAG11 改读 cam0（`CamDiag11_Rd(0)`） |
| 3 | st 恒 0 | v3 曾解除 lock 门控；v5 恢复门控（lock 实测可信后） | `cfg_fsm_rstn = sys 复位释放 & lock` |
| 4 | 训练不起 | PLL 分频被误改（out_div=28→1 等） | 对齐 gmsl 后训练通（lock=1 st=3 raw=1） |
| 5 | done=0 不启动 | checker `.start(~mc_srstn)` 极性接反，复位释放后 start=0 | `.start(mc_srstn)` |
| 6 | mcst=2 卡 AW | "W 等 AW"修复与控制器 WVALID-first 互等死锁 | PRE_WRITE 起 W + 期间传输计数 |

## 5. 诊断位图（DIAG11 @0x2C，**读 cam0 CSR**）

```text
{err_cnt[15:0], mcst[15:12], 5'h0, done_raw[6], st[5:4], lock[3], cfg_ok[2], done[1], fail[0]}
```

- `st`（CFG FSM）：0=IDLE，1=训练中，3=完成
- `mcst`（checker）：0=IDLE，1=WR_ADDR，2=PRE_WR，3=WR，4=POST_WR(等B)，
  5=RD_ADDR，6=PRE_RD，7=RD_CMP，8=POST_RD，9=DONE
- 软件打印（cam_show 内，DDR 行两路 cam 都读 cam0）：

```text
ddr: lock=%d st=%d raw=%d cfg_ok=%d mcst=%d done=%d fail=%d err=%d
```

快速判读：lock=0 → st 恒 0（查 PLL/复位）；st=1 raw=0 → 训练不认参考时钟；
mcst=2 → 写通道死锁；mcst=4 → 写完无 B；mcst=9 且 done=1 fail=0 → 通路正常。

## 6. 验证状态

- **TB**（sim/tb_ddr_memcheck.sv）：AW 模型 = WVALID-first（AWREADY 仅在双 VALID 后断言）+ 随机反压；
  R 通道 ~12% 随机空档；协议断言（wlast/rlast 位置、LEN 匹配、WSTRB 恒满）；
  burst 记账以 wlast 划界。结果 `[DDR-MC-PASS] done=1 fail=0 err=0 | bursts=4 w_beats=480 r_beats=480 proto_err=0`。
- **板测**：3495 突发 × 120 beat 全区域（26MB）写读比对零错。
- TB 的 AXI slave 内存模型为本工程私有（Efinity 官方 EFX_LPDDR4_16_V1.v 是占位模型，无行为）。

## 7. 关键文件

| 文件 | 作用 |
| --- | --- |
| rtl/ddr_memcheck.v | 行突发写读比对（ALEN=119、TOTAL_BURSTS=3495、固定计数制防越界） |
| rtl/top_cam_demo.sv | CFG FSM（~L510）+ checker 例化 + DIAG11 打包（~L757） |
| rtl/apb_cam_ctrl.sv | CSR DIAG11 @0x2C |
| sim/tb_ddr_memcheck.sv | 闭环 TB（含 WVALID-first AW 模型） |
| sw/top_demo/src/main.c | cam_show 的 DDR 打印（读 cam0） |
| sw/top_demo/src/userDef.h | CAMC_REG_DIAG11 位图注释 |
| ws-e1-cam-ddr-csi2.peri.xml | pll_ddr / ddr_inst 配置（§1） |
| 参考（只读） | EvoVerse `ddr-memtest/rtl/memory_checker.v`（握手结构）、`si5338-clock-config/top_soc.v`（同板 FSM）、gmsl 工程 peri（PLL 参数） |

## 8. 对阶段 1/2（frame_writer / frame_reader）的接口契约

- 地址布局（**v4.10c3k 修正**，详见 §9）：帧 A @ 0x0_0000_0000、帧 B @ **0x0_2000_0000**；行槽 8KB stride（行号 << 13），行数据 7680B = 64+56 两突发各自落在单个 4KB 窗内；一帧 = 2160 行 × 8KB = 17.6MB。A 帧占 0..17.7MB，B 帧占 32..49.7MB，均在 2Gb 器件 256MB 容量界内。
- 写帧：遵守 §3 全部要点（尤其 WVALID-first 与 PRE_WRITE 计数）。
- 自检突发形态（120 beat 单 burst）与应用 burst 形态（64+56 两突发）现已不同，但同为 64B beat INCR、同样遵守 §3 握手规则；阶段 0 用相同 beat 宽度验证了通路，突发拆分差异不影响协议行为（burst 边界以 WLAST 划分）。
- 总线占用估算：4K@60 写侧 ≈ 1.06GB/s，占 LPDDR4x-2133 峰值 ~16%，读写逐行交替 turnaround 开销 ~1.6%。

## 9. AXI 地址映射与容量约束（v4.10c3k 板测教训，2026-10-22）

### 9.1 硬核地址映射规则（Efinity《Address Mapping》文档）

AXI 字节地址 → DRAM 的 row/bank/column 是**固定字段拼接**，字段宽度由器件容量决定。
最大空间示例（33 位）与低密度示例：

| [32] | [31:15] | [14:12] | [11:2] | [1:0] |
| --- | --- | --- | --- | --- |
| Chip select | Row | Bank | Column | Datapath |

| [32:28] | [27] | [26:12] | [11:9] | [8:2] | [1:0] |
| --- | --- | --- | --- | --- | --- |
| Not used | Chip select | Row | Bank | Column | Datapath |

- x32 器件：控制器地址 LSB = AXI bit2；**x16 器件：控制器地址 LSB = AXI bit1**（Datapath bit0 恒 0）。
- **"不用的 MSB 必须驱动 0"是硬约束**：超出容量字段的地址位被硬核**静默剥离**，等效于地址对容量取模回绕——AXI 协议层不报错、无 SLVERR、RESP=OKAY，所有协议计数无感。

### 9.2 本板容量账

LPDDR4x 2Gb x16 1 rank：2^31 bit ÷ 8 ÷ 2B/字 = 2^27 字 → AXI 字节空间 **256MB = 0x1000_0000**，
有效地址 **[27:0]**。bit28（0x1000_0000）及以上一旦置位即超界，被硬核剥离回绕。

### 9.3 c3k 根因案例（B 问题：摄像头模式底部 112 行闪区）

- 症状：诊断图案（mod-1024 灰度 ramp）模式稳定不闪；摄像头模式底部 112 行（行 2048..2159）闪烁。
- 布局：行槽 8KB（数据 7680B = 64+56 两突发，各自 4KB 窗内），A 帧 @ 0x0（占 0..0x10E1600 ≈ 17.7MB），B 帧 @ **0x1100_0000**（272MB，超界）。
- 根因：0x1100_0000 = bit28+bit24，bit28 被硬核剥离 → B 帧实效落址 **0x0100_0000 = 2048 行 × 8KB = 恰为 A 帧行 2048 处** → B 帧头 112 行与 A 帧尾 112 行地址重叠。乒乓语义被破坏：reader 读 A 尾部时 writer 正往同址写 B 头部 → 底部 112 行读写竞态 = 闪区。
- 证据闭环（为什么此前 6+ 轮探针/计数"洗清"了 DDR 段仍在这里翻车）：
  - 写读两侧 FRAME_B 参数逐字一致 → 地址账本自洽 → rd late/miss/err、ddr err 全绿；
  - 探针 A/B（c3j）是数据域指纹 → 数据序列完美，看不到物理落点错；
  - mod-1024 诊断图案：行 2048..2159 与行 0..111 灰度值相同（2048 ≡ 0 mod 1024）→ 错位内容覆盖后显示不变 → 图案模式稳定（对 δ≡0 mod 1024 的地址别名双重致盲）；
  - 行为仿真模型（ddr_ctrl_model）默认 4Gb=1GiB 线性映射 → 0x1100_0000 在模型里合法 → **仿真结构性不复现**；tb_phase4 VACT=90 帧仅 720KB 与 B 基址无重叠，双保险盲区。
- 修复：u_fw（top_cam_demo ~L661）与 u_rd（~L754）的 FRAME_B → **0x0200_0000**（B 帧 32..49.7MB，与 A 帧间隔 14MB，4KB 对齐不变；bit25 落在 Row 字段内合法）。两处参数必须同改（写读对称）。
- 验收：2026-10-22 板测，摄像头模式底部闪区消失，**B 问题闭环**。回归 P4C-OK / rd 90/90 / P4-OK / SLOW-OK 全绿，出片 map/interface/pnr/pgm 全 PASS。

### 9.4 DDR 地址布局守则（后续改动必读）

1. 任何 DDR 地址/布局改动前先对 **256MB（0x1000_0000）容量界**做静态核算：最高占用地址 = 基址 + 2160×8192 − 1，必须 < 0x1000_0000。
2. 行为仿真模型不建模容量回绕——超界类缺陷只能靠静态审查 + 板测把守；如需仿真覆盖，给 ddr_ctrl_model 配 `MEM_DENSITY_GBIT=2` 并开 range_check。
3. **"计数全绿 + 数据探针干净"不能证明 DDR 段无误**：地址域错误（别名/重叠/回绕）对数据域指纹与自洽性计数双重不可见——只有地址序列检查（如 c3k 后可选的 awaddr/araddr 探针）或显示内容才能暴露。
4. 帧基址选择：除容量界外，确认基址的最高有效位落在 Row 字段内（避开 Chip-select/Datapath 边界歧义位）；A/B 两帧基址在 u_fw 与 u_rd 两处保持逐字一致。

## 10. cam1（1080p60）帧布局预算（2026-10-23 任务2 阶段0 冻结，实施前复核）

按 §9.4 守则对 cam1 回放链做静态核算（1080p = 1920×1080 RAW10，64b 载体同构 cam0）：

| 项 | 值 | 推导 |
| --- | --- | --- |
| 行数据 | 3840B/行 | 源 480 拍×40b = 2400B，64b 零扩展载体 480 拍×8B = 3840B |
| AXI 写形态 | 512b/beat，32+28 两突发（各落 4KB 窗内） | 32×64B=2048B + 28×64B=1792B，和 3840B ≤ 4096B |
| 行槽 stride | 4KB（行号 << 12） | 3840B ≤ 4096B，行间不重叠，且每行槽 4KB 对齐 |
| 一帧 | 4KB × 1080 行 = 4.32MB | |
| cam1 FRAME_A1 | **0x0_0400_0000**（64MB） | 占 64..68.32MB；MSB=bit26 落 Row 字段 ✓；与 cam0 B 帧（32..49.7MB）间隔 14.3MB |
| cam1 FRAME_B1 | **0x0_0500_0000**（80MB） | 占 80..84.32MB；MSB=bit26 落 Row 字段 ✓（**不用 0x0600_0000**——其 bit27 落 Chip-select 字段，违反守则 4）；与 A1 间隔 11.68MB |
| 容量界 | 最高占用 84.32MB < 256MB（0x1000_0000）✓ | 全部地址位 [27:0] 内 |
| 与 cam0 区域重叠检查 | cam0 A(0..17.7M) / B(32..49.7M) 与 cam1 A1/B1 零重叠 ✓ | |

总带宽账（4 口汇聚后）：cam0 写 1.06 + cam0 读 ~1.06 + cam1 写 ~0.26 + cam1 读 ~0.26 ≈ **2.6GB/s**，LPDDR4x 峰值占用 ~16% → ~20%，充裕。

仿真注意：行为模型/自建 TB DDR 模型不建模容量回绕（§9.3 教训），cam1 布局虽在界内，仍建议 ddr_ctrl_model 路线配 `MEM_DENSITY_GBIT=2` 开 range_check 双保险。
