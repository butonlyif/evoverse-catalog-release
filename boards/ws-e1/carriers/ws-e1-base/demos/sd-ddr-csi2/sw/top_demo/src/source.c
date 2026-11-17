/*
 * source.c
 *
 *  Created on: 17 Mar 2021
 *      Author: user
 */
#include "uart.h"
#include "bsp.h"
#include "efx_mmc_driver.h"
#include "mmc.h"
#include "userDef.h"


#define Reg_Out32(a,b) write_u32(b,a);

static const int fbase[] = {
	10000,
	100000,
	1000000,
	10000000,
};

static const int multipliers[] = {
	0,	/* reserved */
	10,
	12,
	13,
	15,
	20,
	25,
	30,
	35,
	40,
	45,
	50,
	55,
	60,
	70,
	80,
};

void sd_send_cmd(struct mmc *mmc, struct mmc_cmd *cmd, u32 index, u32 resp_type, u32 cmdarg)
{
	struct mmc_ops *ops = mmc->cfg->ops;
	struct mmc_data *data = NULL;

	cmd->cmdidx = index;
	cmd->resp_type = resp_type;
	cmd->cmdarg =cmdarg;

	ops->send_cmd(mmc,cmd,data);
}


void SD_READ_CSD(struct mmc *mmc, struct mmc_cmd *cmd)
{
	sd_send_cmd(mmc,cmd,MMC_CMD_SEND_CSD,MMC_RSP_R2,(mmc->rca<<16));
	mmc->csd[0]= cmd->response[0];
	mmc->csd[1]= cmd->response[1];
	mmc->csd[2]= cmd->response[2];
	mmc->csd[3]= cmd->response[3];

	mmc->capacity = (((mmc->csd[1]>>8) &0x3FFFFF)+1)*512;
	mmc->capacity *=1024;
	mmc->tran_speed = multipliers[(mmc->csd[2]>>27) &0x07] * fbase[(mmc->csd[2]>>24) &0x03];

	if(DEBUG_PRINTF_EN == 1)
	{
		bsp_printf("CSD 0x%x 0x%x 0x%x 0x%x\r\n",mmc->csd[0],mmc->csd[1],mmc->csd[2],mmc->csd[3]);
		bsp_printf("FILE_FORMAT = %d\r\n",(mmc->csd[0]>>2) &0x03);		//[11:10]
		bsp_printf("TMP_WRITE_PROTECT = %d\r\n",(mmc->csd[0]>>4) &0x01);//[12]
		bsp_printf("PERM_WRITE_PROTECT = %d\r\n",(mmc->csd[0]>>5) &0x01);//[13]
		bsp_printf("COPY = %d\r\n",(mmc->csd[0]>>6) &0x01);			//[14]
		bsp_printf("FILE_FORMAT_GRP = %d\r\n",(mmc->csd[0]>>7) &0x01);//[15]
		//[20:16]
		bsp_printf("WRITE_BL_PARTIAL = %d\r\n",(mmc->csd[0]>>13) &0x01);//[21]
		bsp_printf("WRITE_BL_LEN = %d\r\n",(mmc->csd[0]>>14) &0x0F);//[25:22]
		bsp_printf("R2W_FACTOR = %d\r\n",(mmc->csd[0]>>18) &0x07);//[28:26]
		//[30:29]
		bsp_printf("WP_GRP_ENABLE = %d\r\n",(mmc->csd[0]>>23) &0x01);//[31]

		bsp_printf("WP_GRP_SIZE = %d\r\n",(mmc->csd[0]>>24) &0x7F);//[38:32]

		bsp_printf("SECTOR_SIZE = %d\r\n",((mmc->csd[1] & 0x3F)<<1)|((mmc->csd[0])>>31 &0x1));//[45:39]
		bsp_printf("ERASE_BLK_EN = %d\r\n",(mmc->csd[1]>>6) &0x01);//[46]
		//[47]
		bsp_printf("C_SIZE = %d\r\n",(mmc->csd[1]>>8) &0x3FFFFF);//[69:48]
		//[75:70]
		bsp_printf("DSR_IMP = %d\r\n",(mmc->csd[2]>>4) &0x01);//[76]
		bsp_printf("READ_BLK_MISAIGN = %d\r\n",(mmc->csd[2]>>5) &0x01);//[77]
		bsp_printf("WRITE_BLK_MISAIGN = %d\r\n",(mmc->csd[2]>>6) &0x01);//[78]
		bsp_printf("READ_BL_PARTIAL = %d\r\n",(mmc->csd[2]>>7) &0x01);//[79]
		bsp_printf("READ_BL_LEN = %d\r\n",(mmc->csd[2]>>8) &0x0F);//[83:80]
		bsp_printf("CCC = %d\r\n",(mmc->csd[2]>>12) &0x0FFF);//[95:84]
		bsp_printf("TRAN_SPEED = 0x%x\r\n",(mmc->csd[2]>>24) &0x0FF);//[103:96]
		bsp_printf("NSAC = 0x%x\r\n",(mmc->csd[3]) &0x0FF);//[111:104]
		bsp_printf("TAAC = 0x%x\r\n",(mmc->csd[3]>>8) &0x0FF);//[119:112]
		//[125:120]
		bsp_printf("TAAC = 0x%x\r\n",(mmc->csd[3]>>22) &0x03);//[127:126]
		bsp_printf("mmc->capacity = %d\r\n",(((mmc->csd[1]>>8) &0x3FFFFF)+1)*512);
		bsp_printf("mmc->tran_speed = %d\r\n",mmc->tran_speed);
	}


}

