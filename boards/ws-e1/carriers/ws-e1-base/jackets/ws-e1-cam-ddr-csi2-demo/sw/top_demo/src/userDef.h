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
/* CTRL @0x00 是唯一寄存器（paddr[2]=0，整字读写）：
 *   [1:0]   bayer_phase  0=RGGB 1=GRBG 2=GBRG 3=BGGR（IMX415 标定 0）
 *   [2]     adaptive     demosaic R/B 站点 G 方向自适应
 *   [15:8]  wb_r         白平衡增益（Q8.8 高 8 位整数档）
 *   [23:16] wb_g
 *   [31:24] wb_b
 * 复位默认 0xB4EBC80C = wb 180/235/200 + pat_en=1(上电发灰度图案) +
 * adaptive=1 + phase=0(RGGB)，
 * 上电不写即出像；写入对流水线逐拍生效（帧内即变，无帧边界等待）。 */
#define CAMC_REG_CTRL		0x00
#define CAMC_CTRL_RESET		0xB4EBC80Cu
#define CAMC_DEFAULT_WB_R	200
#define CAMC_DEFAULT_WB_G	235
#define CAMC_DEFAULT_WB_B	180

#endif
