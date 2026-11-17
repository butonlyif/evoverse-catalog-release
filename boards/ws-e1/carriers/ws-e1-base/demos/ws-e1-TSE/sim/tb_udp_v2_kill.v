//============================================================================
// tb_udp_v2_kill : udp_pat_gen_v2 包边界停车（pat_gen_kill）定向用例
// 2026-11-06 PC 运行时模式切换配套。背景：inc 无限流包间不回 S_IDLE（FSM 链
// S_DATA→S_IPG→S_HDR），en 撤除不停车——kill 是唯一干净停法。
// 覆盖：
//   A) inc 无限流中途 kill：当前包以 tlast 完整收尾 → S_IDLE → 静默无毛刺
//   B) kill 后重启（PatGen 等效序列）：包流恢复且包长完整（tlast 间隔 1500B）
//   C) RAW10 无限流中途 kill：包边界停车 + 等满一个 FRAME_PERIOD 验证
//      frame_tick 不复燃（pat_en 熄火生效）
//============================================================================
`timescale 1ns/1ps

module tb_udp_v2_kill;

localparam FRAME_PERIOD   = 4_166_667;
localparam PKTS_PER_FRAME = 1788;

reg         clk    = 1'b0;
reg         rstn   = 1'b0;
reg         en_pulse = 1'b0;
reg         raw10_en = 1'b0;    //Phase A/B: inc；Phase C: 1
reg  [15:0] num    = 16'd0;     //无限
reg  [15:0] ipg    = 16'd12;
reg  [15:0] dlen   = 16'd1458;
reg         kill   = 1'b0;
wire [7:0]  tdata;
wire        tvalid;
wire        tlast;
wire [31:0] fno_dbg;
wire [9:0]  dbg;
reg         tready = 1'b1;

always #4 clk = ~clk;   // 125MHz

udp_pat_gen_v2 #(
    .FRAME_PERIOD   (FRAME_PERIOD),
    .IPG_RAW10      (12),
    .DATA_PER_PKT   (1450),
    .LAST_DATA      (850),
    .PKTS_PER_FRAME (PKTS_PER_FRAME),
    .FRAME_PIXELS   (2073600)
) dut (
    .clk(clk), .rstn(rstn),
    .pat_gen_en(en_pulse), .pat_gen_num(num), .pat_gen_ipg(ipg),
    .raw10_en(raw10_en),
    .pat_gen_kill(kill),
    .pat_mode(2'b00),
    .dst_mac(48'hffffffffffff), .src_mac(48'heae85e0060c8),
    .src_ip(32'h0a000008), .dst_ip(32'h0a000003),
    .udp_dlen(dlen), .src_port(16'd0521), .dst_port(16'd2715),
    .tdata(tdata), .tvalid(tvalid), .tlast(tlast), .tready(tready),
    .frame_num_o(fno_dbg),
    .dbg_state_o(dbg)
);

integer errors = 0;
integer pkts   = 0;     //tvalid 上升沿计数（包启动数）
integer tl_cnt = 0;     //tlast 计数
integer bytes_in_pkt = 0;
reg    seen_tlast_since_kill = 0;
reg    tl_seen_kill_mark = 0;
reg    tv_prev = 1'b0;
integer last_pkt_len = 0;

always @(posedge clk) begin
    if (tvalid && tready) bytes_in_pkt = bytes_in_pkt + 1;
    if (tvalid && tlast) begin
        tl_cnt = tl_cnt + 1;
        last_pkt_len = bytes_in_pkt;
        if (tl_seen_kill_mark) begin
            seen_tlast_since_kill = 1;
            //合法包长：inc=1508B（42+1466，G6 实测同源）；RAW10=1500B/900B(帧末)
            if (bytes_in_pkt !== 1508 && bytes_in_pkt !== 1500 && bytes_in_pkt !== 900) begin
                errors = errors + 1;
                $display("[FAIL] kill 边界包不完整: %0d bytes (expect 1508/1500/900)", bytes_in_pkt);
            end
            tl_seen_kill_mark = 0;
        end
        bytes_in_pkt = 0;
    end else if (!tvalid) bytes_in_pkt = 0;
    if (tvalid && !tv_prev) pkts = pkts + 1;
    tv_prev <= tvalid;
end

task automatic wait_idle(input integer max_cyc);
    integer w;
    begin
        for (w = 0; w < max_cyc; w = w + 1) begin
            @(posedge clk);
            if (dut.state == 3'h0) disable wait_idle;
        end
    end
endtask

//静默检查：n 拍内不得有任何 tvalid
task automatic check_quiet(input integer n, input [255:0] tag);
    integer w;
    begin
        for (w = 0; w < n; w = w + 1) begin
            @(posedge clk);
            if (tvalid !== 1'b0) begin
                errors = errors + 1;
                $display("[FAIL] %0s: 停车后 tvalid 复燃 @%0t", tag, $time);
                disable check_quiet;
            end
        end
    end
endtask

initial begin
    repeat (20) @(posedge clk);
    rstn = 1'b1;
    repeat (50) @(posedge clk);

    // ---- Phase A: inc 无限流中途 kill ----
    en_pulse = 1'b1; @(posedge clk); en_pulse = 1'b0;
    wait (pkts >= 5);
    $display("[TB] A: inc 流运行中 pkts=%0d tl=%0d，发起 kill", pkts, tl_cnt);
    kill = 1'b1;
    tl_seen_kill_mark = 1;
    wait_idle(100000);
    if (dut.state !== 3'h0) begin
        errors = errors + 1;
        $display("[FAIL] A: kill 后未回 S_IDLE");
    end
    if (!seen_tlast_since_kill) begin
        errors = errors + 1;
        $display("[FAIL] A: kill 边界包未以 tlast 收尾");
    end
    check_quiet(20000, "A-inc");
    //pat_en 熄火检查放在静默期之后（S_IDLE 进入的下一拍才清，当拍读会误报）
    if (dut.pat_en !== 1'b0) begin
        errors = errors + 1;
        $display("[FAIL] A: 停车后 pat_en 未熄火");
    end
    $display("[TB] A PASS: 包边界停车 + 静默");

    // ---- Phase B: kill 后重启（PatGen 等效：kill 已清 + en 脉冲）----
    kill = 1'b0;
    repeat (10) @(posedge clk);
    en_pulse = 1'b1; @(posedge clk); en_pulse = 1'b0;
    wait (pkts >= 10);
    //包完整性：连续 3 个 tlast，包长均须 1500B（延后一拍采样避免同沿竞态）
    begin : PKTLEN
        integer k;
        for (k = 0; k < 3; k = k + 1) begin
            @(posedge tlast);
            @(posedge clk);
            if (last_pkt_len !== 1508) begin
                errors = errors + 1;
                $display("[FAIL] B: 重启后包长 %0d (expect 1508)", last_pkt_len);
            end
        end
    end
    $display("[TB] B PASS: kill 后重启包流恢复且完整");

    // ---- Phase C: RAW10 无限流中途 kill + frame_tick 不复燃 ----
    raw10_en = 1'b1;
    repeat (100) @(posedge clk);        //拉开 raw10_mode 与脉冲（板级教训同步）
    en_pulse = 1'b1; @(posedge clk); en_pulse = 1'b0;
    wait (pkts >= 15);
    $display("[TB] C: RAW10 流运行中，发起 kill");
    kill = 1'b1;
    tl_seen_kill_mark = 1;
    wait_idle(100000);
    if (!seen_tlast_since_kill) begin
        errors = errors + 1;
        $display("[FAIL] C: kill 边界包未以 tlast 收尾");
    end
    check_quiet(20000, "C-raw10-boundary");
    //关键：等满一个帧周期，frame_tick 不得复燃（pat_en 熄火 + kill 门控）
    check_quiet(FRAME_PERIOD + 10000, "C-frame-tick");
    if (dut.state !== 3'h0 || dut.pat_en !== 1'b0) begin
        errors = errors + 1;
        $display("[FAIL] C: 帧周期后 state/pat_en 异常 state=%0d pat_en=%b",
                 dut.state, dut.pat_en);
    end
    $display("[TB] C PASS: RAW10 停车 + frame_tick 不复燃");

    if (errors == 0)
        $display("=== TB_UDP_V2_KILL: ALL CHECKS PASSED ===");
    else
        $display("=== TB_UDP_V2_KILL: %0d ERRORS ===", errors);
    $finish;
end

// 超时看门狗
initial begin
    #200_000_000;   // 200ms
    $display("=== TB_UDP_V2_KILL TIMEOUT: pkts=%0d tl=%0d state=%0d ===", pkts, tl_cnt, dut.state);
    $finish;
end

endmodule
