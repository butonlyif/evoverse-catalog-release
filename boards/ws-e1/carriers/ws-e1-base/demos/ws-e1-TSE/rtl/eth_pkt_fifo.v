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
`default_nettype none
`timescale 1 ns / 1 ns
//============================================================================
// 模块名称: eth_pkt_fifo
// 功能描述: 以太网帧数据 CPU 通路。RX 侧以 AXI-Stream 从机 tap 取收到的帧字节流
//           经跨时钟域 FIFO 交给 CPU（APB 读窗口）；TX 侧 CPU 经 APB 写窗口压入
//           帧字节流，以 AXI-Stream 主机送出。RX 溢出保护为帧粒度准入（SOF 判
//           水位、整帧丢弃）+ 溢出 sticky 标志（写 1 清除）。
// 接口说明: AXI4-Stream (8bit, tlast/tuser) + CPU 状态/数据窗口
// 设计约束: rx_clk 域 = MAC rx_axis_clk；apb_clk 域 = CPU APB 时钟；
//           两域可同频不同相（当前工程同为 50MHz），FIFO 结构天然支持 CDC
// 重要约束: TSEMAC UG 明确 rx_axis_mac_tready 背压不受支持（帧中拉低会静默损
//           坏帧），故 rx_tready 恒为 1；FIFO 剩余空间不足 FRAME_GUARD 时在帧
//           头整帧丢弃。FRAME_GUARD 必须 ≥ MAC frm_length 对应的 AXI 帧字数
//           （当前 1518-4=1514），启用 jumbo 时需同步加大。
// ============================================================================
module eth_pkt_fifo #(
    parameter FIFO_DEPTH  = 4096,   // 必须 2 的幂，且 > FRAME_GUARD
    parameter FRAME_GUARD = 1536    // RX 帧准入水位（字）：SOF 时需剩余空间 ≥ 此值
)(
    //RX Side (AXI4-Stream Slave, rx_clk domain)
    input  wire                         rx_clk,
    input  wire                         rx_rstn,
    input  wire [7:0]                   rx_tdata,
    input  wire                         rx_tvalid,
    input  wire                         rx_tlast,
    input  wire                         rx_tuser,
    output wire                         rx_tready,
    //TX Side (AXI4-Stream Master, tx_clk domain)
    input  wire                         tx_clk,
    input  wire                         tx_rstn,
    output wire [7:0]                   tx_tdata,
    output wire                         tx_tvalid,
    output wire                         tx_tlast,
    output wire                         tx_tuser,
    input  wire                         tx_tready,
    //CPU Status/Access (apb_clk domain)
    input  wire                         apb_clk,
    input  wire                         apb_rstn,
    output wire [11:0]                  rx_word_cnt,
    output wire                         rx_overflow,     //sticky, 写1清除
    input  wire                         rx_overflow_clr,
    input  wire                         rx_rd_en,        //读弹出脉冲
    output wire [9:0]                   rx_rddata,       //ShowAhead {tuser,tlast,tdata}
    output wire [12:0]                  tx_free_cnt,     //12 位语义：空时=DEPTH-1(4095)，满时=0
                                                        //（不用 4096=2^12 常数减法：该算术模式在
                                                        // 综合 13 位常数-12 位值+==0 比较时硅上出错，
                                                        // 见 DAYLOG 2026-11-02；4095 封顶避开边界）
    output wire                         tx_full,         //FIFO 真满标志（写域，综合稳健）
    input  wire [8:0]                   tx_wrdata,       //{tlast,tdata}
    input  wire                         tx_wr_en
);
// Parameter Define
localparam AW_C = $clog2(FIFO_DEPTH);

// Register Define
reg                             rx_overflow_r;
reg                             tx_tvalid_r;
reg [8:0]                       tx_payload_r;
reg                             frame_act_r;        //当前正在接收一帧（tlast 关闭）
reg                             frame_acc_r;        //本帧已准入（可写入 FIFO）
reg                             drop_toggle_r;      //rx_clk 域丢帧事件 toggle
(* ASYNC_REG = "TRUE" *) reg [2:0]  drop_sync_r;    //toggle 同步至 apb_clk
reg                             drop_toggle_d;      //同步链滞后拍

// Wire Define
wire [AW_C-1:0]                 rx_wrcnt;
wire                            rx_rdreq;
wire                            rx_rdempty;
wire [9:0]                      rx_q;
wire [AW_C-1:0]                 tx_wrcnt;
wire                            tx_rdreq;
wire                            tx_rdempty;
wire [8:0]                      tx_q;
wire                            tx_wrfull;
wire                            sof;                //帧首字节（tvalid 上升沿）
wire                            eof;                //帧尾字节
wire                            frame_accept;       //SOF 准入判决
wire                            rx_wr_gate;         //当前字节是否写入 FIFO
wire                            drop_event;         //apb_clk 域丢帧事件脉冲

/*----------------------------------------------------------------------------------*\
                                 The main code
\*----------------------------------------------------------------------------------*/

/*----------------- RX Side: AXI4-Stream tap -> CDC FIFO -----------------*/
//TSEMAC UG：rx_axis_mac_tready 背压不受支持（帧中拉低会静默损坏帧）→ 恒为 1
assign rx_tready = 1'b1;

