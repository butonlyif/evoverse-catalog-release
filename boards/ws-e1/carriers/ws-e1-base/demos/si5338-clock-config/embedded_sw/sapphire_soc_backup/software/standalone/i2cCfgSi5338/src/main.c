
#include <stdint.h>
#include "bsp.h"
#include "i2c.h"
#include "i2cDemo.h" 
#include "Si5338-RevB-Registers.h"

#define I2C_MASTER_ADDR 0x70    // Slave device address
#define I2C_FREQUENCY   100000  // Set your I2C Frequency here

void init(){
    //I2C init
    I2c_Config i2c;
    i2c.samplingClockDivider    = 3;                            
    i2c.timeout                 = I2C_CTRL_HZ/10;               // timeout = 0.1s
    i2c.tsuDat                  = I2C_CTRL_HZ/I2C_FREQUENCY/3;  // tsuDat = 3.33us
    i2c.tLow                    = I2C_CTRL_HZ/I2C_FREQUENCY/2;  // tLow   = 5us
    i2c.tHigh                   = I2C_CTRL_HZ/I2C_FREQUENCY/2;  // tHigh  = 5us
    i2c.tBuf                    = I2C_CTRL_HZ/I2C_FREQUENCY;    // tBuf   = 10us

    i2c_applyConfig(I2C_CTRL, &i2c);                            // Apply the configs from i2c structure into the I2C controller.
}

void main() {
    bsp_init();
    init(); // Initiatize

    bsp_printf("I2C Cfg Si5338 Begin. \r\n");

    u8 slaveAddr = (I2C_MASTER_ADDR << 1) & 0xFF; // The slave address is shifted left by 1 bit to allocate the bit for rw bit
    while(1){ // Forever loop
        u8 reg_addr;
        u8 reg_data;

        //Write register map;
        for (int i = 0; i < NUM_REGS_MAX; i++){
    	    u8 clear_new_val;
    	    u8 curr_val;
    	    u8 clear_curr_val;
    	    u8 combined;

    	    if(Reg_Store[i].Reg_Mask != 0x00){
    	    	if(Reg_Store[i].Reg_Mask == 0xff){
    	    		i2c_writeData_b(I2C_CTRL, slaveAddr,Reg_Store[i].Reg_Addr, &Reg_Store[i].Reg_Val ,0x01);
    	    		bsp_printf("writeData%d: %x \r\n" ,Reg_Store[i].Reg_Addr,Reg_Store[i].Reg_Val);
    	    	}
    	    	else {
    	    		i2c_readData_b(I2C_CTRL, slaveAddr, Reg_Store[i].Reg_Addr,&curr_val , 0x01);
    	    		bsp_printf("readData%d,:%x \r\n", Reg_Store[i].Reg_Addr,curr_val);
    	    		clear_curr_val = curr_val & (~Reg_Store[i].Reg_Mask);

    	    		clear_new_val =Reg_Store[i].Reg_Val & Reg_Store[i].Reg_Mask;

    	    		combined = clear_curr_val | clear_new_val;
    	    		i2c_writeData_b(I2C_CTRL, slaveAddr,Reg_Store[i].Reg_Addr, &combined ,0x01);
    	    		bsp_printf("writeData%d: %x \r\n",Reg_Store[i].Reg_Addr,combined);
    	    	}
    	    }
        	i2c_readData_b(I2C_CTRL, slaveAddr, Reg_Store[i].Reg_Addr,&curr_val , 0x01);
        	bsp_printf("readData%d,:%x \r\n\n", Reg_Store[i].Reg_Addr,curr_val);
        }

        //Soft reset
        bsp_printf("Soft reset.\r\n");
        reg_addr = 246;
        reg_data = 0x02;
        i2c_writeData_b(I2C_CTRL, slaveAddr,reg_addr, &reg_data ,0x01);

        bsp_printf("I2C Cfg Si5338 Done. \r\n");

        while(1){};
    }
}






