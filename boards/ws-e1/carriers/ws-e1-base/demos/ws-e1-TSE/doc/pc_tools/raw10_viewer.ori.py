#!/usr/bin/env python3
"""实时查看器：UDP 收包 → 解包 → 重组 → 白平衡 → demosaic → 实时显示（G7）

OSD 叠加：fps / 帧号 / 丢帧数 / 带宽 / 残帧数。
菜单（键盘，窗口需焦点）：
  1 = 选择图案（进入子菜单后按 0..3：0 彩条 / 1 横向灰度 / 2 垂直灰度 / 3 棋盘）
  2 = 图案轮播开/关（每 5s 自动切下一个图案）
  3 = 截屏（frame_XXXXXX.png，s 键同效）
  4 = 退出（q / ESC 同效）
图案命令经 UDP 发往板子 PAT_CTRL_PORT(10006)，载荷 '0'..'3'。

用法：
  uv sync                                  # 首次安装依赖
  uv run raw10_viewer.py                   # 默认收 10.0.0.3:10005，控板 10.0.0.8
  uv run raw10_viewer.py --cfa BGGB --wb 2.1,1.0,1.0,1.6

相机模式白平衡：默认 --wb 即 GRBG 相位对白灯定标值；草地占满画面等单色
场景灰世界失效（--autowb 会整体带 complementary 色偏），此时用默认手动 WB。
CFA 相位定案（2026-11-08 板测，红物/草地/白灯三重验证）：本板相机流为
**GRBG**（G 在主对角线），默认 --cfa GRBG。重要教训——参考工程
ws-e1-cam-4K-1080-60fps-ref 标注"IMX415 标定 0(RGGB)"不可信：其
wb_design_spec 自载"200/235/180 板级实证画面发绿"（把 R/B 往下压的增益
只在相位错时才"看起来合理"，压过头=发绿），即其标定从未真正成功。
本板判据：RGGB 解码下白灯 R/G≈1.64、主对角线均值高 20%（典型索尼 G 最强）、
草地呈紫色（真 G 被解码进 R/B 平面）、红色物体显紫——GRBG 下全部恢复正常。
RTL 合成图案流仍是 RGGB（raw10_pat_src 行偶 {R,Gr}），看图案需 --cfa RGGB；
两流共用同一条 FIFO→UDP→viewer 链路，打包/解包顺序经彩条+expected_image
双重验证无误，故差异确属传感器流本身（非 RTL bug）。

相机显示动态范围（2026-11-08）：默认 --gamma 2.2（sRGB 标准显示编码）——
10bit 线性直显会暗部压黑（灯周围黑圈不可见）、高光饱和。gamma 编码暗部
大幅提亮、高光不变。传感器增益（RTL imx415_rom.sv 的 0x3090，值=dB×10/3，
最高 0xF0=72dB）负责把场景亮度抬到传感器量程，gamma 只管显示端。
"""

import argparse
import queue
import socket
import threading
import time

import cv2
import numpy as np

# Windows DPI 感知（必须在创建任何 cv2 窗口前）：HighGUI 默认不感知 DPI，
# 显示缩放≠100% 时 Windows 按位图拉伸窗口——草地等高频纹理出现摩尔竖纹+
# 锯齿（G11n17 板测实证：raw 数据 2~64px 全周期 FFT 列纹幅值≈0，纹在显示层）。
# 声明感知后 1:1 即真正物理像素。已处于感知状态时 shcore 调用会抛错，忽略。
import sys
if sys.platform == 'win32':
    import ctypes
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)   # per-monitor v2
    except Exception:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass

from raw10 import (FrameReassembler, apply_wb, cfa_channel_map, frame_to_image,
                   H, W, PAYLOAD_LAST, PAT_NAMES)

PAT_CTRL_PORT = 10006    #板子 TEST_MODE=0 控制服务端口

