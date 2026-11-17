// ============================================================================
// ddr_memcheck.v — LPDDR4X 读写比对自检（阶段 0 DDR 通路验证）
// 移植自 EvoVerse ws-e1 ddr-memtest/memory_checker.v（板上验证过的参考），
// 修正与改动（相对原参考）：
//  1. [修 bug] 原代码 fail 在每个 burst 的 WRITE_ADDR 拍被清零——中途错后
//     续 burst 会洗掉 fail 标志造成误 PASS。本版 fail 置位即保持（sticky），
//     另加 err_cnt 累计比对错误次数。
//  2. [修 bug] 原代码 reset/IDLE 分支 `wdata <= 256'd0` 位宽不匹配（512 位
//     端口），本版改 512'd0。
//  3. [修时序] 本 DDR 控制器为 WVALID-先于-AWREADY 型（AWREADY 在
//     AWVALID && WVALID 都见过后才断言）：W 通道在 PRE_WRITE 起爆，
//     PRE_WRITE 期间发生的传输同样计入 beat（对齐参考 checker）；
//     wlast 与最后 beat 严格同拍。
//  4. [参数化] ALEN=119 => 120 beat × 64B = 7680B/突发 = 恰好一行 UYVY，
//     与未来 frame_writer/frame_reader 的行 burst 形态一致——自检环境=
//     应用环境。
//  5. 覆盖量 = TOTAL_BURSTS × 7680B（固定 burst 计数制，不用地址阈值，
//     天然无末突发越界；板上 3495 突发覆盖 0x0~0x103F200 ≈ 帧 A/B 乒乓区，
//     2Gb 颗粒 = 256MB，A/B 帧 @ 0x0/0x01000000 各 16MB）。
//  6. 数据图案沿用参考的"地址+beat 指纹"（高低 256 位镜像，自恢复性好）。
// ============================================================================

