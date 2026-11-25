//=====================================================================
// axi_rd_arb_tb.sv — axi_rd_arb 单元 TB（arbiter.md §205 约定）
// 结构 : 双可编程 master BFM + 512b 存储从端记分板（不用 DDR 行为模型）
//        SVA 层次引用 RTL（Q3 定案：SVA 不进 .v）
// 从端 : 可编程 rvalid 节奏（恒流/随机间隙/中途永停）
// 数据 : d(a,id,i) = {457'd0, a[32:0], id[5:0], i[15:0]}——从端按 M 口捕获
//        的 araddr/arid 生成，BFM 按自身请求预算，路由错/载荷错必然失配
// 地址 : S1 基址 0x0400_0000 / S0 基址 0x0500_0000（与 ddr_interface.md §10 一致）
//=====================================================================
`timescale 1ns/1ps
module axi_rd_arb_tb;

//---------------------------------------------------------------------
// 时钟/复位
//---------------------------------------------------------------------
logic clk = 1'b0;
always #5 clk = ~clk;                 // 100MHz（单元仿真频率无关）
logic rstn = 1'b0;

localparam logic [32:0] BASE1 = 33'h0_0400_0000;   // S1/cam0
localparam logic [32:0] BASE0 = 33'h0_0500_0000;   // S0/cam1

integer cyc = 0;
always @(posedge clk) cyc = cyc + 1;

//---------------------------------------------------------------------
// BFM 寄存器组（索引 1=S1/cam0，0=S0/cam1）
//---------------------------------------------------------------------
logic [1:0]   arv;
logic [32:0]  ara  [2];
logic [7:0]   arl  [2];
logic [2:0]   ars  [2];
logic [1:0]   arb  [2];
logic [5:0]   ari  [2];
logic [3:0]   arq  [2];
logic [3:0]   arc  [2];
logic         arlk [2];
logic [1:0]   rry;                    // rready，BFM 任务驱动
// BFM/从端旋钮（先声明后使用——vlog 纪律）
integer       rrymode = 0;            // 0=恒 ready 1=每 3 拍让 1 拍
integer       rry_hold_at = -1;       // 指定 beat 序号前拖 rready（末拍节流专项）
integer       rry_hold_cyc = 0;       // 拖拍数
integer       r1_base = 0, r0_base = 0;
integer       rl_rise1 = 0, rl_rise0 = 0, arfire1 = 0, arfire0 = 0;

//---------------------------------------------------------------------
// DUT
//---------------------------------------------------------------------
wire s1_arready_w, s0_arready_w;
wire s1_rvalid_w,  s0_rvalid_w;
wire [511:0] s1_rdata_w, s0_rdata_w;
wire [1:0]   s1_rresp_w, s0_rresp_w;
wire s1_rlast_w, s0_rlast_w;
wire [5:0]   s1_rid_w, s0_rid_w;
wire m_arvalid_w;  logic m_arready_r;   // 从端过程驱动，须为变量
wire [32:0] m_araddr_w;  wire [7:0] m_arlen_w;  wire [5:0] m_arid_w;
wire [3:0]  m_arqos_w;
logic m_rvalid_w;                       // 从端过程驱动（须为变量，勿改回 wire）
wire  m_rready_w;
logic [511:0] m_rdata_w;  logic [1:0] m_rresp_w;
logic  m_rlast_w;         logic [5:0] m_rid_w;
wire [68:0] dbg;

axi_rd_arb dut (
    .clk(clk), .rstn(rstn),
    .s1_arvalid(arv[1]), .s1_arready(s1_arready_w), .s1_araddr(ara[1]),
    .s1_arlen(arl[1]), .s1_arsize(ars[1]), .s1_arburst(arb[1]),
    .s1_arid(ari[1]), .s1_arqos(arq[1]), .s1_arcache(arc[1]), .s1_arlock(arlk[1]),
    .s1_rvalid(s1_rvalid_w), .s1_rready(rry[1]), .s1_rdata(s1_rdata_w),
    .s1_rresp(s1_rresp_w), .s1_rlast(s1_rlast_w), .s1_rid(s1_rid_w),
    .s0_arvalid(arv[0]), .s0_arready(s0_arready_w), .s0_araddr(ara[0]),
    .s0_arlen(arl[0]), .s0_arsize(ars[0]), .s0_arburst(arb[0]),
    .s0_arid(ari[0]), .s0_arqos(arq[0]), .s0_arcache(arc[0]), .s0_arlock(arlk[0]),
    .s0_rvalid(s0_rvalid_w), .s0_rready(rry[0]), .s0_rdata(s0_rdata_w),
    .s0_rresp(s0_rresp_w), .s0_rlast(s0_rlast_w), .s0_rid(s0_rid_w),
    .m_arvalid(m_arvalid_w), .m_arready(m_arready_r), .m_araddr(m_araddr_w),
    .m_arlen(m_arlen_w), .m_arsize(), .m_arburst(), .m_arid(m_arid_w),
    .m_arqos(m_arqos_w), .m_arcache(), .m_arlock(),
    .m_rvalid(m_rvalid_w), .m_rready(m_rready_w), .m_rdata(m_rdata_w),
    .m_rresp(m_rresp_w), .m_rlast(m_rlast_w), .m_rid(m_rid_w),
    .dbg(dbg)
);

// 握手脉冲（监控/记分板口径）
wire s1_rfire_w = s1_rvalid_w & rry[1];
wire s0_rfire_w = s0_rvalid_w & rry[0];
wire m_arfire_w = m_arvalid_w & m_arready_r;
wire m_rfire_w  = m_rvalid_w  & m_rready_w;

//---------------------------------------------------------------------
// 从端配置旋钮（每用例设置）
//---------------------------------------------------------------------
integer armode = 0;           // arready 延迟 0..armode
integer rsmode = 1;           // 1=恒流 2=随机间隙 3=beat 后永停
integer rstall_after = 10;    // rsmode=3 的停拍点

//---------------------------------------------------------------------
// 从端（DDR target1 stub）：AR 捕获 + 按捕获载荷回流 R 突发
//---------------------------------------------------------------------
logic [7:0]  m_arlen_r;
logic [32:0] m_araddr_r;
logic [5:0]  m_arid_r;
integer      m_beat = 0;
integer      ar_wait = 0;
integer      rgap = 0;
logic        ar_ok = 1'b0;
integer      slave_err = 0;

function automatic logic [511:0] rpat(logic [32:0] a, logic [5:0] id, int i);
    rpat = {457'd0, a, id, i[15:0]};
endfunction

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        m_arready_r <= 1'b0; m_rvalid_w <= 1'b0;
        ar_wait <= 0; rgap <= 0;
        m_arlen_r <= 8'd0; m_araddr_r <= 33'd0; m_arid_r <= 6'd0;
        m_beat <= 0; ar_ok <= 1'b0;
    end else begin
        // ---- AR 通道 ----
        if (m_arvalid_w && m_arready_r) begin           // fire
            m_arready_r <= 1'b0;
            ar_wait     <= $urandom_range(0, armode);
        end else if (!m_arready_r && m_arvalid_w) begin
            if (ar_wait == 0) begin
                m_arready_r <= 1'b1;
                m_arlen_r   <= m_arlen_w;
                m_araddr_r  <= m_araddr_w;
                m_arid_r    <= m_arid_w;
                m_beat      <= 0;
                ar_ok       <= 1'b1;                    // 地址捕获，突发开窗
                m_rvalid_w  <= 1'b1;                    // 首拍即刻回流
                m_rdata_w   <= rpat(m_araddr_w, m_arid_w, 0);
                m_rresp_w   <= 2'b00;
                m_rid_w     <= m_arid_w;
                m_rlast_w   <= (m_arlen_w == 8'd0);
            end else ar_wait <= ar_wait - 1;
        end
        // ---- R 通道（数据按捕获载荷推进；rvalid=0 且突发开窗时重给）----
        if (m_rvalid_w && m_rready_w) begin             // fire
            if (m_beat >= m_arlen_r) begin              // 末拍已交付
                m_rvalid_w <= 1'b0;
                ar_ok      <= 1'b0;
            end else begin
                m_rdata_w <= rpat(m_araddr_r, m_arid_r, m_beat + 1);
                m_rlast_w <= (m_beat + 1 == m_arlen_r);
                if (rsmode == 1) m_rvalid_w <= 1'b1;    // 恒流
                else begin
                    if (rsmode == 2) rgap <= $urandom_range(0, 3);
                    m_rvalid_w <= 1'b0;                 // 间隙后重给（下方）
                end
            end
            m_beat <= m_beat + 1;
        end else if (!m_rvalid_w && ar_ok) begin        // 间隙计数与重给
            if (rsmode == 3 && m_beat >= rstall_after)
                m_rvalid_w <= 1'b0;                     // 永停（T10b）
            else if (rgap != 0) rgap <= rgap - 1;
            else m_rvalid_w <= 1'b1;
        end
    end
end

//---------------------------------------------------------------------
// BFM 任务（DA1：valid 置位后未握手不得改载荷）
//---------------------------------------------------------------------
integer txn_no [2];
initial begin txn_no[1] = 0; txn_no[0] = 0; end

task automatic recv_r(int p, int nb, int txn);
int i;
logic [511:0] d;
logic [5:0]   xid;
begin
    xid = (p == 1) ? 6'h11 : 6'h22;
    for (i = 0; i < nb; i = i + 1) begin
        // 指定 beat 前拖 rready（末拍节流/看门狗边界专项）
        if (i == rry_hold_at) begin
            rry[p] <= 1'b0;
            repeat (rry_hold_cyc) @(posedge clk);
        end
        rry[p] <= 1'b1;                     // 本拍 ready（等真握手）
        forever begin
            @(posedge clk);
            // 只有 rvalid && rready 同拍才算消费（valid-hold 挂起不得误计）
            if (p == 1 ? (s1_rvalid_w && rry[1]) : (s0_rvalid_w && rry[0])) break;
        end
        d = rpat((p == 1) ? ara[1] : ara[0], xid, i);
        if ((p == 1 ? s1_rdata_w : s0_rdata_w) !== d) begin
            $display("[BFM][ERR] P%0d txn%0d beat%0d 数据不符 got!=exp", p, txn, i);
            slave_err = slave_err + 1;
        end
        if ((p == 1 ? s1_rid_w : s0_rid_w) !== xid) begin
            $display("[BFM][ERR] P%0d txn%0d beat%0d rid=%0h != %0h", p, txn, i,
                     p == 1 ? s1_rid_w : s0_rid_w, xid);
            slave_err = slave_err + 1;
        end
        if ((p == 1 ? s1_rresp_w : s0_rresp_w) !== 2'b00) begin
            $display("[BFM][ERR] P%0d txn%0d beat%0d rresp=%0h", p, txn, i,
                     p == 1 ? s1_rresp_w : s0_rresp_w);
            slave_err = slave_err + 1;
        end
        if (i == nb-1 && !(p == 1 ? s1_rlast_w : s0_rlast_w)) begin
            $display("[BFM][ERR] P%0d txn%0d 末拍 rlast=0", p, txn);
            slave_err = slave_err + 1;
        end
        if (i != nb-1 &&  (p == 1 ? s1_rlast_w : s0_rlast_w)) begin
            $display("[BFM][ERR] P%0d txn%0d beat%0d 提前 rlast", p, txn, i);
            slave_err = slave_err + 1;
        end
        rry[p] <= 1'b0;                                 // 收拍后默认收回
        if (rrymode == 1 && (i % 3) == 2)
            repeat (2) @(posedge clk);                  // beat 间隙（背压，valid-hold 下安全）
    end
    if (p == 1) rl_rise1 = rl_rise1 + 1; else rl_rise0 = rl_rise0 + 1;
end
endtask

task automatic send_ar(int p, logic [32:0] a, int nb, logic [5:0] id);
begin
    @(posedge clk);
    arv[p] <= 1'b1; ara[p] <= a; arl[p] <= nb[7:0] - 8'd1; ars[p] <= 3'b110;
    arb[p] <= 2'b01; ari[p] <= id; arq[p] <= 4'd0; arc[p] <= 4'h0; arlk[p] <= 1'b0;
    forever begin
        @(posedge clk);
        if ((p == 1 && s1_arready_w) || (p == 0 && s0_arready_w)) break;
    end
    arv[p] <= 1'b0;
end
endtask

task automatic send_txn(int p, logic [32:0] a, int nb);
int txn, rl0;
logic [5:0] xid;
begin
    txn = txn_no[p]; txn_no[p] = txn_no[p] + 1;
    rl0 = (p == 1) ? rl_rise1 : rl_rise0;       // 入口快照（跨测试累计， 勿用相对基线）
    xid = (p == 1) ? 6'h11 : 6'h22;
    fork
        send_ar(p, a, nb, xid);
        begin
            recv_r(p, nb, txn);
        end
    join
    // §2 单 outstanding：本事务 rlast 交付后才发起下一事务
    if (p == 1) wait (rl_rise1 > rl0);
    else        wait (rl_rise0 > rl0);
end
endtask

task automatic do_reset();
begin
    rstn = 1'b0;
    arv = 2'b00; rry = 2'b00;
    m_arready_r = 1'b0; m_rvalid_w = 1'b0;
    repeat (5) @(negedge clk);            // 负沿释放复位，避免与 posedge 采样竞态
    rstn = 1'b1;
    @(negedge clk);
end
endtask

//---------------------------------------------------------------------
// 监控/A1 A2 A5 A6 检查
//---------------------------------------------------------------------
integer rbeat [2];        // 每口事务内 beat 计数
logic [32:0] arbase [2];
logic [5:0]  arid_rec [2];
integer s_rfire_cnt, m_rfire_cnt, m_ar_open;
integer err_a1, err_a2, err_a5, err_lat;
logic   rprev1, rprev0;
integer t_ar, t_sr, t_mar;
logic   t1_meas = 0;

initial begin
    rbeat[1] = 0; rbeat[0] = 0; arbase[1] = 33'd0; arbase[0] = 33'd0;
    arid_rec[1] = 6'd0; arid_rec[0] = 6'd0;
    s_rfire_cnt = 0; m_rfire_cnt = 0; m_ar_open = 0;
    rl_rise1 = 0; rl_rise0 = 0; arfire1 = 0; arfire0 = 0;
    err_a1 = 0; err_a2 = 0; err_a5 = 0; err_lat = 0;
    rprev1 = 0; rprev0 = 0;
end

always @(posedge clk) begin
    if (rstn) begin
        // ---- 源侧事务轮廓 ----
        if (arv[1] && s1_arready_w) begin
            arbase[1] = ara[1]; arid_rec[1] = ari[1]; rbeat[1] = 0; arfire1 = arfire1 + 1;
        end
        if (arv[0] && s0_arready_w) begin
            arbase[0] = ara[0]; arid_rec[0] = ari[0]; rbeat[0] = 0; arfire0 = arfire0 + 1;
        end
        // ---- M 口 ----
        if (m_rfire_w) m_rfire_cnt = m_rfire_cnt + 1;
        if (s1_rfire_w | s0_rfire_w) s_rfire_cnt = s_rfire_cnt + 1;
        if (m_arfire_w) begin
            if (m_ar_open != 0) begin
                $display("[MON][ERR][A2] 前突发未收完即收第二条 AR @%0d", cyc);
                err_a2 = err_a2 + 1;
            end
            m_ar_open = 1;
        end
        if (m_rlast_w && m_rfire_w) m_ar_open = 0;
        // ---- A5：双请授予必授 ~last_q（§5.1 req_alt 优先）----
        if (dut.grant_en && arv[1] && arv[0]) begin
            if (dut.win === dut.last_q) begin
                $display("[MON][ERR][A5] 双请授予选中 last 口 @%0d", cyc);
                err_a5 = err_a5 + 1;
            end
        end
        // ---- A1：M 口载荷恒属授权口 ----
        if (m_arvalid_w && dut.lock_q) begin
            if (dut.gnt_q) begin
                if (m_araddr_w !== arbase[1] || m_arid_w !== arid_rec[1]
                    || m_arlen_w !== arl[1]) begin
                    $display("[MON][ERR][A1] M 口载荷非 S1 @%0d", cyc);
                    err_a1 = err_a1 + 1;
                end
            end else begin
                if (m_araddr_w !== arbase[0] || m_arid_w !== arid_rec[0]
                    || m_arlen_w !== arl[0]) begin
                    $display("[MON][ERR][A1] M 口载荷非 S0 @%0d", cyc);
                    err_a1 = err_a1 + 1;
                end
            end
        end
        // ---- A6：锁释放拍两侧握手计数守恒 ----
        if (dut.lock_release) begin
            if (s_rfire_cnt != m_rfire_cnt) begin
                $display("[MON][ERR][A6] 释放拍宿侧 %0d != M 口 %0d", s_rfire_cnt, m_rfire_cnt);
                slave_err = slave_err + 1;
            end
        end
        // ---- T1 延迟测量 ----
        if (t1_meas) begin
            if (arv[1] && s1_arready_w && t_ar < 0) t_ar = cyc;
            if (m_arfire_w && t_mar < 0) t_mar = cyc;
            if (s1_rvalid_w && !rprev1 && t_sr < 0) t_sr = cyc;
        end
        rprev1 = s1_rvalid_w; rprev0 = s0_rvalid_w;
    end
end

// A6 全程松界（skid 在途容 1 拍）
always @(posedge clk) begin
    if (rstn && ((s_rfire_cnt > m_rfire_cnt + 1) || (m_rfire_cnt > s_rfire_cnt + 1))) begin
        $display("[MON][ERR][A6] 在途偏差 >1：宿 %0d M %0d @%0d", s_rfire_cnt, m_rfire_cnt, cyc);
        slave_err = slave_err + 1;
    end
end

//---------------------------------------------------------------------
// SVA A4/A7/A8/A10（层次引用 RTL 内部状态）
//---------------------------------------------------------------------
integer err_sva = 0;

property p_a4a; @(posedge clk) disable iff (!rstn)
    (dut.lock_q &&  dut.gnt_q) |-> (!s0_arready_w && !s0_rvalid_w);
endproperty
property p_a4b; @(posedge clk) disable iff (!rstn)
    (dut.lock_q && !dut.gnt_q) |-> (!s1_arready_w && !s1_rvalid_w);
endproperty
property p_ar_hold; @(posedge clk) disable iff (!rstn)
    (m_arvalid_w && !m_arready_r) |=> (m_arvalid_w && $stable(m_araddr_w) &&
        $stable(m_arlen_w) && $stable(m_arid_w) && $stable(m_arqos_w));
endproperty
property p_r_hold1; @(posedge clk) disable iff (!rstn)
    (s1_rvalid_w && !rry[1]) |=> (s1_rvalid_w && $stable(s1_rdata_w) &&
        $stable(s1_rlast_w) && $stable(s1_rid_w));
endproperty
property p_r_hold0; @(posedge clk) disable iff (!rstn)
    (s0_rvalid_w && !rry[0]) |=> (s0_rvalid_w && $stable(s0_rdata_w) &&
        $stable(s0_rlast_w) && $stable(s0_rid_w));
endproperty
property p_a8; @(posedge clk) disable iff (!rstn)
    (!dut.lock_q) |-> (!m_arvalid_w && !s1_rvalid_w && !s0_rvalid_w);
endproperty
property p_a10; @(posedge clk) disable iff (!rstn)
    ((dut.lock_q && $stable(dut.lock_q)) |-> ($stable(dut.gnt_q) && $stable(dut.last_q)));
endproperty
// 读锁释放点（头注释第5条）：M 口末拍握手后锁必须仍保持（数据尚在 skid）
property p_drain; @(posedge clk) disable iff (!rstn)
    (m_rfire_w && m_rlast_w && dut.lock_q && !dut.lock_release) |=> dut.lock_q;
endproperty

A4a: assert property (p_a4a) else begin
    $display("[SVA][ERR][A4] S1 锁定期 S0 泄漏 @%0t", $time); err_sva++; end
A4b: assert property (p_a4b) else begin
    $display("[SVA][ERR][A4] S0 锁定期 S1 泄漏 @%0t", $time); err_sva++; end
A7a: assert property (p_ar_hold) else begin
    $display("[SVA][ERR][A7] AR valid-hold 违反 @%0t", $time); err_sva++; end
A7r1: assert property (p_r_hold1) else begin
    $display("[SVA][ERR][A7] S1 R valid-hold 违反 @%0t", $time); err_sva++; end
A7r0: assert property (p_r_hold0) else begin
    $display("[SVA][ERR][A7] S0 R valid-hold 违反 @%0t", $time); err_sva++; end
A8:  assert property (p_a8) else begin
    $display("[SVA][ERR][A8] 空闲泄漏 ar=%b r1=%b r0=%b @%0t",
             m_arvalid_w, s1_rvalid_w, s0_rvalid_w, $time); err_sva++; end
A10: assert property (p_a10) else begin
    $display("[SVA][ERR][A10] 锁定期 gnt/last 不稳 @%0t", $time); err_sva++; end
ADR: assert property (p_drain) else begin
    $display("[SVA][ERR][ADR] M 口末拍握手后锁提前释放 @%0t", $time); err_sva++; end

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

task automatic fail_if(input string tag);
begin
    if (slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat > base_err)
        $display("[TEST][%s] FAIL（累计错 %0d）", tag,
                 slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat - base_err);
    else
        $display("[TEST][%s] PASS", tag);
end
endtask

// T7：复位后两口同拍首争用 → 必授 S1（§5.1 tie-break，last=0 有意安排）
task automatic t7();
logic g0;
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat;
    r1_base = rl_rise1; r0_base = rl_rise0;
    armode = 0; rsmode = 1; rrymode = 0;
    fork
        begin
            wait (dut.lock_q == 1'b1);            // 首锁建立拍采样授予归属
            g0 = dut.gnt_q;
        end
        begin send_txn(1, BASE1, 16); end
        begin send_txn(0, BASE0, 16); end
    join
    if (g0 !== 1'b1) begin
        $display("[TEST][T7][ERR] 首争用授予 %b != S1", g0);
        slave_err = slave_err + 1;
    end
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    fail_if("T7");
end
endtask

// T1：单口基线 + 延迟 ≤ 直连+3 拍
task automatic t1();
integer lat_m, lat_s;
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat;
    r1_base = rl_rise1; r0_base = rl_rise0;
    armode = 0; rsmode = 1; rrymode = 0;
    t_ar = -1; t_mar = -1; t_sr = -1; t1_meas = 1;
    send_txn(1, BASE1, 64);
    wait (dut.lock_q == 1'b0);
    t1_meas = 0;
    if (t_ar < 0 || t_mar < 0 || t_sr < 0) begin
        $display("[TEST][T1][ERR] 延迟采样缺失 ar=%0d mar=%0d sr=%0d", t_ar, t_mar, t_sr);
        err_lat = err_lat + 1;
    end else begin
        lat_m = t_sr - t_ar;                // master 视角首拍延迟
        lat_s = t_mar - t_ar;               // 地址通道开销
        $display("[T1] master 视角首拍延迟 %0d 拍（地址开销 %0d 拍）", lat_m, lat_s);
        if (lat_s > 3) begin
            $display("[TEST][T1][ERR] 地址开销 %0d > 3 拍", lat_s);
            err_lat = err_lat + 1;
        end
    end
    send_txn(1, BASE1 + 64*64, 56);
    send_txn(1, BASE1 + 64*120, 32);
    send_txn(1, BASE1 + 64*152, 28);
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    fail_if("T1");
end
endtask

// T2：双口并发争用（RR 交替由 A5 监控）
task automatic t2();
integer r;
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat;
    r1_base = rl_rise1; r0_base = rl_rise0;
    armode = 0; rsmode = 1; rrymode = 0;
    for (r = 0; r < 3; r = r + 1) begin
        fork
            send_txn(1, BASE1 + 64*r*128, 64);
            send_txn(0, BASE0 + 64*r*128, 32);
        join
    end
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    fail_if("T2");
end
endtask

// T3：随机背压（rvalid 间隙 + arready 延迟 + master rready 节流）；看门狗不得触发
task automatic t3();
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat;
    r1_base = rl_rise1; r0_base = rl_rise0;
    armode = 4; rsmode = 2; rrymode = 1;
    fork
        send_txn(1, BASE1, 56);
        send_txn(0, BASE0, 28);
    join
    send_txn(1, BASE1 + 64*64, 28);
    send_txn(0, BASE0 + 64*64, 64);
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    if (dut.stuck_q) begin
        $display("[TEST][T3][ERR] 随机背压触发看门狗");
        slave_err = slave_err + 1;
    end
    fail_if("T3");
end
endtask

// T4：最坏交错——S1 长突发进行中 S0 请求嵌入（原子性 A2）
task automatic t4();
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat;
    r1_base = rl_rise1; r0_base = rl_rise0;
    armode = 0; rsmode = 1; rrymode = 0;
    fork
        send_txn(1, BASE1, 64);
        begin
            repeat (8) @(posedge clk);       // S1 已锁定后 S0 才请求
            send_txn(0, BASE0, 32);
        end
    join
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    fail_if("T4");
end
endtask

// T5：末拍节流——master 在末拍前拖 rready（读锁释放点专项：M 口末拍握手后
// 锁必须保持到 skid 末拍完整交付，S0 请求在释放前不得抢入）
task automatic t5();
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat;
    r1_base = rl_rise1; r0_base = rl_rise0;
    armode = 0; rsmode = 1; rrymode = 0;
    rry_hold_at = 15; rry_hold_cyc = 7;      // 16 拍突发的末拍前拖 7 拍
    fork
        send_txn(1, BASE1, 16);
        begin
            repeat (3) @(posedge clk);       // S1 锁定后 S0 才请求（挂起至释放）
            send_txn(0, BASE0, 32);
        end
    join
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    rry_hold_at = -1; rry_hold_cyc = 0;
    fail_if("T5");
end
endtask

// T6：混合长短事务 + dbg 计数对账（RTL 计数全程累计不清零，查增量）
task automatic t6();
integer dt1, dt0, db1, db0;
begin
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat;
    r1_base = rl_rise1; r0_base = rl_rise0;
    armode = 1; rsmode = 2; rrymode = 0;
    dt1 = dbg_txn1; dt0 = dbg_txn0; db1 = dbg_beat1; db0 = dbg_beat0;
    send_txn(1, BASE1, 64);
    send_txn(0, BASE0, 28);
    send_txn(1, BASE1 + 64*64, 56);
    send_txn(0, BASE0 + 64*64, 32);
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
    fail_if("T6");
end
endtask

// T10：看门狗边界
//   a) master 末拍拖 4000 < 4096：不触发（进展窗口边界）
//   b) R 永停 > 4096：触发 sticky；复位清 sticky/锁
task automatic t10();
integer db1;
begin
    // ---- a) 4000 拍无进展不触发 ----
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat;
    r1_base = rl_rise1; r0_base = rl_rise0;
    armode = 0; rsmode = 1; rrymode = 0;
    rry_hold_at = 15; rry_hold_cyc = 4000;   // 16 拍突发末拍前拖 4000 拍
    send_txn(1, BASE1, 16);
    wait (dut.lock_q == 1'b0);
    repeat (4) @(posedge clk);
    rry_hold_at = -1; rry_hold_cyc = 0;
    if (dut.stuck_q) begin
        $display("[TEST][T10a][ERR] 4000 拍无进展误触发看门狗");
        slave_err = slave_err + 1;
    end
    fail_if("T10a");

    // ---- b) 永停触发 sticky ----
    base_err = slave_err + err_sva + err_a1 + err_a2 + err_a5 + err_lat;
    r1_base = rl_rise1; r0_base = rl_rise0;
    rsmode = 3; rstall_after = 10;
    db1 = dbg_beat1;                              // 增量基线（dbg_beat 为自复位累计值）
    fork send_txn(1, BASE1, 64); join_none
    repeat (6000) @(posedge clk);                 // > 4096 看门狗窗
    if (!dut.stuck_q) begin
        $display("[TEST][T10b][ERR] R 永停未触发看门狗");
        slave_err = slave_err + 1;
    end
    if (dut.lock_q != 1'b1) begin
        $display("[TEST][T10b][ERR] 锁未保持");
        slave_err = slave_err + 1;
    end
    $display("[T10b] 部分完成可读：beat=%0d", dbg_beat1 - db1);
    if ((dbg_beat1 - db1) != 16'd10) begin
        $display("[TEST][T10b][ERR] 部分完成 beat 增量 %0d != 10", dbg_beat1 - db1);
        slave_err = slave_err + 1;
    end
    do_reset();
    if (dut.stuck_q || dut.lock_q) begin
        $display("[TEST][T10b][ERR] 复位未清 sticky/锁");
        slave_err = slave_err + 1;
    end
    fail_if("T10b");
end
endtask

//---------------------------------------------------------------------
// 调度与汇总
//---------------------------------------------------------------------
initial begin
    $timeformat(-9, 0, " ns", 10);   // %0t 以 ns 显示
    $display("==== axi_rd_arb 单元 TB 开始 ====");
    do_reset();
    t7();    // 复位后首争用（须最先，吃新复位状态）
    t1();
    t2();
    t3();
    t4();
    t5();
    t6();
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
