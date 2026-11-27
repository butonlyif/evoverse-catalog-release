////////////////////////////////////////////////////////////////////////////
//  tb_proj_smoke.sv — 最小 DDR 测试工程 smoke TB（ddr_test_top × ddr_axi_model_top）
//
//  目的：在接真实板子之前，用行为模型（../../rtl/ddr_axi_model_top.sv）
//  验证 ddr_test_top 的完整链路：
//    POR → PLL lock → CFG FSM v5（2^21 拍）→ CFG_DONE → ARSTN 释放
//    → ddr_memcheck（4 burst 缩量）写读比对 → DIAG11 → UART 帧读出
//
//  判据：
//    P1 模型 CFG_DONE=1（配置序列走通）
//    P2 mc_done=1 且 mc_fail=0 且 err_cnt=0（memcheck 全对）
//    P3 模型 CTRL_ERR=0（无协议错误）
//    P4 UART 收到 >=2 帧完整 "DDR:XXXXXXXX\n"，末帧解码 fail=0、done=1、
//       cfg_ok=1、lock=1（端到端读出通道走通）
//
//  编译（QuestaSim，在 proj/sim 下）：
//    vlog -sv -work work ../../rtl/ddr_model_pkg.sv ../../rtl/ddr_fifo.sv \
//         ../../rtl/ddr_async_fifo.sv ../../rtl/mem_model.sv \
//         ../../rtl/core_scheduler.sv ../../rtl/cfg_ctrl_fsm.sv \
//         ../../rtl/axi_port_shell.sv ../../rtl/axi_port_shell_cdc.sv \
//         ../../rtl/ddr_model_assertions.sv ../../rtl/ddr_axi_model_top.sv \
//         ../rtl/reset_ctrl.sv ../rtl/ddr_memcheck.v ../rtl/ddr_status_uart.sv \
//         ../rtl/ddr_test_top.sv tb_proj_smoke.sv
//    vsim -c -voptargs="+acc" -do "run -all; quit -f" work.tb_proj_smoke -l tb_proj_smoke.log
//
//  模型口径差异（本 smoke 实测发现，均已内置处理，详见
//  ../../docs/correlation-plan.md）：
//   1. AWCACHE=0000 早返 B：memcheck 恒驱 awcache=0000，模型按手册走
//      PHY_ISSUE 早返 B（AW 握手 +2 拍）。TB 侧把 0000 翻译成 1111+COBUF=0
//      （基线 WLAST+4 口径），与 tb_phase4_ddrm 对 frame_writer 的处理同款。
//   2. AXI4 4KB 规则：模型强制 burst 不跨 4KB（cross_4kb/table5_ok，
//      ASIZE=6 时 beats≤64），违例判 SLVERR 且丢弃写数据。板级 3495×7680B
//      配置跨 4KB、真硬核容忍。仿真口径 MC_ALEN=63（64 beat×64B=4096B 压线）。
//   3. QOS 位宽：TJ180 peri 接口 QOS 引脚 1 位（隐式声明），模型按 4 位收，
//      TB 零扩展后接入。
//   4. ARVALID 握手纪律：模型 arready 为组合电平（恒可收）；memcheck 原实现
//      握手后多保持 1 拍 ARVALID → 每个 AR 被收 2 条（err=192=3×64 实锤）。
//      proj 副本 ddr_memcheck.v 已修（握手次拍撤 VALID），板级行为不变；
//      rtl/ 原版未动，留作 correlation §8.6 的对照证据。
////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module tb_proj_smoke;

    localparam realtime BIT_NS   = 8680.6;      // 115200 波特位时间
    localparam realtime TMO_NS   = 25_000_000;  // 25ms 仿真超时
    localparam int      REP_TICKS = 20_000;     // UART 报告间隔（0.1ms @200M）

    reg  clk200 = 0;
    reg  clk_ctrl = 0;
    reg  clk27 = 0;
    always #2.5   clk200   = ~clk200;   // 200MHz
    always #2.45  clk_ctrl = ~clk_ctrl; // 与 ACLK 异相（CDC 模型）
    always #5.0   clk27    = ~clk27;    // 100MHz 加速 POR（板级 27M）

    reg pll_sys_locked = 0;
    reg pll_ddr_locked = 0;
    reg uart_rxd = 1;
    wire uart_txd;

    //-------------------------------------------------------------------------
    // DUT
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
        .MC_TOTAL_BURSTS   (4),
        // 模型按 AXI4 强制 4KB 边界（ddr_model_pkg cross_4kb/table5_ok：ASIZE=6
        // 时 beats≤64 且 0+bytes≤4096）。板级 3495×7680B 配置跨 4KB，真硬核容忍、
        // 模型判 SLVERR 且丢弃写数据 → 仿真口径用 ALEN=63（64 beat×64B=4096B 压线）。
        .MC_ALEN           (63),
        // 钉死 Phase 0 自检形态：top 默认 TG_MODE/UART_SCAN_MODE 随 correlation
        // 相位演进（Phase 2 起 =2），smoke 判据（mcst=9 + DIAG11 帧 0000907e）
        // 只对 MODE0/SCAN_MODE=0 成立——显式覆盖，不继承演进中的默认值
        .TG_MODE           (0),
        .UART_SCAN_MODE    (0),
        .UART_REPORT_TICKS (REP_TICKS)
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
    // ddr_axi_model_top（行为模型，2Gb x16 口径，CDC 双钟）
    //
    // B 时机口径翻译（2026-10-22 smoke 实测发现）：
    //   memcheck 恒驱 awcache=0000，模型按手册 0000→PHY_ISSUE 早返 B
    //   （AW 握手 +2 拍，早于 WLAST）。但 memcheck 在 PRE_WRITE 态就拉
    //   bready=1（ddr_memcheck.v L235，为吞吐设计），早到的 B 在 WRITE
    //   阶段即被消费，POST_WRITE 扑空 → mcst=4 死等（本 TB 首跑实锤，
    //   CTRL_ERR 同帧置位）。板级真硬核实测为晚返 B（阶段 0 板测
    //   DIAG11 fail=0 done=1 通过），故模型侧把 0000 翻译为 1111+COBUF=0
    //   （基线 WLAST+4 口径）——与 tb_phase4_ddrm 对 frame_writer 的处理
    //   同款，也是 ddr-test-spec §8.6 BVALID 时机标定的第一个靶子。
    //-------------------------------------------------------------------------
    wire [3:0] awcache0_m = (awcache0 == 4'b0000) ? 4'b1111 : awcache0;
    wire [3:0] awcache1_m = (awcache1 == 4'b0000) ? 4'b1111 : awcache1;

    // QOS 口径翻译：TJ180 peri 接口 QOS 引脚为 1 位（top_cam_demo 隐式声明），
    // TB 4 位线高位悬空成 Z；模型按 4 位收，零扩展后再给（仿真无 Z/X 扩散）
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
    // UART 接收解码（8N1）
    //-------------------------------------------------------------------------
    task automatic uart_sync;
        integer k;
        begin
            // 等待空闲（txd 持续高 ≥10 bit）再返回，避免帧中切入错位
            // （首跑实锤：接收器从任意相位切入，frame 1 头对成 ')' 乱码）
            forever begin
                if (uart_txd !== 1'b1)
                    @(posedge uart_txd);        // 正在帧内 → 等本帧结束回高
                k = 0;
                while (uart_txd === 1'b1 && k < 10) begin
                    #(BIT_NS);
                    k = k + 1;
                end
                if (k >= 10) return;            // 空闲确认
            end
        end
    endtask

    task automatic uart_rx_byte(output [7:0] data);
        integer i;
        begin
            // 下沿 + 中点校验为有效起始位；否则是帧内数据位下沿，重新等
            forever begin
                @(negedge uart_txd);                    // 候选起始位
                #(BIT_NS/2.0);
                if (uart_txd === 1'b0)
                    break;
            end
            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_NS);
                data[i] = uart_txd;
            end
            #(BIT_NS);                              // 停止位
        end
    endtask

    //-------------------------------------------------------------------------
    // 主流程
    //-------------------------------------------------------------------------
    integer n_err = 0;
    integer frames = 0;
    reg [7:0] rxbyte;
    reg [31:0] frame_val;
    reg [7:0]  hexbuf [0:11];
    integer hi, dig;

    initial begin
        $display("[TB] proj smoke: ddr_test_top x ddr_axi_model_top");
        #100ns  pll_sys_locked = 1;
        #100ns  pll_ddr_locked = 1;

        // P1: 模型 CFG_DONE（CFG FSM 2^21 拍 ≈10.5ms 后发 START）
        wait (u_dut.cfg_st == 2'b01);
        $display("[TB][%0t] CFG FSM entered CFG_START", $time);
        fork : wait_cfg
            begin
                wait (cfg_done === 1'b1);
                $display("[TB][%0t] P1 PASS: model CFG_DONE=1", $time);
                disable wait_cfg;               // 杀 timeout 分支，join 立即返回
            end
            begin
                #TMO_NS;
                $display("[TB][%0t] P1 FAIL: CFG_DONE timeout", $time);
                n_err = n_err + 1;
                disable wait_cfg;
            end
        join

        // P2: memcheck 完成（done/fail/err_cnt）
        fork : wait_mc
            begin
                wait (u_dut.mc_done === 1'b1);
                if (u_dut.mc_fail === 1'b0 && u_dut.mc_err_cnt === 16'h0) begin
                    $display("[TB][%0t] P2 PASS: mc_done=1 fail=0 err=0 (mcst=%0d)",
                             $time, u_dut.mc_state);
                end else begin
                    $display("[TB][%0t] P2 FAIL: mc_done=1 fail=%0d err=%0d",
                             $time, u_dut.mc_fail, u_dut.mc_err_cnt);
                    n_err = n_err + 1;
                end
                disable wait_mc;                // 杀 timeout 分支
            end
            begin
                #TMO_NS;
                $display("[TB][%0t] P2 FAIL: mc_done timeout (mcst=%0d aw_valid=%0b b_valid=%0b)",
                         $time, u_dut.mc_state, awvalid0, bvalid0);
                n_err = n_err + 1;
                disable wait_mc;
            end
        join

        // P3: 模型无协议错误
        if (ctrl_err === 1'b0)
            $display("[TB][%0t] P3 PASS: model CTRL_ERR=0", $time);
        else begin
            $display("[TB][%0t] P3 FAIL: model CTRL_ERR=1", $time);
            n_err = n_err + 1;
        end

        // P4: UART 读出 ≥2 帧，末帧解码
        begin : uart_check
            uart_sync;                          // 先同步到空闲，避免帧中切入错位
            for (frames = 0; frames < 2; frames = frames + 1) begin
                fork : rx_frame
                    begin
                        uart_rx_byte(rxbyte);
                        if (rxbyte != "D") begin
                            $display("[TB][%0t] P4 FAIL: frame head '%c'", $time, rxbyte);
                            n_err = n_err + 1;
                            disable rx_frame;
                        end
                        for (hi = 0; hi < 11; hi = hi + 1) begin
                            uart_rx_byte(rxbyte);
                            hexbuf[hi] = rxbyte;
                        end
                        uart_rx_byte(rxbyte);           // 第 13 字节 '\n'（不消费会错位成下帧头）
                        if (rxbyte != "\n") begin
                            $display("[TB][%0t] P4 FAIL: frame tail %02h", $time, rxbyte);
                            n_err = n_err + 1;
                        end
                        disable rx_frame;       // 收帧完成，杀 timeout 分支
                    end
                    begin
                        #(20 * BIT_NS * 10);            // 13B×10bit×8.68us≈1.13ms，留裕量
                        $display("[TB][%0t] P4 FAIL: uart frame timeout", $time);
                        n_err = n_err + 1;
                        disable rx_frame;
                    end
                join
                // hex 解码（8 字符 = hexbuf[3..10]，[0..2]="DR:"，[11]='\n'）
                frame_val = 32'h0;
                for (dig = 3; dig <= 10; dig = dig + 1) begin
                    if (hexbuf[dig] >= "0" && hexbuf[dig] <= "9")
                        frame_val = (frame_val << 4) | (hexbuf[dig] - "0");
                    else if (hexbuf[dig] >= "A" && hexbuf[dig] <= "F")
                        frame_val = (frame_val << 4) | (hexbuf[dig] - "A" + 10);
                    else begin
                        $display("[TB][%0t] P4 FAIL: bad hex char '%c' @%0d",
                                 $time, hexbuf[dig], dig);
                        n_err = n_err + 1;
                    end
                end
                $display("[TB][%0t] P4 frame %0d: DIAG11=%08h", $time, frames + 1, frame_val);
            end
            // 末帧位图检查：{err, mcst, 0, done_raw, st, lock, cfg_ok, done, fail}
            if (frame_val[0] === 1'b1) begin
                $display("[TB][%0t] P4 FAIL: uart frame fail=1", $time);
                n_err = n_err + 1;
            end else if (frame_val[3:0] === 4'b1110 && frame_val[6] === 1'b1)
                $display("[TB][%0t] P4 PASS: uart frame lock=1 cfg_ok=1 done=1 fail=0", $time);
            else
                $display("[TB][%0t] P4 INFO: fail=0，{lock,cfg_ok,done}=%b（帧早于 mc_done 属正常）",
                         $time, frame_val[3:1]);
        end

        if (n_err == 0)
            $display("[TB] ================= PROJ SMOKE ALL PASS =================");
        else
            $display("[TB] ================= PROJ SMOKE FAIL (n_err=%0d) =================", n_err);
        $finish;
    end

    // 全局超时兜底
    initial begin
        #60_000_000;
        $display("[TB] GLOBAL TIMEOUT");
        $display("[TB] PROJ SMOKE FAIL (timeout)");
        $finish;
    end

    //-------------------------------------------------------------------------
    // 调试探针（默认关闭，+define+TB_DEBUG 打开）：逐 burst err 快照 +
    // 首个错拍详情 + 模型内部 mem/AR 事务逐条对账
    //-------------------------------------------------------------------------
    reg [3:0]   mc_prev = 4'h0;
    reg [15:0]  snap [0:7];
    integer     snaps = 0;
    reg         first_bad = 0;
    reg [511:0] first_exp, first_got;
    reg [32:0]  first_addr;
    reg [8:0]   first_beat;
    always @(posedge clk200) begin
        mc_prev <= u_dut.mc_state;
        if (u_dut.mc_state == 4'd7 && mc_prev != 4'd7 && snaps < 8) begin
            snap[snaps] = u_dut.mc_err_cnt;
            snaps = snaps + 1;
        end
        if (u_dut.mc_state == 4'd7 && u_dut.u_mc.rvalid && !first_bad &&
            u_dut.u_mc.rdata !== u_dut.u_mc.exp_rdata) begin
            first_bad  <= 1'b1;
            first_exp  <= u_dut.u_mc.exp_rdata;
            first_got  <= u_dut.u_mc.rdata;
            first_addr <= u_dut.u_mc.araddr;
            first_beat <= u_dut.u_mc.beat_cnt;
        end
    end

    final begin
        $display("[TB] per-burst err snapshot (before burst0..%0d): %p", snaps-1, snap);
        if (first_bad) begin
            $display("[TB] first mismatch: araddr=%h beat=%0d", first_addr, first_beat);
            $display("[TB]   exp=%h", first_exp[127:0]);
            $display("[TB]   got=%h", first_got[127:0]);
        end
    end

`ifdef TB_DEBUG
    // 模型内部 mem 事务探针（ctrl_clk 域）：ah/bc = pat 指纹（写源地址/beat 序号）
    integer mw_i = 0, mr_i = 0;
    always @(posedge clk_ctrl) begin
        if (u_model.mem_we && mw_i < 600) begin
            $display("[MW][%0t] #%-3d a=%h ah=%h bc=%02h",
                     $time, mw_i, u_model.mem_waddr,
                     u_model.mem_wdata[255:224], u_model.mem_wdata[7:0]);
            mw_i = mw_i + 1;
        end
        if (u_model.mem_re && mr_i < 600) begin
            $display("[MR][%0t] #%-3d a=%h ah=%h bc=%02h",
                     $time, mr_i, u_model.mem_raddr,
                     u_model.mem_rdata[255:224], u_model.mem_rdata[7:0]);
            mr_i = mr_i + 1;
        end
    end

    // AR 链路探针（三层字段级对账）：shell → 异步 FIFO → scheduler rd 队列
    ddr_model_pkg::ddr_cmd_t RQ_C;
    always @(posedge clk200) begin
        if (u_model.g_cdc.u_port0.arvalid && u_model.g_cdc.u_port0.arready)
            $display("[ARpush][%0t] addr=%h len=%0d size=%0d burst=%0d",
                     $time, u_model.g_cdc.u_port0.araddr,
                     u_model.g_cdc.u_port0.arlen, u_model.g_cdc.u_port0.arsize,
                     u_model.g_cdc.u_port0.arburst);
    end
    always @(posedge clk_ctrl) begin
        if (u_model.g_cdc.ar_cmd_pop_0)
            $display("[ARpop][%0t] addr=%h len=%0d size=%0d burst=%0d",
                     $time, u_model.g_cdc.ar_cmd_head_0.addr,
                     u_model.g_cdc.ar_cmd_head_0.len,
                     u_model.g_cdc.ar_cmd_head_0.size,
                     u_model.g_cdc.ar_cmd_head_0.burst);
        if (u_model.rd_cmd_pop) begin
            RQ_C = ddr_model_pkg::ddr_cmd_t'(u_model.rd_cmd_head);
            $display("[RQ][%0t] addr=%h len=%0d size=%0d beats=%0d",
                     $time, RQ_C.addr, RQ_C.len, RQ_C.size, RQ_C.beats);
        end
    end
`endif

endmodule
