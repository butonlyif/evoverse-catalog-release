//============================================================================
// tb_axi4_st_mux3 : 3 选 1 AXI4-Stream mux 自校验 testbench
// 运行: vsim -c tb_axi4_st_mux3 -do "run -all; quit -f"
//============================================================================
`timescale 1ns/1ps
module tb_axi4_st_mux3;

reg clk = 0;
always #5 clk = ~clk;

reg  [1:0]  sel;
reg  [7:0]  tdata0, tdata1, tdata2;
reg         tvalid0, tvalid1, tvalid2;
reg         tlast0, tlast1, tlast2;
reg         tuser0, tuser1, tuser2;
wire        tready0, tready1, tready2;
wire [7:0]  tdata;
wire        tvalid, tlast, tuser;
reg         tready;

integer errors;

axi4_st_mux3 dut (
    .mux_select             (sel),
    .tdata0(tdata0), .tvalid0(tvalid0), .tlast0(tlast0), .tuser0(tuser0), .tready0(tready0),
    .tdata1(tdata1), .tvalid1(tvalid1), .tlast1(tlast1), .tuser1(tuser1), .tready1(tready1),
    .tdata2(tdata2), .tvalid2(tvalid2), .tlast2(tlast2), .tuser2(tuser2), .tready2(tready2),
    .tdata(tdata), .tvalid(tvalid), .tlast(tlast), .tuser(tuser), .tready(tready)
);

//单路发送: 在指定路上发一字
task send(input integer path, input [7:0] d, input last, input usr);
    begin
        case (path)
        0: begin tdata0 = d; tvalid0 = 1; tlast0 = last; tuser0 = usr; end
        1: begin tdata1 = d; tvalid1 = 1; tlast1 = last; tuser1 = usr; end
        2: begin tdata2 = d; tvalid2 = 1; tlast2 = last; tuser2 = usr; end
        endcase
        @(posedge clk);
        case (path)
        0: tvalid0 = 0;
        1: tvalid1 = 0;
        2: tvalid2 = 0;
        endcase
        #1;
    end
endtask

//期望输出检查
task expect_out(input [7:0] d, input last, input usr, input rdy_exp, input [8*10-1:0] tag);
    begin
        if (tdata !== d || tlast !== last || tuser !== usr) begin
            errors = errors + 1;
            $display("[FAIL] %0s: out=%02x(last=%b,user=%b) expect %02x(last=%b,user=%b)",
                     tag, tdata, tlast, tuser, d, last, usr);
        end
        if (tready !== rdy_exp) begin
            errors = errors + 1;
            $display("[FAIL] %0s: tready=%b expect %b", tag, tready, rdy_exp);
        end
    end
endtask

initial begin
    errors = 0;
    sel = 2'b00; tdata0 = 0; tdata1 = 0; tdata2 = 0;
    tvalid0 = 0; tvalid1 = 0; tvalid2 = 0;
    tlast0 = 0; tlast1 = 0; tlast2 = 0;
    tuser0 = 0; tuser1 = 0; tuser2 = 0;
    tready = 1'b1;
    repeat (5) @(posedge clk);

    //--------------------------------------------------------------
    // TEST1: sel=00 选通路 0，通路 1/2 恒 tready=1
    //--------------------------------------------------------------
    $display("[TEST1] select=00");
    sel = 2'b00;
    send(0, 8'hA0, 1'b1, 1'b0); #1;
    expect_out(8'hA0, 1'b1, 1'b0, 1'b1, "sel00 path0");
    send(1, 8'hB1, 1'b0, 1'b1); #1;
    if (tvalid !== 1'b0) begin
        errors = errors + 1;
        $display("[FAIL] sel00 path1 leaked to output");
    end
    if (tready1 !== 1'b1 || tready2 !== 1'b1) begin
        errors = errors + 1;
        $display("[FAIL] unselected path tready not forced 1");
    end
    if (errors == 0) $display("[PASS] TEST1");

    //--------------------------------------------------------------
    // TEST2: sel=01 选通路 1，tready=0 时选中通路 tready 拉低
    //--------------------------------------------------------------
    $display("[TEST2] select=01");
    sel = 2'b01;
    tready = 1'b0;
    send(1, 8'hC2, 1'b1, 1'b0); #1;
    expect_out(8'hC2, 1'b1, 1'b0, 1'b0, "sel01 path0 tready=0");
    tready = 1'b1;
    send(0, 8'hD3, 1'b0, 1'b0); #1;
    if (tvalid !== 1'b0) begin
        errors = errors + 1;
        $display("[FAIL] sel01 path0 leaked to output");
    end
    if (errors == 0) $display("[PASS] TEST2");

    //--------------------------------------------------------------
    // TEST3: sel=1x 选通路 2（两值均选中）
    //--------------------------------------------------------------
    $display("[TEST3] select=1x");
    sel = 2'b10;
    send(2, 8'hE4, 1'b0, 1'b1); #1;
    expect_out(8'hE4, 1'b0, 1'b1, 1'b1, "sel10 path2");
    sel = 2'b11;
    send(2, 8'hF5, 1'b1, 1'b0); #1;
    expect_out(8'hF5, 1'b1, 1'b0, 1'b1, "sel11 path2");
    if (tready0 !== 1'b1 || tready1 !== 1'b1) begin
        errors = errors + 1;
        $display("[FAIL] sel1x unselected tready not 1");
    end
    if (errors == 0) $display("[PASS] TEST3");

    //--------------------------------------------------------------
    repeat (5) @(posedge clk);
    if (errors == 0)
        $display("=== TB_AXI4_ST_MUX3: ALL TESTS PASSED ===");
    else
        $display("=== TB_AXI4_ST_MUX3: %0d ERRORS ===", errors);
    $finish;
end

endmodule
`default_nettype wire
