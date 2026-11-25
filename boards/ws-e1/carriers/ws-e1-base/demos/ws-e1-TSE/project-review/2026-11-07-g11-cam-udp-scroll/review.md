[English](review.en.md) | 中文

# G11 相机 RAW10 UDP 直推卷动定位与根治（G11n6~n13 定位 / G11n14 多 bank 拼接修复 / G11n15 帧界对齐）

- Case ID: 2026-11-07-g11-cam-udp-scroll
- Created / last supplemented: 2026-11-07 / 2026-11-08（G11n15、G11n15b）
- Environment: runtime（TJ180A484S 载板 + FTDI 下载器 + PC 千兆网口）；Windows host
- SDK version / Adapter / toolchain: Efinity 2026.1（efinity-riscv-ide-2026.1）； QuestaSim vlog/vsim；固件 riscv sapphire standalone
- Project revision: 无 Git（工程未纳入版本管理，DAYLOG 为事实记录）
- Requirement and outcome sources: 会话（用户）+ DAYLOG/2026-11.md G11 系列 + 板测 UART 回传（用户粘贴）

## Goals and actual results

目标：修复 IMX415 1080p30 RAW10 经千兆 UDP 到 PC 的画面卷动（组级丢失→组相位滑移）。
实际结果：**已修复并板测闭环（2026-11-08 G11n14 follow-up，见文末）**——用户在
DDR 转向决策后改道"加大 FIFO 深度吸收净积"，多 bank 拼接 163,840 组
（cam_fifo_bank mod-5 交错路由）+ 单门限流控实现零拒收，画面稳定 30fps 不卷动。
原终局分析（段内瞬时带宽 1.30Gbps > 千兆极限）不变，深缓冲使其可吸收。

## Overall process and phenomena

| Stage | What was done | Observed / manual interventions | Outcome and source |
|---|---|---|---|
| G11n6 | 双门限+深 FIFO(8192) 板测 | rej 21%、occ 钉 8000、消费 74% | DAYLOG G11n6 |
| G11n7 | map.v 网表静态取证十锥 0 mismatch + 时序收敛 | RTL≠硅 假设否决；[300]/[304] CSR 直读撕裂定案 | DAYLOG G11n7 |
| G11n8 | 单门限流控重构（用户选型），回归 PASS | 板测全指标纹丝不动（第 3 次） | DAYLOG G11n8 + 用户回传 |
| G11n9 | 观测探针轮（fullhi/fullrise/rejrun/tvrun/occ min-peak） | 触满 82 万次/s、rej 段最长 48 拍、tvrun 51 拍 | 用户回传 CAMDBG9/10 |
| G11n10 | 门限 300→2048（曾因例化覆盖未生效→修正重烧） | 门限生效但 rej/触顶/白等全不动 → 门限-锁相模型证伪 | 用户回传 + DAYLOG |
| G11n11/13 | hsgap min/max + 行距 4 桶直方图探针 | **min=2961 拍、A 桶 1086/帧、B/C=0、D 1.04/帧** → 帧结构真相 | 用户回传 CAMDBG11/12 |
| ILA 用户实测 | 单行波形：633 拍/行、480 有效、行首长段+90% 占空 | 用户领域知识：帧结构 30 OB+1080 有效+6 尾；raw_2_axi4st 只出有效行 | 会话 |
| 终局分析 | 全链条数字闭合（本 review §How far） | 用户决策：DDR 帧缓存（拷贝 ws-e1-cam-4K-1080-60fps-ref） | 会话 |

## Key artifacts and evidence

| Evidence ID | Original artifact path | Version / linkage | Supported fact | Ref | Snapshot | Status |
|---|---|---|---|---|---|---|
| E1 直方图回传 | 会话粘贴（CAMDBG12 两轮） | G11n13 bit | A=1086/帧、B=C=0、D=1.04/帧 → 14.8µs 背靠背行 + 17.35ms 帧尾 gap | 见 evidence/g11n13_camdbg.txt | evidence/ 下原始粘贴 | present |
| E2 板测宏观数据 | 会话粘贴（四轮 cam 回传） | G11n8/n10 bit | rej 21.5%、消费 74%、白等 50%、包周期 ~24.9µs 恒定 | evidence/g11_board_macro.txt | 同上 | present |
| E3 ILA 波形 | 用户 ILA 抓图（无文件） | — | 行 633 拍、480 有效、行首长段+90% 占空 | 会话 | — | user-reported |
| E4 BFM 节律回归 | sim/tb_cam_udp.sv + 运行日志 | ILA 节律参数 | 均匀行节律下 RTL 路径 fullrej=0（ rej 非逻辑 bug） | DAYLOG G11n12 段 | sim/ 源码在 | present |
| E5 终局核算脚本 | .tools/g11n13_decode.py | 输入=E1 | 全链条闭合：32.43M 组/s=1.30Gbps vs gen 24M；净积 135K=16×FIFO | 脚本在工程 | present |
| E6 新工程 spec | D:\Projs\ws-e1-ddr-ge\SPEC-udp-from-ddr.md | 2026-11-07 | DDR 改造完整规格（后续工作入口） | 外部路径 | present |

