// ============================================================================
// camera_path.v — 相机图像流水线顶层（raw_2_axi4st -> demosaic -> wb_axis
//                 -> rgb2yuv_axis -> shape_video_axis 五级串联）
//
// 数据通路（全链 1 拍 = 4 像素，拍率 1:1，无反压直通）：
//   40bit  raw_2_axi4st : 传感器拍流窗口裁剪 -> AXIS（4xRAW10）
//   120bit demosaic     : RAW10 拜耳 -> RGB 10bit x4px
//   96bit  wb_axis      : 白平衡增益 + 8bit 量化
//   64bit  rgb2yuv_axis : RGB888 -> UYVY（YUV422 8-bit）
//   shape_video_axis    : AXIS -> CSI-2 TX 视频成形（整帧门控/VFP trim，
//                         设计契约见 shape_video_axis.sv 头注释）
//
// 时钟域：五级写侧共 aclk（前四级全部逻辑 + shape 写侧）；shape 读侧独立
// pixel_clk 输出 CSI-2 TX Video Interface。复位两级分开：aresetn /
// pixel_rst_n（须同时释放或先于数据释放，冷启动零丢帧依赖 shape 帧锚定）。
//
// 控制口：bayer_phase/adaptive（demosaic）、wb_r/wb_g/wb_b（wb_axis）原样
// 暴露，由上层（SoC APB 寄存器）静态驱动。
// ============================================================================

