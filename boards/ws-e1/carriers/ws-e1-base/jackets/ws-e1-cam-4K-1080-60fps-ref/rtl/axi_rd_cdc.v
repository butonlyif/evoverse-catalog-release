//=====================================================================
// axi_rd_cdc.v — AXI4 读口异步钟域转换（cam1_rd 37.125M ↔ 互联 148.5M）
// 契约   : doc/arbiter.md v1.2 §4.3（AR 载荷 61b / R 载荷 521b，深度 4）
// 结构   : 两通道独立 async FIFO（寄存器阵 + 首字直通）：
//            AR 命令 FIFO   s(37.125M 写) → m(148.5M 读)
//            R  响应 FIFO   m(148.5M 写)  → s(37.125M 读)
// 灰指针 : 参照 rtl/disp_line_fifo.v——指针与 2FF 同步链全部 syn_keep
//          （2026-10-12 async_path_fifo 板级前科：gray 链被综合重定时/
//          合并导致水位失真，属已验证必修项，勿删）
// 语义   : 全接口 AXI valid-hold；s_arready = ~AR FIFO 满（kimi3-M1：
//          满反压贯穿硬核读数据队列，深度 >=16，不丢数）；s_rvalid =
//          ~R FIFO 空（首字直通，无输出寄存附加延迟）
// 载荷   : AR 61b = {arlock,arcache4,arqos4,arid6,arburst2,arsize3,arlen8,araddr33}
//          R  521b = {rid6,rlast,rresp2,rdata512}
// 语言   : 纯 Verilog-2001 可综合子集
//=====================================================================

module axi_rd_cdc #(
    parameter AW = 2                      // 深度 4（§4.3 冻结）
) (
    // ---- s 侧：cam1_rd master 接入（aclk_s = 37.125M）----
    input  wire          aclk_s,
    input  wire          rstn_s,          // 低有效异步；本域复位树驱动
    input  wire          s_arvalid,
    output wire          s_arready,
    input  wire  [32:0]  s_araddr,
    input  wire  [7:0]   s_arlen,
    input  wire  [2:0]   s_arsize,
    input  wire  [1:0]   s_arburst,
    input  wire  [5:0]   s_arid,
    input  wire  [3:0]   s_arqos,
    input  wire  [3:0]   s_arcache,
    input  wire          s_arlock,
    output wire          s_rvalid,
    input  wire          s_rready,
    output wire [511:0]  s_rdata,
    output wire [1:0]    s_rresp,
    output wire          s_rlast,
    output wire [5:0]    s_rid,

    // ---- m 侧：互联（aclk_m = 148.5M，接 axi_rd_arb S0）----
    input  wire          aclk_m,
    input  wire          rstn_m,
    output wire          m_arvalid,
    input  wire          m_arready,
    output wire [32:0]   m_araddr,
    output wire [7:0]    m_arlen,
    output wire [2:0]    m_arsize,
    output wire [1:0]    m_arburst,
    output wire [5:0]    m_arid,
    output wire [3:0]    m_arqos,
    output wire [3:0]    m_arcache,
    output wire          m_arlock,
    input  wire          m_rvalid,
    output wire          m_rready,
    input  wire [511:0]  m_rdata,
    input  wire [1:0]    m_rresp,
    input  wire          m_rlast,
    input  wire [5:0]    m_rid
);

//=====================================================================
// 0. 通用：二进制 ↔ 格雷
//=====================================================================
function [AW:0] b2g(input [AW:0] b);
    begin
        b2g = b ^ (b >> 1);
    end
endfunction

function [AW:0] g2b(input [AW:0] g);
    integer i;
    begin
        g2b[AW] = g[AW];
        for (i = AW-1; i >= 0; i = i - 1)
            g2b[i] = g2b[i+1] ^ g[i];
    end
endfunction

//=====================================================================
// 1. AR 命令 FIFO（s 写 37.125M → m 读 148.5M，载荷 61b，深度 4）
//=====================================================================
reg [60:0] ar_mem [0:(1<<AW)-1];

(* syn_keep = "true" *) reg [AW:0] ar_wptr;             // s 域
(* syn_keep = "true" *) reg [AW:0] ar_rptr;             // m 域
// m→s / s→m 2FF 同步链（gray，syn_keep 必修——见头注释）
(* syn_keep = "true" *) reg [AW:0] ar_rptr_s0, ar_rptr_s1;   // ar_rptr -> s 域
(* syn_keep = "true" *) reg [AW:0] ar_wptr_m0, ar_wptr_m1;   // ar_wptr -> m 域

wire [AW:0] g_ar_wptr = b2g(ar_wptr);
wire [AW:0] g_ar_rptr = b2g(ar_rptr);

wire [AW:0] ar_rptr_s = g2b(ar_rptr_s1);   // s 域视角读指针（满判定）
wire [AW:0] ar_wptr_m = g2b(ar_wptr_m1);   // m 域视角写指针（空判定）

