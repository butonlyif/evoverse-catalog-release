////////////////////////////////////////////////////////////////////////////
//  imx415_init.c -- IMX415 camera I2C configuration (camera step 2)
//
//  Target: 1920x1080 @ 60 fps (1944x1096 rows incl. blanking), RAW10,
//  4 MIPI lanes @ 1782 Mbps, INCK = 37.125 MHz (module crystal, bench
//  confirmed). Config per cam2_1080p.md (bench-verified R9.53/R9.54).
//
//  Flow (per bring-up test plan):
//    [L1a] bus recovery + CHIP_ID read 0x3F12 (expect 0x0514; fall back
//          to VMAX/HMAX reset defaults if SENSOR_INFO unprogrammed)
//    [L1b] write config table (real Sony map), every byte ACK-checked,
//          then geo1080 + LANEMODE + DPHY-1782 blocks
//    [L1c] readback-verify key registers (VMAX/HMAX/SYS_MODE/INCKSEL)
//    [L1d] 0x3002=0x00 master start (while still in standby) ->
//          0x3000=0x00 standby release -> ~220 ms settle
//
//  Expected downstream (obs2 CSR 0xF812_0000): DT=0x2B, WC=2430
//  (1944 x 1.25), pcnt=485 beats/line (0-based), lcnt=1115 lines/frame
//  (19 EBD/OB + 1096 rows), fcnt increments @ 60 fps.
//  NOTE: the FPGA bitstream must be built with data_rate=1782 (peri.xml
//  already set).
////////////////////////////////////////////////////////////////////////////
#include <stdint.h>
#include "bsp.h"
#include "i2c.h"
#include "gpio.h"
#include "imx415_init.h"

/* Dual camera target (top_cam_demo instantiates two top_cam paths): choose
 * the I2C controller + cam_en gpio bit once in imx415_init(id); every
 * imx415_* primitive below then acts on that camera.
 *   cam0: SYSTEM_I2C_0_IO_CTRL (0xF8016000) + w_gpio_write[0] -> cam_0_en
 *   cam1: SYSTEM_I2C_1_IO_CTRL (0xF8017000) + w_gpio_write[1] -> cam_1_en */
static u32         cam_i2c_base = SYSTEM_I2C_0_IO_CTRL;
static u32         cam_gpio_bit = 0x1;
static const char *cam_tag      = "cam0";
#define CAM_I2C_REG         cam_i2c_base              /* selected at runtime */
#define CAM_GPIO_REG        SYSTEM_GPIO_0_IO_CTRL     /* 0xF8015000, [bit] = cam_en */
#define CAM_I2C_ADDR_W      0x34                      /* 7-bit 0x1A << 1 */
#define CAM_I2C_ADDR_R      0x35
#define CAM_I2C_TIMEOUT     20000000u                 /* bounded wait */

/* cam_en power sequencing must touch only this camera's bit: the SoC GPIO
 * OUTPUT register is a whole-word write (top: 4-bit io_write drives BOTH
 * cam_en), so clearing the whole word would kill the other camera's
 * already-streaming sensor. */
static void cam_gpio_clr(void)
{
	gpio_setOutput(CAM_GPIO_REG,
		       gpio_getOutput(CAM_GPIO_REG) & ~cam_gpio_bit);
}

static void cam_gpio_set(void)
{
	gpio_setOutput(CAM_GPIO_REG,
		       gpio_getOutput(CAM_GPIO_REG) | cam_gpio_bit);
}

/* ------------------------------------------------------------------ */
/* Low-level primitives with TIMEOUT on every wait.                   */
/*                                                                     */
/* BSP's i2c_*Blocking functions spin forever if the bus is stuck low  */
/* (no pull-ups / slave holding SDA): the master waits for the bus to  */
/* become idle and never returns -- which is what froze the first     */
/* bring-up attempt. All waits below are bounded.                     */
/* ------------------------------------------------------------------ */
static int cam_wait_clr(u32 off, u32 mask)
{
	u32 t = CAM_I2C_TIMEOUT;
	while (read_u32(CAM_I2C_REG + off) & mask) {
		if (--t == 0)
			return -1;
	}
	return 0;
}

/* start condition; -10 = never completed, -11 = dropped (bus not free) */
static int cam_start(void)
{
	i2c_masterStart(CAM_I2C_REG);
	if (cam_wait_clr(I2C_MASTER_STATUS, I2C_MASTER_START) < 0)
		return -10;
	if (read_u32(CAM_I2C_REG + I2C_MASTER_STATUS) & I2C_MASTER_START_DROPPED)
		return -11;
	return 0;
}

/* nack bit tx; waits for TX_VALID clear (9 SCL edges) */
static int cam_txnack(void)
{
	i2c_txNack(CAM_I2C_REG);
	return cam_wait_clr(I2C_TX_ACK, I2C_TX_VALID);
}

/* stop condition; waits for master not busy */
static int cam_stop(void)
{
	i2c_masterStop(CAM_I2C_REG);
	return cam_wait_clr(I2C_MASTER_STATUS, I2C_MASTER_BUSY);
}

