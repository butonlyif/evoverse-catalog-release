`timescale 1ns/1ps
//============================================================================
// raw_wb_tb.sv — raw_wb_axis 单元回归（v5 RAW10 域白平衡）
//
// 参考模型独立实现：通道判定用标准 Bayer 2x2 位置表（{row,col} 直接查，
// 非 DUT 嵌套三元式转录）；增益公式同规格 §2（q=(p*g+2048)>>12，钳 1023）。
//
// 用例：
//   T1 unity 直通（0x1000x3 位精确，含随机气泡）+ 边带逐拍对齐
//   T2 四相位对照（V2）：4 相位 x 三通道异增益，逐像素比参考模型
//   T3 饱和 + dbg_sat 计数（dbg_sat 跨用例累计，全程对账）
//   T4 舍入边界点（0.5x/1.00024x 增益定点复核）
//   T5 pat_bypass=1 大增益强制 unity
//============================================================================

module raw_wb_tb;

    localparam LINES = 8;           // 每帧行数
    localparam BEATS = 6;           // 每行拍数（4px/拍 -> 24px/行）

    logic clk = 0, rstn = 0;
    always #5 clk = ~clk;

    // DUT 口
    logic [39:0] s_tdata;
    logic        s_tvalid, s_tlast;
    logic [2:0]  s_tuser;           // {eof, sol, sof}
    logic [1:0]  phase;
    logic [15:0] g_r, g_g, g_b;
    logic        pat_byp;
    logic [39:0] m_tdata;
    logic        m_tvalid, m_tlast;
    logic [2:0]  m_tuser;
    logic [15:0] dbg_sat;

    raw_wb_axis dut (
        .aclk(clk), .aresetn(rstn),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid),
        .s_axis_tlast(s_tlast), .s_axis_tuser(s_tuser),
        .bayer_phase(phase),
        .wb_r(g_r), .wb_g(g_g), .wb_b(g_b),
        .pat_bypass(pat_byp),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid),
        .m_axis_tlast(m_tlast), .m_axis_tuser(m_tuser),
        .dbg_sat(dbg_sat)
    );

    //--------------------------------------------------------------------
    // 参考模型（独立 Bayer 位置表 + 规格公式）
    //--------------------------------------------------------------------
    typedef enum int {C_R, C_G, C_B} ch_e;

    function automatic int g_ch_gain(input ch_e c, input int gr,
                                     input int gg, input int gb);
        return (c == C_R) ? gr : (c == C_B) ? gb : gg;
    endfunction

    function automatic ch_e ch_of(input int ph, input int row, input int col);
        int r = row & 1, c = col & 1;
        case (ph)
            0: ch_of = (r==0 && c==0) ? C_R : (r==1 && c==1) ? C_B : C_G; // RGGB
            1: ch_of = (r==0 && c==0) ? C_G : (r==0 && c==1) ? C_R :
                       (r==1 && c==0) ? C_B : C_G;                        // GRBG
            2: ch_of = (r==0 && c==0) ? C_G : (r==0 && c==1) ? C_B :
                       (r==1 && c==0) ? C_R : C_G;                        // GBRG
            default: ch_of = (r==0 && c==0) ? C_B : (r==1 && c==1) ? C_R
                               : C_G;                                     // BGGR
        endcase
    endfunction

    function automatic int model_q(input int pix, input ch_e c,
                                   input int gr, input int gg, input int gb);
        int q = (pix * g_ch_gain(c, gr, gg, gb) + 2048) >> 12;
        return (q > 1023) ? 1023 : q;
    endfunction

    // 期望输出队列（边带随拍入队，输出逐弹出比对）
    typedef struct packed {
        logic [39:0] dat;
        logic        lst;
        logic [2:0]  usr;
    } exp_t;
    exp_t exp_q[$];
    int   exp_sat;                  // 期望饱和拍累计（对账 dbg_sat 累计值）
    int   errors;

    task automatic push_beat(input logic [39:0] din, input int row,
                             input int bt, input int ph,
                             input int gr, input int gg, input int gb,
                             input logic bypass);
        logic [39:0] dout = '0;
        logic        satb = 1'b0;
        for (int p = 0; p < 4; p++) begin
            int col = bt*4 + p;
            int pix = din[10*p +: 10];
            ch_e c  = ch_of(ph, row, col);
            int q   = bypass ? pix : model_q(pix, c, gr, gg, gb);
            if (!bypass &&
                ((pix * g_ch_gain(c, gr, gg, gb) + 2048) >> 12) > 1023)
                satb = 1'b1;
            dout[10*p +: 10] = q[9:0];
        end
        exp_q.push_back('{dout,
                         (bt == BEATS-1),
                         {(row == LINES-1) && (bt == BEATS-1),   // eof
                          (bt == 0),                             // sol
                          (row == 0) && (bt == 0)}});            // sof
        exp_sat += satb;
    endtask

    //--------------------------------------------------------------------
    // 激励/比对
    //--------------------------------------------------------------------
    function automatic logic [39:0] beat_data(input int row, input int bt);
        logic [39:0] d = '0;
        for (int p = 0; p < 4; p++)
            d[10*p +: 10] = (row*BEATS*4 + bt*4 + p) % 1024;
        return d;
    endfunction

    // 驱动一帧；bub_en=1 时每拍后随机插 0~2 个气泡
    task automatic drive_frame(input int ph, input int gr, input int gg,
                               input int gb, input logic bypass,
                               input logic bub_en);
        phase   = ph[1:0];
        g_r     = gr[15:0];
        g_g     = gg[15:0];
        g_b     = gb[15:0];
        pat_byp = bypass;
        for (int row = 0; row < LINES; row++) begin
            for (int bt = 0; bt < BEATS; bt++) begin
                logic [39:0] din = beat_data(row, bt);
                logic eof = (row == LINES-1) && (bt == BEATS-1);
                push_beat(din, row, bt, ph, gr, gg, gb, bypass);
                @(negedge clk);
                s_tdata  <= din;
                s_tvalid <= 1'b1;
                s_tlast  <= (bt == BEATS-1);
                s_tuser  <= {eof, (bt == 0), (row == 0 && bt == 0)};
                @(negedge clk);
                s_tvalid <= 1'b0;
                s_tlast  <= 1'b0;
                s_tuser  <= 3'b0;
                if (bub_en)
                    repeat ($urandom_range(0, 2)) @(negedge clk);
            end
        end
    endtask

    // 饱和帧：全 1023 像素（指定增益必饱和）
    task automatic drive_sat_frame(input int gr, input int gg, input int gb);
        phase = 0;
        g_r   = gr[15:0];
        g_g   = gg[15:0];
        g_b   = gb[15:0];
        for (int row = 0; row < LINES; row++)
            for (int bt = 0; bt < BEATS; bt++) begin
                logic eof = (row == LINES-1) && (bt == BEATS-1);
                push_beat(40'h3FF3FF3FF3, row, bt, 0, gr, gg, gb, 1'b0);
                @(negedge clk);
                s_tdata  <= 40'h3FF3FF3FF3;
                s_tvalid <= 1'b1;
                s_tlast  <= (bt == BEATS-1);
                s_tuser  <= {eof, (bt == 0), (row == 0 && bt == 0)};
                @(negedge clk);
                s_tvalid <= 1'b0;
                s_tlast  <= 1'b0;
                s_tuser  <= 3'b0;
            end
    endtask

    // 输出比对循环（全程并行跑）
    initial forever begin
        @(posedge clk);
        if (m_tvalid) begin
            exp_t e;
            if (exp_q.size() == 0) begin
                errors++;
                $display("[TB][FAIL] 多余输出拍 dat=%h", m_tdata);
            end else begin
                e = exp_q.pop_front();
                if (m_tdata !== e.dat || m_tlast !== e.lst || m_tuser !== e.usr) begin
                    errors++;
                    $display("[TB][FAIL] 拍不齐 dat=%h(期%h) lst=%b(期%b) usr=%b(期%b)",
                             m_tdata, e.dat, m_tlast, e.lst, m_tuser, e.usr);
                end
            end
        end
    end

    task automatic drain_and_check(input string name);
        int guard = 0;
        while ((exp_q.size() != 0) && guard < 200) begin
            @(posedge clk);
            guard++;
        end
        repeat (4) @(posedge clk);
        if (exp_q.size() != 0) begin
            errors++;
            $display("[TB][FAIL] %s 期望拍未出齐（余 %0d）", name, exp_q.size());
        end
        if (dbg_sat !== exp_sat[15:0]) begin
            errors++;
            $display("[TB][FAIL] %s dbg_sat=%0d 期 %0d", name, dbg_sat, exp_sat);
        end
        if (errors == 0)
            $display("[TB][ ok ] %s", name);
    endtask

    //--------------------------------------------------------------------
    // 用例序列
    //--------------------------------------------------------------------
    initial begin
        exp_sat = 0;
        errors  = 0;
        s_tdata = '0; s_tvalid = 0; s_tlast = 0; s_tuser = 0;
        phase = 0; g_r = 16'h1000; g_g = 16'h1000; g_b = 16'h1000;
        pat_byp = 0;
        repeat (4) @(negedge clk);
        rstn = 1;
        repeat (2) @(negedge clk);

        // T1: unity 直通 + 气泡（RGGB，中性增益）
        drive_frame(0, 16'h1000, 16'h1000, 16'h1000, 1'b0, 1'b1);
        drain_and_check("T1 unity 直通+气泡 位精确");

        // T2: 四相位对照（V2），异增益无饱和（像素 <=191 不触顶）
        for (int ph = 0; ph < 4; ph++) begin
            drive_frame(ph, 16'h1400, 16'h0C00, 16'h1800, 1'b0, 1'b1);
            drain_and_check($sformatf("T2 相位 %0d 对照", ph));
        end
        phase = 0;

        // T3: 饱和 + dbg_sat（增益 1.5x，全 1023 -> 每拍饱和，累计对账）
        drive_sat_frame(16'h1800, 16'h1800, 16'h1800);
        drain_and_check("T3 饱和钳位 + dbg_sat 累计");

        // T4: 舍入边界定点复核（单拍帧：sof|sol|eof 同拍）
        //   px0=0(R,1.00024x)->0；px1=1(G,0.5x)->1
        //   px2=1023(R,1.00024x)->1023；px3=3(G,0x0801)->1
        g_r = 16'h1001; g_g = 16'h0800; g_b = 16'h0801;
        begin : t4
            logic [39:0] din = {10'd3, 10'd1023, 10'd1, 10'd0};
            push_beat(din, 0, 0, 0, g_r, g_g, g_b, 1'b0);
            exp_q[$].lst = 1'b1;                    // 单拍行/帧：last+eof
            exp_q[$].usr = 3'b111;
            @(negedge clk);
            s_tdata <= din; s_tvalid <= 1; s_tlast <= 1; s_tuser <= 3'b111;
            @(negedge clk);
            s_tvalid <= 0; s_tlast <= 0; s_tuser <= 0;
        end
        drain_and_check("T4 舍入边界点");
        g_r = 16'h1000; g_g = 16'h1000; g_b = 16'h1000;

        // T5: pat_bypass 大增益强制 unity
        pat_byp = 1'b1;
        drive_frame(0, 16'h3FFF, 16'h3FFF, 16'h3FFF, 1'b0, 1'b1);
        drain_and_check("T5 pat_bypass 强制 unity");
        pat_byp = 1'b0;

        if (errors == 0)
            $display("RAW_WB_TB: PASS errors=0");
        else
            $display("RAW_WB_TB: FAIL errors=%0d", errors);
        $finish;
    end

    // 超时看门狗
    initial begin
        #500000;
        $display("RAW_WB_TB: TIMEOUT");
        $finish;
    end

endmodule
