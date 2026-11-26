////////////////////////////////////////////////////////////////////////////
//  ddr_test_top.sv — 最小 DDR 板测工程顶层（从 top_cam_demo.sv 裁剪重建）
//
//  保留的板级验证资产（勿改动时序/结构）：
//    - POR 发生器（i_clk_27m 256 拍）→ PLL 复位释放（同 top_cam_demo L450-472）
//    - LPDDR CFG FSM v5（lock 门控 + 2^21 拍等待，top_cam_demo L511-581，
//      板测 6 轮迭代结论，见原文件注释 v1~v5）
//    - ARSTN_0/1 = ddr_cfg_ok（CFG 完成后才释放 DDR AXI 复位）
//    - ddr_memcheck 阶段 0 形态（target0@sys_clk_200m，ALEN=119×3495 burst，
//      TOP_CAM_L863-915），TOTAL_BURSTS 参数化供 TG/仿真扫参数
//    - DIAG11 状态字（top_cam_demo L1124-1130 同位图）
//
//  变更（相对 top_cam_demo）：
//    - 去掉 2x top_cam / riscv_soc / CSI IP；APB DIAG 读出通道换成
//      ddr_status_uart（GPIOR_70/72 引脚复用，115200 8N1）
//    - peri.xml 裁剪：删 4 个 DPHY/3 个 CSI PLL/cam GPIO/JTAG USER1；
//      DDR target1 的 ACLK_1 从 pixel_clk 换绑 sys_clk_200m（本工程
//      target1 仅 tie-off，与 target0 同域即可）
//
//  上板判据（UART 终端直接看，13 字节帧 'DDR:'+8hex+'\n'）：
//    DDR:0000907e → err=0 mcst=9(DONE) done_raw=1 cfg_st=3
//    lock=1 cfg_ok=1 done=1 fail=0 —— 连续多帧稳定输出即 Phase 0 通过
////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module ddr_test_top #(
    parameter int MC_TOTAL_BURSTS   = 16'd16,   // TG Phase 1：每轮 16 burst（Phase 0 全扫改回 3495）
    parameter int MC_ALEN           = 8'd63,    // TG Phase 1：64 beat = 4KB（Phase 0 一行 UYVY 改回 119）
    parameter int MC_ASIZE          = 3'b110,   // 64B/beat
    parameter int UART_REPORT_TICKS = 320_000,  // 1.6ms/帧（Phase 4 补档时曾用
                                                // 340_000 移采样相位，已还原）
    // correlation Phase 1：TG OSTD 扫描（memcheck TG_MODE=1，仿真/板级同参数）
    // 板级 Phase 4 默认形态：TG_MODE=1 OSTD 扫描 + 双端口对称流量
    //（u_mc@target0 报告 + u_mc2@target1 负载，§8.5 竞争退化/公平性）
    //（Phase 7 形态 5，Phase 6 形态 4，Phase 3 形态 3，Phase 2/5 形态 2，历史见 plan §9）
    parameter int TG_MODE            = 1,       // 1=OSTD 扫描（5=容量/别名 4=OOO 3=固定速率 2=延迟 0=自检）
    parameter int TG_OSTD_MAX        = 16,      // 扫描终值（MODE1 用）
    parameter int TG_N_BURST         = 16,      // 每轮 burst 数（MODE0/1 用）
    parameter int TG_ROUND_GAP_TICKS = 400_000, // 轮/块间隔拍（板级 2ms@200M；MODE2 须 >200 拍供分位数迭代跑完）
    parameter int TG_LAT_WARMUP      = 100,     // 每相丢前 warm-up 笔数
    parameter int TG_LAT_P5_N        = 600,     // Phase 5 B 时机矩阵每块笔数
    parameter int UART_SCAN_MODE     = 1        // 1=扫描帧 {err_sat,rd_cyc,ostd,mcst}（MODE1；2=延迟轮发）
) (
    // 时钟 / 复位（peri pll_sys / pll_ddr）
    (* syn_peri_port = 0 *) input  i_clk_27m,       // POR 基准（gclk，27MHz 板晶）
    (* syn_peri_port = 0 *) input  sys_clk_100m,    // pll_sys#1（本工程不使用，peri 输出保留）
    (* syn_peri_port = 0 *) input  sys_clk_200m,    // pll_sys#2：DDR ACLK_0 / CFG FSM / UART 域
    (* syn_peri_port = 0 *) input  pll_sys_locked,
    (* syn_peri_port = 0 *) output pll_sys_rstn,
    (* syn_peri_port = 0 *) input  pll_ddr_locked,
    (* syn_peri_port = 0 *) output pll_ddr_rstn,

    // UART 读出（GPIOR_72/70，与 top_demo 相同引脚）
    (* syn_peri_port = 0 *) input  uart_0_rxd,
    (* syn_peri_port = 0 *) output uart_0_txd,

    // ---- DDR target0（peri DDR_0，ACLK_0 = sys_clk_200m）----
    (* syn_peri_port = 0 *) input  ddr_inst_ARREADY_0,
    (* syn_peri_port = 0 *) input  ddr_inst_AWREADY_0,
    (* syn_peri_port = 0 *) input  [5:0]  ddr_inst_BID_0,
    (* syn_peri_port = 0 *) input  [1:0]  ddr_inst_BRESP_0,
    (* syn_peri_port = 0 *) input  ddr_inst_BVALID_0,
    (* syn_peri_port = 0 *) input  ddr_inst_CFG_DONE,
    (* syn_peri_port = 0 *) input  ddr_inst_CTRL_BUSY,
    (* syn_peri_port = 0 *) input  [1:0]  ddr_inst_CTRL_CKE,
    (* syn_peri_port = 0 *) input  ddr_inst_CTRL_CMD_Q_ALMOST_FULL,
    (* syn_peri_port = 0 *) input  ddr_inst_CTRL_DP_IDLE,
    (* syn_peri_port = 0 *) input  ddr_inst_CTRL_INT,
    (* syn_peri_port = 0 *) input  ddr_inst_CTRL_MEM_RST_VALID,
    (* syn_peri_port = 0 *) input  [1:0]  ddr_inst_CTRL_PORT_BUSY,
    (* syn_peri_port = 0 *) input  ddr_inst_CTRL_REFRESH,
    (* syn_peri_port = 0 *) input  [511:0] ddr_inst_RDATA_0,
    (* syn_peri_port = 0 *) input  [5:0]  ddr_inst_RID_0,
    (* syn_peri_port = 0 *) input  ddr_inst_RLAST_0,
    (* syn_peri_port = 0 *) input  [1:0]  ddr_inst_RRESP_0,
    (* syn_peri_port = 0 *) input  ddr_inst_RVALID_0,
    (* syn_peri_port = 0 *) input  ddr_inst_WREADY_0,
    (* syn_peri_port = 0 *) output [32:0] ddr_inst_ARADDR_0,
    (* syn_peri_port = 0 *) output ddr_inst_ARAPCMD_0,
    (* syn_peri_port = 0 *) output [1:0]  ddr_inst_ARBURST_0,
    (* syn_peri_port = 0 *) output [5:0]  ddr_inst_ARID_0,
    (* syn_peri_port = 0 *) output [7:0]  ddr_inst_ARLEN_0,
    (* syn_peri_port = 0 *) output ddr_inst_ARLOCK_0,
    (* syn_peri_port = 0 *) output ddr_inst_ARQOS_0,
    (* syn_peri_port = 0 *) output [2:0]  ddr_inst_ARSIZE_0,
    (* syn_peri_port = 0 *) output ddr_inst_ARSTN_0,
    (* syn_peri_port = 0 *) output ddr_inst_ARVALID_0,
    (* syn_peri_port = 0 *) output [32:0] ddr_inst_AWADDR_0,
    (* syn_peri_port = 0 *) output ddr_inst_AWALLSTRB_0,
    (* syn_peri_port = 0 *) output ddr_inst_AWAPCMD_0,
    (* syn_peri_port = 0 *) output [1:0]  ddr_inst_AWBURST_0,
    (* syn_peri_port = 0 *) output [3:0]  ddr_inst_AWCACHE_0,
    (* syn_peri_port = 0 *) output ddr_inst_AWCOBUF_0,
    (* syn_peri_port = 0 *) output [5:0]  ddr_inst_AWID_0,
    (* syn_peri_port = 0 *) output [7:0]  ddr_inst_AWLEN_0,
    (* syn_peri_port = 0 *) output ddr_inst_AWLOCK_0,
    (* syn_peri_port = 0 *) output ddr_inst_AWQOS_0,
    (* syn_peri_port = 0 *) output [2:0]  ddr_inst_AWSIZE_0,
    (* syn_peri_port = 0 *) output ddr_inst_AWVALID_0,
    (* syn_peri_port = 0 *) output ddr_inst_BREADY_0,
    (* syn_peri_port = 0 *) output ddr_inst_CFG_RESET,
    (* syn_peri_port = 0 *) output ddr_inst_CFG_SEL,
    (* syn_peri_port = 0 *) output ddr_inst_CFG_START,
    (* syn_peri_port = 0 *) output ddr_inst_RREADY_0,
    (* syn_peri_port = 0 *) output [511:0] ddr_inst_WDATA_0,
    (* syn_peri_port = 0 *) output ddr_inst_WLAST_0,
    (* syn_peri_port = 0 *) output [63:0]  ddr_inst_WSTRB_0,
    (* syn_peri_port = 0 *) output ddr_inst_WVALID_0,

    // ---- DDR target1（peri DDR_0，ACLK_1 = sys_clk_200m，本工程 tie-off）----
    (* syn_peri_port = 0 *) input  ddr_inst_ARREADY_1,
    (* syn_peri_port = 0 *) input  ddr_inst_AWREADY_1,
    (* syn_peri_port = 0 *) input  [5:0]  ddr_inst_BID_1,
    (* syn_peri_port = 0 *) input  [1:0]  ddr_inst_BRESP_1,
    (* syn_peri_port = 0 *) input  ddr_inst_BVALID_1,
    (* syn_peri_port = 0 *) input  [511:0] ddr_inst_RDATA_1,
    (* syn_peri_port = 0 *) input  [5:0]  ddr_inst_RID_1,
    (* syn_peri_port = 0 *) input  ddr_inst_RLAST_1,
    (* syn_peri_port = 0 *) input  [1:0]  ddr_inst_RRESP_1,
    (* syn_peri_port = 0 *) input  ddr_inst_RVALID_1,
    (* syn_peri_port = 0 *) input  ddr_inst_WREADY_1,
    (* syn_peri_port = 0 *) output [32:0] ddr_inst_ARADDR_1,
    (* syn_peri_port = 0 *) output ddr_inst_ARAPCMD_1,
    (* syn_peri_port = 0 *) output [1:0]  ddr_inst_ARBURST_1,
    (* syn_peri_port = 0 *) output [5:0]  ddr_inst_ARID_1,
    (* syn_peri_port = 0 *) output [7:0]  ddr_inst_ARLEN_1,
    (* syn_peri_port = 0 *) output ddr_inst_ARLOCK_1,
    (* syn_peri_port = 0 *) output ddr_inst_ARQOS_1,
    (* syn_peri_port = 0 *) output [2:0]  ddr_inst_ARSIZE_1,
    (* syn_peri_port = 0 *) output ddr_inst_ARSTN_1,
    (* syn_peri_port = 0 *) output ddr_inst_ARVALID_1,
    (* syn_peri_port = 0 *) output [32:0] ddr_inst_AWADDR_1,
    (* syn_peri_port = 0 *) output ddr_inst_AWALLSTRB_1,
    (* syn_peri_port = 0 *) output ddr_inst_AWAPCMD_1,
    (* syn_peri_port = 0 *) output [1:0]  ddr_inst_AWBURST_1,
    (* syn_peri_port = 0 *) output [3:0]  ddr_inst_AWCACHE_1,
    (* syn_peri_port = 0 *) output ddr_inst_AWCOBUF_1,
    (* syn_peri_port = 0 *) output [5:0]  ddr_inst_AWID_1,
    (* syn_peri_port = 0 *) output [7:0]  ddr_inst_AWLEN_1,
    (* syn_peri_port = 0 *) output ddr_inst_AWLOCK_1,
    (* syn_peri_port = 0 *) output ddr_inst_AWQOS_1,
    (* syn_peri_port = 0 *) output [2:0]  ddr_inst_AWSIZE_1,
    (* syn_peri_port = 0 *) output ddr_inst_AWVALID_1,
    (* syn_peri_port = 0 *) output ddr_inst_BREADY_1,
    (* syn_peri_port = 0 *) output ddr_inst_RREADY_1,
    (* syn_peri_port = 0 *) output [511:0] ddr_inst_WDATA_1,
    (* syn_peri_port = 0 *) output ddr_inst_WLAST_1,
    (* syn_peri_port = 0 *) output [63:0]  ddr_inst_WSTRB_1,
    (* syn_peri_port = 0 *) output ddr_inst_WVALID_1
);

    //-------------------------------------------------------------------------
    // 全局异步复位（照抄 top_cam_demo L450-472：POR 256 拍 @27M）
    //-------------------------------------------------------------------------
    reg [7:0] cnt = 8'h0;
    reg i_arstn;
    always @(posedge i_clk_27m) begin
        if (cnt == 8'hff) begin
            cnt     <= 8'hff;
            i_arstn <= 1'b1;
        end else begin
            cnt     <= cnt + 1'b1;
            i_arstn <= 1'b0;
        end
    end

    // PLL 复位（active high release；pll_ddr_rstn 口对齐已验证 peri 配置）
    assign pll_ddr_rstn = i_arstn;
    assign pll_sys_rstn = i_arstn;

    wire sys_clk_200m_rstn;
    reset_ctrl #(.NUM_RST(1), .IN_RST_ACTIVE(1'b0), .OUT_RST_ACTIVE(1'b0)) u_rx_rst_200m (
        .i_arst (pll_sys_locked), .i_clk (sys_clk_200m), .o_srst (sys_clk_200m_rstn)
    );

    //-------------------------------------------------------------------------
    // LPDDR 配置 FSM v5（照抄 top_cam_demo L533-581，板测 6 轮迭代定稿：
    // 复位门控 = sys 复位释放 & pll_ddr_locked，lock 后才开跑 2^21 拍 ≈10.5ms
    // 覆盖 PLL/训练时序，然后发 CFG_START 直到 CFG_DONE）
    //-------------------------------------------------------------------------
    localparam [1:0] IDLE      = 2'b00,
                     CFG_START = 2'b01,
                     CFG_DONE  = 2'b11;

    reg  [1:0]  cfg_st, cfg_next;
    reg  [20:0] cfg_count;
    wire        ddr_cfg_ok;

    assign ddr_cfg_ok = (cfg_st == CFG_DONE);

    wire cfg_fsm_rstn = sys_clk_200m_rstn & pll_ddr_locked;

    always_ff @(posedge sys_clk_200m or negedge cfg_fsm_rstn) begin
        if (~cfg_fsm_rstn) begin
            cfg_st    <= IDLE;
            cfg_count <= 21'h0;
        end else begin
            cfg_st <= cfg_next;
            if (cfg_st == IDLE)
                cfg_count <= cfg_count + 1'b1;
            else
                cfg_count <= 21'h0;
        end
    end

    always_comb begin
        cfg_next = cfg_st;
        case (cfg_st)
            IDLE: begin
                if (&cfg_count)
                    cfg_next = CFG_START;
                else
                    cfg_next = IDLE;
            end
            CFG_START: begin
                if (ddr_inst_CFG_DONE)
                    cfg_next = CFG_DONE;
                else
                    cfg_next = CFG_START;
            end
            CFG_DONE: cfg_next = CFG_DONE;
            default:  cfg_next = IDLE;
        endcase
    end

    assign ddr_inst_CFG_START = (cfg_st != IDLE);
    assign ddr_inst_CFG_RESET = (cfg_st == IDLE);
    assign ddr_inst_CFG_SEL   = 1'b0;

    // DDR AXI 接口复位：CFG 完成后才释放（top_cam_demo L634-635）
    assign ddr_inst_ARSTN_0 = ddr_cfg_ok;
    assign ddr_inst_ARSTN_1 = ddr_cfg_ok;

    //-------------------------------------------------------------------------
    // DDR 自检（阶段 0 形态，照抄 top_cam_demo g_ddr_memtest 分支）：
    // ddr_memcheck 接管 target0，对 0x0~0x02000000（2Gb=256MB）做行突发
    // 写→读回比对。memcheck 复位随 CFG 完成同步释放（CYCLE=4）。
    //-------------------------------------------------------------------------
    wire        mc_done, mc_fail;
    wire [15:0] mc_err_cnt;
    wire [3:0]  mc_state;
    wire        mc_srstn;
    // TG 扫描输出（correlation Phase 1，TG_MODE=1 有效）
    wire [7:0]  tg_err_sat;
    wire [3:0]  tg_ostd;
    wire [15:0] tg_rd_cyc;
    // MODE2 延迟报告口（correlation Phase 2，TG_MODE=2 有效）
    wire [31:0] lat_word;
    wire        lat_next;

    reset_ctrl #(.NUM_RST(1), .IN_RST_ACTIVE(1'b1), .OUT_RST_ACTIVE(1'b0), .CYCLE(4))
    u_mc_rst (
        .i_arst (~ddr_cfg_ok), .i_clk (sys_clk_200m), .o_srst (mc_srstn)
    );

    ddr_memcheck #(
        .START_ADDR  (33'h0_0000_0000),
        .TOTAL_BURSTS(MC_TOTAL_BURSTS[15:0]),
        .ALEN        (MC_ALEN[7:0]),
        .ASIZE       (MC_ASIZE[2:0]),
        .TG_MODE     (TG_MODE[2:0]),    // Phase 6：MODE4 需 3 位（4=3'b100，[1:0] 截断会变自检）
        .TG_OSTD_MAX (TG_OSTD_MAX[4:0]),
        .TG_N_BURST  (TG_N_BURST[15:0]),
        .TG_ROUND_GAP_TICKS (TG_ROUND_GAP_TICKS[31:0]),
        .TG_LAT_WARMUP (TG_LAT_WARMUP),
        .TG_LAT_P5_N   (TG_LAT_P5_N)
    ) u_mc (
        .axi_clk   (sys_clk_200m),          // = ACLK_0（peri 绑定）
        .rstn      (mc_srstn),
        .start     (mc_srstn),              // 复位释放即启动

        .awid      (ddr_inst_AWID_0),
        .awaddr    (ddr_inst_AWADDR_0),
        .awlen     (ddr_inst_AWLEN_0),
        .awsize    (ddr_inst_AWSIZE_0),
        .awburst   (ddr_inst_AWBURST_0),
        .awcache   (ddr_inst_AWCACHE_0),
        .awlock    (ddr_inst_AWLOCK_0),
        .awvalid   (ddr_inst_AWVALID_0),
        .awcobuf   (ddr_inst_AWCOBUF_0),
        .awapcmd   (ddr_inst_AWAPCMD_0),
        .awallstrb (ddr_inst_AWALLSTRB_0),
        .awqos     (ddr_inst_AWQOS_0),
        .awready   (ddr_inst_AWREADY_0),
        .wdata     (ddr_inst_WDATA_0),
        .wstrb     (ddr_inst_WSTRB_0),
        .wlast     (ddr_inst_WLAST_0),
        .wvalid    (ddr_inst_WVALID_0),
        .wready    (ddr_inst_WREADY_0),
        .bid       (ddr_inst_BID_0),
        .bvalid    (ddr_inst_BVALID_0),
        .bready    (ddr_inst_BREADY_0),
        .arid      (ddr_inst_ARID_0),
        .araddr    (ddr_inst_ARADDR_0),
        .arlen     (ddr_inst_ARLEN_0),
        .arsize    (ddr_inst_ARSIZE_0),
        .arburst   (ddr_inst_ARBURST_0),
        .arlock    (ddr_inst_ARLOCK_0),
        .arvalid   (ddr_inst_ARVALID_0),
        .arapcmd   (ddr_inst_ARAPCMD_0),
        .arqos     (ddr_inst_ARQOS_0),
        .arready   (ddr_inst_ARREADY_0),
        .rid       (ddr_inst_RID_0),
        .rdata     (ddr_inst_RDATA_0),
        .rlast     (ddr_inst_RLAST_0),
        .rvalid    (ddr_inst_RVALID_0),
        .rready    (ddr_inst_RREADY_0),
        .rresp     (ddr_inst_RRESP_0),

        .done      (mc_done),
        .fail      (mc_fail),
        .err_cnt   (mc_err_cnt),
        .dbg_state (mc_state),
        .tg_ostd   (tg_ostd),
        .tg_rd_cyc (tg_rd_cyc),
        .tg_err_sat(tg_err_sat),
        .lat_word  (lat_word),
        .lat_next  (lat_next)
    );

    //-------------------------------------------------------------------------
    // 第二 memcheck（correlation Phase 4 双端口对称流量，§8.5）：
    // target1 同参 MODE1 OSTD 扫描作负载发生器；布置区错开 32MB 防互踩
    //（u_mc 布置 0x0~0x10000）。结果不进 UART（单报告口留 port0），
    // port0 竞争退化曲线 vs Phase 1 单口基线 → 仲裁标定判据（plan §9 Phase 4）
    //-------------------------------------------------------------------------
    wire        mc2_done, mc2_fail;
    wire [15:0] mc2_err_cnt;
    wire [3:0]  mc2_state;
    wire [7:0]  mc2_err_sat;
    wire [3:0]  mc2_ostd;
    wire [15:0] mc2_rd_cyc;
    wire [31:0] mc2_lat_word;
    wire        mc2_lat_next = 1'b0;    // 报告口不用，tie 防 X

    ddr_memcheck #(
        .START_ADDR  (33'h0_0200_0000),     // 32MB 错开（<256MB 合法区）
        .TOTAL_BURSTS(MC_TOTAL_BURSTS[15:0]),
        .ALEN        (MC_ALEN[7:0]),
        .ASIZE       (MC_ASIZE[2:0]),
        .TG_MODE     (TG_MODE[2:0]),
        .TG_OSTD_MAX (TG_OSTD_MAX[4:0]),
        .TG_N_BURST  (TG_N_BURST[15:0]),
        .TG_ROUND_GAP_TICKS (TG_ROUND_GAP_TICKS[31:0]),
        .TG_LAT_WARMUP (TG_LAT_WARMUP),
        .TG_LAT_P5_N   (TG_LAT_P5_N)
    ) u_mc2 (
        .axi_clk   (sys_clk_200m),          // = ACLK_1（peri 绑定同域）
        .rstn      (mc_srstn),
        .start     (mc_srstn),

        .awid      (ddr_inst_AWID_1),
        .awaddr    (ddr_inst_AWADDR_1),
        .awlen     (ddr_inst_AWLEN_1),
        .awsize    (ddr_inst_AWSIZE_1),
        .awburst   (ddr_inst_AWBURST_1),
        .awcache   (ddr_inst_AWCACHE_1),
        .awlock    (ddr_inst_AWLOCK_1),
        .awvalid   (ddr_inst_AWVALID_1),
        .awcobuf   (ddr_inst_AWCOBUF_1),
        .awapcmd   (ddr_inst_AWAPCMD_1),
        .awallstrb (ddr_inst_AWALLSTRB_1),
        .awqos     (ddr_inst_AWQOS_1),
        .awready   (ddr_inst_AWREADY_1),
        .wdata     (ddr_inst_WDATA_1),
        .wstrb     (ddr_inst_WSTRB_1),
        .wlast     (ddr_inst_WLAST_1),
        .wvalid    (ddr_inst_WVALID_1),
        .wready    (ddr_inst_WREADY_1),
        .bid       (ddr_inst_BID_1),
        .bvalid    (ddr_inst_BVALID_1),
        .bready    (ddr_inst_BREADY_1),
        .arid      (ddr_inst_ARID_1),
        .araddr    (ddr_inst_ARADDR_1),
        .arlen     (ddr_inst_ARLEN_1),
        .arsize    (ddr_inst_ARSIZE_1),
        .arburst   (ddr_inst_ARBURST_1),
        .arlock    (ddr_inst_ARLOCK_1),
        .arvalid   (ddr_inst_ARVALID_1),
        .arapcmd   (ddr_inst_ARAPCMD_1),
        .arqos     (ddr_inst_ARQOS_1),
        .arready   (ddr_inst_ARREADY_1),
        .rid       (ddr_inst_RID_1),
        .rdata     (ddr_inst_RDATA_1),
        .rlast     (ddr_inst_RLAST_1),
        .rvalid    (ddr_inst_RVALID_1),
        .rready    (ddr_inst_RREADY_1),
        .rresp     (ddr_inst_RRESP_1),

        .done      (mc2_done),
        .fail      (mc2_fail),
        .err_cnt   (mc2_err_cnt),
        .dbg_state (mc2_state),
        .tg_ostd   (mc2_ostd),
        .tg_rd_cyc (mc2_rd_cyc),
        .tg_err_sat(mc2_err_sat),
        .lat_word  (mc2_lat_word),
        .lat_next  (mc2_lat_next)
    );

    //-------------------------------------------------------------------------
    // DIAG11（top_cam_demo L1124-1130 同位图）+ UART 读出
    //   st: 0=IDLE 1=CFG_START(训练中) 3=CFG_DONE
    //   mcst: 0=IDLE 1=WADDR 2=PRE_W 3=WRITE 4=POST_W 5=RADDR 6=PRE_R
    //         7=COMPARE 8=POST_R 9=DONE
    //-------------------------------------------------------------------------
    wire [31:0] ddr_diag;
    // UART_SCAN_MODE=2：延迟轮发帧 lat_word（帧格式见 ddr_status_uart 头注）；
    // UART_SCAN_MODE=1：扫描帧 {err_sat[7:0], rd_cyc[15:0], ostd[3:0], mcst[3:0]}
    //  —— 每轮 OSTD 一帧，接收端按 ostd 字段归档；TG_DONE 时 mcst=9
    assign ddr_diag = (UART_SCAN_MODE == 2) ? lat_word :
                      UART_SCAN_MODE
        ? {tg_err_sat, tg_rd_cyc, tg_ostd, mc_state}
        : {mc_err_cnt, mc_state, 5'h0, ddr_inst_CFG_DONE, cfg_st,
           pll_ddr_locked, ddr_cfg_ok, mc_done, mc_fail};

    ddr_status_uart #(
        .CLK_HZ            (200_000_000),
        .BAUD              (115_200),
        .UART_REPORT_TICKS (UART_REPORT_TICKS),
        .SCAN_MODE         (UART_SCAN_MODE)
    ) u_dbg (
        .clk      (sys_clk_200m),
        .rstn     (sys_clk_200m_rstn),
        .diag     (ddr_diag),
        .txd      (uart_0_txd),
        .lat_next (lat_next)
    );

    // 未使用输入 tie（防 lint 未驱动告警）
    wire unused_ok = &{1'b0, uart_0_rxd, sys_clk_100m,
                       ddr_inst_CTRL_INT, ddr_inst_CTRL_MEM_RST_VALID,
                       ddr_inst_CTRL_REFRESH, ddr_inst_CTRL_BUSY,
                       ddr_inst_CTRL_CMD_Q_ALMOST_FULL, ddr_inst_CTRL_DP_IDLE,
                       ddr_inst_CTRL_CKE, ddr_inst_CTRL_PORT_BUSY,
                       ddr_inst_ARREADY_1, ddr_inst_AWREADY_1, ddr_inst_BID_1,
                       ddr_inst_BRESP_1, ddr_inst_BVALID_1, ddr_inst_RDATA_1,
                       ddr_inst_RID_1, ddr_inst_RLAST_1, ddr_inst_RRESP_1,
                       ddr_inst_RVALID_1, ddr_inst_WREADY_1, 1'b1};

endmodule
