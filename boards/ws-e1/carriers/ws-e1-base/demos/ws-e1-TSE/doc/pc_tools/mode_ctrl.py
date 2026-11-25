#!/usr/bin/env python3
"""mode_ctrl.py - 板子运行时模式控制（UDP 10006，2026-11-06 统一应用固件配套）

用法:
    uv run mode_ctrl.py <cmd> [board_ip]

命令:
    t        G6 递增线速流（1500B 帧，951 Mbps 压测模式）
    v        G7 RAW10 1080p@30fps 视频流（配合 raw10_viewer.py）
    n        停流 -> 网络服务（ping / UDP echo / UART ip-mac 配置全可用）
    s        恢复上次的流（v 或 t）
    0-3      RAW10 显示图案: 0=8色彩条 1=横向灰度 2=垂直灰度 3=棋盘

说明:
    - 命令均为即发即忘（板子不发应答），以 UART 打印与流量变化为准
    - 模式切换在包边界干净停流（RTL kill 位），不会产生拼接巨帧
    - RAW10 流中途切 't' 会截掉当前帧 -> viewer 丢帧计数 +1，属预期

例:
    uv run mode_ctrl.py v            # 切视频流（默认板 10.0.0.8）
    uv run mode_ctrl.py n 10.0.0.9   # 对改过 IP 的板子停流进网络服务
"""
import socket
import sys

DEFAULT_BOARD = "10.0.0.8"
CTRL_PORT = 10006
LOCAL_IP = "10.0.0.3"   # PC NIC（2026-11-06 由 .2 迁移）


def main():
    if len(sys.argv) < 2 or len(sys.argv[1]) != 1:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    board = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_BOARD

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.bind((LOCAL_IP, 0))   # 显式绑板子所接的网卡；失败立即报错
    except OSError as e:
        print(f"[FAIL] bind {LOCAL_IP} 失败: {e}\n"
              f"板子所接网卡（{LOCAL_IP}）不在线，静默回退会把命令发到别的网卡"
              f"（同一 L2 多网卡时系统路由可能选错出口）")
        sys.exit(1)
    s.sendto(cmd.encode(), (board, CTRL_PORT))
    s.close()
    print(f"sent {cmd!r} -> {board}:{CTRL_PORT}")


if __name__ == "__main__":
    main()