/************************** Function File ***************************/
void SD_CardInitial(struct mmc *mmc, struct mmc_cmd *cmd)
{
	u32 Value;
	char busy=0;
	u32 rca=0;
	int wait_busy_count;

    for(int i=0; i<1; i++) {

        Reg_Out32(APB_1 + 0x08,0x00);
        sd_send_cmd(mmc,cmd,MMC_CMD_GO_IDLE_STATE,MMC_RSP_NONE,0);
        bsp_uDelay(1000);

        Reg_Out32(APB_1 + 0x08,0x01);
        sd_send_cmd(mmc,cmd,MMC_CMD_SEND_EXT_CSD,MMC_RSP_R7,0x01AA);

        Reg_Out32(APB_1 + 0x08,0x02);
        sd_send_cmd(mmc,cmd,MMC_CMD_APP_CMD,MMC_RSP_R1,0);

		wait_busy_count = 0;
        while (busy==0)
        {
                Value = 0;
                Value |= 0x1<<30;//HCS
                Value |= 0x0<<28;//XPC
                Value |= 0x0<<24;//S18R
                Value |= 0x100000;//VDD VOLTAGE
                bsp_uDelay(50000);//delay 50ms
                Reg_Out32(APB_1 + 0x08,0x04);
                sd_send_cmd(mmc,cmd,MMC_CMD_APP_CMD,MMC_RSP_R1,0);
                Reg_Out32(APB_1 + 0x08,0x05);
                sd_send_cmd(mmc,cmd,SD_CMD_APP_SEND_OP_COND,MMC_RSP_R3,Value);
                bsp_printf("Respose: 0x%x\r\n",cmd->response[0]);
                busy = (cmd->response[0]>>31)&0x1;
                bsp_uDelay(1000000);//delay 50ms
				
			wait_busy_count++;
			if (wait_busy_count >=10)
			{
				break;
			}
        }

        if(busy == 1) {
            break;
        }
        bsp_uDelay(1000000);
    }

	if (busy != 1) {
		bsp_printf("Err: SD card not ready (ACMD41 OCR busy timeout)\r\n");
		while (1) {}
	}

	sd_send_cmd(mmc,cmd,MMC_CMD_ALL_SEND_CID,MMC_RSP_R2,0);
	mmc->cid[0]=cmd->response[0];
	mmc->cid[1]=cmd->response[1];
	mmc->cid[2]=cmd->response[2];
	mmc->cid[3]=cmd->response[3];

	sd_send_cmd(mmc,cmd,MMC_CMD_SET_RELATIVE_ADDR,MMC_RSP_R6,0);

	mmc->rca = (cmd->response[0]&0xffff0000)>>16;
	SD_READ_CSD(mmc,cmd);
	sd_send_cmd(mmc,cmd,MMC_CMD_SELECT_CARD,MMC_RSP_R1b,(mmc->rca<<16));
	//write_u32(DATA_WIDTH, APB_0+SDHC_ADDR+0x028);//sdhc_reg - Host Control 1

	sd_send_cmd(mmc,cmd,MMC_CMD_APP_CMD,MMC_RSP_R1,(mmc->rca<<16));
	sd_send_cmd(mmc,cmd,SD_CMD_APP_SET_BUS_WIDTH,MMC_RSP_R1,DATA_WIDTH);
	sd_send_cmd(mmc,cmd,MMC_CMD_SET_BLOCKLEN,MMC_RSP_R1,BLOCK_SIZE);

	if(DEBUG_PRINTF_EN)
		bsp_printf("SD_CardInitial done\r\n");
}


