//============================================================================
// video_reader.v
//
// DDR Port 1 video streaming engine (phase C: MIPI CSI-2 TX path).
//
// Reads a frame buffer from the DDR hard controller AXI Port 1 (512-bit
// beats), serialises each beat into eight 64-bit words and streams them to
// the shape_video_data async-FIFO write port (same sys_clk_125m domain).
//
// Frame looping / pattern cycling:
//   - After the last beat of a frame the engine immediately re-issues AR for
//     the next frame -> the video stream is continuous and frame aligned
//     (shape_video_data has no frame sync: FIFO word 0 = frame word 0).
//   - Every SWITCH_FRAMES completed frames the pattern index advances and the
//     read address becomes BASE + pat_idx * FRAME_BYTES, wrapping at
//     NUM_FRAMES. With 8 patterns x 180 frames this reproduces the reference
//     pattern_gen behaviour (3 s per pattern at 60 fps).
//
// Pause/resume (CTRL.RUN=0/1):
//   RUN only gates new AR issue; the stream position (beat counter) is kept,
//   so pause/resume never loses or duplicates a word -> FIFO alignment holds.
//
// Register map (APB, word offsets):
//   0x00 ID      : 0x56314452 ("V1DR")
//   0x04 CTRL    : [0] RUN, [3] OWN_P1 (DDR port-1 owner: 0=verif reader)
//   0x08 STATUS  : [0] BUSY, [1] SLVERR
//   0x0C BASE    : frame[0] start byte address (64-byte aligned)
//   0x10 FBYTES  : one frame in bytes (multiple of 64)
//   0x14 NFRAME  : number of patterns stored from BASE (>=1)
//   0x18 NSWITCH : frames shown before switching pattern (0 = never switch)
//   0x1C PAT_IDX : current pattern index (RO)
//   0x20 FCNT    : frames completed since first RUN (RO)
//
// Single clock domain: aclk = sys_clk_125m.
//============================================================================