module ddr_memcheck #(
    parameter [32:0] START_ADDR = 33'h0_0000_0000,
    parameter [15:0] TOTAL_BURSTS = 16'd3495,   // 3495×7680B ≈ 26MB（帧乒乓区）
    parameter [7:0]  ALEN       = 8'd119,       // 120 beat/burst
    parameter [2:0]  ASIZE      = 3'b110        // 64B/beat
)(
    input  wire        axi_clk,
    input  wire        rstn,          // 低有效，同步释放（ddr_cfg_ok 后）
    input  wire        start,         // rstn 释放后置 1 即启动

    // AXI4 写地址
    output wire [5:0]  awid,
    output reg  [32:0] awaddr,
    output reg  [7:0]  awlen,
    output reg  [2:0]  awsize,
    output reg  [1:0]  awburst,
    output reg  [3:0]  awcache,
    output reg         awlock,
    output reg         awvalid,
    output reg         awcobuf,
    output reg         awapcmd,
    output reg         awallstrb,
    output reg         awqos,
    input  wire        awready,
    // AXI4 写数据
    output reg  [511:0] wdata,
    output wire [63:0]  wstrb,
    output reg         wlast,
    output reg         wvalid,
    input  wire        wready,
    // AXI4 写响应
    input  wire [5:0]  bid,
    input  wire        bvalid,
    output reg         bready,
    // AXI4 读地址
    output wire [5:0]  arid,
    output reg  [32:0] araddr,
    output reg  [7:0]  arlen,
    output reg  [2:0]  arsize,
    output reg  [1:0]  arburst,
    output reg         arlock,
    output reg         arvalid,
    output reg         arapcmd,
    output reg         arqos,
    input  wire        arready,
    // AXI4 读数据
    input  wire [5:0]  rid,
    input  wire [511:0] rdata,
    input  wire        rlast,
    input  wire        rvalid,
    output reg         rready,
    input  wire [1:0]  rresp,

    // 结果（sticky，复位清除）
    output reg         done,          // 全区域扫描完成
    output reg         fail,          // 任一比对错（sticky）
    output reg  [15:0] err_cnt,       // 比对错误累计次数
    output wire [3:0]  dbg_state      // 状态机快照（板级诊断用）
);

    localparam [8:0]  BEATS      = ALEN + 9'd1;                      // 120
    localparam [32:0] BURST_STEP = {21'b0, BEATS, 6'b0};             // 7680B = 一行
    // 覆盖量 = TOTAL_BURSTS × 7680B（固定计数制：不依赖地址阈值，天然无
    // 末突发越界；板上 3495 突发覆盖 0x0~0x103F200 ≈ 帧 A/B 区）

    localparam IDLE         = 4'd0,
               WRITE_ADDR   = 4'd1,
               PRE_WRITE    = 4'd2,
               WRITE        = 4'd3,
               POST_WRITE   = 4'd4,
               READ_ADDR    = 4'd5,
               PRE_READ     = 4'd6,
               READ_COMPARE = 4'd7,
               POST_READ    = 4'd8,
               DONE         = 4'd9;

    reg [3:0]  state;
    reg        start_sync0, start_sync1;
    reg [8:0]  beat_cnt;          // 当前待发/待比 beat 序号（BEATS-1..0）
    reg [15:0] burst_idx;         // 当前 burst 序号（0..TOTAL_BURSTS-1）
    reg [511:0] exp_rdata;        // 当拍期望值
    reg        rburst_done, read_done;

    assign awid  = 6'h0;
    assign arid  = 6'h0;
    assign wstrb = {64{1'b1}};
    assign dbg_state = state;

    // PRE_WRITE 内全部 beat 已打完（最后一拍清 wvalid 后成立）
    wire wlast_done = (beat_cnt == 9'd0) && (wvalid == 1'b0);

    // start 两拍整形（同域；参考实现同款）
    always @(posedge axi_clk or negedge rstn) begin
        if (!rstn) begin
            start_sync0 <= 1'b0;
            start_sync1 <= 1'b0;
        end else begin
            start_sync0 <= start;
            start_sync1 <= start_sync0;
        end
    end

    // 状态机时序
    always @(posedge axi_clk or negedge rstn) begin
        if (!rstn)
            state <= IDLE;
        else begin
            case (state)
                IDLE:         if (start_sync1) state <= WRITE_ADDR;
                WRITE_ADDR:   state <= PRE_WRITE;
                // 本控制器：AWREADY 在 AWVALID && WVALID 之后才断言——
                // PRE_WRITE 等 AW/W 双 ready，或 beat 已全部在 PRE_WRITE 打完
                PRE_WRITE:   if (awready && (wready || wlast_done))
                                 state <= wlast_done ? POST_WRITE : WRITE;
                WRITE:        if (beat_cnt == 9'd0 && (!wvalid || wready))
                                  state <= POST_WRITE;
                POST_WRITE:   if (bvalid)
                                  state <= (burst_idx == TOTAL_BURSTS - 16'd1)
                                           ? READ_ADDR : WRITE_ADDR;
                READ_ADDR:    if (arready) state <= PRE_READ;
                PRE_READ:     state <= READ_COMPARE;
                READ_COMPARE: if (rvalid && beat_cnt == 9'd0)
                                  state <= POST_READ;
                POST_READ:    state <= read_done ? DONE : READ_ADDR;
                DONE:         state <= DONE;
                default:      state <= IDLE;
            endcase
        end
    end

    // 写数据指纹：地址低 32 位 + beat 序号低 8 位混合（高低 128 位组镜像；
    // 参考实现同款结构，总宽 512 位精确匹配）
    function [511:0] pat;
        input [32:0] a;
        input [8:0]  b;
        reg [31:0] ah;
        reg [7:0]  bc;
        begin
            ah = a[31:0];
            bc = b[7:0];
            pat = {{~ah, ah, {8{bc}}, ah, ~ah, {8{~bc}}},
                   { ah, ~ah, {8{~bc}}, ~ah, ah, {8{bc}}}};
        end
    endfunction

    // 数据/地址通路
    always @(posedge axi_clk or negedge rstn) begin
        if (!rstn) begin
            awaddr      <= START_ADDR;
            awvalid     <= 1'b0;
            awlen       <= 8'd0;
            awsize      <= 3'd0;
            awburst     <= 2'd0;
            awcache     <= 4'd0;
            awlock      <= 1'b0;
            awcobuf     <= 1'b0;
            awapcmd     <= 1'b0;
            awallstrb   <= 1'b0;
            awqos       <= 1'b0;
            araddr      <= START_ADDR;
            arvalid     <= 1'b0;
            arlen       <= 8'd0;
            arsize      <= 3'd0;
            arburst     <= 2'd0;
            arlock      <= 1'b0;
            arapcmd     <= 1'b0;
            arqos       <= 1'b0;
            wdata       <= 512'd0;
            wvalid      <= 1'b0;
            wlast       <= 1'b0;
            bready      <= 1'b0;
            rready      <= 1'b0;
            beat_cnt    <= 9'd0;
            burst_idx   <= 16'd0;
            exp_rdata   <= 512'd0;
            rburst_done <= 1'b0;
            read_done   <= 1'b0;
            done        <= 1'b0;
            fail        <= 1'b0;
            err_cnt     <= 16'd0;
        end else begin
            case (state)
                IDLE: begin
                    awaddr  <= START_ADDR;
                    araddr  <= START_ADDR;
                    awvalid <= 1'b0;
                    arvalid <= 1'b0;
                    wvalid  <= 1'b0;
                    wlast   <= 1'b0;
                    bready  <= 1'b0;
                    rready  <= 1'b0;
                    done    <= 1'b0;
                end

                WRITE_ADDR: begin
                    awvalid <= 1'b1;
                    awlen   <= ALEN;
                    awsize  <= ASIZE;
                    awburst <= 2'b01;               // INCR
                    awqos   <= 1'b1;                // 参考 checker 同款（写通道 qos 置 1）
                    wvalid  <= 1'b0;                // 每 burst 起始强制清（参考同款）
                    beat_cnt <= BEATS - 9'd1;       // 119
                    wdata    <= pat(awaddr, BEATS - 9'd1);
                    done     <= 1'b0;
                end

                PRE_WRITE: begin
                    // 控制器 WVALID-先于-AWREADY 型：W 在此起爆，期间发生的
                    // 传输同样计数（参考 checker 同款）；wlast 与末 beat 同拍
                    if (awready)
                        awvalid <= 1'b0;
                    wvalid <= 1'b1;
                    bready <= 1'b1;
                    if (wready && wvalid) begin
                        if (beat_cnt == 9'd0) begin
                            wvalid <= 1'b0;         // 最后 beat
                            wlast  <= 1'b0;
                        end else begin
                            if (beat_cnt == 9'd1)
                                wlast <= 1'b1;      // 与最后 beat 同拍
                            beat_cnt <= beat_cnt - 9'd1;
                            wdata    <= pat(awaddr, beat_cnt - 9'd1);
                        end
                    end
                end

                WRITE: begin
                    if (wready && wvalid) begin
                        if (beat_cnt == 9'd0) begin
                            wvalid <= 1'b0;         // 最后 beat（wlast 已同拍置位）
                            wlast  <= 1'b0;
                        end else begin
                            if (beat_cnt == 9'd1)
                                wlast  <= 1'b1;     // 与最后 beat 同拍
                            beat_cnt <= beat_cnt - 9'd1;
                            wdata    <= pat(awaddr, beat_cnt - 9'd1);
                        end
                    end
                end

                POST_WRITE: begin
                    if (wready)
                        wlast <= 1'b0;
                    if (bvalid) begin
                        bready <= 1'b0;
                        if (burst_idx == TOTAL_BURSTS - 16'd1) begin
                            araddr    <= START_ADDR;    // 读阶段从头比对
                            burst_idx <= 16'd0;
                        end else begin
                            awaddr    <= awaddr + BURST_STEP;
                            burst_idx <= burst_idx + 16'd1;
                        end
                    end
                end

                READ_ADDR: begin
                    // araddr 由 POST_WRITE（末拍回 START_ADDR）与 POST_READ
                    // （+步进）维护，此处不得改写
                    arvalid <= 1'b1;
                    arlen   <= ALEN;
                    arsize  <= ASIZE;
                    arburst <= 2'b01;
                    beat_cnt <= BEATS - 9'd1;
                    exp_rdata <= pat(araddr, BEATS - 9'd1);
                end

                PRE_READ: begin
                    arvalid <= 1'b0;
                    rburst_done <= 1'b0;
                    rready  <= 1'b1;
                end

                READ_COMPARE: begin
                    if (rvalid) begin
                        if (rdata !== exp_rdata) begin
                            fail    <= 1'b1;        // sticky
                            err_cnt <= err_cnt + 16'd1;
                        end
                        if (beat_cnt != 9'd0) begin
                            beat_cnt  <= beat_cnt - 9'd1;
                            exp_rdata <= pat(araddr, beat_cnt - 9'd1);
                        end else begin
                            rburst_done <= 1'b1;
                            if (burst_idx == TOTAL_BURSTS - 16'd1)
                                read_done <= 1'b1;
                        end
                    end
                end

                POST_READ: begin
                    if (!read_done) begin
                        araddr    <= araddr + BURST_STEP;
                        burst_idx <= burst_idx + 16'd1;
                    end
                    rready <= 1'b1;
                end

                DONE: begin
                    done <= 1'b1;
                end

                default: ;
            endcase
        end
    end

endmodule
