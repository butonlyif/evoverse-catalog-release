// CFG_RESET / CFG_START / CFG_SEL / CFG_DONE configuration controller.
// CFG_SEL is active-low enable. CFG_DONE is only asserted while the
// initialization is complete and CFG_START remains asserted.
(* keep_hierarchy = "yes" *)
module cfg_ctrl_fsm #(
  parameter int INIT_CYCLES = 1000
) (
  input  logic clk,
  input  logic cfg_reset,   // active high
  input  logic cfg_start,
  input  logic cfg_sel,     // active low enable
  output logic cfg_done,
  output logic init_busy
);
  typedef enum logic [1:0] {
    S_IDLE,
    S_INIT,
    S_DONE
  } state_t;

  state_t state;
  int     cnt;

  always_ff @(posedge clk) begin
    if (cfg_reset) begin
      state <= S_IDLE;
      cnt   <= 0;
    end else if (cfg_sel) begin
      state <= S_IDLE;
      cnt   <= 0;
    end else begin
      case (state)
        S_IDLE: begin
          cnt <= 0;
          if (cfg_start) state <= S_INIT;
        end
        S_INIT: begin
          if (!cfg_start) begin
            state <= S_IDLE;
            cnt   <= 0;
          end else if (cnt >= INIT_CYCLES-1) begin
            state <= S_DONE;
            cnt   <= 0;
          end else begin
            cnt <= cnt + 1;
          end
        end
        S_DONE: begin
          // If the software drops CFG_START after DONE the controller returns
          // to IDLE; the TB assertion flags this as a contract violation.
          if (!cfg_start) state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
    end
  end

  assign cfg_done  = (state == S_DONE) && !cfg_reset && !cfg_sel && cfg_start;
  assign init_busy = (state != S_DONE);

endmodule
