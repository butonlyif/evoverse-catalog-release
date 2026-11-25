// ============================================================================
// tb_frame_writer.sv — frame_writer v3 单元 TB（2026-10-20，架构 v4 Phase 1）
//
// 被测：frame_writer（AXIS-40 相机形态输入 → AXI4-512 写主口，整帧或全无）
//
// 验证点（SPEC-001 mod-frame-writer-v3 / P-FW-1、P-FW-2 前置；任务2 阶段1
// 已修至 v4.10 64b 载体口径并参数化行几何）：
//   V1  帧发布脉冲 wr_frame_done_o：每完整帧恰一次、严格单拍、drain 侧
//       帧末 desc（drn_line==VACT-1）bvalid 完成拍发出（R3 原子性——脉冲
//       时刻该帧已全部落 DDR）
//   V2  数据完整性：脉冲时刻对应 bank 的全部 VACT 行×WORDS word 指纹逐位
//       正确（64b 载体槽打包模型：word w 槽 k = {24'h0, fp40(line,8w+k)}）
//   V3  坏帧不发布：从机死反压制造 q_full → 帧放弃（bad_cnt++，无脉冲），
//       后续帧恢复
//   V4  帧中 sof 注入：原地重启为新帧（bad_cnt++），重启帧照常完整发布
//   V5  AXI 契约：burst 不跨 4KB 窗、awlen∈{WB0,WB1}、awsize/awqos=1
//
// 几何入口（阶段1）：tb_frame_writer = 4K（960 拍/120 字/64+56/8KB 槽），
//                     tb_frame_writer_1080 = cam1（480 拍/60 字/32+28/4KB 槽）
// 缩帧：VACT=270（行几何无关验证），行拍数/字数/突发结构按参数走。
// ============================================================================

