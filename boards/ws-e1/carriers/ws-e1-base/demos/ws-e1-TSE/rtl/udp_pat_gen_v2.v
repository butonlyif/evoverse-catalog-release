/////////////////////////////////////////////////////////////////////////////
// Module    : udp_pat_gen_v2
// Function  : Gigabit UDP datapath generator
//             Mode1: 1080p RAW10 @30fps video stream (8B meta + RAW10 packed data)
//             Mode0: incrementing payload pattern (v1 compatible, for G6 test)
//             - 42B header pipelined; IP checksum accumulated during ETH bytes
//             - UDP checksum = 0x0000 (RFC768: unused; ETH CRC + meta/pixel
//               formula provide integrity)
//             - G11n16 重构：RAW10 图案路径（pattern_quad/frame_tick 帧节奏/
//               pat_mode）整体迁移到 200M 域 raw10_pat_src（与相机共用 FIFO
//               链路），本模块 RAW10 只剩 cam_r=1 一种组合（相机/图案源统一
//               走 cam 模式）；inc 线速流保留（debug 专用）。固件默认开机
//               网络服务模式（不发流）
//             - 8B meta per pkt: frame_num[31:0] + byte_offset[31:0], big endian
// Interface : AXI4-Stream (8bit) master; control regs compatible with v1
// Timing    : clk = 125MHz (tx_axis_clk); registered outputs; preload model
/////////////////////////////////////////////////////////////////////////////
`default_nettype none
`timescale 1 ns / 1 ns

module udp_pat_gen_v2 #(
    parameter DATA_PER_PKT   = 1450,
    parameter PKTS_PER_FRAME = 1788
)(
input  wire                     clk,
input  wire                     rstn,
input  wire                     pat_gen_en,
input  wire [15:0]              pat_gen_num,    //RAW10=frames(0=inf); inc=pkts(0=inf)
input  wire [15:0]              pat_gen_ipg,    //inc mode IPG (bytes, min 12)
input  wire                     raw10_en,       //1=RAW10 stream; 0=increment pattern
input  wire                     pat_gen_kill,   //包边界停车（0x208 bit3）：当前包 tlast 后回 S_IDLE；
                                                //start_pulse 自动清除。inc 无限流包间不回 S_IDLE、
                                                //en 撤除不停车，无此位无法干净切换模式（2026-11-06）
input  wire                     cam_en,         //G10：相机源（0x208 bit6）。cam_r=1 时 DATA 组字节取 cam_quad_i
input  wire                     cam_pkt_req,    //G10 pacer 发包请求（占用率达标，本模块仅 S_IDLE 采样）
input  wire                     cam_pkt_go,     //G11i pacer occ 电平（无状态门）：S_IPG 包间逐包门控
input  wire [8:0]               cam_pkt_len,    //G11n15 pacer 动态包长 min(290,occ) 组：S_IDLE 授予拍
                                                //采样锁存 grp_len_r；帧尾短包=occ 余数 → FIFO 精确排空
input  wire [39:0]              cam_quad_i,     //G11i 相机组（标准 async_fifo dout：rd 后一拍有效，读后粘滞）
input  wire                     cam_quad_valid, //G11i FIFO 非空
output wire                     cam_quad_rd,    //G11i 组读脉冲 → pacer/FIFO rd_en（提前装载拍一拍发出）
input  wire [47:0]              dst_mac,
input  wire [47:0]              src_mac,
input  wire [31:0]              src_ip,
input  wire [31:0]              dst_ip,
input  wire [15:0]              udp_dlen,       //inc mode UDP payload length
input  wire [15:0]              src_port,
input  wire [15:0]              dst_port,
output reg  [7:0]               tdata,
output reg                      tvalid,
output reg                      tlast,
input  wire                     tready,
output reg  [31:0]              frame_num_o,
output wire [9:0]               dbg_state_o     //{raw10_r,pat_en,inf,state[2:0],frame_tick,en_d1,0}
);

localparam  VER = 4'h4;
localparam  IHL = 4'h5;
localparam  TOS = 8'h00;
localparam  FLG = 5'h00;
localparam  TTL = 8'h40;
localparam  PTC = 8'h11;

localparam  IP_HDR_WORDS  = 4'd9;
localparam  META_BYTES    = 4'd8;
localparam  PKTS_M1       = 11'd1787;

