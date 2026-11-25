////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2013-2022 Efinix Inc. All rights reserved.              
//
// This   document  contains  proprietary information  which   is        
// protected by  copyright. All rights  are reserved.  This notice       
// refers to original work by Efinix, Inc. which may be derivitive       
// of other work distributed under license of the authors.  In the       
// case of derivative work, nothing in this notice overrides the         
// original author's license agreement.  Where applicable, the           
// original license agreement is included in it's original               
// unmodified form immediately below this header.                        
//                                                                       
// WARRANTY DISCLAIMER.                                                  
//     THE  DESIGN, CODE, OR INFORMATION ARE PROVIDED “AS IS” AND        
//     EFINIX MAKES NO WARRANTIES, EXPRESS OR IMPLIED WITH               
//     RESPECT THERETO, AND EXPRESSLY DISCLAIMS ANY IMPLIED WARRANTIES,  
//     INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF          
//     MERCHANTABILITY, NON-INFRINGEMENT AND FITNESS FOR A PARTICULAR    
//     PURPOSE.  SOME STATES DO NOT ALLOW EXCLUSIONS OF AN IMPLIED       
//     WARRANTY, SO THIS DISCLAIMER MAY NOT APPLY TO LICENSEE.           
//                                                                       
// LIMITATION OF LIABILITY.                                              
//     NOTWITHSTANDING ANYTHING TO THE CONTRARY, EXCEPT FOR BODILY       
//     INJURY, EFINIX SHALL NOT BE LIABLE WITH RESPECT TO ANY SUBJECT    
//     MATTER OF THIS AGREEMENT UNDER TORT, CONTRACT, STRICT LIABILITY   
//     OR ANY OTHER LEGAL OR EQUITABLE THEORY (I) FOR ANY INDIRECT,      
//     SPECIAL, INCIDENTAL, EXEMPLARY OR CONSEQUENTIAL DAMAGES OF ANY    
//     CHARACTER INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS OF      
//     GOODWILL, DATA OR PROFIT, WORK STOPPAGE, OR COMPUTER FAILURE OR   
//     MALFUNCTION, OR IN ANY EVENT (II) FOR ANY AMOUNT IN EXCESS, IN    
//     THE AGGREGATE, OF THE FEE PAID BY LICENSEE TO EFINIX HEREUNDER    
//     (OR, IF THE FEE HAS BEEN WAIVED, $100), EVEN IF EFINIX SHALL HAVE 
//     BEEN INFORMED OF THE POSSIBILITY OF SUCH DAMAGES.  SOME STATES DO 
//     NOT ALLOW THE EXCLUSION OR LIMITATION OF INCIDENTAL OR            
//     CONSEQUENTIAL DAMAGES, SO THIS LIMITATION AND EXCLUSION MAY NOT   
//     APPLY TO LICENSEE.                                                
//
////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>
#include "bsp.h"
#include "tseDemo.h"
#include "common.h"
#include "efx_tse_mac.h"
#include "uart.h"        //G5：uart_readOccupancy/uart_read 非阻塞命令行



//YT8531 完整驱动（移植自 LOOPBACK 测通工程，Linux motorcomm.c 模型）
#include "yt8531fd.h"

//阶段2 网络服务：ARP/ICMP 应答（G3/G4）
#include "net_config.h"
#include "eth_frame.h"
#include "arp.h"
#include "icmp.h"
////////////////////////////////////////////////////////////////////////////////
// 运行时模式切换（2026-11-06：PC 经 UDP 10006 即时切换，免重编译上板）
//   '0'..'3'  RAW10 图案模式（0x208[5:4]，由 200M 域图案源 raw10_pat_src 消费）
//   't'       G6 递增线速流（debug 专用，PAT_TYPE=0 行为，1500B/线速 IPG）
//   'v'       RAW10 图案流（G11n16：图案源经 FIFO 链路走 cam 模式，CamGen(1)）
//   'c'       G10 相机 RAW10 直推（CamGen(0)，同一条 FIFO 链路）
//   'n'       停流 → 网络服务（ARP/ICMP/IPv4 回显/tick/UART 配置）
//   's'       恢复上次的流
// G11n16 重构：图案生成迁到 200M 相机域（raw10_pat_src → 源 mux → 同一条
// cam_fifo_bank 链路），gen 旧 125M 图案直发路径删除；默认开机网络服务模式
//（不发流，mux→sw）。RTL 依据：udp_pat_gen_v2 的 en 只在 S_IDLE 起作用（start
// 边沿），inc 无限流包间不回 S_IDLE、en 撤除不停车——停流必须走 pat_gen_kill
//（0x208 bit3，包边界干净停车，start 自动解除）。切换在包边界进行。
#define RMODE_STREAM_INC    0   //递增线速流（debug）
#define RMODE_NETSVC        1   //网络服务（无流，mux→sw）——默认开机模式
#define RMODE_STREAM_RAW10  2   //RAW10 图案流（G11n16：200M 图案源经 FIFO 链路）
#define RMODE_STREAM_CAM    3   //G10 相机 RAW10 直推（同一条 FIFO 链路）
static u8 g_run_mode = RMODE_NETSVC;       //G11n16：默认开机网络服务（StartRunning 覆盖）
static u8 g_pat_type_rt = PAT_TYPE;        //PatGen 参数化流类型（0=inc / 2=raw10）
static volatile u8 g_mode_req = 0xFF;      //PC 请求（PatCtrlCmd 置位，主循环消费）

