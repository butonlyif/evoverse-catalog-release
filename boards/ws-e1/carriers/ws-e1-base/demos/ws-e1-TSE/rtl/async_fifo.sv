//=============================================================================
// 标准异步 FIFO，Block RAM 推断（真双端口）
// 非 FWFT：rd_en 拉高一拍后 dout 有效
// 指针使用格雷码跨时钟域同步
// 深度必须是 2 的幂
//=============================================================================
module async_fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 16,
    parameter int AW    = $clog2(DEPTH)
)(
    // 写侧
    input  logic             wr_clk,
    input  logic             wr_rst_n,
    input  logic             wr_en,
    input  logic [WIDTH-1:0] din,
    output logic             full,

    // 读侧
    input  logic             rd_clk,
    input  logic             rd_rst_n,
    input  logic             rd_en,
    output logic [WIDTH-1:0] dout,
    output logic             empty,
    //G11j-4 诊断指针（不参与功能；不接则悬空）
    output logic [AW:0]      dbg_wr_bin,       // 写域：真实写指针
    output logic [AW:0]      dbg_rd_bin,       // 读域：真实读指针
    output logic [AW:0]      dbg_rd_bin_sync,  // 写域：full 所见的同步读指针
    //G11n14 bank 拼接用：写格雷寄存值（cam_fifo_bank 读域同步链需要；
    //不接则悬空，单 FIFO 用法零影响）
    output logic [AW:0]      dbg_wr_gray
);

    //------------------------------------------------------------------
    // Block RAM 存储体（真双端口）
    //------------------------------------------------------------------
    (* syn_ramstyle = "block_ram" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

    //------------------------------------------------------------------
    // 二进制指针 + 格雷码指针（G11k 修复一：格雷指针寄存输出）
    // 原实现 assign wr_gray = wr_bin ^ (wr_bin>>1) 组合直出跨域：RTL 仿真
    // 零延迟无毛刺全 PASS，网表上 XOR 过渡毛刺被对域同步 FF 采样成幻影指针
    // （G11j 系列 full 在 occ=83 误置冻结的根因）。改为 bin_next/gray_next
    // 同沿寄存：格雷值每拍至多变 1 位，跨域采样安全；寄存值与原组合式每拍
    // 完全相等（同沿用 next 值），仿真行为不变。
    //------------------------------------------------------------------
    logic [AW:0] wr_bin, rd_bin;
    logic [AW:0] wr_gray, rd_gray;

    wire        wr_accept    = wr_en && !full;
    wire        rd_accept    = rd_en && !empty;
    wire [AW:0] wr_bin_next  = wr_bin + {{AW{1'b0}}, wr_accept};
    wire [AW:0] rd_bin_next  = rd_bin + {{AW{1'b0}}, rd_accept};
    wire [AW:0] wr_gray_next = wr_bin_next ^ (wr_bin_next >> 1);
    wire [AW:0] rd_gray_next = rd_bin_next ^ (rd_bin_next >> 1);

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin  <= '0;
            wr_gray <= '0;
        end else begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin  <= '0;
            rd_gray <= '0;
        end else begin
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
        end
    end

    //------------------------------------------------------------------
    // 读侧同步写指针
    //------------------------------------------------------------------
    logic [AW:0] wr_gray_sync1, wr_gray_sync2;
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_sync1 <= '0;
            wr_gray_sync2 <= '0;
        end
        else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

    //------------------------------------------------------------------
    // 写侧同步读指针
    //------------------------------------------------------------------
    logic [AW:0] rd_gray_sync1, rd_gray_sync2;
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_sync1 <= '0;
            rd_gray_sync2 <= '0;
        end
        else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    //------------------------------------------------------------------
    // 格雷码转二进制
    //------------------------------------------------------------------
    function automatic [AW:0] gray2bin(input [AW:0] g);
        gray2bin[AW] = g[AW];
        for (int i = AW-1; i >= 0; i--) begin
            gray2bin[i] = gray2bin[i+1] ^ g[i];
        end
    endfunction

    logic [AW:0] wr_bin_sync, rd_bin_sync;
    assign wr_bin_sync = gray2bin(wr_gray_sync2);
    assign rd_bin_sync = gray2bin(rd_gray_sync2);

    //G11j-4 诊断指针直出
    assign dbg_wr_bin     = wr_bin;
    assign dbg_rd_bin     = rd_bin;
    assign dbg_rd_bin_sync = rd_bin_sync;
    assign dbg_wr_gray    = wr_gray;   //G11n14 寄存后的写格雷（跨域安全源）

    //------------------------------------------------------------------
    // 空满判断（G11k 修复二：full 判据改标准双高位取反）
    // G11j-4 的单高位取反 {~rd_gray_sync2[AW], rd_gray_sync2[AW-1:0]} 实际触发
    // 条件是 W+R ≡ 2^(AW+1)-1（板级实证：W=1669、R=378、W+R=2047 时 full=1，
    // 而真实占用 1291 > DEPTH=1024 —— 写指针已套圈覆写 267 字后才碰巧置位，
    // 且把写侧永久冻死与 pacer occ<300 互锁）。标准判据（等价二进制
    // occ==DEPTH，推导见注释头部）：
    //   full  = 写格雷高二位 == 同步读格雷高二位取反，低 AW-1 位相等
    //   empty = 读格雷 == 同步后的写格雷（不变）
    // 同步滞后使占用率视角偏大 → full 提前保守置位，方向安全。
    //------------------------------------------------------------------
    assign full  = (wr_gray == {~rd_gray_sync2[AW:AW-1], rd_gray_sync2[AW-2:0]});
    assign empty = (rd_gray == wr_gray_sync2);

    //------------------------------------------------------------------
    // 写逻辑
    //------------------------------------------------------------------
    always_ff @(posedge wr_clk) begin
        if (wr_accept) begin
            mem[wr_bin[AW-1:0]] <= din;
        end
    end

    //------------------------------------------------------------------
    // 读逻辑
    //------------------------------------------------------------------
    always_ff @(posedge rd_clk) begin
        if (rd_accept) begin
            dout <= mem[rd_bin[AW-1:0]];
        end
    end

endmodule
