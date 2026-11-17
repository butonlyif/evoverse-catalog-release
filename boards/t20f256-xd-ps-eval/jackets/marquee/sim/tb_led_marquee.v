`timescale 1ns / 1ps
//============================================================================
// 模块名称: tb_led_marquee
// 功能描述: t20f256_xd_ps_eval_marquee 协议性质自检 testbench（对齐无关）
//           不假设首个 step_tick 的绝对相位；以 dut.u_marquee.rst_n 同步
//           释放为采样起点，在每个 negedge 采样一次：
//           PROP-RESET  首个采样 = one-hot bit0（复位值）
//           PROP-ONEHOT 每个采样恰 1 位点亮
//           PROP-ROTATE 值变化必为循环左移一位（含 bit9→bit0 回绕）
//           PROP-HOLD   相邻变化间隔恰 STEP_CYCLES 个采样
//============================================================================
module tb_led_marquee;
    localparam integer LEDS        = 10;
    localparam integer STEP_CYCLES = 4;
    localparam integer CHECKS      = 30 * STEP_CYCLES;   // ≈3 圈完整旋转

    reg        clk    = 1'b0;
    reg        arst_n = 1'b0;
    wire [9:0] led;

    t20f256_xd_ps_eval_marquee #(
        .STEP_CYCLES (STEP_CYCLES)
    ) dut (
        .clk_50m_i (clk),
        .arst_n_i  (arst_n),
        .led_o     (led)
    );

    // 50 MHz 时钟（20 ns 周期）
    always #10 clk = ~clk;

    function integer count_ones(input [9:0] v);
        integer k;
        begin
            count_ones = 0;
            for (k = 0; k < LEDS; k = k + 1)
                if (v[k]) count_ones = count_ones + 1;
        end
    endfunction

    integer   errors   = 0;
    integer   checks   = 0;
    integer   rotates  = 0;
    integer   hold_cnt = 0;
    reg [9:0] cur;
    reg [9:0] prev;

    initial begin
        arst_n = 1'b0;
        repeat (5) @(posedge clk);
        arst_n = 1'b1;    // 异步释放；DUT 内部 3 级同步释放
    end

    // rst_n 同步释放完成后的每个 negedge 采样（对齐无关，无固定偏移假设）
    always @(negedge clk) begin
        if (dut.u_marquee.rst_n === 1'b1 && checks < CHECKS) begin
            checks = checks + 1;
            cur    = led;
            if (checks == 1) begin
                hold_cnt = 1;
                // PROP-RESET: 复位释放后首个采样 = bit0
                if (cur !== 10'h001) begin
                    errors = errors + 1;
                    $display("FAIL PROP-RESET sample=1 led=%b exp=0000000001", cur);
                end
            end else if (cur === prev) begin
                hold_cnt = hold_cnt + 1;
            end else begin
                rotates = rotates + 1;
                // PROP-ROTATE: 循环左移一位
                if (cur !== {prev[LEDS-2:0], prev[LEDS-1]}) begin
                    errors = errors + 1;
                    $display("FAIL PROP-ROTATE rotate=%0d prev=%b cur=%b",
                             rotates, prev, cur);
                end
                // PROP-HOLD: 上一值持续恰 STEP_CYCLES 个采样
                if (hold_cnt !== STEP_CYCLES) begin
                    errors = errors + 1;
                    $display("FAIL PROP-HOLD rotate=%0d hold=%0d exp=%0d",
                             rotates, hold_cnt, STEP_CYCLES);
                end
                hold_cnt = 1;
            end
            // PROP-ONEHOT: 恰 1 位点亮
            if (count_ones(cur) !== 1) begin
                errors = errors + 1;
                $display("FAIL PROP-ONEHOT sample=%0d led=%b", checks, cur);
            end
            prev = cur;

            if (checks == CHECKS) begin
                if (errors == 0 && rotates >= LEDS)
                    $display("TB-RESULT: PASS (%0d samples, %0d rotations, %0d errors)",
                             checks, rotates, errors);
                else if (errors == 0)
                    $display("TB-RESULT: FAIL (insufficient rotations: %0d)", rotates);
                else
                    $display("TB-RESULT: FAIL (%0d errors / %0d checks)",
                             errors, checks);
                $finish;
            end
        end
    end
endmodule
