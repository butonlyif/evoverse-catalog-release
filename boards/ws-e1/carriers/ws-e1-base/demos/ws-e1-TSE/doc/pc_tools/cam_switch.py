#!/usr/bin/env python
# cam_switch.py — G10 相机流切换器（UDP 10006 控制口）
# 用法：python cam_switch.py c     # 切相机 RAW10 直推
#       python cam_switch.py v/n/s/t / 0-3（同固件命令集）
import socket, sys

BOARD = ("10.0.0.8", 10006)
cmd = (sys.argv[1] if len(sys.argv) > 1 else "c").encode()
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(1.0)
# 连发 3 次提高可靠性（控制报文稀疏，固件 RX FIFO 偶发丢弃无害）
for _ in range(3):
    s.sendto(cmd, BOARD)
print(f"sent {cmd!r} x3 -> {BOARD[0]}:{BOARD[1]}")
s.close()
