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
//     THE  DESIGN, CODE, OR INFORMATION ARE PROVIDED "AS IS" AND
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
////////////////////////////////////////////////////////////////////////////////
#pragma once
/************************** Project Header File ***************************/
#define PRINTF_EN           1
#define TEST_MODE           0               //0 : Normal Mode — 统一应用（2026-11-06）：boot 进流模式
                                            //    （PAT_TYPE 选流类型），PC 经 UDP 10006 运行时切换
                                            //    t/v/n/s + 图案 0-3，无需重编译
                                            //1 : Link partner Test Mode;
                                            //2 : boot 进网络服务（统一应用的 netsvc 初态，
                                            //    之后同样可由 PC 运行时切流）

#define PAT_NUM 	        0               //0=无限流（G6 压测需持续 60s）
#define PAT_DLEN	        1458            //1500B 帧（G6：线速载荷上限 959Mbps）
#define PAT_IPG		        12              //线速最小帧间隙（12B=96 拍@125M 8bit）
#define PAT_TYPE	        0               //0 : UDP Pattern(递增,v2兼容,G6 千兆压测);
                                            //1 : MAC Pattern;
                                            //2 : RAW10 1080p@30fps 视频流(udp_pat_gen_v2)
#define DST_MAC_H 	        0xffff
#define DST_MAC_L 	        0xffffffff
#define SRC_MAC_H 	        0xeae8
#define SRC_MAC_L 	        0x5e0060c8
#define SRC_IP 		        0x0a000008      // 10.0.0.8  (board)
#define DST_IP 		        0x0a000003      // 10.0.0.3  (PC NIC，2026-11-06 由 .2 迁移)
#define SRC_PORT	        0x0521
#define DST_PORT	        0x2715
#define PAT_CTRL_PORT       10006   //TEST_MODE=0 图案控制端口：载荷 '0'..'3' 切换图案

/************************** System Header File ***************************/
#define PHY_ADDR            0x0             // YT8531 responds at MDIO addr 0 (board strap)

/************************** HW Header File ***************************/
#define TSEMAC_CSR          IO_APB_SLAVE_0_INPUT
#define TSEMAC_BASE         IO_APB_SLAVE_0_INPUT

/************************** Application Header File ***************************/
#define TX_ENA_MASK    		0xFFFFFFFE
#define RX_ENA_MASK    		0xFFFFFFFD
#define XON_GEN_MASK 		0xFFFFFFFB
#define PROMIS_EN_MASK   	0xFFFFFFEF
#define PAD_EN_MASK   		0xFFFFFFDF
#define CRC_FWD_MASK   		0xFFFFFFBF
#define PAUSE_IGNORE_MASK   0xFFFFFEFF
#define TX_ADDR_INS_MASK   	0xFFFFFBFF
#define LOOP_ENA_MASK   	0xFFFF7FFF
#define ETH_SPEED_MASK   	0xFFF8FFFF
#define XOFF_GEN_MASK 		0xFFBFFFFF
#define CNT_RST_MASK 		0x7FFFFFFF
