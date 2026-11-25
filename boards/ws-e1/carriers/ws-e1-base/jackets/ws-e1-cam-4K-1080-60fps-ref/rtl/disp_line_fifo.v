// ============================================================================
// disp_line_fifo.v — DDR 回放显示链的异步行缓存（阶段 2）
//
// 结构：简单双口 BRAM FIFO（写 512b @200M / 读 512b @pixel_clk，READ_UNKNOWN
// 模式，Efinix 推断模板同款 + syn_ramstyle 约束），读侧 2 槽乒乓预取 +
// 512b->64b 串行化（每字 8 beat）。
//
//   写侧（frame_reader，sys_clk_200m）：wr_en 推入 512b 字（= 8 个 AXIS 拍）；
//     wr_level 供水位门控（reader 在深度 - 一行 - 裕量之内才发下一行 AR）
//   读侧（disp_timing_gen，pixel_clk）：rd_en 按 beat 消费；rd_words 为读侧
//     可用字数（行启动门控 >= 一行字数，保证行内不欠跑）；行中段允许气泡
//     （shape 契约与相机源一致：tvalid 气泡原样传递，按拍计数）
//
// 容量：512 字 = 4 行（120 字/行）。稳态 reader 写速 >> gen 读速，FIFO 常
// 满水位运行，行启动门控恒通过；跨帧错序事件只损失画面连续性（丢帧级），
// 不产生短行。
// ============================================================================

