#include <stdint.h>
#include "bsp.h"
#include "userDef.h"

////////////////////////////////////////////////////////////////////////////
//  main.c -- top_cam_demo 双相机 DDR 回放架构固件（v4.11，2026-10-24）
//
//  架构（v3）：2x (IMX415 -> my_csi2_rx -> camera_path[cap_t*] ->
//  frame_writer -> DDR -> frame_reader -> camera_path[rd_t*] ->
//  raw_wb -> demosaic -> rgb10_to_rgb8 -> rgb2yuv ->
//  tx_line_buf/disp_timing -> my_csi2_tx（旧称 shape，v4 起内联
//  top_cam.sv）。显示唯一来源 =
//  DDR 回放，无直通旁路；源/显示时钟 ppm 差由 frame_writer（整帧或
//  全无）+ frame_reader（显示节拍门，源快向帧界跳帧）吸收。
//
//  资源映射（top_cam_demo.sv）：
//    cam0: DPHY RX0 -> DPHY TX0, APB slave0 (0xF810_0000)
//    cam1: DPHY RX2 -> DPHY TX2, APB slave1 (0xF811_0000)
//    传感器使能/I2C：v4.11 起 RTL 固化（cam_i2c_init）——cam_en 与
//    cam_scl/sda pad 驱动源已从 SoC GPIO/I2C 切到 init 模块，上电复位
//    释放后 cam0 自启、cam1 错峰跟随（start = cam0 init_done），数据链
//    gate_ready/raw_aresetn 与 init_done 放行（doc/cam-i2c-rtl-init-plan.md）。
//    SoC I2C0/1 write 线解耦悬空，read 线保留作总线活动观测。
//
//  CPU 只做两件事：
//    1. cam_i2c_init 状态观测（DIAG3@0x0C 只读）与 rerun 触发
//       （DIAG7@0x1C sticky 位，'y' 键；Q1 评审定案：固件去 I2C 配置
//       职能、保留 debug 观测）
//    2. 两路 apb_cam_ctrl 的白平衡/bayer 相位/图案源运行时调节
//       （UART 菜单先以 '[' / ']' 选目标路，其余键只作用于目标路）
////////////////////////////////////////////////////////////////////////////

/* 桥片间隔扫频按键步进（doc/csi_bridge_gap_sweep.md，扫频中可调重编）：
 *   2026-10-19 板测第一点：g_f=10（Vtotal 2260，59.73Hz）即黑 =>
 *   桥片容差 < 0.44%，帧距步进收细到 1 tick 定位 [0..10] 内边界 */
#define GAP_FRAME_STEP	1
#define GAP_LINE_STEP	10

/* 每路一份 CSR 运行时状态（软件镜像，键入即写对应 APB slave） */
typedef struct {
	int wb_r, wb_g, wb_b;
	int phase, adaptive, pat_en, pat_sel;
	int dbg_sel;		/* CTRL[6] tx_line_buf 入口直注棋盘源（旧称
	 * shape 入口；仅 cam0 4K 路编译该源，cam1 1080 路无效） */
	int gap_line;		/* CTRL2[15:0] 直注源行间距（拍，桥片扫频） */
	int gap_frame;		/* CTRL2[31:16] 直注源帧间距（tick） */
} cam_state_t;

static cam_state_t cam_st[2] = {
	/* v5.1：{wb_r, wb_g, wb_b（影子直接 U4.12，1.0=0x1000，标定默认）,
	 * phase=0, adaptive=1, pat_en=0(上电摄像头零切换), pat_sel=1(与 RTL
	 * 复位 pat_sel=01 一致——自检 cam_apply 组装值须等于
	 * CAMC_CTRL_RESET，否则 readback mismatch), dbg_sel=0,
	 * gap_line=0, gap_frame=0} */
	{ CAMC_DEFAULT_WB_R, CAMC_DEFAULT_WB_G, CAMC_DEFAULT_WB_B,
	  0, 1, 0, 1, 0, 0, 0 },
	{ CAMC_DEFAULT_WB_R, CAMC_DEFAULT_WB_G, CAMC_DEFAULT_WB_B,
	  0, 1, 0, 1, 0, 0, 0 },
};
static int cam_tgt;		/* UART 菜单当前目标：0=cam0(APB0) 1=cam1(APB1) */
static int hb_en = 1;		/* 0.5s 心跳打印开关（'f' 切换；默认开 =
				白平衡调试期，稳定后可关避免刷屏） */