//帧边界：FIFO 模式下帧中 tvalid 间隙合法，帧只由 tlast 关闭
assign sof = rx_tvalid && (frame_act_r == 1'b0);
assign eof = rx_tvalid && rx_tlast;

always @(posedge rx_clk or negedge rx_rstn)
begin
    if(rx_rstn == 1'b0)
        frame_act_r <= 1'b0;
    else if(eof == 1'b1)
        frame_act_r <= 1'b0;
    else if(sof == 1'b1)
        frame_act_r <= 1'b1;
end

//准入判决：SOF 时剩余空间需容纳一个最长帧（加宽位宽避免回绕）
assign frame_accept = (({1'b0, rx_wrcnt} + FRAME_GUARD) <= FIFO_DEPTH);

always @(posedge rx_clk or negedge rx_rstn)
begin
    if(rx_rstn == 1'b0)
        frame_acc_r <= 1'b0;
    else if(eof == 1'b1)
        frame_acc_r <= 1'b0;
    else if(sof == 1'b1)
        frame_acc_r <= frame_accept;
end

//帧首字节当拍用判决结果，后续字节用准入标志（无部分帧入 FIFO）
assign rx_wr_gate = sof ? frame_accept : frame_acc_r;

//丢帧事件（rx_clk 域）
always @(posedge rx_clk or negedge rx_rstn)
begin
    if(rx_rstn == 1'b0)
        drop_toggle_r <= 1'b0;
    else if((sof == 1'b1) && (frame_accept == 1'b0))
        drop_toggle_r <= ~drop_toggle_r;
end

DC_FIFO #(
    .FIFO_MODE                          ("ShowAhead"                    ),
    .DATA_WIDTH                         (10                             ),
    .FIFO_DEPTH                         (FIFO_DEPTH                     )
) u_rx_fifo
(
    //System Signal
    .Reset                              (!rx_rstn                       ),
    //Write Signal
    .WrClk                              (rx_clk                         ),
    .WrEn                               (rx_tvalid && rx_wr_gate        ),
    .WrDNum                             (rx_wrcnt                       ),
    .WrFull                             (                               ),
    .WrData                             ({rx_tuser, rx_tlast, rx_tdata} ),
    //Read Signal
    .RdClk                              (apb_clk                        ),
    .RdEn                               (rx_rdreq                       ),
    .RdDNum                             (                               ),
    .RdEmpty                            (rx_rdempty                     ),
    .RdData                             (rx_q                           )
);

assign rx_word_cnt = {{(12-AW_C){1'b0}}, rx_wrcnt};
assign rx_rddata   = rx_q;

//丢帧事件 2 级同步到 apb_clk 域并沿检测
always @(posedge apb_clk or negedge apb_rstn)
begin
    if(apb_rstn == 1'b0) begin
        drop_sync_r   <= 3'b000;
        drop_toggle_d <= 1'b0;
    end else begin
        drop_sync_r   <= {drop_sync_r[1:0], drop_toggle_r};
        drop_toggle_d <= drop_sync_r[2];
    end
end

assign drop_event = drop_sync_r[2] ^ drop_toggle_d;

//溢出 sticky：整帧被丢时置位，软件写 1 清除
always @(posedge apb_clk or negedge apb_rstn)
begin
    if(apb_rstn == 1'b0)
        rx_overflow_r <= 1'b0;
    else if(rx_overflow_clr == 1'b1)
        rx_overflow_r <= 1'b0;
    else if(drop_event == 1'b1)
        rx_overflow_r <= 1'b1;
end

assign rx_overflow = rx_overflow_r;

//APB 读弹出：ShowAhead 模式下 rx_q 当前有效，rd_en 弹出下一个
assign rx_rdreq = rx_rd_en && (rx_rdempty == 1'b0);

/*----------------- TX Side: CDC FIFO -> AXI4-Stream master -----------------*/
DC_FIFO #(
    .FIFO_MODE                          ("ShowAhead"                    ),
    .DATA_WIDTH                         (9                              ),
    .FIFO_DEPTH                         (FIFO_DEPTH                     )
) u_tx_fifo
(
    //System Signal
    .Reset                              (!tx_rstn                       ),
    //Write Signal
    .WrClk                              (apb_clk                        ),
    .WrEn                               (tx_wr_en && (tx_wrfull == 1'b0)),
    .WrDNum                             (tx_wrcnt                       ),
    .WrFull                             (tx_wrfull                      ),
    .WrData                             (tx_wrdata                      ),
    //Read Signal
    .RdClk                              (tx_clk                         ),
    .RdEn                               (tx_rdreq                       ),
    .RdDNum                             (                               ),
    .RdEmpty                            (tx_rdempty                     ),
    .RdData                             (tx_q                           )
);

//free = 4095 - fill：全 12 位算术，无 2^12 常数边界；满时强制 0（配合 tx_full）
assign tx_free_cnt = tx_wrfull ? 13'd0 : (13'd4095 - {1'b0, tx_wrcnt});
assign tx_full     = tx_wrfull;

//AXI4-Stream master：非空且（空闲或对端就绪）时弹出
assign tx_rdreq = (tx_rdempty == 1'b0) && ((tx_tvalid_r == 1'b0) || (tx_tready == 1'b1));

always @(posedge tx_clk or negedge tx_rstn)
begin
    if(tx_rstn == 1'b0)
        tx_tvalid_r <= 1'b0;
    else if(tx_rdreq == 1'b1)
        tx_tvalid_r <= 1'b1;
    else if(tx_tready == 1'b1)
        tx_tvalid_r <= 1'b0;
end

always @(posedge tx_clk or negedge tx_rstn)
begin
    if(tx_rstn == 1'b0)
        tx_payload_r <= 9'h0;
    else if(tx_rdreq == 1'b1)
        tx_payload_r <= tx_q;
end

assign tx_tdata  = tx_payload_r[7:0];
assign tx_tlast  = tx_payload_r[8];
assign tx_tuser  = 1'b0;
assign tx_tvalid = tx_tvalid_r;

endmodule

`default_nettype wire
