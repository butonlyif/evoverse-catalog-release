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
// 1.0 Initial rev (Efinix TSEMAC example design)
// 1.1 tready 背压改造：TSEMAC UG 明确 rx_axis_mac_tready 背压不受支持（帧中
//     拉低会静默损坏帧），tready 改恒 1；溢出保护改为帧粒度准入——SOF 时剩
//     余空间不足 FRAME_GUARD 则整帧丢弃，FIFO 中只有完整帧。
//
// *******************************
`timescale 1 ns / 1 ns
`default_nettype none
module mac_rx2tx
(
//Globle Signals
//
//Receive AXI4-Stream Interface
input  wire                     rx_axis_clk,
input  wire                     rx_axis_rstn,
input  wire [7:0]               rx_axis_mac_tdata,
input  wire                     rx_axis_mac_tvalid,
input  wire                     rx_axis_mac_tlast,
input  wire                     rx_axis_mac_tuser,
output wire                     rx_axis_mac_tready,
//Transmit AXI4-Stream Interface
input  wire                     tx_axis_clk,
input  wire                     tx_axis_rstn,
output  reg     [7:0]           tx_axis_mac_tdata,
output  reg                     tx_axis_mac_tvalid,
output  reg                     tx_axis_mac_tlast,
output  reg                     tx_axis_mac_tuser,
input  wire                     tx_axis_mac_tready
);
// Parameter Define
localparam FRAME_GUARD = 1536;   // 帧准入水位（字）≥ 最长 RX AXI 帧 1514

// Register Define
reg                             frame_act_r;    //当前正在接收一帧（tlast 关闭）
reg                             frame_acc_r;    //本帧已准入（可写入 FIFO）

// Wire Define
wire    [9:0]                   u1_data;
wire                            u1_wrreq;
wire                            u1_rdreq;
wire    [9:0]                   u1_q;
wire                            u1_empty;
wire    [10:0]                  u1_wrcnt;
wire                            sof;            //帧首字节
wire                            eof;            //帧尾字节
wire                            frame_accept;   //SOF 准入判决

/*----------------------------------------------------------------------------------*\
                                 The main code
\*----------------------------------------------------------------------------------*/

/*----------------------- Rx Clock Region ----------------------------*/
//TSEMAC UG：rx_axis_mac_tready 背压不受支持 → 恒为 1
assign rx_axis_mac_tready = 1'b1;

//帧边界：帧中 tvalid 间隙合法，帧只由 tlast 关闭
assign sof = rx_axis_mac_tvalid && (frame_act_r == 1'b0);
assign eof = rx_axis_mac_tvalid && rx_axis_mac_tlast;

always @(posedge rx_axis_clk or negedge rx_axis_rstn)
begin
    if(rx_axis_rstn == 1'b0)
        frame_act_r <= 1'b0;
    else if(eof == 1'b1)
        frame_act_r <= 1'b0;
    else if(sof == 1'b1)
        frame_act_r <= 1'b1;
end

//准入判决：SOF 时剩余空间需容纳一个最长帧（加宽位宽避免回绕）
assign frame_accept = (({1'b0, u1_wrcnt} + FRAME_GUARD) <= 2048);

always @(posedge rx_axis_clk or negedge rx_axis_rstn)
begin
    if(rx_axis_rstn == 1'b0)
        frame_acc_r <= 1'b0;
    else if(eof == 1'b1)
        frame_acc_r <= 1'b0;
    else if(sof == 1'b1)
        frame_acc_r <= frame_accept;
end

/*----------------------- Fifo 1 Region ----------------------------*/
DC_FIFO #(
    .FIFO_MODE                          ("ShowAhead"                        ),
    .DATA_WIDTH                         (10                                 ),
    .FIFO_DEPTH                         (2048                               )
)
u1
(
  //System Signal
    .Reset                              (!rx_axis_rstn                      ),
  //Write Signal
    .WrClk                              (rx_axis_clk                        ),
    .WrEn                               (u1_wrreq                           ),
    .WrDNum                             (u1_wrcnt                           ),
    .WrFull                             (                                   ),
    .WrData                             (u1_data                            ),
  //Read Signal
    .RdClk                              (tx_axis_clk                        ),
    .RdEn                               (u1_rdreq                           ),
    .RdDNum                             (                                   ),
    .RdEmpty                            (u1_empty                           ),
    .RdData                             (u1_q                               )
);

assign u1_data = {rx_axis_mac_tuser,rx_axis_mac_tlast,rx_axis_mac_tdata};
//帧首字节当拍用判决结果，后续字节用准入标志（无部分帧入 FIFO）
assign u1_wrreq = (rx_axis_mac_tvalid == 1'b1) &&
                  (sof ? frame_accept : frame_acc_r);
assign u1_rdreq = (u1_empty == 1'b0) && ((tx_axis_mac_tvalid == 1'b0) || (tx_axis_mac_tready == 1'b1));

/*----------------------- Tx Clock Region ----------------------------*/

always @(posedge tx_axis_clk or negedge tx_axis_rstn)
begin
    if(tx_axis_rstn == 1'b0)
        tx_axis_mac_tvalid <= 1'b0;
	else if(u1_rdreq == 1'b1)
        tx_axis_mac_tvalid <= 1'b1;
    else if(tx_axis_mac_tready == 1'b1)
        tx_axis_mac_tvalid <= 1'b0;
end

always @(posedge tx_axis_clk or negedge tx_axis_rstn)
begin
    if(tx_axis_rstn == 1'b0)
        tx_axis_mac_tdata <= 8'h0;
    else if(u1_rdreq == 1'b1)
        tx_axis_mac_tdata <= u1_q[7:0];
	else if(tx_axis_mac_tready == 1'b1)
        tx_axis_mac_tdata <= 8'h0;
end

always @(posedge tx_axis_clk or negedge tx_axis_rstn)
begin
    if(tx_axis_rstn == 1'b0)
        tx_axis_mac_tlast <= 1'b0;
    else if(u1_rdreq == 1'b1)
        tx_axis_mac_tlast <= u1_q[8];
	else if(tx_axis_mac_tready == 1'b1)
        tx_axis_mac_tlast <= 1'b0;
end

always @(posedge tx_axis_clk or negedge tx_axis_rstn)
begin
    if(tx_axis_rstn == 1'b0)
        tx_axis_mac_tuser <= 1'b0;
    else if((u1_rdreq == 1'b1) && (u1_q[8] == 1'b1))
        tx_axis_mac_tuser <= u1_q[9];
	else if(tx_axis_mac_tready == 1'b1)
        tx_axis_mac_tuser <= 1'b0;
end

endmodule
`default_nettype wire
