`timescale 1ns/1ps
//==============================================================================
// cam_i2c_init.sv -- IMX415 上电初始化控制器（cam-i2c-rtl-init-plan §4.1/§4.4）
//
// 目标：下载 bit 后无需固件，RTL 自动完成 IMX415 的 I2C 配置，配置完成后
//       init_done=1 放行数据路径（top_cam 的 gate_ready / raw_aresetn 用）。
//
// 序列（同源自 sw/top_demo/src/imx415_init.c，经 tools/gen_imx415_rom.py
//       生成 rtl/imx415_rom.sv，共 142 条写事务）：
//   1. cam_en 低 PWR_OFF_MS  （硬复位：清导轨/半配置态；cam0~300ms）
//   2. cam_en 高 + SETTLE_MS （模块上电稳定；~12ms）
//   3. 逐条目走 ROM：START + 0x34 + {regH, regL, val} + STOP（7bit 0x1A）
//      每条目 NACK/err 重试 RETRY_MAX 次、间隔 RETRY_GAP_MS（固件 10 次/10ms）
//   4. 条目重试耗尽 -> cam_en 放电 DISCHARGE_MS 后整轮重来（固件 500ms/3 轮）
//   5. 全表完成 -> init_done=1（保持）；ROUND_MAX 轮全败 -> init_fail=1（sticky）
//
// 复用约定：
//   - 内嵌 rtl/i2c_master.sv（P1 已验证；开漏约定 pad_o=1 释放）
//   - err/NACK 统一走 CMD_RESET 归位（i2c_master 的 CMD_RESET 同时清 err
//     与释放 pad，等价于固件的 applyConfig+recover+stop 复活路径）
//   - 无读回校验（评审 Q3）；无 START_DROPPED 检测，伪 START 依赖地址
//     NACK + 重试兜底（计划 §7 风险）
//   - 错峰：cam1 的 start 接 cam0 的 init_done（电平）
//   - rerun：start 重新触发即全序列重跑（cam_en 重新走硬复位时序）
//
// 时序常数：CYC = (SYS_FREQ/1000) * MS，200MHz 下最大 DISCHARGE=1e8，32bit 无溢出。
//==============================================================================
module cam_i2c_init #(
    parameter int SYS_FREQ      = 200_000_000,
    parameter int I2C_FREQ      = 50_000,    // 板级飞线结论 50kHz（P1 实证）
    parameter bit MODE_4K       = 1'b1,      // 1=cam0 4K60 / 0=cam1 1080p60（透传 ROM）
    parameter int PWR_OFF_MS    = 300,
    parameter int PWR_SETTLE_MS = 12,
    parameter int RETRY_GAP_MS  = 10,
    parameter int DISCHARGE_MS  = 500,
    parameter int RETRY_MAX     = 10,        // 每条目写尝试次数（含首次，同固件）
    parameter int ROUND_MAX     = 3          // 整轮尝试次数（同固件）
) (
    input  logic       clk,
    input  logic       rst_n,

    // I2C 开漏 pad（pad_o=1 释放；顶层做 oe=~o 的开漏映射）
    input  logic       scl_pad_i,
    output logic       scl_pad_o,
    input  logic       sda_pad_i,
    output logic       sda_pad_o,

    // 摄像头电源/使能（1=上电；本路 cam_en 独立驱动）
    output logic       cam_en,

    // 控制 / 状态
    input  logic       start,        // 上升沿触发一次完整初始化（运行中忽略；
                                     //  错峰接法：cam1.start = cam0.init_done）
    output logic       init_done,    // 1=配置完成，放行数据路径（保持至下次 start）
    output logic       init_fail,    // 1=ROUND_MAX 轮全败（sticky 至下次 start）
    output logic       busy,         // 初始化进行中

    // 观测（APB debug / TB）
    output logic [7:0] dbg_idx,
    output logic [1:0] dbg_round,
    output logic [3:0] dbg_retry
);

    localparam int CYC_PWR_OFF   = (SYS_FREQ / 1000) * PWR_OFF_MS;
    localparam int CYC_SETTLE    = (SYS_FREQ / 1000) * PWR_SETTLE_MS;
    localparam int CYC_RETRY_GAP = (SYS_FREQ / 1000) * RETRY_GAP_MS;
    localparam int CYC_DISCHARGE = (SYS_FREQ / 1000) * DISCHARGE_MS;

    // 与 rtl/i2c_master.sv 一致的命令编码
    localparam logic [2:0] CMD_START = 3'd1, CMD_TX = 3'd2,
                           CMD_STOP  = 3'd4, CMD_RESET = 3'd5;

    initial begin
        if (CYC_PWR_OFF < 1 || CYC_SETTLE < 1 || CYC_RETRY_GAP < 1 ||
            CYC_DISCHARGE < 1)
            $fatal(1, "%m: MS 参数过小（CYC=0），SYS_FREQ=%0d", SYS_FREQ);
        // i2c_master 要求 T_SCL>=2（否则 CNT_W=$clog2(1)=0，[CNT_W-1:0] 反向，
        // vopt-3373 elaboration 失败）
        if (SYS_FREQ / I2C_FREQ < 2)
            $fatal(1, "%m: SYS_FREQ/I2C_FREQ=%0d < 2", SYS_FREQ / I2C_FREQ);
    end

    //------------------------------------------------------------------
    // FSM
    //------------------------------------------------------------------
    typedef enum logic [4:0] {
        ST_IDLE,        // 等 start（init_done/fail 后回此态并保持结果）
        ST_PWR_OFF,     // cam_en 低（硬复位）
        ST_SETTLE,      // cam_en 高，上电稳定
        ST_LOAD,        // 取 ROM 条目，装载字节流
        ST_START_I,     // 发 START
        ST_START_W,
        ST_TX_I,        // 发字节 bytebuf[31:24]
        ST_TX_W,
        ST_STOP_I,      // 发 STOP
        ST_STOP_W,
        ST_NEXT,        // 条目成功：idx++ / 表尾判定
        ST_RST_I,       // CMD_RESET（NACK/err 归位：清 err + 释放 pad）
        ST_RST_W,
        ST_RETRY_GAP,   // 条目重试间隔；重试耗尽 -> 整轮失败处理
        ST_DISCHARGE,   // cam_en 放电，整轮重试
        ST_DONE,        // init_done=1
        ST_FAIL         // init_fail=1
    } state_e;

    state_e      st;
    logic        go;
    logic [2:0]  cmd;
    logic [7:0]  tx_data;
    logic        m_busy, m_done, m_nack, m_err;
    logic [7:0]  rom_idx;
    logic [7:0]  rom_last;
    logic [23:0] rom_data;
    logic [31:0] bytebuf;      // {0x34, regH, regL, val}，左移出字节
    logic [1:0]  byten;
    int unsigned gap_cnt;
    int unsigned retry;        // 当前条目已失败次数
    int unsigned round;        // 已失败整轮数

    // start 上升沿检测（完成回 IDLE 后不被残留电平重复触发）
    // 组合出沿（2026-11-06）：原时序版 start_pe <= start & ~start_q 在 start=1'b1
    // 常数下被 Efinity 综合器常量传播判恒 0（忽略复位初值瞬态）→ FSM 收不到
    // 启动 → 整个 cam_i2c_init 被综合删除（g10e 板上 en/busy/done/fail 全 0 的
    // 根因）。组合版依赖时序 FF 输出 start_q，综合器无法传播；且复位释放
    // 第一拍 pe=1（start_q 尚为复位值 0），自启更快。
    logic start_q;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) start_q <= 1'b0;
        else        start_q <= start;
    logic start_pe;
    assign start_pe = start & ~start_q;

    imx415_rom #(
        .MODE_4K(MODE_4K)
    ) u_rom (
        .idx     (rom_idx),
        .data    (rom_data),
        .last_idx(rom_last)
    );

    i2c_master #(
        .SYS_FREQ(SYS_FREQ),
        .I2C_FREQ(I2C_FREQ)
    ) u_i2cm (
        .clk      (clk),
        .rst_n    (rst_n),
        .scl_pad_i(scl_pad_i),
        .scl_pad_o(scl_pad_o),
        .sda_pad_i(sda_pad_i),
        .sda_pad_o(sda_pad_o),
        .cmd      (cmd),
        .tx_data  (tx_data),
        .tx_ack   (1'b0),          // master 不代从机应答，ACK 由 nack 报告
        .go       (go),
        .busy     (m_busy),
        .done     (m_done),
        .nack     (m_nack),
        .rx_data  (),
        .rx_valid (),
        .err      (m_err)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st       <= ST_IDLE;
            cam_en   <= 1'b0;
            init_done <= 1'b0;
            init_fail <= 1'b0;
            go       <= 1'b0;
            cmd      <= '0;
            tx_data  <= '0;
            rom_idx  <= '0;
            bytebuf  <= '0;
            byten    <= '0;
            gap_cnt  <= 0;
            retry    <= 0;
            round    <= 0;
        end else begin
            go <= 1'b0;                       // go 单拍（寄存器输出天然整拍）
            case (st)
                //--------------------------------------------------
                ST_IDLE: begin
                    // 未启动/失败后保持断电；完成后保持 cam_en=1（sensor 续流）
                    if (!init_done && !init_fail)
                        cam_en <= 1'b0;
                    if (start_pe) begin
                        init_done <= 1'b0;
                        init_fail <= 1'b0;
                        retry     <= 0;
                        round     <= 0;
                        rom_idx   <= '0;
                        gap_cnt   <= 0;
                        st        <= ST_PWR_OFF;
                    end
                end
                //--------------------------------------------------
                // 电源时序（错峰入口：cam1 由 cam0 init_done 触发 start）
                //--------------------------------------------------
                ST_PWR_OFF: begin
                    cam_en  <= 1'b0;
                    gap_cnt <= gap_cnt + 1'b1;
                    if (gap_cnt >= CYC_PWR_OFF - 1) begin
                        gap_cnt <= 0;
                        cam_en  <= 1'b1;
                        st      <= ST_SETTLE;
                    end
                end
                ST_SETTLE: begin
                    gap_cnt <= gap_cnt + 1'b1;
                    if (gap_cnt >= CYC_SETTLE - 1) begin
                        gap_cnt <= 0;
                        st      <= ST_LOAD;
                    end
                end
                //--------------------------------------------------
                // 条目事务：START + 4 字节 + STOP
                //--------------------------------------------------
                ST_LOAD: begin
                    bytebuf <= {8'h34, rom_data};  // {addrW, regH, regL, val}
                    byten   <= 2'd0;
                    st      <= ST_START_I;
                end
                ST_START_I: begin
                    go  <= 1'b1;
                    cmd <= CMD_START;
                    st  <= ST_START_W;
                end
                ST_START_W: begin
                    if (m_done) begin
                        if (m_err) begin
                            retry <= retry + 1'b1;
                            st    <= ST_RST_I;
                        end else begin
                            st <= ST_TX_I;
                        end
                    end
                end
                ST_TX_I: begin
                    go      <= 1'b1;
                    cmd     <= CMD_TX;
                    tx_data <= bytebuf[31:24];
                    st      <= ST_TX_W;
                end
                ST_TX_W: begin
                    if (m_done) begin
                        if (m_nack || m_err) begin
                            retry <= retry + 1'b1;
                            st    <= ST_RST_I;
                        end else if (byten == 2'd3) begin
                            st <= ST_STOP_I;
                        end else begin
                            byten   <= byten + 1'b1;
                            bytebuf <= {bytebuf[23:0], 8'h00};
                            st      <= ST_TX_I;
                        end
                    end
                end
                ST_STOP_I: begin
                    go  <= 1'b1;
                    cmd <= CMD_STOP;
                    st  <= ST_STOP_W;
                end
                ST_STOP_W: begin
                    if (m_done) begin
                        if (m_err) begin
                            retry <= retry + 1'b1;
                            st    <= ST_RST_I;
                        end else begin
                            st <= ST_NEXT;
                        end
                    end
                end
                //--------------------------------------------------
                ST_NEXT: begin
                    retry <= 0;
                    if (rom_idx == rom_last) begin
                        st <= ST_DONE;
                    end else begin
                        rom_idx <= rom_idx + 1'b1;
                        st      <= ST_LOAD;
                    end
                end
                //--------------------------------------------------
                // NACK/err 恢复：CMD_RESET 归位 -> 间隔 -> 重发/弃条
                //--------------------------------------------------
                ST_RST_I: begin
                    go  <= 1'b1;
                    cmd <= CMD_RESET;
                    st  <= ST_RST_W;
                end
                ST_RST_W: begin
                    if (m_done)
                        st <= ST_RETRY_GAP;
                end
                ST_RETRY_GAP: begin
                    gap_cnt <= gap_cnt + 1'b1;
                    if (gap_cnt >= CYC_RETRY_GAP - 1) begin
                        gap_cnt <= 0;
                        if (retry >= RETRY_MAX) begin
                            round <= round + 1'b1;
                            st    <= (round + 1 >= ROUND_MAX) ? ST_FAIL
                                                              : ST_DISCHARGE;
                        end else begin
                            st <= ST_LOAD;        // 重发当前条目
                        end
                    end
                end
                ST_DISCHARGE: begin
                    cam_en  <= 1'b0;
                    gap_cnt <= gap_cnt + 1'b1;
                    if (gap_cnt >= CYC_DISCHARGE - 1) begin
                        gap_cnt <= 0;
                        rom_idx <= '0;
                        retry   <= 0;             // 新轮从满重试起步（板级教训：
                                                  // 不清则第 2/3 轮首次失败即弃）
                        st      <= ST_PWR_OFF;    // 重走硬复位时序
                    end
                end
                //--------------------------------------------------
                ST_DONE: begin
                    init_done <= 1'b1;
                    st        <= ST_IDLE;
                end
                ST_FAIL: begin
                    init_fail <= 1'b1;
                    st        <= ST_IDLE;
                end
                default: st <= ST_IDLE;
            endcase
        end
    end

    assign busy      = (st != ST_IDLE);
    assign dbg_idx   = rom_idx;
    assign dbg_round = round[1:0];
    assign dbg_retry = retry[3:0];

    // 防呆：条目索引不得越过 ROM 表尾
    no_idx_overrun: assert property (
        @(posedge clk) disable iff (!rst_n)
        (st == ST_NEXT) |-> (rom_idx <= rom_last)
    ) else $error("%m: rom_idx %0d 越过表尾 %0d", rom_idx, rom_last);

endmodule
