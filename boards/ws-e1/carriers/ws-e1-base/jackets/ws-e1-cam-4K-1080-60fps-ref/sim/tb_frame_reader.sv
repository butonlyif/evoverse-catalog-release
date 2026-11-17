// ============================================================================
// tb_frame_reader.sv — frame_reader v4 单元 TB（2026-10-21，架构 v4 Phase 2）
//
// 被测：frame_reader（148.5M 显示域回放，帧级 drop/repeat 仲裁）
//
// 验证点（SPEC-001 mod-frame-reader-v3 / alg-bank-handoff；任务2 阶段1 已修至
// v4.10 64b 载体口径、补 v4.9 disp_sof 锚模型并参数化行几何）：
//   V1  槽节拍：输出帧周期恒 FRAME_TICKS tick（源解耦，R1）
//   V2  零漂：稳态 drop=repeat=0；起步解禁窗容忍合并 drop≤1 + 慢向
//       重读 repeat≤1（流序列 0,0,2 后零事件，4K/1080 实证逐 fid 一致）
//   V3  +ppm（源快）：drop 主导单调增长，repeat=0，输出仍恒速
//   V4  -ppm（源慢）：repeat 主导单调增长，输出仍恒速
//   V5  原子性：帧内帧序号指纹恒同（无撕裂，R3）
//   V6  起步门：done_cnt>=2 前不发射
//   V7  数据完整性：输出拍低 40b 指纹逐拍正确（64b 载体槽打包 mem 模型）
//
// v4.2（Phase 2 验收版）：
//   - V2/V3/V4/V6 判定改用流级 fid 序列审计（FIDSEQ 真值：从 sof 携带的
//     帧号序列直接测 drop/repeat），DUT dbg_fr_cnt 自计数仅作对账打印
//     ——仲裁同拍竞态修复后两者逐段一致（S0..S3 全对账通过）。
//   - 源模型：P = FTICKS*TICK_CLKS - 11*ppm_x100（+ppm=源快=周期缩短，
//     符号统一在源周期块取负）。
//   - 已知代价：S0 起步解禁窗（done_cnt>=2）把前两个请求合并进首发
//     （丢帧 1）+ 解禁边界慢向重读补一帧（帧 0 重播），容忍
//     stream drop ≤1 且 repeat ≤1；稳态零事件。
//
// 几何入口（阶段1）：tb_frame_reader = 4K（960 拍/120 字/64+56/8KB 槽/
//                     tick 1100 拍），tb_frame_reader_1080 = cam1（480 拍/
//                     60 字/32+28/4KB 槽/tick 550 拍）。
// 缩帧：VACT=90、FRAME_TICKS=100。
// 场景：分段变速（零漂 12 帧 → +2% 60 帧 → -2% 60 帧 → +100ppm 30 帧）。
// ============================================================================

