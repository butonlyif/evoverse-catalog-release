
# Efinity Interface Designer SDC
# Version: 2022.2.317
# Date: 2022-12-22 16:24

# Copyright (C) 2017 - 2022 Efinix Inc. All rights reserved.

# Device: Ti180L484
# Project: top
# Timing Model: C4 (preliminary)
#               NOTE: The timing data is not final

# PLL Constraints
#################
create_clock -period 10.0000 pll_inst2__CLKOUT0
create_clock -period 6.4 mipi_dphy_tx_pclk

create_clock -period 10.000 -name mipi_rx_cfg_clk [get_ports {mipi_rx_cfg_clk}]
create_clock -period 4.000 -name dphy_byte_clk [get_ports {dphy_byte_clk}]
create_clock -period 4.000 -name dbg_clk [get_ports {dbg_clk}]
create_clock -period 200.000 -name CLK_5M [get_ports {CLK_5M}]
create_clock -period 40.000 -name i_fb_clk [get_ports {i_fb_clk}]
create_clock -period 50.000 -name esc_clk [get_ports {esc_clk}]
create_clock -period 40.000 -name mipi_ref_clk [get_ports {mipi_ref_clk}]
create_clock -period 6.800 -name i_sysclk_div2 [get_ports {i_sysclk_div2}]

