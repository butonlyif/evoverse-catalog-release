//rev 3.0 
//suport parallel pixel & YUV422 8bit color bar
module color_bar_yuv #(
		parameter DYN_EN = 1'b0,
		parameter HS_POLORY =1'b1,
		parameter VS_POLORY = 1'b1,
		parameter SYMBOL_WIDTH = 'd10,
		parameter SYMBOL_NUM	= 'd3,
		parameter PAR_PIXEL_NUM = 'd4,    // 你是4像素并行
		parameter HFP 	= 13'd10,
		parameter HST 			= 13'd20,
		parameter HACT 			= 13'd3840,
		parameter HBP 			= 13'd20,
		parameter VFP 			= 13'd10,
		parameter VST 			= 13'd10,
		parameter VACT 			= 13'd2160,
		parameter VBP 			= 13'd10,
		parameter TEST_MODE 	= 2'd2
)(
	input		wire			clk,
	input 		wire 			rst_n,

	output 	reg	[15:0] h_cnt = 0,
	output  reg	[15:0] v_cnt = 0,
	output	reg					hs = 0,
	output	reg					vs  = 0,
	output	reg					de = 1'b0,
	output	reg [63:0] 			o_vid_data = 'd0   // 64bit YUV422 输出
);

//=========================================================
// 8色标准彩条 Y/Cb/Cr (BT.601 标准)
//=========================================================
localparam Y_WHITE   = 8'd235;  localparam Cb_WHITE  = 8'd128;  localparam Cr_WHITE  = 8'd128;
localparam Y_YELLOW  = 8'd219;  localparam Cb_YELLOW = 8'd16;   localparam Cr_YELLOW = 8'd142;
localparam Y_CYAN    = 8'd188;  localparam Cb_CYAN   = 8'd154;  localparam Cr_CYAN   = 8'd54;
localparam Y_GREEN   = 8'd172;  localparam Cb_GREEN  = 8'd42;   localparam Cr_GREEN  = 8'd42;
localparam Y_MAGENTA = 8'd105;  localparam Cb_MAGENTA= 8'd214;  localparam Cr_MAGENTA= 8'd214;
localparam Y_RED     = 8'd89;   localparam Cb_RED    = 8'd54;   localparam Cr_RED    = 8'd240;
localparam Y_BLUE    = 8'd58;   localparam Cb_BLUE   = 8'd240;  localparam Cr_BLUE   = 8'd110;
localparam Y_BLACK   = 8'd16;   localparam Cb_BLACK  = 8'd128;  localparam Cr_BLACK  = 8'd128;

localparam S_HBP 	= 2'd0;
localparam S_HST 	= 2'd1;
localparam S_HACT 	= 2'd2;
localparam S_HFP 	= 2'd3;
localparam S_VBP 	= 2'd0;
localparam S_VST 	= 2'd1;
localparam S_VACT 	= 2'd2;
localparam S_VFP 	= 2'd3;

localparam HFP_CNT = HFP/PAR_PIXEL_NUM;
localparam HBP_CNT = HBP/PAR_PIXEL_NUM;
localparam HACT_CNT = HACT/PAR_PIXEL_NUM;
localparam HST_CNT = HST/PAR_PIXEL_NUM;

reg	[1:0] 	h_state = S_HST;
reg	[1:0] 	v_state = S_VST;
reg	hs_r1 = 1'b0;
reg vs_r1 = 1'b0;
reg	de_r1 = 1'b0;

//=========================================================
// H 状态机（完全不变）
//=========================================================
always @( posedge clk or negedge rst_n )
begin
	if( ~rst_n ) begin 
		h_state <= S_HST;
		h_cnt <= 0;
	end else begin 
		case(h_state )
		S_HST : begin
				if( h_cnt == HST_CNT - 1) begin
						h_cnt <= 0;
						h_state <= S_HBP;
				end else 
						h_cnt <= h_cnt + 1'b1;
		end
		S_HBP : begin
				if( h_cnt == HBP_CNT - 1) begin
						h_cnt <= 0;
						h_state <= S_HACT;
				end else 
						h_cnt <= h_cnt + 1'b1;
		end
		S_HACT : begin
				if( h_cnt == HACT_CNT - 1) begin
						h_cnt <= 0;
						h_state <= S_HFP;
				end else 
						h_cnt <= h_cnt + 1'b1;
		end
		S_HFP : begin
				if( h_cnt == HFP_CNT - 1) begin
						h_cnt <= 0;
						h_state <= S_HST;
				end else 
						h_cnt <= h_cnt + 1'b1;
		end
		default: begin
				h_state <= S_HST;
				h_cnt <= 0;
		end
		endcase
	end 
end

