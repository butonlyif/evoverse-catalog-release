////////////////////////////////////////////////////////////////////////////
//  tb_proj_addr.sv — correlation Phase 7：容量/别名探测（模型侧）
//
//  同一份 TG RTL（ddr_memcheck TG_MODE=5 Phase 7 版）跑 ddr_axi_model_top，
//  得到模型侧容量边界与越界回绕（别名）行为基线；板级跑同参对照
//  （correlation-plan §4 Phase 7，测试 spec §8.8）。
//
//  板级配置为单 rank LPDDR4x 2Gb（256MB，2 的幂）→ rank 边界/CS_BIT/非 2 幂
//  扫描不适用，缩范围为容量边界 + 越界别名行为。
//
//  流量口径（仿真/板级一致）：
//    - 9 探针 blk0-8：{0, 256M-4K, 256M, 256M+4K, 512M, 1G, 2G, 4G-4K, 4G}，
//      每轮 4 笔串行（ostd=1）：写 Yi(=Xi mod 256M) 参考 → 写 Xi 探针 →
//      读 Xi（比对 pattern(Xi)，hi_err>0=不可存储/SLVERR）→ 读 Yi
//      （比对基准仍 pattern(Xi)：读回 pattern(Xi)=Xi 回绕污染 Yi 实锤）
//
//  判据（模型侧，模型行为已知——越界=SLVERR 且写丢弃）：
//    P1 模型 CFG_DONE=1
//    P2 done=1 且 fail=0（MODE5 不置全局 fail，越界 err 是预期观测）
//    P3 合法探针 0/1：hi_err==0；越界探针 2-8：hi_err>0（模型 SLVERR）；
//      别名探针 2-7：alias_err>0（模型写丢弃，Yi 不被污染）；探针 8 别名
//      指纹退化（pat 只取地址低 32 位，pat(4G)==pat(0)）只记录不判
//    P4 CTRL_ERR=1 为预期签名（SLVERR 命令置 core_sticky），须与
//      berr/rresp 计数互证；CTRL_ERR=0 反而异常
//    P5 lat_word 轮发连续性（MODE5 指针：kind 0-3 回绕、set 恒 0、
//      blk 0-8 + 状态字 9 回绕）
//
//  编译（QuestaSim，cwd=proj/sim）：同 tb_proj_ooo 文件列表 + 本文件
//    vsim -c -voptargs="+acc" -do "run -all; quit -f" work.tb_proj_addr -l tb_proj_addr.log
////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module tb_proj_addr;

    localparam realtime TMO_CFG  = 20_000_000;   // 20ms（CFG 10.5ms + 裕量）
    localparam realtime TMO_MEAS = 100_000_000;  // 100ms（9 轮 × 4 笔 4KB，量小）

    reg clk200 = 0;
    reg clk_ctrl = 0;
    reg clk27 = 0;
    always #2.5   clk200   = ~clk200;   // 200MHz
    always #2.45  clk_ctrl = ~clk_ctrl; // 与 ACLK 异相（CDC 模型）
    always #5.0   clk27    = ~clk27;    // 100MHz 加速 POR（板级 27M）

    reg pll_sys_locked = 0;
    reg pll_ddr_locked = 0;
    reg uart_rxd = 1;
    wire uart_txd;

    //-------------------------------------------------------------------------
    // DUT（ddr_test_top，TG_MODE=5 容量/别名探测）
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
        .TG_MODE           (5),        // 容量/别名探测（Phase 7）
        .TG_OSTD_MAX       (16),
        .TG_N_BURST        (16),
        .TG_ROUND_GAP_TICKS(2000),     // 10us 轮间隔
        .UART_REPORT_TICKS (20_000),
        .UART_SCAN_MODE    (2)
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
    // 模型（QOS 零扩展；AWCACHE 直通——MODE5 写基线 0000，无歧义）
    //-------------------------------------------------------------------------
    wire [3:0] awqos0_m = {3'b000, awqos0[0]};
    wire [3:0] arqos0_m = {3'b000, arqos0[0]};
    wire [3:0] awqos1_m = {3'b000, awqos1[0]};
    wire [3:0] arqos1_m = {3'b000, arqos1[0]};

    wire ctrl_init_done, ctrl_ready, ctrl_err, ctrl_busy_m;

    ddr_axi_model_top #(
        .DATA_WIDTH         (16),
        .MEM_DENSITY_GBIT   (2),
        .CDC_ENABLE         (1),
        .ENABLE_CTRL_STATUS (1)
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
    // P5：lat_word 轮发连续性监视（MODE5 指针：kind 0-3 回绕、set 恒 0、
    // blk 0-8 + 状态字 9 回绕）
    //-------------------------------------------------------------------------
    integer p5_err = 0;
    integer p5_cnt = 0;
    reg [3:0] exp_blk;
    reg [2:0] exp_kind;
    reg       p5_anchored = 0;
    always @(posedge clk200) begin
        if (u_dut.mc_done === 1'b1 && u_dut.lat_next === 1'b1) begin
            if (p5_anchored) begin
                if ({u_dut.lat_word[31:28], u_dut.lat_word[25:23]} !==
                    {exp_blk, exp_kind} || u_dut.lat_word[27:26] !== 2'd0) begin
                    if (p5_err < 5)
                        $display("[TB][%0t] P5 FAIL: word #%0d got blk=%0d set=%0d kind=%0d, expect blk=%0d set=0 kind=%0d",
                                 $time, p5_cnt,
                                 u_dut.lat_word[31:28], u_dut.lat_word[27:26],
                                 u_dut.lat_word[25:23], exp_blk, exp_kind);
                    p5_err = p5_err + 1;
                end
            end else begin
                p5_anchored = 1;
            end
            exp_blk  = u_dut.lat_word[31:28];
            exp_kind = u_dut.lat_word[25:23];
            if (exp_kind == 3'd3) begin
                exp_kind = 3'd0;
                exp_blk  = (exp_blk == 4'd9) ? 4'd0 : exp_blk + 4'd1;  // MODE5：0-8+9 回绕
            end else
                exp_kind = exp_kind + 3'd1;
            p5_cnt = p5_cnt + 1;
        end
    end

    //-------------------------------------------------------------------------
    // 诊断：非_OK 响应计数（越界 SLVERR 的预期签名）
    //-------------------------------------------------------------------------
    integer berr_cnt = 0;
    integer rerr_cnt = 0;
    always @(posedge clk200) begin
        if (bvalid0 && bready0 && bresp0 !== 2'b00) berr_cnt = berr_cnt + 1;
        if (rvalid0 && rready0 && rresp0 !== 2'b00) rerr_cnt = rerr_cnt + 1;
    end

    //-------------------------------------------------------------------------
    // 主流程
    //-------------------------------------------------------------------------
    integer i, n_err;

    initial begin
        n_err = 0;
        $display("[TB] proj addr: Phase 7 capacity/alias probe (model side), 9 probes x (W Yi, W Xi, R Xi, R Yi)");
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

        // P2: 测量完成（MODE5 不置 fail——越界 err 是预期观测）
        fork : wait_ad
            begin
                wait (u_dut.mc_done === 1'b1);
                if (u_dut.mc_fail === 1'b0)
                    $display("[TB][%0t] P2 PASS: done=1 fail=0", $time);
                else begin
                    $display("[TB][%0t] P2 FAIL: fail=1 (MODE5 must not raise fail)",
                             $time);
                    n_err = n_err + 1;
                end
                disable wait_ad;
            end
            begin
                #TMO_MEAS;
                $display("[TB][%0t] P2 FAIL: done timeout (state=%0d issued=%0d completed=%0d blk=%0d)",
                         $time, u_dut.mc_state,
                         u_dut.u_mc.tg_issued, u_dut.u_mc.tg_completed,
                         u_dut.u_mc.blk_idx);
                n_err = n_err + 1;
                disable wait_ad;
            end
        join
        #2000;  // 末轮锁存余量

        // P3: 探针结果表（模型行为已知：越界=SLVERR+写丢弃）
        $display("[TB] ---- capacity/alias probe table (model side) ----");
        $display("[TB] blk | probe addr     | hi_err | alias_err | verdict");
        for (i = 0; i < 9; i = i + 1) begin
            $display("[TB]  %0d  | 0x%07h | %6d | %9d | %s",
                     i, u_dut.u_mc.ad_addr_f(i[3:0]),
                     u_dut.u_mc.ad_hi_r[i], u_dut.u_mc.ad_al_r[i],
                     (u_dut.u_mc.ad_hi_r[i] == 0) ? "accessible" :
                     "not-accessible(SLVERR)");
        end

        // 合法探针 0/1：hi_err 必须 0
        if (u_dut.u_mc.ad_hi_r[0] !== 16'd0 || u_dut.u_mc.ad_hi_r[1] !== 16'd0) begin
            $display("[TB] P3 FAIL: legal probes hi_err nonzero (blk0=%0d blk1=%0d)",
                     u_dut.u_mc.ad_hi_r[0], u_dut.u_mc.ad_hi_r[1]);
            n_err = n_err + 1;
        end else
            $display("[TB] P3 PASS: legal probes (0, 256M-4K) hi_err=0");

        // 越界探针 2-8：hi_err 必须 >0（模型 SLVERR，越界不可访问）
        begin : chk_hi
            integer hi_bad;
            hi_bad = 0;
            for (i = 2; i < 9; i = i + 1)
                if (u_dut.u_mc.ad_hi_r[i] == 16'd0) hi_bad = hi_bad + 1;
            if (hi_bad != 0) begin
                $display("[TB] P3 FAIL: %0d out-of-range probes unexpectedly accessible (hi_err=0)",
                         hi_bad);
                n_err = n_err + 1;
            end else
                $display("[TB] P3 PASS: all OOB probes (2-8) hi_err>0 (model SLVERR)");
        end

        // 别名探针 2-7：alias_err 必须 >0（模型写丢弃，Yi 不被污染）
        // 探针 8 指纹退化（pat 取地址低 32 位，pat(4G)==pat(0)）只记录
        begin : chk_al
            integer al_bad;
            al_bad = 0;
            for (i = 2; i < 8; i = i + 1)
                if (u_dut.u_mc.ad_al_r[i] == 16'd0) al_bad = al_bad + 1;
            if (al_bad != 0) begin
                $display("[TB] P3 FAIL: %0d probes alias_err=0 (unexpected wraparound aliasing!)",
                         al_bad);
                n_err = n_err + 1;
            end else
                $display("[TB] P3 PASS: probes 2-7 alias_err>0 (no wraparound, OOB write dropped)");
            $display("[TB] NOTE: probe 8 (4G) alias fingerprint degenerate (pat low-32) al=%0d, report-only",
                     u_dut.u_mc.ad_al_r[8]);
        end

        // P4: CTRL_ERR=1 为预期签名（SLVERR 命令置 core_sticky），与计数互证
        if (ctrl_err === 1'b1 && rerr_cnt > 0 && berr_cnt > 0)
            $display("[TB][%0t] P4 PASS: CTRL_ERR=1 with SLVERR corroboration (bresp!=OK=%0d rresp!=OK=%0d)",
                     $time, berr_cnt, rerr_cnt);
        else if (ctrl_err === 1'b0) begin
            $display("[TB][%0t] P4 FAIL: CTRL_ERR=0 but OOB probes expected SLVERR sticky (berr=%0d rerr=%0d)",
                     $time, berr_cnt, rerr_cnt);
            n_err = n_err + 1;
        end else begin
            $display("[TB][%0t] P4 FAIL: CTRL_ERR=1 but no non-OK responses seen (berr=%0d rerr=%0d)",
                     $time, berr_cnt, rerr_cnt);
            n_err = n_err + 1;
        end

        // P5: lat_word 轮发连续性（等 >=3 帧脉冲再评估，同 tb_proj_ooo 口径）
        begin : wait_p5_win
            realtime t_p50;
            t_p50 = $realtime;
            while ((p5_cnt < 3) && (($realtime - t_p50) < 6_000_000))
                @(posedge clk200);
        end
        if (p5_anchored && p5_cnt > 1 && p5_err == 0)
            $display("[TB] P5 PASS: lat_word %0d words in sequence", p5_cnt);
        else if (p5_err != 0) begin
            $display("[TB] P5 FAIL: %0d/%0d words out of sequence",
                     p5_err, p5_cnt);
            n_err = n_err + 1;
        end else begin
            $display("[TB] P5 FAIL: no/insufficient lat_next pulses (%0d)", p5_cnt);
            n_err = n_err + 1;
        end

        if (n_err == 0)
            $display("[TB] ================= PROJ ADDR ALL PASS =================");
        else
            $display("[TB] ================= PROJ ADDR FAIL (n_err=%0d) =================",
                     n_err);
        $finish;
    end

    // 全局超时兜底
    initial begin
        #150_000_000;
        $display("[TB] GLOBAL TIMEOUT");
        $display("[TB] PROJ ADDR FAIL (timeout)");
        $finish;
    end

endmodule
