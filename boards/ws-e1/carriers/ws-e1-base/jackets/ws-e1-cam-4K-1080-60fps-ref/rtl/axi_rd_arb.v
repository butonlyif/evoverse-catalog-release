//=====================================================================
// axi_rd_arb.v — AXI4 读口 2→1 仲裁（RR1 + 事务级锁定 + 单 outstanding）
// 规格   : doc/arbiter.md v1.2 §4.2/§5（读写同构）；同构底稿 : rtl/axi_wr_arb.v
// 拓扑   : S1=cam0_rd(bit1) 直连 / S0=cam1_rd_cdc(bit0) → DDR target1，
//          全口 148.5M（ACLK_1 = pixel_clk）
// 语言   : 纯 Verilog-2001 可综合子集；无初始块/无 SV 结构
//
// 纪律（实现要点，全部对齐规格，勿"顺手优化"）：
//   1) 复位 last=0 → 首争用授 S1=cam0（§5.1，有意安排，注释与 T7 固化）
//   2) 运行期永不复位（§6）：rstn 仅上电复位树驱动一次，源切换/flush 不碰本模块
//   3) AR 仅授予拍捕获（§5.1 拍0）；锁定期两 S 口 arready 恒 0（单事务语义）
//   4) R 为半缓冲 skid 的 1:2 demux（M→S，§5.3 四规则方向镜像）：
//      载入=M 口握手、清除=S 口握手、同拍载入优先、
//      m_rready = lock & (!r_pend | s_rfire)——!r_pend 项防 beat 重复
//      （v1.2 复核 P0 的读侧镜像，勿删）；rresp/rid/rlast 随 rdata 同拍
//      寄存（§5.5）；s{gnt}_rvalid = 寄存输出（valid-hold）
//   5) 读锁释放点（§5.2 实现修正）：= 末拍【宿侧】握手（s_rfire & rlast_q），
//      非 M 口 rlast 握手——1 深半缓冲下 M 口末拍握手时数据尚在 skid 未
//      交付，若彼时释放锁，s{gnt}_rvalid 随 lock 门控掉，master 永远等不到
//      rlast（死锁）。代价：事务间空拍 +1（§5.4 固有开销预算内）
//   6) 空闲拍 m_rready=1（不楔死 DDR 口）；空闲拍 m_rvalid → 丢弃+stuck
//   7) 看门狗进展只认 R 握手拍（M 口接收 / S 口交付），4096 拍无进展 →
//      sticky stuck
//   8) vlog 纪律：寄存器/线网先声明后使用（声明块统置于功能段之前）
//=====================================================================

module axi_rd_arb (
    input  wire          clk,
    input  wire          rstn,               // 低有效异步；仅上电置位（§6）

    // ---------- S1 = cam0（bit1）----------
    input  wire          s1_arvalid,
    output wire          s1_arready,
    input  wire  [32:0]  s1_araddr,          // 33 位原样透传，不拼接/裁剪（§4.1）
    input  wire  [7:0]   s1_arlen,
    input  wire  [2:0]   s1_arsize,
    input  wire  [1:0]   s1_arburst,
    input  wire  [5:0]   s1_arid,
    input  wire  [3:0]   s1_arqos,
    input  wire  [3:0]   s1_arcache,
    input  wire          s1_arlock,
    output wire          s1_rvalid,          // R 1:2 demux（M→S）
    input  wire          s1_rready,          // master 驱动，只采样不生成
    output wire [511:0]  s1_rdata,
    output wire [1:0]    s1_rresp,
    output wire          s1_rlast,
    output wire [5:0]    s1_rid,

    // ---------- S0 = cam1（bit0）----------
    input  wire          s0_arvalid,
    output wire          s0_arready,
    input  wire  [32:0]  s0_araddr,
    input  wire  [7:0]   s0_arlen,
    input  wire  [2:0]   s0_arsize,
    input  wire  [1:0]   s0_arburst,
    input  wire  [5:0]   s0_arid,
    input  wire  [3:0]   s0_arqos,
    input  wire  [3:0]   s0_arcache,
    input  wire          s0_arlock,
    output wire          s0_rvalid,
    input  wire          s0_rready,
    output wire [511:0]  s0_rdata,
    output wire [1:0]    s0_rresp,
    output wire          s0_rlast,
    output wire [5:0]    s0_rid,

    // ---------- M 口 → DDR target1 ----------
    output wire          m_arvalid,
    input  wire          m_arready,
    output wire [32:0]   m_araddr,
    output wire [7:0]    m_arlen,
    output wire [2:0]    m_arsize,
    output wire [1:0]    m_arburst,
    output wire [5:0]    m_arid,
    output wire [3:0]    m_arqos,
    output wire [3:0]    m_arcache,
    output wire          m_arlock,
    input  wire          m_rvalid,
    output wire          m_rready,
    input  wire [511:0]  m_rdata,
    input  wire [1:0]    m_rresp,
    input  wire          m_rlast,
    input  wire [5:0]    m_rid,

    // ---------- 诊断（§7，69 位打包，与 axi_wr_arb 同布局）----------
    // [68]    gnt_active [67:66] gnt_eff [65] lock [64] watchdog_stuck
    // [63:48] txn_cnt S1 [47:32] txn_cnt S0
    // [31:16] beat_cnt S1 [15:0] beat_cnt S0（读=S 口 R 数据交付握手）
    output wire [68:0]   dbg
);

