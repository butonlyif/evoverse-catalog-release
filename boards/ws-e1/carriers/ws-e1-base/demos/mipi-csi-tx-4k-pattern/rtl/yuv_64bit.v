module yuv_64bit #(
    // 水平时序参数（原始像素单位）
    parameter HSP  = 44,
    parameter HBP  = 148,
    parameter HACT = 1920,
    parameter HFP  = 88,
    
    // 垂直时序参数（行单位）
    parameter VSP  = 5,
    parameter VBP  = 36,
    parameter VACT = 1080,
    parameter VFP  = 4,
    
    parameter PPC = 4         // 每时钟像素数
)(
    // 输入时钟域（原始像素时钟）
    input  wire          rst_n,
    input  wire          pclk,           // 原始像素时钟
    input  wire          data_vs,        // 输入垂直同步
    input  wire          data_hs,        // 输入水平同步
    input  wire          data_de,        // 输入数据有效
    input  wire [15:0]   pixel_dat,      // 输入像素数据 {Cb,Y} 或 {Cr,Y}
    
    // 输出时钟域（pclk的4分之一）
    input  wire          clk_out,        // pclk/4 时钟
    output wire          vs_out,         // 输出垂直同步
    output wire          hs_out,         // 输出水平同步
    output wire          de_out,         // 输出数据有效（一行内连续）
    output wire [63:0]   pixel_data_out  // 输出4像素 {Y4,V3,Y3,U3,Y2,V1,Y1,U1}
);

/*************************************************/
/**************** 参数计算 **********************/
/*************************************************/
// 水平参数（像素单位）转组单位
localparam HSP_GROUP = HSP / PPC;     // 44/4 = 11
localparam HBP_GROUP = HBP / PPC;     // 148/4 = 37
localparam HACT_GROUP = HACT / PPC;   // 1920/4 = 480
localparam HFP_GROUP = HFP / PPC;     // 88/4 = 22
localparam H_TOTAL_GROUP = HSP_GROUP + HBP_GROUP + HACT_GROUP + HFP_GROUP;  // 550

// 垂直参数（行单位，不变）
localparam VSP_CNT = VSP;             // 5
localparam VBP_CNT = VBP;             // 36
localparam VACT_CNT = VACT;           // 1080
localparam VFP_CNT = VFP;             // 4
localparam V_TOTAL_LINE = VSP_CNT + VBP_CNT + VACT_CNT + VFP_CNT;  // 1125

// 有效区域
localparam H_ACT_START = HSP_GROUP + HBP_GROUP;  // 48
localparam H_ACT_END = H_ACT_START + HACT_GROUP; // 528
localparam V_ACT_START = VSP_CNT + VBP_CNT;      // 41
localparam V_ACT_END = V_ACT_START + VACT_CNT;   // 1121

// FIFO深度：需要缓存至少一行数据（480个4像素组），取512
localparam FIFO_DEPTH = 512;

/*************************************************/
/**************** 输入帧同步检测 ****************/
/*************************************************/
reg data_vs_1p;
reg data_vs_2p;
reg data_vs_rising;
reg data_vs_falling;

always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        data_vs_1p <= 1'b0;
        data_vs_2p <= 1'b0;
    end else begin
        data_vs_1p <= data_vs;
        data_vs_2p <= data_vs_1p;
    end
end

assign data_vs_rising = data_vs_1p && !data_vs_2p;
assign data_vs_falling = !data_vs_1p && data_vs_2p;

/*************************************************/
/**************** 输入像素打包（pclk域）*********/
/*************************************************/
reg [1:0] pack_cnt_in;
reg [15:0] pixel_buf_in [0:3];
reg [63:0] pixel_group_in;
reg        fifo_wr_en;
reg        frame_start_flag;

