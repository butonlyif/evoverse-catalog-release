module yuv_gen #(
	parameter HS 	= 12,
	parameter HBP 	= 80,
	parameter HFP 	= 20,
	parameter HDISP = 960,

	parameter VS 	= 12,
	parameter VBP 	= 12,
	parameter VFP 	= 15,
	parameter VDISP = 720
)
(
	input 		      rst_n,
	
	input  			  pclk,
	output 			  data_vs,
	output 			  data_hs,
	output reg		  data_de,
	output reg [63:0] pixel_dat
	
);

parameter HP    = HS + HBP + HDISP + HFP - 1;
parameter VP    = VS + VBP + VDISP + VFP - 1;

localparam Y_BLACK  = 8'd16  ;
localparam Y_WHIET  = 8'd180 ;
localparam Y_RED    = 8'd65  ;  
localparam Y_GREEN  = 8'd112 ; 
localparam Y_BLUE   = 8'd32  ; 

localparam CB_BLACK = 8'd128 ;
localparam CB_WHIET = 8'd128 ;
localparam CB_RED   = 8'd100 ;  
localparam CB_GREEN = 8'd72  ; 
localparam CB_BLUE  = 8'd212 ; 

localparam CR_BLACK = 8'd128 ;
localparam CR_WHIET = 8'd128 ;
localparam CR_RED   = 8'd212 ;  
localparam CR_GREEN = 8'd58  ; 
localparam CR_BLUE  = 8'd114 ; 

 
/*************************************************/
/********************sys var*********************/
/*************************************************/
wire hdisp_de,vdisp_de;

reg [15:0] hcnt;
reg [15:0] vcnt;

/*************************************************/
/********************sys rst_n********************/
/*************************************************/
reg system_rstn,system_rstn_r;
always @(posedge pclk or negedge rst_n) begin
	if(!rst_n) begin
		system_rstn <= 1'b0;
	end else begin
		system_rstn_r <= rst_n;
		system_rstn <= system_rstn_r;
	end
end


always @(posedge pclk or negedge system_rstn) begin
	if(!system_rstn) begin
		hcnt <= 0;
		vcnt <= 0;
	end else begin
		if(hcnt < HP)	hcnt <= hcnt + 1;
		else			hcnt <= 0;
		
		if(hcnt == HP) begin
			if(vcnt < VP)	vcnt <= vcnt + 1;
			else			vcnt <= 0;
		end
	end
end

reg vs;
reg hs;

/*************************************************/
/******************** hs gen *********************/
/*************************************************/
always @(posedge pclk or negedge system_rstn) begin
	if(!system_rstn) 	hs <= 1'b0;
	else if(hcnt < HS)	hs <= 1'b0;
	else				hs <= 1'b1;
end
/*************************************************/
/******************** vs gen *********************/
/*************************************************/
always @(posedge pclk or negedge system_rstn) begin
	if(!system_rstn) 	vs <= 1'b0;
	else if(vcnt < VS)	vs <= 1'b0;
	else				vs <= 1'b1;
end
/*************************************************/
/******************** de gen *********************/
/*************************************************/
assign hdisp_de = ((hcnt >= HS + HBP) && (hcnt < HS + HBP + HDISP))?1'b1:1'b0 ;
assign vdisp_de = ((vcnt >= VS + VBP) && (vcnt < VS + VBP + VDISP))?1'b1:1'b0 ;

assign de = hdisp_de&vdisp_de;
/*************************************************/
/*************************************************/
/*************************************************/
reg vs_reg;
reg hs_reg;
reg de_reg;
wire vsync_r;
always @(posedge pclk or negedge system_rstn) begin
    if(~system_rstn)begin
        vs_reg <= 0;
		hs_reg <= 0;
		de_reg <= 0;
		data_de <= 0;
    end else begin 
        vs_reg <= vs;
		hs_reg <= hs;
		de_reg <= de;
		data_de <= de_reg;
	end
end

assign vsync_r = vs&(!vs_reg);
assign de_r = de&(!de_reg);

assign data_vs = vs_reg;
assign data_hs = hs_reg;
/*************************************************/
/**************** rgb data gen *******************/
/*************************************************/
reg[2:0] pt_sel;
reg[5:0] pt_cnt;
always @(posedge pclk or negedge system_rstn) begin
    if(~system_rstn)
        pt_cnt <= 0;
    else if(vsync_r)
        pt_cnt <= pt_cnt + 1;
end

