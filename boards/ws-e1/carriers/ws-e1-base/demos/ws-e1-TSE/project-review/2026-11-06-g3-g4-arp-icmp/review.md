[English](review.en.md) | 中文

# 项目实施回顾：G3+G4 ARP/ICMP 应答板级验收（附带 G1 关门、G2 复测、RX 通路死因根治）

- Case ID: 2026-11-06-g3-g4-arp-icmp
- 创建 / 最后补充: 2026-11-06（创建）
- 环境: 开发 + 运行时（本机 PC 10.0.0.2（以太网 5，另有 10.0.0.3 网卡）+ ws-e1-base 板
  + TJ180A484S）；Windows；RiscFree 工具链 + Efinity 2026.1
- 项目修订: 未纳入 git（全部为未提交工作树改动）
- 上游关联: 2026-11-05-g7-raw10-udp-stream（其"缺口与后续"中的 G1/G2 回切复测由本案例完成）

## 目标与实际结果

目标（用户确认顺序）：G3（`ping 10.0.0.8` 前 PC `arp -a` 动态学到板 MAC）→
G4（ping 丢包 0%，≥100 包）→ G1 正式关门 → 后续 G5/G6。

实际结果：
- **G3 PASS**：删静态 ARP 后首 ping 4/4，`arp -a` 出现 `10.0.0.8 ea-e8-5e-00-60-c8 dynamic`（证据 E1）。
- **G4 PASS**：`ping -n 100` 100/100、0% 丢包、avg 5ms、TTL=64（证据 E2）；
  板侧 UART ICMP 应答 100 次与请求严格 1:1（证据 E5）。
- **G1 正式关门**：UDP echo 绑定端口方式 4/4、payload 逐字节一致（证据 E3）。
- **G2 复测 PASS**（用户明确要求先测）：新 bit 上 tick 帧 13 包/12s、payload 正确。
- **额外收获：根治 RX 通路死因**（yt8531 rgmii-id 配置被参考驱动移植覆盖，见下）。

## 总体过程与现象

