//=====================================================================
// axi_rd_cdc_tb.sv — axi_rd_cdc 单元 TB（arbiter.md §205/§4.3 判据：
//                     CDC 单元 TB 回环比对 + 首字延迟量化）
// 结构 : s 域 master BFM（37.125M）+ m 域 DDR target1 stub（148.5M）
//        回环比对：AR 载荷在 m 口比对；R 数据按 m 口捕获载荷生成，
//        s 口逐 beat 比对——CDC 丢数/错序/载荷错任一必然失配
// 时钟 : aclk_m 6.734ns / aclk_s 26.936ns（精确 4:1，与板级一致）
// 量化 : [CDC-LAT] AR 握手拍 → 首拍 RVALID 拍（s 域主口径）+
//        m 域分段（AR pop → 首拍 RVALID）
// 实证 : ar_full/r_full 反压路径必须真实走过（gating SVA + 窗口观测）
// SVA  : 全放 TB（Q3 定案），层次引用 dut.ar_full/dut.r_full
//=====================================================================
`timescale 1ns/1ps
module axi_rd_cdc_tb;

//---------------------------------------------------------------------
// 时钟/复位（双域独立异步复位，错开释放）
//---------------------------------------------------------------------
logic clk_m = 1'b0;
always #3.367 clk_m = ~clk_m;          // 148.5MHz
logic clk_s = 1'b0;
always #13.468 clk_s = ~clk_s;         // 37.125MHz（26.936/6.734 = 4.0）
logic rstn_s = 1'b0;
logic rstn_m = 1'b0;

localparam logic [32:0] BASE = 33'h0_0400_0000;   // target1（ddr_interface.md §10）

integer s_cyc = 0;
always @(posedge clk_s) s_cyc = s_cyc + 1;
integer m_cyc = 0;
always @(posedge clk_m) m_cyc = m_cyc + 1;

//---------------------------------------------------------------------
// s 域 master BFM 信号
//---------------------------------------------------------------------
logic          s_arv;
logic [32:0]   s_araddr_w;
logic [7:0]    s_arlen_w;
logic [2:0]    s_arsize_w;
logic [1:0]    s_arburst_w;
logic [5:0]    s_arid_w;
logic [3:0]    s_arqos_w;
logic [3:0]    s_arcache_w;
logic          s_arlock_w;
logic          s_rry;                  // rready，BFM 任务驱动

wire           s_arready_w;
wire           s_rvalid_w;
wire [511:0]   s_rdata_w;
wire [1:0]     s_rresp_w;
wire           s_rlast_w;
wire [5:0]     s_rid_w;

//---------------------------------------------------------------------
// m 域 DDR target1 stub 信号（过程驱动，须为变量）
//---------------------------------------------------------------------
logic          m_arready_r;
logic          m_rv;
logic [511:0]  m_rdata_w;
logic [1:0]    m_rresp_w;
logic          m_rlast_w;
logic [5:0]    m_rid_w;

wire           m_arvalid_w;
wire           m_rready_w;
wire [32:0]    m_araddr_w;
wire [7:0]     m_arlen_w;
wire [2:0]     m_arsize_w;
wire [1:0]     m_arburst_w;
wire [5:0]     m_arid_w;
wire [3:0]     m_arqos_w;
wire [3:0]     m_arcache_w;
wire           m_arlock_w;

//---------------------------------------------------------------------
// DUT
//---------------------------------------------------------------------
axi_rd_cdc dut (
    .aclk_s(clk_s), .rstn_s(rstn_s),
    .s_arvalid(s_arv), .s_arready(s_arready_w), .s_araddr(s_araddr_w),
    .s_arlen(s_arlen_w), .s_arsize(s_arsize_w), .s_arburst(s_arburst_w),
    .s_arid(s_arid_w), .s_arqos(s_arqos_w), .s_arcache(s_arcache_w),
    .s_arlock(s_arlock_w),
    .s_rvalid(s_rvalid_w), .s_rready(s_rry), .s_rdata(s_rdata_w),
    .s_rresp(s_rresp_w), .s_rlast(s_rlast_w), .s_rid(s_rid_w),
    .aclk_m(clk_m), .rstn_m(rstn_m),
    .m_arvalid(m_arvalid_w), .m_arready(m_arready_r), .m_araddr(m_araddr_w),
    .m_arlen(m_arlen_w), .m_arsize(m_arsize_w), .m_arburst(m_arburst_w),
    .m_arid(m_arid_w), .m_arqos(m_arqos_w), .m_arcache(m_arcache_w),
    .m_arlock(m_arlock_w),
    .m_rvalid(m_rv), .m_rready(m_rready_w), .m_rdata(m_rdata_w),
    .m_rresp(m_rresp_w), .m_rlast(m_rlast_w), .m_rid(m_rid_w)
);

//---------------------------------------------------------------------
// 期望队列（单写单读：send_ar 写 / m stub 与 s recv 各自读）
//---------------------------------------------------------------------
logic [32:0] q_addr [0:31];
logic [7:0]  q_len  [0:31];
logic [5:0]  q_id   [0:31];
integer      q_wr = 0, q_rd_m = 0, q_rd_s = 0;

//---------------------------------------------------------------------
// 旋钮（每用例设置）
//---------------------------------------------------------------------
integer ar_ack_gap = 0;      // m stub 每次 AR pop 后停拍数（AR 积压制造）
integer rsmode      = 1;     // 1=恒流 2=随机间隙
integer s_throttle  = 0;     // 0=恒收 1=每 3 拍收 1 拍（R 积压制造）
integer lat_en      = 0;     // 首字延迟测量使能

// 延迟测量（s 域主口径：AR 握手沿 → 首拍 RVALID 沿）
integer lat_ars = 0, lat_max = 0, lat1 = 0;
integer m_cap_cyc = 0, m_rv0_cyc = 0, m_lat = 0;

// 反压路径实证标志
integer ar_full_seen = 0, r_full_seen = 0;
always @(posedge clk_s) if (rstn_s && dut.ar_full) ar_full_seen = 1;
always @(posedge clk_m) if (rstn_m && dut.r_full)  r_full_seen  = 1;

integer slave_err = 0;
integer err_sva   = 0;
integer err_base  = 0;                 // 本测试入口基线（fail_if 判增量）

//---------------------------------------------------------------------
// 数据图案（m stub 与 s recv 共用；载荷错/路由错必然失配）
//---------------------------------------------------------------------
function automatic logic [511:0] rpat(logic [32:0] a, logic [5:0] id, int i);
    logic [63:0] h;
    begin
        h = ({64'd0, a} * 64'h9E37_79B9_7F4A_7C15) ^
            ({64'd0, {58'd0, id}} * 64'hC2B2_AE3D_27D4_EB4F);
        rpat = {8{h}} ^ {32{i[15:0]}};
    end
endfunction

//---------------------------------------------------------------------
// m 域 DDR target1 stub：AR 捕获（载荷比对）+ 按捕获载荷回流 R 突发
//---------------------------------------------------------------------
logic [7:0]  m_arlen_r;
logic [32:0] m_araddr_r;
logic [5:0]  m_arid_r;
integer      m_beat = 0;
integer      ar_wait = 0;
integer      rgap = 0;
logic        ar_ok = 1'b0;

always @(posedge clk_m or negedge rstn_m) begin
    if (!rstn_m) begin
        m_arready_r <= 1'b0; m_rv <= 1'b0;
        ar_wait <= 0; rgap <= 0;
        m_arlen_r <= 8'd0; m_araddr_r <= 33'd0; m_arid_r <= 6'd0;
        m_beat <= 0; ar_ok <= 1'b0;
    end else begin
        // ---- AR 通道：满反压 = ready 回落，pop 后按 ar_ack_gap 停拍 ----
        if (m_arvalid_w && m_arready_r) begin           // fire（ar_pop）
            m_arready_r <= 1'b0;
            ar_wait     <= ar_ack_gap;
        end else if (!m_arready_r && m_arvalid_w && !ar_ok) begin // 串行化：R 末拍交付后才捕获下一 AR（杜绝与 R fire 同拍 NBA 覆盖）
            if (ar_wait == 0) begin
                m_arready_r <= 1'b1;
                m_araddr_r  <= m_araddr_w;
                m_arlen_r   <= m_arlen_w;
                m_arid_r    <= m_arid_w;
                m_beat      <= 0;
                ar_ok       <= 1'b1;                    // 地址捕获，突发开窗
                m_cap_cyc   = m_cyc;                    // AR 接受沿（m 域延迟锚）
                // AR 载荷比对（期望队列同序）
                if (m_araddr_w !== q_addr[q_rd_m]) begin
                    $display("[M-STUB][ERR] AR%0d addr=%0h != %0h",
                             q_rd_m, m_araddr_w, q_addr[q_rd_m]);
                    slave_err = slave_err + 1;
                end
                if (m_arlen_w !== q_len[q_rd_m]) begin
                    $display("[M-STUB][ERR] AR%0d len=%0h != %0h",
                             q_rd_m, m_arlen_w, q_len[q_rd_m]);
                    slave_err = slave_err + 1;
                end
                if (m_arid_w !== q_id[q_rd_m]) begin
                    $display("[M-STUB][ERR] AR%0d id=%0h != %0h",
                             q_rd_m, m_arid_w, q_id[q_rd_m]);
                    slave_err = slave_err + 1;
                end
                q_rd_m = q_rd_m + 1;
                // 零延迟回流首拍
                m_rv      <= 1'b1;
                m_rdata_w <= rpat(m_araddr_w, m_arid_w, 0);
                m_rresp_w <= 2'b00;
                m_rid_w   <= m_arid_w;
                m_rlast_w <= (m_arlen_w == 8'd0);
            end else ar_wait <= ar_wait - 1;
        end
        // ---- R 通道：r_full 时 m_rready 拉低，valid-hold 保持不丢 ----
        if (m_rv && m_rready_w) begin                   // fire（r_push）
            if (m_beat >= m_arlen_r) begin              // 末拍已交付
                m_rv   <= 1'b0;
                ar_ok  <= 1'b0;
            end else begin
                m_rdata_w <= rpat(m_araddr_r, m_arid_r, m_beat + 1);
                m_rlast_w <= (m_beat + 1 == m_arlen_r);
                if (rsmode == 1) m_rv <= 1'b1;          // 恒流
                else begin
                    rgap <= $urandom_range(0, 3);
                    m_rv <= 1'b0;                       // 间隙后重给（下方）
                end
            end
            if (m_beat == 0) m_rv0_cyc = m_cyc;         // 首拍 fire 沿
            m_beat <= m_beat + 1;
        end else if (!m_rv && ar_ok) begin              // 间隙计数与重给
            if (rgap != 0) rgap <= rgap - 1;
            else m_rv <= 1'b1;
        end
    end
end

//---------------------------------------------------------------------
// s 域 master BFM 任务
//---------------------------------------------------------------------
task automatic send_ar(logic [32:0] a, int nb, logic [5:0] id);
begin
    q_addr[q_wr] = a; q_len[q_wr] = nb[7:0] - 8'd1; q_id[q_wr] = id;
    q_wr = q_wr + 1;
    @(posedge clk_s);
    s_arv       <= 1'b1; s_araddr_w <= a; s_arlen_w <= nb[7:0] - 8'd1;
    s_arsize_w  <= 3'b110; s_arburst_w <= 2'b01; s_arid_w <= id;
    s_arqos_w   <= 4'd0; s_arcache_w <= 4'h0; s_arlock_w <= 1'b0;
    forever begin
        @(posedge clk_s);
        if (s_arready_w) break;                         // s_arvalid & s_arready
    end
    lat_ars = s_cyc;                                    // AR 握手沿
    s_arv <= 1'b0;
end
endtask

task automatic recv_txn();
int i, nb, l;
logic [32:0] ea;
logic [5:0]  eid;
begin
    ea  = q_addr[q_rd_s]; nb = q_len[q_rd_s] + 1; eid = q_id[q_rd_s];
    if (lat_en) begin
        // 首拍 RVALID 沿（不论 ready；测量口径 = 首拍 RVALID − AR 握手）
        forever begin
            @(posedge clk_s);
            if (s_rvalid_w) break;
        end
        l = s_cyc - lat_ars;
        if (l > lat_max) lat_max = l;
    end
    for (i = 0; i < nb; i = i + 1) begin
        if (s_throttle == 1 && (i % 3) == 2)
            repeat (2) @(posedge clk_s);                // beat 间隙（R 积压制造）
        s_rry <= 1'b1;                                  // 本拍 ready（等真握手）
        forever begin
            @(posedge clk_s);
            if (s_rvalid_w && s_rry) break;
        end
        if (s_rdata_w !== rpat(ea, eid, i)) begin
            $display("[BFM][ERR] txn%0d beat%0d 数据不符 got!=exp", q_rd_s, i);
            slave_err = slave_err + 1;
        end
        if (s_rid_w !== eid) begin
            $display("[BFM][ERR] txn%0d beat%0d rid=%0h != %0h",
                     q_rd_s, i, s_rid_w, eid);
            slave_err = slave_err + 1;
        end
        if (s_rresp_w !== 2'b00) begin
            $display("[BFM][ERR] txn%0d beat%0d rresp=%0h", q_rd_s, i, s_rresp_w);
            slave_err = slave_err + 1;
        end
        if (i == nb-1 && !s_rlast_w) begin
            $display("[BFM][ERR] txn%0d 末拍 rlast=0", q_rd_s);
            slave_err = slave_err + 1;
        end
        if (i != nb-1 && s_rlast_w) begin
            $display("[BFM][ERR] txn%0d beat%0d 提前 rlast", q_rd_s, i);
            slave_err = slave_err + 1;
        end
        s_rry <= 1'b0;                                  // 收拍后默认收回
    end
    q_rd_s = q_rd_s + 1;
end
endtask

// 串行单事务（延迟测量干净：上一事务 R 收完 FIFO 空后才发下一 AR）
task automatic send_txn(logic [32:0] a, int nb, logic [5:0] id);
begin
    fork
        send_ar(a, nb, id);
        recv_txn();
    join
end
endtask

//---------------------------------------------------------------------
// SVA（层次引用 DUT 内部 full，gating 一致性）
//---------------------------------------------------------------------
property p_s_r_hold;
    @(posedge clk_s) disable iff (!rstn_s)
    (s_rvalid_w && !s_rry) |=> (s_rvalid_w && $stable(s_rdata_w) &&
                                $stable(s_rid_w) && $stable(s_rlast_w));
endproperty
property p_m_ar_hold;                   // 首字直通输出在反压期稳定
    @(posedge clk_m) disable iff (!rstn_m)
    (m_arvalid_w && !m_arready_r) |=> (m_arvalid_w && $stable(m_araddr_w) &&
                                       $stable(m_arlen_w) && $stable(m_arid_w));
endproperty
property p_m_r_hold;
    @(posedge clk_m) disable iff (!rstn_m)
    (m_rv && !m_rready_w) |=> (m_rv && $stable(m_rdata_w) &&
                               $stable(m_rid_w) && $stable(m_rlast_w));
endproperty
property p_ar_full_gate;
    @(posedge clk_s) disable iff (!rstn_s)
    dut.ar_full |-> (!s_arready_w);
endproperty
property p_r_full_gate;
    @(posedge clk_m) disable iff (!rstn_m)
    dut.r_full |-> (!m_rready_w);
endproperty

a_s_r_hold  : assert property (p_s_r_hold)  else err_sva = err_sva + 1;
a_m_ar_hold : assert property (p_m_ar_hold) else err_sva = err_sva + 1;
a_m_r_hold  : assert property (p_m_r_hold)  else err_sva = err_sva + 1;
a_ar_full   : assert property (p_ar_full_gate) else err_sva = err_sva + 1;
a_r_full    : assert property (p_r_full_gate)  else err_sva = err_sva + 1;

//---------------------------------------------------------------------
// 用例
//---------------------------------------------------------------------
task automatic do_reset();
begin
    rstn_s = 1'b0; rstn_m = 1'b0;
    s_arv = 1'b0; s_rry = 1'b0;
    m_arready_r = 1'b0; m_rv = 1'b0;
    q_wr = 0; q_rd_m = 0; q_rd_s = 0;
    ar_full_seen = 0; r_full_seen = 0;
    repeat (5) @(posedge clk_s);
    rstn_m = 1'b1;                       // m 域先释放（独立复位域实证）
    repeat (3) @(posedge clk_s);
    rstn_s = 1'b1;
    repeat (2) @(posedge clk_s);
end
endtask

task automatic fail_if(string nm);
begin
    if (slave_err + err_sva != err_base) $display("[TEST][%s] FAIL", nm);
    else                                 $display("[TEST][%s] PASS", nm);
end
endtask

// T1：单事务直通 + [CDC-LAT] 首字延迟量化（FIFO 空路径）
task automatic t1();
begin
    err_base = slave_err + err_sva;
    ar_ack_gap = 0; rsmode = 1; s_throttle = 0; lat_en = 1;
    lat_max = 0;
    send_txn(BASE, 9, 6'h21);
    lat1 = lat_max;
    $display("[CDC-LAT] s 域（37.125M）：AR 握手 → 首拍 RVALID = %0d 拍", lat1);
    m_lat = m_rv0_cyc - m_cap_cyc;
    $display("[CDC-LAT] m 域（148.5M）：AR pop → 首拍 RVALID = %0d 拍（stub 零延迟）", m_lat);
    if (lat1 == 0 || lat1 > 8) begin
        $display("[TEST][T1][ERR] 首字延迟 %0d 拍超出合理窗 [1..8]", lat1);
        slave_err = slave_err + 1;
    end
    if (m_lat == 0 || m_lat > 2) begin
        $display("[TEST][T1][ERR] m 域分段延迟 %0d 拍超出合理窗 [1..2]", m_lat);
        slave_err = slave_err + 1;
    end
    fail_if("T1");
end
endtask

// T2：AR FIFO 满反压（8 连发 > 深度 4，m 侧慢 pop；载荷逐一比对不丢）
task automatic t2();
begin
    err_base = slave_err + err_sva;
    ar_ack_gap = 40; rsmode = 1; s_throttle = 0; lat_en = 0;
    fork
        begin : T2_SEND
            int k;
            for (k = 0; k < 8; k = k + 1)
                send_ar(BASE + k*64, 1, 6'h30 + k[5:0]);
        end
        begin : T2_RECV
            int k;
            for (k = 0; k < 8; k = k + 1) recv_txn();
        end
    join
    if (!ar_full_seen) begin
        $display("[TEST][T2][ERR] 8 连发未实证 ar_full 反压路径");
        slave_err = slave_err + 1;
    end
    fail_if("T2");
end
endtask

// T3：R FIFO 满反压（2×16 beat 恒流 vs s 侧 3 拍收 1；r_full 门控 m_rready）
task automatic t3();
begin
    err_base = slave_err + err_sva;
    ar_ack_gap = 0; rsmode = 1; s_throttle = 1; lat_en = 0;
    fork
        begin
            send_ar(BASE, 16, 6'h40);
            send_ar(BASE + 16*64, 16, 6'h41);
        end
        begin
            recv_txn();
            recv_txn();
        end
    join
    if (!r_full_seen) begin
        $display("[TEST][T3][ERR] 恒流+慢收未实证 r_full 反压路径");
        slave_err = slave_err + 1;
    end
    fail_if("T3");
end
endtask

// T4：混合压测（10 事务，len/gap/节奏交替；全比对 + 延迟 max）
task automatic t4();
int i;
begin
    err_base = slave_err + err_sva;
    lat_en = 1; lat_max = 0;
    for (i = 0; i < 10; i = i + 1) begin
        rsmode     = (i % 2 == 1) ? 2 : 1;
        s_throttle = i % 2;
        ar_ack_gap = i % 4;
        send_txn(BASE + i*4096, 4 + (i % 8), 6'h20 + i[5:0]);
    end
    $display("[CDC-LAT] T4 十事务首字延迟 max = %0d 拍（37.125M）", lat_max);
    if (lat_max > 8) begin
        $display("[TEST][T4][ERR] 首字延迟 max %0d 拍 > 8", lat_max);
        slave_err = slave_err + 1;
    end
    fail_if("T4");
end
endtask

//---------------------------------------------------------------------
// 调度与汇总
//---------------------------------------------------------------------
initial begin
    $timeformat(-9, 0, " ns", 10);
    $display("==== axi_rd_cdc 单元 TB 开始（回环比对 + 满反压 + CDC-LAT）====");
    do_reset();
    t1();
    t2();
    t3();
    t4();
    $display("==== 汇总：slave_err=%0d sva=%0d ====", slave_err, err_sva);
    if (slave_err + err_sva == 0) $display("==== ALL TESTS PASS ====");
    else                          $display("==== TESTS FAILED ====");
    $finish;
end

// 全局看门狗（TB 自身防挂死）
initial begin
    #10_000_000;   // 10ms 仿真墙钟
    $display("[TB][FATAL] 全局超时");
    $finish;
end

endmodule