/* bus recovery (up to 9 SCL pulses + STOP) */
static int cam_recover(void)
{
	int i;

	for (i = 0; i < 3; i++) {
		i2c_masterRecover(CAM_I2C_REG);
		if (cam_wait_clr(I2C_MASTER_STATUS, I2C_MASTER_RECOVER) < 0)
			return -12;
		if ((read_u32(CAM_I2C_REG + I2C_MASTER_STATUS) &
		     I2C_MASTER_RECOVER_DROPPED) == 0)
			return 0;
	}
	return 0;   /* dropped x3: keep going, probe will tell more */
}

/* bounded-ACK byte transmit (never hangs on missing ACK) */
static int cam_tx_check(u8 b)
{
	i2c_txByte(CAM_I2C_REG, b);
	if (cam_txnack() < 0)
		return -20;                    /* clock gen stalled   */
	/* cam_txnack() already waited the 9 SCL edges, so the NACK flag is
	   final: polling for it to clear burns CAM_I2C_TIMEOUT (~seconds)
	   per NACKed byte (that is what made the ID-stage register dump
	   take >1 min -- nonexistent addresses always NACK). Check once. */
	if (i2c_rxNack(CAM_I2C_REG))
		return -1;                 /* no ACK from slave   */
	return 0;
}

/* ------------------------------------------------------------------ */
/* I2C timing: 50 kHz @ 200 MHz core clock. History on the fly-wired   */
/* bus: 100k -> 50k -> 25k -> 10k -> 50k (no-ACK seen at several       */
/* rates; the bus idles 1/1 and recovers cleanly, so rate is not       */
/* clearly the culprit). Per the IMX415 AC table (0-400 kHz,           */
/* tLOW >= 1.3 us etc.) all items met.                                 */
/* ------------------------------------------------------------------ */
static I2c_Config cam_cfg = {
	.samplingClockDivider = 9,
	.timeout              = 16000,   /* hw watchdog 0.8 ms (~4.4 byte
					    times at 50 kHz; fires only on an
					    INACTIVE frame, never mid-transfer) */
	.tsuDat               = 5,       /* 250 ns >= tSU;DAT 100 ns        */
	.tLow                 = 1999,    /* (200M/50k/2)-1 = 10 us          */
	.tHigh                = 1999,
	.tBuf                 = 3999,    /* 40 us >> tBUF 1.3 us            */
};

/* -20 recovery: the I2C CONTROLLER (FPGA side) stalled mid-transaction.
   The cam_en power cycle only resets the sensor -- it cannot touch a
   wedged master FSM, so reapply the config (restarts the timing
   generator) and clear the bus before retrying. */
static void cam_ctrl_reset(void)
{
	i2c_applyConfig(CAM_I2C_REG, &cam_cfg);
	cam_recover();
	cam_stop();
}

/* [L0a] fast address probe for bus scan: one START + W addr + read ACK */
static int cam_probe_addr(u8 addr7)
{
	int nack;

	if (cam_start() < 0) { cam_stop(); return -10; }
	i2c_txByte(CAM_I2C_REG, (u8)(addr7 << 1));
	if (cam_txnack() < 0) {
		cam_stop();
		cam_ctrl_reset();         /* else the whole scan stalls */
		return -20;
	}
	nack = i2c_rxNack(CAM_I2C_REG);   /* valid right after 9th clock */
	cam_stop();
	return nack ? -1 : 0;
}

static int imx415_write_once(u16 reg, u8 val)
{
	int rc;

	if ((rc = cam_start()) < 0)       goto w_err;
	if ((rc = cam_tx_check(CAM_I2C_ADDR_W)) < 0)  goto w_stop;
	if ((rc = cam_tx_check((u8)(reg >> 8))) < 0)  goto w_stop;
	if ((rc = cam_tx_check((u8)(reg & 0xFF))) < 0) goto w_stop;
	if ((rc = cam_tx_check(val)) < 0) goto w_stop;
	return cam_stop();

w_stop:
	cam_stop();
w_err:
	return rc;
}

static int imx415_read_once(u16 reg, u8 *val)
{
	int rc;

	if ((rc = cam_start()) < 0)       goto r_err;
	if ((rc = cam_tx_check(CAM_I2C_ADDR_W)) < 0)  goto r_stop;
	if ((rc = cam_tx_check((u8)(reg >> 8))) < 0)  goto r_stop;
	if ((rc = cam_tx_check((u8)(reg & 0xFF))) < 0) goto r_stop;
	if ((rc = cam_start()) < 0)       goto r_stop;   /* repeated start */
	if ((rc = cam_tx_check(CAM_I2C_ADDR_R)) < 0)  goto r_stop;
	i2c_txByte(CAM_I2C_REG, 0xFF);            /* release SDA, clock 8 bits */
	if (cam_txnack() < 0) { rc = -20; goto r_stop; }
	*val = (u8)i2c_rxData(CAM_I2C_REG);
	return cam_stop();

r_stop:
	cam_stop();
r_err:
	return rc;
}

int imx415_write_reg(u16 reg, u8 val)
{
	int rc = imx415_write_once(reg, val);

	if (rc == -20) {                    /* controller stalled: revive it */
		cam_ctrl_reset();
		rc = imx415_write_once(reg, val);
	}
	return rc;
}

int imx415_read_reg(u16 reg, u8 *val)
{
	int rc = imx415_read_once(reg, val);

	if (rc == -20) {
		cam_ctrl_reset();
		rc = imx415_read_once(reg, val);
	}
	return rc;
}