module disp_line_fifo #(
    parameter AW          = 9,     // 512 字（= 4 行 x 120 字）
    parameter LINE_WORDS  = 120    // 每行 512b 字数（960 beat / 8）
)(
    // ---- 写侧（sys_clk_200m）----
    input  wire         wr_clk,
    input  wire         wr_rstn,
    input  wire [511:0] wr_data,
    input  wire         wr_en,
    output wire         wr_full,
    output wire [11:0]  wr_level,       // 写侧水位（字，固 12 位，零扩展）

    // ---- 读侧（pixel_clk）----
    input  wire         rd_clk,
    input  wire         rd_rstn,
    input  wire         rd_en,          // beat 消费（64b）
    output wire [63:0]  rd_data,
    output wire         rd_beat_ok,     // 本拍 rd_data 有效
    output wire [11:0]  rd_words        // 读侧可用字数（固 12 位，零扩展）
);

    localparam [AW:0] DEPTH = (1 << AW);

    //--------------------------------------------------------------------
    // BRAM（简单双口：wr_clk 写 / rd_clk 读，寄存输出）
    //--------------------------------------------------------------------
    (* syn_ramstyle = "block_ram" *) reg [511:0] mem [0:DEPTH-1];

    //--------------------------------------------------------------------
    // 指针（AW+1 位环绕）+ 格雷同步
    //   指针与 2FF 同步链全部加 syn_keep：EFX 综合器会重定时/合并跨钟
    //   同步链导致水位失真（2026-10-12 async_path_fifo 同款板级黑屏
    //   前科——gray 链被优化后 empty 恒真/读侧停摆），属已验证必修项
    //--------------------------------------------------------------------
    (* syn_keep = "true" *) reg [AW:0] wr_ptr, rd_ptr;
    wire [AW:0] g_wr = wr_ptr ^ (wr_ptr >> 1);
    wire [AW:0] g_rd = rd_ptr ^ (rd_ptr >> 1);

    (* syn_keep = "true" *) reg [AW:0] g_rd_s0, g_rd_s1;    // rd_ptr -> wr_clk
    (* syn_keep = "true" *) reg [AW:0] g_wr_s0, g_wr_s1;    // wr_ptr -> rd_clk
    always @(posedge wr_clk or negedge wr_rstn)
        if (!wr_rstn) begin g_rd_s0 <= 0; g_rd_s1 <= 0; end
        else        begin g_rd_s0 <= g_rd; g_rd_s1 <= g_rd_s0; end
    always @(posedge rd_clk or negedge rd_rstn)
        if (!rd_rstn) begin g_wr_s0 <= 0; g_wr_s1 <= 0; end
        else        begin g_wr_s0 <= g_wr; g_wr_s1 <= g_wr_s0; end

    function [AW:0] g2b(input [AW:0] g);
        integer i;
        begin
            g2b[AW] = g[AW];
            for (i = AW-1; i >= 0; i = i - 1)
                g2b[i] = g2b[i+1] ^ g[i];
        end
    endfunction

    wire [AW:0] rd_ptr_wsync = g2b(g_rd_s1);    // 写侧视角的读指针
    wire [AW:0] wr_ptr_rsync = g2b(g_wr_s1);    // 读侧视角的写指针

    assign wr_full  = (wr_ptr[AW-1:0] == rd_ptr_wsync[AW-1:0]) &&
                      (wr_ptr[AW]     != rd_ptr_wsync[AW]);
    assign wr_level = (wr_ptr - rd_ptr_wsync);   // 截断至 12 位（LHS 口径）
    assign rd_words = (wr_ptr_rsync - rd_ptr);

    //--------------------------------------------------------------------
    // 写口
    //--------------------------------------------------------------------
    always @(posedge wr_clk or negedge wr_rstn) begin
        if (!wr_rstn)
            wr_ptr <= 0;
        else if (wr_en && !wr_full)
            wr_ptr <= wr_ptr + 1'b1;
    end
    always @(posedge wr_clk) begin
        if (wr_en && !wr_full)
            mem[wr_ptr[AW-1:0]] <= wr_data;
    end

    //--------------------------------------------------------------------
    // 读口：2 槽乒乓预取（掩盖 BRAM 1 拍读延迟）+ 8 beat 串行化
    //
    //   pop 流水：pop_fire(T) 发读地址（q <= mem[raddr] 同沿取旧址）->
    //   T+1 q 有效 -> T+1 沿落空槽。发射槽按 sel 交替，末 beat 释放。
    //   发射吞吐：稳态 8 beat / 1 pop，峰值 1 beat/拍（行内连续消费）。
    //--------------------------------------------------------------------
    reg  [AW-1:0] raddr;
    reg  [511:0]  q;
    reg  [511:0]  slot0, slot1;
    reg           s0_v, s1_v;
    reg           sel;                    // 当前发射槽
    reg  [2:0]    nxt;                    // 槽内 beat 序号 0..7
    reg           pop_pend;

    wire        cur_v     = sel ? s1_v : s0_v;
    wire [511:0] cur_w    = sel ? slot1 : slot0;
    assign rd_data    = cur_w[nxt*64 +: 64];
    assign rd_beat_ok = cur_v;

    wire [1:0]  occ      = {1'b0, s0_v} + {1'b0, s1_v};      // 0..2（须 2 位！）
    wire pop_fire = (occ < 2) && (rd_ptr != wr_ptr_rsync) && !pop_pend;

    always @(posedge rd_clk or negedge rd_rstn) begin
        if (!rd_rstn) begin
            raddr    <= 0;
            pop_pend <= 1'b0;
        end else begin
            q <= mem[raddr];
            if (pop_fire)
                raddr <= raddr + 1'b1;
            pop_pend <= pop_fire;
        end
    end

    always @(posedge rd_clk or negedge rd_rstn) begin
        if (!rd_rstn) begin
            rd_ptr <= 0;
            s0_v   <= 1'b0;
            s1_v   <= 1'b0;
            sel    <= 1'b0;
            nxt    <= 3'd0;
        end else begin
            // pop 落槽（pop_pend 期间 q = 刚弹出的字）
            if (pop_pend) begin
                if (!s0_v) begin slot0 <= q; s0_v <= 1'b1; end
                else       begin slot1 <= q; s1_v <= 1'b1; end
            end
            // 末 beat 释放发射槽并切换
            if (rd_en && cur_v && (nxt == 3'd7)) begin
                if (sel) s1_v <= 1'b0;
                else     s0_v <= 1'b0;
                sel <= ~sel;
                nxt <= 3'd0;
            end else if (rd_en && cur_v) begin
                nxt <= nxt + 3'd1;
            end
            // pop 推进读指针
            if (pop_fire)
                rd_ptr <= rd_ptr + 1'b1;
        end
    end

endmodule
