[English](register_map.en.md) | 中文

# 寄存器映射

固件定义见 [sw/top_demo/src/userDef.h](../sw/top_demo/src/userDef.h)，RTL 实现见
[rtl/ddr_port1_reader.v](../rtl/ddr_port1_reader.v) 与 [rtl/video_reader.v](../rtl/video_reader.v)。

## 总线拓扑（Sapphire SOC APB 空间）

| 基址 | 外设 | 说明 |
|---|---|---|
| `0xF8010000` | `system_uart_0` | 串口 115200 8N1 |
| `0xF8100000` | `ddr_port1_reader`（P1R） | APB slave 0，port1 校验读 master |
| `0xF8110000` | `video_reader`（VR） | APB slave 1，port1 视频流 master |
| `0xF8120000` | SDHC（经 APB3→AXI4-Lite 桥） | 寄存器偏移 `+0x100` |

DDR 可用区间：`0x01300000 - 0xF7FFFFFF`。

## ddr_port1_reader（P1R，基址 0xF8100000）

单突发校验读 master：发一次 AR，收满 `BEATS` 拍后置 DONE，返回校验和与首末字。
调试用（正式视频流走 video_reader）。

| 偏移 | 名称 | 访问 | 位段 |
|---|---|---|---|
| `0x00` | `REG_ID` | RO | 读 `0x50315231`（"P1R1"） |
| `0x04` | `REG_CTRL` | RW | [0] START，[1] CLR_DONE，[2] ABORT |
| `0x08` | `REG_STATUS` | RO | [0] BUSY，[1] DONE，[2] SLVERR，[3] RVALID seen（粘滞），[4] RLAST seen（粘滞） |
| `0x0C` | `REG_ADDR` | RW | 读起始地址（字节） |
| `0x10` | `REG_LEN` | RW | 读长度（字节） |
| `0x14` | `REG_BEATS` | RW | 期望 R 拍数 |
| `0x18` | `REG_SUM_LO` | RO | 数据 64 位校验和低 32 位 |
| `0x1C` | `REG_SUM_HI` | RO | 校验和高 32 位 |
| `0x20` | `REG_FIRST_W0` | RO | 首拍 word0 |
| `0x24` | `REG_LAST_W0` | RO | 末拍 word0 |
| `0x28` | `REG_RLAST_BURST` | RO | 最后一次突发实际返回拍数（RLAST 锁存） |
| `0x2C` | `REG_RID_FIRST` | RO | 首拍 RID（ARID=0，非 0 即幽灵响应） |
| `0x30` | `REG_RID_LAST` | RO | 末拍 RID |
| `0x34` | `REG_AR_DELAY` | RO | AR 发出到 ARREADY 的周期数（0xFF = 未接受） |
| `0x38` | `REG_IDLE_RV` | RO | DONE 后空闲期 RVALID 上升沿数（>0 = 宏自行吐响应） |

## video_reader（VR，基址 0xF8110000）

循环帧读 master：从 `ADDR` 起连读 `NFRAME` 帧每帧 `FBYTES` 字节，每 `NSWITCH` 帧换一帧
地址（即换图案），无限循环。

| 偏移 | 名称 | 访问 | 位段 |
|---|---|---|---|
| `0x00` | `REG_ID` | RO | 读 `0x56314452`（"V1DR"） |
| `0x04` | `REG_CTRL` | RW | [0] RUN，[3] OWN_P1 |
| `0x08` | `REG_STATUS` | RO | [0] BUSY，[1] SLVERR |
| `0x0C` | `REG_ADDR` | RW | 帧数组基址（本工程 `0x02000000`） |
| `0x10` | `REG_FBYTES` | RW | 每帧字节数（1843200） |
| `0x14` | `REG_NFRAME` | RW | 帧数 = 图案数（8） |
| `0x18` | `REG_NSWITCH` | RW | 每图案帧数（180 = 3 s @60 fps） |
| `0x1C` | `REG_PAT_IDX` | RO | 当前图案索引 0..7 |
| `0x20` | `REG_FCNT` | RO | 累计帧计数 |

## 起流写序（main.c 阶段 [6]）

```
VR_Wr(CTRL,   0x0);      // 停流, OWN_P1=0
VR_Wr(ADDR,   0x02000000);
VR_Wr(FBYTES, 1843200);
VR_Wr(NFRAME, 8);
VR_Wr(NSWITCH,180);
VR_Wr(CTRL,   0x8);      // OWN_P1=1  (port1 交给 video_reader)
VR_Wr(CTRL,   0x9);      // RUN=1    起流
```

轮询判据：`(STATUS & 0x3) == 0x1`（RUN 态非忙、无 SLVERR）且 `FCNT > 100`。

## SD 卡数据布局（LBA，卡尾布局，避开 MBR/FAT）

```
sign_lba = pat_lba - 1                       签名块: magic "YUV8" + 几何 + 8×校验和
pat_lba  .. pat_lba+28799                    8 × 3600 块图案 (每图案 1843200 B)
frame_lba..(A/B 帧保留测试区, 3600 块)         frame_path_test 用
最后 0x100 块                                 保护边距
```

像素格式注意：CSI-2 TX pack-64 每像素 16-bit slot `{Y[15:8], C[7:0]}`；DDR 小端下相邻
两像素字节序为 `C Y C Y`（U Y V Y），**不是**标准 YUYV（Y U Y V）。
