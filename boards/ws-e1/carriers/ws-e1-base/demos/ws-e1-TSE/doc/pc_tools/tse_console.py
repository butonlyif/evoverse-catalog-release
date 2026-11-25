#!/usr/bin/env python3
"""tse_console.py - 一体化控制台：左侧模式控制按钮 + 右侧 RAW10 实时视频（单 Tk 窗口）

= mode_gui.py（模式控制）+ raw10_viewer.py（视频显示）合体。
  两个独立工具保留可用；日常用本工具即可。

视频处理链与 raw10_viewer.py 全量对齐（直接复用其函数）：TNR → 列 FPN 校正
→ 自动白平衡（场景自适应路由）→ WB → EA demosaic → CCM → gamma/ev LUT →
饱和度 → 锐化。默认参数与 viewer 相同（--wb 1.56,1.0,1.0,1.59、gamma 2.2、
EA、列校正开）。验证 RTL 图案时加 --decol 0 --autowb 关闭（图案自带精确
色彩，校正会破坏真值）。

布局:
    左列: [流模式] t/v/c/n/s  [RAW10 图案] 0-3  [轮播][截屏]  发送日志
    右列: 视频画布（cv2 处理 -> Tk PhotoImage/PPM 零依赖渲染）
          下方状态栏: fps / 帧号 / 丢帧 / 带宽 / 图案 / AWB

用法:
    uv run tse_console.py                       # 默认: 视频收 10.0.0.3:10005，控板 10.0.0.8
    uv run tse_console.py --autowb              # 自动白平衡（场景自适应）
    uv run tse_console.py --ev 0.5 --sat 1.3    # 提亮 + 提饱和
    uv run tse_console.py --cfa BGGB --scale 0.45
"""
import argparse
import queue
import socket
import threading
import time
import tkinter as tk
from tkinter import messagebox

import cv2
import numpy as np

from raw10 import FrameReassembler, apply_wb, frame_to_image, PAT_NAMES
from raw10_viewer import (CV_BAYER, CV_BAYER_EA, auto_gains, decol_columns,
                          make_tnr, parse_gains)

PAT_CTRL_PORT = 10006


