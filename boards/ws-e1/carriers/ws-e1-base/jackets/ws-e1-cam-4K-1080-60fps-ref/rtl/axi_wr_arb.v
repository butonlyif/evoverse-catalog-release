//=====================================================================
// axi_wr_arb.v — AXI4 写口 2→1 仲裁（RR1 + 事务级锁定 + 单 outstanding）
// 规格   : doc/arbiter.md v1.2（已冻结）；实施计划 : doc/arbiter-impl-plan.md S1
// 拓扑   : S1=cam0_fw(bit1) / S0=cam1_fw(bit0) → DDR target0，同在 sys_clk_200m
// 语言   : 纯 Verilog-2001 可综合子集；无初始块/无 SV 结构
//
// 纪律（实现要点，全部对齐规格，勿"顺手优化"）：
//   1) 复位 last=0 → 首争用授 S1=cam0（§5.1，有意安排，注释与 T7 固化）
//   2) 运行期永不复位（§6）：rstn 仅上电复位树驱动一次，源切换/flush 不碰本模块
//   3) AW 仅授予拍捕获（§5.1 拍0）；锁定期两 S 口 awready 恒 0（单事务语义）
//   4) W 为半缓冲 skid：载入=S 握手、清除=M 握手、同拍载入优先、
//      s_wready = gnt & (!w_pend | m_wready) & ~w_done（§5.3 四规则；
//      !w_pend 项防 WVALID-first 下 beat 重复——v1.2 复核 P0，勿删）
//   5) w_done 后到：锁于 w_done 置位拍释放；W 永不到达：锁保持至复位（§5.2）
//   6) 空闲拍 m_bready=1（不楔死 DDR 口）；空闲拍 m_bvalid = DDR 违约 → 丢弃+stuck
//   7) 看门狗进展只认 M 口握手拍（W 数据 / B 响应），4096 拍无进展 → sticky stuck
//   8) vlog 纪律：寄存器/线网先声明后使用（声明块统置于功能段之前）
//=====================================================================

module axi_wr_arb (
    input  wire          clk,
    input  wire          rstn,               // 低有效异步；仅上电置位（§6）

    // ---------- S1 = cam0（bit1）----------
    input  wire          s1_awvalid,
    output wire          s1_awready,
    input  wire  [32:0]  s1_awaddr,          // 33 位原样透传，不拼接/裁剪（§4.1）
    input  wire  [7:0]   s1_awlen,
    input  wire  [2:0]   s1_awsize,
    input  wire  [1:0]   s1_awburst,
    input  wire  [5:0]   s1_awid,
    input  wire  [3:0]   s1_awqos,           // =1 必达 DDR（§4.1 写契约）
    input  wire  [3:0]   s1_awcache,
    input  wire          s1_awlock,
    input  wire          s1_wvalid,
    output wire          s1_wready,
    input  wire  [511:0] s1_wdata,
    input  wire  [63:0]  s1_wstrb,
    input  wire          s1_wlast,
    output wire          s1_bvalid,
    input  wire          s1_bready,
    output wire  [1:0]   s1_bresp,
    output wire  [5:0]   s1_bid,

    // ---------- S0 = cam1（bit0）----------
    input  wire          s0_awvalid,
    output wire          s0_awready,
    input  wire  [32:0]  s0_awaddr,
    input  wire  [7:0]   s0_awlen,
    input  wire  [2:0]   s0_awsize,
    input  wire  [1:0]   s0_awburst,
    input  wire  [5:0]   s0_awid,
    input  wire  [3:0]   s0_awqos,
    input  wire  [3:0]   s0_awcache,
    input  wire          s0_awlock,
    input  wire          s0_wvalid,
    output wire          s0_wready,
    input  wire  [511:0] s0_wdata,
    input  wire  [63:0]  s0_wstrb,
    input  wire          s0_wlast,
    output wire          s0_bvalid,
    input  wire          s0_bready,
    output wire  [1:0]   s0_bresp,
    output wire  [5:0]   s0_bid,

    // ---------- M 口 → DDR target0 ----------
    output wire          m_awvalid,
    input  wire          m_awready,
    output wire  [32:0]  m_awaddr,
    output wire  [7:0]   m_awlen,
    output wire  [2:0]   m_awsize,
    output wire  [1:0]   m_awburst,
    output wire  [5:0]   m_awid,
    output wire  [3:0]   m_awqos,
    output wire  [3:0]   m_awcache,
    output wire          m_awlock,
    output wire          m_wvalid,
    input  wire          m_wready,
    output wire  [511:0] m_wdata,
    output wire  [63:0]  m_wstrb,
    output wire          m_wlast,
    input  wire          m_bvalid,
    output wire          m_bready,
    input  wire  [1:0]   m_bresp,
    input  wire  [5:0]   m_bid,

    // ---------- 诊断（§7，69 位打包）----------
    // [68]    gnt_active（本拍有有效授予）
    // [67:66] gnt_eff（one-hot；授予拍即反映新授予，空闲为 00）
    // [65]    lock    [64] watchdog_stuck（sticky，含契约违约置位）
    // [63:48] txn_cnt S1（16b 饱和） [47:32] txn_cnt S0
    // [31:16] beat_cnt S1（16b 饱和） [15:0]  beat_cnt S0（写=M 口 W 数据握手）
    output wire [68:0]   dbg
);

