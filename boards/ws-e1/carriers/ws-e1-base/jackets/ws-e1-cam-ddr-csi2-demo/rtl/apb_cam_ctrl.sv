// ============================================================================
// apb_cam_ctrl.v — camera_path 控制口 APB CSR（top_cam_demo 中挂 riscv_soc
//                  APB slave 0）
//
// 寄存器（word 编址，仅 offset 0x0 的 CTRL 使用，其余 offset 读 0、写忽略）：
//   CTRL @0x00：
//     [1:0]   bayer_phase  拜耳相位 0=RGGB 1=GRBG 2=GBRG 3=BGGR
//     [2]     adaptive     demosaic R/B 站点自适应 G 方向
//     [3]     pat_en       1 = pattern_gen 拍流替换 my_csi2_rx 输出
//                          （复位默认 1：上电即发灰度图案）
//     [5:4]   pat_sel      图案选择 0=灰度竖 ramp 1=橙蓝竖条
//                          2=灰度横 ramp 3=8x8 棋盘（复位默认灰度）
//     [15:8]  wb_r         白平衡增益（Q8.8 高 8 位）
//     [23:16] wb_g
//     [31:24] wb_b
//
//   复位默认 = 板级标定值（wb 200/235/180、adaptive=1、phase=0/RGGB、
//   pat_en=1/pat_sel=0 上电发灰度图案），上电未配置也可出像
//   （与 TB 标定值一致）。
//   零等待 APB：pready 恒 1，pslverr 恒 0（软件误访问不会挂总线）。
// ============================================================================

module apb_cam_ctrl #(
    parameter CTRL_RESET = 32'hB4EB_C80C   // {wb_b, wb_g, wb_r, pat_en=1, adaptive=1, phase=0(RGGB)}
) (
    input  wire        pclk,
    input  wire        presetn,
    input  wire [15:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // camera_path 控制口（写后立即生效，静态输出）
    output wire [1:0]  bayer_phase,
    output wire        adaptive,
    output wire [7:0]  wb_r,
    output wire [7:0]  wb_g,
    output wire [7:0]  wb_b,

    // 图案源选择（top_cam_demo 输入 mux + pattern_gen 图案选择）
    output wire        pat_en,
    output wire [1:0]  pat_sel
);

    reg [31:0] ctrl_r;

    assign bayer_phase = ctrl_r[1:0];
    assign adaptive    = ctrl_r[2];
    assign pat_en      = ctrl_r[3];
    assign pat_sel     = ctrl_r[5:4];
    assign wb_r        = ctrl_r[15:8];
    assign wb_g        = ctrl_r[23:16];
    assign wb_b        = ctrl_r[31:24];

    // 仅 CTRL @0x0 可写（paddr[2]==0）；word 编址下 bit2 是首个寄存器选择位
    wire wr_en = psel & penable & pwrite & ~paddr[2];

    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            ctrl_r <= CTRL_RESET;
        else if (wr_en)
            ctrl_r <= pwdata;
    end

    assign prdata  = paddr[2] ? 32'h0 : ctrl_r;
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

endmodule
