vlib work

vlog +define+RTL_SIM line_buffer.v
vlog +define+RTL_SIM ../true_dual_port_ram.v

vlog line_buffer_tb.v
vsim -t ns -novopt work.line_buffer_tb

add wave -hex -position insertpoint  \
sim:/line_buffer_tb/r_arst \
sim:/line_buffer_tb/r_sysclk 

add wave -hex -position insertpoint  \
sim:/line_buffer_tb/r_we \
sim:/line_buffer_tb/i_Y_wd 

add wave -unsigned -position insertpoint  \
sim:/line_buffer_tb/w_ptr 

add wave -hex -position insertpoint  \
sim:/line_buffer_tb/w_vs \
sim:/line_buffer_tb/w_hs \
sim:/line_buffer_tb/w_ah \
sim:/line_buffer_tb/w_de \
sim:/line_buffer_tb/w_Y_rd 

add wave -hex -position insertpoint  \
sim:/line_buffer_tb/inst_line_buffer/inst_y_buffer/we1 \
sim:/line_buffer_tb/inst_line_buffer/inst_y_buffer/din1 \
sim:/line_buffer_tb/inst_line_buffer/inst_y_buffer/addr1 \
sim:/line_buffer_tb/inst_line_buffer/inst_y_buffer/addr2 \
sim:/line_buffer_tb/inst_line_buffer/inst_y_buffer/dout1 \
sim:/line_buffer_tb/inst_line_buffer/inst_y_buffer/dout2
