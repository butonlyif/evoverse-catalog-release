################################## Clock Constraints ##########################
# ws_e1_tse — TJ180A484S / C4 RGMII 千兆以太网
#
# reference_pin 取值来源：Efinity Interface Designer 自动生成的
# outflow/ws_e1_tse.pt.sdc（CLKOUT~X~Y 索引随器件与布局变化，勿手工猜测）。
# 本文件中的端口名与顶层 rtl/ws_e1_tse.v 的实际导出名一致（DDR 双极性：_HI/_LO）。
create_clock -period 20.00 clk_50m
create_clock -period 8.00 clk_125m
create_clock -waveform {2.00 6.00} -period 8.00 clk_125m_90deg
create_clock -period 8.00 pll_rgmii_rx_clk
create_clock -period 100.00 [get_ports {jtag_inst1_TCK}]
# Camera CSI-2 链路时钟（P1/G8）：2026-11-06 起 clk_100m/clk_200m 由 pll_0 直接输出
#（VCO=1000，与 clk_50m 同源同步）；DPHY 恢复字钟（1782/16=111.375M，周期同参考工程
# 8.9787ns；参考工程 ws-e1-cam-ddr-csi2.sdc L70 同构）
create_clock -period 10.000 -name clk_100m [get_ports {clk_100m}]
create_clock -period 5.000  -name clk_200m [get_ports {clk_200m}]
create_clock -period 8.9787 -name dphy_rx2_clk_CLKOUT [get_ports {dphy_rx2_clk_CLKOUT}]

# 各时钟组互斥：组间不建立时序关系
# pll_0 家族（clk_50m/clk_100m/clk_200m）同 VCO 同源同步并为一组，组内保留时序分析
set_clock_groups -exclusive -group {clk_50m clk_100m clk_200m} -group {clk_125m} -group {clk_125m_90deg} -group {rgmii_rxc} -group {jtag_inst1_TCK}
# 相机域与以太网域异步；DPHY 恢复字钟源自传感器（停振无固定相位），独立组
set_clock_groups -asynchronous -group {clk_50m clk_100m clk_200m} -group {pll_rgmii_rx_clk}
set_clock_groups -asynchronous -group {clk_50m clk_100m clk_200m} -group {dphy_rx2_clk_CLKOUT}
set_clock_groups -asynchronous -group {dphy_rx2_clk_CLKOUT} -group {clk_125m}
set_clock_groups -asynchronous -group {dphy_rx2_clk_CLKOUT} -group {clk_125m_90deg}
set_clock_groups -asynchronous -group {dphy_rx2_clk_CLKOUT} -group {pll_rgmii_rx_clk}

