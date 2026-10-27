create_clock -period 10.0 S_AXI_CPU_ACLK
create_clock -period 13.333 fx10_gpif_lvds_pclk
create_clock -period 6.25 axi_m0_clk
create_clock -period 6.25 axi_m1_clk
create_clock -period 10.0 csi_cfg_clk
create_clock -period 6.25 mipi_pclk

set_clock_groups -exclusive -group {S_AXI_CPU_ACLK} -group {fx10_gpif_lvds_pclk mipi_pclk}