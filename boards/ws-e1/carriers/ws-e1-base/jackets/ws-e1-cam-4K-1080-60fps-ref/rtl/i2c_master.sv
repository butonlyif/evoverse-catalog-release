//==============================================================================
// Module : i2c_master
// File   : i2c_master.sv
// Style  : SystemVerilog (IEEE 1800-2017 subset, synthesizable)
//
// Purpose:
//   A small I2C bus master. Byte-oriented command interface: each command
//   (START, TX byte, RX byte, STOP) is one transaction the user kicks off
//   by pulsing `go` and waits for `done`.
//
//   Open-drain pad convention: pad_o = 0 means drive low, pad_o = 1 means
//   release. The bus is the wired-AND of master and slave drivers (see
//   the testbench for the bus model).
//
// User interface:
//   cmd    = 3'd1 -> START
//   cmd    = 3'd2 -> TX  (shift out tx_data, sample ACK from slave -> nack)
//   cmd    = 3'd3 -> RX  (shift in 8 bits, drive ACK based on tx_ack)
//   cmd    = 3'd4 -> STOP
//
//   Typical write:  START, TX(addr<<1 | 0), TX(data), STOP
//   Typical read:   START, TX(addr<<1 | 1), RX(ACK), RX(NACK), STOP
//
// Pitfalls explicitly addressed (master side):
//
//   1. START / STOP generation
//      SDA must change while SCL is HIGH (the only time SDA is allowed
//      to change during SCL high). Master holds SCL high for both START
//      (SDA falling) and STOP (SDA rising), and only lowers SCL after
//      the SDA transition has been established.
//
//   2. SDA contention
//      Master drives SDA only when it owns the bus:
//        - TX byte      : drives each data bit
//        - TX-ACK read  : RELEASES SDA so the slave can ACK
//        - RX byte      : RELEASES SDA so the slave can drive
//        - RX-ACK send  : drives ACK (low) or NACK (high)
//
//   3. SCL clock stretching
//      Each SCL high phase waits for scl_pad_i to actually go high.
//      (For sim this is a no-op because the slave doesn't stretch.)
//
//   4. Data setup / hold
//      SDA is updated while SCL is low and is stable before SCL rises.
//      Master samples SDA at the end of the SCL high phase.
//
//   5. ACK timing
//      ACK is driven before the 9th SCL rising edge, released on the
//      9th SCL falling edge.
//
//   6. Bit ordering
//      I2C is MSB-first. tx_shift[7] is the current output bit;
//      sampled bits are shifted in from the LSB side.
//
// Not in scope: multi-master arbitration, Hs-mode, SMBus, combined
// transactions (user sequences START..STOP manually).
//==============================================================================
module i2c_master #(
    parameter int SYS_FREQ = 100_000_000,   // System clock frequency (Hz)
    parameter int I2C_FREQ = 400_000,       // I2C SCL frequency (Hz)
    //================================================================
    // SCL_TIMEOUT_CYCLES: max cycles the master will wait for scl_pad_i
    // to go high when it expects SCL high (slave clock-stretching
    // window). If the slave holds SCL low longer than this, the
    // watchdog fires `err` and aborts the current command.
    // Default 20000 = 200 us at 100 MHz. Set very large to effectively
    // disable. Width controlled by SCL_TO_W.
    parameter int SCL_TIMEOUT_CYCLES = 20_000,
    parameter int SCL_TO_W           = 18
) (
    input  logic       clk,
    input  logic       rst_n,

    // I2C bus (open-drain: 0 = drive low, 1 = release)
    input  logic       scl_pad_i,
    output logic       scl_pad_o,
    input  logic       sda_pad_i,
    output logic       sda_pad_o,

    // Command interface
    input  logic [2:0] cmd,         // CMD_START, CMD_TX, CMD_RX, CMD_STOP, CMD_RESET
    input  logic [7:0] tx_data,     // byte to send (CMD_TX)
    input  logic       tx_ack,      // 0 = ACK, 1 = NACK to send (CMD_RX)
    input  logic       go,          // pulse high for 1 cycle to launch cmd

    // Status
    output logic       busy,        // command in progress
    output logic       done,        // pulse high for 1 cycle when cmd finishes
    output logic       nack,        // CMD_TX: 1 if slave NACKed the byte
    output logic [7:0] rx_data,     // CMD_RX: received byte
    output logic       rx_valid,    // CMD_RX: pulse high when rx_data is valid
    // Error flag. Latched high when the SCL watchdog fires (slave held
    // SCL low longer than SCL_TIMEOUT_CYCLES during a transaction).
    // Cleared by CMD_RESET or rst_n. The master FSM returns to ST_IDLE
    // after a watchdog event; user can then issue CMD_RESET and retry.
    output logic       err
);

    // -----------------------------------------------------------------
    // Derived timing (clocks per SCL half-period)
    // -----------------------------------------------------------------
    localparam int T_SCL  = SYS_FREQ / I2C_FREQ;
    localparam int T_LOW  = T_SCL / 2;
    localparam int T_HIGH = T_SCL - T_LOW;
    localparam int CNT_W  = $clog2(T_SCL + 1);

    // Command codes
    typedef enum logic [2:0] {
        CMD_NOP   = 3'd0,
        CMD_START = 3'd1,
        CMD_TX    = 3'd2,
        CMD_RX    = 3'd3,
        CMD_STOP  = 3'd4,
        CMD_RESET = 3'd5    // soft reset: clear state, err, return to IDLE
    } cmd_t;

    // Main FSM states
    typedef enum logic [3:0] {
        ST_IDLE,       // true bus idle (SCL=1, SDA=1) -- only after STOP
        ST_START_PRE,  // SCL rising (released), SDA still high.
                       //   CRITICAL for repeated START: gives the slave's
                       //   SCL filter time to see scl_q=1 BEFORE we drop
                       //   SDA. Without this state, the slave's start_det
                       //   races against scl_rise (sda_fall fires before
                       //   scl_q updates through the glitch filter) and
                       //   the slave misses the START, shifting in a stray
                       //   bit instead.
        ST_START_A,    // SDA falling while SCL high -> real START
        ST_START_B,    // SCL falling (after START established)
        ST_HOLD,       // SCL held low, SDA released, waiting for next cmd
        ST_DATA,       // 8 data bits (SCL cycles)
        ST_ACK,        // 9th SCL cycle (ACK bit)
        ST_STOP_A,     // SCL rising (preparation for STOP)
        ST_STOP_B      // SDA rising while SCL high
    } state_t;

    // SCL sub-state (within ST_DATA and ST_ACK)
    typedef enum logic [0:0] {
        SCL_L,         // SCL driven low
        SCL_H          // SCL released high
    } scl_st_t;

    // -----------------------------------------------------------------
    // State registers
    // -----------------------------------------------------------------
    state_t           state;
    scl_st_t          scl_st;
    logic [3:0]       bit_cnt;      // 0..7 for data, 8 = ack done
    logic [7:0]       tx_shift;
    logic [7:0]       rx_shift;
    logic             cmd_is_rx;    // latched at go time
    logic [CNT_W-1:0] cnt;          // sub-phase counter

    // Compare helpers -- use localparam ints to avoid width-mismatch
    // warnings when CNT is narrower than the int literal.
    // (Declared here, ahead of the SCL-watchdog process, which also
    // references CNT_LOW_END.)
    localparam int CNT_LOW_END  = T_LOW  - 1;
    localparam int CNT_HIGH_END = T_HIGH - 1;

    // Status outputs
    logic        busy_r;
    logic        done_r;
    logic        nack_r;
    logic [7:0]  rx_data_r;
    logic        rx_valid_r;
    logic        err_r;             // latched SCL-stuck error

    // -----------------------------------------------------------------
    // SCL watchdog: counts cycles while we expect SCL to be high
    // (scl_should_be_high) but the bus reads low. This covers:
    //   - ST_START_PRE: SCL released, waiting for it to rise
    //   - ST_DATA SCL_H: clock-stretching window
    //   - ST_ACK  SCL_H: clock-stretching window
    //   - ST_STOP_A:     SCL released, waiting for it to rise
    // If the count hits SCL_TIMEOUT_CYCLES, we set scl_timeout=1 and
    // the FSM aborts (transitions to ST_IDLE, sets err).
    // -----------------------------------------------------------------
    logic              scl_should_be_high;
    logic [SCL_TO_W-1:0] scl_to_cnt;
    logic              scl_timeout;

    assign scl_should_be_high =
        (state == ST_START_PRE) ||
        (state == ST_DATA && scl_st == SCL_H) ||
        (state == ST_ACK  && scl_st == SCL_H) ||
        (state == ST_STOP_A);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_to_cnt  <= '0;
            scl_timeout <= 1'b0;
        end else begin
            // Clear paths (single-owner process; the FSM itself no longer
            // writes scl_timeout -- vopt-7061):
            //   1) CMD_RESET consumed at ST_IDLE (matches the FSM's
            //      CMD_RESET handling, which pulses done_r);
            //   2) a completed ST_STOP_B (same completion condition the
            //      FSM uses to return to ST_IDLE).
            // Neither coincides with the set condition below (in both
            // states scl_should_be_high is 0).
            if ((go && state == ST_IDLE && cmd == CMD_RESET) ||
                (state == ST_STOP_B &&
                 cnt == CNT_LOW_END[CNT_W-1:0])) begin
                scl_timeout <= 1'b0;
                scl_to_cnt  <= '0;
            end else if (scl_should_be_high && !scl_pad_i) begin
                if (scl_to_cnt == SCL_TIMEOUT_CYCLES[SCL_TO_W-1:0]-1'b1) begin
                    scl_timeout <= 1'b1;
                end else begin
                    scl_to_cnt <= scl_to_cnt + 1'b1;
                end
            end else begin
                scl_to_cnt <= '0;
            end
        end
    end

    // -----------------------------------------------------------------
    // SDA / SCL drivers (combinational from state + data)
    //   sda_oe = 1 : drive SDA low
    //   sda_oe = 0 : release SDA (pulled high by bus)
    //   scl_oe = 1 : drive SCL low
    //   scl_oe = 0 : release SCL
    // -----------------------------------------------------------------
    logic sda_oe;
    logic scl_oe;
    logic tx_msb;   // iverilog-friendly alias for tx_shift[7]
    assign tx_msb = tx_shift[7];

    always_comb begin
        sda_oe = 1'b0;
        scl_oe = 1'b0;
        case (state)
            ST_IDLE: ;   // both released (true bus idle, only after STOP)

            // ST_START_PRE: release SCL so it rises, but keep SDA released
            // (still high). The slave's glitch-filtered scl_q updates to 1
            // by the end of this state. Then ST_START_A drops SDA while
            // scl_q is already 1, so start_det fires cleanly.
            ST_START_PRE: begin
                sda_oe = 1'b0;   // SDA still high (released)
                scl_oe = 1'b0;   // SCL released -> rises
            end

            ST_START_A: begin
                sda_oe = 1'b1;   // drive SDA low while SCL still high
                // SCL stays high (released) -> START condition
            end

            ST_START_B: begin
                sda_oe = 1'b1;   // keep SDA low
                scl_oe = 1'b1;   // drive SCL low -> bus ready for data
            end

            // ST_HOLD: hold SCL low, release SDA. This is the bridge
            // between commands -- it prevents the slave from seeing
            // SDA released while SCL is high (which it would interpret
            // as a STOP). The next command (or a final STOP) proceeds
            // from here.
            ST_HOLD: begin
                sda_oe = 1'b0;   // release SDA
                scl_oe = 1'b1;   // hold SCL low
            end

            ST_DATA: begin
                if (cmd_is_rx) begin
                    sda_oe = 1'b0;            // RX: release SDA
                end else begin
                    sda_oe = ~tx_msb;         // TX: drive per data bit
                end
                if (scl_st == SCL_L) scl_oe = 1'b1;
                // SCL_H: release SCL
            end

            ST_ACK: begin
                if (cmd_is_rx) begin
                    // RX-ACK send: master drives ACK (low) or NACK (high)
                    sda_oe = ~tx_ack;
                end else begin
                    // TX-ACK read: master releases so slave can ACK
                    sda_oe = 1'b0;
                end
                if (scl_st == SCL_L) scl_oe = 1'b1;
            end

            ST_STOP_A: begin
                sda_oe = 1'b1;   // SDA still low
                scl_oe = 1'b1;   // KEEP SCL low -- critical! Releasing
                                 // SCL here would generate an extra
                                 // scl_rise in the slave, which would
                                 // shift in a stray 0 bit. We hold SCL
                                 // low and release both SCL+SDA together
                                 // in ST_STOP_B so the slave sees the
                                 // SCL rise and SDA rise in the SAME
                                 // cycle, letting stop_det take priority
                                 // over scl_rise.
            end

            ST_STOP_B: begin
                sda_oe = 1'b0;   // SDA released -> SDA rises = STOP
                // SCL also released (scl_oe stays 0 from ST_STOP_A)
                // -- both rise in the same cycle, so the slave's
                // stop_det fires together with scl_rise.
            end
        endcase
    end

    assign scl_pad_o = scl_oe ? 1'b0 : 1'b1;
    assign sda_pad_o = sda_oe ? 1'b0 : 1'b1;

    // -----------------------------------------------------------------
    // Outputs
    // -----------------------------------------------------------------
    assign busy     = busy_r;
    assign done     = done_r;
    assign nack     = nack_r;
    assign rx_data  = rx_data_r;
    assign rx_valid = rx_valid_r;
    assign err      = err_r;

    // -----------------------------------------------------------------
    // Main FSM
    // -----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            scl_st     <= SCL_L;
            cnt        <= 0;
            bit_cnt    <= 0;
            tx_shift   <= 8'h00;
            rx_shift   <= 8'h00;
            cmd_is_rx  <= 1'b0;
            busy_r     <= 1'b0;
            done_r     <= 1'b0;
            nack_r     <= 1'b0;
            rx_data_r  <= 8'h00;
            rx_valid_r <= 1'b0;
            err_r      <= 1'b0;
        end else begin
            // One-cycle pulse: done. Sticky: rx_valid -- stays high
            // until user starts a new CMD_TX/RX that consumes the byte.
            done_r     <= 1'b0;

            case (state)
                // ----------------------------------------------------
                // ST_IDLE: true bus idle (SCL=1, SDA=1). Only entered
                // after a STOP. From here, the next command is always
                // a fresh START.
                ST_IDLE: begin
                    busy_r <= 1'b0;
                    cnt    <= 0;
                    scl_st <= SCL_L;
                    if (go) begin
                        // CMD_RESET: clear err and all state, stay in IDLE.
                        // Also clears scl_timeout so a new transaction can run.
                        if (cmd == CMD_RESET) begin
                            err_r     <= 1'b0;
                            nack_r    <= 1'b0;
                            rx_valid_r <= 1'b0;
                            done_r    <= 1'b1;   // pulse done so the user
                                                  // knows reset completed
                        end else begin
                            busy_r <= 1'b1;
                            case (cmd)
                                CMD_START: state <= ST_START_PRE;
                                CMD_TX: begin
                                    state     <= ST_DATA;
                                    cmd_is_rx <= 1'b0;
                                    tx_shift  <= tx_data;
                                    bit_cnt   <= 4'd0;
                                    scl_st    <= SCL_L;
                                    cnt       <= 0;
                                    rx_valid_r <= 1'b0;   // consumed
                                end
                                CMD_RX: begin
                                    state     <= ST_DATA;
                                    cmd_is_rx <= 1'b1;
                                    rx_shift  <= 8'h00;
                                    bit_cnt   <= 4'd0;
                                    scl_st    <= SCL_L;
                                    cnt       <= 0;
                                    rx_valid_r <= 1'b0;   // consumed
                                end
                                CMD_STOP: state <= ST_STOP_A;
                                default:  busy_r <= 1'b0;
                            endcase
                        end
                    end
                end

                // ----------------------------------------------------
                // ST_HOLD: holding SCL low, SDA released. Bridge state
                // between commands. Prevents the slave from seeing a
                // SDA-rise-while-SCL-high (phantom STOP) when the
                // master releases SDA at the end of a byte.
                //
                // CRITICAL: we do NOT release SCL here. Going to
                // ST_IDLE would release SCL, and the slave would count
                // that as an extra SCL rising edge -- shifting every
                // following byte by one bit. Instead, we keep SCL
                // driven low and just wait for the next command.
                // busy_r is held at 0 here so the user can pulse go
                // at any time without the "wait for busy" logic
                // deadlocking.
                ST_HOLD: begin
                    busy_r <= 1'b0;
                    if (go) begin
                        if (cmd == CMD_RESET) begin
                            // Soft reset: clear err and all state, return
                            // to ST_IDLE. Bus is already idle here (SCL=0,
                            // SDA=1), so no bus action needed.
                            state      <= ST_IDLE;
                            err_r      <= 1'b0;
                            nack_r     <= 1'b0;
                            rx_valid_r <= 1'b0;
                            done_r     <= 1'b1;   // pulse done
                            cnt        <= 0;
                            scl_st     <= SCL_L;
                        end else begin
                            busy_r <= 1'b1;
                            case (cmd)
                                CMD_START: state <= ST_START_PRE;
                                CMD_TX: begin
                                    state     <= ST_DATA;
                                    cmd_is_rx <= 1'b0;
                                    tx_shift  <= tx_data;
                                    bit_cnt   <= 4'd0;
                                    scl_st    <= SCL_L;
                                    cnt       <= 0;
                                    rx_valid_r <= 1'b0;   // consumed
                                end
                                CMD_RX: begin
                                    state     <= ST_DATA;
                                    cmd_is_rx <= 1'b1;
                                    rx_shift  <= 8'h00;
                                    bit_cnt   <= 4'd0;
                                    scl_st    <= SCL_L;
                                    cnt       <= 0;
                                    rx_valid_r <= 1'b0;   // consumed
                                end
                                CMD_STOP: state <= ST_STOP_A;
                                default:  ;
                            endcase
                        end
                    end
                end

                // ----------------------------------------------------
                // START sequence (3 states):
                //   ST_START_PRE: release SCL, hold SDA high. Gives the
                //                 slave's SCL filter time to update
                //                 scl_q to 1. CRITICAL for repeated
                //                 START: the slave's filter is "pre-
                //                 loaded" by the previous byte's ACK
                //                 cycle, so SDA and SCL do NOT update
                //                 in lockstep if we change them in the
                //                 same cycle. Separating them avoids
                //                 the race.
                //   ST_START_A:   drive SDA low while SCL still high ->
                //                 real START condition. start_det fires.
                //   ST_START_B:   drive SCL low, SDA still low. Bus is
                //                 ready for the first data bit.
                ST_START_PRE: begin
                    if (scl_timeout) begin
                        // SCL never went high -- slave is dead or SDA
                        // is stuck. Abort. Pulse done_r so the user's
                        // wait-for-done logic returns; they check `err`.
                        state  <= ST_IDLE;
                        busy_r <= 1'b0;
                        done_r <= 1'b1;
                        err_r  <= 1'b1;
                        cnt    <= 0;
                    end else if (cnt == CNT_LOW_END[CNT_W-1:0]) begin
                        state <= ST_START_A;
                        cnt   <= 0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                ST_START_A: begin
                    // SDA falling while SCL high. The slave's start_det
                    // should fire here. If the slave didn't see it (e.g.,
                    // wrong address -> back to IDLE), we just continue --
                    // no harm done.
                    if (cnt == CNT_LOW_END[CNT_W-1:0]) begin
                        state <= ST_START_B;
                        cnt   <= 0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                ST_START_B: begin
                    if (cnt == CNT_LOW_END[CNT_W-1:0]) begin
                        state  <= ST_HOLD;
                        done_r <= 1'b1;
                        cnt    <= 0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                // ----------------------------------------------------
                // DATA: 8 SCL cycles, shifting out (TX) or in (RX)
                // In SCL_H phase we gate the counter on scl_pad_i so the
                // slave can clock-stretch (hold SCL low) for any duration.
                // The SCL watchdog fires err if the stretch exceeds
                // SCL_TIMEOUT_CYCLES.
                ST_DATA: begin
                    if (scl_st == SCL_L) begin
                        if (cnt == CNT_LOW_END[CNT_W-1:0]) begin
                            scl_st <= SCL_H;
                            cnt    <= 0;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end else begin
                        // SCL_H: wait for scl_pad_i=1 (slave may stretch).
                        if (scl_timeout) begin
                            state  <= ST_IDLE;
                            busy_r <= 1'b0;
                            done_r <= 1'b1;
                            err_r  <= 1'b1;
                            scl_st <= SCL_L;
                            cnt    <= 0;
                        end else if (scl_pad_i) begin
                            if (cnt == CNT_HIGH_END[CNT_W-1:0]) begin
                                // SCL has been high long enough; sample (RX)
                                // and shift.
                                if (cmd_is_rx) begin
                                    rx_shift <= {rx_shift[6:0], sda_pad_i};
                                end else begin
                                    tx_shift <= {tx_shift[6:0], 1'b0};
                                end
                                bit_cnt <= bit_cnt + 1'b1;
                                scl_st   <= SCL_L;
                                cnt      <= 0;
                                if (bit_cnt == 4'd7) begin
                                    state <= ST_ACK;
                                end
                            end else begin
                                cnt <= cnt + 1'b1;
                            end
                        end
                        // else: scl_pad_i=0 (slave stretching), cnt frozen
                    end
                end

                // ----------------------------------------------------
                // ACK: 9th SCL cycle. Same SCL_H gating as ST_DATA.
                ST_ACK: begin
                    if (scl_st == SCL_L) begin
                        if (cnt == CNT_LOW_END[CNT_W-1:0]) begin
                            scl_st <= SCL_H;
                            cnt    <= 0;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end else begin
                        if (scl_timeout) begin
                            state  <= ST_IDLE;
                            busy_r <= 1'b0;
                            done_r <= 1'b1;
                            err_r  <= 1'b1;
                            scl_st <= SCL_L;
                            cnt    <= 0;
                        end else if (scl_pad_i) begin
                            if (cnt == CNT_HIGH_END[CNT_W-1:0]) begin
                                if (cmd_is_rx) begin
                                    rx_data_r  <= rx_shift;
                                    rx_valid_r <= 1'b1;
                                end else begin
                                    nack_r <= sda_pad_i;   // 1 = NACK
                                end
                                // After ACK: go to ST_HOLD (not ST_IDLE) so
                                // SDA release happens while SCL is still low,
                                // avoiding a phantom STOP in the slave.
                                state  <= ST_HOLD;
                                done_r <= 1'b1;
                                scl_st <= SCL_L;
                                cnt    <= 0;
                            end else begin
                                cnt <= cnt + 1'b1;
                            end
                        end
                        // else: slave stretching SCL, cnt frozen
                    end
                end

                // ----------------------------------------------------
                // STOP: SCL rising, then SDA rising while SCL high.
                ST_STOP_A: begin
                    if (scl_timeout) begin
                        // SCL never went high during STOP prep. This is
                        // unusual (no slave should stretch during STOP)
                        // but we handle it for robustness.
                        state  <= ST_IDLE;
                        busy_r <= 1'b0;
                        done_r <= 1'b1;
                        err_r  <= 1'b1;
                        cnt    <= 0;
                    end else if (cnt == CNT_HIGH_END[CNT_W-1:0]) begin
                        state <= ST_STOP_B;
                        cnt   <= 0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                ST_STOP_B: begin
                    if (cnt == CNT_LOW_END[CNT_W-1:0]) begin
                        // After a real STOP, the bus is truly idle
                        // (SCL=1, SDA=1), so ST_IDLE is correct here.
                        // A successful STOP also clears any pending
                        // scl_timeout (done in the watchdog process,
                        // which owns that register).
                        state  <= ST_IDLE;
                        done_r <= 1'b1;
                        busy_r <= 1'b0;
                        cnt    <= 0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
            endcase
        end
    end

endmodule
