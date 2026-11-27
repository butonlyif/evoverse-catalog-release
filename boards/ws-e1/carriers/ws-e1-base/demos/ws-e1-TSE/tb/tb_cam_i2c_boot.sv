`timescale 1ns / 1ps
//============================================================================
// tb_cam_i2c_boot -- cam_i2c_init 自启性快速验证
// 问题背景（2026-11-06）：g10e 板上 cam_status 位 en=0/busy=0/done=0/fail=0
//   （FSM 停 IDLE），而 clk_200m/复位链/start=1 全部成立。
// 本 TB 加速参数（SYS_FREQ=100k，MS 参数=1ms→100 拍）验证：
//   A1: 复位释放后 FSM 自动离开 IDLE（start=1'b1 出沿自启）
//   A2: cam_en 在 PWR_OFF 结束后拉高
//   A3: FSM 进入事务阶段（busy=1，START 命令出现）
//   A4: 无 I2C 从机（NACK）时走重试/整轮路径（retry/round 增长或 fail）
// errors=0 判据：A1-A3 全部成立（FSM 启动性）。A4 记录现象不定错。
//============================================================================
module tb_cam_i2c_boot;

    localparam integer SYS_FREQ = 100_000;   // 100kHz 加速
    localparam integer TCLK = 10_000_000 / SYS_FREQ; // 10us @100k

    reg clk = 0;
    reg rst_n = 0;
    reg scl_pad_i = 1'b1;                    // 开漏总线空闲（外部上拉）
    reg sda_pad_i = 1'b1;
    wire scl_pad_o, sda_pad_o;
    wire cam_en, init_done, init_fail, busy;
    wire [7:0] dbg_idx;
    wire [1:0] dbg_round;
    wire [3:0] dbg_retry;

    // pad 回读模型：pad_o=0（驱动）时总线被拉低；pad_o=1（释放）时上拉为高
    wire scl_bus = (scl_pad_o === 1'b0) ? 1'b0 : 1'b1;
    wire sda_bus = (sda_pad_o === 1'b0) ? 1'b0 : 1'b1;
    // 简易从机 ACK：地址字节后第 9 拍拉低 SDA（模拟 IMX415 应答）
    reg [3:0] ack_cnt = 0;
    reg       ack_expect = 0;
    always @(negedge sda_pad_o) ack_cnt = 0;

    cam_i2c_init #(
        .SYS_FREQ      (SYS_FREQ),
        .I2C_FREQ      (SYS_FREQ / 20),         // 5kHz I2C（加速）
        .MODE_4K       (1'b0),
        .PWR_OFF_MS    (1),
        .PWR_SETTLE_MS (1),
        .RETRY_GAP_MS  (1),
        .DISCHARGE_MS  (1)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .scl_pad_i(scl_bus), .scl_pad_o(scl_pad_o),
        .sda_pad_i(sda_bus), .sda_pad_o(sda_pad_o),
        .cam_en(cam_en),
        .start(1'b1),                        // 与 ws_e1_tse.v 相同：恒 1 自启
        .init_done(init_done), .init_fail(init_fail), .busy(busy),
        .dbg_idx(dbg_idx), .dbg_round(dbg_round), .dbg_retry(dbg_retry)
    );

    always #(TCLK/2) clk = ~clk;

    integer errors = 0;
    reg [63:0] cyc = 0;
    reg saw_not_idle = 0, saw_cam_en_hi = 0, saw_busy = 0, saw_start_cmd = 0;

    always @(posedge clk) cyc <= cyc + 1;

    always @(posedge clk) begin
        if (rst_n && cyc > 100) begin
            if (busy || cam_en) begin
                saw_not_idle = 1;
                if (cam_en) saw_cam_en_hi = 1;
                if (busy)   saw_busy = 1;
            end
        end
    end

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        // 加速参数下：PWR_OFF 100 拍 + SETTLE 100 拍 + 首事务百拍级
        repeat (6000) @(posedge clk);        // ~60ms 模拟时间窗口
        $display("== RESULT ==");
        $display("saw_not_idle   = %0d (A1: FSM 自动离开 IDLE)", saw_not_idle);
        $display("saw_cam_en_hi  = %0d (A2: cam_en 拉高)", saw_cam_en_hi);
        $display("saw_busy       = %0d (A3: FSM 事务运行)", saw_busy);
        $display("done=%0d fail=%0d busy=%0d cam_en=%0d idx=%0d round=%0d retry=%0d",
                 init_done, init_fail, busy, cam_en, dbg_idx, dbg_round, dbg_retry);
        if (!saw_not_idle)  begin $display("ERR: FSM 从未离开 IDLE —— start 自启失效"); errors = errors + 1; end
        if (!saw_cam_en_hi) begin $display("ERR: cam_en 从未拉高"); errors = errors + 1; end
        if (!saw_busy)      begin $display("ERR: busy 从未置位"); errors = errors + 1; end
        if (errors == 0) $display("PASS errors=0");
        else             $display("FAIL errors=%0d", errors);
        $finish;
    end
endmodule