# OpenCV Bayer 常量与传感器排列的对应关系（2026-11-06 用 8 彩条实验实测确定）：
# 真实 RGGB 传感器（2x2 = [[R,G],[G,B]]）→ cv2.COLOR_BayerRG2RGB 颜色严格正确
# （白黄青绿品红红蓝黑逐条验证）；BayerBG2RGB 则黄↔青、红↔蓝互换，即此前
# "颜色不对"的根因。其余常量保留供非 RGGB 相机扩展。
CV_BAYER = {
    'RGGB': cv2.COLOR_BayerRG2RGB,
    'BGGB': cv2.COLOR_BayerBG2RGB,
    'GRBG': cv2.COLOR_BayerGR2RGB,
    'GBRG': cv2.COLOR_BayerGB2RGB,
}

# 边缘感知 demosaic（-EA 后缀，插值方向沿边缘梯度选择）：双线性在边缘会
# 产生拉链状锯齿/彩色镶边（Bayer 通道混叠），EA 显著消除，1080p 实测
# 2.9ms/帧开销可忽略。默认启用；--demosaic linear 可切回旧行为对比。
CV_BAYER_EA = {
    'RGGB': cv2.COLOR_BayerRG2RGB_EA,
    'BGGB': cv2.COLOR_BayerBG2RGB_EA,
    'GRBG': cv2.COLOR_BayerGR2RGB_EA,
    'GBRG': cv2.COLOR_BayerGB2RGB_EA,
}


def decol_columns(img, max_corr=12):
    """逐帧列 FPN 校正（去暗场竖纹，G11n17）。

    现象：高增益暗场下画面隐约竖线——传感器列读出电路的固定偏移（列 FPN，
    逐帧静态）被 gamma 暗部提亮显形；场景变亮后被信号淹没（板测两态对比实证）。
    方法：列剖面 = 行中位归零后的列中位（隔 8 行采样，静态偏移足够）；减去
    剖面的 >32px 慢变成分（那是镜头阴影/场景渐变，不是噪声）只留细梳，限幅
    ±max_corr 防止误吃真实竖直场景结构。暗场列纹被减除，亮场校正值自然趋零。
    行采样 ::8（G11n18：::4 时 np.median 双调用 23ms 成为处理线程产能瓶颈，
    列 FPN 逐帧静态、密度减半无影响，降到 ~12ms）。
    注意：图案流（RTL 合成）自带 2px CFA 结构，验证图案时加 --decol 0 关闭。
    """
    f = img.astype(np.float32)
    row_med = np.median(f[::8], axis=1, keepdims=True)
    prof = np.median(f[::8] - row_med, axis=0)
    fine = prof - cv2.blur(prof.reshape(1, -1), (1, 33)).ravel()
    corr = np.clip(fine, -max_corr, max_corr)
    return np.clip(f - corr[None, :], 0, 1023).astype(np.uint16)


def parse_gains(spec):
    """'R,Gr,Gb,B' -> dict；缺省全 1.0"""
    names = ('R', 'Gr', 'Gb', 'B')
    g = {n: 1.0 for n in names}
    if spec:
        for n, v in zip(names, spec.split(',')):
            g[n] = float(v)
    return g