/* CSR 访问：id 选路（APB slave0/slave1），唯一寄存器整字读写 */
static u32 cam_apb(int id) { return (id == 1) ? APB_1 : APB_0; }
static void CamCtrl_Wr(int id, u32 v) { write_u32(v, cam_apb(id) + CAMC_REG_CTRL); }
static u32  CamCtrl_Rd(int id)        { return read_u32(cam_apb(id) + CAMC_REG_CTRL); }
static u32  CamDiag4_Rd(int id)       { return read_u32(cam_apb(id) + CAMC_REG_DIAG4); }
static u32  CamDiag5_Rd(int id)       { return read_u32(cam_apb(id) + CAMC_REG_DIAG5); }
static u32  CamDiag8_Rd(int id)       { return read_u32(cam_apb(id) + CAMC_REG_DIAG8); }
static u32  CamDiag9_Rd(int id)       { return read_u32(cam_apb(id) + CAMC_REG_DIAG9); }
static u32  CamDiag11_Rd(int id)      { return read_u32(cam_apb(id) + CAMC_REG_DIAG11); }
static u32  CamDiag12_Rd(int id)      { return read_u32(cam_apb(id) + CAMC_REG_DIAG12); }
static u32  CamDiag13_Rd(int id)      { return read_u32(cam_apb(id) + CAMC_REG_DIAG13); }
static u32  CamDiag14_Rd(int id)      { return read_u32(cam_apb(id) + CAMC_REG_DIAG14); }
static u32  CamDiag15_Rd(int id)      { return read_u32(cam_apb(id) + CAMC_REG_DIAG15); }
static u32  CamDiag3_Rd(int id)       { return read_u32(cam_apb(id) + CAMC_REG_DIAG3); }

/* 组装 CTRL 字：{wb_b, wb_g, wb_r, 1'b0, dbg_sel, pat_sel, pat_en,
 * adaptive, phase}。v5 起 wb 字段退役（wb_axis 退出路径）恒 0x40 占位，
 * 实际增益走 WB_RAW0/1（cam_apply 尾部写入）；bit7 无消费者
 * （replay_pat_gen 已拆除，CTRL[7] 保留位布局恒 0）。 */
#define CAMC_WB_RETIRED	0x40u
static u32 cam_pack(u32 phase, u32 adaptive,
		    u32 pat_en, u32 pat_sel, u32 dbg_sel)
{
	return (CAMC_WB_RETIRED << 24) | (CAMC_WB_RETIRED << 16) |
	       (CAMC_WB_RETIRED << 8) |
	       ((dbg_sel & 1u) << 6) |
	       ((pat_sel & 3u) << 4) |
	       ((pat_en & 1u) << 3) | ((adaptive & 1u) << 2) | (phase & 3u);
}

/* 把软件镜像 cam_st[id] 写进对应路的 CSR */
static void cam_apply(int id)
{
	cam_state_t *s = &cam_st[id];

	CamCtrl_Wr(id, cam_pack((u32)s->phase, (u32)s->adaptive,
				(u32)s->pat_en, (u32)s->pat_sel,
				(u32)s->dbg_sel));
	/* CTRL2：直注源行/帧间距（0 = 无附加间隔 = 60.000Hz 基线） */
	write_u32((((u32)s->gap_frame & 0xFFFFu) << 16) |
		  ((u32)s->gap_line & 0xFFFFu),
		  cam_apb(id) + CAMC_REG_CTRL2);
	/* WB_RAW0/1（v5.1）：影子直接 U4.12（1.0=0x1000）免移位直写；
	 * WB_RAW0={wb_g_raw, wb_r_raw}，WB_RAW1=wb_b_raw */
	write_u32((((u32)s->wb_g & 0xFFFFu) << 16) |
		  ((u32)s->wb_r & 0xFFFFu),
		  cam_apb(id) + CAMC_REG_WB_RAW0);
	write_u32((u32)s->wb_b & 0xFFFFu,
		  cam_apb(id) + CAMC_REG_WB_RAW1);
}

