//============================================================================
// tb_cam_udp.sv — G10 相机 UDP 直推单元级联合仿真（黑屏定位）
// 复现路径：BFM(200M 相机流) → 顶层写窗(复刻) → async_fifo（G11i 标准 FIFO）
//           → cam_udp_pacer → udp_pat_gen_v2 cam 分支 → AXI-S payload
// 判据：gen 数据段解出的 40 位组应等于 BFM 写入序（特征码 {4'hA,q[31:0],4'h5}）
//       板上现象 = payload 全 0；仿真若复现即纯逻辑 bug，波形定位
//============================================================================
`timescale 1ns/1ps

module tb_cam_udp;

    reg clk200 = 1'b0;
    reg clk125 = 1'b0;
    always #2.5 clk200 = ~clk200;    // 200 MHz
    always #4.0  clk125 = ~clk125;   // 125 MHz

    reg mac_rstn   = 1'b0;
    reg cam_src_en = 1'b0;      // pacer 侧 cam_en（CSR bit6 → pacer.frame_active）
    reg cam_src_en_gen = 1'b0;  // gen 侧 cam_en（CSR bit6 → gen.cam_en 锁存 cam_r）
                                // 场景4可分开驱动：gen 有 cam_r 而 pacer 哑火（板上实证组合）

    // ---------------- BFM：200M 域相机 RAW10 流 ----------------
    // 每拍 tvalid=1；tdata = {4'hA, q32[31:0], 4'h5}（特征码，q32 全局组计数）
    reg         raw_tvalid = 1'b0;
    reg [39:0]  raw_tdata  = 40'h0;
    reg [2:0]   raw_tuser  = 3'b000;     // {eof, sol, sof}
    reg         bfm_run    = 1'b0;
    integer     q32        = 0;          // 全局组计数（跨帧不停）
    integer     q_frame    = 0;          // 帧内组计数 0..518399
    integer     in_line    = 0;          // 行内组计数
    integer     gap_cnt    = 0;          // 行消隐拍计数
    integer     vblank     = 0;          // 帧消隐拍计数
    // G11n14：真实节律 BFM（G11n13 直方图定案 + ILA 行内结构）——
    //   行 = 行首 51 拍连段（ILA tvrun_max）+ body Bresenham 均匀放余组
    //        （ILA 实测：行有效跨度 633 拍、tvalid 480 拍，body 占空 429/582≈74%），
    //        行周期 = 633 + LN_GAP = 2961 拍 = 14.8µs（hsgap_min 板测）
    //   帧 = 1080 行背靠背（段长 3,197,880 拍 = 15.99ms，段写速 32.43M 组/s）
    //        + 帧尾单 gap 3,469,632 拍 = 17.35ms（hsgap_max 板测）→ 帧周期 33.34ms
    //   收支：段净积 ≈ 518400 − 23.96M×15.99ms ≈ 135,351 组 → bank FIFO 163,840 吸收
    //        （2^18 需 1024 块 BRAM 超资源，bank0=2^17+bank1=2^15 拼接 640 块），
    //        帧尾 17.35ms 排空 135K 需 5.7ms ✓ 整帧收支 800K > 518.4K ✓
    localparam integer LN_QUADS = 480;
    localparam integer LN_HEAD  = 51;        // 行首连段拍数（ILA tvrun_max）
    localparam integer LN_SPAN  = 633;       // 行有效跨度（ILA 实测）
    localparam integer LN_GAP   = 2961 - LN_SPAN;   // 2328 行距（hsgap_min=2961）
    localparam integer VB_GAP   = 3469632;   // 帧尾 gap 17.35ms@200M（G11n13 直方图 D 桶）
    localparam integer LN_BODY  = LN_SPAN - LN_HEAD;   // 582 body 拍数
    localparam integer LN_BODYQ = LN_QUADS - LN_HEAD;  // 429 body 组数

    // 期望队列（FIFO 写入序，环形 262144——G11n14：bank FIFO 163,840 下稳态积压
    // 可达 ~135K，16384 环回绕必然碰撞假阳性；262144 > 2×163840 全覆盖无碰撞）
    reg [39:0]  exp_q [0:262143];
    integer     exp_wr = 0, exp_rd = 0;
    integer     full_rej = 0;   // armed&&tvalid&&full：被 FIFO 满拒绝的相机组（板上丢组对拍物）
    integer     drain_cnt = 0;  // FIFO 排空后 gen 重复末值组（灰带对拍物）
    integer     mismatch = 0;   //（提前声明：帧末统计块 L160 先于监视器使用）
    integer     frm_cnt   = 0;

    // G11n14 行内节律状态：行首 51 拍连段全有效；body 用 Bresenham 累进器把
    // 429 组均匀摊到 582 拍（每拍 acc+429，≥582 即发组并扣 582）——精确复刻
    // ILA"跨度 633 拍、480 有效"的 74% 占空，且最后一组恰落在跨度末拍。
    integer     line_beat = 0;   // 行内拍计数（0..LN_SPAN-1）
    integer     body_acc  = 0;   // body Bresenham 累进器
    wire        head_zone = (line_beat < LN_HEAD);
    wire        body_fire = !head_zone && (body_acc + LN_BODYQ >= LN_BODY);
    wire        bfm_fire  = (in_line < LN_QUADS) && (head_zone || body_fire);

    always @(posedge clk200) begin
        if (!bfm_run) begin
            raw_tvalid <= 1'b0; q_frame <= 0; in_line <= 0; gap_cnt <= 0; vblank <= 0;
            line_beat <= 0; body_acc <= 0;
        end else if (vblank > 0) begin
            vblank <= vblank - 1; raw_tvalid <= 1'b0;
            line_beat <= 0; body_acc <= 0; in_line <= 0;
        end else if (gap_cnt > 0) begin
            gap_cnt <= gap_cnt - 1; raw_tvalid <= 1'b0;
            line_beat <= 0; body_acc <= 0; in_line <= 0;
        end else if (bfm_fire) begin
            raw_tvalid <= 1'b1;
            raw_tuser  <= {(q_frame == 518399), (in_line == 0), (q_frame == 0)};
            raw_tdata  <= {4'hA, q32[31:0], 4'h5};
            q32     <= q32 + 1;
            q_frame <= (q_frame == 518399) ? 0 : q_frame + 1;   //G11i：帧内计数回绕
            if (q_frame == 518399) begin
                in_line <= 0; line_beat <= 0; body_acc <= 0; vblank <= VB_GAP;
            end else if (in_line == LN_QUADS-1) begin
                in_line <= 0; line_beat <= 0; body_acc <= 0; gap_cnt <= LN_GAP;
            end else begin
                in_line  <= in_line + 1;
                line_beat <= line_beat + 1;
                body_acc <= head_zone ? 0
                                      : body_acc + LN_BODYQ - LN_BODY;  // fire 扣减
            end
        end else begin
            raw_tvalid <= 1'b0;                                  // body 气泡拍
            line_beat <= line_beat + 1;
            body_acc  <= body_acc + LN_BODYQ;
        end
    end
    // q32 与期望队列在写窗真写入时推进（与顶层 cam_udp_wr_en 对齐）
    // ---------------- G11n16 图案源 + 源 mux 镜像（PHASE5） ----------------
    // tb 参数缩水：GRP_TOTAL=1920（4 行）+ FRAME_PERIOD=30000（150µs/帧）加速。
    // 图案内容逐组对拍由 tb_raw10_pat_src 负责（真实几何），本 tb 只验链路完整
    // 性（FIFO 序 + 魔数结构 + 背压）。pat_mode 用 1（横向灰度）：组值含非 0/全 F
    // 字节，不会与帧魔数 M1/M2 混淆（彩条白/黑条组恰为全 F/全 0，会污染 m1/m2 计数）
    reg  [1:0]  pat_mode_tb     = 2'b01;
    reg         fifo_src_sel_tb = 1'b0;
    wire [39:0] pat_tdata_w;
    wire        pat_tvalid_w, pat_tlast_w;
    wire [2:0]  pat_tuser_w;

    raw10_pat_src #(.FRAME_PERIOD(30_000), .GRP_TOTAL(1920)) u_pat (
        .clk_i      (clk200),
        .rstn_i     (mac_rstn),
        .pat_mode_i (pat_mode_tb),
        .tdata_o    (pat_tdata_w),
        .tvalid_o   (pat_tvalid_w),
        .tlast_o    (pat_tlast_w),
        .tuser_o    (pat_tuser_w)
    );

    reg  [1:0]  sel_sy = 2'b00;
    reg         sel_eff = 1'b0;         // 帧边界锁存（与顶层 G11n16 同构）
    wire [39:0] src_tdata  = sel_eff ? pat_tdata_w  : raw_tdata;
    wire        src_tvalid = sel_eff ? pat_tvalid_w : raw_tvalid;
    wire [2:0]  src_tuser  = sel_eff ? pat_tuser_w  : raw_tuser;
    wire cam_udp_sof_evt = src_tvalid && src_tuser[0];
    wire cam_udp_eof_evt = src_tvalid && src_tuser[2];

    always @(posedge clk200 or negedge mac_rstn) begin
        if (!mac_rstn) begin
            sel_sy  <= 2'b00;
            sel_eff <= 1'b0;
        end else begin
            sel_sy <= {sel_sy[0], fifo_src_sel_tb};
            if (cam_udp_sof_evt)
                sel_eff <= sel_sy[1];
        end
    end

    // ---------------- 顶层写逻辑镜像（ws_e1_tse.v G11n15 魔数插入同步） ----------------
    reg         cam_udp_armed;
    reg         cam_udp_wr_en;
    reg         cam_udp_sof_tg;
    reg         cam_udp_eof_evt_r;
    reg  [1:0]  cam_src_sy;
    reg [39:0]  cam_udp_wr_data;   //G11n15 镜像 RTL：魔数组与数据共用 din
    wire        cam_udp_full;
    wire        cam_udp_wr_rst_n_w = 1'b1;   //G11h 镜像 RTL：连续流，FIFO 指针不复位
    //G11n15 魔数插入通路（与顶层逐行同构）
    reg  [1:0]  cam_ins_cnt;
    reg  [39:0] cam_dat_d1, cam_dat_d2, cam_dat_d3;
    reg         cam_vld_d1, cam_vld_d2, cam_vld_d3;
    wire        cam_udp_wr_gate = cam_udp_sof_evt ? (cam_src_sy[1] && !cam_udp_full)
                                                  : (cam_udp_armed && src_tvalid && !cam_udp_full);

    always @(posedge clk200 or negedge mac_rstn) begin
        if (!mac_rstn) begin
            cam_src_sy        <= 2'b00;
            cam_udp_armed     <= 1'b0;
            cam_udp_wr_en     <= 1'b0;
            cam_udp_sof_tg    <= 1'b0;
            cam_udp_eof_evt_r <= 1'b0;
            cam_ins_cnt       <= 2'd0;
            cam_dat_d1 <= 40'h0; cam_dat_d2 <= 40'h0; cam_dat_d3 <= 40'h0;
            cam_vld_d1 <= 1'b0;  cam_vld_d2 <= 1'b0;  cam_vld_d3 <= 1'b0;
        end else begin
            cam_src_sy <= {cam_src_sy[0], cam_src_en};
            cam_dat_d1 <= src_tdata;
            cam_dat_d2 <= cam_dat_d1;
            cam_dat_d3 <= cam_dat_d2;
            cam_vld_d1 <= cam_udp_wr_gate;
            cam_vld_d2 <= cam_vld_d1;
            cam_vld_d3 <= cam_vld_d2;
            if (cam_udp_sof_evt)
                cam_ins_cnt <= 2'd1;
            else if (cam_ins_cnt != 2'd0)
                cam_ins_cnt <= cam_ins_cnt + 2'd1;
            case (cam_ins_cnt)
                2'd1:    cam_udp_wr_data <= 40'hFFFFFFFFFF;   // M1：全白组
                2'd2:    cam_udp_wr_data <= 40'h0000000000;   // M2：全黑组
                default: cam_udp_wr_data <= cam_dat_d3;
            endcase
            if (cam_ins_cnt == 2'd1 || cam_ins_cnt == 2'd2)
                cam_udp_wr_en <= cam_src_sy[1] && !cam_udp_full;
            else
                cam_udp_wr_en <= cam_vld_d3;
            if (cam_udp_sof_evt)
                cam_udp_sof_tg <= ~cam_udp_sof_tg;
            if (cam_udp_sof_evt)
                cam_udp_armed <= cam_src_sy[1];
            cam_udp_eof_evt_r <= cam_udp_eof_evt;
        end
    end

    // ---------------- FIFO（G11n14 镜像 RTL：cam_fifo_bank 拼接 163,840） ----------------
    wire        cam_udp_empty;
    wire [39:0] cam_udp_dout;
    wire        cam_quad_rd_w;
    wire        cam_udp_rd_rst_n;
    wire        cam_udp_fifo_rd_rstn_w = mac_rstn & cam_udp_rd_rst_n;
    wire [17:0] bank_occrd;                 // bank 读域精确占用 → pacer
    wire [17:0] bank_wcnt, bank_rq;         // bank 总写/读计数（诊断）

    cam_fifo_bank #(.WIDTH(40), .BANK0_DEPTH(131072), .BANK1_DEPTH(32768)) u_fifo (
        .wr_clk   (clk200),
        .wr_rst_n (mac_rstn & cam_udp_wr_rst_n_w),
        .wr_en    (cam_udp_wr_en),
        .din      (cam_udp_wr_data),
        .full     (cam_udp_full),
        .rd_clk   (clk125),
        .rd_rst_n (cam_udp_fifo_rd_rstn_w),
        .rd_en    (cam_quad_rd_w),
        .dout     (cam_udp_dout),
        .empty    (cam_udp_empty),
        .occ_rd   (bank_occrd),
        .occ_wr   (),
        .dbg_wcnt (bank_wcnt),
        .dbg_rq   (bank_rq)
    );

    // 写入真发生 → 期望队列入队（与 FIFO wr_en 同语义：wr_en && !full）
    //G11h 镜像 RTL：exp 指针连续流自由跑（无每帧复位，与 FIFO 指针恒一致）
    always @(posedge clk200) begin
        if (!mac_rstn)
            exp_wr <= 0;
        else if (cam_udp_wr_en && !cam_udp_full) begin
            if (exp_wr >= 470 && exp_wr <= 492)   //G11i 分歧窗口（行0末组479/行1首组480）
                $display("[%0t] WR  idx=%0d data=%h tvalid=%b", $time, exp_wr, raw_tdata, raw_tvalid);
            exp_q[exp_wr[17:0]] <= cam_udp_wr_data;   //G11i：与 FIFO din 同信号（延迟一拍对齐）
            exp_wr <= exp_wr + 1;
        end
    end

    // ---------------- 帧末统计（G11h：板上"每帧丢 1/3"机制对拍）----------------
    // eof_evt_r 拍打印（写侧复位窗开始前 exp_wr 尚未清零）
    integer last_mism = 0, last_drain = 0, last_fullrej = 0;   //G11k：帧末快照（超时判定用）
    // PHASE6：固件序列切换后坏帧计数（切换后第 2 帧起 mism/drain 任一非零记 1）
    integer p6a_frm = -1, p6b_frm = -1, p6_bad = 0;
    always @(posedge clk200) begin
        if (bfm_run && cam_udp_armed && src_tvalid && cam_udp_full)
            full_rej <= full_rej + 1;
        if (bfm_run && cam_udp_eof_evt_r) begin
            $display("[%0t] == FRAME %0d END: wrote=%0d/518400 full_rej=%0d drain=%0d mism=%0d qidx=%0d occ=%0d gen_st=%0d",
                     $time, frm_cnt, exp_wr, full_rej, drain_cnt, mismatch,
                     cam_udp_status[30:19], cam_udp_status[17:0], pat_dbg[5:3]);
            last_mism     <= mismatch;      //G11k：清零前快照
            last_drain    <= drain_cnt;
            last_fullrej  <= full_rej;
            // PHASE6：切换后第 2 帧起（跳过混流切换帧+紧随帧）持续 mism/drain 即坏帧
            if ((p6a_frm >= 0 && frm_cnt > p6a_frm + 1) ||
                (p6b_frm >= 0 && frm_cnt > p6b_frm + 1)) begin
                if (mismatch > 0 || drain_cnt > 0) p6_bad = p6_bad + 1;
            end
            frm_cnt   <= frm_cnt + 1;
            full_rej  <= 0;
            drain_cnt <= 0;
            mismatch  <= 0;
        end
    end

    // ---------------- G11k 背压场景：MAC tready 随机空洞（块体在文件尾，----------------
    // gen_tready 声明之后） ----------------

    // ---------------- pacer ----------------
    wire        cam_pkt_req_w;
    wire        cam_pkt_go_w;
    wire [8:0]  cam_pkt_len_w;    //G11n15 动态包长 min(290,occ)
    wire [31:0] cam_udp_status;
    wire [9:0]  pat_dbg;

    cam_udp_pacer #(
        .QUADS_PER_PKT (290), .FIFO_AW(18)   //G11n14：bank 拼接 163,840 → occ 18 位（与 RTL 同步）
    ) u_pacer (
        .clk           (clk125),
        .rstn          (mac_rstn),
        .cam_en        (cam_src_en),
        .pause_i       (1'b0),
        .sof_toggle    (cam_udp_sof_tg),
        .fifo_occ      (bank_occrd),     //G11n14：bank 读域精确占用（wq_gray 废弃）
        .cam_quad_rd   (cam_quad_rd_w),
        .gen_state     (pat_dbg[5:3]),
        .cam_pkt_req   (cam_pkt_req_w),
        .cam_pkt_go    (cam_pkt_go_w),
        .pkt_len_o     (cam_pkt_len_w),  //G11n15 动态包长 → gen
        .status_o      (cam_udp_status),
        .fifo_rd_rst_n (cam_udp_rd_rst_n)
    );

    // ---------------- gen ----------------
    wire [7:0]  gen_tdata;
    wire        gen_tvalid, gen_tlast;
    reg         gen_tready = 1'b1;
    reg         pat_gen_en_r = 1'b0;    // 0x208 bit0（en，沿触发 start_pulse）
    reg         raw10_en_r  = 1'b0;     // 0x208 bit2
    reg         kill_r_tb   = 1'b0;     // 0x208 bit3
    wire [31:0] frame_num_o;

    udp_pat_gen_v2 u_gen (   //G11n16：FRAME_PERIOD 参数已删（图案帧节奏迁 200M 域）
        .clk(clk125), .rstn(mac_rstn),
        .pat_gen_en(pat_gen_en_r), .pat_gen_num(16'd0), .pat_gen_ipg(16'd12),
        .raw10_en(raw10_en_r), .pat_gen_kill(kill_r_tb),
        .cam_en(cam_src_en_gen), .cam_pkt_req(cam_pkt_req_w), .cam_pkt_go(cam_pkt_go_w),
        .cam_pkt_len(cam_pkt_len_w),   //G11n15 动态包长（授予拍锁存 grp_len_r）
        .cam_quad_i(cam_udp_dout), .cam_quad_valid(~cam_udp_empty),
        .cam_quad_rd(cam_quad_rd_w),
        .dst_mac(48'h001122334455), .src_mac(48'h665544332211),
        .src_ip(32'h0A000008), .dst_ip(32'h0A000003),
        .udp_dlen(16'd1470), .src_port(16'd10005), .dst_port(16'd10005),
        .tdata(gen_tdata), .tvalid(gen_tvalid), .tlast(gen_tlast),
        .tready(gen_tready), .frame_num_o(frame_num_o), .dbg_state_o(pat_dbg)
    );

    // ---------------- G11i debug2：帧 1 卡死探针（33.3~33.6ms 每 2µs 采样）----------------
    //G11n15：pacer 无 frame_active——act 换 occ_ready（status bit31），qidx/occ 走 status 位域
    integer probe_cnt = 0;
    always @(posedge clk125) begin
        if ($realtime >= 33_300_000 && $realtime <= 33_620_000) begin
            probe_cnt = probe_cnt + 1;
            if (probe_cnt % 250 == 0)
                $display("[%0t] PROBE rdy=%b qidx=%0d req=%b go=%b occ=%0d st=%0d dout_v=%b rd=%b exp_wr=%0d",
                         $time, cam_udp_status[31], cam_udp_status[30:19], cam_pkt_req_w, cam_pkt_go_w,
                         cam_udp_status[17:0], u_gen.state, u_gen.dout_v, cam_quad_rd_w, exp_wr);
        end
    end

    // ---------------- G11i debug：FIFO 读侧 + gen 装载对拍（仅前 3 包窗口）----------------
    reg rd_d_tb = 0;
    always @(posedge clk125) begin
        if ($realtime < 85_000) begin
            if (cam_quad_rd_w)
                $display("[%0t] RD  rq=%0d empty=%b dout_v=%b dout=%h",
                         $time, u_fifo.dbg_rq, cam_udp_empty, u_gen.dout_v, cam_udp_dout);
            rd_d_tb <= cam_quad_rd_w;
            if (rd_d_tb)
                $display("[%0t] RDd dout=%h (rq=%0d)", $time, cam_udp_dout, u_fifo.dbg_rq);
            if (u_gen.cam_arm_load)
                $display("[%0t] ARM_LOAD p<=%h state=%0d", $time, cam_udp_dout, u_gen.state);
        end
    end

    // ---------------- 监视器：收字节流，按包切，数据段 5B 解组对拍 ----------------
    integer byte_cnt   = 0;      // 包内字节计数（0..1457 / ..857）
    integer pkt_cnt    = 0;      // 已完成包计数
    integer grp_in_pkt = 0;      // 数据段已消费组数
    integer dbyte      = 0;      // 数据段字节计数（组内 0..4）
    reg [39:0] acc_q;            // 组累积
    integer nz_bytes    = 0;     // 数据段非零字节
    integer tot_dbytes  = 0;
    reg [39:0] expv;
    reg        mon_on = 1'b0;
    reg        phase4_on = 1'b0;     // 场景4：cam_r=1 + pacer 哑火（后门回归）
    integer    pkt_cnt_p3 = 0;
    integer    pkt_cnt_all = 0;      // 所有包计数（不受 mon_on 门控，phase4 判据）
    integer    m1_cnt = 0;           //G11n15：流中全白魔数组计数（每帧应恰 1）
    integer    m2_cnt = 0;           //G11n15：流中全黑魔数组计数（每帧应恰 1）
    // mon_on：仅 cam 阶段对拍（图案阶段字节流为 inc，无 RAW10 结构）

    always @(posedge clk125)
        if (gen_tvalid && gen_tready && gen_tlast)
            pkt_cnt_all = pkt_cnt_all + 1;

    always @(posedge clk125) begin
        if (gen_tvalid && gen_tready && mon_on) begin
            if (byte_cnt >= 42) begin
                // payload 段
                tot_dbytes = tot_dbytes + 1;
                if (byte_cnt >= 50) begin
                    // 数据段（跳过 8B meta）
                    nz_bytes = nz_bytes + (gen_tdata != 8'h00 ? 1 : 0);
                    acc_q = {acc_q[31:0], gen_tdata};
                    dbyte = dbyte + 1;
                    if (dbyte == 5) begin
                        dbyte = 0;
                        grp_in_pkt = grp_in_pkt + 1;
                        if (exp_rd != exp_wr) begin
                            expv = exp_q[exp_rd[17:0]];
                            exp_rd = exp_rd + 1;
                        end else begin
                            drain_cnt = drain_cnt + 1;  // FIFO 排空：gen 重复末值（=板上灰带）
                            if ($realtime < 85_000)
                                $display("[%0t] DRAIN grp got=%h (exp_rd=%0d exp_wr=%0d)",
                                         $time, acc_q, exp_rd, exp_wr);
                            expv = acc_q;              // 重复值不算数据错
                        end
                        if (acc_q !== expv) begin
                            mismatch = mismatch + 1;
                            if (mismatch <= 6)
                                $display("[%0t] pkt%0d grp%0d got=%h exp=%h MISMATCH",
                                         $time, pkt_cnt, grp_in_pkt, acc_q, expv);
                        end else if (grp_in_pkt <= 2 || (exp_rd >= 476 && exp_rd <= 492)) begin
                            $display("[%0t] pkt%0d grp%0d got=%h OK (exp_rd=%0d)",
                                     $time, pkt_cnt, grp_in_pkt, acc_q, exp_rd);
                        end
                        //G11n15 帧界魔数结构校验：每帧数据流头应为 M1(全白)+M2(全黑) 各 1 组
                        if (acc_q === 40'hFFFFFFFFFF) m1_cnt = m1_cnt + 1;
                        if (acc_q === 40'h0000000000) m2_cnt = m2_cnt + 1;
                    end
                end else begin
                    // meta 段打印（每包首 8B）
                    if (byte_cnt == 42)
                        $display("[%0t] --- pkt %0d meta/fn starts ---", $time, pkt_cnt);
                end
            end
            byte_cnt = byte_cnt + 1;
            if (gen_tlast) begin
                $display("[%0t] === pkt %0d done: dbytes=%0d nz=%0d (%0d%%) grp=%0d mism=%0d exp_wr=%0d exp_rd=%0d",
                         $time, pkt_cnt, tot_dbytes, nz_bytes,
                         (tot_dbytes>0) ? (100*nz_bytes/tot_dbytes) : 0,
                         grp_in_pkt, mismatch, exp_wr, exp_rd);
                pkt_cnt   = pkt_cnt + 1;
                byte_cnt  = 0;
                nz_bytes  = 0;
                tot_dbytes= 0;
                grp_in_pkt= 0;
                if (pkt_cnt >= 3 && !phase4_on) begin
                    $display("MAGICCHK: m1=%0d m2=%0d (每帧 M1/M2 各 1，相位：M2 后紧跟帧首组)", m1_cnt, m2_cnt);
                    $display("SIM RESULT PHASE3: PASS (mismatch=%0d, 3 pkts 对拍全过)", mismatch);
                    phase4_on = 1'b1;    // 转 phase4（phase4 initial 以 pkt_cnt>=3 触发）
                end
            end
        end
    end

    // ---------------- 激励：模拟固件真实切换序列 t(图案) → c(相机) ----------------
    // 固件 StreamStop：kill=1（0x08）→ 0x00；StreamCam：0x0 → 0x4 → 0x45 → 0x44
    integer gen_state_prev = 0;
    initial begin
        repeat (8) @(posedge clk125);
        mac_rstn = 1'b1;
        repeat (8) @(posedge clk125);

        // ---- 阶段 1：inc 图案流（固件 't'：en=1, raw10=0）----
        pat_gen_en_r = 1'b1;
        #40_000;                                 // 40µs 图案连发
        // ---- 阶段 2：StreamStop（kill 包边界停车）----
        kill_r_tb = 1'b1;
        wait (pat_dbg[5:3] == 3'h0);             // gen 回 S_IDLE
        repeat (4) @(posedge clk125);
        pat_gen_en_r = 1'b0;
        kill_r_tb   = 1'b0;
        repeat (8) @(posedge clk125);

        // ---- 阶段 3：StreamCam（0x0 → 0x4 → 0x45 → 0x44）----
        cam_src_en  = 1'b1;                      // 0x4（bit6 电平先行）
        cam_src_en_gen = 1'b1;
        raw10_en_r  = 1'b1;
        repeat (4) @(posedge clk125);
        pat_gen_en_r = 1'b1;                     // 0x45：en↑ 锁存 cam_r=1
        repeat (4) @(posedge clk125);
        pat_gen_en_r = 1'b0;                     // 0x44：撤 en 脉冲（固件同款；G11n16c
                                                 // 教训：漏此步则 en 恒 1，后续 kill 无
                                                 // start_pulse 可清 → kill_r 恒 1 拦死 gen）
        mon_on = 1'b1;
        bfm_run   = 1'b1;                        // 相机流开始（首拍即 sof）
    end

    // ---------------- 场景4：板实证组合 —— cam_r=1 + CSR=0（pacer 哑火）----------------
    // 复刻：ARP 注入 kill+写0 → [208]=0 后 gen.cam_r 残留 1（修复前 frame_tick 后门
    // 会发全 0 payload 帧；修复后 cam_r=1 抑制 frame_tick → 1 个 frame_tick 内零发包）
    initial begin
        wait (pkt_cnt_all >= 999999999);   //G11h：场景4停用（后门回归已存档），永不触发
        repeat (4) @(posedge clk125);
        phase4_on = 1'b1;
        mon_on = 1'b0;
        pkt_cnt_p3 = pkt_cnt_all;
        // ARP 注入同款：kill → 0x00（CSR 全清，cam_src_en=0 = pacer 哑火）
        kill_r_tb = 1'b1;
        wait (pat_dbg[5:3] == 3'h0);
        repeat (4) @(posedge clk125);
        pat_gen_en_r = 1'b0;
        cam_src_en   = 1'b0;                 // [208]=0：pacer 侧全哑
        raw10_en_r   = 1'b0;
        cam_src_en_gen = 1'b0;
        repeat (4) @(posedge clk125);
        kill_r_tb = 1'b0;
        repeat (8) @(posedge clk125);
        // 板实证残留态：CSR=0 但 gen.cam_en=1 且 en 0→1 重锁 cam_r=1
        //（0x45 那拍 cam_en/raw10 电平由旧锁存残留——这里直接给 gen 侧电平）
        raw10_en_r     = 1'b1;
        cam_src_en_gen = 1'b1;
        pat_gen_en_r   = 1'b1;               // start_pulse → cam_r=1, raw10_r=1, pat_en=1
        repeat (4) @(posedge clk125);
        pat_gen_en_r = 1'b0;                 // CSR 回 0（cam_src_en_pacer 保持 0）
        raw10_en_r   = 1'b0;
        cam_src_en_gen = 1'b0;
        // 等 2.5 个 frame_tick（2ms，FRAME_PERIOD 已覆写 100k=0.8ms）：
        // 修复后零发包；未修复则每个 frame_tick 发全 0 帧
        #2_000_000;
        if (pkt_cnt_all == pkt_cnt_p3)
            $display("SIM RESULT PHASE4: PASS — cam_r=1+pacer哑火下 2ms(2.5 tick) 零发包（后门已堵）");
        else
            $display("SIM RESULT PHASE4: FAIL — 后门仍在发包 pkt_cnt_all %0d→%0d", pkt_cnt_p3, pkt_cnt_all);
        $finish;
    end

    // ---------------- G11k 背压场景：MAC tready 随机空洞 ----------------
    // 复刻板上 R=378 冻结触发：MAC 背压恰落在 b4/rd_d 拍 → 装载被跳过 →
    // dout_v 卡 1 → cam_quad_rd 永久停发（修复前）。帧 0 保持无背压（PHASE3
    // 对拍基线不变），帧 1 起 40~239 拍间隔注入 1~3 拍空洞（≈1.4% 背压，
    // 低于相机速率裕量；帧 1 约 51.8 万组装载，b4 命中数千次）。
    initial begin
        wait (frm_cnt >= 1);
        //G11l/G11n14 长停顿复刻（板上本轮场景）：MAC 300µs 不收。G11n14 bank FIFO
        // 163,840 下 300µs 仅积 ~4.6K 组远不到满——full_rej 预期 0，本场景回归
        // 背压/停顿下数据通路完整性（判据 mism=0 且流量存活）。
        repeat (312500) @(posedge clk125);       // 先过帧消隐（无写入），进有效视频
        gen_tready = 1'b0;
        repeat (37500)  @(posedge clk125);       // 300µs @125M：FIFO 积压上涨但远不满
        gen_tready = 1'b1;
        forever begin
            repeat (40 + ({$random} % 200)) @(posedge clk125);
            gen_tready = 1'b0;
            repeat (1 + ({$random} % 3))  @(posedge clk125);
            gen_tready = 1'b1;
        end
    end

    // ---------------- PHASE5：G11n16 图案源链路（sel 运行中切换） ----------------
    // 3 个相机帧（帧 1/2 带 G11k 背压）后置 fifo_src_sel=1：帧边界锁存生效，
    // 相机在切帧截断（残帧由下一帧魔数自然丢弃），此后图案帧走同一条 FIFO
    // 链路。判据并入文末：MAGICCHK m1==m2==frm + G11K-BACKPRESSURE
    // last_mism/last_drain==0（快照取自最新图案帧，背压持续全程覆盖）。
    initial begin
        wait (frm_cnt >= 3);
        $display("[%0t] PHASE5: fifo_src_sel 0->1 (帧边界锁存切换)", $time);
        fifo_src_sel_tb = 1'b1;
    end

    // ---------------- PHASE6：固件真实切换序列（StreamStop kill + CamGen 重启） ----------------
    // 板上 'v'↔'c' 不是 bit7 平移（main.c ApplyMode）：先 StreamStop——[208]=0x08
    // kill=1 且 bit2/6/7 全清，等包边界 S_IDLE；再 CamGen(sel)——[208]=0x0 → 电平
    // 0x44|sel?0x80 → 100µs → +0x1 en 脉冲（start_pulse 重锁 cam_r）→ 100µs → 撤脉冲。
    // PHASE5 的 bit7 平移没有 kill+CSR=0 窗口与 en 重锁路径——G11n16 板测
    // "相机↔图案切换即冻结"的头号 tb 盲区（G11n15b 教训：盲区不守门）。
    // PHASE6a = 'v'→'c'（图案模式中 kill）；PHASE6b = 'c'→'v'（相机恢复后 kill）。
    // 判据：切换后帧流恢复（frm_cnt 推进）+ 第 2 帧起 mism/drain 双零（文末 PHASE6 判定）
    initial begin
        wait (frm_cnt >= 13);              // 3 相机帧（PHASE3/5）+ 10 图案帧
        $display("[%0t] PHASE6a: 'v'->'c' 固件序列 StreamStop+CamGen(0)", $time);
        kill_r_tb       = 1'b1;            // [208]=0x08：kill=1，bit2/6/7 全清
        raw10_en_r      = 1'b0;
        cam_src_en      = 1'b0;
        cam_src_en_gen  = 1'b0;
        fifo_src_sel_tb = 1'b0;
        wait (pat_dbg[5:3] == 3'h0);       // 包边界停车（固件轮 [24C] state）
        repeat (4) @(posedge clk125);
        kill_r_tb       = 1'b0;            // [208]=0x0
        // CamGen(0)：电平建立 → 100µs → en 脉冲 → 100µs → 撤脉冲
        cam_src_en      = 1'b1;
        cam_src_en_gen  = 1'b1;
        raw10_en_r      = 1'b1;
        #100_000;
        pat_gen_en_r    = 1'b1;            // 0x45：en↑ start_pulse 重锁 cam_r=1
        #100_000;
        pat_gen_en_r    = 1'b0;            // 0x44：撤脉冲
        p6a_frm = frm_cnt;
        $display("[%0t] PHASE6a: CamGen(0) 完成 p6a_frm=%0d（等 sel_eff 帧边界锁存 0 + 相机恢复）", $time, p6a_frm);
    end

    initial begin
        wait (p6a_frm >= 0 && frm_cnt >= p6a_frm + 3);   // 3 个相机帧恢复后
        $display("[%0t] PHASE6b: 'c'->'v' 固件序列 StreamStop+CamGen(1)", $time);
        kill_r_tb       = 1'b1;
        raw10_en_r      = 1'b0;
        cam_src_en      = 1'b0;
        cam_src_en_gen  = 1'b0;
        fifo_src_sel_tb = 1'b0;
        wait (pat_dbg[5:3] == 3'h0);
        repeat (4) @(posedge clk125);
        kill_r_tb       = 1'b0;
        cam_src_en      = 1'b1;
        cam_src_en_gen  = 1'b1;
        raw10_en_r      = 1'b1;
        fifo_src_sel_tb = 1'b1;            // CamGen(1)：bit7=1
        #100_000;
        pat_gen_en_r    = 1'b1;
        #100_000;
        pat_gen_en_r    = 1'b0;
        p6b_frm = frm_cnt;
        $display("[%0t] PHASE6b: CamGen(1) 完成 p6b_frm=%0d（图案帧应恢复）", $time, p6b_frm);
    end

    // ---------------- G11n3 occ 视角 vs 真实占用偏差监控（板上实锤对拍） ----------------
    // G11n14：真实占用 = bank_wcnt − bank_rq（同域模 2^18 模减，bank 内同源计数零偏差）；
    // 视角 = pacer status[17:0]。bank FIFO 163,840 下 300µs 停顿仅积 ~4.6K 组不会满，
    // full_tot 预期 0——监控保留作 occ 通路一致性回归（视角 vs 真实差应 ≤ 同步滞后）。
    wire [17:0] tb_real_occ = u_fifo.dbg_wcnt - u_fifo.dbg_rq;
    integer occ_diff_max = 0, occ_diff_cur = 0;
    integer full_tot = 0, full_lowview = 0;
    always @(posedge clk125) if (mac_rstn && bfm_run) begin
        occ_diff_cur = (tb_real_occ > cam_udp_status[17:0]) ?
                       (tb_real_occ - cam_udp_status[17:0]) :
                       (cam_udp_status[17:0] - tb_real_occ);
        if (occ_diff_cur > occ_diff_max) occ_diff_max = occ_diff_cur;
        if (cam_udp_full) begin
            full_tot = full_tot + 1;
            if (cam_udp_status[17:0] < 2048) full_lowview = full_lowview + 1;
        end
    end

    initial begin
        #220_000_000;           // G11n16b：3 相机帧 + PHASE5 图案帧 + PHASE6 双向固件切换（3 相机帧恢复）
        $display("OCCCHK G11n3: occ_diff_max=%0d full_tot=%0d full_lowview=%0d (view<300 while truly full)",
                 occ_diff_max, full_tot, full_lowview);
        $display("SIM TIMEOUT: pkt_cnt=%0d exp_wr=%0d exp_rd=%0d status=%h",
                 pkt_cnt, exp_wr, exp_rd, cam_udp_status);
        $display("MAGICCHK: m1=%0d m2=%0d frm=%0d (应 m1==m2≈frm_cnt，帧界魔数每帧各 1；含图案帧)",
                 m1_cnt, m2_cnt, frm_cnt);
        $display("PHASE5 CHK: sel_eff=%b pat_frames_included (帧边界切换后链路完整性并入 G11K 判据)",
                 sel_eff);
        // PHASE6 判定：双向固件序列切换后帧流恢复 + 第 2 帧起无坏帧
        if (p6a_frm >= 0 && p6b_frm >= 0 && p6_bad == 0 && frm_cnt >= p6b_frm + 5)
            $display("SIM RESULT PHASE6: PASS (v->c p6a_frm=%0d, c->v p6b_frm=%0d, frm=%0d, bad=%0d — 切换后双向帧流恢复)",
                     p6a_frm, p6b_frm, frm_cnt, p6_bad);
        else
            $display("SIM RESULT PHASE6: FAIL (p6a_frm=%0d p6b_frm=%0d frm=%0d bad=%0d — 切换后停流/坏帧)",
                     p6a_frm, p6b_frm, frm_cnt, p6_bad);
        //G11k 背压判定：帧 1 全程带 tready 空洞，错位/排空/冻结任一非零即 FAIL
        if (frm_cnt >= 2 && last_mism == 0 && last_drain == 0 && pkt_cnt_all > 0)
            $display("SIM RESULT G11K-BACKPRESSURE: PASS (frm=%0d last_mism=%0d last_drain=%0d last_fullrej=%0d)",
                     frm_cnt, last_mism, last_drain, last_fullrej);
        else
            $display("SIM RESULT G11K-BACKPRESSURE: FAIL (frm=%0d last_mism=%0d last_drain=%0d pkt_cnt_all=%0d)",
                     frm_cnt, last_mism, last_drain, pkt_cnt_all);
        $finish;
    end

    // pacer occ 采样打印（诊断；G11n14 位域：bit31=occ_ready bits30:19=qidx bit18=active）
    always @(posedge clk125)
        if ($time > 1000 && $time % 200000 == 0)
            $display("[%0t] pacer: occ=%0d qidx=%0d act=%b | fifo empty=%b wcnt=%0d rq=%0d wr_en=%b req=%b gen_state=%0d",
                     $time, cam_udp_status[17:0], cam_udp_status[30:19],
                     cam_udp_status[18],
                     cam_udp_empty, u_fifo.dbg_wcnt, u_fifo.dbg_rq,
                     cam_udp_wr_en, cam_pkt_req_w, pat_dbg[5:3]);
    // ---------------- PHASE6 死区探针（G11n16c：'v'->'c' 重启后发送链路死 81ms 取证） ----------------
    // 仿真实锤：PHASE6a 重启后 FRAME13-15 三整帧 qidx 卡 897、occ 卡 149797、
    // full_rej=518400、gen_st=0、零发包——冻结=板上现象。探针打印 gen 侧
    // {state,cam_r,kill_r,start_pulse,dout_v} + pacer 侧 {req,occ,ready} 全组合，
    // 并与 PHASE6b（'c'->'v'，同样序列却恢复）对照定位卡死信号。
    integer p6_probe_cnt = 0;
    reg [2:0] p6_st_d = 3'd0;
    always @(posedge clk125) begin
        p6_st_d <= pat_dbg[5:3];
        if ($realtime >= 101_640_000 && $realtime <= 103_000_000) begin
            if (pat_dbg[5:3] !== p6_st_d)
                $display("[%0t] P6-TRANS st %0d->%0d (cam_r=%b kill=%b req=%b dv=%b)",
                         $time, p6_st_d, pat_dbg[5:3], u_gen.cam_r, u_gen.kill_r,
                         cam_pkt_req_w, u_gen.dout_v);
            p6_probe_cnt = p6_probe_cnt + 1;
            if (p6_probe_cnt % 500 == 0)
                $display("[%0t] P6 st=%0d cam_r=%b kill=%b pul=%b genCamEn=%b raw10=%b req=%b go=%b occ=%0d rdy=%b emp=%b dv=%b rd=%b qidx=%0d",
                         $time, pat_dbg[5:3], u_gen.cam_r, u_gen.kill_r,
                         (u_gen.pat_gen_en && !u_gen.en_d1), cam_src_en_gen, raw10_en_r,
                         cam_pkt_req_w, cam_pkt_go_w,
                         cam_udp_status[17:0], cam_udp_status[31], cam_udp_empty,
                         u_gen.dout_v, cam_quad_rd_w, cam_udp_status[30:19]);
        end
    end

    // ---------------- G11n16c 发散定位（第二轮：真整数计数，无 mod 陷阱） ----------------
    // 第一轮教训：WDIV 在 mod-163840 回绕处误报（diff=163840≡0）；RDIV 的 18 位
    // 模运算把正常超前 1 组算成 32770。写侧条件与 FIFO 逐位相同（exp_wr≡wcnt
    // 恒成立，免检）；读侧改用 tb 侧真整数 rq 计数与 exp_rd 直接相减。
    // 常态超前 ≤2（S_IDLE 授予读 + 流水）；新最大超前 >2 即打印（锁定切换边界丢组时刻）。
    integer p6_rq_cnt = 0;
    integer p6_ahead_max = 0;
    always @(posedge clk125) begin
        if (u_fifo.rd_accept) p6_rq_cnt = p6_rq_cnt + 1;
        if (p6_rq_cnt - exp_rd > p6_ahead_max) begin
            p6_ahead_max = p6_rq_cnt - exp_rd;
            if (p6_ahead_max > 2)
                $display("[%0t] AHEAD_NEW_MAX=%0d (rq=%0d exp_rd=%0d st=%0d dv=%b rd=%b kill=%b req=%b)",
                         $time, p6_ahead_max, p6_rq_cnt, exp_rd, u_gen.state, u_gen.dout_v,
                         cam_quad_rd_w, u_gen.kill_r, cam_pkt_req_w);
        end
    end

endmodule