always @(posedge pclk or negedge system_rstn) begin
    if((~system_rstn)||(pt_sel > 3'd5))
       pt_sel <= 0;
    else if(vsync_r && (pt_cnt == 6'b111_111))
       pt_sel <= pt_sel + 1;
end
//当前有效行内像素序号，消隐区清零
reg [15:0] h_act;
always @(posedge pclk or negedge system_rstn)begin
    if (!system_rstn)
		h_act<= 0;
	else if(de)
		h_act<=h_act+1;
	else 
		h_act<=0;
end
//当前有效场内行序号，新一帧 vsync_r 清零，每行开头 de_r+1
reg [15:0] v_act;
always @(posedge pclk or negedge system_rstn)begin
    if (!system_rstn)
		v_act<= 0;
	else if(vsync_r)
		v_act<=0;
	else if(de_r)
		v_act<=v_act+1;
	else 
		v_act<=0;
end
/*************************************************/
/*************************************************/
/*************************************************/
reg[15:0] px_data0;
reg[15:0] px_data1;
reg[15:0] px_data2;
reg[15:0] px_data3;
reg[15:0] px_data4;
reg[15:0] px_data5;
//从上到下渐变亮度
always @(posedge pclk or negedge system_rstn)begin
    if (!system_rstn)
		px_data0<={16'h1080};
	else 
		px_data0<={8'h80,vcnt[7:0]};	//纵向亮度渐变		
end
//横向亮度渐变
always @(posedge pclk or negedge system_rstn)begin
    if (!system_rstn)
		px_data1<=16'h1080;
	else 
		px_data1<={8'h80,hcnt[7:0]};
end
//大步进纵向灰度阶梯（vcnt [9:2]），位截取压缩，渐变台阶更大，方便观测灰度分层
always @(posedge pclk or negedge system_rstn)begin
    if (!system_rstn)
		px_data2<=16'h1080;
	else 
		px_data2<={8'h80,vcnt[9:2]};	
end

always @(posedge pclk or negedge system_rstn)begin
    if (!system_rstn)
		px_data3<=16'h1080;
	else 
		px_data3<={8'h80,hcnt[10:3]};
end
//全屏纯红色块，hcnt[0]区分奇偶像素：奇像素输出 {Cb,Y}，偶像素 {Cr,Y}，严格 YUYV 打包
always @(posedge pclk or negedge system_rstn)begin
    if (!system_rstn)begin
		px_data4<=16'h1080;
	end
	else if((vcnt >= (VS+VBP)) && (vcnt < (VS+VBP+(VDISP/5)*1)))begin
		if(hcnt[0])
			px_data4<={CB_RED,Y_RED};
		else
			px_data4<={CR_RED,Y_RED};
	end
	else if((vcnt >= (VS+VBP+(VDISP/5)*1)) && (vcnt < (VS+VBP+(VDISP/5)*2)))begin
		if(hcnt[0])
			px_data4<={CB_RED,Y_RED};
		else
			px_data4<={CR_RED,Y_RED};
	end
	else if((vcnt >= (VS+VBP+(VDISP/5)*2)) && (vcnt < (VS+VBP+(VDISP/5)*3)))begin
		if(hcnt[0])
			px_data4<={CB_RED,Y_RED};
		else
			px_data4<={CR_RED,Y_RED};
	end
	else if((vcnt >= (VS+VBP+(VDISP/5)*3)) && (vcnt < (VS+VBP+(VDISP/5)*4)))begin
		if(hcnt[0])
			px_data4<={CB_RED,Y_RED};
		else
			px_data4<={CR_RED,Y_RED};
	end
	else begin
		if(hcnt[0])
			px_data4<={CB_RED,Y_RED};
		else
			px_data4<={CR_RED,Y_RED};
	end
end
//px_data5：水平五等分标准彩条（红 / 绿 / 蓝 / 黑 / 白）
always @(posedge pclk or negedge system_rstn)begin
    if (!system_rstn)begin
		px_data5<=16'h1080;
	end
	else if((hcnt >= (HS+HBP)) && (hcnt < (HS+HBP+(HDISP/5)*1)))begin
		if(hcnt[0])
			px_data5<={CB_RED,Y_RED};
		else
			px_data5<={CR_RED,Y_RED};
	end
	else if((hcnt >= (HS+HBP+(HDISP/5)*1)) && (hcnt < (HS+HBP+(HDISP/5)*2)))begin
		if(hcnt[0])
			px_data5<={CB_GREEN,Y_GREEN};
		else
			px_data5<={CR_GREEN,Y_GREEN};
	end
	else if((hcnt >= (HS+HBP+(HDISP/5)*2)) && (hcnt < (HS+HBP+(HDISP/5)*3)))begin
		if(hcnt[0])
			px_data5<={CB_BLUE,Y_BLUE};
		else
			px_data5<={CR_BLUE,Y_BLUE};
	end
	else if((hcnt >= (HS+HBP+(HDISP/5)*3)) && (hcnt < (HS+HBP+(HDISP/5)*4)))begin
		if(hcnt[0])
			px_data5<={CB_BLACK,Y_BLACK};
		else
			px_data5<={CR_BLACK,Y_BLACK};
	end
	else begin
		if(hcnt[0])
			px_data5<={CB_WHIET,Y_WHIET};
		else
			px_data5<={CR_WHIET,Y_WHIET};
	end
end

always @(posedge pclk or negedge system_rstn)begin
  	if ((!system_rstn)||(!de_reg))
		pixel_dat<=16'h1080;
	else if(pt_sel == 'd0)
		pixel_dat<=px_data0;
	else if(pt_sel == 'd1)
		pixel_dat<=px_data1;
	else if(pt_sel == 'd2)
		pixel_dat<=px_data2;
	else if(pt_sel == 'd3)
		pixel_dat<=px_data3;
	else if(pt_sel == 'd4)
		pixel_dat<=px_data4;
	else if(pt_sel == 'd5)
		pixel_dat<=px_data5;
end




endmodule