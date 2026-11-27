/////////////////////////////////////////////////////////////////////////////
//           _____       
//          / _______    Copyright (C) 2013-2020 Efinix Inc. All rights reserved.
//         / /       \   
//        / /  ..    /   
//       / / .'     /    
//    __/ /.'      /     
//   __   \       /      
//  /_/ /\ \_____/ /     
// ____/  \_______/      
//
// *******************************
// Revisions:
// 1.0 Initial rev
//
// *******************************
`timescale 1 ns / 1 ns
module reg_apb3#(
    parameter                       ADDR_WTH = 10
)
(
//Globle Signals
//
//APB3 Slave Interface
input                           s_apb3_clk,
input                           s_apb3_rstn,
input           [ADDR_WTH-1:0]  s_apb3_paddr,
input                           s_apb3_psel,
input                           s_apb3_penable,
output  reg                     s_apb3_pready,
input                           s_apb3_pwrite,//0:rd; 1:wr;
input           [31:0]          s_apb3_pwdata,
output  reg     [31:0]          s_apb3_prdata,
output  wire                    s_apb3_pslverror,
//Cfg Space Registers
//--Example Registers Field
output  reg                     mac_sw_rst,
output  reg                     axi4_st_mux_select,
output  reg                     pat_mux_select,
output  reg                     udp_pat_gen_en,
output  reg                     mac_pat_gen_en,
output  reg                     raw10_mode,     //RAW10 1080p@30fps 视频流模式（udp_pat_gen_v2）
output  reg                     cam_src_en,     //G10：0x208 bit6，相机 RAW10 直推 UDP 流（udp_pat_gen_v2 cam 源）
output  reg                     fifo_src_sel,   //G11n16：0x208 bit7，FIFO 写源选择 0=相机 RX 1=raw10_pat_src（200M 域帧边界锁存）
output  reg                     pat_gen_kill,   //包边界停车（0x208 bit3，udp_pat_gen_v2 2026-11-06 模式切换）
output  reg     [1:0]           pat_mode,       //RAW10 图案选择：0彩条 1横向灰度 2垂直灰度 3棋盘
output  reg     [15:0]          pat_gen_num,
output  reg     [15:0]          pat_gen_ipg,
output  reg     [47:0]          pat_dst_mac,
output  reg     [47:0]          pat_src_mac,
output  reg     [15:0]          pat_mac_dlen,
output  reg     [31:0]          pat_src_ip,
output  reg     [31:0]          pat_dst_ip,
output  reg     [15:0]          pat_src_port,
output  reg     [15:0]          pat_dst_port,
output  reg     [15:0]          pat_udp_dlen,
//Ethernet Packet FIFO Interface (eth_pkt_fifo)
input  wire [11:0]              eth_rx_word_cnt,
input  wire                     eth_rx_overflow,
output wire                     eth_rx_overflow_clr,
output wire                     eth_rx_rd_en,
input  wire [9:0]               eth_rx_rddata,      //{tuser,tlast,tdata}
input  wire [12:0]              eth_tx_free_cnt,    //12 位语义：空=4095，满=0
input  wire                     eth_tx_full,        //FIFO 真满标志
input  wire [15:0]              eth_dbg_rxc_cnt,    //RX 诊断：rgmii_rxc 引脚时钟计数
input  wire [15:0]              eth_dbg_pll_cnt,    //RX 诊断：pll_rgmii_rx_clk 输出计数
input  wire                     pll_rgmii_locked,   //RX PLL 锁定状态（直通）
input  wire [9:0]               pat_dbg_i,          //v2 状态探针 {raw10_r,pat_en,inf,state[2:0],frame_tick,en_d1,0}
//Camera CSI-2 链路探针（P1/G8，异步跨域直读：单调计数允许小撕裂误差，判据看步进）
input  wire [31:0]              cam_dt_cnt,         //RAW10 有效像素拍计数（csi_clk_200m 域）
input  wire [31:0]              cam_sof_dbg,        //G11j 0x2CC {full,armed,sof_cnt[29:0]}（200M 域）
input  wire [31:0]              cam_rawdt_cnt,      //G11j 0x2D0 raw_tvalid 输出拍计数（200M 域）
input  wire [31:0]              cam_mark_dbg,       //G11j-3 0x2D4 tuser[1] 裸计数（200M 域）
input  wire [31:0]              cam_sync_dbg,       //G11j-3 0x2D8 tuser[0] 裸计数（200M 域）
input  wire [31:0]              cam_vsedge_dbg,     //G11j-3 0x2DC vs 上升沿计数（200M 域）
input  wire [31:0]              cam_hsedge_dbg,     //G11j-3 0x2E0 hs 上升沿计数（200M 域）
input  wire [31:0]              cam_fifoptr_dbg,    //G11n14 0x2E4 {bank_wcnt[17:0], bank_rq[13:0]}（cam_fifo_bank 模 163840 指针）
input  wire [31:0]              cam_fifoptr2_dbg,   //G11n14 0x2E8 {bank_rq[17:0], 14'b0}——rq={ptr2[31:14],ptr1[13:0]} 拼装
input  wire [31:0]              cam_fullrej_cnt,    //G11m 0x2EC cam FIFO 拒收写累计（wr_en&&full，丢数定量）
output  reg                     cam_udp_pause,      //G11m 0x2F4 bit0 pacer 软暂停（cam 控制帧注入协议）
input  wire [31:0]              cam_tx_pkt_cnt,     //G11n 0x2F0 gen 包完成数（125M 跨域直读）
input  wire [31:0]              cam_tx_bp_cnt,      //G11n 0x2F8 gen tvalid&&!tready 背压拍数（125M 跨域直读）
input  wire [31:0]              cam_rd_cnt,         //G11n2 0x2FC cam_quad_rd 拉高累计（=FIFO 弹出，裁决收支缺口）
input  wire [31:0]              cam_ipgwait_cnt,    //G11n2 0x300 gen S_IPG 等待 cam_pkt_go 白等拍（裁决 occ 门控）
input  wire [15:0]              cam_err_sot_cnt,    //DPHY SOT 错误事件计数（csi_clk_100m 域）
input  wire [15:0]              cam_err_sotsync_cnt,//DPHY SOT-SYNC 错误事件计数（csi_clk_100m 域）
input  wire [15:0]              cam_err_esc_cnt,    //DPHY ESC 错误事件计数（csi_clk_100m 域）
input  wire [15:0]              cam_err_linestate_cnt, //DPHY LINESTATE 错误事件计数（csi_clk_100m 域）
input  wire [31:0]              cam_status,         //相机链路状态（已 2FF 同步进 APB 域）
input  wire [15:0]              cam_i2c_stat,       //G10 防删探针：{en,done,fail,busy,round[1:0],retry[3:0],4'h0}（'h093 魔数同构独立消费链）
input  wire [15:0]              free200_cnt,        //G10 诊断：200M 域自由计数（0x2C4 低 16 位）
input  wire [15:0]              free100_cnt,        //G10 诊断：100M 域自由计数（0x2C4 高 16 位）
input  wire [7:0]               cam_lane_status,    //G8 诊断：[7:4]数据lane STOPSTATE 实时，[3:0]lane_seen 粘滞（VALID 出现过）
//G9 单帧捕获（专用 RAM dump）：arm + 状态/弹出窗口
output wire                     cap_rd_en,          //'h0AE 读脉冲（捕获读指针步进）
output reg                      cap_arm,            //'h2B0 bit0 armed；done 后自动清零
input  wire                     cap_done,           //一帧捕获完成（已同步到 APB 域）
input  wire [15:0]              cap_ptr_stat,       //捕获读出计数现状（64 行=30720 需 >12 位）
input  wire [31:0]              cap_rdata_lo,       //当前拍 [31:0]
input  wire [7:0]               cap_rdata_hi,       //当前拍 [39:32]
input  wire [31:0]              cam_udp_status,     //G10 pacer 状态（G11n5 布局：bit31=armed,bit12=active,bit11=done,bits10:0=occ）
input  wire [31:0]              cam_ipgnact_cnt,    //G11n5 0x304 白等成分①：S_IPG 且帧不活跃
input  wire [31:0]              cam_ipgnoarm_cnt,   //G11n5 0x308 白等成分②：S_IPG 且 active 且 !armed
input  wire [31:0]              cam_fullhi_cnt,     //G11n9 0x30C full=1 拍累计（200M 跨域直读）
input  wire [31:0]              cam_fullrise_cnt,   //G11n9 0x310 full 上升沿数（满事件次数）
input  wire [31:0]              cam_rejrun_max,     //G11n9 0x314 连续 rej 最大拍数（峰值保持）
input  wire [31:0]              cam_tvrun_max,      //G11n9 0x318 连续 tvalid 最大拍数（峰值保持）
input  wire [31:0]              cam_occ_dbg,        //G11n9 0x31C pacer {occ_min,occ_peak}（sof 清零）
input  wire [31:0]              cam_hsgap_max,      //G11n11 0x320 hs→hs 间隔最大拍（G11n13 帧内语义）
input  wire [31:0]              cam_hsgap_min,      //G11n11 0x324 hs→hs 间隔最小拍（保持型）
input  wire [31:0]              cam_hsgap_a,        //G11n13 0x328 直方图 <3500 拍（近距行）
input  wire [31:0]              cam_hsgap_b,        //G11n13 0x32C 直方图 3500..5499
input  wire [31:0]              cam_hsgap_c,        //G11n13 0x330 直方图 5500..7999（正常带）
input  wire [31:0]              cam_hsgap_d,        //G11n13 0x334 直方图 >=8000（远距/vblank）
output wire [8:0]               eth_tx_wrdata,      //{tlast,tdata}
output wire                     eth_tx_wr_en,
//TX mux3 software-frame select (1: sw frame path)
output reg                     eth_sw_tx_sel
);
// Parameter Define 

// Register Define
reg     [ADDR_WTH-3:0]          loc_addr;
reg                             loc_wr_vld;
reg                             loc_rd_vld;

// Wire Define

/*----------------------------------------------------------------------------------*\
                                 The main code
\*----------------------------------------------------------------------------------*/
//apb3 interface
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        loc_addr <= {ADDR_WTH-2{1'b0}};
	else if((s_apb3_psel == 1'b1) && (s_apb3_penable == 1'b0))
		loc_addr <= s_apb3_paddr[2+:ADDR_WTH-2];
end

always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        loc_wr_vld <= 1'b0;
	else if((s_apb3_psel == 1'b1) && (s_apb3_penable == 1'b0) && (s_apb3_pwrite == 1'b1))
		loc_wr_vld <= 1'b1;
    else
        loc_wr_vld <= 1'b0;
end

always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        loc_rd_vld <= 1'b0;
	else if((s_apb3_psel == 1'b1) && (s_apb3_penable == 1'b0) && (s_apb3_pwrite == 1'b0))
		loc_rd_vld <= 1'b1;
    else
        loc_rd_vld <= 1'b0;
end

always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        s_apb3_pready <= 1'b0;
	else if((loc_wr_vld == 1'b1) || (loc_rd_vld == 1'b1))
		s_apb3_pready <= 1'b1;
    else
        s_apb3_pready <= 1'b0;
end

always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        s_apb3_prdata <= 32'h0;
	else if(loc_rd_vld == 1'b1)
        begin
            case(loc_addr)
            //Example Registers Field
            'h080 : s_apb3_prdata <= {31'h0,mac_sw_rst};
            'h081 : s_apb3_prdata <= {27'h0,eth_sw_tx_sel,2'b0,pat_mux_select,axi4_st_mux_select};
            'h082 : s_apb3_prdata <= {24'h0, fifo_src_sel, cam_src_en, pat_mode, pat_gen_kill, raw10_mode, mac_pat_gen_en, udp_pat_gen_en};
            'h083 : s_apb3_prdata <= {pat_gen_ipg,pat_gen_num};
            'h084 : s_apb3_prdata <= pat_dst_mac[31:0];
            'h085 : s_apb3_prdata <= {16'h0,pat_dst_mac[47:32]};
            'h086 : s_apb3_prdata <= pat_src_mac[31:0];
            'h087 : s_apb3_prdata <= {16'h0,pat_src_mac[47:32]};
            'h088 : s_apb3_prdata <= {16'h0,pat_mac_dlen};
            'h089 : s_apb3_prdata <= pat_src_ip;
            'h08a : s_apb3_prdata <= pat_dst_ip;
            'h08b : s_apb3_prdata <= {pat_dst_port,pat_src_port};
            'h08c : s_apb3_prdata <= {16'h0,pat_udp_dlen};
            //Ethernet Packet FIFO
            'h090 : s_apb3_prdata <= {19'h0, eth_rx_overflow, eth_rx_word_cnt};
            'h091 : s_apb3_prdata <= {22'h0, eth_rx_rddata};
            'h092 : s_apb3_prdata <= {5'h0, pat_dbg_i[8:0], eth_tx_full, eth_tx_free_cnt};  //高9位=v2 探针（借用，'h92 分支必然在网表）
            'h093 : s_apb3_prdata <= {22'h0C0DEBA, pat_dbg_i};  //高22位=magic（截断为 0xDEBA→读回 0x037AE8xx），低10位=探针；2026-11-06 对拍证伪 paddr[3] 损伤，地址可任意选
            'h094 : s_apb3_prdata <= {eth_dbg_rxc_cnt, eth_dbg_pll_cnt};
            'h095 : s_apb3_prdata <= {31'h0, pll_rgmii_locked};
            //Camera CSI-2 探针（P1/G8）：APB 字节地址 0x270-0x2A0
            //（G7 时的"0x258/0x25C 别名"实为未映射地址 stale prdata；对拍标定后
            //  读通道可信，地址选择不再受限 —— 2026-11-06）
            'h09C : s_apb3_prdata <= cam_dt_cnt;                                     //0x270 RAW10 有效拍计数
            'h0A0 : s_apb3_prdata <= {cam_err_linestate_cnt, cam_err_esc_cnt};       //0x280 {LINESTATE, ESC}
            'h0A4 : s_apb3_prdata <= {cam_err_sotsync_cnt, cam_err_sot_cnt};         //0x290 {SOTSYNC, SOT}
            'h0A8 : s_apb3_prdata <= cam_status;                                     //0x2A0 状态（见 ws_e1_tse.v cam_status 位定义）
            'h0B0 : s_apb3_prdata <= cam_udp_status;                                 //0x2C0 pacer 状态
            'h0C1 : s_apb3_prdata <= cam_ipgnact_cnt;                               //0x304 白等①帧门关
            'h0C2 : s_apb3_prdata <= cam_ipgnoarm_cnt;                              //0x308 白等②occ门
            'h0C3 : s_apb3_prdata <= cam_fullhi_cnt;                                //0x30C full=1 拍累计（G11n9）
            'h0C4 : s_apb3_prdata <= cam_fullrise_cnt;                              //0x310 full 上升沿数（G11n9）
            'h0C5 : s_apb3_prdata <= cam_rejrun_max;                                //0x314 连续 rej 最大拍数（G11n9）
            'h0C6 : s_apb3_prdata <= cam_tvrun_max;                                 //0x318 连续 tvalid 最大拍数（G11n9）
            'h0C7 : s_apb3_prdata <= cam_occ_dbg;                                   //0x31C {occ_min,occ_peak}（G11n9）
            'h0C8 : s_apb3_prdata <= cam_hsgap_max;                                 //0x320 hs 间隔最大拍（G11n11/13 帧内）
            'h0C9 : s_apb3_prdata <= cam_hsgap_min;                                 //0x324 hs 间隔最小拍（G11n11）
            'h0CA : s_apb3_prdata <= cam_hsgap_a;                                   //0x328 直方 <3500（G11n13）
            'h0CB : s_apb3_prdata <= cam_hsgap_b;                                   //0x32C 直方 3500..5499
            'h0CC : s_apb3_prdata <= cam_hsgap_c;                                   //0x330 直方 5500..7999
            'h0CD : s_apb3_prdata <= cam_hsgap_d;                                   //0x334 直方 >=8000
            'h0B1 : s_apb3_prdata <= {free100_cnt, free200_cnt};                     //0x2C4 自由计数器（步进=钟活）
            'h0B2 : s_apb3_prdata <= {16'h0, cam_i2c_stat};                          //0x2C8 i2c init 状态独立链（防综合删除）
            'h0B3 : s_apb3_prdata <= cam_sof_dbg;                                    //0x2CC {full,armed,sof_cnt[29:0]} G11j 输出侧诊断
            'h0B4 : s_apb3_prdata <= cam_rawdt_cnt;                                  //0x2D0 raw_tvalid 输出拍计数（G11j）
            'h0B5 : s_apb3_prdata <= cam_mark_dbg;                                   //0x2D4 tuser[1] 裸计数（G11j-3）
            'h0B6 : s_apb3_prdata <= cam_sync_dbg;                                   //0x2D8 tuser[0] 裸计数（G11j-3）
            'h0B7 : s_apb3_prdata <= cam_vsedge_dbg;                                 //0x2DC vs 上升沿计数（G11j-3）
            'h0B8 : s_apb3_prdata <= cam_hsedge_dbg;                                 //0x2E0 hs 上升沿计数（G11j-3）
            'h0B9 : s_apb3_prdata <= cam_fifoptr_dbg;                                //0x2E4 {wcnt,wr_bin,rd_sync_bin}（G11j-4）
            'h0BA : s_apb3_prdata <= cam_fifoptr2_dbg;                               //0x2E8 {rd_bin,wgray,0}（G11j-4）
            'h0BB : s_apb3_prdata <= cam_fullrej_cnt;                                //0x2EC FIFO 拒收写累计（G11m 丢数定量）
            'h0BC : s_apb3_prdata <= cam_tx_pkt_cnt;                                 //0x2F0 gen 包完成数（G11n 发包率）
            'h0BE : s_apb3_prdata <= cam_tx_bp_cnt;                                  //0x2F8 gen 背压拍数（G11n MAC tready 定量）
            'h0BF : s_apb3_prdata <= cam_rd_cnt;                                     //0x2FC cam_quad_rd 拉高累计（G11n2 FIFO 弹出）
            'h0C0 : s_apb3_prdata <= cam_ipgwait_cnt;                                //0x300 gen S_IPG 白等拍（G11n2 occ 门控定量）
            'h0AB : s_apb3_prdata <= {24'h0, cam_lane_status};                       //0x2AC 每 lane 活动探针
            'h0AC : s_apb3_prdata <= {14'h0, cap_done, cap_arm, cap_ptr_stat};       //0x2B0 捕获状态（cnt 16 位）
            'h0AD : s_apb3_prdata <= cap_rdata_lo;                                   //0x2B4 当前拍低 32 位
            'h0AE : s_apb3_prdata <= {24'h0, cap_rdata_hi};                          //0x2B8 当前拍高 8 位（读后指针步进）
            endcase
        end
end

assign s_apb3_pslverror = 1'b0;

//G9 捕获 arm：单拍脉冲（写 0x2B0 bit0=1 出一拍，顶层沿检测捕获下一帧；
//与 done 解耦——done 保持期间可再次 arm，无死锁）
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        cap_arm <= 1'b0;
    else if((loc_wr_vld == 1'b1) && (loc_addr == 'h0AC))
        cap_arm <= s_apb3_pwdata[0];
    else
        cap_arm <= 1'b0;
end

//G9 捕获读脉冲：0x2B8 读即步进顶层读指针（与 prdata 采样同拍，读后生效）
assign cap_rd_en = loc_rd_vld && (loc_addr == 'h0AE);

/*----------------------------------------------------------------------------------*\
    Register Space -- Example Registers Field
\*----------------------------------------------------------------------------------*/
//loc_addr = 0x080; axi_addr = 0x200; RW;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            mac_sw_rst <= 1'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h080))
        begin
            mac_sw_rst <= s_apb3_pwdata[0];
        end
end

//G11m：0x2F4 bit0 pacer 软暂停（cam 控制帧注入：pause→包边界停车→mux 切换
//发送→还原→unpause，全程无竞争无丢数）
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'h0)
        cam_udp_pause <= 1'h0;
    else if((loc_wr_vld == 1'b1) && (loc_addr == 'h0BD))
        cam_udp_pause <= s_apb3_pwdata[0];
end

//loc_addr = 0x081; axi_addr = 0x204; RW;
//[axi4_st_mux_select] 0:pat tx mode; 1:rx2tx loopback mode;
//[pat_mux_select] 0:udp pat; 1:mac pat;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            axi4_st_mux_select <= 1'h0;
            pat_mux_select <= 1'h0;
            eth_sw_tx_sel <= 1'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h081))
        begin
            axi4_st_mux_select <= s_apb3_pwdata[0];
            pat_mux_select <= s_apb3_pwdata[1];
            eth_sw_tx_sel <= s_apb3_pwdata[4];
        end
end

//loc_addr = 0x082; axi_addr = 0x208; RW;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            udp_pat_gen_en <= 1'h0;
            mac_pat_gen_en <= 1'h0;
            raw10_mode     <= 1'h0;
            pat_gen_kill   <= 1'h0;
            pat_mode       <= 2'h0;
            cam_src_en     <= 1'h0;
            fifo_src_sel   <= 1'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h082))
        begin
            udp_pat_gen_en <= s_apb3_pwdata[0];
            mac_pat_gen_en <= s_apb3_pwdata[1];
            raw10_mode     <= s_apb3_pwdata[2];
            pat_gen_kill   <= s_apb3_pwdata[3];
            pat_mode       <= s_apb3_pwdata[5:4];
            cam_src_en     <= s_apb3_pwdata[6];
            fifo_src_sel   <= s_apb3_pwdata[7];
        end
end

//loc_addr = 0x083; axi_addr = 0x20c; RW;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            pat_gen_num <= 16'h0;
            pat_gen_ipg <= 16'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h083))
        begin
            pat_gen_num <= s_apb3_pwdata[15:0];
            pat_gen_ipg <= s_apb3_pwdata[31:16];
        end
end

//loc_addr = 0x084; axi_addr = 0x210; RW;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            pat_dst_mac[31:0] <= 32'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h084))
        begin
            pat_dst_mac[31:0] <= s_apb3_pwdata[31:0];
        end
end

//loc_addr = 0x085; axi_addr = 0x214; RW;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            pat_dst_mac[47:32] <= 16'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h085))
        begin
            pat_dst_mac[47:32] <= s_apb3_pwdata[15:0];
        end
end

//loc_addr = 0x086; axi_addr = 0x218; RW;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            pat_src_mac[31:0] <= 32'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h086))
        begin
            pat_src_mac[31:0] <= s_apb3_pwdata[31:0];
        end
end

//loc_addr = 0x087; axi_addr = 0x21c; RW;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            pat_src_mac[47:32] <= 16'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h087))
        begin
            pat_src_mac[47:32] <= s_apb3_pwdata[15:0];
        end
end

//loc_addr = 0x088; axi_addr = 0x220; RW;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            pat_mac_dlen <= 16'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h088))
        begin
            pat_mac_dlen <= s_apb3_pwdata[15:0];
        end
end

//loc_addr = 0x089; axi_addr = 0x224; RW;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            pat_src_ip <= 32'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h089))
        begin
            pat_src_ip <= s_apb3_pwdata[31:0];
        end
end

//loc_addr = 0x08a; axi_addr = 0x228; RW;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            pat_dst_ip <= 32'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h08a))
        begin
            pat_dst_ip <= s_apb3_pwdata[31:0];
        end
end

//loc_addr = 0x08b; axi_addr = 0x22c; RW;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            pat_src_port <= 16'h0;
            pat_dst_port <= 16'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h08b))
        begin
            pat_src_port <= s_apb3_pwdata[15:0];
            pat_dst_port <= s_apb3_pwdata[31:16];
        end
end

//loc_addr = 0x08c; axi_addr = 0x230; RW;
always @(posedge s_apb3_clk or negedge s_apb3_rstn)
begin
    if(s_apb3_rstn == 1'b0)
        begin
            pat_udp_dlen <= 16'h0;
        end
	else if((loc_wr_vld == 1'b1) && (loc_addr == 'h08c))
        begin
            pat_udp_dlen <= s_apb3_pwdata[15:0];
        end
end

/*----------------------------------------------------------------------------------*\
    Register Space -- The End
\*----------------------------------------------------------------------------------*/

/*----------------------------------------------------------------------------------*\
    Ethernet Packet FIFO window
\*----------------------------------------------------------------------------------*/
//loc_addr = 0x090; axi_addr = 0x240; RX_STATUS: R={19'h0,overflow,word_cnt[11:0]};
//                  W: bit0=1 清除溢出 sticky
assign eth_rx_overflow_clr = (loc_wr_vld == 1'b1) && (loc_addr == 'h090) && s_apb3_pwdata[0];

//loc_addr = 0x091; axi_addr = 0x244; RX_DATA: R={22'h0,{tuser,tlast,tdata}}, 读自动弹出
assign eth_rx_rd_en = (loc_rd_vld == 1'b1) && (loc_addr == 'h091);

//loc_addr = 0x092; axi_addr = 0x248; TX_STATUS: R={20'h0,full,free_cnt[11:0]}

//loc_addr = 0x093; axi_addr = 0x24c; TX_DATA: W={tlast,tdata[7:0]}
assign eth_tx_wrdata = s_apb3_pwdata[8:0];
assign eth_tx_wr_en  = (loc_wr_vld == 1'b1) && (loc_addr == 'h093);

endmodule
