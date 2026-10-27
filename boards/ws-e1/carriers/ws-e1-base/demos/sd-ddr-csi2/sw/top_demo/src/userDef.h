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
#define SD_CLK_FREQ   		MAX_CLK_FREQ	//KHz -> 100MHz/2 = 50MHz SD bus clock
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

/* YUV422 (YUYV packed) 720p frame for the DDR Port0/Port1 path test */
#define FRAME_WIDTH			1280
#define FRAME_HEIGHT			720
#define FRAME_BPP			2				/* bytes per pixel */
#define FRAME_SIZE			(FRAME_WIDTH * FRAME_HEIGHT * FRAME_BPP)	/* 1843200 */
#define FRAME_BLK_CNT			(FRAME_SIZE / BLOCK_SIZE)			/* 3600 */
/* Test region is parked at the END of the card (runtime placement:
 *   frame_lba = total_blocks - FRAME_END_MARGIN - FRAME_BLK_CNT,
 *   signature block = frame_lba - 1).
 * This keeps LBA 0 (MBR), LBA 1..N (FS boot/FAT/dir metadata) untouched;
 * margin stays clear of the very last blocks. */
#define FRAME_END_MARGIN		0x100
#define FRAME_SIGN_MAGIC		0x32565559u	/* "YUV2" (v2: per-pixel cursor) */
#define DDR_FRAME_ADDR			0x01000000

/* ddr_port1_reader registers (mapped on APB slave 0) */
#define P1R_BASE			APB_0
#define P1R_REG_ID			0x00
#define P1R_REG_CTRL			0x04	/* [0] START, [1] CLR_DONE, [2] ABORT */
#define P1R_REG_STATUS			0x08	/* [0] BUSY, [1] DONE, [2] SLVERR,
						 * [3] RVALID seen (sticky),
						 * [4] RLAST seen (sticky) */
#define P1R_REG_ADDR			0x0C
#define P1R_REG_LEN			0x10
#define P1R_REG_BEATS			0x14
#define P1R_REG_SUM_LO			0x18
#define P1R_REG_SUM_HI			0x1C
#define P1R_REG_FIRST_W0		0x20
#define P1R_REG_LAST_W0			0x24
#define P1R_REG_RLAST_BURST		0x28	/* beats returned by the macro in the
                         * last burst (latched at RLAST) */
#define P1R_REG_RID_FIRST		0x2C	/* RID of the first R beat (we send
                         * ARID=0; anything else = ghost resp.) */
#define P1R_REG_RID_LAST		0x30	/* RID of the last R beat */
#define P1R_REG_AR_DELAY		0x34	/* cycles in AR before ARREADY
                         * (0xFF = never accepted) */
#define P1R_REG_IDLE_RV			0x38	/* RVALID rising edges while idle
                         * after DONE (>0 = macro spews
                         * responses on its own) */

/* Phase C: 8-pattern MIPI CSI-2 TX video path.
 * Patterns match the reference pattern_gen.v: colour bars, crosshair over
 * gradient, H gradient, V gradient, red, green, blue, 32x32 checkerboard.
 * 3 s per pattern = 180 frames @ 60 fps.
 * Region sits at the end of the card BELOW the A/B frame zone:
 *   pat_lba  = frame_sign_lba - PAT8_END_MARGIN - PAT8_BLK_CNT
 *   sign_lba = pat_lba - 1
 * Slot layout note: CSI-2 TX pack-64 stores each pixel as 16-bit slot
 * {Y[15:8], C[7:0]}; in little-endian DDR a pixel pair is bytes C Y C Y
 * (U Y V Y) -- NOT standard YUYV (Y U Y V). */
#define PAT8_COUNT			8
#define PAT8_BLK_CNT			(FRAME_BLK_CNT * PAT8_COUNT)	/* 28800 */
#define PAT8_END_MARGIN			0x100
#define PAT8_SIGN_MAGIC			0x3856555Au	/* "YUV8" v2: burst-fixed RTL + per-slot staging */
#define PAT8_SWITCH_FRAMES		180
#define DDR_PAT_ADDR			0x02000000	/* 8 x 1.8 MB, above FW image */

/* video_reader registers (mapped on APB slave 1) */
#define VR_BASE				APB_1
#define VR_REG_ID			0x00
#define VR_REG_CTRL			0x04	/* [0] RUN, [3] OWN_P1 */
#define VR_REG_STATUS			0x08	/* [0] BUSY, [1] SLVERR */
#define VR_REG_ADDR			0x0C
#define VR_REG_FBYTES			0x10
#define VR_REG_NFRAME			0x14
#define VR_REG_NSWITCH			0x18
#define VR_REG_PAT_IDX			0x1C	/* RO */
#define VR_REG_FCNT			0x20	/* RO */

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
