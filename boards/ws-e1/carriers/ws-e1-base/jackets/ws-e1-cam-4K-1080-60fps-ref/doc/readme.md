[English](readme.en.md) | 中文

# ws-e1-cam-4K-1080-60fps-ref 项目说明

Efinix Titanium FPGA 直连相机 demo：IMX415 → CSI-2 RX → 图像流水线 → CSI-2 TX → 面板。
**无 DDR、无帧缓冲**，显示帧率跟随传感器（1080p60 直通）。当前为**双相机**架构（2 路完整链路），RISC-V 软核只负责传感器 I2C 配置与运行时 CSR 调节。

> 状态（2026-09-27）：单路链路已板级验证通过（图案/相机显示均正确）；双相机改动（RTL + 固件）已完成，**尚未重新综合上板**。

## 1. 硬件架构

```
每路 top_cam（rtl/top_cam.sv）：
  DPHY RX硬核 → my_csi2_rx(裸IP) → RAW10 4px @sys_clk_200m
    → [mux: pattern_gen | sensor]  ← CSR pat_en 软切换（沿触发两域软复位）
    → camera_path:
        raw_2_axi4st (解包/窗口) → demosaic → wb_axis → rgb2yuv_axis
        → shape_video_axis（跨域 aclk→pixel_clk + 成形 + 帧率锁定）
    → UYVY 4px @tx_pixel_clk → my_csi2_tx(裸IP) → DPHY TX硬核 → 面板

top_cam_demo（rtl/top_cam_demo.sv）= 2x top_cam + riscv_soc + DDR空跑 + PLL复位链
```

时钟：`sys_clk_200m`（RX 像素输出域 + 流水线 aclk + APB pclk）、`tx_pixel_clk` 37.125MHz（面板像素 + TX + pattern 行节拍源）、`sys_clk_100m`（RX 控制器钟，AXI tie off）、`i_clk_27m`（TX 上电自复位基准）、`esc_clk`（DPHY TX）、`dphy_rx*_clk_CLKOUT`（RX 恢复字钟，无流停振）。

DDR 不使用，但引脚绑定保留（peri.xml 不动），CFG FSM 照常初始化 DDR 硬核。

## 2. 双相机资源映射

| | cam0 (u_cam_0) | cam1 (u_cam_1) |
|---|---|---|
| 数据链路 | DPHY RX0 → DPHY TX0 | DPHY RX2 → DPHY TX2 |
| APB（apb_cam_ctrl） | slave0 = 0xF810_0000 | slave1 = 0xF811_0000 |
| I2C（IMX415，7bit 0x1A） | I2C0 = 0xF801_6000 | I2C1 = 0xF801_7000 |
| cam_en（GPIO0 整字写） | bit0 | bit1 |

APB slave2/3 为 dummy 即答（误访问不挂 CPU）。地址宏在 `sw/bsp/include/soc.h`，固件侧封装在 `sw/top_demo/src/userDef.h`（APB_0/APB_1）。

## 3. 目录结构

- `rtl/` — 全部 RTL（见下表）
- `ip/` — Efinity 裸 IP：`my_csi2_rx`、`my_csi2_tx`、`riscv_soc`（SaxonSoc/VexRiscv，BRAM 固件）
- `sw/top_demo/src/` — 固件源码：`main.c`、`imx415_init.c/.h`、`userDef.h`
- `sw/bsp/` — SaxonSoc BSP（驱动头文件、链接脚本、openocd）
- `sim/` — QuestaSim TB 与回归日志
- `work_syn/`、`work_pnr/`、`work_pt/`、`outflow/` — Efinity 综合/布线/烧录脚本与产物（`ws-e1-cam-ddr-csi2.bit/.hex`）
- `ws-e1-cam-ddr-csi2.peri.xml` — peri 子系统引脚绑定（DPHY 硬核/SOC 外设，改引脚才动它）

### RTL 模块

