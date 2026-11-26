[English](phase0-summary.en.md) | 中文

# Phase 0 总结 — DDR 双异步端口前提验证（架构 v4）

> 状态：**已完成（2026-10-20）** · 规格：SPEC-001 rev.1 APPROVED · 对应需求：R6 / RK-1 定界 / EV-09 确证

## 1. 目标

验证架构 v4 的全部前提：**Efinity DDR 硬核（LPDDR4x，ddr_inst 单控制器双 AXI 口）能否接受 Port1（axi_target1）工作在 148.5MHz 独立 AXI 时钟**（Port0 保持 200MHz 写口）。此前提不成立则整个 v4（reader 搬显示域、删除数据路径 CDC）不成立。

## 2. 关键发现

- 平台里 **148.5MHz 输出已存在**：`peri.xml` 中 `pll_csi`（PLL_BL0，27M 参考）的 CLKOUT1 名为 `pixel_clk`（VCO 1485M ÷10），conn_type=gclk，正是 CSI TX 像素钟源——**无需新增 PLL**。
- 板级顶层实为 `top_cam_demo.sv`（fw/fr 实例所在）；DDR 为单硬核双 AXI 口结构（`axi_target0` / `axi_target1` 各自独立 ACLK pin）。
- 现有 `disp_timing_gen.v` / `disp_line_fifo.v` 是新架构 disp_timing / tx_line_buf 的直接基座（另项利好）。

## 3. 改动清单

| 文件 | 改动 |
|---|---|
| `ws-e1-cam-ddr-csi2.peri.xml` | `axi_target1` 的 `ACLK_1` 时钟源 `sys_clk_200m` → `pixel_clk`（单点换绑，Port0 不动） |
| `rtl/top_cam_demo.sv` | 新增 localparam `DDR_P1_148=1`；`FRAME_WRITER` 暂 0（fw/fr 回 idle，可回退）；新增 generate 分支 `g_ddr_memtest_148`：现成 `ddr_memcheck` 整体挂 **target1 @ pixel_clk**（读写分相自检，复用阶段 0 板测形态），配 pixel_clk 域 `reset_ctrl`（u_mc_rst_148） |
| 验收读数 | DIAG11 @0x2C：`{err_cnt, mcst, ..., done_raw, st, lock, cfg_ok, done, fail}` |

## 4. 验证结果

| 关卡 | 结果 | 说明 |
|---|---|---|
| `efx_run --flow interface` | **PASS** | peri.xml 换绑被 Efinity 2026.1 接受（RK-1 工具侧定界 ✓） |
| `--flow map` | **PASS** | 新分支综合零错误 |
| `--flow pnr` | **PASS** | 布线+STA：148.5M 域内 slack +2.006ns；新增逻辑零违例；200M↔148.5M 互跨负 slack 为**存量** CDC 路径（SDC 无 async 组，上轮 bit 同样存在，非本次引入） |
| **板级**（上板加载新 bit） | **PASS** | `cam_show` 读 DIAG11：**err=0 st=3 lock=1 cfg=1 done=1 fail=0** —— memcheck 148.5M 全区写→读回比对零错（26MB / 3495 burst） |

**结论：EV-09 由 PROPOSED 升 CONFIRMED。双异步端口前提成立。**

## 5. 环境备忘（工具链 CLI）

```powershell
# 环境里已有 EFINITY_HOME 指向安装根，会跳过 setup.bat 导致 PYTHONHOME 错误；
# 用 cmd 链式调用 setup.bat 一次性设全环境：
cmd.exe /v:on /c "call D:\Efinity\2026.1\bin\setup.bat && D:\Efinity\2026.1\bin\efx_run.bat <project.xml> --flow <interface|map|pnr>"
# flow 名：interface（peri 处理）/ map（综合）/ pnr（布线+STA）
```

## 6. 回退点 / 遗留

- 回退：`FRAME_WRITER=1`、`DDR_P1_148=0` 即恢复 v3.4 板测形态。
- 新位流：`outflow/ws-e1-cam-ddr-csi2.bit`（g_ddr_memtest_148 分支，显示黑屏为预期——回放链未接）。
- RK-2（FRAME_B 与 2Gb 容量边界）缓解：现有布局 2×17.6MB=35MB ≪ 256MB；memtest 覆盖 0~26MB 区域已含边界前区域，Phase 1 数据比对进一步覆盖。