//=====================================================================
// 0. 寄存器声明（先声明后使用——vlog 纪律）
//=====================================================================
// 仲裁状态
reg         lock_q;       // 事务锁：授予拍置位，收尾拍清除
reg         gnt_q;        // 归属：1=S1(cam0) 0=S0(cam1)；复位空
reg         last_q;       // 上次服务口；复位 0 → 首争用偏 S1（有意安排）
reg         b_seen_q;     // B 握手已发生（锁定期内）
reg         w_done_q;     // wlast 已在 M 口握手完成
// AW 载荷寄存器（仅授予拍捕获，§5.1）
reg         aw_pend_q;
reg  [32:0] awaddr_q;
reg  [7:0]  awlen_q;
reg  [2:0]  awsize_q;
reg  [1:0]  awburst_q;
reg  [5:0]  awid_q;
reg  [3:0]  awqos_q;
reg  [3:0]  awcache_q;
reg         awlock_q;
// W 半缓冲 skid（§5.3）
reg         w_pend_q;
reg [511:0] wdata_q;
reg [63:0]  wstrb_q;
reg         wlast_q;
// 看门狗与诊断（§5.6/§7）
reg [12:0]  wd_cnt_q;
reg         stuck_q;
reg [15:0]  txn1_q, txn0_q, beat1_q, beat0_q;

//=====================================================================
// 1. RR1 仲裁（§5.1）：req = sN_awvalid；空闲拍采样，req[~last] 优先
//=====================================================================
wire req_alt  = last_q ? s0_awvalid : s1_awvalid;   // ~last 口请求
wire req_same = last_q ? s1_awvalid : s0_awvalid;   // last 口请求
wire grant_en = ~lock_q & (req_alt | req_same);     // 空闲拍且有请求
wire win      = req_alt ? ~last_q : last_q;         // 本拍授予口（RR1：同请必翻转）