//=====================================================================
// 0. 寄存器声明（先声明后使用——vlog 纪律）
//=====================================================================
// 仲裁状态
reg         lock_q;       // 事务锁：授予拍置位，末拍交付拍清除
reg         gnt_q;        // 归属：1=S1(cam0) 0=S0(cam1)；复位空
reg         last_q;       // 上次服务口；复位 0 → 首争用偏 S1（有意安排）
// AR 载荷寄存器（仅授予拍捕获，§5.1）
reg         ar_pend_q;
reg  [32:0] araddr_q;
reg  [7:0]  arlen_q;
reg  [2:0]  arsize_q;
reg  [1:0]  arburst_q;
reg  [5:0]  arid_q;
reg  [3:0]  arqos_q;
reg  [3:0]  arcache_q;
reg         arlock_q;
// R 半缓冲 skid（§5.3 方向镜像）
reg         r_pend_q;
reg [511:0] rdata_q;
reg [1:0]   rresp_q;
reg         rlast_q;
reg [5:0]   rid_q;
// 看门狗与诊断（§5.6/§7）
reg [12:0]  wd_cnt_q;
reg         stuck_q;
reg [15:0]  txn1_q, txn0_q, beat1_q, beat0_q;

//=====================================================================
// 1. RR1 仲裁（§5.1）：req = sN_arvalid；空闲拍采样，req[~last] 优先
//=====================================================================
wire req_alt  = last_q ? s0_arvalid : s1_arvalid;   // ~last 口请求
wire req_same = last_q ? s1_arvalid : s0_arvalid;   // last 口请求
wire grant_en = ~lock_q & (req_alt | req_same);     // 空闲拍且有请求
wire win      = req_alt ? ~last_q : last_q;         // 本拍授予口（RR1：同请必翻转）

