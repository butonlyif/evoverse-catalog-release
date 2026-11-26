#!/usr/bin/env python3
"""CCM 近似标定：无色卡，用场景已知色物体粗解 3x3 色彩校正矩阵。

背景：CCM 正式标定需要 24 色卡（ColorChecker）；本脚本用场景里的白色 +
高饱和红/绿/蓝物体做 4 点最小二乘近似——准度介于经验矩阵与色卡标定之间，
适合没有色卡时的快速起步。

近似假设：目标是理想 sRGB 原色（白=(Y,Y,Y)，红=(Y,0,0)，绿=(0,Y,0)，
蓝=(0,0,Y)，Y=Rec.709 亮度）。真实物体反射光谱非理想（红物也会反一点绿），
解出的矩阵会略过饱和——属近似法固有偏差，矩阵对角线往 1 收一点即可回调。

用法：
  1. 相机对准含 白色（白灯/白纸）+ 红 + 绿 + 蓝 四种物体的场景，
     四个物体分散摆放、互不遮挡、避免反光死白
  2. uv run ccm_calib.py            （抓 20 帧平均后弹出窗口）
  3. 在窗口里依次点击 白 -> 红 -> 绿 -> 蓝 的物体中心（各点一下）
  4. 终端打印 CCM 矩阵、验证表和可直接复制的 --ccm 命令行
  5. 把 --ccm 参数行加进 raw10_viewer.py 启动命令

标定状态与 viewer 一致：WB 增益（默认同 viewer 定标值）之后、gamma 之前
的线性域。WB 变了（换光源）需重标。
"""

import argparse
import queue
import socket

import cv2
import numpy as np

from raw10 import FrameReassembler, frame_to_image, cfa_channel_map


def grab_avg(args):
    """收包线程抓 N 帧取平均（时域降噪，统计量更稳）"""
    reasm = FrameReassembler()
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 << 20)
    s.bind((args.bind, args.port))
    s.settimeout(2.0)
    q = queue.Queue(maxsize=8)

    def rx():
        while True:
            try:
                pkt, _ = s.recvfrom(2048)
            except socket.timeout:
                continue
            _, _, done, f = reasm.feed(pkt)
            if done:
                try:
                    q.put_nowait(frame_to_image(f['buf']))
                except queue.Full:
                    pass

    import threading
    threading.Thread(target=rx, daemon=True).start()

    frames = []
    print(f'capturing {args.frames} frames ...')
    while len(frames) < args.frames:
        frames.append(q.get(timeout=10.0))
        if len(frames) % 5 == 0:
            print(f'  {len(frames)}/{args.frames}')
    return np.mean(np.stack(frames), axis=0).astype(np.float32)


