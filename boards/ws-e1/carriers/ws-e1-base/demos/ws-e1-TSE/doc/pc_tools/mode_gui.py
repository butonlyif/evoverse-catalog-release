#!/usr/bin/env python3
"""mode_gui.py - 板子运行时模式控制图形界面（UDP 10006，与 mode_ctrl.py 同协议）

单击按钮即发单字节命令（即发即忘，板子无应答），以板侧 UART 打印与流量变化为准。
命令语义见 mode_ctrl.py docstring；图形界面只是把命令变成按钮。

用法:
    uv run mode_gui.py             # 默认板 10.0.0.8，本地绑定 10.0.0.3
    uv run mode_gui.py 10.0.0.9    # 指定板 IP（如 UART 改过 IP 的板子）

界面分区:
    [流模式]  t=线速流 / v=RAW10 视频 / n=网络服务 / s=恢复上次流
    [RAW10 图案]  0=彩条 / 1=横灰阶 / 2=垂直灰阶 / 3=棋盘（仅 RAW10 流下可见）
    [日志]  每次发送的时间戳记录
"""
import socket
import sys
import time
import tkinter as tk
from tkinter import messagebox

CTRL_PORT = 10006
LOCAL_IP = "10.0.0.3"   # 板子所接网卡（2026-11-06 由 .2 迁移）

# (按钮文字, 命令字节, 提示说明)
MODE_BTNS = [
    ("t  线速流",  "t", "G6 递增线速流：1500B 帧 ~951 Mbps 压测"),
    ("v  视频流",  "v", "G7 RAW10 1080p@30fps（raw10_viewer.py 观看）"),
    ("n  网络服务", "n", "停流 → netsvc：ping / UDP echo / UART ip-mac"),
    ("s  恢复流",  "s", "恢复上次流类型（v 或 t）"),
]
PAT_BTNS = [
    ("0  彩条",    "0", "8 色竖彩条（默认）"),
    ("1  横灰阶",  "1", "横向灰度"),
    ("2  垂直灰阶", "2", "纵向灰度（G7 验收图案）"),
    ("3  棋盘",    "3", "棋盘格"),
]


class App:
    def __init__(self, root: tk.Tk, board_ip: str):
        self.root = root
        self.board_ip = board_ip
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            self.sock.bind((LOCAL_IP, 0))   # 显式绑板子所接网卡；失败即弹窗退出
        except OSError as e:
            messagebox.showerror(
                "绑定失败",
                f"bind {LOCAL_IP} 失败:\n{e}\n\n"
                f"板子所接网卡（{LOCAL_IP}）不在线。\n"
                f"静默回退会把命令发到别的网卡（同一 L2 多网卡时系统路由可能选错出口）。",
            )
            root.destroy()
            return

        root.title(f"EvoVerse TSE 模式控制   板 {board_ip}:{CTRL_PORT}   本机 {LOCAL_IP}")
        root.resizable(False, False)

        pad = dict(padx=10, pady=6)

        # ---- 流模式区 ----
        box1 = tk.LabelFrame(root, text="流模式（单击即发送）", padx=8, pady=8)
        box1.pack(fill="x", **pad)
        for col, (label, cmd, tip) in enumerate(MODE_BTNS):
            b = tk.Button(box1, text=label, width=12, height=2,
                          font=("Microsoft YaHei UI", 11, "bold"),
                          command=lambda c=cmd, t=tip: self.send(c, t))
            b.grid(row=0, column=col, padx=6, pady=2)
            tk.Label(box1, text=tip, font=("Microsoft YaHei UI", 8),
                     fg="#666", wraplength=130, justify="center"
                     ).grid(row=1, column=col, padx=6)

        # ---- RAW10 图案区 ----
        box2 = tk.LabelFrame(root, text="RAW10 显示图案（流模式内即时切换，仅视频流可见）",
                             padx=8, pady=8)
        box2.pack(fill="x", **pad)
        for col, (label, cmd, tip) in enumerate(PAT_BTNS):
            b = tk.Button(box2, text=label, width=12, height=2,
                          font=("Microsoft YaHei UI", 10),
                          command=lambda c=cmd, t="图案" + cmd: self.send(c, t))
            b.grid(row=0, column=col, padx=6, pady=2)
            tk.Label(box2, text=tip, font=("Microsoft YaHei UI", 8),
                     fg="#666", wraplength=130, justify="center"
                     ).grid(row=1, column=col, padx=6)

        # ---- 日志区 ----
        box3 = tk.LabelFrame(root, text="发送日志", padx=8, pady=8)
        box3.pack(fill="both", expand=True, **pad)
        self.log = tk.Text(box3, width=64, height=8, font=("Consolas", 9),
                           state="disabled", bg="#f7f7f7")
        self.log.pack(fill="both", expand=True)
        self.log_write(f"就绪。目标 {board_ip}:{CTRL_PORT}，命令即发即忘（板子无应答），"
                       f"以板侧 UART 与流量变化为准。")

    def log_write(self, msg: str):
        self.log.configure(state="normal")
        self.log.insert("end", f"[{time.strftime('%H:%M:%S')}] {msg}\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def send(self, cmd: str, tip: str):
        try:
            self.sock.sendto(cmd.encode(), (self.board_ip, CTRL_PORT))
            self.log_write(f"发送 {cmd!r} -> {self.board_ip}:{CTRL_PORT}   ({tip})")
        except OSError as e:
            self.log_write(f"发送 {cmd!r} 失败: {e}")


def main():
    board = sys.argv[1] if len(sys.argv) > 1 else "10.0.0.8"
    root = tk.Tk()
    App(root, board)
    root.mainloop()


if __name__ == "__main__":
    main()
