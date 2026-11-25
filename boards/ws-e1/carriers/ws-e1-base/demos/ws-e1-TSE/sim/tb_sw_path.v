//============================================================================
// tb_sw_path : 软件帧（mux3 In2）→ MAC TX 联合仿真
// 例化板级顶层 ws_e1_tse（SIM_MODE：跳过 SoC），tb 模拟固件的 APB 写序列
// （按 main.c TEST_MODE=2 新版语义：mux=0x10 + promis + MAC + 计数清零 +
//   tick 帧 106B），判据：MAC 统计 aFramesTxOK（与板上读数同口径）+ RGMII ctl 帧计数
// 运行: vsim -c tb_sw_path -do "run -all; quit -f"
//============================================================================
`timescale 1ns/1ps
`define SIM_MODE

module tb_sw_path;

reg         clk_50m  = 1'b0;    //SoC/系统/APB
reg         clk_125m = 1'b0;    //axis + MAC TX 引擎域（板级真实：同接 clk_125m）
reg         rgmii_rxc = 1'b0;   //PHY RXC（MAC RX 域）
reg         pll_0_locked = 1'b0;
reg         pll_rgmii_locked = 1'b0;   //RX PLL 锁定瞬态：250ns 拉高（晚于 PLL0）
//顶层 mac_reset = ~pll_0_locked & ~pll_rgmii_locked（组合）。板上 PLL 上电需数百 ms
//才锁定，锁定前 mac_reset=1 复位 MAC；仿真必须复现这一过程，否则 MAC 引擎 FSM 为 X 态。
initial begin
    #200;
    pll_0_locked = 1'b1;    //模拟 PLL0 锁定
    #50;
    pll_rgmii_locked = 1'b1; //模拟 PLL_TR0(RXC) 锁定
end

always #10  clk_50m  = ~clk_50m;   //50MHz 板级真实（此前 100MHz 掩盖了 50M/125M 时钟比 bug）
always #4   clk_125m = ~clk_125m;  //125MHz 板级真实
always #4   rgmii_rxc = ~rgmii_rxc;//125MHz 板级真实

wire        pll_rstn;
wire        pll_rgmii_rstn;
wire [3:0]  rgmii_txd_HI, rgmii_txd_LO;
wire        rgmii_tx_ctl_HI, rgmii_tx_ctl_LO;
wire        rgmii_txc_HI, rgmii_txc_LO;
reg         rgmii_rxd0_HI = 0, rgmii_rxd0_LO = 0;
reg         rgmii_rxd1_HI = 0, rgmii_rxd1_LO = 0;
reg         rgmii_rxd2_HI = 0, rgmii_rxd2_LO = 0;
reg         rgmii_rxd3_HI = 0, rgmii_rxd3_LO = 0;
reg         rgmii_rx_ctl_HI = 0, rgmii_rx_ctl_LO = 0;
reg         phy_mdi = 1'b1;
wire        phy_mdo, phy_mdo_en, phy_mdc;

//SIM_MODE APB3 端口对应的 tb 侧驱动 reg（在 DUT 例化前声明）
reg  [15:0] apb3_paddr;
reg         apb3_psel;
reg         apb3_penable;
reg         apb3_pwrite;
reg  [31:0] apb3_pwdata;
wire        apb3_pready;
wire [31:0] apb3_prdata;
wire        apb3_pslverror;

ws_e1_tse dut (
    .clk                        (clk_50m),
    .clk_125m                   (clk_125m),
    .pll_0_locked               (pll_0_locked),
    .pll_rgmii_locked           (pll_rgmii_locked),
    .pll_rstn                   (pll_rstn),
    .pll_rgmii_rstn             (pll_rgmii_rstn),
    .rgmii_txd_HI               (rgmii_txd_HI),
    .rgmii_txd_LO               (rgmii_txd_LO),
    .rgmii_tx_ctl_HI            (rgmii_tx_ctl_HI),
    .rgmii_tx_ctl_LO            (rgmii_tx_ctl_LO),
    .rgmii_txc_HI               (rgmii_txc_HI),
    .rgmii_txc_LO               (rgmii_txc_LO),
    .rgmii_rxd0_HI              (rgmii_rxd0_HI),
    .rgmii_rxd0_LO              (rgmii_rxd0_LO),
    .rgmii_rxd1_HI              (rgmii_rxd1_HI),
    .rgmii_rxd1_LO              (rgmii_rxd1_LO),
    .rgmii_rxd2_HI              (rgmii_rxd2_HI),
    .rgmii_rxd2_LO              (rgmii_rxd2_LO),
    .rgmii_rxd3_HI              (rgmii_rxd3_HI),
    .rgmii_rxd3_LO              (rgmii_rxd3_LO),
    .rgmii_rx_ctl_HI            (rgmii_rx_ctl_HI),
    .rgmii_rx_ctl_LO            (rgmii_rx_ctl_LO),
    .pll_rgmii_rx_clk           (rgmii_rxc),
    .phy_mdi                    (phy_mdi),
    .phy_mdo                    (phy_mdo),
    .phy_mdo_en                 (phy_mdo_en),
    .phy_mdc                    (phy_mdc),
    //SIM_MODE：APB3 端口（tb 模拟 SoC master）
    .apb3_paddr                 (apb3_paddr),
    .apb3_psel                  (apb3_psel),
    .apb3_penable               (apb3_penable),
    .apb3_pwrite                (apb3_pwrite),
    .apb3_pwdata                (apb3_pwdata),
    .apb3_pready                (apb3_pready),
    .apb3_prdata                (apb3_prdata),
    .apb3_pslverror             (apb3_pslverror)
);

