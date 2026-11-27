/////////////////////////////////////////////////////////////////////////////
// tb_cam_udp.v — G10 相机 UDP 直推链路仿真
// 复现板上「raw10 图案流 → kill → cam 启动 → 应发包」切换序列，
// 监视：写窗 armed / FIFO occ / pacer req / gen cam_r / AXI 输出。
// 相机激励：200M 域连续组流，每 CAM_FRM_QUADS 组一个 sof/eof 帧边界。
/////////////////////////////////////////////////////////////////////////////
`timescale 1 ns / 1 ps

module tb_cam_udp;

    // ---- 时钟 ----
    reg clk125 = 0;                 // 125M
    reg clk200 = 0;                 // 200M
    always #4  clk125 = ~clk125;    // 8ns
    always #2.5 clk200 = ~clk200;   // 5ns

    reg rstn = 0;

    // ---- CSR 模拟（reg_apb3 0x208 输出侧）----
    reg        udp_en   = 0;        // bit0
    reg        raw10_en = 0;        // bit2
    reg        kill     = 0;        // bit3
    reg        cam_en   = 0;        // bit6（跨 3 域直连，tb 忠实复刻）
    reg [1:0]  pat_mode = 0;        // bit5:4
    reg [15:0] pat_num  = 16'd0;    // 0=无限
    reg [15:0] pat_ipg  = 16'd12;

    // ---- 相机像素流激励（200M 域）----
    reg        raw_tvalid = 0;
    reg [39:0] raw_tdata  = 0;
    reg [2:0]  raw_tuser  = 0;      // 真实编码 {eof,sol,sof}：bit0=sof 帧首，bit2=eof 帧末

    // ---- 写窗逻辑（复刻 ws_e1_tse.v 200M 块）----
    reg  [1:0]  cam_src_sy;
    reg         cam_udp_wr_en, cam_udp_armed;
    reg  [9:0]  cam_udp_wcnt, cam_udp_wgray;
    reg         cam_udp_sof_tg;
    reg         cam_udp_eof_evt_r;
    reg  [1:0]  cam_udp_wr_rst_cnt;
    wire        cam_udp_sof_evt = raw_tvalid && raw_tuser[2];
    wire        cam_udp_eof_evt = raw_tvalid && raw_tuser[0];
    wire        cam_udp_full;
    wire        cam_udp_wr_rst_n_w = (cam_udp_wr_rst_cnt == 2'b00);
    integer     cam_byte;        // 相机组数据指纹

    always @(posedge clk200 or negedge rstn) begin
        if (!rstn) begin
            cam_src_sy <= 0; cam_udp_armed <= 0; cam_udp_wr_en <= 0;
            cam_udp_wcnt <= 0; cam_udp_wgray <= 0; cam_udp_sof_tg <= 0;
            cam_udp_eof_evt_r <= 0; cam_udp_wr_rst_cnt <= 0;
        end else begin
            cam_src_sy <= {cam_src_sy[0], cam_en};
            if (cam_udp_eof_evt)
                cam_udp_sof_tg <= ~cam_udp_sof_tg;
            if (cam_udp_sof_evt) begin
                cam_udp_armed <= cam_src_sy[1];
                cam_udp_wr_en <= cam_src_sy[1] && !cam_udp_full && (cam_udp_wr_rst_cnt == 0);
            end else begin
                cam_udp_wr_en <= cam_udp_armed && raw_tvalid && !cam_udp_full
                                 && (cam_udp_wr_rst_cnt == 0);
            end
            cam_udp_eof_evt_r <= cam_udp_eof_evt;
            if (cam_udp_eof_evt_r && cam_udp_wr_rst_cnt == 0)
                cam_udp_wr_rst_cnt <= 2'd2;
            else if (cam_udp_wr_rst_cnt != 0) begin
                cam_udp_wr_rst_cnt <= cam_udp_wr_rst_cnt - 1;
                if (cam_udp_wr_rst_cnt == 1) begin
                    cam_udp_wcnt  <= 0;
                    cam_udp_wgray <= 0;
                end
            end
            if (cam_udp_wr_en) begin
                cam_udp_wcnt  <= cam_udp_wcnt + 1;
                cam_udp_wgray <= (cam_udp_wcnt + 1) ^ ((cam_udp_wcnt + 1) >> 1);
            end
        end
    end

    // ---- gen/pacer 互连 ----
    wire [39:0] cam_udp_dout;
    wire        cam_udp_empty;
    wire        cam_pkt_req_w, cam_quad_rd_w;
    wire [31:0] cam_udp_status;
    wire        cam_udp_rd_rst_n;
    wire [9:0]  dbg_state;
    wire [7:0]  tdata;
    wire        tvalid, tlast;
    reg         tready = 1'b1;      // 下游 MAC 永远 ready（等价线速）

    // pacer 状态探针分解（status_o = {qidx[17:0],2'b00,act,done,occ[9:0]}）
    wire [17:0] pacer_qidx   = cam_udp_status[31:14];
    wire        pacer_active = cam_udp_status[11];
    wire        pacer_done   = cam_udp_status[10];
    wire [9:0]  pacer_occ    = cam_udp_status[9:0];

    // gen state 探针
    wire [2:0] gen_state   = dbg_state[5:3];
    wire gen_cam_r    = dbg_state[7];    // pat_dbg_i 位序 {raw10_r,pat_en,inf,state,ft,en_d1,0}
                                        // dbg_state_o = {raw10_en,raw10_r,pat_en,inf,state,ft,en_d1,tvalid}
                                        // → raw10_r=bit8, pat_en=bit7...cam_r 不在探针里，用层次引用
    wire gen_raw10_r  = u_gen.raw10_r;
    wire gen_cam_r_h  = u_gen.cam_r;

    udp_pat_gen_v2 #(
        .FRAME_PERIOD (23'd20000)        // 缩帧周期：160µs（真实 4.167ms）
    ) u_gen (
        .clk          (clk125      ),
        .rstn         (rstn        ),
        .pat_gen_en   (udp_en      ),
        .pat_gen_num  (pat_num     ),
        .pat_gen_ipg  (pat_ipg     ),
        .raw10_en     (raw10_en    ),
        .pat_mode     (pat_mode    ),
        .pat_gen_kill (kill        ),
        .cam_en       (cam_en      ),
        .cam_pkt_req  (cam_pkt_req_w ),
        .cam_quad_i   (cam_udp_dout  ),
        .cam_quad_valid(!cam_udp_empty),
        .cam_quad_rd  (cam_quad_rd_w ),
        .dst_mac      (48'hAABBCCDDEEFF ),
        .src_mac      (48'h112233445566 ),
        .src_ip       (32'h0A000008 ),
        .dst_ip       (32'h0A000003 ),
        .udp_dlen     (16'd1458    ),
        .src_port     (16'h2710    ),
        .dst_port     (16'h2715    ),
        .tdata        (tdata       ),
        .tvalid       (tvalid      ),
        .tlast        (tlast       ),
        .tready       (tready      ),
        .frame_num_o  (            ),
        .dbg_state_o  (dbg_state   )
    );

    cam_udp_pacer #(
        .START_THR (300),
        .FIFO_AW   (10)
    ) u_pacer (
        .clk           (clk125        ),
        .rstn          (rstn          ),
        .cam_en        (cam_en        ),
        .sof_toggle    (cam_udp_sof_tg),
        .wq_gray       (cam_udp_wgray ),
        .cam_quad_rd   (cam_quad_rd_w ),
        .gen_state     (dbg_state[5:3]),
        .cam_pkt_req   (cam_pkt_req_w ),
        .status_o      (cam_udp_status),
        .fifo_rd_rst_n (cam_udp_rd_rst_n)
    );

    async_fwft_fifo #(
        .WIDTH (40),
        .DEPTH (1024)
    ) u_fifo (
        .wr_clk   (clk200                  ),
        .wr_rst_n (rstn & cam_udp_wr_rst_n_w),
        .wr_en    (cam_udp_wr_en           ),
        .din      (raw_tdata               ),
        .full     (cam_udp_full            ),
        .rd_clk   (clk125                  ),
        .rd_rst_n (rstn & cam_udp_rd_rst_n ),
        .rd_en    (cam_quad_rd_w           ),
        .dout     (cam_udp_dout            ),
        .empty    (cam_udp_empty           )
    );

    // ---- 相机流发生：真实编码 {eof,sol,sof}（bit0=sof 帧首 / bit2=eof 帧末）、
    //      真实节拍 12 拍/组（16.4M 组/s @200M）、每帧后消隐 BLANK 拍 ----
    localparam integer CAM_FRM_QUADS = 2048;   // 仿真短帧（真实 518400）
    localparam integer CAM_BLANK     = 400;    // 帧间消隐拍数
    integer qidx = 0, qdiv = 0;
    always @(posedge clk200) begin
        if (!rstn) begin
            raw_tvalid <= 0; qidx <= 0; qdiv <= 0;
        end else begin
            if (qdiv == 11) begin
                qdiv <= 0;
                // 组拍
                raw_tvalid <= 1'b1;
                raw_tdata  <= {4{cam_byte[9:0]}};
                raw_tuser  <= 3'b000;
                if (qidx == 0) raw_tuser[0] <= 1'b1;                       // sof（bit0）
                if (qidx == CAM_FRM_QUADS-1) raw_tuser[2] <= 1'b1;         // eof（bit2）
                qidx <= (qidx == CAM_FRM_QUADS-1) ? 0 : qidx + 1;
                cam_byte <= cam_byte + 1;
            end else begin
                qdiv <= qdiv + 1;
                if (qidx == 0 && qdiv == 1) raw_tvalid <= 1'b0;            // 消隐开始（帧边界后）
                if (qdiv == 10) raw_tvalid <= 1'b1;                        // 消隐结束
            end
        end
    end

    // ---- AXI 输出监视 ----
    integer out_bytes = 0, out_pkts = 0;
    reg [7:0] pay8 [0:7];
    always @(posedge clk125) begin
        if (tvalid && tready) begin
            out_bytes <= out_bytes + 1;
            if (tlast) out_pkts <= out_pkts + 1;
        end
    end

    // ---- 激励 ----
    integer i;
    task csr_step(input integer v);       // 模拟固件写 0x208（同一拍更新各位）
        begin
            udp_en   <= v[0];
            raw10_en <= v[2];
            kill     <= v[3];
            pat_mode <= v[5:4];
            cam_en   <= v[6];
            #200000;                      // 固件 bsp_uDelay(100) = 100µs
        end
    endtask

    task show(string tag);
        begin
            $display("[%0t ns] %s: gen{en=%b raw10r=%b camr=%b paten=%b st=%0d} pacer{act=%b done=%b req=%b qidx=%0d occ=%0d} fifo{we=%b fe=%b} OUT{pkts=%0d B=%0d}",
                $time, tag, udp_en, gen_raw10_r, gen_cam_r_h, u_gen.pat_en, gen_state,
                pacer_active, pacer_done, cam_pkt_req_w, pacer_qidx, pacer_occ,
                cam_udp_wr_en, cam_udp_empty, out_pkts, out_bytes);
        end
    endtask

    initial begin
        cam_byte = 16'h0100;
        #100 rstn = 1;
        #1000;

        // ===== 阶段1：raw10 图案流启动（固件 v 序列 0x4→0x5→0x4）=====
        csr_step(8'h04);
        csr_step(8'h05);
        csr_step(8'h04);
        #50000;   // 等 2-3 帧图案包
        show("AFTER-PAT");
        if (out_pkts == 0) begin $display("*** FAIL: raw10 图案流没起来"); $finish; end

        // ===== 阶段2：kill 停车（固件 StreamStop：0x0C → 等 IDLE → 0x04）=====
        csr_step(8'h0C);                  // kill=1（raw10 电平保持）
        wait (gen_state == 3'h0);
        #100;
        show("AFTER-KILL");
        kill <= 0; #200000;

        // ===== 阶段3：cam 启动（固件 c 序列 0x4→0x45→0x44）=====
        out_bytes = 0; out_pkts = 0;
        csr_step(8'h04);
        csr_step(8'h45);
        csr_step(8'h44);
        #200000;                          // cam 需等 sof 开窗 + occ≥300 + 发包
        show("AFTER-CAM-200us");
        #500000;
        show("AFTER-CAM-700us");

        if (out_pkts == 0)
            $display("*** FAIL: cam 模式 %0t ns 后仍 0 包（复现板上现象）", $time);
        else
            $display("*** PASS: cam 流发包 %0d", out_pkts);
        $finish;
    end

    initial begin
        #3000000 $display("*** TIMEOUT"); $finish;
    end
endmodule
