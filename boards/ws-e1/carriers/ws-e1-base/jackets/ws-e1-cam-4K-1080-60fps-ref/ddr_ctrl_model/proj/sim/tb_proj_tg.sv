////////////////////////////////////////////////////////////////////////////
//  tb_proj_tg.sv — correlation Phase 1：TG OSTD 扫描（模型侧）
//
//  同一份 TG RTL（ddr_memcheck TG_MODE=1）跑 ddr_axi_model_top，得到模型
//  侧 OSTD-耗时曲线；板级跑同参数得到对照曲线（correlation-plan §4 Phase 1）。
//
//  流量口径（仿真/板级一致）：
//    - ALEN=63（64 beat×64B = 4096B，4KB 压线安全）
//    - 每轮 16 burst × 4KB = 64KB，地址 0x0 起步进 4KB（不重叠）
//    - OSTD 1→16 递增，每轮 err 独立清零；轮间隔 10us（TG_ROUND_GAP=2000）
//
//  判据：
//    P1 模型 CFG_DONE=1
//    P2 TG done=1 且 fail=0（16 轮全对）
//    P3 每轮 err_cnt=0（per-RID 乱序比对零错）
//    P4 模型 CTRL_ERR=0
//    输出：OSTD→rd_cyc 曲线表 + 等效读带宽（GB/s），饱和点 = 曲线折平处
//
//  编译（QuestaSim，cwd=proj/sim）：
//    vlog -sv -work work ../../rtl/ddr_model_pkg.sv ../../rtl/ddr_fifo.sv \
//         ../../rtl/ddr_async_fifo.sv ../../rtl/mem_model.sv \
//         ../../rtl/core_scheduler.sv ../../rtl/cfg_ctrl_fsm.sv \
//         ../../rtl/axi_port_shell.sv ../../rtl/axi_port_shell_cdc.sv \
//         ../../rtl/ddr_model_assertions.sv ../../rtl/ddr_axi_model_top.sv \
//         ../rtl/reset_ctrl.sv ../rtl/ddr_memcheck.v ../rtl/ddr_status_uart.sv \
//         ../rtl/ddr_test_top.sv tb_proj_tg.sv
//    vsim -c -voptargs="+acc" -do "run -all; quit -f" work.tb_proj_tg -l tb_proj_tg.log
//
//  模型口径差异处理（同 tb_proj_smoke，详见 ../../docs/correlation-plan.md）：
//    AWCACHE=0000→1111 翻译、QOS 零扩展、ARVALID 握手纪律（TG 发侧
//    !arvalid 门控天然满足）。
////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module tb_proj_tg;

    localparam realtime TMO_NS   = 30_000_000;  // 30ms（CFG 10.5ms + 扫描 + 裕量）
    localparam int      ROUNDS    = 16;

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
    // DUT（ddr_test_top，TG_MODE=1 扫描）
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
        .MC_ALEN           (63),       // 64 beat×64B=4096B（4KB 压线，模型强制）
        .TG_MODE           (1),
        .TG_OSTD_MAX       (ROUNDS),
        .TG_N_BURST        (16),
        .TG_ROUND_GAP_TICKS(2000),     // 10us 仿真轮间隔
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
        .ddr_inst_AWAPCMD_0 (awapcmd0),
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
        .ddr_inst_AWAPCMD_1 (awapcmd1),
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
    // 模型（口径翻译同 tb_proj_smoke：AWCACHE 0000→1111、QOS 零扩展）
    //-------------------------------------------------------------------------
    wire [3:0] awcache0_m = (awcache0 == 4'b0000) ? 4'b1111 : awcache0;
    wire [3:0] awcache1_m = (awcache1 == 4'b0000) ? 4'b1111 : awcache1;
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
        .AWAPCMD_0  (awapcmd0),
        .AWQOS_0    (awqos0_m),
        .AWCACHE_0  (awcache0_m),
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
        .AWAPCMD_1  (awapcmd1),
        .AWQOS_1    (awqos1_m),
        .AWCACHE_1  (awcache1_m),
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
    // 轮采样：TG_RD_REQ(10) → TG_ROUND_GAP(11) 转换沿采本轮结果
    //-------------------------------------------------------------------------
    integer    n_err = 0;
    reg [3:0]  tg_prev = 4'h0;
    reg [15:0] rd_tab  [0:ROUNDS-1];
    reg [15:0] err_tab [0:ROUNDS-1];
    integer    rounds_seen = 0;

    always @(posedge clk200) begin
        tg_prev <= u_dut.u_mc.state;
        if (u_dut.u_mc.state == 4'd11 && tg_prev == 4'd10 && rounds_seen < ROUNDS) begin
            // 转换沿直接采运行计数（锁存 tg_rd_cyc 本拍 NBA 尚未生效）；
            // 同时采锁存值用于交叉验证，两者应只差锁存延迟 1-2 拍
            rd_tab[rounds_seen]  = u_dut.u_mc.tg_cyc_cnt;
            err_tab[rounds_seen] = u_dut.u_mc.err_cnt;
            rounds_seen = rounds_seen + 1;
        end
    end

    //-------------------------------------------------------------------------
    // 主流程
    //-------------------------------------------------------------------------
    integer i;
    real bw;
    initial begin
        $display("[TB] proj tg: OSTD sweep (model side), %0d rounds x %0d bursts",
                 ROUNDS, 16);
        #100ns  pll_sys_locked = 1;
        #100ns  pll_ddr_locked = 1;

        // P1: CFG_DONE
        wait (u_dut.cfg_st == 2'b01);
        fork : wait_cfg
            begin
                wait (cfg_done === 1'b1);
                $display("[TB][%0t] P1 PASS: model CFG_DONE=1", $time);
                disable wait_cfg;
            end
            begin
                #TMO_NS;
                $display("[TB][%0t] P1 FAIL: CFG_DONE timeout", $time);
                n_err = n_err + 1;
                disable wait_cfg;
            end
        join

        // P2: TG 扫描完成
        fork : wait_tg
            begin
                wait (u_dut.mc_done === 1'b1);
                if (u_dut.mc_fail === 1'b0)
                    $display("[TB][%0t] P2 PASS: tg done=1 fail=0", $time);
                else begin
                    $display("[TB][%0t] P2 FAIL: tg fail=1", $time);
                    n_err = n_err + 1;
                end
                disable wait_tg;
            end
            begin
                #TMO_NS;
                $display("[TB][%0t] P2 FAIL: tg done timeout (state=%0d issued=%0d completed=%0d)",
                         $time, u_dut.mc_state, u_dut.u_mc.tg_issued,
                         u_dut.u_mc.tg_completed);
                n_err = n_err + 1;
                disable wait_tg;
            end
        join

        // P3: 曲线 + 每轮 err 检查
        $display("[TB] ---- OSTD sweep curve (model side) ----");
        $display("[TB] ostd  rd_cyc  err  bw_GBps");
        for (i = 0; i < rounds_seen; i = i + 1) begin
            bw = (16.0 * 4096.0 * 200.0e6) / rd_tab[i] / 1.0e9;
            $display("[TB] %4d  %6d  %3d  %6.2f",
                     i + 1, rd_tab[i], err_tab[i], bw);
            if (err_tab[i] !== 16'd0) begin
                $display("[TB] P3 FAIL: round %0d err=%0d", i + 1, err_tab[i]);
                n_err = n_err + 1;
            end
        end
        if (rounds_seen == ROUNDS)
            $display("[TB] P3 PASS: all %0d rounds err=0", ROUNDS);
        else begin
            $display("[TB] P3 FAIL: rounds_seen=%0d (expect %0d)", rounds_seen, ROUNDS);
            n_err = n_err + 1;
        end

        // P4: 模型无协议错误
        if (ctrl_err === 1'b0)
            $display("[TB][%0t] P4 PASS: model CTRL_ERR=0", $time);
        else begin
            $display("[TB][%0t] P4 FAIL: model CTRL_ERR=1", $time);
            n_err = n_err + 1;
        end

        if (n_err == 0)
            $display("[TB] ================= PROJ TG ALL PASS =================");
        else
            $display("[TB] ================= PROJ TG FAIL (n_err=%0d) =================",
                     n_err);
        $finish;
    end

    // 全局超时兜底
    initial begin
        #80_000_000;
        $display("[TB] GLOBAL TIMEOUT");
        $display("[TB] PROJ TG FAIL (timeout)");
        $finish;
    end

endmodule