//-------- APB BFM：驱动顶层 APB 端口（模拟固件总线写序列） --------
task apb_wr(input [15:0] addr, input [31:0] data);
begin
    @(posedge clk_50m);
    apb3_paddr  = addr;
    apb3_pwdata = data;
    apb3_pwrite = 1'b1;
    apb3_psel   = 1'b1;
    apb3_penable= 1'b0;
    @(posedge clk_50m);
    apb3_penable = 1'b1;
    @(posedge clk_50m);
    while (apb3_pready !== 1'b1) @(posedge clk_50m);
    apb3_psel = 1'b0; apb3_penable = 1'b0;
    @(posedge clk_50m);
end
endtask

task apb_rd(input [15:0] addr, output [31:0] data);
begin
    @(posedge clk_50m);
    apb3_paddr  = addr;
    apb3_pwrite = 1'b0;
    apb3_psel   = 1'b1;
    apb3_penable= 1'b0;
    @(posedge clk_50m);
    apb3_penable = 1'b1;
    @(posedge clk_50m);
    while (apb3_pready !== 1'b1) @(posedge clk_50m);
    data = apb3_prdata;
    apb3_psel = 1'b0; apb3_penable = 1'b0;
    @(posedge clk_50m);
end
endtask

//固件寄存器地址（板上 CPU 视角全地址，16 位 APB）
localparam [15:0] R_CMD     = 16'hf810_0008,
                  R_MACLO   = 16'hf810_000C,
                  R_MACHI   = 16'hf810_0010,
                  R_MUX     = 16'hf810_0204,
                  R_FILT    = 16'hf810_0140,
                  R_TXSTAT  = 16'hf810_0248,
                  R_TXDATA  = 16'hf810_024C,
                  R_TXOK    = 16'hf810_0068;

integer tx_beat = 0;       //mux3 输出的 AXI 拍计数
integer ctl_frames = 0;    //RGMII ctl_LO 上升沿计数（帧数近似）
reg     ctl_d = 0;

always @(posedge clk_125m) begin
    if (dut.tx_axis_mac_tvalid && dut.tx_axis_mac_tready) tx_beat = tx_beat + 1;
end
always @(posedge clk_125m) begin
    ctl_d <= rgmii_tx_ctl_LO;
    if (rgmii_tx_ctl_LO && !ctl_d) ctl_frames = ctl_frames + 1;
end

//自测帧构造 + 发送（与固件 build_tick_frame / MacTxSend 逐行等价）
reg [7:0] frmb [0:127];
integer   frmlen;

task build_frame;
input [15:0] id;
integer i;
reg [31:0] sum;
begin
    for (i = 0; i < 6; i = i + 1) frmb[i] = 8'hff;      //dst MAC 广播
    frmb[6]  = 8'hea; frmb[7]  = 8'he8;                 //src MAC ea:e8:5e:00:60:c8
    frmb[8]  = 8'h5e; frmb[9]  = 8'h00;
    frmb[10] = 8'h60; frmb[11] = 8'hc8;
    frmb[12] = 8'h08; frmb[13] = 8'h00;                 //ethertype IPv4
    frmb[14] = 8'h45; frmb[15] = 8'h00;
    frmb[16] = 8'h00; frmb[17] = 8'd106;                //total len = 42+64
    frmb[18] = id[15:8]; frmb[19] = id[7:0];
    frmb[20] = 8'h00; frmb[21] = 8'h00;                 //IP csum 占位
    frmb[22] = 8'h40; frmb[23] = 8'h11;                 //TTL=64, proto=UDP
    frmb[26] = 8'h0a; frmb[27] = 8'h00;                 //SRC_IP 10.0.0.8
    frmb[28] = 8'h00; frmb[29] = 8'h08;
    frmb[30] = 8'h0a; frmb[31] = 8'h00;                 //DST_IP 10.0.0.2
    frmb[32] = 8'h00; frmb[33] = 8'h02;
    sum = 32'h0;                                        //IP 头校验和（14..33）
    for (i = 14; i < 34; i = i + 2)
        sum = sum + {16'h0, frmb[i], 8'h0, frmb[i+1]};
    sum = (sum & 32'h0000ffff) + (sum >> 16);
    sum = (sum & 32'h0000ffff) + (sum >> 16);
    sum = ~sum & 32'h0000ffff;
    frmb[24] = sum[15:8]; frmb[25] = sum[7:0];
    frmb[34] = 8'h05; frmb[35] = 8'h21;                 //SRC_PORT 1313
    frmb[36] = 8'h27; frmb[37] = 8'h15;                 //DST_PORT 10005
    frmb[38] = 8'h00; frmb[39] = 8'd72;                 //UDP len = 8+64
    frmb[40] = 8'h00; frmb[41] = 8'h00;                 //UDP csum off
    for (i = 0; i < 64; i = i + 1)
        frmb[42+i] = 8'h41 + (i % 26);                  //payload 'A'..'Z' 循环
    frmlen = 106;
end
endtask

task mac_tx_send;
integer i;
reg [31:0] v;
begin
    apb_rd(R_TXSTAT, v);                                //MacTxSend: 等 free >= len
    while ((v & 32'h0000_1FFF) < frmlen)
        apb_rd(R_TXSTAT, v);
    for (i = 0; i < frmlen; i = i + 1)                  //逐字节写，末字节带 tlast
        apb_wr(R_TXDATA, {23'h0, (i == frmlen-1), frmb[i]});
end
endtask

reg [31:0] v;

initial begin
    //上电稳定
    repeat (20) @(posedge clk_50m);

    //---- 固件 TEST_MODE=2 SwEchoRun 序列逐行复刻（全部 RMW，不碰 ena 位、无 proto 脉冲）----
    apb_wr(R_MUX, 32'h0000_0010);                                //MacPathMode(2)
    apb_rd(R_CMD, v); v = (v & ~32'h0000_0010) | 32'h0000_0010;  //promis_en=1 (RMW)
    apb_wr(R_CMD, v);
    //MacAddrSet(0,0)
    apb_wr(16'hf810_0188, 32'h0000_ffff);                        //dst MAC [47:32]
    apb_wr(16'hf810_0184, 32'hffff_ffff);                        //dst MAC [31:0]
    apb_wr(16'hf810_0180, 32'h0000_0000);                        //tx_dst_addr_ins=0
    apb_wr(R_MACHI,       32'h0000_eae8);                        //src MAC [47:32]
    apb_wr(R_MACLO,       32'h5e00_60c8);                        //src MAC [31:0]
    apb_rd(R_CMD, v); v = v & ~32'h0000_0200;                    //src_addr_ins(bit9)=0
    apb_wr(R_CMD, v);
    apb_wr(R_FILT, 32'h0000_0000);                               //broadcast_filter_en=0
    //MacCntClean：cnt_reset 脉冲（ena=1 状态下直接清，官方例程同款）
    apb_rd(R_CMD, v); v = v | 32'h8000_0000;
    apb_wr(R_CMD, v);
    repeat (50) @(posedge clk_50m);                              //≈1us
    apb_rd(R_CMD, v); v = v & ~32'h8000_0000;
    apb_wr(R_CMD, v);

    repeat (200) @(posedge clk_125m);

    //---- 发 3 帧 ----
    build_frame(1); mac_tx_send;
    repeat (5000) @(posedge clk_125m);
    build_frame(2); mac_tx_send;
    repeat (5000) @(posedge clk_125m);
    build_frame(3); mac_tx_send;
    repeat (20000) @(posedge clk_125m);

    //---- 读判据 ----
    begin : JUDGE
        reg [31:0] okt, txs;
        apb_rd(R_TXOK, okt);
        apb_rd(R_TXSTAT, txs);
        $display("[RESULT] aFramesTxOK=%0d  tx_beat=%0d  ctl_frames=%0d  TX_STATUS=%08x",
                 okt[15:0], tx_beat, ctl_frames, txs);
        if (okt[15:0] >= 3 && ctl_frames >= 3)
            $display("=== SW PATH: ALL 3 FRAMES CONSUMED BY MAC ===");
        else if (okt[15:0] == 0)
            $display("=== SW PATH: MAC CONSUMED NOTHING (板上现象复现) ===");
        else
            $display("=== SW PATH: PARTIAL %0d/3 ===", okt[15:0]);
    end
    $finish;
end

endmodule
`default_nettype wire