////////////////////////////////////////////////////////////////////////////////
void PatGen()
{
	u32 Value;
    //ex_reg pat_dst_mac[47:32]
	write_u32(DST_MAC_H, (TSEMAC_CSR+0x214));
    //ex_reg pat_dst_mac[31:0]
	write_u32(DST_MAC_L, (TSEMAC_CSR+0x210));
    //ex_reg pat_src_mac[47:32]
	write_u32(SRC_MAC_H, (TSEMAC_CSR+0x21c));
    //ex_reg pat_src_mac[31:0]
	write_u32(SRC_MAC_L, (TSEMAC_CSR+0x218));
    //ex_reg pat_src_ip
	write_u32(SRC_IP, (TSEMAC_CSR+0x224));
    //ex_reg pat_dst_ip
	write_u32(DST_IP, (TSEMAC_CSR+0x228));
	Value = (DST_PORT<<16) | (SRC_PORT&0xffff);
    //ex_reg pat_dst_port & pat_src_port
	write_u32(Value, (TSEMAC_CSR+0x22c));
	Value = (PAT_IPG<<16) | (PAT_NUM&0xffff);
    //ex_reg pat_gen_ipg & pat_gen_num
	write_u32(Value, (TSEMAC_CSR+0x20c));
    //ex_reg pat_mac_dlen
	write_u32(PAT_DLEN, (TSEMAC_CSR+0x220));
    //ex_reg pat_udp_dlen
	write_u32(PAT_DLEN, (TSEMAC_CSR+0x230));
    //ex_reg mac_pat_gen_en & udp_pat_gen_en
	write_u32(0x0, (TSEMAC_CSR+0x208));
	if(g_pat_type_rt == 0) {
        //ex_reg pat_mux_select & axi4_st_mux_select
		write_u32(0x0, (TSEMAC_CSR+0x204));
        //ex_reg mac_pat_gen_en & udp_pat_gen_en（写 0 先清残留 kill 位，再起脉冲）
		write_u32(0x1, (TSEMAC_CSR+0x208));
        //ex_reg mac_pat_gen_en & udp_pat_gen_en
		write_u32(0x0, (TSEMAC_CSR+0x208));
	} else if(g_pat_type_rt == 1) {
        //旧 MAC 图案（v1 兼容，运行时模式切换不使用）
        //ex_reg pat_mux_select & axi4_st_mux_select
		write_u32(0x2, (TSEMAC_CSR+0x204));
        //ex_reg mac_pat_gen_en & udp_pat_gen_en
		write_u32(0x2, (TSEMAC_CSR+0x208));
        //ex_reg mac_pat_gen_en & udp_pat_gen_en
		write_u32(0x0, (TSEMAC_CSR+0x208));
	}
	//G11n16：旧 raw10 直发分支（g_pat_type_rt==2）已删——图案流改走 CamGen(1)
	//（200M 图案源经 FIFO 链路），'v' 不再进入本函数（仅 't' inc debug 使用）
	if(PRINTF_EN == 1) {
        bsp_print("Info : Set Pattern Generator.");
	}
}