## How far validation reached

- 仿真：tb_cam_udp（真实 ILA 节律 BFM）PASS——证明**均匀节律下 RTL 数据路径无 rej**；
  rej 为板级真实写入节律超出所致（节律例外性已被 E1 直方图实证）。
- Build：多轮 GUI 编译烧板（用户执行），map/pnr PASS（G11n7 slack +1.377 无违例）。
- 板级：四轮 pacing 方案 + 三轮探针读数（用户 UART 回传）——**卷动未修复**（结构性根因），
  但定位链完整闭环。hardwareStatus: 卷动问题 NOT_FIXED（根因已定位，修复转 DDR 工程）。

## Problems and improvement candidates

| Candidate | Expected / phenomenon / impact | Evidence | Root cause | Suggestion | Scope |
|---|---|---|---|---|---|
| C1 CSR 撕裂读 | 125M 域计数器 50M APB 直读出现非物理值 | G11n7 | 无同步快照（已定案） | 新工程 CSR 加两次一致判读/快照寄存器 | ws-e1-ddr-ge |
| C2 parameter 覆盖坑 | 改默认值未 grep 例化覆盖 → 门限未上板（G11n10 乌龙） | DAYLOG | 例化显式参数覆盖模块默认 | 改参数必须全例化点核查 | 项目惯例 |
| C3 帧结构探测法 | 传感器节律假设错误消耗四轮板测 | E1/E3 | 缺少节律直方图探针（首日就该上） | 长时统计直方图探针模板化 | SDK 候选 |

## Project lessons and SDK feedback

- 教训 1：**先测分布再建模型**——"均匀行"假设驱动了全部 pacing 推理，一个 4 桶直方图
  探针（一轮烧板）就能推翻它并直接给出根因形态。
- 教训 2：板测宏观指标四轮恒定（rej/消费/包周期）本身就是"系统性常数"的强信号，
  应更早从"调参数"切换到"测节律"。
- 教训 3：ILA 单窗口只能证明局部节律，跨行/跨帧尺度需长时间统计探针。
- SDK 候选：时间间隔直方图探针模板（min/max/N 桶，参数化信号与桶界）。

Development intake: 未归集（候选 C3 可在 SDK 仓库 intake）。

## Material gaps and later follow-ups

- ILA 波形原图未存档（user-reported）；G11n9~n13 各轮 cam 回传全文在 evidence/。
- 传感器行距 ≥21.6µs 备选方案（30fps rej=0 另一条路）存档于 SPEC §0，未验证。
- DDR 方案（D:\Projs\ws-e1-ddr-ge + SPEC-udp-from-ddr.md）留档备胎，未执行；
  实际路线为 G11n14 多 bank 拼接（本工程内闭环）。
- G11n14 仿真 occ_diff_max=98311（tb 监控语义疑点，两轮同值）未查——不阻塞，
  板测无此现象。

## Follow-up 2026-11-08: G11n14 多 bank 拼接 FIFO——卷动根治，零拒收

- 路线变更（用户决策）：DDR 转向备胎搁置，改"加大 FIFO 深度吸收净积"。
  用户推导容量并纠正 Efinix BRAM=10Kb/块假设；2^18 超 46 块、2^17 差 8.9 行
  → 用户提出多 FIFO 拼接 → bank0(2^17)+bank1(2^15)=163,840 组（640 块）。
- 实现：cam_fifo_bank.sv（新，对外与 async_fifo 同构）+ pacer fifo_occ 直供
  （18bit）+ 顶层例化/CSR/镜像块改造 + tb 真实节律 BFM（行周期 2961 拍、
  帧尾 17.35ms、Bresenham 74% 占空）+ exp_q 环 262144。