| 阶段 | 做了什么 | 观察现象 / 人工干预 | 结果与来源 |
|---|---|---|---|
| 固件实现 | 新增 net_config/eth_frame/arp/icmp 四模块（src/*.c 自动入编译），main.c RX 分发：ARP→应答、ICMP→应答、其余 IPv4 维持 L2/L3 对称回显；net_config_t 单一事实来源（G5 预留）；TEST_MODE=2 | — | make -B PASS |
| 上板路径 | OpenOCD ELF 加载（11-05 曾成功）今日**复现失败**：`Halt timed out`→改自制 cfg 后 tap/examine/soft_reset_halt 正常，但 `load_image` 必现 `mpsse_flush()` 停滞；小 cfg（diag_lock）读寄存器正常。多次实例争用 FTDI 加剧。**改走 binGen→symbol bin 嵌入→全编译→ftdi_pgm**（11-02 验证过的路径） | OpenOCD 根因未明（记录待查）；binGen `-c` 参数不带 `.v` 后缀（`-c myriscv`），rom 落在 cwd 下需拷贝到 ip/myriscv | bit 编译/下载 PASS |
| G2 复测（用户要求） | PC UDP 10005 收 tick | 13 包/12s，payload "TSE-SW-TX-TICK-A" | PASS |
| ping 首测 | 删静态 ARP（`Remove-NetNeighbor` 需管理员，最终 UAC `arp -d` 删除）→ ping | 100% 丢包；UART rx=0 且无 RX 分发打印 | FAIL（触发诊断） |
| RX 诊断 | 固件 [stat] 扩展：rx(0x6C)/ierr(0x88)/drop(0x9C)/all(0xB4)/rxst(RX_STATUS)/dbg94(rxc+pll 探针)/lock/cfg | RXC 时钟翻转、PLL 锁定、MAC 配置正确，但 **etherStatsPkts=0（连坏帧都没有）**→ 故障在 RGMII 采样点上游；排除软件分发与 FIFO 写侧 | 证据 E4 |
| 根因 | 对照两次 boot PHY 快照：drv_init 每次把 PHY 写 plain（8030/F0），而板上残留初值 8130/F1（echo 时代 rgmii-id）；peri.xml rgmii_rxc delay="0" | plain+零延迟=1G RGMII 双端零延迟→采样错位→RX 全丢；yt8531fd.h 参考驱动移植（USE_PHY_RGMII_ID 默认 0）覆盖了实测有效配置 | 假设→修复验证闭环 |
| 修复 | yt8531fd.h：USE_PHY_RGMII_ID 默认 1 + 恢复实测值（CHIP_CFG bit8 + RGMII_CFG1=0x00F1）；重编固件→嵌入→全编译→下载 | boot 打印 `YT8531 rgmii-id cfg=0x000000f1 chip=0x00008130`（与残留实测值逐位一致） | bit 编译/下载 PASS |
| G3/G4 验收 | 删静态 ARP → `ping -S 10.0.0.2 10.0.0.8 -n 4` → `arp -a`；`-n 100` | dynamic 学习 + 100/100 0% + TTL=64；板侧 ARP=3/ICMP=100/rx+11 | PASS（E1/E2/E5） |
| G1 关门 | UDP echo：临时端口方式 0 收（板侧 tx 计数证明已发）→ 改绑定 10005 端口 | 4/4 payload 逐字节一致；判定 Windows 不投递临时端口 UDP 回包（host 侧，非板子缺陷） | PASS（E3） |

观察/报告/假设分离说明：Windows 临时端口 UDP 回包不投递为**观察**（MAC tx 计数+绑定端口对照），
根因（防火墙状态表）为**未验证假设**，未做内核级实验；OpenOCD mpsse 卡死为**观察**，根因未知。

## 关键产物与证据

| 证据 ID | 原始产物/日志 | 版本/输入关联 | 支持的事实 | 位置 | 快照/SHA-256 | 采集时间/复制类型 | 状态 |
|---|---|---|---|---|---|---|---|
| E1 | G3 ping + arp -a 输出抄录 | rgmii-id 修复 bit | ARP 动态学习 4/4 | evidence/g3_ping_arp_dynamic.txt | fa6f552e…de1c | 2026-11-06/抄录 | 已快照 |
| E2 | G4 ping 100 包输出抄录 | 同上 | 100/100 0% TTL=64 | evidence/g4_ping_100_0loss.txt | 99b5b85e…582c | 2026-11-06/抄录 | 已快照 |
| E3 | G1 UDP echo 输出抄录 | 同上 | 4/4 payload 一致 + Windows 临时端口观察 | evidence/g1_udp_echo_10005.txt | 45df5867…9e5f | 2026-11-06/抄录 | 已快照 |
| E4 | 修复前 [stat] 判别数据抄录 | 修复前 bit | RX 死因判别链（MAC 零帧/时钟正常/PHY 配置对照） | evidence/rx_diag_before_fix.txt | 3e6f74c6…3905 | 2026-11-06/抄录 | 已快照 |
| E5 | 修复后 boot+验收统计抄录 | 修复 bit | rgmii-id 生效；ICMP 100/100 板侧 1:1 | evidence/uart_after_fix_summary.txt | 98b48a8f…99f6 | 2026-11-06/抄录 | 已快照 |
| E6 | yt8531fd.h 修复版源 | rgmii-id 恢复 | USE_PHY_RGMII_ID=1 + 0xF1 配置 | embedded_sw/sapphire/software/standalone/driver/yt8531fd.h | e9e6d0b5…0bdb | 2026-11-06/原始 | 在库 |
| E7 | main.c（net service + [stat] 诊断） | 阶段2 固件 | ARP/ICMP/回显分发与判别计数 | embedded_sw/sapphire/software/standalone/tseDemo/src/main.c | 59ec70e2…18a8 | 2026-11-06/原始 | 在库 |
| E8 | ws_e1_tse.bit | 修复版编译产物 | 板上运行配置 | outflow/ws_e1_tse.bit | 95407a37…265a | 2026-11-06/原始 | 在库（可能被下次编译覆盖） |

## 验证到达的边界

- 固件：make -B PASS（arp/icmp/eth_frame/net_config 全编译）。
- Build：efx_run compile（map→interface→pnr→pgm）两次全 PASS（诊断版 + 修复版）。
- 编程：ftdi_pgm -m jtag 两次成功（Device ID 0x00690A79）。OpenOCD ELF 加载路径**未走通**（见观察）。
- 板级功能：G1/G2/G3/G4 全部真实硬件验证 PASS；RTL 本轮零改动（全部为固件/PHY 配置层修复）。

## 项目经验与 SDK 反馈

项目教训：
1. **PHY RGMII 延迟配置必须与 FPGA 侧 delay 二选一明确归属**：yt8531fd.h "plain" 默认
   前提是"peri rgmii_rxc delay=15"，而 peri 实际 delay=0——两个默认值各自"合理"叠加成
   双零延迟。跨层默认值组合必须有一次板级联测锁定。
2. **PHY 寄存器跨 bit 下载保持**：对比"写前初值 vs 写后值"是定位配置回退的利器
   （本次 8130/F1 残留直接给出实测有效值）。
3. **固件 [stat] 全链判别计数**（MAC 收发计数 + RX_STATUS + rxc/pll 探针 + COMMAND_CONFIG
   一次打出）一次上板即可把 RX 故障切到具体层，避免多轮猜测。
4. **固件上板走 binGen→symbol bin→重编 bit→ftdi_pgm**（与本工程 BRAM 初始化架构一致）；
   OpenOCD ELF 加载依赖调试隧道，当日稳定性不及前者。
5. **Windows 侧 UDP 回包投递不可依赖临时端口**：UDP echo 类测试 PC 必须绑定固定端口；
   test_udp_rx.ps1 仅单向收帧，双向 echo 需要专门脚本（待补 doc/pc_tools）。
6. `Remove-NetNeighbor` 删静态 ARP 需管理员；`Remove-NetNeighbor -Force` 在本机 PS5.1
   报参数错误，用提权 `arp -d` 或 netsh。双网卡同网段（10.0.0.2/10.0.0.3）需 `ping -S`。

可转移给 SDK 的候选：
1. PHY 驱动模板应显式断言 RGMII 延迟配置策略（phy-internal / fpga-peri / none），
   编译期检查 peri.xml delay 与宏默认的组合一致性。
2. EvoVerse 固件模板内置 [stat] 全链判别打印（MAC 计数器 + FIFO 状态 + 时钟探针一次输出）。
3. pc_tools 补双向 UDP echo 测试脚本（绑定固定端口 + payload 校验）。

## 缺口与后续

- Windows 临时端口 UDP 回包不投递：未用抓包确认丢弃层（pktmon 提权两次未执行成功），
  防火墙状态表根因是假设。
- OpenOCD ELF 加载 mpsse_flush 卡死：根因未明（tap/examine/soft_reset_halt/读寄存器均正常，
  仅 load_image 阶段停滞），与 11-05 的成功记录矛盾，待复现条件分析。
- G5（UART 可配 IP/MAC）、G6（≥900Mbps 压测）待做；G7 附加项（ping 控制面共存 + viewer 10min）
  待做。
- 诊断 [stat] 打印（每 2s）保留在固件中，量大时可改回 8s。
- DAYLOG 2026-11-06 条目已补记。

## 2026-11-06 跟进：G5 PASS（UART 命令行运行时可配 IP/MAC）

- 实现：net_config_set_ip/mac/gw/mask + **net_config_apply()**（同步 MAC_ADDR_LO/HI
  过滤寄存器 + pattern 源寄存器 0x218/0x21c/0x224）；main.c 增非阻塞 UART 命令行
  CmdPoll()（ip/mac/gw/mask/show/help，64B 行缓冲，回显+退格），挂入网络服务主循环；
  ICMP/ARP/tick 帧全部读 g_net_cfg（volatile）。固件 RAM 18KB/32KB（55%）。
  重编固件 → binGen 嵌入 → 全编译 → ftdi_pgm 下载。
- 验收（evidence/g5_uart_cfg_ip_mac.txt）：
  - `ip 10.0.0.9`：ping .9 4/4、`arp -a` 动态学到 .9；ping 旧 .8 → unreachable
    （PC 本地提示，板子不再应答旧 IP，证明 ICMP 目标匹配跟随配置）✓
  - `mac ...c9` + `ip 10.0.0.77`（全新 IP 强制重新 ARP）：ping .77 3/3，
    `arp -a` → `10.0.0.77 ea-e8-5e-00-60-c9 dynamic` —— IP/MAC 双即时生效，
    协议栈/MAC 过滤/pattern 寄存器三处一致 ✓
  - 恢复默认（.8 / ...c8）后 ping .8 4/4 ✓
- 观察（host 侧行为）：改 MAC 后若 ARP 缓存未老化，`arp -a` 仍显示旧 MAC
  （PC 直接用缓存发 ICMP，不重新 ARP）；验证 MAC 生效应改用全新 IP 强制重新 ARP。
- 无 RTL 改动；本案例覆盖门控更新为 **G1–G5 全部 PASS**。

## 2026-11-06 跟进 2：G7 视频流实时显示（用户要求"显示出来"）

- 背景：G7 板级验收（2026-11-05）仅做 test_raw10_rx.py 像素级比对（无头），用户要求
  实际显示画面。固件切回 TEST_MODE=0 + PAT_TYPE=2（G7 已知配置，RAM 34.9%），重编
  → binGen 嵌入 → 全编译 → ftdi_pgm 下载。
- viewer 会话（raw10_viewer.py，BGGB，白平衡增益全 1.0）：
  - 截图 OSD：**fps 29.0 / frame 954 / lost 0 / 626 Mbps / pkts 2796966**（带宽与
    G7 无头验收 622.1Mbps 一致，30fps 达标，零丢帧）
  - 会话总结：frames=1565 lost=0 last_fn=1798 pkts=2798885（viewer 绑定晚于起流
    ~7.8s，前 233 帧未接入属正常；观看期零丢帧）
  - 画面内容：udp_pat_gen_v2 合成图案经 demosaic 渲染为竖直彩条（合成测试图案，
    非真实相机图像）；用户按键截图 2 张
- 证据：evidence/g7_viewer_frame_000000.png（f1fad57a…2acf）、
  evidence/g7_viewer_frame_000001.png（10c77bf7…e05a）；原件在 doc/pc_tools/。
- 板子当前状态：RAW10 流模式（TEST_MODE=0）持续发流；切回 G3–G5 网络服务模式需
  将 TEST_MODE 改回 2 并重编上板（固件宏，非运行时命令）。

## 2026-11-06 跟进 3：G7 附加项收官——控制面与流共存 PASS + 图案发生器 v3

**观察（用户驱动）**：确认未来摄像头为 RGGB → 像素公式改为显示友好图案（RTL 4
模式：竖彩条/横灰阶/纵灰阶/棋盘，CSR 0x208 bit[4:3]），viewer 加菜单（选择/轮播
/截图/退出）。随后用户报告切换无效，且 Wireshark 抓到 11664B 巨型 UDP 包
（11664=8×1458，恰好 8 个标准图案包粘连——帧拼接铁证）。

**假设→证据链（三轮编译）**：
1. viewer 按键路由 bug：selecting 态数字键被主菜单热键抢走 → 修复路由优先级
   （viewer 会话日志证实 12 次命令全部正确发出）。
2. 图案模式 ARP 应答上不了线：TX mux 指向图案发生器，sw 帧 FIFO 到不了 MAC
   （UART 有 reply sent、PC ARP 表空、控制 UDP 未发出——三层证据闭环）。
3. mux 注入迭代：v1 mid-frame 切换 → 巨帧拼接丢弃；v2 S_IDLE 等待失效（CSR
   地址误写 +0x093，未定义地址读回恒 0 → 轮询恒真空转）；v3 地址修正
   （+0x24C，PatGen PROBE 同源）→ 注入成功。
   教训：RTL 寄存器名 ≠ 固件地址映射；未定义 CSR 读恒 0 会把等待静默变空转。

**板级验证（v3 上板，全部 PC+UART 双侧证据）**：
- ARP 共存：arp -a 恢复动态学习（ea-e8-5e-00-60-c8）；流中 2 次 ARP 注入
- ICMP 共存：ping 3/5（TTL=64；UART reply sent ×4 → 1 包未达+1 应答竞态，
  存活率约 80%，列为已知待改进）
- 菜单闭环：viewer 12 命令（4 手选+8 轮播）与 UART PAT MODE 12:12 一一对应
- 流完整性：viewer 全程 **1950 帧 lost=0**（含 2 次 ARP 注入穿插）——S_IDLE
  窗口注入对视频流零损伤；巨型粘连包 v3 后未再现
- 图案发生器 v3（4 图案 + RGGB 相位）板级显示正常，用户确认"显示正常，符合预期"

**证据**：evidence/g7x_uart_patmode_transcript.txt（UART+viewer 转录；原始日志随
监听窗口关闭被清理，转录在会话内逐行保留）。固件 main.c（S_IDLE 注入版）与
当班 bit 的新 SHA256 已更新至下方证据表。

## 2026-11-06 晚 2：G6 PASS（吞吐 951 Mbps；丢包 0.015% 归因 PC 接收端，用户确认收口）

**改动**：RTL 零改动（v2 inc 模式天然线速）；固件宏 PAT_TYPE 2→0、PAT_DLEN
1458、PAT_IPG 12、PAT_NUM=0；新 PC 工具 doc/pc_tools/test_udp_thr.py。

**载荷规律（实测破译）**：UDP socket 无 IP 头可看，但 v2 inc 载荷是跨包连续的
mod-256 递增流，每包推进 1466（1458+8 meta 跳变）→ 从载荷首字节可恢复包序，
丢包检测不依赖 IP ID。板上 3 包交叉验证。

**三次 60s 压测（同板同 bit）**：
| 轮 | 接收实现 | 吞吐 | 丢包 | badpay |
|---|---|---|---|---|
| 1 | 逐包现算模板（bug：拖垮接收→15k pps，数据作废） | - | - | - |
| 2 | 预编译模板 memcmp | 951.5 Mbps / 81.6k pps | 23 事件 ~609 包 (0.0125%) | 0 |
| 3 | recv_into + 禁 GC | 951.2 Mbps | 28 事件 ~762 包 (0.0156%) | 0 |
| 4 | + HIGH_PRIORITY_CLASS | 951.3 Mbps | 28 事件 ~742 包 (0.0152%) | 0 |

**归因分析（板侧无责的证据链）**：
- 吞吐稳定 951.x ≈ 理论上限（实测线上帧 1508B：1458/12.224µs = 953.7Mbps 理论，
  99.7% 效率；81.6k pps 与 12.224µs 帧周期吻合）
- 收到的每个包载荷零误码（任何 FPGA 侧 FIFO/时序故障会损坏字节而非整包静默丢失）
- FPGA TX 路径图案 FSM→mux3→MAC 全硬件同频直连，无 FIFO 可溢出——线上发出
  即到达，架构上不存在板侧丢包机制
- 丢失呈随机秒级分布且与秒速率微跌（~80.9k vs 81.6k，≈2.4ms 停顿）同步；
  运行间波动 ±12%——典型主机侧特征； ReceivedPacketErrors=0（USB 网卡计数
  可靠性有限）
- PC 网卡 = ASIX AX88179 USB3.0 千兆（USB 微帧 125µs 预算 + 驱动环队列），
  32MB SO_RCVBUF 排除 socket 队列溢出 → 丢在 NIC/驱动层，应用层无法观测

**最终判定（用户选择"接受归因收口"）**：G6 **PASS**——吞吐 951.2–951.5 Mbps
（≥900，为理论 953.7 的 99.7%）+ 载荷逐字节零误码达标；"丢包 0" 受 PC 侧
USB 千兆网卡（ASIX AX88179）接收栈限制未在本环境达成（0.012–0.016%，三轮
609/762/742 包），已归因并注明局限：FPGA TX 全硬件直连无丢包机制、收包零
字节损坏、丢失与主机调度停顿同步。后续如需严格 0 丢包复测，建议 PCIe 网卡
（Intel i210/i225 级）。

## 2026-11-06 晚 3：PC 运行时模式切换（t/v/图案板级 PASS；n 模式 sw-TX 死路待取证）

**需求（用户提问"PC端能不能改测试模式？→ 选择现在实现"）**：UDP 10006 即时切换
t（inc 线速流）/v（RAW10）/n（网络服务）/s（恢复上次流）/0-3（显示图案），
免每次 ~2-3 分钟全编译上板。

**实现**：
- RTL 唯一改动——pat_gen_kill（CSR 0x208 bit3）：RTL 审计发现 inc 无限流
  FSM 永不回 S_IDLE 且 pat_en 不门控 tvalid，en 撤除不停车 → 无任何软件停车
  机制，必须加 kill 位。电平锁存 kill_r、当前包 tlast 边界干净回 S_IDLE、
  start_pulse 自动清除、停车后 pat_en 熄火。lint 0 错 0 警；tb_udp_v2 回归 +
  tb_udp_v2_kill 定向三段（中途 kill 停车 / kill 后重启 / RAW10 frame_tick
  不复燃）ALL PASSED。
- 固件统一应用：TEST_MODE 仅决定 boot 初态，运行时全部 UDP 命令切换；
  PatGen 参数化（g_pat_type_rt）；AppRun 合并流/网络服务两态。**inc 模式注入
  修复**：晚 3 初版沿用 v3 S_IDLE 等待注入，在 inc 线速（IPG=96ns）下必超时
  → mid-frame 裸切把 ARP 应答拼成巨帧丢弃 → PC ARP 学不到 → 控制面死路
  （UART 证实板子 5 次注入全执行但 PC 全收不到）；改 kill 包边界停车注入
  （停 ≤12.2µs → mux→sw 直发 → PatGen 重启）后 ping 恢复。
- PC 工具：mode_ctrl.py（显式 bind 10.0.0.3 失败即报错，防双网卡静默回退
  路由到未接板的 ASIX）、uart_dump.py（UART 抓取+落盘）。

**板上网卡事实修正（用户中断报告"10.0.0.3 掉线了，你重新来"）**：接板网卡
实为"以太网 6"（Realtek USB GbE #3，10.0.0.3，1Gbps）；"以太网 5"（ASIX
AX88179，10.0.0.2）不接板。**晚 2 节归因中的网卡型号由 ASIX 修正为 Realtek**
（"PC 侧 USB 网卡接收栈限制"结论不变）。当晚中途一次 0 包/ping 全失败事件
归因 10.0.0.3 网卡闪断（用户报告 + 恢复后立即恢复正常），非板侧故障。

**板级验收（PC+UART 双侧，统一应用版 bit）**：
| 命令 | 结果 |
|---|---|
| boot 默认 | inc 线速流 951.4–952.5 Mbps ✓ |
| t | inc 线速流 950.3 Mbps 载荷零误码 ✓ |
| v | RAW10 30.00fps / 622.1Mbps / 丢帧 0 / 像素比对 5 帧 PASS ✓ |
| 2 | 图案 2 像素比对 PASS ✓ |
| ping（流中） | kill 停车注入后 ping 2/2 + ARP 动态学习 ea-e8-5e-00-60-c8 ✓ |
| n | 流停止 + 主循环活 + RX 收帧 ✓，但 **sw-TX 死路** ✗ |
| s | 未测当晚；次日晚 4 补测全 PASS（见下节） |

**sw-TX 死路（观察，未解）**：netsvc 下 MacTxSend 写 0x24C（TX FIFO 数据口）
但 wrcnt 恒 0、TXOK=0、TXSTAT=0x100fff（free=4095 空、bit13 full=0、
bits[22:14] dbg=0x40=infinite_en——读数全部"健康"且语义自洽）、MUX=0x10 正确、
CFG208=0x0（流已停）、主循环存活、**干净 boot 首次 n 即复现**（排除状态污染）。
已排除：reg_apb3 'h093 写解码破坏、tx_status 读数损坏。结论：写 strobe 被
TX DC_FIFO 静默丢弃。11-02 硅级病灶家族（free/full 13 位算术综合敏感）为
**假设**，但读数自洽使简单复发解释不成立。取证路径（已写入 DAYLOG）：
tb_reg_pkt 回放 CPU 写序列区分 RTL vs 硅 → map.v 对照 'h093 wr_en→
DC_FIFO WrEn cone。

**证据边界**：流间切换（t/v/图案/ping）为板级实测 PASS；n 模式 RX 侧板级
实测、TX 侧 FAIL（死路）；s 未测；sw-TX 死路根因未定位（取证计划已列）。
板子当前状态：OpenOCD 探针 resume 后固件回 boot 态 = inc 线速流。

## 2026-11-06 晚 4：s 补测全 PASS + netsvc 逃生路径 + USB 插槽环境事件

**环境事件（用户报告"改过 USB 网卡插槽，换回原来的"）**：USB 2.0 插槽期间
连环假象——吞吐被压 342 Mbps（USB2 有效上限）、ping/ICMP 小帧全丢、
mode_ctrl "sent" 成功但命令根本没上线（无连接 UDP 静默丢弃，板侧 UART 零
打印）。换回 USB 3.0 原插槽立即恢复 951 Mbps。教训：吞吐异常先查 PC 侧
USB 拓扑；板侧 UART MODE REQ 打印是命令送达的唯一权威证据。晚 3 的
"MODE -> raw10 打印缺失疑云"就此获得新解释方向（当时命令送达与打印捕获
受同环境干扰）。

**JTAG 重配置逃生 + boot 态观察**：死路 + PC ARP 表老化使 UDP 控制面单向
锁死 → ftdi_pgm -m jtag 重下载统一应用版 bit 逃生（Device ID 0x00690A79）。
观察：重配置后实测为 RAW10 流（帧号 10165≈5.6min，raw10 全项 PASS），与
PAT_TYPE=0（inc boot）编译值不符，来源未定（疑 USB2 期间某条 v 延迟送达），
后续全链自洽，不再深究。

**s 补测全序列（PC+UART 双侧，doc/pc_tools/uart_s_test.txt 存档 02499567…ed4e）**：
| 步骤 | PC 侧 | 板侧 UART |
|---|---|---|
| RAW10 基线 | 30.00fps/622.1Mbps/丢帧 0/像素 PASS | - |
| s（RAW10 中） | 帧号 11148.. 无中断 | MODE REQ -> stream（no-op 预期） |
| t（→inc） | 951.1 Mbps/81.6k pps | MODE REQ -> thruput + MODE -> thruput stream |
| s（inc 中） | 949.9 Mbps 保持 | MODE REQ -> stream（no-op） |
| n（→netsvc） | ping 2/2 丢（死路复现） | MODE -> net service + [stat] tx=0 + ICMP reply sent×2 |
| s（netsvc 逃生） | **951.2 Mbps 流恢复** | MODE REQ -> stream + MODE -> thruput stream |
| v（收尾） | - | MODE -> raw10 stream |

**sw-TX 死路影响面修正（重要）**：板侧铁证闭环——netsvc 下 rx 计数递增
（rx=0→1→2 请求全到）+ "ICMP: echo reply sent"×2 + **[stat] tx=00000000**
（MAC TXOK 零）→ 应答 CPU 侧"已发"但 MAC TX 计数不动，写被吞板上实锤。
**死路只锁板→PC 方向**（tick/ARP 应答/echo）；PC ARP 表健在时 UDP 命令
（PC→板）照常送达，s 逃生即证。控制面完全锁死条件 = netsvc 死路 + PC ARP
表无板 MAC（老化后）→ 唯一逃生 = 重上电 / JTAG 重配置。可用性结论：n 模式
待修（取证路径不变：tb_reg_pkt 回放 → map.v 'h093→WrEn cone）；流模式全套
（t/v/s/0-3/流中 ping）可用。板子当前状态：RAW10 视频流持续发送。

## 2026-11-06 晚 5：sw-TX 死路根因定案 + syn_keep 修复板级验收 PASS（死路关闭）

**第一步 tb_sw_path 回放（区分 RTL vs 硅）**：重建 Questa 工程（work_kill 库），
当前 RTL（含 pat_gen_kill）**PASS：aFramesTxOK=3 / tx_beat=318 / ctl_frames=3 /
TX_STATUS=0x00000fff**——sw 帧→'h093→TX FIFO→mux3→MAC→RGMII 全链 3/3 帧消费，
判定 RTL 层完全健康、死路是硅级。

**第二步 map.v 网表取证（u_eth_pkt_fifo/u_tx_fifo）**：写口 cone LUTMASK 逐一
解码（efx_lut4.v 权威语义）确认 n46=~full & loc_wr_vld & 'h093 匹配**完全正确**；
根因 = DC_FIFO 复位握手 `WrClkRstGen[1] <= &RdClkRstGen` 的两个 [1] FF 被 map
**消解为无驱动 wire**（[1] 复位释放后终态恒 0 被视死寄存器；u_rx_fifo 同款 FF
保留——综合处理不一致），而下游全部寄存器 SR 配 **SR_POLARITY=1'b0（低有效，
efx_ff.v L67 语义 sr_int=~SR）**直连该 wire → 硅上恒异步复位：FullFlag 恒 0、
FifoWrAddr 恒 0、wrcnt 恒 0、free 恒 4095、读域恒空 → TX 不发。板上全部读数
100% 吻合。定性：**Efinity map 硅级病灶，11-02 病灶家族近亲**。

**修复**：rtl/DaulClkFifo.v 两处握手 reg 加 `(* syn_keep = "true" *)`（逻辑
恒等）。tb_sw_path 回归 PASS → 全编译 5 步 PASS → 新网表确认两 FF 恢复驱动
（L43537/L43547）→ JTAG 下载板验。

**板级验收（修复版 bit 4eba25c1…6c78e，PC+UART 双侧，uart_fix_test.txt
60d10370…8688）**：
| 项 | PC 侧 | 板侧 |
|---|---|---|
| boot inc 流 | 950.7 Mbps ✓ | - |
| 流中 ping | 3/3 0% ✓ | ARP reply sent ✓ |
| n → netsvc ping | **5/5 0%**（修复前 2/2 全丢）✓ | **[stat] tx=0x04→…→0x28 单调递增**（修复前恒 0）+ ICMP reply sent ×5 ✓ |
| n → tick | 5 包/5s = 1Hz ✓ | tx 计数 1Hz 步进 ✓ |
| s → 恢复流 | 948.6 Mbps ✓ | MODE -> thruput stream ✓ |

**sw-TX 死路正式关闭**：运行时模式切换 t/v/n/s/0-3 全功能可用，无已知遗留
缺陷。可转移 SDK 候选：DC_FIFO 用法应核对网表握手 FF 存在性或预置 syn_keep
模板（消解+低有效 SR 恒复位是系统性风险模式）。板子当前状态：RAW10 视频流。

<!-- evoverse-project-review:evidence
{"hardwareStatus":"PASS_G1-G7_GATES_PLUS_RUNTIME_MODE_SWITCH_ALL_MODES_t/v/n/s/pattern_swTX_DEADLOCK_ROOT_CAUSED_AND_FIXED_syn_keep","evidence":[
{"category":"board_validation","path":"doc/pc_tools/uart_fix_test.txt","digest":"60d10370c86a7e27380bb10a88728bdfda0ddd323cf1a89234365d535a028688","note":"晚 5：修复版板验 UART 存档（[stat] tx 单调递增 + ICMP/ARP reply sent + tick + s 恢复）"},
{"category":"rtl_source","path":"rtl/DaulClkFifo.v","digest":"32b59b156c48c674ba531f67441bc0fc63373fddba0671a4efe103dbcaf8a8ce","note":"晚 5 修复：DC_FIFO 复位握手 FF 加 syn_keep（逻辑恒等）；此前为 Efinity 展开源码原版"},
{"category":"simulation","path":"sim/tb_sw_path.v","digest":"0bb7ba5fecce022735ba59f86956d7e9100ded9a5b2ab0938160de3b1a9b4c1d","note":"晚 5：RTL vs 硅判别回放 TB，3/3 帧消费 PASS（work_kill Questa 库）"},
{"category":"board_validation","path":"doc/pc_tools/uart_s_test.txt","digest":"02499567029e584836133e6d366167c07919f7311b4d8209b360aa7b33efed4e","note":"晚 4：s 补测全程板侧 UART 存档（MODE REQ/MODE 全序列 + netsvc [stat] tx=0 死路铁证 + s 逃生打印）"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g3_ping_arp_dynamic.txt","digest":"fa6f552e1c2519d735fdf4441810a5394d74e91a8f82bbee3c44dc191fe9de1c"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g4_ping_100_0loss.txt","digest":"99b5b85e6628a587a84ffb3e9e8937907d266e5310cce5c2a62177317590582c"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g1_udp_echo_10005.txt","digest":"45df5867727ec77e4c1f81411fbf22e007749aeb1c34caa80ff81d55d7a89e5f"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/rx_diag_before_fix.txt","digest":"3e6f74c6a0599f96b6d0b069a1f917d148b23bf460bceb598955811c8ecb3905"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/uart_after_fix_summary.txt","digest":"98b48a8f7bb3d6ccbda44f3895b5a157010b28715235a198e2128bd09b9699f6"},
{"category":"firmware_source","path":"embedded_sw/sapphire/software/standalone/driver/yt8531fd.h","digest":"e9e6d0b528c85e2634d6ca1967554d13929c1eacb7d496429cba73f8bbe50bdb"},
{"category":"firmware_source","path":"embedded_sw/sapphire/software/standalone/tseDemo/src/main.c","digest":"6b173135b336abe6c81073dd9375001bacc25c45b64bf130731aa18bf8949110","note":"2026-11-06 晚 3 统一应用版：AppRun 合并 + kill 停车注入 + t/v/n/s 运行时切换；历史：v3 S_IDLE 注入版 a3ad558d…、G3/G4 版 59ec70e2…"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g5_uart_cfg_ip_mac.txt","digest":"a8f2b9af3d57c9cfe60e728e065aa4354f62b814e77599f1e86cb99f3eee3ce5"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g7_viewer_frame_000000.png","digest":"f1fad57a03dbffb799c4c03298353fb41256695f26428a2030f90889a5252acf"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g7_viewer_frame_000001.png","digest":"10c77bf7327d2961de4e485b67902edf0c13b09596a9e2a23520bec013ffe05a"},
{"category":"board_validation","path":"project-review/2026-11-06-g3-g4-arp-icmp/evidence/g7x_uart_patmode_transcript.txt","digest":"5c140e49f692893673f71c68b4d20201122d0f9550c46d7a18884bcd1e6657bf","note":"转录（原日志随窗口清理）；PAT MODE 12:12 对应 + lost=0"},
{"category":"rtl_source","path":"rtl/udp_pat_gen_v2.v","digest":"a6d968f16b36881273245962f0829bff345eb0fe138200d8730544363dceccfa","note":"2026-11-06 晚 3 kill 版：pat_gen_kill 包边界停车 + pat_en 熄火；历史：v3 图案版 aaf2dec9…"},
{"category":"rtl_source","path":"rtl/reg_apb3.v","digest":"e8992690eb89ffac5cf354607e116e86dbc0d800932c2f8743d9cd12814c4fac","note":"晚 3：新增 0x208 bit3 pat_gen_kill 读写"},
{"category":"rtl_source","path":"rtl/ws_e1_tse.v","digest":"3f023fdec1aa090d936d1617752890cf7c89dbb128fca81dcbea57df8fd458ad","note":"晚 3：pat_gen_kill 接线（reg_apb3 → udp_pat_gen_v2）"},
{"category":"simulation","path":"sim/tb_udp_v2_kill.v","digest":"ac48b574ab5e13274a0430530e04a6dc08a82d4a65e9e5cf25f26692afdb378a","note":"kill 定向 TB：中途停车/重启/RAW10 frame_tick 不复燃，ALL PASSED"},
{"category":"pc_tool","path":"doc/pc_tools/mode_ctrl.py","digest":"18ebac8f5b2db1edfb03ac1a04bf662adb2ae91c8139b74733c16e3d5425225f","note":"晚 3：UDP 10006 运行时模式控制（t/v/n/s/0-3），显式 bind 10.0.0.3"},
{"category":"pc_tool","path":"doc/pc_tools/uart_dump.py","digest":"0cc48c5602a346c1e0be57b6d3eff19385a271355d2f3590ef89d87f1119d6f0","note":"晚 3：UART 抓取打印+落盘"},
{"category":"bitstream","path":"outflow/ws_e1_tse.bit","digest":"4eba25c1df93736ba73453c44b1398777637217fab495b17f4323f3f1436c78e","note":"2026-11-06 晚 5 死路修复版（DaulClkFifo syn_keep）；已被本版覆盖：晚 3 统一应用版 75994359…、G6 版 7cc2c09c…、G7x 图案 v3 版 ca49ea67…、G3/G4 版 95407a37…"},
{"category":"firmware_source","path":"embedded_sw/sapphire/bsp/efinix/EfxSapphireSoc/app/tseDemo.h","digest":"e2571fe47640fbceefdae3bfbbfe514845625ddb21e641140240625c0a04f3b6","note":"晚 3：TEST_MODE 注释改为统一应用语义（boot 初态）；G6 版 cc293572…"},
{"category":"pc_tool","path":"doc/pc_tools/test_udp_thr.py","digest":"7c9c922c600907984d8689f9467f60bd392ffb66892df501ba2e46e5066803b1","note":"G6 接收端：1466 步进序列恢复判丢包 + 256 预编译模板 + recv_into + 高优先级"}
]}
-->
