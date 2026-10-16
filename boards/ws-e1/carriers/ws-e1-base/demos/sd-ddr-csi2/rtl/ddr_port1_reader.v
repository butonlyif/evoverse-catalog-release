//============================================================================
// ddr_port1_reader.v
//
// DDR Port 1 read-path verification engine.
//
// Reads a byte range from the DDR hard controller AXI Port 1 (512-bit),
// computes a 64-bit additive checksum (sum of all 32-bit words, matching the
// software-side calc_sum64) and captures the first/last beat word for quick
// debug. Firmware compares the result against the CPU (Port 0) view of the
// same range to prove: SD ADMA -> DDR Port0 write -> DDR Port1 read path.
//
// Register map (APB, word offsets):
//   0x00 ID      : 0x50315231 ("P1R1")
//   0x04 CTRL    : [0] START (write 1 to launch), [1] CLR_DONE
//   0x08 STATUS  : [0] BUSY, [1] DONE, [2] SLVERR
//   0x0C ADDR    : start byte address (must be 64-byte aligned)
//   0x10 LEN     : length in bytes (multiple of 64)
//   0x14 BEATS   : beats completed (64 bytes each)
//   0x18 SUM_LO  : checksum [31:0]
//   0x1C SUM_HI  : checksum [63:32]
//   0x20 FIRST_W0: word0 of the first beat
//   0x24 LAST_W0 : word0 of the last beat
//   0x28 RLAST_BURST: beats returned by the macro in the last burst
//   0x2C RID_FIRST: RID of the first R beat  (ghost-response probe)
//   0x30 RID_LAST : RID of the last  R beat  (ghost-response probe)
//   0x34 AR_DELAY : cycles in FSM_AR before ARREADY (0xFF = never)
//   0x38 IDLE_RV  : rising edges of RVALID while idle after DONE
//                   (non-zero = the macro spuriously emits R beats on
//                    its own - a stuck/ghost response stream)
//
// Single clock domain: aclk = sys_clk_125m (125 MHz) - the whole SoC and both
// DDR AXI ports share this one clock since the Interface Designer clock merge.
//============================================================================

