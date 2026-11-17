///////////////////////////////////////////////////////////////////////////////////
//  Copyright (c) 2025 SaxonSoc contributors
//  SPDX license identifier: MIT
//////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>
#include "bsp.h"
#include "i2c.h"
#include "userDef.h" 

// ===================== 【完全按照你手册】BMI088 寄存器 =====================
#define BMI088_ACCEL_I2C_ADDR    0x18    // 加速度计地址
#define BMI088_ACCEL_CHIP_ID     0x00    // ID 寄存器
#define BMI088_ACCEL_X_LSB       0x12    // 手册数据寄存器
#define BMI088_ACCEL_X_MSB       0x13
#define BMI088_ACCEL_Y_LSB       0x14
#define BMI088_ACCEL_Y_MSB       0x15
#define BMI088_ACCEL_Z_LSB       0x16
#define BMI088_ACCEL_Z_MSB       0x17

#define BMI088_ACCEL_PWR_CTRL    0x7D    // 唤醒寄存器
#define BMI088_ACCEL_RANGE       0x41
#define BMI088_ACCEL_BW          0x40

#define I2C_FREQUENCY            100000
// ==========================================================================

#ifdef SYSTEM_I2C_0_IO_CTRL

// I2C初始化
void i2c_init(void){
    I2c_Config i2c;
    i2c.samplingClockDivider    = 3;
    i2c.timeout                 = I2C_CTRL_HZ / 10;
    i2c.tsuDat                  = I2C_CTRL_HZ / I2C_FREQUENCY / 3;
    i2c.tLow                    = I2C_CTRL_HZ / I2C_FREQUENCY / 2;
    i2c.tHigh                   = I2C_CTRL_HZ / I2C_FREQUENCY / 2;
    i2c.tBuf                    = I2C_CTRL_HZ / I2C_FREQUENCY;
    i2c_applyConfig(I2C_CTRL, &i2c);
}

// 读一个寄存器
uint8_t bmi_read(uint8_t reg){
    uint8_t data;
    uint8_t addr_8bit = BMI088_ACCEL_I2C_ADDR << 1;
    i2c_readData_b(I2C_CTRL, addr_8bit, reg, &data, 1);
    return data;
}

// 写一个寄存器
void bmi_write(uint8_t reg, uint8_t val){
    uint8_t addr_8bit = BMI088_ACCEL_I2C_ADDR << 1;
    i2c_writeData_b(I2C_CTRL, addr_8bit, reg, &val, 1);
}

// 简单延时
void delay_ms(uint32_t ms){
    volatile uint32_t i,j;
    for(i=0; i<ms; i++)
        for(j=0; j<10000; j++);
}

// ===================== BMI088 唤醒初始化（必须执行） =====================
void bmi088_init(void){
    delay_ms(50);
    bmi_write(BMI088_ACCEL_PWR_CTRL, 0x04);  // 退出睡眠
    delay_ms(50);
    bmi_write(BMI088_ACCEL_RANGE, 0x01);    // ±2g
    delay_ms(10);
    bmi_write(BMI088_ACCEL_BW,    0x08);    // 25Hz
    delay_ms(50);
}

// ===================== 主函数 =====================
void main(void)
{
    bsp_init();
    i2c_init();
    delay_ms(100);

    // ========== 只打印一次 ID ==========
    uint8_t id = bmi_read(BMI088_ACCEL_CHIP_ID);
    bsp_printf("=== BMI088 ===\r\n");
    bsp_printf("CHIP_ID = 0x%02X\r\n", id);

    if(id == 0x1E){
        bsp_printf("✅ Sensor OK\r\n");
        bmi088_init();
        bsp_printf("✅ Start read data...\r\n\r\n");
    }else{
        bsp_printf("❌ Error\r\n");
        while(1);
    }

    // ========== 循环打印数据 ==========
    while(1){
        int16_t ax = (bmi_read(BMI088_ACCEL_X_MSB) << 8) | bmi_read(BMI088_ACCEL_X_LSB);
        int16_t ay = (bmi_read(BMI088_ACCEL_Y_MSB) << 8) | bmi_read(BMI088_ACCEL_Y_LSB);
        int16_t az = (bmi_read(BMI088_ACCEL_Z_MSB) << 8) | bmi_read(BMI088_ACCEL_Z_LSB);

        // 一直打印，不停
        bsp_printf("X: %6d  Y: %6d  Z: %6d\r\n", ax, ay, az);
        delay_ms(200);
    }
}

#else
void main(void){
    bsp_init();
    bsp_printf("I2C DISABLE\r\n");
}
#endif
