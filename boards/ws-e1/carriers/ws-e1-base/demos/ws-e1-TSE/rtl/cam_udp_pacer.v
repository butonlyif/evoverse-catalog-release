/////////////////////////////////////////////////////////////////////////////
// Module    : cam_udp_pacer
// Function  : 相机 RAW10 UDP 推流的发包流控（125M 域）—— G11n15 纯流式
//             演进：G11n8 单门限流控（occ≥START_THR 才放行）解决浅 FIFO
//             (8192) 时代包内断流（门限=包级预缓冲）。G11n14 深缓冲
//             (163,840 组 bank 拼接) 零拒收后暴露帧对齐缺陷：发送窗
//             （写侧 sof_tg 复位 quad_idx / frame_active 窗）与实际读出
//             数据帧不同相——深 FIFO 流水滞后 ~0.45 帧，gen 的帧号边界
//             相对数据流错位 → PC 按 fn/off 重组上下/左右错位+列相位
//             色偏（板测"左移后左紫右绿 + 上下偏移"，G11n13 定案的帧内
//             净积吸收正常，纯帧界语义问题）。
//             G11n15 方案：帧界标记随数据走（写侧 sof 在 FIFO 数据流
//             帧首前插 2 组魔数 40'hFFFFFFFFFF + 40'h0000000000），发送
//             改纯流式：
//               req/go = cam_en && occ>0（START_THR 删除——动态包长
//               min(290,occ) 保证包内绝不断流，且帧尾精确排空到 0；
//               门限 2048 会在帧尾滞留 2047 组 → 下一帧魔数前粘残组）
//               pkt_len_o = min(QUADS_PER_PKT, occ)（gen S_IDLE 授予拍
//               采样）。occ 读域同步偏小方向安全（写活跃时真实 ≥ 读数；
//               写停后逐拍收敛）→ 不会空读重复组；帧尾段写已停、occ 收
//               敛后精确清零。
//             每帧 FIFO 全排空（帧尾 17.35ms gap > 排空 ~12ms 含 IPG）
//             → 下一帧魔数天然在 FIFO 头 → 数据流按帧分节，帧界由 PC
//             端魔数切帧（raw10.py FrameReassembler），gen 元数据 fn/off
//             仅作兼容填充。误检/漏检每帧自愈（每帧头重新对齐）。
//             帧边界：写侧每帧 sof 翻转 toggle（200M）→ 本模块边沿检测
//             仅用于 occ_min/peak 探针清零（观测跟写帧走）。
// Interface : cam_pkt_req 电平（gen 在 S_IDLE 才采样）；pkt_len_o 同拍
//             采样；cam_quad_rd 为 udp_pat_gen_v2 每组消费脉冲。
// Timing    : clk = 125MHz (tx_axis_clk)
/////////////////////////////////////////////////////////////////////////////
`default_nettype none
`timescale 1 ns / 1 ns

