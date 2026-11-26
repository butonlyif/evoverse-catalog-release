// shape_video_data.v
// 重构版 - 纯数据通路，不判断帧开始
// 1. 去掉 frame_sync 机制：假定 FIFO 第一个读出的字就是一帧的第一个像素，
//    pattern_gen 连续供数，pause 反压自动节流到与显示速率一致
// 2. FIFO 显式同步读 + 边界打一拍：pixel_data / pixel_data_valid / hsync / vsync
//    全部寄存器输出且严格同相位。
//    （旧版黑屏根因：组合读被综合器推断成块 RAM 同步读，数据天然晚 2 拍而
//      valid 当拍，两者错拍；且读出寄存器被跨模块合并进 IP 内部流水线，
//      加 debugger 强制 preserve 后相位才碰巧对上）
// 3. 行完整性：有效行行首必须攒满 LINE_WORDS 才放行时序（宁可拉长消隐），
//    行内（H_HACT）绝不暂停 —— 一行数据中间不断，FIFO 永不读空
// 4. 垂直状态机复位直接进入 V_SYNC
// Verbatim copy from D:\Projs\ws-e1-mipi-1280x720-yuv\rtl\shape_video_data.v

module shape_video_data #(
    parameter HACT = 1920,
    parameter VACT = 1080,
    parameter HSP  = 44,
    parameter HBP  = 148,
    parameter HFP  = 88,
    parameter VSP  = 5,
    parameter VBP  = 36,
    parameter VFP  = 4,
    parameter PPC  = 2,                     // 每时钟像素数（必须与数据格式匹配）
    parameter FIFO_DEPTH = 2048,            // FIFO深度（2的幂）
    parameter [5:0] DATA_TYPE = 6'h24       // CSI-2 数据类型（默认 RGB888）
)(
    // 像素时钟域（视频输出）
    input  wire         pixel_clk,
    input  wire         pixel_rst_n,

    // 系统时钟域（数据输入）
    input  wire         sys_clk,
    input  wire         sys_rst_n,
    input  wire [63:0]  sys_pixel_data,
    input  wire         sys_valid,

    // 反压输出（FIFO 将满，冻结 pattern_gen）
    output wire         pause,

    // CSI-2 TX Video Interface
    output wire         hsync_vc0,
    output wire         vsync_vc0,
    output wire [5:0]   datatype,
    output wire [63:0]  pixel_data,
    output wire         pixel_data_valid,
    output wire [15:0]  haddr,
    output wire [15:0]  line_num,
    output wire [15:0]  frame_num
);

    //================================================================
    // 1. 参数检查
    //================================================================
    initial begin
        if (HACT % PPC != 0) $fatal("HACT must be multiple of PPC");
        if (HSP  % PPC != 0) $fatal("HSP must be multiple of PPC");
        if (HBP  % PPC != 0) $fatal("HBP must be multiple of PPC");
        if (HFP  % PPC != 0) $fatal("HFP must be multiple of PPC");
        if (FIFO_DEPTH & (FIFO_DEPTH - 1))
            $fatal("FIFO_DEPTH must be power of 2");
    end

    //================================================================
    // 2. 本地参数
    //================================================================
    localparam FIFO_ADDR_WIDTH = $clog2(FIFO_DEPTH);   // 地址位宽
    localparam FIFO_PTR_WIDTH  = FIFO_ADDR_WIDTH + 1;  // 指针位宽（额外一位区分空/满）
    localparam FIFO_WIDTH      = 64;

    localparam LINE_WORDS = HACT / PPC;   // 每行数据字数

    //================================================================
    // 3. 异步 FIFO（格雷码指针，RTL 实现）—— 写端
    //================================================================
    reg [FIFO_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    reg [FIFO_PTR_WIDTH-1:0]  wr_ptr_bin;      // 二进制指针
    reg [FIFO_PTR_WIDTH-1:0]  wr_ptr_gray;     // 格雷码指针
    reg [FIFO_PTR_WIDTH-1:0]  rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    reg [FIFO_PTR_WIDTH-1:0]  rd_ptr_bin;
    reg [FIFO_PTR_WIDTH-1:0]  rd_ptr_gray;
    reg [FIFO_PTR_WIDTH-1:0]  wr_ptr_gray_sync1, wr_ptr_gray_sync2;

    wire full, almost_full;

    // 满标志：写格雷码 == 读格雷码取反（高两位相反）
    assign full = (wr_ptr_gray == {~rd_ptr_gray_sync2[FIFO_PTR_WIDTH-1:FIFO_PTR_WIDTH-2],
                                   rd_ptr_gray_sync2[FIFO_PTR_WIDTH-3:0]});

    // ---- 二进制转格雷码函数 ----
    function [FIFO_PTR_WIDTH-1:0] bin2gray;
        input [FIFO_PTR_WIDTH-1:0] bin;
        begin
            bin2gray = bin ^ (bin >> 1);
        end
    endfunction

    // ---- 格雷码转二进制函数（组合逻辑） ----
    function [FIFO_PTR_WIDTH-1:0] gray2bin;
        input [FIFO_PTR_WIDTH-1:0] gray;
        reg [FIFO_PTR_WIDTH-1:0] bin;
        integer i;
        begin
            bin = gray;
            for (i = FIFO_PTR_WIDTH-2; i >= 0; i = i - 1)
                bin[i] = bin[i+1] ^ gray[i];
            gray2bin = bin;
        end
    endfunction

    // ---- 写操作（sys_clk 域，无帧清零：数据流跨帧连续） ----
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wr_ptr_bin        <= 0;
            wr_ptr_gray       <= 0;
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            // 同步读指针格雷码（两级同步）
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;

            if (sys_valid && !full) begin
                mem[wr_ptr_bin[FIFO_ADDR_WIDTH-1:0]] <= sys_pixel_data;
                wr_ptr_bin  <= wr_ptr_bin + 1'b1;
                wr_ptr_gray <= bin2gray(wr_ptr_bin + 1'b1);
            end
        end
    end

    // ---- almost_full（写端余量，二进制指针计算） ----
    wire [FIFO_PTR_WIDTH-1:0] rd_ptr_bin_sync = gray2bin(rd_ptr_gray_sync2);
    wire [FIFO_PTR_WIDTH-1:0] used_words      = wr_ptr_bin - rd_ptr_bin_sync;
    wire [FIFO_PTR_WIDTH-1:0] free_words      = FIFO_DEPTH - used_words;
    assign almost_full = (free_words < (LINE_WORDS + 16));  // 余量 16 个字
    assign pause       = almost_full;   // 反压信号

    //================================================================
    // 4. 视频时序状态机（自由跑，仅在数据行行首受 FIFO 存量门控）
    //================================================================
    // ---- 水平状态机 ----
    localparam [2:0] H_HSYNC  = 0,
                     H_HBACK  = 1,
                     H_HACT   = 2,
                     H_HFRONT = 3;
    reg [2:0]  h_state;
    reg [15:0] h_cnt;

    // ---- 垂直状态机（复位后直接进入 V_SYNC） ----
    localparam [2:0] V_SYNC  = 0,
                     V_BACK  = 1,
                     V_ACT   = 2,
                     V_FRONT = 3;
    reg [2:0]  v_state;
    reg [15:0] v_cnt;
    reg [15:0] line_num_reg;
    reg [15:0] frame_num_reg;

    // ---- 行启动门槛 ----
    // 本模块不判断帧开始：时序自由跑，只在"即将输出有效数据行"且 FIFO
    // 攒满一行时放行：
    //   - 垂直消隐（v_state != V_ACT）：无需数据，自由跑
    //   - 行内（h_state == H_HACT）：绝不暂停（一行数据中间不能断）
    //   - 有效行消隐段：等 FIFO >= LINE_WORDS，宁可拉长消隐也不冒险
    // used_words_rd 用 2 级同步后的写指针计算，滞后实际 2~3 拍且只少不多
    // （写端只增不减）→ 判"够一行"时实际存量只会更多 → 行内不可能读空
    wire [FIFO_PTR_WIDTH-1:0] wr_ptr_bin_rd = gray2bin(wr_ptr_gray_sync2);
    wire [FIFO_PTR_WIDTH-1:0] used_words_rd = wr_ptr_bin_rd - rd_ptr_bin;
    wire have_line = (used_words_rd >= LINE_WORDS);
    wire can_run   = (v_state != V_ACT) || (h_state == H_HACT) || have_line;

    wire line_end = (h_state == H_HFRONT) && (h_cnt == HFP/PPC - 1);

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            h_state <= H_HSYNC;
            h_cnt   <= 0;
        end else if (can_run) begin
            case (h_state)
                H_HSYNC:  if (h_cnt == HSP/PPC - 1) begin h_state <= H_HBACK;  h_cnt <= 0; end
                          else h_cnt <= h_cnt + 1'b1;
                H_HBACK:  if (h_cnt == HBP/PPC - 1) begin h_state <= H_HACT;   h_cnt <= 0; end
                          else h_cnt <= h_cnt + 1'b1;
                H_HACT:   if (h_cnt == HACT/PPC - 1) begin h_state <= H_HFRONT; h_cnt <= 0; end
                          else h_cnt <= h_cnt + 1'b1;
                H_HFRONT: if (h_cnt == HFP/PPC - 1) begin h_state <= H_HSYNC;  h_cnt <= 0; end
                          else h_cnt <= h_cnt + 1'b1;
                default:  h_state <= H_HSYNC;
            endcase
        end
    end

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            v_state       <= V_SYNC;
            v_cnt         <= 0;
            line_num_reg  <= 0;
            frame_num_reg <= 0;
        end else if (can_run) begin
            if (line_end) begin
                case (v_state)
                    V_SYNC:  if (v_cnt == VSP - 1) begin
                                v_state <= V_BACK;
                                v_cnt   <= 0;
                             end else begin
                                v_cnt <= v_cnt + 1'b1;
                             end
                    V_BACK:  if (v_cnt == VBP - 1) begin
                                v_state <= V_ACT;
                                v_cnt   <= 0;
                                line_num_reg <= 0;
                             end else begin
                                v_cnt <= v_cnt + 1'b1;
                             end
                    V_ACT:   if (v_cnt == VACT - 1) begin
                                v_state <= V_FRONT;
                                v_cnt   <= 0;
                             end else begin
                                v_cnt <= v_cnt + 1'b1;
                                line_num_reg <= line_num_reg + 1'b1;
                             end
                    V_FRONT: if (v_cnt == VFP - 1) begin
                                v_state <= V_SYNC;
                                v_cnt   <= 0;
                                frame_num_reg <= frame_num_reg + 1'b1;  // vsync 上升沿更新
                             end else begin
                                v_cnt <= v_cnt + 1'b1;
                             end
                    default: v_state <= V_SYNC;
                endcase
            end
        end
    end

    //================================================================
    // 5. FIFO 读端（pixel_clk 域）：显式同步读 + 边界寄存器
    //================================================================
    // 读使能 = 未打拍的行有效信号。块 RAM 同步读：当拍用当前指针取数，
    // 数据下一拍出现在 pixel_data_r —— 与打一拍的 valid_r 严格同拍。
    // 数据与全部控制信号统一 1 拍寄存器输出，相位关系写死在 RTL，
    // 不受综合器跨模块寄存器合并/重定时影响。
    // （同步读的另一个收益：RAM 推断不再改变 RTL 时序，行为与综合结果一致）
    // 行内读空不可能发生：见 §4 行启动门槛证明。
    wire raw_active = (v_state == V_ACT) && (h_state == H_HACT);

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            rd_ptr_bin        <= 0;
            rd_ptr_gray       <= 0;
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            // 同步写指针格雷码（两级同步）
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;

            if (raw_active) begin
                rd_ptr_bin  <= rd_ptr_bin + 1'b1;
                rd_ptr_gray <= bin2gray(rd_ptr_bin + 1'b1);
            end
        end
    end

    reg [FIFO_WIDTH-1:0] pixel_data_r;
    reg                  valid_r;
    reg                  hs_r, vs_r;

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            pixel_data_r <= 64'd0;
            valid_r      <= 1'b0;
            hs_r         <= 1'b1;   // 低有效，复位取非同步电平
            vs_r         <= 1'b1;
        end else begin
            if (raw_active)
                pixel_data_r <= mem[rd_ptr_bin[FIFO_ADDR_WIDTH-1:0]];
            valid_r <= raw_active;
            hs_r    <= (h_state != H_HSYNC);
            vs_r    <= (v_state != V_SYNC);
        end
    end

    //================================================================
    // 6. 输出（全部为模块边界寄存器，数据与控制同相位）
    //================================================================
    assign pixel_data       = pixel_data_r;
    assign pixel_data_valid = valid_r;
    assign hsync_vc0        = hs_r;        // 低有效：同步期=0
    assign vsync_vc0        = vs_r;        // 低有效：同步期=0
    assign datatype         = DATA_TYPE;
    assign haddr            = HACT[15:0];
    assign line_num         = line_num_reg;
    assign frame_num        = frame_num_reg;

endmodule