module video_reader #(
    parameter integer AXI_ID_W = 6
)(
    input  wire                  aclk,
    input  wire                  aresetn,

    // APB slave (SoC io_apbSlave_1, 0xF8110000)
    input  wire [15:0]           paddr,
    input  wire                  psel,
    input  wire                  penable,
    input  wire                  pwrite,
    input  wire [31:0]           pwdata,
    output wire [31:0]           prdata,
    output wire                  pready,
    output wire                  pslverr,

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
    input  wire [511:0]          rdata,

    // 64-bit video stream -> shape_video_data (same aclk domain)
    input  wire                  pause_i,     // FIFO almost-full backpressure
    output wire                  vid_valid,
    output wire [63:0]           vid_data,

    // DDR port-1 arbitration (consumed in top_soc_sd)
    output wire                  own_mem1
);

    localparam [2:0] FSM_IDLE = 3'd0;
    localparam [2:0] FSM_AR   = 3'd1;
    localparam [2:0] FSM_DATA = 3'd2;

    //------------------------------------------------------------------------
    // CSR registers
    //------------------------------------------------------------------------
    reg         run_reg;
    reg         own_p1_reg;
    reg  [31:0] base_reg;
    reg  [31:0] fbytes_reg;
    reg  [15:0] nframe_reg;
    reg  [15:0] nswitch_reg;

    wire        apb_fire = psel & penable;

    always @(posedge aclk) begin
        if (!aresetn) begin
            run_reg    <= 1'b0;
            own_p1_reg <= 1'b0;
            base_reg   <= 32'd0;
            fbytes_reg <= 32'd0;
            nframe_reg <= 16'd0;
            nswitch_reg<= 16'd0;
        end else if (apb_fire & pwrite) begin
            case (paddr[7:2])
                6'h1: begin run_reg    <= pwdata[0];
                            own_p1_reg <= pwdata[3]; end
                6'h3: base_reg   <= pwdata;
                6'h4: fbytes_reg <= pwdata;
                6'h5: nframe_reg <= pwdata[15:0];
                6'h6: nswitch_reg<= pwdata[15:0];
                default: ;
            endcase
        end
    end

    assign own_mem1 = own_p1_reg;

    //------------------------------------------------------------------------
    // Engine state
    //------------------------------------------------------------------------
    reg [2:0]   fsm;
    reg [31:0]  cur_addr;      // read address of current frame
    reg [19:0]  beats_total;   // 64B beats per frame
    reg [19:0]  beats_done;
    reg         slverr;
    reg [15:0]  pat_idx;
    reg [15:0]  switch_cnt;
    reg [31:0]  frame_cnt;

    // Same hard-macro limits as ddr_port1_reader (UG Table 5): ARSIZE = 6
    // caps the burst at 64 beats (ARLEN <= 63) and a burst must not cross a
    // 4KB address boundary.
    wire [31:0] burst_addr  = cur_addr + {beats_done, 6'd0}; // + beats*64
    wire [6:0]  bnd_beats   = 7'd64 - {1'b0, burst_addr[11:6]}; // beats to 4KB line end
    wire [19:0] beats_left  = beats_total - beats_done;
    wire [8:0]  cap_beats   = (beats_left >= 20'd64) ? 9'd64 : beats_left[8:0];
    wire [8:0]  burst_beats = (cap_beats >= {2'd0, bnd_beats})
                              ? {2'd0, bnd_beats} : cap_beats;

    assign araddr  = burst_addr;
    assign arlen   = burst_beats - 9'd1;                   // 64 beats -> 0x3F
    assign arvalid = (fsm == FSM_AR) & run_reg;
    assign arsize  = 3'b110;      // 64 bytes
    assign arburst = 2'b01;       // INCR
    assign arid    = {AXI_ID_W{1'b0}};
    assign arlock  = 1'b0;
    assign arqos   = 1'b0;

    //------------------------------------------------------------------------
    // 512 -> 64 bit serialiser
    //
    // One DDR beat is captured into beat_q only when the serialiser is empty
    // (rready = ~avail). Each captured beat is drained as eight 64-bit words;
    // draining stalls while the shape_video_data FIFO asserts pause. Words are
    // neither lost nor duplicated across pause/resume, so the FIFO stream
    // stays frame aligned.
    //------------------------------------------------------------------------
    reg [511:0] beat_q;
    reg         avail;           // beat_q holds an undrained beat
    reg [2:0]   csel;            // 64-bit chunk inside the beat

    // own_p1_reg gates both capture and drain: while the verification reader
    // owns DDR Port 1 (OWN_P1=0) stray R beats of its transactions must not
    // enter the serialiser, otherwise a stale beat would leak into the video
    // FIFO at ownership handover and skew the stream (no frame sync below).
    wire fire      = avail & ~pause_i & own_p1_reg;
    wire rready_i  = ~avail & own_p1_reg;
    wire beat_take = rvalid & rready_i;

    assign vid_valid = fire;
    assign vid_data  = beat_q[{csel, 6'd0} +: 64];
    assign rready    = rready_i;

    always @(posedge aclk) begin
        if (!aresetn) begin
            beat_q <= 512'd0;
            avail  <= 1'b0;
            csel   <= 3'd0;
        end else if (beat_take) begin
            beat_q <= rdata;         // registers the DDR macro output (timing)
            avail  <= 1'b1;
            csel   <= 3'd0;
        end else if (fire) begin
            if (csel == 3'd7) begin
                avail <= 1'b0;
                csel  <= 3'd0;
            end else begin
                csel <= csel + 3'd1;
            end
        end
    end

    //------------------------------------------------------------------------
    // FSM
    //------------------------------------------------------------------------
    wire do_switch = (nswitch_reg != 16'd0) &&
                     ((switch_cnt + 16'd1) >= nswitch_reg);

    always @(posedge aclk) begin
        if (!aresetn) begin
            fsm        <= FSM_IDLE;
            cur_addr   <= 32'd0;
            beats_total<= 20'd0;
            beats_done <= 20'd0;
            slverr     <= 1'b0;
            pat_idx    <= 16'd0;
            switch_cnt <= 16'd0;
            frame_cnt  <= 32'd0;
        end else begin
            case (fsm)
                FSM_IDLE: begin
                    if (run_reg && (fbytes_reg[5:0] == 6'd0) && fbytes_reg != 32'd0) begin
                        cur_addr    <= base_reg;
                        beats_total <= fbytes_reg[25:6];
                        beats_done  <= 20'd0;
                        slverr      <= 1'b0;
                        pat_idx     <= 16'd0;
                        switch_cnt  <= 16'd0;
                        fsm         <= FSM_AR;
                    end
                end

                FSM_AR: begin
                    if (arvalid & arready) begin
                        fsm <= FSM_DATA;
                    end
                end

                FSM_DATA: begin
                    if (beat_take) begin
                        beats_done <= beats_done + 20'd1;
                        if (rresp != 2'b00)
                            slverr <= 1'b1;
                        /* AXI4: RLAST is the authoritative end-of-burst marker -
                         * the DDR macro terminates bursts early regardless of
                         * ARLEN, so never wait out a beat count. */
                        if (rlast || (beats_done + 20'd1 == beats_total)) begin
                            if (beats_done + 20'd1 == beats_total) begin
                                // frame complete
                                frame_cnt  <= frame_cnt + 32'd1;
                                beats_done <= 20'd0;
                                if (do_switch) begin
                                    switch_cnt <= 16'd0;
                                    if ((pat_idx + 16'd1 >= nframe_reg) || (nframe_reg <= 16'd1)) begin
                                        pat_idx  <= 16'd0;
                                        cur_addr <= base_reg;
                                    end else begin
                                        pat_idx  <= pat_idx + 16'd1;
                                        cur_addr <= cur_addr + fbytes_reg;
                                    end
                                end else begin
                                    switch_cnt <= switch_cnt + 16'd1;
                                end
                            end
                            fsm <= FSM_AR;
                        end
                    end
                end

                default: fsm <= FSM_IDLE;
            endcase
        end
    end

    //------------------------------------------------------------------------
    // APB read
    //------------------------------------------------------------------------
    assign pready   = 1'b1;
    assign pslverr  = 1'b0;

    assign prdata = (paddr[7:2] == 6'h0) ? 32'h56314452 :
                    (paddr[7:2] == 6'h1) ? {28'd0, own_p1_reg, 2'd0, run_reg} :
                    (paddr[7:2] == 6'h2) ? {30'd0, slverr, (fsm != FSM_IDLE)} :
                    (paddr[7:2] == 6'h3) ? base_reg :
                    (paddr[7:2] == 6'h4) ? fbytes_reg :
                    (paddr[7:2] == 6'h5) ? {16'd0, nframe_reg} :
                    (paddr[7:2] == 6'h6) ? {16'd0, nswitch_reg} :
                    (paddr[7:2] == 6'h7) ? {16'd0, pat_idx} :
                    (paddr[7:2] == 6'h8) ? frame_cnt : 32'd0;

    // unused
    wire unused_ok = &{1'b0, rid, 1'b0};

endmodule