void SD_EraseBlk(struct mmc *mmc, struct mmc_cmd *cmd,u32 sd_addr, u32 blk_count)
{
	sd_send_cmd(mmc,cmd,SD_CMD_ERASE_WR_BLK_START,MMC_RSP_R1,sd_addr);
	sd_send_cmd(mmc,cmd,SD_CMD_ERASE_WR_BLK_END,MMC_RSP_R1,sd_addr+(blk_count-1)*BLOCK_SIZE);
	sd_send_cmd(mmc,cmd,MMC_CMD_ERASE,MMC_RSP_R1b,0);
}


void SD_WRITE_BLOCK(struct mmc *mmc, u32 addr, void* src, u32 blocks)
{
	struct mmc_cmd *cmd;
	struct mmc_data *data;
	struct mmc_ops	*ops = mmc->cfg->ops;

	cmd = malloc(sizeof(struct mmc_cmd));
	data = malloc(sizeof(struct mmc_data));

	memset(cmd,0,sizeof(struct mmc_cmd));
	memset(data,0,sizeof(struct mmc_data));

	data->blocksize = mmc->read_bl_len;
	data->blocks = blocks;

	if(data->blocks == 1)	cmd->cmdidx=MMC_CMD_WRITE_SINGLE_BLOCK;
	else					cmd->cmdidx=MMC_CMD_WRITE_MULTIPLE_BLOCK;

	cmd->cmdarg =addr;
	cmd->resp_type=MMC_RSP_R1;

	data->src=src;
	data->flags = MMC_DATA_WRITE;

	ops->send_cmd(mmc,cmd,data);

	free(cmd);
	free(data);

	return;
}

void SD_READ_BLOCK(struct mmc *mmc, u32 addr, char* dest, u32 blocks)
{
	struct mmc_cmd *cmd;
	struct mmc_data *data;
	struct mmc_ops	*ops = mmc->cfg->ops;


	cmd = malloc(sizeof(struct mmc_cmd));
	data = malloc(sizeof(struct mmc_data));

	memset(cmd,0,sizeof(struct mmc_cmd));
	memset(data,0,sizeof(struct mmc_data));

	data->blocksize = mmc->read_bl_len;
	data->blocks = blocks;

	if(data->blocks == 1)	cmd->cmdidx=MMC_CMD_READ_SINGLE_BLOCK;
	else					cmd->cmdidx=MMC_CMD_READ_MULTIPLE_BLOCK;

	cmd->cmdarg =addr;
	cmd->resp_type=MMC_RSP_R1;
	data->dest=dest;
	data->flags = MMC_DATA_READ;


	mmc->cfg->ops->send_cmd(mmc,cmd,data);

	free(cmd);
	free(data);

	return;
}

char SD_ReadWriteCompare(char* wrbuf, char* rdbuf ,u64 wr_start ,u64 wr_end ,u64 rd_start ,u64 rd_end,u32 block_count,u32 current_blk,u32 total_blk)
{
	char err=0;
	u32 m,cmpblk;
	u32 rd_speed,wr_speed;

	if(block_count>MAX_BLK_BUF)	cmpblk=MAX_BLK_BUF;
	else						cmpblk=block_count;

	if(memcmp(wrbuf,rdbuf,sizeof(char)*cmpblk*BLOCK_SIZE))
	{
		bsp_printf("Tested Block %d/%d\n\r",current_blk,total_blk);

			for(m=0;m<(cmpblk*BLOCK_SIZE/4);m++)
			{
				if(wrbuf[m] != rdbuf[m])
				{
				bsp_printf("compare fail m=%d wr= 0x%x rd=0x%x\n\r",m,wrbuf[m],rdbuf[m]);
				err=1;
				break;
				}

			}
	}
	else
	{
		wr_speed = ((block_count*BLOCK_SIZE)*1024)/((wr_end-wr_start)/(BSP_CLINT_HZ/1000000));
		rd_speed = ((block_count*BLOCK_SIZE)*1024)/((rd_end-rd_start)/(BSP_CLINT_HZ/1000000));

		if((current_blk % 1024) ==0)
			bsp_printf("Tested Block %d/%d          Write s=%d KByte/s   Read s=%d KByte/s           \r",current_blk,total_blk,wr_speed,rd_speed);

	}

	return err;
}


