/////////////////////////////////////////////////////////////////////////////
// Module    : raw10_pat_src
// Function  : G11n16 图案源（200MHz 相机域）：以相机 AXI-Stream 窗口流同构接口
//             自由运行输出 1080p RAW10 测试图案，写入与相机同一条 cam_fifo_bank
//             链路（复用 G10 写路径 + 魔数插入 + pacer + gen 相机模式）。
//             旧 125M gen 直发图案路径（pattern_quad/frame_tick）删除（G11n16）。
// Interface : 复刻 raw_2_axi4st 输出：tdata[39:0] / tvalid / tlast /
//             tuser[2:0]={eof,sol,sof}，纯组合流式输出，自由运行（由下游 G10
//             写路径的 cam_src_sy 使能门控，本模块不加使能，与相机行为一致）。
// 节奏       : 帧周期 6,666,667 拍 @200MHz（30fps）；每帧 518,400 组（480 组/行
//             × 1080 行）。G11n16b 板测修正——行突发节奏（同构相机微观节奏）：
//             每行 480 组背靠背（1 组/拍，2.4µs 突发），行周期 LINE_PERIOD=3100
//             拍（相机 hs→hs 节奏同构）行间静默，帧尾 vblank ≈16.6ms 供 FIFO
//             排空。原"1 组/12 拍均匀细流"板测实证（2026-11-08）：pacer 纯流式
//             即到即发 → occ 平衡 ~40 → pkt_len=min(290,occ)≈40 组 → 533k pps
//             小包风暴 → PC UDP 栈丢包无图像；行突发使 occ 恢复相机模式
//             82~500 锯齿 → 290 组大包、pps 回到相机量级。
// 图案       : 四模式（pat_mode[1:0] 经 2FF 同步，准静态，组边界自然生效）
//             0=RGGB 8 彩条 1=横向灰度 2=垂直灰度 3=棋盘
//             与 PC doc/pc_tools/raw10.py expected_image() 严格同步（函数自
//             udp_pat_gen_v2.v 原样搬移，G11n16）。
/////////////////////////////////////////////////////////////////////////////
`default_nettype none
`timescale 1 ns / 1 ns

module raw10_pat_src #(
    parameter FRAME_PERIOD = 23'd6_666_667,   // 30fps @200MHz（=行活跃+vblank 总拍）
    parameter GRP_TOTAL    = 20'd518_400      // 480 组/行 × 1080 行（须为 480 整数倍）
)(
    input  wire        clk_i,
    input  wire        rstn_i,
    input  wire [1:0]  pat_mode_i,     // reg_apb3 0x208[5:4]（50M 域，准静态）
    output wire [39:0] tdata_o,        // RAW10 4px 打包组（{p0,p1,p2,p3} 各 10bit）
    output wire        tvalid_o,
    output wire        tlast_o,        // 同 eof（帧末组拍）
    output wire [2:0]  tuser_o         // {eof, sol, sof}
);

localparam [10:0] GRP_PER_LINE = 11'd480;
localparam [10:0] LINES        = GRP_TOTAL / GRP_PER_LINE;   // 518400/480=1080
// 行周期：相机 hs→hs 节奏同构（板测 hsgap 直方图主带 <3500 拍）。行活跃段
// 480 拍 + 行间静默 2620 拍；帧尾 vblank = FRAME_PERIOD - LINES×LINE_PERIOD。
localparam [12:0] LINE_PERIOD  = 13'd3100;
localparam [21:0] VBLANK_BEATS = FRAME_PERIOD - LINES * LINE_PERIOD;  // 3,318,667 ≈16.6ms

// pat_mode 2FF 同步（准静态输入；组边界自然生效，无需握手）
reg [1:0] pat_mode_r;
always @(posedge clk_i or negedge rstn_i)
    if (!rstn_i) pat_mode_r <= 2'b00;
    else         pat_mode_r <= {pat_mode_r[0], pat_mode_i};