- 首版缺陷（run1 仿真实锤，full_rej=73600/帧）：位测试路由 wcnt[17] 容量
  塌缩——读写窗口可整体落在 bank0 区间，bank0 局部满而 bank1 全空 → 拒写。
  修复 = mod-5 交错路由（163840=5×32768 整除、4:1 容量比、两侧同规则保序，
  任意积压下 b0=4/5·P 恰满、b1=1/5·P 恰满，总容量全额可用）。
- 修复后仿真（tb_g11n14_run2.log）：三帧 fullrej=0/mism=0/drain=0，occ 帧末
  137031/142933/142865 ≈ 理论净积 135,351+门限 ✓。
- 板测（evidence/g11n14_camdbg.txt，重新下载后）：fullhi/fullrise/rejrun 全 0
  = 零拒收；occ_min=1908（≈门限 2048 下探）、occ_peak=139,944（=理论
  135,351+2048+在途精确闭合）；hsgap_min=2961/hsgap_max=3469632 直方图帧
  结构板级复证；画面稳定 30fps 不卷动。**G11 卷动问题闭环。**
- 后续：IMX415 拜耳排列重定（--cfa 四相位）；occ_diff_max=98311 tb 监控疑点
  择机排查。

## Follow-up 2026-11-08: G11n15 帧界对齐——深 FIFO 帧不同相残留缺陷（仿真闭环，待板测）

- 板测残留（用户确认）：画面整体左移、左侧偏紫/右侧偏绿 + 上下偏移；PC 端
  无丢帧。用户自诊：写 FIFO 不提供帧信息，读侧不知帧首；图案↔相机切换需
  重算帧号。拜耳排列确认为 RGGB（图案模式颜色正确 → PC 端 CFA 参数无误，
  色偏是帧界错位的列相位假色，非拜耳相位错）。
- 根因：gen 发送窗与 FIFO 深缓冲读出数据帧不同相（滞后 ~0.45 帧净积），
  PC 按 (fn, off) 元数据重组时帧界错位 → 整帧像素错位 + 列相位色偏。
- 方案（用户认可魔数切帧 + 仓库内 PC 脚本可改）：四层链路改造——
  ① 写侧帧首插 2 组魔数 40'hFFFFFFFFFF + 40'h0000000000（RAW10 中
    "全白组紧跟全黑组"概率极低；数据/门控各延迟 3 拍，sof 拍启动
    ins_cnt 1→2→3→0，M1@t+2/M2@t+3/帧首组@t+4，wr_en 与 dat_d3 同相）；
  ② pacer 纯流式（删 START_THR/QUADS_LAST/QUADS_FRAME，req/go = cam_en &&
    occ>0，动态包长 min(290,occ) 经 pkt_len_o 直供 gen；门限会残留 2047 组
    粘下一帧魔数 → 纯流式 + 动态短包精确排空）；
  ③ gen 动态包长（S_IDLE 授予拍锁存 grp_len_r；cam 每包回 S_IDLE；
    包末组禁用 b3 预读/b4 装载防与授予拍 rd 冲突）；
  ④ PC raw10.py FrameReassembler 双模式重组器（魔数=帧起始标记，消费后按
    字节计数凑满 2,592,000B 即成帧，无下一帧依赖；粘性 _meta_mode 回退
    图案元数据流，数据段头重现魔数自动切回相机模式；魔数前残数据短帧落账
    自愈；每帧重对齐 → 图案↔相机切换即插即用）。
- 仿真两轮缺陷链 + run3 PASS（tb_g11n15_run3.log）：
  run1 FAIL（full_rej=5174）：S_IPG→S_HDR 包链路径绕过 S_IDLE，grp_len_r
  首包粘滞整段 → 读侧饿死 → FIFO 积压 → 帧尾不排空 → 魔数被顶开；修复 =
  cam 模式每包回 S_IDLE。run2 FAIL（流错位、M2 全程缺失）：包尾 b3 预读 +
  b4 装载把下一包首组装进 p，逐包回 S_IDLE 后授予拍 rd 再读一组、S_ARM 重载
  覆盖 → 每包净丢 1 组；修复 = 包末组抑制预读/装载（pay_left==2/1）。
  run3 PASS：frm=3、mism=0、drain=0、fullrej=0、MAGICCHK m1=3 m2=3（每帧
  魔数精确一对 = 帧间 FIFO 精确排空铁证）、exp_wr=exp_rd=1,555,206
  （3×518,402 收支闭合）、尾包 pkt5369 grp=91 动态排空实证。
