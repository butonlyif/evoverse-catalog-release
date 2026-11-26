// ============================================================================
// tb_disp_timing.sv — disp_timing v2 + tx_line_buf 单元 TB（v4 Phase 3）
//
// 验证点：
//   B0  tx_line_buf 独立子测：8:1 聚合位序 / 水位 / 溢出整组丢弃
//       （starve）/ 2 拍读延迟 / 排空后水位归零
//   V1  行契约：每个 valid 突发恒 960 拍连续（无短行/断流，R4）
//   V2  帧契约：每帧 line_tick = FRAME_SLOTS 槽；line_num 0..VACT-1 递进；
//       frame_num 逐帧 +1；vsync 低窗 = VSP 行
//   V3  门控：快源 late 增量=0；慢源 late 增量>0（帧率锁定供给率）
//   V4  数据完整性：TX 拍流 = 写入拍流按序（FIFO 序，逐拍比对）
//   V5  TX D8 契约：hsync 低窗=HSP、datatype/haddr 常量、frame_open
//       每帧恰 1 拍
//   V6  行内零欠载（门控预算生效，under_cnt=0）
//
// 缩帧：VACT=90、FRAME_SLOTS=100（VSP2/VBP4/VFP1/PAD3）。
// 几何入口（任务2 阶段2）：tb_disp_timing = 4K（1100 拍/960 字/44+75+18 段/
// haddr 3840），tb_disp_timing_1080 = cam1（550 拍/480 字/11+37+19 段/
// haddr 1920——CEA HFP 22 挤 3 拍给 GATE+PREF 的 RTL 实测口径）。
// ============================================================================