//--------------------------------------------------------------------------
// 帧节奏（G11n16b 行突发）：line_beat 行内拍计数，0..479 拍为行活跃段
// （480 组背靠背，1 组/拍），480..LINE_PERIOD-1 行间静默；line_cnt 行号
// 0..LINES-1；末行走完后进入 vblank（VBLANK_BEATS 拍，同相机消隐），
// frame_wrap 拍复位全部计数/组号/图案坐标，下一拍即新帧第 0 组
//（复位释放后计数全 0，首帧第 0 组在第 0 拍）
//--------------------------------------------------------------------------
reg         in_vblk;
reg  [12:0] line_beat;               // 行内拍计数（0..LINE_PERIOD-1）
reg  [10:0] line_cnt;                // 行号（0..LINES-1）
reg  [21:0] vblk_beat;               // 帧尾 vblank 拍计数
reg  [19:0] grp_idx;                 // 组号（0..GRP_TOTAL-1）
wire        line_wrap  = (line_beat == LINE_PERIOD - 13'd1);
wire        frame_wrap = in_vblk && (vblk_beat == VBLANK_BEATS - 22'd1);
wire        grp_beat   = !in_vblk && (line_beat < GRP_PER_LINE);

always @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
        in_vblk   <= 1'b0;
        line_beat <= 13'd0;
        line_cnt  <= 11'd0;
        vblk_beat <= 22'd0;
        grp_idx   <= 20'd0;
    end else if (frame_wrap) begin
        in_vblk   <= 1'b0;
        line_beat <= 13'd0;
        line_cnt  <= 11'd0;
        vblk_beat <= 22'd0;
        grp_idx   <= 20'd0;
    end else if (in_vblk) begin
        vblk_beat <= vblk_beat + 22'd1;
    end else begin
        line_beat <= line_wrap ? 13'd0 : line_beat + 13'd1;
        if (line_wrap) begin
            line_cnt <= (line_cnt == LINES - 11'd1) ? 11'd0 : line_cnt + 11'd1;
            if (line_cnt == LINES - 11'd1)
                in_vblk <= 1'b1;        // 末行走完 → 帧尾 vblank
        end
        if (grp_beat)
            grp_idx <= grp_idx + 20'd1; // 组号推进（帧尾由 frame_wrap 归零）
    end
end

//--------------------------------------------------------------------------
// 图案坐标推进（自 udp_pat_gen_v2.v 搬移）：col_cnt 为组首列（偶），
// 480 组/行整除 1920 → 组首列恒偶，无组内跨行断裂
//--------------------------------------------------------------------------
reg  [10:0] col_cnt;
reg         row_par;
reg  [10:0] row_cnt;
wire [10:0] col_next  = (col_cnt >= 11'd1916) ? 11'd0 : col_cnt + 11'd4;
wire        rowp_next = (col_cnt >= 11'd1916) ? ~row_par : row_par;
wire [10:0] row_next  = (col_cnt >= 11'd1916) ? row_cnt + 11'd1 : row_cnt;

always @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
        col_cnt <= 11'd0;
        row_par <= 1'b0;
        row_cnt <= 11'd0;
    end else if (frame_wrap) begin
        col_cnt <= 11'd0;               // 帧界归零（gap 期保持上帧末值无害）
        row_par <= 1'b0;
        row_cnt <= 11'd0;
    end else if (grp_beat) begin
        col_cnt <= col_next;
        row_par <= rowp_next;
        row_cnt <= row_next;
    end
end

//--------------------------------------------------------------------------
// 图案发生（与 doc/pc_tools/raw10.py expected_image(mode) 严格同步）：
//   0 彩条：RGGB 8 条 × 240px（白黄青绿品红红蓝黑），行偶 {R,Gr} 行奇 {Gb,B}
//   1 横向灰度：p = col>>1
//   2 垂直灰度：p = row 饱和 1023
//   3 棋盘：120px 黑白格（块奇偶异或链）
//   每组 4px 起始列恒为偶，图案切换在组边界自然生效
//--------------------------------------------------------------------------
function [39:0] pattern_quad;       // {p0,p1,p2,p3} 各 10bit
    input [10:0] col;               //组首列（偶）
    input [10:0] rowv;              //当前行号
    reg   [2:0]  bar;
    reg          cpar, rpar;
    reg          r_on, g_on, b_on;
    reg   [9:0]  vr, vg, vb;
    reg   [9:0]  vgray;
    begin
        case (pat_mode_r)
        2'b00: begin                            //彩条（RGGB CFA 彩色）
            if (col >= 11'd1680)      bar = 3'd7;      //黑
            else if (col >= 11'd1440) bar = 3'd6;      //蓝
            else if (col >= 11'd1200) bar = 3'd5;      //红
            else if (col >= 11'd960)  bar = 3'd4;      //品红
            else if (col >= 11'd720)  bar = 3'd3;      //绿
            else if (col >= 11'd480)  bar = 3'd2;      //青
            else if (col >= 11'd240)  bar = 3'd1;      //黄
            else                      bar = 3'd0;      //白
            case (bar)
                3'd0:    {r_on, g_on, b_on} = 3'b111;
                3'd1:    {r_on, g_on, b_on} = 3'b110;
                3'd2:    {r_on, g_on, b_on} = 3'b011;
                3'd3:    {r_on, g_on, b_on} = 3'b010;
                3'd4:    {r_on, g_on, b_on} = 3'b101;
                3'd5:    {r_on, g_on, b_on} = 3'b100;
                3'd6:    {r_on, g_on, b_on} = 3'b001;
                default: {r_on, g_on, b_on} = 3'b000;
            endcase
            vr = r_on ? 10'h3FF : 10'h000;
            vg = g_on ? 10'h3FF : 10'h000;
            vb = b_on ? 10'h3FF : 10'h000;
            pattern_quad[39:30] = row_par ? vg : vr;   //p0 偶列
            pattern_quad[29:20] = row_par ? vb : vg;   //p1 奇列
            pattern_quad[19:10] = row_par ? vg : vr;   //p2 偶列
            pattern_quad[ 9: 0] = row_par ? vb : vg;   //p3 奇列
        end
        2'b01: begin                            //横向灰度
            vgray = col[10:1];                       //p0 = col>>1
            pattern_quad[39:30] = vgray;
            pattern_quad[29:20] = vgray;             //p1 = (col+1)>>1 = col>>1（col 偶）
            vgray = col[10:1] + 10'd1;               //p2 = (col+2)>>1
            pattern_quad[19:10] = vgray;
            pattern_quad[ 9: 0] = vgray;             //p3 = (col+3)>>1（col 偶，同 p2）
        end
        2'b10: begin                            //垂直灰度
            vgray = (rowv >= 11'd1024) ? 10'h3FF : rowv[9:0];
            pattern_quad[39:30] = vgray;
            pattern_quad[29:20] = vgray;
            pattern_quad[19:10] = vgray;
            pattern_quad[ 9: 0] = vgray;
        end
        default: begin                          //棋盘
            //块奇偶（块 120px，列 16 块/行 9 块）：奇偶性在每条块边界翻转，
            //全边界比较结果异或链 = (col/120)&1（col<=1916 共 15 条边界）
            cpar = (col  >= 11'd120);
            cpar = cpar ^ (col  >= 11'd240);
            cpar = cpar ^ (col  >= 11'd360);
            cpar = cpar ^ (col  >= 11'd480);
            cpar = cpar ^ (col  >= 11'd600);
            cpar = cpar ^ (col  >= 11'd720);
            cpar = cpar ^ (col  >= 11'd840);
            cpar = cpar ^ (col  >= 11'd960);
            cpar = cpar ^ (col  >= 11'd1080);
            cpar = cpar ^ (col  >= 11'd1200);
            cpar = cpar ^ (col  >= 11'd1320);
            cpar = cpar ^ (col  >= 11'd1440);
            cpar = cpar ^ (col  >= 11'd1560);
            cpar = cpar ^ (col  >= 11'd1680);
            cpar = cpar ^ (col  >= 11'd1800);
            rpar = (rowv >= 11'd120);
            rpar = rpar ^ (rowv >= 11'd240);
            rpar = rpar ^ (rowv >= 11'd360);
            rpar = rpar ^ (rowv >= 11'd480);
            rpar = rpar ^ (rowv >= 11'd600);
            rpar = rpar ^ (rowv >= 11'd720);
            rpar = rpar ^ (rowv >= 11'd840);
            rpar = rpar ^ (rowv >= 11'd960);
            vgray = (cpar ^ rpar) ? 10'h3FF : 10'h000;
            pattern_quad[39:30] = vgray;
            pattern_quad[29:20] = vgray;
            pattern_quad[19:10] = vgray;
            pattern_quad[ 9: 0] = vgray;
        end
        endcase
    end
endfunction

// 流式输出（纯组合：坐标寄存器 + 一级函数 LUT，下游 G10 写路径有 3 拍延迟链）
assign tdata_o  = pattern_quad(col_cnt, row_cnt);
assign tvalid_o = grp_beat;
assign tlast_o  = (grp_idx == GRP_TOTAL - 20'd1) && grp_beat;   // 同 eof
assign tuser_o  = {(grp_idx == GRP_TOTAL - 20'd1) && grp_beat,  // eof
                   (col_cnt == 11'd0) && grp_beat,              // sol（行首组）
                   (grp_idx == 20'd0) && grp_beat};             // sof

endmodule

`default_nettype wire