- 顶层冒烟：vlog Errors=6 全部历史 vlog-2388（与 G11n6 基线一致），零新增。
- PC 端自检：临时脚本 6 测试全 PASS（完整帧/魔数跨包/短帧不显示/重同步
  自愈/图案流回退/模式交替）。
- 变更文件：rtl/ws_e1_tse.v（写侧魔数插入 + 例化接线）、rtl/cam_udp_pacer.v
  （纯流式）、rtl/udp_pat_gen_v2.v（动态包长）、doc/pc_tools/raw10.py、
  sim/tb_cam_udp.sv（镜像魔数 + MAGICCHK）。
- 待办：用户 GUI 编译烧板 + 新 raw10.py viewer 板测（判据：画面无左右/上下
  偏移、色彩正常 RGGB、图案↔相机切换即插即用、fn 连续无持续丢帧、
  CSR [2EC] fullrej=0）；SDC L21 -exclusive → -asynchronous 小修正未做。

### G11n15b 修复轮（2026-11-08，首次板测暴露双缺陷）

- 板测现象：相机模式"帧号在涨、丢帧 0、包数在涨、fps=0、画面冻结"；且"切换
  有问题，切不过去图案和其他模式"。重启 tse_console 与板卡后依旧。
- 诊断方法（PC 侧抓包探针逐层排除，全部本机真实抓包）：①流健康性（4s：
  621.9Mbps、53,688 包/s、fn 环回 120 次=30fps、off 零跳变零丢包）→ ②魔数
  逐包扫描（39-42 个/4s，误判"每 3 帧才插一次魔数"——教训：**逐包扫描看不见
  跨包拆分的魔数**，occ=1 竞争时 M1/M2 拆两个包 + dlen=10 魔数专包 occ=2 竞争）
  → ③连续字节流+跨包 carry 全量检测（120 个/4s=每帧一对，间距中位数
  2,592,010B=恰一帧，±1 组抖动为 occ 读域同步粘滞非缺陷）→ ④真实抓包
  （107,302 包落盘）回放仓库重组器 → 57 完整帧/28.5fps → **流健康、PC 代码
  有真 bug**，区分度决定性。
- 缺陷1（PC raw10.py）：_meta_mode→相机切换路径消费魔数后漏置 _pending=True
  → buf 凑过帧长又触发"超帧长无魔数"判回 meta_mode → 无限振荡回 legacy
  （legacy 按 (fn,off) 重组相机流因帧首短包 off 与字节位置错开 → 永不成帧）。
  "帧号涨（meta fn 每帧+1）/丢帧 0/fps=0"三联画像精确吻合。修复：置
  _pending=True。
- 缺陷2（RTL udp_pat_gen_v2）：G11n15 纯流式使 FIFO 帧间隙排空到 0 →
  occ_ready=0 → cam_pkt_go=0；gen S_IPG 的 ipg_exit=(ipg_cnt>=lim && (!cam_r ||
  cam_pkt_go)) 永不满足 → 卡死 S_IPG → 切图案/其它模式的 start_pulse 进不来。
  G11n14 门限时代 occ_ready 恒 1（START_THR=2048）掩盖该路径。修复：S_IPG 出口
  增加 `kill_r || !cam_en → S_IDLE`（回 S_IDLE 中止，不能走 ipg_exit→S_HDR：
  cam_r=1 会凭空发幽灵包、绕过 pacer 授予协议）。
- 验证：①PC 三阶段场景回放（合成图案流→真实相机流→回切图案）：切相机 57
  完整帧（修复前 0）；②tb_cam_udp 回归 PASS（frm=3 mism=0 drain=0 fullrej=0
  m1=3 m2=3，cam 路径不受 gen 改动影响）；③顶层冒烟 Errors=6 全历史零新增。
- 变更文件：doc/pc_tools/raw10.py（1 处）、rtl/udp_pat_gen_v2.v（1 处）。
- 待板测（用户）：GUI 重编译烧板（gen 一处改动）+ 重启 tse_console（新
  raw10.py）。判据：相机 ~28fps 流畅、图案↔相机双向切换即插即用、
  CSR [2EC] fullrej=0。

### G11n15c 修正轮（2026-11-08，G11n15b RTL 改动证伪回退）

- G11n15b bit 板测新症状：下载 bit 后默认不发数据、只能切到相机、切不到
  图案/其它模式 → G11n15b 的 RTL 改动被证伪。
