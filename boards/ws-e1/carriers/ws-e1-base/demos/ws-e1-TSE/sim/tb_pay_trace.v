// tb_pay_trace: 观察 S_DATA 末拍 → IPG → S_HDR 的精确序列（0 基 pay_cnt）
`timescale 1ns/1ps
module tb_pay_trace;
reg         clk    = 1'b0;
reg         rstn   = 1'b0;
reg         en_pulse = 1'b0;
reg         raw10_en = 1'b1;
reg  [15:0] num    = 16'd0;
reg  [15:0] ipg    = 16'd12;
reg  [47:0] dst_mac = 48'hffffffffffff;
reg  [47:0] src_mac = 48'heae85e0060c8;
reg  [31:0] src_ip  = 32'h0a000008;
reg  [31:0] dst_ip  = 32'h0a000002;
reg  [15:0] dlen    = 16'd1458;
reg  [15:0] sport   = 16'h0521;
reg  [15:0] dport   = 16'h2715;
wire [7:0]  tdata;
wire        tvalid, tlast;
reg         tready = 1'b1;

always #4 clk = ~clk;

udp_pat_gen_v2 #(
    .FRAME_PERIOD(4_166_667), .IPG_RAW10(12),
    .DATA_PER_PKT(1450), .LAST_DATA(850),
    .PKTS_PER_FRAME(1788), .FRAME_PIXELS(2073600)
) dut (
    .clk(clk), .rstn(rstn),
    .pat_gen_en(en_pulse), .pat_gen_num(num), .pat_gen_ipg(ipg),
    .raw10_en(raw10_en),
    .dst_mac(dst_mac), .src_mac(src_mac),
    .src_ip(src_ip), .dst_ip(dst_ip),
    .udp_dlen(dlen), .src_port(sport), .dst_port(dport),
    .tdata(tdata), .tvalid(tvalid), .tlast(tlast), .tready(tready),
    .frame_num_o()
);

integer beats = 0;
always @(posedge clk) begin
    if (rstn && tvalid && tready) beats = beats + 1;
end

initial begin
    repeat (20) @(posedge clk);
    rstn = 1'b1;
    repeat (10) @(posedge clk);
    en_pulse = 1'b1;
    @(posedge clk);
    en_pulse = 1'b0;
    // 逐拍打印第一包尾部到第二包头部（载荷序号 1450..1462 区间）
    forever begin
        @(posedge clk);
        if (beats >= 1493 && beats <= 1512)
            $display("  B%0d tdata=%02x tlast=%b state=%0d pay_cnt=%0d meta_cnt=%0d grp_byte=%0d grp_cnt=%0d ipg_cnt=%0d",
                beats, tdata, tlast, dut.state, dut.pay_cnt, dut.meta_cnt, dut.grp_byte, dut.grp_cnt, dut.ipg_cnt);
        if (beats > 1512) begin
            $display("=== TRACE DONE: beats=%0d ===", beats);
            $finish;
        end
    end
end

initial begin
    #50_000_000;
    $display("=== TIMEOUT beats=%0d ===", beats);
    $finish;
end
endmodule
