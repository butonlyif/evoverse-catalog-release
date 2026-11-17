//============================================================================
// tb_raw10_pat_src.sv — G11n16 图案源单模块仿真（真实几何，无参数缩水）
// 判据：
//   1) 帧节奏：sof→sof 恰 6,666,667 拍（30fps@200M）；每帧 tvalid 恰 518,400 组
//   2) 帧结构：sof/eof 每帧各 1 拍，tlast==eof，sol=行首组（grp%480==0）
//   3) 组节拍（G11n16b 行突发）：行活跃段相邻组恰 1 拍（背靠背 480 组），
//      行界间隔恰 2621 拍（LINE_PERIOD 3100 - 480 + 1），帧首组豁免
//   4) 内容：逐组与独立期望模型对拍（公式镜像 doc/pc_tools/raw10.py
//      expected_image()——模式 1 组内 {g,g,g+1,g+1}，模式 2/3 组内同值）
//   5) pat_mode 运行中切换：组边界自然生效（2FF 同步后下一组即新图案）
//============================================================================
`timescale 1ns/1ps

module tb_raw10_pat_src;

    reg clk = 1'b0;
    always #2.5 clk = ~clk;              // 200 MHz

    reg         rstn     = 1'b0;
    reg [1:0]   pat_mode = 2'b00;
    wire [39:0] tdata;
    wire        tvalid, tlast;
    wire [2:0]  tuser;                   // {eof, sol, sof}

    raw10_pat_src u_dut (
        .clk_i    (clk),
        .rstn_i   (rstn),
        .pat_mode_i (pat_mode),
        .tdata_o  (tdata),
        .tvalid_o (tvalid),
        .tlast_o  (tlast),
        .tuser_o  (tuser)
    );

    //------------------------------------------------------------------
    // 独立期望模型：镜像 expected_image() 公式（col=组首列，row 组内恒同或
    // {g,g,g+1,g+1}；与 RTL 同为组级 40bit {p0,p1,p2,p3} 各 10bit）
    //------------------------------------------------------------------
    function [39:0] exp_quad(input [1:0] mode, input integer col, input integer row);
        reg [2:0]  bar;
        reg        cpar, rpar;
        reg        r_on, g_on, b_on;
        reg  [9:0] vr, vg, vb, vgray;
        reg        row_par;
        begin
            row_par = row[0];
            case (mode)
            2'b00: begin
                if (col >= 1680)      bar = 3'd7;
                else if (col >= 1440) bar = 3'd6;
                else if (col >= 1200) bar = 3'd5;
                else if (col >= 960)  bar = 3'd4;
                else if (col >= 720)  bar = 3'd3;
                else if (col >= 480)  bar = 3'd2;
                else if (col >= 240)  bar = 3'd1;
                else                  bar = 3'd0;
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
                exp_quad[39:30] = row_par ? vg : vr;
                exp_quad[29:20] = row_par ? vb : vg;
                exp_quad[19:10] = row_par ? vg : vr;
                exp_quad[ 9: 0] = row_par ? vb : vg;
            end
            2'b01: begin                          //横向灰度：px=col>>1（组内 {g,g,g+1,g+1}）
                vgray = col[10:1];
                exp_quad[39:30] = vgray;
                exp_quad[29:20] = vgray;
                vgray = col[10:1] + 10'd1;
                exp_quad[19:10] = vgray;
                exp_quad[ 9: 0] = vgray;
            end
            2'b10: begin                          //垂直灰度：px=min(row,1023)
                vgray = (row >= 1024) ? 10'h3FF : row[9:0];
                exp_quad[39:30] = vgray;
                exp_quad[29:20] = vgray;
                exp_quad[19:10] = vgray;
                exp_quad[ 9: 0] = vgray;
            end
            default: begin                        //棋盘：((c/120 + r/120)&1)*1023
                cpar = (col >= 120);
                cpar = cpar ^ (col >= 240);
                cpar = cpar ^ (col >= 360);
                cpar = cpar ^ (col >= 480);
                cpar = cpar ^ (col >= 600);
                cpar = cpar ^ (col >= 720);
                cpar = cpar ^ (col >= 840);
                cpar = cpar ^ (col >= 960);
                cpar = cpar ^ (col >= 1080);
                cpar = cpar ^ (col >= 1200);
                cpar = cpar ^ (col >= 1320);
                cpar = cpar ^ (col >= 1440);
                cpar = cpar ^ (col >= 1560);
                cpar = cpar ^ (col >= 1680);
                cpar = cpar ^ (col >= 1800);
                rpar = (row >= 120);
                rpar = rpar ^ (row >= 240);
                rpar = rpar ^ (row >= 360);
                rpar = rpar ^ (row >= 480);
                rpar = rpar ^ (row >= 600);
                rpar = rpar ^ (row >= 720);
                rpar = rpar ^ (row >= 840);
                rpar = rpar ^ (row >= 960);
                vgray = (cpar ^ rpar) ? 10'h3FF : 10'h000;
                exp_quad[39:30] = vgray;
                exp_quad[29:20] = vgray;
                exp_quad[19:10] = vgray;
                exp_quad[ 9: 0] = vgray;
            end
            endcase
        end
    endfunction

    //------------------------------------------------------------------
    // 监视与检查
    //------------------------------------------------------------------
    integer cyc        = 0;     // 距上一 sof 的拍数（sof 拍复位）
    integer sof_period = 0;     // 最近一次实测 sof→sof 周期（应 6,666,667）
    integer grp_cnt    = 0;     // 本帧已收组数
    integer grp_gap    = 99;    // 距上一组拍的间隔（首组无参照，哨兵 99）
    integer grp_sp_bad = 0;     // 组间隔≠1（行内）且≠2621（行界）计数
    // G11n16b 行突发：行界间隔 = LINE_PERIOD 3100 - 突发 480 + 1 = 2621 拍
    localparam LINE_GAP_CYC = 2620;   // grp_gap 值（间隔拍数-1）
    integer mism       = 0;
    integer err_frame  = 0;     // 帧结构错误
    integer frame      = 0;     // 已完成帧数
    integer sw_skip    = 0;     // 模式切换后跳过的组数（2FF 同步窗口）
    reg     first_sof  = 1'b1;

    always @(posedge clk) begin
        if (!rstn) begin
            cyc <= 0; grp_cnt <= 0; grp_gap <= 99; first_sof <= 1'b1;
        end else begin
            grp_gap <= (tvalid) ? 0 : grp_gap + 1;
            if (tvalid) begin
                // 组节拍（G11n16b 行突发）：行内相邻组 1 拍、行界 2621 拍
                //（帧首组跨 vblank，grp_cnt==0 豁免；哨兵 99 首组豁免）
                if (grp_cnt != 0 && grp_gap != 0 && grp_gap != LINE_GAP_CYC && grp_gap != 99) begin
                    grp_sp_bad = grp_sp_bad + 1;
                    if (grp_sp_bad <= 5)
                        $display("[%0t] GROUP SPACING %0d (expect 1 or 2621) frame=%0d grp=%0d",
                                 $time, grp_gap+1, frame, grp_cnt);
                end
                // sof 拍：周期检查（cyc 在 sof 拍计 0 → 实测值 = 周期-1 = 6,666,666）
                if (tuser[0]) begin
                    if (!first_sof) begin
                        sof_period = cyc + 1;
                        if (cyc != 6_666_666) begin
                            err_frame = err_frame + 1;
                            $display("[%0t] SOF PERIOD %0d (expect 6666667)", $time, cyc+1);
                        end
                    end
                    first_sof <= 1'b0;
                    cyc       <= 0;
                end else begin
                    cyc <= cyc + 1;
                end
                // 帧结构检查
                if (tuser[1] !== ((grp_cnt % 480) == 0)) begin err_frame = err_frame + 1;
                    $display("[%0t] sol=%b expect=%b grp=%0d", $time, tuser[1], ((grp_cnt%480)==0), grp_cnt); end
                if (tlast !== (grp_cnt == 518399)) begin err_frame = err_frame + 1;
                    $display("[%0t] tlast=%b expect grp=518399 (grp=%0d)", $time, tlast, grp_cnt); end
                if (tuser[2] !== (grp_cnt == 518399)) begin err_frame = err_frame + 1;
                    $display("[%0t] eof=%b expect grp=518399 (grp=%0d)", $time, tuser[2], grp_cnt); end
                // 内容对拍（切换后跳 2 组同步窗口）
                if (sw_skip > 0) begin
                    sw_skip = sw_skip - 1;
                    if (sw_skip == 0)
                        $display("[%0t] MODE SWITCH effective at grp=%0d (mode=%0d)", $time, grp_cnt, pat_mode);
                end else begin
                    if (tdata !== exp_quad(pat_mode, (grp_cnt % 480) * 4, grp_cnt / 480)) begin
                        mism = mism + 1;
                        if (mism <= 6)
                            $display("[%0t] grp=%0d got=%h exp=%h MISMATCH (mode=%0d)",
                                     $time, grp_cnt, tdata,
                                     exp_quad(pat_mode, (grp_cnt%480)*4, grp_cnt/480), pat_mode);
                    end
                end
                if (grp_cnt == 518399) begin
                    // 帧末（eof 拍）：组数与周期打印
                    $display("[%0t] FRAME %0d done: groups=518400 sof_period=%0d mism_cum=%0d err=%0d",
                             $time, frame, sof_period, mism, err_frame);
                    frame <= frame + 1;
                    grp_cnt <= 0;
                end else begin
                    grp_cnt <= grp_cnt + 1;
                end
            end else if (cyc == 6_666_666) begin
                // 帧尾 gap 末拍：本帧组数检查（下一拍即新帧 sof）
                if (grp_cnt != 518400) begin err_frame = err_frame + 1;
                    $display("[%0t] frame %0d: groups=%0d (expect 518400)", $time, frame, grp_cnt); end
            end else begin
                cyc <= cyc + 1;
            end
        end
    end

    //------------------------------------------------------------------
    // 激励：帧 0 中段切模式 1 → 帧 1 末切模式 2 → 帧 2 末切模式 3
    //------------------------------------------------------------------
    initial begin
        repeat (8) @(posedge clk);
        rstn = 1'b1;
        // 帧 0（模式 0 彩条）中途切换：组边界自然生效检查
        wait (frame == 0 && u_dut.grp_idx == 300000);
        pat_mode = 2'b01;
        sw_skip  = 2;
        wait (frame == 1);                   // 帧 0 完成（含模式 1 后半帧对拍）
        pat_mode = 2'b10;                    // 帧 1 为纯模式 2
        sw_skip  = 0;
        wait (frame == 2);
        pat_mode = 2'b11;                    // 帧 2 为纯模式 3
        wait (frame == 3);
        #1000;
        if (mism == 0 && err_frame == 0 && grp_sp_bad == 0 && sof_period == 6_666_667)
            $display("SIM RESULT PAT_SRC: PASS (4 frames, mism=0, struct_err=0, spacing_err=0, sof_period=%0d)",
                     sof_period);
        else
            $display("SIM RESULT PAT_SRC: FAIL (mism=%0d err=%0d spacing=%0d sof_period=%0d expect 6666667)",
                     mism, err_frame, grp_sp_bad, sof_period);
        $finish;
    end

    initial begin
        #130_000_000;                        // 4 帧 ×33.3ms + 裕量
        $display("SIM TIMEOUT PAT_SRC: frame=%0d mism=%0d err=%0d", frame, mism, err_frame);
        $display("SIM RESULT PAT_SRC: FAIL (timeout)");
        $finish;
    end
endmodule
