// ============================================================================
// tb_phase5_cam1.sv — Phase 5 cam1（1080p60）DDR 回放全链 TB
//   以 tb_phase4_ddrm.sv 为基线的 cam1 几何变体（cam1-ddr-replay-plan §4
//   阶段 5 判据：1080 缩帧全链 TB，复刻 P4C 内容判据）：
//     - 源窗口 = cam1 1080p 缺省组：LINE_TOTAL_PIX=1944（486 拍）/SKIP 11/
//       VACT 缩帧 90 行；sink 载体 = 480 拍/60 字/32+28 两突发/4KB 行槽
//       （stride shift 12）；
//     - 三钟域：clk200（源/writer/写仲裁/model port0）/ clk148（cdc m 侧/
//       读仲裁/model port1）/ clk37=37.125M（reader/显示链/cdc s 侧），
//       板级同构（target1 ACLK=148.5M，reader 域=37.125M）；
//     - 拓扑 = top_cam_demo 阶段5 集成镜像：u_fw1 -> axi_wr_arb S0 ->
//       model target0；u_rd1 -> axi_rd_cdc -> axi_rd_arb S0 -> target1
//       （对侧 S1 恒 idle——cam0 不在场，RR1 空闲回退 S0 由单元 TB 覆盖）；
//     - 显示链 = demosaic(GW480)->wb->rgb2yuv->tx_line_buf->disp_timing
//       （LINE_CLKS=550 / SLOTS=140 = 5+36+90+4+5 缩帧 / HACT 1920）；
//     - 帧握手 toggle 200M -> 37.125M 跨域（复刻板级 tog 结构）；
//     - DDR 布局 cam1：A1=0x0400_0000 / B1=0x0500_0000（§3/§10 核算）。
//   判据 = tb_phase4_ddrm 全量（P1/P2/P3/P4C/SLOW/CTRL_ERR sticky），其中
//   P4C = 源指纹 {l,b,A5C3} 逐拍穿越 writer->写仲裁->DDR 模型->读仲裁->
//   CDC->reader 的比特精确比对（rf_idx>=3 门，防假绿 cmp 计数自检）。
// ============================================================================