| 文件 | 职责 |
|---|---|
| top_cam_demo.sv | 双相机顶层：2x top_cam + soc（I2C/GPIO/APB 分配）+ DDR 空跑 |
| top_cam.sv | 单路：CSI2 RX + pattern_gen + camera_path + CSI2 TX + apb_cam_ctrl + 行节拍发生器 + 源切换软复位 |
| camera_path.sv | 五级流水装配（raw→demosaic→wb→rgb2yuv→shape），含 pat_en 时 wb 直通/blk_clip 旁路 mux |
| raw_2_axi4st.sv | RAW10 4px 解包 + 传感器窗口几何（1944x1096 有效 1920x1080） |
| demosaic.sv | Bayer→RGB（RGGB 默认，G 方向自适应可选） |
| wb_axis.sv | 白平衡增益，**编码 0x40 = x1.0**（隐含 raw10→8bit x4） |
| rgb2yuv_axis.sv | BT.601 full-range YUV + **暗场钳位 blk_clip**（Y<24→0 且 U=V=128，相机域专用） |
| shape_video_axis.sv | 跨域成形：FIFO 水位管理 + 帧率锁定 + 消隐段整行排水 |
| pattern_gen.sv | 自诊断图案（pclk 行节拍推进）：灰竖 ramp / 红蓝竖条 / 灰横 ramp / 8x8 棋盘 |
| apb_cam_ctrl.sv | APB CSR，唯一寄存器 CTRL@0x00，复位 0xB4EBC80C 上电即出像 |
| reset_ctrl.sv | 多域同步复位链 |

## 4. CSR（apb_cam_ctrl CTRL@0x00，两路寄存器组相同）

```
[1:0]  bayer_phase  0=RGGB 1=GRBG 2=GBRG 3=BGGR
[2]    adaptive     demosaic 自适应
[3]    pat_en       1=图案源 0=传感器（变化沿触发 camera_path 两域软复位）
[5:4]  pat_sel      0=灰竖 ramp 1=红蓝竖条 2=灰横 ramp 3=棋盘
[15:8] wb_r  [23:16] wb_g  [31:24] wb_b     （0x40=x1.0）
复位默认 0xB4EBC80C = wb 200/235/180 + pat_en=1（灰 ramp）+ adaptive=1 + RGGB
```

写入逐拍生效（帧内即变，源切换撕裂最多 1 行）。

## 5. 关键设计决策（2026-09 板级验证史，勿回退）

1. **pattern pclk 行节拍**：pattern_gen 行推进等 `line_tick`（tx_pixel_clk 计 550 拍翻转 → 2FF CDC 取沿）。每帧 1091 行 + 34 pad 节拍 = 618,750 pclk = 精确 60fps。旧 aclk 自由跑有 37ppm 双钟差 → 内容 2.5 行/s 漂移 = 板级图案慢滚动，已根治。
2. **wb 直通**：pat_en=1 时 wb 强制 0x40。sensor 校准增益（200/235/180 ≈ x3.1/3.7/2.8）会把按显示幅度编码的图案打出饱和色偏（橙显黄、蓝显青、灰 ramp 偏绿）。
3. **blk_clip 旁路**：rgb2yuv 暗场钳位（Y<24→0、UV→128）是 sensor 暗场 FPN/暗电流噪声治理，会把图案精确码值的暗部整段压黑（渐变前 ~10% 黑平顶）。`blk_clip = !pat_en`：相机域钳位、图案域旁路。
4. **红蓝竖条**（pat_sel=1）：单通道满幅 0x3C0 饱和钳 255、零值站乘任意增益仍 0，天然 wb 免疫。
5. **shape 帧间调节三件套**：`DRAIN_CAP_LINES=54`（消隐段整行排水帽）/ `VFRONT_WAIT_LINES=4`（帧首低水位门）/ `HIGH_LINES=60`（整帧丢弃兜底）。显示 Vblank(45 行) 与供给 pad(34 行) 相位自由漂移，帧内锯齿最坏 79 行 > FIFO 容量 68.27 行，任何固定水位带必撞——水位钉 [9,55] 行 + PPM 帧率差由排水行数逐帧吸收。
6. **源切换软复位**：pat_en 变化沿 → ~1µs 两域脉冲复位 camera_path（shape 读写指针清零、等新源 SOF），消除切换后画面垂直偏移。
7. **IMX415 配置要点**（imx415_init.c，逐字节 ACK 校验 + 有界等待）：
   - 流出顺序：0x3002=0（master start，仍在 standby 中先写）→ 0x3000=0（释放 standby）→ ~220ms
   - 1080p60 = VMAX 2250 / HMAX 550 / 全像素 + 2/2 binning；BLKLEVEL=50
   - 1782Mbps DPHY timing 表 **TCLKZERO 高字节 0x401F=0x01 必写**；LANEMODE 0x4001=0x03（4-lane）
   - "SONY magic" 块必须在 VMAX/HMAX/时钟寄存器还是复位默认值时写（顺序错会 wedge sensor，0x3736 观测过）
   - 位流必须以 data_rate=1782 构建（peri.xml 已设）