`timescale 1ns / 1ps

module tb_disp_timing_core #(
    parameter int LINE_CLKS   = 1100,
    parameter int FRAME_SLOTS = 100,
    parameter int LINE_WORDS  = 960,
    parameter int VSP_L = 2, VBP_L = 4, VACT_L = 90, VFP_L = 1, PAD_L = 3,
    parameter int HSP_CLKS = 44, HBP_CLKS = 75, HFP_CLKS = 18,
    parameter int HACT_PX  = 3840,
    parameter int GAP_FAST = 100       // 快源行间隙（供给率须 > 显示率：
                                       // 4K 1060<1100 / 1080 540<550）
);

    localparam real HALF = 3.367;        // 148.5MHz
    localparam int DEPTH_WORDS = 2048;
    reg clk = 0, rstn = 0;
    always #(HALF) clk = ~clk;
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // ------------------------------------------------------------------
    // DUT 互联（buf_rd_en 经 TB 端接：Phase A 由 TB 独立驱动做子测）
    // ------------------------------------------------------------------
    reg         s_tvalid = 0;
    reg  [63:0] s_tdata  = 0;
    reg         dt_rstn  = 0;            // disp_timing 复位（Phase A 独立压制）
    reg         tb_rd_en = 0;            // Phase A 排空驱动
    wire        dt_rd_en;
    wire [63:0] buf_rdata;
    wire        buf_valid;
    wire [15:0] buf_level;
    wire        hsync, vsync, pdv, frame_open;
    wire [5:0]  datatype;
    wire [63:0] pixel_data;
    wire [15:0] haddr, line_num, frame_num;
    wire        line_tick;
    wire [31:0] dbg_dtg, dbg_buf;
    wire        buf_rd_en = tb_rd_en | dt_rd_en;

    tx_line_buf #(.DEPTH_WORDS(DEPTH_WORDS)) u_buf (
        .clk(clk), .rst_n(rstn),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid),
        .rd_en(buf_rd_en), .rd_data(buf_rdata), .rd_valid(buf_valid),
        .level_o(buf_level), .dbg_buf_cnt_o(dbg_buf)
    );

    disp_timing #(
        .LINE_CLKS(LINE_CLKS), .FRAME_SLOTS(FRAME_SLOTS),
        .LINE_WORDS(LINE_WORDS),
        .VSP_L(VSP_L), .VBP_L(VBP_L), .VACT_L(VACT_L),
        .VFP_L(VFP_L), .PAD_L(PAD_L),
        .HSP_CLKS(HSP_CLKS), .HBP_CLKS(HBP_CLKS), .HFP_CLKS(HFP_CLKS),
        .HACT_PX(HACT_PX),
        // 1 行水位字 = LINE_WORDS 拍 × 40b ÷ 64b（4K=600 / 1080=300）
        .LINE_BUF_WORDS(LINE_WORDS * 40 / 64)
    ) u_dt (
        .clk(clk), .rst_n(dt_rstn),
        .buf_rd_en(dt_rd_en), .buf_rdata(buf_rdata), .buf_valid(buf_valid),
        .buf_level(buf_level),
        .hsync(hsync), .vsync(vsync), .datatype(datatype),
        .pixel_data(pixel_data), .pixel_data_valid(pdv),
        .haddr(haddr), .line_num(line_num), .frame_num(frame_num),
        .frame_open(frame_open), .line_tick_o(line_tick),
        .dbg_dtg_cnt_o(dbg_dtg)
    );

    // ------------------------------------------------------------------
    // V7 PAD=0 角回归（2026-10-21 板级 Vp 4096 行 bug）：PAD=0 时帧周期
    // 必须恰为 FRAME_SLOTS×LINE_CLKS，Vp 不得数满 2^12 行。恒满水源
    // （buf_valid=1、level=0x7FFF）只验时序不验数据。
    // ------------------------------------------------------------------
    localparam int FS0 = VSP_L + VBP_L + VACT_L + VFP_L;   // 97，PAD=0
    wire vs0, tick0, fo0, dt_rd0;
    wire [15:0] ln0, fn0;
    disp_timing #(
        .LINE_CLKS(LINE_CLKS), .FRAME_SLOTS(FS0), .LINE_WORDS(LINE_WORDS),
        .VSP_L(VSP_L), .VBP_L(VBP_L), .VACT_L(VACT_L),
        .VFP_L(VFP_L), .PAD_L(0),
        .HSP_CLKS(HSP_CLKS), .HBP_CLKS(HBP_CLKS), .HFP_CLKS(HFP_CLKS),
        .LINE_BUF_WORDS(LINE_WORDS * 40 / 64)
    ) u_dt0 (
        .clk(clk), .rst_n(dt_rstn),
        .buf_rd_en(dt_rd0), .buf_rdata(64'd0), .buf_valid(1'b1),
        .buf_level(16'h7FFF),
        .hsync(), .vsync(vs0), .datatype(), .pixel_data(),
        .pixel_data_valid(), .haddr(), .line_num(ln0), .frame_num(fn0),
        .frame_open(fo0), .line_tick_o(tick0), .dbg_dtg_cnt_o()
    );
    reg pad_done = 0;
    integer pad_err = 0;
    initial begin
        wait (dt_rstn);
        @(posedge vs0);
        for (int f = 0; f < 4; f++) begin
            automatic int t0 = cyc;
            @(posedge vs0);
            if (cyc - t0 !== FS0 * LINE_CLKS) begin
                $display("[V7-FAIL] PAD=0 frame period=%0d exp=%0d",
                         cyc - t0, FS0 * LINE_CLKS);
                pad_err = pad_err + 1;
            end
        end
        pad_done = 1;
    end

    // 编码：写序号 w -> 拍数据（分片异或指纹，防通道对调漏检）
    function [63:0] enc(input integer w);
        enc = {{2{w[15:0]}}, {2{~w[15:0]}}};
    endfunction

    integer fail_cnt = 0;
    integer wseq = 0;                    // 全局写序号
    integer i, lat;

    // ------------------------------------------------------------------
    // 源模型：逐行写 960 拍；行间隙可调（快源 100 / 慢源 540）；水位
    // 自限幅（模拟 ISP 有界延迟，防溢出丢拍干扰完整性判定）
    // ------------------------------------------------------------------
    reg src_run = 0;
    integer gap = 100;
    integer bi2;
    initial begin
        wait (src_run);
        forever begin
            wait (buf_level < 16'd1800);
            for (bi2 = 0; bi2 < LINE_WORDS; bi2 = bi2 + 1) begin
                @(posedge clk);
                s_tvalid <= 1'b1;
                s_tdata  <= enc(wseq + bi2);
            end
            wseq = wseq + LINE_WORDS;
            @(posedge clk);
            s_tvalid <= 1'b0;
            repeat (gap) @(posedge clk);
        end
    end

    // ------------------------------------------------------------------
    // B0：tx_line_buf 独立子测（disp_timing 压复位，TB 独占读口）
    // 写 3000 拍（375 组 > 256 组）：119 组溢出丢弃；排空 2048 字比对；
    // 校验水位/starve/2 拍读延迟。
    // ------------------------------------------------------------------
    integer rseq = 0;
    integer first_issue = -1, first_valid = -1;
    initial begin
        repeat (10) @(posedge clk);
        rstn = 1;
        for (i = 0; i < 3000; i = i + 1) begin
            @(posedge clk);
            s_tvalid <= 1'b1;
            s_tdata  <= enc(wseq + i);
        end
        wseq = 3000;
        @(posedge clk);
        s_tvalid <= 1'b0;
        repeat (4) @(posedge clk);
        if (buf_level !== 16'd2048) begin
            $display("[B0-FAIL] level=%0d exp=2048", buf_level);
            fail_cnt = fail_cnt + 1;
        end
        if (dbg_buf[15:0] !== 16'd119) begin
            $display("[B0-FAIL] starve=%0d exp=119", dbg_buf[15:0]);
            fail_cnt = fail_cnt + 1;
        end
        // ---- 排空 2048 字（内容按序 + 首拍延迟 2）----
        for (i = 0; i < DEPTH_WORDS + 8; i = i + 1) begin
            @(posedge clk);
            tb_rd_en <= (i < DEPTH_WORDS);
            if (tb_rd_en && first_issue < 0) first_issue = cyc;
            if (buf_valid) begin
                if (first_valid < 0) first_valid = cyc;
                if (buf_rdata !== enc(rseq)) begin
                    $display("[B0-FAIL] rd[%0d]=%h exp=%h", rseq, buf_rdata, enc(rseq));
                    fail_cnt = fail_cnt + 1;
                end
                rseq = rseq + 1;
            end
        end
        tb_rd_en <= 1'b0;
        if (rseq !== 2048) begin
            $display("[B0-FAIL] drained=%0d exp=2048", rseq);
            fail_cnt = fail_cnt + 1;
        end
        if (buf_level !== 16'd0) begin
            $display("[B0-FAIL] drain level=%0d exp=0", buf_level);
            fail_cnt = fail_cnt + 1;
        end
        if ((first_valid - first_issue) !== 2) begin
            $display("[B0-FAIL] rd latency=%0d exp=2", first_valid - first_issue);
            fail_cnt = fail_cnt + 1;
        end
        if (fail_cnt == 0)
            $display("[B0-OK] tx_line_buf standalone: agg/level/starve/latency");
        // ---- 释放 disp_timing：缓冲空起步，主场景写入从 wseq=3000 起 ----
        repeat (4) @(posedge clk);
        dt_rstn = 1;
        src_run = 1;
    end

    // ------------------------------------------------------------------
    // 主监视器（单进程，阻塞赋值消跨块竞态）
    //   V1 突发恒 960 连续 / V2 行号-帧号-帧槽 / V4 数据逐拍
    // ------------------------------------------------------------------
    integer burst_len = 0;
    integer pdv_q = 0;
    reg strict = 1;                      // 快源段帧槽严格 ==；慢源段允许拉伸
    integer tx_beats = 0;
    integer ticks_frame = 0;
    integer last_frame = -1;
    integer exp_line = 0;
    integer open_cnt = 0;
    integer vs_fall_cyc = -1;
    integer hs_low = 0;

    always @(posedge clk) if (rstn && dt_rstn) begin
        // ---- TX 拍流账本 ----
        if (pdv) begin
            if (pdv_q == 0) begin           // 突发起点：行号连续性
                if (line_num !== exp_line[15:0]) begin
                    $display("[V2-FAIL] line_num=%0d exp=%0d @cyc%0d",
                             line_num, exp_line, cyc);
                    fail_cnt = fail_cnt + 1;
                    if (fail_cnt > 8) $finish;
                end
                exp_line = exp_line + 1;
                if (exp_line == VACT_L) exp_line = 0;
            end
            burst_len = burst_len + 1;
            // V4：TX 第 n 拍 = 主场景写入第 n 拍（起点 wseq=3000）
            if (pixel_data !== enc(3000 + tx_beats)) begin
                $display("[V4-FAIL] tx[%0d]=%h exp=%h",
                         tx_beats, pixel_data, enc(3000 + tx_beats));
                fail_cnt = fail_cnt + 1;
                if (fail_cnt > 8) $finish;
            end
            tx_beats = tx_beats + 1;
        end else if (pdv_q != 0) begin       // 突发结束：V1 长度
            if (burst_len !== LINE_WORDS) begin
                $display("[V1-FAIL] burst=%0d exp=960 @cyc%0d", burst_len, cyc);
                fail_cnt = fail_cnt + 1;
            end
            burst_len = 0;
        end
        pdv_q = pdv;

        // ---- 槽节拍 / 帧结构 ----
        if (line_tick) begin
            if (last_frame < 0) begin
                last_frame  = frame_num;
                ticks_frame = 1;
            end else if (frame_num != last_frame) begin
                // 边界拍 frame_num 已前翻（与 tick 同拍）——该拍为旧帧
                // 第 FRAME_SLOTS 拍（旧帧实收 = ticks_frame + 1），
                // 新帧从下一 tick 重新从 0 计。慢源段跳槽拉长帧（≥100）。
                if (strict ? (ticks_frame !== FRAME_SLOTS - 1)
                           : (ticks_frame < FRAME_SLOTS - 1)) begin
                    $display("[V2-FAIL] frame %0d ticks=%0d exp=%0d",
                             last_frame, ticks_frame + 1, FRAME_SLOTS);
                    fail_cnt = fail_cnt + 1;
                end
                ticks_frame = 0;
                last_frame  = frame_num;
                exp_line    = 0;
            end else
                ticks_frame = ticks_frame + 1;
        end
        if (frame_open) open_cnt = open_cnt + 1;

        // ---- vsync 低窗 = VSP 行 × LINE_CLKS ----
        if (!vsync) begin
            if (vs_fall_cyc < 0) vs_fall_cyc = cyc;
        end else if (vs_fall_cyc >= 0) begin
            if ((cyc - vs_fall_cyc) !== VSP_L * LINE_CLKS) begin
                $display("[V2-FAIL] vsync low=%0d exp=%0d",
                         cyc - vs_fall_cyc, VSP_L * LINE_CLKS);
                fail_cnt = fail_cnt + 1;
            end
            vs_fall_cyc = -1;
        end

        // ---- hsync 低窗 = HSP（V5）----
        if (!hsync) hs_low = hs_low + 1;
        else if (hs_low != 0) begin
            if (hs_low !== HSP_CLKS) begin
                $display("[V5-FAIL] hsync low=%0d exp=%0d", hs_low, HSP_CLKS);
                fail_cnt = fail_cnt + 1;
            end
            hs_low = 0;
        end
    end

    // ------------------------------------------------------------------
    // 场景调度与判定：快源 3 帧（late 增量 0）→ 慢源 5 帧（late 增长）
    // ------------------------------------------------------------------
    integer l0, l1, l2;
    initial begin
        wait (dt_rstn);
        gap = GAP_FAST;
        wait (frame_num == 1);
        repeat (20) @(posedge clk);
        l0 = dbg_dtg[31:16];
        wait (frame_num == 4);
        l1 = dbg_dtg[31:16];
        if (l1 - l0 != 0) begin
            $display("[V3-FAIL] fast phase late +%0d exp=0", l1 - l0);
            fail_cnt = fail_cnt + 1;
        end
        gap = 540;
        strict = 0;
        wait (frame_num == 5);
        repeat (20) @(posedge clk);
        l2 = dbg_dtg[31:16];
        wait (frame_num == 10);
        if (dbg_dtg[31:16] - l2 == 0) begin
            $display("[V3-FAIL] slow phase late no growth");
            fail_cnt = fail_cnt + 1;
        end
        // ---- V6 行内零欠载 ----
        if (dbg_dtg[15:0] != 0) begin
            $display("[V6-FAIL] under=%0d exp=0", dbg_dtg[15:0]);
            fail_cnt = fail_cnt + 1;
        end
        // ---- V5 D8 常量 / frame_open 每帧 1 拍 ----
        if (datatype !== 6'h1E || haddr !== HACT_PX[15:0]) begin
            $display("[V5-FAIL] datatype=%h haddr=%0d", datatype, haddr);
            fail_cnt = fail_cnt + 1;
        end
        if (open_cnt < 9) begin
            $display("[V5-FAIL] frame_open pulses=%0d exp>=9", open_cnt);
            fail_cnt = fail_cnt + 1;
        end
        if (tx_beats < 8 * VACT_L * LINE_WORDS) begin
            $display("[SUM-FAIL] tx_beats=%0d too few", tx_beats);
            fail_cnt = fail_cnt + 1;
        end
        // ---- V7 PAD=0 角回归判定 ----
        wait (pad_done);
        fail_cnt = fail_cnt + pad_err;
        if (fail_cnt == 0)
            $display("[DT-OK] disp_timing v2 + tx_line_buf all checks passed (tx_beats=%0d)",
                     tx_beats);
        else
            $display("[DT-FAIL] fail_cnt=%0d", fail_cnt);
        $finish;
    end

    // 看门狗（快 4 帧 ~3ms + 慢 6 帧 ~6ms + 子测，留裕量）
    initial begin
        #15_000_000;
        $display("[DT-FAIL] watchdog (frame_num=%0d tx_beats=%0d)", frame_num, tx_beats);
        $finish;
    end

endmodule

// 4K60 几何（cam0 现行为：1100 拍 / 960 字 / 44+75+18 段 / haddr 3840）
module tb_disp_timing;
    tb_disp_timing_core #(
        .LINE_CLKS(1100), .LINE_WORDS(960),
        .HSP_CLKS(44), .HBP_CLKS(75), .HFP_CLKS(18), .HACT_PX(3840)
    ) u_core ();
endmodule

// 1080p60 几何（cam1：550 拍 / 480 字 / 11+37+19 段 / haddr 1920）
module tb_disp_timing_1080;
    tb_disp_timing_core #(
        .LINE_CLKS(550), .LINE_WORDS(480),
        .HSP_CLKS(11), .HBP_CLKS(37), .HFP_CLKS(19), .HACT_PX(1920),
        .GAP_FAST(60)                  // 480+60=540 < 550 保持快源
    ) u_core ();
endmodule