- 重读 FSM 实锤：cam 模式每包从 S_DATA 直接回 S_IDLE（L566 cam_r 分支），
  根本不进入 S_IPG → G11n15b 前提"cam 卡死 S_IPG"不成立；原"切不过图案"
  实为 PC raw10.py `_pending` 单根因。G11n15b 的 `!cam_en → S_IDLE` 在图案/
  inc 模式（cam_en=0 常态）劫持每包回 S_IDLE、破坏包内链 S_IPG→S_HDR →
  图案流每 frame_tick 仅 1 包（1788 倍减速）→ 精确解释新症状。G11n15b
  回归 PASS 的盲区：tb PHASE3/PHASE4 未覆盖图案模式多包链。
- 修复：S_IPG 回退 G11n15 原始 `if (ipg_exit) → S_HDR`；raw10.py `_pending`
  修复保留。回归 PASS（tb_g11n15c_run1.log：PHASE3 mismatch=0、BACKPRESSURE
  frm=3 mism=0 drain=0 fullrej=0、m1=3 m2=3）；冒烟 Errors=6 零新增。
- 教训：改 FSM 出口前必须枚举所有进入该状态的路径；tb 未覆盖路径不会守门。
- 待板测（用户）：重编译烧板 + 重启 tse_console。判据：①下载 bit 后图案
  默认即流 ②图案↔相机双向切换即插即用 ③相机 ~28fps ④[2EC] fullrej=0。

<!-- evoverse-project-review:evidence
{"hardwareStatus":"BOARD_OBSERVED_PASS","note":"G11 卷动=板测闭环（G11n14）；G11n15 帧对齐=G11n15c 仿真闭环，板测待用户执行（G11n15b RTL 改动已证伪回退，PC _pending 修复保留）","evidence":[{"category":"board-observation","path":"project-review/2026-11-07-g11-cam-udp-scroll/evidence/g11n13_camdbg.txt","digest":"see-file"},{"category":"board-observation","path":"project-review/2026-11-07-g11-cam-udp-scroll/evidence/g11n14_camdbg.txt","digest":"see-file"},{"category":"board-observation","path":"project-review/2026-11-07-g11-cam-udp-scroll/evidence/g11_board_macro.txt","digest":"see-file"},{"category":"simulation-log","path":"sim/tb_g11n14_run2.log","digest":"see-file"},{"category":"simulation-log","path":"sim/tb_g11n15_run3.log","digest":"see-file"},{"category":"simulation-log","path":"sim/tb_g11n15c_run1.log","digest":"see-file"},{"category":"rtl","path":"rtl/cam_fifo_bank.sv","digest":"see-file"},{"category":"rtl","path":"rtl/cam_udp_pacer.v","digest":"see-file"},{"category":"rtl","path":"rtl/udp_pat_gen_v2.v","digest":"see-file"},{"category":"pc-tool","path":"doc/pc_tools/raw10.py","digest":"see-file"},{"category":"analysis","path":".tools/g11n13_decode.py","digest":"see-file"},{"category":"spec","path":"../ws-e1-ddr-ge/SPEC-udp-from-ddr.md","digest":"see-file"}]}
-->

### G11n16 重构轮（2026-11-08，图案源迁移 200M 域统一 FIFO 链路）

- 架构结论（本轮核心）：G11n15 系列切换缺陷（相机→图案切不过、线速→图案异常）
  及 G11n15b 误修的根源是**两套并存的流路径**——相机走 200M 写侧→cam_fifo_bank→
  pacer→gen cam 模式，图案在 gen 125M 域内直发（pattern_quad+frame_tick），两者
  各有独立启动/停止/门控语义，切换组合爆炸。用户决策重构：图案生成移到 200M
  相机域按摄像头节奏写同一条 FIFO 链路；inc 线速降级 debug；默认开机网络服务。
- 改动：新建 rtl/raw10_pat_src.v（200M 自由运行图案源，接口复刻相机窗口流，
  30fps=6,666,667 拍/帧、518,400 组/帧、1 组/12 拍、帧尾 gap 2.23ms）；reg_apb3
  0x208 bit7 fifo_src_sel；ws_e1_tse 源 mux + sof 拍锁存（帧边界切换，杜绝帧内
  拼接）；udp_pat_gen_v2 删图案直发路径（raw10_r 蕴含 cam_r）；main.c 默认
  RMODE_NETSVC、CamGen(sel) 参数化（'c'=相机 'v'=图案源，唯一差异 0x208 bit7）。
  PC raw10.py 魔数切帧对图案流自动生效，功能零改动。
