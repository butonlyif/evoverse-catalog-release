#include <stdint.h>
#include "bsp.h"
#include "userDef.h"
#include "imx415_init.h"

////////////////////////////////////////////////////////////////////////////
//  main.c -- top_cam_demo 双相机直连架构固件
//
//  架构（2026-09）：2x (IMX415 -> my_csi2_rx -> camera_path -> my_csi2_tx)
//  例化于 top_cam_demo。视频通路无 DDR、无帧缓冲，显示帧率跟随传感器
//  （1080p60 直通）。
//
//  资源映射（top_cam_demo.sv）：
//    cam0: DPHY RX0 -> DPHY TX2, APB slave0 (0xF810_0000),
//          I2C0 (0xF801_6000), GPIO0.bit0 -> cam_0_en
//    cam1: DPHY RX2 -> DPHY TX0, APB slave1 (0xF811_0000),
//          I2C1 (0xF801_7000), GPIO0.bit1 -> cam_1_en
//
//  CPU 只做两件事：
//    1. I2C 配置两颗 IMX415（imx415_init(0/1)，各自 cam_en 上电时序 +
//       有界重试；GPIO 按 bit 隔离，一路重新上电不误伤另一路出流）
//    2. 两路 apb_cam_ctrl 的白平衡/bayer 相位/图案源运行时调节
//       （UART 菜单先以 '[' / ']' 选目标路，其余键只作用于目标路）
////////////////////////////////////////////////////////////////////////////

/* 每路一份 CSR 运行时状态（软件镜像，键入即写对应 APB slave） */
typedef struct {
	int wb_r, wb_g, wb_b;
	int phase, adaptive, pat_en, pat_sel;
} cam_state_t;

static cam_state_t cam_st[2] = {
	{ CAMC_DEFAULT_WB_R, CAMC_DEFAULT_WB_G, CAMC_DEFAULT_WB_B, 0, 1, 1, 0 },
	{ CAMC_DEFAULT_WB_R, CAMC_DEFAULT_WB_G, CAMC_DEFAULT_WB_B, 0, 1, 1, 0 },
};
static int cam_tgt;		/* UART 菜单当前目标：0=cam0(APB0) 1=cam1(APB1) */

/* CSR 访问：id 选路（APB slave0/slave1），唯一寄存器整字读写 */
static u32 cam_apb(int id) { return (id == 1) ? APB_1 : APB_0; }
static void CamCtrl_Wr(int id, u32 v) { write_u32(v, cam_apb(id) + CAMC_REG_CTRL); }
static u32  CamCtrl_Rd(int id)        { return read_u32(cam_apb(id) + CAMC_REG_CTRL); }

/* 组装 CTRL 字：{wb_b, wb_g, wb_r, pat_sel, pat_en, adaptive, phase} */
static u32 cam_pack(u32 phase, u32 adaptive, u32 r, u32 g, u32 b,
		    u32 pat_en, u32 pat_sel)
{
	return ((b & 0xFFu) << 24) | ((g & 0xFFu) << 16) |
	       ((r & 0xFFu) << 8) | ((pat_sel & 3u) << 4) |
	       ((pat_en & 1u) << 3) | ((adaptive & 1u) << 2) | (phase & 3u);
}

/* 把软件镜像 cam_st[id] 写进对应路的 CSR */
static void cam_apply(int id)
{
	cam_state_t *s = &cam_st[id];

	CamCtrl_Wr(id, cam_pack((u32)s->phase, (u32)s->adaptive,
				(u32)s->wb_r, (u32)s->wb_g, (u32)s->wb_b,
				(u32)s->pat_en, (u32)s->pat_sel));
}

/* 读回解包打印（确认 APB 通路 + 当前生效配置） */
static void cam_show(int id)
{
	static const char *ph[] = { "RGGB", "GRBG", "GBRG", "BGGR" };
	static const char *pt[] = { "gray", "red/blu", "horiz", "chess" };
	u32 v = CamCtrl_Rd(id);

	bsp_printf("cam%d csr 0x%x: wb %d/%d/%d adaptive=%d phase=%d(%s)"
		" src=%s pat=%s%s\r\n",
		id, (int)v,
		(int)((v >> 8) & 0xFFu), (int)((v >> 16) & 0xFFu),
		(int)((v >> 24) & 0xFFu),
		(int)((v >> 2) & 1u), (int)(v & 3u),
		ph[v & 3u],
		((v >> 3) & 1u) ? "pattern" : "camera",
		pt[(v >> 4) & 3u],
		(id == cam_tgt) ? "  <- menu target" : "");
}

static int clamp8(int v)
{
	if (v < 0)   return 0;
	if (v > 255) return 255;
	return v;
}

static void cam_menu(void)
{
	bsp_printf("menu: '['=target cam0  ']'=target cam1 (keys act on target)\r\n"
		   "      [c]amera | [p]attern | [g]ray [o] red/blu [h]oriz"
		   " chess[b]oard\r\n"
		   "      [1-4] bayer phase | [z] adaptive toggle\r\n"
		   "      [q/a] wb_r +/-16   [w/s] wb_g +/-16   [e/d] wb_b +/-16\r\n"
		   "      [x] reset defaults | [i] show both CSR | [?] help\r\n");
}

