//============================================================================
// tb_udp_v2 : udp_pat_gen_v2 RAW10 视频流校验
//  - 抓取 3 帧完整线上字节，逐项校验：
//    1) 帧长 1500B（1788 包×1500B），tlast 落在每包末字节
//    2) ETH/IP/UDP 头字段 + IP 校验和（含校验和字节后总和反码和=0xFFFF）
//    3) UDP checksum 字节 = 0x0000
//    4) 元数据：帧号连续、偏移 = 包序号×1450（大端）
//    5) RAW10 载荷逐字节：pat_mode 逐帧轮换（f%4），四图案期望值逐字节比对：
//       0=RGGB 8 彩条（每条 240px：白黄青绿品红红蓝黑，0x3FF/0x000，
//         行偶 {R,Gr} 行奇 {Gb,B}）
//       1=横向灰度（c>>1，全平面同值）
//       2=垂直灰度（row 饱和 1023，全平面同值）
//       3=棋盘（120px 黑白格，全平面同值），4px->5B MIPI 交错打包
//    6) 帧周期 ≈ 4,166,667 拍（30.00fps ±容差）
//    模式切换挂在 frame_num_o 翻新（帧末最后一拍）→ 帧间空闲段，图案整帧生效
//============================================================================
`timescale 1ns/1ps

module tb_udp_v2;

localparam FRAME_PERIOD   = 4_166_667;
localparam PKTS_PER_FRAME = 1788;
localparam FRAMES         = 4;
localparam FRAME_WIRE     = (PKTS_PER_FRAME - 1) * 1500 + 900;  // 2681400
localparam WIRE_BYTES     = FRAMES * FRAME_WIRE;

reg         clk    = 1'b0;
reg         rstn   = 1'b0;
reg         en_pulse = 1'b0;
reg         raw10_en = 1'b1;
reg  [15:0] num    = 16'd0;      // 无限
reg  [15:0] ipg    = 16'd12;
reg  [47:0] dst_mac = 48'hffffffffffff;
reg  [47:0] src_mac = 48'heae85e0060c8;
reg  [31:0] src_ip  = 32'h0a000008;
reg  [31:0] dst_ip  = 32'h0a000002;
reg  [15:0] dlen    = 16'd1458;
reg  [15:0] sport   = 16'd0521;
reg  [15:0] dport   = 16'd2715;
reg  [1:0]  pat_mode = 2'b00;   //帧 f 用 f%4（挂在 fno_dbg 翻新）
wire [7:0]  tdata;
wire        tvalid;
wire        tlast;
wire [31:0] fno_dbg;
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
    .pat_gen_kill(1'b0),    //回归不带 kill（悬空 X 会让 start 门控变 X，2026-11-06 教训）
    .pat_mode(pat_mode),
    .dst_mac(dst_mac), .src_mac(src_mac),
    .src_ip(src_ip), .dst_ip(dst_ip),
    .udp_dlen(dlen), .src_port(sport), .dst_port(dport),
    .tdata(tdata), .tvalid(tvalid), .tlast(tlast), .tready(tready),
    .frame_num_o(fno_dbg)
);

//帧号翻新（帧末最后一拍）→ 下帧图案模式 = 帧号%4（帧间空闲段切换，整帧生效）
always @(fno_dbg) pat_mode = fno_dbg[1:0];

// ---- 捕获 ----
reg [7:0] mem [0:WIRE_BYTES-1];
reg       lastq [0:WIRE_BYTES-1];
integer   total     = 0;
integer   frame_start_cycle [0:FRAMES];
integer   cyc = 0;
integer   frames_seen = 0;
reg       prev_tvalid = 0;

always #1 cyc = cyc + 1;
integer rise_cnt = 0;
always @(posedge clk) begin
    if (tvalid && !prev_tvalid) begin
        rise_cnt = rise_cnt + 1;
        if (rise_cnt == 1)            frame_start_cycle[0] = cyc;   //帧 0 首包
        if (rise_cnt == PKTS_PER_FRAME + 1)  frame_start_cycle[1] = cyc;   //帧 1 首包
        if (rise_cnt == 2 * PKTS_PER_FRAME + 1) frame_start_cycle[2] = cyc; //帧 2 首包
        if (rise_cnt == 3 * PKTS_PER_FRAME + 1) frame_start_cycle[3] = cyc; //帧 3 首包
        if (frames_seen < FRAMES) frames_seen = frames_seen + 1;
    end
    prev_tvalid <= tvalid;
    if (tvalid && tready && total < WIRE_BYTES) begin
        mem[total]   = tdata;
        lastq[total] = tlast;
        total = total + 1;
    end
end

integer errors = 0;
integer i, j, k, p, base, d, g, gidx, pbase, off, f, t0, t1;
reg [15:0] sum;
reg [15:0] expb;
reg [9:0]  px0, px1, px2, px3;
reg [31:0] fno, offs;
integer    pkt_len;

// 期望像素（与 rtl/udp_pat_gen_v2.v pattern_quad 严格同步，2026-11-06）
// mode: 0=RGGB 彩条 1=横向灰度 2=垂直灰度 3=棋盘
function [9:0] exp_px;
    input integer pidx;              //帧内全局像素序号
    input integer mode;              //本帧图案模式（=帧号%4）
    integer c, r, rfull, bar;
    reg ron, gon, bon;
    begin
        c = pidx % 1920;
        rfull = pidx / 1920;
        r = rfull & 1;
        case (mode)
            1: exp_px = c >> 1;                              //横向灰度
            2: exp_px = (rfull >= 1024) ? 10'h3FF : rfull;   //垂直灰度（饱和）
            3: exp_px = (((c / 120) ^ (rfull / 120)) & 1) ? 10'h3FF : 10'h000; //棋盘
            default: begin                                   //RGGB 彩条
                bar = c / 240;           //0白 1黄 2青 3绿 4品红 5红 6蓝 7黑
                case (bar)
                    0: {ron, gon, bon} = 3'b111;
                    1: {ron, gon, bon} = 3'b110;
                    2: {ron, gon, bon} = 3'b011;
                    3: {ron, gon, bon} = 3'b010;
                    4: {ron, gon, bon} = 3'b101;
                    5: {ron, gon, bon} = 3'b100;
                    6: {ron, gon, bon} = 3'b001;
                    default: {ron, gon, bon} = 3'b000;
                endcase
                if (r == 0)
                    exp_px = (c % 2 == 0) ? (ron ? 10'h3FF : 10'h000)   //行偶：偶列 R
                                          : (gon ? 10'h3FF : 10'h000);  //      奇列 Gr
                else
                    exp_px = (c % 2 == 0) ? (gon ? 10'h3FF : 10'h000)   //行奇：偶列 Gb
                                          : (bon ? 10'h3FF : 10'h000);  //      奇列 B
            end
        endcase
    end
endfunction

// 期望帧号/偏移字节比较辅助（隐含在循环内）

initial begin
    repeat (20) @(posedge clk);
    rstn = 1'b1;
    repeat (50) @(posedge clk);
    en_pulse = 1'b1;
    @(posedge clk);
    en_pulse = 1'b0;

    wait (total == WIRE_BYTES);
    $display("[TB] captured %0d bytes, frames_seen=%0d", total, frames_seen);

    // ---- p0/p1 边界诊断 ----
    $display("[DUMP] p0 tail + p1 head:");
    for (i = 1494; i <= 1560; i = i + 1)
        $display("  [%0d] %02x tlast=%b", i, mem[i], lastq[i]);
    $display("[DUMP] p0 tlast positions:");
    for (i = 0; i < 1500; i = i + 1)
        if (lastq[i]) $display("  tlast at %0d (data=%02x)", i, mem[i]);
    $display("[DUMP] p1786 tail + p1787 head (f0):");
    for (i = 2680490; i <= 2680525; i = i + 1)
        $display("  [%0d] %02x tlast=%b", i, mem[i], lastq[i]);
    $display("[DUMP] frame0 wire total check: last tlast at:");
    for (i = 2681300; i <= 2681450; i = i + 1)
        if (lastq[i]) $display("  tlast at %0d", i);
    $display("[DUMP] frame0 ALL tlast positions (count + first 10):");
    begin : TLSCAN
        integer tl_cnt;
        tl_cnt = 0;
        for (i = 0; i < 2681401; i = i + 1) begin
            if (lastq[i]) begin
                tl_cnt = tl_cnt + 1;
                if (tl_cnt <= 10) $display("  tlast #%0d at %0d", tl_cnt, i);
            end
        end
        $display("  frame0 tlast total=%0d", tl_cnt);
    end

    // ---- 帧周期检查（帧起始间隔 ≈ FRAME_PERIOD×8ns，30.00fps）----
    for (f = 1; f < FRAMES; f = f + 1) begin
        t0 = frame_start_cycle[f] - frame_start_cycle[f-1];
        if ((t0 > FRAME_PERIOD * 8 + 100) || (t0 < FRAME_PERIOD * 8 - 100)) begin
            errors = errors + 1;
            $display("[FAIL] frame period f%0d = %0d ns (expect ~%0d)", f, t0, FRAME_PERIOD * 8);
        end
    end

    // ---- 逐包校验 ----
    for (f = 0; f < FRAMES; f = f + 1) begin
        fno = f;
        for (p = 0; p < PKTS_PER_FRAME; p = p + 1) begin
            base = f * FRAME_WIRE + p * 1500;
            pkt_len = (p == PKTS_PER_FRAME - 1) ? 900 : 1500;

            // 1) 帧长：tlast 应在每包末字节
            if (!lastq[base + pkt_len - 1]) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: tlast not at byte %0d", f, p, pkt_len);
            end
            // 包内其它字节不得有 tlast（抽样：只查前 3 与末 4）
            if (lastq[base] || lastq[base+1] || lastq[base+2] ||
                lastq[base+pkt_len-4] || lastq[base+pkt_len-3] || lastq[base+pkt_len-2]) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: stray tlast", f, p);
            end

            // 2) ETH 头
            if (mem[base] !== 8'hff || mem[base+1] !== 8'hff || mem[base+2] !== 8'hff ||
                mem[base+3] !== 8'hff || mem[base+4] !== 8'hff || mem[base+5] !== 8'hff) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: dst mac", f, p);
            end
            if (mem[base+6] !== src_mac[47:40] || mem[base+7] !== src_mac[39:32] ||
                mem[base+8] !== src_mac[31:24] || mem[base+9] !== src_mac[23:16] ||
                mem[base+10] !== src_mac[15:8] || mem[base+11] !== src_mac[7:0]) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: src mac", f, p);
            end
            if (mem[base+12] !== 8'h08 || mem[base+13] !== 8'h00) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: ethertype", f, p);
            end

            // 3) IP 头字段
            if (mem[base+14] !== 8'h45 || mem[base+15] !== 8'h00) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: ip ver/ihl", f, p);
            end
            if ({mem[base+16], mem[base+17]} !== (p == 1787 ? 16'd886 : 16'd1486)) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: ip len=%04x", f, p, {mem[base+16], mem[base+17]});
            end
            if (mem[base+22] !== 8'h40 || mem[base+23] !== 8'h11) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: ttl/proto", f, p);
            end
            if ({mem[base+26], mem[base+27]} !== src_ip[31:16] ||
                {mem[base+28], mem[base+29]} !== src_ip[15:0]) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: src ip", f, p);
            end
            if ({mem[base+30], mem[base+31]} !== dst_ip[31:16] ||
                {mem[base+32], mem[base+33]} !== dst_ip[15:0]) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: dst ip", f, p);
            end
            if ({mem[base+34], mem[base+35]} !== sport) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: src port", f, p);
            end
            if ({mem[base+36], mem[base+37]} !== dport) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: dst port", f, p);
            end
            if ({mem[base+38], mem[base+39]} !== (p == 1787 ? 16'd866 : 16'd1466)) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: udp len=%04x", f, p, {mem[base+38], mem[base+39]});
            end

            // 4) UDP checksum = 0
            if ({mem[base+40], mem[base+41]} !== 16'h0000) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: udp cs=%04x", f, p, {mem[base+40], mem[base+41]});
            end

            // 5) IP checksum：含校验和字节的全部 10 word 反码和应为 0xFFFF
            sum = 16'd0;
            for (k = 0; k < 10; k = k + 1) begin
                sum = sum + {mem[base+14+2*k], mem[base+15+2*k]};
                sum = (sum & 16'hffff) + (sum >> 16);
                sum = (sum & 16'hffff) + (sum >> 16);
            end
            if (sum !== 16'hffff) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: ip cksum sum=%04x", f, p, sum);
            end

            // 6) 元数据
            off = p * 1450;
            if ({mem[base+42], mem[base+43], mem[base+44], mem[base+45]} !== fno) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: meta frame=%08x", f, p,
                         {mem[base+42], mem[base+43], mem[base+44], mem[base+45]});
            end
            if ({mem[base+46], mem[base+47], mem[base+48], mem[base+49]} !== off) begin
                errors = errors + 1;
                $display("[FAIL] f%0d p%0d: meta off=%08x expect %08x", f, p,
                         {mem[base+46], mem[base+47], mem[base+48], mem[base+49]}, off);
            end

            // 7) RAW10 数据逐字节（前 8 字节/包抽全查首包；这里全查）
            d = pkt_len - 50;              // 本包 RAW10 数据字节数
            for (i = 0; i < d; i = i + 1) begin
                gidx = (off + i) / 5;      // 帧内全局组号
                j    = (off + i) % 5;      // 组内字节号
                pbase = gidx * 4;
                px0 = exp_px(pbase, f);
                px1 = exp_px(pbase + 1, f);
                px2 = exp_px(pbase + 2, f);
                px3 = exp_px(pbase + 3, f);
                case (j)
                    0: expb = px0[9:2];
                    1: expb = {px0[1:0], px1[9:4]};   //标准 MIPI RAW10（2026-11-03 同步 RTL 修正）
                    2: expb = {px1[3:0], px2[9:6]};
                    3: expb = {px2[5:0], px3[9:8]};
                    default: expb = px3[7:0];
                endcase
                if (mem[base + 50 + i] !== expb) begin
                    errors = errors + 1;
                    if (errors < 20)
                        $display("[FAIL] f%0d p%0d d%0d: got %02x expect %02x",
                                 f, p, i, mem[base + 50 + i], expb);
                end
            end
        end
    end

    if (errors == 0)
        $display("=== TB_UDP_V2: ALL CHECKS PASSED (%0d bytes, %0d frames) ===", total, FRAMES);
    else
        $display("=== TB_UDP_V2: %0d ERRORS ===", errors);
    $finish;
end

// 超时看门狗
initial begin
    // 边界逐拍跟踪
    forever begin
        @(posedge clk);
        if ((total >= 1497 && total <= 1503) || (total >= 2680498 && total <= 2680504))
            $display("  BEAT total=%0d tvalid=%b tdata=%02x tlast=%b state=%0d hdr_cnt=%0d pay_left=%0d ipg_cnt=%0d",
                total, tvalid, tdata, tlast, dut.state, dut.hdr_cnt, dut.pay_left, dut.ipg_cnt);
    end
end

initial begin
    forever begin
        @(posedge clk);
        if ((total >= 2680497) && (total <= 2680506))
            $display("  CYC tvalid=%b tdata=%02x tlast=%b state=%0d hdr_cnt=%0d pay_left=%0d ipg_cnt=%0d total=%0d",
                tvalid, tdata, tlast, dut.state, dut.hdr_cnt, dut.pay_left, dut.ipg_cnt, total);
    end
end

initial begin
    #300_000_000;   // 300ms 仿真时间
    $display("=== TB_UDP_V2 TIMEOUT: total=%0d ===", total);
    $finish;
end

endmodule