//=========================================================
// V 状态机（完全不变）
//=========================================================
always @( posedge clk or negedge rst_n  )
begin
	if( ~rst_n ) begin 
		v_state <= S_VST;
		v_cnt <= 0;
	end else begin 
		case(v_state )
		S_VST : begin
				if( h_cnt == HFP_CNT - 1 && h_state == S_HFP ) begin
					if( v_cnt == VST - 1 ) begin 
						v_cnt <= 0;
						v_state <= S_VBP;
					end else 
						v_cnt <= v_cnt + 1'b1;
				end
		end
		S_VBP : begin
				if( h_cnt == HFP_CNT - 1 && h_state == S_HFP ) begin
					if( v_cnt == VBP - 1 ) begin 
						v_cnt <= 0;
						v_state <= S_VACT;
					end else 
						v_cnt <= v_cnt + 1'b1;
				end
		end
		S_VACT : begin
				if( h_cnt == HFP_CNT - 1 && h_state == S_HFP ) begin
					if( v_cnt == VACT - 1 ) begin 
						v_cnt <= 0;
						v_state <= S_VFP;
					end else 
						v_cnt <= v_cnt + 1'b1;
				end
		end
		S_VFP : begin
				if( h_cnt == HFP_CNT - 1 && h_state == S_HFP ) begin
					if( v_cnt == VFP - 1 ) begin 
						v_cnt <= 0;
						v_state <= S_VST;
					end else 
						v_cnt <= v_cnt + 1'b1;
				end
		end
		default: begin
				v_state <= S_VST;
				v_cnt <= 0;
		end
		endcase
	end 
end

//=========================================================
// 核心：YUV422 8色竖条彩条（你要的格式）
//=========================================================
reg [7:0] Y_pat, Cb_pat, Cr_pat;
always @(*) begin
	if(h_state == S_HACT) begin
		if( h_cnt < HACT_CNT/8 )
			{Y_pat, Cb_pat, Cr_pat} = {Y_WHITE, Cb_WHITE, Cr_WHITE};
		else if( h_cnt < HACT_CNT/8*2 )
			{Y_pat, Cb_pat, Cr_pat} = {Y_YELLOW, Cb_YELLOW, Cr_YELLOW};
		else if( h_cnt < HACT_CNT/8*3 )
			{Y_pat, Cb_pat, Cr_pat} = {Y_CYAN, Cb_CYAN, Cr_CYAN};
		else if( h_cnt < HACT_CNT/8*4 )
			{Y_pat, Cb_pat, Cr_pat} = {Y_GREEN, Cb_GREEN, Cr_GREEN};
		else if( h_cnt < HACT_CNT/8*5 )
			{Y_pat, Cb_pat, Cr_pat} = {Y_MAGENTA, Cb_MAGENTA, Cr_MAGENTA};
		else if( h_cnt < HACT_CNT/8*6 )
			{Y_pat, Cb_pat, Cr_pat} = {Y_RED, Cb_RED, Cr_RED};
		else if( h_cnt < HACT_CNT/8*7 )
			{Y_pat, Cb_pat, Cr_pat} = {Y_BLUE, Cb_BLUE, Cr_BLUE};
		else
			{Y_pat, Cb_pat, Cr_pat} = {Y_BLACK, Cb_BLACK, Cr_BLACK};
	end
	else begin
		{Y_pat, Cb_pat, Cr_pat} = {Y_BLACK, Cb_BLACK, Cr_BLACK};
	end
end

//=========================================================
// 打包成你需要的 64bit YUV422 格式
// pixel_data[63:0] = {Y4,V3,Y3,U3, Y2,V1,Y1,U1}
//=========================================================
always @(posedge clk or negedge rst_n) begin
	if(~rst_n)
		o_vid_data <= 64'd0;
	else if(h_state == S_HACT && v_state == S_VACT)
		o_vid_data <= {Y_pat, Cr_pat, Y_pat, Cb_pat, Y_pat, Cr_pat, Y_pat, Cb_pat};
	else
		o_vid_data <= 64'd0;
end

//=========================================================
// 同步信号 DE / HS / VS（完全不变）
//=========================================================
always @( posedge clk or negedge rst_n )
begin
	if( !rst_n ) begin
		de 	  <= 'd0;
	end else begin
		de <= (h_state == S_HACT & v_state == S_VACT );
	end 
end

always @( posedge clk or negedge rst_n )
begin
	if( !rst_n ) begin
		vs 	  <= 'd0;
		vs_r1 <= 'd0;
	end else begin
		vs <= (VS_POLORY == 1'b1) ? (v_state == S_VST) : ~(v_state == S_VST );
		vs_r1 <= vs;
	end 
end

always @( posedge clk or negedge rst_n)
begin
	if( !rst_n ) begin
		hs_r1 <= 'd0;
	end else begin
		hs <= (HS_POLORY == 1'b1) ? (h_state == S_HST) : ~(h_state == S_HST);
	end 
end

endmodule