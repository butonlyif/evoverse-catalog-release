// ============================================================================
// tb_phase4_ddrm.sv — Phase 4 + ddr_ctrl_model 实模型 TB
//   以 tb_phase4.sv 为基线，把两处内联 AXI 从机 stub（writer 侧 awready/
//   wready/b 应答器 + reader 侧 arready/rdata 应答器 + assoc mem）整体替换为
//   ddr_ctrl_model 的 ddr_axi_model_top：
//     - CDC_ENABLE=1：ACLK_0=clk200（=ctrl_clk），ACLK_1=clk148（真异步，
//       1.347:1 非整比）——对齐板级 target0@200M / target1@148.5M；
//     - 容量改板级口径：MEM_DENSITY_GBIT=2 + DATA_WIDTH=16 → 256MiB；
//       FRAME_B 相应改 0x0200_0000（板级 bank 布局）；
//     - CFG 握手（RESET→START→DONE）先于路径复位释放；
//     - writer 侧带照实连接（awcache=0000 → 模型 PHY_ISSUE 早返 B，与
//       板级契约一致；writer 在 D_POSTWR 采样保持型 bvalid，兼容早返）。
//   判据 = tb_phase4 全量 P1-P4/P4C + 新增 DDRM sticky CTRL_ERR 检查。
//
// 缩帧：VACT=90、FRAME_SLOTS=100（与 tb_full_chain 同款）。
// 判据：
//   P1 disp_timing 完成帧（frame_num 增长，df>0）
//   P2 TX HACT 突发 960 拍连续（显示链活）
//   P3 诊断等价量：rd 回放流每帧 sol/tlast=90/90（tb 本地计数）；dms_sol
//      增长；frm（vsync 沿）增长；TX 有 valid 拍
//   P4（v4.10 新增）内容校验：源侧逐拍注入指纹 {f,l,b,16'hA5C3}，reader
//      回放流输出侧逐拍零扩展比对（{24'h0, 指纹}）——覆盖 writer 512b
//      打包 -> AXI -> DDR 模型 -> reader 切片全链比特一致性（40b 时代
//      仿真盲区：板级竖线头号嫌疑链）。
// ============================================================================