// 4像素打包
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        pack_cnt_in <= 0;
        fifo_wr_en <= 0;
        pixel_group_in <= 64'h0;
        frame_start_flag <= 1'b0;
    end else begin
        // 帧起始标志
        if(data_vs_rising) begin
            frame_start_flag <= 1'b1;
            pack_cnt_in <= 0;
        end else if(data_de) begin
            frame_start_flag <= 1'b0;
        end
        
        if(data_de) begin
            // 缓存像素
            pixel_buf_in[pack_cnt_in] <= pixel_dat;
            
            if(pack_cnt_in == 3) begin
                // 打包4个像素为64位
                // 输入格式：奇像素 {U, Y}，偶像素 {V, Y}
                // pixel_buf[0] = 像素1（奇）{U1, Y1}
                // pixel_buf[1] = 像素2（偶）{V1, Y2}
                // pixel_buf[2] = 像素3（奇）{U3, Y3}
                // pixel_buf[3] = 像素4（偶）{V3, Y4}
                pixel_group_in <= {
                    pixel_buf_in[3][7:0],   // Y4
                    pixel_buf_in[3][15:8],  // V3
                    pixel_buf_in[2][7:0],   // Y3
                    pixel_buf_in[2][15:8],  // U3
                    pixel_buf_in[1][7:0],   // Y2
                    pixel_buf_in[1][15:8],  // V1
                    pixel_buf_in[0][7:0],   // Y1
                    pixel_buf_in[0][15:8]   // U1
                };
                fifo_wr_en <= 1'b1;
                pack_cnt_in <= 0;
            end else begin
                pack_cnt_in <= pack_cnt_in + 1;
                fifo_wr_en <= 1'b0;
            end
        end else begin
            pack_cnt_in <= 0;
            fifo_wr_en <= 1'b0;
        end
    end
end

/*************************************************/
/**************** 异步FIFO实例化 ****************/
/*************************************************/
wire fifo_full;
wire fifo_empty;
wire fifo_prog_full;
wire fifo_overflow;
wire fifo_underflow;
wire [15:0] fifo_rdata;
wire [7:0] fifo_wr_cnt;
wire [7:0] fifo_rd_cnt;
wire fifo_rst_busy;

async_fifo_16 u_async_fifo_16 (
    .prog_full_o (fifo_prog_full),
    .full_o      (fifo_full),
    .empty_o     (fifo_empty),
    .wr_clk_i    (pclk),
    .rd_clk_i    (clk_out),
    .wr_en_i     (fifo_wr_en),
    .rd_en_i     (fifo_rd_en),
    .wdata       (pixel_group_in[15:0]),  // 注意：FIFO是16位，需要分多次写入
    .rst_busy    (fifo_rst_busy),
    .rdata       (fifo_rdata),
    .a_rst_i     (~rst_n),
    .wr_datacount_o (fifo_wr_cnt),
    .rd_datacount_o (fifo_rd_cnt),
    .underflow_o (fifo_underflow),
    .overflow_o  (fifo_overflow)
);

/*************************************************/
/**************** 帧同步控制（输出域）***********/
/*************************************************/
// 由于FIFO是16位的，64位数据需要分4次写入/读取
// 方案：使用4个FIFO，或者将64位拆分为4个16位

// 方案1：使用4个FIFO（推荐）
reg [1:0] fifo_sel;
reg [3:0] fifo_wr_en_4;
wire [3:0] fifo_full_4;
wire [3:0] fifo_empty_4;
wire [15:0] fifo_rdata_4 [0:3];
reg [3:0] fifo_rd_en_4;

genvar i;
generate
    for(i=0; i<4; i=i+1) begin : gen_fifo
        async_fifo_16 u_fifo (
            .prog_full_o (),
            .full_o      (fifo_full_4[i]),
            .empty_o     (fifo_empty_4[i]),
            .wr_clk_i    (pclk),
            .rd_clk_i    (clk_out),
            .wr_en_i     (fifo_wr_en_4[i]),
            .rd_en_i     (fifo_rd_en_4[i]),
            .wdata       (pixel_group_in[(i*16)+:16]),
            .rst_busy    (),
            .rdata       (fifo_rdata_4[i]),
            .a_rst_i     (~rst_n),
            .wr_datacount_o (),
            .rd_datacount_o (),
            .underflow_o (),
            .overflow_o  ()
        );
    end
endgenerate

// 写入控制
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        fifo_wr_en_4 <= 4'b0000;
    end else begin
        if(fifo_wr_en) begin
            // 同时写入4个FIFO
            fifo_wr_en_4 <= 4'b1111;
        end else begin
            fifo_wr_en_4 <= 4'b0000;
        end
    end
end

/*************************************************/
/**************** 输出域计数器 ******************/
/*************************************************/
reg [15:0] h_cnt_out;
reg [15:0] v_cnt_out;
reg        vsync_out_reg;
reg        hsync_out_reg;
reg        de_out_reg;

