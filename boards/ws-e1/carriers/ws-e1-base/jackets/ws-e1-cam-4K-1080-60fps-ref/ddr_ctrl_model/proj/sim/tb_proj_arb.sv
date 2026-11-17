////////////////////////////////////////////////////////////////////////////
//  tb_proj_arb.sv — correlation Phase 4：双端口仲裁标定（模型侧）
//
//  双 memcheck（ddr_test_top 内置 u_mc@target0 + u_mc2@target1，Phase 4 版）
//  同参 TG_MODE=1 OSTD 扫描（16 笔×4KB/轮，地址布置错开 32MB），跑
//  ddr_axi_model_top 双端口，得到模型侧端口竞争退化与公平性基线；板级跑
//  同参对照（correlation-plan §4 Phase 4，测试 spec §8.5）。
//
//  §8.5 板级无 ILA（无法抓 grant 序列），缩范围为对称流量完成速率对比：
//    - 每档 ostd 记录 port0/port1 各自 rd_cyc → 公平比（饱和档）；
//    - 饱和档（ostd=16）rd_cyc vs 单口基线（tb_proj_tg 平台 1293-1483）
//      → 双口退化倍数；板级同口径 vs 板级单口基线（Phase 1 平台 2284-2317）
//      → 板/仿退化倍数对照 → 真核仲裁行为与模型 ARB_GRANT_INTERVAL=2 同形性。
//  fast path（单口零冷却）由 Phase 1/3 单口零反压全吞吐佐证（§9 Phase 4）。
//
//  判据（主档 ARB_G=2，模型默认）：
//    P1 模型 CFG_DONE=1
//    P2 双实例 done=1 fail=0（数据比对全对——读回各自布置数据）
//    P3 模型 CTRL_ERR=0
//    P4 公平性：饱和档（ostd>=8）|rd_cyc0/rd_cyc1 - 1| <= 0.15
//  表征档（vsim -gARB_G=8）：参数路径活跃自证——饱和档退化应明显大于主档；
//    只打印不判 P4。
//
//  编译（QuestaSim，cwd=proj/sim）：同 tb_proj_addr 文件列表 + 本文件
//    vsim -c -voptargs="+acc" -do "run -all; quit -f" work.tb_proj_arb -l tb_proj_arb.log
//    表征档：vsim -c -voptargs="+acc" -gARB_G=8 -do "run -all; quit -f" work.tb_proj_arb -l tb_proj_arb_g8.log
////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module tb_proj_arb;

    parameter int ARB_G = 2;                 // 模型 ARB_GRANT_INTERVAL（-g 覆盖）
    parameter int CDC_G = 1;                 // 模型 CDC_ENABLE（-gCDC_G=0 表征
                                             // g_sync 形态：ARB_GRANT_INTERVAL
                                             // 仅在该路径生效，板级 CDC 形态无此参数）

    localparam realtime TMO_CFG  = 20_000_000;   // 20ms（CFG 10.5ms + 裕量）
    localparam realtime TMO_MEAS = 100_000_000;  // 100ms（双口 16 轮，量小）
    // 单口饱和平台（tb_proj_tg 模型侧：ostd=16 → 1293-1483 拍，2026-10-22）
    localparam int SGL_BEST  = 1293;
    localparam int SGL_WORST = 1483;

    reg clk200 = 0;
    reg clk_ctrl = 0;
    reg clk27 = 0;
    always #2.5   clk200   = ~clk200;   // 200MHz
    // CDC_G=1（板级形态）：ctrl_clk 与 ACLK 异频模拟跨域；CDC_G=0（g_sync
    // 表征）：同源同频——axi_port_shell 无 CDC，跨域激励会破裂协议
    generate
        if (CDC_G == 0) always #2.5  clk_ctrl = ~clk_ctrl;
        else            always #2.45 clk_ctrl = ~clk_ctrl;
    endgenerate
    always #5.0   clk27    = ~clk27;    // 100MHz 加速 POR（板级 27M）

    reg pll_sys_locked = 0;
    reg pll_ddr_locked = 0;
    reg uart_rxd = 1;
    wire uart_txd;

    //-------------------------------------------------------------------------
    // DUT（ddr_test_top，Phase 4 版：u_mc@target0 + u_mc2@target1 对称流量）
    //-------------------------------------------------------------------------
    wire [32:0] awaddr0, araddr0, awaddr1, araddr1;
    wire [511:0] wdata0, rdata0, wdata1, rdata1;
    wire [63:0]  wstrb0, wstrb1;
    wire [7:0]   awlen0, arlen0, awlen1, arlen1;
    wire [5:0]   awid0, arid0, bid0, rid0, awid1, arid1, bid1, rid1;
    wire [3:0]   awcache0, awcache1, awqos0, arqos0, awqos1, arqos1;
    wire [2:0]   awsize0, arsize0, awsize1, arsize1;
    wire [1:0]   awburst0, arburst0, awburst1, arburst1, bresp0, rresp0, bresp1, rresp1;
    wire [1:0]   ctrl_cke, ctrl_port_busy;
    wire awvalid0, awready0, wvalid0, wready0, wlast0, bvalid0, bready0;
    wire arvalid0, arready0, rvalid0, rready0, rlast0;
    wire awvalid1, awready1, wvalid1, wready1, wlast1, bvalid1, bready1;
    wire arvalid1, arready1, rvalid1, rready1, rlast1;
    wire awlock0, arlock0, awapcmd0, arapcmd0, awallstrb0, awcobuf0;
    wire awlock1, arlock1, awapcmd1, arapcmd1, awallstrb1, awcobuf1;
    wire cfg_start, cfg_reset, cfg_sel, cfg_done;
    wire ctrl_busy, ctrl_cmd_q_af, ctrl_dp_idle, ctrl_int, ctrl_mrv, ctrl_refresh;
    wire arstn0, arstn1;

    ddr_test_top #(
        .MC_TOTAL_BURSTS   (16),
        .MC_ALEN           (63),
        .TG_MODE           (1),        // OSTD 扫描（Phase 4 双口对称流量）
        .TG_OSTD_MAX       (16),
        .TG_N_BURST        (16),
        .TG_ROUND_GAP_TICKS(2000),     // 10us 轮间隔
        .UART_REPORT_TICKS (20_000),
        .UART_SCAN_MODE    (1)
    ) u_dut (
        .i_clk_27m    (clk27),
        .sys_clk_100m (1'b0),
        .sys_clk_200m (clk200),
        .pll_sys_locked (pll_sys_locked),
        .pll_sys_rstn (),
        .pll_ddr_locked (pll_ddr_locked),
        .pll_ddr_rstn (),
        .uart_0_rxd   (uart_rxd),
        .uart_0_txd   (uart_txd),

        .ddr_inst_ARREADY_0 (arready0),
        .ddr_inst_AWREADY_0 (awready0),
        .ddr_inst_BID_0     (bid0),
        .ddr_inst_BRESP_0   (bresp0),
        .ddr_inst_BVALID_0  (bvalid0),
        .ddr_inst_CFG_DONE  (cfg_done),
        .ddr_inst_CTRL_BUSY (ctrl_busy),
        .ddr_inst_CTRL_CKE  (ctrl_cke),
        .ddr_inst_CTRL_CMD_Q_ALMOST_FULL (ctrl_cmd_q_af),
        .ddr_inst_CTRL_DP_IDLE (ctrl_dp_idle),
        .ddr_inst_CTRL_INT  (ctrl_int),
        .ddr_inst_CTRL_MEM_RST_VALID (ctrl_mrv),
        .ddr_inst_CTRL_PORT_BUSY (ctrl_port_busy),
        .ddr_inst_CTRL_REFRESH (ctrl_refresh),
        .ddr_inst_RDATA_0   (rdata0),
        .ddr_inst_RID_0     (rid0),
        .ddr_inst_RLAST_0   (rlast0),
        .ddr_inst_RRESP_0   (rresp0),
        .ddr_inst_RVALID_0  (rvalid0),
        .ddr_inst_WREADY_0  (wready0),
        .ddr_inst_ARADDR_0  (araddr0),
        .ddr_inst_ARAPCMD_0 (arapcmd0),
        .ddr_inst_ARBURST_0 (arburst0),
        .ddr_inst_ARID_0    (arid0),
        .ddr_inst_ARLEN_0   (arlen0),
        .ddr_inst_ARLOCK_0  (arlock0),
        .ddr_inst_ARQOS_0   (arqos0),
        .ddr_inst_ARSIZE_0  (arsize0),
        .ddr_inst_ARSTN_0   (arstn0),
        .ddr_inst_ARVALID_0 (arvalid0),
        .ddr_inst_AWADDR_0  (awaddr0),
        .ddr_inst_AWALLSTRB_0 (awallstrb0),
        .ddr_inst_AWAPCMD_0 (arapcmd0),
        .ddr_inst_AWBURST_0 (awburst0),
        .ddr_inst_AWCACHE_0 (awcache0),
        .ddr_inst_AWCOBUF_0 (awcobuf0),
        .ddr_inst_AWID_0    (awid0),
        .ddr_inst_AWLEN_0   (awlen0),
        .ddr_inst_AWLOCK_0  (awlock0),
        .ddr_inst_AWQOS_0   (awqos0),
        .ddr_inst_AWSIZE_0  (awsize0),
        .ddr_inst_AWVALID_0 (awvalid0),
        .ddr_inst_BREADY_0  (bready0),
        .ddr_inst_CFG_RESET (cfg_reset),
        .ddr_inst_CFG_SEL   (cfg_sel),
        .ddr_inst_CFG_START (cfg_start),
        .ddr_inst_RREADY_0  (rready0),
        .ddr_inst_WDATA_0   (wdata0),
        .ddr_inst_WLAST_0   (wlast0),
        .ddr_inst_WSTRB_0   (wstrb0),
        .ddr_inst_WVALID_0  (wvalid0),

        .ddr_inst_ARREADY_1 (arready1),
        .ddr_inst_AWREADY_1 (awready1),
        .ddr_inst_BID_1     (bid1),
        .ddr_inst_BRESP_1   (bresp1),
        .ddr_inst_BVALID_1  (bvalid1),
        .ddr_inst_RDATA_1   (rdata1),
        .ddr_inst_RID_1     (rid1),
        .ddr_inst_RLAST_1   (rlast1),
        .ddr_inst_RRESP_1   (rresp1),
        .ddr_inst_RVALID_1  (rvalid1),
        .ddr_inst_WREADY_1  (wready1),
        .ddr_inst_ARADDR_1  (araddr1),
        .ddr_inst_ARAPCMD_1 (arapcmd1),
        .ddr_inst_ARBURST_1 (arburst1),
        .ddr_inst_ARID_1    (arid1),
        .ddr_inst_ARLEN_1   (arlen1),
        .ddr_inst_ARLOCK_1  (arlock1),
        .ddr_inst_ARQOS_1   (arqos1),
        .ddr_inst_ARSIZE_1  (arsize1),
        .ddr_inst_ARSTN_1   (arstn1),
        .ddr_inst_ARVALID_1 (arvalid1),
        .ddr_inst_AWADDR_1  (awaddr1),
        .ddr_inst_AWALLSTRB_1 (awallstrb1),
        .ddr_inst_AWAPCMD_1 (arapcmd1),
        .ddr_inst_AWBURST_1 (awburst1),
        .ddr_inst_AWCACHE_1 (awcache1),
        .ddr_inst_AWCOBUF_1 (awcobuf1),
        .ddr_inst_AWID_1    (awid1),
        .ddr_inst_AWLEN_1   (awlen1),
        .ddr_inst_AWLOCK_1  (awlock1),
        .ddr_inst_AWQOS_1   (awqos1),
        .ddr_inst_AWSIZE_1  (awsize1),
        .ddr_inst_AWVALID_1 (awvalid1),
        .ddr_inst_BREADY_1  (bready1),
        .ddr_inst_RREADY_1  (rready1),
        .ddr_inst_WDATA_1   (wdata1),
        .ddr_inst_WLAST_1   (wlast1),
        .ddr_inst_WSTRB_1   (wstrb1),
        .ddr_inst_WVALID_1  (wvalid1)
    );

    //-------------------------------------------------------------------------
    // 模型（双端口；QOS 零扩展；AWCACHE 直通——MODE1 写布置全程 0000）
    //-------------------------------------------------------------------------
    wire [3:0] awqos0_m = {3'b000, awqos0[0]};
    wire [3:0] arqos0_m = {3'b000, arqos0[0]};
    wire [3:0] awqos1_m = {3'b000, awqos1[0]};
    wire [3:0] arqos1_m = {3'b000, arqos1[0]};

    wire ctrl_init_done, ctrl_ready, ctrl_err, ctrl_busy_m;

    ddr_axi_model_top #(
        .DATA_WIDTH         (16),
        .MEM_DENSITY_GBIT   (2),
        .CDC_ENABLE         (CDC_G),
        .ENABLE_CTRL_STATUS (1),
        .ARB_GRANT_INTERVAL (ARB_G)    // 主档 2（默认）；表征档 -gARB_G=8
    ) u_model (
        .ctrl_clk   (clk_ctrl),
        .ACLK_0     (clk200),
        .ARSTN_0    (arstn0),
        .AWADDR_0   (awaddr0),
        .AWBURST_0  (awburst0),
        .AWID_0     (awid0),
        .AWLEN_0    (awlen0),
        .AWREADY_0  (awready0),
        .AWSIZE_0   (awsize0),
        .AWVALID_0  (awvalid0),
        .AWLOCK_0   (awlock0),
        .AWAPCMD_0  (arapcmd0),
        .AWQOS_0    (awqos0_m),
        .AWCACHE_0  (awcache0),
        .AWALLSTRB_0(awallstrb0),
        .AWCOBUF_0  (awcobuf0),
        .WDATA_0    (wdata0),
        .WLAST_0    (wlast0),
        .WREADY_0   (wready0),
        .WSTRB_0    (wstrb0),
        .WVALID_0   (wvalid0),
        .BID_0      (bid0),
        .BREADY_0   (bready0),
        .BRESP_0    (bresp0),
        .BVALID_0   (bvalid0),
        .ARADDR_0   (araddr0),
        .ARBURST_0  (arburst0),
        .ARID_0     (arid0),
        .ARLEN_0    (arlen0),
        .ARREADY_0  (arready0),
        .ARSIZE_0   (arsize0),
        .ARVALID_0  (arvalid0),
        .ARLOCK_0   (arlock0),
        .ARAPCMD_0  (arapcmd0),
        .ARQOS_0    (arqos0_m),
        .RDATA_0    (rdata0),
        .RID_0      (rid0),
        .RLAST_0    (rlast0),
        .RREADY_0   (rready0),
        .RRESP_0    (rresp0),
        .RVALID_0   (rvalid0),

        .ACLK_1     (clk200),
        .ARSTN_1    (arstn1),
        .AWADDR_1   (awaddr1),
        .AWBURST_1  (awburst1),
        .AWID_1     (awid1),
        .AWLEN_1    (awlen1),
        .AWREADY_1  (awready1),
        .AWSIZE_1   (awsize1),
        .AWVALID_1  (awvalid1),
        .AWLOCK_1   (awlock1),
        .AWAPCMD_1  (arapcmd1),
        .AWQOS_1    (awqos1_m),
        .AWCACHE_1  (awcache1),
        .AWALLSTRB_1(awallstrb1),
        .AWCOBUF_1  (awcobuf1),
        .WDATA_1    (wdata1),
        .WLAST_1    (wlast1),
        .WREADY_1   (wready1),
        .WSTRB_1    (wstrb1),
        .WVALID_1   (wvalid1),
        .BID_1      (bid1),
        .BREADY_1   (bready1),
        .BRESP_1    (bresp1),
        .BVALID_1   (bvalid1),
        .ARADDR_1   (araddr1),
        .ARBURST_1  (arburst1),
        .ARID_1     (arid1),
        .ARLEN_1    (arlen1),
        .ARREADY_1  (arready1),
        .ARSIZE_1   (arsize1),
        .ARVALID_1  (arvalid1),
        .ARLOCK_1   (arlock1),
        .ARAPCMD_1  (arapcmd1),
        .ARQOS_1    (arqos1_m),
        .RDATA_1    (rdata1),
        .RID_1      (rid1),
        .RLAST_1    (rlast1),
        .RREADY_1   (rready1),
        .RRESP_1    (rresp1),
        .RVALID_1   (rvalid1),

        .CFG_RESET  (cfg_reset),
        .CFG_START  (cfg_start),
        .CFG_SEL    (cfg_sel),
        .CFG_DONE   (cfg_done),
        .CTRL_INIT_DONE (ctrl_init_done),
        .CTRL_READY (ctrl_ready),
        .CTRL_ERR   (ctrl_err),
        .CTRL_BUSY  (ctrl_busy_m),
        .DBG_FIELDS (),
        .DBG_FIELDS_ADDR ()
    );

    //-------------------------------------------------------------------------
    // 每档 rd_cyc 采样：tg_ostd 是轮尾递增的输出（4 位，16 显示 4'h0），
    // 变化拍时 tg_rd_cyc 已锁存上一轮值（GAP 首拍锁存先于 ostd 递增）
    //-------------------------------------------------------------------------
    integer tab0 [0:15];    // port0：按 (ostd mod 16) 存
    integer tab1 [0:15];    // port1
    reg [3:0] last0 = 4'h1;
    reg [3:0] last1 = 4'h1;
    reg       tab_vld [0:1] = '{1'b1, 1'b1};  // last 初值=ostd 复位值 1，首个边沿
                                    // 即第 1 轮完成（1→2），直接可存（无 X 边沿风险）
    reg       done0_d = 1'b0, done1_d = 1'b0;  // done 上升沿检测（补存末轮）

    always @(posedge clk200) begin
        // port0（u_mc 报告口）
        if (u_dut.mc_srstn === 1'b1 && u_dut.tg_ostd !== last0) begin
            if (tab_vld[0])
                tab0[last0] = u_dut.tg_rd_cyc;
            tab_vld[0] = 1'b1;
            last0 = u_dut.tg_ostd;
        end
        // port1（u_mc2，无报告口，直接采内部 wire）
        if (u_dut.mc_srstn === 1'b1 && u_dut.mc2_ostd !== last1) begin
            if (tab_vld[1])
                tab1[last1] = u_dut.mc2_rd_cyc;
            tab_vld[1] = 1'b1;
            last1 = u_dut.mc2_ostd;
        end
        // 末轮（ostd=16 存于索引 0）无 ostd 递增边沿（memcheck 到 MAX 不再递增
        // 直接 DONE），done 上升沿补存；此时 tg_rd_cyc 已在末轮 GAP 首拍锁存
        done0_d <= u_dut.mc_done;
        done1_d <= u_dut.mc2_done;
        if (u_dut.mc_done === 1'b1 && done0_d === 1'b0 && tab_vld[0])
            tab0[last0] = u_dut.tg_rd_cyc;
        if (u_dut.mc2_done === 1'b1 && done1_d === 1'b0 && tab_vld[1])
            tab1[last1] = u_dut.mc2_rd_cyc;
    end

    //-------------------------------------------------------------------------
    // 诊断：比对错即时打印
    //-------------------------------------------------------------------------
    reg        fail0_d = 1'b0, fail1_d = 1'b0;
    always @(posedge clk200) begin
        fail0_d <= u_dut.mc_fail;
        fail1_d <= u_dut.mc2_fail;
        if (u_dut.mc_fail === 1'b1 && fail0_d === 1'b0)
            $display("[TB][DIAG][%0t] port0 first miss: state=%0d err=%0d",
                     $time, u_dut.mc_state, u_dut.mc_err_cnt);
        if (u_dut.mc2_fail === 1'b1 && fail1_d === 1'b0)
            $display("[TB][DIAG][%0t] port1 first miss: state=%0d err=%0d",
                     $time, u_dut.mc2_state, u_dut.mc2_err_cnt);
    end

    //-------------------------------------------------------------------------
    // 主流程
    //-------------------------------------------------------------------------
    integer i, n_err;
    real    ratio;

    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            tab0[i] = 0;  tab1[i] = 0;
        end
        tab_vld[0] = 1'b1;  tab_vld[1] = 1'b1;
        n_err = 0;
        $display("[TB] proj arb: Phase 4 dual-port arbitration (model side), TG_MODE=1 both ports, ARB_GRANT_INTERVAL=%0d",
                 ARB_G);
        #100ns  pll_sys_locked = 1;
        #100ns  pll_ddr_locked = 1;

        // P1: CFG_DONE
        fork : wait_cfg
            begin
                wait (cfg_done === 1'b1);
                $display("[TB][%0t] P1 PASS: model CFG_DONE=1", $time);
                disable wait_cfg;
            end
            begin
                #TMO_CFG;
                $display("[TB][%0t] P1 FAIL: CFG_DONE timeout", $time);
                n_err = n_err + 1;
                disable wait_cfg;
            end
        join

        // P2: 双实例完成
        fork : wait_done
            begin
                wait (u_dut.mc_done === 1'b1 && u_dut.mc2_done === 1'b1);
                if (u_dut.mc_fail === 1'b0 && u_dut.mc2_fail === 1'b0)
                    $display("[TB][%0t] P2 PASS: both ports done=1 fail=0 (err0=%0d err1=%0d)",
                             $time, u_dut.mc_err_cnt, u_dut.mc2_err_cnt);
                else begin
                    $display("[TB][%0t] P2 FAIL: fail0=%0d fail1=%0d (err0=%0d err1=%0d)",
                             $time, u_dut.mc_fail, u_dut.mc2_fail,
                             u_dut.mc_err_cnt, u_dut.mc2_err_cnt);
                    n_err = n_err + 1;
                end
                disable wait_done;
            end
            begin
                #TMO_MEAS;
                $display("[TB][%0t] P2 FAIL: done timeout (done0=%0d done1=%0d st0=%0d st1=%0d)",
                         $time, u_dut.mc_done, u_dut.mc2_done,
                         u_dut.mc_state, u_dut.mc2_state);
                n_err = n_err + 1;
                disable wait_done;
            end
        join
        #2000;  // 末轮锁存余量（末轮 ostd 递增触发表存）

        // 双口扫描曲线 + 公平/退化
        $display("[TB] ---- dual-port OSTD sweep (model side, G=%0d) ----", ARB_G);
        $display("[TB] ostd | rd_cyc0 | rd_cyc1 | ratio  | vs-single-x0 (single %0d-%0d)",
                 SGL_BEST, SGL_WORST);
        $display("[TB] -----+---------+---------+--------+---------------");
        for (i = 0; i < 16; i = i + 1) begin
            if (tab0[i] > 0 && tab1[i] > 0)
                ratio = 1.0 * tab0[i] / tab1[i];
            else
                ratio = 0.0;
            $display("[TB] %4d | %7d | %7d | %6.3f | %s",
                     (i == 0) ? 16 : i, tab0[i], tab1[i], ratio,
                     (tab0[i] > 0) ? $sformatf("%.2f", 1.0 * tab0[i] / SGL_BEST) : "-");
        end

        // P4: 公平性（饱和档 ostd 8-15 + 16(存于 0)）
        if (ARB_G == 2) begin
            begin : chk_fair
                integer fair_bad;
                fair_bad = 0;
                for (i = 8; i < 16; i = i + 1)
                    if (tab0[i] > 0 && tab1[i] > 0 &&
                        ((1.0 * tab0[i] / tab1[i] > 1.15) ||
                         (1.0 * tab1[i] / tab0[i] > 1.15)))
                        fair_bad = fair_bad + 1;
                if (fair_bad == 0)
                    $display("[TB] P4 PASS: saturated rounds (ostd 8-15) fair ratio within 0.15 of 1.0");
                else begin
                    $display("[TB] P4 FAIL: %0d saturated rounds unfair (>1.15x)", fair_bad);
                    n_err = n_err + 1;
                end
            end
            // 退化倍数摘要（饱和档，ostd=16 存于索引 0）
            if (tab0[0] > 0)
                $display("[TB] SUMMARY: sat rd_cyc0=%0d rd_cyc1=%0d, dual/single degradation = %.2f-%.2f (port0), G=%0d",
                         tab0[0], tab1[0],
                         1.0 * tab0[0] / SGL_WORST, 1.0 * tab0[0] / SGL_BEST, ARB_G);
        end else begin
            $display("[TB] NOTE: ARB_G=%0d characterization run - record degradation, P4 fairness skipped", ARB_G);
        end

        // P3: 模型无协议错误
        if (ctrl_err === 1'b0)
            $display("[TB][%0t] P3 PASS: model CTRL_ERR=0", $time);
        else begin
            $display("[TB][%0t] P3 FAIL: model CTRL_ERR=1", $time);
            n_err = n_err + 1;
        end

        if (n_err == 0)
            $display("[TB] ================= PROJ ARB ALL PASS =================");
        else
            $display("[TB] ================= PROJ ARB FAIL (n_err=%0d) =================",
                     n_err);
        $finish;
    end

    // 全局超时兜底
    initial begin
        #150_000_000;
        $display("[TB] GLOBAL TIMEOUT");
        $display("[TB] PROJ ARB FAIL (timeout)");
        $finish;
    end

endmodule
