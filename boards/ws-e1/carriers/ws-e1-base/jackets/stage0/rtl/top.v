// ws-e1-base-stage0 -- EvoVerse SDK Stage-0 skeleton (LED blink)
// Pins resolved from the carrier pin map: clk_50m@T18, arst_n@H21, led_user@F21
`default_nettype none
module ws_e1_base_stage0 (
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