void SD_InitRandomBuff(char* buf, u32 size)
{
	int m;

	for(m=0;m<size;m++)
	{
		buf[m] = rand() & 0xFF;
	}

	srand(buf[0]);
}

/* Deterministic per-LBA pattern: same data after power cycle without on-chip state */
static char sd_pattern_byte(u32 block_lba, u32 i)
{
	static const uint8_t head[4] = {
		PATTERN_HEAD_0, PATTERN_HEAD_1, PATTERN_HEAD_2, PATTERN_HEAD_3
	};

	if (i < 4)
		return (char)head[i];
	return (char)(PATTERN_XOR ^ (block_lba & 0xFFu) ^ (i & 0xFFu) ^ ((i >> 8) & 0xFFu));
}

void SD_FillBlockPattern(char *buf, u32 block_lba, u32 len)
{
	u32 i;

	for (i = 0; i < len; i++)
		buf[i] = sd_pattern_byte(block_lba, i);
}

int SD_VerifyBlockPattern(const char *buf, u32 block_lba, u32 len)
{
	u32 i;
	char expect;

	for (i = 0; i < len; i++) {
		expect = sd_pattern_byte(block_lba, i);
		if (buf[i] != expect) {
			bsp_printf("Mismatch LBA %d off %d: rd=0x%x exp=0x%x\r\n",
				(int)block_lba, (int)i, (int)buf[i] & 0xff, (int)expect & 0xff);
			return -1;
		}
	}
	return 0;
}

/************************** YUV422 Frame File ***************************/

/* Deterministic YUYV byte at global frame offset gbo:
 *   even byte -> Y  = 16  + ((x + y) & 0x7F)
 *   odd byte  -> U  = 64  + ((x >> 1) & 0x3F)   (first chroma of the pair)
 *              -> V  = 192 - ((y >> 2) & 0x3F)  (second chroma of the pair)
 * Reference (slow) version used for a few sample bytes. */
unsigned char Frame_Yuv422Byte(u32 gbo)
{
	u32 pix = gbo >> 1;
	u32 x = pix % FRAME_WIDTH;
	u32 y = pix / FRAME_WIDTH;

	if ((gbo & 1) == 0)
		return (unsigned char)(16 + ((x + y) & 0x7F));
	if (gbo & 2)
		return (unsigned char)(192 - ((y >> 2) & 0x3F));
	return (unsigned char)(64 + ((x >> 1) & 0x3F));
}

/* Fast fill/verify walk the buffer with an incremental x/y cursor. */
void Frame_FillYuv422(char *buf, u32 gbo_off, u32 len)
{
	u32 i;
	u32 pix = gbo_off >> 1;
	u32 x = pix % FRAME_WIDTH;
	u32 y = pix / FRAME_WIDTH;

	for (i = 0; i < len; i++) {
		u32 gbo = gbo_off + i;
		if ((gbo & 1) == 0)
			buf[i] = (char)(16 + ((x + y) & 0x7F));
		else if (gbo & 2)
			buf[i] = (char)(192 - ((y >> 2) & 0x3F));
		else
			buf[i] = (char)(64 + ((x >> 1) & 0x3F));
		/* one pixel = 2 bytes: advance x after EVERY odd byte */
		if ((gbo & 1) && ++x >= FRAME_WIDTH) { x = 0; y++; }
	}
}

int Frame_VerifyYuv422(const char *buf, u32 gbo_off, u32 len)
{
	u32 i;
	u32 pix = gbo_off >> 1;
	u32 x = pix % FRAME_WIDTH;
	u32 y = pix / FRAME_WIDTH;
	unsigned char exp, got;

	for (i = 0; i < len; i++) {
		u32 gbo = gbo_off + i;
		if ((gbo & 1) == 0)
			exp = (unsigned char)(16 + ((x + y) & 0x7F));
		else if (gbo & 2)
			exp = (unsigned char)(192 - ((y >> 2) & 0x3F));
		else
			exp = (unsigned char)(64 + ((x >> 1) & 0x3F));
		got = (unsigned char)buf[i];
		if (got != exp) {
			bsp_printf("  frame mismatch off=%d rd=0x%x exp=0x%x\r\n",
				(int)gbo, (int)got, (int)exp);
			return -1;
		}
		/* one pixel = 2 bytes: advance x after EVERY odd byte */
		if ((gbo & 1) && ++x >= FRAME_WIDTH) { x = 0; y++; }
	}
	return 0;
}

