////////////////////////////////////////////////////////////////////////////
//  top_cam_demo.v — 摄像头直连顶层（CSI-2 RX IP -> 像素链 -> CSI-2 TX IP）
//
//  v4.10c3m 扁平化（2026-10-22）：camera_path 层删除，原 DISP_V4=1 网表
//  直移本文件（shape_video_axis/async_path_fifo/replay_pat_gen 随
//  DISP_V4=0 分支一并退役，文件已删）。显示成形唯一路径 =
//  tx_line_buf + disp_timing（v4 链，cam0/cam1 统一）。
//
//  数据通路（显示唯一来源 = DDR 回放）：
//    DPHY RX -> my_csi2_rx (裸 IP) -> RAW10 4px @ sys_clk_200m
//            -> raw_2_axi4st -> frame_writer（top_cam_demo）-> DDR
//            -> frame_reader（top_cam_demo）-> rd_t*（同钟直通，无 CDC）
//            -> raw_wb（RAW10 增益，v5）-> demosaic -> rgb10_to_rgb8
//            -> rgb2yuv ->（shape_pat_gen 直注 mux）
//            -> tx_line_buf -> disp_timing -> TX Video Interface
//            -> my_csi2_tx (裸 IP) -> DPHY TX (4 lane)
//
//  时钟：
//    sys_clk_200m : my_csi2_rx 像素输出域 + pattern_gen + raw_2_axi4st
//    tx_pixel_clk : 流水线（demosaic~disp_timing）+ frame_reader 回放域
//                   （v4 Phase 4：reader 换域，回放 CDC 冗余已除）
//    sys_clk_100m  : my_csi2_rx 控制器时钟（AXI tie off，仍需供给）
//    dphy_rx_clk_CLKOUT : DPHY RX 恢复字时钟（byte 域复位随其停振保持）
//    i_clk_27m    : TX 侧上电自复位基准；esc_clk : DPHY TX
//
//  复位：
//    raw 域 aresetn     = sys_clk_200m_rstn & sw_rstn（源切换帧界复位）
//    pixel 域 pixel_rst_n = TX 侧 reset_chain tx_pixel_clk_rstn & sw_rstn_tx
//      （释放晚于 PLL 锁定 + ~300us + ~600us；传感器在软件 I2C 配置完成后
//       才开始发流，满足"pixel_rst_n 先于数据释放"的冷启动锚定契约）
//    my_csi2_rx 复位随 sys_clk_100m 域释放（PLL 锁定前 DPHY RX 硬核保持复位）
//
//  控制：riscv_soc APB slave0 -> apb_cam_ctrl
//    （bayer_phase/adaptive/wb 增益，复位默认 = 板级标定值上电即出像）；
//    APB slave1/2/3 dummy 即答；I2C0/1 -> IMX415；GPIO0.bit0 -> cam_0_en；
//    UART/JTAG USER1 原样（JTAG UPDATE/RESET 为 BRAM 固件加载路径，不可改）。
//
//  DDR：frame_writer/frame_reader 在 top_cam_demo（双摄各自挂 DDR）。
//    ddr_inst 引脚绑定保留（peri.xml 不动），CFG FSM 照常初始化 DDR 硬核。
//////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module top_cam #(
    // ---- raw_2_axi4st 传感器窗口几何（IMX415 1080p60 RAW10 默认）----
    parameter DTYPE           = 6'h2B,       // 像素 DT（RAW10）
    parameter LINE_TOTAL_PIX  = 20'd1944,    // 行总像素（WC=2430 字节）
    parameter LEAD_PIX        = 20'd6,       // 行首丢弃像素
    parameter TRAIL_PIX       = 20'd18,      // 行尾丢弃像素
    parameter LINE_SKIP_FIRST = 20'd11,      // 帧首丢弃 hs 行数
    parameter CAM_LINES       = 16'd1080,    // 有效行数
    parameter GW              = 16'd480,     // 每行组数（= HACT/4）
    // ---- 显示成形几何（须与面板时序一致）----
    parameter HACT            = 16'd1920,
    parameter VACT            = 16'd1080,
    parameter HSP             = 16'd44,
    parameter HBP             = 16'd148,
    parameter HFP             = 16'd88,
    parameter VSP             = 16'd5,
    parameter VBP             = 16'd36,
    parameter VFP             = 16'd4,
    parameter PPC             = 16'd4,
    // ---- disp_timing 行段（pclk 拍口径）----
    // cam0 4K60 板级结构 44/75/18 拍（含 GATE 1 + PREF 2 共 1100）；注意
    // 与上表 HSP/HBP/HFP（像素，喂 pattern_gen 行拍派生）是两套口径——
    // 44/75/18 拍 ≠ 88/296/176 px ÷4。cam1 1080p60 = 11/37/19（CEA
    // 2200px÷4 折算 HFP 22 挤 3 拍给硬编码 GATE+PREF，行和守卫 550 自洽）
    parameter HSP_CLKS        = 16'd44,
    parameter HBP_CLKS        = 16'd75,
    parameter HFP_CLKS        = 16'd18,
    parameter DATA_TYPE       = 6'h1E,       // YUV422 8-bit
    // ---- pattern_gen 图案源（pclk 行节拍配准，见 pattern_gen.v）----
    // 图案行/帧推进与面板同源：pattern_gen 等 line_tick（pixel_clk 每
    // (HSP+HBP+HACT+HFP)/PPC 拍一拍的 CDC 节拍脉冲）推进行。供需同钟同频
    // => 水位零漂移（旧 aclk 计拍与 pclk 37ppm 级独立钟差 = 板级图案慢
    // 滚动，2026-09 根治）
    parameter PATTERN_FRAME_PAD   = 20'd34,     // 帧尾 pad 节拍数
    // ---- 调试：tx_line_buf 入口直注 4K UYVY 棋盘源（shape_pat_gen）----
    parameter DBG_SHAPE_PAT       = 0,
    // ---- v4 显示链帧槽（disp_timing FRAME_SLOTS）----
    // cam0 4K60 = 2250（VSP+VBP+VACT+VFP+PAD=10+72+2160+8+0）；cam1
    // 1080p60 = 1125。pad 由 disp_timing 按槽结构余项自洽推导——独立
    // PAD_L 与标准消隐重复计入 → 2340 槽 57.69Hz（2026-10-21 板级教训）
    parameter DISP_FRAME_SLOTS    = 16'd2250,
    // v4.11（cam-i2c RTL 初始化，doc/cam-i2c-rtl-init-plan.md）：IMX415
    // 分辨率档——cam_i2c_init 内嵌 rom 的 geo 段选择：1=4K（VMAX 4400/
    // HMAX 11254）0=1080p（VMAX 1125/HMAX 5914）。cam0 4K 传 1、cam1
    // 1080p 传 0（top_cam_demo 例化点）
    parameter bit MODE_4K         = 1'b1
    // 2026-10-13 v4：原 ACLK_TX 参数废除——流水线固定跑 tx_pixel_clk。
    // v12（2026-10-14）：ANCHOR_EN/SOF_JUMP_EN 参数随机制退役。
    // v17（2026-10-19）：FIFO_DEPTH 参数随 shape_video_axis 退役删除。
    // v4.10c3m（2026-10-22）：DISP_V4 参数随 DISP_V4=0 分支退役删除
    //（唯一 v4 链）。
) (
    input sys_clk_100m,   
    input sys_clk_200m,
    input sys_clk_100m_rstn,
    input sys_clk_200m_rstn,
    input i_clk_27m,
    input pll_mipi_refclk_locked,
    input tx_pixel_clk,
    input esc_clk,
  
    input dphy_tx_WORD_CLKOUT_HS,
    input dphy_tx_STOPSTATE_CLK,
    input dphy_tx_STOPSTATE_LAN0,
    input dphy_tx_STOPSTATE_LAN1,
    input dphy_tx_STOPSTATE_LAN2,
    input dphy_tx_STOPSTATE_LAN3,
    input dphy_tx_TX_READY_HS_LAN0,
    input dphy_tx_TX_READY_HS_LAN1,
    input dphy_tx_TX_READY_HS_LAN2,
    input dphy_tx_TX_READY_HS_LAN3,
    input dphy_tx_TX_ULPS_ACTIVE_CLK_NOT,
    input dphy_tx_TX_ULPS_ACTIVE_NOT_LAN0,
    input dphy_tx_TX_ULPS_ACTIVE_NOT_LAN1,
    input dphy_tx_TX_ULPS_ACTIVE_NOT_LAN2,
    input dphy_tx_TX_ULPS_ACTIVE_NOT_LAN3,
  
    // MIPI TX peri pins
  
    output dphy_tx_PLL_SSC_EN,
    output dphy_tx_RESET_N,
    output [7:0] dphy_tx_TX_DATA_ESC,
    output dphy_tx_TX_LPDT_ESC,
    output dphy_tx_TX_VALID_ESC,
    output [3:0] dphy_tx_TX_TRIGGER_ESC,
    output dphy_tx_TX_REQUEST_ESC_LAN0,
    output dphy_tx_TX_REQUEST_ESC_LAN1,
    output dphy_tx_TX_REQUEST_ESC_LAN2,
    output dphy_tx_TX_REQUEST_ESC_LAN3,
    output dphy_tx_TX_REQUEST_HS,
    output dphy_tx_TX_REQUEST_HS_LAN0,
    output dphy_tx_TX_REQUEST_HS_LAN1,
    output dphy_tx_TX_REQUEST_HS_LAN2,
    output dphy_tx_TX_REQUEST_HS_LAN3,
    output dphy_tx_TX_SKEW_CAL_HS_LAN0,
    output dphy_tx_TX_SKEW_CAL_HS_LAN1,
    output dphy_tx_TX_SKEW_CAL_HS_LAN2,
    output dphy_tx_TX_SKEW_CAL_HS_LAN3,
    output dphy_tx_TX_ULPS_CLK,
    output dphy_tx_TX_ULPS_ESC_LAN0,
    output dphy_tx_TX_ULPS_ESC_LAN1,
    output dphy_tx_TX_ULPS_ESC_LAN2,
    output dphy_tx_TX_ULPS_ESC_LAN3,
    output dphy_tx_TX_ULPS_EXIT,
    output dphy_tx_TX_ULPS_EXIT_LAN0,
    output dphy_tx_TX_ULPS_EXIT_LAN1,
    output dphy_tx_TX_ULPS_EXIT_LAN2,
    output dphy_tx_TX_ULPS_EXIT_LAN3,
    output [15:0] dphy_tx_TX_DATA_HS_LAN0,
    output [15:0] dphy_tx_TX_DATA_HS_LAN1,
    output [15:0] dphy_tx_TX_DATA_HS_LAN2,
    output [15:0] dphy_tx_TX_DATA_HS_LAN3,
    output dphy_tx_TX_WORD_VALID_HS_LAN0,
    output dphy_tx_TX_WORD_VALID_HS_LAN1,
    output dphy_tx_TX_WORD_VALID_HS_LAN2,
    output dphy_tx_TX_WORD_VALID_HS_LAN3,
  
    // word clock from RX CLK lane (HS byte/word clock, stops when no stream)
    input  dphy_rx_clk_CLKOUT,
    // DPHY control (active-low resets)
    output dphy_rx_RESET_N,
    output dphy_rx_RST0_N,
    // clock lane status (debug observation)
  
    // clock lane ULPS
    input  dphy_rx_ULPS_CLK_ACTIVEN,
    input  dphy_rx_ULPS_CLK_ENTER,
    // data lane escape clocks
  
    input  dphy_rx_ESC_LAN0_CLK,
    input  dphy_rx_ESC_LAN1_CLK,
    input  dphy_rx_ESC_LAN2_CLK,
    input  dphy_rx_ESC_LAN3_CLK,
  
    // LP / escape / control errors
    input  dphy_rx_LINESTATE_LAN0_ERROR,
    input  dphy_rx_LINESTATE_LAN1_ERROR,
    input  dphy_rx_LINESTATE_LAN2_ERROR,
    input  dphy_rx_LINESTATE_LAN3_ERROR,
    input  dphy_rx_ESC_LAN0_ERROR,
    input  dphy_rx_ESC_LAN1_ERROR,
    input  dphy_rx_ESC_LAN2_ERROR,
    input  dphy_rx_ESC_LAN3_ERROR,
    // lane stop state (LP-11 idle indicator)
    input  dphy_rx_STOPSTATE_LAN0,
    input  dphy_rx_STOPSTATE_LAN1,
    input  dphy_rx_STOPSTATE_LAN2,
    input  dphy_rx_STOPSTATE_LAN3,
    // HS receive interface
    input  dphy_rx_HS_LAN0_VALID,
    input  dphy_rx_HS_LAN1_VALID,
    input  dphy_rx_HS_LAN2_VALID,
    input  dphy_rx_HS_LAN3_VALID,
    input  [15:0] dphy_rx_HS_LAN0_DATA,
    input  [15:0] dphy_rx_HS_LAN1_DATA,
    input  [15:0] dphy_rx_HS_LAN2_DATA,
    input  [15:0] dphy_rx_HS_LAN3_DATA,
    input  dphy_rx_HS_LAN0_SKEWCAL,
    input  dphy_rx_HS_LAN1_SKEWCAL,
    input  dphy_rx_HS_LAN2_SKEWCAL,
    input  dphy_rx_HS_LAN3_SKEWCAL,
    input  dphy_rx_HS_LAN0_SYNC,
    input  dphy_rx_HS_LAN1_SYNC,
    input  dphy_rx_HS_LAN2_SYNC,
    input  dphy_rx_HS_LAN3_SYNC,
    input  dphy_rx_HS_LAN0_SOTSYNC_ERROR,
    input  dphy_rx_HS_LAN1_SOTSYNC_ERROR,
    input  dphy_rx_HS_LAN2_SOTSYNC_ERROR,
    input  dphy_rx_HS_LAN3_SOTSYNC_ERROR,
    // data lane ULPS
    input  dphy_rx_ULPS_LAN0_ACTIVEN,
    input  dphy_rx_ULPS_LAN1_ACTIVEN,
    input  dphy_rx_ULPS_LAN2_ACTIVEN,
    input  dphy_rx_ULPS_LAN3_ACTIVEN,
    input  dphy_rx_ULPS_LAN0_ENTER,
    input  dphy_rx_ULPS_LAN1_ENTER,
    input  dphy_rx_ULPS_LAN2_ENTER,
    input  dphy_rx_ULPS_LAN3_ENTER,

    //-------------------------------------------------------------------------
    // riscv_soc
    //   APB slave0 -> apb_cam_ctrl（摄像头链路控制口）
    //-------------------------------------------------------------------------
    input [15:0] apb_paddr,
    input        apb_psel,
    input        apb_penable,
    input        apb_pwrite,
    input  [31:0] apb_pwdata,
    output [31:0] apb_prdata,
    output        apb_pready,
    output        apb_pslverr,

    //-------------------------------------------------------------------------
    // cam_i2c_init（v4.11，doc/cam-i2c-rtl-init-plan.md）：RTL 固化
    // IMX415 配置——上电（或 CSR rerun 触发）后本模块内控传感器使能
    // 时序并经 I2C 走完 142 条寄存器表，init_done 放行数据链
    //（gate_ready/raw_aresetn 两处与项，§4.5）。开漏 pad 三线约定同
    // SoC I2C：pad_o=1 释放/0 驱动低，顶层 oe = ~pad_o
    //-------------------------------------------------------------------------
    output       cam_en,            // 传感器使能（FSM 内控：PWR_OFF 300ms
                                    // 保持 0，之后拉 1 直至完成/失败）
    input        cam_scl_pad_i,     // I2C pad 回读
    output       cam_scl_pad_o,     // 1=释放 0=驱动低
    input        cam_sda_pad_i,
    output       cam_sda_pad_o,
    input        cam_i2c_start,     // 配置启动（上升沿触发；cam0 上电接
                                    // 1'b1 自然释放出沿，cam1 接 cam0 的
                                    // cam_init_done 电平错峰，§4.4）
    output       cam_init_done,     // 全表完成（sticky；观测另走 CSR
                                    // DIAG3@0x0C）

    // DDR 自检状态透传（顶层 ddr_memcheck -> CSR DIAG11；cam1 实例接 0）
    input [31:0] ddr_diag,

    // DDR frame_writer 状态透传（顶层 frame_writer -> CSR DIAG12/13；cam1 接 0）
    input [31:0] ddr_diag2,
    input [31:0] ddr_diag3,
    input [31:0] ddr_diag7,     // fw 输入侧异常：{abandon[15:0], short[7:0], ab_beat[7:0]}

    // DDR 读链路状态透传（顶层 frame_reader -> CSR DIAG14/15；cam1 接 0）
    input [31:0] ddr_diag4,
    input [31:0] ddr_diag5,
    input [31:0] ddr_diag19,    // v4：reader drop/repeat 计数（DIAG19 0x4C 复用）

    // frame_writer 输入流（v4.10 64b 载体：fw 直吃 raw 源零扩展 {24'h0,
    // data[39:0]}，aclk 域；cam1 无源置 0）
    output [63:0] cap_tdata,
    output        cap_tvalid,
    output        cap_tlast,
    output [2:0]  cap_tuser,
    output        fw_rstn,          // aclk 域复位（仅 200M 系统复位，源切换
                                    // 不复位 fw/rd——见下方 fw_rstn 块注释）
    output        fw_flush,         // v4.10c3c 源切换 writer 账本重置宽脉冲
                                    //（1ms；writer 仅 drain 空闲拍执行，AXI
                                    // 零接触，无 2026-10-20 楔死风险）
    input         disp_rst_req_i,   // v4.10c3f tx 域复位请求（pixel_clk 域
                                    // 单拍= reader flush 执行拍透传）：显示
                                    // 链与 reader 停流同步复位

    // frame_reader 回放流注入（v4：reader 换域 pixel_clk——rd_clk/rd_rstn
    // 为回放 CDC 写钟/复位；cam1 无回放源置 0）
    input [63:0] rd_tdata,
    input        rd_tvalid,
    input        rd_tlast,
    input [2:0]  rd_tuser,
    input        rd_clk,
    input        rd_rstn,

    // 行节拍输出（pat_line_tick 的 tx_pixel_clk 域副本；与 shape 直注源
    // 同节拍，disp_timing_gen 退役后仅观测预留）
    output       line_tick_o,

    // 行节拍输出（aclk 域原拍 = pattern_gen 同款，frame_reader 行槽推进用）
    output       pat_tick_aclk,

    // 显示开帧脉冲（shape vback_exit 单拍，pixel_clk 域；v3.4 reader 改
    // 自由跑槽节拍后仅诊断预留，非节奏源）
    output       disp_open_o,

    // v4：disp_timing 行节拍（显示时序唯一发生源，同源 -> frame_reader）
    output       disp_line_tick_o,
    // v4.4：显示行缓冲有整行空间（tx_line_buf 水位 -> reader 发射门节流）
    output       line_room_o,
    // v4.9：显示帧界（disp_timing vsync -> reader 帧授权锚）
    output       disp_sof_o,
    // v4.9：显示断粮预警（tlb < 1 行整 -> reader 帧尾救援授权）
    output       disp_stall_o

);

    wire [1:0]  cp_bayer_phase;
    wire        cp_adaptive;
    wire [7:0]  cp_wb_r, cp_wb_g, cp_wb_b;   // CTRL wb 字段退役占位（v5 wb_axis 退路，悬空）
    // RAW10 域白平衡增益（v5，U4.12，1.0=0x1000，CSR WB_RAW0/1@0x54/0x58）
    wire [15:0] cp_wb_raw_r, cp_wb_raw_g, cp_wb_raw_b;
    wire        cp_pat_en;
    wire [1:0]  cp_pat_sel;
    wire        cp_dbg_sel;
    wire [15:0] cp_pat_line_gap;     // 直注源行间距（拍，CSR CTRL2[15:0]）
    wire [15:0] cp_pat_frame_gap;    // 直注源帧间距（tick，CSR CTRL2[31:16]）
    // 诊断汇总口（CSR paddr 读回；原 DIAG1 CDC FIFO lost/level 随扁平化
    // 退役，恒 0 占位保持寄存器布局）
    wire [31:0] path_diag;
    wire [31:0] path_stats2;             // -> CSR DIAG4（{fw_sof, dms_sol}）
    wire [31:0] path_stats3;             // -> CSR DIAG5（{yuv_v, frm}）
    wire [31:0] path_stats4;             // -> CSR DIAG8（disp_timing {late,under}）
    wire [31:0] path_stats5;             // -> CSR DIAG9（指纹探针 B）
    wire [31:0] path_stats7;             // -> CSR DIAG17（指纹探针 A）
    wire [31:0] path_stats6;             // -> CSR DIAG16（rd 口节拍直证，v4）
    // DIAG18（2026-10-19 绝对窗口版）= {df_win[7:0], live_win[23:0]}：
    // 0.75s 固定窗内 shape 出帧数（60.00Hz=45）与非零内容拍（满速
    // ≈1,555,200）——桥片"无信号"首查点，绝对值免采样窗换算
    wire [31:0] diag18;
    wire [31:0] path_stats21;            // -> CSR DIAG21（{16'h0, raw_wb 饱和拍数}）

    // cam_i2c_init（v4.11）：观测打包 -> CSR DIAG3@0x0C + rerun 触发位
    //（vlog 不容先用后声明，声明前置；例化与沿检测见 u_cam_ctrl 之后）
    wire        i2c_cam_en;
    wire        i2c_init_done, i2c_init_fail, i2c_busy;
    wire [7:0]  i2c_dbg_idx;
    wire [1:0]  i2c_dbg_round;
    wire [3:0]  i2c_dbg_retry;
    wire [1:0]  cp_i2c_rerun;        // CSR DIAG7 槽 sticky 触发位
    wire [31:0] i2c_diag;

    apb_cam_ctrl #(
        .CTRL_RESET(32'h4040_4014)   // wb 字段退役占位 0x40x3(v5 wb_axis 退路), pat_sel=01(橙蓝竖条), pat_en=0(上电摄像头零切换), adaptive=1, phase=0(RGGB)
    ) u_cam_ctrl (
        .pclk        (sys_clk_200m),
        .presetn     (sys_clk_200m_rstn),
        .paddr       (apb_paddr),
        .psel        (apb_psel),
        .penable     (apb_penable),
        .pwrite      (apb_pwrite),
        .pwdata      (apb_pwdata),
        .prdata      (apb_prdata),
        .pready      (apb_pready),
        .pslverr     (apb_pslverr),
        .diag_status (path_diag),
        .diag_status4(path_stats2),
        .diag_status5(path_stats3),
        .diag_status8(path_stats4),
        .diag_status9(path_stats5),
        .diag_status17(path_stats7),
        .diag_status16(path_stats6),             // DIAG16：rd 口节拍直证（v4）
        .diag_status18(diag18),
        .diag_status20(ddr_diag7),
        .diag_status21(path_stats21),            // DIAG21：raw_wb 饱和拍数（v5）
        .diag_status11(ddr_diag),
        .diag_status12(ddr_diag2),
        .diag_status13(ddr_diag3),
        .bayer_phase (cp_bayer_phase),
        .adaptive    (cp_adaptive),
        .wb_r        (cp_wb_r),
        .wb_g        (cp_wb_g),
        .wb_b        (cp_wb_b),
        .wb_r_raw    (cp_wb_raw_r),              // WB_RAW0/1：RAW10 U4.12（v5）
        .wb_g_raw    (cp_wb_raw_g),
        .wb_b_raw    (cp_wb_raw_b),
        .pat_en      (cp_pat_en),
        .pat_sel     (cp_pat_sel),
        .dbg_sel     (cp_dbg_sel),
        .pat_line_gap (cp_pat_line_gap),
        .pat_frame_gap (cp_pat_frame_gap),
        .diag_status14(ddr_diag4),
        .diag_status15(ddr_diag5),
        .diag_status19(ddr_diag19),
        .diag_status3 (i2c_diag),            // DIAG3 复用：cam_i2c 观测
        .cam_i2c_rerun(cp_i2c_rerun)         // DIAG7 复用：rerun sticky
    );

    //-------------------------------------------------------------------------
    // cam_i2c_init（v4.11）：上电/CSR rerun 触发的 IMX415 RTL 配置器。
    //   start = 顶层 cam_i2c_start（cam0 上电 1'b1 释放出沿 / cam1 接
    //   cam0 init_done 错峰）| rerun sticky 位沿（DIAG7@0x1C 写 1）。
    //   同域（pclk = sys_clk_200m）无需异步同步器，打两拍消稳态抖动即可。
    //-------------------------------------------------------------------------
    reg i2c_rerun_q1, i2c_rerun_q2, i2c_rerun_q3;
    always @(posedge sys_clk_200m or negedge sys_clk_200m_rstn)
        if (!sys_clk_200m_rstn) begin
            i2c_rerun_q1 <= 1'b0;
            i2c_rerun_q2 <= 1'b0;
            i2c_rerun_q3 <= 1'b0;
        end else begin
            i2c_rerun_q1 <= cp_i2c_rerun[0];
            i2c_rerun_q2 <= i2c_rerun_q1;
            i2c_rerun_q3 <= i2c_rerun_q2;
        end
    wire i2c_rerun_pe = i2c_rerun_q2 & ~i2c_rerun_q3;

    cam_i2c_init #(
        .SYS_FREQ (200_000_000),    // I2C 50kHz 分频基准（同 P2 仿真实证组）
        .I2C_FREQ (50_000),
        .MODE_4K  (MODE_4K)         // geo 段透传（cam0=4K / cam1=1080p）
    ) u_i2c_init (
        .clk        (sys_clk_200m),
        .rst_n      (sys_clk_200m_rstn),   // 不含 init_done（防自锁死）
        .scl_pad_i  (cam_scl_pad_i),
        .scl_pad_o  (cam_scl_pad_o),
        .sda_pad_i  (cam_sda_pad_i),
        .sda_pad_o  (cam_sda_pad_o),
        .cam_en     (i2c_cam_en),
        .start      (cam_i2c_start | i2c_rerun_pe),
        .init_done  (i2c_init_done),
        .init_fail  (i2c_init_fail),
        .busy       (i2c_busy),
        .dbg_idx    (i2c_dbg_idx),
        .dbg_round  (i2c_dbg_round),
        .dbg_retry  (i2c_dbg_retry)
    );
    assign cam_en        = i2c_cam_en;
    assign cam_init_done = i2c_init_done;
    // DIAG3 观测（v4.11b 加 pad 读回三比特：{en[19], sda_i[18], scl_i[17]}，
    // 板级判别"无 ACK"归因——电源/上拉/输入链 vs 事务层）
    assign i2c_diag      = {12'h0, i2c_cam_en, cam_sda_pad_i, cam_scl_pad_i,
                            i2c_init_fail, i2c_init_done, i2c_busy,
                            i2c_dbg_round, i2c_dbg_retry, i2c_dbg_idx};

    //-------------------------------------------------------------------------
    // MIPI CSI-2 RX：my_csi2_rx 裸 IP 直例化
    //
    //   clk = sys_clk_100m（IP 控制器时钟，AXI tie off）
    //   clk_pixel = sys_clk_200m（像素输出域，>= 178.2MHz UG 下限）
    //   clk_byte_HS = DPHY 恢复字时钟（无流停振，复位保持）
    //   DPHY 复位随 100M 域释放：PLL 锁定前硬核保持复位
    //-------------------------------------------------------------------------
    wire dphy_rx_clk_CLKOUT_rstn;


    reset_ctrl #(.NUM_RST(1), .IN_RST_ACTIVE(1'b0), .OUT_RST_ACTIVE(1'b0)) u_rx_rst_byte (
        .i_arst (sys_clk_200m_rstn), .i_clk (dphy_rx_clk_CLKOUT), .o_srst (dphy_rx_clk_CLKOUT_rstn)
    );

    assign dphy_rx_RESET_N  = sys_clk_100m_rstn;
    assign dphy_rx_RST0_N = sys_clk_100m_rstn;

    // RxValidHS 端口为每 lane 2bit，DPHY 每 lane 只给 1bit，复制扩展
    wire [1:0] rx_valid_ext0, rx_valid_ext1, rx_valid_ext2, rx_valid_ext3;
    assign rx_valid_ext0 = {2{dphy_rx_HS_LAN0_VALID}};
    assign rx_valid_ext1 = {2{dphy_rx_HS_LAN1_VALID}};
    assign rx_valid_ext2 = {2{dphy_rx_HS_LAN2_VALID}};
    assign rx_valid_ext3 = {2{dphy_rx_HS_LAN3_VALID}};

    // 像素输出（clk_pixel = sys_clk_200m 域）
    wire [63:0] rx_pixel_data;
    wire        rx_pixel_valid, rx_pixel_hs, rx_pixel_vs;
    wire [5:0]  rx_pixel_datatype;

    // TX 复位链输出（reset_ctrl 在下方例化，此处提前声明供显示流水线连接）
    wire tx_pixel_clk_rstn, word_clk_arstn, esc_clk_arstn;

    my_csi2_rx u_csi2_rx_cam0 (
        .reset_n         (sys_clk_100m_rstn),
        .clk             (sys_clk_100m),
        .reset_byte_HS_n (dphy_rx_clk_CLKOUT_rstn),
        .clk_byte_HS     (dphy_rx_clk_CLKOUT),
        .reset_pixel_n   (sys_clk_200m_rstn),
        .clk_pixel       (sys_clk_200m),

        .RxClkEsc           ({dphy_rx_ESC_LAN3_CLK,
                              dphy_rx_ESC_LAN2_CLK,
                              dphy_rx_ESC_LAN1_CLK,
                              dphy_rx_ESC_LAN0_CLK}),
        .RxUlpsClkNot       (dphy_rx_ULPS_CLK_ENTER),
        .RxUlpsActiveClkNot (dphy_rx_ULPS_CLK_ACTIVEN),
        .RxErrEsc           ({dphy_rx_ESC_LAN3_ERROR,
                              dphy_rx_ESC_LAN2_ERROR,
                              dphy_rx_ESC_LAN1_ERROR,
                              dphy_rx_ESC_LAN0_ERROR}),
        .RxErrControl       ({dphy_rx_LINESTATE_LAN3_ERROR,
                              dphy_rx_LINESTATE_LAN2_ERROR,
                              dphy_rx_LINESTATE_LAN1_ERROR,
                              dphy_rx_LINESTATE_LAN0_ERROR}),
        .RxErrSotSyncHS     ({dphy_rx_HS_LAN3_SOTSYNC_ERROR,
                              dphy_rx_HS_LAN2_SOTSYNC_ERROR,
                              dphy_rx_HS_LAN1_SOTSYNC_ERROR,
                              dphy_rx_HS_LAN0_SOTSYNC_ERROR}),
        .RxUlpsEsc          ({dphy_rx_ULPS_LAN3_ENTER,
                              dphy_rx_ULPS_LAN2_ENTER,
                              dphy_rx_ULPS_LAN1_ENTER,
                              dphy_rx_ULPS_LAN0_ENTER}),
        .RxUlpsActiveNot    ({dphy_rx_ULPS_LAN3_ACTIVEN,
                              dphy_rx_ULPS_LAN2_ACTIVEN,
                              dphy_rx_ULPS_LAN1_ACTIVEN,
                              dphy_rx_ULPS_LAN0_ACTIVEN}),
        .RxSkewCalHS        ({dphy_rx_HS_LAN3_SKEWCAL,
                              dphy_rx_HS_LAN2_SKEWCAL,
                              dphy_rx_HS_LAN1_SKEWCAL,
                              dphy_rx_HS_LAN0_SKEWCAL}),
        .RxStopState        ({dphy_rx_STOPSTATE_LAN3,
                              dphy_rx_STOPSTATE_LAN2,
                              dphy_rx_STOPSTATE_LAN1,
                              dphy_rx_STOPSTATE_LAN0}),
        .RxSyncHS           ({dphy_rx_HS_LAN3_SYNC,
                              dphy_rx_HS_LAN2_SYNC,
                              dphy_rx_HS_LAN1_SYNC,
                              dphy_rx_HS_LAN0_SYNC}),
        .RxDataHS0          (dphy_rx_HS_LAN0_DATA),
        .RxDataHS1          (dphy_rx_HS_LAN1_DATA),
        .RxDataHS2          (dphy_rx_HS_LAN2_DATA),
        .RxDataHS3          (dphy_rx_HS_LAN3_DATA),
        .RxDataHS4          (),
        .RxDataHS5          (),
        .RxDataHS6          (),
        .RxDataHS7          (),
        .RxValidHS0         (rx_valid_ext0),
        .RxValidHS1         (rx_valid_ext1),
        .RxValidHS2         (rx_valid_ext2),
        .RxValidHS3         (rx_valid_ext3),
        .RxValidHS4         (),
        .RxValidHS5         (),
        .RxValidHS6         (),
        .RxValidHS7         (),

        // AXI-Lite CSR 不接入（tie off，同 csi_rx_top 已验证用法）
        .axi_clk     (sys_clk_100m),
        .axi_reset_n (sys_clk_100m_rstn),
        .axi_awaddr  (6'b0),
        .axi_awvalid (1'b0),
        .axi_awready (),
        .axi_wdata   (32'b0),
        .axi_wvalid  (1'b0),
        .axi_wready  (),
        .axi_bvalid  (),
        .axi_bready  (1'b1),
        .axi_araddr  (6'b0),
        .axi_arvalid (1'b0),
        .axi_arready (),
        .axi_rdata   (),
        .axi_rvalid  (),
        .axi_rready  (1'b1),
        .irq         (),

        // Video Interface -> 显示链 raw_2_axi4st（同域直连，in_dtype 取 pixel 域元数据）
        .hsync_vc1  (), .hsync_vc2  (), .hsync_vc3  (), .hsync_vc4  (),
        .hsync_vc5  (), .hsync_vc6  (), .hsync_vc7  (), .hsync_vc8  (),
        .hsync_vc9  (), .hsync_vc10 (), .hsync_vc11 (), .hsync_vc12 (),
        .hsync_vc13 (), .hsync_vc14 (), .hsync_vc15 (),
        .vsync_vc1  (), .vsync_vc2  (), .vsync_vc3  (), .vsync_vc4  (),
        .vsync_vc5  (), .vsync_vc6  (), .vsync_vc7  (), .vsync_vc8  (),
        .vsync_vc9  (), .vsync_vc10 (), .vsync_vc11 (), .vsync_vc12 (),
        .vsync_vc13 (), .vsync_vc14 (), .vsync_vc15 (),
        .hsync_vc0        (rx_pixel_hs),
        .vsync_vc0        (rx_pixel_vs),
        .pixel_data       (rx_pixel_data),
        .pixel_data_valid (rx_pixel_valid),
        .pixel_datatype   (rx_pixel_datatype),
        .pixel_per_clk    (),
        .datatype (),
        .shortpkt_data_field (),
        .word_count (),
        .vcx(),
        .vc(),
        .pixel_line_num   (),
        .pixel_frame_num  (),
        .pixel_wordcount  (),
        .pixel_vc         (),
        .pixel_vcx        ()

    );

    //-------------------------------------------------------------------------
    // pattern_gen 行节拍发生器：pixel_clk 计 550 拍/行（(HSP+HBP+HACT+HFP)
    // /PPC）翻转触发器，2FF CDC 进 aclk 域取沿 => 每面板行一个 aclk 单拍
    // 脉冲。pattern_gen 行推进改吃此节拍，与面板行/帧节奏同钟同频（根治
    // 图案慢滚动，见 pattern_gen.v 头注释）
    //-------------------------------------------------------------------------
    localparam int PAT_LINE_TICK_PCLK = (HSP + HBP + HACT + HFP) / PPC;  // 1080p=550 / 4K=1100
    reg [10:0] pat_tick_cnt;                 // 1100 拍需 11bit
    reg        pat_tick_tgl;
    always @(posedge tx_pixel_clk or negedge tx_pixel_clk_rstn) begin
        if (!tx_pixel_clk_rstn) begin
            pat_tick_cnt <= 11'd0;
            pat_tick_tgl <= 1'b0;
        end else if (pat_tick_cnt == PAT_LINE_TICK_PCLK - 11'd1) begin
            pat_tick_cnt <= 11'd0;
            pat_tick_tgl <= ~pat_tick_tgl;
        end else begin
            pat_tick_cnt <= pat_tick_cnt + 11'd1;
        end
    end
    reg [2:0] pat_tick_sync;
    always @(posedge sys_clk_200m or negedge sys_clk_200m_rstn)
        if (!sys_clk_200m_rstn) pat_tick_sync <= 3'b000;
        else                 pat_tick_sync <= {pat_tick_sync[1:0], pat_tick_tgl};
    wire pat_line_tick = pat_tick_sync[1] ^ pat_tick_sync[2];

    //-------------------------------------------------------------------------
    // pattern_gen：自诊断图案拍流（raw_2_axi4st 之前注入，传感器协议同构）。
    // CSR CTRL[3] pat_en=1 时经下方 mux 替换 my_csi2_rx 输出；行中切换
    // 最多撕裂 1 行（raw 限定行首拍自愈），固件在帧边界切换即可。
    //-------------------------------------------------------------------------
    wire [39:0] pat_data;
    wire        pat_valid, pat_vs, pat_hs;
    wire [5:0]  pat_dtype;

    pattern_gen #(
        .DUMMY_LINES (LINE_SKIP_FIRST),
        .LIVE_LINES  (CAM_LINES),
        .LINE_BEATS  (LINE_TOTAL_PIX[19:2]),
        .FRAME_PAD   (PATTERN_FRAME_PAD),
        .DT_RAW10    (DTYPE)
    ) u_pat_gen (
        .aclk      (sys_clk_200m),
        .aresetn   (sys_clk_200m_rstn),
        .line_tick (pat_line_tick),
        .pat_sel   (cp_pat_sel),
        .pat_data  (pat_data),
        .pat_valid (pat_valid),
        .pat_dtype (pat_dtype),
        .pat_hs    (pat_hs),
        .pat_vs    (pat_vs)
    );

    // 前向声明（vlog 不容先用后声明）：生效拍时序链信号，赋值见下方
    // "v4.10c3c 生效拍时序链"块
    wire        raw_rst_trig;        // 生效拍触发（= sw_eff_r）
    wire        gate_ready;          // 开门条件（= fw_flush_done & i2c_init_done，赋值见 flush 链尾）
    reg  [17:0] fw_fl_cnt;
    reg         fw_flush_act, fw_flush_done;

    // ---- 源切换软复位（2026-09 板级修复）：pat_en / dbg_sel 变化沿 =>
    //      显示链 ----
    // 两域脉冲复位。切换瞬间 shape FIFO 残留旧源尾字（非整行/帧对齐），
    // 显示下一帧从残字起读 => 画面垂直偏移 N 行（N=残字/480 行）。软复位
    // 语义：写侧 drop_frame=1 重新等新源 SOF、FIFO 读写指针清零（残字清
    // 光）、读侧 v 回 Vsync 重启帧 => 切换后从新源帧首垂直对齐；代价是切
    // 换瞬间失步/黑一帧（源切换本就撕裂，固件切完即恢复）。aclk 与
    // tx_pixel_clk 同为 sys_clk_200m（u_csi2_rx clk_pixel 同源），单域展宽
    // 脉冲同时复位两侧；pattern_gen/shape_pat_gen 不复位（自由跑，shape
    // 等 SOF 接入；shape_pat_gen 的 aresetn 随显示链软复位一起清）。
    reg [1:0] sw_src_q1, sw_src_q2, sw_src_q3;   // {dbg_sel, pat_en}
    always @(posedge sys_clk_200m or negedge sys_clk_200m_rstn)
        if (!sys_clk_200m_rstn) begin
            // 对齐 CTRL_RESET=B4EB_C814 默认 {dbg=0, pat_en=0}（v4.10c 起
            // 上电摄像头零切换；v4.11 勘正——旧注释/复位值 pat_en=1 是
            // CTRL_RESET 改 pat_en=0 前的遗留，sw_src_chg 无消费者故无害）
            sw_src_q1 <= 2'b00; sw_src_q2 <= 2'b00; sw_src_q3 <= 2'b00;
        end else begin
            sw_src_q1 <= {cp_dbg_sel, cp_pat_en};
            sw_src_q2 <= sw_src_q1;
            sw_src_q3 <= sw_src_q2;
        end
    wire sw_src_chg = (sw_src_q3 != sw_src_q2);
    reg [7:0] sw_rst_cnt;
    reg       sw_rst_act;
    // v4.10c3c：触发源从 sw_src_chg（CSR 写即触发，帧中复位 raw 悬空
    // writer 收流）改为 raw_rst_trig（帧界生效拍，VFP 间隙复位无害）
    always @(posedge sys_clk_200m or negedge sys_clk_200m_rstn) begin
        if (!sys_clk_200m_rstn) begin
            sw_rst_cnt <= 8'd0;
            sw_rst_act <= 1'b0;
        end else if (raw_rst_trig) begin
            sw_rst_cnt <= 8'd200;               // ~1us 复位脉冲
            sw_rst_act <= 1'b1;
        end else if (sw_rst_act) begin
            sw_rst_cnt <= sw_rst_cnt - 8'd1;
            sw_rst_act <= (sw_rst_cnt != 8'd1);
        end
    end
    wire sw_rstn = ~sw_rst_act;                 // 低有效，正常 1

    // tx 域复位（v4.10c3f 重定义触发时机）：reader flush 执行拍（m_axis
    // 断流同拍）触发——148.5M 显示链（demosaic/wb/rgb2yuv/shape/tlb/
    // disp_timing）与 reader 停流同步复位。【c3d 板测教训】生效拍复位
    // tx 域会留下 1.25ms 窗口：复位完的显示链被 reader 旧重放流（无帧
    // 头锚）继续灌 => demosaic 行窗二次污染 => 切图案黑屏数秒后撕裂。
    // disp_rst_req_i 与本逻辑同在 pixel_clk 域（reader flush_fire 单拍
    // 透传），直连展宽 ~1µs，无需同步器。
    reg [8:0] tx_rst_cnt;
    reg       tx_rst_act;
    always @(posedge tx_pixel_clk or negedge tx_pixel_clk_rstn)
        if (!tx_pixel_clk_rstn) begin
            tx_rst_cnt <= 9'd0;
            // 复位值 0（c3f）：cam1 无 flush 链路（fire 恒 0）若上电锁
            // 复位则显示链永死；cam0 的干净性由 boot 引导（tx_pixel_clk
            // 复位链 + flush 窗内 fire 复位）双重保证，无需上电锁存
            tx_rst_act <= 1'b0;
        end else if (disp_rst_req_i) begin
            tx_rst_cnt <= 9'd200;            // ~1.35us @148.5MHz
            tx_rst_act <= 1'b1;
        end else if (tx_rst_cnt != 9'd0) begin
            tx_rst_cnt <= tx_rst_cnt - 9'd1;
            tx_rst_act <= (tx_rst_cnt != 9'd1);
        end
    wire sw_rstn_tx = ~tx_rst_act;

    // frame_writer/reader 复位（v2 单钟 aclk 域）= 仅 200M 系统复位。
    // 【2026-10-20 板级根因】此处曾含 & sw_rstn，实测 'p'(图案源)→'c'(相
    //   机) 100% 楔死 DDR 写通道：sw_rst 的 1µs 低脉冲落在 frame_writer
    //   活跃 AXI 写突发中间 => 主口 awvalid/wvalid/wlast 从突发中间被掐
    //   断，而 DDR 硬核不在本复位域（ddr_inst_ARSTN 仅在 CFG 完成时释放，
    //   其后从不复位）=> 控制器 port0 残留半截写事务，后续写病态爬行
    //   （实测 ~8 行/帧）=> writer 8 槽描述队列涨满（q_full）=> 整帧或
    //   全无纪律判坏帧、关帧不翻 par => frame_req（=par 沿）永不发生 =>
    //   reader 零请求全链饿死。板级特征：fw ln=7 冻结、ovf/bad=frm、
    //   rd req=0 st=0、DIAG11 err=0（控制器无协议错，只是被掐）。反向
    //   'p' 能恢复是因为楔死态下 AXI 总线已静默数秒，第二次复位落点干
    //   净——非对称性即"切在忙时必楔"的直接证据。
    // 修复：writer/reader 不参与源切换软复位。v2 writer 的整帧或全无 +
    //   帧中 sof 坏帧重启纪律本就为源中切换设计（坏帧不发布，reader 继
    //   续读上一完整帧）；raw 在 sw_rst 期间 line_no=0 < 行窗起点零泄漏，
    //   恢复后首行必带 sof => writer 走帧中 sof 路径干净重启。显示链
    //   双域复位照旧（切换干净度不受影响）。代价：fw/rd 诊断计数
    //   器不再随切换清零（固件本就按增量判读）。
    assign fw_rstn = sys_clk_200m_rstn;
    assign fw_flush = fw_flush_act;

    // shape 开帧脉冲（v4.10b：声明前移——disp_open_o 观测口在此前向引用，
    // vlog 不认 wire 前向引用）
    (* syn_keep = "true" *)wire tx_frame_open;

    //-------------------------------------------------------------------------
    // pat_line_tick 的 tx_pixel_clk 域副本（直注源/行节拍在 TX 域消费；
    // pattern_gen 仍在 200M 域用原 pat_line_tick）
    reg [2:0] pat_tick_sync_tx;
    always @(posedge tx_pixel_clk or negedge tx_pixel_clk_rstn)
        if (!tx_pixel_clk_rstn) pat_tick_sync_tx <= 3'b000;
        else                    pat_tick_sync_tx <= {pat_tick_sync_tx[1:0], pat_tick_tgl};
    wire pat_line_tick_tx = pat_tick_sync_tx[1] ^ pat_tick_sync_tx[2];
    assign line_tick_o = pat_line_tick_tx;   // 顶层 disp 链路行槽（观测预留）
    assign pat_tick_aclk = pat_line_tick;    // frame_reader 行槽（aclk 原拍）
    assign disp_open_o  = tx_frame_open;     // 显示开帧脉冲（reader 节拍门）

    // 源输入 mux：pat_en=1 图案源 / 0 传感器直通
    wire [39:0] path_in_data;
    wire        path_in_valid, path_in_vs, path_in_hs;
    wire [5:0]  path_in_dtype;

    // ---- 帧界对齐源切换（v4.10b）----
    // cp_pat_en 直改 mux 曾在帧中插入新流：writer 走"帧中 sof"路径 →
    // DDR 帧内新旧内容混合 → TX 奇异帧 → 桥片拒锁（板测"切来切去死
    // 桥片"实锤，仅重上下电可恢复）。改为请求挂起：等当前源 vs 下降沿
    //（帧尾 VFP 间隙，旧帧完整交付）再生效——新流从帧界起步，writer
    // 在 pad 期按 sol/sof 干净记账。pending 超时 2 帧（33ms）强制生效
    //（源断流防护：如摄像头断流切图案时 rx_vs 恒 0 无下降沿）。
    //
    // ---- 切入门（v4.10c3 板测修正）----
    // 切换生效时新源流（尤其恒跑的 pattern_gen）正处行中间——raw_2_axi4st
    // 的 vs/hs 帧行账本与流相位差，无法自愈 → 持续斜卷/坏帧（板测'p'切
    // 图案斜卷+黑屏实锤）。切入门：生效拍关闭数据流，等新源 vs 上升沿
    //（帧头）才放行——raw_2_axi4st 看到的流永远从干净帧头起步，与传感
    // 器上电出流同构。新源断流时 gate 恒 0 → 显示冻旧帧（reader rpt），
    // 即断流防护的自然延伸。翻转拍与 vs 沿同拍时保守优先 gate=0（最多
    // 多等一帧）。
    reg         pat_sel_eff;
    reg         pat_vs_d, rx_vs_d;
    reg         sw_gate;
    reg [25:0]  sw_to_cnt;
    reg         sw_eff_r;        // 生效拍单拍脉冲（驱动 raw 复位与 flush 时序）
    reg         sw_ever_eff;     // 已发生过生效（诊断保留，gate_ready 不再用）
    reg         boot_done;       // v4.10c3d 上电引导：首个源 VFP 触发一次
                                 // sw_rst+flush 链——c3 起固件首写 CSR 的
                                 // 隐式 camera_path 复位随帧界生效制失效，
                                 // 上电杂散流污染 demosaic/shape 卡死数分
                                 // 钟不自愈（板测实锤）；引导复位对齐
                                 // "干净帧头前路径必须复位"纪律
    wire        sw_pending  = (cp_pat_en != pat_sel_eff);
    wire        cur_vs_fall = pat_sel_eff ? (pat_vs_d & ~pat_vs)
                                          : (rx_vs_d & ~rx_pixel_vs);
    wire        new_vs_rise = pat_sel_eff ? (~pat_vs_d & pat_vs)
                                          : (~rx_vs_d & rx_pixel_vs);
    always @(posedge sys_clk_200m or negedge sys_clk_200m_rstn) begin
        if (!sys_clk_200m_rstn) begin
            pat_vs_d   <= 1'b0;
            rx_vs_d    <= 1'b0;
            pat_sel_eff<= 1'b0;
            sw_gate    <= 1'b0;          // 上电等引导完成+首个 vs 帧头
            sw_to_cnt  <= 26'd0;
            sw_eff_r   <= 1'b0;
            sw_ever_eff<= 1'b0;
            boot_done  <= 1'b0;
        end else begin
            pat_vs_d <= pat_vs;
            rx_vs_d  <= rx_pixel_vs;
            sw_eff_r  <= 1'b0;
            if (new_vs_rise && !(sw_pending && cur_vs_fall) && gate_ready)
                sw_gate <= 1'b1;         // 新源帧头且 flush 完成：放行
            else if (sw_pending && cur_vs_fall) begin
                pat_sel_eff <= cp_pat_en;
                sw_gate     <= 1'b0;     // 生效拍：关门等新源帧头
                sw_to_cnt   <= 26'd0;
                sw_eff_r    <= 1'b1;     // 触发 raw 复位 + flush 时序
                sw_ever_eff <= 1'b1;
            end else if (!boot_done && cur_vs_fall) begin
                boot_done   <= 1'b1;     // 上电引导：VFP 复位接收路径，
                sw_gate     <= 1'b0;     // 之后与切换共用 flush 链+开门
                sw_eff_r    <= 1'b1;     // 时序（flush_done 后才允许开门）
                sw_ever_eff <= 1'b1;
            end else if (sw_pending) begin
                sw_to_cnt <= sw_to_cnt + 26'd1;
                // 26'd6_700_000 @200MHz = 33.5ms = 2 帧
                if (&sw_to_cnt) begin
                    pat_sel_eff <= cp_pat_en;
                    sw_gate     <= 1'b0; // 超时强制：同样关门等帧头
                    sw_to_cnt   <= 26'd0;
                    sw_eff_r    <= 1'b1;
                    sw_ever_eff <= 1'b1;
                end
            end else
                sw_to_cnt <= 26'd0;
        end
    end

    // ---- v4.10c3c 生效拍时序链：raw 复位 -> writer flush -> gate 开门 ----
    // 【2026-10-20 板级根因修正】raw 复位（sw_rst_act）从"CSR 写即触发"
    // 改为"帧界生效拍触发"——CSR 写时刻在帧中，旧流正在进 raw，此刻复
    // 位 raw 会让 writer 收到悬空流（行窗卡死/半行未提交）→ 切回后黑
    // 屏（v4.10c3b 板测实锤）。生效拍=旧源帧尾 VFP 间隙，复位无害。
    //
    // flush：生效后延迟 1.25ms（覆盖 1µs raw 复位 + writer drain 排空）
    // 发 1ms 宽脉冲——writer 仅在 drain 空闲拍执行账本清（AXI 零接触，
    // 无楔死风险）。gate 开门等 flush 完成后再等新源帧头。
    assign raw_rst_trig = sw_eff_r;           // 生效拍触发（替代旧 sw_src_chg）
    always @(posedge sys_clk_200m or negedge sys_clk_200m_rstn) begin
        if (!sys_clk_200m_rstn) begin
            fw_fl_cnt     <= 18'd0;
            fw_flush_act  <= 1'b0;
            fw_flush_done <= 1'b0;
        end else if (sw_eff_r) begin
            fw_fl_cnt     <= 18'd250_000; // 1.25ms @200MHz
            fw_flush_act  <= 1'b0;
            fw_flush_done <= 1'b0;
        end else if (fw_flush_act) begin
            // flush 宽脉冲期：倒计 200_000 拍 = 1ms 后收脉冲
            if (fw_fl_cnt == 18'd0) begin
                fw_flush_act  <= 1'b0;
                fw_flush_done <= 1'b1;
            end else
                fw_fl_cnt <= fw_fl_cnt - 18'd1;
        end else if (fw_fl_cnt != 18'd0) begin
            fw_fl_cnt <= fw_fl_cnt - 18'd1;
            if (fw_fl_cnt == 18'd1) begin
                fw_flush_act <= 1'b1;     // 延迟到期：1ms 宽 flush 启动
                fw_fl_cnt    <= 18'd200_000;
            end
        end
    end
    // 开门只认 flush 完成 + cam_i2c_init 全表完成（v4.11）：上电引导与
    // 每次切换都必须走完"raw 复位 + writer flush"链，且传感器完成 142
    // 条配置后才可能有流——两与项杜绝带脏账本/污染路径/无源空转接流
    assign gate_ready = fw_flush_done & i2c_init_done;

    assign path_in_data  = pat_sel_eff ? pat_data        : rx_pixel_data[39:0];
    // 三信号全门（v4.10c3b）：valid/hs/vs 一并门断——只门 valid 会让
    // raw_2_axi4st 在关门期收到"有 hs 无数据"的短行（DIAG20 short 路径）；
    // 全断等效传感器重新插拔，gate 重开后从 vs 上升沿全新开始。vs/hs 沿
    // 检测（new_vs_rise）用 mux 前原始信号，不受门影响。
    assign path_in_valid = sw_gate && (pat_sel_eff ? pat_valid : rx_pixel_valid);
    assign path_in_vs    = sw_gate && (pat_sel_eff ? pat_vs     : rx_pixel_vs);
    assign path_in_hs    = sw_gate && (pat_sel_eff ? pat_hs     : rx_pixel_hs);
    assign path_in_dtype = pat_sel_eff ? DTYPE           : rx_pixel_datatype;

    //-------------------------------------------------------------------------
    // CDC 位置（2026-10-13 v4 架构，历史）：异步 FIFO 曾置于 raw 之后，
    // 根因：my_csi2_rx Generic Frame Mode 的 hsync 是与 valid 重合的电平
    // （IP 手册 Figure 2），入口 FIFO 丢空拍压缩会把行间隙抹掉 => hs 电
    // 平整帧连成一线 => raw 行计数不推进（板级 cam0 dms=0 实锤）。raw 在
    // 源域完成协议清洗后输出自定界 AXIS（tuser 行界在包里）。
    // 【v4.10c3m】reader 换域（rd_clk = pixel_clk）+ DISP_V4 唯一化后，
    // 回放 CDC 与 DIAG1（lost/level）退役，path_diag 恒 0 占位。
    //-------------------------------------------------------------------------
    assign path_diag = 32'h0;

    //-------------------------------------------------------------------------
    // 显示流水线（v4.10c3m 扁平化：原 camera_path DISP_V4=1 网表直移本文件）
    //   raw 域（sys_clk_200m）：raw_2_axi4st（与 CSI2RX 同域，v2 验证形态）
    //   pixel_clk 域（tx_pixel_clk）：回放直通 -> raw_wb（RAW10 增益，v5）
    //     -> demosaic -> rgb10_to_rgb8 -> rgb2yuv
    //     ->（shape_pat_gen 直注 mux）-> tx_line_buf -> disp_timing -> TX
    //   回放流 rd_t* 与 pixel_clk 同域（v4 Phase 4 reader 换域），直通无
    //   CDC。复位两级分开：raw_aresetn（raw 域，含源切换帧界复位）/
    //   pixel_rst_n（流水线域，TX 复位链 & 源切换软复位，须先于数据释放）。
    //-------------------------------------------------------------------------
    // raw_aresetn 含 i2c_init_done（v4.11）：传感器未配置完成前 raw 链
    //（raw_2_axi4st 起）保持复位——上电引导机制保证 flush 链不会提前跑
    //（init_done=0 时无流 -> 无 vs 沿 -> boot 不触发），此处再兜一层：
    // 即使杂散毛刺进 raw 也不污染 demosaic。cam_i2c_init 自身复位不含
    // 该与项（sys_clk_200m_rstn，防自锁死）。
    wire raw_aresetn = sys_clk_200m_rstn & sw_rstn & i2c_init_done;
    wire pixel_rst_n = tx_pixel_clk_rstn & sw_rstn_tx;

    // TX Video Interface 连线（disp_timing -> my_csi2_tx）
    (* syn_keep = "true" *)wire        tx_vsync, tx_hsync, tx_pixel_valid;
    (* syn_keep = "true" *)wire [63:0] tx_pixel_data;
    (* syn_keep = "true" *)wire [5:0]  tx_datatype;
    (* syn_keep = "true" *)wire [15:0] tx_haddr, tx_line_num, tx_frame_num;

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
    (* syn_keep = "true" *)wire [2:0]   yuv_tuser;

    //--------------------------------------------------------------------
    // 1. raw_2_axi4st：传感器拍流 -> AXIS-40（源域协议清洗：DT 门控/
    //    LEAD/TRAIL 裁剪/行窗口筛选，输出自定界 AXIS——行界在包里）
    //--------------------------------------------------------------------
    raw_2_axi4st #(
        .DTYPE           (DTYPE),
        .LINE_TOTAL_PIX  (LINE_TOTAL_PIX),
        .LEAD_PIX        (LEAD_PIX),
        .TRAIL_PIX       (TRAIL_PIX),
        .LINE_SKIP_FIRST (LINE_SKIP_FIRST),
        .LINES           (CAM_LINES)
    ) u_raw (
        .aclk         (sys_clk_200m),
        .aresetn      (raw_aresetn),
        .in_data      (path_in_data),
        .in_valid     (path_in_valid),
        .in_vs        (path_in_vs),
        .in_hs        (path_in_hs),
        .in_dtype     (path_in_dtype),
        .m_axis_tdata (raw_tdata),
        .m_axis_tvalid(raw_tvalid),
        .m_axis_tlast (raw_tlast),
        .m_axis_tuser (raw_tuser)
    );

    // frame_writer 输入（v4.10 64b 载体）：raw 40b 源零扩展直连（回放态
    // 仍持续写活流，reader 才有新帧可翻；直注图案态 writer 写的是图案流）
    assign cap_tdata  = {24'h0, raw_tdata};
    assign cap_tvalid = raw_tvalid;
    assign cap_tlast  = raw_tlast;
    assign cap_tuser  = raw_tuser;

    //--------------------------------------------------------------------
    // 2. 回放流 -> raw_wb_axis（v5：RAW10 域白平衡，U4.12 逐通道增益，
    //    doc/wb_design_spec.md）-> demosaic。白平衡自 demosaic 之后的
    //    wb_axis 前移至此；cdc_valid 为 v3 遗留名 = raw_wb 口 tvalid。
    //    demosaic 只吃 RAW10 段：64b 载体低 40b 连线层切片后进增益。
    //    pat_en=1（图案源）bypass unity 位精确直通（图案按显示幅度编码）。
    //--------------------------------------------------------------------
    wire [39:0] rd_raw40    = rd_tdata[39:0];
    wire [39:0] dms_in_tdata;
    wire [2:0]  dms_in_tuser;
    wire        dms_in_tlast;
    wire        cdc_valid;
    wire [15:0] raw_wb_sat;

    raw_wb_axis u_raw_wb (
        .aclk         (tx_pixel_clk),
        .aresetn      (pixel_rst_n),
        .s_axis_tdata (rd_raw40),
        .s_axis_tvalid(rd_tvalid),
        .s_axis_tlast (rd_tlast),
        .s_axis_tuser (rd_tuser),
        .bayer_phase  (cp_bayer_phase),
        .wb_r         (cp_wb_raw_r),
        .wb_g         (cp_wb_raw_g),
        .wb_b         (cp_wb_raw_b),
        .pat_bypass   (cp_pat_en),
        .m_axis_tdata (dms_in_tdata),
        .m_axis_tvalid(cdc_valid),
        .m_axis_tlast (dms_in_tlast),
        .m_axis_tuser (dms_in_tuser),
        .dbg_sat      (raw_wb_sat)
    );
    assign path_stats21 = {16'h0, raw_wb_sat};   // DIAG21：饱和拍计数（16b 自由回绕）

    // 自由跑速率计数（DIAG4，16bit 回绕；判读：fw_sof_free 增量 +0/+1 为
    // 断流、+60/s 为满速；dms_sol_free 满速 129.6k 行/s，16bit 圈增量
    // 1424±漂移，2026-10-19 mod-65536 判读结论）
    reg [15:0] dms_sol_free, fw_sof_free;
    reg [15:0] yuv_v_cnt;
    always @(posedge sys_clk_200m or negedge raw_aresetn) begin
        if (!raw_aresetn)
            fw_sof_free <= 16'd0;
        else if (raw_tvalid && raw_tuser[0])
            fw_sof_free <= fw_sof_free + 16'd1;
    end
    always @(posedge tx_pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            dms_sol_free <= 16'd0;
            yuv_v_cnt    <= 16'd0;
        end else begin
            if (dms_tvalid && dms_tuser[1]) dms_sol_free <= dms_sol_free + 16'd1;
            if (yuv_tvalid) yuv_v_cnt <= yuv_v_cnt + 16'd1;
        end
    end
    assign path_stats2 = {fw_sof_free, dms_sol_free};

    // 显示出帧计数（pixel_clk 域）：frm>0 = 显示链/TX 已发帧
    reg [15:0] frm_cnt;
    reg        vsync_d;
    always @(posedge tx_pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            vsync_d <= 1'b0;
            frm_cnt <= 16'd0;
        end else begin
            vsync_d <= tx_vsync;
            if (tx_vsync & ~vsync_d) frm_cnt <= frm_cnt + 16'd1;
        end
    end
    assign path_stats3 = {yuv_v_cnt, frm_cnt};

    //--------------------------------------------------------------------
    // v4.10c3j 指纹探针 A（writer 入口 = raw_t*，raw 域）：
    // 定位"行账本全绿但显示带内容错位"的帧内内容位移 δ。
    // 指纹 = 每行 sol 首拍的 tdata[39:30]（诊断图案 4 像素同值 flat，
    // lead/trail 裁剪不影响行中任意拍的取值）。
    // 比对：行 0（sof∧sol）仅锚定记录；后续行 fp ≠ fp_prev+1 (mod 1024)
    //   → err++ 并锁存 delta = fp - (fp_prev+1)（mod 1024）。
    //   delta 判读（底部闪区、内容自更早行来）：768=早移 256 行，
    //   512=早移 512 行，256=早移 768 行（或晚移 256）。
    // 判读：err=0 且 delta 恒 → writer 入口干净，错位在 DDR 及以后段
    //   （看探针 B/DIAG9）；err 随帧增长 → 源→writer 入口段错位
    //   （csi2_rx/raw_2_axi4st/pattern_gen 段）。仅在诊断图案 pat_sel=2
    //   模式有效；摄像头自然图像无指纹会误报（判读时忽略）。
    //--------------------------------------------------------------------
    reg  [9:0]  fpA_prev, fpA_delta;
    reg  [15:0] fpA_err;
    reg         fpA_v;
    always @(posedge sys_clk_200m or negedge raw_aresetn) begin
        if (!raw_aresetn) begin
            fpA_prev  <= 10'd0;
            fpA_delta <= 10'd0;
            fpA_err   <= 16'd0;
            fpA_v     <= 1'b0;
        end else if (raw_tvalid && raw_tuser[1]) begin        // 行首拍
            fpA_prev <= raw_tdata[39:30];
            fpA_v    <= 1'b1;
            if (!raw_tuser[0] && fpA_v &&
                (raw_tdata[39:30] != (fpA_prev + 10'd1))) begin
                fpA_err   <= fpA_err + 16'd1;
                fpA_delta <= raw_tdata[39:30] - (fpA_prev + 10'd1);
            end
        end
    end
    // DIAG17=0x44：探针 A 读数 = {err[15:0], delta[9:0], v, 5'h0}
    //（v=1 已锚定；err=0 且 v=1 = 全程指纹连续）
    assign path_stats7 = {fpA_err, fpA_delta, fpA_v, 5'h0};

    //--------------------------------------------------------------------
    // v4.10c3j 指纹探针 B（demosaic 入口 = dms_in_t*/cdc_valid，
    // pixel_clk 域 = reader 回放流直通）。算法同探针 A。
    // 四象限判读（诊断图案模式）：
    //   A 红（err 增长）           → 源→writer 入口段错位
    //   A 绿、B 红（err 增长）     → writer→DDR→reader 段错位（DDR 真
    //                                硬件嫌疑；tb P4C 该段内容级已验绿，
    //                                板级复现即 DDR 控制器/引脚级问题）
    //   A、B 全绿                  → demosaic 及以后（ISP 段）
    //--------------------------------------------------------------------
    reg  [9:0]  fpB_prev, fpB_delta;
    reg  [15:0] fpB_err;
    reg         fpB_v;
    always @(posedge tx_pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            fpB_prev  <= 10'd0;
            fpB_delta <= 10'd0;
            fpB_err   <= 16'd0;
            fpB_v     <= 1'b0;
        end else if (cdc_valid && dms_in_tuser[1]) begin      // 行首拍
            fpB_prev <= dms_in_tdata[39:30];
            fpB_v    <= 1'b1;
            if (!dms_in_tuser[0] && fpB_v &&
                (dms_in_tdata[39:30] != (fpB_prev + 10'd1))) begin
                fpB_err   <= fpB_err + 16'd1;
                fpB_delta <= dms_in_tdata[39:30] - (fpB_prev + 10'd1);
            end
        end
    end
    assign path_stats5 = {fpB_err, fpB_delta, fpB_v, 5'h0};
                                            // DIAG9：探针 B 读数（格式同 DIAG17）

    //--------------------------------------------------------------------
    // DIAG16（0x40）：回放口节拍直证——双钟对照定位：
    //   beat_rd = rd_clk 域直数（rd_clk 断则恒 0）
    //   beat_px = pixel_clk 域直数（rd_t* 与 pixel_clk 同域，rd_clk 断也
    //             应滚动；恒 0 = rd_tvalid 本身未到达显示链）
    //--------------------------------------------------------------------
    reg [15:0] rd16_sol, rd16_beat;
    reg [15:0] rd16_beat_px;
    always @(posedge rd_clk or negedge rd_rstn) begin
        if (!rd_rstn) begin
            rd16_sol  <= 16'd0;
            rd16_beat <= 16'd0;
        end else if (rd_tvalid) begin
            rd16_beat <= rd16_beat + 16'd1;
            if (rd_tuser[1]) rd16_sol <= rd16_sol + 16'd1;
        end
    end
    always @(posedge tx_pixel_clk) begin
        if (rd_tvalid)
            rd16_beat_px <= rd16_beat_px + 16'd1;
    end
    assign path_stats6 = {rd16_sol, rd16_beat_px};   // DIAG16

    //--------------------------------------------------------------------
    // 3. demosaic：RAW10 拜耳 -> RGB x4px（AXIS-40 -> AXIS-120）
    //--------------------------------------------------------------------
    demosaic #(
        .GW   (GW),
        .LINES(CAM_LINES)
    ) u_demosaic (
        .aclk         (tx_pixel_clk),
        .aresetn      (pixel_rst_n),
        .s_axis_tdata (dms_in_tdata),
        .s_axis_tvalid(cdc_valid),
        .s_axis_tlast (dms_in_tlast),
        .s_axis_tuser (dms_in_tuser),
        .bayer_phase  (cp_bayer_phase),
        .adaptive     (cp_adaptive),
        .m_axis_tdata (dms_tdata),
        .m_axis_tvalid(dms_tvalid),
        .m_axis_tlast (dms_tlast),
        .m_axis_tuser (dms_tuser),
        .dbg_reswin_cnt ()
    );

    //--------------------------------------------------------------------
    // 4. rgb10_to_rgb8：10bit -> 8bit 量化（AXIS-120 -> AXIS-96）。
    //    v5 起白平衡已前移 demosaic 之前（u_raw_wb），本段只做 ÷4 量化
    //    —— 与旧 wb_axis@0x40 位精确等价（wb_axis 已退出路径，仅 TB
    //    平台链保留引用）。
    //--------------------------------------------------------------------
    rgb10_to_rgb8 u_q8 (
        .aclk         (tx_pixel_clk),
        .aresetn      (pixel_rst_n),
        .s_axis_tdata (dms_tdata),
        .s_axis_tvalid(dms_tvalid),
        .s_axis_tlast (dms_tlast),
        .s_axis_tuser (dms_tuser),
        .m_axis_tdata (wb_tdata),
        .m_axis_tvalid(wb_tvalid),
        .m_axis_tlast (wb_tlast),
        .m_axis_tuser (wb_tuser)
    );

    //--------------------------------------------------------------------
    // 5. rgb2yuv_axis：RGB888 -> UYVY（AXIS-96 -> AXIS-64）。
    //    blk_clip：pat_en=1 旁路——暗场钳位（Y<24 归零）是 sensor 暗场
    //    FPN 噪声钳制，会把精确码值 ramp 的暗部整段压黑（板级表现为
    //    渐变前 ~10% 纯黑平顶后突变，2026-09 确认）。
    //--------------------------------------------------------------------
    rgb2yuv_axis u_rgb2yuv (
        .aclk         (tx_pixel_clk),
        .aresetn      (pixel_rst_n),
        .s_axis_tdata (wb_tdata),
        .s_axis_tvalid(wb_tvalid),
        .s_axis_tlast (wb_tlast),
        .s_axis_tuser (wb_tuser),
        .blk_clip     (!cp_pat_en),
        .m_axis_tdata (yuv_tdata),
        .m_axis_tvalid(yuv_tvalid),
        .m_axis_tlast (yuv_tlast),
        .m_axis_tuser (yuv_tuser)
    );

    //--------------------------------------------------------------------
    // 6. 显示入口直注测试源（DBG_SHAPE_PAT 编译期开关，调试用）：
    //    shape_pat_gen（4K UYVY 棋盘）与正常流水线 yuv 流的入口 mux
    //    （CSR CTRL[6] dbg_pat_sel 运行时切换，4K 偏移隔离实验）。
    //--------------------------------------------------------------------
    wire [63:0] dbg_pat_tdata;
    wire        dbg_pat_tvalid, dbg_pat_tlast;
    wire [2:0]  dbg_pat_tuser;

    generate
        if (DBG_SHAPE_PAT) begin : g_shape_pat
            shape_pat_gen #(
                .LINE_WORDS (HACT / PPC),
                // v17 同速同构契约：2160 数据行 + 90 pad tick = 2250 tick/帧
                // = 显示自然帧。旧配置（2250+1 超速源）依赖已删除的 Vblank
                // 排水机制，v17 下队头堆盈余行 -> 门超时空开 -> 行乱。
                .SRC_LINES  (2160),
                .PAD_TICKS  (90),
                .TICK_CLOCKS((HSP + HBP + HACT + HFP) / PPC)
            ) u_shape_pat (
                .aclk          (tx_pixel_clk),
                .aresetn       (pixel_rst_n),
                .line_tick     (pat_line_tick_tx),
                .line_gap      (cp_pat_line_gap),
                .frame_gap     (cp_pat_frame_gap),
                .m_axis_tdata  (dbg_pat_tdata),
                .m_axis_tvalid (dbg_pat_tvalid),
                .m_axis_tlast  (dbg_pat_tlast),
                .m_axis_tuser  (dbg_pat_tuser)
            );
        end else begin : g_shape_pat
            assign dbg_pat_tdata  = 64'd0;
            assign dbg_pat_tvalid = 1'b0;
            assign dbg_pat_tlast  = 1'b0;
            assign dbg_pat_tuser  = 3'd0;
        end
    endgenerate

    wire [63:0] shape_in_tdata;
    wire        shape_in_tvalid, shape_in_tlast;
    wire [2:0]  shape_in_tuser;

    localparam logic DBG_EN = (DBG_SHAPE_PAT != 0);
    wire        use_dbg_pat = cp_dbg_sel & DBG_EN;
    assign shape_in_tdata  = use_dbg_pat ? dbg_pat_tdata  : yuv_tdata;
    assign shape_in_tvalid = use_dbg_pat ? dbg_pat_tvalid : yuv_tvalid;
    assign shape_in_tlast  = use_dbg_pat ? dbg_pat_tlast  : yuv_tlast;
    assign shape_in_tuser  = use_dbg_pat ? dbg_pat_tuser  : yuv_tuser;

    //--------------------------------------------------------------------
    // 7. 显示成形（v4 唯一路径）：yuv -> tx_line_buf -> disp_timing -> TX。
    //    显示时序唯一发生源（R1：与源零反馈），门控跳槽消化欠供
    //    （alg-line-gate），disp_line_tick_o 同源反哺 frame_reader 槽节拍。
    //--------------------------------------------------------------------
    wire        dt_rd_en, dt_valid;
    wire [63:0] dt_rdata;
    wire [15:0] dt_level;
    wire [31:0] dt_buf_dbg;

    tx_line_buf #(.DEPTH_WORDS(2048)) u_tlb (
        .clk          (tx_pixel_clk),
        .rst_n        (pixel_rst_n),
        .s_axis_tdata (shape_in_tdata),
        // 冷启动锚定契约：TX 复位链就绪前不开收流窗
        .s_axis_tvalid(shape_in_tvalid & pixel_rst_n),
        .rd_en        (dt_rd_en),
        .rd_data      (dt_rdata),
        .rd_valid     (dt_valid),
        .level_o      (dt_level),
        .dbg_buf_cnt_o(dt_buf_dbg)
    );

    disp_timing #(
        // 行总拍 = 像素行结构 ÷PPC（cam0 4K60=1100 / cam1 1080p60=550），
        // 与 pattern_gen 行拍同源派生；行内段用拍口径参数 HSP/HBP/HFP_CLKS
        .LINE_CLKS  ((HSP + HBP + HACT + HFP) / PPC),
        .HSP_CLKS   (HSP_CLKS),
        .HBP_CLKS   (HBP_CLKS),
        .HFP_CLKS   (HFP_CLKS),
        .FRAME_SLOTS(DISP_FRAME_SLOTS),
        // GATE 门限独立字口径（水位=64b 字，1 行 = (HACT/PPC) px x 40b
        // / 64b = 600 字；LINE_WORDS 保持 960 拍 = 行时序口径，见
        // disp_timing.v——单位混用曾是帧尾 Hg 冻结/斜卷根因）
        .LINE_WORDS (HACT / PPC),
        .LINE_BUF_WORDS((HACT / PPC) * 40 / 64),
        .VSP_L      (VSP),
        .VBP_L      (VBP),
        .VACT_L     (VACT),
        .VFP_L      (VFP),
        // pad = 槽结构余项（2026-10-21 板级实锤：独立 PAD_L=90 与标准
        // 消隐重复计入 → 2340 槽 = 57.69Hz 非标帧率）
        .PAD_L      (DISP_FRAME_SLOTS - VSP - VBP - VACT - VFP),
        .HACT_PX    (HACT),
        .DATA_TYPE  (DATA_TYPE)
    ) u_dtg (
        .clk          (tx_pixel_clk),
        .rst_n        (pixel_rst_n),
        .buf_rd_en    (dt_rd_en),
        .buf_rdata    (dt_rdata),
        .buf_valid    (dt_valid),
        .buf_level    (dt_level),
        .hsync        (tx_hsync),
        .vsync        (tx_vsync),
        .datatype     (tx_datatype),
        .pixel_data   (tx_pixel_data),
        .pixel_data_valid(tx_pixel_valid),
        .haddr        (tx_haddr),
        .line_num     (tx_line_num),
        .frame_num    (tx_frame_num),
        .frame_open   (tx_frame_open),
        .line_tick_o  (disp_line_tick_o),   // 显示槽节拍（同源 -> reader）
        .dbg_dtg_cnt_o(path_stats4)         // DIAG8 重映射：{late, under}
    );

    // v4.4 行水位节流：reader 发射门（tlb 须容得下整行 960 字）
    assign line_room_o = (dt_level <= 16'd2048 - (HACT / PPC));
    assign disp_sof_o  = tx_vsync;      // v4.9：显示帧界 -> reader 授权锚
    // v4.9 断粮预警：水位 < 1 行（600 字/4K，与 disp_timing GATE 同口径）
    // ——显示 Hg 门即将冻结/已冻结，reader 须立即开帧喂链
    assign disp_stall_o = (dt_level < (HACT / PPC) * 40 / 64);

    //--------------------------------------------------------------------
    // DIAG18 绝对窗口版（2026-10-19）：0.75s 固定窗（111,375,000
    // pixel_clk = 148.5MHz × 0.75）锁存——
    //   df_win[7:0]   = 窗内显示出帧数（vsync^）。60.00Hz=45 / 56Hz=42 /
    //                   30Hz=22，绝对值免采样窗换算，桥片"无信号"首查点
    //                  （55Hz 非标帧率 = 拒锁根因实测）。
    //   live_win[23:0]= 窗内显示入口非零内容拍 ÷64（满速 = 2160 行 ×
    //                   960 拍 × 45 帧 = 93.3M/窗，直接计数 24bit 必回绕
    //                   混叠；÷64 后满速 ≈ 1,458,000 不回绕）。恒 0 =
    //                   全黑内容。
    //--------------------------------------------------------------------
    localparam logic [26:0] WIN_TICKS = 27'd111_375_000;
    reg  [26:0] win_cnt;
    wire        win_tick = (win_cnt == WIN_TICKS - 27'd1);
    reg  [23:0] live_acc, live_win;
    reg  [5:0]  live_div;                   // 内容拍 64 分频（只在内容拍推进）
    reg  [7:0]  df_acc,  df_win;
    always @(posedge tx_pixel_clk or negedge pixel_rst_n)
        if (!pixel_rst_n)
            win_cnt <= 27'd0;
        else if (win_tick)
            win_cnt <= 27'd0;
        else
            win_cnt <= win_cnt + 27'd1;
    always @(posedge tx_pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            live_acc <= 24'd0;  live_win <= 24'd0;
            live_div <= 6'd0;
            df_acc   <= 8'd0;   df_win  <= 8'd0;
        end else if (win_tick) begin
            live_acc <= 24'd0;  live_win <= live_acc;
            df_acc   <= 8'd0;   df_win  <= df_acc;
        end else begin
            if (shape_in_tvalid && (shape_in_tdata != 64'd0)) begin
                live_div <= live_div + 6'd1;
                if (&live_div)              // 每 64 个内容拍计 1
                    live_acc <= live_acc + 24'd1;
            end
            if (tx_vsync & ~vsync_d)
                df_acc <= df_acc + 8'd1;
        end
    end
    assign diag18 = {df_win, live_win};

    //-------------------------------------------------------------------------
    // MIPI CSI-2 TX：my_csi2_tx 裸 IP 直例化
    //
    //   复位释放链：
    //     i_clk_27m 自复位(256 拍) -> PLL 释放 -> DPHY(PLL locked + ~300us)
    //     -> 像素/字/esc 域（再 + ~600us skewcal）
    //-------------------------------------------------------------------------
    // LP (escape) 数据路径未被 CSI-2 TX IP 使用 -> tie off
    assign dphy_tx_TX_DATA_ESC    = 8'h0;
    assign dphy_tx_TX_LPDT_ESC    = 1'b0;
    assign dphy_tx_TX_VALID_ESC   = 1'b0;
    assign dphy_tx_TX_TRIGGER_ESC = 4'h0;




    assign dphy_tx_RESET_N     = pll_mipi_refclk_locked;
    assign dphy_tx_PLL_SSC_EN  = 1'b0;

    //wait for ~300us for DPHY ready
    reg [12:0] cnt_250us;
    reg reset_esc_n;
    reg clk_byte_HS_n;
    always @(posedge i_clk_27m or negedge dphy_tx_RESET_N) begin
        if (~dphy_tx_RESET_N) begin
            cnt_250us     <= 13'd0;
            reset_esc_n   <= 1'b0;
            clk_byte_HS_n <= 1'b0;
        end else if (cnt_250us == 13'h1fff) begin
            cnt_250us     <= 13'h1fff;
            reset_esc_n   <= 1'b1;
            clk_byte_HS_n <= 1'b1;
        end else begin
            cnt_250us     <= cnt_250us + 1'b1;
            reset_esc_n   <= 1'b0;
            clk_byte_HS_n <= 1'b0;
        end
    end

    //wait another ~600us tINIT_NS + skewcal
    reg [13:0] cnt_500us;
    reg reset_pixel_n;
    always @(posedge i_clk_27m or negedge clk_byte_HS_n) begin
        if (~clk_byte_HS_n) begin
            cnt_500us      <= 14'd0;
            reset_pixel_n  <= 1'b0;
        end else if (cnt_500us == 14'h3fff) begin
            cnt_500us      <= 14'h3fff;
            reset_pixel_n  <= 1'b1;
        end else begin
            cnt_500us      <= cnt_500us + 1'b1;
            reset_pixel_n  <= 1'b0;
        end
    end

    // 四个使用域的低有效同步复位（原 8 路版只保留实际使用路）
    // （声明提前到 u_path 例化之前，避免端口连接隐式 wire 与显式声明冲突）

    reset_ctrl #(
        .NUM_RST       (3),
        .CYCLE         (2),
        .IN_RST_ACTIVE (3'b000),
        .OUT_RST_ACTIVE(3'b000)
    ) u_tx_reset_ctrl (
        .i_arst ({reset_pixel_n, clk_byte_HS_n, reset_esc_n}),
        .i_clk  ({tx_pixel_clk, dphy_tx_WORD_CLKOUT_HS, esc_clk}),
        .o_srst ({tx_pixel_clk_rstn, word_clk_arstn, esc_clk_arstn})
    );

    // Mapping to DPHY TX
    wire                      TxUlpsClk;
    wire                      TxUlpsExitClk;
    wire [3:0]                TxUlpsEsc;
    wire [3:0]                TxUlpsExit;
    wire [3:0]                TxRequestEsc;
    wire [3:0]                TxSkewCalHS;
    wire [3:0]                TxRequestHS;
    wire                      TxRequestHSc;
    wire [15:0]               TxDataHS0, TxDataHS1, TxDataHS2, TxDataHS3;
    wire [1:0]                TxReqValidHS0, TxReqValidHS1, TxReqValidHS2, TxReqValidHS3;
    wire                      TxUlpsActiveClkNot;
    wire [3:0]                TxStopStateD;
    wire                      TxStopStateC;
    wire [3:0]                TxUlpsActiveNot;
    wire [3:0]                TxReadyHS;

    assign TxStopStateC = dphy_tx_STOPSTATE_CLK;
    assign dphy_tx_TX_REQUEST_HS = TxRequestHSc;
    assign dphy_tx_TX_ULPS_CLK   = TxUlpsClk;
    assign dphy_tx_TX_ULPS_EXIT  = TxUlpsExitClk;
    assign TxUlpsActiveClkNot = dphy_tx_TX_ULPS_ACTIVE_CLK_NOT;

    assign dphy_tx_TX_ULPS_ESC_LAN0 = TxUlpsEsc[0];
    assign dphy_tx_TX_ULPS_ESC_LAN1 = TxUlpsEsc[1];
    assign dphy_tx_TX_ULPS_ESC_LAN2 = TxUlpsEsc[2];
    assign dphy_tx_TX_ULPS_ESC_LAN3 = TxUlpsEsc[3];
    assign dphy_tx_TX_ULPS_EXIT_LAN0 = TxUlpsExit[0];
    assign dphy_tx_TX_ULPS_EXIT_LAN1 = TxUlpsExit[1];
    assign dphy_tx_TX_ULPS_EXIT_LAN2 = TxUlpsExit[2];
    assign dphy_tx_TX_ULPS_EXIT_LAN3 = TxUlpsExit[3];
    assign dphy_tx_TX_REQUEST_ESC_LAN0 = TxRequestEsc[0];
    assign dphy_tx_TX_REQUEST_ESC_LAN1 = TxRequestEsc[1];
    assign dphy_tx_TX_REQUEST_ESC_LAN2 = TxRequestEsc[2];
    assign dphy_tx_TX_REQUEST_ESC_LAN3 = TxRequestEsc[3];
    assign dphy_tx_TX_SKEW_CAL_HS_LAN0 = TxSkewCalHS[0];
    assign dphy_tx_TX_SKEW_CAL_HS_LAN1 = TxSkewCalHS[1];
    assign dphy_tx_TX_SKEW_CAL_HS_LAN2 = TxSkewCalHS[2];
    assign dphy_tx_TX_SKEW_CAL_HS_LAN3 = TxSkewCalHS[3];
    assign TxStopStateD[0] = dphy_tx_STOPSTATE_LAN0;
    assign TxStopStateD[1] = dphy_tx_STOPSTATE_LAN1;
    assign TxStopStateD[2] = dphy_tx_STOPSTATE_LAN2;
    assign TxStopStateD[3] = dphy_tx_STOPSTATE_LAN3;

    assign TxUlpsActiveNot[0] = dphy_tx_TX_ULPS_ACTIVE_NOT_LAN0;
    assign TxUlpsActiveNot[1] = dphy_tx_TX_ULPS_ACTIVE_NOT_LAN1;
    assign TxUlpsActiveNot[2] = dphy_tx_TX_ULPS_ACTIVE_NOT_LAN2;
    assign TxUlpsActiveNot[3] = dphy_tx_TX_ULPS_ACTIVE_NOT_LAN3;
    assign TxReadyHS[0] = dphy_tx_TX_READY_HS_LAN0;
    assign TxReadyHS[1] = dphy_tx_TX_READY_HS_LAN1;
    assign TxReadyHS[2] = dphy_tx_TX_READY_HS_LAN2;
    assign TxReadyHS[3] = dphy_tx_TX_READY_HS_LAN3;

    assign dphy_tx_TX_DATA_HS_LAN0 = TxDataHS0;
    assign dphy_tx_TX_DATA_HS_LAN1 = TxDataHS1;
    assign dphy_tx_TX_DATA_HS_LAN2 = TxDataHS2;
    assign dphy_tx_TX_DATA_HS_LAN3 = TxDataHS3;
    assign dphy_tx_TX_REQUEST_HS_LAN0 = TxRequestHS[0];
    assign dphy_tx_TX_REQUEST_HS_LAN1 = TxRequestHS[1];
    assign dphy_tx_TX_REQUEST_HS_LAN2 = TxRequestHS[2];
    assign dphy_tx_TX_REQUEST_HS_LAN3 = TxRequestHS[3];
    assign dphy_tx_TX_WORD_VALID_HS_LAN0 = TxReqValidHS0[1];
    assign dphy_tx_TX_WORD_VALID_HS_LAN1 = TxReqValidHS1[1];
    assign dphy_tx_TX_WORD_VALID_HS_LAN2 = TxReqValidHS2[1];
    assign dphy_tx_TX_WORD_VALID_HS_LAN3 = TxReqValidHS3[1];

    // MIPI CSI-2 TX IP : zero software init, free-run streaming mode
    my_csi2_tx u_my_csi2_tx (
        .clk_byte_HS        (dphy_tx_WORD_CLKOUT_HS),
        .reset_byte_HS_n    (word_clk_arstn),

        .clk_pixel          (tx_pixel_clk),
        .reset_pixel_n      (tx_pixel_clk_rstn),  // 像素侧必须用 tx_pixel_clk 域同步释放复位

        .clk_esc            (esc_clk),
        .reset_esc_n        (esc_clk_arstn),

        .hsync_vc1          (), .hsync_vc2 (), .hsync_vc3 (), .hsync_vc4 (),
        .hsync_vc5          (), .hsync_vc6 (), .hsync_vc7 (), .hsync_vc8 (),
        .hsync_vc9          (), .hsync_vc10(), .hsync_vc11(), .hsync_vc12(),
        .hsync_vc13         (), .hsync_vc14(), .hsync_vc15(),
        .vsync_vc1          (), .vsync_vc2 (), .vsync_vc3 (), .vsync_vc4 (),
        .vsync_vc5          (), .vsync_vc6 (), .vsync_vc7 (), .vsync_vc8 (),
        .vsync_vc9          (), .vsync_vc10(), .vsync_vc11(), .vsync_vc12(),
        .vsync_vc13         (), .vsync_vc14(), .vsync_vc15(),
        .frame_num          (tx_frame_num),
        .hsync_vc0          (tx_hsync),
        .vsync_vc0          (tx_vsync),
        .line_num           (tx_line_num),
        .haddr              (tx_haddr),
        .pixel_data         (tx_pixel_data),
        .pixel_data_valid   (tx_pixel_valid),
        .datatype           (tx_datatype),

        // AXI4-Lite tie off, no register access
        .axi_clk            (sys_clk_100m),
        .axi_reset_n        (sys_clk_100m_rstn),
        .axi_awready		(),
        .axi_awaddr         (6'b0),
        .axi_awvalid        (1'b0),
        .axi_wready			(),
        .axi_wdata          (32'b0),
        .axi_wvalid         (1'b0),
        .axi_bready         (1'b0),
        .axi_bvalid			(),
        .axi_araddr         (6'b0),
        .axi_arvalid        (1'b0),
        .axi_rready         (1'b1),
        .axi_arready		(),
        .axi_rdata			(),
        .axi_rvalid			(),
        .irq                (),


        .TxUlpsClk          (TxUlpsClk),
        .TxUlpsExitClk      (TxUlpsExitClk),
        .TxUlpsActiveClkNot (TxUlpsActiveClkNot),
        .TxUlpsEsc          (TxUlpsEsc),
        .TxSkewCalHS        (TxSkewCalHS),
        .TxUlpsExit         (TxUlpsExit),
        .TxRequestEsc       (TxRequestEsc),
        .TxStopStateD       (TxStopStateD),
        .TxStopStateC       (TxStopStateC),
        .TxUlpsActiveNot    (TxUlpsActiveNot),
        .TxReadyHS          (TxReadyHS),
        .TxRequestHS        (TxRequestHS),
        .TxRequestHSc       (TxRequestHSc),
        .TxDataHS0          (TxDataHS0),
        .TxDataHS1          (TxDataHS1),
        .TxDataHS2          (TxDataHS2),
        .TxDataHS3          (TxDataHS3),
        .TxDataHS4          (),
        .TxDataHS5          (),
        .TxDataHS6          (),
        .TxDataHS7          (),
        .TxReqValidHS0      (TxReqValidHS0),
        .TxReqValidHS1      (TxReqValidHS1),
        .TxReqValidHS2      (TxReqValidHS2),
        .TxReqValidHS3      (TxReqValidHS3),
        .TxReqValidHS4      (),
        .TxReqValidHS5      (),
        .TxReqValidHS6      (),
        .TxReqValidHS7      ()
    );

endmodule
