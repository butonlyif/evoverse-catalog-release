#!/usr/bin/env python3
"""RAW10 UDP 流采集器：收包 → 重组 → 完整帧落盘（G11n18）

用途：抓取板子相机/图案 RAW10 流存成单个 .bin 文件（默认 30 秒，~78MB），
供离线回放分析（RTL AWB 仿真 V5 场景的 RAW 回放源、PC 端算法离线调参）。

文件格式：
    16B 头 + N 帧连续拼接
    头 = b'R10C' | W u16le | H u16le | nframes u32le | reserved u32le *2
    每帧恰 BYTES_PER_FRAME(2,592,000)B，RAW10 打包（MIPI CSI-2 惯例 4px=5B）
    回放：跳过 16B 头后每 2,592,000B 用 raw10.frame_to_image 解一帧

只落账完整帧：FrameReassembler 魔数切帧，损坏/残帧丢弃并计数——
回放端拿到的是干净的整帧序列。Ctrl-C 提前停止同样保证头部帧数正确。

用法：
  uv run raw10_capture.py                        # 默认 30 秒
  uv run raw10_capture.py --seconds 60
  uv run raw10_capture.py --out D:\\data\\cap.bin
"""

import argparse
import socket
import struct
import time

from raw10 import BYTES_PER_FRAME, FrameReassembler, H, W

MAGIC = b'R10C'
HDR = struct.Struct('<4sHHII')            #magic, W, H, nframes, reserved = 16B


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--bind', default='10.0.0.3')
    ap.add_argument('--port', type=int, default=10005)
    ap.add_argument('--seconds', type=float, default=30.0,
                    help='采集时长（秒，默认 30；Ctrl-C 可提前停止）')
    ap.add_argument('--out', default='',
                    help='输出文件（默认 raw10_capture_时间戳.bin，存在当前目录）')
    args = ap.parse_args()

    out = args.out or time.strftime('raw10_capture_%Y%m%d_%H%M%S.bin')

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 << 20)
    s.bind((args.bind, args.port))
    s.settimeout(1.0)
    print(f'listening on {args.bind}:{args.port}  ->  {out}')
    print(f'capture {args.seconds}s  (~{args.seconds * 30 * BYTES_PER_FRAME / 1e6:.0f} MB)')

    reasm = FrameReassembler()
    n = 0                     # 已落盘完整帧
    n_partial = 0             # 丢弃的残帧
    n_lost = 0                # 帧号缺口（丢包估计）
    n_dups = 0
    last_fn = None
    t0 = time.time()
    t_last = t0
    f = open(out, 'wb')
    f.write(HDR.pack(MAGIC, W, H, 0, 0))       #头部占位，结束时回填帧数
    try:
        while time.time() - t0 < args.seconds:
            try:
                pkt, _ = s.recvfrom(2048)
            except socket.timeout:
                continue
            fn, _, done, frame = reasm.feed(pkt)
            if last_fn is not None and fn > last_fn:
                n_lost += fn - last_fn - 1
            last_fn = fn
            if done:
                buf = frame['buf']
                if len(buf) == BYTES_PER_FRAME:
                    f.write(buf.tobytes())
                    n += 1
                else:
                    n_partial += 1
            n_dups = reasm.n_dups
            now = time.time()
            if now - t_last >= 1.0:
                t_last = now
                print(f'  {now - t0:5.1f}/{args.seconds:.0f}s  '
                      f'frames {n}  partial {n_partial}  lost {n_lost}  dup {n_dups}')
    except KeyboardInterrupt:
        print('\nCtrl-C：提前停止')
    finally:
        f.seek(0)
        f.write(HDR.pack(MAGIC, W, H, n, 0))       #回填真实帧数
        f.close()
    dur = time.time() - t0
    print(f'saved {out}: {n} frames / {dur:.1f}s '
          f'({n * BYTES_PER_FRAME / 1e6:.1f} MB, '
          f'partial {n_partial}, lost {n_lost}, dup {n_dups})')


if __name__ == '__main__':
    main()
