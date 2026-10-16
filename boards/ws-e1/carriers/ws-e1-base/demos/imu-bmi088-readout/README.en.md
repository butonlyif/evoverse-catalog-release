English | [中文](README.md)
# imu-bmi088-readout — BMI088 6-Axis IMU Data Readout (RISC-V + I2C)

> Original directory: `imu_bmi088/imu_bmi088/`

## 1. Overview

A Sapphire RISC-V soft core reads the onboard Bosch BMI088 6-axis IMU (accelerometer +
gyroscope) via **I2C0**, converts the readings into physical quantities, and prints them
periodically over UART. It is the minimal complete example of "soft core + I2C sensor"
integration: the FPGA side only needs a standard SoC top level, all business logic lives in
the C code, and switching to another I2C sensor only requires changing the software.

- Device: Titanium **TJ180A484S** (C4)
- Toolchain: Efinity 2025.2.288.4.15 (pass, bitstream generated)
- Top module: `top_soc` ([top_soc.v](top_soc.v))
- Core software: `embedded_sw/soc/software/standalone/i2c/i2cMasterDemo/src/main.c`

## 2. Hardware Resource Usage

| Resource | Configuration |
| --- | --- |
| Soft core | Sapphire SoC (IP instance name `soc`): UART0, SPI0, **I2C0**, GPIO0(4bit), JTAG_USER1 debug |
| `main_pll` (PLL_TL0) | 50MHz → io_systemClk 100MHz |
| `pll_inst2` (PLL_BL0) | External Si5338 156.25MHz reference (template leftover, not required by this demo) |
| **I2C0** | SCL=GPIOR_N_37 / SDA=GPIOR_P_37 (1.8V bank) |
| GPIO | `clk_25m_gpio` @GPIOL_26 (pll_clkin), `si5338_pll_clk_156m25` clkout @GPIOL_33 |

No DDR, no MIPI. Board-level peripherals: **BMI088 IMU**, UART serial port.

## 3. Directory Structure

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

> This reorganization removed `embedded_sw/sapphire/` (a complete duplicate software tree
> under the old instance name); the valid software tree is `embedded_sw/soc/`.

## 4. Working Principle (software main.c, Chinese comments)

1. Initialize I2C at 100kHz; read the accelerometer (0x18) / gyroscope (0x68) CHIP_ID for
   verification (ACC=0x1E, GYRO=0x0F; on mismatch print "sensor error" and loop forever);
2. Configure the accelerometer to ±2g / 25Hz and the gyroscope to ±250°/s / 25Hz;
3. In an endless loop, read the 6-axis raw values every 200ms, convert them into
   **mg / mdps**, and print `ACC: X=.. Y=.. Z=.. mg | GYRO: ...` over UART.

## 5. Run and Verify

1. Open `soc.xml` in Efinity, build, and program the bitstream;
2. Download and run `i2cMasterDemo` via JTAG/OpenOCD;
3. On the UART terminal, observe CHIP_ID verification passing plus periodic 6-axis data;
4. Shaking the board should change the values accordingly; at rest, level, ACC Z reads about
   +1000mg.

## 6. Integration Notes for Customer Systems

- The BMI088 is a **dual-die** device (two I2C addresses: ACC 0x18 + GYRO 0x68) and its
  power sequencing requires ACC before GYRO; main.c already follows the manual's order.
  When replacing the sensor, keep this sequencing framework;
- The I2C pins are changed in the I2C0 configuration of `soc.peri.xml` (bank/pins); the RTL
  does not need to be touched;
- If the customer system does not need the Si5338-related PLL/GPIO (template leftover),
  delete `pll_inst2` and the clkout GPIO from the peri; the IMU function is unaffected;
- The `ip/soc_ti180` path in the `soc.xml` synthesis include list is stale (the directory
  does not exist; harmless on Windows). When migrating to Linux builds, remove that include.

## 7. Known Issues and Notes

- `soc_onchip.v`/`soc_onchip_define.vh` are not listed in the project; they are old-version
  leftovers and can be ignored;
- The 4 `EfxSapphireSoc...bin` files in the root directory duplicate files under `ip/soc/`
  and `ip/soc/source/hardware/netlist/` (a consequence of the IP generation mechanism);
  treat `ip/soc/source/hardware/netlist/` as authoritative.