// 有效授予（含授予拍组合窗口）：拍0 的 W 早到捕获与 dbg 即用此值（§5.1 流水线）
wire [1:0] gnt_eff = grant_en ? (win ? 2'b10 : 2'b01)
                    : (lock_q   ? (gnt_q ? 2'b10 : 2'b01) : 2'b00);

//=====================================================================
// 2. 地址通道（§5.1 拍0 捕获 + §5.2 锁定期语义）
//=====================================================================
wire s1_awfire = grant_en &  win;                   // 胜者必有 awvalid（req 定义）
wire s0_awfire = grant_en & ~win;
assign s1_awready = rstn & s1_awfire;               // 复位期输出 ready=0（§6）
assign s0_awready = rstn & s0_awfire;

wire m_awfire = m_awvalid & m_awready;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        aw_pend_q <= 1'b0;  awaddr_q <= 33'd0; awlen_q <= 8'd0;
        awsize_q  <= 3'd0;  awburst_q <= 2'd0; awid_q  <= 6'd0;
        awqos_q   <= 4'd0;  awcache_q <= 4'd0; awlock_q <= 1'b0;
    end else if (grant_en) begin                        // 拍0 载荷捕获（授予拍仅此一次）
        aw_pend_q <= 1'b1;
        awaddr_q  <= win ? s1_awaddr  : s0_awaddr;
        awlen_q   <= win ? s1_awlen   : s0_awlen;
        awsize_q  <= win ? s1_awsize  : s0_awsize;
        awburst_q <= win ? s1_awburst : s0_awburst;
        awid_q    <= win ? s1_awid    : s0_awid;
        awqos_q   <= win ? s1_awqos   : s0_awqos;
        awcache_q <= win ? s1_awcache : s0_awcache;
        awlock_q  <= win ? s1_awlock  : s0_awlock;
    end else if (m_awfire) begin
        aw_pend_q <= 1'b0;                              // 清除后 m_awvalid 恒 0 直至锁释放
    end
end

assign m_awvalid = aw_pend_q & lock_q;
assign m_awaddr  = awaddr_q;
assign m_awlen   = awlen_q;
assign m_awsize  = awsize_q;
assign m_awburst = awburst_q;
assign m_awid    = awid_q;
assign m_awqos   = awqos_q;
assign m_awcache = awcache_q;
assign m_awlock  = awlock_q;

//=====================================================================
// 3. W 半缓冲 skid（§5.3 四规则）
//    载入=S 握手；清除=M 握手；同拍载入优先（满流水不断流）；
//    s_wready = gnt & (!w_pend | m_wready) & ~w_done
//      —— !w_pend 项：寄存器空时不等 DDR ready（WVALID-first 无重复，v1.2 P0）
//      —— ~w_done 项：单事务，末拍收完后不再接收（防 master 超发）
//=====================================================================
wire m_wfire = m_wvalid & m_wready;

// 防超发封堵：w_done_q 为寄存信号，M 口末拍（wlast）排空拍次拍才置位——
// 该一拍盲区内若 skid 恰好排空（m_wready=1），下一事务首拍会在旧锁内
// 提前 fire 并被当作旧事务发出（实测 burst1 首字经旧锁上 M 时从机已结束
// 事务而丢弃，整行数据前移 1 拍）。末拍当拍组合封锁消除盲区；合法 burst
// 末拍因 skid 滞后必早于 M 口 wlast fire ≥1 拍，不受影响。
wire wlast_m_fire = m_wfire & wlast_q;
wire s1_wready_w = gnt_eff[1] & (~w_pend_q | m_wready) & ~(w_done_q | wlast_m_fire);
wire s0_wready_w = gnt_eff[0] & (~w_pend_q | m_wready) & ~(w_done_q | wlast_m_fire);
assign s1_wready = rstn & s1_wready_w;
assign s0_wready = rstn & s0_wready_w;

wire s1_wfire = s1_wvalid & s1_wready_w;
wire s0_wfire = s0_wvalid & s0_wready_w;
wire s_wfire  = s1_wfire | s0_wfire;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        w_pend_q <= 1'b0; wdata_q <= 512'd0; wstrb_q <= 64'd0; wlast_q <= 1'b0;
    end else if (s_wfire) begin                         // 载入优先于清除（§5.3 规则2）
        w_pend_q <= 1'b1;
        wdata_q  <= gnt_eff[1] ? s1_wdata : s0_wdata;
        wstrb_q  <= gnt_eff[1] ? s1_wstrb : s0_wstrb;
        wlast_q  <= gnt_eff[1] ? s1_wlast : s0_wlast;
    end else if (m_wfire) begin
        w_pend_q <= 1'b0;
    end
end

assign m_wvalid = w_pend_q & lock_q;                    // W 门控不变式（§5.3/A8）
assign m_wdata  = wdata_q;
assign m_wstrb  = wstrb_q;
assign m_wlast  = wlast_q;

//=====================================================================
// 4. 锁与事务收尾（§5.2）
//    b_seen_q/w_done_q 为寄存状态：收尾拍 = 两者均立的最早拍
//      正常流（W 先于 B）：b_fire && w_done_q 拍即收尾（同拍再仲裁，+1 拍可授）
//      B 先于 W（违约）：置 stuck 不释放；w_done 置位拍（次拍可见）才释放
//      W 永不到达：锁保持至复位，看门狗同时置 stuck
//=====================================================================
wire b_fire       = m_bvalid & m_bready;
wire w_done_set   = m_wfire & m_wlast & lock_q;         // w_done：M 口 wlast 握手置位
wire lock_release = lock_q & (b_fire | b_seen_q) & w_done_q;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        lock_q   <= 1'b0;
        gnt_q    <= 1'b0;      // 复位授予空（§6）；last=0 → 首争用授 S1=cam0
        last_q   <= 1'b0;
        b_seen_q <= 1'b0;
        w_done_q <= 1'b0;
    end else begin
        if (grant_en) begin                             // 授予拍：锁存 grant + last（§5.1）
            gnt_q  <= win;
            last_q <= win;
            lock_q <= 1'b1;
        end else if (lock_release) begin
            lock_q   <= 1'b0;
            b_seen_q <= 1'b0;
            w_done_q <= 1'b0;
        end
        if (b_fire & lock_q & ~lock_release)            // 收尾拍置位与清零不打架
            b_seen_q <= 1'b1;
        if (w_done_set & ~lock_release)
            w_done_q <= 1'b1;
    end
end

//=====================================================================
// 5. B 通道（§5.5）：组合 mux by gnt，锁定期覆盖 B 全程（释放拍即握手拍）
//    空闲拍 m_bready=1（不楔死 DDR 口）；空闲拍 m_bvalid → 违约丢弃+stuck
//=====================================================================
assign m_bready  = rstn & (lock_q ? (gnt_q ? s1_bready : s0_bready) : 1'b1);
assign s1_bvalid = lock_q &  gnt_q & m_bvalid;
assign s0_bvalid = lock_q & ~gnt_q & m_bvalid;
assign s1_bresp  = m_bresp;                             // 载荷组合透传，valid 已按 gnt 门控
assign s0_bresp  = m_bresp;
assign s1_bid    = m_bid;
assign s0_bid    = m_bid;

//=====================================================================
// 6. 看门狗（§5.6）：仅 M 口握手拍算进展；>4096 拍无进展 → sticky stuck
//=====================================================================
wire wd_progress = m_wfire | b_fire;
wire wd_timeout  = lock_q & (wd_cnt_q == 13'd4096);

always @(posedge clk or negedge rstn) begin
    if (!rstn)                      wd_cnt_q <= 13'd0;
    else if (~lock_q | wd_progress) wd_cnt_q <= 13'd0;
    else if (~wd_timeout)           wd_cnt_q <= wd_cnt_q + 13'd1;
end

//=====================================================================
// 7. 违约检测（§5.2）+ 诊断计数（§7）
//=====================================================================
// B 先于 W 完成一拍以上（同拍 B+WLAST 宽限不误报；A9 的 RTL 侧实现）
wire viol_b_before_w = lock_q & b_seen_q & ~w_done_q;
// 空闲拍出现 B 响应：锁语义保证不应发生，丢弃（S 口 bvalid 已被 lock 门控）
wire viol_idle_bresp = ~lock_q & m_bvalid;

always @(posedge clk or negedge rstn) begin
    if (!rstn) stuck_q <= 1'b0;
    else if (wd_timeout | viol_b_before_w | viol_idle_bresp)
        stuck_q <= 1'b1;                                // sticky，复位前不清（§5.6）
end

// 完成事务数：收尾拍归属 gnt；完成 beat 数：M 口 W 数据握手归属 gnt（§7）
wire txn_inc1  = lock_release &  gnt_q;
wire txn_inc0  = lock_release & ~gnt_q;
wire beat_inc1 = m_wfire &  gnt_q;
wire beat_inc0 = m_wfire & ~gnt_q;

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
