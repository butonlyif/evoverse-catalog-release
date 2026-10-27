///////////////////////////////////////////////////////////////////////////////////
//  Copyright (c) 2025 SaxonSoc contributors
//  SPDX license identifier: MIT
//////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>
#include "bsp.h"
#include "i2c.h"
#include "userDef.h" 

// ===================== BMI088 完整地址 =====================
#define BMI088_ACCEL_ADDR    0x18    // 加速度计
#define BMI088_GYRO_ADDR     0x68    // 陀螺仪

// 加速度寄存器
#define ACC_CHIP_ID          0x00
#define ACC_X_LSB            0x12
#define ACC_X_MSB            0x13
#define ACC_Y_LSB            0x14
#define ACC_Y_MSB            0x15
#define ACC_Z_LSB            0x16
#define ACC_Z_MSB            0x17
#define ACC_PWR_CTRL         0x7D
#define ACC_RANGE            0x41
#define ACC_BW               0x40

// 陀螺仪寄存器
#define GYRO_CHIP_ID         0x00
#define GYRO_X_LSB           0x02
#define GYRO_X_MSB           0x03
#define GYRO_Y_LSB           0x04
#define GYRO_Y_MSB           0x05
#define GYRO_Z_LSB           0x06
#define GYRO_Z_MSB           0x07
#define GYRO_RANGE           0x0F
#define GYRO_BW              0x10
#define GYRO_LPM1            0x11

#define I2C_FREQ             100000
// ===========================================================

#ifdef SYSTEM_I2C_0_IO_CTRL

void i2c_init(void){
    I2c_Config i2c;
    i2c.samplingClockDivider    = 3;
    i2c.timeout                 = I2C_CTRL_HZ / 10;
    i2c.tsuDat                  = I2C_CTRL_HZ / I2C_FREQ / 3;
    i2c.tLow                    = I2C_CTRL_HZ / I2C_FREQ / 2;
    i2c.tHigh                   = I2C_CTRL_HZ / I2C_FREQ / 2;
    i2c.tBuf                    = I2C_CTRL_HZ / I2C_FREQ;
    i2c_applyConfig(I2C_CTRL, &i2c);
}

// 通用读函数
uint8_t bmi_read(uint8_t slave_addr, uint8_t reg){
    uint8_t data;
    uint8_t addr_8bit = slave_addr << 1;
    i2c_readData_b(I2C_CTRL, addr_8bit, reg, &data, 1);
    return data;
}

// 通用写函数
void bmi_write(uint8_t slave_addr, uint8_t reg, uint8_t val){
    uint8_t addr_8bit = slave_addr << 1;
    i2c_writeData_b(I2C_CTRL, addr_8bit, reg, &val, 1);
}

void delay_ms(uint32_t ms){
    volatile uint32_t i,j;
    for(i=0; i<ms; i++)
        for(j=0; j<10000; j++);
}

// ===================== 加速度初始化 =====================
void accel_init(void){
    delay_ms(50);
    bmi_write(BMI088_ACCEL_ADDR, ACC_PWR_CTRL, 0x04);
    delay_ms(50);
    bmi_write(BMI088_ACCEL_ADDR, ACC_RANGE, 0x01);   // ±2g
    delay_ms(10);
    bmi_write(BMI088_ACCEL_ADDR, ACC_BW, 0x08);      // 25Hz
    delay_ms(50);
}

// ===================== 陀螺仪初始化 =====================
void gyro_init(void){
    delay_ms(50);
    bmi_write(BMI088_GYRO_ADDR, GYRO_RANGE, 0x00);   // ±250°/s
    delay_ms(10);
    bmi_write(BMI088_GYRO_ADDR, GYRO_BW, 0x07);     // 25Hz
    delay_ms(10);
    bmi_write(BMI088_GYRO_ADDR, GYRO_LPM1, 0x00);   // 正常模式
    delay_ms(50);
}

// ===================== 单位换算 =====================
// 加速度：mg
int32_t acc_raw_to_mg(int16_t raw){
    return (raw * 6000) / 32768;
}

// 陀螺仪：mdps (0.001 °/s)
int32_t gyro_raw_to_mdps(int16_t raw){
    return (raw * 250000) / 32768;
}

// ===================== 主函数 =====================
void main(void)
{
    bsp_init();
    i2c_init();
    delay_ms(100);

    bsp_printf("======= BMI088 ACC + GYRO =======\r\n");

    // 只打印一次 ID
    uint8_t acc_id = bmi_read(BMI088_ACCEL_ADDR, ACC_CHIP_ID);
    uint8_t gyro_id = bmi_read(BMI088_GYRO_ADDR, GYRO_CHIP_ID);
    bsp_printf("ACC ID: 0x%02X   GYRO ID: 0x%02X\r\n", acc_id, gyro_id);

    if(acc_id == 0x1E && gyro_id == 0x0F){
        bsp_printf("BMI088_sucess\r\n");
        accel_init();
        gyro_init();
        bsp_printf("start_data_trace\r\n");
    }else{
        bsp_printf("❌ 传感器异常\r\n");
        while(1);
    }

    while(1){
        // ========== 读取加速度 ==========
        int16_t ax = (bmi_read(BMI088_ACCEL_ADDR, ACC_X_MSB) << 8) | bmi_read(BMI088_ACCEL_ADDR, ACC_X_LSB);
        int16_t ay = (bmi_read(BMI088_ACCEL_ADDR, ACC_Y_MSB) << 8) | bmi_read(BMI088_ACCEL_ADDR, ACC_Y_LSB);
        int16_t az = (bmi_read(BMI088_ACCEL_ADDR, ACC_Z_MSB) << 8) | bmi_read(BMI088_ACCEL_ADDR, ACC_Z_LSB);

        int32_t ax_mg = acc_raw_to_mg(ax);
        int32_t ay_mg = acc_raw_to_mg(ay);
        int32_t az_mg = acc_raw_to_mg(az);

        // ========== 读取陀螺仪 ==========
        int16_t gx = (bmi_read(BMI088_GYRO_ADDR, GYRO_X_MSB) << 8) | bmi_read(BMI088_GYRO_ADDR, GYRO_X_LSB);
        int16_t gy = (bmi_read(BMI088_GYRO_ADDR, GYRO_Y_MSB) << 8) | bmi_read(BMI088_GYRO_ADDR, GYRO_Y_LSB);
        int16_t gz = (bmi_read(BMI088_GYRO_ADDR, GYRO_Z_MSB) << 8) | bmi_read(BMI088_GYRO_ADDR, GYRO_Z_LSB);

        int32_t gx_mdps = gyro_raw_to_mdps(gx);
        int32_t gy_mdps = gyro_raw_to_mdps(gy);
        int32_t gz_mdps = gyro_raw_to_mdps(gz);

        // ========== 打印 ==========
        bsp_printf("ACC: X=%4d Y=%4d Z=%4d mg | GYRO: X=%6d Y=%6d Z=%6d mdps\r\n",
                   ax_mg, ay_mg, az_mg,
                   gx_mdps, gy_mdps, gz_mdps);

        delay_ms(200);
    }
}

#else
void main(void){
    bsp_init();
    bsp_printf("I2C DISABLE\r\n");
}
#endif