localparam  S_IDLE = 3'h0;
localparam  S_HDR  = 3'h1;
localparam  S_DATA = 3'h2;
localparam  S_IPG  = 3'h3;
localparam  S_ARM  = 3'h4;      //装填态：参数锁存完成后再发首字节

reg  [2:0]                  state;
reg  [5:0]                  hdr_cnt;
reg  [10:0]                 pay_left;   //remaining payload bytes (1 = last beat)
reg                         pat_en;
reg                         kill_r;     //包边界停车请求（start_pulse 自动清）
reg                         infinite_en;
reg  [15:0]                 num_cnt;
reg  [15:0]                 ipg_r;
reg                         raw10_r;
reg                         cam_r;      //G10：相机源模式（start_pulse 锁存；cam_r=1 时 raw10_r 必为 1）
reg  [15:0]                 ipg_cnt;
reg  [15:0]                 ip_id;
reg  [16:0]                 ip_ck_r;
reg  [15:0]                 ip_cksum;
wire [7:0]                  udp_len_hi;
wire [7:0]                  udp_len_lo;
reg  [47:0]                 dst_mac_r;
reg  [47:0]                 src_mac_r;
reg  [31:0]                 src_ip_r;
reg  [31:0]                 dst_ip_r;
reg  [15:0]                 src_port_r;
reg  [15:0]                 dst_port_r;
reg  [15:0]                 udp_dlen_r;
reg  [9:0]                  p0, p1, p2, p3;
reg  [3:0]                  meta_cnt;
reg  [2:0]                  grp_byte;
reg  [10:0]                 grp_cnt;
reg  [7:0]                  inc_byte;
reg  [31:0]                 frame_num;
reg  [31:0]                 pkt_off;
reg  [10:0]                 pkt_idx;
reg  [8:0]                  grp_len_r;  //G11n15：cam 模式本包组数（S_IDLE 授予拍锁存 cam_pkt_len；
                                        //cam 每包回 S_IDLE → 逐包重锁；S_HDR 末拍重装 pay_left 用
                                        //锁存值——授予拍后 occ 波动不得影响本包长度。安全性：pacer
                                        //occ 读域永不虚高（写侧同步滞后偏小）→ 锁存值 ≤ FIFO 真实+1
                                        //（首组 rd 粘滞补偿）→ 不空读；帧尾写停收敛后锁存=真实 →
                                        //残组逐包收敛清空（尾包 L=occ，预读 1 组 + 新读 L-1）
reg                         en_d1;

