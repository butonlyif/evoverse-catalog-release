[English](README.en.md) | 中文
# imu-bmi088-readout — BMI088 六轴 IMU 数据读取（RISC-V + I2C）

> 原目录：`imu_bmi088/imu_bmi088/`

## 1. 概述

Sapphire RISC-V 软核经 **I2C0 读取板载 Bosch BMI088 六轴 IMU**（加速度计 +
陀螺仪），换算为物理量后经 UART 周期打印。是"软核 + I2C 传感器"集成的最小
完整样例：FPGA 侧只需标准 SoC 顶层，业务逻辑全部在 C 代码中，客户换其它
I2C 传感器时改软件即可。

- 器件：Titanium **TJ180A484S**（C4）
- 工具链：Efinity 2025.2.288.4.15（pass，bitstream 已生成过）
- 顶层模块：`top_soc`（[top_soc.v](top_soc.v)）
- 核心软件：`embedded_sw/soc/software/standalone/i2c/i2cMasterDemo/src/main.c`

## 2. 硬件资源占用

| 资源 | 配置 |
| --- | --- |
| 软核 | Sapphire SoC（IP 实例名 `soc`）：UART0、SPI0、**I2C0**、GPIO0(4bit)、JTAG_USER1 调试 |
| `main_pll`（PLL_TL0） | 50MHz → io_systemClk 100MHz |
| `pll_inst2`（PLL_BL0） | 外部 Si5338 156.25MHz 参考（模板残留，非本 demo 必需） |
| **I2C0** | SCL=GPIOR_N_37 / SDA=GPIOR_P_37（1.8V bank） |
| GPIO | `clk_25m_gpio` @GPIOL_26（pll_clkin）、`si5338_pll_clk_156m25` clkout @GPIOL_33 |

无 DDR、无 MIPI。板级外设：**BMI088 IMU**、UART 串口。

## 3. 目录结构

```
imu-bmi088-readout/
├── soc.xml / soc.peri.xml          # Efinity 工程（打开这个）
├── constraints.sdc                 # 时序约束
├── top_soc.v                       # 顶层 top_soc
├── design_modules.v                # Sapphire 配套模块
├── soc_onchip.v / *_define.vh      # 旧版 SoC 包装（未被工程引用，遗留）
├── EfxSapphireSoc...ram_symbol*.bin  # SoC RAM 初始化镜像 ×4
├── ip/soc/                         # Sapphire SoC IP（含 netlist 网表）
└── embedded_sw/
    └── soc/                        # ★ 当前有效软件树（实例名 soc 对应）
        ├── bsp/efinix/EfxSapphireSoc/
        ├── software/standalone/i2c/i2cMasterDemo/src/main.c   # ★ BMI088 主程序
        └── cpu0.yaml               # RISC-V 软件构建配置
```

> 本次整理已删除 `embedded_sw/sapphire/`（旧实例名的完整重复软件树），
> 有效的软件树是 `embedded_sw/soc/`。

## 4. 工作原理（软件 main.c，中文注释）

1. I2C 100kHz 初始化；分别读加速度计（0x18）/陀螺仪（0x68）CHIP_ID 校验
   （ACC=0x1E、GYRO=0x0F，不符打印"传感器异常"并死循环）；
2. 配置加速度计 ±2g / 25Hz、陀螺仪 ±250°/s / 25Hz；
3. 死循环每 200ms 读 6 轴原始值并换算为 **mg / mdps**，UART 打印
   `ACC: X=.. Y=.. Z=.. mg | GYRO: ...`。

## 5. 运行与验证

1. Efinity 打开 `soc.xml` 编译烧录 bitstream；
2. 经 JTAG/OpenOCD 下载运行 `i2cMasterDemo`；
3. UART 终端看到 CHIP_ID 校验通过 + 周期性六轴数据；
4. 晃动板卡数值应相应变化；静止水平放置时 ACC Z 轴约 +1000mg。

## 6. 集成到客户系统的要点

- BMI088 是**双芯片**（ACC 0x18 + GYRO 0x68 两个 I2C 地址），上电时序要求
  先 ACC 后 GYRO，main.c 已按手册顺序处理，换传感器时注意保留时序框架；
- I2C 引脚在 `soc.peri.xml` 的 I2C0 配置中修改 bank/管脚即可，RTL 不用动；
- 若客户系统不需要 Si5338 相关 PLL/GPIO（模板残留），可在 peri 中删除
  `pll_inst2` 与 clkout GPIO，不影响 IMU 功能；
- `soc.xml` synthesis include 中的 `ip/soc_ti180` 路径已失效（目录不存在，
  Windows 下无害），如迁移到 Linux 构建需删除该 include。

## 7. 已知问题与注意事项

- `soc_onchip.v`/`soc_onchip_define.vh` 未列入工程，属旧版遗留，可忽略；
- 根目录 4 个 `EfxSapphireSoc...bin` 与 `ip/soc/`、`ip/soc/source/hardware/netlist/`
  下存在多处重复（IP 生成机制所致），以 `ip/soc/source/hardware/netlist/` 为准。
