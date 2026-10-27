#include <stdint.h>
#include <string.h>
#include "bsp.h"
#include "intc.h"
#include "efx_mmc_driver.h"
#include "source.h"
#include "userDef.h"

/*
 * YUV422 720p frame DDR path test
 *
 *   Frame region lives at the END of the card (never touches MBR/FS metadata)
 *   and is written ONCE: a signature block below the frame records magic +
 *   geometry + reference checksum. Later runs read the signature, see the
 *   frame is already stored and skip generation + SD write entirely.
 *
 *   first run : [1] CPU builds frame in DDR (port 0) -> sum A
 *               [2] SD write frame + signature (ADMA reads DDR port 0)
 *   every run : [3] CPU wipes the frame buffer in DDR
 *               [4] SD multi-block read: ADMA writes DDR (port 0)
 *               [5] ddr_port1_reader reads the frame back on AXI port 1 -> sum C
 *               [6] CPU re-reads the frame on port 0 -> sum B + pattern
 *
 *   PASS when A == B == C, beat count complete and pattern intact,
 *   proving: SD -> DMA -> DDR port0 write -> DDR port1 read path.
 */

static void print_frame_head(const char *label, const u8 *p)
{
	int i;

	bsp_printf("%s", label);
	for (i = 0; i < 8; i++)
		bsp_printf(" %x", (int)p[i]);
	bsp_printf("  (Y0 U Y1 V Y2 U Y3 V)\r\n");
}