always @(posedge clk_out or negedge rst_n) begin
    if(!rst_n) begin
        h_cnt_out <= 0;
        v_cnt_out <= 0;
        vsync_out_reg <= 1'b1;
        hsync_out_reg <= 1'b1;
        de_out_reg <= 1'b0;
    end else begin
        // 水平计数
        if(h_cnt_out < H_TOTAL_GROUP - 1)
            h_cnt_out <= h_cnt_out + 1;
        else begin
            h_cnt_out <= 0;
            // 垂直计数
            if(v_cnt_out < V_TOTAL_LINE - 1)
                v_cnt_out <= v_cnt_out + 1;
            else
                v_cnt_out <= 0;
        end
        
        // 同步信号生成
        hsync_out_reg <= (h_cnt_out >= HSP_GROUP);
        vsync_out_reg <= (v_cnt_out >= VSP_CNT);
        de_out_reg <= (h_cnt_out >= H_ACT_START) && (h_cnt_out < H_ACT_END) &&
                      (v_cnt_out >= V_ACT_START) && (v_cnt_out < V_ACT_END);
    end
end

assign vs_out = vsync_out_reg;
assign hs_out = hsync_out_reg;
assign de_out = de_out_reg;

/*************************************************/
/**************** FIFO读取与输出 ****************/
/*************************************************/
reg [1:0] rd_state;
reg [63:0] pixel_data_reg;
reg [3:0] read_ready;

always @(posedge clk_out or negedge rst_n) begin
    if(!rst_n) begin
        rd_state <= 0;
        fifo_rd_en_4 <= 4'b0000;
        pixel_data_reg <= 64'h0;
        read_ready <= 4'b0000;
    end else if(de_out_reg) begin
        // 每个时钟周期需要输出一组4像素数据
        case(rd_state)
            0: begin
                // 检查所有4个FIFO非空
                if(!fifo_empty_4[0] && !fifo_empty_4[1] && 
                   !fifo_empty_4[2] && !fifo_empty_4[3]) begin
                    fifo_rd_en_4 <= 4'b1111;
                    rd_state <= 1;
                end
            end
            1: begin
                // 读取数据
                pixel_data_reg <= {
                    fifo_rdata_4[3][15:8],
                    fifo_rdata_4[3][7:0],
                    fifo_rdata_4[2][15:8],
                    fifo_rdata_4[2][7:0],
                    fifo_rdata_4[1][15:8],
                    fifo_rdata_4[1][7:0],
                    fifo_rdata_4[0][15:8],
                    fifo_rdata_4[0][7:0]
                };
                fifo_rd_en_4 <= 4'b0000;
                rd_state <= 0;
            end
        endcase
    end else begin
        rd_state <= 0;
        fifo_rd_en_4 <= 4'b0000;
        pixel_data_reg <= 64'h0;
    end
end

assign pixel_data_out = pixel_data_reg;

/*************************************************/
/**************** 帧同步状态机 ******************/
/*************************************************/
// 确保读取的帧与输出VSYNC对齐
reg [1:0] frame_sync_state;
reg [3:0] frame_buffer_ready;
reg [15:0] frame_counter;

localparam FRAME_SYNC_IDLE = 0;
localparam FRAME_SYNC_WAIT = 1;
localparam FRAME_SYNC_READY = 2;

always @(posedge clk_out or negedge rst_n) begin
    if(!rst_n) begin
        frame_sync_state <= FRAME_SYNC_IDLE;
        frame_buffer_ready <= 4'b0000;
        frame_counter <= 0;
    end else begin
        case(frame_sync_state)
            FRAME_SYNC_IDLE: begin
                // 等待输入帧开始
                if(data_vs_rising) begin
                    frame_counter <= frame_counter + 1;
                    frame_sync_state <= FRAME_SYNC_WAIT;
                end
            end
            
            FRAME_SYNC_WAIT: begin
                // 等待输出VSYNC
                if(vsync_out_reg && h_cnt_out == 0) begin
                    // 检查FIFO是否有足够数据
                    if(fifo_rd_cnt >= HACT_GROUP) begin
                        frame_buffer_ready <= 4'b1111;
                        frame_sync_state <= FRAME_SYNC_READY;
                    end
                end
            end
            
            FRAME_SYNC_READY: begin
                // 正常读取
                if(vsync_out_reg && h_cnt_out == 0) begin
                    frame_buffer_ready <= 4'b0000;
                    frame_sync_state <= FRAME_SYNC_IDLE;
                end
            end
        endcase
    end
end

endmodule