//G10 相机/图案源 RAW10 直推（udp_pat_gen_v2 cam 源，0x208 bit6=cam_src_en）：
//G11n16 参数化 sel——FIFO 写源选择（0x208 bit7 fifo_src_sel）：0=相机 RX，
//1=200M 图案源 raw10_pat_src。两源同一条 cam_fifo_bank 链路，gen 侧同为
//cam 模式；图案模式切换（'0'..'3'）只改 0x208[5:4]，由图案源运行时消费。
//头参数复用图案寄存器；两段式启动——cam_en/raw10/sel 电平先于 en 上升沿一个
//APB 周期建立（125M 域 start_pulse 锁存 cam_r，同拍采样竞态会锁错模式，
//与原 PatGen raw10 分支同一实测教训）。num=0 无限帧；帧间由 pacer 门控发包。
//MacRxPoll 由 efx_tse_mac.h 提供（static inline，包含于头部）
static void CamGen(int sel)
{
	u32 Value;
	int i;
	u32 lvl = 0x44 | (sel ? 0x80 : 0x00);       //bit2 raw10 + bit6 cam_src + bit7 fifo_src_sel
	write_u32(DST_MAC_H, (TSEMAC_CSR+0x214));
	write_u32(DST_MAC_L, (TSEMAC_CSR+0x210));
	write_u32(SRC_MAC_H, (TSEMAC_CSR+0x21c));
	write_u32(SRC_MAC_L, (TSEMAC_CSR+0x218));
	write_u32(SRC_IP, (TSEMAC_CSR+0x224));
	write_u32(DST_IP, (TSEMAC_CSR+0x228));
	Value = (DST_PORT<<16) | (SRC_PORT&0xffff);
	write_u32(Value, (TSEMAC_CSR+0x22c));
	Value = (PAT_IPG<<16) | 0;                  //num=0：无限帧连续相机流
	write_u32(Value, (TSEMAC_CSR+0x20c));
	write_u32(PAT_DLEN, (TSEMAC_CSR+0x220));
	write_u32(PAT_DLEN, (TSEMAC_CSR+0x230));
	write_u32(0x0, (TSEMAC_CSR+0x204));         //mux→pattern（UDP 路径）
	write_u32(0x0, (TSEMAC_CSR+0x208));         //全清（kill 已由 StreamStop 清）
	write_u32(lvl, (TSEMAC_CSR+0x208));         //电平先建立（ILA 实证：bit6 与 en
	                                            //同拍翻转时 125M 采样竞态锁错 cam_r=0）
	bsp_uDelay(100);
	write_u32(lvl | 0x1, (TSEMAC_CSR+0x208));   //en↑ → start_pulse 锁存 cam_r=1（电平已稳 100µs）
	bsp_uDelay(100);
	write_u32(lvl, (TSEMAC_CSR+0x208));         //撤销 en 脉冲，电平保持
	//G10 诊断：启动后 2s 内轮询 2 次（pacer act/occ/qidx 需等帧边界 + 占用积累）
	//注意 bsp_printf 参数上限 5，拆两行；只用 %08x（%u 行为异常）
	//G11m：延时改为 500×1ms 排空 RX——曾纯 bsp_uDelay(500000)×2 把 RX FIFO
	//饿死（板上实证 Warn: RX fifo overflow → 控制命令丢失 → 切不回图案）
	for (i = 0; i < 2; i++) {
		u8 rxd[64];
		int j;
		for (j = 0; j < 500; j++) { MacRxPoll(rxd, sizeof(rxd)); bsp_uDelay(1000); }
		bsp_printf("CAM%08x: [208]=%08x [2C0]=%08x [24C]=%08x\r\n",
			i, read_u32(TSEMAC_CSR+0x208), read_u32(TSEMAC_CSR+0x2C0),
			read_u32(TSEMAC_CSR+0x24C));
		bsp_printf("CAMST: [2A0]=%08x [2AC]=%08x [270]=%08x [240]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2A0), read_u32(TSEMAC_CSR+0x2AC),
			read_u32(TSEMAC_CSR+0x270), read_u32(TSEMAC_CSR+0x240));
		//G11j：输出侧诊断——[2CC]={full,armed,sof_cnt}，[2D0]=raw_tvalid 拍计数
		bsp_printf("CAMDBG: [2CC]=%08x [2D0]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2CC), read_u32(TSEMAC_CSR+0x2D0));
	}
}


////////////////////////////////////////////////////////////////////////////////
// 控制服务（原 TEST_MODE=0 PatCtrlRun，2026-11-06 扩展为全模式统一 AppRun）
//   ARP request -> 应答（G3 模块复用；PC 发控制 UDP 前的先决条件）
//   ICMP echo  -> 应答（G7x：ping 与流共存）
//   UDP dst_port=PAT_CTRL_PORT：
//     '0'..'3'          -> CSR 0x208[5:4] RAW10 图案模式
//     't'/'v'/'n'/'s'   -> 模式切换请求（主循环 ApplyMode 执行）
// RX FIFO 溢出容忍：控制报文稀疏（菜单点击级），偶发丢弃无害
static int PatCtrlCmd(u8 *f, int len)
{
	u16 dport, dlen;
	u32 v;
	u8 cmd;

	if (len < 42) return 0;
	dport = ((u16)f[36] << 8) | f[37];
	if (dport != PAT_CTRL_PORT) return 0;
	dlen = ((u16)f[38] << 8) | f[39];
	if (dlen < 9 || len < 42 + (int)(dlen - 8)) return 0;
	cmd = f[42];
	if (cmd >= '0' && cmd <= '3') {
		//read-modify-write 0x208：保留 raw10_mode(bit2)/kill(bit3)，只改 [5:4]
		v = read_u32(TSEMAC_CSR+0x208) & ~(u32)0x30;
		write_u32(v | ((u32)(cmd - '0') << 4), (TSEMAC_CSR+0x208));
		bsp_printf("PAT MODE -> %c\r\n", cmd);
	} else if (cmd == 't' || cmd == 'T') {           //G6 递增线速流
		g_mode_req = RMODE_STREAM_INC;
		bsp_print("MODE REQ -> thruput\r\n");
	} else if (cmd == 'v' || cmd == 'V') {           //G7 RAW10 视频流
		g_mode_req = RMODE_STREAM_RAW10;
		bsp_print("MODE REQ -> raw10\r\n");
	} else if (cmd == 'c' || cmd == 'C') {           //G10 相机 RAW10 直推
		g_mode_req = RMODE_STREAM_CAM;
		bsp_print("MODE REQ -> cam\r\n");
	} else if (cmd == 'i' || cmd == 'I') {           //相机/I2C 状态快照
		bsp_printf("CAMST: [2A0]=%08x [2AC]=%08x [270]=%08x [240]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2A0), read_u32(TSEMAC_CSR+0x2AC),
			read_u32(TSEMAC_CSR+0x270), read_u32(TSEMAC_CSR+0x240));
		bsp_printf("CLKST: [2C4]=%08x [2C4]=%08x [250]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2C4), read_u32(TSEMAC_CSR+0x2C4),
			read_u32(TSEMAC_CSR+0x250));
		bsp_printf("CAMDBG: [2CC]=%08x [2D0]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2CC), read_u32(TSEMAC_CSR+0x2D0));
		//G11j-3：[2D4]=tuser[1]裸计数 [2D8]=tuser[0]裸计数 [2DC]=vs沿 [2E0]=hs沿（全32位）
		bsp_printf("CAMDBG2: [2D4]=%08x [2D8]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2D4), read_u32(TSEMAC_CSR+0x2D8));
		bsp_printf("CAMDBG3: [2DC]=%08x [2E0]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2DC), read_u32(TSEMAC_CSR+0x2E0));
		//G11j-4：[2E4]={wcnt,wr_bin,rd_sync_bin} [2E8]={rd_bin,wgray,0}（FIFO 指针）
		bsp_printf("CAMDBG4: [2E4]=%08x [2E8]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2E4), read_u32(TSEMAC_CSR+0x2E8));
	} else if (cmd == 'n' || cmd == 'N') {           //停流 → 网络服务
		g_mode_req = RMODE_NETSVC;
		bsp_print("MODE REQ -> netsvc\r\n");
	} else if (cmd == 's' || cmd == 'S') {           //恢复上次的流
		g_mode_req = (g_pat_type_rt == 2) ? RMODE_STREAM_RAW10 : RMODE_STREAM_INC;
		bsp_print("MODE REQ -> stream\r\n");
	} else {
		return 0;   //未识别命令
	}
	return 0;       //控制命令均不发应答（以 UART 打印与流量变化为准）
}

//流停止：kill 位（0x208 bit3）包边界停车。inc 无限流包间不回 S_IDLE、en 撤除
//不停车（RTL 实读确认），kill 是唯一干净停法；RAW10 同样适用（当前包收尾即停，
//可能截掉半帧 → viewer 丢帧计数 +1，控制动作可接受）。停车后清 kill + mux→sw。
static void StreamStop(void)
{
	u32 g;
	write_u32(0x08, (TSEMAC_CSR+0x208));     //kill=1（其余位清零，引擎停车）
	//等包边界：inc ≤12.2µs，RAW10 ≤包时长；pat_dbg state（0x24C bit[5:3]==S_IDLE）
	for (g = 0; g < 100000; g++)
		if ((read_u32(TSEMAC_CSR+0x24C) & 0x38) == 0) break;
	write_u32(0x00, (TSEMAC_CSR+0x208));     //清 kill（PatGen 重启亦会清）
	write_u32(0x10, (TSEMAC_CSR+0x204));     //mux→sw
}

//应用模式切换（主循环内执行；PatCtrlCmd 只置 g_mode_req，避免 RX 处理中途切态）
static void ApplyMode(u8 m)
{
	if (m == g_run_mode) return;

	if (g_run_mode != RMODE_NETSVC) {
		StreamStop();                        //流→流/流→netsvc：先包边界停流
	} else {
		//netsvc→流：等 sw TX FIFO 排空（free==4095），防 tick 尾帧与图案首帧拼接
		u32 g;
		for (g = 0; g < 1000000; g++)
			if ((read_u32(TSEMAC_CSR+ETH_TX_STATUS) & 0x1FFF) == 4095) break;
	}
	if (m == RMODE_NETSVC) {
		bsp_print("MODE -> net service (ping/echo/UART cfg)\r\n");
	} else if (m == RMODE_STREAM_CAM) {
		g_pat_type_rt = 2;                   //G10：cam 模式复用 RAW10 帧间注入路径
		                                     //（不 kill/不碰 0x208——否则 ARP/ICMP 一来
		                                     //就 kill+PatGen 重启，cam_r 被重锁 0、
		                                     //cam 配置被抹成 inc，[208] 读回 0 实证）
		CamGen(0);                           //G10：相机源（fifo_src_sel=0）两段式启动
		bsp_print("MODE -> cam stream\r\n");
	} else if (m == RMODE_STREAM_RAW10) {
		//G11n16：'v' 图案流=200M 图案源（fifo_src_sel=1）走同一 FIFO 链路，
		//gen 侧同为 cam 模式——与 'c' 唯一区别是 0x208 bit7
		g_pat_type_rt = 2;
		CamGen(1);
		bsp_print("MODE -> raw10 pattern stream (200M src)\r\n");
	} else {
		g_pat_type_rt = 0;
		PatGen();                            //mux→pattern + inc 启动脉冲（清 kill_r）
		bsp_print("MODE -> thruput stream (debug)\r\n");
	}
	MacCntClean();
	g_run_mode = m;
}

//统一应用主循环（原 PatCtrlRun/SwEchoRun 合并，2026-11-06）：
//  流模式（inc/raw10）：ARP/ICMP 控制面注入；控制 UDP 切图案/模式；无 tick/[stat]
//    inc 线速：kill 包边界停车注入（2026-11-06 晚，替代 v3 超时裸切——裸切会
//    把应答帧拼成巨帧丢弃，PC ARP 学不到，控制面死路）
//    RAW10：帧间 S_IDLE 窗口注入（v3 板级验证零丢帧）
//  网络服务：ARP/ICMP/IPv4 回显直发（mux 已指向 sw）+ 1s tick + [stat] + UART
static int build_tick_frame(u8 *f, u16 id);
static void CmdPoll(void);

static void AppRun(void)
{
	u8 buf[1600];
	u8 tick[128];
	int len;
	int i;
	u32 ms = 999;            //netsvc 首帧 tick 立即发出
	u16 tick_id = 1;

	while (1) {
		len = MacRxPoll(buf, sizeof(buf));
		if (len > 0) {
			int rl = 0;
			int echo = 0;
			u16 etype = ((u16)buf[12] << 8) | buf[13];
			if (g_run_mode == RMODE_NETSVC) {      //诊断 hex dump 仅 netsvc（流模式下刷屏）
				bsp_printf("RX len=%d type=%04x:", len, etype);
				for (i = 0; i < 16 && i < len; i++)
					bsp_printf(" %02x", buf[i]);
				bsp_print("\r\n");
			}
			if (etype == 0x0806) {                    //ARP 请求→应答（G3）
				rl = arp_process(buf, len);
				if (rl > 0) bsp_print("ARP: reply sent\r\n");
			} else if (etype == 0x0800) {             //ICMP echo / UDP ctrl
				rl = icmp_process(buf, len);
				if (rl > 0) bsp_print("ICMP: echo reply sent\r\n");
				if (rl == 0) rl = PatCtrlCmd(buf, len);
				if (rl == 0 && g_run_mode == RMODE_NETSVC) echo = 1; //G1 回显
			}
			if (rl > 0) {
				if (g_run_mode == RMODE_NETSVC) {
					MacTxSend(buf, rl);               //mux 已指向 sw，直发
				} else if (g_run_mode == RMODE_STREAM_CAM) {
					//G11m：cam 流帧间背靠背（S_IDLE 仅 1-2 拍/33ms），旧"帧间窗口
					//注入"guard 30ms 必超时 → mid-stream 切 mux：在传帧损坏 +
					//FIFO 满丢数（卷动源）+ CPU 忙等饿死 RX（控制丢失）。改 pacer
					//pause 协议（CSR 0x2F4）：pause→gen 包边界停 S_IPG（线空闲）
					//→ mux→sw 直发 → 还原 → unpause 续流。无竞争、零丢数、断流 ≤1 包。
					write_u32(0x1, (TSEMAC_CSR+0x2F4));   //pause=1
					bsp_uDelay(50);                       //当前包收尾 ≤12µs + MAC 冲刷裕量
					write_u32(0x10, (TSEMAC_CSR+0x204));  //mux→sw
					MacTxSend(buf, rl);
					write_u32(0x00, (TSEMAC_CSR+0x204));  //mux→pattern
					write_u32(0x0, (TSEMAC_CSR+0x2F4));   //unpause（S_IPG 立即续流）
				} else if (g_pat_type_rt == 2) {
					//RAW10：帧间 S_IDLE 窗口注入（v3 板级验证零丢帧）——帧间隙
					//≈12ms，sw 帧≈12µs 过线后 mux 回图案
					{
						u32 guard;
						for (guard = 0; guard < 30000; guard++)
							if ((read_u32(TSEMAC_CSR+0x24C) & 0x38) == 0) break;
					}
					write_u32(0x10, (TSEMAC_CSR+0x204));  //mux→sw
					MacTxSend(buf, rl);
					write_u32(0x00, (TSEMAC_CSR+0x204));  //mux→pattern
				} else {
					//inc 线速：包间 IPG 仅 96ns，S_IDLE 不可捕获，v3 注入超时后
					//mid-frame 切 mux → ARP 应答被拼成巨帧丢弃（PC ARP 永远学不到，
					//控制面死路）。改用 kill 包边界停车（≤12.2µs）→ mux→sw 直发
					//→ PatGen 重启复流。代价：注入瞬间 ~100µs 停顿（吞吐影响可忽略）
					u32 guard;
					write_u32(0x08, (TSEMAC_CSR+0x208));  //kill（包边界停车）
					for (guard = 0; guard < 100000; guard++)
						if ((read_u32(TSEMAC_CSR+0x24C) & 0x38) == 0) break;
					write_u32(0x00, (TSEMAC_CSR+0x208));
					write_u32(0x10, (TSEMAC_CSR+0x204));  //mux→sw
					MacTxSend(buf, rl);
					PatGen();                             //mux→pattern + 重启（清 kill_r）
				}
			} else if (echo) {
				//其余 IPv4 维持 L2/L3 对称回显（G1 证据链；IP src/dst 交换后
				//UDP pseudo-header 和不变 → UDP checksum 原样合法）
				u16 c;
				for (i = 0; i < 6; i++) { u8 t = buf[i]; buf[i] = buf[6+i]; buf[6+i] = t; }
				{
					int s = 14 + 12;                  //IP src 偏移
					for (i = 0; i < 4; i++) { u8 t = buf[s+i]; buf[s+i] = buf[s+4+i]; buf[s+4+i] = t; }
					buf[24] = 0; buf[25] = 0;
					c = eth_ip_checksum(&buf[14], 20);
					buf[24] = (u8)(c >> 8); buf[25] = (u8)c;
				}
				MacTxSend(buf, len);
			}
		}
		CmdPoll();                                //G5：UART 命令行（全模式可用）
		if (g_mode_req != 0xFF) {                 //PC 模式切换请求
			u8 m = g_mode_req;
			g_mode_req = 0xFF;
			ApplyMode(m);
		}
		bsp_uDelay(1000);                         //1ms 轮询粒度（与原 SwEchoRun 同，保 G2 tick 语义）
		if (++ms >= 1000) {                       //1s 节拍
			ms = 0;
			if (g_run_mode == RMODE_NETSVC) {     //tick/[stat] 仅 netsvc（G2）
				MacTxSend(tick, build_tick_frame(tick, tick_id++));
				if ((tick_id & 0x1) == 0) {       //每 2s 打印诊断计数
					bsp_printf("[stat] tx=%x rx=%x ierr=%x drop=%x all=%x rxst=%x dbg94=%x lock=%x cfg=%x\r\n",
						read_u32(TSEMAC_BASE+A_FRAME_TRANSMITTED_OK),
						read_u32(TSEMAC_BASE+A_FRAME_RECEIVED_OK),
						read_u32(TSEMAC_BASE+IF_INDICATES_ERROR),
						read_u32(TSEMAC_BASE+A_RX_FILTER_FRAMES_ERROR),
						read_u32(TSEMAC_BASE+ETHER_STATS_PKTS),
						read_u32(TSEMAC_CSR+ETH_RX_STATUS),
						read_u32(TSEMAC_CSR+0x250),
						read_u32(TSEMAC_CSR+0x254),
						read_u32(TSEMAC_BASE+COMMAND_CONFIG));
				}
			}
		}
	}
}

void StartRunning()
{
	u32 Value;
    //诊断结论（实验 A/B/C/D 对照）：proto_reset 脉冲后 sw 帧通路死（手写帧/pattern 帧
    //在无脉冲状态下均正常）。复位默认数据路径本就干净，去掉 mac_sw_rst 脉冲。
    //if(PRINTF_EN == 1) {
    //    bsp_print("Info : Assert mac reset ");
    //}
    //bsp_uDelay(1);
    //write_u32(0x0, (TSEMAC_CSR+0x200));   //mac_sw_rst: 不再触发 proto_reset
    if(PRINTF_EN == 1) {
        bsp_print("Info : skip proto_reset pulse (diag E)\r\n");
    }

	if(TEST_MODE == 0 || TEST_MODE == 2) {
        //ex_reg pat_mux_select & axi4_st_mux_select
		write_u32(0x1, (TSEMAC_CSR+0x204));
		MacCntClean();
		//控制面 MAC 配置（read-modify-write，不碰 ena 位——实验 C 教训）
		//promis_en=1 禁用地址过滤 + 关广播过滤：保证 ARP/ICMP/控制 UDP 能进 CPU
		Value = read_u32(TSEMAC_BASE+COMMAND_CONFIG) & PROMIS_EN_MASK;
		Value |= (0x1<<4);
		write_u32(Value, (TSEMAC_BASE+COMMAND_CONFIG));
		MacAddrSet(0, 0);
		write_u32(0x0, (TSEMAC_CSR+0x140));
		//网络配置单一事实来源 + 同步 pattern 源寄存器（图案头 src 与 ARP 应答一致）
		net_config_init();
		net_config_apply();
		//统一应用入口（2026-11-06）：TEST_MODE 只决定 boot 初态，此后所有模式
		//（thruput/raw10 图案/cam/netsvc/图案 0-3）由 PC 经 UDP 10006 运行时切换
		//G11n16：默认开机网络服务模式（不发流，mux→sw）——重定义 boot 行为
		g_pat_type_rt = PAT_TYPE;
		g_run_mode = RMODE_NETSVC;
		bsp_print("unified app: UDP 10006 cmds t/v/n/s/c + pat 0-3\r\n");
		if(g_run_mode == RMODE_NETSVC) {
			write_u32(0x10, (TSEMAC_CSR+0x204));   //mux→sw（CPU 直发通路）
			bsp_printf("PHY snap: CHIP_CFG=%04x GATING=%04x SLEEP=%04x RGMII1=%04x\r\n",
				yt8531_ext_read(YT8531_EXT_CHIP_CFG), yt8531_ext_read(YT8531_EXT_CLK_GATING),
				yt8531_ext_read(YT8531_EXT_SLEEP_CTRL), yt8531_ext_read(YT8531_EXT_RGMII_CFG1));
			bsp_print("net service mode: ARP reply + ICMP echo reply + IPv4 echo\r\n");
			bsp_printf("local %d.%d.%d.%d / %02x:%02x:%02x:%02x:%02x:%02x\r\n",
				(g_net_cfg.local_ip >> 24) & 0xff, (g_net_cfg.local_ip >> 16) & 0xff,
				(g_net_cfg.local_ip >> 8) & 0xff, g_net_cfg.local_ip & 0xff,
				g_net_cfg.local_mac[0], g_net_cfg.local_mac[1],
				g_net_cfg.local_mac[2], g_net_cfg.local_mac[3],
				g_net_cfg.local_mac[4], g_net_cfg.local_mac[5]);
			bsp_print("UART cfg console: ip/mac/gw/mask/show, try 'help'\r\ncfg> ");
		}
		//G11n16：boot 不再自动 PatGen（默认 netsvc 不发流；流经 't'/'v'/'c' 启动）
		AppRun();
	} else if(TEST_MODE == 1) {
        //ex_reg pat_mux_select & axi4_st_mux_select
		write_u32(0x1, (TSEMAC_CSR+0x204));
		MacAddrSet(0, 1);
		MacCntClean();
		bsp_print("test mode = 1\n\r ");
	}

	while(1){
//		bsp_uDelay(3000000);
//		CntMonitor();
	}
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
// TEST_MODE=2 : 网络服务模式（阶段2：G3 ARP + G4 ICMP + G1 IPv4 回显）
// TX 自测：每秒发 1 帧广播 UDP 到 PC 10005 端口（G2：PC 侧收到即通）
// RX 分发：ARP 请求 -> 应答（G3）；ICMP echo -> 应答（G4）；
//          其余 IPv4 -> L2/L3 对称交换回发（G1 证据链维持）；非 IPv4 仅打印
// 依据 TSEMAC UG：crc_fwd=0 时 RX 无 FCS、TX 自动加 CRC
//构造自测帧：广播 MAC / 本板 IP -> DST_IP / SRC_PORT -> DST_PORT / 64B payload
static int build_tick_frame(u8 *f, u16 id)
{
	int i;
	const u16 total = 20 + 8 + 64;
	const u8  bm[6] = {0xff,0xff,0xff,0xff,0xff,0xff};
	for (i = 0; i < 6; i++) { f[i] = bm[i]; f[6+i] = g_net_cfg.local_mac[i]; }
	f[12] = 0x08; f[13] = 0x00;                          //ethertype IPv4
	f[14] = 0x45; f[15] = 0x00;
	f[16] = (u8)(total >> 8); f[17] = (u8)total;
	f[18] = (u8)(id >> 8);    f[19] = (u8)id;
	f[20] = 0x00; f[21] = 0x00;
	f[22] = 64;   f[23] = 17;                            //TTL, UDP
	f[24] = 0;    f[25] = 0;
	f[26] = (u8)(g_net_cfg.local_ip >> 24); f[27] = (u8)(g_net_cfg.local_ip >> 16);
	f[28] = (u8)(g_net_cfg.local_ip >> 8);  f[29] = (u8) g_net_cfg.local_ip;
	f[30] = (u8)(DST_IP >> 24); f[31] = (u8)(DST_IP >> 16);
	f[32] = (u8)(DST_IP >> 8);  f[33] = (u8)DST_IP;
	{ u16 c = eth_ip_checksum(&f[14], 20); f[24] = (u8)(c >> 8); f[25] = (u8)c; }
	f[34] = (u8)(SRC_PORT >> 8); f[35] = (u8)SRC_PORT;
	f[36] = (u8)(DST_PORT >> 8); f[37] = (u8)DST_PORT;
	f[38] = (u8)((8 + 64) >> 8); f[39] = (u8)(8 + 64);
	f[40] = 0;    f[41] = 0;                             //UDP checksum off
	for (i = 0; i < 64; i++)
		f[42+i] = "TSE-SW-TX-TICK-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[i % 62];
	return 42 + 64;
}

////////////////////////////////////////////////////////////////////////////////
// G5：UART 命令行（非阻塞轮询，回车执行，立即生效）
// ip a.b.c.d / mac xx:xx:xx:xx:xx:xx / gw a.b.c.d / mask a.b.c.d / show / help
// 生效路径：ARP/ICMP/tick 帧读 g_net_cfg；MAC 过滤与 pattern 源寄存器由
// net_config_apply() 同步刷新
static char cmd_buf[64];
static int  cmd_len = 0;

static void CmdHelp(void)
{
	bsp_print("commands:\r\n");
	bsp_print("  ip a.b.c.d            - set local IP\r\n");
	bsp_print("  mac xx:xx:xx:xx:xx:xx - set local MAC\r\n");
	bsp_print("  gw a.b.c.d            - set gateway (stored)\r\n");
	bsp_print("  mask a.b.c.d          - set netmask (stored)\r\n");
	bsp_print("  show                  - print config\r\n");
}

//前缀匹配（不依赖 libc）：line 是否以 cmd 开头
static int cmd_prefix(const char *line, const char *cmd)
{
	int i;
	for (i = 0; cmd[i]; i++)
		if (line[i] != cmd[i]) return 0;
	return 1;
}

static void CmdExec(char *line)
{
	while (*line == ' ') line++;
	if (cmd_prefix(line, "ip ")) {
		if (net_config_set_ip(line + 3) == 0) { bsp_print("IP set.\r\n"); net_config_show(); }
		else bsp_print("Err: bad IP format (a.b.c.d)\r\n");
	} else if (cmd_prefix(line, "mac ")) {
		if (net_config_set_mac(line + 4) == 0) { bsp_print("MAC set.\r\n"); net_config_show(); }
		else bsp_print("Err: bad MAC format (xx:xx:xx:xx:xx:xx)\r\n");
	} else if (cmd_prefix(line, "gw ")) {
		if (net_config_set_gw(line + 3) == 0) bsp_print("GW set.\r\n");
		else bsp_print("Err: bad IP format\r\n");
	} else if (cmd_prefix(line, "mask ")) {
		if (net_config_set_mask(line + 5) == 0) bsp_print("MASK set.\r\n");
		else bsp_print("Err: bad IP format\r\n");
	} else if (cmd_prefix(line, "show")) {
		net_config_show();
	} else if (cmd_prefix(line, "cam")) {           //相机/时钟状态快照
		bsp_printf("CAMST: [2A0]=%08x [2AC]=%08x [270]=%08x [240]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2A0), read_u32(TSEMAC_CSR+0x2AC),
			read_u32(TSEMAC_CSR+0x270), read_u32(TSEMAC_CSR+0x240));
		bsp_printf("CLKST: [2C4]=%08x [2C4]=%08x [250]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2C4), read_u32(TSEMAC_CSR+0x2C4),
			read_u32(TSEMAC_CSR+0x250));
		bsp_printf("CAMDBG: [2CC]=%08x [2D0]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2CC), read_u32(TSEMAC_CSR+0x2D0));
		//G11j-3：[2D4]=tuser[1]裸计数 [2D8]=tuser[0]裸计数 [2DC]=vs沿 [2E0]=hs沿（全32位）
		bsp_printf("CAMDBG2: [2D4]=%08x [2D8]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2D4), read_u32(TSEMAC_CSR+0x2D8));
		bsp_printf("CAMDBG3: [2DC]=%08x [2E0]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2DC), read_u32(TSEMAC_CSR+0x2E0));
		//G11j-4：[2E4]={wcnt,wr_bin,rd_sync_bin} [2E8]={rd_bin,wgray,0}（FIFO 指针）
		bsp_printf("CAMDBG4: [2E4]=%08x [2E8]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2E4), read_u32(TSEMAC_CSR+0x2E8));
		//G11m：[2EC]=FIFO 拒收写累计（丢数定量——画面卷动=相位滑移源）+ 过线帧数
		bsp_printf("CAMDBG5: [2EC]=%08x TXOK=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2EC), read_u32(TSEMAC_BASE+A_FRAME_TRANSMITTED_OK));
		//G11n：[2F0]=gen 包完成数 [2F8]=tvalid&&!tready 背压拍数（两次 cam 取差：
		//pkt差/秒=实际发包率（线速需求 81.2K/s）；bp差/(125M×秒)=MAC 背压占空比）
		bsp_printf("CAMDBG6: [2F0]=%08x [2F8]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2F0), read_u32(TSEMAC_CSR+0x2F8));
		//G11n2：[2FC]=cam_quad_rd 拉高（FIFO 弹出，对照接受 15.33M/s）
		//[300]=S_IPG 白等拍（对照 125M×秒——若占比≈50%=gen 等 occ 主瓶颈）
		bsp_printf("CAMDBG7: [2FC]=%08x [300]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2FC), read_u32(TSEMAC_CSR+0x300));
		//G11n5 白等成分裁决：[2C0] 稳态（bit31=armed,bit12=active,bits10:0=occ）
		//+ [304]=帧门关白等 + [308]=occ门白等；两者之和 ≈ [300] 白等总数
		bsp_printf("CAMDBG8: [2C0]=%08x [304]=%08x [308]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x2C0), read_u32(TSEMAC_CSR+0x304),
			read_u32(TSEMAC_CSR+0x308));
		//G11n9 裁决探针：低锯齿稳态 vs rej 21% 矛盾（两次 cam 取差 + 峰值直读）
		//[30C]=full=1拍累计 [310]=full上升沿数（均值=单次满事件时长）
		//[314]=连续rej最大拍 [318]=连续tvalid最大拍 [31C]={occ_min,occ_peak}帧内锯齿
		bsp_printf("CAMDBG9: [30C]=%08x [310]=%08x [314]=%08x [318]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x30C), read_u32(TSEMAC_CSR+0x310),
			read_u32(TSEMAC_CSR+0x314), read_u32(TSEMAC_CSR+0x318));
		bsp_printf("CAMDBG10: [31C]=%08x (min=%04x peak=%04x)\r\n",
			read_u32(TSEMAC_CSR+0x31C),
			read_u32(TSEMAC_CSR+0x31C) >> 16,
			read_u32(TSEMAC_CSR+0x31C) & 0xFFFF);
		//G11n11/13 行间隔分布：min=2961 已实锤"半距行"，直方图 4 桶闭合 rej 机制
		bsp_printf("CAMDBG11: [320]=%08x [324]=%08x (hsgap_max=%d hsgap_min=%d)\r\n",
			read_u32(TSEMAC_CSR+0x320), read_u32(TSEMAC_CSR+0x324),
			read_u32(TSEMAC_CSR+0x320), read_u32(TSEMAC_CSR+0x324));
		bsp_printf("CAMDBG12: [328]=%08x [32C]=%08x [330]=%08x [334]=%08x\r\n",
			read_u32(TSEMAC_CSR+0x328), read_u32(TSEMAC_CSR+0x32C),
			read_u32(TSEMAC_CSR+0x330), read_u32(TSEMAC_CSR+0x334));
	} else if (cmd_prefix(line, "help") || line[0] == '?') {
		CmdHelp();
	} else {
		bsp_print("Err: unknown cmd (try help)\r\n");
	}
}

static void CmdPoll(void)
{
	while (uart_readOccupancy(BSP_UART_TERMINAL) > 0) {
		char c = uart_read(BSP_UART_TERMINAL);
		if (c == '\r' || c == '\n') {
			if (cmd_len > 0) {
				cmd_buf[cmd_len] = '\0';
				bsp_print("\r\n");
				CmdExec(cmd_buf);
				cmd_len = 0;
			}
			bsp_print("cfg> ");
		} else if (c == 0x08 || c == 0x7f) {                 //退格
			if (cmd_len > 0) { cmd_len--; bsp_print("\b \b"); }
		} else if (c >= 32 && c < 127 && cmd_len < (int)(sizeof(cmd_buf) - 1)) {
			cmd_buf[cmd_len++] = c;
			uart_write(BSP_UART_TERMINAL, c);                //回显
		}
		//其余控制字符丢弃
	}
}

//PHY 内部回环（TEST_MODE=1）：写 BMCR loopback 位；Phy_Wr 来自 yt8531fd.h
void PhyLoopInit(u32 speed)
{
	//PhyDlySetRXTX(15, 15); //change the delay here for Test_mode_0 (Normal mode)
	if(speed == 0x4) {
		Phy_Wr(0x0, 0x4140);
		if(PRINTF_EN == 1) {
			bsp_print("Info : Set Phy 1000Mbps Loopback Mode.");
		}
	} else if(speed == 0x2) {
		Phy_Wr(0x0, 0x6100);
		if(PRINTF_EN == 1) {
			bsp_print("Info : Set Phy 100Mbps Loopback Mode.");
		}
	} else if(speed == 0x1) {
		Phy_Wr(0x0, 0x4100);
		if(PRINTF_EN == 1) {
			bsp_print("Info : Set Phy 10Mbps Loopback Mode.");
		}
	}
}


////////////////////////////////////////////////////////////////////////////////
void main() {
    u32 prompt=0;
    u32 speed;

    bsp_init();
    bsp_print("tse demo !");
	//参考工程（LOOPBACK 测通）YT8531 序列：完整初始化 → 死等真实链路（BMSR/SSR
	//交叉验证）→ 链路后重配 RGMII → 等 RXC PLL 锁（链路建立后 PLL 需 10~30s 才锁，
	//参考工程等 60s 才初始化 MAC）
	yt8531_drv_init();
	speed = yt8531_drv_linkup();
	yt8531_post_link_rgmii();
	{
		u32 t;
		for (t = 0; t < 60000; t++) {          //最多 60s 等 RXC PLL lock
			if (read_u32(TSEMAC_CSR+0x254) & 0x1) {   //CSR word 0x095 bit0 = pll_rgmii_locked
				bsp_printf("Info : RXC PLL locked after ~%d ms\r\n", (int)t);
				break;
			}
			bsp_uDelay(1000);
		}
		if (t >= 60000) {
			bsp_print("Warn : RXC PLL not locked within 60s (check RXC wiring)\r\n");
		}
	}
	if(TEST_MODE == 1){
	    	PhyLoopInit(speed); // 4=1000Mbps, 2=100Mbps, 1=10Mbps, change the number to change speed
	    }
	else {
		MacNormalInit(speed);
	}
	


    StartRunning();

}