static void frame_path_test(struct mmc *mmc, u32 total_blocks)
{
	static u32 sig[BLOCK_SIZE / 4];	/* signature block, DDR -> DMA safe */
	u8  *frame = (u8 *)DDR_FRAME_ADDR;
	u32 words = FRAME_SIZE / 4;
	u32 frame_lba = total_blocks - FRAME_END_MARGIN - FRAME_BLK_CNT;
	u32 sign_lba = frame_lba - 1;
	u32 sumA_lo, sumA_hi, sumB_lo, sumB_hi, sumC_lo, sumC_hi;
	u32 beats, first_w0, last_w0;
	u32 i, rc, pass;

	bsp_printf("\r\n--- YUV422 720p frame path test ---\r\n");
	bsp_printf("frame %dx%d YUYV = %d bytes (%d blocks @ LBA 0x%x..0x%x), DDR 0x%x\r\n",
		FRAME_WIDTH, FRAME_HEIGHT, FRAME_SIZE, FRAME_BLK_CNT,
		(int)frame_lba, (int)(frame_lba + FRAME_BLK_CNT - 1),
		(int)DDR_FRAME_ADDR);
	bsp_printf("test region at end of card, FS/MBR untouched\r\n");

	if (P1Reader_Rd(P1R_REG_ID) != 0x50315231u) {
		bsp_printf("ERROR: ddr_port1_reader not found (ID 0x%x)\r\n",
			(int)P1Reader_Rd(P1R_REG_ID));
		while (1) {}
	}
	bsp_printf("ddr_port1_reader ID ok\r\n");

	/* [1] read signature: is the frame already stored on the card? */
	memset(sig, 0, sizeof(sig));
	SD_READ_BLOCK(mmc, sign_lba, (char *)sig, 1);

	/* refuse to overwrite anything that looks like a boot/FS block (0x55AA) */
	if ((sig[127] >> 16) == 0xAA55u) {
		bsp_printf("ERROR: LBA 0x%x holds boot/FS data, abort (no write).\r\n",
			(int)sign_lba);
		return;
	}

	if (sig[0] == FRAME_SIGN_MAGIC && sig[1] == FRAME_WIDTH &&
	    sig[2] == FRAME_HEIGHT && sig[3] == FRAME_BPP &&
	    sig[4] == FRAME_BLK_CNT) {
		sumA_lo = sig[5];
		sumA_hi = sig[6];
		bsp_printf("[1/5] frame already on card (signature ok) -> skip generate + SD write\r\n");
		bsp_printf("  ref sumA = %x_%x (from signature)\r\n",
			(int)sumA_hi, (int)sumA_lo);
	} else {
		/* [1] generate frame + reference checksum A */
		bsp_printf("[1/5] no valid signature -> generate YUV422 frame (CPU, port 0)...\r\n");
		for (i = 0; i < FRAME_BLK_CNT; i++)
			Frame_FillYuv422((char *)(frame + i * BLOCK_SIZE),
				i * BLOCK_SIZE, BLOCK_SIZE);
		calc_sum64((const u32 *)frame, words, &sumA_lo, &sumA_hi);
		print_frame_head("  frame head:", frame);
		bsp_printf("  ref sumA = %x_%x\r\n", (int)sumA_hi, (int)sumA_lo);

		/* [2] write frame to SD card via ADMA (reads DDR port 0), once */
		bsp_printf("[2/5] SD write %d blocks (ADMA reads DDR port 0)...\r\n",
			(int)FRAME_BLK_CNT);
		SD_WRITE_BLOCK(mmc, frame_lba, (void *)frame, FRAME_BLK_CNT);

		memset(sig, 0, sizeof(sig));
		sig[0] = FRAME_SIGN_MAGIC;
		sig[1] = FRAME_WIDTH;
		sig[2] = FRAME_HEIGHT;
		sig[3] = FRAME_BPP;
		sig[4] = FRAME_BLK_CNT;
		sig[5] = sumA_lo;
		sig[6] = sumA_hi;
		SD_WRITE_BLOCK(mmc, sign_lba, (void *)sig, 1);
		bsp_printf("  frame + signature stored (future runs skip SD write)\r\n");
	}

	/* [3] wipe the frame buffer */
	bsp_printf("[3/5] wipe frame buffer...\r\n");
	memset(frame, 0, FRAME_SIZE);

	/* [4] read frame back from SD via ADMA (writes DDR port 0) */
	bsp_printf("[4/5] SD read %d blocks (ADMA writes DDR port 0)...\r\n",
		(int)FRAME_BLK_CNT);
	SD_READ_BLOCK(mmc, frame_lba, (char *)frame, FRAME_BLK_CNT);

	/* [5] hardware reader on DDR AXI port 1 */
	/* [5a] burst ladder: read increasing lengths to find the stall point
	 * (1 beat, 2, 6 = golden-ref size, 64 = one full burst, 1K beats).
	 * rb = beats the macro actually returned in the last burst (RLAST). */
	{
		static const u32 lens[5] = {64, 128, 384, 4096, 65536};
		u32 i, bl, bh, bb, bf, bl2;

		bsp_printf("[5a] port1 burst ladder...\r\n");
		for (i = 0; i < 5; i++) {
			rc = P1Reader_Run(DDR_FRAME_ADDR, lens[i], 200,
				&bl, &bh, &bb, &bf, &bl2);
			bsp_printf("  len %6d: rc %d, beats %3d/%3d, rb %3d, sum %x_%x, w0 0x%x\r\n",
				(int)lens[i], (int)rc, (int)bb,
				(int)((lens[i] + 63) / 64),
				(int)P1Reader_Rd(P1R_REG_RLAST_BURST),
				(int)bh, (int)bl, (int)bf);
			if (rc != 0)
				break;
		}
	}

	/* [5b] and [6] probes relocated BELOW the pass/fail judgment: both
	 * overwrite frame-buffer bytes, which used to corrupt sumB/sumC and
	 * the YUV verify (test-order defect, not a hardware failure). */

	bsp_printf("[5/5] ddr_port1_reader reads frame (DDR port 1)...\r\n");
	rc = P1Reader_Run(DDR_FRAME_ADDR, FRAME_SIZE, 2000,
		&sumC_lo, &sumC_hi, &beats, &first_w0, &last_w0);
	if (rc != 0) {
		bsp_printf("FAIL: port 1 reader error %d\r\n", (int)rc);
		return;
	}

	/* [6] CPU view on port 0 */
	calc_sum64((const u32 *)frame, words, &sumB_lo, &sumB_hi);
	rc = Frame_VerifyYuv422((const char *)frame, 0, FRAME_SIZE);
	print_frame_head("  readback head:", frame);

	bsp_printf("\r\n  sumA (CPU gen)   = %x_%x\r\n", (int)sumA_hi, (int)sumA_lo);
	bsp_printf("  sumB (CPU port0) = %x_%x\r\n", (int)sumB_hi, (int)sumB_lo);
	bsp_printf("  sumC (HW port1)  = %x_%x\r\n", (int)sumC_hi, (int)sumC_lo);
	bsp_printf("  beats = %d / %d, first_w0 = 0x%x, last_w0 = 0x%x\r\n",
		(int)beats, (int)(FRAME_SIZE / 64), (int)first_w0, (int)last_w0);

	/* ghost-response / AR-channel probes after the full-frame read */
	P1Reader_Diag();

	pass = 1;
	if (sumA_lo != sumB_lo || sumA_hi != sumB_hi) {
		bsp_printf("  MISMATCH: CPU port0 view differs from reference\r\n");
		pass = 0;
	}
	if (sumA_lo != sumC_lo || sumA_hi != sumC_hi) {
		bsp_printf("  MISMATCH: port 1 readout differs from reference\r\n");
		pass = 0;
	}
	if (beats != FRAME_SIZE / 64) {
		bsp_printf("  MISMATCH: incomplete transfer on port 1\r\n");
		pass = 0;
	}
	if (rc != 0) {
		bsp_printf("  MISMATCH: pattern verification failed\r\n");
		pass = 0;
	}

	if (pass)
		bsp_printf("\r\nPASS: SD -> DMA -> DDR port0 write -> DDR port1 read verified.\r\n");
	else
		bsp_printf("\r\nFAIL: see mismatches above.\r\n");

	/*-----------------------------------------------------------------
	 * Post-judgment diagnostics (DDR-corrupting, non-fatal).
	 *
	 * [5b] address sensitivity probe: CPU writes distinct magic words to
	 * four 64B slots via port 0, then the hardware reader reads one beat
	 * from each slot. Distinguishes:
	 *   - w0 == its own magic  -> addressing works, data path fine
	 *   - w0 == first magic    -> macro repeats beat 0 of each burst
	 *   - w0 == 0x06070e06     -> data source is fixed, AR never reaches
	 *                             the DRAM read path
	 * A port0 read-back + 1 ms delay drains the CPU posted writes first:
	 * without it the port1 read can race the write drain and return the
	 * OLD DRAM content (observed on board: w0 = previous frame data).
	 */
	{
		u32 a, bl, bh, bb, bf, bl2;
		static const u32 probe_ofs[4] = {0, 64, 128, 192};

		bsp_printf("[5b] port1 address probe (post-judgment)...\r\n");
		for (i = 0; i < 4; i++) {
			volatile u32 *p = (volatile u32 *)(DDR_FRAME_ADDR +
				probe_ofs[i]);
			u32 m = 0xA5000000u + probe_ofs[i];
			u32 k;
			for (k = 0; k < 16; k++)
				p[k] = m + k;
		}
		{
			u32 bad = 0, k;
			for (i = 0; i < 4; i++) {
				volatile u32 *p = (volatile u32 *)(DDR_FRAME_ADDR +
					probe_ofs[i]);
				u32 m = 0xA5000000u + probe_ofs[i];
				for (k = 0; k < 16; k++)
					if (p[k] != m + k)
						bad++;
			}
			bsp_uDelay(1000);
			bsp_printf("  port0 readback %s\r\n",
				bad ? "STALE (writes not visible yet)" : "ok");
		}
		for (i = 0; i < 4; i++) {
			a = DDR_FRAME_ADDR + probe_ofs[i];
			rc = P1Reader_Run(a, 64, 100, &bl, &bh, &bb, &bf, &bl2);
			(void)bb;
			bsp_printf("  @0x%08x: rc %d, w0 0x%08x (exp 0x%08x)\r\n",
				(int)a, (int)rc, (int)bf,
				(int)(0xA5000000u + probe_ofs[i]));
			if (rc != 0)
				break;
		}
		/* DDR 0: program area - a beat from here proves the macro reads
		 * real DRAM somewhere, even if the address is being ignored.
		 * NOTE: the CPU DDR window starts at 0x1000 (SYSTEM_DDR_BMB),
		 * so 0x0-0xFFF is unreachable from software - never deref it. */
		rc = P1Reader_Run(0, 64, 100, &bl, &bh, &bb, &bf, &bl2);
		(void)bb;
		bsp_printf("  @0x00000000: rc %d, w0 0x%08x\r\n", (int)rc,
			(int)bf);
	}

	/* [6] stuck-ARADDR readout: fill every CPU-reachable DDR byte the
	 * tests use (0x00300000..0x03000000 - firmware lives below 0x200000)
	 * with address-encoded words, then read single beats back via port1.
	 *   w0 == probed address     -> addressing actually works
	 *   w0 == some other value X -> if X looks like 0x0wwwwwwC it IS the
	 *                               stuck source address (self-announced)
	 *   w0 == 0x06070e06 again   -> source is below 0x1000 (CPU-blind
	 *                               DRAM) or not DRAM at all
	 * Same posted-write drain as [5b] (spot check + 10 ms).
	 */
	{
		volatile u32 *fa = (volatile u32 *)0x00200000u;
		u32 nw = (0x03000000u - 0x00200000u) / 4u;
		u32 k, w0s, bl, bh, bb, bl2;

		for (k = 0; k < nw; k++)
			fa[k] = 0x00200000u + 4u * k;
		bsp_printf("[6] filled 0x00200000..0x03000000 with addr-encoded data\r\n");
		{
			u32 bad = 0;
			for (k = 0; k < nw; k += 4096)
				if (fa[k] != 0x00200000u + 4u * k)
					bad++;
			if (fa[nw - 1] != 0x00200000u + 4u * (nw - 1))
				bad++;
			bsp_uDelay(10000);
			bsp_printf("  port0 readback %s\r\n",
				bad ? "STALE (writes not visible yet)" : "ok");
		}
		{
			volatile u32 *fw = (volatile u32 *)0x00001000u;
			bsp_printf("  firmware head (CPU): %08x %08x %08x %08x\r\n",
				(int)fw[0], (int)fw[1], (int)fw[2], (int)fw[3]);
		}
		rc = P1Reader_Run(0x00001000u, 64, 100, &bl, &bh, &bb, &w0s, &bl2);
		(void)bb; (void)bl; (void)bh;
		bsp_printf("  probe @0x00001000: rc %d, w0 0x%08x (expect firmware head)\r\n",
			(int)rc, (int)w0s);
		rc = P1Reader_Run(0x01512340u, 64, 100, &bl, &bh, &bb, &w0s, &bl2);
		bsp_printf("  probe @0x01512340: rc %d, w0 0x%08x (exp 0x01512340)\r\n",
			(int)rc, (int)w0s);
		rc = P1Reader_Run(0x02555580u, 64, 100, &bl, &bh, &bb, &w0s, &bl2);
		bsp_printf("  probe @0x02555580: rc %d, w0 0x%08x (exp 0x02555580)\r\n",
			(int)rc, (int)w0s);
	}
}

