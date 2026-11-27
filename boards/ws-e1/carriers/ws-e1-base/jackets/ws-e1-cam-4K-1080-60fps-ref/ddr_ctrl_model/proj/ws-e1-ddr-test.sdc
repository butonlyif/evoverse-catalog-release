
# Minimal DDR test project SDC（从 ws-e1-cam-ddr-csi2.sdc 裁剪）
# 注意：此文件由 Interface Designer 生成/覆盖；手工版本仅用于直接跑
# efx_map/efx_pnr 命令行流程。peri 重新生成后以生成版为准。

# PLL Constraints
###################
# sys_clk_100m 约束已移除：顶层仅保留该 peri 输出端口但不使用，
# 综合后端口被移除，create_clock 会报 "No valid pin(s) found"（2026-10-22 PnR 实测）
# create_clock -period 8.000 -name sys_clk_100m [get_ports {sys_clk_100m}]
create_clock -period 5.000 -name sys_clk_200m [get_ports {sys_clk_200m}]

# GPIO Constraints
####################
create_clock -period 37.037 -name i_clk_27m [get_ports {i_clk_27m}]
# uart_0_txd：115200 慢速输出，默认约束即可；如需显式：
# set_output_delay -clock sys_clk_200m -max 10.0 [get_ports {uart_0_txd}]

# DDR Constraints（peri 生成版含完整 input/output delay，命令行流程可省——
# DDR 硬核侧路径由器件弧约束，fabric 侧仅在跨 200M 时需检查）
###################

# 本工程全部逻辑在 sys_clk_200m 单域（i_clk_27m 仅 POR 计数器，无跨域路径）
set_clock_groups -asynchronous -group {sys_clk_200m} -group {i_clk_27m}
