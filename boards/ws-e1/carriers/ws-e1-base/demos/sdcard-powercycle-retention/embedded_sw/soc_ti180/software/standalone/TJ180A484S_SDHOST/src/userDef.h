#ifndef USERDEF_H_
#define USERDEF_H_

#include "soc.h"

/************************** Hardware Header File ***************************/
#define UART_0				SYSTEM_UART_0_IO_CTRL
#define APB_0				IO_APB_SLAVE_0_INPUT
#define APB_1				IO_APB_SLAVE_1_INPUT
#define DDR_SADDR 			0x01300000
#define DDR_EADDR  			0xf7ffffff
#define PROBE_ADDR 			IO_APB_SLAVE_2_INPUT
#define SDHC_INTERRUPT      SYSTEM_PLIC_USER_INTERRUPT_B_INTERRUPT

/************************** Main Header File ***************************/
#define DEBUG_PRINTF_EN   	0

/************************** SDHC Header File ***************************/
#define MAX_CLK_FREQ  		50000			//KHz
#define SD_CLK_FREQ   		MAX_CLK_FREQ	//KHz
#define SDHC_ADDR     		0x100
#define BLOCK_SIZE    		0x200
#define MAX_BLK_BUF   		0x1
#define DATA_WIDTH    		0x2 			//0x0:1-bit mode; 0x2:4-bit mode;

/* Retention test data pattern (first 4 bytes of each block, for quick UART check) */
#define PATTERN_HEAD_0		0xA9
#define PATTERN_HEAD_1		0xA3
#define PATTERN_HEAD_2		0xA6
#define PATTERN_HEAD_3		0xA5
#define PATTERN_XOR		0xA9

/* Power-cycle retention test region (LBA block index, not byte address) */
#define RETENTION_START_LBA		0x1000
#define RETENTION_BLOCK_COUNT		128

/************************** INTC Header File *****************************/
#define INT_ENABLE  				0xffffffcf
#define INT_COMMAND_COMPLETE      	0x1
#define INT_TRANSFER_COMPLETE     	0x2
#define INT_BLOCK_GAP_EVENT       	0x4
#define INT_BUFFER_WRITE_READY    	0x10
#define INT_BUFFER_READ_READY     	0x20
#define INT_CARD_INSERTION        	0x40
#define INT_CARD_REMOVAL          	0x80
#define INT_COMMAND_TIMEOUT_ERROR 	0x10000
#define INT_COMMAND_CRC_ERROR     	0x20000
#define INT_COMMAND_END_BIT_ERROR 	0x40000
#define INT_COMMAND_INDEX_ERROR   	0x80000
#define INT_DATA_CRC_ERROR        	0x200000


#endif