wire ar_full  = (ar_wptr[AW-1:0] == ar_rptr_s[AW-1:0]) &&
                (ar_wptr[AW]     != ar_rptr_s[AW]);
wire ar_empty = (ar_rptr == ar_wptr_m);

wire ar_push = s_arvalid & ~ar_full;       // s 域
wire ar_pop  = ~ar_empty & m_arready;      // m 域（valid-hold 见下）

assign s_arready = rstn_s & ~ar_full;
assign m_arvalid = rstn_m & ~ar_empty;     // 首字直通：非空即 valid

assign {m_arlock, m_arcache, m_arqos, m_arid, m_arburst,
        m_arsize, m_arlen, m_araddr} = ar_mem[ar_rptr[AW-1:0]];

always @(posedge aclk_s or negedge rstn_s) begin
    if (!rstn_s)
        ar_wptr <= {AW+1{1'b0}};
    else if (ar_push) begin
        ar_mem[ar_wptr[AW-1:0]] <= {s_arlock, s_arcache, s_arqos, s_arid,
                                    s_arburst, s_arsize, s_arlen, s_araddr};
        ar_wptr <= ar_wptr + {{AW{1'b0}}, 1'b1};
    end
end

always @(posedge aclk_m or negedge rstn_m) begin
    if (!rstn_m) begin
        ar_rptr    <= {AW+1{1'b0}};
        ar_wptr_m0 <= {AW+1{1'b0}};
        ar_wptr_m1 <= {AW+1{1'b0}};
    end else begin
        if (ar_pop)
            ar_rptr <= ar_rptr + {{AW{1'b0}}, 1'b1};
        ar_wptr_m0 <= g_ar_wptr;
        ar_wptr_m1 <= ar_wptr_m0;
    end
end

always @(posedge aclk_s or negedge rstn_s) begin
    if (!rstn_s) begin
        ar_rptr_s0 <= {AW+1{1'b0}};
        ar_rptr_s1 <= {AW+1{1'b0}};
    end else begin
        ar_rptr_s0 <= g_ar_rptr;
        ar_rptr_s1 <= ar_rptr_s0;
    end
end

//=====================================================================
// 2. R 响应 FIFO（m 写 148.5M → s 读 37.125M，载荷 521b，深度 4）
//=====================================================================
reg [520:0] r_mem [0:(1<<AW)-1];

(* syn_keep = "true" *) reg [AW:0] r_wptr;              // m 域
(* syn_keep = "true" *) reg [AW:0] r_rptr;              // s 域
(* syn_keep = "true" *) reg [AW:0] r_wptr_s0, r_wptr_s1;     // r_wptr -> s 域
(* syn_keep = "true" *) reg [AW:0] r_rptr_m0, r_rptr_m1;     // r_rptr -> m 域

wire [AW:0] g_r_wptr = b2g(r_wptr);
wire [AW:0] g_r_rptr = b2g(r_rptr);

wire [AW:0] r_wptr_s = g2b(r_wptr_s1);     // s 域视角写指针（空判定）
wire [AW:0] r_rptr_m = g2b(r_rptr_m1);     // m 域视角读指针（满判定）

wire r_full  = (r_wptr[AW-1:0] == r_rptr_m[AW-1:0]) &&
               (r_wptr[AW]     != r_rptr_m[AW]);
wire r_empty = (r_rptr == r_wptr_s);

wire r_push = m_rvalid & ~r_full;          // m 域
wire r_pop  = ~r_empty & s_rready;         // s 域（valid-hold 见下）

assign m_rready = rstn_m & ~r_full;
assign s_rvalid = rstn_s & ~r_empty;       // 首字直通：非空即 valid

assign {s_rid, s_rlast, s_rresp, s_rdata} = r_mem[r_rptr[AW-1:0]];

always @(posedge aclk_m or negedge rstn_m) begin
    if (!rstn_m)
        r_wptr <= {AW+1{1'b0}};
    else if (r_push) begin
        r_mem[r_wptr[AW-1:0]] <= {m_rid, m_rlast, m_rresp, m_rdata};
        r_wptr <= r_wptr + {{AW{1'b0}}, 1'b1};
    end
end

always @(posedge aclk_s or negedge rstn_s) begin
    if (!rstn_s) begin
        r_rptr    <= {AW+1{1'b0}};
        r_wptr_s0 <= {AW+1{1'b0}};
        r_wptr_s1 <= {AW+1{1'b0}};
    end else begin
        if (r_pop)
            r_rptr <= r_rptr + {{AW{1'b0}}, 1'b1};
        r_wptr_s0 <= g_r_wptr;
        r_wptr_s1 <= r_wptr_s0;
    end
end

always @(posedge aclk_m or negedge rstn_m) begin
    if (!rstn_m) begin
        r_rptr_m0 <= {AW+1{1'b0}};
        r_rptr_m1 <= {AW+1{1'b0}};
    end else begin
        r_rptr_m0 <= g_r_rptr;
        r_rptr_m1 <= r_rptr_m0;
    end
end

endmodule
