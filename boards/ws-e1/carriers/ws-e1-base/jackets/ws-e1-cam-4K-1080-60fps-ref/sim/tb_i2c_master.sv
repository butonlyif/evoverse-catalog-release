`timescale 1ns/1ps
//==============================================================================
// tb_i2c_master.sv -- rtl/i2c_master.sv 单元 TB（cam-i2c-rtl-init-plan P1 前置门）
//
// 覆盖（计划 §5）：
//   T0  复位释放后总线空闲电平（SCL=SDA=1）
//   T1  完整寄存器写（START + 0x34 + regH + regL + val + STOP），ACK 全程正确
//   T2  第二次写（连续性/指针更新）
//   T3  读 + 重复 START（0x34 写指针 -> SR -> 0x35 读 1 字节 NACK 收尾），
//       rx_data/rx_valid 正确
//   T4  地址 NACK 捕获（nack 标志）
//   T5  从机时钟拉伸（拉伸 < 看门狗窗口）事务完整
//   T6  SCL 卡死 -> 看门狗 err 置位、done 返回；CMD_RESET 清 err
//   T7  err 事后新事务正常（不残留故障态）
//   T8  实参数冒烟（SYS_FREQ=200M / I2C_FREQ=50k，G3）：SCL 高/低半周期
//       ≈10us 与一次完整寄存器写
//
// 总线模型：开漏 wired-AND（master pad_o 1=释放；slave _pull 1=拉低）。
// slave BFM 在 TB 时钟沿采样总线沿（START/STOP 优先于数据采样），
// ACK 采样在 SCL 沿（避开 master 释放 SDA 的同沿竞态）。
//
// 判定：errors==0 -> "TB_I2C_MASTER: PASS"。
//==============================================================================
module tb_i2c_master;

    localparam logic [2:0] CMD_START = 3'd1, CMD_TX = 3'd2, CMD_RX = 3'd3,
                           CMD_STOP  = 3'd4, CMD_RESET = 3'd5;

    int errors = 0;

    //------------------------------------------------------------------
    // DUT #1：小参数（快仿真，T_SCL=10 clk，看门狗 60 clk）
    //------------------------------------------------------------------
    logic clk_s = 1'b0;
    always #50 clk_s = ~clk_s;                  // 10 MHz

    logic       rstn_s;
    logic [2:0] cmd_s;
    logic [7:0] txdat_s;
    logic       txack_s, go_s;
    logic       scl_o_s, sda_o_s;
    wire        scl_s, sda_s;
    logic       busy_s, done_s, nack_s, rxv_s, err_s;
    logic [7:0] rxdat_s;

    i2c_master #(
        .SYS_FREQ          (10_000),
        .I2C_FREQ          (1_000),
        .SCL_TIMEOUT_CYCLES(60),
        .SCL_TO_W          (6)
    ) dut (
        .clk      (clk_s),
        .rst_n    (rstn_s),
        .scl_pad_i(scl_s),
        .scl_pad_o(scl_o_s),
        .sda_pad_i(sda_s),
        .sda_pad_o(sda_o_s),
        .cmd      (cmd_s),
        .tx_data  (txdat_s),
        .tx_ack   (txack_s),
        .go       (go_s),
        .busy     (busy_s),
        .done     (done_s),
        .nack     (nack_s),
        .rx_data  (rxdat_s),
        .rx_valid (rxv_s),
        .err      (err_s)
    );

    // slave BFM（小参数 DUT 的总线对端）
    logic       slv_rstn_s;
    logic       sda_pull_s, scl_pull_s;
    logic       nack_addr_s = 1'b0, stuck_scl_s = 1'b0;
    logic [31:0] stretch_s = 0;
    logic [15:0] cap_reg_s;
    logic [7:0]  cap_val_s;
    logic        cap_we_s, cap_stop_s;
    logic [15:0] cur_reg_s;

    wire [7:0] rd_data_s = (cur_reg_s == 16'h301C) ? 8'h5A :
                           (cur_reg_s == 16'h3024) ? 8'hCA : 8'h00;

    i2c_slave_bfm u_slv_s (
        .clk      (clk_s),
        .rst_n    (rstn_s & slv_rstn_s),
        .scl      (scl_s),
        .sda      (sda_s),
        .sda_pull (sda_pull_s),
        .scl_pull (scl_pull_s),
        .nack_addr(nack_addr_s),
        .stretch_n(stretch_s),
        .stuck_scl(stuck_scl_s),
        .cap_reg  (cap_reg_s),
        .cap_val  (cap_val_s),
        .cap_we   (cap_we_s),
        .cap_stop (cap_stop_s),
        .rd_data  (rd_data_s),
        .cur_reg  (cur_reg_s)
    );

    // 开漏总线（wired-AND）
    assign scl_s = scl_o_s & ~scl_pull_s;
    assign sda_s = sda_o_s & ~sda_pull_s;

    //------------------------------------------------------------------
    // DUT #2：实参数冒烟（G3：SYS_FREQ=200M / I2C_FREQ=50k，默认看门狗）
    //------------------------------------------------------------------
    logic clk_f = 1'b0;
    always #2.5 clk_f = ~clk_f;                 // 200 MHz

    logic       rstn_f;
    logic [2:0] cmd_f;
    logic [7:0] txdat_f;
    logic       txack_f, go_f;
    logic       scl_o_f, sda_o_f;
    wire        scl_f, sda_f;
    logic       busy_f, done_f, nack_f, rxv_f, err_f;
    logic [7:0] rxdat_f;

    i2c_master #(
        .SYS_FREQ(200_000_000),
        .I2C_FREQ(50_000)
    ) dut_fast (
        .clk      (clk_f),
        .rst_n    (rstn_f),
        .scl_pad_i(scl_f),
        .scl_pad_o(scl_o_f),
        .sda_pad_i(sda_f),
        .sda_pad_o(sda_o_f),
        .cmd      (cmd_f),
        .tx_data  (txdat_f),
        .tx_ack   (txack_f),
        .go       (go_f),
        .busy     (busy_f),
        .done     (done_f),
        .nack     (nack_f),
        .rx_data  (rxdat_f),
        .rx_valid (rxv_f),
        .err      (err_f)
    );

    logic       slv_rstn_f;
    logic       sda_pull_f, scl_pull_f;
    logic [15:0] cap_reg_f;
    logic [7:0]  cap_val_f;
    logic        cap_we_f, cap_stop_f;
    logic [15:0] cur_reg_f;

    i2c_slave_bfm u_slv_f (
        .clk      (clk_f),
        .rst_n    (rstn_f & slv_rstn_f),
        .scl      (scl_f),
        .sda      (sda_f),
        .sda_pull (sda_pull_f),
        .scl_pull (scl_pull_f),
        .nack_addr(1'b0),
        .stretch_n(32'd0),
        .stuck_scl(1'b0),
        .cap_reg  (cap_reg_f),
        .cap_val  (cap_val_f),
        .cap_we   (cap_we_f),
        .cap_stop (cap_stop_f),
        .rd_data  (8'h00),
        .cur_reg  (cur_reg_f)
    );

    assign scl_f = scl_o_f & ~scl_pull_f;
    assign sda_f = sda_o_f & ~sda_pull_f;

`ifdef DBG
    // fast 总线驱动源监视（定位假 START）
    always @(sda_o_f or sda_pull_f or scl_o_f or scl_pull_f or sda_f or scl_f)
        if ($time > 300_000)
            $display("[DBG-BUSF] t=%0t sda_o=%b spull=%b scl_o=%b cpull=%b -> sda=%b scl=%b",
                     $time, sda_o_f, sda_pull_f, scl_o_f, scl_pull_f, sda_f, scl_f);