module camera_path #(
    // ---- raw_2_axi4st：传感器窗口几何 ----
    parameter DTYPE           = 6'h2B,       // 像素 DT（RAW10）
    parameter LINE_TOTAL_PIX  = 20'd1944,    // 行总像素（IMX415, WC=2430）
    parameter LEAD_PIX        = 20'd6,       // 行首丢弃像素
    parameter TRAIL_PIX       = 20'd18,      // 行尾丢弃像素
    parameter LINE_SKIP_FIRST = 20'd11,      // 帧首丢弃 hs 行数
    parameter LINES           = 16'd1080,    // 有效行数（raw 输出 = demosaic 处理）
    // ---- demosaic ----
    parameter GW              = 16'd480,     // 每行组数（= H_ACTIVE/4）
    // ---- shape_video_axis：CSI-2 TX 成形 ----
    parameter HACT            = 16'd1920,
    parameter VACT            = 16'd1080,
    parameter HSP             = 16'd44,
    parameter HBP             = 16'd148,
    parameter HFP             = 16'd88,
    parameter VSP             = 16'd5,
    parameter VBP             = 16'd36,
    parameter VFP             = 16'd4,
    parameter PPC             = 16'd4,       // 每时钟像素数（全链固定 4）
    parameter DATA_TYPE       = 6'h1E,       // YUV422 8-bit
    parameter FIFO_DEPTH      = 16'd32768,
    parameter HIGH_LINES      = 16'd60,
    parameter LOW_LINES       = 16'd12,
    parameter TRIM_LINES      = 16'd4,
    parameter VFRONT_WAIT_LINES = 16'd4,
    parameter DRAIN_CAP_LINES   = 16'd54
) (
    // ---- 时钟/复位 ----
    input  wire        aclk,            // 流水线时钟（含 shape 写侧）
    input  wire        aresetn,
    input  wire        pixel_clk,       // shape 读侧（CSI-2 TX 域）
    input  wire        pixel_rst_n,

    // ---- 传感器/图案拍流（不可暂停源，经 cam_frame_writer 等）----
    input  wire [39:0] in_data,         // 4xRAW10 打包
    input  wire        in_valid,
    input  wire        in_vs,           // 帧起始（上升沿）
    input  wire        in_hs,           // 行同步（脉冲或行电平）
    input  wire [5:0]  in_dtype,

    // ---- 流水线控制（APB 静态驱动）----
    input  wire [1:0]  bayer_phase,     // 0=RGGB 1=GRBG 2=GBRG 3=BGGR
    input  wire        adaptive,        // R/B 站点自适应 G 方向
    input  wire [7:0]  wb_r,            // 白平衡增益 Q8.8 高 8 位
    input  wire [7:0]  wb_g,
    input  wire [7:0]  wb_b,
    input  wire        blk_clip,        // rgb2yuv 暗场钳位使能（1=sensor 域钳
                                        // FPN 噪；0=图案域旁路，ramp 暗部
                                        // 不被 Y<24 整段压黑）

    // ---- CSI-2 TX Video Interface（与 shape_video_axis 一致）----
    output wire        hsync_vc0,
    output wire        vsync_vc0,
    output wire [5:0]  datatype,
    output wire [63:0] pixel_data,
    output wire        pixel_data_valid,
    output wire [15:0] haddr,
    output wire [15:0] line_num,
    output wire [15:0] frame_num

);

    //--------------------------------------------------------------------
    // 级间连线（AXIS，无 tready：全链 always-ready 直通）
    //--------------------------------------------------------------------
    (* syn_keep = "true" *)wire [39:0]  raw_tdata;
    (* syn_keep = "true" *)wire         raw_tvalid, raw_tlast;
    (* syn_keep = "true" *)wire [2:0]   raw_tuser;             // {eof, sol, sof}

    (* syn_keep = "true" *)wire [119:0] dms_tdata;
    (* syn_keep = "true" *)wire         dms_tvalid, dms_tlast;
    (* syn_keep = "true" *)wire [2:0]   dms_tuser;

    (* syn_keep = "true" *)wire [95:0]  wb_tdata;
    (* syn_keep = "true" *)wire         wb_tvalid, wb_tlast;
    (* syn_keep = "true" *)wire [2:0]   wb_tuser;

    (* syn_keep = "true" *)wire [63:0]  yuv_tdata;
    (* syn_keep = "true" *)wire         yuv_tvalid, yuv_tlast;
   (* syn_keep = "true" *) wire [2:0]   yuv_tuser;

    //--------------------------------------------------------------------
    // 1. raw_2_axi4st：传感器拍流 -> AXIS-40（窗口裁剪/行列筛选）
    //--------------------------------------------------------------------
    raw_2_axi4st #(
        .DTYPE           (DTYPE),
        .LINE_TOTAL_PIX  (LINE_TOTAL_PIX),
        .LEAD_PIX        (LEAD_PIX),
        .TRAIL_PIX       (TRAIL_PIX),
        .LINE_SKIP_FIRST (LINE_SKIP_FIRST),
        .LINES           (LINES)
    ) u_raw (
        .aclk         (aclk),
        .aresetn      (aresetn),
        .in_data      (in_data),
        .in_valid     (in_valid),
        .in_vs        (in_vs),
        .in_hs        (in_hs),
        .in_dtype     (in_dtype),
        .m_axis_tdata (raw_tdata),
        .m_axis_tvalid(raw_tvalid),
        .m_axis_tlast (raw_tlast),
        .m_axis_tuser (raw_tuser)
    );

    //--------------------------------------------------------------------
    // 2. demosaic：RAW10 拜耳 -> RGB x4px（AXIS-40 -> AXIS-120）
    //--------------------------------------------------------------------
    demosaic #(
        .GW   (GW),
        .LINES(LINES)
    ) u_demosaic (
        .aclk         (aclk),
        .aresetn      (aresetn),
        .s_axis_tdata (raw_tdata),
        .s_axis_tvalid(raw_tvalid),
        .s_axis_tlast (raw_tlast),
        .s_axis_tuser (raw_tuser),
        .bayer_phase  (bayer_phase),
        .adaptive     (adaptive),
        .m_axis_tdata (dms_tdata),
        .m_axis_tvalid(dms_tvalid),
        .m_axis_tlast (dms_tlast),
        .m_axis_tuser (dms_tuser)
    );

    //--------------------------------------------------------------------
    // 3. wb_axis：白平衡 + 8bit 量化（AXIS-120 -> AXIS-96）
    //--------------------------------------------------------------------
    wb_axis u_wb (
        .aclk         (aclk),
        .aresetn      (aresetn),
        .s_axis_tdata (dms_tdata),
        .s_axis_tvalid(dms_tvalid),
        .s_axis_tlast (dms_tlast),
        .s_axis_tuser (dms_tuser),
        .wb_r         (wb_r),
        .wb_g         (wb_g),
        .wb_b         (wb_b),
        .m_axis_tdata (wb_tdata),
        .m_axis_tvalid(wb_tvalid),
        .m_axis_tlast (wb_tlast),
        .m_axis_tuser (wb_tuser)
    );

    //--------------------------------------------------------------------
    // 4. rgb2yuv_axis：RGB888 -> UYVY（AXIS-96 -> AXIS-64）
    //--------------------------------------------------------------------
    rgb2yuv_axis u_rgb2yuv (
        .aclk         (aclk),
        .aresetn      (aresetn),
        .s_axis_tdata (wb_tdata),
        .s_axis_tvalid(wb_tvalid),
        .s_axis_tlast (wb_tlast),
        .s_axis_tuser (wb_tuser),
        .blk_clip     (blk_clip),
        .m_axis_tdata (yuv_tdata),
        .m_axis_tvalid(yuv_tvalid),
        .m_axis_tlast (yuv_tlast),
        .m_axis_tuser (yuv_tuser)
    );

    //--------------------------------------------------------------------
    // 5. shape_video_axis：AXIS-64 -> CSI-2 TX 视频成形（写侧 aclk 域）
    //--------------------------------------------------------------------
    shape_video_axis #(
        .HACT      (HACT),
        .VACT      (VACT),
        .HSP       (HSP),
        .HBP       (HBP),
        .HFP       (HFP),
        .VSP       (VSP),
        .VBP       (VBP),
        .VFP       (VFP),
        .PPC       (PPC),
        .DATA_TYPE (DATA_TYPE),
        .FIFO_DEPTH(FIFO_DEPTH),
        .HIGH_LINES(HIGH_LINES),
        .LOW_LINES (LOW_LINES),
        .TRIM_LINES(TRIM_LINES),
        .VFRONT_WAIT_LINES(VFRONT_WAIT_LINES),
        .DRAIN_CAP_LINES  (DRAIN_CAP_LINES)
    ) u_shape (
        .s_axis_aclk   (aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tdata  (yuv_tdata),
        .s_axis_tvalid (yuv_tvalid),
        .s_axis_tlast  (yuv_tlast),
        .s_axis_tuser  (yuv_tuser),
        .pixel_clk     (pixel_clk),
        .pixel_rst_n   (pixel_rst_n),
        .hsync_vc0     (hsync_vc0),
        .vsync_vc0     (vsync_vc0),
        .datatype      (datatype),
        .pixel_data    (pixel_data),
        .pixel_data_valid(pixel_data_valid),
        .haddr         (haddr),
        .line_num      (line_num),
        .frame_num     (frame_num)
    );

endmodule