wire                        acc = tvalid && tready;
//内部状态探针（板上经 CSR 0x096 读取）：输入 raw10_en 也在内，区分连线断 vs pulse 时序
assign dbg_state_o = {raw10_en, raw10_r, pat_en, infinite_en, state, 1'b0, en_d1, tvalid}; //G11n16：frame_tick 位随图案路径删除置 0
//G11n16：pkt_is_last_w 已删（RAW10 图案固定 1788 包/帧模型随路径迁移，
//cam 模式动态包长不再有"帧末包"常量概念）
wire [10:0]                 cam_pay_len  = 11'd8 + grp_len_r * 3'd5;           // 8B meta + 5B×N组
wire [15:0]                 cam_udp_len  = 16'd16 + grp_len_r * 3'd5;          // +8B UDP hdr
wire [15:0]                 ip_len_w = raw10_r ? (cam_udp_len + 16'd20)
                                               : (udp_dlen_r + 16'd28);
wire [10:0]                 payload_len = raw10_r ?
                    cam_pay_len :
                    (udp_dlen_r[10:0] + 11'd8);

//G11n16：pattern_quad 图案函数整体迁出至 rtl/raw10_pat_src.v（200M 域图案源），
//内容与 PC doc/pc_tools/raw10.py expected_image() 的同步契约随迁，此处不再维护。
wire [5:0]                  hdr_n  = hdr_cnt + 6'd1;
wire [3:0]                  meta_n = meta_cnt + 4'd1;
wire [2:0]                  grp_n  = grp_byte + 3'd1;
//G11n16：旧 payload_len（图案固定包长模型）/grp_total 已删——统一声明见上方
wire                        data_last_beat = (pay_left == 11'd1);
wire [15:0]                 ipg_lim = ipg_r;    //G11n16：raw10 分支删（cam 模式不经过 S_IPG）
//G11i：IPG 退出条件（FSM 与输出块 tvalid 必须同用——输出块原只看 ipg_cnt，
//S_IPG 等待 cam_pkt_go 期间 tvalid=1 空发 dst_mac[0] 字节流 → 包错位/全 0 组）
wire ipg_exit = (ipg_cnt >= ipg_lim) && (!cam_r || cam_pkt_go);

//G11i 组读协议（标准 async_fifo，非 FWFT）：rd 提前一拍——S_IDLE 授予拍读包首组、
//grp_byte==3 拍读下一组，装载拍（S_ARM / grp_byte==4）dout 已顶上（dout 读后粘滞）。
//dout_v 标记 dout 持有未装载组：帧末包尾 b3 预读的下一帧首组跨 S_IDLE 保留到
//S_ARM 装载（原 FWFT 版末包尾拍发 rd 却不装载 p → 每帧界净丢 1 组）。
reg  rd_d;                    // rd_en 打拍（标准 FIFO：rd 后一拍 dout 有效）
reg  dout_v;                  // dout 持有未装载进 p 的组
wire cam_arm_load = (state == S_ARM)  && cam_r && (rd_d || dout_v);
//G11k 修复：b4 装载条件 rd_d → (rd_d || dout_v)。rd_d 只活一拍（b3 rd 的下一
//拍）；若 MAC 背压恰在该拍 acc=0，装载被跳过、grp_byte 停在 4，acc 恢复时
//rd_d 已过期 → dout_v 置 1 却永远无人消费 → cam_quad_rd(!dout_v) 永久停发、
//读指针冻结（板级实证 R=378 冻结 → full 互锁死锁）。dout_v 在装载前保持，
//恢复拍照样装载；dout 读后粘滞，数据不丢。
//G11n15：包末组禁用 b3 预读与 b4 装载——cam 每包回 S_IDLE 后，下一包首组必须在
//授予拍重新读（S_ARM 装载）；若包末仍预读+装 p，S_IDLE 授予 rd（!dout_v 成立）
//会再读一组并在 S_ARM 覆盖 p → 每包净丢 1 组（sim pkt0 丢 M2 实证）。pay_left==2
//即 b3 拍（下一拍 b4 为载荷末字节）；pay_left==1 即 b4 拍（原 PKTS_M1 帧末抑制条件
//扩展 cam 每包）。
wire cam_grp_load = (state == S_DATA) && acc && (meta_cnt == META_BYTES) &&
                    (grp_byte == 3'd4) && (rd_d || dout_v) &&
                    !(raw10_r && (pay_left == 11'd1) &&
                      ((pkt_idx == PKTS_M1) || cam_r));
//G11n16c：S_IDLE 授予项补 !kill_r——kill 电平释放到 start_pulse 清 kill_r 之间
//（固件 StreamStop→CamGen 的 100µs 窗），cam_en/raw10 电平已恢复而 kill_r 锁存
//仍=1：原授予读照发、FSM 却被 kill_r 拦在 S_IDLE → 连续两拍双弹，标准 FIFO 单
//dout 寄存器首组被次拍覆盖 → 每次模式切换净丢 1 组（PC 端 byte_offset 断链
//整帧重组失败=板上"切一下画面冻结"）。S_DATA b3 预读不动（包边界停车需要）。
assign cam_quad_rd = cam_r && !dout_v && cam_quad_valid &&
                     ((state == S_IDLE && cam_pkt_req && !kill_r) ||
                      (state == S_DATA && acc && (meta_cnt == META_BYTES) &&
                       (grp_byte == 3'd3) &&
                       !(cam_r && (pay_left == 11'd2))));
always @(posedge clk or negedge rstn) begin
    if (!rstn) rd_d <= 1'b0;
    else       rd_d <= cam_quad_rd;
end
always @(posedge clk or negedge rstn) begin
    if (!rstn)             dout_v <= 1'b0;
    else if (cam_grp_load) dout_v <= 1'b0;    // b4 装载消费（rd_d 同拍：读即消费）
    else if (cam_arm_load) dout_v <= 1'b0;    // 包首装载消费
    else if (rd_d)         dout_v <= 1'b1;    // 新读成组；帧末包尾预读跨帧保留
end

// G11n15 包长锁存：S_IDLE 授予拍采样 pacer pkt_len_o（组合=min(290,occ)）。
// 与 S_IDLE 分支 pay_left 装载同拍同源 → pay_left/grp_len_r 恒一致。
always @(posedge clk or negedge rstn) begin
    if (!rstn)                               grp_len_r <= 9'd290;
    else if (state == S_IDLE && cam_pkt_req) grp_len_r <= cam_pkt_len;
end

// IP checksum current word (f(hdr_cnt))
reg [15:0] ip_word;
always @(*) begin
    case (hdr_cnt)
        4'd0:    ip_word = {VER, IHL, TOS};
        4'd1:    ip_word = ip_len_w;
        4'd2:    ip_word = ip_id;
        4'd3:    ip_word = 16'h0000;
        4'd4:    ip_word = {TTL, PTC};
        4'd5:    ip_word = src_ip_r[31:16];
        4'd6:    ip_word = src_ip_r[15:0];
        4'd7:    ip_word = dst_ip_r[31:16];
        4'd8:    ip_word = dst_ip_r[15:0];
        default: ip_word = 16'h0000;
    endcase
end

// Header current byte (f(hdr_cnt))
reg [7:0] hdr_byte;
always @(*) begin
    case (hdr_cnt)
        7'd0 : hdr_byte = dst_mac_r[47:40];
        7'd1 : hdr_byte = dst_mac_r[39:32];
        7'd2 : hdr_byte = dst_mac_r[31:24];
        7'd3 : hdr_byte = dst_mac_r[23:16];
        7'd4 : hdr_byte = dst_mac_r[15:8];
        7'd5 : hdr_byte = dst_mac_r[7:0];
        7'd6 : hdr_byte = src_mac_r[47:40];
        7'd7 : hdr_byte = src_mac_r[39:32];
        7'd8 : hdr_byte = src_mac_r[31:24];
        7'd9 : hdr_byte = src_mac_r[23:16];
        7'd10: hdr_byte = src_mac_r[15:8];
        7'd11: hdr_byte = src_mac_r[7:0];
        7'd12: hdr_byte = 8'h08;
        7'd13: hdr_byte = 8'h00;
        7'd14: hdr_byte = {VER, IHL};
        7'd15: hdr_byte = TOS;
        7'd16: hdr_byte = ip_len_w[15:8];
        7'd17: hdr_byte = ip_len_w[7:0];
        7'd18: hdr_byte = ip_id[15:8];
        7'd19: hdr_byte = ip_id[7:0];
        7'd20: hdr_byte = {FLG, 3'h0};
        7'd21: hdr_byte = 8'h00;
        7'd22: hdr_byte = TTL;
        7'd23: hdr_byte = PTC;
        7'd24: hdr_byte = ip_cksum[15:8];
        7'd25: hdr_byte = ip_cksum[7:0];
        7'd26: hdr_byte = src_ip_r[31:24];
        7'd27: hdr_byte = src_ip_r[23:16];
        7'd28: hdr_byte = src_ip_r[15:8];
        7'd29: hdr_byte = src_ip_r[7:0];
        7'd30: hdr_byte = dst_ip_r[31:24];
        7'd31: hdr_byte = dst_ip_r[23:16];
        7'd32: hdr_byte = dst_ip_r[15:8];
        7'd33: hdr_byte = dst_ip_r[7:0];
        7'd34: hdr_byte = src_port_r[15:8];
        7'd35: hdr_byte = src_port_r[7:0];
        7'd36: hdr_byte = dst_port_r[15:8];
        7'd37: hdr_byte = dst_port_r[7:0];
        7'd38: hdr_byte = udp_len_hi;
        7'd39: hdr_byte = udp_len_lo;
        7'd40: hdr_byte = 8'h00;
        7'd41: hdr_byte = 8'h00;
        default: hdr_byte = 8'h00;
    endcase
end

// Header next byte (f(hdr_cnt+1))
reg [7:0] hdr_byte_n;
always @(*) begin
    case (hdr_n)
        7'd0 : hdr_byte_n = dst_mac_r[47:40];
        7'd1 : hdr_byte_n = dst_mac_r[39:32];
        7'd2 : hdr_byte_n = dst_mac_r[31:24];
        7'd3 : hdr_byte_n = dst_mac_r[23:16];
        7'd4 : hdr_byte_n = dst_mac_r[15:8];
        7'd5 : hdr_byte_n = dst_mac_r[7:0];
        7'd6 : hdr_byte_n = src_mac_r[47:40];
        7'd7 : hdr_byte_n = src_mac_r[39:32];
        7'd8 : hdr_byte_n = src_mac_r[31:24];
        7'd9 : hdr_byte_n = src_mac_r[23:16];
        7'd10: hdr_byte_n = src_mac_r[15:8];
        7'd11: hdr_byte_n = src_mac_r[7:0];
        7'd12: hdr_byte_n = 8'h08;
        7'd13: hdr_byte_n = 8'h00;
        7'd14: hdr_byte_n = {VER, IHL};
        7'd15: hdr_byte_n = TOS;
        7'd16: hdr_byte_n = ip_len_w[15:8];
        7'd17: hdr_byte_n = ip_len_w[7:0];
        7'd18: hdr_byte_n = ip_id[15:8];
        7'd19: hdr_byte_n = ip_id[7:0];
        7'd20: hdr_byte_n = {FLG, 3'h0};
        7'd21: hdr_byte_n = 8'h00;
        7'd22: hdr_byte_n = TTL;
        7'd23: hdr_byte_n = PTC;
        7'd24: hdr_byte_n = ip_cksum[15:8];
        7'd25: hdr_byte_n = ip_cksum[7:0];
        7'd26: hdr_byte_n = src_ip_r[31:24];
        7'd27: hdr_byte_n = src_ip_r[23:16];
        7'd28: hdr_byte_n = src_ip_r[15:8];
        7'd29: hdr_byte_n = src_ip_r[7:0];
        7'd30: hdr_byte_n = dst_ip_r[31:24];
        7'd31: hdr_byte_n = dst_ip_r[23:16];
        7'd32: hdr_byte_n = dst_ip_r[15:8];
        7'd33: hdr_byte_n = dst_ip_r[7:0];
        7'd34: hdr_byte_n = src_port_r[15:8];
        7'd35: hdr_byte_n = src_port_r[7:0];
        7'd36: hdr_byte_n = dst_port_r[15:8];
        7'd37: hdr_byte_n = dst_port_r[7:0];
        7'd38: hdr_byte_n = udp_len_hi;
        7'd39: hdr_byte_n = udp_len_lo;
        7'd40: hdr_byte_n = 8'h00;
        7'd41: hdr_byte_n = 8'h00;
        default: hdr_byte_n = 8'h00;
    endcase
end

// UDP length bytes（G11n16：图案固定包长分支删，raw10_r 蕴含 cam_r）
wire [15:0] udp_len_w = raw10_r ? cam_udp_len : (udp_dlen_r + 16'd8);
assign udp_len_hi = udp_len_w[15:8];
assign udp_len_lo = udp_len_w[7:0];

// DATA next byte (f(meta_n/grp_n))
reg [7:0] data_next_b;
reg [39:0] quad_nxt;
always @(*) begin
    quad_nxt = 40'h0;
    if (!raw10_r)
        data_next_b = inc_byte + 8'd1;
    else if (meta_cnt == META_BYTES - 4'd1)
        data_next_b = p0[9:2];                   // meta[7] -> group0 b0
    else if (meta_cnt != META_BYTES)
        case (meta_n)
            4'd1:    data_next_b = frame_num[23:16];
            4'd2:    data_next_b = frame_num[15:8];
            4'd3:    data_next_b = frame_num[7:0];
            4'd4:    data_next_b = pkt_off[31:24];
            4'd5:    data_next_b = pkt_off[23:16];
            4'd6:    data_next_b = pkt_off[15:8];
            4'd7:    data_next_b = pkt_off[7:0];
            default: data_next_b = 8'h00;
        endcase
    else if (grp_byte == 3'd4) begin
        quad_nxt = cam_quad_i;                  //G11n16：组数据只来自相机/图案 FIFO（cam_quad_i）
        data_next_b = quad_nxt[39:32];           // 下组 b0 = P1[9:2]
    end
    else
        // 标准 MIPI CSI-2 RAW10 打包（无损 10bit×4px = 5B）：
        // b1={P1[1:0],P2[9:4]} b2={P2[3:0],P3[9:6]} b3={P3[5:0],P4[9:8]} b4=P4[7:0]
        // （2026-11-03 修正：原 {p0[1:0],p1[7:2]} 交错映射丢失 P2/P3/P4 的 [9:8]）
        case (grp_n)
            3'd1:    data_next_b = {p0[1:0], p1[9:4]};
            3'd2:    data_next_b = {p1[3:0], p2[9:6]};
            3'd3:    data_next_b = {p2[5:0], p3[9:8]};
            default: data_next_b = p3[7:0];
        endcase
end

/*----------------------------------------------------------------------------------*/

// start pulse sync
always @(posedge clk or negedge rstn) begin
    if (!rstn) en_d1 <= 1'b0;
    else       en_d1 <= pat_gen_en;
end
wire start_pulse = pat_gen_en && !en_d1;

//G11n16：frame_timer/frame_tick 已删——RAW10 图案帧节奏迁至 200M 域
//raw10_pat_src（帧节拍由图案源自产，gen 仅按 pacer req 消费）

// mode/params latch on start pulse
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        ipg_r       <= 16'd12;
        raw10_r     <= 1'b0;
        cam_r       <= 1'b0;
        udp_dlen_r  <= 16'd1458;
        dst_mac_r   <= 48'h0;
        src_mac_r   <= 48'h0;
        src_ip_r    <= 32'h0;
        dst_ip_r    <= 32'h0;
        src_port_r  <= 16'h0;
        dst_port_r  <= 16'h0;
    end else begin
        dst_mac_r  <= dst_mac;
        src_mac_r  <= src_mac;
        src_ip_r   <= src_ip;
        dst_ip_r   <= dst_ip;
        src_port_r <= src_port;
        dst_port_r <= dst_port;
        if (start_pulse) begin
            ipg_r       <= (pat_gen_ipg < 16'd12) ? 16'd12 : pat_gen_ipg;
            raw10_r     <= raw10_en;
            cam_r       <= cam_en && raw10_en;   //G10：相机源仅在 RAW10 模式有意义
            udp_dlen_r  <= udp_dlen;
        end
    end
end

// 发包计数（单一驱动块：start_pulse 装载 + 包尾递减；num_cnt/infinite_en
// 原在 latch/settle 两块赋值，综合报 VDB-1000 多驱动）
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        num_cnt     <= 16'd0;
        infinite_en <= 1'b0;
    end else if (start_pulse) begin
        num_cnt     <= pat_gen_num;
        infinite_en <= (pat_gen_num == 16'd0);
    end else if (acc && tlast && !infinite_en && (num_cnt != 16'd0) &&
                 (!raw10_r || (pkt_idx == PKTS_M1))) begin
        num_cnt <= num_cnt - 16'd1;                 //inc 每包减；RAW10 每帧末包减
    end
end

// 包边界停车（2026-11-06 PC 运行时模式切换）：kill 电平锁存到当前包 tlast 边界
// 生效（S_DATA 末拍/S_IPG 即回 S_IDLE）。start_pulse 自动清，重启引擎即解除。
always @(posedge clk or negedge rstn) begin
    if (!rstn)              kill_r <= 1'b0;
    else if (start_pulse)   kill_r <= 1'b0;
    else if (pat_gen_kill)  kill_r <= 1'b1;
end

// FSM
always @(posedge clk or negedge rstn) begin
    if (!rstn)
        state <= S_IDLE;
    else case (state)
        //G11n16：frame_tick 启动分支已删（图案帧节奏迁 200M 域 raw10_pat_src，
        //图案源经 FIFO 链路走 cam 模式）。S_IDLE 启动只剩两条：
        //  start_pulse && !cam_en   → inc debug 线速流
        //  cam_r && cam_pkt_req     → 相机/图案源 FIFO 链路（pacer 节奏发包）
        S_IDLE: if ((start_pulse && !cam_en && !pat_gen_kill) ||
                   (cam_r && cam_pkt_req && !kill_r))      //G10：pacer 节奏发包
                    state <= S_ARM;
        S_ARM:  state <= S_HDR;                     //参数已锁存 1 拍，装填首字节
        S_HDR:  if (acc && (hdr_cnt == 7'd41))
                    state <= S_DATA;
        S_DATA: if (acc && data_last_beat) begin
                    //G11n15：cam 模式每包必回 IDLE——动态包长 grp_len_r 只在 S_IDLE
                    //授予拍重锁，原 S_IPG→S_HDR 链路径绕过 S_IDLE，burst 首包的 L
                    //粘滞整段（occ 小时 L=1 → 读侧饿死 → FIFO 积压 → 帧尾不排空 →
                    //下一帧魔数被残组顶开；sim FRAME0 full_rej=5174 实证）。
                    //kill：当前包发完即停（包边界干净停车，防 mid-frame 撕帧）
                    //G11n16：raw10_r 蕴含 cam_r（图案直发路径删），S_DATA 末拍
                    //只剩 cam_r → S_IDLE 与 inc → S_IPG 两种组合
                    if (cam_r || kill_r)
                        state <= S_IDLE;
                    else
                        state <= S_IPG;
                end
        //S_IPG 仅 inc 模式包间链（G11n16：cam/图案模式每包回 S_IDLE，不经过此态）。
        //历史注释（G11n15c）：原"切不过图案"实为 PC 端 raw10.py _pending 缺陷；
        //G11n15b 的 !cam_en 劫持每包回 S_IDLE 曾破坏包内链，已回退。
        S_IPG:  if (ipg_exit)
                    state <= S_HDR;  //帧内下一包
        default: state <= S_IDLE;
    endcase
end

// IPG counter
always @(posedge clk or negedge rstn) begin
    if (!rstn)               ipg_cnt <= 16'h0;
    else if (state == S_IPG) ipg_cnt <= ipg_cnt + 16'd1;
    else                     ipg_cnt <= 16'h0;
end

// header position
always @(posedge clk or negedge rstn) begin
    if (!rstn)                hdr_cnt <= 6'd0;
    else if (state == S_HDR) begin
        if (acc) hdr_cnt <= (hdr_cnt == 7'd41) ? 6'd0 : hdr_cnt + 6'd1;
    end else                  hdr_cnt <= 6'd0;
end

// IP checksum accumulate (per-packet reset at hdr_cnt==0)
always @(posedge clk or negedge rstn) begin
    if (!rstn)                ip_ck_r <= 17'd0;
    else if (acc && (state == S_HDR)) begin
        if (hdr_cnt == 4'd0)
            ip_ck_r <= ip_word;                               //首 word，清累计
        else if (hdr_cnt <= IP_HDR_WORDS - 4'd1)
            ip_ck_r <= ip_ck_r[15:0] + ip_word + ip_ck_r[16];
        else if (hdr_cnt == IP_HDR_WORDS)
            ip_ck_r <= {1'b0, ip_ck_r[15:0]} + ip_ck_r[16];
    end
end
always @(posedge clk or negedge rstn) begin
    if (!rstn)            ip_cksum <= 16'h0;
    else if (acc && (state == S_HDR) && (hdr_cnt == IP_HDR_WORDS + 4'd1))
        ip_cksum <= ~ip_ck_r[15:0];
end

// IP ID increment per packet
always @(posedge clk or negedge rstn) begin
    if (!rstn)             ip_id <= 16'h0;
    else if (acc && tlast) ip_id <= ip_id + 16'd1;
end

// packet/frame settle at tlast（仅 RAW10；num_cnt/infinite_en 归发包计数单一驱动块）
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        frame_num   <= 32'h0;
        frame_num_o <= 32'h0;
        pkt_off     <= 32'h0;
        pkt_idx     <= 11'd0;
    end else if (acc && tlast && raw10_r) begin
        if (pkt_idx == PKTS_M1) begin
            frame_num   <= frame_num + 32'd1;
            frame_num_o <= frame_num + 32'd1;
            pkt_idx     <= 11'd0;
            pkt_off     <= 32'h0;
        end else begin
            pkt_idx <= pkt_idx + 11'd1;
            pkt_off <= pkt_off + DATA_PER_PKT;
        end
    end
end

// run level
always @(posedge clk or negedge rstn) begin
    if (!rstn)                                              pat_en <= 1'b0;
    else if (start_pulse)                                   pat_en <= 1'b1;
    else if (acc && tlast && !infinite_en && (num_cnt == 16'd1))
        pat_en <= 1'b0;
    else if (kill_r && (state == S_IDLE))                   pat_en <= 1'b0; //停车后熄火
end

// DATA phase counters and pixel group advance
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        pay_left  <= payload_len;
        meta_cnt  <= 4'd0;
        grp_byte  <= 3'd0;
        grp_cnt   <= 11'd0;
        inc_byte  <= 8'h00;
        p0 <= 10'd0; p1 <= 10'd0; p2 <= 10'd0; p3 <= 10'd0;
    end else if (state == S_IDLE) begin
        //G11n15：cam 模式用授予拍 cam_pkt_len 组合（与 grp_len_r 锁存同拍同源）
        pay_left  <= (raw10_r && cam_r) ? (11'd8 + cam_pkt_len * 3'd5) : payload_len;
        meta_cnt  <= 4'd0;
        grp_byte  <= 3'd0;
        grp_cnt   <= 11'd0;
        inc_byte  <= 8'h00;
        //G11n16：图案首组装载已删（图案路径迁 200M 域）；cam 模式首组在 S_ARM 从 FIFO 预载
    end else if ((state == S_ARM) && cam_r && (rd_d || dout_v)) begin
        {p0, p1, p2, p3} <= cam_quad_i;                     //G11i：S_IDLE 授予拍 rd 已读出（或跨帧保留组）
    end else if ((state == S_HDR) && acc && (hdr_cnt == 7'd41)) begin
        //G11n15：cam 用锁存 grp_len_r（授予拍后 occ 波动不影响本包长度）
        pay_left  <= (raw10_r && cam_r) ? cam_pay_len : payload_len;
        meta_cnt <= raw10_r ? 4'd0 : 4'd8;
        grp_byte <= 3'd0;
        grp_cnt  <= 11'd0;
    end else if ((state == S_DATA) && acc) begin
        pay_left <= (pay_left == 11'd1) ? 11'd0 : pay_left - 11'd1;
        if (!raw10_r) begin
            inc_byte <= inc_byte + 8'd1;
        end else if (meta_cnt == META_BYTES - 4'd1) begin
            meta_cnt <= META_BYTES;
            grp_byte <= 3'd0;
        end else if (meta_cnt != META_BYTES) begin
            meta_cnt <= meta_n;
        end else begin
            grp_byte <= (grp_byte == 3'd4) ? 3'd0 : grp_n;
            if (grp_byte == 3'd4) begin
                grp_cnt <= grp_cnt + 11'd1;
                if (cam_r && (rd_d || dout_v))              //G11i/G11k：组数据取 FIFO（标准 dout），
                    {p0, p1, p2, p3} <= cam_quad_i;         //b4 即时装载或 acc 空洞后补偿装载
            end
        end
    end
end

// outputs (preload model)
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        tvalid <= 1'b0;
        tlast  <= 1'b0;
        tdata  <= 8'h00;
    end else begin
        if (state == S_IDLE) begin
            tvalid <= 1'b0;
        end else if (state == S_ARM) begin
            //仅驱动输出寄存器；参数/计数装填全部在 DATA counters 块的 S_IDLE 分支
            //完成（此处重复赋值会对 pay_left/meta_cnt/.../p0..p3 多驱动，综合报 VDB-1000）
            tvalid <= 1'b1;
            tlast  <= 1'b0;
            tdata  <= hdr_byte;
        end else if (acc) begin
            if (state == S_HDR) begin
                tlast  <= 1'b0;
                if (hdr_cnt == 7'd41)
                    tdata <= raw10_r ? frame_num[31:24] : inc_byte;  //DATA 首字节
                else
                    tdata <= hdr_byte_n;         //下一包头字节
            end else if (state == S_DATA) begin
                if (data_last_beat) begin
                    tvalid <= 1'b0;
                    tdata  <= 8'h00;
                end else begin
                    tlast <= (pay_left == 11'd2);  //下一拍=末拍（0 基）
                    tdata <= data_next_b;
                end
            end
        end else if ((state == S_IPG) && !kill_r) begin
            // IPG 末两拍：先预装包头字节 0（tdata）；FSM 切入 S_HDR 的同沿置 tvalid——
            // 保证 tvalid=1 的第一拍正好是 S_HDR 首拍（hdr_cnt=0，发送字节 0）
            // （帧末包发完直接回 IDLE，不经过 S_IPG，故此处仅在包间有效）
            // kill 拦截：kill 时本分支不得置 tvalid，否则停车沿冒出 1 拍假数据
            if (ipg_cnt == ipg_lim - 16'd2)
                tdata <= dst_mac_r[47:40];
            else if (ipg_exit) begin
                tvalid <= 1'b1;
                tlast  <= 1'b0;
            end
        end
    end
end

endmodule

`default_nettype wire
