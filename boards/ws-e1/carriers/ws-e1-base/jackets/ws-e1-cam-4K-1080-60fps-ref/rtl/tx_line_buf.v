// ============================================================================
// tx_line_buf.v — TX 行缓冲（架构 v4 Phase 3，mod-tx-line-buf）
//
// 写侧 AXIS-64 拍流（ISP yuv，每行 LINE_WORDS=960 拍）8:1 聚合为 512b 宽
// 写入 BRAM（WIDE_WORDS=256 ≈ 2.1 行）；读侧按 64b 拍供 disp_timing HACT
// 拉取，水位（64b 字口径）供行启动门控（alg-line-gate）。
//
//   - 双侧同 CLK-DISP148（v4），指针无需 gray 同步（结构保留直通）
//   - 读延迟 2 拍：BRAM 同步读 + 64b 通道选择输出寄存
//   - 满溢出：门控预算下不可达（alg-prefetch-budget）；防护为整组（8 拍）
//     丢弃并 starve_events++（行粒度保护，绝无半行注入）
//   - BRAM 推断纪律：读侧无复位（mem_q 不清），syn_ramstyle=block_ram
// ============================================================================
module tx_line_buf #(
    parameter DEPTH_WORDS = 2048,       // 64b 字口径（>= 2x960）
    parameter WIDE_WORDS  = 256         // 512b 字口径（= DEPTH_WORDS/8）
) (
    input  wire        clk,
    input  wire        rst_n,
    // 写侧 AXIS-64 拍流（无反压；行界由上游保证，本模块不解析 tuser）
    input  wire [63:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    // 读侧：disp_timing 拉取（非空即读）
    input  wire        rd_en,
    output wire [63:0] rd_data,        // rd_en 后第 2 拍有效
    output wire        rd_valid,       // 与 rd_data 同拍
    output wire [15:0] level_o,        // 64b 字水位（门控输入）
    output wire [31:0] dbg_buf_cnt_o   // {max_level[15:0], starve_events[15:0]}
);

    (* syn_ramstyle = "block_ram" *) reg [511:0] mem [0:WIDE_WORDS-1];

    // 64b 字口径指针（12 位：0..2048，多一位 wrap 区分满/空；mem 地址取
    // 512b 粒度 [10:3]，通道取 [2:0]）
    reg [11:0] wptr, rptr;
    reg [2:0]  agg_beat;                             // 8:1 聚合计数
    reg [511:0] agg_shr;                             // 聚合移位（beat0 -> [63:0]）
    reg [15:0] max_level, starve;

    wire [11:0] level    = wptr - rptr;              // 同域直通（0..2048）
    wire        grp_full = s_axis_tvalid && (agg_beat == 3'd7);
    wire        grp_room = (level <= DEPTH_WORDS - 8);
    wire        grp_wr   = grp_full && grp_room;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr      <= 12'd0;
            rptr      <= 12'd0;
            agg_beat  <= 3'd0;
            agg_shr   <= 512'd0;
            max_level <= 16'd0;
            starve    <= 16'd0;
        end else begin
            // ---- 写侧：8:1 聚合（beat0 落 [63:0]，位序与位流连续切片一致）----
            if (s_axis_tvalid) begin
                agg_beat <= agg_beat + 3'd1;
                if (grp_full) begin
                    agg_beat <= 3'd0;
                    if (grp_room) begin
                        mem[wptr[10:3]] <= {s_axis_tdata, agg_shr[511:64]};
                        wptr <= wptr + 12'd8;
                    end else begin
                        starve <= starve + 16'd1;    // 溢出：整组丢弃
                    end
                end
                agg_shr <= {s_axis_tdata, agg_shr[511:64]};
            end
            // ---- 读侧：非空即消费（rd_issue）----
            if (rd_en && (level != 12'd0))
                rptr <= rptr + 12'd1;
            // ---- 诊断 ----
            if (level > max_level)
                max_level <= level;
        end
    end

    // ---- 读管线：2 拍延迟。地址/通道/有效三级同程（lane 与 mem_q 必须
    // 双寄存同行——lane 单寄存会在输出拍被下一次发射覆盖，组内通道旋转
    // 1 实锤）；输出 64b 通道为寄存后值的组合选择。读侧无复位（BRAM 纪律）。
    reg [7:0]    raddr_q;
    reg [2:0]    lane_q, lane_q2;
    reg [1:0]    pend_q;
    reg [511:0]  mem_q;
    wire         rd_issue = rd_en && (level != 12'd0);

    always @(posedge clk) begin
        // stage1：地址/通道/有效寄存（BRAM 读端口，512b 粒度）
        raddr_q <= rptr[10:3];
        lane_q  <= rptr[2:0];
        pend_q  <= {pend_q[0], rd_issue};
        // stage2：BRAM 同步读（用已寄存地址）+ 通道同行寄存
        mem_q   <= mem[raddr_q];
        lane_q2 <= lane_q;
    end

    assign rd_data  = mem_q[{lane_q2, 6'd0} +: 64];
    assign rd_valid = pend_q[1];
    assign level_o       = {4'd0, level};
    assign dbg_buf_cnt_o = {max_level, starve};

endmodule
