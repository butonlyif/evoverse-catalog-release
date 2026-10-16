
`timescale 1ps/1ps
module memory_checker (

input axi_clk,
input rstn,
input start,
output [5:0] awid,
output reg [32:0] awaddr,
output reg [7:0] awlen,
output reg [2:0] awsize,
output reg [1:0] awburst,
output reg [3:0] awcache,
output reg awlock,
output reg awvalid,
output reg awcobuf,
output reg awapcmd,
output reg awallstrb,
output reg awqos,
input awready,
output reg atype,

output [5:0] arid,
output reg [32:0] araddr,
output reg [7:0] arlen,
output reg [2:0] arsize,
output reg [1:0] arburst,
output reg arlock,
output reg arvalid,
output reg arapcmd,
output reg arqos,
input arready,

output reg [511:0] wdata,
output  [63:0] wstrb,
output reg wlast,
output reg wvalid,
input wready,

input [5:0] rid,
input [511:0] rdata,
output reg [511:0] rdata_obs,
input rlast,
input rvalid,
output reg rready,
input [1:0] rresp,

input [5:0] bid,
input bvalid,
output reg bready,

output reg fail,
output reg done,
output reg [511:0] rdata_exp

);

assign awid = 6'h00;
assign arid = 6'h00;
assign wstrb = 64'hFFFFFFFF_FFFFFFFF;

parameter ALEN = 5;
parameter ASIZE = 6;
parameter START_ADDR = 33'h000000000; 
parameter STOP_ADDR = 33'h000001900;
parameter ADDR_OFFSET = (ALEN + 1)*64;
//Main states
localparam
	IDLE = 4'b0000, 
	WRITE_ADDR = 4'b0001,
	PRE_WRITE = 4'b0010,
	WRITE = 4'b0011,
	POST_WRITE = 4'b0100,
	READ_ADDR = 4'b0101,
	PRE_READ = 4'b0110,
	READ_COMPARE = 4'b0111,
	POST_READ = 4'b1000,
	DONE = 4'b1001;

reg [3:0] states, nstates;
reg bvalid_done;
reg [1:0] start_sync;
reg [8:0] write_cnt, nxt_cnt, read_cnt;
reg [511:0] rdata_store;
reg wburst_done, rburst_done, write_done, read_done;
always @(posedge axi_clk or negedge rstn) begin
	if (!rstn) begin
		start_sync <= 2'b00;
	end else begin
		start_sync[0] <= start;
		start_sync[1] <= start_sync[0];
	end
end

always @(posedge axi_clk or negedge rstn) begin
 	if (!rstn) begin
	states <= IDLE;
	end else begin
	states <= nstates;
	end
end

always @(states or start_sync[1] or write_cnt or rburst_done or write_done or read_done or bvalid_done or awready or arready or wready) begin
	case(states) 
	IDLE 	   : if (start_sync[1]) 			nstates = WRITE_ADDR;
	             else					nstates = IDLE;
	WRITE_ADDR : 						nstates = PRE_WRITE;
	PRE_WRITE  : if (awready & wready)			nstates = WRITE;
		     else					nstates = PRE_WRITE;
	WRITE	   : if (write_cnt == 9'd0)			nstates = POST_WRITE;
		     else		 			nstates = WRITE;
	POST_WRITE : if (write_done & bvalid_done) 		nstates = READ_ADDR;
		     else if (bvalid_done)			nstates = WRITE_ADDR;
		     else					nstates = POST_WRITE;
	READ_ADDR  : if (arready) 				nstates = PRE_READ;
		     else					nstates = READ_ADDR;
	PRE_READ   :						nstates = READ_COMPARE;
	READ_COMPARE  : if (rburst_done) 			nstates = POST_READ;
			else					nstates = READ_COMPARE;
	POST_READ  :	if (read_done) 				nstates = DONE;
			else					nstates = READ_ADDR;
	DONE	   :    if (start_sync[1])	        nstates = DONE;
            else 
                        nstates = IDLE;
    
    
    
	default							nstates = IDLE;
	endcase
end

reg wready_f;

always @(posedge axi_clk or negedge rstn) begin
	if (!rstn) begin
		nxt_cnt <= 9'd0;
	end else begin
		nxt_cnt <= write_cnt - 1'b1;
	end 

end

always @(posedge axi_clk or negedge rstn) begin
	if (!rstn) begin
		awaddr <= START_ADDR;
		awvalid <= 1'b0;
		atype <= 1'b0;
		awburst <= 2'b00;
		awsize <= 3'b000;
		awlen <= 8'd0;
		awlock <= 1'b0;
		awcobuf <= 1'b0;
		awapcmd <= 1'b0;
		awallstrb <= 1'b0;
		awcache <= 4'd0;
		awqos <= 1'b0;
	        araddr <= 33'd0;
                arvalid <= 1'b0;
                arburst <= 2'b00;
                arsize <= 3'b000;
                arlen <= 8'd0;
                arlock <= 1'b0;
                arapcmd <= 1'b0;
                arqos <= 1'b0;
		wvalid <= 1'b0;
		write_cnt <= ALEN;
		write_done <= 1'b0;
		wdata <= 512'd0;
		wburst_done <= 1'b0;
		wlast <= 1'b0;
		bready <= 1'b0;
		fail <= 1'b0;
		done <= 1'b0;
		rready <= 1'b0;
		bvalid_done <=1'b0;
		wready_f <= 1'b0;
        rdata_obs <= 512'd0;
        rdata_exp <= 512'd0;
	end else begin
		if (states == IDLE) begin
	                awaddr <= START_ADDR;
	                awvalid <= 1'b0;
        	        atype <= 1'b0;
               	 	awburst <= 2'b00;
                	awsize <= 3'b000;
                	awlen <= 8'd0;
                	awlock <= 1'b0;
			awcobuf <= 1'b0;
			awapcmd <= 1'b0;
			awallstrb <= 1'b0;
			awcache <= 4'd0;
			awqos <= 1'b0;
			arqos <= 1'b0;
	                araddr <= START_ADDR;
        	        arvalid <= 1'b0;
               		arburst <= 2'b00;
                	arsize <= 3'b000;
                	arlen <= 8'd0;
                	arlock <= 1'b0;
                	arapcmd <= 1'b0;
                	wvalid <= 1'b0;
                	write_cnt <= ALEN + 1;
                	wdata <= 256'd0;
                	wburst_done <= 1'b0;
                	wlast <= 1'b0;
                	bready <= 1'b0;
			rready <= 1'b0;
			bvalid_done <= 1'b0;
			fail <= 1'b0;
			done <= 1'b0;
		end
		if (states == WRITE_ADDR) begin
			awvalid <= 1'b1;
			atype <= 1'b1;
			awsize <= ASIZE;
			awlen <= ALEN;
			awburst <= 2'b01;
			awlock <= 2'b00;
			awqos <= 1'b1;
			wvalid <= 1'b0;
			write_cnt <= write_cnt - 1;
			wburst_done <= 1'b0;
			bvalid_done <= 1'b0;
			bready <= 1'b0;
			rready <= 1'b0;
			done <= 1'b0;
			fail <= 1'b0;
                        wdata <= {{~awaddr[31:0], awaddr[31:0], {8{write_cnt[7:0]}}, awaddr[31:0], ~awaddr[31:0], {8{~write_cnt[7:0]}}},{awaddr[31:0], ~awaddr[31:0], {8{~write_cnt[7:0]}}, ~awaddr[31:0], awaddr[31:0], {8{write_cnt[7:0]}}}};

		end
		if (states == PRE_WRITE) begin
		      if (awready) begin
			awvalid <= 1'b0;
		      end else begin
			awvalid <= 1'b1;
		      end		
			atype <= 1'b0;
			bready <= 1'b1;
		      if(wready & wvalid) begin
			wready_f <= 1'b1;
                        write_cnt <= write_cnt - 1;
			wdata <= {{~awaddr[31:0], awaddr[31:0], {8{write_cnt[7:0]}}, awaddr[31:0], ~awaddr[31:0], {8{~write_cnt[7:0]}}},{awaddr[31:0], ~awaddr[31:0], {8{~write_cnt[7:0]}}, ~awaddr[31:0], awaddr[31:0], {8{write_cnt[7:0]}}}};
			if (write_cnt == 9'd1) begin
				wlast <= 1'b1;
			end
		      end else begin
			wvalid <= 1'b1;
		      end
		end
		if (states == WRITE) begin
			if (wready) begin
				if (write_cnt == 9'd0) begin
				wburst_done <= 1'b1;
				wlast <= 1'b0;
				wvalid <= 1'b0;
					if (awaddr >= STOP_ADDR) begin
					write_done <= 1'b1;
					end else begin
					write_done <= 1'b0;
					end
				end else if (write_cnt == 9'd1) begin
					wlast <= 1'b1;
					write_cnt <= write_cnt - 1;
		                        wdata <= {{~awaddr[31:0], awaddr[31:0], {8{write_cnt[7:0]}}, awaddr[31:0], ~awaddr[31:0], {8{~write_cnt[7:0]}}},{awaddr[31:0], ~awaddr[31:0], {8{~write_cnt[7:0]}}, ~awaddr[31:0], awaddr[31:0], {8{write_cnt[7:0]}}}};

				end else begin
				write_cnt <= write_cnt - 1;
	                        wdata <= {{~awaddr[31:0], awaddr[31:0], {8{write_cnt[7:0]}}, awaddr[31:0], ~awaddr[31:0], {8{~write_cnt[7:0]}}},{awaddr[31:0], ~awaddr[31:0], {8{~write_cnt[7:0]}}, ~awaddr[31:0], awaddr[31:0], {8{write_cnt[7:0]}}}};

				end
			end
		end
		if (states == POST_WRITE) begin
			if (write_done) begin
				awaddr <= START_ADDR;
			end else begin
				if (bvalid) begin
				awaddr <= awaddr + ADDR_OFFSET;
				write_cnt <= ALEN + 1;
				end
			end
			if (wready == 1'b1) begin
				wlast <= 1'b0;	
				wvalid <= 1'b0;	
			end
			if (bvalid) begin
				bvalid_done <= 1'b1;
				bready <= 1'b0;
			end
		end
		if (states == READ_ADDR) begin
			arvalid <= 1'b1;
			read_cnt <= ALEN + 1;
			arsize <= ASIZE;
			arlen <= ALEN;
			arburst <= 2'b01; 
				
		end
		if (states == PRE_READ) begin
			arvalid <= 1'b0;
			rburst_done <= 1'b0;
                        rdata_store <= {{~araddr[31:0], araddr[31:0], {8{read_cnt[7:0]}},araddr[31:0],~araddr[31:0],{8{~read_cnt[7:0]}}},{araddr[31:0], ~araddr[31:0], {8{~read_cnt[7:0]}},~araddr[31:0],araddr[31:0],{8{read_cnt[7:0]}}}};
			read_cnt <= read_cnt - 1'b1;
		end
		if (states == READ_COMPARE) begin
			rready <= 1'b1;
			if (read_cnt != 9'd0) begin
			if (rvalid == 1'b1) begin
                        rdata_store <= {{~araddr[31:0], araddr[31:0], {8{read_cnt[7:0]}},araddr[31:0],~araddr[31:0],{8{~read_cnt[7:0]}}},{araddr[31:0], ~araddr[31:0], {8{~read_cnt[7:0]}},~araddr[31:0],araddr[31:0],{8{read_cnt[7:0]}}}};
			read_cnt <= read_cnt - 1'b1;
				if (rdata != rdata_store) begin
					rdata_obs <= rdata;
                    rdata_exp <= rdata_store;
					fail <= 1'b1;
					`ifdef EFX_SIM
					$display("ERROR!! Read mismatch : read = 0x%x, expected = 0x%x",rdata,rdata_store);
					`endif 
				end else begin
					`ifdef EFX_SIM
					$display("Read match: read = 0x%x, expected = 0x%x",rdata,rdata_store);
					`endif
				end
	
			end
			end
			if (read_cnt == 9'd0) begin
	                        if (rvalid == 1'b1) begin
                                       if (rdata !== rdata_store) begin
                                                fail <= 1'b1;
                                                `ifdef EFX_SIM
                                                $display("ERROR!! Read mismatch : read = 0x%x, expected = 0x%x",rdata,rdata_store);
                                                `endif
                                        end else begin
                                                `ifdef EFX_SIM
                                                $display("Read match: read = 0x%x, expected = 0x%x",rdata,rdata_store);
                                                `endif
                                        end


					if (araddr >= STOP_ADDR) begin
						read_done <= 1'b1;
					end else begin
						read_done <= 1'b0;
					end
					rburst_done <= 1'b1;
				end
			end	
		end
		if (states == POST_READ) begin
			araddr <= araddr + ADDR_OFFSET;
			rready <= 1'b1;
		end
		if (states == DONE) begin
			done <= 1'b1;
		end
	end

end




endmodule