- 证据：
  - tb_raw10_pat_src PASS（sim/tb_g11n16_patsrc_run2.log）：4 帧逐组独立期望对拍
    mism=0（四图案 + 运行中切换组边界生效）、sof 周期 6,666,667 精确、组间隔
    12 拍、518,400 组/帧、sof/eof/sol/tlast 结构零错。
  - tb_cam_udp PASS（sim/tb_g11n16_camudp_run1.log）：PHASE3 mismatch=0；
    PHASE5 帧 3 后 fifo_src_sel 0→1 帧边界切换生效，图案帧走同一条链路；
    MAGICCHK m1=m2=237（frm=236+切换瞬间截断帧魔数对，符合预期）；
    G11K-BACKPRESSURE PASS（last_mism=0 drain=0 fullrej=0，exp_wr==exp_rd
    精确排空）。
  - 顶层冒烟 Errors=6 全历史 vlog-2388 基线零新增。
- 教训：跨文件转写公式必须对照 PC 参考实现逐式复核（不得凭注释概括）；tb
  链路用缩水几何时选 pat_mode=1 避免彩条白/黑条组与魔数 M1/M2 混淆。
- 待板测（用户）：GUI 重编译烧板 + 重启 tse_console。判据：①开机无流（ping
  通、'i' 快照）②'t' debug 线速 ③'v' 图案四模式 ④'c' 相机 ~28fps
  ⑤图案↔相机双向切换即插即用 ⑥[2EC] fullrej=0。

### G11n16b 板测缺陷轮（2026-11-08，均匀细流→533k pps 小包风暴→行突发修复）

- 板测（G11n16 烧板）：'v' 切图案打印正常但 PC 无图像。dump 解码定位（间隔
  ~1.567s 两拍）：[2CC] armed=1/sof_cnt+48（30fps 图案 sof 正常）、
  [2E4]/[2E8] wcnt/rq 各 +26,145,545（mod-163840 恰 159 圈）=16.68M 组/s=
  图案源精确速率（FIFO 收支平衡、链路全活）、[2F0] 533k pps、[31C] occ peak
  ×4=40 → 每包仅 min(290,occ)≈40 组。注：occ_dbg 为 >>2 打包，读数须 ×4。
- 根因：图案源"1 组/12 拍均匀细流"与 pacer 纯流式（occ>0 即发）耦合 → occ
  平衡 ~40 → 533k pps 小包风暴（相机模式靠整行 480 组突发把 occ 顶到
  82~500 → 290 组大包 ~33-66k pps）。PC UDP 栈超限丢包；包头开销 21~29% 把
  线速顶到 ~0.9Gbit。仿真未覆盖（tb 不建模 PC 端 pps 承载力）。
- 修复（rtl/raw10_pat_src.v 节奏重构）：行突发同构相机微观节奏——每行 480 组
  背靠背（1 组/拍）+ 行周期 3100 拍（相机 hs→hs 主带同构）+ 帧尾 vblank
  3,318,667 拍（≈16.6ms 同相机消隐，保证帧尾排空/魔数对齐）；帧周期仍
  6,666,667 拍=30fps；LINES=GRP_TOTAL/480 派生（tb 缩水仍成立）。
- 证据：tb_raw10_pat_src PASS（sim/tb_g11n16b_patsrc_run1.log，4 帧 mism=0、
  spacing_err=0、sof_period 精确）；tb_cam_udp PASS（sim/tb_g11n16b_camudp_run1.log，
  PHASE3 mismatch=0、PHASE5 图案帧 occ≈770 稳态锯齿/fullrej=0、MAGICCHK
  m1=m2=237 与基线一致、G11K-BACKPRESSURE PASS）；顶层冒烟 Errors=6 基线零
  新增（vlog -sv +define+SIM_MODE +incdir+..）。
- 教训：①流控策略与源节奏是耦合契约——pacer"即到即发"隐含写入为突发形态，
  改源节奏须重审包长下限；②速率形态类缺陷（pps/包长分布）超出功能正确性
  tb 判据覆盖，需显式断言或板测；③探针判读先查打包粒度。
- 待板测（用户）：'v' 图案四模式画面恢复；图案↔相机双向切换；[2EC] fullrej=0；
  预期 [31C] occ peak×4 ≈ 500-800、pps 回相机量级。