def auto_gains(img, gains, cfa='RGGB', speed=0.1, mode='auto'):
    """自动白平衡 v3：场景自适应算法路由（白块法 / Shades of Grey）。

    白块法（中性亮块统计）：有白色物体/灯时是最准的估计——高光即光源色。
    判据：2x2 块亮度 85 分位以上、非饱和（<1010）、且按当前增益折算后块内
    四通道接近（|max-min|<=20% 亮度，筛掉亮草等彩色高亮——白块可能只占画面
    百分之几，纯亮度分位会被亮草淹没）。只在中性掩膜内统计四通道均值（每块
    恰含 R/Gr/Gb/B 各一个亚像素）；增益收敛中掩膜逐帧重估（EMA 互相带动收敛）。

    Shades of Grey 回退（单色主导场景救兵）：白块 <1% 时灰世界会把场景色当
    光源（草地满屏→整体带补色，v2 板测教训）。SoG 用 Minkowski p=6 范数估计
    每通道光源强度：(mean((I/1023)^6))^(1/6)*1023——p=1 退化为灰世界均值、
    p→∞ 退化为白块最大值，p=6 兼取两者，对单色场景显著更稳、零训练开销。
    隔行采样（[::2,::2]，~27万像素/子面）统计量足够且省一半幂运算。

    路由（mode='auto'）：中性块占比 >=1% → 白块法；不足或白块法失败 → SoG。
    mode='patch'/'shade' 手动锁定（patch 失败仍回落 SoG，好过不动作）。
    通道归属经 cfa_channel_map 与 apply_wb 同源；锚定最亮通道（只补短不压长，
    白灯不被拖灰）；EMA speed=0.1/帧（~0.3s 收敛）防闪烁，限幅 0.25..4.0。
    返回 (gains, source) 供 OSD 显示当前所用估计器。
    """
    p00 = img[0::2, 0::2]
    p01 = img[0::2, 1::2]
    p10 = img[1::2, 0::2]
    p11 = img[1::2, 1::2]
    sub = {(0, 0): p00, (0, 1): p01, (1, 0): p10, (1, 1): p11}
    chn = cfa_channel_map(cfa)

    if float(img.mean()) < 1.0:
        return gains, 'none'

    means = {}
    source = 'shade'
    # 白块法判据：亮区中的中性块（疑似白色物体/镜面高光）。
    # 块统计隔 4 抽 1（[::4,::4] 每子面 32k 块）：分位/掩膜/均值是纯统计量，
    # 抽样不影响结果（EMA 平滑残差）；全子面 float 运算 15-20ms 曾是
    # --autowb 掉帧主因（G11n18，console 实测帧率减半）
    if mode in ('auto', 'patch'):
        s00, s01, s10, s11 = (sub[rc][::4, ::4]
                              for rc in ((0, 0), (0, 1), (1, 0), (1, 1)))
        L = (s00.astype(np.uint32) + s01 + s10 + s11) >> 2
        v0 = s00.astype(np.float32) * gains[chn[(0, 0)]]
        v1 = s01.astype(np.float32) * gains[chn[(0, 1)]]
        v2 = s10.astype(np.float32) * gains[chn[(1, 0)]]
        v3 = s11.astype(np.float32) * gains[chn[(1, 1)]]
        vst = np.stack((v0, v1, v2, v3))
        vmax, vmin = vst.max(0), vst.min(0)
        Lw = vst.mean(0)
        mask = ((L >= np.percentile(L, 85)) & (L < 1010)
                & ((vmax - vmin) <= 0.20 * Lw))
        if int(mask.sum()) >= 0.01 * L.size:
            for rc, ch in chn.items():
                m = float(sub[rc][::4, ::4][mask].mean())
                if m > 1.0:
                    means[ch] = m
            if len(means) == 4:
                source = 'patch'
            else:
                means = {}
    # 回退/指定：Shades of Grey（p=6 Minkowski 范数，隔行采样）
    if not means:
        for rc, ch in chn.items():
            x = sub[rc][::2, ::2].astype(np.float32) / 1023.0
            m = float((x ** 6).mean()) ** (1.0 / 6.0) * 1023.0
            if m > 1.0:
                means[ch] = m
    if not means:
        return gains, 'none'
    # 锚定最亮通道：只补短不压长——若锚全图均值，草地主导场景会把白块/灯
    # 整体拖暗到场景均值（白灯变灰）；锚 max 则最亮通道增益恒 1，白块保持
    # 原有亮度，其余通道按响应差补齐
    target = max(means.values())
    for ch, m in means.items():
        g = min(4.0, max(0.25, target / m))
        gains[ch] = gains[ch] * (1.0 - speed) + g * speed
    return gains, source


