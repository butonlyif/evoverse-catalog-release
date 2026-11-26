//============================================================================
// tb_cap_read.sv — G11i cap 路径统一 async_fifo 验证
// 复刻：顶层写窗（arm→sof 起 CAP_BEATS 组，wr_en 打一拍 + din 延迟一拍对齐）
//       + async_fifo(32768) + 首组预读/持有逻辑 + reg_apb3 0x2B4/0x2B8 读时序
// 判据：CSR 读序 == 写入序（首组经预读呈现）；读尽后重复末组不崩溃
//============================================================================
`timescale 1ns/1ps

module tb_cap_read;

    reg clk200 = 0, clk50 = 0;
    always #2.5 clk200 = ~clk200;   // 200 MHz
    always #10  clk50  = ~clk50;    // 50 MHz
    reg rstn = 0;
    initial begin #100; rstn = 1; end

    localparam int          CAP_BEATS   = 8192;
    localparam logic [12:0] CAP_BEATS_M1 = CAP_BEATS-1;

    // ---------------- BFM：arm 后一拍起 CAP_BEATS 拍有效流（首拍 sof）----------------
    reg        arm_w = 0, arm_go = 0;
    reg        tvalid = 0;
    reg [2:0]  tuser  = 0;
    reg [39:0] tdata  = 0;
    integer    beat   = 0;

    always @(posedge clk200 or negedge rstn) begin
        if (!rstn) begin
            tvalid <= 0; tuser <= 0; tdata <= 0; beat <= 0;
        end else if (arm_go) begin
            tvalid <= 1; tuser <= 3'b001;          // sof（tuser={eof,sol,sof}）
            tdata  <= {4'hC, 32'd0, 4'h3};
            beat   <= 1;
        end else if (tvalid && beat < CAP_BEATS) begin
            tuser  <= 3'b000;
            tdata  <= {4'hC, beat[31:0], 4'h3};
            beat   <= beat + 1;
        end else begin
            tvalid <= 0;
        end
    end

    // ---------------- 顶层写窗复刻（ws_e1_tse.v G11i 版）----------------
    reg  [2:0]  cap_arm_sy = 0;
    reg         cap_armed_200 = 0, cap_active = 0, cap_done_200 = 0;
    reg  [12:0] cap_wptr = 0;
    reg         cap_fifo_wr_en = 0;
    reg  [39:0] cap_wr_data_r = 0;
    wire        cap_fifo_full, cap_fifo_empty;
    wire        sof_evt = tvalid & tuser[0];

    always @(posedge clk200 or negedge rstn) begin
        if (!rstn) begin
            cap_arm_sy <= 3'b000; cap_armed_200 <= 0; cap_active <= 0;
            cap_done_200 <= 0; cap_wptr <= 0; cap_fifo_wr_en <= 0;
        end else begin
            cap_arm_sy    <= {cap_arm_sy[1:0], arm_w};
            cap_wr_data_r <= tdata;               // din 与打一拍的 wr_en 对齐
            if (cap_arm_sy[1:0] == 2'b01) begin
                cap_armed_200 <= 1;
                cap_done_200  <= 0;
            end
            cap_fifo_wr_en <= 0;
            if (cap_armed_200 & tvalid & tuser[0]) begin
                cap_armed_200  <= 0;
                cap_active     <= 1;
                cap_wptr       <= 1;
                cap_fifo_wr_en <= ~cap_fifo_full;
            end else if (cap_active & tvalid) begin
                cap_fifo_wr_en <= ~cap_fifo_full;
                if (cap_wptr == CAP_BEATS_M1) begin
                    cap_active   <= 0;
                    cap_done_200 <= 1;
                end else begin
                    cap_wptr <= cap_wptr + 1'b1;
                end
            end
        end
    end

    // ---------------- FIFO + 预读/持有（同顶层 G11i）----------------
    wire [39:0] cap_fifo_dout;
    reg         cap_rd_en_w = 0;    // CSR 0x2B8 读脉冲
    reg         cap_hold_v = 0;
    wire        cap_pre_rd  = !cap_hold_v && !cap_fifo_empty;
    wire        cap_rd_hit  = (cap_rd_en_w || cap_pre_rd) && !cap_fifo_empty;
    wire        cap_rd_en_f = cap_rd_en_w | cap_pre_rd;

    always @(posedge clk50 or negedge rstn) begin
        if (!rstn)              cap_hold_v <= 0;
        else if (cap_rd_hit)    cap_hold_v <= 1;
        else if (cap_rd_en_w)   cap_hold_v <= 0;
    end

    async_fifo #(.WIDTH(40), .DEPTH(32768)) u_cap (
        .wr_clk(clk200), .wr_rst_n(rstn),
        .wr_en(cap_fifo_wr_en), .din(cap_wr_data_r), .full(cap_fifo_full),
        .rd_clk(clk50), .rd_rst_n(rstn),
        .rd_en(cap_rd_en_f), .dout(cap_fifo_dout), .empty(cap_fifo_empty)
    );

    // ---------------- 固件 CSR 消费（0x2B4 采样 → 0x2B8 采样+步进）----------------
    integer got = 0, errors = 0, k;
    initial begin
        @(posedge rstn); #50;
        arm_w = 1; #10; arm_w = 0;              // CSR 写 0x2B0 bit0
        #100;                                   // armed 建立后才来 sof
        arm_go = 1; @(posedge clk200); #1; arm_go = 0;
        wait (cap_done_200 === 1'b1);
        #3000;                                  // done 跨域 + 预读完成
        if (cap_fifo_dout !== {4'hC, 32'd0, 4'h3})
            $display("[%0t] PRE-READ ERR: dout=%h exp=c000000003", $time, cap_fifo_dout);
        else
            $display("[%0t] PRE-READ OK: 首组已呈现", $time);
        for (k = 0; k < CAP_BEATS + 16; k = k + 1) begin
            @(posedge clk50); #1;               // 0x2B4 语义：采样当前 dout
            if (k < CAP_BEATS && cap_fifo_dout !== {4'hC, got[31:0], 4'h3}) begin
                errors = errors + 1;
                if (errors <= 5)
                    $display("[%0t] ERR k=%0d got=%h exp=%h", $time, k,
                             cap_fifo_dout, {4'hC, got[31:0], 4'h3});
            end
            cap_rd_en_w = 1;                    // 0x2B8 语义：同拍采样 + rd 脉冲
            @(posedge clk50); #1;
            cap_rd_en_w = 0;
            if (k < CAP_BEATS) got = got + 1;
        end
        if (errors == 0)
            $display("TB_CAP PASS: %0d 组全序读出（首组预读 + 逐组步进），+%0d 越界读无崩溃",
                     CAP_BEATS, 16);
        else
            $display("TB_CAP FAIL: errors=%0d", errors);
        $finish;
    end

endmodule