`endif

    // SCL 半周期实测（T8）
    realtime t_rise_f = 0, t_fall_f = 0, high_w_f = 0, low_w_f = 0;
    logic    meas_en_f = 0;
    always @(posedge scl_f) begin
        if (t_fall_f != 0 && meas_en_f) low_w_f = $realtime - t_fall_f;
        t_rise_f = $realtime;
    end
    always @(negedge scl_f) begin
        if (t_rise_f != 0 && meas_en_f) high_w_f = $realtime - t_rise_f;
        t_fall_f = $realtime;
    end

    //------------------------------------------------------------------
    // 判定与驱动
    //------------------------------------------------------------------
    task automatic chk(input bit cond, input string msg);
        if (cond) $display("[TB][ ok ] %0s", msg);
        else begin
            errors++;
            $display("[TB][FAIL] %0s (t=%0t)", msg, $time);
        end
    endtask

    // 单命令驱动：go 一拍，等 done 一拍
    task automatic i2c_cmd(input logic [2:0] c,
                           input logic [7:0] d    = 8'h00,
                           input logic       tack = 1'b0);
        begin
            @(negedge clk_s);
            cmd_s <= c; txdat_s <= d; txack_s <= tack; go_s <= 1'b1;
            @(negedge clk_s);
            go_s <= 1'b0;
            wait (done_s === 1'b1);
            @(posedge clk_s);
            `ifdef DBG
            $display("[DBG] t=%0t cmd=%0d done nack=%b err=%b busy=%b scl=%b sda=%b",
                     $time, c, nack_s, err_s, busy_s, scl_s, sda_s);
            `endif
        end
    endtask

    // 寄存器写全流程（小参数 DUT）：逐字节查 nack + 捕获比对
    task automatic i2c_write_reg(input logic [15:0] reg_, input logic [7:0] val,
                                 input string tag);
        begin
            i2c_cmd(CMD_START);
            i2c_cmd(CMD_TX, 8'h34);
            chk(nack_s == 1'b0, $sformatf("%s addr ACK", tag));
            i2c_cmd(CMD_TX, reg_[15:8]);
            chk(nack_s == 1'b0, $sformatf("%s regH ACK", tag));
            i2c_cmd(CMD_TX, reg_[7:0]);
            chk(nack_s == 1'b0, $sformatf("%s regL ACK", tag));
            i2c_cmd(CMD_TX, val);
            chk(nack_s == 1'b0, $sformatf("%s val ACK", tag));
            wait (cap_we_s === 1'b1);
            @(posedge clk_s);
            chk(cap_reg_s == reg_ && cap_val_s == val,
                $sformatf("%s slave captured reg=%04x val=%02x (got %04x/%02x)",
                          tag, reg_, val, cap_reg_s, cap_val_s));
            i2c_cmd(CMD_STOP);
            repeat (5) @(posedge clk_s);
            chk(busy_s == 1'b0, $sformatf("%s busy low after STOP", tag));
        end
    endtask

    //------------------------------------------------------------------
    // 主测试序列
    //------------------------------------------------------------------
    initial begin
        $display("[TB] tb_i2c_master start");
        rstn_s     = 1'b0;
        slv_rstn_s = 1'b0;
        rstn_f     = 1'b0;
        slv_rstn_f = 1'b0;
        cmd_s = '0; txdat_s = '0; txack_s = 0; go_s = 0;
        cmd_f = '0; txdat_f = '0; txack_f = 0; go_f = 0;
        repeat (5) @(posedge clk_s);
        rstn_s     = 1'b1;
        slv_rstn_s = 1'b1;
        rstn_f     = 1'b1;
        slv_rstn_f = 1'b1;
        repeat (5) @(posedge clk_s);

        //--------------------------------------------------------------
        // T0：复位释放后空闲电平
        //--------------------------------------------------------------
        chk(scl_s === 1'b1 && sda_s === 1'b1, "T0 idle SCL=1 SDA=1 (small)");
        chk(scl_f === 1'b1 && sda_f === 1'b1, "T0 idle SCL=1 SDA=1 (fast)");

        //--------------------------------------------------------------
        // T1：寄存器写 0x301C = 0x00
        //--------------------------------------------------------------
        i2c_write_reg(16'h301C, 8'h00, "T1");

        //--------------------------------------------------------------
        // T2：寄存器写 0x3024 = 0xCA
        //--------------------------------------------------------------
        i2c_write_reg(16'h3024, 8'hCA, "T2");

        //--------------------------------------------------------------
        // T3：读 + 重复 START（cur_reg=0x301C -> expect 0x5A）
        //--------------------------------------------------------------
        i2c_cmd(CMD_START);
        i2c_cmd(CMD_TX, 8'h34);
        chk(nack_s == 1'b0, "T3 addr-W ACK");
        i2c_cmd(CMD_TX, 8'h30);
        i2c_cmd(CMD_TX, 8'h1C);
        i2c_cmd(CMD_START);                    // 重复 START
        i2c_cmd(CMD_TX, 8'h35);
        chk(nack_s == 1'b0, "T3 addr-R ACK (repeated START)");
        i2c_cmd(CMD_RX, 8'h00, 1'b0);          // 读 1 字节，回 ACK
        chk(rxv_s == 1'b1, "T3 rx_valid");
        chk(rxdat_s == 8'h5A,
            $sformatf("T3 rx_data=0x%02x (expect 0x5A)", rxdat_s));
        i2c_cmd(CMD_RX, 8'h00, 1'b1);          // 最后一字节回 NACK
        i2c_cmd(CMD_STOP);

        //--------------------------------------------------------------
        // T4：地址 NACK 捕获
        //--------------------------------------------------------------
        nack_addr_s = 1'b1;
        i2c_cmd(CMD_START);
        i2c_cmd(CMD_TX, 8'h34);
        chk(nack_s == 1'b1, "T4 addr NACK captured");
        i2c_cmd(CMD_STOP);
        nack_addr_s = 1'b0;

        //--------------------------------------------------------------
        // T5：时钟拉伸（20 clk < 看门狗 60）
        //--------------------------------------------------------------
        stretch_s = 32'd20;
        i2c_write_reg(16'h301C, 8'hA5, "T5");
        stretch_s = 32'd0;

        //--------------------------------------------------------------
        // T6：SCL 卡死 -> 看门狗 err；CMD_RESET 清 err
        //--------------------------------------------------------------
        begin
            realtime t0, dt;
            stuck_scl_s = 1'b1;
            @(negedge clk_s);
            cmd_s <= CMD_TX; txdat_s <= 8'h34; txack_s <= 0; go_s <= 1'b1;
            @(negedge clk_s);
            go_s <= 1'b0;
            t0 = $realtime;
            wait (done_s === 1'b1);
            dt = $realtime - t0;
            @(posedge clk_s);
            chk(err_s == 1'b1, "T6 watchdog err set");
            chk(dt < 10_000ns,
                $sformatf("T6 abort latency %0t < 10us", dt));
            stuck_scl_s = 1'b0;
            slv_rstn_s  = 1'b0;                // BFM 从卡死态复位
            repeat (3) @(posedge clk_s);
            slv_rstn_s = 1'b1;
            chk(scl_s === 1'b1 && sda_s === 1'b1, "T6 bus released after abort");
            i2c_cmd(CMD_RESET);
            chk(err_s == 1'b0, "T6 CMD_RESET cleared err");
        end

        //--------------------------------------------------------------
        // T7：err 事后新事务正常
        //--------------------------------------------------------------
        i2c_write_reg(16'h3024, 8'hCA, "T7");

        //--------------------------------------------------------------
        // T8：实参数冒烟（200M/50k）：SCL 半周期 ≈10us + 完整写
        // （go 脉冲必须 negedge 锚定——posedge 后直发只覆盖半拍，
        //   master 采样不到 go，会永远停在 ST_HOLD）
        //--------------------------------------------------------------
        begin
            i2c_cmd_f(CMD_START);
            meas_en_f = 1'b1;
            i2c_cmd_f(CMD_TX, 8'h34);          // 在这个字节内测 SCL 宽度
            meas_en_f = 1'b0;
            chk(high_w_f > 8_000ns && high_w_f < 12_000ns,
                $sformatf("T8 SCL high %0t ns (expect ~10000)", high_w_f));
            chk(low_w_f  > 8_000ns && low_w_f  < 12_000ns,
                $sformatf("T8 SCL low  %0t ns (expect ~10000)", low_w_f));
            // 收尾该事务并完成一次完整写
            i2c_cmd_f_stop_then_write();
        end

        //--------------------------------------------------------------
        // 结论
        //--------------------------------------------------------------
        $display("TB_I2C_MASTER: %s errors=%0d",
                 (errors == 0) ? "PASS" : "FAIL", errors);
        $finish;
    end

    // T8 收尾：STOP 掉 T8 半程事务，再做一次完整写（fast DUT）
    task automatic i2c_cmd_f(input logic [2:0] c, input logic [7:0] d = 8'h00);
        begin
            @(negedge clk_f);
            cmd_f <= c; txdat_f <= d; go_f <= 1'b1;
            @(negedge clk_f);
            go_f <= 1'b0;
            wait (done_f === 1'b1);
            @(posedge clk_f);
`ifdef DBG
            $display("[DBG-F] t=%0t cmd=%0d done nack=%b scl=%b sda=%b",
                     $time, c, nack_f, scl_f, sda_f);