`timescale 1ns / 1ps

module tb_phase5_cam1;

    localparam real  HALF200 = 2.5;
    localparam real  HALF148 = 3.367;
    localparam real  HALF37  = 13.468;
    localparam int   VACT    = 90;
    localparam int   BEATS   = 480;    // HACT 载体拍（1920px/4）
    localparam int   WORDS   = 60;     // 3840B / 64B
    localparam int   SLOTS   = 140;    // 5+36+90+4+5（缩帧）
    localparam [32:0] FRAME_A1 = 33'h0_0400_0000;
    localparam [32:0] FRAME_B1 = 33'h0_0500_0000;

    reg clk200 = 0, clk148 = 0, clk37 = 0;
    reg rstn200 = 0, rstn148 = 0, rstn37 = 0;
    always #(HALF200) clk200 = ~clk200;
    always #(HALF148) clk148 = ~clk148;
    always #(HALF37)  clk37  = ~clk37;
    integer fail_cnt = 0;

    // ---------------- 源（cam1 窗口：1944px/行 = 486 拍）----------------
    reg  [39:0] in_data;
    reg         in_valid, in_vs, in_hs;
    reg  [5:0]  in_dtype = 6'h2B;
    integer     f_cnt, l_cnt, b_cnt;
    localparam int LINE_TOTAL_BEATS = 486;   // 1944/4
    localparam int SKIP_LINES       = 11;
    reg  [1:0]  vs_gap = 0;
    // P4C 主用例：源锚行 = 486+2476 = 2962 拍 = 14.8us 与显示行同速。
    // gap=0 会以 2.43us/行快灌（4K 源 966 拍不积压，cam1 行短 2 倍），
    // DDR 写口 ~3-3.5us/行 跟不上 -> 8 槽队列溢出 q_full -> 整帧 bad。
    integer     src_gap_beats = 2476;        // 慢源实验（SLOW 段切 3958）
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
                in_vs  <= (vs_gap == 2'd2);
                vs_gap = vs_gap - 1;
            end else if (src_gap_cnt != 0) begin
                src_gap_cnt <= src_gap_cnt - 1;
            end else if (f_cnt < 64) begin
                if (b_cnt == 0) in_hs <= 1'b1;
                // 帧无关指纹：内容仅 (l,b) 函数——P4C 无需帧号对齐
                in_data  <= {4'h0, l_cnt[7:0], b_cnt[9:0], 16'hA5C3};
                in_valid <= 1'b1;
                if (b_cnt == LINE_TOTAL_BEATS-1) begin
                    b_cnt <= 0;
                    src_gap_cnt <= src_gap_beats;
                    if (l_cnt == SKIP_LINES + VACT-1) begin
                        l_cnt <= 0; f_cnt <= f_cnt + 1;
                        vs_gap = 2;
                    end else
                        l_cnt <= l_cnt + 1;
                end else
                    b_cnt <= b_cnt + 1;
            end
        end
    end

    // ---------------- raw_2_axi4st（cam1 窗口清洗）-----------------------
    wire [39:0] raw_tdata;
    wire        raw_tvalid, raw_tlast;
    wire [2:0]  raw_tuser;

    raw_2_axi4st #(
        .DTYPE           (6'h2B),
        .LINE_TOTAL_PIX  (20'd1944),
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

    wire [63:0]  cap_tdata  = {24'h0, raw_tdata};
    wire         cap_tvalid = raw_tvalid;
    wire         cap_tlast  = raw_tlast;
    wire [2:0]   cap_tuser  = raw_tuser;

    // ---------------- 写侧：u_fw1 -> axi_wr_arb -> model target0 --------
    wire [32:0]  awaddr;
    wire [7:0]   awlen;
    wire         awvalid, wlast, wvalid;
    wire [511:0] wdata;
    wire         awready, wready, bvalid;
    wire         wr_par, fw1_frame_done;
    wire         fw1_bready;
    integer      done_pulses = 0;
    always @(posedge clk200) if (fw1_frame_done) done_pulses = done_pulses + 1;
    integer aw_cnt = 0, w_cnt = 0, bx_cnt = 0;
    always @(posedge clk200) begin
        if (awvalid && awready) aw_cnt = aw_cnt + 1;
        if (wvalid && wready)   w_cnt = w_cnt + 1;
        if (bvalid && fw1_bready) bx_cnt = bx_cnt + 1;
    end

    wire [2:0]   awsize;
    wire [1:0]   awburst;
    wire [3:0]   awcache, awqos;
    wire         awlock, awcobuf, awapcmd, awallstrb;
    wire [63:0]  wstrb;
    wire [5:0]   bid1;
    wire [1:0]   bresp1;
    wire         cfg_done, ctrl_init_done, ctrl_ready, ctrl_err, ctrl_busy;
    reg          cfg_reset = 1'b1, cfg_start = 1'b0;
    wire [3:0]   fw1_state;
    wire [15:0]  fw1_line_cnt, fw1_frame_cnt, fw1_pad_cnt, fw1_ovf_cnt;
    wire [11:0]  fw1_line;
    wire [31:0]  fw1_dbg2;

    frame_writer #(
        .VACT    (16'd90),
        .FRAME_A (FRAME_A1),
        .FRAME_B (FRAME_B1),
        .BEATS_PER_LINE    (10'd480),
        .WORDS_PER_LINE    (7'd60),
        .WB0_BEATS         (9'd32),
        .WB1_BEATS         (9'd28),
        .LINE_STRIDE_SHIFT (5'd12)
    ) u_fw1 (
        .aclk(clk200), .rstn(rstn200), .flush_i(1'b0),
        .s_axis_tdata(cap_tdata), .s_axis_tvalid(cap_tvalid),
        .s_axis_tlast(cap_tlast), .s_axis_tuser(cap_tuser),
        .awaddr(awaddr), .awlen(awlen), .awvalid(awvalid), .awready(awready),
        .awsize(awsize), .awburst(awburst), .awcache(awcache), .awlock(awlock),
        .awcobuf(awcobuf), .awapcmd(awapcmd), .awallstrb(awallstrb),
        .awqos(awqos),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid),
        .wready(wready),
        .bid(bid1), .bvalid(bvalid), .bready(fw1_bready),
        .line_cnt(fw1_line_cnt), .frame_cnt(fw1_frame_cnt),
        .pad_cnt(fw1_pad_cnt), .ovf_cnt(fw1_ovf_cnt), .dbg_state(fw1_state),
        .wr_par(wr_par), .wr_line(fw1_line), .wr_frame_done_o(fw1_frame_done),
        .wr_perf(), .fw_dbg2(fw1_dbg2)
    );

    // u_wr_arb M → model target0
    wire [32:0]  ddr_awaddr;
    wire [7:0]   ddr_awlen;
    wire [2:0]   ddr_awsize;
    wire [1:0]   ddr_awburst;
    wire [3:0]   ddr_awqos, ddr_awcache;
    wire         ddr_awlock;
    wire         ddr_awvalid, ddr_awready;
    wire         ddr_wvalid, ddr_wready, ddr_wlast;
    wire [511:0] ddr_wdata;
    wire [63:0]  ddr_wstrb;
    wire         ddr_bvalid, ddr_bready;
    wire [1:0]   ddr_bresp;

    axi_wr_arb u_wr_arb (
        .clk  (clk200), .rstn (rstn200),
        // S1 = cam0（不在场，恒 idle）
        .s1_awvalid (1'b0),        .s1_awready (),
        .s1_awaddr  (33'h0),       .s1_awlen   (8'h0),
        .s1_awsize  (3'h0),        .s1_awburst (2'h0),
        .s1_awid    (6'h0),        .s1_awqos   (4'h0),
        .s1_awcache (4'h0),        .s1_awlock  (1'b0),
        .s1_wvalid  (1'b0),        .s1_wready  (),
        .s1_wdata   (512'h0),      .s1_wstrb   (64'h0),
        .s1_wlast   (1'b0),
        .s1_bvalid  (),            .s1_bready  (1'b1),
        .s1_bresp   (),            .s1_bid     (),
        // S0 = cam1 u_fw1
        .s0_awvalid (awvalid),     .s0_awready (awready),
        .s0_awaddr  (awaddr),      .s0_awlen   (awlen),
        .s0_awsize  (awsize),      .s0_awburst (awburst),
        .s0_awid    (6'h0),        .s0_awqos   (awqos),
        .s0_awcache (awcache),     .s0_awlock  (awlock),
        .s0_wvalid  (wvalid),      .s0_wready  (wready),
        .s0_wdata   (wdata),       .s0_wstrb   (wstrb),
        .s0_wlast   (wlast),
        .s0_bvalid  (bvalid),      .s0_bready  (fw1_bready),
        .s0_bresp   (bresp1),      .s0_bid     (bid1),
        // M → model target0
        .m_awvalid  (ddr_awvalid),  .m_awready  (ddr_awready),
        .m_awaddr   (ddr_awaddr),   .m_awlen    (ddr_awlen),
        .m_awsize   (ddr_awsize),   .m_awburst  (ddr_awburst),
        .m_awid     (),             .m_awqos    (ddr_awqos),
        .m_awcache  (ddr_awcache),  .m_awlock   (ddr_awlock),
        .m_wvalid   (ddr_wvalid),   .m_wready   (ddr_wready),
        .m_wdata    (ddr_wdata),    .m_wstrb    (ddr_wstrb),
        .m_wlast    (ddr_wlast),
        .m_bvalid   (ddr_bvalid),   .m_bready   (ddr_bready),
        .m_bresp    (ddr_bresp),    .m_bid      (),
        .dbg        ()
    );

    // ---------------- 帧握手 toggle 跨域（200M -> 37.125M，板级同款）----
    reg tog200 = 0;
    always @(posedge clk200 or negedge rstn200)
        if (!rstn200) tog200 <= 0;
        else if (fw1_frame_done) tog200 <= ~tog200;
    reg [2:0] tog37 = 0;
    reg [1:0] par37 = 0;
    always @(posedge clk37 or negedge rstn37) begin
        if (!rstn37) begin tog37 <= 0; par37 <= 0; end
        else begin
            tog37 <= {tog37[1:0], tog200};
            par37 <= {par37[0], wr_par};
        end
    end
    wire fw_done_37 = tog37[1] ^ tog37[2];
    wire fw_par_37  = par37[1];

    wire rd_rstn_37 = rstn37;

    // ---------------- 读侧：u_rd1 -> cdc -> arb -> model target1 --------
    wire [63:0] rd_tdata;
    wire        rd_tvalid, rd_tlast;
    wire [2:0]  rd_tuser;
    wire        disp_line_tick;
    wire        disp_line_room;
    wire        disp_sof;
    wire        disp_stall;
    wire        rd_rstn_148 = rstn148;

    // u_rd1（37.125M）AXI -> cdc s 侧
    wire        rd1_arvalid, rd1_arready, rd1_arlock;
    wire [32:0] rd1_araddr;
    wire [7:0]  rd1_arlen;
    wire [2:0]  rd1_arsize;
    wire [1:0]  rd1_arburst;
    wire [5:0]  rd1_arid;
    wire [3:0]  rd1_arqos;
    wire        rd1_rvalid, rd1_rready, rd1_rlast;
    wire [511:0] rd1_rdata;
    wire [1:0]  rd1_rresp;
    wire [5:0]  rd1_rid;

    // cdc m 侧 -> arb S0
    wire        cdc_m_arvalid, cdc_m_arready;
    wire [32:0] cdc_m_araddr;
    wire [7:0]  cdc_m_arlen;
    wire [2:0]  cdc_m_arsize;
    wire [1:0]  cdc_m_arburst;
    wire [5:0]  cdc_m_arid;
    wire [3:0]  cdc_m_arqos, cdc_m_arcache;
    wire        cdc_m_arlock;
    wire        cdc_m_rvalid, cdc_m_rready;
    wire [511:0] cdc_m_rdata;
    wire [1:0]  cdc_m_rresp;
    wire        cdc_m_rlast;
    wire [5:0]  cdc_m_rid;

    axi_rd_cdc u_rd_cdc1 (
        .aclk_s    (clk37),        .rstn_s (rd_rstn_37),
        .s_arvalid (rd1_arvalid),  .s_arready (rd1_arready),
        .s_araddr  (rd1_araddr),   .s_arlen (rd1_arlen),
        .s_arsize  (rd1_arsize),   .s_arburst (rd1_arburst),
        .s_arid    (rd1_arid),     .s_arqos (rd1_arqos),
        .s_arcache (4'h0),         .s_arlock (rd1_arlock),
        .s_rvalid  (rd1_rvalid),   .s_rready (rd1_rready),
        .s_rdata   (rd1_rdata),
        .s_rresp   (rd1_rresp),    .s_rlast (rd1_rlast),
        .s_rid     (rd1_rid),
        .aclk_m    (clk148),       .rstn_m (rd_rstn_148),
        .m_arvalid (cdc_m_arvalid),.m_arready (cdc_m_arready),
        .m_araddr  (cdc_m_araddr), .m_arlen (cdc_m_arlen),
        .m_arsize  (cdc_m_arsize), .m_arburst (cdc_m_arburst),
        .m_arid    (cdc_m_arid),   .m_arqos (cdc_m_arqos),
        .m_arcache (cdc_m_arcache),.m_arlock (cdc_m_arlock),
        .m_rvalid  (cdc_m_rvalid), .m_rready (cdc_m_rready),
        .m_rdata   (cdc_m_rdata),
        .m_rresp   (cdc_m_rresp),  .m_rlast (cdc_m_rlast),
        .m_rid     (cdc_m_rid)
    );

    wire [68:0] rd_arb_dbg;
    wire [32:0] m_araddr;
    wire [7:0]  m_arlen;
    wire [2:0]  m_arsize;
    wire [1:0]  m_arburst;
    wire [5:0]  m_arid;
    wire [3:0]  m_arqos;
    wire        m_arvalid, m_arready, m_arlock;
    wire        m_rvalid, m_rready, m_rlast;
    wire [511:0] m_rdata;
    wire [1:0]  m_rresp;
    wire [5:0]  m_rid;

    axi_rd_arb u_rd_arb (
        .clk(clk148), .rstn(rd_rstn_148),
        // S1 = cam0（不在场，恒 idle）
        .s1_arvalid (1'b0),            .s1_arready (),
        .s1_araddr  (33'h0),           .s1_arlen   (8'h0),
        .s1_arsize  (3'h0),            .s1_arburst (2'h0),
        .s1_arid    (6'h0),            .s1_arqos   (4'h0),
        .s1_arcache (4'h0),            .s1_arlock  (1'b0),
        .s1_rvalid  (),                .s1_rready  (1'b1),
        .s1_rdata   (),
        .s1_rresp   (),                .s1_rlast   (),
        .s1_rid     (),
        // S0 = cam1_rd_cdc m 侧
        .s0_arvalid (cdc_m_arvalid),   .s0_arready (cdc_m_arready),
        .s0_araddr  (cdc_m_araddr),    .s0_arlen   (cdc_m_arlen),
        .s0_arsize  (cdc_m_arsize),    .s0_arburst (cdc_m_arburst),
        .s0_arid    (cdc_m_arid),      .s0_arqos   (cdc_m_arqos),
        .s0_arcache (cdc_m_arcache),   .s0_arlock  (cdc_m_arlock),
        .s0_rvalid  (cdc_m_rvalid),    .s0_rready  (cdc_m_rready),
        .s0_rdata   (cdc_m_rdata),
        .s0_rresp   (cdc_m_rresp),     .s0_rlast   (cdc_m_rlast),
        .s0_rid     (cdc_m_rid),
        // M = model target1（148.5M）
        .m_arvalid  (m_arvalid),       .m_arready  (m_arready),
        .m_araddr   (m_araddr),        .m_arlen    (m_arlen),
        .m_arsize   (m_arsize),        .m_arburst  (m_arburst),
        .m_arid     (m_arid),          .m_arqos    (m_arqos),
        .m_arcache  (),                .m_arlock   (m_arlock),
        .m_rvalid   (m_rvalid),        .m_rready   (m_rready),
        .m_rdata    (m_rdata),
        .m_rresp    (m_rresp),         .m_rlast    (m_rlast),
        .m_rid      (m_rid),
        .dbg        (rd_arb_dbg)
    );

    frame_reader #(
        .VACT    (16'd90),
        .FRAME_TICKS (16'd140),
        .FRAME_A (FRAME_A1),
        .FRAME_B (FRAME_B1),
        // 锚窗口：VSP+VBP(41) - 余量 2（tb 同 cam0 口径： demosaic 3 行窗）
        .ANCHOR_WAIT (12'd39),
        .BEATS_PER_LINE    (10'd480),
        .WORDS_PER_LINE    (7'd60),
        .WB0_BEATS         (9'd32),
        .WB1_BEATS         (9'd28),
        .LINE_STRIDE_SHIFT (5'd12)
    ) u_rd1 (
        .aclk(clk37), .rstn(rd_rstn_37), .flush_i(1'b0), .enable(1'b1),
        .flush_done_o(),
        .line_tick(disp_line_tick),
        .line_room_i(disp_line_room),
        .disp_sof_i(disp_sof),
        .disp_stall_i(disp_stall),
        .wr_frame_done(fw_done_37), .wr_frame_par(fw_par_37),
        .m_axis_tdata(rd_tdata), .m_axis_tvalid(rd_tvalid),
        .m_axis_tlast(rd_tlast), .m_axis_tuser(rd_tuser),
        .araddr(rd1_araddr), .arlen(rd1_arlen), .arvalid(rd1_arvalid),
        .arready(rd1_arready),
        .arid(rd1_arid), .arsize(rd1_arsize), .arburst(rd1_arburst),
        .arlock(rd1_arlock),
        .arapcmd(), .arqos(rd1_arqos),
        .rdata(rd1_rdata), .rlast(rd1_rlast), .rvalid(rd1_rvalid),
        .rready(rd1_rready),
        .rresp(rd1_rresp), .rid(rd1_rid),
        .rd_frame_cnt(), .rd_line(), .rd_state(), .rd_err(), .dbg_fr_cnt()
    );

    // ---------------- ddr_ctrl_model 实模型 ------------------------------
    ddr_axi_model_top #(
        .CDC_ENABLE         (1'b1),
        .MEM_DENSITY_GBIT   (2),
        .DATA_WIDTH         (16),
        .ENABLE_CTRL_STATUS (1'b1)
    ) u_ddr (
        .ctrl_clk      (clk200),
        // ---- target0：u_wr_arb M（200M 域）----
        .ACLK_0        (clk200), .ARSTN_0    (rstn200),
        .AWADDR_0      (ddr_awaddr), .AWBURST_0 (ddr_awburst),
        .AWID_0        (6'h0),
        .AWLEN_0       (ddr_awlen),  .AWREADY_0 (ddr_awready),
        .AWSIZE_0      (ddr_awsize),
        .AWVALID_0     (ddr_awvalid),.AWLOCK_0  (ddr_awlock),
        .AWAPCMD_0     (1'b0),
        .AWQOS_0       (ddr_awqos),  .AWCACHE_0 (ddr_awcache),
        .AWALLSTRB_0   (1'b0),
        .AWCOBUF_0     (1'b0),
        .WDATA_0       (ddr_wdata),  .WLAST_0   (ddr_wlast),
        .WREADY_0      (ddr_wready),
        .WSTRB_0       (ddr_wstrb),  .WVALID_0  (ddr_wvalid),
        .BID_0         (),           .BREADY_0  (ddr_bready),
        .BRESP_0       (ddr_bresp),
        .BVALID_0      (ddr_bvalid),
        .ARADDR_0      (33'h0),  .ARBURST_0 (2'h0),    .ARID_0  (6'h0),
        .ARLEN_0       (8'h0),   .ARREADY_0 (),        .ARSIZE_0(3'h0),
        .ARVALID_0     (1'b0),   .ARLOCK_0  (1'b0),    .ARAPCMD_0(1'b0),
        .ARQOS_0       (4'h0),
        .RDATA_0       (),       .RID_0     (),        .RLAST_0 (),
        .RREADY_0      (1'b0),   .RRESP_0   (),        .RVALID_0(),
        // ---- target1：u_rd_arb M（148.5M 域，板级 ACLK_1 同绑）----
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
        .DBG_FIELDS    (), .DBG_FIELDS_ADDR()
    );

    // ---------------- 显示链（37.125M 域，板级同构）----------------------
    wire [39:0] dms_in_tdata = rd_tdata[39:0];
    wire [2:0]  dms_in_tuser = rd_tuser;
    wire        dms_in_tlast = rd_tlast;
    wire        cdc_valid    = rd_tvalid;

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
        .GW   (16'd480),
        .LINES(16'd90)
    ) u_demosaic (
        .aclk         (clk37), .aresetn(rstn37),
        .s_axis_tdata (dms_in_tdata), .s_axis_tvalid(cdc_valid),
        .s_axis_tlast (dms_in_tlast), .s_axis_tuser(dms_in_tuser),
        .bayer_phase  (2'd0), .adaptive(1'b1),
        .m_axis_tdata (dms_tdata), .m_axis_tvalid(dms_tvalid),
        .m_axis_tlast (dms_tlast), .m_axis_tuser(dms_tuser),
        .dbg_reswin_cnt ()
    );

    wb_axis u_wb (
        .aclk         (clk37), .aresetn(rstn37),
        .s_axis_tdata (dms_tdata), .s_axis_tvalid(dms_tvalid),
        .s_axis_tlast (dms_tlast), .s_axis_tuser(dms_tuser),
        .wb_r(8'd200), .wb_g(8'd235), .wb_b(8'd180),
        .m_axis_tdata (wb_tdata), .m_axis_tvalid(wb_tvalid),
        .m_axis_tlast (wb_tlast), .m_axis_tuser(wb_tuser)
    );

    rgb2yuv_axis u_rgb2yuv (
        .aclk         (clk37), .aresetn(rstn37),
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
        .clk          (clk37), .rst_n(rstn37),
        .s_axis_tdata (yuv_tdata),
        .s_axis_tvalid(yuv_tvalid & rstn37),
        .rd_en        (dt_rd_en),
        .rd_data      (dt_rdata), .rd_valid(dt_valid),
        .level_o      (dt_level),
        .dbg_buf_cnt_o()
    );

    wire        hsync, vsync, pdv, frame_open;
    wire [5:0]  datatype;
    wire [63:0] pixel_data;
    wire [15:0] haddr, line_num, frame_num;
    wire [31:0] dbg4;

    disp_timing #(
        .LINE_CLKS  (550),                  // CTA 1080p60@PPC4
        .FRAME_SLOTS(SLOTS[15:0]),          // 140 = 5+36+90+4+5（缩帧）
        .LINE_WORDS (16'd480),              // HACT/PPC = 1920/4
        .LINE_BUF_WORDS(16'd300),           // 480px x 40b / 64b = 1 行整
        .VSP_L      (16'd5),  .VBP_L(16'd36),
        .VACT_L     (16'd90), .VFP_L(16'd4),
        .PAD_L      (16'd5),                // SLOTS - 5 - 36 - 90 - 4
        .HACT_PX    (16'd1920),
        .HSP_CLKS   (16'd11),               // 550 = 11+37+1+2+480+19
        .HBP_CLKS   (16'd37),
        .HFP_CLKS   (16'd19),
        .DATA_TYPE  (6'h1E)
    ) u_dtg (
        .clk          (clk37), .rst_n(rstn37),
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

    // 行水位节流/帧界/断粮（与 top_cam 内联网表同式；1 行整 = 300 字）
    assign disp_line_room = (dt_level <= 16'd2048 - 16'd480);
    assign disp_sof       = vsync;
    assign disp_stall     = (dt_level < 16'd300);

    // P3 等价量
    integer dms_sol = 0, yuv_v = 0, frm_cnt = 0;
    reg     frm_vs_q = 1'b1;
    always @(posedge clk37) begin
        if (rstn37) begin
            if (dms_tvalid && dms_tuser[1]) dms_sol = dms_sol + 1;
            if (yuv_tvalid)                 yuv_v  = yuv_v + 1;
            frm_vs_q <= vsync;
            if (vsync && !frm_vs_q) frm_cnt = frm_cnt + 1;
        end
    end

    // ---------------- 内容校验（P4C，复刻 tb_phase4_ddrm v4.10 判据）------
    // ref[bank][line][beat]：帧 k 全拍以自增前 cap_sof_cnt 寻址 -> ref[k%2]
    //（与 writer bank 序一致）；源指纹帧无关 => 比对门 rf_idx>=3。
    reg [63:0] ref_mem [0:1][0:VACT-1][0:BEATS-1];
    integer    cap_sof_cnt = 0, cap_l = 0, cap_b = 0;
    integer    cke_err = 0, cke_beats = 0, cke_frames = 0, cke_skip = 0, cke_cmp = 0;
    reg [63:0] cke_exp;
    always @(posedge clk200 or negedge rstn200) begin
        if (!rstn200) begin
            cap_sof_cnt = 0; cap_l = 0; cap_b = 0;
        end else if (cap_tvalid) begin
            if (cap_tuser[0]) begin
                cap_l = 0; cap_b = 0;
            end else if (cap_tuser[1]) begin
                cap_l = cap_l + 1; cap_b = 0;
            end
            if (cap_l < VACT && cap_b < BEATS)
                ref_mem[cap_sof_cnt[0]][cap_l][cap_b] = cap_tdata;
            cap_b = cap_b + 1;
            if (cap_tuser[0]) cap_sof_cnt = cap_sof_cnt + 1;
        end
    end

    integer rd_l = 0, rd_b = 0, rd_sel = 0;
    integer pubs = 0, rf_idx = 0, rf_err = 0, rf_shown = 0;
    integer rd_sol_frame = 0, rd_tl_frame = 0;
    integer rd_sol_work = 0, rd_tl_work = 0;
    always @(posedge clk37) begin
        if (rd_rstn_37 && rd_tvalid) begin
            if (rd_tuser[0]) begin
                if (rf_idx > 0)
                    $display("[C-FRM] replay#%0d sel=%0d pubs=%0d err=%0d",
                             rf_idx, rd_sel, pubs, rf_err);
                rf_idx = rf_idx + 1;
                rf_err = 0; rf_shown = 0;
                rd_l = 0; rd_b = 0;
                rd_sel = u_rd1.par_r;
                cke_frames = cke_frames + 1;
                rd_sol_frame = rd_sol_work;  rd_tl_frame = rd_tl_work;
                rd_sol_work = 1;             rd_tl_work = 0;
            end else begin
                if (rd_tuser[1]) begin
                    rd_l = rd_l + 1; rd_b = 0;
                    rd_sol_work = rd_sol_work + 1;
                end
                if (rd_tlast) rd_tl_work = rd_tl_work + 1;
            end
            if (rf_idx >= 3 && rd_l < VACT && rd_b < BEATS) begin
                cke_cmp = cke_cmp + 1;
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
    always @(posedge clk37)
        if (rd_rstn_37 && fw_done_37) pubs = pubs + 1;

    // P2：TX HACT 突发连续拍
    integer pdv_q = 0, burst_len = 0, bursts = 0, pdv_beats = 0;
    always @(posedge clk37) if (rstn37) begin
        if (pdv) begin
            burst_len = burst_len + 1;
            pdv_beats = pdv_beats + 1;
        end else if (pdv_q != 0) begin
            if (burst_len !== BEATS) begin
                $display("[P2-FAIL] burst=%0d exp=%0d @%0t", burst_len, BEATS, $time);
                fail_cnt = fail_cnt + 1;
                if (fail_cnt > 8) $finish;
            end
            bursts = bursts + 1;
            burst_len = 0;
        end
        pdv_q = pdv;
    end

    // LATE 监视（发射行迟到定位）
    always @(posedge clk37)
        if (rd_rstn_37 && u_rd1.st == 3'd1 && u_rd1.line_tick
            && !u_rd1.rdy[u_rd1.r_sel] && !u_rd1.delayed)
            $display("[LATE] line_r=%0d rdln=%0d pubs=%0d @%0t",
                     u_rd1.line_r, u_rd1.rdln, pubs, $time);

    // vsync 周期（SLOW 判据用）
    integer cyc37 = 0;
    always @(posedge clk37) cyc37 = cyc37 + 1;
    reg vs_d = 0;
    integer vs_rise_cyc = -1;
    integer vs_p0, vs_p1, vs_p2;
    integer late_snap, late_snap0;
    reg [31:0] fr_snap;
    always @(posedge clk37) begin
        vs_d <= vsync;
        if (vsync && !vs_d && rstn37) begin
            if (vs_rise_cyc >= 0) begin
                vs_p0 = vs_p1; vs_p1 = vs_p2;
                vs_p2 = cyc37 - vs_rise_cyc;
            end
            vs_rise_cyc = cyc37;
            late_snap0  = late_snap;
            late_snap   = u_dtg.late_cnt;
            fr_snap     = u_rd1.dbg_fr_cnt;
        end
    end

    // ---------------- 主流程 ----------------
    initial begin
        $display("[TB] phase5 cam1 full-chain: VACT=%0d BEATS=%0d WORDS=%0d SLOTS=%0d",
                 VACT, BEATS, WORDS, SLOTS);
        // DDR 模型 CFG 握手（同 tb_phase4_ddrm）
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
        repeat (10) @(posedge clk37);
        rstn37  = 1;
        // 等 6 个显示帧（140 槽 x 550 拍 x 26.9ns ≈ 2.08ms/帧）
        wait (frame_num >= 6);
        repeat (3000) @(posedge clk37);

        $display("[SUM] fw_done? tog37=%b par=%b", tog37[1:0], par37[1]);
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
            $display("[P4C-OK] content bit-exact through fw1->wr_arb->DDR->rd_arb->cdc->rd1");
        $display("[SUM] dms_sol=%0d yuv_v=%0d frm=%0d", dms_sol, yuv_v, frm_cnt);
        $display("[SUM] late/under = %h", dbg4);
        $display("[SUM] rd sol/tlast per frame = %0d/%0d (exp 90/90)",
                 rd_sol_frame, rd_tl_frame);
        $display("[SUM] frame_num=%0d line_num=%0d bursts=%0d pdv_beats=%0d",
                 frame_num, line_num, bursts, pdv_beats);
        $display("[SUM] wr: done=%0d aw=%0d w=%0d bx=%0d fcnt=%0d",
                 done_pulses, aw_cnt, w_cnt, bx_cnt, fw1_frame_cnt);
        // P1：帧完成
        if (frame_num < 6) begin
            $display("[P1-FAIL] frame_num=%0d", frame_num);
            fail_cnt = fail_cnt + 1;
        end
        // P3：诊断等价量
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
        // DDRM：sticky CTRL_ERR
        $display("[DDRM] ctrl_err=%b init_done=%b ready=%b busy=%b",
                 ctrl_err, ctrl_init_done, ctrl_ready, ctrl_busy);
        if (ctrl_err !== 1'b0) begin
            $display("[DDRM-FAIL] sticky CTRL_ERR set");
            fail_cnt = fail_cnt + 1;
        end
        if (fail_cnt == 0)
            $display("[P5-OK] cam1 full-chain all checks passed");
        else
            $display("[P5-FAIL] fail_cnt=%0d", fail_cnt);

        // ================= 慢源实验（1.5x 显示行期供给）=================
        // 显示行 = 550 x 26.9ns ≈ 14.8us；源行 = (486+gap) x 5ns，gap=3958
        // -> 22.2us ≈ 1.5x 显示行期（相机病理：源慢于消费）。
        $display("[SLOW] begin: vs_p=%0d late=%0d fr=%h",
                 vs_p2, late_snap, fr_snap);
        src_gap_beats = 3958;
        repeat (6) @(posedge vsync);
        repeat (2000) @(posedge clk37);
        $display("[SLOW] result: vs_p_prev=%0d vs_p=%0d (exp_fast=%0d)",
                 vs_p1, vs_p2, SLOTS * 550);
        $display("[SLOW] late_delta=%0d fr=%h (drop=%0d rpt=%0d)",
                 late_snap - late_snap0, fr_snap,
                 $signed(fr_snap[31:16]), $signed(fr_snap[15:0]));
        if (vs_p2 < SLOTS * 550) begin
            $display("[SLOW-FAIL] display period shrunk below slot rate");
            fail_cnt = fail_cnt + 1;
        end else
            $display("[SLOW-OK] display period >= slot rate under slow supply");
        $finish;
    end

    initial begin
        #60_000_000;
        $display("[P5-FAIL] watchdog frame_num=%0d dms_sol=%0d frm=%0d",
                 frame_num, dms_sol, frm_cnt);
        $display("[P5-FAIL] wr: done=%0d aw=%0d w=%0d bx=%0d d_st=%0d inframe=%b fcnt=%0d",
                 done_pulses, aw_cnt, w_cnt, bx_cnt,
                 u_fw1.d_st, u_fw1.in_frame, u_fw1.frame_cnt_r);
        $display("[P5-FAIL] wr2: dw=%0d dr=%0d bad=%0d drop=%0d pad=%0d ovf=%0d lnf=%0d ldl=%0d qfull=%b",
                 u_fw1.dw_ptr, u_fw1.dr_ptr, u_fw1.bad_cnt_r, u_fw1.drop_cnt_r,
                 u_fw1.pad_cnt_r, u_fw1.ovf_cnt_r, u_fw1.line_in_frame,
                 u_fw1.last_drop_line_r, u_fw1.q_full);
        $display("[P5-FAIL] pubchain: tog200=%b tog37=%b fw37=%b pubs=%0d ctrl_err=%b",
                 tog200, tog37[2:1], fw_done_37, pubs, ctrl_err);
        $display("[P5-FAIL] rd_arb dbg=%h -> gnt_act=%b gnt=%b lock=%b stuck=%b txn_s0=%0d beat_s0=%0d",
                 rd_arb_dbg, rd_arb_dbg[68], rd_arb_dbg[67:66], rd_arb_dbg[65],
                 rd_arb_dbg[64], rd_arb_dbg[47:32], rd_arb_dbg[15:0]);
        $display("[P5-FAIL] S0: arv=%b arrdy=%b rv=%b rrdy=%b | M: arv=%b arrdy=%b rv=%b rrdy=%b",
                 cdc_m_arvalid, cdc_m_arready, cdc_m_rvalid, cdc_m_rready,
                 m_arvalid, m_arready, m_rvalid, m_rready);
        $display("[P5-FAIL] cdc s: arv=%b arrdy=%b rv=%b rrdy=%b",
                 rd1_arvalid, rd1_arready, rd1_rvalid, rd1_rready);
        $display("[P5-FAIL] reader: state=%h arv=%b rv=%b rrdy=%b err=%h frmcnt=%0d",
                 u_rd1.rd_state, u_rd1.arvalid, u_rd1.rvalid,
                 u_rd1.rready, u_rd1.rd_err, u_rd1.rd_frame_cnt);
        $finish;
    end

endmodule