def make_tnr(n, thresh=24):
    """时域降噪 TNR v2：运动自适应指数平均（v1 纯平均拖影明显，板测否决）。

    传感器读出/散粒噪声逐帧独立，N 帧平均 SNR +√N。运动自适应是关键：
    上一帧累积结果与本帧差 >thresh LSB 的像素判为运动，直接采用本帧值
    （不进平均）——静止区享受降噪，运动区无拖影。EMA（alpha=1/N）单
    float32 累加缓冲，无环形队列。返回值滞后一帧（上一帧累积结果），
    30fps 下 33ms 不可感知。
    """
    acc = None
    alpha = 1.0 / n

    def tnr(img):
        nonlocal acc
        if acc is None:
            acc = img.astype(np.float32)
            return img
        out = np.clip(acc + 0.5, 0, 1023).astype(np.uint16)
        moved = cv2.absdiff(img, out) > thresh
        acc += (img.astype(np.float32) - acc) * alpha
        acc[moved] = img[moved]
        return out

    return tnr


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--bind', default='10.0.0.3')
    ap.add_argument('--port', type=int, default=10005)
    ap.add_argument('--board', default='10.0.0.8', help='板子 IP（控制命令目标）')
    ap.add_argument('--cfa', default='RGGB', choices=list(CV_BAYER),
                    help='拜耳相位（默认 RGGB=IMX415 原生，G11n17 RTL 组内反序'
                         '修复后；旧固件需 --cfa GRBG 代偿，看图案亦用 RGGB）')
    ap.add_argument('--wb', default='1.56,1.0,1.0,1.59',
                    help='R,Gr,Gb,B 增益（默认 RGGB 正序流灰世界定标 '
                         'R/G=0.64 B/G=0.63；换光照可用 --autowb）')
    ap.add_argument('--autowb', action='store_true',
                    help='自动白平衡（相机模式用）：场景自适应算法路由——'
                         '中性亮块 >=1% 用白块法，不足切 Shades of Grey (p=6)；'
                         '单色主导场景不再整体偏色')
    ap.add_argument('--awb-mode', default='auto', choices=('auto', 'patch', 'shade'),
                    help='AWB 算法（--autowb 时生效）：auto=按场景自动路由；'
                         'patch=锁定白块法；shade=锁定 Shades of Grey')
    ap.add_argument('--demosaic', default='ea', choices=('ea', 'linear'),
                    help='去马赛克算法（默认 ea=边缘感知，消除边缘拉链锯齿/'
                         '彩色镶边；linear=旧双线性，更快但锯齿明显）')
    ap.add_argument('--decol', type=int, default=0,
                    help='列 FPN 校正（默认 0 关闭——decol 16.5ms 是帧预算大头，'
                         '低增益下竖纹不显；高增益暗场竖纹明显时用 --decol 1 开启；'
                         '验证 RTL 图案必须关闭）')
    ap.add_argument('--gamma', type=float, default=2.2,
                    help='显示 gamma 编码（默认 2.2=标准 sRGB；1=旧线性显示）。'
                         '暗部大幅提亮、高光不变——解决灯过曝+黑圈压黑的动态范围问题')
    ap.add_argument('--tnr', type=int, default=0,
                    help='时域降噪帧数 N（默认 0 关闭；如 --tnr 6 ≈ 6 帧平均，'
                         'SNR +√N。运动自适应：运动区直接采用新帧，无拖影）')
    ap.add_argument('--tone', action='store_true',
                    help='局部色调映射（CLAHE 增益图法）：暗部局部提亮、高光'
                         '不压、色彩不发灰——对标手机相机的阴影增强')
    ap.add_argument('--ev', type=float, default=0.0,
                    help='曝光补偿（数字增益，单位 stop：+1=亮度x2，0.5=x1.4）。'
                         '折进 gamma LUT 运行时零开销；高光提前饱和，WB 在增益'
                         '后统计仍正确。板端曝光/增益固定，这是 PC 侧整体提亮'
                         '的免费旋钮')
    ap.add_argument('--sat', type=float, default=1.0,
                    help='饱和度系数（默认 1.0 不动；1.2~1.4 提升色彩浓艳度。'
                         'gamma 显示编码会把暗色提亮显粉，红显浅/橙时用）')
    ap.add_argument('--sharp', type=float, default=0.0,
                    help='锐化强度（unsharp mask，0 关闭；0.5~1.0 补回被提亮/'
                         '噪声冲淡的边缘对比。过大振铃发硬，噪声也随之放大）')
    ap.add_argument('--ccm', default='',
                    help='3x3 色彩校正矩阵（9 个逗号分隔数，行序 R 行/G 行/B 行，'
                         '行和=1 保白点；或 "imx415" 用内置经验矩阵）。线性域'
                         '施加（WB 后 gamma 前），消通道串扰。经验值未经标定，'
                         '正式标定需 24 色卡')
    ap.add_argument('--scale', type=float, default=1.0,
                    help='显示缩放（默认 1.0=真实大小 1920x1080；小屏用 0.5）')
    args = ap.parse_args()

    gains = parse_gains(args.wb)
    awb_src = '-'
    demosaic_code = (CV_BAYER_EA if args.demosaic == 'ea' else CV_BAYER)[args.cfa]

    # CCM 3x3（线性域）：'imx415' 经验起始值（未标定，方向参考 Sony 传感器
    # 典型串扰特性——R 混 G 强、B 混 G 弱），或 9 个逗号分隔自定义值
    ccm_m = None
    if args.ccm == 'imx415':
        ccm_m = np.array([[1.80, -0.60, -0.20],
                          [-0.20, 1.35, -0.15],
                          [-0.10, -0.35, 1.45]], np.float32)
    elif args.ccm:
        v = [float(x) for x in args.ccm.split(',')]
        if len(v) != 9:
            ap.error('--ccm 需要 9 个逗号分隔数值或 "imx415"')
        ccm_m = np.array(v, np.float32).reshape(3, 3)

    # 显示 gamma 编码 LUT（10bit 线性 -> 8bit gamma）：人眼感知是伽马响应，
    # 线性直显会显得暗且暗部层次全压黑。GAMMA_LUT[rgb] 一次 numpy gather 完成。
    GAMMA_LUT = np.arange(1024, dtype=np.float32)
    if args.ev:
        GAMMA_LUT = np.minimum(GAMMA_LUT * (2.0 ** args.ev), 1023)
    GAMMA_LUT = np.uint8(np.clip(
        ((GAMMA_LUT / 1023.0) ** (1.0 / args.gamma)) * 255.0 + 0.5, 0, 255))

    # TNR 累加器（相机模式才有意义，图案流是合成数据无噪声）与 CLAHE 对象。
    # CLAHE 用较大 tile（16x16）+ clip 2.0：在低分辨率增益图上足够平滑
    tnr = make_tnr(args.tnr) if args.tnr > 0 else None
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(16, 16)) if args.tone else None

    q = queue.Queue(maxsize=3)          # 收包线程 -> 显示线程
    stats = {'frames': 0, 'lost': 0, 'mbps': 0.0, 'fps': 0.0, 'last_fn': -1,
             'resid': 0, 'dups': 0, 'npkt': 0, 'proc': 0, 'drop': 0}

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 << 20)
    s.bind((args.bind, args.port))
    s.settimeout(1.0)
    print(f'listening on {args.bind}:{args.port}  cfa={args.cfa} wb={gains}')
    print(f'pat control -> {args.board}:{PAT_CTRL_PORT}')
    print('menu: [1]select pattern(0-3)  [2]carousel 5s  [3]shot  [4]quit')

    stop = threading.Event()

    # ---- 图案控制（PC 菜单 -> 板子）----
    ctrl = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    pat_state = {'mode': 0, 'selecting': False, 'carousel': False,
                 'last_switch': time.time()}

    def send_pat(mode):
        """发图案命令：载荷首字节 '0'..'3' -> 板子写 CSR 0x208[5:4]"""
        try:
            ctrl.sendto(str(mode).encode(), (args.board, PAT_CTRL_PORT))
            print(f'PAT -> {mode} ({PAT_NAMES[mode]})')
        except OSError as e:
            print(f'PAT send failed: {e}')
        pat_state['mode'] = mode
        pat_state['last_switch'] = time.time()

    def rx_loop():
        reasm = FrameReassembler()
        last_fn = None
        t_win = time.time()
        pkt_win = 0
        data_win = 0
        while not stop.is_set():
            try:
                pkt, _ = s.recvfrom(2048)
            except socket.timeout:
                continue
            fn, _, done, f = reasm.feed(pkt)
            pkt_win += 1
            data_win += len(pkt)
            if last_fn is not None and fn > last_fn:
                stats['lost'] += fn - last_fn - 1
            last_fn = fn
            stats['last_fn'] = fn
            stats['npkt'] += 1
            if done:
                stats['frames'] += 1
                try:
                    q.put_nowait(frame_to_image(f['buf']))
                except queue.Full:
                    stats['drop'] += 1   # 处理落后丢整帧（丢帧不丢包）
            stats['resid'] = len(reasm.frames)
            stats['dups'] = reasm.n_dups
            now = time.time()
            if now - t_win >= 1.0:
                # fps 由显示循环按实际处理帧数计（G11n18：此前在 rx 侧计
                # "重组完成数"，处理慢只丢队列帧、OSD 看不出来——假 30fps）
                stats['mbps'] = data_win * 8 / (now - t_win) / 1e6
                t_win = now
                data_win = 0

    th = threading.Thread(target=rx_loop, daemon=True)
    th.start()

    win = 'raw10_viewer'
    cv2.namedWindow(win, cv2.WINDOW_AUTOSIZE)
    shot_idx = 0
    fps_win, fps_last = time.time(), 0      #fps 统计窗口（处理侧）

    while True:
        #轮播：每 5s 切下一个图案
        if pat_state['carousel'] and time.time() - pat_state['last_switch'] >= 5.0:
            send_pat((pat_state['mode'] + 1) % 4)
        try:
            img = q.get(timeout=1.0)
        except queue.Empty:
            if cv2.waitKey(30) & 0xFF in (ord('q'), 27, ord('4')):
                break
            continue

        if tnr is not None:
            img = tnr(img)
        if args.decol:
            img = decol_columns(img)
        if args.autowb:
            gains, awb_src = auto_gains(img, gains, args.cfa,
                                        mode=args.awb_mode)
        img = apply_wb(img, gains, args.cfa)
        rgb = cv2.cvtColor(img, demosaic_code)          # 16U Bayer -> 3ch 16U
        if ccm_m is not None:
            # 3x3 色彩校正矩阵（cv2.transform SIMD，~5ms）：行和=1 保白点，
            # 负系数消通道串扰。uint16 饱和上限是 65535 而 LUT 只收 0..1023，
            # 矩阵放大项会越界，必须 clip 回 10bit
            rgb = cv2.transform(rgb, ccm_m)
            np.minimum(rgb, 1023, out=rgb)
        if args.gamma > 0 and args.gamma != 1.0:
            disp = GAMMA_LUT[rgb]                       # 10bit 线性 -> gamma 编码 8bit
        else:
            disp = (rgb >> 2).astype(np.uint8)          # 10bit -> 8bit 线性（旧行为）
        if args.sharp > 0:
            # unsharp mask：提亮（--ev/gamma）放大噪声+压局部对比，观感像
            # 失焦；高斯模糊差值补回边缘对比（sigma 1.5 作用在细节尺度）
            blur = cv2.GaussianBlur(disp, (0, 0), 1.5)
            disp = cv2.addWeighted(disp, 1.0 + args.sharp, blur, -args.sharp, 0)
        if args.sat != 1.0:
            # 饱和度增强（HSV S 通道乘系数）：gamma 显示编码把暗值提亮，
            # 纯红变浅红/粉红（用户板测"红色不够红"），提 S 补回浓艳度
            hsv = cv2.cvtColor(disp, cv2.COLOR_RGB2HSV)
            hsv[..., 1] = np.minimum(hsv[..., 1] * args.sat, 255).astype(np.uint8)
            disp = cv2.cvtColor(hsv, cv2.COLOR_HSV2RGB)
        if clahe is not None:
            # 局部色调映射 v2（增益图法，v1 LAB 直方图均衡板测否决：块边界
            # 花斑、饱和度拉灰、噪声放大）。1/4 分辨率灰度上跑 CLAHE 得目标
            # 亮度 → 增益图 = eq/small，双线性上采样后 RGB 三通道同乘：
            # 增益图平滑无块边界；三通道同增益保持色度比例（不发灰）；
            # gain 下限 1.0 只提亮阴影、高光永不被压。上限 3.0 防暗点炸噪。
            L = cv2.cvtColor(disp, cv2.COLOR_RGB2GRAY)
            small = cv2.resize(L, (disp.shape[1] // 4, disp.shape[0] // 4),
                               interpolation=cv2.INTER_AREA).astype(np.float32)
            eq = clahe.apply(small.astype(np.uint8)).astype(np.float32)
            gain = eq / np.maximum(small, 1.0)
            np.clip(gain, 1.0, 3.0, out=gain)
            gain = cv2.resize(gain, (disp.shape[1], disp.shape[0]),
                              interpolation=cv2.INTER_LINEAR)
            disp = np.clip(disp * gain[..., None] + 0.5, 0, 255).astype(np.uint8)
        disp = cv2.resize(disp, None, fx=args.scale, fy=args.scale,
                          interpolation=cv2.INTER_AREA)

        hint = ('select pattern 0-3' if pat_state['selecting'] else
                'carousel 5s' if pat_state['carousel'] else
                '[1]pat [2]carousel [3]shot [4]quit')
        osd = [
            f'fps {stats["fps"]:.1f}   frame {stats["last_fn"]}',
            f'lost {stats["lost"]}   drop {stats["drop"]}   '
            f'resid {stats["resid"]}   dup {stats["dups"]}',
            f'{stats["mbps"]:.0f} Mbps   pkts {stats["npkt"]}',
            f'pat[{pat_state["mode"]}] {PAT_NAMES[pat_state["mode"]]}   {hint}',
        ]
        if args.autowb:
            osd.append(f'awb[{awb_src}] R{gains["R"]:.2f} '
                       f'G{(gains["Gr"] + gains["Gb"]) / 2:.2f} '
                       f'B{gains["B"]:.2f}   gamma {args.gamma}')
        if tnr is not None or clahe is not None:
            osd.append(f'enhance: tnr x{args.tnr or "off"}'
                       f'{" + tone-mapping" if clahe is not None else ""}')
        y0 = 24
        for i, line in enumerate(osd):
            cv2.putText(disp, line, (10, y0 + i * 22),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 0), 3, cv2.LINE_AA)
            cv2.putText(disp, line, (10, y0 + i * 22),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 255, 0), 1, cv2.LINE_AA)
        cv2.imshow(win, disp)
        #fps 按实际处理/显示帧数计（每帧完整走完处理链才算）
        stats['proc'] += 1
        now = time.time()
        if now - fps_win >= 1.0:
            stats['fps'] = (stats['proc'] - fps_last) / (now - fps_win)
            fps_last = stats['proc']
            fps_win = now
        key = cv2.waitKey(1) & 0xFF
        #选择模式下数字键 0-3 优先于一切主菜单热键（2026-11-06 修复：
        #原先 '3' 被截屏、'1' 被 toggle 抢走，导致 1→3/1→1 无法选图案）
        if pat_state['selecting']:
            if key in (ord('q'), 27):
                pat_state['selecting'] = False
                print('select cancelled')
            elif ord('0') <= key <= ord('3'):
                pat_state['selecting'] = False
                send_pat(key - ord('0'))
            #其余键在选择模式下忽略
        else:
            if key in (ord('q'), 27, ord('4')):
                break
            if key == ord('s') or key == ord('3'):
                fn = f'frame_{shot_idx:06d}.png'
                cv2.imwrite(fn, disp)
                print(f'screenshot -> {fn}')
                shot_idx += 1
            elif key == ord('1'):
                pat_state['selecting'] = True
                print('select pattern: 0=colorbar 1=h-gradient '
                      '2=v-gradient 3=checker')
            elif key == ord('2'):
                pat_state['carousel'] = not pat_state['carousel']
                pat_state['last_switch'] = time.time()
                print(f'carousel {"ON (5s)" if pat_state["carousel"] else "OFF"}')

    stop.set()
    th.join(timeout=1.0)
    cv2.destroyAllWindows()
    print(f'session: frames={stats["frames"]} lost={stats["lost"]} '
          f'last_fn={stats["last_fn"]} pkts={stats["npkt"]}')


if __name__ == '__main__':
    main()