void main(void)
{
	int rc[2];
	int id, hb;
	u32 csr;

	bsp_init();
	bsp_printf("\r\n--- top_cam_demo: 2x sensor -> camera_path -> CSI-2 direct ---\r\n");

	/* 两路 APB 通路自检：复位默认 = 0xB4EBC80C（板级标定值，上电即发
	 * 灰度图案，传感器就绪前面板就有显示；写一遍默认再读回，验证的是
	 * APB slave0/slave1 两条从机通路）。*/
	for (id = 0; id < 2; id++) {
		csr = CamCtrl_Rd(id);
		bsp_printf("cam%d ctrl reset readback: 0x%x (expect 0xb4ebc80c)\r\n",
			id, (int)csr);
		cam_apply(id);
		csr = CamCtrl_Rd(id);
		if (csr != CAMC_CTRL_RESET)
			bsp_printf("ERROR: cam%d ctrl write/readback mismatch\r\n",
				id);
		cam_show(id);
	}

	/* 两颗 IMX415 上电 + I2C 配置 + 出流（cam_en 时序与 3 次有界重试在
	 * imx415_init 内；GPIO 按 bit 隔离，cam1 上电时序不打断已出流的
	 * cam0）。上电默认两路都发灰度图案，传感器就绪后 UART 发 'c' 切
	 * 相机预览，'p' 切回图案源。*/
	rc[0] = imx415_init(0);
	rc[1] = imx415_init(1);
	for (id = 0; id < 2; id++) {
		if (rc[id] == 0)
			bsp_printf("cam%d IMX415 init OK - pattern on panel,"
				" 'c' for live preview\r\n", id);
		else
			bsp_printf("cam%d IMX415 init FAILED rc=%d - pattern"
				" stays on panel\r\n", id, rc[id]);
	}

	cam_menu();

	/* 运行时调节循环：先 '[' / ']' 选目标，其余键只改目标路；CSR 写
	 * 逐拍生效，帧内即变（源切换撕裂最多 1 行）*/
	hb = 0;
	while (1) {
		bsp_uDelay(500000);		/* 0.5 s poll tick */
		while (uart_readOccupancy(BSP_UART_TERMINAL) != 0) {
			char c = (char)uart_read(BSP_UART_TERMINAL);
			cam_state_t *s = &cam_st[cam_tgt];
			int dirty = 1;

			switch (c) {
			case '[':
				cam_tgt = 0;
				dirty = 0;
				cam_show(0);
				cam_show(1);
				break;
			case ']':
				cam_tgt = 1;
				dirty = 0;
				cam_show(0);
				cam_show(1);
				break;
			case 'c': case 'C':
				s->pat_en = 0;
				break;
			case 'p': case 'P':
				s->pat_en = 1;
				break;
			case 'g': case 'G':
				s->pat_sel = 0; s->pat_en = 1;   /* 灰度竖 ramp */
				break;
			case 'o': case 'O':
				s->pat_sel = 1; s->pat_en = 1;   /* 红/蓝竖条 */
				break;
			case 'h': case 'H':
				s->pat_sel = 2; s->pat_en = 1;   /* 灰度横 ramp */
				break;
			case 'b': case 'B':
				s->pat_sel = 3; s->pat_en = 1;   /* 8x8 棋盘 */
				break;
			case '1': case '2': case '3': case '4':
				s->phase = c - '1';
				break;
			case 'z': case 'Z':
				s->adaptive = !s->adaptive;
				break;
			case 'q': s->wb_r = clamp8(s->wb_r + 16); break;
			case 'a': s->wb_r = clamp8(s->wb_r - 16); break;
			case 'w': s->wb_g = clamp8(s->wb_g + 16); break;
			case 's': s->wb_g = clamp8(s->wb_g - 16); break;
			case 'e': s->wb_b = clamp8(s->wb_b + 16); break;
			case 'd': s->wb_b = clamp8(s->wb_b - 16); break;
			case 'x': case 'X':
				s->wb_r = CAMC_DEFAULT_WB_R;
				s->wb_g = CAMC_DEFAULT_WB_G;
				s->wb_b = CAMC_DEFAULT_WB_B;
				s->phase = 0;
				s->adaptive = 1;
				break;
			case 'i': case 'I':
				cam_show(0);
				cam_show(1);
				dirty = 0;
				break;
			case '?':
				cam_menu();
				dirty = 0;
				break;
			default:
				dirty = 0;
				break;
			}
			if (dirty) {
				cam_apply(cam_tgt);
				cam_show(cam_tgt);
			}
		}
		if (++hb >= 10) {	/* 心跳 ~5 s：两路 APB 活性 + 配置回显 */
			hb = 0;
			cam_show(0);
			cam_show(1);
		}
	}
}