/* ------------------------------------------------------------------ */
/* Register table: IMX415 (real Sony map) 1080p60, 4-lane RAW10,      */
/* 1782 Mbps, CSI-2, INCK 37.125 MHz (cam2_1080p.md, bench-verified)  */
/*                                                                    */
/* Composition follows the mainline Linux imx415.c setup order:       */
/*   1. format regs + "SONY magic" block (with VMAX/HMAX/clock regs   */
/*      still at reset defaults -- writing the 0x37xx PLL/VCO block   */
/*      after reprogramming the clock config wedges the sensor)       */
/*   2. legacy geometry rows kept only to preserve the verified write */
/*      order -- every mode-dependent value is overwritten by the     */
/*      geo1080 block in imx415_init_once()                           */
/*   3. clock params 1782 Mbps / 37.125 MHz (kernel clk_params col)   */
/* ------------------------------------------------------------------ */

/* Boot-time knobs:
   CAM_PWR_OFF_US   cam_en low time (hard reset). 300 ms is the value
                     that made first-init reliable (clears rails + any
                     wedged state from an aborted previous init); trim
                     at your own risk to shorten boot.
   CAM_ID_REG_DUMP  1 = full 21-register dump when CHIP_ID != 0x0514.
                     One-time bring-up diagnostic: this batch's
                     SENSOR_INFO is permanently unprogrammed, so the
                     ID-mismatch branch runs on EVERY boot and the dump
                     costs ~21 reads + prints (~100 ms) each time. The
                     cheap VMAX/HMAX fallback check below is the trusted
                     identification, so the dump is off by default.
   CAM_LANE_MAP_TEST 1 = write LANEMODE=2-lane instead of 4-lane. The
                     sensor then only drives D0/D1 (LAN2/3 stay LP-11). */
#define CAM_PWR_OFF_US  300000
#define CAM_ID_REG_DUMP 0
#define CAM_LANE_MAP_TEST 0

#if CAM_LANE_MAP_TEST
#define CAM_LANEMODE_VAL 0x01   /* 2-lane                          */
#else
#define CAM_LANEMODE_VAL 0x03   /* 4-lane                          */
#endif

