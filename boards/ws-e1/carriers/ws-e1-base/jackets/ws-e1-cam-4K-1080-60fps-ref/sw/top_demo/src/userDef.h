#ifndef USERDEF_H_
#define USERDEF_H_

#include "soc.h"

/************************** Hardware Header File ***************************/
#define UART_0				SYSTEM_UART_0_IO_CTRL
#define APB_0				IO_APB_SLAVE_0_INPUT	/* apb_cam_ctrl cam0 */
#define APB_1				IO_APB_SLAVE_1_INPUT	/* apb_cam_ctrl cam1 */
/* top_cam_demo 双相机：APB slave0/slave1 分别挂 cam0/cam1 的 apb_cam_ctrl
 * （寄存器组相同）；slave2/3 仍为 dummy 即答，软件不访问。 */

/**************** apb_cam_ctrl (APB slave 0/1，cam0/cam1 各一份) *****************/
/* CTRL @0x00（v5 起仅低 8 位生效）：
 *   [1:0]   bayer_phase  0=RGGB 1=GRBG 2=GBRG 3=BGGR（IMX415 标定 0）
 *   [2]     adaptive     demosaic R/B 站点 G 方向自适应
 *   [15:8]  wb_r         （v5 退役占位：wb_axis 退出路径，固定 0x40；
 *   [23:16] wb_g           实际增益走 WB_RAW0/1，软件影子里程见下）
 *   [31:24] wb_b
 * 复位默认 0x40404014（v5：wb 退役 0x40x3 + pat_en=0 上电摄像头零切换 +
 * adaptive=1 + phase=0(RGGB)），
 * 上电不写即出像；写入对流水线逐拍生效（帧内即变，无帧边界等待）。 */
#define CAMC_REG_CTRL		0x00
#define CAMC_REG_DIAG		0x04   /* 只读：DIAG1 退役（top_cam 恒 0 占位，
					   旧 CDC FIFO lost/level 语义已废）*/
#define CAMC_REG_CTRL2		0x08   /* 读写：[15:0]行间距(拍) [31:16]帧间距(tick)
					   直注源桥片间隔扫频（复位 0，见
					   doc/csi_bridge_gap_sweep.md）*/
#define CAMC_REG_DIAG3		0x0C   /* 只读 v4.11 复用：cam_i2c_init 观测
					   {fail[16], done[15], busy[14],
					    round[13:12], retry[11:8], idx[7:0]}
					   （v4.10 raw 断流定位槽已退役）*/
#define CAMC_REG_DIAG4		0x10   /* 只读：{fw_sof_free[15:0], dms_sol_free[15:0]} 自由跑速率 */
#define CAMC_REG_DIAG5		0x14   /* 只读：{yuv_v_cnt[15:0], frm_cnt[15:0]} */
#define CAMC_REG_DIAG6		0x18   /* 只读：退役（恒 0，旧 rx_pixel_valid 拍数）*/
#define CAMC_REG_DIAG7		0x1C   /* 读写 v4.11 复用：cam_i2c rerun
					   sticky [1:0]（写 1 触发本路重配置，
					   写 0 归位；v4.10 rx DT/vs/hs 槽已
					   退役）*/
#define CAMC_REG_DIAG8		0x20   /* 只读：shape dbg_mon {srch[31:24], lvl[23:16], 16'h0} */
#define CAMC_REG_DIAG9		0x24   /* 只读：shape 读侧 {8'h0, 8'h0, underrun[15:8], df[7], vfs[6], vst[2:0], hst[2:0]} */
#define CAMC_REG_DIAG10		0x28   /* 只读：退役（恒 0，旧帧行数记录仪）*/
#define CAMC_REG_DIAG11		0x2C   /* 只读：DDR 自检 {err_cnt[15:0], mcst[15:12], 5'h0, done_raw[6], st[5:4], lock[3], cfg_ok[2], done[1], fail[0]}（读 cam0）*/
#define CAMC_REG_DIAG12		0x30   /* 只读：frame_writer {frame_cnt[15:0], line_cnt[15:0]}（读 cam0）*/
#define CAMC_REG_DIAG13		0x34   /* 只读：frame_writer {ovf_cnt[15:0], pad_cnt[15:0]}（读 cam0）*/
#define CAMC_REG_DIAG14		0x38   /* 只读：frame_reader {frame_cnt[15:0], state[3:0], line[11:0]}（读 cam0）*/
#define CAMC_REG_DIAG15		0x3C   /* 只读：frame_reader rd_err {late[7:0], miss[7:0], err[7:0], req[7:0]}（读 cam0；
					   旧注释 {4'h0,state,under,late,gen_frames} 系 v3 replay_pat_gen 时代残留）*/
#define CAMC_REG_DIAG16		0x40   /* 只读 v4 复用：回放口节拍直证 {rd_sol[15:0], rd_beat[15:0]}（读 cam0）*/
#define CAMC_REG_DIAG17		0x44   /* 只读：rd 回放流帧锚定 {tlast[15:0], sol[15:0]}/帧（读 cam0）*/
#define CAMC_REG_DIAG18		0x48   /* 只读：显示侧 0.75s 绝对窗 {df_win[7:0], live_win[23:0]}（读 cam0）*/
#define CAMC_REG_DIAG19		0x4C   /* 只读 v4 复用：reader {drop[15:0], repeat[15:0]}（读 cam0）*/
#define CAMC_REG_DIAG20		0x50   /* 只读：fw 输入侧异常 {abandon[15:0], short[7:0], ab_beat[7:0]}（读 cam0）*/
#define CAMC_REG_WB_RAW0	0x54   /* 读写 v5 新增：RAW10 域白平衡 U4.12（1.0=0x1000）
					   [15:0] wb_r_raw  [31:16] wb_g_raw（复位 1.0x2）*/
#define CAMC_REG_WB_RAW1	0x58   /* 读写 v5 新增：[15:0] wb_b_raw（复位 1.0）*/
#define CAMC_REG_DIAG21		0x5C   /* 只读 v5 新增：{16'h0, raw_wb 饱和拍计数[15:0]} */
#define CAMC_CTRL_RESET		0x40404014u	/* v5: wb 退役 0x40x3, pat_en=0 上电摄像头零切换 */
/* 白平衡软件影子里程（v5.1：直接 U4.12，1.0 = 0x1000 = 4096）：
 * q/a/w/s/e/d 键 ±64 ≈ ±1/64 倍；写 CSR 免移位直写，可调范围
 * 0~0xFFFF（≈0~1600%，硬件 16bit 全开）。
 * 默认 = 2026-10-24 板级标定基准（R 0x6a80 / G 0x4e00 / B 0x5e40，
 * 与 RTL WB_RAW0/1 复位值一致），'x' 键复位回此基准继续微调。 */
#define CAMC_DEFAULT_WB_R	0x6A80
#define CAMC_DEFAULT_WB_G	0x4E00
#define CAMC_DEFAULT_WB_B	0x5E40

#endif