module ddr_port1_reader #(
    parameter integer AXI_ID_W = 6
)(
    input  wire                  aclk,
    input  wire                  aresetn,

    // APB slave (SoC io_apbSlave_0)
    input  wire [15:0]           paddr,
    input  wire                  psel,
    input  wire                  penable,
    input  wire                  pwrite,
    input  wire [31:0]           pwdata,
    output wire [31:0]           prdata,
    output wire                  pready,
    output wire                  pslverror,

    // AXI4 read master -> DDR Port 1
    output wire [31:0]           araddr,
    output wire [1:0]            arburst,
    output wire [AXI_ID_W-1:0]   arid,
    output wire [7:0]            arlen,
    output wire                  arlock,
    output wire                  arqos,
    output wire [2:0]            arsize,
    output wire                  arvalid,
    input  wire                  arready,
    input  wire [AXI_ID_W-1:0]   rid,
    input  wire                  rlast,
    input  wire [1:0]            rresp,
    input  wire                  rvalid,
    output wire                  rready,
    input  wire [511:0]          rdata
);

    localparam [2:0] FSM_IDLE  = 3'd0;
    localparam [2:0] FSM_AR    = 3'd1;
    localparam [2:0] FSM_DATA  = 3'd2;
    localparam [2:0] FSM_DONE  = 3'd3;

    reg [2:0]   fsm;
    reg [31:0]  addr_reg;
    reg [31:0]  len_reg;       // bytes
    reg [20:0]  beats_total;   // 64B beats
    reg [20:0]  beats_done;
    reg [8:0]   burst_rcvd;    // beats received in the current burst
    reg [8:0]   rlast_burst;   // burst_rcvd latched at RLAST (diagnostics)
    reg [5:0]   rid_first;     // RID of the very first R beat of the run
    reg [5:0]   rid_last;      // RID of the most recent R beat
    reg [7:0]   ar_delay;      // cycles spent in FSM_AR before ARREADY
    reg [7:0]   ar_ticks;      // cycle counter inside the current FSM_AR
    reg [15:0]  idle_rv_cnt;   // RVALID rising edges seen while idle
    reg         rvalid_d;      // RVALID edge detector
    reg         busy;
    reg         done;
    reg         slverr;
    // sticky observability for on-board bring-up: did the macro ever raise
    // RVALID / RLAST during this run? (cleared on START)
    reg         rvalid_seen;
    reg         rlast_seen;

    reg [63:0]  sum;
    reg [31:0]  first_w0;
    reg [31:0]  last_w0;

    // NOTE: the AR request channel is driven COMBINATIONALLY (araddr/arlen/
    // arvalid assigns below), exactly like the passing baseline reader in
    // TJ180A484S-good. A previous build registered the request
    // (araddr_q/arlen_q/arvalid_q) and Efinity synthesis silently dropped
    // the arlen_q[7:1] FFs (mapped netlist: ARLEN_1[7:1] tied to GND, only
    // ARLEN_1[0] kept an FF, D = burst_beats[0]) - the board then showed
    // rb = ARLEN[0]+1 on every burst. Do not re-register arlen.

    wire        apb_fire = psel & penable;

    // Beat input pipeline stage: register the 512-bit beat one cycle so the
    // checksum adder tree starts from registers (closed timing at 125 MHz on
    // sys_clk_125m; the DDR hard macro RDATA routing no longer
    // feeds the tree directly).
    reg [511:0] rdata_q;
    reg          rvalid_q;
    reg [1:0]    rresp_q;
    reg          rlast_q;
    reg [5:0]    rid_q;
    always @(posedge aclk) begin
        rdata_q  <= rdata;
        rvalid_q <= rvalid;
        rresp_q  <= rresp;
        rlast_q  <= rlast;
        rid_q    <= rid;
    end

    // 64-bit additive checksum of one 512-bit beat (16 x 32-bit words).
    // Balanced 4-level adder tree over the registered beat (the previous
    // serial 16-add chain was the critical path at 125 MHz).
    wire [32:0] s1_0 = rdata_q[ 31:  0] + rdata_q[ 63: 32];
    wire [32:0] s1_1 = rdata_q[ 95: 64] + rdata_q[127: 96];
    wire [32:0] s1_2 = rdata_q[159:128] + rdata_q[191:160];
    wire [32:0] s1_3 = rdata_q[223:192] + rdata_q[255:224];
    wire [32:0] s1_4 = rdata_q[287:256] + rdata_q[319:288];
    wire [32:0] s1_5 = rdata_q[351:320] + rdata_q[383:352];
    wire [32:0] s1_6 = rdata_q[415:384] + rdata_q[447:416];
    wire [32:0] s1_7 = rdata_q[479:448] + rdata_q[511:480];
    wire [33:0] s2_0 = s1_0 + s1_1;
    wire [33:0] s2_1 = s1_2 + s1_3;
    wire [33:0] s2_2 = s1_4 + s1_5;
    wire [33:0] s2_3 = s1_6 + s1_7;
    wire [34:0] s3_0 = s2_0 + s2_1;
    wire [34:0] s3_1 = s2_2 + s2_3;
    wire [35:0] s4   = s3_0 + s3_1;
    wire [63:0] beat_sum = {28'd0, s4};

    // One-cycle-delayed beat qualification (see rdata_q above). beat counter /
    // burst bookkeeping run on this delayed stream so they stay consistent.
    wire beat_fire = rvalid_q & rready;

    always @(posedge aclk) begin
        if (!aresetn) begin
            fsm        <= FSM_IDLE;
            busy       <= 1'b0;
            done       <= 1'b0;
            slverr     <= 1'b0;
            beats_done <= 21'd0;
            beats_total<= 21'd0;
            burst_rcvd <= 9'd0;
            rlast_burst<= 9'd0;
            rid_first  <= 6'h3f;
            rid_last   <= 6'h3f;
            ar_delay   <= 8'hff;
            ar_ticks   <= 8'd0;
            sum        <= 64'd0;
            first_w0   <= 32'd0;
            last_w0    <= 32'd0;
        end else begin
            // CTRL[2] ABORT: recover from a hung transaction (macro stalled)
            if (abort_pulse) begin
                fsm        <= FSM_IDLE;
                busy       <= 1'b0;
                done       <= 1'b0;
            end else
            case (fsm)
                FSM_IDLE: begin
                    if (start_pulse) begin
                        beats_total <= len_reg[26:6] + {20'd0, |len_reg[5:0]};
                        beats_done  <= 21'd0;
                        sum         <= 64'd0;
                        slverr      <= 1'b0;
                        busy        <= 1'b1;
                        fsm         <= FSM_AR;
                        ar_ticks    <= 8'd0;
                    end
                end

                FSM_AR: begin
                    ar_ticks <= ar_ticks + 8'd1;
                    // arvalid is high for the whole state (combinational);
                    // the macro may accept in the very first cycle.
                    if (arready) begin
                        fsm       <= FSM_DATA;
                        burst_rcvd<= 9'd0;
                        ar_delay  <= ar_ticks;  // latency probe (>=1)
                    end
                end

                FSM_DATA: begin
                    if (beat_fire) begin
                        beats_done <= beats_done + 21'd1;
                        burst_rcvd <= burst_rcvd + 9'd1;
                        sum        <= sum + beat_sum;
                        last_w0    <= rdata_q[31:0];
                        if (beats_done == 21'd0) begin
                            first_w0 <= rdata_q[31:0];
                            rid_first<= rid_q;
                        end
                        rid_last <= rid_q;
                        if (rresp_q != 2'b00)
                            slverr <= 1'b1;
                        if (rlast_q)
                            rlast_burst <= burst_rcvd + 9'd1;
                        if (rlast_q || (beats_done + 21'd1 == beats_total)) begin
                            if (beats_done + 21'd1 == beats_total) begin
                                fsm  <= FSM_DONE;
                                busy <= 1'b0;
                                done <= 1'b1;
                            end else begin
                                fsm <= FSM_AR;
                                ar_ticks <= 8'd0;
                            end
                        end
                    end
                end

                FSM_DONE: begin
                    if (start_pulse) begin
                        /* restart directly without a prior CLR_DONE */
                        beats_total <= len_reg[26:6] + {20'd0, |len_reg[5:0]};
                        beats_done  <= 21'd0;
                        sum        <= 64'd0;
                        slverr     <= 1'b0;
                        busy       <= 1'b1;
                        done       <= 1'b0;
                        fsm        <= FSM_AR;
                        ar_ticks   <= 8'd0;
                    end else if (clr_done_pulse) begin
                        done <= 1'b0;
                        fsm  <= FSM_IDLE;
                    end
                end

                default: fsm <= FSM_IDLE;
            endcase
        end
    end

    // Burst sizing, replicating the passing baseline (TJ180A484S-good):
    // up to 256 beats per AR, no 4KB-boundary split. The good build sends
    // ARLEN up to 0xFF and the macro honours it. The AR payload is driven
    // combinationally from the registers exactly like the baseline - see
    // the NOTE near the register declarations for why it must not be
    // registered. The RLAST-authoritative close in FSM_DATA stays as a
    // safety net so a truncating macro can never hang us.
    wire [31:0] burst_addr  = addr_reg + {5'd0, beats_done, 6'd0}; // + beats*64
    wire [20:0] beats_left  = beats_total - beats_done;
    wire [8:0]  burst_beats = (beats_left >= 21'd256) ? 9'd256 : beats_left[8:0];

    assign araddr  = burst_addr;
    assign arlen   = burst_beats[7:0] - 8'd1;   // 256 beats -> 0xFF
    assign arvalid = (fsm == FSM_AR);
    assign arsize  = 3'b110;      // 64 bytes
    assign arburst = 2'b01;       // INCR
    assign arid    = {AXI_ID_W{1'b0}};
    assign arlock  = 1'b0;
    assign arqos   = 1'b0;
    // RREADY held permanently high, like the passing baseline reader. The
    // macro's port 1 appears to dislike RREADY gaps between bursts (every
    // gated build truncated bursts to 2 beats + returned constant data,
    // while the always-ready baseline gets full-length bursts + real data).
    // Stray beats are impossible per board diagnostics (idle_rv == 0), so
    // always-accepting costs nothing; late beats outside FSM_DATA are simply
    // dropped by the FSM qualification below.
    assign rready  = 1'b1;

    //------------------------------------------------------------------------
    // Ghost-response detector: after the run completes (FSM_DONE, rready low,
    // no AR outstanding), any rising edge on RVALID means the macro emits
    // read responses on its own. A non-zero IDLE_RV read by software after a
    // short delay proves the R stream is not driven by our AR requests.
    // Sole driver of idle_rv_cnt/rvalid_d (VDB-1000: never assign them in
    // the main FSM block above).
    //------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            rvalid_d   <= 1'b0;
            idle_rv_cnt<= 16'd0;
        end else begin
            rvalid_d <= rvalid;
            if (start_pulse)
                idle_rv_cnt <= 16'd0;   // re-arm on a new run
            else if ((fsm == FSM_DONE) && rvalid && !rvalid_d
                     && !idle_rv_cnt[15])
                idle_rv_cnt <= idle_rv_cnt + 16'd1;
        end
    end

    //------------------------------------------------------------------------
    // APB register access
    //------------------------------------------------------------------------

    reg        start_pulse;
    reg        clr_done_pulse;
    reg        abort_pulse;

    always @(posedge aclk) begin
        if (!aresetn) begin
            start_pulse    <= 1'b0;
            clr_done_pulse <= 1'b0;
            abort_pulse    <= 1'b0;
        end else begin
            start_pulse    <= apb_fire &  pwrite & (paddr[7:2] == 6'h1) & pwdata[0];
            clr_done_pulse <= apb_fire &  pwrite & (paddr[7:2] == 6'h1) & pwdata[1];
            abort_pulse    <= apb_fire &  pwrite & (paddr[7:2] == 6'h1) & pwdata[2];
        end
    end

    // Sticky channel activity flags (cleared by START)
    always @(posedge aclk) begin
        if (!aresetn) begin
            rvalid_seen <= 1'b0;
            rlast_seen  <= 1'b0;
        end else if (start_pulse) begin
            rvalid_seen <= 1'b0;
            rlast_seen  <= 1'b0;
        end else begin
            if (rvalid)
                rvalid_seen <= 1'b1;
            if (rvalid & rlast)
                rlast_seen  <= 1'b1;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            addr_reg <= 32'd0;
            len_reg  <= 32'd0;
        end else if (apb_fire & pwrite) begin
            case (paddr[7:2])
                6'h3: addr_reg <= pwdata;   // ADDR
                6'h4: len_reg  <= pwdata;   // LEN
                default: ;
            endcase
        end
    end

    // NOTE: start_pulse is delayed one cycle from the APB access; addr/len are
    // registered in the same cycle, so they are stable when FSM_IDLE samples it.

    assign pready    = 1'b1;
    assign pslverror = 1'b0;

    assign prdata = (paddr[7:2] == 6'h0) ? 32'h50315231 :
                    (paddr[7:2] == 6'h2) ? {27'd0, rlast_seen, rvalid_seen, slverr, done, busy} :
                    (paddr[7:2] == 6'h3) ? addr_reg :
                    (paddr[7:2] == 6'h4) ? len_reg :
                    (paddr[7:2] == 6'h5) ? {11'd0, beats_done} :
                    (paddr[7:2] == 6'h6) ? sum[31:0] :
                    (paddr[7:2] == 6'h7) ? sum[63:32] :
                    (paddr[7:2] == 6'h8) ? first_w0 :
                    (paddr[7:2] == 6'h9) ? last_w0 :
                    (paddr[7:2] == 6'ha) ? {23'd0, rlast_burst} :
                    (paddr[7:2] == 6'hb) ? {26'd0, rid_first} :
                    (paddr[7:2] == 6'hc) ? {26'd0, rid_last} :
                    (paddr[7:2] == 6'hd) ? {24'd0, ar_delay} :
                    (paddr[7:2] == 6'he) ? idle_rv_cnt : 32'd0;

endmodule
