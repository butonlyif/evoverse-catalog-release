import io
p = r'D:\Projs\ws-e1-TSE\sim\tb_udp_v2.v'
s = io.open(p, encoding='utf-8').read()
s = s.replace('if ((total >= 1495 && total <= 1512) || (total >= 2680498 && total <= 2680508))',
              'if ((total >= 1497 && total <= 1503) || (total >= 2680498 && total <= 2680504))')
s = s.replace('$display("  BEAT total=%0d tdata=%02x tlast=%b state=%0d hdr_cnt=%0d pay_cnt=%0d meta_cnt=%0d grp_byte=%0d",\n                total, tdata, tlast, dut.state, dut.hdr_cnt, dut.pay_left, dut.meta_cnt, dut.grp_byte);',
              '$display("  BEAT total=%0d tvalid=%b tdata=%02x tlast=%b state=%0d hdr_cnt=%0d pay_left=%0d ipg_cnt=%0d",\n                total, tvalid, tdata, tlast, dut.state, dut.hdr_cnt, dut.pay_left, dut.ipg_cnt);')
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('ok')
