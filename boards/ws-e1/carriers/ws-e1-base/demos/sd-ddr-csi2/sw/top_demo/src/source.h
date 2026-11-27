/*
 * source.h
 *
 *  Created on: 17 Mar 2021
 *      Author: user
 */

#ifndef SRC_SOURCE_H_
#define SRC_SOURCE_H_

/* VexRiscv DataCache (write-back) flush: clean+invalidate whole dcache.
 * "fence rw,rw" (rs1=x0) triggers the full flush on this SoC. */
static inline void dma_sync_caches(void)
{
	asm volatile("fence rw, rw" ::: "memory");
}

void SD_CMD(struct mmc *mmc, struct mmc_cmd *cmd);
void SD_CardInitial(struct mmc *mmc, struct mmc_cmd *cmd);
void SD_EraseBlk(struct mmc *mmc, struct mmc_cmd *cmd,u32 sd_addr, u32 blk_count);
void SD_WRITE_BLOCK(struct mmc *mmc, u32 addr, void* src, u32 blocksw);
void SD_READ_BLOCK(struct mmc *mmc, u32 addr, char* dest, u32 blocks);
char SD_ReadWriteCompare(char* wrbuf, char* rdbuf ,u64 wr_start ,u64 wr_end ,u64 rd_start ,u64 rd_end,u32 block_count,u32 current_blk,u32 total_blk);
void SD_InitRandomBuff(char* buf, u32 size);
void SD_FillBlockPattern(char *buf, u32 block_lba, u32 len);
int SD_VerifyBlockPattern(const char *buf, u32 block_lba, u32 len);

/* YUV422 (YUYV) 720p frame pattern + checksums */
unsigned char Frame_Yuv422Byte(u32 gbo);
void Frame_FillYuv422(char *buf, u32 gbo_off, u32 len);
int Frame_VerifyYuv422(const char *buf, u32 gbo_off, u32 len);
void calc_sum64(const u32 *p, u32 words, u32 *lo, u32 *hi);

/* ddr_port1_reader driver (APB slave 0) */
void P1Reader_Wr(u32 off, u32 val);
u32 P1Reader_Rd(u32 off);
int P1Reader_Run(u32 addr, u32 len_bytes, u32 timeout_ms,
		u32 *sum_lo, u32 *sum_hi, u32 *beats, u32 *first_w0, u32 *last_w0);
void P1Reader_Diag(void);

/* Phase C: 8-pattern generator (CSI-2 pack-64 slot layout C Y C Y) */
void Frame_FillPattern(char *buf, u32 pat);
int Frame_VerifyPattern(const char *buf, u32 pat);

/* video_reader driver (APB slave 1) */
void VR_Wr(u32 off, u32 val);
u32 VR_Rd(u32 off);

#endif /* SRC_SOURCE_H_ */