`timescale 1ns / 1ps

module tb_phase4_ddrm;

    localparam real  HALF200 = 2.5;
    localparam real  HALF148 = 3.367;
    localparam int   VACT    = 90;
    localparam int   BEATS   = 960;
    localparam int   WORDS   = 120;   // 7680B / 64B（v4.10 64b 载体）
    localparam int   SLOTS   = 100;
    localparam [32:0] FRAME_A = 33'h0_0000_0000;
    localparam [32:0] FRAME_B = 33'h0_0200_0000;   // 板级 bank 布局（256MiB 内）

    reg clk200 = 0, clk148 = 0;
    reg rstn200 = 0, rstn148 = 0;
    always #(HALF200) clk200 = ~clk200;
    always #(HALF148) clk148 = ~clk148;
    integer fail_cnt = 0;

    // ---------------- 源（in_* 格式：vs/hs 电平 + 40b 拍）----------------
    // 几何对齐板级 IMX415 窗口：行发 966 拍（3864px，窗口裁 960），帧发
    // 11 跳行 + 90 有效行；DT=0x2B（RAW10，raw_2_axi4st 门控）。
    reg  [39:0] in_data;
    reg         in_valid, in_vs, in_hs;
    reg  [5:0]  in_dtype = 6'h2B;
    integer     f_cnt, l_cnt, b_cnt;
    localparam int LINE_TOTAL_BEATS = 966;   // 3864/4
    localparam int SKIP_LINES       = 11;
    reg  [1:0]  vs_gap = 0;              // 帧间 vs 空拍（vs 不得与首行 hs 同拍
                                         // ——raw_2_axi4st 的 vs 清 hs_seen，
                                         // 同拍会使首行不占行号 → 帧少一行）
    // ---- 慢源实验（相机病理复现）：行间空拍把源线率压到显示消费率的
    //      2/3（板级相机态 reader 供给节奏）。行周期 = (966+gap)×5ns；
    //      gap=1256 → 11.11ms/行 ≈ 1.5×显示行(1100×6.734ns)。
    integer     src_gap_beats = 0;
    integer     src_gap_cnt = 0;

    always @(posedge clk200 or negedge rstn200) begin
        if (!rstn200) begin
            in_valid <= 0; in_vs <= 0; in_hs <= 0; in_data <= 0;
            f_cnt = 0; l_cnt = 0; b_cnt = 0; vs_gap = 0; src_gap_cnt = 0;
        end else begin
            in_valid <= 1'b0;
            in_vs    <= 1'b0;
            in_hs    <= 1'b0;
            if (vs_gap != 0) begin
                in_vs  <= (vs_gap == 2'd2);   // 空拍期 vs 单拍上升沿
                vs_gap = vs_gap - 1;
            end else if (src_gap_cnt != 0) begin
                src_gap_cnt <= src_gap_cnt - 1;  // 行间空拍（慢源）
            end else if (f_cnt < 64) begin
                if (b_cnt == 0) in_hs <= 1'b1;                 // 行同步电平
                // 帧无关指纹（v4.10b）：内容仅 (l,b) 函数——每帧相同，使
                // P4C 内容校验无需帧号对齐（ref[bank] 新旧帧等价）。帧对齐
                // 正确性由既有 P1-P3 判据（df/late/drop/rpt）覆盖。
                in_data  <= {4'h0, l_cnt[7:0], b_cnt[9:0], 16'hA5C3};
                in_valid <= 1'b1;
                if (b_cnt == LINE_TOTAL_BEATS-1) begin
                    b_cnt <= 0;
                    src_gap_cnt <= src_gap_beats;
                    if (l_cnt == SKIP_LINES + VACT-1) begin
                        l_cnt <= 0; f_cnt <= f_cnt + 1;
                        vs_gap = 2;               // 帧尾：进 vs 空拍
                    end else
                        l_cnt <= l_cnt + 1;
                end else
                    b_cnt <= b_cnt + 1;
            end
        end
    end

    // ---------------- raw_2_axi4st（源域协议清洗）+ frame_writer ----------
    wire [39:0] raw_tdata;
    wire        raw_tvalid, raw_tlast;
    wire [2:0]  raw_tuser;                  // {eof, sol, sof}

    raw_2_axi4st #(
        .DTYPE           (6'h2B),
        .LINE_TOTAL_PIX  (20'd3864),
        .LEAD_PIX        (20'd6),  .TRAIL_PIX(20'd18),
        .LINE_SKIP_FIRST (20'd11),
        .LINES           (16'd90)
    ) u_raw (
        .aclk         (clk200),
        .aresetn      (rstn200),
        .in_data      (in_data), .in_valid(in_valid),
        .in_vs        (in_vs),   .in_hs(in_hs), .in_dtype(in_dtype),
        .m_axis_tdata (raw_tdata), .m_axis_tvalid(raw_tvalid),
        .m_axis_tlast (raw_tlast), .m_axis_tuser(raw_tuser)
    );

    wire [63:0]  cap_tdata  = {24'h0, raw_tdata};   // v4.10 64b 载体（零扩展）
    wire         cap_tvalid = raw_tvalid;
    wire         cap_tlast  = raw_tlast;
    wire [2:0]   cap_tuser  = raw_tuser;

    wire [32:0]  awaddr;
    wire [7:0]   awlen;
    wire         awvalid, wlast, wvalid;
    wire [511:0] wdata;
    wire         awready, wready, bvalid;   // 模型 target0 驱动
    wire         wr_par, wr_frame_done;
    wire         fw_bready;              // writer 自管理 B 应答 ready
    integer      done_pulses = 0;        // wr_frame_done 脉冲计数（诊断）
    always @(posedge clk200) if (wr_frame_done) done_pulses = done_pulses + 1;
    integer aw_cnt = 0, w_cnt = 0, bx_cnt = 0;
    integer cap_sof = 0, cap_eof = 0, cap_sol = 0;
    always @(posedge clk200) begin
        if (awvalid && awready) aw_cnt = aw_cnt + 1;
        if (wvalid && wready)   w_cnt = w_cnt + 1;
        if (bvalid && fw_bready) bx_cnt = bx_cnt + 1;
        if (cap_tvalid && cap_tuser[0]) cap_sof = cap_sof + 1;
        if (cap_tvalid && cap_tuser[2]) cap_eof = cap_eof + 1;
        if (cap_tvalid && cap_tuser[1]) cap_sol = cap_sol + 1;
    end

    // ---- DDR 模型侧带连线（writer 输出照实引出；writer 内部恒驱：
    //      awsize=6/awburst=INCR/awcache=0/awqos=1/wstrb=全1，其余 0）----
    wire [2:0]   awsize, arsize;
    wire [1:0]   awburst, arburst;
    wire [3:0]   awcache, awqos, arqos;
    wire         awlock, awcobuf, awapcmd, awallstrb;
    wire         arlock, arapcmd;
    wire [63:0]  wstrb;
    wire [5:0]   bid1, rid1;
    wire [1:0]   bresp1, rresp1;
    wire         rvalid1, rlast1;
    wire [511:0] rdata1;
    wire         arready148;          // 模型 target1 ARREADY（clk148 域）
    wire         cfg_done, ctrl_init_done, ctrl_ready, ctrl_err, ctrl_busy;
    wire [32:0]  dbg_fields, dbg_fields_addr;
    reg          cfg_reset = 1'b1, cfg_start = 1'b0;
    // B 时机口径（Phase 5 板级相关性改版后修正）：writer 恒驱 awcache=0000，
    // 其 B 契约要求"数据完成后返 B"（D_POSTWR 现场等最后一笔 B，b_cnt==1
    // 判行完成；中途的 B 会被 D_WADDR/D_PREWR/D_WRITE 的采样路径错位消费）。
    // 当前模型 cmd_is_early：cache[0]=1 → 早返（0001/0011/0111/1111 同形），
    // bit0=0 → DATA_DONE 晚返（0000/0010/0100/1110 同形，WA≈WL+55-99）。
    // 旧版模型的 1111→晚返翻译已失效（1111 现为早返 → B 双双落在数据期
    // 被 D_WRITE 消费 → D_POSTWR 等 B#3 死锁，writer 卡 1 行/38ms 实测）。
    // 照实直连 writer 的 0000（与板级 c3m 晚返同形）。
    wire [3:0]   awcache_m = 4'b0000;

    frame_writer #(.VACT(VACT[15:0]), .FRAME_A(FRAME_A), .FRAME_B(FRAME_B)) u_fw (
        .aclk(clk200), .rstn(rstn200), .flush_i(1'b0),
        .s_axis_tdata(cap_tdata), .s_axis_tvalid(cap_tvalid),
        .s_axis_tlast(cap_tlast), .s_axis_tuser(cap_tuser),
        .awaddr(awaddr), .awlen(awlen), .awvalid(awvalid), .awready(awready),
        .awsize(awsize), .awburst(awburst), .awcache(awcache), .awlock(awlock),
        .awcobuf(awcobuf), .awapcmd(awapcmd), .awallstrb(awallstrb),
        .awqos(awqos),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid),
        .wready(wready),
        .bid(bid1), .bvalid(bvalid), .bready(fw_bready),
        .line_cnt(), .frame_cnt(), .pad_cnt(), .ovf_cnt(), .dbg_state(),
        .wr_par(wr_par), .wr_line(), .wr_frame_done_o(wr_frame_done),
        .wr_perf(), .fw_dbg2()
    );

    // （tb_phase4 的 writer 侧内联从机 stub 已删除——由 u_ddr target0 承担）

    // ---------------- 帧握手 toggle 跨域（板级同款）----------------
    reg tog200 = 0;
    always @(posedge clk200 or negedge rstn200)
        if (!rstn200) tog200 <= 0;
        else if (wr_frame_done) tog200 <= ~tog200;
    reg [2:0] tog148 = 0;
    reg [1:0] par148 = 0;
    always @(posedge clk148 or negedge rstn148) begin
        if (!rstn148) begin tog148 <= 0; par148 <= 0; end
        else begin
            tog148 <= {tog148[1:0], tog200};
            par148 <= {par148[0], wr_par};
        end
    end
    wire fw_done_148 = tog148[1] ^ tog148[2];
    wire fw_par_148  = par148[1];

    wire rd_rstn_148 = rstn148;   // 简化：仿真直接给 released 复位

    // ---------------- frame_reader（148.5M，line_tick = disp 同源）--------
    wire [63:0] rd_tdata;
    wire        rd_tvalid, rd_tlast;
    wire [2:0]  rd_tuser;
    wire        disp_line_tick;
    wire        disp_line_room;
    wire        disp_sof;               // v4.9：显示帧界（reader 授权锚）
    wire        disp_stall;             // v4.9：显示断粮（reader 救援授权）
    wire [32:0] araddr;
    wire [7:0]  arlen;
    wire        arvalid, rready, rvalid, rlast;
    wire [511:0] rdata;
    // （arready148/rdata1/rlast1/rvalid1/rresp1/rid1 及侧带已在上方声明，
    //   全部由 u_ddr target1 驱动）

    // 阶段4：读侧互联（P4C 判据：回放流经 u_rd_arb 不破）。
    // S1=reader（侧带透传，reader 恒 0）/ S0=cam1 恒 idle / M=u_ddr
    // target1，全口 clk148（ACLK_1）。
    wire        rd_arvalid, rd_arready, rd_arlock;
    wire [32:0] rd_araddr;
    wire [7:0]  rd_arlen;
    wire [2:0]  rd_arsize;
    wire [1:0]  rd_arburst;
    wire [5:0]  rd_arid;
    wire [3:0]  rd_arqos;
    wire        rd_rvalid, rd_rready, rd_rlast;
    wire [511:0] rd_rdata;
    wire [1:0]  rd_rresp;
    wire [5:0]  rd_rid;
    wire        m_arvalid, m_arready, m_arlock;
    wire [32:0] m_araddr;
    wire [7:0]  m_arlen;
    wire [2:0]  m_arsize;
    wire [1:0]  m_arburst;
    wire [5:0]  m_arid;
    wire [3:0]  m_arqos;
    wire        m_rvalid, m_rready, m_rlast;
    wire [511:0] m_rdata;
    wire [1:0]  m_rresp;
    wire [5:0]  m_rid;
    wire [68:0] rd_arb_dbg;

    axi_rd_arb u_rd_arb (
        .clk(clk148), .rstn(rd_rstn_148),
        // S1 = cam0 reader
        .s1_arvalid(rd_arvalid), .s1_arready(rd_arready),
        .s1_araddr (rd_araddr),  .s1_arlen (rd_arlen),
        .s1_arsize (rd_arsize),  .s1_arburst(rd_arburst),
        .s1_arid   (rd_arid),    .s1_arqos (rd_arqos),
        .s1_arcache(4'h0),       .s1_arlock(rd_arlock),
        .s1_rvalid (rd_rvalid),  .s1_rready(rd_rready),
        .s1_rdata  (rd_rdata),
        .s1_rresp  (rd_rresp),   .s1_rlast (rd_rlast),
        .s1_rid    (rd_rid),
        // S0 = cam1（恒 idle）
        .s0_arvalid(1'b0), .s0_arready(),
        .s0_araddr (33'h0), .s0_arlen (8'h0),
        .s0_arsize (3'h0),  .s0_arburst(2'h0),
        .s0_arid   (6'h0),  .s0_arqos (4'h0),
        .s0_arcache(4'h0),  .s0_arlock(1'b0),
        .s0_rvalid (), .s0_rready(1'b1),
        .s0_rdata  (),
        .s0_rresp  (), .s0_rlast (), .s0_rid (),
        // M = u_ddr target1（148.5M，Phase 0 已证真异步端口钟）
        .m_arvalid (m_arvalid), .m_arready(m_arready),
        .m_araddr  (m_araddr),  .m_arlen  (m_arlen),
        .m_arsize  (m_arsize),  .m_arburst(m_arburst),
        .m_arid    (m_arid),    .m_arqos  (m_arqos),
        .m_arcache(),          .m_arlock (m_arlock),
        .m_rvalid  (m_rvalid), .m_rready (m_rready),
        .m_rdata   (m_rdata),
        .m_rresp   (m_rresp),  .m_rlast  (m_rlast),
        .m_rid     (m_rid),
        .dbg       (rd_arb_dbg)
    );

    frame_reader #(
        .VACT(VACT[15:0]), .FRAME_TICKS(SLOTS[15:0]),
        .FRAME_A(FRAME_A), .FRAME_B(FRAME_B),
        // v4.10c3h 锚窗口对齐（与板级 VSP+VBP-余量 同构）：tb VSP+VBP=6
        // （VSP 2 + VBP 4），余量 2（DDR 首字 + demosaic 3 行窗冲洗在 tb
        // 缩帧下的等比例折减），发射起点右移对齐显示 Va 开拉点。
        .ANCHOR_WAIT(12'd4)
    ) u_rd (
        .aclk(clk148), .rstn(rd_rstn_148), .flush_i(1'b0), .enable(1'b1),
        .flush_done_o(),
        .line_tick(disp_line_tick),
        .line_room_i(disp_line_room),
        .disp_sof_i(disp_sof),
        .disp_stall_i(disp_stall),
        .wr_frame_done(fw_done_148), .wr_frame_par(fw_par_148),
        .m_axis_tdata(rd_tdata), .m_axis_tvalid(rd_tvalid),
        .m_axis_tlast(rd_tlast), .m_axis_tuser(rd_tuser),
        .araddr(rd_araddr), .arlen(rd_arlen), .arvalid(rd_arvalid), .arready(rd_arready),
        .arid(rd_arid), .arsize(rd_arsize), .arburst(rd_arburst), .arlock(rd_arlock),
        .arapcmd(), .arqos(rd_arqos),
        .rdata(rd_rdata), .rlast(rd_rlast), .rvalid(rd_rvalid), .rready(rd_rready),
        .rresp(rd_rresp), .rid(rd_rid),
        .rd_frame_cnt(), .rd_line(), .rd_state(), .rd_err(), .dbg_fr_cnt()
    );

    // ---------------- ddr_ctrl_model 实模型（替换两处内联 stub）----------
    // CDC_ENABLE=1：port0 在 ACLK_0=clk200（=ctrl_clk），port1 在 ACLK_1=
    // clk148（真异步 1.347:1）。容量=板级 2Gbit x16 = 256MiB。
    // ENABLE_CTRL_STATUS=1 打开 sticky CTRL_ERR 观测。
    ddr_axi_model_top #(
        .CDC_ENABLE         (1'b1),
        .MEM_DENSITY_GBIT   (2),
        .DATA_WIDTH         (16),
        .ENABLE_CTRL_STATUS (1'b1)
    ) u_ddr (
        .ctrl_clk      (clk200),
        // ---- target0：frame_writer（200M 域）----
        .ACLK_0        (clk200), .ARSTN_0    (rstn200),
        .AWADDR_0      (awaddr), .AWBURST_0 (awburst), .AWID_0  (6'h0),
        .AWLEN_0       (awlen),  .AWREADY_0 (awready), .AWSIZE_0(awsize),
        .AWVALID_0     (awvalid),.AWLOCK_0  (awlock),  .AWAPCMD_0(awapcmd),
        .AWQOS_0       (awqos),  .AWCACHE_0 (awcache_m), .AWALLSTRB_0(awallstrb),
        .AWCOBUF_0     (awcobuf),
        .WDATA_0       (wdata),  .WLAST_0   (wlast),   .WREADY_0(wready),
        .WSTRB_0       (wstrb),  .WVALID_0  (wvalid),
        .BID_0         (bid1),   .BREADY_0  (fw_bready), .BRESP_0(bresp1),
        .BVALID_0      (bvalid),
        .ARADDR_0      (33'h0),  .ARBURST_0 (2'h0),    .ARID_0  (6'h0),
        .ARLEN_0       (8'h0),   .ARREADY_0 (),        .ARSIZE_0(3'h0),
        .ARVALID_0     (1'b0),   .ARLOCK_0  (1'b0),    .ARAPCMD_0(1'b0),
        .ARQOS_0       (4'h0),
        .RDATA_0       (),       .RID_0     (),        .RLAST_0 (),
        .RREADY_0      (1'b0),   .RRESP_0   (),        .RVALID_0(),
        // ---- target1：读侧互联 M 口（148.5M 域，Phase 0 已证真异步端口钟）
        .ACLK_1        (clk148), .ARSTN_1   (rd_rstn_148),
        .AWADDR_1      (33'h0),  .AWBURST_1 (2'h0),    .AWID_1  (6'h0),
        .AWLEN_1       (8'h0),   .AWREADY_1 (),        .AWSIZE_1(3'h0),
        .AWVALID_1     (1'b0),   .AWLOCK_1  (1'b0),    .AWAPCMD_1(1'b0),
        .AWQOS_1       (4'h0),   .AWCACHE_1 (4'h0),    .AWALLSTRB_1(1'b0),
        .AWCOBUF_1     (1'b0),
        .WDATA_1       (512'h0), .WLAST_1   (1'b0),    .WREADY_1(),
        .WSTRB_1       (64'h0),  .WVALID_1  (1'b0),
        .BID_1         (),       .BREADY_1  (1'b0),    .BRESP_1 (), .BVALID_1(),
        .ARADDR_1      (m_araddr), .ARBURST_1 (m_arburst), .ARID_1 (m_arid),
        .ARLEN_1       (m_arlen),  .ARREADY_1 (m_arready), .ARSIZE_1(m_arsize),
        .ARVALID_1     (m_arvalid),.ARLOCK_1  (m_arlock), .ARAPCMD_1(1'b0),
        .ARQOS_1       (m_arqos),
        .RDATA_1       (m_rdata), .RID_1     (m_rid),   .RLAST_1 (m_rlast),
        .RREADY_1      (m_rready),.RRESP_1   (m_rresp), .RVALID_1(m_rvalid),
        // ---- CFG / 状态 ----
        .CFG_RESET     (cfg_reset), .CFG_START(cfg_start), .CFG_SEL(1'b0),
        .CFG_DONE      (cfg_done),
        .CTRL_INIT_DONE(ctrl_init_done), .CTRL_READY(ctrl_ready),
        .CTRL_ERR      (ctrl_err),  .CTRL_BUSY(ctrl_busy),
        .DBG_FIELDS    (dbg_fields), .DBG_FIELDS_ADDR(dbg_fields_addr)
    );

    // ---------------- 显示链直例化（v4.10c3m 扁平化，板级同构）----------
    // 回放流直通（reader 已换域 clk148，无 CDC）-> demosaic -> wb ->
    // rgb2yuv -> tx_line_buf -> disp_timing。直注源/mux/探针为板级诊断
    // 配置，tb 不复制（源格式不同其读数本就是噪声）。
    wire [39:0] dms_in_tdata = rd_tdata[39:0];   // demosaic 只吃 RAW10 段
    wire [2:0]  dms_in_tuser = rd_tuser;
    wire        dms_in_tlast = rd_tlast;
    wire        cdc_valid    = rd_tvalid;      // v3 遗留名 = rd_tvalid 别名

    wire [119:0] dms_tdata;
    wire         dms_tvalid, dms_tlast;
    wire [2:0]   dms_tuser;
    wire [95:0]  wb_tdata;
    wire         wb_tvalid, wb_tlast;
    wire [2:0]   wb_tuser;
    wire [63:0]  yuv_tdata;
    wire         yuv_tvalid, yuv_tlast;
    wire [2:0]   yuv_tuser;

    demosaic #(
        .GW   (16'd960),
        .LINES(16'd90)
    ) u_demosaic (
        .aclk         (clk148), .aresetn(rstn148),
        .s_axis_tdata (dms_in_tdata), .s_axis_tvalid(cdc_valid),
        .s_axis_tlast (dms_in_tlast), .s_axis_tuser(dms_in_tuser),
        .bayer_phase  (2'd0), .adaptive(1'b1),
        .m_axis_tdata (dms_tdata), .m_axis_tvalid(dms_tvalid),
        .m_axis_tlast (dms_tlast), .m_axis_tuser(dms_tuser),
        .dbg_reswin_cnt ()
    );

    wb_axis u_wb (
        .aclk         (clk148), .aresetn(rstn148),
        .s_axis_tdata (dms_tdata), .s_axis_tvalid(dms_tvalid),
        .s_axis_tlast (dms_tlast), .s_axis_tuser(dms_tuser),
        .wb_r(8'd200), .wb_g(8'd235), .wb_b(8'd180),
        .m_axis_tdata (wb_tdata), .m_axis_tvalid(wb_tvalid),
        .m_axis_tlast (wb_tlast), .m_axis_tuser(wb_tuser)
    );

    rgb2yuv_axis u_rgb2yuv (
        .aclk         (clk148), .aresetn(rstn148),
        .s_axis_tdata (wb_tdata), .s_axis_tvalid(wb_tvalid),
        .s_axis_tlast (wb_tlast), .s_axis_tuser(wb_tuser),
        .blk_clip     (1'b0),
        .m_axis_tdata (yuv_tdata), .m_axis_tvalid(yuv_tvalid),
        .m_axis_tlast (yuv_tlast), .m_axis_tuser(yuv_tuser)
    );

    wire        dt_rd_en, dt_valid;
    wire [63:0] dt_rdata;
    wire [15:0] dt_level;

    tx_line_buf #(.DEPTH_WORDS(2048)) u_tlb (
        .clk          (clk148), .rst_n(rstn148),
        .s_axis_tdata (yuv_tdata),
        .s_axis_tvalid(yuv_tvalid & rstn148),   // 冷启动锚定契约同板级
        .rd_en        (dt_rd_en),
        .rd_data      (dt_rdata), .rd_valid(dt_valid),
        .level_o      (dt_level),
        .dbg_buf_cnt_o()
    );

    wire        hsync, vsync, pdv, frame_open;
    wire [5:0]  datatype;
    wire [63:0] pixel_data;
    wire [15:0] haddr, line_num, frame_num;
    wire [31:0] dbg4;                       // disp_timing {late, under}

    disp_timing #(
        .LINE_CLKS  (1100),
        .FRAME_SLOTS(SLOTS[15:0]),
        .LINE_WORDS (16'd960),              // HACT/PPC = 3840/4
        .LINE_BUF_WORDS(16'd600),           // 960 px x 40b / 64b（1 行整）
        .VSP_L      (16'd2),  .VBP_L(16'd4),
        .VACT_L     (16'd90), .VFP_L(16'd1),
        .PAD_L      (16'd3),                // SLOTS - 2 - 4 - 90 - 1
        .HACT_PX    (16'd3840),
        .DATA_TYPE  (6'h1E)
    ) u_dtg (
        .clk          (clk148), .rst_n(rstn148),
        .buf_rd_en    (dt_rd_en),
        .buf_rdata    (dt_rdata), .buf_valid(dt_valid),
        .buf_level    (dt_level),
        .hsync        (hsync), .vsync(vsync), .datatype(datatype),
        .pixel_data   (pixel_data), .pixel_data_valid(pdv),
        .haddr        (haddr), .line_num(line_num), .frame_num(frame_num),
        .frame_open   (frame_open),
        .line_tick_o  (disp_line_tick),
        .dbg_dtg_cnt_o(dbg4)
    );

    // 行水位节流/帧界/断粮（与 top_cam 内联网表同式）
    assign disp_line_room = (dt_level <= 16'd2048 - 16'd960);
    assign disp_sof       = vsync;
    assign disp_stall     = (dt_level < 16'd600);

    // P3 等价量（tb 本地计数，替代 top_cam DIAG4/5 读数）
    integer dms_sol = 0, yuv_v = 0, frm_cnt = 0;
    reg     frm_vs_q = 1'b1;
    always @(posedge clk148) begin
        if (rstn148) begin
            if (dms_tvalid && dms_tuser[1]) dms_sol = dms_sol + 1;
            if (yuv_tvalid)                 yuv_v  = yuv_v + 1;
            frm_vs_q <= vsync;
            if (vsync && !frm_vs_q) frm_cnt = frm_cnt + 1;
        end
    end

    // ---------------- 内容校验（v4.10 新增，P4）--------------------------
    // 双缓冲参考捕获：writer 输入流（cap，200M）按帧奇偶（帧号%2 = DDR
    // bank 奇偶）交替捕获每行每拍 64b 内容；reader 回放流（rd，148M）在
    // sof 时探 u_rd.par_r（reader 授权锁存的回放帧 bank 奇偶），逐拍比对
    // ref[sel][line][beat] 全 64b（含高 24b 扩展恒 0）。覆盖 writer 512b
    // 打包 -> AXI -> DDR 模型 -> reader 切片全链比特一致性。
    // 纪律（防假阳性）：
    //   1) 帧 k 全拍（含 sof 拍）以自增前的 cap_sof_cnt 寻址 -> ref[k%2]，
    //      与 writer bank 奇偶（帧 0 -> A）严格一致；
    //   2) tb 源指纹帧无关（每帧内容相同）=> ref[bank] 新旧帧等价，
    //      比对门只需 rf_idx >= 3（跳过引导期回放），不依赖发布/回放
    //      速率对齐（v4.10a 的 pubs==rf_idx 门在 writer 恒超前时永假，
    //      曾致整场比对被跳过 = 假绿，sr 512b 截断 bug 漏检实锤）。
    reg [63:0] ref_mem [0:1][0:VACT-1][0:BEATS-1];
    integer    cap_sof_cnt = 0, cap_l = 0, cap_b = 0;
    integer    cke_err = 0, cke_beats = 0, cke_frames = 0, cke_skip = 0, cke_cmp = 0;
    reg [63:0] cke_exp;
    always @(posedge clk200 or negedge rstn200) begin
        if (!rstn200) begin
            cap_sof_cnt = 0; cap_l = 0; cap_b = 0;
        end else if (cap_tvalid) begin
            if (cap_tuser[0]) begin                   // sof（tuser={eof,sol,sof}）
                cap_l = 0; cap_b = 0;
            end else if (cap_tuser[1]) begin
                cap_l = cap_l + 1; cap_b = 0;
            end
            // 帧内全部拍（含 sof 拍）用自增前的 cnt —— 帧 k -> ref[k%2]，
            // 与 writer bank 序（帧 0 -> A）一致；自增必须在存储之后
            if (cap_l < VACT && cap_b < BEATS)
                ref_mem[cap_sof_cnt[0]][cap_l][cap_b] = cap_tdata;
            cap_b = cap_b + 1;
            if (cap_tuser[0]) cap_sof_cnt = cap_sof_cnt + 1;
        end
    end

    integer rd_l = 0, rd_b = 0, rd_sel = 0;
    integer pubs = 0, rf_idx = 0, rf_err = 0, rf_shown = 0;
    // P3 等价量：rd 回放流每帧 sol/tlast 计数（tb 本地——"reader 每帧
    // 恰发 VACT 行"回归判据）
    integer rd_sol_frame = 0, rd_tl_frame = 0;
    integer rd_sol_work = 0, rd_tl_work = 0;
    always @(posedge clk148) begin
        if (rd_rstn_148 && rd_tvalid) begin
            if (rd_tuser[0]) begin                    // sof（tuser={eof,sol,sof}）
                if (rf_idx > 0)
                    $display("[C-FRM] replay#%0d sel=%0d pubs=%0d err=%0d",
                             rf_idx, rd_sel, pubs, rf_err);
                rf_idx = rf_idx + 1;
                rf_err = 0; rf_shown = 0;
                rd_l = 0; rd_b = 0;
                rd_sel = u_rd.par_r;   // 回放帧 bank 奇偶（= 帧号%2）
                cke_frames = cke_frames + 1;
                rd_sol_frame = rd_sol_work;  rd_tl_frame = rd_tl_work;
                rd_sol_work = 1;             rd_tl_work = 0;
                // sof 拍即行 0（与旧显示链计数语义一致：work 从 1 起计）
            end else begin
                if (rd_tuser[1]) begin
                    rd_l = rd_l + 1; rd_b = 0;
                    rd_sol_work = rd_sol_work + 1;
                end
                if (rd_tlast) rd_tl_work = rd_tl_work + 1;
            end
            if (rf_idx >= 3 && rd_l < VACT && rd_b < BEATS) begin
                cke_cmp = cke_cmp + 1;            // 比对执行计数（防假绿自检）
                cke_exp = ref_mem[rd_sel][rd_l][rd_b];
                if (rd_tdata !== cke_exp) begin
                    cke_err = cke_err + 1;
                    rf_err = rf_err + 1;
                    if (rf_shown < 2) begin
                        rf_shown = rf_shown + 1;
                        $display("[C-FAIL] r#%0d sel=%0d l=%0d b=%0d got=%h exp=%h",
                                 rf_idx, rd_sel, rd_l, rd_b, rd_tdata, cke_exp);
                    end
                end
            end
            cke_beats = cke_beats + 1;
            rd_b = rd_b + 1;
        end
    end
    always @(posedge clk148)
        if (rd_rstn_148 && fw_done_148) pubs = pubs + 1;

    // ---------------- 监视 ----------------
    // ---- v4.10c3g 偏移/冻结机理监视（B 问题：固定偏移+底部闪区）----
    // 假说：reader 锚（vsync 下降沿=Vs 起始）后立即发射行 0，而显示 Va 段
    // 在锚后 VSP+VBP 行（tb=6）才开拉；tx_line_buf 仅 3.4 行深，装不下超
    // 前量 -> 背压流控闭环 -> 每帧锚时刻 reader 尚有 D 行残行 -> 显示帧尾
    // GATE 冻结 D 行（late 集中帧尾段=底部闪区），且 D = 偏移量（闪区=
    // 偏移部分）。测量口径（clk148 拍，除以 1100=行）：
    //   phi   = 锚 -> rd 流 sof 发射拍差（reader 帧相位）
    //   psi   = 锚 -> 显示 Va[0] 开拉拍差（Hg 过门进 Hp）
    //   late  = 每显示帧 GATE 冻结行数；frz = 冻结发生时的 Va 行号（前 4 个）
    //   lvl   = 帧内 tlb 水位 min/max（流控震荡区间）
    integer m_cyc = 0, m_vs_prev = -1, m_rdsof_prev = -1, m_va0_prev = -1;
    integer m_late_p = 0, m_frm = 0, m_late_last = -1;
    integer m_lmin = 32768, m_lmax = 0, m_frz_n = 0;
    integer m_frz_r0 = -1, m_frz_r1 = -1, m_frz_r2 = -1, m_frz_r3 = -1;
    reg m_vs_q = 1'b1;
    wire [15:0] m_lvl  = u_tlb.level_o;
    wire [15:0] m_late = u_dtg.late_cnt;
    wire [2:0]  m_vseg = u_dtg.v_seg;
    wire [11:0] m_vcnt = u_dtg.v_cnt;
    wire [2:0]  m_hst  = u_dtg.h_st;
    wire        m_va   = (m_vseg == 3'd2);
    always @(posedge clk148) begin
        m_cyc = m_cyc + 1;
        if (rstn148) begin
            m_vs_q <= vsync;
            if (m_vs_q && !vsync) begin                 // 授权锚（Vs 起始）
                if (m_vs_prev >= 0) begin
                    m_frm = m_frm + 1;
                    $display("[OFF] frm=%0d phi=%0d psi=%0d late=+%0d lvl=%0d..%0d frz=%0d,%0d,%0d,%0d",
                             m_frm,
                             (m_rdsof_prev >= 0) ? (m_rdsof_prev - m_vs_prev) : -9999,
                             (m_va0_prev   >= 0) ? (m_va0_prev   - m_vs_prev)   : -9999,
                             m_late - m_late_p, m_lmin, m_lmax,
                             m_frz_r0, m_frz_r1, m_frz_r2, m_frz_r3);
                    m_late_p = m_late; m_lmin = 32768; m_lmax = 0;
                    m_frz_n = 0; m_frz_r0 = -1; m_frz_r1 = -1;
                    m_frz_r2 = -1; m_frz_r3 = -1;
                end
                m_vs_prev = m_cyc;
            end
            if (rd_rstn_148 && rd_tvalid && rd_tuser[0]) m_rdsof_prev = m_cyc;
            if (m_va && m_vcnt == 12'd0 && m_hst == 3'd3) m_va0_prev = m_cyc;
            if (m_lvl < m_lmin) m_lmin = m_lvl;
            if (m_lvl > m_lmax) m_lmax = m_lvl;
            if (m_late_last < 0) m_late_last = m_late;
            else if (m_late != m_late_last) begin
                m_late_last = m_late;
                if (m_va && m_frz_n < 4) begin
                    case (m_frz_n)
                    0: m_frz_r0 = m_vcnt;
                    1: m_frz_r1 = m_vcnt;
                    2: m_frz_r2 = m_vcnt;
                    default: m_frz_r3 = m_vcnt;
                    endcase
                    m_frz_n = m_frz_n + 1;
                end
            end
        end
    end

    // late 行位置监视（v4.10b 板测顶底闪对位）：S_WAIT 中 tick 到而数据
    // 未就绪即 late，打印发射行号/读路径行号——用于确认 late 是否集中在
    // 帧头/帧尾（顶底闪假设）或均匀分布。
    always @(posedge clk148)
        if (rd_rstn_148 && u_rd.st == 3'd1 && u_rd.line_tick
            && !u_rd.rdy[u_rd.r_sel] && !u_rd.delayed)
            $display("[LATE] line_r=%0d rdln=%0d pubs=%0d @%0t",
                     u_rd.line_r, u_rd.rdln, pubs, $time);
    integer ar_hs = 0, rv_cnt = 0;
    always @(posedge clk148) begin
        if (arvalid && arready148)  ar_hs = ar_hs + 1;
        if (rvalid1 && rready)      rv_cnt = rv_cnt + 1;
    end
    integer pdv_q = 0, burst_len = 0, bursts = 0, pdv_beats = 0;
    always @(posedge clk148) if (rstn148) begin
        if (pdv) begin
            burst_len = burst_len + 1;
            pdv_beats = pdv_beats + 1;
        end else if (pdv_q != 0) begin
            if (burst_len !== BEATS) begin
                $display("[P2-FAIL] burst=%0d exp=960 @%0t", burst_len, $time);
                fail_cnt = fail_cnt + 1;
                if (fail_cnt > 8) $finish;
            end
            bursts = bursts + 1;
            burst_len = 0;
        end
        pdv_q = pdv;
    end

    // ---------------- 慢源实验监视（相机病理复现）----------------
    // vsync 周期（clk148）、late_cnt/under_cnt/drop 快照、reader sol 速率。
    integer cyc148 = 0;
    always @(posedge clk148) cyc148 = cyc148 + 1;
    reg vs_d = 0;
    integer vs_rise_cyc = -1;
    integer vs_p0, vs_p1, vs_p2;         // 最近 3 个 vsync 周期
    integer late_snap, late_snap0;
    reg [31:0] fr_snap;
    always @(posedge clk148) begin
        vs_d <= vsync;
        if (vsync && !vs_d && rstn148) begin
            if (vs_rise_cyc >= 0) begin
                vs_p0 = vs_p1; vs_p1 = vs_p2;
                vs_p2 = cyc148 - vs_rise_cyc;
            end
            vs_rise_cyc = cyc148;
            late_snap0  = late_snap;
            late_snap   = u_dtg.late_cnt;
            fr_snap     = u_rd.dbg_fr_cnt;
        end
    end

    // ---------------- 主流程 ----------------
    integer i;
    initial begin
        $display("[TB] phase4 + ddr_ctrl_model (CDC): VACT=%0d SLOTS=%0d",
                 VACT, SLOTS);
        // DDR 模型 CFG 握手：RESET(≥5 ctrl_clk) → 释放 → START → 等 DONE
        // （START 保持；DONE 后才放行路径复位，路径流量不撞初始化阻塞窗）
        repeat (12) @(posedge clk200);
        cfg_reset = 1'b0;
        cfg_start = 1'b1;
        wait (cfg_done === 1'b1);
        $display("[CFG] ddr model ready @%0t err=%b busy=%b",
                 $time, ctrl_err, ctrl_busy);
        repeat (4) @(posedge clk200);

        repeat (20) @(posedge clk200);
        rstn200 = 1;
        repeat (10) @(posedge clk148);
        rstn148 = 1;
        // 等 6 个显示帧（源 ~432us/帧，起步 ~2.5ms）
        wait (frame_num >= 6);
        repeat (3000) @(posedge clk148);

        $display("[SUM] fw_done? tog148=%b par=%b", tog148[1:0], par148[1]);
        $display("[SUM] CONTENT: frames=%0d beats=%0d cmp=%0d err=%0d",
                 cke_frames, cke_beats, cke_cmp, cke_err);
        if (cke_cmp == 0) begin
            $display("[P4C-FAIL] comparator never ran (gate stuck)");
            fail_cnt = fail_cnt + 1;
        end else if (cke_err != 0 || cke_frames == 0) begin
            $display("[P4C-FAIL] content check: frames=%0d beats=%0d err=%0d",
                     cke_frames, cke_beats, cke_err);
            fail_cnt = fail_cnt + 1;
        end else
            $display("[P4C-OK] content bit-exact through writer->DDR->reader");
        $display("[SUM] dms_sol=%0d yuv_v=%0d frm=%0d", dms_sol, yuv_v, frm_cnt);
        $display("[SUM] late/under = %h", dbg4);
        $display("[SUM] rd sol/tlast per frame = %0d/%0d (exp 90/90)",
                 rd_sol_frame, rd_tl_frame);
        $display("[SUM] frame_num=%0d line_num=%0d bursts=%0d pdv_beats=%0d",
                 frame_num, line_num, bursts, pdv_beats);
        // P1：帧完成
        if (frame_num < 6) begin
            $display("[P1-FAIL] frame_num=%0d", frame_num);
            fail_cnt = fail_cnt + 1;
        end
        // P3：诊断等价量（tb 本地计数）
        if (rd_sol_frame !== 90 || rd_tl_frame !== 90) begin
            $display("[P3-FAIL] rd sol/tlast=%0d/%0d exp 90/90",
                     rd_sol_frame, rd_tl_frame);
            fail_cnt = fail_cnt + 1;
        end
        if (dms_sol == 0) begin
            $display("[P3-FAIL] dms_sol=0");
            fail_cnt = fail_cnt + 1;
        end
        if (frm_cnt < 4) begin
            $display("[P3-FAIL] frm_cnt=%0d (vsync edges)", frm_cnt);
            fail_cnt = fail_cnt + 1;
        end
        if (pdv_beats == 0) begin
            $display("[P3-FAIL] no TX valid beats");
            fail_cnt = fail_cnt + 1;
        end
        // DDRM：sticky CTRL_ERR（非法 cache/cobuf 组合、坏 WLAST 等粘滞）
        $display("[DDRM] ctrl_err=%b init_done=%b ready=%b busy=%b",
                 ctrl_err, ctrl_init_done, ctrl_ready, ctrl_busy);
        if (ctrl_err !== 1'b0) begin
            $display("[DDRM-FAIL] sticky CTRL_ERR set");
            fail_cnt = fail_cnt + 1;
        end
        if (fail_cnt == 0)
            $display("[P4-OK] board topology all checks passed");
        else
            $display("[P4-FAIL] fail_cnt=%0d", fail_cnt);

        // ================= 慢源实验（相机病理复现）=================
        // 源线率压到显示消费 2/3（gap=1256）。测量：显示 vsync 周期是否
        // 跌破 SLOTS×LINE_CLKS（供给节流）、late_cnt 增量、drop/repeat。
        $display("[SLOW] begin: vs_p=%0d late=%0d fr=%h",
                 vs_p2, late_snap, fr_snap);
        src_gap_beats = 1256;
        repeat (6) @(posedge vsync);
        repeat (2000) @(posedge clk148);
        $display("[SLOW] result: vs_p_prev=%0d vs_p=%0d (exp_fast=%0d)",
                 vs_p1, vs_p2, SLOTS * 1100);
        $display("[SLOW] late_delta=%0d fr=%h (drop=%0d rpt=%0d)",
                 late_snap - late_snap0, fr_snap,
                 $signed(fr_snap[31:16]), $signed(fr_snap[15:0]));
        if (vs_p2 < SLOTS * 1100) begin
            $display("[SLOW-FAIL] display period shrunk below slot rate");
            fail_cnt = fail_cnt + 1;
        end else
            $display("[SLOW-OK] display period >= slot rate under 2/3 supply");
        $finish;
    end

    initial begin
        #40_000_000;
        $display("[P4-FAIL] watchdog frame_num=%0d dms_sol=%0d frm=%0d",
                 frame_num, dms_sol, frm_cnt);
        $display("[P4-FAIL] rd_arb dbg=%h -> gnt_act=%b gnt=%b lock=%b stuck=%b txn_s1=%0d beat_s1=%0d",
                 rd_arb_dbg, rd_arb_dbg[68], rd_arb_dbg[67:66], rd_arb_dbg[65],
                 rd_arb_dbg[64], rd_arb_dbg[63:48], rd_arb_dbg[31:16]);
        $display("[P4-FAIL] S1: arv=%b arrdy=%b rv=%b rrdy=%b | M: arv=%b arrdy=%b rv=%b rrdy=%b",
                 rd_arvalid, rd_arready, rd_rvalid, rd_rready,
                 m_arvalid, m_arready, m_rvalid, m_rready);
        $display("[P4-FAIL] reader: state=%h arv=%b arrdy=%b rv=%b rrdy=%b line=%0d frmcnt=%0d err=%h",
                 u_rd.rd_state, u_rd.arvalid, u_rd.arready, u_rd.rvalid,
                 u_rd.rready, u_rd.rd_line, u_rd.rd_frame_cnt, u_rd.rd_err);
        // ---- writer 侧 + 发布链探针（定位 reader 起步门未开根因）----
        // d_st: 0=D_SETUP 1=D_PREWR 2=D_WRITE 3=D_POSTWR（卡 3 = 等 B）
        $display("[P4-FAIL] writer: done=%0d aw=%0d w=%0d bx=%0d d_st=%0d inframe=%b lnf=%0d fcnt=%0d",
                 done_pulses, aw_cnt, w_cnt, bx_cnt,
                 u_fw.d_st, u_fw.in_frame, u_fw.line_in_frame, u_fw.frame_cnt_r);
        $display("[P4-FAIL] writer2: dw=%0d dr=%0d bad=%0d drop=%0d bldrop=%0d awr=%b wrdy=%b bv=%b brdy=%b",
                 u_fw.dw_ptr, u_fw.dr_ptr, u_fw.bad_cnt_r, u_fw.drop_cnt_r,
                 u_fw.last_drop_line_r, awready, wready, bvalid, fw_bready);
        $display("[P4-FAIL] pubchain: tog200=%b tog148=%b fw148=%b pubs=%0d done_sync=%b ctrl_err=%b",
                 tog200, tog148[2:1], fw_done_148, pubs, u_rd.done_sync, ctrl_err);
        $finish;
    end

endmodule