/* gap 状态打印（每次 u/j/n/m 后）：行周期/Htotal/帧率换算即时可读，
 * 黑屏瞬间终端最后一行即肇事值（CPU/UART 与视频通路独立） */
static void gap_show(int id)
{
	cam_state_t *s = &cam_st[id];
	u32 lp = 1100u + (u32)s->gap_line;		/* 行周期（拍）*/
	u32 fp = 2160u * lp + (90u + (u32)s->gap_frame) * 1100u;
	u32 fps = fp ? (148500000u / fp) : 0;

	bsp_printf("gap: line=%d(%dns,Htot=%dpx) frame=%d fps~%d\r\n",
		   s->gap_line, (int)(lp * 6734u / 1000u),
		   (int)(lp * 4u), s->gap_frame, (int)fps);
}

/* 读回打印（确认 APB 通路 + 当前生效配置）。历史多代 diag dump
 * （DIAG2/6/7/10 全量解码等）随 RTL dbg 清理一并删除（2026-10-19） */
static void cam_show(int id)
{
	bsp_printf("cam%d ctrl=0x%x ctrl2=0x%x\r\n", id, (int)CamCtrl_Rd(id),
		   (int)read_u32(cam_apb(id) + CAMC_REG_CTRL2));
	bsp_printf("cam%d wb_raw0=0x%x(wb_raw1=0x%x) sat=%d\r\n", id,
		   (int)read_u32(cam_apb(id) + CAMC_REG_WB_RAW0),
		   (int)read_u32(cam_apb(id) + CAMC_REG_WB_RAW1),
		   (int)read_u32(cam_apb(id) + CAMC_REG_DIAG21) & 0xFFFF);
}

/* cam_i2c_init 状态观测（v4.11：RTL 固化配置，固件只读；位布局见
 * apb_cam_ctrl.sv DIAG3 注释。v4.11b 加 en/scl/sda pad 读回判别） */
static void cam_i2c_show(int id)
{
	u32 d = CamDiag3_Rd(id);

	bsp_printf("cam%d i2c: %s idx=%d retry=%d round=%d en=%d scl=%d sda=%d\r\n",
		   id,
		   ((d >> 16) & 1u) ? "FAIL" :
		   (((d >> 15) & 1u) ? "done" :
		    (((d >> 14) & 1u) ? "busy" : "idle")),
		   (int)(d & 0xFFu), (int)((d >> 8) & 0xFu),
		   (int)((d >> 12) & 3u),
		   (int)((d >> 19) & 1u), (int)((d >> 17) & 1u),
		   (int)((d >> 18) & 1u));
}

/* rerun 触发（DIAG7 sticky 位：写 1 出沿启动重配置，延时后写 0 归位，
 * 等下次触发） */
static void cam_i2c_rerun(int id)
{
	write_u32(1u, cam_apb(id) + CAMC_REG_DIAG7);
	bsp_uDelay(1000);
	write_u32(0u, cam_apb(id) + CAMC_REG_DIAG7);
	bsp_printf("cam%d i2c rerun triggered (DIAG3 poll with '0')\r\n", id);
}

/* 白平衡心跳行：两路增益影子按 U4.12 十六进制打印（1.0=0x1000，读数即
 * CSR 回写值），'*' 标当前 UART 目标路；sat=RAW10 域饱和拍计数（DIAG21，
 * 累计 16bit，增量快 = 增益过大画面削顶） */