static const struct {
	u16 reg;
	u8  val;
} imx415_reg_tbl[] = {
	{0x3000, 0x01},                          /* standby                 */
	/* ---- format (kernel imx415_init_table head) ----                 */
	{0x3031, 0x00},                          /* ADBIT 10bit             */
	{0x3032, 0x00},                          /* MDBIT 10bit (reset 0x01)*/
	/* BLKLEVEL = 0x032 (50 LSB @10bit) - the Sony/TI default
	 * (IMX415_BLKLEVEL_DEFAULT 50 in the TI kernel driver). The sensor
	 * corrects its native dark level to this output pedestal. Raising
	 * it (100) just brightened the dark floor (Y 12 -> 25 measured) -
	 * wrong direction, reverted. The ISP dark-floor clamp handles the
	 * residual column noise. */
	{0x30E2, 0x32},                          /* BLKLEVEL[7:0] = 50      */
	{0x30E3, 0x00},                          /* BLKLEVEL[9:8]           */
	{0x30C0, 0x0A},                          /* OUTSEL (cam2_1080p.md fixed value) */
	{0x30C1, 0x00},                          /* DRV                     */
	/* ---- kernel "SONY magic" block. ORDER MATTERS: it must be written
	   while VMAX/HMAX/SYS_MODE/INCKSEL still hold their RESET defaults.
	   Writing 0x37xx after the clock config is reprogrammed wedges the
	   sensor (observed on board at 0x3736). ----                     */
	{0x32D4, 0x21}, {0x32EC, 0xA1},
	{0x3452, 0x7F}, {0x3453, 0x03},
	{0x358A, 0x04}, {0x35A1, 0x02},
	{0x36BC, 0x0C}, {0x36CC, 0x53}, {0x36CD, 0x00}, {0x36CE, 0x3C},
	{0x36D0, 0x8C}, {0x36D1, 0x00}, {0x36D2, 0x71}, {0x36D4, 0x3C},
	{0x36D6, 0x53}, {0x36D7, 0x00}, {0x36D8, 0x71}, {0x36DA, 0x8C},
	{0x36DB, 0x00},
	{0x3724, 0x02}, {0x3726, 0x02}, {0x3732, 0x02},
	{0x3734, 0x03}, {0x3736, 0x03}, {0x3742, 0x03},
	{0x3862, 0xE0}, {0x38CC, 0x30}, {0x38CD, 0x2F},
	{0x395C, 0x0C}, {0x3A42, 0xD1}, {0x3A4C, 0x77},
	{0x3AE0, 0x02}, {0x3AEC, 0x0C},
	{0x3B00, 0x2E}, {0x3B06, 0x29},
	{0x3B98, 0x25}, {0x3B99, 0x21},
	{0x3B9B, 0x13}, {0x3B9C, 0x13}, {0x3B9D, 0x13}, {0x3B9E, 0x13},
	{0x3BA1, 0x00}, {0x3BA2, 0x06}, {0x3BA3, 0x0B}, {0x3BA4, 0x10},
	{0x3BA5, 0x14}, {0x3BA6, 0x18}, {0x3BA7, 0x1A}, {0x3BA8, 0x1A},
	{0x3BA9, 0x1A},
	{0x3BAC, 0xED}, {0x3BAD, 0x01}, {0x3BAE, 0xF6}, {0x3BAF, 0x02},
	{0x3BB0, 0xA2}, {0x3BB1, 0x03},
	{0x3BB2, 0xE0}, {0x3BB3, 0x03}, {0x3BB4, 0xE0}, {0x3BB5, 0x03},
	{0x3BB6, 0xE0}, {0x3BB7, 0x03}, {0x3BB8, 0xE0}, {0x3BBA, 0xE0},
	{0x3BBC, 0xDA}, {0x3BBE, 0x88}, {0x3BC0, 0x44}, {0x3BC2, 0x7B},
	{0x3BC4, 0xA2}, {0x3BC8, 0xBD}, {0x3BCA, 0xBD},
	/* ---- legacy geometry rows (VMAX 6576 = 30fps basis): kept for
	   the verified write order only; the geo1080 block in
	   imx415_init_once() overwrites the mode-dependent values ----    */
	{0x301C, 0x04},                          /* WINMODE window crop     */
	{0x3020, 0x01}, {0x3021, 0x01},          /* H/V binning             */
	{0x3022, 0x01},                          /* ADDMODE 2/2             */
	{0x3024, 0xB0}, {0x3025, 0x19},          /* VMAX = 6576 (30fps)     */
	{0x3028, 0x6D}, {0x3029, 0x01},          /* HMAX = 365              */
	{0x3040, 0x88}, {0x3041, 0x02},          /* PIX_HST  = 0x288        */
	{0x3042, 0x08}, {0x3043, 0x0A},          /* PIX_HWIDTH = 0xA08      */
	{0x3044, 0xF0}, {0x3045, 0x02},          /* PIX_VST  = 0x2F0        */
	{0x3046, 0x40}, {0x3047, 0x0B},          /* PIX_VWIDTH = 0xB40      */
	{0x3050, 0x08},                          /* SHR0                    */
	{0x30D9, 0x02}, {0x30DA, 0x01},          /* DIG_CLP (binning 2/2)   */
	/* ---- clock params 1782 Mbps / INCK 37.125 MHz (kernel
	   clk_params column, written LAST per kernel order) ----          */
	{0x3008, 0x7F},                          /* BCWAIT_TIME             */
	{0x300A, 0x5B},                          /* CPWAIT_TIME             */
	{0x3033, 0x04},                          /* SYS_MODE = 1782 Mbps    */
	{0x3115, 0x00},                          /* INCKSEL1                */
	{0x3116, 0x24}, {0x3118, 0xC0}, {0x311A, 0xE0}, {0x311E, 0x24},
	{0x400C, 0x01},                          /* INCKSEL6 (1782 col)     */
	{0x4074, 0x00},                          /* INCKSEL7 (>=1440: 0)    */
	{0x4004, 0x48}, {0x4005, 0x09},          /* TXCLKESC 0x948          */
};
/* streaming start (mainline kernel order, bench-verified): 0x3002=0x00
   master-mode start is written WHILE STILL IN STANDBY, then 0x3000=0x00
   releases standby and the stream comes up (~220 ms to settle). Writing
   only 0x3000=0x00 wakes the sensor into IDLE: no stream, clock lanes
   stay dead. See imx415_stream_on() below. */

#define IMX415_TBL_N     (sizeof(imx415_reg_tbl) / sizeof(imx415_reg_tbl[0]))
#define IMX415_STREAM_REG 0x3000

/* readback-verified key registers: {reg, expected} */
static const struct {
	u16 reg;
	u8  exp;
} imx415_verify[] = {
	{0x3024, 0xCA},   /* VMAX = 2250 (60fps)    */
	{0x3025, 0x08},   /* VMAX mid               */
	{0x3028, 0x26},   /* HMAX = 550             */
	{0x3029, 0x02},   /* HMAX high              */
	{0x3031, 0x00},   /* ADBIT 10bit             */
	{0x3033, 0x04},   /* SYS_MODE  = 1782 Mbps   */
	{0x400C, 0x01},   /* INCKSEL6 (1782 col)     */
	{0x4074, 0x00},   /* INCKSEL7 (>=1440: 0)    */
	{0x4001, CAM_LANEMODE_VAL},   /* LANEMODE    */
};

/* ------------------------------------------------------------------ */
/* Start streaming, mainline-kernel order (cam2_1080p.md §E, tested):
   0x3002=0x00 master-mode start FIRST (while still in standby), then
   0x3000=0x00 releases standby and the stream comes up. */
int imx415_stream_on(void)
{
	int rc = imx415_write_reg(0x3002, 0x00);            /* master start */

	if (rc == 0)
		rc = imx415_write_reg(IMX415_STREAM_REG, 0x00); /* standby off */
	return rc;
}
int imx415_stream_off(void)
{
	int rc = imx415_write_reg(IMX415_STREAM_REG, 0x01);  /* standby    */
	if (rc == 0)
		rc = imx415_write_reg(0x3002, 0x01);         /* master stop */
	return rc;
}

