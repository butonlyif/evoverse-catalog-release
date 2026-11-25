[English](cam1-ddr-replay-plan.en.md) | 中文
# cam1（1080p60）DDR 回放链复刻方案（冻结稿）

日期：2026-10-23
状态：**方案已冻结**（用户确认：完整复刻 cam0 v4.10 设计 + 双 AXI Interconnect 共享 DDR 双口；基于当前工程实施）
基线：v4.10c3m。本文件是任务2 的实施基准；DDR 布局核算见 [ddr_interface.md §10](ddr_interface.md)。

---

## 1. 现状与差距

cam1（u_cam_1）目前只有显示链外壳：top_cam 例化仅覆盖 `DISP_FRAME_SLOTS=1125`，流水线跑
`pixel_clk_1080` 37.125MHz；**无 DDR 回放**（top_cam_demo 中 cam1 `rd_t*` tie-off 恒黑场，
无 u_fw/u_rd）。且存在一处**参数不自洽**：top_cam 内 u_dtg 例化 `LINE_CLKS=1100` 硬编码 + 
HSP/HBP/HFP_CLKS 未传参——1080p@PPC4 行拍应为 550，现状相当于 30Hz 且行段和 620≠1100
会触发 disp_timing 结构守卫（仿真 FATAL）。

目标：cam1 复刻 cam0 全链 = 64b 载体 writer/reader + LPDDR4X 帧乒乓 + 帧级仲裁（disp_sof 锚
+ ANCHOR_WAIT）+ 源切换/上电复刻 + 诊断。

## 2. 拓扑（冻结）

> **2026-10-23 变更**：经评审**不使用** Efinity AXI Interconnect IP（内部实现不透明、512b+2-to-1 非默认参数无厂商验证、ADDR 档位与 S/M 方向受限），改为**自研事务级仲裁器** `axi_wr_arb` / `axi_rd_arb`（RR1、2→1、512b、33 位地址直通），设计规格见 **[arbiter.md](arbiter.md)**（评审中）。下文拓扑中的 "AXI IC" 均指自研仲裁器，互联 IP 生成步骤作废。

```
cam0_fw(200M) ─┐
               ├─ AXI IC 写 2→1 @200M ──> DDR target0 (ACLK=sys_clk_200m, 不变)
cam1_fw(200M) ─┘   ROUND_ROBIN_1

cam0_rd(148.5M) ─────────────┐
                             ├─ AXI IC 读 2→1 @148.5M ──> DDR target1 (ACLK=pixel_clk, 不变)
cam1_rd(37.125M) ─AXI CDC────┘   ROUND_ROBIN_1
                  (AR/R 两通道 async FIFO, 37.125→148.5)
```

- **peri.xml 零改动**：target0 ACLK_0=200M、target1 ACLK_1=148.5M 维持现绑。
- 写侧两 master 同为 200M 域（raw 域共享 sys_clk_200m），互联单钟直连，**零 CDC**。
- 读侧互联钟 = 148.5M（cam0_rd 原钟），cam1_rd 经 2 通道 AXI CDC 接入；cam0_rd 协议不变，
  仅改接线（经互联，地址通道 +1 拍）。
- cam1 回放带宽 ~0.5GB/s（写 0.26 + 读 0.26），占读/写互联各 ~3%，仲裁影响可忽略。
- Interconnect IP 配置（Efinity IP Manager，AXI Interconnect，两份；2026-10-23 按 UG v1.8 Table 16/17 与向导实测定稿）：

| 向导参数 | 写侧 IC（axi_xbar_wr） | 读侧 IC（axi_xbar_rd） |
|---|---|---|
| Protocol | AXI4 | AXI4 |
| Arbitration Mode | ROUND_ROBIN_1 | ROUND_ROBIN_1 |
| **Number of Slave Interfaces** | **2**（S0=cam1_fw，S1=cam0_fw） | **2**（S0=cam1_rd_cdc，S1=cam0_rd） |
| **Number of Master Interfaces** | **1** → target0 | **1** → target1 |
| AXI Address Width | 32 | 32 |
| AXI Data Width | 512 | 512 |
| AXI ID Width | 6（对齐 DDR 口，writer 驱动 awid=0） | 6 |
| AXI User Width | 1 | 1 |
| AXI Tab：Destination Address Space / Offset（M=1 单行） | 28 / 0x0000_0000 | 28 / 0x0000_0000 |
| 时钟（例化时接） | 200M | 148.5M |

向导注意事项：
1. 打开向导默认 Slave=1/Master=2（示例设计方向），**必须改成 2/1**——s_axi_* 是上游摄像头 master 接入口，m_axi_* 是去往 DDR slave 的出口。
2. AXI Address Width 向导只给 32/64 档（UG 文本写 12-64），取 32：帧地址最高 bit26，writer/reader 内部 33 位地址的 [32] 恒 0——互联 S 口接 [31:0]，M 口出线 [32] 补 1'b0 接 DDR。
3. Arbitration 取消 PRIORITY 改 RR1（用户决策）：2 口 = 严格交替，两路利用率写 ~8%/读 ~14%，无饿死与可感延迟。
4. 厂商 Testbench 交付物只用默认参数测过（UG L468），仅作参考；回归以自研单元 TB 为准。

