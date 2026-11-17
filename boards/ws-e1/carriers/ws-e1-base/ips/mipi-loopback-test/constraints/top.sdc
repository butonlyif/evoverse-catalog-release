
# Efinity Interface Designer SDC
# Version: 2023.1.150.5.11
# Date: 2023-11-06 23:24

# Copyright (C) 2017 - 2023 Efinix Inc. All rights reserved.

# Device: Ti180J484
# Project: Ti180MIPI
# Timing Model: I4 (final)

# PLL Constraints
#################

create_clock -period 40.0000 clk0
create_clock -period 5 pixel_clk
create_clock -period 10.0000 mipi_clk
create_clock -period 10.0000 cfg_clk
create_clock -period 50.0000 esc_clk
create_clock -period 20.0000 pll_inst2_CLKOUT2
create_clock -period 40.0000 pll_inst2_CLKOUT3  
create_clock -period 8 mipi_dphy_rx_clk_CLKOUT
create_clock -period 8 mipi_dphy_tx_SLOWCLK

create_clock -period 10.00 mipi_dphy_rx_inst2_CAL_CLK
create_clock -period 50.00 mipi_dphy_tx_inst1_ESC_CLK

set_clock_groups -asynchronous -group {pixel_clk} 
set_clock_groups -asynchronous -group {cfg_clk}
set_clock_groups -asynchronous -group {mipi_clk}
set_clock_groups -asynchronous -group {esc_clk}
set_clock_groups -asynchronous -group {jtag_inst1_TCK}	
set_clock_groups -asynchronous -group {mipi_dphy_rx_inst2_CAL_CLK}	
set_clock_groups -asynchronous -group {mipi_dphy_tx_inst1_ESC_CLK}	
set_clock_groups -asynchronous -group {mipi_dphy_tx_SLOWCLK}
set_clock_groups -asynchronous -group {mipi_dphy_rx_clk_CLKOUT}												
# GPIO Constraints
####################
# set_input_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -max <MAX CALCULATION> [get_ports {MIPI_REF_CLK}]
# set_input_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -min <MIN CALCULATION> [get_ports {MIPI_REF_CLK}]

