[English](review.en.md) | 中文

# 项目实施回顾：G7 RAW10 1080p@30fps UDP 视频流板级验收

- Case ID: 2026-11-05-g7-raw10-udp-stream
- 创建 / 最后补充: 2026-11-05（创建）
- 环境: 开发 + 运行时（本机 PC 10.0.0.2 + ws-e1-base 板 + TJ180A484S）；Windows
- SDK 版本: Efinity 2026.1（D:\efinity\2026.1，efx_run 自举；RiscFree 工具链
  D:\efinity\efinity-riscv-ide-2026.1\toolchain\bin）；Questa（tb_udp_v2）
- 项目修订: 未纳入 git（与 DAYLOG 11-01 记录一致）；全部为未提交工作树改动
- 需求与结果来源: 会话 + 用户补充（Wireshark 观测、bit/hex 下载规矩）

## 目标与实际结果

目标：把 RAW10 1080p@30fps 测试视频流（udp_pat_gen_v2）经 TSE MAC→YT8531→网线
发到 PC，并用 doc/pc_tools/test_raw10_rx.py 做板级验收（G7 门）。

实际结果：**G7 板级验收 PASS**——295 完整帧、0 丢帧、0 重复/乱序、30.00 fps、
622.1 Mbps、5 个采样帧全像素比对 OK（10s 窗口，帧号 738..1037）。

## 总体过程与现象

| 阶段 | 做了什么 | 观察现象 / 人工干预 | 结果与来源 |
|---|---|---|---|
| v2 集成 | udp_pat_gen_v2 接顶层、raw10_mode CSR 位、TB 全套 | 早前版本 raw10_mode 顶层连线缺失（已修） | 仿真 PASS（历史会话） |
| 固件 | TEST_MODE=0 + PAT_TYPE=2，pulse 时序 100µs | — | ELF 产出 |
| 板上"递增流"谜题 | 多轮重编/读探针 | 'h83 magic case 读数不符（case 重复项）；板上长期跑旧网表 | 观察记录 |
| 旧网表实锤 | 'h92 借道探针（pat_dbg_i 塞入 0x092 高 9 位） | 重烧 .bit 后 D92=0x00700fff（raw10_r/pat_en/inf=1）→ 此前"烧板未生效" | 观察记录（OpenOCD 读数） |
| 烧写规矩（用户明确） | .bit=JTAG 直配立即生效；.hex=更新 flash 需重新上下电 | 多轮"烧板没生效"实为 hex 未断电 | 用户报告 |
| 末包丢失定位 | 线上 1787 包/帧、无 858B 末包；MAC OVF/CONT/ifOut 计数器零增量 | MAC/FIFO/溢出全部排除 | OpenOCD + PC 嗅探 |
| 根因（用户 Wireshark） | 抓到 900B 末包在线：`[BAD UDP LENGTH 1466 > IP PAYLOAD LENGTH]` | Windows 协议栈静默丢弃长度不符 UDP → PC socket 永远收不到末包 | 用户报告（决定性） |
| RTL 修复 | 末包 UDP len=866 / IP len=886（原为满包常量 1466/1486） | pkt_is_last_w 选择，注释注明实证依据 | rtl/udp_pat_gen_v2.v |
| 仿真 | tb_udp_v2 同步末包长度期望 | 3 帧 8,044,200 字节逐字节校验 | ALL CHECKS PASSED（证据 E2） |
| 编译 | efx_run --flow compile | map/interface/pnr/pgm 全 PASS | 证据 E3 |
| 下载与加载 | ftdi_pgm .bit（JTAG，0x00690A79）+ OpenOCD 加载 ELF | Firmware started | 观察 |
| G7 验收 | test_raw10_rx.py --seconds 10 | 全项 PASS | 证据 E1 |

## 关键产物与证据

| 证据 ID | 原始产物/日志 | 版本/输入关联 | 支持的事实 | 位置 | 快照/SHA-256 | 采集时间/复制类型 | 状态 |
|---|---|---|---|---|---|---|---|
| E1 | test_raw10_rx.py 输出 | 本 bit+ELF | G7 全项 PASS | evidence/g7_acceptance_output.txt | a5c62279…16678 | 2026-11-05/抄录 | 已快照 |
| E2 | Questa TB 日志 | 修复后 RTL | 末包长度校验 PASS | evidence/tb_v2_fix.log | 2b03f9bc…f95d | 2026-11-05/原始字节 | 已快照 |
| E3 | efx_run 编译日志 | ws_e1_tse.xml | map/pnr/pgm PASS | evidence/g7_compile.log | e55513df…662b | 2026-11-05/原始字节 | 已快照 |
| E4 | Wireshark 单行抓包 | 修复前 bit | BAD UDP LENGTH 1466>866（用户 PC 上抓到） | — | — | 2026-11-05/用户报告 | 用户报告（未留原始文件） |
| E5 | ws_e1_tse.bit | 本次编译产物 | 板上运行的配置 | outflow/ws_e1_tse.bit | 7576bb41…a6bc | 2026-11-05/原始 | 在库（可能被下次编译覆盖） |
| E6 | udp_pat_gen_v2.v | 修复版源 | 末包长度字段修复 | rtl/udp_pat_gen_v2.v | 1708e84b…65c5 | 2026-11-05/原始 | 在库 |

