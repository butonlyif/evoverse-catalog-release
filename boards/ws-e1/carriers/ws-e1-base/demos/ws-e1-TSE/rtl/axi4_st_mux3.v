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
// 模块名称: axi4_st_mux3
// 功能描述: AXI4-Stream 3 选 1 复用器（纯组合）。select[1:0]:
//           2'b00 → In0；2'b01 → In1；2'b1x → In2。
//           未选中通路的 tready 恒 1（令其上游自由流动，与 axi4_st_mux 一致）。
// 接口说明: AXI4-Stream (8bit)
// 设计约束: 纯组合逻辑，无时钟
// ============================================================================
module axi4_st_mux3
(
//Select Interface
input  wire [1:0]                   mux_select,
//Mux In 0 Interface
input  wire [7:0]                   tdata0,
input  wire                         tvalid0,
input  wire                         tlast0,
input  wire                         tuser0,
output wire                         tready0,
//Mux In 1 Interface
input  wire [7:0]                   tdata1,
input  wire                         tvalid1,
input  wire                         tlast1,
input  wire                         tuser1,
output wire                         tready1,
//Mux In 2 Interface
input  wire [7:0]                   tdata2,
input  wire                         tvalid2,
input  wire                         tlast2,
input  wire                         tuser2,
output wire                         tready2,
//Mux Out Interface
output wire [7:0]                   tdata,
output wire                         tvalid,
output wire                         tlast,
output wire                         tuser,
input  wire                         tready
);
// Parameter Define

// Wire Define

/*----------------------------------------------------------------------------------*\
                                 The main code
\*----------------------------------------------------------------------------------*/

assign tdata  = (mux_select[1]) ? tdata2  :
                (mux_select[0]) ? tdata1  : tdata0;
assign tvalid = (mux_select[1]) ? tvalid2 :
                (mux_select[0]) ? tvalid1 : tvalid0;
assign tlast  = (mux_select[1]) ? tlast2  :
                (mux_select[0]) ? tlast1  : tlast0;
assign tuser  = (mux_select[1]) ? tuser2  :
                (mux_select[0]) ? tuser1  : tuser0;

assign tready0 = (mux_select == 2'b00) ? tready : 1'b1;
assign tready1 = (mux_select == 2'b01) ? tready : 1'b1;
assign tready2 = (mux_select[1] == 1'b1) ? tready : 1'b1;

endmodule

`default_nettype wire
