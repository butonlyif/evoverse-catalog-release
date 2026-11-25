// ============================================================================
// apb_cam_ctrl.v — camera_path 控制口 APB CSR（top_cam_demo 中挂 riscv_soc
//                  APB slave 0）
//
// 寄存器（word 编址，仅 offset 0x0 的 CTRL 使用，其余 offset 读 0、写忽略）：
//   CTRL @0x00：
//     [1:0]   bayer_phase  拜耳相位 0=RGGB 1=GRBG 2=GBRG 3=BGGR
//     [2]     adaptive     demosaic R/B 站点自适应 G 方向
//     [3]     pat_en       1 = pattern_gen 拍流替换 my_csi2_rx 输出
//                          （复位默认 1：上电出图案）
//     [5:4]   pat_sel      图案选择 0=灰度竖 ramp 1=橙蓝竖条
//                          2=灰度横 ramp 3=8x8 棋盘（复位默认橙蓝竖条）
//     [6]     dbg_sel      1 = tx_line_buf 入口直注棋盘源（旧称 shape
//                          入口；DBG_SHAPE_PAT 编译期实例化，绕开相机
//                          流水线。仅 cam0 4K 路例化，cam1 1080 路无效：
//                          shape_pat_gen 为 4K 几何）
//     [7]     （退役：曾为 CDC 入口 replay_pat_gen 直注选择，2026-10-24
//                          核实该源已随扁平化拆除、输出无消费者，端口
//                          与固件键位删除；bit 恒 0）
//     [15:8]  wb_r         （v5 退役占位：wb_axis 退出路径，软件固定写
//     [23:16] wb_g            0x40 保持布局兼容；实际增益走 WB_RAW0/1）
//     [31:24] wb_b
//
//   CTRL2 @0x08（2026-10-19 新增，复用退役 DIAG2 槽，可读写，复位 0）：
//     [15:0]  line_gap     直注源行间距（拍）：行周期 = TICK_CLOCKS+g_l
//     [31:16] frame_gap    直注源帧间距（tick）：帧尾 pad = PAD_TICKS+g_f
//     （桥片行/帧间距接受域扫频用，见 doc/csi_bridge_gap_sweep.md；
//      仅作用于 shape_pat_gen 直注源，相机/图案路径零影响）
//
//   WB_RAW0 @0x54（v5 新增，可读写）：RAW10 域白平衡 U4.12，1.0 = 0x1000
//     （doc/wb_design_spec.md；复位中性 1.0，白点经软件菜单标定后回写）
//     [15:0]  wb_r_raw
//     [31:16] wb_g_raw
//   WB_RAW1 @0x58（v5 新增，可读写）：
//     [15:0]  wb_b_raw     [31:16] 恒 0
//   DIAG21 @0x5C（v5 新增，只读）：{16'h0, raw_wb 饱和拍计数[15:0]}
//     （16bit 自由回绕；中性增益下应近 0，持续增长 = 增益过高钳 1023）
//
//   DIAG3 @0x0C（v4.11 复用退役槽，只读）：cam_i2c_init 观测（RTL 固化
//     IMX415 配置，doc/cam-i2c-rtl-init-plan.md §4.3）
//     [7:0]   dbg_idx     当前条目号（0..141；走表完成后保持 last=141）
//     [11:8]  dbg_retry   当前条目重试计数
//     [13:12] dbg_round   整轮重试轮次
//     [14]    busy        FSM 非空闲
//     [15]    done        全表配置完成（sticky，数据链放行条件之一）
//     [16]    fail        重试耗尽（sticky，rerun 写 1 可恢复）
//     [17]    scl_i       SCL pad 读回（v4.11b 板级判别）
//     [18]    sda_i       SDA pad 读回
//     [19]    cam_en      传感器使能现值
//
//   DIAG7 @0x1C（v4.11 复用退役槽，可读写，复位 0）：
//     [0]     rerun_trig  cam0 实例 cam_i2c_init rerun sticky 位：写 1
//     [1]                 cam1 实例同上（每实例 CSR 自取本位）
//     置位触发一次重配置（top_cam 内沿检测接 start，软件写 0 归位等
//     下次）。每 top_cam 实例内嵌一个 apb_cam_ctrl，bit0 为本实例位，
//     [1] 预留双实例同读一 CSR 的形态，当前恒写 0 即可。
//
//   复位默认（v5）= 中性：wb CTRL 字段 0x40x3（退役占位）、WB_RAW0/1
//   全 1.0（0x1000×3，白点经软件菜单标定后回写）、adaptive=1、
//   phase=0/RGGB、pat_en=0 上电即摄像头预览——v4.10c 纯摄像头基线：
//   上电零切换，CSR 与硬件 pat_sel_eff 复位态一致，无 pending/超时介入；
//   传感器未出流时面板黑，'p' 可手动切图案兜底）
//   零等待 APB：pready 恒 1，pslverr 恒 0（软件误访问不会挂总线）。
// ============================================================================

