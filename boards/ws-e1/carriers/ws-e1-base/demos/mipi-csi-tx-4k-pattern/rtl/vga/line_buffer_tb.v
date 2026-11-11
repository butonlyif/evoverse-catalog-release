`timescale 1ns/1ns

module line_buffer_tb();

function integer log2;
	input	integer	val;
	integer	i;
	begin
		log2 = 0;
		for (i=0; 2**i<val; i=i+1)
			log2 = i+1;
	end
endfunction

localparam	COLOR_DEPTH		= 8;
localparam	MAX_HRES		= 16;
localparam	MAX_LINE		= 3;

localparam	HRES_WIDTH	= log2(MAX_HRES);

localparam	s_idle	= 2'b00;
localparam	s_wr	= 2'b01;
localparam	s_rd	= 2'b01;
localparam	s_blank	= 2'b10;
localparam	s_done	= 2'b11;

reg		r_arst;
reg		r_sysclk;

reg		r_we;
wire	[COLOR_DEPTH-1:0]w_Y_wd[0:511];
wire	[COLOR_DEPTH-1:0]i_Y_wd;
reg		[8:0]r_ptr;
reg		[7:0]r_wr_lcnt;

wire	w_vs;
wire	w_hs;
wire	w_ah;
wire	w_de;
wire	[MAX_LINE*COLOR_DEPTH-1:0]w_Y_rd;

wire	[8:0]w_ptr;

reg		[1:0]r_state_1P;

assign	w_Y_wd[8* 0+0]	= /*'h0_0_0;/*/8'h0_0;
assign	w_Y_wd[8* 0+1]	= /*'h0_0_8;/*/8'h0_1;
assign	w_Y_wd[8* 0+2]	= /*'h0_0_1;/*/8'h0_2;
assign	w_Y_wd[8* 0+3]	= /*'h0_0_9;/*/8'h0_3;
assign	w_Y_wd[8* 0+4]	= /*'h0_0_2;/*/8'h0_4;
assign	w_Y_wd[8* 0+5]	= /*'h0_0_A;/*/8'h0_5;
assign	w_Y_wd[8* 0+6]	= /*'h0_0_3;/*/8'h0_6;
assign	w_Y_wd[8* 0+7]	= /*'h0_0_B;/*/8'h0_7;

assign	w_Y_wd[8* 1+0]	= /*'h0_0_4;/*/8'h0_8;
assign	w_Y_wd[8* 1+1]	= /*'h0_0_C;/*/8'h0_9;
assign	w_Y_wd[8* 1+2]	= /*'h0_0_5;/*/8'h0_A;
assign	w_Y_wd[8* 1+3]	= /*'h0_0_D;/*/8'h0_B;
assign	w_Y_wd[8* 1+4]	= /*'h0_0_6;/*/8'h0_C;
assign	w_Y_wd[8* 1+5]	= /*'h0_0_E;/*/8'h0_D;
assign	w_Y_wd[8* 1+6]	= /*'h0_0_7;/*/8'h0_E;
assign	w_Y_wd[8* 1+7]	= /*'h0_0_F;/*/8'h0_F;

assign	w_Y_wd[8* 2+0]	= /*'h0_8_0;/*/8'h1_0;
assign	w_Y_wd[8* 2+1]	= /*'h0_8_8;/*/8'h1_1;
assign	w_Y_wd[8* 2+2]	= /*'h0_8_1;/*/8'h1_2;
assign	w_Y_wd[8* 2+3]	= /*'h0_8_9;/*/8'h1_3;
assign	w_Y_wd[8* 2+4]	= /*'h0_8_2;/*/8'h1_4;
assign	w_Y_wd[8* 2+5]	= /*'h0_8_A;/*/8'h1_5;
assign	w_Y_wd[8* 2+6]	= /*'h0_8_3;/*/8'h1_6;
assign	w_Y_wd[8* 2+7]	= /*'h0_8_B;/*/8'h1_7;

assign	w_Y_wd[8* 3+0]	= /*'h0_8_4;/*/8'h1_8;
assign	w_Y_wd[8* 3+1]	= /*'h0_8_C;/*/8'h1_9;
assign	w_Y_wd[8* 3+2]	= /*'h0_8_5;/*/8'h1_A;
assign	w_Y_wd[8* 3+3]	= /*'h0_8_D;/*/8'h1_B;
assign	w_Y_wd[8* 3+4]	= /*'h0_8_6;/*/8'h1_C;
assign	w_Y_wd[8* 3+5]	= /*'h0_8_E;/*/8'h1_D;
assign	w_Y_wd[8* 3+6]	= /*'h0_8_7;/*/8'h1_E;
assign	w_Y_wd[8* 3+7]	= /*'h0_8_F;/*/8'h1_F;

assign	w_Y_wd[8* 4+0]	= /*'h0_1_0;/*/8'h2_0;
assign	w_Y_wd[8* 4+1]	= /*'h0_1_8;/*/8'h2_1;
assign	w_Y_wd[8* 4+2]	= /*'h0_1_1;/*/8'h2_2;
assign	w_Y_wd[8* 4+3]	= /*'h0_1_9;/*/8'h2_3;
assign	w_Y_wd[8* 4+4]	= /*'h0_1_2;/*/8'h2_4;
assign	w_Y_wd[8* 4+5]	= /*'h0_1_A;/*/8'h2_5;
assign	w_Y_wd[8* 4+6]	= /*'h0_1_3;/*/8'h2_6;
assign	w_Y_wd[8* 4+7]	= /*'h0_1_B;/*/8'h2_7;

assign	w_Y_wd[8* 5+0]	= /*'h0_1_4;/*/8'h2_8;
assign	w_Y_wd[8* 5+1]	= /*'h0_1_C;/*/8'h2_9;
assign	w_Y_wd[8* 5+2]	= /*'h0_1_5;/*/8'h2_A;
assign	w_Y_wd[8* 5+3]	= /*'h0_1_D;/*/8'h2_B;
assign	w_Y_wd[8* 5+4]	= /*'h0_1_6;/*/8'h2_C;
assign	w_Y_wd[8* 5+5]	= /*'h0_1_E;/*/8'h2_D;
assign	w_Y_wd[8* 5+6]	= /*'h0_1_7;/*/8'h2_E;
assign	w_Y_wd[8* 5+7]	= /*'h0_1_F;/*/8'h2_F;

assign	w_Y_wd[8* 6+0]	= /*'h0_9_0;/*/8'h3_0;
assign	w_Y_wd[8* 6+1]	= /*'h0_9_8;/*/8'h3_1;
assign	w_Y_wd[8* 6+2]	= /*'h0_9_1;/*/8'h3_2;
assign	w_Y_wd[8* 6+3]	= /*'h0_9_9;/*/8'h3_3;
assign	w_Y_wd[8* 6+4]	= /*'h0_9_2;/*/8'h3_4;
assign	w_Y_wd[8* 6+5]	= /*'h0_9_A;/*/8'h3_5;
assign	w_Y_wd[8* 6+6]	= /*'h0_9_3;/*/8'h3_6;
assign	w_Y_wd[8* 6+7]	= /*'h0_9_B;/*/8'h3_7;

assign	w_Y_wd[8* 7+0]	= /*'h0_9_4;/*/8'h3_8;
assign	w_Y_wd[8* 7+1]	= /*'h0_9_C;/*/8'h3_9;
assign	w_Y_wd[8* 7+2]	= /*'h0_9_5;/*/8'h3_A;
assign	w_Y_wd[8* 7+3]	= /*'h0_9_D;/*/8'h3_B;
assign	w_Y_wd[8* 7+4]	= /*'h0_9_6;/*/8'h3_C;
assign	w_Y_wd[8* 7+5]	= /*'h0_9_E;/*/8'h3_D;
assign	w_Y_wd[8* 7+6]	= /*'h0_9_7;/*/8'h3_E;
assign	w_Y_wd[8* 7+7]	= /*'h0_9_F;/*/8'h3_F;

assign	w_Y_wd[8* 8+0]	= /*'h0_2_0;/*/8'h4_0;
assign	w_Y_wd[8* 8+1]	= /*'h0_2_8;/*/8'h4_1;
assign	w_Y_wd[8* 8+2]	= /*'h0_2_1;/*/8'h4_2;
assign	w_Y_wd[8* 8+3]	= /*'h0_2_9;/*/8'h4_3;
assign	w_Y_wd[8* 8+4]	= /*'h0_2_2;/*/8'h4_4;
assign	w_Y_wd[8* 8+5]	= /*'h0_2_A;/*/8'h4_5;
assign	w_Y_wd[8* 8+6]	= /*'h0_2_3;/*/8'h4_6;
assign	w_Y_wd[8* 8+7]	= /*'h0_2_B;/*/8'h4_7;

assign	w_Y_wd[8* 9+0]	= /*'h0_2_4;/*/8'h4_8;
assign	w_Y_wd[8* 9+1]	= /*'h0_2_C;/*/8'h4_9;
assign	w_Y_wd[8* 9+2]	= /*'h0_2_5;/*/8'h4_A;
assign	w_Y_wd[8* 9+3]	= /*'h0_2_D;/*/8'h4_B;
assign	w_Y_wd[8* 9+4]	= /*'h0_2_6;/*/8'h4_C;
assign	w_Y_wd[8* 9+5]	= /*'h0_2_E;/*/8'h4_D;
assign	w_Y_wd[8* 9+6]	= /*'h0_2_7;/*/8'h4_E;
assign	w_Y_wd[8* 9+7]	= /*'h0_2_F;/*/8'h4_F;

assign	w_Y_wd[8*10+0]	= /*'h0_A_0;/*/8'h5_0;
assign	w_Y_wd[8*10+1]	= /*'h0_A_8;/*/8'h5_1;
assign	w_Y_wd[8*10+2]	= /*'h0_A_1;/*/8'h5_2;
assign	w_Y_wd[8*10+3]	= /*'h0_A_9;/*/8'h5_3;
assign	w_Y_wd[8*10+4]	= /*'h0_A_2;/*/8'h5_4;
assign	w_Y_wd[8*10+5]	= /*'h0_A_A;/*/8'h5_5;
assign	w_Y_wd[8*10+6]	= /*'h0_A_3;/*/8'h5_6;
assign	w_Y_wd[8*10+7]	= /*'h0_A_B;/*/8'h5_7;

assign	w_Y_wd[8*11+0]	= /*'h0_A_4;/*/8'h5_8;
assign	w_Y_wd[8*11+1]	= /*'h0_A_C;/*/8'h5_9;
assign	w_Y_wd[8*11+2]	= /*'h0_A_5;/*/8'h5_A;
assign	w_Y_wd[8*11+3]	= /*'h0_A_D;/*/8'h5_B;
assign	w_Y_wd[8*11+4]	= /*'h0_A_6;/*/8'h5_C;
assign	w_Y_wd[8*11+5]	= /*'h0_A_E;/*/8'h5_D;
assign	w_Y_wd[8*11+6]	= /*'h0_A_7;/*/8'h5_E;
assign	w_Y_wd[8*11+7]	= /*'h0_A_F;/*/8'h5_F;

assign	w_Y_wd[8*12+0]	= /*'h0_3_0;/*/8'h6_0;
assign	w_Y_wd[8*12+1]	= /*'h0_3_8;/*/8'h6_1;
assign	w_Y_wd[8*12+2]	= /*'h0_3_1;/*/8'h6_2;
assign	w_Y_wd[8*12+3]	= /*'h0_3_9;/*/8'h6_3;
assign	w_Y_wd[8*12+4]	= /*'h0_3_2;/*/8'h6_4;
assign	w_Y_wd[8*12+5]	= /*'h0_3_A;/*/8'h6_5;
assign	w_Y_wd[8*12+6]	= /*'h0_3_3;/*/8'h6_6;
assign	w_Y_wd[8*12+7]	= /*'h0_3_B;/*/8'h6_7;

assign	w_Y_wd[8*13+0]	= /*'h0_3_4;/*/8'h6_8;
assign	w_Y_wd[8*13+1]	= /*'h0_3_C;/*/8'h6_9;
assign	w_Y_wd[8*13+2]	= /*'h0_3_5;/*/8'h6_A;
assign	w_Y_wd[8*13+3]	= /*'h0_3_D;/*/8'h6_B;
assign	w_Y_wd[8*13+4]	= /*'h0_3_6;/*/8'h6_C;
assign	w_Y_wd[8*13+5]	= /*'h0_3_E;/*/8'h6_D;
assign	w_Y_wd[8*13+6]	= /*'h0_3_7;/*/8'h6_E;
assign	w_Y_wd[8*13+7]	= /*'h0_3_F;/*/8'h6_F;

assign	w_Y_wd[8*14+0]	= /*'h0_B_0;/*/8'h7_0;
assign	w_Y_wd[8*14+1]	= /*'h0_B_8;/*/8'h7_1;
assign	w_Y_wd[8*14+2]	= /*'h0_B_1;/*/8'h7_2;
assign	w_Y_wd[8*14+3]	= /*'h0_B_9;/*/8'h7_3;
assign	w_Y_wd[8*14+4]	= /*'h0_B_2;/*/8'h7_4;
assign	w_Y_wd[8*14+5]	= /*'h0_B_A;/*/8'h7_5;
assign	w_Y_wd[8*14+6]	= /*'h0_B_3;/*/8'h7_6;
assign	w_Y_wd[8*14+7]	= /*'h0_B_B;/*/8'h7_7;

assign	w_Y_wd[8*15+0]	= /*'h0_B_4;/*/8'h7_8;
assign	w_Y_wd[8*15+1]	= /*'h0_B_C;/*/8'h7_9;
assign	w_Y_wd[8*15+2]	= /*'h0_B_5;/*/8'h7_A;
assign	w_Y_wd[8*15+3]	= /*'h0_B_D;/*/8'h7_B;
assign	w_Y_wd[8*15+4]	= /*'h0_B_6;/*/8'h7_C;
assign	w_Y_wd[8*15+5]	= /*'h0_B_E;/*/8'h7_D;
assign	w_Y_wd[8*15+6]	= /*'h0_B_7;/*/8'h7_E;
assign	w_Y_wd[8*15+7]	= /*'h0_B_F;/*/8'h7_F;

assign	w_Y_wd[8*16+0]	= /*'h0_4_0;/*/8'h8_0;
assign	w_Y_wd[8*16+1]	= /*'h0_4_8;/*/8'h8_1;
assign	w_Y_wd[8*16+2]	= /*'h0_4_1;/*/8'h8_2;
assign	w_Y_wd[8*16+3]	= /*'h0_4_9;/*/8'h8_3;
assign	w_Y_wd[8*16+4]	= /*'h0_4_2;/*/8'h8_4;
assign	w_Y_wd[8*16+5]	= /*'h0_4_A;/*/8'h8_5;
assign	w_Y_wd[8*16+6]	= /*'h0_4_3;/*/8'h8_6;
assign	w_Y_wd[8*16+7]	= /*'h0_4_B;/*/8'h8_7;

assign	w_Y_wd[8*17+0]	= /*'h0_4_4;/*/8'h8_8;
assign	w_Y_wd[8*17+1]	= /*'h0_4_C;/*/8'h8_9;
assign	w_Y_wd[8*17+2]	= /*'h0_4_5;/*/8'h8_A;
assign	w_Y_wd[8*17+3]	= /*'h0_4_D;/*/8'h8_B;
assign	w_Y_wd[8*17+4]	= /*'h0_4_6;/*/8'h8_C;
assign	w_Y_wd[8*17+5]	= /*'h0_4_E;/*/8'h8_D;
assign	w_Y_wd[8*17+6]	= /*'h0_4_7;/*/8'h8_E;
assign	w_Y_wd[8*17+7]	= /*'h0_4_F;/*/8'h8_F;

assign	w_Y_wd[8*18+0]	= /*'h0_C_0;/*/8'h9_0;
assign	w_Y_wd[8*18+1]	= /*'h0_C_8;/*/8'h9_1;
assign	w_Y_wd[8*18+2]	= /*'h0_C_1;/*/8'h9_2;
assign	w_Y_wd[8*18+3]	= /*'h0_C_9;/*/8'h9_3;
assign	w_Y_wd[8*18+4]	= /*'h0_C_2;/*/8'h9_4;
assign	w_Y_wd[8*18+5]	= /*'h0_C_A;/*/8'h9_5;
assign	w_Y_wd[8*18+6]	= /*'h0_C_3;/*/8'h9_6;
assign	w_Y_wd[8*18+7]	= /*'h0_C_B;/*/8'h9_7;

assign	w_Y_wd[8*19+0]	= /*'h0_C_4;/*/8'h9_8;
assign	w_Y_wd[8*19+1]	= /*'h0_C_C;/*/8'h9_9;
assign	w_Y_wd[8*19+2]	= /*'h0_C_5;/*/8'h9_A;
assign	w_Y_wd[8*19+3]	= /*'h0_C_D;/*/8'h9_B;
assign	w_Y_wd[8*19+4]	= /*'h0_C_6;/*/8'h9_C;
assign	w_Y_wd[8*19+5]	= /*'h0_C_E;/*/8'h9_D;
assign	w_Y_wd[8*19+6]	= /*'h0_C_7;/*/8'h9_E;
assign	w_Y_wd[8*19+7]	= /*'h0_C_F;/*/8'h9_F;

assign	w_Y_wd[8*20+0]	= /*'h0_5_0;/*/8'hA_0;
assign	w_Y_wd[8*20+1]	= /*'h0_5_8;/*/8'hA_1;
assign	w_Y_wd[8*20+2]	= /*'h0_5_1;/*/8'hA_2;
assign	w_Y_wd[8*20+3]	= /*'h0_5_9;/*/8'hA_3;
assign	w_Y_wd[8*20+4]	= /*'h0_5_2;/*/8'hA_4;
assign	w_Y_wd[8*20+5]	= /*'h0_5_A;/*/8'hA_5;
assign	w_Y_wd[8*20+6]	= /*'h0_5_3;/*/8'hA_6;
assign	w_Y_wd[8*20+7]	= /*'h0_5_B;/*/8'hA_7;

assign	w_Y_wd[8*21+0]	= /*'h0_5_4;/*/8'hA_8;
assign	w_Y_wd[8*21+1]	= /*'h0_5_C;/*/8'hA_9;
assign	w_Y_wd[8*21+2]	= /*'h0_5_5;/*/8'hA_A;
assign	w_Y_wd[8*21+3]	= /*'h0_5_D;/*/8'hA_B;
assign	w_Y_wd[8*21+4]	= /*'h0_5_6;/*/8'hA_C;
assign	w_Y_wd[8*21+5]	= /*'h0_5_E;/*/8'hA_D;
assign	w_Y_wd[8*21+6]	= /*'h0_5_7;/*/8'hA_E;
assign	w_Y_wd[8*21+7]	= /*'h0_5_F;/*/8'hA_F;

assign	w_Y_wd[8*22+0]	= /*'h0_D_0;/*/8'hB_0;
assign	w_Y_wd[8*22+1]	= /*'h0_D_8;/*/8'hB_1;
assign	w_Y_wd[8*22+2]	= /*'h0_D_1;/*/8'hB_2;
assign	w_Y_wd[8*22+3]	= /*'h0_D_9;/*/8'hB_3;
assign	w_Y_wd[8*22+4]	= /*'h0_D_2;/*/8'hB_4;
assign	w_Y_wd[8*22+5]	= /*'h0_D_A;/*/8'hB_5;
assign	w_Y_wd[8*22+6]	= /*'h0_D_3;/*/8'hB_6;
assign	w_Y_wd[8*22+7]	= /*'h0_D_B;/*/8'hB_7;

assign	w_Y_wd[8*23+0]	= /*'h0_D_4;/*/8'hB_8;
assign	w_Y_wd[8*23+1]	= /*'h0_D_C;/*/8'hB_9;
assign	w_Y_wd[8*23+2]	= /*'h0_D_5;/*/8'hB_A;
assign	w_Y_wd[8*23+3]	= /*'h0_D_D;/*/8'hB_B;
assign	w_Y_wd[8*23+4]	= /*'h0_D_6;/*/8'hB_C;
assign	w_Y_wd[8*23+5]	= /*'h0_D_E;/*/8'hB_D;
assign	w_Y_wd[8*23+6]	= /*'h0_D_7;/*/8'hB_E;
assign	w_Y_wd[8*23+7]	= /*'h0_D_F;/*/8'hB_F;

assign	w_Y_wd[8*24+0]	= /*'h0_6_0;/*/8'hC_0;
assign	w_Y_wd[8*24+1]	= /*'h0_6_8;/*/8'hC_1;
assign	w_Y_wd[8*24+2]	= /*'h0_6_1;/*/8'hC_2;
assign	w_Y_wd[8*24+3]	= /*'h0_6_9;/*/8'hC_3;
assign	w_Y_wd[8*24+4]	= /*'h0_6_2;/*/8'hC_4;
assign	w_Y_wd[8*24+5]	= /*'h0_6_A;/*/8'hC_5;
assign	w_Y_wd[8*24+6]	= /*'h0_6_3;/*/8'hC_6;
assign	w_Y_wd[8*24+7]	= /*'h0_6_B;/*/8'hC_7;

assign	w_Y_wd[8*25+0]	= /*'h0_6_4;/*/8'hC_8;
assign	w_Y_wd[8*25+1]	= /*'h0_6_C;/*/8'hC_9;
assign	w_Y_wd[8*25+2]	= /*'h0_6_5;/*/8'hC_A;
assign	w_Y_wd[8*25+3]	= /*'h0_6_D;/*/8'hC_B;
assign	w_Y_wd[8*25+4]	= /*'h0_6_6;/*/8'hC_C;
assign	w_Y_wd[8*25+5]	= /*'h0_6_E;/*/8'hC_D;
assign	w_Y_wd[8*25+6]	= /*'h0_6_7;/*/8'hC_E;
assign	w_Y_wd[8*25+7]	= /*'h0_6_F;/*/8'hC_F;

assign	w_Y_wd[8*26+0]	= /*'h0_E_0;/*/8'hD_0;
assign	w_Y_wd[8*26+1]	= /*'h0_E_8;/*/8'hD_1;
assign	w_Y_wd[8*26+2]	= /*'h0_E_1;/*/8'hD_2;
assign	w_Y_wd[8*26+3]	= /*'h0_E_9;/*/8'hD_3;
assign	w_Y_wd[8*26+4]	= /*'h0_E_2;/*/8'hD_4;
assign	w_Y_wd[8*26+5]	= /*'h0_E_A;/*/8'hD_5;
assign	w_Y_wd[8*26+6]	= /*'h0_E_3;/*/8'hD_6;
assign	w_Y_wd[8*26+7]	= /*'h0_E_B;/*/8'hD_7;

assign	w_Y_wd[8*27+0]	= /*'h0_E_4;/*/8'hD_8;
assign	w_Y_wd[8*27+1]	= /*'h0_E_C;/*/8'hD_9;
assign	w_Y_wd[8*27+2]	= /*'h0_E_5;/*/8'hD_A;
assign	w_Y_wd[8*27+3]	= /*'h0_E_D;/*/8'hD_B;
assign	w_Y_wd[8*27+4]	= /*'h0_E_6;/*/8'hD_C;
assign	w_Y_wd[8*27+5]	= /*'h0_E_E;/*/8'hD_D;
assign	w_Y_wd[8*27+6]	= /*'h0_E_7;/*/8'hD_E;
assign	w_Y_wd[8*27+7]	= /*'h0_E_F;/*/8'hD_F;

assign	w_Y_wd[8*28+0]	= /*'h0_7_0;/*/8'hE_0;
assign	w_Y_wd[8*28+1]	= /*'h0_7_8;/*/8'hE_1;
assign	w_Y_wd[8*28+2]	= /*'h0_7_1;/*/8'hE_2;
assign	w_Y_wd[8*28+3]	= /*'h0_7_9;/*/8'hE_3;
assign	w_Y_wd[8*28+4]	= /*'h0_7_2;/*/8'hE_4;
assign	w_Y_wd[8*28+5]	= /*'h0_7_A;/*/8'hE_5;
assign	w_Y_wd[8*28+6]	= /*'h0_7_3;/*/8'hE_6;
assign	w_Y_wd[8*28+7]	= /*'h0_7_B;/*/8'hE_7;

assign	w_Y_wd[8*29+0]	= /*'h0_7_4;/*/8'hE_8;
assign	w_Y_wd[8*29+1]	= /*'h0_7_C;/*/8'hE_9;
assign	w_Y_wd[8*29+2]	= /*'h0_7_5;/*/8'hE_A;
assign	w_Y_wd[8*29+3]	= /*'h0_7_D;/*/8'hE_B;
assign	w_Y_wd[8*29+4]	= /*'h0_7_6;/*/8'hE_C;
assign	w_Y_wd[8*29+5]	= /*'h0_7_E;/*/8'hE_D;
assign	w_Y_wd[8*29+6]	= /*'h0_7_7;/*/8'hE_E;
assign	w_Y_wd[8*29+7]	= /*'h0_7_F;/*/8'hE_F;

assign	w_Y_wd[8*30+0]	= /*'h0_F_0;/*/8'hF_0;
assign	w_Y_wd[8*30+1]	= /*'h0_F_8;/*/8'hF_1;
assign	w_Y_wd[8*30+2]	= /*'h0_F_1;/*/8'hF_2;
assign	w_Y_wd[8*30+3]	= /*'h0_F_9;/*/8'hF_3;
assign	w_Y_wd[8*30+4]	= /*'h0_F_2;/*/8'hF_4;
assign	w_Y_wd[8*30+5]	= /*'h0_F_A;/*/8'hF_5;
assign	w_Y_wd[8*30+6]	= /*'h0_F_3;/*/8'hF_6;
assign	w_Y_wd[8*30+7]	= /*'h0_F_B;/*/8'hF_7;

assign	w_Y_wd[8*31+0]	= /*'h0_F_4;/*/8'hF_8;
assign	w_Y_wd[8*31+1]	= /*'h0_F_C;/*/8'hF_9;
assign	w_Y_wd[8*31+2]	= /*'h0_F_5;/*/8'hF_A;
assign	w_Y_wd[8*31+3]	= /*'h0_F_D;/*/8'hF_B;
assign	w_Y_wd[8*31+4]	= /*'h0_F_6;/*/8'hF_C;
assign	w_Y_wd[8*31+5]	= /*'h0_F_E;/*/8'hF_D;
assign	w_Y_wd[8*31+6]	= /*'h0_F_7;/*/8'hF_E;
assign	w_Y_wd[8*31+7]	= /*'h0_F_F;/*/8'hF_F;

assign	w_Y_wd[8*32+0]	= /*'h1_0_0;/*/8'h0_0;
assign	w_Y_wd[8*32+1]	= /*'h1_0_8;/*/8'h0_1;
assign	w_Y_wd[8*32+2]	= /*'h1_0_1;/*/8'h0_2;
assign	w_Y_wd[8*32+3]	= /*'h1_0_9;/*/8'h0_3;
assign	w_Y_wd[8*32+4]	= /*'h1_0_2;/*/8'h0_4;
assign	w_Y_wd[8*32+5]	= /*'h1_0_A;/*/8'h0_5;
assign	w_Y_wd[8*32+6]	= /*'h1_0_3;/*/8'h0_6;
assign	w_Y_wd[8*32+7]	= /*'h1_0_B;/*/8'h0_7;

assign	w_Y_wd[8*33+0]	= /*'h1_0_4;/*/8'h0_8;
assign	w_Y_wd[8*33+1]	= /*'h1_0_C;/*/8'h0_9;
assign	w_Y_wd[8*33+2]	= /*'h1_0_5;/*/8'h0_A;
assign	w_Y_wd[8*33+3]	= /*'h1_0_D;/*/8'h0_B;
assign	w_Y_wd[8*33+4]	= /*'h1_0_6;/*/8'h0_C;
assign	w_Y_wd[8*33+5]	= /*'h1_0_E;/*/8'h0_D;
assign	w_Y_wd[8*33+6]	= /*'h1_0_7;/*/8'h0_E;
assign	w_Y_wd[8*33+7]	= /*'h1_0_F;/*/8'h0_F;

assign	w_Y_wd[8*34+0]	= /*'h1_8_0;/*/8'h1_0;
assign	w_Y_wd[8*34+1]	= /*'h1_8_8;/*/8'h1_1;
assign	w_Y_wd[8*34+2]	= /*'h1_8_1;/*/8'h1_2;
assign	w_Y_wd[8*34+3]	= /*'h1_8_9;/*/8'h1_3;
assign	w_Y_wd[8*34+4]	= /*'h1_8_2;/*/8'h1_4;
assign	w_Y_wd[8*34+5]	= /*'h1_8_A;/*/8'h1_5;
assign	w_Y_wd[8*34+6]	= /*'h1_8_3;/*/8'h1_6;
assign	w_Y_wd[8*34+7]	= /*'h1_8_B;/*/8'h1_7;

assign	w_Y_wd[8*35+0]	= /*'h1_8_4;/*/8'h1_8;
assign	w_Y_wd[8*35+1]	= /*'h1_8_C;/*/8'h1_9;
assign	w_Y_wd[8*35+2]	= /*'h1_8_5;/*/8'h1_A;
assign	w_Y_wd[8*35+3]	= /*'h1_8_D;/*/8'h1_B;
assign	w_Y_wd[8*35+4]	= /*'h1_8_6;/*/8'h1_C;
assign	w_Y_wd[8*35+5]	= /*'h1_8_E;/*/8'h1_D;
assign	w_Y_wd[8*35+6]	= /*'h1_8_7;/*/8'h1_E;
assign	w_Y_wd[8*35+7]	= /*'h1_8_F;/*/8'h1_F;

assign	w_Y_wd[8*36+0]	= /*'h1_1_0;/*/8'h2_0;
assign	w_Y_wd[8*36+1]	= /*'h1_1_8;/*/8'h2_1;
assign	w_Y_wd[8*36+2]	= /*'h1_1_1;/*/8'h2_2;
assign	w_Y_wd[8*36+3]	= /*'h1_1_9;/*/8'h2_3;
assign	w_Y_wd[8*36+4]	= /*'h1_1_2;/*/8'h2_4;
assign	w_Y_wd[8*36+5]	= /*'h1_1_A;/*/8'h2_5;
assign	w_Y_wd[8*36+6]	= /*'h1_1_3;/*/8'h2_6;
assign	w_Y_wd[8*36+7]	= /*'h1_1_B;/*/8'h2_7;

assign	w_Y_wd[8*37+0]	= /*'h1_1_4;/*/8'h2_8;
assign	w_Y_wd[8*37+1]	= /*'h1_1_C;/*/8'h2_9;
assign	w_Y_wd[8*37+2]	= /*'h1_1_5;/*/8'h2_A;
assign	w_Y_wd[8*37+3]	= /*'h1_1_D;/*/8'h2_B;
assign	w_Y_wd[8*37+4]	= /*'h1_1_6;/*/8'h2_C;
assign	w_Y_wd[8*37+5]	= /*'h1_1_E;/*/8'h2_D;
assign	w_Y_wd[8*37+6]	= /*'h1_1_7;/*/8'h2_E;
assign	w_Y_wd[8*37+7]	= /*'h1_1_F;/*/8'h2_F;

assign	w_Y_wd[8*38+0]	= /*'h1_9_0;/*/8'h3_0;
assign	w_Y_wd[8*38+1]	= /*'h1_9_8;/*/8'h3_1;
assign	w_Y_wd[8*38+2]	= /*'h1_9_1;/*/8'h3_2;
assign	w_Y_wd[8*38+3]	= /*'h1_9_9;/*/8'h3_3;
assign	w_Y_wd[8*38+4]	= /*'h1_9_2;/*/8'h3_4;
assign	w_Y_wd[8*38+5]	= /*'h1_9_A;/*/8'h3_5;
assign	w_Y_wd[8*38+6]	= /*'h1_9_3;/*/8'h3_6;
assign	w_Y_wd[8*38+7]	= /*'h1_9_B;/*/8'h3_7;

assign	w_Y_wd[8*39+0]	= /*'h1_9_4;/*/8'h3_8;
assign	w_Y_wd[8*39+1]	= /*'h1_9_C;/*/8'h3_9;
assign	w_Y_wd[8*39+2]	= /*'h1_9_5;/*/8'h3_A;
assign	w_Y_wd[8*39+3]	= /*'h1_9_D;/*/8'h3_B;
assign	w_Y_wd[8*39+4]	= /*'h1_9_6;/*/8'h3_C;
assign	w_Y_wd[8*39+5]	= /*'h1_9_E;/*/8'h3_D;
assign	w_Y_wd[8*39+6]	= /*'h1_9_7;/*/8'h3_E;
assign	w_Y_wd[8*39+7]	= /*'h1_9_F;/*/8'h3_F;

assign	w_Y_wd[8*40+0]	= /*'h1_2_0;/*/8'h4_0;
assign	w_Y_wd[8*40+1]	= /*'h1_2_8;/*/8'h4_1;
assign	w_Y_wd[8*40+2]	= /*'h1_2_1;/*/8'h4_2;
assign	w_Y_wd[8*40+3]	= /*'h1_2_9;/*/8'h4_3;
assign	w_Y_wd[8*40+4]	= /*'h1_2_2;/*/8'h4_4;
assign	w_Y_wd[8*40+5]	= /*'h1_2_A;/*/8'h4_5;
assign	w_Y_wd[8*40+6]	= /*'h1_2_3;/*/8'h4_6;
assign	w_Y_wd[8*40+7]	= /*'h1_2_B;/*/8'h4_7;

assign	w_Y_wd[8*41+0]	= /*'h1_2_4;/*/8'h4_8;
assign	w_Y_wd[8*41+1]	= /*'h1_2_C;/*/8'h4_9;
assign	w_Y_wd[8*41+2]	= /*'h1_2_5;/*/8'h4_A;
assign	w_Y_wd[8*41+3]	= /*'h1_2_D;/*/8'h4_B;
assign	w_Y_wd[8*41+4]	= /*'h1_2_6;/*/8'h4_C;
assign	w_Y_wd[8*41+5]	= /*'h1_2_E;/*/8'h4_D;
assign	w_Y_wd[8*41+6]	= /*'h1_2_7;/*/8'h4_E;
assign	w_Y_wd[8*41+7]	= /*'h1_2_F;/*/8'h4_F;

assign	w_Y_wd[8*42+0]	= /*'h1_A_0;/*/8'h5_0;
assign	w_Y_wd[8*42+1]	= /*'h1_A_8;/*/8'h5_1;
assign	w_Y_wd[8*42+2]	= /*'h1_A_1;/*/8'h5_2;
assign	w_Y_wd[8*42+3]	= /*'h1_A_9;/*/8'h5_3;
assign	w_Y_wd[8*42+4]	= /*'h1_A_2;/*/8'h5_4;
assign	w_Y_wd[8*42+5]	= /*'h1_A_A;/*/8'h5_5;
assign	w_Y_wd[8*42+6]	= /*'h1_A_3;/*/8'h5_6;
assign	w_Y_wd[8*42+7]	= /*'h1_A_B;/*/8'h5_7;

assign	w_Y_wd[8*43+0]	= /*'h1_A_4;/*/8'h5_8;
assign	w_Y_wd[8*43+1]	= /*'h1_A_C;/*/8'h5_9;
assign	w_Y_wd[8*43+2]	= /*'h1_A_5;/*/8'h5_A;
assign	w_Y_wd[8*43+3]	= /*'h1_A_D;/*/8'h5_B;
assign	w_Y_wd[8*43+4]	= /*'h1_A_6;/*/8'h5_C;
assign	w_Y_wd[8*43+5]	= /*'h1_A_E;/*/8'h5_D;
assign	w_Y_wd[8*43+6]	= /*'h1_A_7;/*/8'h5_E;
assign	w_Y_wd[8*43+7]	= /*'h1_A_F;/*/8'h5_F;

assign	w_Y_wd[8*44+0]	= /*'h1_3_0;/*/8'h6_0;
assign	w_Y_wd[8*44+1]	= /*'h1_3_8;/*/8'h6_1;
assign	w_Y_wd[8*44+2]	= /*'h1_3_1;/*/8'h6_2;
assign	w_Y_wd[8*44+3]	= /*'h1_3_9;/*/8'h6_3;
assign	w_Y_wd[8*44+4]	= /*'h1_3_2;/*/8'h6_4;
assign	w_Y_wd[8*44+5]	= /*'h1_3_A;/*/8'h6_5;
assign	w_Y_wd[8*44+6]	= /*'h1_3_3;/*/8'h6_6;
assign	w_Y_wd[8*44+7]	= /*'h1_3_B;/*/8'h6_7;

assign	w_Y_wd[8*45+0]	= /*'h1_3_4;/*/8'h6_8;
assign	w_Y_wd[8*45+1]	= /*'h1_3_C;/*/8'h6_9;
assign	w_Y_wd[8*45+2]	= /*'h1_3_5;/*/8'h6_A;
assign	w_Y_wd[8*45+3]	= /*'h1_3_D;/*/8'h6_B;
assign	w_Y_wd[8*45+4]	= /*'h1_3_6;/*/8'h6_C;
assign	w_Y_wd[8*45+5]	= /*'h1_3_E;/*/8'h6_D;
assign	w_Y_wd[8*45+6]	= /*'h1_3_7;/*/8'h6_E;
assign	w_Y_wd[8*45+7]	= /*'h1_3_F;/*/8'h6_F;

assign	w_Y_wd[8*46+0]	= /*'h1_B_0;/*/8'h7_0;
assign	w_Y_wd[8*46+1]	= /*'h1_B_8;/*/8'h7_1;
assign	w_Y_wd[8*46+2]	= /*'h1_B_1;/*/8'h7_2;
assign	w_Y_wd[8*46+3]	= /*'h1_B_9;/*/8'h7_3;
assign	w_Y_wd[8*46+4]	= /*'h1_B_2;/*/8'h7_4;
assign	w_Y_wd[8*46+5]	= /*'h1_B_A;/*/8'h7_5;
assign	w_Y_wd[8*46+6]	= /*'h1_B_3;/*/8'h7_6;
assign	w_Y_wd[8*46+7]	= /*'h1_B_B;/*/8'h7_7;

assign	w_Y_wd[8*47+0]	= /*'h1_B_4;/*/8'h7_8;
assign	w_Y_wd[8*47+1]	= /*'h1_B_C;/*/8'h7_9;
assign	w_Y_wd[8*47+2]	= /*'h1_B_5;/*/8'h7_A;
assign	w_Y_wd[8*47+3]	= /*'h1_B_D;/*/8'h7_B;
assign	w_Y_wd[8*47+4]	= /*'h1_B_6;/*/8'h7_C;
assign	w_Y_wd[8*47+5]	= /*'h1_B_E;/*/8'h7_D;
assign	w_Y_wd[8*47+6]	= /*'h1_B_7;/*/8'h7_E;
assign	w_Y_wd[8*47+7]	= /*'h1_B_F;/*/8'h7_F;

assign	w_Y_wd[8*48+0]	= /*'h1_4_0;/*/8'h8_0;
assign	w_Y_wd[8*48+1]	= /*'h1_4_8;/*/8'h8_1;
assign	w_Y_wd[8*48+2]	= /*'h1_4_1;/*/8'h8_2;
assign	w_Y_wd[8*48+3]	= /*'h1_4_9;/*/8'h8_3;
assign	w_Y_wd[8*48+4]	= /*'h1_4_2;/*/8'h8_4;
assign	w_Y_wd[8*48+5]	= /*'h1_4_A;/*/8'h8_5;
assign	w_Y_wd[8*48+6]	= /*'h1_4_3;/*/8'h8_6;
assign	w_Y_wd[8*48+7]	= /*'h1_4_B;/*/8'h8_7;

assign	w_Y_wd[8*49+0]	= /*'h1_4_4;/*/8'h8_8;
assign	w_Y_wd[8*49+1]	= /*'h1_4_C;/*/8'h8_9;
assign	w_Y_wd[8*49+2]	= /*'h1_4_5;/*/8'h8_A;
assign	w_Y_wd[8*49+3]	= /*'h1_4_D;/*/8'h8_B;
assign	w_Y_wd[8*49+4]	= /*'h1_4_6;/*/8'h8_C;
assign	w_Y_wd[8*49+5]	= /*'h1_4_E;/*/8'h8_D;
assign	w_Y_wd[8*49+6]	= /*'h1_4_7;/*/8'h8_E;
assign	w_Y_wd[8*49+7]	= /*'h1_4_F;/*/8'h8_F;

assign	w_Y_wd[8*50+0]	= /*'h1_C_0;/*/8'h9_0;
assign	w_Y_wd[8*50+1]	= /*'h1_C_8;/*/8'h9_1;
assign	w_Y_wd[8*50+2]	= /*'h1_C_1;/*/8'h9_2;
assign	w_Y_wd[8*50+3]	= /*'h1_C_9;/*/8'h9_3;
assign	w_Y_wd[8*50+4]	= /*'h1_C_2;/*/8'h9_4;
assign	w_Y_wd[8*50+5]	= /*'h1_C_A;/*/8'h9_5;
assign	w_Y_wd[8*50+6]	= /*'h1_C_3;/*/8'h9_6;
assign	w_Y_wd[8*50+7]	= /*'h1_C_B;/*/8'h9_7;

assign	w_Y_wd[8*51+0]	= /*'h1_C_4;/*/8'h9_8;
assign	w_Y_wd[8*51+1]	= /*'h1_C_C;/*/8'h9_9;
assign	w_Y_wd[8*51+2]	= /*'h1_C_5;/*/8'h9_A;
assign	w_Y_wd[8*51+3]	= /*'h1_C_D;/*/8'h9_B;
assign	w_Y_wd[8*51+4]	= /*'h1_C_6;/*/8'h9_C;
assign	w_Y_wd[8*51+5]	= /*'h1_C_E;/*/8'h9_D;
assign	w_Y_wd[8*51+6]	= /*'h1_C_7;/*/8'h9_E;
assign	w_Y_wd[8*51+7]	= /*'h1_C_F;/*/8'h9_F;

assign	w_Y_wd[8*52+0]	= /*'h1_5_0;/*/8'hA_0;
assign	w_Y_wd[8*52+1]	= /*'h1_5_8;/*/8'hA_1;
assign	w_Y_wd[8*52+2]	= /*'h1_5_1;/*/8'hA_2;
assign	w_Y_wd[8*52+3]	= /*'h1_5_9;/*/8'hA_3;
assign	w_Y_wd[8*52+4]	= /*'h1_5_2;/*/8'hA_4;
assign	w_Y_wd[8*52+5]	= /*'h1_5_A;/*/8'hA_5;
assign	w_Y_wd[8*52+6]	= /*'h1_5_3;/*/8'hA_6;
assign	w_Y_wd[8*52+7]	= /*'h1_5_B;/*/8'hA_7;

assign	w_Y_wd[8*53+0]	= /*'h1_5_4;/*/8'hA_8;
assign	w_Y_wd[8*53+1]	= /*'h1_5_C;/*/8'hA_9;
assign	w_Y_wd[8*53+2]	= /*'h1_5_5;/*/8'hA_A;
assign	w_Y_wd[8*53+3]	= /*'h1_5_D;/*/8'hA_B;
assign	w_Y_wd[8*53+4]	= /*'h1_5_6;/*/8'hA_C;
assign	w_Y_wd[8*53+5]	= /*'h1_5_E;/*/8'hA_D;
assign	w_Y_wd[8*53+6]	= /*'h1_5_7;/*/8'hA_E;
assign	w_Y_wd[8*53+7]	= /*'h1_5_F;/*/8'hA_F;

assign	w_Y_wd[8*54+0]	= /*'h1_D_0;/*/8'hB_0;
assign	w_Y_wd[8*54+1]	= /*'h1_D_8;/*/8'hB_1;
assign	w_Y_wd[8*54+2]	= /*'h1_D_1;/*/8'hB_2;
assign	w_Y_wd[8*54+3]	= /*'h1_D_9;/*/8'hB_3;
assign	w_Y_wd[8*54+4]	= /*'h1_D_2;/*/8'hB_4;
assign	w_Y_wd[8*54+5]	= /*'h1_D_A;/*/8'hB_5;
assign	w_Y_wd[8*54+6]	= /*'h1_D_3;/*/8'hB_6;
assign	w_Y_wd[8*54+7]	= /*'h1_D_B;/*/8'hB_7;

assign	w_Y_wd[8*55+0]	= /*'h1_D_4;/*/8'hB_8;
assign	w_Y_wd[8*55+1]	= /*'h1_D_C;/*/8'hB_9;
assign	w_Y_wd[8*55+2]	= /*'h1_D_5;/*/8'hB_A;
assign	w_Y_wd[8*55+3]	= /*'h1_D_D;/*/8'hB_B;
assign	w_Y_wd[8*55+4]	= /*'h1_D_6;/*/8'hB_C;
assign	w_Y_wd[8*55+5]	= /*'h1_D_E;/*/8'hB_D;
assign	w_Y_wd[8*55+6]	= /*'h1_D_7;/*/8'hB_E;
assign	w_Y_wd[8*55+7]	= /*'h1_D_F;/*/8'hB_F;

assign	w_Y_wd[8*56+0]	= /*'h1_6_0;/*/8'hC_0;
assign	w_Y_wd[8*56+1]	= /*'h1_6_8;/*/8'hC_1;
assign	w_Y_wd[8*56+2]	= /*'h1_6_1;/*/8'hC_2;
assign	w_Y_wd[8*56+3]	= /*'h1_6_9;/*/8'hC_3;
assign	w_Y_wd[8*56+4]	= /*'h1_6_2;/*/8'hC_4;
assign	w_Y_wd[8*56+5]	= /*'h1_6_A;/*/8'hC_5;
assign	w_Y_wd[8*56+6]	= /*'h1_6_3;/*/8'hC_6;
assign	w_Y_wd[8*56+7]	= /*'h1_6_B;/*/8'hC_7;

assign	w_Y_wd[8*57+0]	= /*'h1_6_4;/*/8'hC_8;
assign	w_Y_wd[8*57+1]	= /*'h1_6_C;/*/8'hC_9;
assign	w_Y_wd[8*57+2]	= /*'h1_6_5;/*/8'hC_A;
assign	w_Y_wd[8*57+3]	= /*'h1_6_D;/*/8'hC_B;
assign	w_Y_wd[8*57+4]	= /*'h1_6_6;/*/8'hC_C;
assign	w_Y_wd[8*57+5]	= /*'h1_6_E;/*/8'hC_D;
assign	w_Y_wd[8*57+6]	= /*'h1_6_7;/*/8'hC_E;
assign	w_Y_wd[8*57+7]	= /*'h1_6_F;/*/8'hC_F;

assign	w_Y_wd[8*58+0]	= /*'h1_E_0;/*/8'hD_0;
assign	w_Y_wd[8*58+1]	= /*'h1_E_8;/*/8'hD_1;
assign	w_Y_wd[8*58+2]	= /*'h1_E_1;/*/8'hD_2;
assign	w_Y_wd[8*58+3]	= /*'h1_E_9;/*/8'hD_3;
assign	w_Y_wd[8*58+4]	= /*'h1_E_2;/*/8'hD_4;
assign	w_Y_wd[8*58+5]	= /*'h1_E_A;/*/8'hD_5;
assign	w_Y_wd[8*58+6]	= /*'h1_E_3;/*/8'hD_6;
assign	w_Y_wd[8*58+7]	= /*'h1_E_B;/*/8'hD_7;

assign	w_Y_wd[8*59+0]	= /*'h1_E_4;/*/8'hD_8;
assign	w_Y_wd[8*59+1]	= /*'h1_E_C;/*/8'hD_9;
assign	w_Y_wd[8*59+2]	= /*'h1_E_5;/*/8'hD_A;
assign	w_Y_wd[8*59+3]	= /*'h1_E_D;/*/8'hD_B;
assign	w_Y_wd[8*59+4]	= /*'h1_E_6;/*/8'hD_C;
assign	w_Y_wd[8*59+5]	= /*'h1_E_E;/*/8'hD_D;
assign	w_Y_wd[8*59+6]	= /*'h1_E_7;/*/8'hD_E;
assign	w_Y_wd[8*59+7]	= /*'h1_E_F;/*/8'hD_F;

assign	w_Y_wd[8*60+0]	= /*'h1_7_0;/*/8'hE_0;
assign	w_Y_wd[8*60+1]	= /*'h1_7_8;/*/8'hE_1;
assign	w_Y_wd[8*60+2]	= /*'h1_7_1;/*/8'hE_2;
assign	w_Y_wd[8*60+3]	= /*'h1_7_9;/*/8'hE_3;
assign	w_Y_wd[8*60+4]	= /*'h1_7_2;/*/8'hE_4;
assign	w_Y_wd[8*60+5]	= /*'h1_7_A;/*/8'hE_5;
assign	w_Y_wd[8*60+6]	= /*'h1_7_3;/*/8'hE_6;
assign	w_Y_wd[8*60+7]	= /*'h1_7_B;/*/8'hE_7;

assign	w_Y_wd[8*61+0]	= /*'h1_7_4;/*/8'hE_8;
assign	w_Y_wd[8*61+1]	= /*'h1_7_C;/*/8'hE_9;
assign	w_Y_wd[8*61+2]	= /*'h1_7_5;/*/8'hE_A;
assign	w_Y_wd[8*61+3]	= /*'h1_7_D;/*/8'hE_B;
assign	w_Y_wd[8*61+4]	= /*'h1_7_6;/*/8'hE_C;
assign	w_Y_wd[8*61+5]	= /*'h1_7_E;/*/8'hE_D;
assign	w_Y_wd[8*61+6]	= /*'h1_7_7;/*/8'hE_E;
assign	w_Y_wd[8*61+7]	= /*'h1_7_F;/*/8'hE_F;

assign	w_Y_wd[8*62+0]	= /*'h1_F_0;/*/8'hF_0;
assign	w_Y_wd[8*62+1]	= /*'h1_F_8;/*/8'hF_1;
assign	w_Y_wd[8*62+2]	= /*'h1_F_1;/*/8'hF_2;
assign	w_Y_wd[8*62+3]	= /*'h1_F_9;/*/8'hF_3;
assign	w_Y_wd[8*62+4]	= /*'h1_F_2;/*/8'hF_4;
assign	w_Y_wd[8*62+5]	= /*'h1_F_A;/*/8'hF_5;
assign	w_Y_wd[8*62+6]	= /*'h1_F_3;/*/8'hF_6;
assign	w_Y_wd[8*62+7]	= /*'h1_F_B;/*/8'hF_7;

assign	w_Y_wd[8*63+0]	= /*'h1_F_4;/*/8'hF_8;
assign	w_Y_wd[8*63+1]	= /*'h1_F_C;/*/8'hF_9;
assign	w_Y_wd[8*63+2]	= /*'h1_F_5;/*/8'hF_A;
assign	w_Y_wd[8*63+3]	= /*'h1_F_D;/*/8'hF_B;
assign	w_Y_wd[8*63+4]	= /*'h1_F_6;/*/8'hF_C;
assign	w_Y_wd[8*63+5]	= /*'h1_F_E;/*/8'hF_D;
assign	w_Y_wd[8*63+6]	= /*'h1_F_7;/*/8'hF_E;
assign	w_Y_wd[8*63+7]	= /*'h1_F_F;/*/8'hF_F;

assign	w_ptr	= r_ptr[8:0];
assign	i_Y_wd	= w_Y_wd[w_ptr];

line_buffer
#(
	.P_DEPTH		(COLOR_DEPTH),
	.PW				(COLOR_DEPTH),
	.X_CNT_WIDTH	(11)
)
inst_line_buffer
(
	.i_arstn		(~r_arst),
	.i_pclk			(r_sysclk),

	.i_vsync		(1'b1),
	.i_hsync		(r_we),
	.i_de			(r_we),
	.i_valid		(r_we),
	.i_p			(i_Y_wd),
	
	.o_vsync		(w_vs),
	.o_hsync		(w_hs),
	.o_de			(w_ah),
	.o_valid		(w_de),
	.o_p_11			(w_Y_rd[0*COLOR_DEPTH+:COLOR_DEPTH]),
	.o_p_00			(w_Y_rd[1*COLOR_DEPTH+:COLOR_DEPTH]),
	.o_p_01			(w_Y_rd[2*COLOR_DEPTH+:COLOR_DEPTH]),
	
	.o_x			()
);

initial
begin
	r_arst	<= 1'b1;
	#10	r_arst	<= 1'b0;
end

initial
begin
	r_sysclk	<= 1'b1;
	forever
		#5	r_sysclk	<= ~r_sysclk;
end

always@(posedge r_arst or posedge r_sysclk)
begin
	if (r_arst)
	begin
		r_state_1P		<= s_idle;
		r_we			<= 1'b0;
		r_ptr			<= {9{1'b0}};
		r_wr_lcnt		<= {6{1'b0}};
	end
	else
	begin
		case (r_state_1P)
			s_idle:
			begin
				r_wr_lcnt	<= r_wr_lcnt+1'b1;
				if (r_wr_lcnt == 8'd3)
				begin
					r_state_1P	<= s_wr;
					r_we		<= 1'b1;
					r_wr_lcnt	<= {8{1'b0}};
				end
			end
			
			s_wr:
			begin
				r_ptr		<= r_ptr+1'b1;
				r_wr_lcnt	<= r_wr_lcnt+1'b1;
				if (r_wr_lcnt == MAX_HRES-1'b1)
				begin
					r_state_1P	<= s_idle;
					r_we		<= 1'b0;
					r_wr_lcnt	<= {8{1'b0}};
				end
			end
			
			s_blank:
			begin
			end
			
			s_done:
			begin
			end
		endcase
	end
end

endmodule