class Console:
    def __init__(self, root: tk.Tk, args):
        self.root = root
        self.args = args
        self.stop = threading.Event()
        self.q = queue.Queue(maxsize=2)
        self.raw_q = queue.Queue(maxsize=2)   #重组帧 -> 处理线程（忙时丢帧不丢包）
        self.stats = {'frames': 0, 'lost': 0, 'mbps': 0.0, 'fps': 0.0,
                      'last_fn': -1, 'resid': 0, 'dups': 0, 'npkt': 0,
                      'drop': 0}
        self.pat_mode = 0
        self.carousel = False
        self.last_switch = time.time()
        self.shot_idx = 0
        self.last_disp = None          #最近一帧（RGB uint8），供截屏
        self.imgtk = None              #防 PhotoImage 被 GC
        self.awb_src = '-'             #当前 AWB 估计器（状态栏显示）
        self._last_frames = 0          #fps 500ms 窗口基准

        # ---- 视频处理链预置（与 raw10_viewer 同构）----
        self.demosaic = (CV_BAYER_EA if args.demosaic == 'ea' else CV_BAYER)[args.cfa]
        GAMMA = np.arange(1024, dtype=np.float32)
        if args.ev:
            GAMMA = np.minimum(GAMMA * (2.0 ** args.ev), 1023)
        self.gamma_lut = np.uint8(np.clip(
            ((GAMMA / 1023.0) ** (1.0 / args.gamma)) * 255.0 + 0.5, 0, 255))
        self.tnr = make_tnr(args.tnr) if args.tnr > 0 else None
        self.ccm_m = None
        if args.ccm == 'imx415':
            self.ccm_m = np.array([[1.80, -0.60, -0.20],
                                   [-0.20, 1.35, -0.15],
                                   [-0.10, -0.35, 1.45]], np.float32)
        elif args.ccm:
            self.ccm_m = np.array(
                [float(x) for x in args.ccm.split(',')], np.float32).reshape(3, 3)
        self.gains = parse_gains(args.wb)

        self.ctrl = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            self.ctrl.bind((args.bind, 0))
        except OSError as e:
            messagebox.showerror('绑定失败',
                f'bind {args.bind} 失败:\n{e}\n板子所接网卡不在线，'
                f'静默回退会把命令发到别的网卡。')
            root.destroy()
            return

        self.rx_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.rx_sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 << 20)
        try:
            self.rx_sock.bind((args.bind, args.port))
        except OSError as e:
            messagebox.showerror('视频端口绑定失败',
                f'bind {args.bind}:{args.port} 失败:\n{e}\n'
                f'（可能被另一个 viewer 占用）')
            root.destroy()
            return

        root.title(f'EvoVerse TSE 控制台   板 {args.board}:{PAT_CTRL_PORT}   '
                   f'视频 {args.bind}:{args.port}')
        root.protocol('WM_DELETE_WINDOW', self.on_close)

        # ---------------- 左列：控制面板 ----------------
        left = tk.Frame(root)
        left.pack(side='left', fill='y', padx=8, pady=6)

        box1 = tk.LabelFrame(left, text='流模式（单击即发送）', padx=6, pady=4)
        box1.pack(fill='x', pady=(0, 6))
        mode_btns = [('t  线速流', 't', 'G6 递增线速流 ~951 Mbps（debug）'),
                     ('v  图案流', 'v', 'RAW10 1080p@30fps 图案（200M 源，G11n16）'),
                     ('c  相机', 'c', 'IMX415 相机 RAW10（同 FIFO 链路）'),
                     ('n  网络服务', 'n', '停流 → ping/echo'),
                     ('s  恢复流', 's', '恢复上次流')]
        for i, (label, cmd, tip) in enumerate(mode_btns):
            tk.Button(box1, text=label, width=10, height=1,
                      font=('Microsoft YaHei UI', 10, 'bold'),
                      command=lambda c=cmd, t=tip: self.send_cmd(c, t)
                      ).grid(row=i // 2, column=i % 2, padx=4, pady=3, sticky='ew')

        box2 = tk.LabelFrame(left, text="RAW10 图案（'v' 图案流下即时切换）", padx=6, pady=4)
        box2.pack(fill='x', pady=(0, 6))
        for i in range(4):
            tk.Button(box2, text=f'{i} {PAT_NAMES[i]}', width=10,
                      command=lambda m=i: self.send_pat(m)
                      ).grid(row=i // 2, column=i % 2, padx=4, pady=3, sticky='ew')

        self.var_carousel = tk.BooleanVar(value=False)
        tk.Checkbutton(box2, text='轮播（每 5s 切下一个图案）',
                       variable=self.var_carousel,
                       command=self.on_carousel).grid(row=2, column=0,
                       columnspan=2, sticky='w', padx=4, pady=2)
        tk.Button(box2, text='截屏保存 PNG', width=10,
                  command=self.on_shot).grid(row=3, column=0, padx=4, pady=3,
                  sticky='ew')

        box3 = tk.LabelFrame(left, text='发送日志', padx=6, pady=4)
        box3.pack(fill='both', expand=True)
        self.log = tk.Text(box3, width=34, height=10, font=('Consolas', 8),
                           state='disabled', bg='#f7f7f7')
        self.log.pack(fill='both', expand=True)
        self.log_write(f'就绪。控制 -> {args.board}:{PAT_CTRL_PORT}，'
                       f'命令即发即忘，以画面/流量为准。')

        # ---------------- 右列：视频 ----------------
        right = tk.Frame(root)
        right.pack(side='left', fill='both', expand=True, padx=8, pady=6)
        dw, dh = int(1920 * args.scale), int(1080 * args.scale)
        self.canvas = tk.Canvas(right, width=dw, height=dh, bg='#111',
                                highlightthickness=0)
        self.canvas.pack()
        self.video_win = self.canvas.create_image(0, 0, anchor='nw')
        self.status = tk.Label(right, text='等待视频流…（点左侧 v 进入视频流）',
                               font=('Consolas', 10), anchor='w', fg='#0a0')
        self.status.pack(fill='x', pady=(4, 0))

        threading.Thread(target=self.rx_loop, daemon=True).start()
        threading.Thread(target=self.process_loop, daemon=True).start()
        self.root.after(30, self.on_frame)
        self.root.after(500, self.on_tick)

    # ---------------- 控制 ----------------
    def log_write(self, msg):
        self.log.configure(state='normal')
        self.log.insert('end', f"[{time.strftime('%H:%M:%S')}] {msg}\n")
        self.log.see('end')
        self.log.configure(state='disabled')

    def send_cmd(self, cmd, tip):
        try:
            self.ctrl.sendto(cmd.encode(), (self.args.board, PAT_CTRL_PORT))
            self.log_write(f"发送 {cmd!r} ({tip})")
        except OSError as e:
            self.log_write(f'发送 {cmd!r} 失败: {e}')

    def send_pat(self, mode):
        self.send_cmd(str(mode), f'图案 {PAT_NAMES[mode]}')
        self.pat_mode = mode
        self.last_switch = time.time()

    def on_carousel(self):
        self.carousel = self.var_carousel.get()
        self.last_switch = time.time()
        self.log_write(f'轮播 {"开 (5s)" if self.carousel else "关"}')

    def on_shot(self):
        if self.last_disp is None:
            self.log_write('截屏失败：还没有完整帧')
            return
        fn = f'frame_{self.shot_idx:06d}.png'
        cv2.imwrite(fn, cv2.cvtColor(self.last_disp, cv2.COLOR_RGB2BGR))
        self.log_write(f'截屏 -> {fn}')
        self.shot_idx += 1

    # ---------------- 视频 ----------------
    def rx_loop(self):
        """收包线程：只收包+重组（必须快！处理放 process_loop）。

        G11n18 教训：处理链（decol/AWB/demosaic ~25-35ms/帧）放进收包线程后
        跟不上 53.7k pps，内核 socket 缓冲溢出 → 大量丢包 + 帧率崩。收包线程
        唯一职责是尽快排空 socket，重组完的帧经 raw_q 交给处理线程，忙时丢
        整帧（丢帧可见但不丢包，丢包才致命——半帧数据全废）。
        """
        reasm = FrameReassembler()
        last_fn, t_win, data_win = None, time.time(), 0
        while not self.stop.is_set():
            try:
                pkt, _ = self.rx_sock.recvfrom(2048)
            except socket.timeout:
                continue
            except OSError:
                break
            fn, _, done, f = reasm.feed(pkt)
            data_win += len(pkt)
            if last_fn is not None and fn > last_fn:
                self.stats['lost'] += fn - last_fn - 1
            last_fn = fn
            self.stats['npkt'] += 1
            if done:
                try:
                    self.raw_q.put_nowait(f['buf'])
                except queue.Full:
                    try:
                        self.raw_q.get_nowait()              #丢旧帧防延迟
                        self.stats['drop'] += 1
                        self.raw_q.put_nowait(f['buf'])
                    except (queue.Empty, queue.Full):
                        self.stats['drop'] += 1
            self.stats['resid'] = len(reasm.frames)
            self.stats['dups'] = reasm.n_dups
            now = time.time()
            if now - t_win >= 1.0:
                self.stats['mbps'] = data_win * 8 / (now - t_win) / 1e6
                t_win = now
                data_win = 0

    def process_loop(self):
        """处理线程：完整处理链（对齐 raw10_viewer）-> PPM 入队（Tk 渲染）"""
        args = self.args
        dw, dh = int(1920 * args.scale), int(1080 * args.scale)
        while not self.stop.is_set():
            try:
                buf = self.raw_q.get(timeout=0.5)
            except queue.Empty:
                continue
            img = frame_to_image(buf)
            if self.tnr is not None:                         #时域降噪（Bayer 域）
                img = self.tnr(img)
            if args.decol:                                   #列 FPN 校正
                img = decol_columns(img)
            if args.autowb:                                  #场景自适应 AWB
                self.gains, self.awb_src = auto_gains(
                    img, self.gains, args.cfa, mode=args.awb_mode)
            img = apply_wb(img, self.gains, args.cfa)
            rgb = cv2.cvtColor(img, self.demosaic)           #16U Bayer -> RGB
            if self.ccm_m is not None:                       #CCM（线性域）
                rgb = cv2.transform(rgb, self.ccm_m)
                np.minimum(rgb, 1023, out=rgb)               #uint16 饱和 65535
                                                             #LUT 只收 0..1023
            # 先缩放再 LUT/饱和/锐化：显示侧三步像素量随 scale 砍 ~8 倍
            # （G11n18：全分辨率做 LUT+HSV+unsharp 是处理线程 12fps 的主因）
            if args.scale != 1.0:
                rgb = cv2.resize(rgb, (dw, dh),
                                 interpolation=cv2.INTER_AREA)
            disp = self.gamma_lut[rgb]                       #10bit 线性 -> 8bit gamma
            # cv2 的 BayerRG2RGB 常量名不符实：对真 RGGB 输入实际产出 BGR 序
            # 数组（R 平面落到 ch2，决定性实验 2026-11-09）。viewer 直喂
            # imshow（按 BGR 解释）负负得正；Tk PhotoImage PPM 按 RGB 解释
            # 字节 → 必须在此显式转回真 RGB，否则红蓝互换（蓝变黄根因）
            disp = cv2.cvtColor(disp, cv2.COLOR_BGR2RGB)
            if args.sat != 1.0:                              #饱和度（显示域）
                hsv = cv2.cvtColor(disp, cv2.COLOR_RGB2HSV)
                hsv[..., 1] = np.clip(
                    hsv[..., 1].astype(np.uint16) * args.sat, 0, 255)
                disp = cv2.cvtColor(hsv, cv2.COLOR_HSV2RGB)
            if args.sharp > 0.0:                             #unsharp 锐化
                blur = cv2.GaussianBlur(disp, (0, 0), 2.0)
                disp = np.clip(disp.astype(np.int16)
                               + ((disp.astype(np.int16) - blur)
                                  * args.sharp), 0, 255).astype(np.uint8)
            self.last_disp = disp
            ppm = b'P6 %d %d 255\n' % (dw, dh) + disp.tobytes()
            try:
                self.q.put_nowait(ppm)
            except queue.Full:
                try:
                    self.q.get_nowait()                      #丢旧帧防延迟
                    self.stats['drop'] += 1
                    self.q.put_nowait(ppm)
                except (queue.Empty, queue.Full):
                    self.stats['drop'] += 1
            self.stats['frames'] += 1

    def on_frame(self):
        """Tk 主循环：取队列最新帧刷新画布（30ms 节拍）"""
        ppm = None
        try:
            while True:
                ppm = self.q.get_nowait()                     #只留最新
        except queue.Empty:
            pass
        if ppm is not None:
            self.imgtk = tk.PhotoImage(data=ppm)
            self.canvas.itemconfig(self.video_win, image=self.imgtk)
        self.root.after(30, self.on_frame)

    def on_tick(self):
        """500ms 节拍：轮播计时 + 状态栏刷新"""
        if self.carousel and time.time() - self.last_switch >= 5.0:
            self.send_pat((self.pat_mode + 1) % 4)
        s = self.stats
        s['fps'] = (s['frames'] - self._last_frames) * 2.0   #500ms 窗口折算
        self._last_frames = s['frames']
        if s['npkt'] == 0:
            self.status.configure(text='等待视频流…（点左侧 v 进入视频流）', fg='#666')
        else:
            awb = (f'   awb[{self.awb_src}]' if self.args.autowb else '')
            self.status.configure(text=(
                f"fps {s['fps']:5.1f}   帧号 {s['last_fn']:8d}   "
                f"丢包 {s['lost']:5d}   丢弃 {s['drop']:5d}   "
                f"{s['mbps']:5.0f} Mbps   "
                f"图案[{self.pat_mode}] {PAT_NAMES[self.pat_mode]}"
                + awb + ('   轮播中' if self.carousel else '')), fg='#0a0')
        self.root.after(500, self.on_tick)

    def on_close(self):
        self.stop.set()
        self.root.destroy()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--bind', default='10.0.0.3')
    ap.add_argument('--port', type=int, default=10005)
    ap.add_argument('--board', default='10.0.0.8')
    ap.add_argument('--cfa', default='RGGB', choices=list(CV_BAYER),
                    help='拜耳相位（默认 RGGB=IMX415 原生，G11n17 RTL 组内反序'
                         '修复后；旧固件需 --cfa GRBG 代偿，看图案亦用 RGGB）')
    ap.add_argument('--wb', default='1.56,1.0,1.0,1.59',
                    help='R,Gr,Gb,B 增益（默认 RGGB 正序流灰世界定标；换光照'
                         '可用 --autowb）')
    ap.add_argument('--autowb', action='store_true',
                    help='自动白平衡：场景自适应算法路由（中性亮块白块法 / '
                         'Shades of Grey 回退）')
    ap.add_argument('--awb-mode', default='auto', choices=('auto', 'patch', 'shade'),
                    help='AWB 算法（--autowb 时生效）：auto=自动路由；'
                         'patch=锁定白块法；shade=锁定 Shades of Grey')
    ap.add_argument('--demosaic', default='ea', choices=('ea', 'linear'),
                    help='去马赛克算法（默认 ea=边缘感知）')
    ap.add_argument('--decol', type=int, default=0,
                    help='列 FPN 校正（默认 0 关闭，与 viewer 同步；'
                         '高增益暗场竖纹明显时用 --decol 1；看图案必须关闭）')
    ap.add_argument('--gamma', type=float, default=2.2,
                    help='显示 gamma 编码（默认 2.2=sRGB 标准）')
    ap.add_argument('--tnr', type=int, default=0,
                    help='时域降噪帧数 N（默认 0 关闭；运动自适应无拖影）')
    ap.add_argument('--tone', action='store_true',
                    help='局部色调映射（CLAHE 增益图法，暗部提亮不压高光）')
    ap.add_argument('--ev', type=float, default=0.0,
                    help='曝光补偿（数字增益 stop：+1=亮度x2，0.5=x1.4），'
                         '折进 gamma LUT 零开销')
    ap.add_argument('--sat', type=float, default=1.0,
                    help='饱和度系数（1.2~1.4 提浓艳，红显浅/橙时用）')
    ap.add_argument('--sharp', type=float, default=0.0,
                    help='锐化强度（unsharp mask，0 关闭；0.5~1.0 补边缘对比）')
    ap.add_argument('--ccm', default='',
                    help='3x3 色彩校正矩阵（9 数或 "imx415" 经验矩阵，未标定）')
    ap.add_argument('--scale', type=float, default=0.35, help='显示缩放')
    args = ap.parse_args()

    root = tk.Tk()
    Console(root, args)
    root.mainloop()


if __name__ == '__main__':
    main()
