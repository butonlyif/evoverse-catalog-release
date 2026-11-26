[English](test_guide.en.md) | 中文

# 测试指南

## 硬件准备

1. TJ180A484S 板，JTAG + USB 串口线连接。
2. SD 卡（≥ 32 MB，卡尾需 ~17 MB 可写区；MBR/FAT 不受影响）。
3. MIPI CSI-2 接收端（DPI 转接板 / 屏 / 分析仪），2 lane D-PHY，720p60。
4. 串口终端 115200 8N1。

## 步骤

1. 烧 FPGA 位流 `outflow\ws-e1-sd-ddr-csi2.bit`。
2. 加载固件 `sw\top_demo\build\top_demo.elf`（Eclipse `top_demo_ti.launch` 或 openocd
   `sw\bsp\openocd\flash_ti.cfg`）。
3. 上电 / 复位，观察串口输出。

## 串口输出判读

### 启动段

```
--- top_demo: SD -> DDR dual-port -> CSI-2 path test ---

Initialize...Done

Card: xxxx MByte, yyyyyy blocks, bus 4-bit
```

若卡容量不足会打印 `ERROR: card too small ...` 并停住——换卡。

### 阶段一：帧保留 / 双口通路测试（frame_path_test）

对卡尾 A/B 帧区做 SD 读写 + DDR port0/port1 双向校验，最后打印：

```
PASS: SD -> DMA -> DDR port0 write -> DDR port1 read verified.
```

其后 `[5b] port1 address probe`、`[6] filled 0x00200000...` 等为非破坏性诊断
（会覆写测试区数据），异常只在排查时参考，不影响最终判定。

### 阶段二：8 图案 MIPI 流测试（pattern_path_test）

| 串口行 | 含义 |
|---|---|
| `video_reader ID ok (APB1)` | VR 寄存器接口正常 |
| `[1/5] patterns already on card ... skip` / `no valid signature -> generate ...` | 首次运行生成图案并写卡（约几十秒）；后续运行跳过 |
| `[2/5] SD write 28800 blocks ...` | 仅首次运行出现 |
| `[3/5] SD read 28800 blocks -> DDR 0x2000000` | ADMA 经 port0 装载图案 |
| `[4/5] CPU port0 checksum: 8/8 ok` | CPU 视角 port0 数据完整 |
| `[5/5] DDR port1 hardware checksum: 8/8 ok` | 硬件读 master 视角 port1 数据完整 |
| `starting MIPI CSI-2 TX stream (8 patterns x 180 frames, 3 s each)...` | 起流 |
| `  t=0s: status=0x1 pat=0 frames=..`（每 2 s 一行） | RUN 态监控 |
| **`PASS: SD -> DDR -> MIPI CSI-2 TX streaming (check display).`** | **最终判定** |

同时屏幕应出现图案循环，每个 3 s：

| 序号 | 图案 |
|---|---|
| 0 | 彩条 |
| 1 | 渐变底 + 十字准线 |
| 2 | 水平渐变 |
| 3 | 垂直渐变 |
| 4 | 纯红 |
| 5 | 纯绿 |
| 6 | 纯蓝 |
| 7 | 32x32 棋盘格 |

串口 `pat=` 值与屏幕图案序号一一对应。

## 失败模式排查

| 现象 | 定位 |
|---|---|
| `ERROR: video_reader not found` / `P1Reader ... != 0x50315231` | 位流与固件不配套（旧位流 / APB 地址错），重烧配套 bit |
| `ERROR: LBA 0x.. holds boot/FS data, abort` | 卡尾签名区是文件系统数据，换卡或重新分区 |
| `[4/5]`（CPU 校验）失败 | SD 读 / port0 写链路：查 sdhost_ctrl 中断、ADMA |
| `[5/5]`（硬件读校验）失败但 [4/5] 通过 | port1 读通路：看 `P1Reader_Diag` 输出的 RID/AR_DELAY/IDLE_RV（幽灵响应特征） |
| `FAIL: video_reader stalled (status 0x..)` | 起流后无帧推进：OWN_P1 未生效 / CSI-2 TX 无 ready / DPHY 未锁定（查 `dphy_tx2_STOPSTATE_*`） |
| 串口 PASS 但屏无图 | 接收端配置：lane 数、720p60 时序、YUV422 格式、字节序（见 register_map.md 像素格式注） |
| 屏幕某图案撕裂/错位 | 该图案数据完好（校验已过），多为接收端行同步问题；对比 pat 序号定位 |

## 回归要点

- 测试全程不改 FPGA 侧状态；重跑只需复位 CPU 重新加载固件。
- 图案数据持久存卡（签名块校验），换固件版本重跑无需重新写卡。
- `OWN_P1` 仲裁：校验阶段（[5/5] 前）port1 归 SOC/调试 master，起流后归 video_reader，
  复位 CPU 不会自动归还——重新加载固件即从 OWN_P1=0 开始。