# MIPI DPHY RX Constraints
#####################################
create_clock -period 6.4000 [get_ports {mipi_dphy_rx_clk_CLKOUT}]
create_clock -period 6.4000 [get_ports {mipi_dphy_rx_inst2_LP_CLK}]
create_clock -period 6.4000 [get_ports {mipi_dphy_rx_inst2_ESC_LAN0_CLK}]
create_clock -period 6.4000 [get_ports {mipi_dphy_rx_inst2_ESC_LAN1_CLK}]
create_clock -period 6.4000 [get_ports {mipi_dphy_rx_inst2_ESC_LAN2_CLK}]
create_clock -period 6.4000 [get_ports {mipi_dphy_rx_inst2_ESC_LAN3_CLK}]
set_output_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 0.835 [get_ports {mipi_dphy_rx_inst2_RST0_N}]
set_output_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 0.089 [get_ports {mipi_dphy_rx_inst2_RST0_N}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN0_CLK -max 4.343 [get_ports {mipi_dphy_rx_inst2_RX_DATA_ESC[*]}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN0_CLK -min 2.895 [get_ports {mipi_dphy_rx_inst2_RX_DATA_ESC[*]}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN0_CLK -max 4.039 [get_ports {mipi_dphy_rx_inst2_RX_LPDT_ESC}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN0_CLK -min 2.693 [get_ports {mipi_dphy_rx_inst2_RX_LPDT_ESC}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN0_CLK -max 3.907 [get_ports {mipi_dphy_rx_inst2_RX_TRIGGER_ESC[3] mipi_dphy_rx_inst2_RX_TRIGGER_ESC[2] mipi_dphy_rx_inst2_RX_TRIGGER_ESC[1] mipi_dphy_rx_inst2_RX_TRIGGER_ESC[0]}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN0_CLK -min 2.605 [get_ports {mipi_dphy_rx_inst2_RX_TRIGGER_ESC[3] mipi_dphy_rx_inst2_RX_TRIGGER_ESC[2] mipi_dphy_rx_inst2_RX_TRIGGER_ESC[1] mipi_dphy_rx_inst2_RX_TRIGGER_ESC[0]}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN0_CLK -max 3.387 [get_ports {mipi_dphy_rx_inst2_ULPS_LAN0_ENTER}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN0_CLK -min 2.258 [get_ports {mipi_dphy_rx_inst2_ULPS_LAN0_ENTER}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN0_CLK -max 3.465 [get_ports {mipi_dphy_rx_inst2_RX_VALID_ESC}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN0_CLK -min 2.310 [get_ports {mipi_dphy_rx_inst2_RX_VALID_ESC}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN1_CLK -max 3.783 [get_ports {mipi_dphy_rx_inst2_ULPS_LAN1_ENTER}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN1_CLK -min 2.522 [get_ports {mipi_dphy_rx_inst2_ULPS_LAN1_ENTER}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN2_CLK -max 4.925 [get_ports {mipi_dphy_rx_inst2_ULPS_LAN2_ENTER}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN2_CLK -min 3.283 [get_ports {mipi_dphy_rx_inst2_ULPS_LAN2_ENTER}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN3_CLK -max 3.289 [get_ports {mipi_dphy_rx_inst2_ULPS_LAN3_ENTER}]
set_input_delay -clock mipi_dphy_rx_inst2_ESC_LAN3_CLK -min 2.192 [get_ports {mipi_dphy_rx_inst2_ULPS_LAN3_ENTER}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.607 [get_ports {mipi_dphy_rx_inst2_ERR_SOT_HS_LAN0}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.071 [get_ports {mipi_dphy_rx_inst2_ERR_SOT_HS_LAN0}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.619 [get_ports {mipi_dphy_rx_inst2_ERR_SOT_HS_LAN1}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.079 [get_ports {mipi_dphy_rx_inst2_ERR_SOT_HS_LAN1}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.559 [get_ports {mipi_dphy_rx_inst2_ERR_SOT_HS_LAN2}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.040 [get_ports {mipi_dphy_rx_inst2_ERR_SOT_HS_LAN2}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.570 [get_ports {mipi_dphy_rx_inst2_ERR_SOT_HS_LAN3}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.046 [get_ports {mipi_dphy_rx_inst2_ERR_SOT_HS_LAN3}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.667 [get_ports {mipi_dphy_rx_inst2_HS_LAN0_SOTSYNC_ERROR}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.112 [get_ports {mipi_dphy_rx_inst2_HS_LAN0_SOTSYNC_ERROR}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.613 [get_ports {mipi_dphy_rx_inst2_HS_LAN1_SOTSYNC_ERROR}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.075 [get_ports {mipi_dphy_rx_inst2_HS_LAN1_SOTSYNC_ERROR}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.745 [get_ports {mipi_dphy_rx_inst2_HS_LAN2_SOTSYNC_ERROR}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.163 [get_ports {mipi_dphy_rx_inst2_HS_LAN2_SOTSYNC_ERROR}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.584 [get_ports {mipi_dphy_rx_inst2_HS_LAN3_SOTSYNC_ERROR}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.056 [get_ports {mipi_dphy_rx_inst2_HS_LAN3_SOTSYNC_ERROR}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.627 [get_ports {mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN0}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.085 [get_ports {mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN0}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.644 [get_ports {mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN1}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.096 [get_ports {mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN1}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.560 [get_ports {mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN2}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.040 [get_ports {mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN2}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.493 [get_ports {mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN3}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 0.995 [get_ports {mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN3}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.693 [get_ports {mipi_dphy_rx_inst2_HS_LAN0_DATA[*]}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.128 [get_ports {mipi_dphy_rx_inst2_HS_LAN0_DATA[*]}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.723 [get_ports {mipi_dphy_rx_inst2_HS_LAN1_DATA[*]}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.149 [get_ports {mipi_dphy_rx_inst2_HS_LAN1_DATA[*]}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.698 [get_ports {mipi_dphy_rx_inst2_HS_LAN2_DATA[*]}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.132 [get_ports {mipi_dphy_rx_inst2_HS_LAN2_DATA[*]}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.734 [get_ports {mipi_dphy_rx_inst2_HS_LAN3_DATA[*]}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.156 [get_ports {mipi_dphy_rx_inst2_HS_LAN3_DATA[*]}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.723 [get_ports {mipi_dphy_rx_inst2_HS_LAN0_SKEWCAL}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.149 [get_ports {mipi_dphy_rx_inst2_HS_LAN0_SKEWCAL}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.656 [get_ports {mipi_dphy_rx_inst2_HS_LAN1_SKEWCAL}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.104 [get_ports {mipi_dphy_rx_inst2_HS_LAN1_SKEWCAL}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.717 [get_ports {mipi_dphy_rx_inst2_HS_LAN2_SKEWCAL}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.145 [get_ports {mipi_dphy_rx_inst2_HS_LAN2_SKEWCAL}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.583 [get_ports {mipi_dphy_rx_inst2_HS_LAN3_SKEWCAL}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.056 [get_ports {mipi_dphy_rx_inst2_HS_LAN3_SKEWCAL}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.707 [get_ports {mipi_dphy_rx_inst2_HS_LAN0_SYNC}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.138 [get_ports {mipi_dphy_rx_inst2_HS_LAN0_SYNC}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.632 [get_ports {mipi_dphy_rx_inst2_HS_LAN1_SYNC}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.088 [get_ports {mipi_dphy_rx_inst2_HS_LAN1_SYNC}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.583 [get_ports {mipi_dphy_rx_inst2_HS_LAN2_SYNC}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.056 [get_ports {mipi_dphy_rx_inst2_HS_LAN2_SYNC}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.536 [get_ports {mipi_dphy_rx_inst2_HS_LAN3_SYNC}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.024 [get_ports {mipi_dphy_rx_inst2_HS_LAN3_SYNC}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.645 [get_ports {mipi_dphy_rx_inst2_HS_LAN0_VALID}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.097 [get_ports {mipi_dphy_rx_inst2_HS_LAN0_VALID}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.612 [get_ports {mipi_dphy_rx_inst2_HS_LAN1_VALID}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.075 [get_ports {mipi_dphy_rx_inst2_HS_LAN1_VALID}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.563 [get_ports {mipi_dphy_rx_inst2_HS_LAN2_VALID}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.042 [get_ports {mipi_dphy_rx_inst2_HS_LAN2_VALID}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.582 [get_ports {mipi_dphy_rx_inst2_HS_LAN3_VALID}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.055 [get_ports {mipi_dphy_rx_inst2_HS_LAN3_VALID}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.647 [get_ports {mipi_dphy_rx_inst2_STOPSTATE_LAN0}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.098 [get_ports {mipi_dphy_rx_inst2_STOPSTATE_LAN0}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.592 [get_ports {mipi_dphy_rx_inst2_STOPSTATE_LAN1}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.061 [get_ports {mipi_dphy_rx_inst2_STOPSTATE_LAN1}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.591 [get_ports {mipi_dphy_rx_inst2_STOPSTATE_LAN2}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.060 [get_ports {mipi_dphy_rx_inst2_STOPSTATE_LAN2}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -max 1.613 [get_ports {mipi_dphy_rx_inst2_STOPSTATE_LAN3}]
set_input_delay -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}] -min 1.075 [get_ports {mipi_dphy_rx_inst2_STOPSTATE_LAN3}]

# MIPI DPHY TX Constraints
#####################################
create_clock -period 6.4000 [get_ports {mipi_dphy_tx_SLOWCLK}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.492 [get_ports {mipi_dphy_tx_inst1_TX_DATA_ESC[*]}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.350 [get_ports {mipi_dphy_tx_inst1_TX_DATA_ESC[*]}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.776 [get_ports {mipi_dphy_tx_inst1_HS_LAN0_DATA[*]}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.190 [get_ports {mipi_dphy_tx_inst1_HS_LAN0_DATA[*]}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.716 [get_ports {mipi_dphy_tx_inst1_HS_LAN1_DATA[*]}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.272 [get_ports {mipi_dphy_tx_inst1_HS_LAN1_DATA[*]}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.764 [get_ports {mipi_dphy_tx_inst1_HS_LAN2_DATA[*]}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.320 [get_ports {mipi_dphy_tx_inst1_HS_LAN2_DATA[*]}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.695 [get_ports {mipi_dphy_tx_inst1_HS_LAN3_DATA[*]}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.279 [get_ports {mipi_dphy_tx_inst1_HS_LAN3_DATA[*]}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.339 [get_ports {mipi_dphy_tx_inst1_TX_LPDT_ESC}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.155 [get_ports {mipi_dphy_tx_inst1_TX_LPDT_ESC}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.345 [get_ports {mipi_dphy_tx_inst1_HS_LAN0_HIGHVALID}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.064 [get_ports {mipi_dphy_tx_inst1_HS_LAN0_HIGHVALID}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.679 [get_ports {mipi_dphy_tx_inst1_HS_LAN1_HIGHVALID}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.267 [get_ports {mipi_dphy_tx_inst1_HS_LAN1_HIGHVALID}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.394 [get_ports {mipi_dphy_tx_inst1_HS_LAN2_HIGHVALID}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.273 [get_ports {mipi_dphy_tx_inst1_HS_LAN2_HIGHVALID}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.590 [get_ports {mipi_dphy_tx_inst1_HS_LAN3_HIGHVALID}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.241 [get_ports {mipi_dphy_tx_inst1_HS_LAN3_HIGHVALID}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.634 [get_ports {mipi_dphy_tx_inst1_REQUESTESC_LAN0}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.121 [get_ports {mipi_dphy_tx_inst1_REQUESTESC_LAN0}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.612 [get_ports {mipi_dphy_tx_inst1_REQUESTESC_LAN1}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.287 [get_ports {mipi_dphy_tx_inst1_REQUESTESC_LAN1}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.671 [get_ports {mipi_dphy_tx_inst1_REQUESTESC_LAN2}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.328 [get_ports {mipi_dphy_tx_inst1_REQUESTESC_LAN2}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.629 [get_ports {mipi_dphy_tx_inst1_REQUESTESC_LAN3}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.263 [get_ports {mipi_dphy_tx_inst1_REQUESTESC_LAN3}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.393 [get_ports {mipi_dphy_tx_inst1_HS_CLK_REQUEST}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.214 [get_ports {mipi_dphy_tx_inst1_HS_CLK_REQUEST}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.483 [get_ports {mipi_dphy_tx_inst1_HS_LAN0_REQUEST}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.043 [get_ports {mipi_dphy_tx_inst1_HS_LAN0_REQUEST}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.641 [get_ports {mipi_dphy_tx_inst1_HS_LAN1_REQUEST}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.190 [get_ports {mipi_dphy_tx_inst1_HS_LAN1_REQUEST}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.804 [get_ports {mipi_dphy_tx_inst1_HS_LAN2_REQUEST}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.213 [get_ports {mipi_dphy_tx_inst1_HS_LAN2_REQUEST}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.680 [get_ports {mipi_dphy_tx_inst1_HS_LAN3_REQUEST}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.193 [get_ports {mipi_dphy_tx_inst1_HS_LAN3_REQUEST}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.342 [get_ports {mipi_dphy_tx_inst1_HS_LAN0_SKEWCAL}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.069 [get_ports {mipi_dphy_tx_inst1_HS_LAN0_SKEWCAL}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.709 [get_ports {mipi_dphy_tx_inst1_HS_LAN1_SKEWCAL}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.177 [get_ports {mipi_dphy_tx_inst1_HS_LAN1_SKEWCAL}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.545 [get_ports {mipi_dphy_tx_inst1_HS_LAN2_SKEWCAL}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.257 [get_ports {mipi_dphy_tx_inst1_HS_LAN2_SKEWCAL}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 1.520 [get_ports {mipi_dphy_tx_inst1_HS_LAN3_SKEWCAL}]
set_output_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 0.190 [get_ports {mipi_dphy_tx_inst1_HS_LAN3_SKEWCAL}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.540 [get_ports {mipi_dphy_tx_inst1_TX_TRIGGER_ESC[3] mipi_dphy_tx_inst1_TX_TRIGGER_ESC[2] mipi_dphy_tx_inst1_TX_TRIGGER_ESC[1] mipi_dphy_tx_inst1_TX_TRIGGER_ESC[0]}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.281 [get_ports {mipi_dphy_tx_inst1_TX_TRIGGER_ESC[3] mipi_dphy_tx_inst1_TX_TRIGGER_ESC[2] mipi_dphy_tx_inst1_TX_TRIGGER_ESC[1] mipi_dphy_tx_inst1_TX_TRIGGER_ESC[0]}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 1.967 [get_ports {mipi_dphy_tx_inst1_ULPS_CLK_ENTER}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.219 [get_ports {mipi_dphy_tx_inst1_ULPS_CLK_ENTER}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.537 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN0_ENTER}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.300 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN0_ENTER}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.639 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN1_ENTER}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.181 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN1_ENTER}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.556 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN2_ENTER}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.293 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN2_ENTER}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.410 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN3_ENTER}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.273 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN3_ENTER}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 1.821 [get_ports {mipi_dphy_tx_inst1_ULPS_CLK_EXIT}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.239 [get_ports {mipi_dphy_tx_inst1_ULPS_CLK_EXIT}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.910 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN0_EXIT}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.172 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN0_EXIT}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.781 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN1_EXIT}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.205 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN1_EXIT}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.395 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN2_EXIT}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.386 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN2_EXIT}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.491 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN3_EXIT}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.306 [get_ports {mipi_dphy_tx_inst1_ULPS_LAN3_EXIT}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 2.349 [get_ports {mipi_dphy_tx_inst1_TX_VALID_ESC}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 0.295 [get_ports {mipi_dphy_tx_inst1_TX_VALID_ESC}]
set_input_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 2.416 [get_ports {mipi_dphy_tx_inst1_HS_LAN0_READY}]
set_input_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 1.611 [get_ports {mipi_dphy_tx_inst1_HS_LAN0_READY}]
set_input_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 2.406 [get_ports {mipi_dphy_tx_inst1_HS_LAN1_READY}]
set_input_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 1.604 [get_ports {mipi_dphy_tx_inst1_HS_LAN1_READY}]
set_input_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 2.610 [get_ports {mipi_dphy_tx_inst1_HS_LAN2_READY}]
set_input_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 1.740 [get_ports {mipi_dphy_tx_inst1_HS_LAN2_READY}]
set_input_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -max 2.543 [get_ports {mipi_dphy_tx_inst1_HS_LAN3_READY}]
set_input_delay -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}] -min 1.695 [get_ports {mipi_dphy_tx_inst1_HS_LAN3_READY}]
set_input_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -max 4.023 [get_ports {mipi_dphy_tx_inst1_TX_READY_ESC}]
set_input_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}] -min 2.682 [get_ports {mipi_dphy_tx_inst1_TX_READY_ESC}]

# JTAG Constraints
####################
 create_clock -period 100 [get_ports {jtag_inst1_TCK}]
set_output_delay -clock jtag_inst1_TCK -max 0.117 [get_ports {jtag_inst1_TDO}]
set_output_delay -clock jtag_inst1_TCK -min -0.075 [get_ports {jtag_inst1_TDO}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -max 0.280 [get_ports {jtag_inst1_CAPTURE}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -min 0.187 [get_ports {jtag_inst1_CAPTURE}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -max 0.280 [get_ports {jtag_inst1_RESET}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -min 0.187 [get_ports {jtag_inst1_RESET}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -max 0.243 [get_ports {jtag_inst1_SEL}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -min 0.162 [get_ports {jtag_inst1_SEL}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -max 0.280 [get_ports {jtag_inst1_UPDATE}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -min 0.187 [get_ports {jtag_inst1_UPDATE}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -max 0.337 [get_ports {jtag_inst1_SHIFT}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -min 0.225 [get_ports {jtag_inst1_SHIFT}]
# JTAG Constraints (extra... not used by current Efinity debug tools)
# create_clock -period <USER_PERIOD> [get_ports {jtag_inst1_DRCK}]
# set_input_delay -clock_fall -clock jtag_inst1_TCK -max 0.280 [get_ports {jtag_inst1_RUNTEST}]
# set_input_delay -clock_fall -clock jtag_inst1_TCK -min 0.187 [get_ports {jtag_inst1_RUNTEST}]
# Create separate clock groups for JTAG clocks. Remove DRCK clock from the list below if it is not defined.
# set_clock_groups -asynchronous -group {jtag_inst1_TCK jtag_inst1_DRCK}

# HSIO GPIO Constraints
#########################
# set_input_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -max <MAX CALCULATION> [get_ports {reset_n}]
# set_input_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -min <MIN CALCULATION> [get_ports {reset_n}]
# set_input_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -max <MAX CALCULATION> [get_ports {start_transfer_n}]
# set_input_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -min <MIN CALCULATION> [get_ports {start_transfer_n}]
# set_output_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -max <MAX CALCULATION> [get_ports {led[0]}]
# set_output_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -min <MIN CALCULATION> [get_ports {led[0]}]
# set_output_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -max <MAX CALCULATION> [get_ports {led[1]}]
# set_output_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -min <MIN CALCULATION> [get_ports {led[1]}]
# set_output_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -max <MAX CALCULATION> [get_ports {led[2]}]
# set_output_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -min <MIN CALCULATION> [get_ports {led[2]}]
# set_output_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -max <MAX CALCULATION> [get_ports {led[3]}]
# set_output_delay -clock <CLOCK> [-reference_pin <clkout_pad>] -min <MIN CALCULATION> [get_ports {led[3]}]

# Clockout Interface
######################
# mipi_dphy_rx_inst2 -clock mipi_dphy_rx_clk_CLKOUT -reference_pin [get_ports {mipi_dphy_rx_clk_CLKOUT~CLKOUT~1~81}]
# mipi_dphy_tx_inst1 -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~78}]
# mipi_dphy_tx_inst1 -clock mipi_dphy_tx_SLOWCLK -reference_pin [get_ports {mipi_dphy_tx_SLOWCLK~CLKOUT~2~78}]