def apply_wb_float(bayer, gains, cfa):
    """线性域四通道增益（与 viewer apply_wb 同映射，float 版支持帧平均）"""
    chn = cfa_channel_map(cfa)
    out = bayer.astype(np.float32)
    for rc, ch in chn.items():
        r, c = rc
        out[r::2, c::2] *= gains[ch]
    return np.clip(out, 0, 1023)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--bind', default='10.0.0.3')
    ap.add_argument('--port', type=int, default=10005)
    ap.add_argument('--cfa', default='RGGB', choices=('RGGB', 'BGGB', 'GRBG', 'GBRG'))
    ap.add_argument('--wb', default='1.56,1.0,1.0,1.59',
                    help='R,Gr,Gb,B 增益（须与 viewer 使用值一致）')
    ap.add_argument('--frames', type=int, default=20, help='平均帧数')
    args = ap.parse_args()

    gains = dict(zip(('R', 'Gr', 'Gb', 'B'),
                     (float(x) for x in args.wb.split(','))))
    bayer = grab_avg(args)
    bayer_code = {'RGGB': cv2.COLOR_BayerRG2RGB_EA, 'BGGB': cv2.COLOR_BayerBG2RGB_EA,
                  'GRBG': cv2.COLOR_BayerGR2RGB_EA, 'GBRG': cv2.COLOR_BayerGB2RGB_EA}
    rgb = cv2.cvtColor(apply_wb_float(bayer, gains, args.cfa).astype(np.uint16),
                       bayer_code[args.cfa]).astype(np.float32)

    # 显示用 gamma（仅可视化，计算全在线性域）
    GAMMA = np.arange(1024, dtype=np.float32)
    GAMMA = np.uint8(np.clip(((GAMMA / 1023.0) ** (1 / 2.2)) * 255 + 0.5, 0, 255))
    disp = GAMMA[np.clip(rgb, 0, 1023).astype(np.uint16)]

    names = ('white', 'RED', 'GREEN', 'BLUE')
    clicks = []

    def on_mouse(event, x, y, flags, param):
        if event == cv2.EVENT_LBUTTONDOWN and len(clicks) < 4:
            clicks.append((x, y))
            cv2.circle(disp, (x, y), 12, (0, 255, 255), 2)
            cv2.putText(disp, f'{len(clicks)}:{names[len(clicks) - 1]}',
                        (x + 16, y + 6), cv2.FONT_HERSHEY_SIMPLEX, 0.7,
                        (0, 255, 255), 2)
            print(f'  #{len(clicks)} {names[len(clicks) - 1]} @ ({x},{y})')

    print('click in order: white -> RED -> GREEN -> BLUE')
    cv2.namedWindow('ccm_calib', cv2.WINDOW_AUTOSIZE)
    cv2.setMouseCallback('ccm_calib', on_mouse)
    while len(clicks) < 4:
        cv2.imshow('ccm_calib', disp)
        if cv2.waitKey(30) & 0xFF in (ord('q'), 27):
            print('cancelled')
            return
    cv2.destroyAllWindows()

    # 9x9 patch 中位取样（抗噪 + 避免点在边缘上）
    meas = np.array([np.median(rgb[max(0, y - 4):y + 5, max(0, x - 4):x + 5]
                               .reshape(-1, 3), axis=0) for x, y in clicks])
    lum = meas @ np.array([0.2126, 0.7152, 0.0722])

    # 齐次零空间法（比 4 点 lstsq 更干净）：R_out 行须在绿、蓝目标上输出为 0
    # （2 个齐次约束，3 自由度 → 1 维零空间），SVD 最小奇异向量即解；行尺度
    # 用白点定标（白点输出 = 白点亮度，WB 归一后行和自动 =1 保白点）。
    # 注意不能用"目标=实测亮度纯原色 (Y,0,0)"做 lstsq——纯原色的 Rec.709
    # 亮度 = 0.2126Y ≠ Y，目标不自洽，lstsq 会折中出压暗矩阵（实测教训）。
    M = np.zeros((3, 3), np.float32)
    for row, own in ((0, 1), (1, 2), (2, 3)):       # R 行杀绿蓝 / G 行杀红蓝 / B 行杀红绿
        A = np.stack([meas[i] for i in (1, 2, 3) if i != own])
        _, _, vt = np.linalg.svd(A)
        u = vt[-1].astype(np.float32)
        if u @ meas[own] < 0:                       # 定向：本原色输出为正
            u = -u
        M[row] = u
    M *= (lum[0] / (M @ meas[0]))[:, None]          # 白点输出 = 白点亮度

    print('\nCCM (rows: R_out/G_out/B_out, input R/G/B):')
    for row in M:
        print('  ' + '  '.join(f'{v:+.3f}' for v in row))
    fixed = np.clip(meas @ M.T, 0, 1023)
    print('\nverify (measured -> corrected, chroma target):')
    labels = ('white', 'red', 'green', 'blue')
    for i, lb in enumerate(labels):
        tgt_show = np.full(3, lum[i]) if i == 0 else \
            [lum[i] if j == i - 1 else 0 for j in range(3)]
        print(f'  {lb:5s} {np.round(meas[i]).astype(int)} -> '
              f'{np.round(fixed[i]).astype(int)}   pure-primary w/ same luma '
              f'{np.round(tgt_show).astype(int)}')
    cmd = ','.join(f'{v:+.3f}' for v in M.ravel())
    print(f'\nraw10_viewer.py --ccm {cmd}')


if __name__ == '__main__':
    main()