/* 64-bit additive checksum over 32-bit little-endian words.
 * Matches the hardware SUM of ddr_port1_reader (sum of all beat words). */
void calc_sum64(const u32 *p, u32 words, u32 *lo, u32 *hi)
{
	u32 l = 0, h = 0, i, v;

	for (i = 0; i < words; i++) {
		v = p[i];
		l += v;
		if (l < v)
			h++;
	}
	*lo = l;
	*hi = h;
}

/************************** DDR Port 1 Reader ****************************/

void P1Reader_Wr(u32 off, u32 val)
{
	write_u32(val, P1R_BASE + off);
}

u32 P1Reader_Rd(u32 off)
{
	return read_u32(P1R_BASE + off);
}

/* Launch the hardware reader on [addr, addr+len) and wait for DONE. */
int P1Reader_Run(u32 addr, u32 len_bytes, u32 timeout_ms,
		u32 *sum_lo, u32 *sum_hi, u32 *beats, u32 *first_w0, u32 *last_w0)
{
	u32 st;
	u32 t = 0;

	/* ABORT first: recovers the FSM from a previously hung transaction
	 * (the FSM ignores START while stuck in DATA state) */
	P1Reader_Wr(P1R_REG_CTRL, 0x6);		/* ABORT + clear previous DONE */
	P1Reader_Wr(P1R_REG_ADDR, addr);
	P1Reader_Wr(P1R_REG_LEN, len_bytes);
	P1Reader_Wr(P1R_REG_CTRL, 0x1);		/* START */

	while (1) {
		st = P1Reader_Rd(P1R_REG_STATUS);
		if (st & 0x2)
			break;						/* DONE */
		if (!(st & 0x1)) {
			bsp_printf("  P1R stopped unexpectedly (status 0x%x)\r\n", (int)st);
			return -1;
		}
		bsp_uDelay(1000);
		if (++t > timeout_ms) {
			bsp_printf("  P1R timeout (st 0x%x, beats %d, w0 0x%x, rv%d rl%d, rb %d)\r\n",
				(int)st, (int)P1Reader_Rd(P1R_REG_BEATS),
				(int)P1Reader_Rd(P1R_REG_FIRST_W0),
				(int)((st >> 3) & 1), (int)((st >> 4) & 1),
				(int)P1Reader_Rd(P1R_REG_RLAST_BURST));
			/* fill the outputs with the live register values so the
			 * caller's MISMATCH print shows real data, not stale
			 * stack leftovers */
			*sum_lo  = P1Reader_Rd(P1R_REG_SUM_LO);
			*sum_hi  = P1Reader_Rd(P1R_REG_SUM_HI);
			*beats   = P1Reader_Rd(P1R_REG_BEATS);
			*first_w0= P1Reader_Rd(P1R_REG_FIRST_W0);
			*last_w0 = P1Reader_Rd(P1R_REG_LAST_W0);
			return -2;
		}
	}

	if (st & 0x4) {
		bsp_printf("  P1R reported SLVERR\r\n");
		return -3;
	}

	*sum_lo  = P1Reader_Rd(P1R_REG_SUM_LO);
	*sum_hi  = P1Reader_Rd(P1R_REG_SUM_HI);
	*beats   = P1Reader_Rd(P1R_REG_BEATS);
	*first_w0= P1Reader_Rd(P1R_REG_FIRST_W0);
	*last_w0 = P1Reader_Rd(P1R_REG_LAST_W0);
	return 0;
}

/* Ghost-response / AR-channel diagnostics. Call after a run completed:
 * waits ~20 ms with rready de-asserted so any self-driven R beats from
 * the macro accumulate in IDLE_RV, then dumps the probes.
 *   rid != 0          -> the R beats are NOT the response to our ARID=0
 *   ar_delay == 0xFF  -> AR was never accepted (should not happen, rc!=0)
 *   idle_rv  > 0      -> macro emits RVALID on its own (ghost stream) */
void P1Reader_Diag(void)
{
	u32 rv0, rv1, rv2;

	bsp_uDelay(20000);			/* idle sampling window */
	rv0 = P1Reader_Rd(P1R_REG_IDLE_RV);
	bsp_uDelay(20000);
	rv1 = P1Reader_Rd(P1R_REG_IDLE_RV);
	bsp_uDelay(20000);
	rv2 = P1Reader_Rd(P1R_REG_IDLE_RV);
	bsp_printf("  [diag] rid first 0x%x last 0x%x, ar_delay %d, "
		"idle_rv %d/%d/%d (20ms x3)\r\n",
		(int)P1Reader_Rd(P1R_REG_RID_FIRST),
		(int)P1Reader_Rd(P1R_REG_RID_LAST),
		(int)P1Reader_Rd(P1R_REG_AR_DELAY),
		(int)rv0, (int)rv1, (int)rv2);
}