## 验证到达的边界

- 仿真：tb_udp_v2 全 PASS（含末包 900B 帧长、IP/UDP 长度、IP 校验和、MIPI 打包、像素公式、30fps 节拍）。
- Build：efx_run compile（map→interface→pnr→pgm）全 PASS。
- 编程：ftdi_pgm -m jtag 下载 .bit 成功（Device ID 0x00690A79）；OpenOCD 加载 tseDemo.elf 成功。
- 板级功能：G7 验收 PASS（E1）。这是真实硬件流验证，非仅编译证据。

## 项目经验与 SDK 反馈

项目教训：
1. **调试下载一律 .bit（JTAG 直配）**；.hex 仅更新 flash，需重新上下电。多轮"烧板未生效"均源于此。
2. **生成式 UDP/IP 包的长度字段必须逐包计算**，禁止对变长包使用编译期常量——PC 协议栈会静默丢弃，且自家接收工具若不校验头部一致性就永远发现不了（本次由用户 Wireshark 发现）。
3. 探针借道已被证实可读的 CSR 分支（'h92），配合"新旧网表读数可区分"的位设计，是识别板上旧网表的低成本手段。
4. Efinity 综合器不支持层次引用（跨模块探针必须加端口）；reg_apb3 的 debug 读通道（JTAG mem2array）读 MAC CSR（0x68 等）不可靠（恒 0xffff），CPU 固件读同一地址正常。
5. case 分支重复项会被综合静默取第一个——加 magic 分支前先查地址冲突。

可转移给 SDK 的候选：
1. udp/pat 类生成器的 PC 端校验工具应内置 **IP total length / UDP length 与实际载荷一致性**检查（本次 test_raw10_rx.py 的盲区）。
2. EvoVerse 编程步骤应显式区分 .bit（直配）与 .hex（flash，需上下电）并汇报。
3. 模板化"CSR 借道探针"方法（把 10 位内部状态塞进已验证 CSR 读数的高位）可写进调试手册。

Development intake 位置与状态: 未归并（本仓库内项目级记录）。

## 缺口与后续

- E4 的 Wireshark 原始抓包文件未留存（用户侧观测，行内容已抄录于本回顾过程表）。
- 修复前"末包被 OS 静默丢弃"在 Windows 协议栈层面的行为是合理推断 + Wireshark 标注佐证，未做内核级行为实验。
- 固件 [TXOK] 仲裁打印代码已入 main.c 但未在上板流程中产出读数（根因已由 Wireshark 闭环，该打印保留待后续复用）。
- DAYLOG 2026-11 本轮条目同日补记。
- G6（递增图案模式吞吐量化）与 G1/G2 回切复测仍待做。

<!-- evoverse-project-review:evidence
{"hardwareStatus":"PASS_G7_UDP_RAW10_30FPS","evidence":[
{"category":"board_validation","path":"project-review/2026-11-05-g7-raw10-udp-stream/evidence/g7_acceptance_output.txt","digest":"a5c6227936862b778382e3703452d28a2b406ffbb1f9aad2b735b6e33e216678"},
{"category":"build_log","path":"project-review/2026-11-05-g7-raw10-udp-stream/evidence/g7_compile.log","digest":"e55513df19f880f25bee9d6e92ebc8b92edd86a48f2ba88fb1d41dbd834d662b"},
{"category":"simulation_log","path":"project-review/2026-11-05-g7-raw10-udp-stream/evidence/tb_v2_fix.log","digest":"2b03f9bc365fb194b26a4a1c1b91df27bd2bc1b9f716764b8421f7998a93f95d"},
{"category":"rtl_source","path":"rtl/udp_pat_gen_v2.v","digest":"1708e84b5d14c4e8fe07d59fe7480af11ebc2d7f879ce2b1a269174caa7d65c5"},
{"category":"bitstream","path":"outflow/ws_e1_tse.bit","digest":"7576bb412ca024307489094893b32ef4708749a37c089732c28556b4f7f5a6bc"}
]}
-->
