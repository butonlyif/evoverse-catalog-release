	module video_pattern_gen #(
		parameter	HACT		= 16'd3840,
		parameter	VACT		= 14'd2160,
		parameter	HSP				= 12'd88,
		parameter	HBP				= 12'd296,
		parameter	HFP				= 12'd176,
		parameter	VSP				= 12'd10,
		parameter	VBP				= 12'd72,
		parameter	VFP				= 12'd8,
		
		parameter PPC = 4         // 每时钟像素数
	)(
		input  wire          clk,
		input  wire          rst_n,
		output reg          vsync_r,
		output reg          hsync_r,
		output reg          de_r,
		output wire [63:0]   pixel_data
	);

	/*************************************************/
	/********** 参数转换（除以PPC） ******************/
	/*************************************************/
	// 水平参数需要除以4
	localparam HSP_GROUP = HSP / PPC;     
	localparam HBP_GROUP = HBP / PPC;     
	localparam HACT_GROUP = HACT / PPC;   
	localparam HFP_GROUP = HFP / PPC;     

	// 垂直参数保持不变
	localparam VSP_CNT = VSP;             
	localparam VBP_CNT = VBP;             
	localparam VACT_CNT = VACT;           
	localparam VFP_CNT = VFP;             

	// 用于图案生成的常量
	localparam HACT_HALF = HACT >> 1;     
	localparam VACT_HALF = VACT >> 1;     
	localparam HACT_DIV8 = HACT / 8;      

	// 总计数器值
	localparam H_TOTAL_GROUP = HSP_GROUP + HBP_GROUP + HACT_GROUP + HFP_GROUP; 
	localparam V_TOTAL_LINE = VSP_CNT + VBP_CNT + VACT_CNT + VFP_CNT;          

	// 有效区域起始和结束
	localparam H_ACT_START = HSP_GROUP + HBP_GROUP;   // 
	localparam H_ACT_END = H_ACT_START + HACT_GROUP;  // 
	localparam V_ACT_START = VSP_CNT + VBP_CNT;       // 
	localparam V_ACT_END = V_ACT_START + VACT_CNT;    // 

	/*************************************************/
	/**************** 计数器 ************************/
	/*************************************************/
	reg [15:0] h_cnt;  // 水平组计数器
	reg [15:0] v_cnt;  // 垂直行计数器 
		 wire          vsync;
		 wire          hsync;
		 wire          de;
	always @(posedge clk)
	begin 
	vsync_r	<=vsync;
	hsync_r	<=hsync;
	de_r	<=de; 
	end
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			h_cnt <= 0;
			v_cnt <= 0;
		end else begin
			if(h_cnt < H_TOTAL_GROUP - 1)
				h_cnt <= h_cnt + 1;
			else begin
				h_cnt <= 0;
				if(v_cnt < V_TOTAL_LINE - 1)
					v_cnt <= v_cnt + 1;
				else
					v_cnt <= 0;
			end
		end
	end

	/*************************************************/
	/**************** 同步信号 **********************/
	/*************************************************/
	assign hsync = (h_cnt < HSP_GROUP) ? 1'b0 : 1'b1;
	 // always @(posedge clk)
		// begin
			// hsync <= (h_cnt < HSP_GROUP) ? 1'b0 : 1'b1;
		// end 
		
		
	assign vsync = (v_cnt < VSP_CNT) ? 1'b0 : 1'b1;
	// always @(posedge clk) vsync <= (v_cnt < VSP_CNT) ? 1'b0 : 1'b1;

	assign de = (h_cnt >= H_ACT_START) && (h_cnt < H_ACT_END) &&
				(v_cnt >= V_ACT_START) && (v_cnt < V_ACT_END);
	// always @(posedge clk) de <= (h_cnt >= H_ACT_START) && (h_cnt < H_ACT_END) &&
				// (v_cnt >= V_ACT_START) && (v_cnt < V_ACT_END);
	/*************************************************/
	/**************** 像素坐标 **********************/
	/*************************************************/
	wire [15:0] h_pixel;  // 实际像素坐标
	wire [11:0] v_pixel;  // 实际行坐标 

	assign h_pixel = (h_cnt - H_ACT_START) * PPC;
	assign v_pixel = v_cnt - V_ACT_START;

	/*************************************************/
	/**************** YUV 常量 **********************/
	/*************************************************/
	// Y 分量
	localparam Y_BLACK   = 8'd16;
	localparam Y_WHITE   = 8'd235;
	localparam Y_RED     = 8'd82;
	localparam Y_GREEN   = 8'd145;
	localparam Y_BLUE    = 8'd41;
	localparam Y_YELLOW  = 8'd210;
	localparam Y_CYAN    = 8'd170;
	localparam Y_MAGENTA = 8'd106;

	// Cb 分量
	localparam CB_BLACK   = 8'd128;
	localparam CB_WHITE   = 8'd128;
	localparam CB_RED     = 8'd90;
	localparam CB_GREEN   = 8'd54;
	localparam CB_BLUE    = 8'd240;
	localparam CB_YELLOW  = 8'd16;
	localparam CB_CYAN    = 8'd166;
	localparam CB_MAGENTA = 8'd202;

	// Cr 分量
	localparam CR_BLACK   = 8'd128;
	localparam CR_WHITE   = 8'd128;
	localparam CR_RED     = 8'd240;
	localparam CR_GREEN   = 8'd34;
	localparam CR_BLUE    = 8'd110;
	localparam CR_YELLOW  = 8'd138;
	localparam CR_CYAN    = 8'd42;
	localparam CR_MAGENTA = 8'd222;

	/*************************************************/
	/******** 图案1：8条 Color Bar *******************/
	/*************************************************/
	function [15:0] get_colorbar;
		input [15:0] x;
		input [15:0] y;
		input [1:0]  sub;
		begin
			case(x / HACT_DIV8)
				0: get_colorbar = sub[0] ? {CR_WHITE, Y_WHITE} : {CB_WHITE, Y_WHITE};   // 白
				1: get_colorbar = sub[0] ? {CR_YELLOW, Y_YELLOW} : {CB_YELLOW, Y_YELLOW}; // 黄
				2: get_colorbar = sub[0] ? {CR_CYAN, Y_CYAN} : {CB_CYAN, Y_CYAN};       // 青
				3: get_colorbar = sub[0] ? {CR_GREEN, Y_GREEN} : {CB_GREEN, Y_GREEN};   // 绿
				4: get_colorbar = sub[0] ? {CR_MAGENTA, Y_MAGENTA} : {CB_MAGENTA, Y_MAGENTA}; // 品红
				5: get_colorbar = sub[0] ? {CR_RED, Y_RED} : {CB_RED, Y_RED};           // 红
				6: get_colorbar = sub[0] ? {CR_BLUE, Y_BLUE} : {CB_BLUE, Y_BLUE};       // 蓝
				default: get_colorbar = sub[0] ? {CR_BLACK, Y_BLACK} : {CB_BLACK, Y_BLACK}; // 黑
			endcase
		end
	endfunction

	/*************************************************/
	/******** 图案2：十字线+渐变 *********************/
	/*************************************************/
	function [15:0] get_crosshair;
		input [15:0] x;
		input [15:0] y;
		input [1:0]  sub;
		begin
			if(x == HACT_HALF || y == VACT_HALF)
				get_crosshair = sub[0] ? {CR_WHITE, Y_WHITE} : {CB_WHITE, Y_WHITE};
			else
				get_crosshair = sub[0] ? {8'h80, (x[7:0] + y[7:0])} : {8'h80, (x[7:0] + y[7:0])};
		end
	endfunction

	/*************************************************/
	/******** 图案3：水平渐变 ***********************/
	/*************************************************/
	function [15:0] get_hgradient;
		input [15:0] x;
		input [15:0] y;
		input [1:0]  sub;
		begin
			// Y 分量从左到右渐变 16-235
			get_hgradient = sub[0] ? {8'h80, x[7:0]} : {8'h80, x[7:0]};
		end
	endfunction

	/*************************************************/
	/******** 图案4：垂直渐变 ***********************/
	/*************************************************/
	function [15:0] get_vgradient;
		input [15:0] x;
		input [15:0] y;
		input [1:0]  sub;
		begin
			// Y 分量从上到下渐变 16-235
			get_vgradient = sub[0] ? {8'h80, y[7:0]} : {8'h80, y[7:0]};
		end
	endfunction

	/*************************************************/
	/******** 图案5：红色纯色 ***********************/
	/*************************************************/
	function [15:0] get_red;
		input [15:0] x;
		input [15:0] y;
		input [1:0]  sub;
		begin
			get_red = sub[0] ? {CR_RED, Y_RED} : {CB_RED, Y_RED};
		end
	endfunction

	/*************************************************/
	/******** 图案6：绿色纯色 ***********************/
	/*************************************************/
	function [15:0] get_green;
		input [15:0] x;
		input [15:0] y;
		input [1:0]  sub;
		begin
			get_green = sub[0] ? {CR_GREEN, Y_GREEN} : {CB_GREEN, Y_GREEN};
		end
	endfunction

	/*************************************************/
	/******** 图案7：蓝色纯色 ***********************/
	/*************************************************/
	function [15:0] get_blue;
		input [15:0] x;
		input [15:0] y;
		input [1:0]  sub;
		begin
			get_blue = sub[0] ? {CR_BLUE, Y_BLUE} : {CB_BLUE, Y_BLUE};
		end
	endfunction

	/*************************************************/
	/******** 图案8：棋盘格 *************************/
	/*************************************************/
	function [15:0] get_checker;
		input [15:0] x;
		input [15:0] y;
		input [1:0]  sub;
		begin
			if(((x >> 5) ^ (y >> 5)) & 1)  // 32x32 棋盘格
				get_checker = sub[0] ? {CR_WHITE, Y_WHITE} : {CB_WHITE, Y_WHITE};
			else
				get_checker = sub[0] ? {CR_BLACK, Y_BLACK} : {CB_BLACK, Y_BLACK};
		end
	endfunction

	/*************************************************/
	/**************** 图案循环切换 ******************/
	/*************************************************/
	// 图案选择编码
	// 0: 8条 Color Bar
	// 1: 十字线+渐变
	// 2: 水平渐变
	// 3: 垂直渐变
	// 4: 红色纯色
	// 5: 绿色纯色
	// 6: 蓝色纯色
	// 7: 棋盘格

	reg [2:0] pattern_sel;
	reg [31:0] frame_cnt;
	reg vsync_1p;

	// VSYNC 边沿检测
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			vsync_1p <= 1'b0;
		end else begin
			vsync_1p <= vsync;
		end
	end

	wire vsync_rising = vsync && !vsync_1p;  // VSYNC上升沿（帧开始）

	// 帧计数器，每3秒切换一次图案（60Hz下约180帧）
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			frame_cnt <= 32'd0;
			pattern_sel <= 3'd0;
		end else if(vsync_rising) begin
			if(frame_cnt >= 32'd180) begin  // 60Hz * 3秒 = 180帧
				frame_cnt <= 32'd0;
				if(pattern_sel == 3'd7)
					pattern_sel <= 3'd0;
				else
					pattern_sel <= pattern_sel + 1'b1;
			end else begin
				frame_cnt <= frame_cnt + 1'b1;
			end
		end
	end

	/*************************************************/
	/**************** 4像素打包输出 ******************/
	/*************************************************/
	reg [63:0] pixel_data_reg;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			pixel_data_reg <= 64'h1080108010801080;
		end else if(de) begin
			case(pattern_sel)
				3'd0: begin  // 8条 Color Bar
					pixel_data_reg <= {
						get_colorbar(h_pixel + 3, v_pixel, 2'd3)[7:0],
						get_colorbar(h_pixel + 3, v_pixel, 2'd3)[15:8],
						get_colorbar(h_pixel + 2, v_pixel, 2'd2)[7:0],
						get_colorbar(h_pixel + 2, v_pixel, 2'd2)[15:8],
						get_colorbar(h_pixel + 1, v_pixel, 2'd1)[7:0],
						get_colorbar(h_pixel + 1, v_pixel, 2'd1)[15:8],
						get_colorbar(h_pixel + 0, v_pixel, 2'd0)[7:0],
						get_colorbar(h_pixel + 0, v_pixel, 2'd0)[15:8]
					};
				end
				
				3'd1: begin  // 十字线+渐变
					pixel_data_reg <= {
						get_crosshair(h_pixel + 3, v_pixel, 2'd3)[7:0],
						get_crosshair(h_pixel + 3, v_pixel, 2'd3)[15:8],
						get_crosshair(h_pixel + 2, v_pixel, 2'd2)[7:0],
						get_crosshair(h_pixel + 2, v_pixel, 2'd2)[15:8],
						get_crosshair(h_pixel + 1, v_pixel, 2'd1)[7:0],
						get_crosshair(h_pixel + 1, v_pixel, 2'd1)[15:8],
						get_crosshair(h_pixel + 0, v_pixel, 2'd0)[7:0],
						get_crosshair(h_pixel + 0, v_pixel, 2'd0)[15:8]
					};
				end
				
				3'd2: begin  // 水平渐变
					pixel_data_reg <= {
						get_hgradient(h_pixel + 3, v_pixel, 2'd3)[7:0],
						get_hgradient(h_pixel + 3, v_pixel, 2'd3)[15:8],
						get_hgradient(h_pixel + 2, v_pixel, 2'd2)[7:0],
						get_hgradient(h_pixel + 2, v_pixel, 2'd2)[15:8],
						get_hgradient(h_pixel + 1, v_pixel, 2'd1)[7:0],
						get_hgradient(h_pixel + 1, v_pixel, 2'd1)[15:8],
						get_hgradient(h_pixel + 0, v_pixel, 2'd0)[7:0],
						get_hgradient(h_pixel + 0, v_pixel, 2'd0)[15:8]
					};
				end
				
				3'd3: begin  // 垂直渐变
					pixel_data_reg <= {
						get_vgradient(h_pixel + 3, v_pixel, 2'd3)[7:0],
						get_vgradient(h_pixel + 3, v_pixel, 2'd3)[15:8],
						get_vgradient(h_pixel + 2, v_pixel, 2'd2)[7:0],
						get_vgradient(h_pixel + 2, v_pixel, 2'd2)[15:8],
						get_vgradient(h_pixel + 1, v_pixel, 2'd1)[7:0],
						get_vgradient(h_pixel + 1, v_pixel, 2'd1)[15:8],
						get_vgradient(h_pixel + 0, v_pixel, 2'd0)[7:0],
						get_vgradient(h_pixel + 0, v_pixel, 2'd0)[15:8]
					};
				end
				
				3'd4: begin  // 红色纯色
					pixel_data_reg <= {
						get_red(h_pixel + 3, v_pixel, 2'd3)[7:0],
						get_red(h_pixel + 3, v_pixel, 2'd3)[15:8],
						get_red(h_pixel + 2, v_pixel, 2'd2)[7:0],
						get_red(h_pixel + 2, v_pixel, 2'd2)[15:8],
						get_red(h_pixel + 1, v_pixel, 2'd1)[7:0],
						get_red(h_pixel + 1, v_pixel, 2'd1)[15:8],
						get_red(h_pixel + 0, v_pixel, 2'd0)[7:0],
						get_red(h_pixel + 0, v_pixel, 2'd0)[15:8]
					};
				end
				
				3'd5: begin  // 绿色纯色
					pixel_data_reg <= {
						get_green(h_pixel + 3, v_pixel, 2'd3)[7:0],
						get_green(h_pixel + 3, v_pixel, 2'd3)[15:8],
						get_green(h_pixel + 2, v_pixel, 2'd2)[7:0],
						get_green(h_pixel + 2, v_pixel, 2'd2)[15:8],
						get_green(h_pixel + 1, v_pixel, 2'd1)[7:0],
						get_green(h_pixel + 1, v_pixel, 2'd1)[15:8],
						get_green(h_pixel + 0, v_pixel, 2'd0)[7:0],
						get_green(h_pixel + 0, v_pixel, 2'd0)[15:8]
					};
				end
				
				3'd6: begin  // 蓝色纯色
					pixel_data_reg <= {
						get_blue(h_pixel + 3, v_pixel, 2'd3)[7:0],
						get_blue(h_pixel + 3, v_pixel, 2'd3)[15:8],
						get_blue(h_pixel + 2, v_pixel, 2'd2)[7:0],
						get_blue(h_pixel + 2, v_pixel, 2'd2)[15:8],
						get_blue(h_pixel + 1, v_pixel, 2'd1)[7:0],
						get_blue(h_pixel + 1, v_pixel, 2'd1)[15:8],
						get_blue(h_pixel + 0, v_pixel, 2'd0)[7:0],
						get_blue(h_pixel + 0, v_pixel, 2'd0)[15:8]
					};
				end
				
				3'd7: begin  // 棋盘格
					pixel_data_reg <= {
						get_checker(h_pixel + 3, v_pixel, 2'd3)[7:0],
						get_checker(h_pixel + 3, v_pixel, 2'd3)[15:8],
						get_checker(h_pixel + 2, v_pixel, 2'd2)[7:0],
						get_checker(h_pixel + 2, v_pixel, 2'd2)[15:8],
						get_checker(h_pixel + 1, v_pixel, 2'd1)[7:0],
						get_checker(h_pixel + 1, v_pixel, 2'd1)[15:8],
						get_checker(h_pixel + 0, v_pixel, 2'd0)[7:0],
						get_checker(h_pixel + 0, v_pixel, 2'd0)[15:8]
					};
				end
				
				default: begin
					pixel_data_reg <= 64'h1080108010801080;
				end
			endcase
		end else begin
			pixel_data_reg <= 64'h1080108010801080;
		end
	end

	assign pixel_data = pixel_data_reg;

	endmodule