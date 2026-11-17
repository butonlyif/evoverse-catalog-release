//=====================================================================
// axi_wr_arb_tb.sv — axi_wr_arb 单元 TB（arbiter-impl-plan.md S2）
// 结构 : 双可编程 master BFM + 512b 存储从端记分板（不用 DDR 行为模型）
//        SVA A1-A10 层次引用 RTL（Q3 定案：SVA 不进 .v）
// 从端 : 默认复现本项目 DDR 的 WVALID-first 契约（见 wvalid 才给 wready）
// 地址 : S1 基址 0x0400_0000 / S0 基址 0x0500_0000（与 ddr_interface.md §10 一致）
//=====================================================================
`timescale 1ns/1ps
module axi_wr_arb_tb;

//---------------------------------------------------------------------
// 时钟/复位
//---------------------------------------------------------------------
logic clk = 1'b0;
always #5 clk = ~clk;                 // 100MHz（单元仿真频率无关）
logic rstn = 1'b0;

// 地址基址（与 ddr_interface.md §10 一致；先声明后使用——vlog 纪律）
localparam logic [32:0] BASE1 = 33'h0_0400_0000;   // S1/cam0
localparam logic [32:0] BASE0 = 33'h0_0500_0000;   // S0/cam1

integer cyc = 0;
always @(posedge clk) cyc = cyc + 1;

//---------------------------------------------------------------------
// BFM 寄存器组（索引 1=S1/cam0，0=S0/cam1）
//---------------------------------------------------------------------
logic [1:0]            awv;
logic [1:0]            wv;
logic [32:0]           awa  [2];
logic [7:0]            awl  [2];
logic [2:0]            aws  [2];
logic [1:0]            awb  [2];
logic [5:0]            awi  [2];
logic [3:0]            awq  [2];
logic [3:0]            awc  [2];
logic                  awlk [2];
logic [511:0]          wd   [2];
logic [63:0]           ws   [2];
logic                  wl   [2];
logic [1:0]            bry;                       // bready，默认 1

//---------------------------------------------------------------------
// DUT
//---------------------------------------------------------------------
wire s1_awready_w, s0_awready_w, s1_wready_w, s0_wready_w;
wire s1_bvalid_w,  s0_bvalid_w;
wire [1:0] s1_bresp_w, s0_bresp_w;
wire [5:0] s1_bid_w,   s0_bid_w;
wire m_awvalid_w;  logic m_awready_r;
wire m_wvalid_w;   logic m_wready_r;
logic m_bvalid_w;  wire m_bready_w;      // stub 过程驱动，须为变量（勿改回 wire）
wire [32:0] m_awaddr_w;  wire [7:0] m_awlen_w;  wire [5:0] m_awid_w;  wire [3:0] m_awqos_w;
wire [511:0] m_wdata_w;  wire [63:0] m_wstrb_w; wire m_wlast_w;
logic [1:0]  m_bresp_w;  logic [5:0] m_bid_w;    // stub 过程驱动，须为变量
wire [68:0] dbg;

axi_wr_arb dut (
    .clk(clk), .rstn(rstn),
    .s1_awvalid(awv[1]), .s1_awready(s1_awready_w), .s1_awaddr(awa[1]),
    .s1_awlen(awl[1]), .s1_awsize(aws[1]), .s1_awburst(awb[1]),
    .s1_awid(awi[1]), .s1_awqos(awq[1]), .s1_awcache(awc[1]), .s1_awlock(awlk[1]),
    .s1_wvalid(wv[1]), .s1_wready(s1_wready_w), .s1_wdata(wd[1]),
    .s1_wstrb(ws[1]), .s1_wlast(wl[1]),
    .s1_bvalid(s1_bvalid_w), .s1_bready(bry[1]), .s1_bresp(s1_bresp_w), .s1_bid(s1_bid_w),
    .s0_awvalid(awv[0]), .s0_awready(s0_awready_w), .s0_awaddr(awa[0]),
    .s0_awlen(awl[0]), .s0_awsize(aws[0]), .s0_awburst(awb[0]),
    .s0_awid(awi[0]), .s0_awqos(awq[0]), .s0_awcache(awc[0]), .s0_awlock(awlk[0]),
    .s0_wvalid(wv[0]), .s0_wready(s0_wready_w), .s0_wdata(wd[0]),
    .s0_wstrb(ws[0]), .s0_wlast(wl[0]),
    .s0_bvalid(s0_bvalid_w), .s0_bready(bry[0]), .s0_bresp(s0_bresp_w), .s0_bid(s0_bid_w),
    .m_awvalid(m_awvalid_w), .m_awready(m_awready_r), .m_awaddr(m_awaddr_w),
    .m_awlen(m_awlen_w), .m_awsize(), .m_awburst(), .m_awid(m_awid_w),
    .m_awqos(m_awqos_w), .m_awcache(), .m_awlock(),
    .m_wvalid(m_wvalid_w), .m_wready(m_wready_r), .m_wdata(m_wdata_w),
    .m_wstrb(m_wstrb_w), .m_wlast(m_wlast_w),
    .m_bvalid(m_bvalid_w), .m_bready(m_bready_w), .m_bresp(m_bresp_w), .m_bid(m_bid_w),
    .dbg(dbg)
);

// 握手脉冲（监控/记分板口径）
wire s1_awfire_w = awv[1] & s1_awready_w;
wire s0_awfire_w = awv[0] & s0_awready_w;
wire s1_wfire_w  = wv[1]  & s1_wready_w;
wire s0_wfire_w  = wv[0]  & s0_wready_w;
wire m_awfire_w  = m_awvalid_w & m_awready_r;
wire m_wfire_w   = m_wvalid_w  & m_wready_r;
wire b_fire_w    = m_bvalid_w  & m_bready_w;

//---------------------------------------------------------------------
// 从端配置旋钮（每用例设置）
//---------------------------------------------------------------------
integer wmode = 1;            // 0=WFIRST 滞后 1=恒高 2=WFIRST+随机间隙 3=beat 后永停
integer awdelay_max = 1;      // awready 延迟 0..max
integer bdelay_cycles = 2;    // wlast→B 延迟
integer wstall_after = 10;    // wmode=3 的停拍点

//---------------------------------------------------------------------
// 从端（DDR target0 stub）
//---------------------------------------------------------------------
logic [7:0]  m_awlen_r;
logic [32:0] m_awaddr_r;
logic [5:0]  m_awid_r;
integer      m_beat = 0;
integer      aw_wait = 0;
integer      wgap = 0;
logic        b_pend = 0;
integer      b_cnt = 0;
integer      slave_err = 0;
logic        aw_ok = 1'b0;        // 当前突发地址已捕获
logic        wlast_seen = 1'b0;   // wlast 已入队，待地址提交
bit [511:0]  wbuf [256];             // 当前突发写数据 FIFO（建模 DDR 写缓存）
integer      ci;

// 存储模型 + 记分板
bit [511:0]      mem  [logic [32:0]];
bit [511:0]      exp1 [logic [32:0]];
bit [511:0]      exp0 [logic [32:0]];

//---------------------------------------------------------------------
// 从端单进程：AW 捕获 + W FIFO + 按序提交 + B 应答
// WVALID-first 契约下 M 口 W beat 可早于 AW 捕获到达（T9/T11 实测），
// beat 先入 wbuf，地址捕获且 wlast 到达后按序提交 mem（同真实 DDR 写缓存）
//---------------------------------------------------------------------
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        m_awready_r <= 1'b0; m_wready_r <= 1'b0;
        aw_wait <= 0; wgap <= 0;
        m_awlen_r <= 8'd0; m_awaddr_r <= 33'd0; m_awid_r <= 6'd0;
        m_beat <= 0; b_pend <= 1'b0; b_cnt <= 0;
        m_bvalid_w <= 1'b0; m_bresp_w <= 2'b00; m_bid_w <= 6'd0;
        aw_ok <= 1'b0; wlast_seen <= 1'b0;
    end else begin
        // ---- 突发提交：地址已捕获且 wlast 已入队 → wbuf 按序写 mem ----
        if (aw_ok && wlast_seen) begin
            for (ci = 0; ci < m_beat; ci = ci + 1)
                mem[m_awaddr_r + 64*ci] = wbuf[ci];
            if (m_beat != m_awlen_r + 1) begin
                $display("[SLV][ERR] beat 数 %0d != awlen+1 %0d @%0t", m_beat, m_awlen_r+1, $time);
                slave_err = slave_err + 1;
            end
            m_beat <= 0; wlast_seen <= 1'b0; aw_ok <= 1'b0;
            b_pend <= 1'b1; b_cnt <= bdelay_cycles;
            m_bresp_w <= 2'b00; m_bid_w <= m_awid_r;    // OKAY（§5.5 恒 OKAY）
        end
        // ---- AW 通道 ----
        if (m_awvalid_w && m_awready_r) begin           // fire
            m_awready_r <= 1'b0;
            aw_wait     <= $urandom_range(0, awdelay_max);
        end else if (!m_awready_r && m_awvalid_w) begin
            if (aw_wait == 0) begin
                m_awready_r <= 1'b1;
                m_awlen_r   <= m_awlen_w;
                m_awaddr_r  <= m_awaddr_w;
                m_awid_r    <= m_awid_w;
                aw_ok       <= 1'b1;                    // 地址捕获，突发开窗
            end else aw_wait <= aw_wait - 1;
        end
        // ---- W 通道（WVALID-first：见 valid 滞后给 ready，与 AW 无关）----
        if (m_wvalid_w && m_wready_r) begin             // fire
            wbuf[m_beat] = m_wdata_w;
            if (m_wlast_w) wlast_seen <= 1'b1;
            if (wmode == 1) m_wready_r <= 1'b1;         // 恒高模式
            else begin
                if (wmode == 2) wgap <= $urandom_range(0, 3);
                m_wready_r <= 1'b0;                     // WFIRST：fire 后收回，见 valid 再给
            end
            m_beat <= m_beat + 1;
        end else if (!m_wready_r && m_wvalid_w) begin
            if (wmode == 3 && m_beat >= wstall_after)   // 永停（T10c：W 永不到达）
                m_wready_r <= 1'b0;
            else if (wgap != 0) wgap <= wgap - 1;
            else m_wready_r <= 1'b1;                    // 滞后 1 拍给 ready
        end
        // ---- B 应答 ----
        if (b_pend && !m_bvalid_w) begin
            if (b_cnt == 0) m_bvalid_w <= 1'b1;
            else b_cnt <= b_cnt - 1;
        end
        if (m_bvalid_w && m_bready_w) begin
            m_bvalid_w <= 1'b0;
            b_pend     <= 1'b0;
        end
    end
end

integer b_rise1, b_rise0, awfire1, awfire0;   // B/AW 上升沿累计（先声明后使用）

//---------------------------------------------------------------------
// BFM 任务（DA1 自检：valid 置位后未握手不得改载荷——由流程保证）
//---------------------------------------------------------------------
function automatic logic [511:0] wpat(int p, int txn, int i);
    wpat = {476'd0, p[3:0], txn[15:0], i[15:0]};
endfunction

integer txn_no [2];
initial begin txn_no[1] = 0; txn_no[0] = 0; end

task automatic send_aw(int p, logic [32:0] a, int nb, logic [5:0] id);
begin
    @(posedge clk);
    awv[p] <= 1'b1; awa[p] <= a; awl[p] <= nb[7:0] - 8'd1; aws[p] <= 3'b110;
    awb[p] <= 2'b01; awi[p] <= id; awq[p] <= 4'h1; awc[p] <= 4'h0; awlk[p] <= 1'b0;
    forever begin
        @(posedge clk);
        if ((p == 1 && s1_awready_w) || (p == 0 && s0_awready_w)) break;
    end
    awv[p] <= 1'b0;
end
endtask

task automatic send_w(int p, int nb, int pre_delay, int gap);
int i;
logic [511:0] d;
begin
    repeat (pre_delay) @(posedge clk);
    for (i = 0; i < nb; i = i + 1) begin
        d = wpat(p, txn_no[p], i);
        wv[p] <= 1'b1; wd[p] <= d; ws[p] <= 64'hFFFFFFFFFFFFFFFF;
        wl[p] <= (i == nb-1);
        forever begin
            @(posedge clk);
            if ((p == 1 && s1_wready_w) || (p == 0 && s0_wready_w)) break;
        end
        wv[p] <= 1'b0;
        if (i < nb-1) repeat (gap) @(posedge clk);
    end
    txn_no[p] = txn_no[p] + 1;
end
endtask

task automatic send_txn(int p, logic [32:0] a, int nb, int w_pre, int gap);
integer br;
begin
    br = (p == 1) ? b_rise1 : b_rise0;
    fork
        send_aw(p, a, nb, (p == 1) ? 6'h11 : 6'h22);
        send_w(p, nb, w_pre, gap);
    join
    // 源侧契约（§2 单 outstanding）：本事务 B 到达后才发起下一事务，
    // 防止 N+1 的 W beat 越过 N 的 WLAST 注入当前锁内流
    if (p == 1) wait (b_rise1 > br);
    else        wait (b_rise0 > br);
end
endtask

task automatic do_reset();
begin
    rstn = 1'b0;
    awv = 2'b00; wv = 2'b00; bry = 2'b11;
    repeat (5) @(negedge clk);            // 负沿释放复位，避免与 posedge 采样竞态
    rstn = 1'b1;
    @(negedge clk);
end
endtask

//---------------------------------------------------------------------
// 监控/记分板/A1 A2 A3 A5 A6 检查
//---------------------------------------------------------------------
integer wbeat   [2];      // 每口事务内 beat 计数
logic [32:0] awbase [2];
logic [5:0]  awid_rec [2];
integer s_wfire_cnt, m_wfire_cnt, m_aw_open;
integer err_a1, err_a2, err_a5, err_lat;
logic   bprev1, bprev0;
logic   b_prev_m = 1'b0;
integer t_aw, t_maw, t_sb, t_mb;
logic   t1_meas = 0;

initial begin
    wbeat[1] = 0; wbeat[0] = 0; awbase[1] = 33'd0; awbase[0] = 33'd0;
    awid_rec[1] = 6'd0; awid_rec[0] = 6'd0;
    s_wfire_cnt = 0; m_wfire_cnt = 0; m_aw_open = 0;
    b_rise1 = 0; b_rise0 = 0; awfire1 = 0; awfire0 = 0;
    err_a1 = 0; err_a2 = 0; err_a5 = 0; err_lat = 0;
    bprev1 = 0; bprev0 = 0;
end

always @(posedge clk) begin
    if (rstn) begin
        // ---- 源侧记分板与事务轮廓 ----
        if (s1_awfire_w) begin
            awbase[1] = awa[1]; awid_rec[1] = awi[1]; wbeat[1] = 0; awfire1 = awfire1 + 1;
        end
        if (s0_awfire_w) begin
            awbase[0] = awa[0]; awid_rec[0] = awi[0]; wbeat[0] = 0; awfire0 = awfire0 + 1;
        end
        if (s1_wfire_w) begin
            exp1[awbase[1] + 64*wbeat[1]] = wd[1];
            wbeat[1] = wbeat[1] + 1;
            s_wfire_cnt = s_wfire_cnt + 1;
            if (wl[1] && (wbeat[1] != awl[1] + 1)) begin
                $display("[MON][ERR] S1 beat 数 %0d != awlen+1 %0d", wbeat[1], awl[1]+1);
                slave_err = slave_err + 1;
            end
            if (wl[1]) wbeat[1] = 0;
        end
        if (s0_wfire_w) begin
            exp0[awbase[0] + 64*wbeat[0]] = wd[0];
            wbeat[0] = wbeat[0] + 1;
            s_wfire_cnt = s_wfire_cnt + 1;
            if (wl[0] && (wbeat[0] != awl[0] + 1)) begin
                $display("[MON][ERR] S0 beat 数 %0d != awlen+1 %0d", wbeat[0], awl[0]+1);
                slave_err = slave_err + 1;
            end
            if (wl[0]) wbeat[0] = 0;
        end
        // ---- M 口 ----
        if (m_wfire_w) m_wfire_cnt = m_wfire_cnt + 1;
        if (m_awfire_w) begin
            if (m_aw_open != 0) begin
                $display("[MON][ERR][A2] 前突发未收完即收第二条 AW @%0d", cyc);
                err_a2 = err_a2 + 1;
            end
            m_aw_open = 1;
        end
        if (m_wlast_w && m_wfire_w) m_aw_open = 0;
        // ---- A5：双请授予必授 ~last_q（§5.1 req_alt 优先）----
        //（不比较相邻双请授予的翻转：败者补位授予同样翻转 last_q，会比较误报）
        if (dut.grant_en && awv[1] && awv[0]) begin
            if (dut.win === dut.last_q) begin
                $display("[MON][ERR][A5] 双请授予选中 last 口 @%0d", cyc);
                err_a5 = err_a5 + 1;
            end
        end
        // ---- A1：M 口载荷恒属授权口 ----
        if (m_awvalid_w && dut.lock_q) begin
            if (dut.gnt_q) begin
                if (m_awaddr_w !== awbase[1] || m_awid_w !== awid_rec[1]
                    || m_awlen_w !== awl[1]) begin
                    $display("[MON][ERR][A1] M 口载荷非 S1 @%0d", cyc);
                    err_a1 = err_a1 + 1;
                end
            end else begin
                if (m_awaddr_w !== awbase[0] || m_awid_w !== awid_rec[0]
                    || m_awlen_w !== awl[0]) begin
                    $display("[MON][ERR][A1] M 口载荷非 S0 @%0d", cyc);
                    err_a1 = err_a1 + 1;
                end
            end
        end
        // ---- A3 部分：B 上升计数 + bid 归属 ----
        if (s1_bvalid_w && !bprev1) begin
            b_rise1 = b_rise1 + 1;
            if (s1_bid_w !== awid_rec[1]) begin
                $display("[MON][ERR][T5] S1 收到错误 bid=%0h", s1_bid_w);
                slave_err = slave_err + 1;
            end
            if (s1_bresp_w !== 2'b00) begin
                $display("[MON][ERR][T5] S1 bresp=%0h", s1_bresp_w);
                slave_err = slave_err + 1;
            end
        end
        if (s0_bvalid_w && !bprev0) begin
            b_rise0 = b_rise0 + 1;
            if (s0_bid_w !== awid_rec[0]) begin
                $display("[MON][ERR][T5] S0 收到错误 bid=%0h", s0_bid_w);
                slave_err = slave_err + 1;
            end
        end
        // ---- T1 延迟测量（bprev 更新前采样，上升沿判定才有效）----
        if (t1_meas) begin
            if (s1_awfire_w && t_aw < 0) t_aw = cyc;
            if (m_awfire_w && t_maw < 0) t_maw = cyc;
            if (s1_bvalid_w && !bprev1 && t_sb < 0) t_sb = cyc;
            if (m_bvalid_w && !b_prev_m && t_mb < 0) t_mb = cyc;
        end
        bprev1 = s1_bvalid_w; bprev0 = s0_bvalid_w;
        // ---- A6：锁释放拍两侧握手计数守恒 ----
        if (dut.lock_release) begin
            if (s_wfire_cnt != m_wfire_cnt) begin
                $display("[MON][ERR][A6] 释放拍源侧 %0d != M 口 %0d", s_wfire_cnt, m_wfire_cnt);
                slave_err = slave_err + 1;
            end
        end
    end
end
always @(posedge clk) b_prev_m <= m_bvalid_w;

// A6 全程松界（skid 在途容 1 拍）
always @(posedge clk) begin
    if (rstn && ((s_wfire_cnt > m_wfire_cnt + 1) || (m_wfire_cnt > s_wfire_cnt + 1))) begin
        $display("[MON][ERR][A6] 在途偏差 >1：源 %0d M %0d @%0d", s_wfire_cnt, m_wfire_cnt, cyc);
        slave_err = slave_err + 1;
    end
end

//---------------------------------------------------------------------
// SVA A4/A7/A8/A9/A10（层次引用 RTL 内部状态）
//---------------------------------------------------------------------
integer err_sva = 0;

property p_a4a; @(posedge clk) disable iff (!rstn)
    (dut.lock_q &&  dut.gnt_q) |-> (!s0_awready_w && !s0_wready_w && !s0_bvalid_w);
endproperty
property p_a4b; @(posedge clk) disable iff (!rstn)
    (dut.lock_q && !dut.gnt_q) |-> (!s1_awready_w && !s1_wready_w && !s1_bvalid_w);
endproperty
property p_aw_hold; @(posedge clk) disable iff (!rstn)
    (m_awvalid_w && !m_awready_r) |=> (m_awvalid_w && $stable(m_awaddr_w) &&
        $stable(m_awlen_w) && $stable(m_awid_w) && $stable(m_awqos_w));
endproperty
property p_w_hold; @(posedge clk) disable iff (!rstn)
    (m_wvalid_w && !m_wready_r) |=> (m_wvalid_w && $stable(m_wdata_w) &&
        $stable(m_wstrb_w) && $stable(m_wlast_w));
endproperty
property p_a8; @(posedge clk) disable iff (!rstn)
    (!dut.lock_q) |-> (!m_awvalid_w && !m_wvalid_w && !m_bvalid_w);
endproperty
property p_a9; @(posedge clk) disable iff (!rstn)
    ((m_bvalid_w && m_bready_w && dut.lock_q && !dut.b_seen_q) |->
        (dut.w_done_q || (m_wvalid_w && m_wready_r && m_wlast_w)));
endproperty
property p_a10; @(posedge clk) disable iff (!rstn)
    ((dut.lock_q && $stable(dut.lock_q)) |-> ($stable(dut.gnt_q) && $stable(dut.last_q)));
endproperty

A4a: assert property (p_a4a) else begin
    $display("[SVA][ERR][A4] S1 锁定期 S0 泄漏 @%0t", $time); err_sva++; end
A4b: assert property (p_a4b) else begin
    $display("[SVA][ERR][A4] S0 锁定期 S1 泄漏 @%0t", $time); err_sva++; end
A7a: assert property (p_aw_hold) else begin
    $display("[SVA][ERR][A7] AW valid-hold 违反 @%0t", $time); err_sva++; end
A7w: assert property (p_w_hold) else begin
    $display("[SVA][ERR][A7] W valid-hold 违反 @%0t", $time); err_sva++; end
A8:  assert property (p_a8) else begin
    $display("[SVA][ERR][A8] 空闲泄漏 aw=%b w=%b b=%b @%0t",
             m_awvalid_w, m_wvalid_w, m_bvalid_w, $time); err_sva++; end
A9:  assert property (p_a9) else begin
    $display("[SVA][ERR][A9] b_fire 时 W 未完成 @%0t", $time); err_sva++; end
A10: assert property (p_a10) else begin
    $display("[SVA][ERR][A10] 锁定期 gnt/last 不稳 @%0t", $time); err_sva++; end

//---------------------------------------------------------------------
// 记分板核对与统计
//---------------------------------------------------------------------
task automatic check_scoreboard(input string tag);
integer mism, nexp;
begin
    mism = 0; nexp = 0;
    foreach (exp1[k]) begin
        nexp = nexp + 1;
        if (!mem.exists(k)) begin
            mism = mism + 1;
            $display("[SB][ERR][%s] 缺写 @%h", tag, k);
        end else if (mem[k] !== exp1[k]) begin
            mism = mism + 1;
            $display("[SB][ERR][%s] 数据不符 @%h", tag, k);
        end
    end
    foreach (exp0[k]) begin
        nexp = nexp + 1;
        if (!mem.exists(k)) begin
            mism = mism + 1;
            $display("[SB][ERR][%s] 缺写 @%h", tag, k);
        end else if (mem[k] !== exp0[k]) begin
            mism = mism + 1;
            $display("[SB][ERR][%s] 数据不符 @%h", tag, k);
        end
    end
    if (mem.size() != nexp) begin
        mism = mism + 1;
        $display("[SB][ERR][%s] mem 条目 %0d != 期望 %0d（重复/多写）", tag, mem.size(), nexp);
    end
    if (mism != 0) slave_err = slave_err + mism;
end
endtask

task automatic clear_models();
begin
    mem.delete(); exp1.delete(); exp0.delete();
    txn_no[1] = 0; txn_no[0] = 0;
end
endtask

//---------------------------------------------------------------------
// dbg 字段
//---------------------------------------------------------------------
wire [15:0] dbg_txn1 = dbg[63:48];
wire [15:0] dbg_txn0 = dbg[47:32];
wire [15:0] dbg_beat1 = dbg[31:16];
wire [15:0] dbg_beat0 = dbg[15:0];

//---------------------------------------------------------------------
// 用例
//---------------------------------------------------------------------
integer base_err;

task automatic fail_if(input string tag, input integer limit);
begin
    if (slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat > limit)
        $display("[TEST][%s] FAIL（累计错 %0d）", tag,
                 slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat);
    else
        $display("[TEST][%s] PASS", tag);
end
endtask

// T7：复位后两口同拍首争用 → 必授 S1（§5.1 tie-break，last=0 有意安排）
// 结构：两口各自 AW→W 串行链并发（S0 的 AW 等 S1 收尾后再 ready，不互等）
task automatic t7();
logic g0;
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5;
    clear_models();
    wmode = 1; awdelay_max = 0; bdelay_cycles = 2;
    fork
        begin
            wait (dut.lock_q == 1'b1);            // 首锁建立拍采样授予归属
            g0 = dut.gnt_q;
        end
        begin send_aw(1, BASE1, 16, 6'h11); send_w(1, 16, 0, 0); end
        begin send_aw(0, BASE0, 16, 6'h22); send_w(0, 16, 0, 0); end
    join
    if (g0 !== 1'b1) begin
        $display("[TEST][T7][ERR] 首争用授予 %b != S1", g0);
        slave_err = slave_err + 1;
    end
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    check_scoreboard("T7");
    fail_if("T7", base_err);
end
endtask

// T1：单口基线 + 延迟 ≤ 直连+3 拍
task automatic t1();
integer lat_m, lat_s;
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5;
    clear_models();
    wmode = 1; awdelay_max = 0; bdelay_cycles = 3;
    t_aw = -1; t_maw = -1; t_sb = -1; t_mb = -1; t1_meas = 1;
    send_txn(1, BASE1, 64, 0, 0);
    wait (dut.lock_q == 1'b0);            // B 收尾后再停表（t_sb/t_mb 捕获需要窗口）
    t1_meas = 0;
    if (t_aw < 0 || t_maw < 0 || t_sb < 0 || t_mb < 0) begin
        $display("[TEST][T1][ERR] 延迟采样缺失 aw=%0d maw=%0d sb=%0d mb=%0d", t_aw, t_maw, t_sb, t_mb);
        err_lat = err_lat + 1;
    end else begin
        lat_m = t_sb - t_aw;
        lat_s = t_mb - t_maw;
        $display("[T1] master 视角延迟 %0d 拍，DDR 视角 %0d 拍，仲裁开销 %0d 拍", lat_m, lat_s, lat_m - lat_s);
        if (lat_m - lat_s > 3) begin
            $display("[TEST][T1][ERR] 延迟开销 %0d > 3 拍", lat_m - lat_s);
            err_lat = err_lat + 1;
        end
    end
    send_txn(1, BASE1 + 64*64, 56, 0, 0);
    send_txn(1, BASE1 + 64*120, 32, 0, 0);
    send_txn(1, BASE1 + 64*152, 28, 0, 0);
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    check_scoreboard("T1");
    fail_if("T1", base_err);
end
endtask

// T2：双口并发争用（RR 交替由 A5 监控）
task automatic t2();
integer r;
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5;
    clear_models();
    wmode = 1; awdelay_max = 0; bdelay_cycles = 2;
    for (r = 0; r < 3; r = r + 1) begin
        fork
            send_txn(1, BASE1 + 64*r*128, 64, 0, 0);
            send_txn(0, BASE0 + 64*r*128, 32, 0, 0);
        join
    end
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    check_scoreboard("T2");
    fail_if("T2", base_err);
end
endtask

// T3：随机背压（wready 间隙 + awready 延迟）；看门狗不得触发
task automatic t3();
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5;
    clear_models();
    wmode = 2; awdelay_max = 4; bdelay_cycles = 6;
    fork
        send_txn(1, BASE1, 56, 0, 3);
        send_txn(0, BASE0, 28, 2, 5);
    join
    send_txn(1, BASE1 + 64*64, 28, 4, 0);
    send_txn(0, BASE0 + 64*64, 64, 1, 2);
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    if (dut.stuck_q) begin
        $display("[TEST][T3][ERR] 随机背压触发看门狗");
        slave_err = slave_err + 1;
    end
    check_scoreboard("T3");
    fail_if("T3", base_err);
end
endtask

// T4：最坏交错——S1 长突发进行中 S0 请求嵌入（原子性 A2 + 记分板）
task automatic t4();
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5;
    clear_models();
    wmode = 1; awdelay_max = 0; bdelay_cycles = 2;
    fork
        begin
            send_aw(1, BASE1, 64, 6'h11);
            send_w(1, 64, 0, 0);
        end
        begin
            repeat (8) @(posedge clk);       // S1 已锁定后 S0 才请求
            send_txn(0, BASE0, 32, 0, 0);
        end
    join
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    check_scoreboard("T4");
    fail_if("T4", base_err);
end
endtask

// T5：响应路由（bid/bresp 归属，监控全程检查；b_rise 为全程累计，查增量）
task automatic t5();
integer br1b, br0b;
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5;
    br1b = b_rise1; br0b = b_rise0;
    clear_models();
    wmode = 1; awdelay_max = 2; bdelay_cycles = 5;
    send_txn(1, BASE1, 64, 0, 0);
    send_txn(0, BASE0, 28, 0, 0);
    send_txn(1, BASE1 + 64*64, 28, 0, 0);
    send_txn(0, BASE0 + 64*64, 64, 0, 0);
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    if ((b_rise1 - br1b) != 2 || (b_rise0 - br0b) != 2) begin
        $display("[TEST][T5][ERR] B 增量 S1=%0d S0=%0d != 2/2", b_rise1 - br1b, b_rise0 - br0b);
        slave_err = slave_err + 1;
    end
    check_scoreboard("T5");
    fail_if("T5", base_err);
end
endtask

// T6：混合长短事务 + dbg 计数对账（RTL 计数全程累计不清零，查增量）
task automatic t6();
integer dt1, dt0, db1, db0;
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5;
    clear_models();
    wmode = 2; awdelay_max = 1; bdelay_cycles = 3;
    dt1 = dbg_txn1; dt0 = dbg_txn0; db1 = dbg_beat1; db0 = dbg_beat0;
    send_txn(1, BASE1, 64, 0, 0);
    send_txn(0, BASE0, 28, 0, 0);
    send_txn(1, BASE1 + 64*64, 56, 0, 0);
    send_txn(0, BASE0 + 64*64, 32, 0, 0);
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    if ((dbg_txn1 - dt1) != 2 || (dbg_txn0 - dt0) != 2) begin
        $display("[TEST][T6][ERR] dbg txn 增量 S1=%0d S0=%0d != 2/2", dbg_txn1 - dt1, dbg_txn0 - dt0);
        slave_err = slave_err + 1;
    end
    if ((dbg_beat1 - db1) != 120 || (dbg_beat0 - db0) != 60) begin
        $display("[TEST][T6][ERR] dbg beat 增量 %0d/%0d != 120/60", dbg_beat1 - db1, dbg_beat0 - db0);
        slave_err = slave_err + 1;
    end
    check_scoreboard("T6");
    fail_if("T6", base_err);
end
endtask

// T9：W 早到（授予前 k 拍拉 WVALID 并保持，DA1）
// 注：轮间必须等 S1 本轮 B 到达（§2 单 outstanding），否则下一轮 beat0 会在
//     w_done_q 置位前的一拍窗内被收进 skid，随 wlast 之后漏到 M 口（实测幽灵拍）
task automatic t9();
integer k, r, br1;
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5;
    clear_models();
    wmode = 1; awdelay_max = 0; bdelay_cycles = 2;
    for (r = 0; r < 3; r = r + 1) begin
        k = 1 + 2*r;                          // 1/3/5 拍
        br1 = b_rise1;
        fork
            begin
                send_txn(0, BASE0 + 64*r*128, 32, 0, 0);   // S0 先占锁
            end
            begin
                // S1 的 W 比 AW 早 k 拍（先 W 后 AW，横跨 S0 锁定期）
                fork
                    send_w(1, 28, 0, 0);
                    begin
                        repeat (k) @(posedge clk);
                        send_aw(1, BASE1 + 64*r*128, 28, 6'h11);
                    end
                join
                wait (b_rise1 > br1);         // 本轮 B 到达后才进入下一轮（§2）
            end
        join
    end
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    check_scoreboard("T9");
    fail_if("T9", base_err);
end
endtask

// T11：WVALID-first 时序专项（P0 场景；wf 滞后模式 = 1 beat/2 拍 + 同拍清载）
task automatic t11();
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5;
    clear_models();
    wmode = 0; awdelay_max = 0; bdelay_cycles = 2;
    send_txn(1, BASE1, 64, 0, 0);
    send_txn(0, BASE0, 28, 0, 0);
    send_txn(1, BASE1 + 64*64, 56, 3, 0);
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    check_scoreboard("T11");
    fail_if("T11", base_err);
end
endtask

// T10：看门狗边界
//   a) B 延迟 4000 < 4096：不触发
//   b) B 延迟 4200 > 4096：触发 sticky，事务仍完成、计数可读
//   c) W 中途永停：锁保持至复位（P1-1 生命周期）
task automatic t10();
integer dt1, db1;
begin
    // ---- a) 4000 拍不触发 ----
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5;
    clear_models();
    wmode = 1; awdelay_max = 0; bdelay_cycles = 4000;
    send_txn(1, BASE1, 16, 0, 0);
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    if (dut.stuck_q) begin
        $display("[TEST][T10a][ERR] 4000 拍延迟误触发看门狗");
        slave_err = slave_err + 1;
    end
    check_scoreboard("T10a");
    fail_if("T10a", base_err);

    // ---- b) 4200 拍触发 sticky，事务完成、计数可读（dbg 累计，查增量）----
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5;
    clear_models();
    bdelay_cycles = 4200;
    dt1 = dbg_txn1; db1 = dbg_beat1;
    send_txn(1, BASE1, 16, 0, 0);
    wait (dut.stuck_q == 1'b1);
    $display("[T10b] 看门狗在 B 到达前触发（sticky 置位）");
    wait (dut.lock_q == 1'b0);                    // B 最终到达，正常收尾释放
    repeat (4) @(posedge clk);
    if (!dut.stuck_q) begin
        $display("[TEST][T10b][ERR] sticky 被清除");
        slave_err = slave_err + 1;
    end
    if ((dbg_txn1 - dt1) != 1 || (dbg_beat1 - db1) != 16) begin
        $display("[TEST][T10b][ERR] 计数不可读 txn增量=%0d beat增量=%0d", dbg_txn1 - dt1, dbg_beat1 - db1);
        slave_err = slave_err + 1;
    end
    check_scoreboard("T10b");
    fail_if("T10b", base_err);

    // ---- c) W 永不到达：锁保持至复位（先复位清 sticky）----
    do_reset();
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5;
    clear_models();
    wmode = 3; wstall_after = 10; bdelay_cycles = 2;
    // 事务线程会因 W 永停挂起（预期），后台运行不阻塞主流程
    fork send_txn(1, BASE1, 64, 0, 0); join_none
    repeat (6000) @(posedge clk);                 // > 4096 看门狗窗
    if (!dut.stuck_q) begin
        $display("[TEST][T10c][ERR] W 永停未触发看门狗");
        slave_err = slave_err + 1;
    end
    if (dut.lock_q != 1'b1) begin
        $display("[TEST][T10c][ERR] 锁未保持（应保持至复位）");
        slave_err = slave_err + 1;
    end
    $display("[T10c] 部分完成可读：beat=%0d（10 拍后停）txn=%0d", dbg_beat1, dbg_txn1);
    if (dbg_beat1 != 16'd10) begin
        $display("[TEST][T10c][ERR] 部分完成 beat 计数 %0d != 10", dbg_beat1);
        slave_err = slave_err + 1;
    end
    do_reset();
    if (dut.stuck_q || dut.lock_q) begin
        $display("[TEST][T10c][ERR] 复位未清 sticky/锁");
        slave_err = slave_err + 1;
    end
    fail_if("T10c", base_err);
end
endtask

//---------------------------------------------------------------------
// 调度与汇总
//---------------------------------------------------------------------
initial begin
    $timeformat(-9, 0, " ns", 10);   // %0t 以 ns 显示
    $display("==== axi_wr_arb 单元 TB 开始 ====");
    do_reset();
    t7();    // 复位后首争用（须最先，吃新复位状态）
    t1();
    t2();
    t3();
    t4();
    t5();
    t6();
    t9();
    t11();
    t10();   // 看门狗会置 sticky，放最后
    $display("==== 汇总：slave_err=%0d sva=%0d a1=%0d a2=%0d a5=%0d lat=%0d ====",
             slave_err, err_sva, err_a1, err_a2, err_a5, err_lat);
    if (slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat == 0)
        $display("==== ALL TESTS PASS ====");
    else
        $display("==== TESTS FAILED ====");
    $finish;
end

// 全局看门狗（TB 自身防挂死）
initial begin
    #40_000_000;   // 40ms 仿真墙钟
    $display("[TB][FATAL] 全局超时");
    $finish;
end

endmodule