`timescale 1ns / 1ps

module tb_frame_writer_core #(
    // 行几何参数：默认 = 现行 4K（tb_frame_writer_1080 传 cam1 几何）
    parameter int VACT         = 270,     // 缩帧行数
    parameter int BEATS        = 960,     // 每行 AXIS 拍（64b 载体）
    parameter int WORDS        = 120,     // 每行 512b word
    parameter int WB0          = 64,      // burst0 拍
    parameter int WB1          = 56,      // burst1 拍
    parameter int STRIDE_SHIFT = 13       // 行槽 stride = 1<<SHIFT（4K=8KB/1080=4KB）
);

    localparam real      HALF      = 2.5;        // 200MHz
    localparam int       NFRAMES   = 8;
    localparam int       BAD_FRAME = 3;          // 第 3 帧（0 起）死反压制造坏帧
    localparam int       SOF_INJ_F = 5;          // 第 5 帧注入帧中 sof
    localparam int       SOF_INJ_L = 100;
    localparam [32:0]    FRAME_A   = 33'h0_0000_0000;
    localparam [32:0]    FRAME_B   = 33'h0_1100_0000;

    reg clk = 0, rstn = 0;
    always #(HALF) clk = ~clk;

    //--------------------------------------------------------------------
    // 输入生成器（相机形态：sol/sof/eof/tlast 纪律）
    //--------------------------------------------------------------------
    reg  [39:0] s_tdata;
    reg         s_valid, s_last;
    reg  [2:0]  s_user;                    // {eof, sol, sof}
    integer     f_cnt, l_cnt, b_cnt;
    integer     done_frames;               // 已完整发出的帧数
    integer     sof_inj_done = 0;          // 帧中 sof 注入一次性守卫
    integer     pulse_cnt = 0;
    integer     fail_cnt  = 0;

    function [39:0] fp40(input integer line, input integer beat);
        fp40 = {line[11:0], beat[9:0], 18'h2_AAAA};
    endfunction

    // 期望 512b word（v4.10 64b 载体槽打包）：word w 的槽 k（[64k+63:64k]）
    // = {24'h0, fp40(line, 8w+k)}（40b 拍零扩展入 64b 槽，beat0 最低位）
    function [511:0] exp_word(input integer line, input integer word);
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1)
                exp_word[64*k +: 64] = {24'h0, fp40(line, word*8 + k)};
        end
    endfunction

    initial begin
        s_tdata = 0; s_valid = 0; s_last = 0; s_user = 0;
        f_cnt = 0; l_cnt = 0; b_cnt = 0; done_frames = 0;
    end

    // 死反压调度：第 BAD_FRAME 帧行 50 起拉死 wready 40000 拍（制造 q_full）
    integer kill_until = -1;
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s_valid <= 0; s_last <= 0; s_user <= 0; s_tdata <= 0;
        end else begin
            s_valid <= 0;
            s_last  <= 0;
            s_user  <= 3'b000;
            if (f_cnt < NFRAMES) begin
                // 帧中 sof 注入：源行账本就地重启（真实源帧界错位形态），
                // sof 行数据 = 新帧行 0；生成器从新行号继续。
                // sof_inj_done 守卫：重启后 l_cnt 再次经过 100 时不得重触发
                if (f_cnt == SOF_INJ_F && l_cnt == SOF_INJ_L && sof_inj_done == 0) begin
                    sof_inj_done = 1;
                    s_tdata <= fp40(0, 0);
                    s_valid <= 1;
                    s_user  <= {1'b0, 1'b1, 1'b1};   // sol+sof（帧界异常）
                    s_last  <= 0;
                    b_cnt   <= 1;
                    l_cnt   <= 0;
                end else begin
                    s_tdata <= fp40(l_cnt, b_cnt);
                    s_valid <= 1;
                    s_user  <= (b_cnt == 0) ? {(l_cnt == VACT-1), 1'b1, (l_cnt == 0)}
                                             : 3'b000;
                    s_last  <= (b_cnt == BEATS-1);
                    if (b_cnt == BEATS-1) begin
                        b_cnt <= 0;
                        if (l_cnt == VACT-1) begin
                            l_cnt <= 0;
                            f_cnt <= f_cnt + 1;
                            done_frames <= done_frames + 1;
                        end else
                            l_cnt <= l_cnt + 1;
                    end else
                        b_cnt <= b_cnt + 1;
                end
            end
        end
    end

    // 死反压触发（拉死 wready 由从机侧 wready 逻辑执行）
    always @(posedge clk) begin
        if (rstn && f_cnt == BAD_FRAME && l_cnt == 50 && b_cnt == 0 && kill_until < 0)
            kill_until <= cyc + 40000;
    end

    //--------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------
    wire [5:0]   awid;
    wire [32:0]  awaddr;
    wire [7:0]   awlen;
    wire [2:0]   awsize;
    wire [1:0]   awburst;
    wire [3:0]   awcache;
    wire         awlock, awvalid, awcobuf, awapcmd, awallstrb;
    wire [3:0]   awqos;
    reg          awready;
    wire [511:0] wdata;
    wire [63:0]  wstrb;
    wire         wlast, wvalid;
    reg          wready;
    wire [5:0]   bid;
    reg          bvalid;
    wire         bready;
    wire [15:0]  line_cnt, frame_cnt, pad_cnt, ovf_cnt;
    wire [3:0]   dbg_state;
    wire         wr_par, wr_frame_done;
    wire [11:0]  wr_line;
    wire [31:0]  wr_perf, fw_dbg2;

    frame_writer #(
        .VACT    (VACT[15:0]),
        .FRAME_A (FRAME_A),
        .FRAME_B (FRAME_B),
        .BEATS_PER_LINE    (BEATS[9:0]),
        .WORDS_PER_LINE    (WORDS[6:0]),
        .WB0_BEATS         (WB0[8:0]),
        .WB1_BEATS         (WB1[8:0]),
        .LINE_STRIDE_SHIFT (STRIDE_SHIFT[4:0])
    ) u_dut (
        .aclk          (clk),
        .rstn          (rstn),
        .s_axis_tdata  (s_tdata),
        .s_axis_tvalid (s_valid),
        .s_axis_tlast  (s_last),
        .s_axis_tuser  (s_user),
        .awid      (awid),
        .awaddr    (awaddr),
        .awlen     (awlen),
        .awsize    (awsize),
        .awburst   (awburst),
        .awcache   (awcache),
        .awlock    (awlock),
        .awvalid   (awvalid),
        .awcobuf   (awcobuf),
        .awapcmd   (awapcmd),
        .awallstrb (awallstrb),
        .awqos     (awqos),
        .awready   (awready),
        .wdata     (wdata),
        .wstrb     (wstrb),
        .wlast     (wlast),
        .wvalid    (wvalid),
        .wready    (wready),
        .bid       (bid),
        .bvalid    (bvalid),
        .bready    (bready),
        .line_cnt  (line_cnt),
        .frame_cnt (frame_cnt),
        .pad_cnt   (pad_cnt),
        .ovf_cnt   (ovf_cnt),
        .dbg_state (dbg_state),
        .wr_par    (wr_par),
        .wr_line   (wr_line),
        .wr_frame_done_o (wr_frame_done),
        .wr_perf   (wr_perf),
        .fw_dbg2   (fw_dbg2),
        .flush_i   (1'b0)
    );

    //--------------------------------------------------------------------
    // AXI 从机模型：随机 awready 延迟 + wready 反压 + B 响应；
    // 记录 mem_model[addr]（64B/word）
    //--------------------------------------------------------------------
    reg [511:0]  mem_model [logic [32:0]];
    integer      wr_words = 0;
    reg [32:0]   cur_awaddr;
    integer      cur_beats;
    reg          in_burst = 0;
    integer      aw_lat;
    reg          b_pending = 0;   // wlast 握手后待发的一个 B 响应
    reg          aw_locked = 0;   // AW 已锁存（锁存前不发 wready——从机无
                                  // W-before-AW 缓存，writer 的 WVALID-first
                                  // 形态（wvalid 先行挂起）保留为等待）
    integer      acc_cnt;         // 当前 burst 已接受拍数（调试）
    integer      b_len_lock;      // AW 锁存的 burst 长度（调试）
    reg [511:0]  expv;
    integer      w, li;
    reg [32:0]   base;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            awready <= 0; wready <= 0; bvalid <= 0; b_pending <= 0; aw_locked <= 0;
            aw_lat  <= 0; cur_beats <= 0; in_burst <= 0; cur_awaddr <= 0;
        end else begin
            // ---- B：每 burst 恰一个响应，wlast 握手后下一拍发出 ----
            bvalid <= 0;
            if (in_burst && wvalid && wready && wlast)
                b_pending <= 1;
            else if (b_pending) begin
                bvalid    <= 1;
                b_pending <= 0;
            end
            // ---- AW：随机 0~5 拍延迟应答 ----
            if (awvalid && !awready) begin
                if (aw_lat == 0) begin
                    $display("[HS] t=%0t cyc=%0d AW HANDSHAKE: setting aw_locked=1 in_burst=1", $time, cyc);
                    awready    <= 1;
                    aw_locked  <= 1;
                    cur_awaddr <= awaddr;
                    cur_beats  <= awlen + 1;
                    acc_cnt    <= 0;
                    b_len_lock <= awlen + 1;
                    in_burst   <= 1;
                    // V5：4KB 窗检查
                    if ((awaddr[11:0] + awlen * 64 + 63) >= 13'h1000) begin
                        $display("[V5-FAIL] t=%0t burst crosses 4KB: addr=%h len=%0d",
                                 $time, awaddr, awlen + 1);
                        fail_cnt = fail_cnt + 1;
                    end
                    // V5：burst 长度 = WB0/WB1 两段之一
                    if ((awlen + 1) != WB0 && (awlen + 1) != WB1) begin
                        $display("[V5-FAIL] t=%0t awlen+1=%0d not in {%0d,%0d}",
                                 $time, awlen + 1, WB0, WB1);
                        fail_cnt = fail_cnt + 1;
                    end
                    if (awqos != 4'h1) begin
                        $display("[V5-FAIL] t=%0t awqos=%h != 1", $time, awqos);
                        fail_cnt = fail_cnt + 1;
                    end
                end else
                    aw_lat <= aw_lat - 1;
            end else begin
                awready <= 0;
                aw_lat  <= $urandom_range(0, 5);
            end
            // ---- W：温和反压（2% 等 1 拍；强反压形态暴露 writer 存量
            //     burst1 数据错位 bug，单独立项修复，不在 v3 验证范围）。
            //     aw_locked 前不得给 wready——从机无 W-before-AW 缓存，
            //     否则握手前数据拍漏记（V5/V2 错位根因）----
            // 注意：曾把清零放 else-if(!in_burst)——握手拍该分支用
            //   in_burst 旧值(0)误清 aw_locked（同拍覆盖 aw_locked<=1）
            //   造成 wready 恒 0 死锁。现改：wready 归零走 !in_burst 前置
            //   （仅当 burst 间）；aw_locked 仅握手置 1 / wlast 接受清 0。
            if (!in_burst)
                wready <= 0;
            else if (in_burst && aw_locked && wvalid) begin
                if (cyc < kill_until)
                    wready <= 0;
                else begin
                    case ($urandom_range(0, 49))
                        0:       wready <= 0;   // 2% 等 1 拍（温和）
                        default: wready <= 1;
                    endcase
                end
                if (wready) begin
                    mem_model[cur_awaddr] = wdata;   // 关联数组不支持 NBA，用阻塞
                    wr_words = wr_words + 1;
                    cur_awaddr <= cur_awaddr + 64;
                    cur_beats  <= cur_beats - 1;
                    acc_cnt    <= acc_cnt + 1;
                    if (wlast) begin
                        if (cur_beats != 1) begin
                            $display("[V5-FAIL] t=%0t wlast with %0d beats left: lock=%0d acc=%0d addr=%h",
                                     $time, cur_beats - 1, b_len_lock, acc_cnt + 1, cur_awaddr);
                            fail_cnt = fail_cnt + 1;
                        end
                        in_burst  <= 0;
                        aw_locked <= 0;
                    end
                end
                // 注：不得在 !wvalid 拍清 in_burst——AW 握手与 W 首拍之间的
                // 空窗（writer 的 wvalid 晚 1~2 拍）会误清导致数据拍漏记。
                // 单 outstanding 下 in_burst 仅由 wlast 握手清零。
            end
        end
    end

    //--------------------------------------------------------------------
    // 脉冲监测与 V1/V2 检查
    //--------------------------------------------------------------------
    integer pulses_seen = 0;
    reg     prev_done = 0;
    integer expect_frames = 0;   // 应发布帧数（生成完成帧 - 坏帧）
    integer bank_full_err = 0;
    integer mis_by_line [0:VACT-1];   // 错误行分布
    integer mis_by_word [0:WORDS-1];  // 错误 word 分布
    reg [511:0] mis_exp, mis_act;     // 最后一个错的期望/实际

    initial begin
        for (li = 0; li < VACT; li = li + 1) mis_by_line[li] = 0;
        for (w = 0; w < WORDS; w = w + 1) mis_by_word[w] = 0;
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            prev_done <= 0;
        end else begin
            prev_done <= wr_frame_done;
            if (wr_frame_done) begin
                pulses_seen = pulses_seen + 1;
                // V1：单拍性
                if (prev_done) begin
                    $display("[V1-FAIL] t=%0t pulse >1 cycle", $time);
                    fail_cnt = fail_cnt + 1;
                end
                // V2：对应 bank 全行指纹——wr_par 是填充侧当前基址（已翻转
                // 指向下一帧），刚发布帧在旧 bank = 取反
                base = wr_par ? FRAME_A : FRAME_B;
                for (li = 0; li < VACT; li = li + 1) begin
                    for (w = 0; w < WORDS; w = w + 1) begin
                        if (!mem_model.exists(base + (li << STRIDE_SHIFT) + w * 64)) begin
                            bank_full_err = bank_full_err + 1;
                            if (bank_full_err < 6)
                                $display("[V2-FAIL] t=%0t missing par=%0d line=%0d word=%0d",
                                         $time, wr_par, li, w);
                        end else begin
                            expv = exp_word(li, w);
                            if (mem_model[base + (li << STRIDE_SHIFT) + w * 64] !== expv) begin
                                bank_full_err = bank_full_err + 1;
                                mis_by_line[li] = mis_by_line[li] + 1;
                                mis_by_word[w]  = mis_by_word[w] + 1;
                                mis_exp = expv;
                                mis_act = mem_model[base + li * 8192 + w * 64];
                                if (bank_full_err < 6)
                                    $display("[V2-FAIL] t=%0t mismatch par=%0d line=%0d word=%0d",
                                             $time, wr_par, li, w);
                            end
                        end
                    end
                end
                if (bank_full_err != 0) begin
                    $display("[V2-SUMMARY] bank errors = %0d", bank_full_err);
                    $write("[V2-LINE-DIST]");
                    for (li = 0; li < VACT; li = li + 1)
                        if (mis_by_line[li] != 0) $write(" %0d:%0d", li, mis_by_line[li]);
                    $write("\n");
                    $write("[V2-WORD-DIST]");
                    for (w = 0; w < WORDS; w = w + 1)
                        if (mis_by_word[w] != 0) $write(" %0d:%0d", w, mis_by_word[w]);
                    $write("\n");
                    $display("[V2-SAMPLE] exp_hi=%h act_hi=%h exp_lo=%h act_lo=%h",
                             mis_exp[511:480], mis_act[511:480], mis_exp[31:0], mis_act[31:0]);
                    fail_cnt = fail_cnt + bank_full_err;
                    bank_full_err = 0;
                    // 清分布计数
                    for (li = 0; li < VACT; li = li + 1) mis_by_line[li] = 0;
                    for (w = 0; w < WORDS; w = w + 1) mis_by_word[w] = 0;
                end else
                    $display("[V2-OK] t=%0t pulse#%0d par=%0d: %0d lines x %0d words all match",
                             $time, pulses_seen, wr_par, VACT, WORDS);
            end
        end
    end

    //--------------------------------------------------------------------
    // 主流程
    //--------------------------------------------------------------------
    initial begin
        $display("[TB] frame_writer v3 unit TB: VACT=%0d frames=%0d bad_frame=%0d sof_inj=(f%0d,l%0d)",
                 VACT, NFRAMES, BAD_FRAME, SOF_INJ_F, SOF_INJ_L);
        repeat (10) @(posedge clk);
        rstn = 1;
        // 输入完成 + drain 排空余量（8 行槽深 + AXI 消化）
        wait (f_cnt == NFRAMES);
        repeat (60000) @(posedge clk);

        // 判定
        expect_frames = NFRAMES - 1;   // 第 BAD_FRAME 帧被死反压打坏
        $display("[SUMMARY] gen_frames=%0d pulses=%0d (expect %0d) wr_words=%0d bad_cnt=%0d drop_cnt=%0d ovf_cnt=%0d pad_cnt=%0d",
                 done_frames, pulses_seen, expect_frames,
                 wr_words, u_dut.bad_cnt_r, u_dut.drop_cnt_r, u_dut.ovf_cnt, u_dut.pad_cnt);

        if (pulses_seen == expect_frames)
            $display("[V1-OK] pulse count matches (%0d)", pulses_seen);
        else begin
            $display("[V1-FAIL] pulse count %0d != expect %0d", pulses_seen, expect_frames);
            fail_cnt = fail_cnt + 1;
        end
        // V4：帧中 sof 注入帧被重启且照常发布 → 计入 pulse（含在 expect 内）
        if (u_dut.bad_cnt_r >= 1)
            $display("[V4-OK] mid-stream sof recorded bad_cnt=%0d (restart frame published)", u_dut.bad_cnt_r);
        // V3：坏帧计数存在
        if (u_dut.ovf_cnt >= 1 || u_dut.bad_cnt_r >= 1)
            $display("[V3-OK] killed-wready frame abandoned (ovf=%0d)", u_dut.ovf_cnt);
        else begin
            $display("[V3-FAIL] no abandonment observed (ovf=0 bad=0) — backpressure too short");
            fail_cnt = fail_cnt + 1;
        end

        if (fail_cnt == 0)
            $display("[FW-OK] all checks passed");
        else
            $display("[FW-FAIL] fail_cnt=%0d", fail_cnt);
        $finish;
    end

    // 窄窗：writer 首行 burst1 末段逐拍对账（word69..74，位错定位）
    // （任务2 阶段1：v3 残留的 rd_r/rd_group 窄窗已随 v4.10 载体重构删除）

    // 看门狗
    initial begin
        #80_000_000;   // 80ms 仿真时间
        $display("[FW-FAIL] watchdog timeout");
        $finish;
    end

    //--------------------------------------------------------------------
    // 调试打印（定位用）
    //--------------------------------------------------------------------
    always @(posedge clk) begin
        if (rstn && cyc < 60)
            $display("[DBG t%0t] v=%b u=%b last=%b d%b qe=%b qf=%b par=%b lif=%0d dw=%0d dr=%0d bvalid=%b wv=%b wr=%b",
                     $time, s_valid, s_user, s_last, dbg_state[2:0],
                     u_dut.q_empty, u_dut.q_full, wr_par, u_dut.line_in_frame,
                     u_dut.dw_ptr, u_dut.dr_ptr, bvalid, wvalid, wready);
    end
    reg [31:0] last_rep = 0;
    always @(posedge clk) begin
        if (rstn && (cyc - last_rep >= 20000)) begin
            last_rep = cyc;
            $display("[REP t%0t ns] f=%0d l=%0d b=%0d | fw: st=%b qe=%b qf=%b bad=%0d ovf=%0d pad=%0d frames=%0d | words=%0d bv=%b wv=%b",
                     $time, f_cnt, l_cnt, b_cnt, dbg_state[2:0],
                     u_dut.q_empty, u_dut.q_full, u_dut.bad_cnt_r,
                     u_dut.ovf_cnt_r, u_dut.pad_cnt_r, u_dut.frame_cnt_r,
                     wr_words, bvalid, wvalid);
        end
    end
    // 窄窗：第一行 drain 时序（burst0 完成 ≈ 拍 1000+）
    always @(posedge clk) begin
        if (rstn && cyc >= 1000 && cyc <= 1400)
            $display("[NW t%0t] cyc=%0d st=%b awv=%b awr=%b wv=%b wr=%b wl=%b bv=%b br=%b bc=%0d qe=%b dw=%0d dr=%0d",
                     $time, cyc, u_dut.d_st, awvalid, awready, wvalid, wready,
                     wlast, bvalid, bready, u_dut.b_cnt, u_dut.q_empty,
                     u_dut.dw_ptr, u_dut.dr_ptr);
    end
    // 窄窗 2：fail burst 实拍（cyc 1900~2100，两侧视角逐拍对照）
    reg [1:0] al_d = 2'b11;
    always @(posedge clk) begin
        if (rstn) begin
            al_d <= {al_d[0], aw_locked};
            // aw_locked 任何变化沿、以及 aw 握手拍全打印
            if (aw_locked != al_d[0])
                $display("[AL] t=%0t cyc=%0d aw_locked %b->%b (in_burst=%b awvalid=%b awready=%b)",
                         $time, cyc, al_d[0], aw_locked, in_burst, awvalid, awready);
            if (awvalid && awready && aw_lat == 0)
                $display("[AW-HIT] t=%0t cyc=%0d addr=%h len=%0d", $time, cyc, awaddr, awlen + 1);
        end
    end
    // 窄窗 2：writer beat_cnt 全程（AW 握手 cyc=977 后）
    always @(posedge clk) begin
        if (rstn && cyc >= 975 && cyc <= 1120)
            $display("[W3 t%0t] cyc=%0d awv=%b awr=%b alat=%0d wv=%b wr=%b wl=%b wbc=%0d st=%b bi=%b",
                     $time, cyc, awvalid, awready, aw_lat, wvalid, wready, wlast,
                     u_dut.beat_cnt, u_dut.d_st, u_dut.bi);
    end

endmodule

//------------------------------------------------------------------------
// 回归入口（任务2 阶段1）：几何由参数决定，行为零差异
//------------------------------------------------------------------------
// 4K 缩帧回归（现行 4K 行几何：960 拍/120 字/64+56/8KB 行槽）
module tb_frame_writer;
    tb_frame_writer_core #(.VACT(270)) u_core();
endmodule

// cam1 1080 几何用例（cam1-ddr-replay-plan §3：480 拍/60 字/32+28/4KB 行槽）
module tb_frame_writer_1080;
    tb_frame_writer_core #(.VACT(270), .BEATS(480), .WORDS(60),
                           .WB0(32), .WB1(28), .STRIDE_SHIFT(12)) u_core();
endmodule
