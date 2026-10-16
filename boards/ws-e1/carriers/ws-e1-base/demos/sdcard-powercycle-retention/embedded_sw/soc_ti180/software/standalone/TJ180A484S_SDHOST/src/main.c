#include <stdint.h>
#include <string.h>
#include "bsp.h"
#include "intc.h"
#include "efx_mmc_driver.h"
#include "source.h"
#include "userDef.h"

char buf[BLOCK_SIZE * MAX_BLK_BUF];
char rd_buf[BLOCK_SIZE * MAX_BLK_BUF];

static void print_pattern_head(const char *label, const uint8_t *data)
{
	bsp_printf("%s bytes[0..3]: %x %x %x %x\r\n",
		label,
		(int)data[0], (int)data[1], (int)data[2], (int)data[3]);
}

static char wait_uart_key(void)
{
	char key;

	bsp_printf("  [w] WRITE phase  -> write test data, then power off\r\n");
	bsp_printf("  [r] READ phase   -> power on again, verify saved data\r\n");
	bsp_printf("  Press w or r: ");

	while (1) {
		key = uart_read(BSP_UART_TERMINAL);
		if (key == 'w' || key == 'W' || key == 'r' || key == 'R') {
			bsp_printf("%c\r\n", key);
			return key;
		}
	}
}

static void retention_write_phase(struct mmc *mmc, struct mmc_cmd *cmd)
{
	u32 lba;
	u32 end_lba = RETENTION_START_LBA + RETENTION_BLOCK_COUNT;

	bsp_printf("\r\n--- WRITE phase ---\r\n");
	bsp_printf("LBA %d .. %d (%d blocks, %d kB)\r\n",
		(int)RETENTION_START_LBA, (int)(end_lba - 1), (int)RETENTION_BLOCK_COUNT,
		(int)((RETENTION_BLOCK_COUNT * BLOCK_SIZE) / 1024));

	SD_EraseBlk(mmc, cmd, RETENTION_START_LBA, RETENTION_BLOCK_COUNT);

	for (lba = RETENTION_START_LBA; lba < end_lba; lba++) {
		SD_FillBlockPattern(buf, lba, BLOCK_SIZE);
		if (lba == RETENTION_START_LBA) {
			print_pattern_head("  write pattern", (const uint8_t *)buf);
		}
		SD_WRITE_BLOCK(mmc, lba, buf, MAX_BLK_BUF);
		if (((lba - RETENTION_START_LBA) & 0x1F) == 0) {
			bsp_printf("  written LBA %d\r\n", (int)lba);
		}
	}

	bsp_printf("\r\nWRITE done.\r\n");
	bsp_printf(">>> Power off the board, wait a few seconds, power on <<<\r\n");
	bsp_printf(">>> JTAG Debug download THIS program again, press Resume, then 'r' <<<\r\n");
}

static void retention_read_phase(struct mmc *mmc)
{
	u32 lba;
	u32 end_lba = RETENTION_START_LBA + RETENTION_BLOCK_COUNT;
	u32 pass = 0;
	u32 fail = 0;
	uint8_t first_bytes[4];

	bsp_printf("\r\n--- READ phase (after power cycle) ---\r\n");
	bsp_printf("LBA %d .. %d (%d blocks)\r\n",
		(int)RETENTION_START_LBA, (int)(end_lba - 1), (int)RETENTION_BLOCK_COUNT);

	for (lba = RETENTION_START_LBA; lba < end_lba; lba++) {
		SD_READ_BLOCK(mmc, lba, rd_buf, MAX_BLK_BUF);
		if (SD_VerifyBlockPattern(rd_buf, lba, BLOCK_SIZE) == 0) {
			if (lba == RETENTION_START_LBA) {
				first_bytes[0] = (uint8_t)rd_buf[0];
				first_bytes[1] = (uint8_t)rd_buf[1];
				first_bytes[2] = (uint8_t)rd_buf[2];
				first_bytes[3] = (uint8_t)rd_buf[3];
			}
			pass++;
		} else {
			fail++;
			break;
		}
		if (((lba - RETENTION_START_LBA) & 0x1F) == 0) {
			bsp_printf("  verified LBA %d\r\n", (int)lba);
		}
	}

	bsp_printf("\r\n");
	if (fail == 0) {
		bsp_printf("PASS: all %d blocks match after power cycle.\r\n", (int)pass);
		print_pattern_head("  read back LBA 0x1000", first_bytes);
	} else {
		bsp_printf("FAIL: %d ok, %d bad (first error above).\r\n", (int)pass, (int)fail);
	}
}

void main(void)
{
	static struct mmc mmc_inst;
	static struct mmc_config cfg_inst;
	static struct mmc_ops ops_inst;
	static struct mmc_cmd cmd_inst;
	struct mmc *mmc = &mmc_inst;
	struct mmc_cmd *cmd = &cmd_inst;
	struct mmc_config *cfg = &cfg_inst;
	struct mmc_ops *ops = &ops_inst;
	char phase;
	u32 total_block_n;

	bsp_init();
	bsp_printf("\r\n--- EFX-SD Power-Cycle Retention Test ---\r\n");

	memset(mmc, 0, sizeof(struct mmc));
	memset(cfg, 0, sizeof(struct mmc_config));
	memset(ops, 0, sizeof(struct mmc_ops));
	memset(cmd, 0, sizeof(struct mmc_cmd));

	mmc->cfg = cfg;
	mmc->cfg->ops = ops;

	bsp_printf("\r\nInitialize...");

	sd_ctrl_mmc_probe(mmc, PROBE_ADDR);
	IntcInitialize(mmc);
	SD_CardInitial(mmc, cmd);
	bsp_printf("Done\r\n\n");

	total_block_n = (u32)(mmc->capacity / 512);
	bsp_printf("Card: %d MByte, %d blocks, bus %d-bit\r\n",
		(int)(mmc->capacity / 1024 / 1024), (int)total_block_n, (DATA_WIDTH == 2) ? 4 : 1);
	bsp_printf("Test region: LBA %d, %d blocks\r\n\r\n",
		(int)RETENTION_START_LBA, (int)RETENTION_BLOCK_COUNT);

	if (RETENTION_START_LBA + RETENTION_BLOCK_COUNT > total_block_n) {
		bsp_printf("ERROR: test region exceeds card capacity.\r\n");
		while (1) {}
	}

	phase = wait_uart_key();

	if (phase == 'w' || phase == 'W') {
		retention_write_phase(mmc, cmd);
	} else {
		retention_read_phase(mmc);
	}

	while (1) {}
}