8. **固件 I2C 全部有界等待**：BSP 的 `i2c_*Blocking` 在总线卡死时死等，禁止使用（首板 bring-up 冻结过的根因）；cam_en 重试前 300ms 硬复位 + 500ms 放电。

## 6. 固件（sw/top_demo）

启动流程：两路 APB 自检（读回 0xB4EBC80C）→ `imx415_init(0)` → `imx415_init(1)` → UART 菜单轮询（0.5s tick，5s 心跳打印两路 CSR）。上电两路都发灰度图案，传感器就绪后按键切相机。

UART 菜单（BSP UART TERMINAL）：`[` / `]` 选目标路 cam0/cam1，其余键只作用于目标路：`c` 相机 / `p` 图案 / `g` `o` `h` `b` 选图案 / `1-4` bayer 相位 / `z` adaptive / `q a w s e d` wb +/-16 / `x` 复默认 / `i` 双路回显。

双相机关键实现：`imx415_init(id)` 运行时切换 I2C 基址 + cam_en bit；**GPIO 读-改-写按 bit 隔离**（GPIO OUTPUT 是整字写，整字清零会断电另一路已出流相机）。两路共用一份 I2C 时序配置（50kHz）。

构建（Windows，已验证）：

```
PATH 加 D:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin（riscv-none-elf-gcc 13.4.0）
cd sw\top_demo && make
产物 build/top_demo.hex —— 经 JTAG UPDATE/RESET 加载进 BRAM（不可改此路径）
```

## 7. 仿真与回归状态

- TB：`sim/tb_top_cam_demo.v` 例化的是 **top_cam（单路）**，含参考链（raw→demosaic→wb→rgb2yuv，与 DUT 逐拍 `===` 对拍）+ 五锚（图案帧周期 16,666,650ns / 红蓝条绝对值 / 灰 ramp R≈G≈B±3 / wb 直通 / blk_clip 旁路）。
- 最新回归日志（均 **TB_PASS**）：`sim/sim_pclktick.log`、`sim_redblue.log`、`sim_wbbypass.log`、`sim_blkclip.log`。
- 仿真注意：vlog 全量编译时 **stub 是 .sv 后缀**（stub_riscv_soc.v 除外）；vsim 全量回归 ~15 分钟。
- **双相机顶层 top_cam_demo 无专用 TB**；u_cam_1 接线（dphy_rx2/dphy_tx0/apb1/i2c1）目前仅经代码评审，未仿真未上板。

## 8. 构建 / 烧录流程

```
1. 综合+布线（bash）：work_syn/run_efx_map.sh → work_pnr/run_efx_pnr.sh → work_pnr/run_efx_pgm.sh
   产物 outflow/ws-e1-cam-ddr-csi2.bit / .hex
2. 固件：sw/top_demo make → build/top_demo.hex → JTAG UPDATE/RESET 加载 BRAM
3. 上板顺序：下载位流 → 固件自动跑（图案先出像）→ 看 UART → 'c' 切相机预览
```

RTL 改动后需重新综合；固件改动只需重烧 hex。

## 9. 当前待办 / 已知坑

- [ ] 双相机改动重新综合 + 固件重烧，上板验证两路
- [ ] I2C1 飞线为新路：若 cam1 无 ACK/偶发 NACK，优先查上拉与线长，必要时给 cam1 单独一份 `I2c_Config`
- [ ] TB 仍是单路 top_cam；若要回归双相机顶层需新 TB（可复用 stub + 双份参考链）
- [ ] 相机模式（pat_en=0）行为与旧版逐位一致（wb 用 CSR 值、blk_clip 使能），单路上板结论仍有效
- 历史踩坑：vlog 编译 stub 文件名 `.sv` 后缀；wb_axis 增益 0x40=x1.0 勿按百分比理解；pattern 值是显示幅度编码（0x3C0=满幅），过 wb 必饱和——所以才有直通 mux。
