#!/usr/bin/env python3
"""无头校验：RAW10 1080p@30fps UDP 流统计（G7 验收，对应 test_udp_rx.ps1 的 RAW10 版）

按 udp_plan.md §3.4 验收标准判定：
  1. 帧号连续，丢帧数 = 0
  2. 每包元数据偏移严格递增（重复/乱序包 = 0）
  3. 抽样帧全像素比对（图案公式 pixel = (row*1920+col) & 0x3FF）
  4. 实测帧率 30.00 ± 0.1 fps
  5. 载荷带宽 622 ± 5 Mbps

用法：
  uv run test_raw10_rx.py --seconds 10
  uv run test_raw10_rx.py --seconds 10 --bind 10.0.0.2 --port 10005 --verify-frames 5
"""

import argparse
import socket
import sys
import time

import numpy as np

from raw10 import (FrameReassembler, PAYLOAD_FULL, PAYLOAD_LAST,
                   BYTES_PER_FRAME, FRAME_PERIOD_MS, expected_image,
                   frame_to_image)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--bind', default='10.0.0.3', help='PC NIC IP（板子目的地址）')
    ap.add_argument('--port', type=int, default=10005)
    ap.add_argument('--seconds', type=float, default=10.0, help='采集时长')
    ap.add_argument('--verify-frames', type=int, default=5, help='全像素比对抽样帧数')
    ap.add_argument('--pat-mode', type=int, default=0, choices=range(4),
                    help='板子当前图案模式（0彩条 1横向灰度 2垂直灰度 3棋盘）')
    args = ap.parse_args()

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 << 20)  # 防突发丢包
    s.bind((args.bind, args.port))
    s.settimeout(1.0)
    print(f'listening on {args.bind}:{args.port}, collecting {args.seconds}s ...')

    reasm = FrameReassembler()
    exp = expected_image(args.pat_mode)
    complete = {}          # fn -> complete time
    verify = {}            # fn -> buf（抽样比对）
    npkt = 0
    nlast = 0
    lost = 0
    last_fn = None
    t0 = None
    t_end = time.time() + args.seconds

    while time.time() < t_end:
        try:
            pkt, _ = s.recvfrom(2048)
        except socket.timeout:
            if t0 is not None:
                print('  (1s no packet ...)')
            continue
        if t0 is None:
            t0 = time.time()
        npkt += 1
        if len(pkt) == PAYLOAD_LAST:
            nlast += 1
        fn, idx, done, f = reasm.feed(pkt)
        if last_fn is not None and fn > last_fn:
            lost += fn - last_fn - 1
        last_fn = fn
        if done and fn not in complete:
            complete[fn] = time.time()
            if len(verify) < args.verify_frames:
                verify[fn] = f['buf'].copy()
    t1 = time.time()

    # ---------------- 统计报告 ----------------
    if not complete:
        print(f'\nRESULT: FAIL — 0 complete frames ({npkt} pkts raw)')
        sys.exit(1)

    dur = (t1 - t0) if t0 else 1e-9
    fn_lo, fn_hi = min(complete), max(complete)
    span = fn_hi - fn_lo + 1                       # 完整帧号跨度
    complete_cnt = len(complete)
    # 帧率/带宽用首末帧完成时刻差（帧 i 完成到帧 i+span-1 完成间隔 = (span-1)×帧周期），
    # 消除采集窗口起止边缘偏差
    meas_dur = complete[fn_hi] - complete[fn_lo]
    fps = (span - 1) / meas_dur if meas_dur > 0 else 0.0
    data_mbps = span * BYTES_PER_FRAME * 8 / (meas_dur + FRAME_PERIOD_MS / 1000.0) / 1e6

    print(f'\n===== RAW10 RX 统计（{dur:.2f}s 窗口） =====')
    print(f'  UDP 包数        : {npkt}  (末包 {nlast})')
    print(f'  完整帧数        : {complete_cnt}  (帧号 {fn_lo}..{fn_hi})')
    print(f'  丢帧数          : {lost}  (帧号跳变统计)')
    print(f'  重复/乱序包     : {reasm.n_dups}')
    print(f'  帧率            : {fps:.2f} fps   (要求 30.00 ± 0.1)')
    print(f'  载荷带宽        : {data_mbps:.1f} Mbps (要求 622 ± 5)')

    # 全像素比对
    print(f'  像素比对        : ', end='')
    ok_pix = True
    for fn in sorted(verify):
        img = frame_to_image(verify[fn])
        if np.array_equal(img, exp):
            print(f'frame {fn} OK  ', end='')
        else:
            ok_pix = False
            d = np.argwhere(img != exp)
            print(f'\n    frame {fn} MISMATCH: {len(d)} px, first at '
                  f'(row={d[0][0]}, col={d[0][1]}) got={img[tuple(d[0])]} '
                  f'exp={exp[tuple(d[0])]}', end='')
    print()

    checks = [
        ('丢帧 = 0',            lost == 0),
        ('无重复/乱序包',        reasm.n_dups == 0),
        ('帧率 30.00±0.1',      29.9 <= fps <= 30.1),
        ('带宽 622±5 Mbps',     617.0 <= data_mbps <= 627.0),
        ('像素比对 PASS',        ok_pix),
    ]
    all_ok = all(ok for _, ok in checks)
    print('  分项判定:')
    for name, ok in checks:
        print(f'    [{"PASS" if ok else "FAIL"}] {name}')
    print(f'\nRESULT: {"PASS — G7 验收达成" if all_ok else "FAIL"}')
    sys.exit(0 if all_ok else 1)


if __name__ == '__main__':
    main()