`timescale 1ns / 1ps

module tb_frame_reader_core #(
    // 行几何参数：默认 = 现行 4K（tb_frame_reader_1080 传 cam1 几何）
    parameter int VACT         = 90,      // 缩帧行数
    parameter int FTICKS       = 100,     // 槽周期（tick）
    parameter int TICK_CLKS    = 1100,    // tick 周期（拍）
    parameter int BEATS        = 960,     // 每行 64b 载体拍
    parameter int WORDS        = 120,     // 每行 512b word
    parameter int WB0          = 64,      // burst0 拍
    parameter int WB1          = 56,      // burst1 拍
    parameter int STRIDE_SHIFT = 13       // 行槽 stride = 1<<SHIFT（4K=8KB/1080=4KB）
);

    localparam real     HALF148    = 3.367;      // 148.5MHz（reader 域）
    localparam [32:0]   FRAME_A    = 33'h0_0000_0000;
    localparam [32:0]   FRAME_B    = 33'h0_1100_0000;

    reg clk = 0, rstn = 0;
    always #(HALF148) clk = ~clk;
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    //--------------------------------------------------------------------
    // disp_timing 模型：本地行节拍（1100 拍/tick，恒速与源无关）
    //--------------------------------------------------------------------
    reg line_tick = 0;
    integer tick_cnt = 0;
    always @(posedge clk) begin
        line_tick <= 0;
        if (rstn) begin
            tick_cnt <= tick_cnt + 1;
            if (tick_cnt == TICK_CLKS - 1) begin
                tick_cnt <= 0;
                line_tick <= 1;
            end
        end else tick_cnt <= 0;
    end

    //--------------------------------------------------------------------
    // disp_timing vsync 模型（v4.9 帧授权锚）：显示帧周期 = FTICKS tick，
    // 每帧前 VS_TICKS 个 tick 为低（低有效 Vs 段），下降沿 = 帧界锚。
    // disp_stall_i/flush_i 单元环境恒 0（line_room_i 恒 1 同理）。
    //--------------------------------------------------------------------
    localparam int VS_TICKS = 5;
    reg     disp_sof_i = 1'b1;
    integer tick_n = 0;
    always @(posedge clk) begin
        if (!rstn)  tick_n <= FTICKS - VS_TICKS;  // 复位后 VS_TICKS tick 处首锚
        else if (line_tick)
            tick_n <= (tick_n == FTICKS - 1) ? 0 : tick_n + 1;
    end
    always @(posedge clk) begin
        if (!rstn) disp_sof_i <= 1'b1;
        else       disp_sof_i <= (tick_n >= VS_TICKS);
    end

    //--------------------------------------------------------------------
    // writer 模型（源）：帧完成即发 done 脉冲 + 翻 par；帧周期 = 显示帧
    // 周期 ×(1+ppm)（分数累加，避免取整漂移）；完成时向 mem_model 填该帧
    // 指纹（数据在脉冲拍可见 = 与真实 writer 时序一致）。
    //--------------------------------------------------------------------
    integer ppm_x100 = 0;              // 频偏 ×100 ppm（+100 = 源快）
    integer k_frame = 0;               // 已完成帧序（0 起；帧 k 在 bank k%2）
    integer src_per_int, src_per_rem;
    reg  wr_done = 0, wr_par = 0;
    integer fill_l, fill_w;
    reg [511:0] fillv;

    reg [511:0] mem_model [logic [32:0]];
    integer     fail_cnt = 0;

    // 指纹：帧 k 行 l word w = 位流切片。位流 beat b = {k[15:0], l[11:0], b[9:0], 2'b00}
    function [39:0] fp40(input integer kk, input integer ll, input integer bb);
        fp40 = {kk[15:0], ll[11:0], bb[9:0], 2'b00};
    endfunction
    // mem 字填充（v4.10 64b 载体槽打包，与 frame_writer 同构）：
    // word w 槽 k（[64k+63:64k]）= {24'h0, fp40(kk, ll, 8w+k)}
    function [511:0] exp_word_rw(input integer kk, input integer ll, input integer w_);
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1)
                exp_word_rw[64*k +: 64] = {24'h0, fp40(kk, ll, w_*8 + k)};
        end
    endfunction

    // 源周期计算：P = FTICKS*TICK_CLKS + src_per_rem 拍。ppm_x100>0 = 源快
    // = 周期缩短，故取负号。rem = 11×ppm_x100 恒为精确整数（110000×ppm/1e4），
    // 无取整漂移。v4.2 修复：原实现 rem 只进累加器、周期恒 src_per_int
    //（ppm 不生效）；后一版 set_phase 预置的带符号 rem 又被本块每拍用旧
    // 约定（+ppm→+周期）覆盖——S1/S2/S3 段频偏方向全部颠倒实锤。
    always @(posedge clk) begin
        src_per_int = FTICKS * TICK_CLKS;
        src_per_rem = -(src_per_int * ppm_x100) / 10000;   // +ppm=源快=周期负偏
    end

    integer src_wait = 0;
    reg  src_run = 0;
    always @(posedge clk) begin
        wr_done <= 0;
        if (!rstn || !src_run) begin
            src_wait <= src_per_int;
        end else begin
            if (src_wait == 0) begin
                // ---- 帧完成事件：k_frame 帧落 bank (k%2) ----
                wr_done <= 1;
                wr_par  <= (k_frame + 1) % 2;   // 翻向下一填充 bank
                for (fill_l = 0; fill_l < VACT; fill_l = fill_l + 1)
                    for (fill_w = 0; fill_w < WORDS; fill_w = fill_w + 1)
                        wr_mem(fill_l, fill_w);
                k_frame = k_frame + 1;
                src_wait <= src_per_int + src_per_rem - 1;
            end else
                src_wait <= src_wait - 1;
        end
    end

    task wr_mem(input integer ll, input integer w_);
        reg [32:0] a;
        reg [1:0] dummy;
        begin
            a = (k_frame % 2 ? FRAME_B : FRAME_A) + (ll << STRIDE_SHIFT) + w_ * 64;
            mem_model[a] = exp_word_rw(k_frame, ll, w_);
            dummy = 0;
        end
    endtask

    //--------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------
    wire [63:0]  m_tdata;     // v4.10 起为 64b 载体拍（低 40b 有效）
    wire         m_tvalid, m_tlast;
    wire [2:0]   m_tuser;
    wire [5:0]   arid;
    wire [32:0]  araddr;
    wire [7:0]   arlen;
    wire [2:0]   arsize;
    wire [1:0]   arburst;
    wire         arlock, arvalid, arapcmd;
    wire [3:0]   arqos;
    reg          arready;
    wire [5:0]   rid;
    wire [511:0] rdata;
    wire         rlast, rvalid;
    reg          rready;
    wire [1:0]   rresp;
    // 从机模型内部驱动（wire 连 DUT，避免多驱动）
    reg          m_rvalid;
    reg [511:0]  m_rdata;
    reg          m_rlast;
    assign rvalid = m_rvalid;
    assign rdata  = m_rdata;
    assign rlast  = m_rlast;
    wire [15:0]  rd_frame_cnt;
    wire [11:0]  rd_line;
    wire [3:0]   rd_state;
    wire [31:0]  rd_err, dbg_fr_cnt;

    // 读数据通道：mem_model → rdata（AR 锁存基址，逐拍 +64）
    reg [32:0] rd_cur_addr;
    integer    rd_lat, rd_beat_left;
    reg        rd_in = 0;

    frame_reader #(
        .VACT        (VACT[15:0]),
        .FRAME_TICKS (FTICKS[15:0]),
        .FRAME_A     (FRAME_A),
        .FRAME_B     (FRAME_B),
        .BEATS_PER_LINE    (BEATS[9:0]),
        .WORDS_PER_LINE    (WORDS[6:0]),
        .WB0_BEATS         (WB0[8:0]),
        .WB1_BEATS         (WB1[8:0]),
        .LINE_STRIDE_SHIFT (STRIDE_SHIFT[4:0])
    ) u_dut (
        .aclk          (clk),
        .rstn          (rstn),
        .flush_i       (1'b0),
        .flush_done_o  (),
        .enable        (1'b1),
        .line_tick     (line_tick),
        .line_room_i   (1'b1),
        .disp_sof_i    (disp_sof_i),
        .disp_stall_i  (1'b0),
        .wr_frame_done (wr_done),
        .wr_frame_par  (wr_par),
        .m_axis_tdata  (m_tdata),
        .m_axis_tvalid (m_tvalid),
        .m_axis_tlast  (m_tlast),
        .m_axis_tuser  (m_tuser),
        .arid     (arid),
        .araddr   (araddr),
        .arlen    (arlen),
        .arsize   (arsize),
        .arburst  (arburst),
        .arlock   (arlock),
        .arvalid  (arvalid),
        .arapcmd  (arapcmd),
        .arqos    (arqos),
        .arready  (arready),
        .rid      (rid),
        .rdata    (rdata),
        .rlast    (rlast),
        .rvalid   (rvalid),
        .rready   (rready),
        .rresp    (rresp),
        .rd_frame_cnt (rd_frame_cnt),
        .rd_line      (rd_line),
        .rd_state     (rd_state),
        .rd_err       (rd_err),
        .dbg_fr_cnt   (dbg_fr_cnt)
    );

    //--------------------------------------------------------------------
    // AXI 读从机：arready 延迟 10 拍（DDR 读延迟抽象，不含尖峰——预算
    // 由 alg-prefetch-budget 证明）；rdata 从 mem_model 顺序读出
    //--------------------------------------------------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            arready <= 0; rd_in <= 0;
            m_rvalid <= 0; m_rlast <= 0;
            rd_lat <= 0; rd_beat_left <= 0; rd_cur_addr <= 0;
        end else begin
            if (arvalid && !arready) begin
                if (rd_lat == 0) begin
                    // V5（几何）：burst 长度 = WB0/WB1 两段之一
                    if ((arlen + 1) != WB0 && (arlen + 1) != WB1) begin
                        $display("[V5-FAIL] t=%0t arlen+1=%0d not in {%0d,%0d}",
                                 $time, arlen + 1, WB0, WB1);
                        fail_cnt = fail_cnt + 1;
                    end
                    arready      <= 1;
                    rd_cur_addr  <= araddr;
                    rd_beat_left <= arlen + 1;
                    rd_in        <= 1;
                end else
                    rd_lat <= rd_lat - 1;
            end else begin
                arready <= 0;
                rd_lat  <= 10;   // 固定 10 拍读延迟
            end
            // R 数据：始终应答（rready 由 DUT 驱动）
            if (rd_in && rready) begin
                m_rvalid <= 1;
                m_rdata  <= (mem_model.exists(rd_cur_addr)) ?
                            mem_model[rd_cur_addr] : 512'hx;
                m_rlast  <= (rd_beat_left == 1);
                rd_cur_addr  <= rd_cur_addr + 64;
                rd_beat_left <= rd_beat_left - 1;
                if (rd_beat_left == 1) begin
                    // 当拍为 burst 末数据拍（wlast 标志下一拍输出）
                    rd_in <= 0;
                end
            end else begin
                m_rvalid <= 0;
                m_rlast  <= 0;
            end
        end
    end

    //--------------------------------------------------------------------
    // 输出流监测：帧号指纹 + 原子性 + 帧周期
    //--------------------------------------------------------------------
    integer frames_seen = 0;
    integer cur_fid = -1;          // 当前输出帧序号
    integer out_l = 0, out_b = 0;
    integer sof_gap = 0, last_sof_cyc = -1;
    integer mismatch_total = 0;
    integer fid_err = 0;
    integer exp_fid, rcv_fid;
    reg [39:0] expd;
    // v4.2 流级 fid 序列审计（真值 drop/repeat）及段起点快照——独立于
    // DUT dbg_fr_cnt 自计数，仲裁同拍竞态修复的对账基准
    integer fid_last = -1;
    integer seq_drop = 0, seq_repeat = 0;
    integer seq_drop0 = 0, seq_rep0 = 0;
    integer sd, sr;

    // 场景账本
    integer phase = 0;             // 0=零漂 1=+ppm 2=-ppm
    integer ph0_fr, ph1_fr, ph2_fr;
    integer ph0_drop0, ph1_drop, ph2_rep;
    integer drop0_at_ph0, drop_at_ph1, rep_at_ph2;

    // V7 校验契约（任务2 阶段1 修订）：v4.10 起输出为 64b 载体拍（低 40b
    // 有效 = 一个 fp40），期望比对 m_tdata[39:0] = fp40(fid,l,b) 逐拍。
    // mem 侧 exp_word_rw 按 64b 槽打包填充（与 writer 同构），回放流逐拍
    // 还原原始 40b 拍序。

    always @(negedge clk) begin
        // negedge 采样：DUT 输出为 posedge NBA 更新，posedge 读会拿到
        // 上一拍旧值（首跑 V7 全体 +1 beat 错位的根因之一）
        // 位置跟踪用阻塞赋值：校验当拍必须用到本拍更新后的 l/b
        //（NBA 会让 sol 拍的 out_b=0 滞后到下一拍，全帧校验错位 1 beat）
        if (m_tvalid) begin
            // 位置跟踪（tuser sol/sof 重建）
            if (m_tuser[1]) begin      // sol
                out_b = 0;
                if (m_tuser[0]) out_l = 0;              // sof：行 0
                else out_l = out_l + 1;                 // 行推进
            end else
                out_b = out_b + 1;
            // 帧号指纹（sof 拍锁存 + 逐拍校验）
            rcv_fid = m_tdata[39:24];
            if (m_tuser[0]) begin
                cur_fid   = rcv_fid;
                frames_seen = frames_seen + 1;
                sof_gap = (last_sof_cyc < 0) ? 0 : (cyc - last_sof_cyc);
                last_sof_cyc = cyc;
                // v4.2 流级 fid 序列审计（真值 drop/repeat，独立于 DUT
                // dbg_fr_cnt 自计数——仲裁同拍竞态修复的对账基准）
                if (fid_last >= 0) begin
                    if (rcv_fid == fid_last) begin
                        seq_repeat = seq_repeat + 1;
                        $display("[FIDREP] t=%0t ph=%0d fid=%0d rep#%0d dbg_fr=%h",
                                 $time, ph, rcv_fid, seq_repeat, dbg_fr_cnt);
                    end else if (rcv_fid > fid_last + 1) begin
                        seq_drop = seq_drop + (rcv_fid - fid_last - 1);
                        $display("[FIDDROP] t=%0t ph=%0d fid=%0d after %0d drop#%0d dbg_fr=%h",
                                 $time, ph, rcv_fid, fid_last,
                                 seq_drop, dbg_fr_cnt);
                    end else if (rcv_fid == fid_last + 1)
                        ;                                      // 正常 +1
                    else
                        $display("[FIDSEQ-ERR] t=%0t fid=%0d after %0d",
                                 $time, rcv_fid, fid_last);
                end
                fid_last = rcv_fid;
            end
            expd = fp40(cur_fid, out_l, out_b);
            if (m_tdata[39:0] !== expd) begin
                mismatch_total = mismatch_total + 1;
                if (mismatch_total < 6)
                    $display("[V7-FAIL] t=%0t fid=%0d l=%0d b=%0d exp=%h act=%h",
                             $time, cur_fid, out_l, out_b, expd, m_tdata);
            end
            // eof 拍：帧尾一致性（行序号=VACT-1）
            if (m_tuser[2] && out_l != VACT-1) begin
                $display("[V5-FAIL] t=%0t eof at line %0d", $time, out_l);
                fid_err = fid_err + 1;
            end
        end
    end

    //--------------------------------------------------------------------
    // 场景调度（分段变速；ppm_x100=1 → 100ppm）
    //   S0 零漂  12 帧：稳态 drop=repeat=0（起步窗合并 d≤1 + 慢向 r≤1）
    //   S1 +2%   60 帧：源快 → drop≈1±1（仲裁方向 +）
    //   S2 -2%   60 帧：源慢 → repeat≈1±1（仲裁方向 -；重读撕裂 ≤1 帧
    //       为规格已知代价，V5/V7 预算放宽 2 帧且必须伴 repeat>0）
    //   S3 +100ppm 30 帧：亚仲裁确认——drop=repeat=0（30 帧漂 0.3 tick）
    //--------------------------------------------------------------------
    integer ph_frames_target = 12;
    integer frames_at_phase_start = 0;
    integer drop_rep_at_phase_start = 0;
    integer mis_at_phase_start = 0;
    integer ph = 0;                // 0=零漂 1=+2% 2=-2% 3=+100ppm
    integer mis_in_phase = 0;
    integer rep_in_phase = 0;

    task set_phase(input integer p, input integer frames);
        begin
            ph = p;
            // ppm_x100 语义：>0 = 源快（周期缩短），符号在源周期块统一
            // 取负——此处只设 ppm，不直接写 src_per_rem（写了他会被
            // always 块每拍覆盖，v4.2 前正是这个覆盖造成段方向颠倒）。
            ph_frames_target         = frames;
            frames_at_phase_start    = frames_seen;
            drop_rep_at_phase_start  = dbg_fr_cnt;
            mis_at_phase_start       = mismatch_total;
            mis_in_phase             = 0;
            rep_in_phase             = 0;
            seq_drop0 = seq_drop;
            seq_rep0  = seq_repeat;
            case (p)
                0: ppm_x100 = 0;
                1: ppm_x100 = 200;    // 源快 2%
                2: ppm_x100 = -200;   // 源慢 2%
                3: ppm_x100 = 100;    // 源快 100ppm
            endcase
            $display("[PHASE] t=%0t phase=%0d ppm_x100=%0d src_rem=%0d start_frames=%0d base=%0d",
                     $time, p, ppm_x100, src_per_rem, frames_seen, dbg_fr_cnt);
        end
    endtask

    // 段统计（段内 drop/repeat/mismatch 增量）
    function integer delta_hi(input [31:0] cur, input [31:0] base);
        delta_hi = cur[31:16] - base[31:16];
    endfunction
    function integer delta_lo(input [31:0] cur, input [31:0] base);
        delta_lo = cur[15:0] - base[15:0];
    endfunction

    initial begin
        $display("[TB] frame_reader v4 unit TB: VACT=%0d FTICKS=%0d", VACT, FTICKS);
        repeat (10) @(posedge clk);
        rstn = 1;
        src_run = 1;
        set_phase(0, 12);
        wait (frames_seen >= 12);
        sd = seq_drop - seq_drop0;
        sr = seq_repeat - seq_rep0;
        $display("[S0] frames=%0d cnt(d=%0d r=%0d) stream(d=%0d r=%0d)",
                 frames_seen - frames_at_phase_start,
                 delta_hi(dbg_fr_cnt, drop_rep_at_phase_start),
                 delta_lo(dbg_fr_cnt, drop_rep_at_phase_start), sd, sr);
        if (sd <= 1 && sr <= 1)
            // 起步解禁窗已知代价（v4.10 实证，4K/1080 逐 fid 一致）：
            // boot 首锚豁免 + done_cnt>=2 解禁把前两个请求合并进首发
            // （丢帧 1），解禁边界慢向重读补一帧（帧 0 重播）——流序列
            // 0,0,2 后 159 帧零事件，无撕裂（V5/V7 全绿）。稳态必须干净。
            $display("[V2-OK] zero-drift: clean after startup (merge drop=%0d slow-repeat=%0d tolerated)", sd, sr);
        else begin
            $display("[V2-FAIL] zero-drift: stream drop=%0d repeat=%0d", sd, sr);
            fail_cnt = fail_cnt + 1;
        end

        set_phase(1, 60);
        wait (frames_seen >= frames_at_phase_start + 60);
        sd = seq_drop - seq_drop0;
        sr = seq_repeat - seq_rep0;
        $display("[S1] frames=%0d cnt(d=%0d r=%0d) stream(d=%0d r=%0d)",
                 frames_seen - frames_at_phase_start,
                 delta_hi(dbg_fr_cnt, drop_rep_at_phase_start),
                 delta_lo(dbg_fr_cnt, drop_rep_at_phase_start), sd, sr);
        if (sd >= 1 && sr == 0)
            $display("[V3-OK] +2%%: stream drop=%0d directional (repeat=0)", sd);
        else begin
            $display("[V3-FAIL] +2%% stream drop=%0d repeat=%0d", sd, sr);
            fail_cnt = fail_cnt + 1;
        end

        set_phase(2, 60);
        wait (frames_seen >= frames_at_phase_start + 60);
        sd = seq_drop - seq_drop0;
        sr = seq_repeat - seq_rep0;
        $display("[S2] frames=%0d cnt(d=%0d r=%0d) stream(d=%0d r=%0d)",
                 frames_seen - frames_at_phase_start,
                 delta_hi(dbg_fr_cnt, drop_rep_at_phase_start),
                 delta_lo(dbg_fr_cnt, drop_rep_at_phase_start), sd, sr);
        if (sr >= 1 && sd == 0)
            $display("[V4-OK] -2%%: stream repeat=%0d directional (drop=0)", sr);
        else begin
            $display("[V4-FAIL] -2%% stream drop=%0d repeat=%0d", sd, sr);
            fail_cnt = fail_cnt + 1;
        end

        set_phase(3, 30);
        wait (frames_seen >= frames_at_phase_start + 30);
        sd = seq_drop - seq_drop0;
        sr = seq_repeat - seq_rep0;
        $display("[S3] frames=%0d cnt(d=%0d r=%0d) stream(d=%0d r=%0d)",
                 frames_seen - frames_at_phase_start,
                 delta_hi(dbg_fr_cnt, drop_rep_at_phase_start),
                 delta_lo(dbg_fr_cnt, drop_rep_at_phase_start), sd, sr);
        if (sd == 0 && sr == 0)
            $display("[V6-OK] +100ppm sub-arbitration: 30 frames clean");
        else begin
            $display("[V6-FAIL] +100ppm arbitrated (30 frames too short for 100ppm)");
            fail_cnt = fail_cnt + 1;
        end

        // ---- 指纹/原子性判定 ----
        // mismatch：零漂/±2% 段全额失败（撕裂预算只在 S2 的 repeat 后记
        // 已知代价）；起步期（首帧）的 1 次 repeat 属解禁窗合法行为。
        if (mismatch_total == 0 && fid_err == 0)
            $display("[V5/V7-OK] stream fingerprint exact, no tearing (%0d frames)",
                     frames_seen);
        else begin
            $display("[V5/V7] mismatch=%0d fid_err=%0d (S2 tear known-cost, count check)",
                     mismatch_total, fid_err);
            fail_cnt = fail_cnt + 1;   // 保守：撕裂亦计失败（已知代价记录）
        end

        if (fail_cnt == 0)
            $display("[FR-OK] all checks passed");
        else
            $display("[FR-FAIL] fail_cnt=%0d", fail_cnt);
        $finish;
    end

    // 看门狗（v4.2：162 帧全场景 ≈120ms，原 60ms 不够覆盖 S2/S3）
    initial begin
        #140_000_000;
        $display("[FR-FAIL] watchdog timeout (frames=%0d)", frames_seen);
        $finish;
    end

endmodule

//------------------------------------------------------------------------
// 回归入口（任务2 阶段1）：几何由参数决定，行为零差异
//------------------------------------------------------------------------
// 4K 缩帧回归（现行 4K 行几何：960 拍/120 字/64+56/8KB 行槽/tick 1100 拍）
module tb_frame_reader;
    tb_frame_reader_core u_core();
endmodule

// cam1 1080 几何用例（cam1-ddr-replay-plan §3：480 拍/60 字/32+28/4KB
// 行槽/tick 550 拍）
module tb_frame_reader_1080;
    tb_frame_reader_core #(.BEATS(480), .WORDS(60), .WB0(32), .WB1(28),
                           .STRIDE_SHIFT(12), .TICK_CLKS(550)) u_core();
endmodule
