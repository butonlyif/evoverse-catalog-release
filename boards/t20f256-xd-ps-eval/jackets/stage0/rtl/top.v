// t20f256-xd-ps-eval-stage0 -- EvoVerse SDK Stage-0 skeleton (LED blink)
// Pins resolved from the carrier pin map: clk_50m@H13, arst_n@A4, led_user@T8
`default_nettype none
module t20f256_xd_ps_eval_stage0 (
    input  wire clk_50m,
    input  wire arst_n,
    output wire led_user
);
    reg [23:0] cnt;
    always @(posedge clk_50m) begin
        if (!arst_n) cnt <= 24'd0;
        else         cnt <= cnt + 1'b1;
    end
    assign led_user = cnt[23];  // ~0.34 Hz blink @ 50 MHz
endmodule
`default_nettype wire
