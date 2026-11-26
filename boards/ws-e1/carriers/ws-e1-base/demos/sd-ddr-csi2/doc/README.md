[English](README.en.md) | 中文

# ws-e1-sd-ddr-csi2

基于 TJ180A484S 器件的 Efinity 工程：**SD 卡 → DDR 双口 → MIPI CSI-2 TX** 图像通路 demo。

- 顶层模块：`top_demo`（工程 XML：`ws-e1-sd-ddr-csi2.xml`）
- 器件：`TJ180A484S`（器件型号为属性约束，不可改名，见 XML `efx:device` / peri.xml `device_def`）
- 视频：1280x720 YUV422 60 fps，8 个测试图案每 3 s 自动轮换、无限循环
- 固件：RISC-V (Sapphire SOC) 裸机程序，Eclipse 工程名 `top_demo`

详细内容见同目录其它文档：

| 文档 | 内容 |
|---|---|
| [architecture.md](architecture.md) | 模块层次、时钟树、数据通路、DDR 仲裁 |
| [register_map.md](register_map.md) | ddr_port1_reader / video_reader 寄存器表 |
| [test_guide.md](test_guide.md) | 测试流程、串口输出判读、故障排查 |

## 目录结构

```
ws-e1-sd-ddr-csi2/
├── ws-e1-sd-ddr-csi2.xml        # Efinity 工程文件
├── ws-e1-sd-ddr-csi2.peri.xml   # Interface Designer 引脚/PLL/GPIO
├── ws-e1-sd-ddr-csi2.sdc        # 时序约束
├── package_settings.xml
├── rtl/                              # 用户 RTL（7 个文件）
│   ├── top_demo.v                    # 顶层：引脚、MIPI TX 例化
│   ├── top_soc_sd.v                  # SOC 封装：riscv_soc + sdhost_ctrl + DDR 仲裁
│   ├── ddr_port1_reader.v            # DDR AXI port1 校验读 master（调试用）
│   ├── video_reader.v                # DDR port1 视频流 master（OWN_P1 仲裁）
│   ├── shape_video_data.v            # 异步 FIFO + 行/帧对齐
│   ├── mipi_tx_top.v                 # CSI-2 TX 打包发送
│   └── reset_ctrl.v                  # 复位同步
├── ip/                               # Efinity 生成 IP
│   ├── sdhost_ctrl/                  # SD 主机控制器（SDIO + ADMA）
│   ├── riscv_soc/                    # Sapphire RISC-V SOC
│   ├── apb3_2_axi4_lite_sdhost/      # APB3→AXI4-Lite 桥
│   └── mipi_csi_tx_2p5g/             # MIPI CSI-2 TX（DPHY TX2）
├── sw/
│   ├── top_demo/                     # 裸机固件（Eclipse 工程名 = 文件夹名 = top_demo）
│   │   ├── makefile
│   │   └── src/                      # main.c / source.c / userDef.h 等
│   ├── bsp/                          # 固件 BSP（include/linker/openocd/driver）
│   └── cpu0.yaml
├── doc/                              # 本文档
├── outflow/                          # 构建产物（.bit/.hex/.map.v 等，可再生成）
└── work_syn/ work_pnr/               # 综合布线工作目录
```

## 依赖

| 项 | 要求 |
|---|---|
| Efinity | 含 Interface Designer 与 Programmer（本工程用 2026.1 版验证） |
| RISC-V 工具链 | `efinity-riscv-ide-2026.1\toolchain\bin`（`riscv-none-elf-gcc`）+ `build_tools\bin`（`make`） |
| SD 卡 | 容量 ≥ 32 MB；卡尾需约 17 MB 可覆写区（图案 + 帧保留测试区） |
| 串口终端 | 115200 8N1（板载 UART，GPIOR_72/70） |
| 显示 | MIPI CSI-2 接收端：DPI 转接板 / 屏 / 协议分析仪（2 lane D-PHY） |

> SD 卡注意事项：测试数据写在**卡尾**（MBR/FAT 不动）。若卡尾签名区读到 `0x55AA` 引导/文件系统数据，固件会拒绝写入以保护原数据。