`endif
        end
    endtask

    task automatic i2c_cmd_f_stop_then_write();
        begin
            i2c_cmd_f(CMD_STOP);
            repeat (5) @(posedge clk_f);
            i2c_cmd_f(CMD_START);
            i2c_cmd_f(CMD_TX, 8'h34);
            chk(nack_f == 1'b0, "T8 fast addr ACK");
            i2c_cmd_f(CMD_TX, 8'h30);
            i2c_cmd_f(CMD_TX, 8'h1C);
            i2c_cmd_f(CMD_TX, 8'h5A);
            wait (cap_we_f === 1'b1);
            @(posedge clk_f);
            chk(cap_reg_f == 16'h301C && cap_val_f == 8'h5A,
                $sformatf("T8 fast captured reg=%04x val=%02x",
                          cap_reg_f, cap_val_f));
            i2c_cmd_f(CMD_STOP);
            repeat (5) @(posedge clk_f);
        end
    endtask

    //------------------------------------------------------------------
    // 全局看门狗
    //------------------------------------------------------------------
    initial begin
        #20_000_000;                           // 20 ms 绝对窗
        $display("[TB][FATAL] global timeout");
        $display("TB_I2C_MASTER: FAIL errors=%0d (timeout)", errors + 1);
        $finish;
    end

`ifdef DUMP
    initial begin
        $dumpfile("tb_i2c_master.vcd");
        $dumpvars(0, tb_i2c_master);
    end
`endif

endmodule

// i2c_slave_bfm 已拆出至 sim/i2c_slave_bfm.sv（多 TB 复用），
// 本 TB 的用例判定不依赖 cap_list 队列，仍走 cap_we 单拍比对。