static int imx415_init_once(void)
{
	u8 v, rd;
	u32 i, j;
	int rc;

	bsp_printf("\r\n--- IMX415[%s] init (1080p60 RAW10 4lane @1782Mbps) ---\r\n",
		cam_tag);

	/* [L0-] cam_en power sequence before touching I2C:
	   low CAM_PWR_OFF_US (hard reset: lets module rails discharge / XCLR
	   reset -- clears any half-configured or wedged state from a previous
	   aborted init), then high -> 12 ms settle -> I2C access.
	   (12 ms covers the 11 ms register-access delay from the IMX415
	   module power-up spec: power enable -> 20 us -> reset high -> 11 ms.) */
	cam_gpio_clr();                               /* this cam_en low only */
	bsp_uDelay(CAM_PWR_OFF_US);

	/* bus clear, then 50 kHz timing @ 200 MHz core clock (cam_cfg:
	   fly-wired bus history 100k -> 50k -> 25k -> 10k -> 50k -- see
	   its comment) */
	i2c_applyConfig(CAM_I2C_REG, &cam_cfg);

	/* [L0-cold] line levels with the sensor UNPOWERED: pure pull-up +
	   fly-wire state. SDA=0 HERE = weak pad pull-up losing (missing
	   external pull-up / long RC / short) - the sensor cannot be the
	   culprit. SDA=1 here but 0 after power = sensor clamping SDA. */
	{
		u32 st = i2c_getSlaveStatus(CAM_I2C_REG);
		bsp_printf("bus cold (cam_en off): SCL=%d SDA=%d (need 1/1)\r\n",
			(int)((st >> 2) & 1), (int)((st >> 1) & 1));
	}

	cam_gpio_set();                               /* this cam_en high */
	bsp_uDelay(12000);

	/* [L0] bus idle level check: SLAVE_STATUS bit1=SDA bit2=SCL.
	   1/1 = pull-ups + idle OK; anything 0 = missing pull-up, shorted
	   or slave holding the line (hardware issue, no I2C will work). */
	{
		u32 st = i2c_getSlaveStatus(CAM_I2C_REG);
		bsp_printf("bus idle (cam_en on): SCL=%d SDA=%d (need 1/1)\r\n",
			(int)((st >> 2) & 1), (int)((st >> 1) & 1));
	}
	if (cam_recover() < 0) {
		bsp_printf("ERROR: bus recovery timed out (SCL stuck low?)\r\n");
		return -5;
	}
	{
		u32 st = i2c_getSlaveStatus(CAM_I2C_REG);
		bsp_printf("bus after recover: SCL=%d SDA=%d (need 1/1)\r\n",
			(int)((st >> 2) & 1), (int)((st >> 1) & 1));
	}

	/* [L1a] read-only probe: CHIP ID at 0x3F12 (real Sony IMX415 map,
	   from the Linux kernel driver). Expect 16-bit LE value 0x0514.
	   Do NOT write probes: 0x03xx registers are reserved on the real
	   IMX415 map and may be NACKed. */
	{
		u8 id_lo = 0, id_hi = 0;

		rc  = imx415_read_reg(0x3F12, &id_lo);
		if (rc == 0)
			rc = imx415_read_reg(0x3F13, &id_hi);
		if (rc != 0) {
			bsp_printf("ERROR: CHIP_ID read failed (rc=%d)\r\n", rc);
			bsp_printf("  rc: -1=no ACK  -10=start stuck  -11=start dropped(bus low)\r\n"
				   "      -12=recover stuck  -20=clock gen stalled\r\n");
			/* [L0a] scan the bus: distinguishes wrong address (IMX415 is
			   0x1A or 0x1B) vs dead sensor (no supply / no INCK). */
			{
				int found = 0;
				u8 a;

				bsp_printf("scanning I2C bus 0x08..0x77...\r\n");
				for (a = 0x08; a <= 0x77; a++) {
					if (cam_probe_addr(a) == 0) {
						bsp_printf("  ACK at 7-bit addr 0x%02x%s\r\n",
							(int)a,
							a == 0x1A ? "  <- IMX415 expected" : "");
						found++;
					}
				}
				if (found == 0)
					bsp_printf("  no device answered: check sensor supply"
						   " (cam_en) / INCK / wiring\r\n");
			}
			bsp_printf("  check: sensor power / addr 0x1A / register map\r\n");
			return -1;
		}
		bsp_printf("CHIP_ID = 0x%02x%02x (expect 0x0514 = IMX415)\r\n",
			(int)id_hi, (int)id_lo);
		if (((id_hi << 8) | id_lo) != 0x0514) {
#if CAM_ID_REG_DUMP
			/* dump a few registers from the real IMX415 map: all-zero
			   => clock/power problem (INCK not running); some values
			   => a live chip answering that is not an IMX415. */
			/* dump signature registers of BOTH candidate maps:
			   IMX415: VMAX 0x3024 LE24, HMAX 0x3028 LE16, ID 0x3F12
			   IMX335: VMAX 0x3030 LE24, HMAX 0x3034 LE16,
			           Y_OUT_SIZE 0x3056 (default 0x0798=1944),
			           ID 0x3912, LANEMODE 0x3A01 */
			static const u16 probe_regs[] = {
				0x3024, 0x3025, 0x3026, 0x3028, 0x3029,
				0x3115, 0x3116, 0x3117,
				0x3F12, 0x3F13,
				0x3030, 0x3031, 0x3032, 0x3034, 0x3035,
				0x3056, 0x3057, 0x3018,
				0x3912, 0x3A01,
			};
			u32 k;

			bsp_printf("register dump (real IMX415 map):\r\n");
			for (k = 0; k < sizeof(probe_regs) / sizeof(probe_regs[0]); k++) {
				u8 v = 0xAA;

				if (imx415_read_reg(probe_regs[k], &v) != 0)
					bsp_printf("  0x%04x: read NACK\r\n", (int)probe_regs[k]);
				else
					bsp_printf("  0x%04x: 0x%02x\r\n",
						(int)probe_regs[k], (int)v);
			}
#endif
			/* Board evidence (2026-09): this batch's SENSOR_INFO
			   region is unprogrammed, ID reads 0x0000. Fall back
			   to the power-on defaults of the real Sony map:
			   VMAX 2250 (0x3024..26 = 0x08CA), HMAX 550
			   (0x3028/29 = 0x0226) -- both observed on board. */
			{
				u8 vm0 = 0, vm1 = 0, hm0 = 0, hm1 = 0;

				if (imx415_read_reg(0x3024, &vm0) == 0 &&
				    imx415_read_reg(0x3025, &vm1) == 0 &&
				    imx415_read_reg(0x3028, &hm0) == 0 &&
				    imx415_read_reg(0x3029, &hm1) == 0 &&
				    vm0 == 0xCA && vm1 == 0x08 &&
				    hm0 == 0x26 && hm1 == 0x02)
					bsp_printf("ID reads 0x0000 (SENSOR_INFO unprogrammed):"
						" VMAX default 2250 + HMAX 550 confirm IMX415"
						" -> continue\r\n");
				else {
					bsp_printf("ERROR: id mismatch - sensor is NOT an"
						" IMX415, refusing unknown register map\r\n");
					return -6;
				}
			}
		}
	}

	/* [L1b] table write, ACK-checked. Long retries: the sensor can
	   NACK for a while when an internal reload settles (10 tries,
	   10 ms apart). If a write still NACKs, read the register back:
	   a matching value means it actually landed (spurious NACK). */
	for (i = 0; i < IMX415_TBL_N; i++) {
		for (j = 0; j < 10; j++) {
			rc = imx415_write_reg(imx415_reg_tbl[i].reg,
					      imx415_reg_tbl[i].val);
			if (rc == 0)
				break;
			bsp_uDelay(10000);
		}
		if (rc != 0) {
			u8 rb = 0xAA;

			if (imx415_read_reg(imx415_reg_tbl[i].reg, &rb) == 0 &&
			    rb == imx415_reg_tbl[i].val)
				bsp_printf("warn: write #%d (0x%04x) NACKed but"
					" readback matches\r\n",
					(int)i, (int)imx415_reg_tbl[i].reg);
			else {
				bsp_printf("ERROR: write #%d (0x%04x) no ACK"
					" (read 0x%02x, want 0x%02x)\r\n",
					(int)i, (int)imx415_reg_tbl[i].reg,
					(int)rb, (int)imx415_reg_tbl[i].val);
				return -2;
			}
		}
	}
	bsp_printf("table written: %d entries\r\n", (int)IMX415_TBL_N);

	/* Geometry -> 1080p60 (cam2_1080p.md §B): all-pixel scan + official
	   2/2-line binning -> output 1944x1096 (valid 1920x1080).
	   VMAX 2250 x HMAX 550 @ 74.25 MHz = exactly 60 fps; VMAX still
	   counts the full physical row count in binning mode.
	   Crop-window regs 0x3040-0x3047 are NOT written: WINMODE=0
	   ignores them, power-on defaults stay. */
	{
		static const struct { u16 reg; u8 val; } geo1080[] = {
			{0x301C, 0x00},   /* WINMODE: all-pixel   */
			{0x3020, 0x01},   /* HADD: 2/2 binning    */
			{0x3021, 0x01},   /* VADD: 2/2 binning    */
			{0x3022, 0x01},   /* ADDMODE: 2/2         */
			{0x3024, 0xCA},   /* VMAX = 2250 -> 60fps */
			{0x3025, 0x08},
			{0x3026, 0x00},
			{0x3028, 0x26},   /* HMAX = 550           */
			{0x3029, 0x02},
			{0x30D9, 0x02},   /* DIG_CLP_VSTART: binning (regmap:
					     06h=all-pixel/crop, 02h=binning) */
			{0x30DA, 0x01},   /* DIG_CLP_VNUM: binning */
		};

		for (i = 0; i < (int)(sizeof(geo1080) / sizeof(geo1080[0])); i++) {
			for (j = 0; j < 3; j++) {
				rc = imx415_write_reg(geo1080[i].reg,
						      geo1080[i].val);
				if (rc == 0)
					break;
				bsp_uDelay(1000);
			}
			if (rc != 0) {
				bsp_printf("ERROR: 1080p geo 0x%04x no ACK\r\n",
					(int)geo1080[i].reg);
				return -2;
			}
		}
		bsp_printf("geometry -> 1944x1096@60fps (all-pixel + 2/2 binning = 1080p)\r\n");
	}

	/* LANEMODE (kernel imx415_set_mode step 3 -- it is written by the
	   driver OUTSIDE the mode table, so the 107-entry copy missed it).
	   Power-on default only drives D0/D1: probes showed valid_seen=0011
	   with lane2/3 dead and SOTSYNC errors, i.e. a 4-lane RX listening
	   to a 2-lane transmitter. 16-bit LE reg: hi byte 0x4002 = 0. */
	for (j = 0; j < 3; j++) {
		rc = imx415_write_reg(0x4001, CAM_LANEMODE_VAL);
		if (rc == 0)
			rc = imx415_write_reg(0x4002, 0x00); /* hi byte    */
		if (rc == 0)
			break;
		bsp_uDelay(1000);
	}
	if (rc != 0) {
		bsp_printf("ERROR: LANEMODE write no ACK\r\n");
		return -2;
	}
#if CAM_LANE_MAP_TEST
	bsp_printf("LANEMODE = 2-lane (LANE-MAP TEST) written\r\n");
#else
	bsp_printf("LANEMODE = 4-lane written\r\n");
#endif

	/* DPHY link timing, official 1782 Mbps column (cam2_1080p.md §D).
	   16-bit LE regs: low byte to reg, high byte to reg+1. TCLKZERO
	   = 0x01DF overflows the low byte -- the 0x401F high byte = 0x01
	   MUST be written or lanes can fail HS entry at 1782 Mbps. */
	{
		static const struct { u16 reg; u16 val; } dphy_timing[] = {
			{0x4018, 0x00B7},   /* TCLKPOST    */
			{0x401A, 0x0067},   /* TCLKPREPARE */
			{0x401C, 0x006F},   /* TCLKTRAIL   */
			{0x401E, 0x01DF},   /* TCLKZERO (hi 0x401F = 0x01!) */
			{0x4020, 0x006F},   /* THSPREPARE  */
			{0x4022, 0x00CF},   /* THSZERO     */
			{0x4024, 0x006F},   /* THSTRAIL    */
			{0x4026, 0x00B7},   /* THSEXIT     */
			{0x4028, 0x005F},   /* TLPX        */
		};

		for (i = 0; i < (int)(sizeof(dphy_timing) /
				      sizeof(dphy_timing[0])); i++) {
			for (j = 0; j < 3; j++) {
				rc = imx415_write_reg(dphy_timing[i].reg,
					(u8)(dphy_timing[i].val & 0xFF));
				if (rc == 0)
					rc = imx415_write_reg(
						dphy_timing[i].reg + 1,
						(u8)(dphy_timing[i].val >> 8));
				if (rc == 0)
					break;
				bsp_uDelay(1000);
			}
			if (rc != 0) {
				bsp_printf("ERROR: DPHY timing 0x%04x no ACK\r\n",
					(int)dphy_timing[i].reg);
				return -2;
			}
		}
		bsp_printf("DPHY link timing 1782 Mbps written (%d regs)\r\n",
			(int)(sizeof(dphy_timing) / sizeof(dphy_timing[0])));
	}

	/* [L1c] readback verify -- one rewrite+re-read retry per reg:
	   occasional bus glitches were observed (0x3028 read 0x08 once,
	   next attempt 0x3032 read 0xAA, likely under-charged rails during
	   rapid cam_en retries), and a single bad byte must not kill the
	   whole init. */
	for (i = 0; i < sizeof(imx415_verify) / sizeof(imx415_verify[0]); i++) {
		if (imx415_read_reg(imx415_verify[i].reg, &v) != 0 ||
		    v != imx415_verify[i].exp) {
			u8 bad = v;

			imx415_write_reg(imx415_verify[i].reg,
					 imx415_verify[i].exp);
			bsp_uDelay(1000);
			if (imx415_read_reg(imx415_verify[i].reg, &v) != 0 ||
			    v != imx415_verify[i].exp) {
				bsp_printf("ERROR: verify 0x%04x = 0x%x (expect 0x%x)\r\n",
					(int)imx415_verify[i].reg, (int)v,
					(int)imx415_verify[i].exp);
				return -3;
			}
			bsp_printf("note: verify 0x%04x glitch (read 0x%x), rewritten ok\r\n",
				(int)imx415_verify[i].reg, (int)bad);
		}
	}
	bsp_printf("readback verify ok (VMAX=2250 HMAX=550 SYS_MODE=1782Mbps)\r\n");

	/* [L1d] start streaming, mainline-kernel order (cam2_1080p.md §E,
	   bench-verified): 0x3002=0x00 master-mode start written WHILE
	   STILL IN STANDBY, then 0x3000=0x00 releases standby. Writing
	   only 0x3000=0x00 wakes the sensor into IDLE: no stream, clock
	   lanes stay dead. ~220 ms to settle (24 ms regulator + 9 frames
	   + margin). */
	if (imx415_stream_on() != 0) {
		bsp_printf("ERROR: stream-on (0x3002/0x3000) not ACKed\r\n");
		return -4;
	}
	bsp_uDelay(220000);   /* regulator + 9 frames + margin */
	/* [L1e] runtime state dump: separates "sensor never left standby"
	   (0x3000/0x3002 read back non-zero) from "clock-select registers
	   drifted" (1782 set no longer matching) when the MIPI link stays
	   quiet. All values must match the expected column. */
	{
		static const struct { u16 reg; u8 exp; } dump_regs[] = {
			{0x3000, 0x00},   /* STANDBY: 0 = operating          */
			{0x3002, 0x00},   /* MODE_SEL: 0 = master start      */
			{0x3024, 0xCA},   /* VMAX lo (geo1080)               */
			{0x3025, 0x08},   /* VMAX mid                        */
			{0x3028, 0x26},   /* HMAX lo = 550                   */
			{0x3029, 0x02},   /* HMAX hi                         */
			{0x3008, 0x7F},   /* BCWAIT  (1782 set)              */
			{0x300A, 0x5B},   /* CPWAIT                          */
			{0x3116, 0x24},   /* INCKSEL2                        */
			{0x3118, 0xC0},   /* INCKSEL3                        */
			{0x311A, 0xE0},   /* INCKSEL4                        */
			{0x311E, 0x24},   /* INCKSEL5                        */
			{0x400C, 0x01},   /* INCKSEL6 (1782 col)             */
			{0x4074, 0x00},   /* INCKSEL7 (>=1440: 0)            */
			{0x4001, CAM_LANEMODE_VAL},   /* LANEMODE            */
			{0x4018, 0xB7},   /* TCLKPOST (1782 linkrate set)    */
			{0x401E, 0xDF},   /* TCLKZERO lo                     */
			{0x401F, 0x01},   /* TCLKZERO hi (MUST be 1)         */
			{0x4022, 0xCF},   /* THSZERO lo                      */
			{0x4028, 0x5F},   /* TLPX                            */
			{0x4004, 0x48},   /* TXCLKESC lo                     */
			{0x4005, 0x09},   /* TXCLKESC hi                     */
		};
		u32 k;

		bsp_printf("runtime dump:\r\n");
		for (k = 0; k < sizeof(dump_regs) / sizeof(dump_regs[0]); k++) {
			u8 rv = 0xAA;

			if (imx415_read_reg(dump_regs[k].reg, &rv) != 0)
				bsp_printf("  0x%04x: NACK\r\n",
					(int)dump_regs[k].reg);
			else
				bsp_printf("  0x%04x: 0x%02x (exp 0x%02x)%s\r\n",
					(int)dump_regs[k].reg, (int)rv,
					(int)dump_regs[k].exp,
					rv == dump_regs[k].exp ? "" :
					"  <-- MISMATCH");
		}
	}
#if CAM_LANE_MAP_TEST
	bsp_printf("streaming ON (1782 Mbps 2-lane RAW10, LANE-MAP TEST) -> watch LA:\r\n"
		   "  DT/WC may stay 0: the RX IP is built as 4-lane, a 2-lane\r\n"
		   "  stream can fail packet assembly.\r\n");
#else
	bsp_printf("streaming ON (1782 Mbps 4-lane RAW10 1080p60) -> watch obs2:\r\n"
		   "  DT=0x2B WC=2430 (1944 x 1.25); pcnt=485 (0-based),\r\n"
		   "  lcnt=1115 (19 EBD/OB + 1096 rows), fcnt increments\r\n"
		   "  (bitstream must be built with data_rate=1782).\r\n");
#endif
	return 0;
}