static void wb_show(void)
{
	int id;

	for (id = 0; id < 2; id++) {
		cam_state_t *s = &cam_st[id];
		bsp_printf("wb%d%s: r=0x%x g=0x%x b=0x%x (U4.12, 1.0=0x1000) sat=%d\r\n",
			id, (id == cam_tgt) ? "*" : "",
			(int)s->wb_r, (int)s->wb_g, (int)s->wb_b,
			(int)(read_u32(cam_apb(id) + CAMC_REG_DIAG21) & 0xFFFFu));
	}
}

/* frame_writer 心跳（DIAG12/13 @0x30/0x34，读 cam0）：frm=已完成帧（sof 计数），
 * ln=当前帧行号；ovf=启动欠账冻结值（继续增长=写吞吐不足）；pad=VACT 外盈余行 */
static void fw_show(void)
{
	u32 fw12 = CamDiag12_Rd(0);
	u32 fw13 = CamDiag13_Rd(0);
	u32 rd14 = CamDiag14_Rd(0);
	u32 rd15 = CamDiag15_Rd(0);
	bsp_printf("fw: frm=%d ln=%d ovf=%d pad=%d\r\n",
		(int)((fw12 >> 16) & 0xFFFFu), (int)(fw12 & 0xFFFFu),
		(int)((fw13 >> 16) & 0xFFFFu), (int)(fw13 & 0xFFFFu));
	/* 回放读链路（DIAG14/15 现行布局，frame_reader 端口/rd_err 实宽
	 * 16/4/12 + 8/8/8/8）：frm=reader 发射帧数；ln=帧内行进度（12bit）；
	 * late=tick 拍数据未就绪延迟发射（设计内）；miss=快向跳帧请求
	 * 未消费沿；err=AXI 收字错账（短突发/行账不符/超长无 rlast）；
	 * req=frame_req 沿计数（对照 fw.frm 判读源侧吞帧） */
	bsp_printf("rd: frm=%d ln=%d | late=%d miss=%d err=%d req=%d\r\n",
		(int)((rd14 >> 16) & 0xFFFFu), (int)(rd14 & 0xFFFu),
		(int)((rd15 >> 24) & 0xFFu), (int)((rd15 >> 16) & 0xFFu),
		(int)((rd15 >> 8) & 0xFFu), (int)(rd15 & 0xFFu));
	/* 回放流帧锚定（DIAG17 @0x44）：sof 清零重启、下一 sof 锁存，读数 =
	 * 上一帧 reader 发射流的 tlast 数与 sol 数，静态可读。应恒
	 * 2160/2160；非 0 即回放行数残缺 */
	u32 d17 = read_u32(cam_apb(0) + CAMC_REG_DIAG17);
	bsp_printf("fr: rd=%d/%d (tlast/sol per frame)\r\n",
		(int)(d17 >> 16), (int)(d17 & 0xFFFFu));
	/* v4（DIAG16/19 复用槽）：d16 = rd 口节拍直证 {rd_sol, rd_beat}（自由
	 * 跑，滚动=reader->camera_path 通路活）；d19 = reader 帧仲裁
	 * {drop[15:0], repeat[15:0]}——drop 增长=源快向跳帧（正常吸收），
	 * repeat 增长=慢向重放；两者皆 0 增长 = 授权停滞（帧率根因） */
	u32 d16 = read_u32(cam_apb(0) + CAMC_REG_DIAG16);
	u32 d19 = read_u32(cam_apb(0) + CAMC_REG_DIAG19);
	bsp_printf("v4: beat=%d sol=%d | drop=%d rpt=%d\r\n",
		(int)(d16 & 0xFFFFu), (int)((d16 >> 16) & 0xFFFFu),
		(int)((d19 >> 16) & 0xFFFFu), (int)(d19 & 0xFFFFu));
	/* fw 输入侧帧纪律异常（DIAG20 @0x50，现行布局）：abandon=坏帧弃用
	 * 数（队满污染/帧中 sof 异常重启，关帧不翻 par => reader 不读坏
	 * 帧）；short=短帧行数；ab_beat=最近弃帧已收 beat 数低 8 位。
	 * 读数静态，无需增量换算 */
	u32 d20 = read_u32(cam_apb(0) + CAMC_REG_DIAG20);
	bsp_printf("fw2: abandon=%d short=%d ab_beat=%d\r\n",
		(int)((d20 >> 16) & 0xFFFFu), (int)((d20 >> 8) & 0xFFu),
		(int)(d20 & 0xFFu));
	/* DDR 控制器状态（DIAG11 @0x2C，读 cam0）：
	 * {err_cnt, mcst[15:12], 5'h0, done_raw[6], st[5:4], lock[3],
	 *  cfg_ok[2], done[1], fail[0]}——writer 卡行/楔死时首查点：
	 * lock/cfg_ok 应恒 1，st 应在常态；err 增长 = 总线层问题。
	 * （2026-10-20 修正：RTL 拼接 {err_cnt, mcst, ...} 首元素在高位，
	 *  err 在 [31:16]；旧打印按 [15:0] 读，读到的 124 实为低位状态
	 *  字节 {CFG_DONE=1, st=3, lock=1, cfg_ok=1} = 0x7C） */
	u32 d11 = CamDiag11_Rd(0);
	bsp_printf("ddr: err=%d st=%d raw=%d lock=%d cfg=%d done=%d fail=%d\r\n",
		(int)((d11 >> 16) & 0xFFFFu), (int)((d11 >> 4) & 3u),
		(int)((d11 >> 6) & 1u), (int)((d11 >> 3) & 1u),
		(int)((d11 >> 2) & 1u), (int)((d11 >> 1) & 1u),
		(int)(d11 & 1u));
	/* cam1 回放链心跳（阶段5，2026-10-24，全部读 APB slave1）：u_fw1/
	 * u_rd1 与 cam0 同 CSR 布局，但几何 = 1080p 回放（VACT 1080 行/
	 * 行 480 拍/LINE_STRIDE 4KB）。判读口径：
	 *   fw1 frm 0.5s 增量 ≈ +31（与 cam0 fw 同为 60fps 域拍节）；
	 *   rd1 frm/late/miss/err/req 与 cam0 rd 同义；
	 *   fr1 应恒 1080/1080（回放行数残缺即非 0 偏差）；
	 *   ddr1 lock/cfg 应恒 1（cam1 侧 DDR 摄取健康）。 */
	u32 fw12_1 = CamDiag12_Rd(1);
	u32 fw13_1 = CamDiag13_Rd(1);
	u32 rd14_1 = CamDiag14_Rd(1);
	u32 rd15_1 = CamDiag15_Rd(1);
	u32 d17_1 = read_u32(cam_apb(1) + CAMC_REG_DIAG17);
	u32 d19_1 = read_u32(cam_apb(1) + CAMC_REG_DIAG19);
	bsp_printf("fw1: frm=%d ln=%d ovf=%d pad=%d\r\n",
		(int)((fw12_1 >> 16) & 0xFFFFu), (int)(fw12_1 & 0xFFFFu),
		(int)((fw13_1 >> 16) & 0xFFFFu), (int)(fw13_1 & 0xFFFFu));
	bsp_printf("rd1: frm=%d ln=%d | late=%d miss=%d err=%d req=%d\r\n",
		(int)((rd14_1 >> 16) & 0xFFFFu), (int)(rd14_1 & 0xFFFu),
		(int)((rd15_1 >> 24) & 0xFFu), (int)((rd15_1 >> 16) & 0xFFu),
		(int)((rd15_1 >> 8) & 0xFFu), (int)(rd15_1 & 0xFFu));
	bsp_printf("fr1: rd=%d/%d (tlast/sol, expect 1080) | drop=%d rpt=%d\r\n",
		(int)(d17_1 >> 16), (int)(d17_1 & 0xFFFFu),
		(int)((d19_1 >> 16) & 0xFFFFu), (int)(d19_1 & 0xFFFFu));
	/* rate1（DIAG4 @APB1，top_cam 内部 per-cam 计数非 ddr_diag 组）：
	 * fw_sof 增量 +0/+1 = 断流，+30/0.5s = cam1 raw 源满速（cap 口活
	 * → fw1 零活动即顶层连线问题）；u_cam_1 的 DIAG11 本就 tie 0
	 * （不挂 DDR 自检），ddr1 状态不可判读，不打印。 */
	u32 d4_1 = CamDiag4_Rd(1);
	u32 d5_1 = CamDiag5_Rd(1);
	u32 d18_1 = read_u32(cam_apb(1) + CAMC_REG_DIAG18);
	bsp_printf("rate1: fw_sof=%d dms_sol=%d | yuvfrm=%d | df=%d live=%d\r\n",
		(int)((d4_1 >> 16) & 0xFFFFu), (int)(d4_1 & 0xFFFFu),
		(int)(d5_1 & 0xFFFFu),
		(int)((d18_1 >> 24) & 0xFFu), (int)(d18_1 & 0xFFFFFFu));
	/* 自由跑速率（DIAG4 @0x10，16bit 回绕增量）：dms=demosaic 出口
	 * sol/行率（满速 129.6k 行/s => 16bit 圈增量 1424±漂移，mod-65536
	 * 混叠判读，2026-10-19 结论）；fwsof=raw 源 sof 率（v2 起 fw 直吃
	 * raw，aclk 域；+0/+1=断流，+60/s=满速）。与 DIAG5 frm_cnt 对照
	 * = 源/显示真实帧率差（ppm 判据） */
	u32 d4 = read_u32(cam_apb(0) + CAMC_REG_DIAG4);
	bsp_printf("rate: dms_sol=%d fw_sof=%d (free-run delta)\r\n",
		(int)(d4 & 0xFFFFu), (int)((d4 >> 16) & 0xFFFFu));
	/* 流水线全程吞吐（DIAG5 @0x14，2026-10-19 位序修正：RTL 拼接
	 * {yuv_v_cnt, frm_cnt} 高位在前，旧打印两字段接反）。yuv_v=rgb2yuv
	 * 出口有效拍率（满速 ~124M 拍/s，16bit 每秒回绕 ~1900 圈，读数纯
	 * 混叠噪声，仅判"在动"）；frm=shape vsync 帧计数（0.5s 采样窗
	 * +30 = 60Hz、+28 = 55.7Hz——显示帧率速读，精确值看 cnt.df） */
	u32 d5 = CamDiag5_Rd(0);
	bsp_printf("yuv: yuv_v=%d frm=%d (free-run delta)\r\n",
		(int)((d5 >> 16) & 0xFFFFu), (int)(d5 & 0xFFFFu));
	/* 显示侧实测（DIAG18 @0x48，2026-10-19 绝对窗口版）：0.75s 固定窗
	 * （111,375,000 pixel_clk）硬件锁存，绝对值免采样换算——
	 * df=窗内 shape 出帧数：45=60.00Hz（桥片应锁）/ 42=56Hz / 22=30Hz
	 * （非标 = "无输入信号"根因）；live=窗内 shape 入口非零内容拍 ÷64
	 * （2026-10-20 RTL 预分频：满速 93.3M/窗 24bit 会回绕），满速
	 * 1458000（内容活），恒 0 = 全黑内容 */
	u32 d18 = read_u32(cam_apb(0) + CAMC_REG_DIAG18);
	bsp_printf("cnt: df=%d/45 live=%d/1458000 (0.75s win)\r\n",
		(int)((d18 >> 24) & 0xFFu), (int)(d18 & 0xFFFFFFu));
	/* 显示链黑匣子（tx_line_buf/disp_timing，旧称 shape，v4 起内联
	 * top_cam.sv；现行 RTL 布局）：
	 *   DIAG8 = {srch[31:24], lvl[23:16], 16'h0}
	 *   srch=rsync 逐字搜索启动次数（行对齐破坏频率，稳态应恒 0）；
	 *   lvl=tx_line_buf 水位快照 used>>9（8192 深，16=满）
	 *   DIAG9 = {8'h0, 8'h0, underrun[15:8], df[7], vfs[6],
	 *   vst[2:0], hst[2:0]}——underrun=Vback 门停留次数（源慢向吸收速
	 *   率）、df=门内出帧、vfs=vsync 期、vst/hst=读侧状态机快照
	 * 注意：本 BSP printf 不支持 %u（走浮点分支致参数错位），必须用 %d */
	u32 shp8 = CamDiag8_Rd(0);
	u32 shp9 = CamDiag9_Rd(0);
	bsp_printf("shp: srch=%d lvl=%d | uflow=%d df=%d vfs=%d vst=%d hst=%d\r\n",
		(int)((shp8 >> 24) & 0xFFu), (int)((shp8 >> 16) & 0xFFu),
		(int)((shp9 >> 8) & 0xFFu),
		(int)((shp9 >> 7) & 1u), (int)((shp9 >> 6) & 1u),
		(int)((shp9 >> 3) & 7u), (int)(shp9 & 7u));
}