/****************** Phase C: 8-pattern generator **************************/

/* BT.601 studio-swing bar colours, index 0..7:
 *   white yellow cyan green magenta red blue black */
static const unsigned char pat8_y [8] = {235, 210, 170, 145, 106,  82,  41,  16};
static const unsigned char pat8_cb[8] = {128,  16, 166,  54, 202,  90, 240, 128};
static const unsigned char pat8_cr[8] = {128, 138,  42,  34, 222, 240, 110, 128};

/* Y / C values for pixel (x, y) of pattern pat -- same maths as the
 * reference pattern_gen.v. odd = position inside the pixel pair:
 * 0 -> C = Cb, 1 -> C = Cr. */
static void pat8_pixel(u32 pat, u32 x, u32 y, int odd,
		unsigned char *py, unsigned char *pc)
{
	u32 ci = 7;

	switch (pat) {
	case 0:						/* 8 vertical colour bars */
		ci = x / (FRAME_WIDTH / 8);
		break;
	case 1:					/* white crosshair over grey gradient */
		if (x != FRAME_WIDTH / 2 && y != FRAME_HEIGHT / 2) {
			*py = (unsigned char)((x + y) & 0xFF);
			*pc = 0x80;
			return;
		}
		ci = 0;
		break;
	case 2:						/* horizontal gradient */
		*py = (unsigned char)(x & 0xFF);
		*pc = 0x80;
		return;
	case 3:						/* vertical gradient */
		*py = (unsigned char)(y & 0xFF);
		*pc = 0x80;
		return;
	case 4: ci = 5; break;				/* red   */
	case 5: ci = 3; break;				/* green */
	case 6: ci = 6; break;				/* blue  */
	default:					/* 32x32 checkerboard */
		ci = (((x >> 5) ^ (y >> 5)) & 1) ? 0 : 7;
		break;
	}
	*py = pat8_y[ci];
	*pc = odd ? pat8_cr[ci] : pat8_cb[ci];
}

/* Fill a whole 720p frame with pattern pat, CSI-2 pack-64 slot layout:
 * each pixel pair occupies 4 bytes C Y C Y (U Y V Y), so the DDR word
 * feeds the shape_video_data FIFO exactly like the reference pattern_gen. */
void Frame_FillPattern(char *buf, u32 pat)
{
	u32 x, y, i = 0;
	unsigned char yv, cc;

	for (y = 0; y < FRAME_HEIGHT; y++) {
		for (x = 0; x < FRAME_WIDTH; x += 2) {
			pat8_pixel(pat, x,     y, 0, &yv, &cc);
			buf[i++] = (char)cc; buf[i++] = (char)yv;
			pat8_pixel(pat, x + 1, y, 1, &yv, &cc);
			buf[i++] = (char)cc; buf[i++] = (char)yv;
		}
	}
}

int Frame_VerifyPattern(const char *buf, u32 pat)
{
	u32 x, y, i = 0;
	unsigned char yv = 0, cc = 0, got;

	for (y = 0; y < FRAME_HEIGHT; y++) {
		for (x = 0; x < FRAME_WIDTH; x += 2) {
			pat8_pixel(pat, x,     y, 0, &yv, &cc);
			got = (unsigned char)buf[i++];
			if (got != cc) goto bad;
			got = (unsigned char)buf[i++];
			if (got != yv) goto bad;
			pat8_pixel(pat, x + 1, y, 1, &yv, &cc);
			got = (unsigned char)buf[i++];
			if (got != cc) goto bad;
			got = (unsigned char)buf[i++];
			if (got != yv) goto bad;
		}
	}
	return 0;
bad:
	bsp_printf("  pattern %d mismatch off=%d rd=0x%x exp C=0x%x Y=0x%x\r\n",
		(int)pat, (int)(i - 1), (int)got, (int)cc, (int)yv);
	return -1;
}

/************************** video_reader (APB 1) **************************/

void VR_Wr(u32 off, u32 val)
{
	write_u32(val, VR_BASE + off);
}

u32 VR_Rd(u32 off)
{
	return read_u32(VR_BASE + off);
}