set_clock_groups -asynchronous  -group {i_fb_clk} 
set_clock_groups -asynchronous   -group {i_sysclk_div2}
set_clock_groups -asynchronous -group {dphy_byte_clk}
set_clock_groups -asynchronous -group {esc_clk}
set_clock_groups -asynchronous -group {mipi_dphy_tx_pclk}
set_clock_groups -asynchronous  -group {i_fb_clk} 
# MIPI DPHY TX Constraints
############################
#create_clock -period 6.4000 -name mipi_dphy_tx_pclk [get_ports {mipi_dphy_tx_pclk}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 2.042 [get_ports {mipi_dphy_tx_inst1_TX_DATA_HS_LAN0[*]}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.190 [get_ports {mipi_dphy_tx_inst1_TX_DATA_HS_LAN0[*]}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.973 [get_ports {mipi_dphy_tx_inst1_TX_DATA_HS_LAN1[*]}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.272 [get_ports {mipi_dphy_tx_inst1_TX_DATA_HS_LAN1[*]}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 2.029 [get_ports {mipi_dphy_tx_inst1_TX_DATA_HS_LAN2[*]}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.320 [get_ports {mipi_dphy_tx_inst1_TX_DATA_HS_LAN2[*]}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.949 [get_ports {mipi_dphy_tx_inst1_TX_DATA_HS_LAN3[*]}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.279 [get_ports {mipi_dphy_tx_inst1_TX_DATA_HS_LAN3[*]}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.547 [get_ports {mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN0}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.064 [get_ports {mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN0}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.931 [get_ports {mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN1}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.267 [get_ports {mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN1}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.604 [get_ports {mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN2}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.273 [get_ports {mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN2}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.828 [get_ports {mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN3}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.242 [get_ports {mipi_dphy_tx_inst1_TX_WORD_VALID_HS_LAN3}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.602 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_HS}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.214 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_HS}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.705 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN0}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.043 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN0}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.887 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN1}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.190 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN1}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 2.074 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN2}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.214 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN2}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.932 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN3}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.193 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_HS_LAN3}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.543 [get_ports {mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN0}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.069 [get_ports {mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN0}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.966 [get_ports {mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN1}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.177 [get_ports {mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN1}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.776 [get_ports {mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN2}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.257 [get_ports {mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN2}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 1.748 [get_ports {mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN3}]
set_output_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 0.190 [get_ports {mipi_dphy_tx_inst1_TX_SKEW_CAL_HS_LAN3}]
set_input_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 2.778 [get_ports {mipi_dphy_tx_inst1_TX_READY_HS_LAN0}]
set_input_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 1.611 [get_ports {mipi_dphy_tx_inst1_TX_READY_HS_LAN0}]
set_input_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 2.766 [get_ports {mipi_dphy_tx_inst1_TX_READY_HS_LAN1}]
set_input_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 1.604 [get_ports {mipi_dphy_tx_inst1_TX_READY_HS_LAN1}]
set_input_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 3.002 [get_ports {mipi_dphy_tx_inst1_TX_READY_HS_LAN2}]
set_input_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 1.740 [get_ports {mipi_dphy_tx_inst1_TX_READY_HS_LAN2}]
set_input_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -max 2.925 [get_ports {mipi_dphy_tx_inst1_TX_READY_HS_LAN3}]
set_input_delay -clock mipi_dphy_tx_pclk -reference_pin [get_ports {mipi_dphy_tx_pclk~CLKOUT~2~520}] -min 1.695 [get_ports {mipi_dphy_tx_inst1_TX_READY_HS_LAN3}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 2.865 [get_ports {mipi_dphy_tx_inst1_TX_DATA_ESC[*]}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.350 [get_ports {mipi_dphy_tx_inst1_TX_DATA_ESC[*]}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 2.690 [get_ports {mipi_dphy_tx_inst1_TX_LPDT_ESC}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.155 [get_ports {mipi_dphy_tx_inst1_TX_LPDT_ESC}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 3.030 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN0}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.121 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN0}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 3.004 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN1}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.287 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN1}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 3.072 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN2}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.328 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN2}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 3.024 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN3}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.263 [get_ports {mipi_dphy_tx_inst1_TX_REQUEST_ESC_LAN3}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 2.921 [get_ports {mipi_dphy_tx_inst1_TX_TRIGGER_ESC[*]}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.281 [get_ports {mipi_dphy_tx_inst1_TX_TRIGGER_ESC[*]}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 2.262 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_CLK}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.219 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_CLK}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 2.917 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN0}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.300 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN0}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 3.034 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN1}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.181 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN1}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 2.939 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN2}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.293 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN2}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 2.771 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN3}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.273 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_ESC_LAN3}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 2.094 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_EXIT}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.239 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_EXIT}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 3.346 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN0}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.172 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN0}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 3.199 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN1}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.205 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN1}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 2.754 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN2}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.386 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN2}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 2.864 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN3}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.306 [get_ports {mipi_dphy_tx_inst1_TX_ULPS_EXIT_LAN3}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 2.701 [get_ports {mipi_dphy_tx_inst1_TX_VALID_ESC}]
set_output_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 0.295 [get_ports {mipi_dphy_tx_inst1_TX_VALID_ESC}]
set_input_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -max 4.626 [get_ports {mipi_dphy_tx_inst1_TX_READY_ESC}]
set_input_delay -clock esc_clk -reference_pin [get_ports {esc_clk~CLKOUT~1~520}] -min 2.682 [get_ports {mipi_dphy_tx_inst1_TX_READY_ESC}]

# Clock Latency Constraints
############################
# set_clock_latency -source -setup <pll_clk_latency_i_fb_50m_max - 0.008> [get_ports {i_fb_clk}]
# set_clock_latency -source -hold <pll_clk_latency_i_fb_50m_min - 0.005> [get_ports {i_fb_clk}]
# set_clock_latency -source -setup <pll_clk_latency_i_fb_50m_max - 0.008> [get_ports {esc_clk}]
# set_clock_latency -source -hold <pll_clk_latency_i_fb_50m_min - 0.005> [get_ports {esc_clk}]
# set_clock_latency -source -setup <pll_clk_latency_i_fb_50m_max - 0.008> [get_ports {mipi_ref_clk}]
# set_clock_latency -source -hold <pll_clk_latency_i_fb_50m_min - 0.005> [get_ports {mipi_ref_clk}]
# set_clock_latency -source -setup <pll_clk_latency_i_fb_50m_max - 0.008> [get_ports {i_sysclk_div2}]
# set_clock_latency -source -hold <pll_clk_latency_i_fb_50m_min - 0.005> [get_ports {i_sysclk_div2}]
# set_clock_latency -source -setup <pll_clk_latency_i_fb_50m_max - 0.005> [get_ports {mipi_rx_cfg_clk}]
# set_clock_latency -source -hold <pll_clk_latency_i_fb_50m_min - 0.003> [get_ports {mipi_rx_cfg_clk}]
# set_clock_latency -source -setup <pll_clk_latency_i_fb_50m_max - 0.005> [get_ports {dphy_byte_clk}]
# set_clock_latency -source -hold <pll_clk_latency_i_fb_50m_min - 0.003> [get_ports {dphy_byte_clk}]
# set_clock_latency -source -setup <pll_clk_latency_i_fb_50m_max - 0.005> [get_ports {dbg_clk}]
# set_clock_latency -source -hold <pll_clk_latency_i_fb_50m_min - 0.003> [get_ports {dbg_clk}]
# set_clock_latency -source -setup <pll_clk_latency_i_fb_50m_max - 0.005> [get_ports {CLK_5M}]
# set_clock_latency -source -hold <pll_clk_latency_i_fb_50m_min - 0.003> [get_ports {CLK_5M}]
# set_clock_latency -source -setup <board_max + 2.193> [get_ports {i_fb_50m}]
# set_clock_latency -source -hold <board_min + 1.271> [get_ports {i_fb_50m}]
