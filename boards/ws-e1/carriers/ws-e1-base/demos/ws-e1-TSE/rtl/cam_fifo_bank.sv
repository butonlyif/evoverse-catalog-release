`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: cam_fifo_bank
// 功能描述: G11n14 多 bank 异步 FIFO 拼接——构造非 2 幂总深度 163,840
//           （bank0=2^17 + bank1=2^15），吸收 IMX415 有效行段净积 135,351 组
//           （G11n13 直方图定案：段内写入 32.43M 组/s > gen 千兆极限 23.96M，
//            帧尾 17.35ms gap 排空只需 5.7ms——整帧收支 800K > 518.4K 有余）。
//           单 FIFO 2^18 需 1024 块 BRAM（10Kb/块）超器件余量 46 块；
//           2^17 差 8.9 行/帧——拼接 163,840（640 块，总 942/1280）两难皆解。
// 接口说明: 对外与单 async_fifo 相同（wr_en/din/full + rd_en/dout/empty，
//           非 FWFT：rd 后一拍 dout 有效），顶层/gen 零适配；
//           增设 occ_rd（读域精确总积压）/occ_wr（写域保守积压）。
// 设计约束: 按序读写保证 bank 路由与数据存在性一致；各 bank 内部仍是标准
//           格雷异步 FIFO（跨域各自安全）；写域 wcnt/读域 rq 为模 163,840
//           计数（各自域内寄存器，不跨域）。bank 边界切换由 rd 流水打拍
//           对齐，dout 连续无气泡。occ 滞后 2 拍（同标准 FIFO），误差 <1 组。
//============================================================================
module cam_fifo_bank #(
    parameter int WIDTH       = 40,
    parameter int BANK0_DEPTH = 131072,   // 2^17（wcnt[17]==0 即 bank0 区）
    parameter int BANK1_DEPTH = 32768,    // 2^15
    parameter int TOTAL_DEPTH = BANK0_DEPTH + BANK1_DEPTH, // 163840
    parameter int CNT_W       = 18        // 2^18=262144 > TOTAL，模减无歧义
)(
    // 写侧（200M）
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [WIDTH-1:0]      din,
    output wire                  full,

    // 读侧（125M）
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output wire [WIDTH-1:0]      dout,
    output wire                  empty,

    // 占用/诊断
    output wire [CNT_W-1:0]      occ_rd,    // 读域：Σ各bank精确占用（写指针滞后2拍）
    output wire [CNT_W-1:0]      occ_wr,    // 写域：Σ各bank保守占用（读指针滞后2拍）
    output wire [CNT_W-1:0]      dbg_wcnt,  // 写域总写计数（模 TOTAL）
    output wire [CNT_W-1:0]      dbg_rq     // 读域总读计数（模 TOTAL）
);

    localparam int AW0 = $clog2(BANK0_DEPTH);  // 17 → 指针 18bit
    localparam int AW1 = $clog2(BANK1_DEPTH);  // 15 → 指针 16bit

    // ------------------------------------------------------------------
    // 写路由（写域）：G11n14b mod-5 交错。总深 163840 = 5×32768 整除，容量比
    // bank0:bank1 = 4:1 → 每 5 组 4 进 b0、1 进 b1；读写两侧同规则 → 数据序
    // 保持（第 g 组永远写读同一 bank，bank 内序=全局序）；wcnt 模 163840 且
    // 163840≡0 (mod 5) → 相位跨圈无漂移。任意积压 ≤163840 时 bank0 占用
    // ≤4/5×163840 = 131072（恰满）、bank1 ≤32768（恰满）→ 总容量全额可用。
    // 原位测试路由（wcnt[17]）缺陷（仿真 full_rej=73600/帧实锤）：读写窗口
    // [rq,wcnt] 可整体落在 bank0 区间，bank0 局部满而 bank1 全空 → 拒写，
    // 有效容量塌缩至 ~77K（bank0 窗口剩余）。
    // ------------------------------------------------------------------
    wire             wr_accept  = wr_en && !full;
    reg  [CNT_W-1:0] wcnt;
    wire [CNT_W-1:0] wcnt_next  = (wcnt == TOTAL_DEPTH-1) ? {CNT_W{1'b0}}
                                                          : wcnt + 1'b1;
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n)          wcnt <= {CNT_W{1'b0}};
        else if (wr_accept)     wcnt <= wcnt_next;
    end

    wire             wr_to_b1   = (wcnt[2:0] == 3'd4);
    wire             wr_en_b0   = wr_accept && !wr_to_b1;
    wire             wr_en_b1   = wr_accept &&  wr_to_b1;

    // ------------------------------------------------------------------
    // 读路由（读域）：rq 模 163840，与写侧同 mod-5 规则（保序）
    // ------------------------------------------------------------------
    reg  [CNT_W-1:0] rq;
    wire             rd_accept   = rd_en && !empty;
    wire [CNT_W-1:0] rq_next     = (rq == TOTAL_DEPTH-1) ? {CNT_W{1'b0}}
                                                         : rq + 1'b1;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)          rq <= {CNT_W{1'b0}};
        else if (rd_accept)     rq <= rq_next;
    end

    wire rd_en_b0 = rd_accept && (rq[2:0] != 3'd4);
    wire rd_en_b1 = rd_accept && (rq[2:0] == 3'd4);

    // dout 流水 bank 选通（rd 路由同拍寄存，与 bank dout 的一拍延迟对齐）
    reg dout_sel_b1;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)      dout_sel_b1 <= 1'b0;
        else if (rd_accept) dout_sel_b1 <= (rq[2:0] == 3'd4);
    end

    // ------------------------------------------------------------------
    // bank 例化（内部标准格雷异步 FIFO，跨域各自安全）
    // ------------------------------------------------------------------
    wire [WIDTH-1:0] dout_b0, dout_b1;
    wire             full_b0, full_b1;
    wire [AW0:0]     wbin0, rbin0, rbin0_sync;   // 写域wr / 读域rd / 写域rd_sync
    wire [AW1:0]     wbin1, rbin1, rbin1_sync;
    wire [AW0:0]     wgray0_dbg;
    wire [AW1:0]     wgray1_dbg;

    async_fifo #(.WIDTH(WIDTH), .DEPTH(BANK0_DEPTH)) u_bank0 (
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n),
        .wr_en(wr_en_b0), .din(din), .full(full_b0),
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n),
        .rd_en(rd_en_b0), .dout(dout_b0), .empty(),
        .dbg_wr_bin(wbin0), .dbg_rd_bin(rbin0), .dbg_rd_bin_sync(rbin0_sync),
        .dbg_wr_gray(wgray0_dbg)
    );

    async_fifo #(.WIDTH(WIDTH), .DEPTH(BANK1_DEPTH)) u_bank1 (
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n),
        .wr_en(wr_en_b1), .din(din), .full(full_b1),
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n),
        .rd_en(rd_en_b1), .dout(dout_b1), .empty(),
        .dbg_wr_bin(wbin1), .dbg_rd_bin(rbin1), .dbg_rd_bin_sync(rbin1_sync),
        .dbg_wr_gray(wgray1_dbg)
    );

    // ------------------------------------------------------------------
    // 读域写指针视图（格雷 2FF + gray2bin，供 occ_rd/empty）
    // ------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [AW0:0] wgray0_s1, wgray0_s2;
    (* ASYNC_REG = "TRUE" *) reg [AW1:0] wgray1_s1, wgray1_s2;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wgray0_s1 <= '0; wgray0_s2 <= '0;
            wgray1_s1 <= '0; wgray1_s2 <= '0;
        end else begin
            wgray0_s1 <= wgray0_dbg; wgray0_s2 <= wgray0_s1;
            wgray1_s1 <= wgray1_dbg; wgray1_s2 <= wgray1_s1;
        end
    end

    function automatic [AW0:0] g2b0(input [AW0:0] g);
        g2b0[AW0] = g[AW0];
        for (int i = AW0-1; i >= 0; i--) g2b0[i] = g2b0[i+1] ^ g[i];
    endfunction
    function automatic [AW1:0] g2b1(input [AW1:0] g);
        g2b1[AW1] = g[AW1];
        for (int i = AW1-1; i >= 0; i--) g2b1[i] = g2b1[i+1] ^ g[i];
    endfunction

    wire [AW0:0] wbin0_rd = g2b0(wgray0_s2);
    wire [AW1:0] wbin1_rd = g2b1(wgray1_s2);

    // 各 bank 占用（模减；占用 < 各自 2^AW 时结果正确）
    wire [AW0:0] occ0_rd = wbin0_rd - rbin0;
    wire [AW1:0] occ1_rd = wbin1_rd - rbin1;
    wire [AW0:0] occ0_wr = wbin0 - rbin0_sync;
    wire [AW1:0] occ1_wr = wbin1 - rbin1_sync;

    // 总占用/空满（读域滞后 2 拍精确；写域滞后 2 拍保守——方向安全）
    assign occ_rd = {1'b0, occ0_rd} + {2'b00, occ1_rd};
    assign occ_wr = {1'b0, occ0_wr} + {2'b00, occ1_wr};
    assign empty  = (occ_rd == {CNT_W{1'b0}});
    assign full   = (occ_wr >= TOTAL_DEPTH-2) || full_b0 || full_b1;

    assign dout   = dout_sel_b1 ? dout_b1 : dout_b0;
    assign dbg_wcnt = wcnt;
    assign dbg_rq   = rq;

endmodule

`default_nettype wire