- **cam0 路径改动声明**：写/读 AXI 接线改经互联（协议语义不变，地址通道 +1 拍 @200M/148.5M，
  相对 1100 拍行预算 ~0.1%，ANCHOR_WAIT 余量不受损——阶段 3/4 用 P4C 判据实证）。
- 回退：若 512b 互联在 TJ180 上资源/时序不收敛（参考 UG：2→1@128b=910 LUT / fMAX 315MHz，
  512b 约 ×4），备选 = 读侧自制轻量仲裁（AR 2 选 1 + R 按 grant 分发，单 outstanding/口），
  需重新评审。

## 3. cam1 关键参数（冻结）

| 参数 | 值 | 说明 |
|---|---|---|
| 源窗口 | LINE_TOTAL_PIX=1944 / SKIP_FIRST=11 / 1080 行 / GW=480 | top_cam 缺省组（已是 1080p） |
| 载体行 | 480 拍（64b）= 3840B = 60 字 | writer/reader 参数化后传入 |
| AXI 突发 | 32+28 两突发（4KB 窗内） | 保持双突发结构，drain FSM 无需改 |
| DDR 布局 | A1=0x0400_0000 / B1=0x0500_0000，行槽 4KB | ddr_interface.md §10 静态核算 |
| 显示时序 | LINE_CLKS=550（HSP11+HBP37+2+LINE_WORDS480+HFP22）、FRAME_SLOTS=1125 | CTA 1080p60，VSP5+VBP36+VACT1080+VFP4 |
| ANCHOR_WAIT | 37（= VSP+VBP 41 − 余量 4） | 板级值；tb 对应缩帧值另定 |
| reader 时钟 | pixel_clk_1080 37.125M | 帧握手 toggle 200M→37.125M（复刻 tog200/tog148 结构） |
| flush 链 | cam1 独立 cam1_fw_flush / cam1_rd_flush | 不动 cam0 链 |

## 4. 实施阶段与验证门

| 阶段 | 内容 | 验证门 |
|---|---|---|
| 0（本文档） | 方案/布局冻结 + ddr_interface §1 勘误 + §10 核算 | 文档评审 |
| 1 | frame_writer/frame_reader 行几何 localparam→parameter（默认值=现 4K，行为零变）；tb_frame_writer/tb_frame_reader 增 1080 几何用例（480 拍/60 字/32+28） | 4K 回归不破 + verible/vlog 0 错 |
| 2 | top_cam u_dtg 例化参数化：LINE_CLKS、HSP/HBP/HFP_CLKS 随参数传入（cam0=1100/44/75/18，cam1=550/11/37/22）；tb_disp_timing 增 1080 用例 | 行段和守卫自洽 + 4K 回归不破 |
| 3 | 写侧互联集成：两份 IC IP 生成入工程；cam0_fw/cam1_fw → IC写 → target0（cam1_fw 挂上暂不使能） | tb_phase4 P4C 经互联不破 |
| 4 | 读侧：axi_rd_cdc 封装（AR/R async FIFO，参考 ddr_async_fifo gray 指针）+ cam0_rd/cam1_rd_cdc → IC读 → target1 | CDC 单元 TB 回环比对 + P4C |
| 5 | cam1 全链：top_cam 引出 cap_t*/line_tick/disp_sof/disp_stall；u_fw1/u_rd1 例化（VACT=1080/60字/A1B1/WAIT37）；帧握手跨域；per-cam flush；cam1 诊断 CSR | 1080 缩帧全链 TB（复刻 P4C 判据） |
| 6 | 4K+1080 双回归 → efx compile 全 PASS → 板测（pattern 先行 → 摄像头源） | map/interface/pnr/pgm 全 PASS；板测判读 |

## 5. 风险与对策

1. **512b 互联资源/时序**：阶段 3 先 map 看 LUT/fMAX；不收敛则切换备选仲裁（§2 回退）。
2. **cam1_rd CDC 延迟吃 ANCHOR_WAIT 余量**：CDC FIFO 首字延迟 + 互联 1 拍须 < 4 槽余量；
   阶段 4 TB 量化首字延迟，必要时调 WAIT=37→35。
3. **互联 IP 生成**：IP Manager 为 GUI 操作，配置按 §2 表；生成后 `<module>_define.vh` 参数入
   工程清单。
4. **DBG_SHAPE_PAT 直注源为 4K 几何**（shape_pat_gen SRC_LINES=2160 硬编码）：cam1 例化保持
   DBG_SHAPE_PAT=0 禁用；如需 1080 直注诊断，后续单独参数化（不在本任务范围）。
5. **cam0 回归保护**：阶段 1/2 的参数化改动默认值必须逐字等于现值；每阶段跑 tb_phase4 判据 +
   vlog 0 Error；verible-syntax MCP 先行。
6. **固件 main.c**：cam1 诊断打印待 DIAG 通道定稿后同步更新（阶段 5 尾）。