# JTAG Constraints（jtag_inst1_RESET/UPDATE/RUNTEST 未 bonding 到封装引脚，不约束）
set_output_delay -clock jtag_inst1_TCK -max 0.117 [get_ports {jtag_inst1_TDO}]
set_output_delay -clock jtag_inst1_TCK -min -0.075 [get_ports {jtag_inst1_TDO}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -max 0.280 [get_ports {jtag_inst1_CAPTURE}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -min 0.187 [get_ports {jtag_inst1_CAPTURE}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -max 0.243 [get_ports {jtag_inst1_SEL}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -min 0.162 [get_ports {jtag_inst1_SEL}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -max 0.337 [get_ports {jtag_inst1_SHIFT}]
set_input_delay -clock_fall -clock jtag_inst1_TCK -min 0.225 [get_ports {jtag_inst1_SHIFT}]

# RGMII RX 侧：以 rgmii_rxc 为参考时钟
set_input_delay -clock rgmii_rxc -reference_pin [get_ports {rgmii_rxc~CLKOUT~333~584}] -max 0.414 [get_ports {rgmii_rx_ctl_LO rgmii_rx_ctl_HI}]
set_input_delay -clock rgmii_rxc -reference_pin [get_ports {rgmii_rxc~CLKOUT~333~584}] -min 0.276 [get_ports {rgmii_rx_ctl_LO rgmii_rx_ctl_HI}]
set_input_delay -clock rgmii_rxc -reference_pin [get_ports {rgmii_rxc~CLKOUT~333~570}] -max 0.414 [get_ports {rgmii_rxd_LO[0] rgmii_rxd_HI[0]}]
set_input_delay -clock rgmii_rxc -reference_pin [get_ports {rgmii_rxc~CLKOUT~333~570}] -min 0.276 [get_ports {rgmii_rxd_LO[0] rgmii_rxd_HI[0]}]
set_input_delay -clock rgmii_rxc -reference_pin [get_ports {rgmii_rxc~CLKOUT~333~571}] -max 0.414 [get_ports {rgmii_rxd_LO[1] rgmii_rxd_HI[1]}]
set_input_delay -clock rgmii_rxc -reference_pin [get_ports {rgmii_rxc~CLKOUT~333~571}] -min 0.276 [get_ports {rgmii_rxd_LO[1] rgmii_rxd_HI[1]}]
set_input_delay -clock rgmii_rxc -reference_pin [get_ports {rgmii_rxc~CLKOUT~333~536}] -max 0.414 [get_ports {rgmii_rxd_LO[2] rgmii_rxd_HI[2]}]
set_input_delay -clock rgmii_rxc -reference_pin [get_ports {rgmii_rxc~CLKOUT~333~536}] -min 0.276 [get_ports {rgmii_rxd_LO[2] rgmii_rxd_HI[2]}]
set_input_delay -clock rgmii_rxc -reference_pin [get_ports {rgmii_rxc~CLKOUT~333~537}] -max 0.414 [get_ports {rgmii_rxd_LO[3] rgmii_rxd_HI[3]}]
set_input_delay -clock rgmii_rxc -reference_pin [get_ports {rgmii_rxc~CLKOUT~333~537}] -min 0.276 [get_ports {rgmii_rxd_LO[3] rgmii_rxd_HI[3]}]

# RGMII TX 侧：数据/控制以 clk_125m 为参考时钟
set_output_delay -clock clk_125m -reference_pin [get_ports {clk_125m~CLKOUT~333~549}] -max 0.263 [get_ports {rgmii_tx_ctl_LO rgmii_tx_ctl_HI}]
set_output_delay -clock clk_125m -reference_pin [get_ports {clk_125m~CLKOUT~333~549}] -min -0.140 [get_ports {rgmii_tx_ctl_LO rgmii_tx_ctl_HI}]
set_output_delay -clock clk_125m -reference_pin [get_ports {clk_125m~CLKOUT~333~526}] -max 0.263 [get_ports {rgmii_txd_LO[0] rgmii_txd_HI[0]}]
set_output_delay -clock clk_125m -reference_pin [get_ports {clk_125m~CLKOUT~333~526}] -min -0.140 [get_ports {rgmii_txd_LO[0] rgmii_txd_HI[0]}]
set_output_delay -clock clk_125m -reference_pin [get_ports {clk_125m~CLKOUT~333~527}] -max 0.263 [get_ports {rgmii_txd_LO[1] rgmii_txd_HI[1]}]
set_output_delay -clock clk_125m -reference_pin [get_ports {clk_125m~CLKOUT~333~527}] -min -0.140 [get_ports {rgmii_txd_LO[1] rgmii_txd_HI[1]}]
set_output_delay -clock clk_125m -reference_pin [get_ports {clk_125m~CLKOUT~333~562}] -max 0.263 [get_ports {rgmii_txd_LO[2] rgmii_txd_HI[2]}]
set_output_delay -clock clk_125m -reference_pin [get_ports {clk_125m~CLKOUT~333~562}] -min -0.140 [get_ports {rgmii_txd_LO[2] rgmii_txd_HI[2]}]
set_output_delay -clock clk_125m -reference_pin [get_ports {clk_125m~CLKOUT~333~561}] -max 0.263 [get_ports {rgmii_txd_LO[3] rgmii_txd_HI[3]}]
set_output_delay -clock clk_125m -reference_pin [get_ports {clk_125m~CLKOUT~333~561}] -min -0.140 [get_ports {rgmii_txd_LO[3] rgmii_txd_HI[3]}]

# RGMII TXC：发送时钟用 90° 移相时钟
set_output_delay -clock clk_125m_90deg -reference_pin [get_ports {clk_125m_90deg~CLKOUT~333~550}] -max 0.263 [get_ports {rgmii_txc_LO rgmii_txc_HI}]
set_output_delay -clock clk_125m_90deg -reference_pin [get_ports {clk_125m_90deg~CLKOUT~333~550}] -min -0.140 [get_ports {rgmii_txc_LO rgmii_txc_HI}]

# MDIO（PHY 管理口）
set_output_delay -clock clk_125m -reference_pin [get_ports {clk_125m~CLKOUT~333~549}] -max 0.263 [get_ports {phy_mdc}]
set_output_delay -clock clk_125m -reference_pin [get_ports {clk_125m~CLKOUT~333~549}] -min -0.140 [get_ports {phy_mdc}]