// 有效授予（含授予拍组合窗口）：dbg 即用此值（§5.1 流水线）
wire [1:0] gnt_eff = grant_en ? (win ? 2'b10 : 2'b01)
                    : (lock_q   ? (gnt_q ? 2'b10 : 2'b01) : 2'b00);

//=====================================================================
// 2. 地址通道（§5.1 拍0 捕获 + §5.2 锁定期语义）
//=====================================================================
wire s1_arfire = grant_en &  win;                   // 胜者必有 arvalid（req 定义）
wire s0_arfire = grant_en & ~win;
assign s1_arready = rstn & s1_arfire;               // 复位期输出 ready=0（§6）
assign s0_arready = rstn & s0_arfire;

wire m_arfire = m_arvalid & m_arready;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        ar_pend_q <= 1'b0;  araddr_q <= 33'd0; arlen_q <= 8'd0;
        arsize_q  <= 3'd0;  arburst_q <= 2'd0; arid_q  <= 6'd0;
        arqos_q   <= 4'd0;  arcache_q <= 4'd0; arlock_q <= 1'b0;
    end else if (grant_en) begin                        // 拍0 载荷捕获（授予拍仅此一次）
        ar_pend_q <= 1'b1;
        araddr_q  <= win ? s1_araddr  : s0_araddr;
        arlen_q   <= win ? s1_arlen   : s0_arlen;
        arsize_q  <= win ? s1_arsize  : s0_arsize;
        arburst_q <= win ? s1_arburst : s0_arburst;
        arid_q    <= win ? s1_arid    : s0_arid;
        arqos_q   <= win ? s1_arqos   : s0_arqos;
        arcache_q <= win ? s1_arcache : s0_arcache;
        arlock_q  <= win ? s1_arlock  : s0_arlock;
    end else if (m_arfire) begin
        ar_pend_q <= 1'b0;                              // 清除后 m_arvalid 恒 0 直至锁释放
    end
end

assign m_arvalid = ar_pend_q & lock_q;
assign m_araddr  = araddr_q;
assign m_arlen   = arlen_q;
assign m_arsize  = arsize_q;
assign m_arburst = arburst_q;
assign m_arid    = arid_q;
assign m_arqos   = arqos_q;
assign m_arcache = arcache_q;
assign m_arlock  = arlock_q;

//=====================================================================
// 3. R 半缓冲 skid（§5.3 四规则，方向镜像：源=DDR，宿=master）
//    载入=M 口握手；清除=S 口握手；同拍载入优先（满流水不断流）；
//    m_rready = lock & (!r_pend | s_rfire)
//      —— !r_pend 项：寄存器空时不等 master ready（防 beat 重复，v1.2 P0 镜像）
//      —— 空闲拍恒 1（不楔死 DDR 口）；空闲拍 m_rvalid = 违约 → 丢弃+stuck
//=====================================================================
wire s1_rfire = r_pend_q & lock_q &  gnt_q & s1_rvalid & s1_rready;
wire s0_rfire = r_pend_q & lock_q & ~gnt_q & s0_rvalid & s0_rready;
wire s_rfire  = s1_rfire | s0_rfire;

assign m_rready = rstn & (lock_q ? (~r_pend_q | s_rfire) : 1'b1);
wire m_rfire = m_rvalid & m_rready;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        r_pend_q <= 1'b0; rdata_q <= 512'd0; rresp_q <= 2'd0;
        rlast_q <= 1'b0; rid_q <= 6'd0;
    end else if (m_rfire & lock_q) begin                // 载入优先于清除（§5.3 规则2）
        r_pend_q <= 1'b1;
        rdata_q  <= m_rdata;
        rresp_q  <= m_rresp;
        rlast_q  <= m_rlast;
        rid_q    <= m_rid;
    end else if (s_rfire) begin
        r_pend_q <= 1'b0;
    end
end

assign s1_rvalid = r_pend_q & lock_q &  gnt_q;          // 宿侧寄存输出（valid-hold）
assign s0_rvalid = r_pend_q & lock_q & ~gnt_q;
assign s1_rdata  = rdata_q;
assign s0_rdata  = rdata_q;
assign s1_rresp  = rresp_q;
assign s0_rresp  = rresp_q;
assign s1_rlast  = rlast_q;
assign s0_rlast  = rlast_q;
assign s1_rid    = rid_q;
assign s0_rid    = rid_q;

//=====================================================================
// 4. 锁与事务收尾（§5.2 + 头注释第5条实现修正）
//    读锁释放 = 末拍宿侧握手（s_rfire & rlast_q）：M 口 rlast 握手时数据
//    尚在 skid，彼时释放会门控掉 s{gnt}_rvalid → master 死锁。
//    收尾拍同拍进入再仲裁（下一授予最早 +1 拍，事务间空拍 2——预算内）
//=====================================================================
wire lock_release = lock_q & s_rfire & rlast_q;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        lock_q <= 1'b0;
        gnt_q  <= 1'b0;      // 复位授予空（§6）；last=0 → 首争用授 S1=cam0
        last_q <= 1'b0;
    end else if (grant_en) begin                        // 授予拍：锁存 grant + last（§5.1）
        gnt_q  <= win;
        last_q <= win;
        lock_q <= 1'b1;
    end else if (lock_release) begin
        lock_q <= 1'b0;
    end
end

//=====================================================================
// 5. 看门狗（§5.6）：仅 R 握手拍算进展；>4096 拍无进展 → sticky stuck
//=====================================================================
wire wd_progress = m_rfire | s_rfire;
wire wd_timeout  = lock_q & (wd_cnt_q == 13'd4096);

always @(posedge clk or negedge rstn) begin
    if (!rstn)                      wd_cnt_q <= 13'd0;
    else if (~lock_q | wd_progress) wd_cnt_q <= 13'd0;
    else if (~wd_timeout)           wd_cnt_q <= wd_cnt_q + 13'd1;
end

//=====================================================================
// 6. 违约检测（§5.2）+ 诊断计数（§7）
//=====================================================================
// 空闲拍出现 R 响应：锁语义保证不应发生，丢弃（S 口 rvalid 已被 lock 门控）
wire viol_idle_rresp = ~lock_q & m_rvalid;

always @(posedge clk or negedge rstn) begin
    if (!rstn) stuck_q <= 1'b0;
    else if (wd_timeout | viol_idle_rresp)
        stuck_q <= 1'b1;                                // sticky，复位前不清（§5.6）
end

// 完成事务数：末拍交付拍归属 gnt；完成 beat 数：S 口 R 数据交付握手归属 gnt（§7）
wire txn_inc1  = lock_release &  gnt_q;
wire txn_inc0  = lock_release & ~gnt_q;
wire beat_inc1 = s_rfire &  gnt_q;
wire beat_inc0 = s_rfire & ~gnt_q;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        txn1_q <= 16'd0; txn0_q <= 16'd0; beat1_q <= 16'd0; beat0_q <= 16'd0;
    end else begin
        if (txn_inc1  & (txn1_q  != 16'hFFFF)) txn1_q  <= txn1_q  + 16'd1;   // 饱和
        if (txn_inc0  & (txn0_q  != 16'hFFFF)) txn0_q  <= txn0_q  + 16'd1;
        if (beat_inc1 & (beat1_q != 16'hFFFF)) beat1_q <= beat1_q + 16'd1;
        if (beat_inc0 & (beat0_q != 16'hFFFF)) beat0_q <= beat0_q + 16'd1;
    end
end

assign dbg = { |gnt_eff, gnt_eff, lock_q, stuck_q,
               txn1_q, txn0_q, beat1_q, beat0_q };

endmodule