static int clamp16(int v)
{
	if (v < 0)     return 0;
	if (v > 65535) return 65535;
	return v;
}

static void cam_menu(void)
{
	bsp_printf("menu: '['=target cam0  ']'=target cam1 (keys act on target)\r\n"
		   "      [c]amera | [g]ray [o] red/blu [h]oriz"
		   " chess[b]oard (pattern keys also enable pat)\r\n"
		   "      [v] tx_line_buf-entry dbg pattern (cam0 4K only)\r\n"
		   "      [f] heartbeat print on/off (1s diag)\r\n"
		   "      [u/j] frame-gap +/-1tick  [n/m] line-gap +/-10beat"
		   " (v-mode sweep)\r\n"
		   "      [1-4] bayer phase | [z] adaptive toggle\r\n"
		   "      [q/a] wb_r +/-64   [w/s] wb_g +/-64   [e/d] wb_b +/-64"
		   " (RAW10 U4.12, 1.0=0x1000, max 1600%)\r\n"
		   "      [x] reset defaults | [i] show both CSR | [?] help\r\n"
		   "      [0] cam i2c init status (RTL, DIAG3)"
		   "  [y] cam i2c rerun (target, DIAG7)\r\n");
}

void main(void)
{
	int id, hb;
	u32 csr;

	bsp_init();
	bsp_printf("\r\n--- top_cam_demo: 2x sensor -> camera_path -> CSI-2 direct ---\r\n");

	/* 两路 APB 通路自检：复位默认 = 0x40404014（v5：wb 退役 0x40x3、
	 * pat_en=0 上电即摄像头零切换，与硬件 pat_sel_eff 复位态一致；写
	 * 一遍默认再读回，验证的是 APB slave0/slave1 两条从机通路）。*/
	for (id = 0; id < 2; id++) {
		csr = CamCtrl_Rd(id);
		bsp_printf("cam%d ctrl reset readback: 0x%x (expect 0x40404014)\r\n",
			id, (int)csr);
		cam_apply(id);
		csr = CamCtrl_Rd(id);
		if (csr != CAMC_CTRL_RESET)
			bsp_printf("ERROR: cam%d ctrl write/readback mismatch\r\n",
				id);
		cam_show(id);
	}

	/* v4.11：IMX415 上电时序与 142 条配置已 RTL 固化（cam_i2c_init），
	 * 复位释放后 cam0 自启、cam1 错峰跟随，固件零参与。数据链由
	 * gate_ready/raw_aresetn 与 init_done 放行——无需固件等待/兜底
	 * （init 失败重试耗尽时 FAIL sticky，'y' rerun 可恢复；'g/o/h/b'
	 * 图案兜底照旧可用）。这里只打印当前配置进度。*/
	cam_i2c_show(0);
	cam_i2c_show(1);

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
			int gap_key = 0;

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
			case 'v': case 'V':
				s->dbg_sel = !s->dbg_sel; /* tx_line_buf 入口
						直注棋盘源开关（仅 cam0 4K 路
						编译该源，cam1 1080 路按此键
						无效；硬件检测变化沿自动软复
						位重启） */
				break;
			case 'f': case 'F':
				hb_en = !hb_en;
				bsp_printf("heartbeat: %s\r\n",
					hb_en ? "on" : "off");
				dirty = 0;
				break;
			case 'u': case 'U':		/* 帧间距 +（'v' 扫频用）*/
				s->gap_frame = (s->gap_frame >
					65535 - GAP_FRAME_STEP) ?
					65535 : s->gap_frame + GAP_FRAME_STEP;
				gap_key = 1;
				break;
			case 'j': case 'J':		/* 帧间距 - */
				s->gap_frame = (s->gap_frame > GAP_FRAME_STEP) ?
					s->gap_frame - GAP_FRAME_STEP : 0;
				gap_key = 1;
				break;
			case 'n': case 'N':		/* 行间距 + */
				s->gap_line = (s->gap_line >
					65535 - GAP_LINE_STEP) ?
					65535 : s->gap_line + GAP_LINE_STEP;
				gap_key = 1;
				break;
			case 'm': case 'M':		/* 行间距 - */
				s->gap_line = (s->gap_line > GAP_LINE_STEP) ?
					s->gap_line - GAP_LINE_STEP : 0;
				gap_key = 1;
				break;
			case '1': case '2': case '3': case '4':
				s->phase = c - '1';
				break;
			case 'z': case 'Z':
				s->adaptive = !s->adaptive;
				break;
			case 'q': case 'Q':
				s->wb_r = clamp16(s->wb_r + 64); break;
			case 'a': case 'A':
				s->wb_r = clamp16(s->wb_r - 64); break;
			case 'w': case 'W':
				s->wb_g = clamp16(s->wb_g + 64); break;
			case 's': case 'S':
				s->wb_g = clamp16(s->wb_g - 64); break;
			case 'e': case 'E':
				s->wb_b = clamp16(s->wb_b + 64); break;
			case 'd': case 'D':
				s->wb_b = clamp16(s->wb_b - 64); break;
			case 'x': case 'X':
				s->wb_r = CAMC_DEFAULT_WB_R;
				s->wb_g = CAMC_DEFAULT_WB_G;
				s->wb_b = CAMC_DEFAULT_WB_B;
				s->phase = 0;
				s->adaptive = 1;
				s->gap_line = 0;	/* 回 60.000Hz 基线 */
				s->gap_frame = 0;
				break;
			case 'i': case 'I':
				cam_show(0);
				cam_show(1);
				dirty = 0;
				break;
			case '0':
				cam_i2c_show(0);
				cam_i2c_show(1);
				dirty = 0;
				break;
			case 'y': case 'Y':
				cam_i2c_rerun(cam_tgt);
				dirty = 0;
				break;
			case '?':
				cam_menu();
				dirty = 0;
				break;
			default:
				dirty = 0;
				/* 未知键回显 hex：大写锁定/输入法全角等
				 * 输入异常一按即暴露（调试期保留） */
				bsp_printf("key 0x%x ignored\r\n",
					(int)(unsigned char)c);
				break;
			}
			if (dirty) {
				cam_apply(cam_tgt);
				if (gap_key)
					gap_show(cam_tgt);
				else
					cam_show(cam_tgt);
			}
		}
		if (++hb >= 2) {	/* 心跳 = 2 圈（1s 打印周期；0.5s 圈仍轮询按
			 * 键，'f' 可关）。注意：16bit 自由跑字段（rate/
			 * yuv）在 1s 窗口回绕 2 圈纯混叠，仅判"在动"，
			 * 精确测率时临时切回 hb>=1 或用 cnt 绝对窗 */
			hb = 0;
			if (hb_en) {
				fw_show();
				wb_show();
			}
		}
	}
}
