`timescale 1ns/1ps
//==============================================================================
// tb_cam_i2c_init.sv -- cam_i2c_init 单元 TB（cam-i2c-rtl-init-plan §5 / P2-4）
//
// 用例：
//   C1  cam0 正常初始化：start -> 电源时序（cam_en 低->高）-> 142 条全序列
//       与 golden(imx415_seq_cam0.hex) 逐条比对 -> init_done=1
//   C2  错峰：cam1.start = cam0.init_done（电平），cam0 完成后 cam1 才上电
//       配置；golden(imx415_seq_cam1.hex) 逐条比对（MODE_4K=0 走 geo1080）
//   C3  注错整轮失败：BFM 地址恒 NACK -> 每条目重试 RETRY_MAX 次 -> 整轮
//       放电重试 ROUND_MAX 轮 -> init_fail=1（sticky）、init_done=0、
//       cam_en 保持上电态（同固件失败退出行为）
//   C4  rerun：C3 后解除 NACK 重新 start -> init_fail 清除、全序列成功、
//       golden 比对通过（覆盖 sticky 清除 + rerun 全流程）
//
// 加速参数：SYS_FREQ=10k（10 cyc/ms）、I2C_FREQ=100k、各 MS 压到 1~2ms。
// 判定：errors==0 -> "TB_CAM_I2C_INIT: PASS"。
//==============================================================================
module tb_cam_i2c_init;

    int errors = 0;

    logic clk = 1'b0;
    always #50 clk = ~clk;                     // 10 MHz
    logic rstn;

    localparam realtime TMO_INIT = 120ms;      // 单次 init 超时
    localparam realtime TMO_FAIL = 80ms;       // C3 失败路径超时

    //------------------------------------------------------------------
    // 三路实例：cam0（正常）/ cam1（错峰从机）/ camf（注错+rerun）
    //------------------------------------------------------------------
    // ---- cam0 ----
    logic       start0 = 1'b0;
    logic       scl0, sda0, scl_o0, sda_o0;
    logic       sda_pull0, scl_pull0;
    logic       cam_en0, done0, fail0, busy0;
    logic [7:0] idx0;
    logic [1:0] rnd0;

    i2c_slave_bfm u_slv0 (
        .clk(clk), .rst_n(rstn), .scl(scl0), .sda(sda0),
        .sda_pull(sda_pull0), .scl_pull(scl_pull0),
        .nack_addr(1'b0), .stretch_n(32'd0), .stuck_scl(1'b0),
        .cap_reg(), .cap_val(), .cap_we(), .cap_stop(),
        .rd_data(8'h00), .cur_reg()
    );
    assign scl0 = scl_o0 & ~scl_pull0;
    assign sda0 = sda_o0 & ~sda_pull0;

    cam_i2c_init #(
        .SYS_FREQ(10_000_000), .I2C_FREQ(100_000), .MODE_4K(1'b1),
        .PWR_OFF_MS(2), .PWR_SETTLE_MS(1), .RETRY_GAP_MS(1), .DISCHARGE_MS(2)
    ) dut0 (
        .clk(clk), .rst_n(rstn),
        .scl_pad_i(scl0), .scl_pad_o(scl_o0),
        .sda_pad_i(sda0), .sda_pad_o(sda_o0),
        .cam_en(cam_en0),
        .start(start0), .init_done(done0), .init_fail(fail0), .busy(busy0),
        .dbg_idx(idx0), .dbg_round(rnd0), .dbg_retry()
    );

    // ---- cam1（错峰从机：start = cam0.init_done）----
    logic       scl1, sda1, scl_o1, sda_o1;
    logic       sda_pull1, scl_pull1;
    logic       cam_en1, done1, fail1, busy1;

    i2c_slave_bfm u_slv1 (
        .clk(clk), .rst_n(rstn), .scl(scl1), .sda(sda1),
        .sda_pull(sda_pull1), .scl_pull(scl_pull1),
        .nack_addr(1'b0), .stretch_n(32'd0), .stuck_scl(1'b0),
        .cap_reg(), .cap_val(), .cap_we(), .cap_stop(),
        .rd_data(8'h00), .cur_reg()
    );
    assign scl1 = scl_o1 & ~scl_pull1;
    assign sda1 = sda_o1 & ~sda_pull1;

    cam_i2c_init #(
        .SYS_FREQ(10_000_000), .I2C_FREQ(100_000), .MODE_4K(1'b0),
        .PWR_OFF_MS(2), .PWR_SETTLE_MS(1), .RETRY_GAP_MS(1), .DISCHARGE_MS(2)
    ) dut1 (
        .clk(clk), .rst_n(rstn),
        .scl_pad_i(scl1), .scl_pad_o(scl_o1),
        .sda_pad_i(sda1), .sda_pad_o(sda_o1),
        .cam_en(cam_en1),
        .start(done0), .init_done(done1), .init_fail(fail1), .busy(busy1),
        .dbg_idx(), .dbg_round(), .dbg_retry()
    );

    // ---- camf（注错 + rerun，RETRY_MAX=2 加速失败路径）----
    logic       start_f = 1'b0;
    logic       nack_f  = 1'b0;
    logic       scl_f, sda_f, scl_o_f, sda_o_f;
    logic       sda_pull_f, scl_pull_f;
    logic       cam_en_f, done_f, fail_f, busy_f;
    logic [1:0] rnd_f;

    i2c_slave_bfm u_slvf (
        .clk(clk), .rst_n(rstn), .scl(scl_f), .sda(sda_f),
        .sda_pull(sda_pull_f), .scl_pull(scl_pull_f),
        .nack_addr(nack_f), .stretch_n(32'd0), .stuck_scl(1'b0),
        .cap_reg(), .cap_val(), .cap_we(), .cap_stop(),
        .rd_data(8'h00), .cur_reg()
    );
    assign scl_f = scl_o_f & ~scl_pull_f;
    assign sda_f = sda_o_f & ~sda_pull_f;

    cam_i2c_init #(
        .SYS_FREQ(10_000_000), .I2C_FREQ(100_000), .MODE_4K(1'b1),
        .PWR_OFF_MS(2), .PWR_SETTLE_MS(1), .RETRY_GAP_MS(1), .DISCHARGE_MS(2),
        .RETRY_MAX(2), .ROUND_MAX(3)
    ) dutf (
        .clk(clk), .rst_n(rstn),
        .scl_pad_i(scl_f), .scl_pad_o(scl_o_f),
        .sda_pad_i(sda_f), .sda_pad_o(sda_o_f),
        .cam_en(cam_en_f),
        .start(start_f), .init_done(done_f), .init_fail(fail_f), .busy(busy_f),
        .dbg_idx(), .dbg_round(rnd_f), .dbg_retry()
    );

    //------------------------------------------------------------------
    // 判定 / 驱动
    //------------------------------------------------------------------
    task automatic chk(input bit cond, input string msg);
        if (cond) $display("[TB][ ok ] %0s", msg);
        else begin
            errors++;
            $display("[TB][FAIL] %0s (t=%0t)", msg, $time);
        end
    endtask

    task automatic pulse_start(ref logic s);
        @(negedge clk); s = 1'b1;
        @(negedge clk); s = 1'b0;
    endtask

    // 等待标志置位（轮询实现：ref 实参不能与 fork 同用，vlog-13219）
    task automatic wait_flag(ref logic f, input realtime tmo, input string tag);
        realtime t_end = $realtime + tmo;
        while (f !== 1'b1 && $realtime < t_end)
            @(posedge clk);
        if (f !== 1'b1) begin
            errors++;
            $display("[TB][FAIL] %s timeout (t=%0t)", tag, $time);
        end
    endtask

    // golden 全序列比对（which: 0=cam0 1=cam1 2=camf 用 cam0 表）
    task automatic check_golden(input int which, input string tag);
        logic [23:0] gol[0:255];
        logic [23:0] cap[$];
        int n_exp, e0 = errors;
        $readmemh(which == 1 ? "imx415_seq_cam1.hex" : "imx415_seq_cam0.hex", gol);
        n_exp = gol[0];
        case (which)
            0: foreach (u_slv0.cap_list[i])
                   cap.push_back({u_slv0.cap_list[i].addr, u_slv0.cap_list[i].data});
            1: foreach (u_slv1.cap_list[i])
                   cap.push_back({u_slv1.cap_list[i].addr, u_slv1.cap_list[i].data});
            2: foreach (u_slvf.cap_list[i])
                   cap.push_back({u_slvf.cap_list[i].addr, u_slvf.cap_list[i].data});
        endcase
        chk(n_exp == 142, $sformatf("%s golden count %0d == 142", tag, n_exp));
        chk(cap.size() == n_exp,
            $sformatf("%s captured %0d entries == golden %0d", tag, cap.size(), n_exp));
        for (int i = 0; i < n_exp && i < cap.size(); i++)
            if (cap[i] !== gol[i+1]) begin
                errors++;
                $display("[TB][FAIL] %s entry %0d: captured %06x != golden %06x",
                         tag, i, cap[i], gol[i+1]);
            end
        if (errors == e0)
            $display("[TB][ ok ] %s golden full-sequence match (%0d entries)",
                     tag, n_exp);
    endtask

    //------------------------------------------------------------------
    // 主序列
    //------------------------------------------------------------------
    realtime t0;

    initial begin
        $display("[TB] tb_cam_i2c_init start");
        rstn = 1'b0;
        repeat (5) @(posedge clk);
        rstn = 1'b1;
        repeat (5) @(posedge clk);

        //==============================================================
        // C1 + C2：cam0 正常 -> init_done 触发 cam1（错峰）
        //==============================================================
        chk(scl0 === 1'b1 && sda0 === 1'b1, "C0 idle bus cam0");
        chk(cam_en0 === 1'b0, "C0 cam_en0 off before start");

        t0 = $realtime;
        pulse_start(start0);
        repeat (2) @(posedge clk);
        chk(busy0 === 1'b1, "C1 busy after start");
        chk(cam_en0 === 1'b0, "C1 cam_en low in PWR_OFF phase");

        wait (cam_en0 === 1'b1);                       // 硬复位结束上电
        chk(($realtime - t0) >= 1_900_000ns,
            $sformatf("C1 cam_en high at %0t ns >= 1.9ms (PWR_OFF=2ms)",
                      $realtime - t0));

        wait_flag(done0, TMO_INIT, "C1 cam0 init_done");
        if (done0) begin
            chk(($realtime - t0) >= 2_900_000ns,
                $sformatf("C1 total %0t ns >= 3ms (PWR_OFF+SETTLE)",
                          $realtime - t0));
            chk(fail0 === 1'b0, "C1 no init_fail");
            check_golden(0, "C1");
        end

        // cam1 由 cam0 的 init_done 上升沿自动启动（打拍沿检测需 2~3 拍）
        repeat (4) @(posedge clk);
        chk(busy1 === 1'b1, "C2 cam1 started by cam0 init_done (staggered)");
        chk(cam_en1 === 1'b0, "C2 cam1 cam_en low (staggered power phase)");
        wait_flag(done1, TMO_INIT, "C2 cam1 init_done");
        if (done1) begin
            chk(fail1 === 1'b0, "C2 no init_fail");
            check_golden(1, "C2");
        end

        //==============================================================
        // C3：注错（地址恒 NACK）-> 重试/放电 3 轮 -> FAIL
        //==============================================================
        nack_f = 1'b1;
        pulse_start(start_f);
        wait_flag(fail_f, TMO_FAIL, "C3 init_fail");
        if (fail_f) begin
            chk(done_f === 1'b0, "C3 init_done stays 0");
            chk(cam_en_f === 1'b1, "C3 cam_en held high after FAIL");
            chk(rnd_f === 2'd3, $sformatf("C3 round counter = 3 (got %0d)", rnd_f));
            chk(busy_f === 1'b0, "C3 fsm back to idle");
        end

        //==============================================================
        // C4：解除 NACK rerun -> 成功 + sticky 清除
        //==============================================================
        nack_f = 1'b0;
        pulse_start(start_f);
        repeat (2) @(posedge clk);
        chk(fail_f === 1'b0, "C4 init_fail cleared by rerun start");
        wait_flag(done_f, TMO_INIT, "C4 rerun init_done");
        if (done_f) begin
            chk(fail_f === 1'b0, "C4 no init_fail after rerun");
            check_golden(2, "C4");
        end

        //--------------------------------------------------------------
        $display("TB_CAM_I2C_INIT: %s errors=%0d",
                 (errors == 0) ? "PASS" : "FAIL", errors);
        $finish;
    end

    //------------------------------------------------------------------
    // 全局看门狗
    //------------------------------------------------------------------
    initial begin
        #400_000_000;                          // 400 ms 绝对窗
        $display("[TB][FATAL] global timeout");
        $display("TB_CAM_I2C_INIT: FAIL errors=%0d (timeout)", errors + 1);
        $finish;
    end

`ifdef DUMP
    initial begin
        $dumpfile("tb_cam_i2c_init.vcd");
        $dumpvars(0, tb_cam_i2c_init);
    end
`endif

endmodule