/* Full init with auto-retry. id selects the camera (0 = I2C0 + gpio bit0,
   1 = I2C1 + gpio bit1). The sensor I2C interface can be wedged by
   a single glitch (observed right after an FPGA bitstream download with
   heavy JTAG traffic near the fly-wired bus): it then NACKs everything
   and only a cam_en power cycle clears it. Each retry starts with the
   300 ms hard reset inside imx415_init_once(), so a wedged state from a
   failed attempt is always cleared before the next one. */
int imx415_init(int id)
{
	int rc = 0;
	int attempt;

	/* target select (top_cam_demo: system_i2c_1 -> cam_1_scl/sda,
	 * w_gpio_write[1] -> cam_1_en) */
	if (id == 1) {
		cam_i2c_base = SYSTEM_I2C_1_IO_CTRL;
		cam_gpio_bit = 0x2;
		cam_tag      = "cam1";
	} else {
		cam_i2c_base = SYSTEM_I2C_0_IO_CTRL;
		cam_gpio_bit = 0x1;
		cam_tag      = "cam0";
	}

	for (attempt = 1; attempt <= 3; attempt++) {
		if (attempt > 1) {
			bsp_printf("--- retry %d/3 after hard reset ---\r\n", attempt);
			/* extra settle: rapid cam_en cycles leave module rails
			   half-charged (showed up as 0xAA reads / NACKs on
			   attempts 2+); let them discharge before the next
			   300 ms off-cycle */
			bsp_uDelay(500000);
		}
		rc = imx415_init_once();
		if (rc == 0) {
			if (attempt > 1)
				bsp_printf("IMX415[%s] init OK (attempt %d)\r\n",
				cam_tag, attempt);
			return 0;
		}
		if (rc == -6)      /* not an IMX415: deterministic, no retry */
			break;
		bsp_printf("IMX415[%s] init FAILED (%d) on attempt %d/3\r\n",
			cam_tag, rc, attempt);
	}
	return rc;
}