## 构建 FPGA

方式一（GUI）：Efinity 打开 `ws-e1-sd-ddr-csi2.xml`，运行 Compile Flow。
方式二（CLI）：

```
awesom build_project --project D:\Projs\ws-e1-sd-ddr-csi2
```

产物：`outflow\ws-e1-sd-ddr-csi2.bit` / `.hex`（约 3 分钟全流程）。

时序说明：`timing.rpt` 存在 10 条小负 slack（-0.3 ~ -0.4 ns），与板上验证通过的原工程基线逐条一致，属已知可接受状态。

## 构建固件

```
set PATH=D:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin;D:\Efinity\efinity-riscv-ide-2026.1\build_tools\bin;%PATH%
cd sw\top_demo
make
```

产物：`build\top_demo.elf` / `.hex` / `.bin`（RAM 占用约 24%）。

## Eclipse workspace 说明

- workspace 是 Efinity RISC-V IDE（Eclipse）的元数据容器（视图布局、索引、最近工程列表），**不包含工程内容**——工程本体跟着 `sw\top_demo` 目录走，workspace 选哪个目录都不影响构建。
- 本工程未指定专用 workspace。首次打开 IDE 时在 workspace 选择对话框任选一个目录即可（建议 `D:\Projs\ws-e1-sd-ddr-csi2\sw` 或任一空目录），然后 Import → General → Existing Projects into Workspace → 选 `sw\top_demo`，工程名显示为 `top_demo`。注意：**固件文件夹名 = Eclipse 工程名 = top_demo**（Efinity 惯例，文件夹名与 `.project` 中名字一致），不要把文件夹改回其它名字，否则 launch 按 `top_demo` 工程名解析会找不到 elf。
- IDE 的 workspace 历史记录存在安装目录：
  `D:\Efinity\efinity-riscv-ide-2026.1\Efinity-RISCV-IDE\configuration\.settings\org.eclipse.ui.ide.prefs`
  的 `RECENT_WORKSPACES` 项。换机器/分享给别人时该文件不会随工程走，属个人 IDE 状态，无需迁移。
- launch 配置（`top_demo_ti.launch`）已写入本工程绝对路径
  `D:\Projs\ws-e1-sd-ddr-csi2\sw\{top_demo,bsp}`；若工程拷到其它路径，需在
  Run → Debug Configurations 里同步修改（或直接删掉 launch 重新生成）。也正因如此，
  `sw\top_demo` 下的 `.project`/`.cproject`/`.launch` 才是随工程分享的有效文件，
  workspace 元数据不是。
- **报错 `Program file does not exist` / `build\top_demo.elf not found`**：launch 里的
  程序路径 `./build/top_demo.elf` 按工程名 `top_demo` 解析。工程名与固件文件夹名不一致
  时（例如曾用 Makefile Project with Existing Code 以文件夹名建过工程）会触发。本工程
  已把文件夹改名为 `sw\top_demo` 使两者强制一致；若 workspace 里有旧名工程，右键
  Delete（不勾 delete contents）后重导即可。
- OpenOCD 相关路径（launch 的 `gdbServerOther`/`targetRegFile`/`svdPath`）已指向新布局
  `sw\bsp\openocd\`，`bsp_loc` 指向 `sw\`（`debug_ti.cfg` 按 `$proj_loc/cpu0.yaml` 取
  CPU 配置）。若拷到其它路径同样需同步修改这三处。

## 烧写与运行

1. Programmer 烧 `outflow\ws-e1-sd-ddr-csi2.bit`（或 `.hex`）。
2. 固件两种加载方式：
   - Eclipse 导入 `sw\top_demo`，用 `top_demo_ti.launch` Run。
   - OpenOCD：`sw\bsp\openocd\` 下 `flash_ti.cfg` / `debug_ti.cfg` 等。
3. 插入 SD 卡，上电，串口 115200 观察输出（判读见 [test_guide.md](test_guide.md)）。
4. 屏幕应出现 8 个图案每 3 s 轮换循环。
