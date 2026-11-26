#!/usr/bin/env python3
"""RAW10 UDP 流模拟器：无板开发/自测用

独立实现 udp_pat_gen_v2.v 的输出格式（打包代码与 raw10.py 解包互为交叉验证），
在 localhost 按帧周期发送合成 RAW10 视频流，供 test_raw10_rx.py / raw10_viewer.py
在硬件不可用时验证全链路（解包/重组/白平衡/demosaic/统计）。

用法：
  uv run sim_raw10_udp.py                    # 默认 127.0.0.1:10005，30fps 无限帧
  uv run sim_raw10_udp.py --frames 120       # 发 120 帧（4s）后退出
  uv run sim_raw10_udp.py --dst 10.0.0.2     # 发往真实 NIC（板级对照）
"""

import argparse
import socket
import struct
import sys
import time

import numpy as np

W, H = 1920, 1080
DATA_PER_PKT = 1450
LAST_DATA = 850
PKTS_PER_FRAME = 1788
META_LEN = 8
BYTES_PER_FRAME = W * H * 10 // 8        # 2,592,000


def build_frame_bytes(frame_num):
    """按图案公式生成一帧 RAW10 打包字节流（复用 raw10.expected_image，与 RTL 公式对齐）。

    图案：RGGB 8 彩条（每条 240px，0x3FF/0x000），2026-11-06 与 udp_pat_gen_v2.v
    cbar_quad 同步；打包 4px = 5B（MIPI 交错）。
    """
    from raw10 import expected_image
    px = expected_image().reshape(-1).astype(np.uint16)        # (2073600,)
    px = px.reshape(-1, 4)                                     # 每组 4 像素
    p1, p2, p3, p4 = px[:, 0], px[:, 1], px[:, 2], px[:, 3]
    # 标准 MIPI CSI-2 RAW10（2026-11-03 与 RTL 修正同步：无损 10bit×4px=5B）
    b0 = (p1 >> 2).astype(np.uint8)
    b1 = (((p1 & 0x3) << 6) | ((p2 >> 4) & 0x3F)).astype(np.uint8)
    b2 = (((p2 & 0xF) << 4) | ((p3 >> 6) & 0x0F)).astype(np.uint8)
    b3 = (((p3 & 0x3F) << 2) | ((p4 >> 8) & 0x03)).astype(np.uint8)
    b4 = (p4 & 0xFF).astype(np.uint8)
    packed = np.stack([b0, b1, b2, b3, b4], axis=1).reshape(-1)
    return packed.tobytes()                                    # 2,592,000 B


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--dst', default='127.0.0.1')
    ap.add_argument('--port', type=int, default=10005)
    ap.add_argument('--fps', type=float, default=30.0)
    ap.add_argument('--frames', type=int, default=0, help='0=无限')
    args = ap.parse_args()

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    dst = (args.dst, args.port)
    frame_period = 1.0 / args.fps

    print(f'sim -> {args.dst}:{args.port}  {args.fps} fps  '
          f'({PKTS_PER_FRAME} pkts/frame, {BYTES_PER_FRAME} B/frame)')
    fn = 0
    t_next = time.time()
    try:
        while args.frames == 0 or fn < args.frames:
            buf = build_frame_bytes(fn)
            hdr_pre = struct.Struct('>II')
            sent = 0
            for idx in range(PKTS_PER_FRAME):
                off = idx * DATA_PER_PKT
                n = LAST_DATA if idx == PKTS_PER_FRAME - 1 else DATA_PER_PKT
                meta = hdr_pre.pack(fn, off)
                s.sendto(meta + buf[off:off + n], dst)
                sent += 1
            # 帧内全速 burst（帧内 sleep 粒度低于 Windows 定时器分辨率会累积滞后），
            # 帧间精确对齐下一帧锚点
            print(f'\rframe {fn} sent ({sent} pkts)', end='', flush=True)
            fn += 1
            t_next += frame_period
            lag = t_next - time.time()
            if lag > 0:
                time.sleep(lag)
            else:
                t_next = time.time()   # 落后则重锚定
    except KeyboardInterrupt:
        pass
    print(f'\nsim done: {fn} frames')


if __name__ == '__main__':
    main()