module cam_udp_pacer #(
    parameter QUADS_PER_PKT = 290,       // 1450B/5B，满包组数
    parameter FIFO_AW       = 18         //G11n14：bank 拼接 FIFO 总深 163,840 → 占用 18 位
)(
    input  wire                     clk,
    input  wire                     rstn,
    input  wire                     cam_en,        // CSR cam_src_en（125M 域准静态）
    input  wire                     pause_i,       //G11m：软暂停——1 时禁 go → gen 包边界停 S_IPG
    input  wire                     sof_toggle,    // 200M 每帧 sof 翻转（仅探针清零用）
    input  wire [FIFO_AW-1:0]       fifo_occ,      //G11n14：cam_fifo_bank 读域精确总占用
    input  wire                     cam_quad_rd,   // gen 每组消费脉冲
    input  wire [2:0]               gen_state,     // udp_pat_gen_v2 state（dbg_state_o[5:3]）
    output wire                     cam_pkt_req,   // 请求发包（gen S_IDLE 时采样）
    output wire                     cam_pkt_go,    //G11i occ 电平门：gen S_IPG 包间门控
    output wire [8:0]               pkt_len_o,     //G11n15：本包组数 = min(290, occ)（S_IDLE 采样）
                                                   //帧尾短包 = occ 余数 → FIFO 精确排空
    output reg  [31:0]              status_o,      //G11n15：{occ_ready,qidx[11:0],0,occ[17:0]}
                                                   //（qidx=消费自由计数观测；frame_active 位废）
    output reg  [31:0]              occ_dbg_o,     //G11n9 0x31C：{occ_min[15:0], occ_peak[15:0]}
                                                   //（>>2 粒度打包，读数×4）
    output reg                      fifo_rd_rst_n  // 流 FIFO 读侧软复位（恒 1，G11h 连续流语义）
);
    localparam [2:0] GEN_S_IDLE = 3'h0;

    // ---- G11n14：occ 直输（cam_fifo_bank 读域已做格雷同步+合成，滞后 2 拍）----
    reg [FIFO_AW-1:0] fifo_occ_r;
    always @(posedge clk or negedge rstn) begin
        if (!rstn)   fifo_occ_r <= {FIFO_AW{1'b0}};
        else         fifo_occ_r <= fifo_occ;
    end

    wire [FIFO_AW-1:0] occ = fifo_occ_r;         //G11n15 纯流式：occ>0 即发

    // ---- G11n15 动态包长：min(满包, occ)。组合直出，gen S_IDLE 授予拍采样。
    //      安全性：occ 读域同步偏小（写活跃时真实 ≥ 读数）→ 不空读；帧尾段
    //      写停后 occ 逐拍收敛 → 最后一包精确清零（滞后差 ≤2 组由下一包收走）----
    wire [FIFO_AW-1:0] occ_cap = (occ > QUADS_PER_PKT[FIFO_AW-1:0])
                                 ? QUADS_PER_PKT[FIFO_AW-1:0] : occ;
    assign pkt_len_o = occ_cap[8:0];

    // ---- 消费计数（观测：status qidx 自由计数，无帧语义——帧界由数据流魔数承担）----
    reg [18:0] quad_idx;
    always @(posedge clk or negedge rstn) begin
        if (!rstn)            quad_idx <= 19'd0;
        else if (cam_quad_rd) quad_idx <= quad_idx + 19'd1;
    end

    // ---- sof toggle 边沿检测（帧起点，仅 occ 探针清零用）----
    (* ASYNC_REG = "TRUE" *) reg [2:0] sof_sy;
    reg [1:0] rst_cnt;
    reg       sof_evt_r;                         // 帧边界一拍（本域，探针清零用）
    wire sof_evt = sof_sy[2] ^ sof_sy[1];
    always @(posedge clk or negedge rstn) begin
        if (!rstn) sof_sy <= 3'b000;
        else       sof_sy <= {sof_sy[1:0], sof_toggle};
    end
    always @(posedge clk or negedge rstn) begin
        if (!rstn) sof_evt_r <= 1'b0;
        else       sof_evt_r <= sof_evt;
    end

    // ---- 读侧软复位恒 1（G11h：连续流，删除 sof 指针复位脉冲）----
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rst_cnt       <= 2'b00;
            fifo_rd_rst_n <= 1'b1;
        end else begin
            rst_cnt <= 2'b00;
        end
    end

    // ---- 发包请求：纯流式（occ>0 即发）。包内不断流由 pkt_len=min(290,occ)
    //      保证（G11n8 门限的历史使命完成——门限 2048 在帧尾会滞留 2047 组，
    //      下一帧魔数前粘残组 → PC 帧界错，G11n15 删除）----
    wire occ_ready = (occ != {FIFO_AW{1'b0}});
    assign cam_pkt_req = cam_en && occ_ready && (gen_state == GEN_S_IDLE);
    //G11i：S_IPG 包间逐包门控电平（否则后续包背靠背 2× 相机速率排空 FIFO）
    assign cam_pkt_go = cam_en && !pause_i && occ_ready;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) status_o <= 32'h0;
        //G11n15 布局：bit31=occ_ready，bits30:19=qidx[11:0]（消费自由计数观测），
        //bit18=0（原 frame_active 废——帧界在数据流魔数），bits17:0=occ
        else       status_o <= {occ_ready, quad_idx[11:0], 1'b0, occ};
    end

    // ---- G11n9 occ 帧内峰值/谷值（sof 清零，观测跟写帧走）----
    reg [17:0] occ_peak, occ_min;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            occ_peak <= 18'h0;
            occ_min  <= 18'h3FFFF;
        end else if (sof_evt) begin
            occ_peak <= 18'h0;
            occ_min  <= 18'h3FFFF;
        end else begin
            if (occ > occ_peak) occ_peak <= occ;
            if (occ < occ_min)  occ_min  <= occ;
        end
    end
    always @(posedge clk or negedge rstn) begin
        if (!rstn)       occ_dbg_o <= 32'h0;
        else             occ_dbg_o <= {occ_min[17:2], occ_peak[17:2]};
    end

endmodule

`default_nettype wire
