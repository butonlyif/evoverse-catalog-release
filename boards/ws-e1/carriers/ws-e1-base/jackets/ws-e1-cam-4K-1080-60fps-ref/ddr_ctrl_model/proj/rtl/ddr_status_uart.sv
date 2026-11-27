////////////////////////////////////////////////////////////////////////////
//  ddr_status_uart.sv — DDR 自检状态 UART 读出（最小 DDR 板测工程专用）
//
//  周期性把 DIAG11 状态字以 ASCII 帧发出，供上位串口直接观测，替代
//  top_cam_demo 的 riscv_soc+APB CSR 读出通道（本工程不带 SoC）。
//
//  帧格式（13 字节，8N1，默认 115200）：
//    'D' 'D' 'R' ':' + 状态字 8 个 hex 字符（高 nibble 在前）+ '\r' '\n'
//  SCAN_MODE=0：DIAG11 = {err_cnt[15:0], mcst[3:0], 5'h0, done_raw, cfg_st[1:0],
//            lock, cfg_ok, done, fail}，hex 读法：
//    n0..n3 = err_cnt   n4 = mcst   n5 = 0
//    n6 = {0,done_raw,cfg_st}   n7 = {lock,cfg_ok,done,fail}
//  同步头 "DDR:" 便于上位机切帧；例：DDR:0000300100000013
//  = err=0 mcst=3(WRITE) st=3(CFG_DONE) lock=1 cfg_ok=1 done=1 fail=0。
//  SCAN_MODE=2（TG_MODE=2 延迟标定，correlation Phase 2）：
//    diag = lat_word = {blk[3:0], set[1:0], kind[2:0], done, 6'h0, data[15:0]}
//    hex 读法（n0..n7）：
//      n0 = blk（0-8 测量块，9=状态字 {fail,err_tot[14:0]}）
//      n1 = {set,kind}：set=n1[3:2]（0=RD 1=WA 2=WL）
//                       kind=n1[2:0]（0=min 1=max 2=cnt 3=P50 4=P95 5=P99 6=ovf）
//      n2 = {done,3'h0}（8=已完成 0=未完）   n3 = '0'
//      n4..n7 = data[15:0]
//    例：DDR:00800012 = blk0 RD min=0x0012=18 拍（done=1）。
//    每帧发出完毕时 lat_next 产生 1 拍脉冲，推进 memcheck 报告轮发指针
//    （kind 最快→set→blk），逐词轮发全部 9 块×3 口径×7 字 + 状态字。
//
//  报告间隔 UART_REPORT_TICKS 个 clk（默认 2^23 ≈ 41.9ms @200MHz），
//  仿真 smoke 用更小值缩短等待。
////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module ddr_status_uart #(
    parameter int CLK_HZ            = 200_000_000,
    parameter int BAUD              = 115_200,
    parameter int UART_REPORT_TICKS = (1 << 23),
    parameter int SCAN_MODE         = 0   // 0=DIAG11 1=TG 扫描帧 2=延迟轮发帧
) (
    input  wire        clk,
    input  wire        rstn,        // 低有效同步复位（sys_clk_200m 域）
    input  wire [31:0] diag,        // DIAG11/lat_word（字节装载时采样）
    output wire        txd,
    output wire        lat_next     // MODE2：帧尾 1 拍脉冲（推进报告指针）
);

    localparam int BIT_TICKS = CLK_HZ / BAUD;   // 200M/115200 ≈ 1736

    function [7:0] hex2asc(input [3:0] nib);
        hex2asc = (nib < 4'hA) ? (8'h30 + {4'h0, nib}) : (8'h37 + {4'h0, nib});
    endfunction

    // 发送帧 ROM：发送中逐字节装载，frame[] 按 diag 实时组合（装载时刻采样）
    wire [7:0] frame [0:12];
    assign frame[0]  = 8'h44;                   // 'D'
    assign frame[1]  = 8'h44;                   // 'D'
    assign frame[2]  = 8'h52;                   // 'R'
    assign frame[3]  = 8'h3A;                   // ':'
    generate
        if (SCAN_MODE == 2) begin : g_lat
            // 延迟轮发帧：diag = lat_word（帧格式见头部注释；hex 变换同款）
            assign frame[4]  = hex2asc(diag[31:28]);
            assign frame[5]  = hex2asc(diag[27:24]);
            assign frame[6]  = hex2asc(diag[23:20]);
            assign frame[7]  = hex2asc(diag[19:16]);
            assign frame[8]  = hex2asc(diag[15:12]);
            assign frame[9]  = hex2asc(diag[11:8]);
            assign frame[10] = hex2asc(diag[7:4]);
            assign frame[11] = hex2asc(diag[3:0]);
        end else if (SCAN_MODE) begin : g_scan
            // 扫描帧：{err_sat[7:0], rd_cyc[15:0], ostd[3:0], tgst[3:0]}
            // hex 读法（8 个字符 n0..n7）：n0,n1=err_sat  n2..n5=rd_cyc
            //   n6=ostd（4'h0=16，第 16 轮；别把 n5 即 rd_cyc 低位误当 ostd）
            //   n7=tgst（9=DONE，0xB=TG_ROUND_GAP，0xA=TG_RD_REQ，0=IDLE/CFG）
            // 例：DDR:0008FC09 = err=0x00 rd_cyc=2300 ostd=16(4'h0) tgst=9(DONE)
            assign frame[4]  = hex2asc(diag[31:28]);
            assign frame[5]  = hex2asc(diag[27:24]);
            assign frame[6]  = hex2asc(diag[23:20]);
            assign frame[7]  = hex2asc(diag[19:16]);
            assign frame[8]  = hex2asc(diag[15:12]);
            assign frame[9]  = hex2asc(diag[11:8]);
            assign frame[10] = hex2asc(diag[7:4]);
            assign frame[11] = hex2asc(diag[3:0]);
        end else begin : g_diag
            // DIAG11 帧：{err_cnt[15:0], mcst[3:0], 5'h0, done_raw, cfg_st[1:0],
            //             lock, cfg_ok, done, fail}
            assign frame[4]  = hex2asc(diag[31:28]);
            assign frame[5]  = hex2asc(diag[27:24]);
            assign frame[6]  = hex2asc(diag[23:20]);
            assign frame[7]  = hex2asc(diag[19:16]);
            assign frame[8]  = hex2asc(diag[15:12]);
            assign frame[9]  = hex2asc(diag[11:8]);
            assign frame[10] = hex2asc(diag[7:4]);
            assign frame[11] = hex2asc(diag[3:0]);
        end
    endgenerate
    assign frame[12] = 8'h0A;                   // '\n'
    localparam int FRAME_LEN = 13;

    //---------------------------------------------------------------------
    // 发送 FSM：1 start + 8 data(LSB first) + 1 stop
    //---------------------------------------------------------------------
    reg [31:0] gap_cnt;
    reg        tx_active;
    reg [3:0]  byte_idx;
    reg [3:0]  bit_idx;
    reg [15:0] div_cnt;
    reg [7:0]  shift;
    reg        txd_r;

    assign txd = txd_r;
    // MODE2：末字节停止位时隙结束拍 = 帧完成拍（tx_active 同拍清零），
    // 此时整帧 8 个数据字节均已按位发出（diag 逐字节装载时刻采样完毕），
    // 次拍起指针推进后的新词供下一帧装载
    assign lat_next = (SCAN_MODE == 2) && tx_active &&
                      (div_cnt == BIT_TICKS - 1) && (bit_idx == 4'd9) &&
                      (byte_idx == FRAME_LEN - 1);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            gap_cnt   <= 32'h0;
            tx_active <= 1'b0;
            byte_idx  <= 4'h0;
            bit_idx   <= 4'h0;
            div_cnt   <= 16'h0;
            shift     <= 8'h0;
            txd_r     <= 1'b1;
        end else if (!tx_active) begin
            txd_r <= 1'b1;
            if (gap_cnt >= UART_REPORT_TICKS[31:0] - 1'b1) begin
                gap_cnt   <= 32'h0;
                tx_active <= 1'b1;
                byte_idx  <= 4'h0;
                bit_idx   <= 4'h0;
                div_cnt   <= 16'h0;
                shift     <= frame[0];
            end else begin
                gap_cnt <= gap_cnt + 1'b1;
            end
        end else if (div_cnt >= BIT_TICKS - 1) begin
            div_cnt <= 16'h0;
            if (bit_idx == 4'd9) begin                  // 停止位结束
                bit_idx <= 4'h0;
                if (byte_idx == FRAME_LEN - 1) begin
                    tx_active <= 1'b0;                  // 帧完成
                end else begin
                    byte_idx <= byte_idx + 1'b1;
                    shift    <= frame[byte_idx + 1'b1];
                end
            end else begin
                bit_idx <= bit_idx + 1'b1;
            end
            if (bit_idx == 4'd0)
                txd_r <= 1'b0;                          // start bit
            else if (bit_idx <= 4'd8) begin
                txd_r <= shift[0];                      // data LSB first
                shift <= {1'b0, shift[7:1]};
            end else
                txd_r <= 1'b1;                          // stop bit
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

endmodule