module apb_cam_ctrl #(
    parameter CTRL_RESET = 32'h4040_4014   // {wb_b, wb_g, wb_r=退役 0x40x3, pat_sel=01(橙蓝竖条), pat_en=0(camera, 上电零切换), adaptive=1, phase=0(RGGB)}
) (
    input  wire        pclk,
    input  wire        presetn,
    input  wire [15:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // camera_path 控制口（写后立即生效，静态输出）
    output wire [1:0]  bayer_phase,
    output wire        adaptive,
    output wire [7:0]  wb_r,
    output wire [7:0]  wb_g,
    output wire [7:0]  wb_b,

    // RAW10 域白平衡增益（v5，U4.12，1.0=0x1000；WB_RAW0/1@0x54/0x58，
    // 消费方 raw_wb_axis，wb_axis 已退出路径）
    output wire [15:0] wb_r_raw,
    output wire [15:0] wb_g_raw,
    output wire [15:0] wb_b_raw,

    // 图案源选择（top_cam_demo 输入 mux + pattern_gen 图案选择）
    output wire        pat_en,
    output wire [1:0]  pat_sel,

    // shape 入口直注源运行时选择（camera_path dbg mux）
    output wire        dbg_sel,

    // 桥片间隔扫频（2026-10-19，doc/csi_bridge_gap_sweep.md）：
    //   CTRL2 @0x08 读写，驱动 shape_pat_gen 直注源的行/帧间距
    output wire [15:0] pat_line_gap,     // 行间距（拍）：行周期=TICK_CLOCKS+g_l
    output wire [15:0] pat_frame_gap,    // 帧间距（tick）：pad=PAD_TICKS+g_f

    // 只读诊断（paddr[2]=1）：path 入口 FIFO {lost[15:0], level[15:0]}
    input  wire [31:0] diag_status,
    // DIAG4=0x10：{fw_sof_free[15:0], dms_sol_free[15:0]}（自由跑速率计）
    input  wire [31:0] diag_status4,
    // DIAG5=0x14：{yuv_v_cnt[15:0], frm_cnt[15:0]}（shape vsync^ 帧数）
    input  wire [31:0] diag_status5,
    // DIAG8=0x20：shape dbg_mon {srch[31:24], lvl[23:16], 16'h0}
    input  wire [31:0] diag_status8,
    // DIAG9=0x24：shape 读侧状态 {8'h0, 8'h0, underrun[15:8], df, vfs,
    //   vst[2:0], hst[2:0]}
    input  wire [31:0] diag_status9,
    // DIAG11=0x2C：DDR 自检状态
    input  wire [31:0] diag_status11,
    // DIAG12=0x30：frame_writer {frame_cnt[15:0], line_cnt[15:0]}
    input  wire [31:0] diag_status12,
    // DIAG13=0x34：frame_writer {ovf_cnt[15:0], pad_cnt[15:0]}
    input  wire [31:0] diag_status13,
    // DIAG14=0x38：frame_reader {frame_cnt[15:0], state[3:0], line[11:0]}
    //   （顶层组包 {rd_frame_cnt, rd_state, rd_line_cnt}）
    input  wire [31:0] diag_status14,
    // DIAG15=0x3C：frame_reader rd_err {late[7:0], miss[7:0], err[7:0],
    //   req[7:0]}（顶层组包 assign rd_diag15 = rd_err；late=tick 拍数
    //   据未就绪延迟发射、miss=frame_req 沿遇积压未消费、err=AXI 收
    //   字错账、req=frame_req 沿计数。旧注释 {4'h0,state,under,late,
    //   gen_frames} 系 v3 replay_pat_gen 时代残留，2026-10-24 修正）
    input  wire [31:0] diag_status15,
    // DIAG17=0x44：rd 回放流帧锚定行计数 {rd_tlast[15:0], rd_sol[15:0]}
    input  wire [31:0] diag_status17,
    // DIAG16=0x40（v4 复用退役槽）：回放口节拍直证 {rd_sol[15:0], rd_beat[15:0]}
    input  wire [31:0] diag_status16,
    // DIAG19=0x4C（v4 复用退役槽）：reader {drop[15:0], repeat[15:0]}
    input  wire [31:0] diag_status19,
    // DIAG20=0x50：fw 输入侧异常 {abandon[15:0], short[7:0], ab_beat[7:0]}
    input  wire [31:0] diag_status20,
    // DIAG21=0x5C（v5 新增）：raw_wb_axis 饱和拍计数 {16'h0, sat[15:0]}
    input  wire [31:0] diag_status21,
    // DIAG18=0x48（2026-10-19 复用退役槽）：{shape frame_num[15:0],
    //   content_live[15:0]}——显示侧实际帧计数（桥片"无信号"首查点）+
    //   shape 入口非零内容拍（全黑内容恒 0）
    input  wire [31:0] diag_status18,
    // DIAG3=0x0C（v4.11 复用退役槽）：cam_i2c_init 观测
    //   {fail[16], done[15], busy[14], round[13:12], retry[11:8], idx[7:0]}
    input  wire [31:0] diag_status3,
    // DIAG7=0x1C（v4.11 复用退役槽，RW）：cam_i2c rerun sticky 触发位
    output wire [1:0]  cam_i2c_rerun
);

    reg [31:0] ctrl_r;
    reg [31:0] ctrl2_r;     // CTRL2 @0x08（复位 0 = 直注源无附加间隔）
    reg [31:0] wb_raw0_r;   // WB_RAW0 @0x54（v5）：{wb_g_raw, wb_r_raw}，复位中性 1.0
    reg [31:0] wb_raw1_r;   // WB_RAW1 @0x58（v5）：{16'h0, wb_b_raw}，复位中性 1.0
    reg [1:0]  rerun_r;     // DIAG7 槽 @0x1C（v4.11 复用）：cam_i2c rerun
                            // sticky 触发位（写 1 置位，top_cam 内沿检测
                            // 接 cam_i2c_init.start 后软件写 0 归位）

    assign bayer_phase = ctrl_r[1:0];
    assign adaptive    = ctrl_r[2];
    assign pat_en      = ctrl_r[3];
    assign pat_sel     = ctrl_r[5:4];
    assign dbg_sel     = ctrl_r[6];
    // CTRL[7]（2026-10-19 复用退役 disp_sel 位）：CDC 入口直注源选择
    //（tx_line_buf 入口直注源 bypass writer/DDR/reader，内容通路测试；
    //  注意 replay_pat_gen 已拆除，CTRL[7] 位无消费者，保留位布局）
    assign wb_r        = ctrl_r[15:8];
    assign wb_g        = ctrl_r[23:16];
    assign wb_b        = ctrl_r[31:24];
    // RAW10 域增益（v5：消费方 raw_wb_axis，增益前移 demosaic 之前）
    assign wb_r_raw    = wb_raw0_r[15:0];
    assign wb_g_raw    = wb_raw0_r[31:16];
    assign wb_b_raw    = wb_raw1_r[15:0];
    // CTRL2（桥片 gap 扫频）
    assign pat_line_gap  = ctrl2_r[15:0];
    assign pat_frame_gap = ctrl2_r[31:16];

    // 写译码按字（paddr[6:2]）：0=CTRL @0x00，2=CTRL2 @0x08（复用退役
    // DIAG2 槽），7=cam_i2c rerun @0x1C（复用退役 DIAG7 槽）。旧
    // ~paddr[2] 译码覆盖不到 0x08 字（bit2=1），随 CTRL2 新增一并收紧。
    wire wr_word_ctrl   = (paddr[6:2] == 5'd0);
    wire wr_word_ctrl2  = (paddr[6:2] == 5'd2);
    wire wr_word_rerun  = (paddr[6:2] == 5'd7);
    wire wr_word_wb0    = (paddr[6:2] == 5'd21);    // WB_RAW0 @0x54（v5）
    wire wr_word_wb1    = (paddr[6:2] == 5'd22);    // WB_RAW1 @0x58（v5）
    wire wr_en = psel & penable & pwrite &
                 (wr_word_ctrl || wr_word_ctrl2 || wr_word_rerun ||
                  wr_word_wb0   || wr_word_wb1);

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ctrl_r    <= CTRL_RESET;
            ctrl2_r   <= 32'd0;
            wb_raw0_r <= 32'h4e00_6a80;   // {G=0x4e00, R=0x6a80} 板级标定基准（2026-10-24）
            wb_raw1_r <= 32'h0000_5e40;   // {--,       B=0x5e40}
            rerun_r   <= 2'd0;
        end else if (wr_en) begin
            if (wr_word_ctrl)
                ctrl_r  <= pwdata;
            else if (wr_word_ctrl2)
                ctrl2_r <= pwdata;
            else if (wr_word_wb0)
                wb_raw0_r <= pwdata;
            else if (wr_word_wb1)
                wb_raw1_r <= pwdata;
            else
                rerun_r <= pwdata[1:0];
        end
    end

    assign cam_i2c_rerun = rerun_r;

    // paddr[6:2] 译码：00000=CTRL，其余=DIAG。已退役地址（DIAG2/6/10/
    // 16/18/19，定位使命完成于 2026-10-19 dbg 清理）读 0，地址保持
    // 兼容；现役见端口注释。DIAG3/7 随 cam_i2c_init（v4.11）复用。
    always @(*) begin
        case (paddr[6:2])
            5'b00001: prdata = diag_status;
            5'b00010: prdata = ctrl2_r;         // CTRL2：{frame_gap[15:0], line_gap[15:0]}
            					//（复用退役 DIAG2 槽，桥片 gap 扫频）
            5'b00011: prdata = diag_status3;    // DIAG3 复用（v4.11）：cam_i2c 观测
            5'b00100: prdata = diag_status4;
            5'b00101: prdata = diag_status5;
            5'b00110: prdata = 32'h0;           // DIAG6 退役（rx 拍数）
            5'b00111: prdata = {30'h0, rerun_r};// DIAG7 复用（v4.11）：cam_i2c rerun sticky
            5'b01000: prdata = diag_status8;
            5'b01001: prdata = diag_status9;
            5'b01010: prdata = 32'h0;           // DIAG10 退役（lpf 记录仪）
            5'b01011: prdata = diag_status11;   // DDR：{err_cnt[15:0], mcst[15:12], 5'h0, done_raw[6], st[5:4], lock[3], cfg_ok[2], done[1], fail[0]}
            5'b01100: prdata = diag_status12;   // FW：{frame_cnt[15:0], line_cnt[15:0]}
            5'b01101: prdata = diag_status13;   // FW：{ovf_cnt[15:0], pad_cnt[15:0]}
            5'b01110: prdata = diag_status14;   // RD：{frame_cnt[15:0], line_cnt[15:0]}
            5'b01111: prdata = diag_status15;   // RD：{4'h0, state, under, late, gen_frames}
            5'b10000: prdata = diag_status16;   // DIAG16（v4）：rd 口节拍直证
            5'b10001: prdata = diag_status17;   // rd 回放流帧锚定：{tlast[15:0], sol[15:0]}/帧
            5'b10010: prdata = diag_status18;   // DIAG18：{shape frame_num[15:0], content_live[15:0]}
            5'b10011: prdata = diag_status19;   // DIAG19（v4）：reader drop/repeat
            5'b10100: prdata = diag_status20;   // fw 输入异常：{abandon[15:0], short[7:0], ab_beat[7:0]}
            5'b10101: prdata = wb_raw0_r;       // WB_RAW0（v5）：{wb_g_raw, wb_r_raw}
            5'b10110: prdata = wb_raw1_r;       // WB_RAW1（v5）：{16'h0, wb_b_raw}
            5'b10111: prdata = diag_status21;   // DIAG21（v5）：{16'h0, raw_wb 饱和拍数}
            default:  prdata = ctrl_r;
        endcase
    end
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

endmodule