/*
 * Phase C: 8-pattern MIPI CSI-2 TX video path
 *
 *   Patterns (same maths as the reference pattern_gen.v): colour bars,
 *   crosshair over gradient, H gradient, V gradient, red, green, blue,
 *   32x32 checkerboard. Stored ONCE at the end of the card BELOW the A/B
 *   frame zone; a signature block records magic + geometry + per-pattern
 *   checksums.
 *
 *   first run : [1] CPU builds 8 patterns in DDR (port 0, staging buffer)
 *               [2] SD write 8 x 3600 blocks + signature (ADMA reads port 0)
 *   every run : [3] SD read 8 patterns -> DDR 0x02000000 (ADMA writes port 0)
 *               [4] CPU port0 checksum + ddr_port1_reader port1 checksum, 8/8
 *               [5] video_reader takes DDR port 1 (OWN_P1=1, RUN=1) and
 *                   streams BASE..BASE+8*FBYTES -> shape_video_data async
 *                   FIFO -> CSI-2 TX IP -> DPHY TX2, switching pattern every
 *                   180 frames (3 s @ 60 fps), looping forever.
 */
static void pattern_path_test(struct mmc *mmc, u32 total_blocks)
{
	static u32 sig[BLOCK_SIZE / 4];
	u32 frame_lba = total_blocks - FRAME_END_MARGIN - FRAME_BLK_CNT;
	u32 pat_lba   = frame_lba - 1 - PAT8_END_MARGIN - PAT8_BLK_CNT;
	u32 sign_lba  = pat_lba - 1;
	u32 ref_lo[PAT8_COUNT], ref_hi[PAT8_COUNT];
	u32 sum_lo, sum_hi, beats, first_w0, last_w0;
	u32 p, rc, pass, s;

	bsp_printf("\r\n--- 8-pattern MIPI CSI-2 TX path test ---\r\n");
	bsp_printf("patterns %d x %d bytes (%d blocks @ LBA 0x%x..0x%x), DDR 0x%x\r\n",
		PAT8_COUNT, FRAME_SIZE, PAT8_BLK_CNT, (int)pat_lba,
		(int)(pat_lba + PAT8_BLK_CNT - 1), (int)DDR_PAT_ADDR);
	bsp_printf("region below the A/B frame zone, FS/MBR untouched\r\n");

	if (VR_Rd(VR_REG_ID) != 0x56314452u) {
		bsp_printf("ERROR: video_reader not found (ID 0x%x)\r\n",
			(int)VR_Rd(VR_REG_ID));
		return;
	}
	bsp_printf("video_reader ID ok (APB1)\r\n");

	/* [1] read signature: are the patterns already stored on the card? */
	memset(sig, 0, sizeof(sig));
	SD_READ_BLOCK(mmc, sign_lba, (char *)sig, 1);

	/* refuse to overwrite anything that looks like a boot/FS block (0x55AA) */
	if ((sig[127] >> 16) == 0xAA55u) {
		bsp_printf("ERROR: LBA 0x%x holds boot/FS data, abort (no write).\r\n",
			(int)sign_lba);
		return;
	}

	if (sig[0] == PAT8_SIGN_MAGIC && sig[1] == FRAME_WIDTH &&
	    sig[2] == FRAME_HEIGHT && sig[3] == FRAME_BPP &&
	    sig[4] == FRAME_BLK_CNT && sig[5] == PAT8_COUNT) {
		bsp_printf("[1/5] patterns already on card (signature ok) -> skip generate + SD write\r\n");
		for (p = 0; p < PAT8_COUNT; p++) {
			ref_lo[p] = sig[6 + 2 * p];
			ref_hi[p] = sig[7 + 2 * p];
		}
	} else {
		/* [1] generate 8 patterns, each straight into its final DDR slot */
		bsp_printf("[1/5] no valid signature -> generate 8 patterns (CPU, port 0)...\r\n");
		for (p = 0; p < PAT8_COUNT; p++) {
			char *slot = (char *)(DDR_PAT_ADDR + p * FRAME_SIZE);
			Frame_FillPattern(slot, p);
			calc_sum64((const u32 *)slot, FRAME_SIZE / 4,
				&ref_lo[p], &ref_hi[p]);
			bsp_printf("  pattern %d: sum = %x_%x\r\n",
				(int)p, (int)ref_hi[p], (int)ref_lo[p]);
		}

		/* [2] write all patterns to SD via ADMA (reads DDR port 0), once.
		   The slots are read individually - reusing one staging buffer
		   would store the last pattern in all 8 card regions. */
		bsp_printf("[2/5] SD write %d blocks (ADMA reads DDR port 0)...\r\n",
			(int)PAT8_BLK_CNT);
		for (p = 0; p < PAT8_COUNT; p++)
			SD_WRITE_BLOCK(mmc, pat_lba + p * FRAME_BLK_CNT,
				(char *)(DDR_PAT_ADDR + p * FRAME_SIZE),
				FRAME_BLK_CNT);

		memset(sig, 0, sizeof(sig));
		sig[0] = PAT8_SIGN_MAGIC;
		sig[1] = FRAME_WIDTH;
		sig[2] = FRAME_HEIGHT;
		sig[3] = FRAME_BPP;
		sig[4] = FRAME_BLK_CNT;
		sig[5] = PAT8_COUNT;
		for (p = 0; p < PAT8_COUNT; p++) {
			sig[6 + 2 * p] = ref_lo[p];
			sig[7 + 2 * p] = ref_hi[p];
		}
		SD_WRITE_BLOCK(mmc, sign_lba, (void *)sig, 1);
		bsp_printf("  patterns + signature stored (future runs skip SD write)\r\n");
	}

	/* [3] load all 8 patterns from SD into the streaming frame array */
	bsp_printf("[3/5] SD read %d blocks -> DDR 0x%x (ADMA writes port 0)...\r\n",
		(int)PAT8_BLK_CNT, (int)DDR_PAT_ADDR);
	for (p = 0; p < PAT8_COUNT; p++)
		SD_READ_BLOCK(mmc, pat_lba + p * FRAME_BLK_CNT,
			(char *)(DDR_PAT_ADDR + p * FRAME_SIZE), FRAME_BLK_CNT);

	/* [4] CPU view on port 0 for every pattern */
	pass = 1;
	for (p = 0; p < PAT8_COUNT; p++) {
		calc_sum64((const u32 *)(DDR_PAT_ADDR + p * FRAME_SIZE),
			FRAME_SIZE / 4, &sum_lo, &sum_hi);
		if (sum_lo != ref_lo[p] || sum_hi != ref_hi[p]) {
			bsp_printf("  MISMATCH: pattern %d CPU port0 sum %x_%x != ref %x_%x\r\n",
				(int)p, (int)sum_hi, (int)sum_lo,
				(int)ref_hi[p], (int)ref_lo[p]);
			pass = 0;
		}
	}
	bsp_printf("[4/5] CPU port0 checksum: %s\r\n", pass ? "8/8 ok" : "FAILED");

	/* [5] hardware reader on DDR AXI port 1 for every pattern */
	for (p = 0; p < PAT8_COUNT; p++) {
		rc = P1Reader_Run(DDR_PAT_ADDR + p * FRAME_SIZE, FRAME_SIZE, 2000,
			&sum_lo, &sum_hi, &beats, &first_w0, &last_w0);
		if (rc != 0 || sum_lo != ref_lo[p] || sum_hi != ref_hi[p] ||
		    beats != FRAME_SIZE / 64) {
			bsp_printf("  MISMATCH: pattern %d port1 rc=%d sum %x_%x beats %d\r\n",
				(int)p, (int)rc, (int)sum_hi, (int)sum_lo,
				(int)beats);
			pass = 0;
		}
	}
	bsp_printf("[5/5] DDR port1 hardware checksum: %s\r\n",
		pass ? "8/8 ok" : "FAILED");

	/* ghost-response / AR-channel probes after the pattern-7 read */
	P1Reader_Diag();

	/* full pixel verify of pattern 0 (catches byte-order mistakes early) */
	if (Frame_VerifyPattern((const char *)DDR_PAT_ADDR, 0) != 0)
		pass = 0;

	if (!pass) {
		bsp_printf("\r\nFAIL: pattern storage/verify error, MIPI streaming not started.\r\n");
		return;
	}

	/* [6] hand DDR port 1 to video_reader and start the MIPI stream */
	bsp_printf("\r\nstarting MIPI CSI-2 TX stream (8 patterns x %d frames, 3 s each)...\r\n",
		PAT8_SWITCH_FRAMES);
	VR_Wr(VR_REG_CTRL, 0x0);			/* stop, OWN_P1 = 0 */
	VR_Wr(VR_REG_ADDR, DDR_PAT_ADDR);
	VR_Wr(VR_REG_FBYTES, FRAME_SIZE);
	VR_Wr(VR_REG_NFRAME, PAT8_COUNT);
	VR_Wr(VR_REG_NSWITCH, PAT8_SWITCH_FRAMES);
	VR_Wr(VR_REG_CTRL, 0x8);			/* OWN_P1 = 1 */
	VR_Wr(VR_REG_CTRL, 0x9);			/* RUN = 1 */

	for (s = 0; s < 5; s++) {
		bsp_printf("  t=%ds: status=0x%x pat=%d frames=%d\r\n", (int)(s * 2),
			(int)VR_Rd(VR_REG_STATUS), (int)VR_Rd(VR_REG_PAT_IDX),
			(int)VR_Rd(VR_REG_FCNT));
		if (s < 4)
			bsp_uDelay(2000000);
	}

	if ((VR_Rd(VR_REG_STATUS) & 0x3) == 0x1 && VR_Rd(VR_REG_FCNT) > 100)
		bsp_printf("\r\nPASS: SD -> DDR -> MIPI CSI-2 TX streaming (check display).\r\n");
	else
		bsp_printf("\r\nFAIL: video_reader stalled (status 0x%x, frames %d).\r\n",
			(int)VR_Rd(VR_REG_STATUS), (int)VR_Rd(VR_REG_FCNT));
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
	u32 total_block_n;

	bsp_init();
	bsp_printf("\r\n--- top_demo: SD -> DDR dual-port -> CSI-2 path test ---\r\n");

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
		(int)(mmc->capacity / 1024 / 1024), (int)total_block_n,
		(DATA_WIDTH == 2) ? 4 : 1);

	if (total_block_n < FRAME_END_MARGIN + FRAME_BLK_CNT + 2) {
		bsp_printf("ERROR: card too small for the end-of-card test region.\r\n");
		while (1) {}
	}
	if (total_block_n < PAT8_BLK_CNT + FRAME_BLK_CNT +
			     PAT8_END_MARGIN + FRAME_END_MARGIN + 4) {
		bsp_printf("ERROR: card too small for the 8-pattern region (~17 MB).\r\n");
		while (1) {}
	}

	frame_path_test(mmc, total_block_n);
	pattern_path_test(mmc, total_block_n);

	while (1) {}
}
