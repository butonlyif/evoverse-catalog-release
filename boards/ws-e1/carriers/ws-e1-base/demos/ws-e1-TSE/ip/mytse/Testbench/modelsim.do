onerror {quit -f}
vlib work
vlog -sv -timescale 1ns/1ps +define+SIM+SIM_MODE+EFX_SIM -sv ./temac_ex.v ./apb3_2_axi4_lite.v ./axi4_st_mux.v ./mac_pat_gen.v ./mac_rx2tx.v ./reg_apb3.v ./udp_pat_gen.v ./tb_header.v ./tb_top.v ./ODDR.v ./glbl.v ./DaulClkFifo.v ./modelsim/mytse.sv
vsim -t ns work.tb_top -gui -voptargs="+acc"
log -r /*
run -all
