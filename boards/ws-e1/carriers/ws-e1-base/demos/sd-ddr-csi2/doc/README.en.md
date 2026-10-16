English | [中文](README.md)

# ws-e1-sd-ddr-csi2

An Efinity project based on the TJ180A484S device: an **SD card → DDR dual-port → MIPI CSI-2 TX** image-path demo.

- Top module: `top_demo` (project XML: `ws-e1-sd-ddr-csi2.xml`)
- Device: `TJ180A484S` (the device name is an attribute-bound constraint and must not be renamed; see the XML `efx:device` / peri.xml `device_def`)
- Video: 1280x720 YUV422 60 fps, 8 test patterns auto-rotating every 3 s in an endless loop
- Firmware: RISC-V (Sapphire SOC) bare-metal program; Eclipse project name `top_demo`

See the other documents in this directory for details:

| Document | Content |
|---|---|
| [architecture.md](architecture.md) | Module hierarchy, clock tree, data path, DDR arbitration |
| [register_map.md](register_map.md) | ddr_port1_reader / video_reader register tables |
| [test_guide.md](test_guide.md) | Test procedure, UART output interpretation, troubleshooting |

## Directory Structure

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

## Dependencies

| Item | Requirement |
|---|---|
| Efinity | Includes Interface Designer and Programmer (this project was verified with the 2026.1 release) |
| RISC-V toolchain | `efinity-riscv-ide-2026.1\toolchain\bin` (`riscv-none-elf-gcc`) + `build_tools\bin` (`make`) |
| SD card | Capacity ≥ 32 MB; the card tail needs roughly 17 MB of overwritable space (patterns + frame-retention test area) |
| Serial terminal | 115200 8N1 (on-board UART, GPIOR_72/70) |
| Display | MIPI CSI-2 receiver: DPI adapter board / panel / protocol analyzer (2-lane D-PHY) |

> SD card note: test data is written to the **end of the card** (MBR/FAT untouched). If the signature area at the card end reads `0x55AA` boot/file-system data, the firmware refuses to write in order to protect the original data.

## Build the FPGA

Option 1 (GUI): open `ws-e1-sd-ddr-csi2.xml` in Efinity and run the Compile Flow.
Option 2 (CLI):

```
awesom build_project --project D:\Projs\ws-e1-sd-ddr-csi2
```

Artifacts: `outflow\ws-e1-sd-ddr-csi2.bit` / `.hex` (about 3 minutes for the full flow).

Timing note: `timing.rpt` contains 10 small negative-slack paths (-0.3 ~ -0.4 ns), identical path-by-path to the original project baseline that passed board-level validation; this is a known acceptable state.

## Build the Firmware

```
set PATH=D:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin;D:\Efinity\efinity-riscv-ide-2026.1\build_tools\bin;%PATH%
cd sw\top_demo
make
```

Artifacts: `build\top_demo.elf` / `.hex` / `.bin` (RAM usage about 24%).

## Eclipse Workspace Notes

- The workspace is a metadata container of the Efinity RISC-V IDE (Eclipse) (view layout, index, recent-project list) and **does not contain the project content**—the project itself travels with the `sw\top_demo` directory; the build is unaffected by whichever directory is chosen as the workspace.
- This project does not specify a dedicated workspace. The first time you open the IDE, pick any directory in the workspace selection dialog (recommended: `D:\Projs\ws-e1-sd-ddr-csi2\sw` or any empty directory), then Import → General → Existing Projects into Workspace → select `sw\top_demo`; the project shows up as `top_demo`. Note: **firmware folder name = Eclipse project name = top_demo** (an Efinity convention: the folder name matches the name in `.project`). Do not rename the folder, otherwise a launch resolving by the `top_demo` project name will fail to find the elf.
- The IDE's workspace history is stored in the installation directory:
  `D:\Efinity\efinity-riscv-ide-2026.1\Efinity-RISCV-IDE\configuration\.settings\org.eclipse.ui.ide.prefs`
  under the `RECENT_WORKSPACES` entry. When switching machines or sharing with others, this file does not travel with the project; it is personal IDE state and needs no migration.
- The launch configuration (`top_demo_ti.launch`) has the absolute paths of this project baked in:
  `D:\Projs\ws-e1-sd-ddr-csi2\sw\{top_demo,bsp}`; if the project is copied elsewhere, update them under
  Run → Debug Configurations (or simply delete the launch and regenerate). For the same reason,
  the effective files to share with the project are `.project`/`.cproject`/`.launch` under `sw\top_demo`,
  not the workspace metadata.
- **Error `Program file does not exist` / `build\top_demo.elf not found`**: the program path `./build/top_demo.elf` in the launch is resolved by the project name `top_demo`. This triggers when the project name and the firmware folder name disagree
  (e.g., a project was previously created from the folder name via Makefile Project with Existing Code). This project
  has renamed the folder to `sw\top_demo` to force the two to match; if a stale-named project exists in the workspace, right-click
  Delete (without delete contents) and re-import.
- OpenOCD-related paths in the launch (`gdbServerOther`/`targetRegFile`/`svdPath`) already point to the new layout
  `sw\bsp\openocd\`, and `bsp_loc` points to `sw\` (`debug_ti.cfg` takes the
  CPU configuration from `$proj_loc/cpu0.yaml`). If the project is copied elsewhere, these three entries must be updated likewise.

## Programming and Running

1. Use the Programmer to flash `outflow\ws-e1-sd-ddr-csi2.bit` (or `.hex`).
2. Two ways to load the firmware:
   - Import `sw\top_demo` in Eclipse and Run with `top_demo_ti.launch`.
   - OpenOCD: `flash_ti.cfg` / `debug_ti.cfg` etc. under `sw\bsp\openocd\`.
3. Insert the SD card, power up, and watch the UART output at 115200 (interpretation: see [test_guide.md](test_guide.md)).
4. The screen should show the 8 patterns rotating every 3 s in a loop.
