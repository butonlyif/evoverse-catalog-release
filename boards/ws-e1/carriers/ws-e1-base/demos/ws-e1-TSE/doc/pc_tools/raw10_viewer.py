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
  uv run raw10_viewer.py --autowb
  uv run raw10_viewer.py --awb-preset 'led4000:0.93,0.95' --awb-pad 0.2

相机模式白平衡：默认 --wb 是板对白灯定标值；草地占满画面等单色场景灰世界失效
（--autowb 会整体带 complementary 色偏），此时用默认手动 WB，或按
raw10_awb_eval.py --calibrate 给该灯做一条预置。
CFA 相位（2026-11-09 更正，详见 capture2/README.md 第 1 节）：默认 --cfa RGGB。
本段此前写的是 **GRBG**，那个"板测三重验证"结论是错的——错因不在判据本身，而在
当时 CV_BAYER 代号表把 demosaic 代号用反，且显示/存图都没做 RGB->BGR 换轴，两个
R/B 互换互相掩盖。代号表修好之后，同一批"RGGB 解码草地发紫、白灯 R/G≈1.64"的
观察不再成立；判"颜色对不对"之前先确认换轴（见 isp_render.to_bgr）。
第二层（RGGB 还是 BGGB，两者互为 R↔B 重标记，色度统计量判不出来）也已定案为
**RGGB**：硬件口径 + 已知颜色实物对照，详见 capture2/README.md 第 1 节。RTL
合成图案流同样是 RGGB（raw10_pat_src 行偶 {R,Gr}）；两流共用同一条 FIFO→UDP→
viewer 链路，打包/解包顺序经彩条 + expected_image 双重验证无误。

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

# OpenCV Bayer 常量与传感器排列的对应关系。
#
# OpenCV 的 BayerXX 名字是物理相位的**互补**名（2026-11-09 用合成图实测，
# 线性与 -EA 两套一致）：物理 [[R,G],[G,B]]（本项目称为 RGGB，(0,0) 是 R）
# 要用 COLOR_BayerBG2RGB 才颜色正确；用 COLOR_BayerRG2RGB 会把 R/B 互换。
# 实测口径：把一张"左半红右半蓝"的已知颜色图按物理相位手工马赛克化，再逐个代号
# demosaic，看哪一支把红还原到左边；四相位全测，OpenCV 4.10 与 5.0 结果一致。
# 这条已经做成自校验脚本，改过 demosaic 相关代码就跑一次（返回码非 0 即本表错）：
#     uv run capture2/cfa_mapping_check.py
#
# 这里必须和 raw10.CFA_MAP 同源：apply_wb 按 CFA_MAP 把增益乘到物理位置，
# demosaic 按本表解释物理位置。两边解释不一致时，白平衡增益会乘到相反通道
# ——R 增益进了 B 通道，画面偏品/青，且用增益标定时会算出荒谬值（实测 R/G≈5）。
#
# 本表曾经反着写（'RGGB': COLOR_BayerRG2RGB）却长期看不出来，原因是第二次互换
# 把它掩盖了：处理链输出是 RGB，而 imshow/imwrite 按 BGR 解释内存，当时显示和存图
# 都没换轴。2026-11-06 那次 8 彩条"实测确定"正是在 --wb 1,1,1,1（增益全 1，
# apply_wb 等于不做事）+ 没换轴两重掩盖下做的，屏幕上看着严格正确。现在出口统一
# 走 isp_render.to_bgr()（本模块就地 cvtColor，避免与 isp_render 互相 import），
# 代号表必须自己就是对的。
CV_BAYER = {
    'RGGB': cv2.COLOR_BayerBG2RGB,
    'BGGB': cv2.COLOR_BayerRG2RGB,
    'GRBG': cv2.COLOR_BayerGB2RGB,
    'GBRG': cv2.COLOR_BayerGR2RGB,
}

# 边缘感知 demosaic（-EA 后缀，插值方向沿边缘梯度选择）：双线性在边缘会
# 产生拉链状锯齿/彩色镶边（Bayer 通道混叠），EA 显著消除，1080p 实测
# 2.9ms/帧开销可忽略。默认启用；--demosaic linear 可切回旧行为对比。
CV_BAYER_EA = {
    'RGGB': cv2.COLOR_BayerBG2RGB_EA,
    'BGGB': cv2.COLOR_BayerRG2RGB_EA,
    'GRBG': cv2.COLOR_BayerGB2RGB_EA,
    'GBRG': cv2.COLOR_BayerGR2RGB_EA,
}

_OSD_K = np.ones((3, 3), np.uint8)


def draw_osd(disp, lines, x=10, y0=24, dy=22, scale_txt=0.55):
    """绿字 + 黑描边，原地绘制并返回同一数组。viewer 和 isp_render 共用这一份。

    描边**不能**再用"厚黑字 + 薄绿字两遍 putText"的写法：OpenCV 的字距本身随
    thickness 变（实测 cv2 5.0.0，'0'×36 在 thickness=1 时 getTextSize 宽 325、
    thickness=3 时宽 361，每字符多走 1px），两遍的字符位置因此逐字错开、越往右
    偏得越多，放大看就是每个字符右边挂一份黑色残影（"0:00/0:10" 后面多出一段黑
    ":10"）。这个写法从项目一开始就是错的，只是 1080p 缩略显示看不出来。
    现在只排一遍字（thickness=1）并栅格化成单通道掩码，靠膨胀得到描边环，黑/绿
    两色取自同一份掩码，位置天然对齐。5 行实测 1.7ms/帧。
    """
    for i, line in enumerate(lines):
        org = (x, y0 + i * dy)
        (w, h), bl = cv2.getTextSize(line, cv2.FONT_HERSHEY_SIMPLEX, scale_txt, 1)
        ox = max(0, org[0] - 3)
        oy = max(0, org[1] - h - 3)
        roi = disp[oy:org[1] + bl + 4, ox:ox + w + 7]
        m = np.zeros(roi.shape[:2], np.uint8)
        cv2.putText(m, line, (org[0] - ox + 2, org[1] - oy),
                    cv2.FONT_HERSHEY_SIMPLEX, scale_txt, 255, 1, cv2.LINE_AA)
        ring = cv2.dilate(cv2.dilate(m, _OSD_K), _OSD_K)   # 2px 描边
        ring[m > 0] = 0
        roi[ring > 0] = 0
        roi[m > 0] = (0, 255, 0)
    return disp


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


# ---- AWB 预置表 / 参数 / 跨帧状态 ------------------------------------------
#
# 预置存"该光源下**估计器自己**给出的 (R/G, B/G)"，口径：线性 RAW 域、扣过黑
# 电平、未乘 WB 增益、mode=auto 收敛后 state.uv_raw 那一组数，必须用
# raw10_awb_eval.py --calibrate 生成。不能用 --wb 的倒数当预置：那是全帧均值
# (gray-world) 口径，和 p=6 范数/白块统计量根本不是一回事——同一段素材实测两种
# 口径差 0.3 以上（均值 0.518/0.597，估计器 0.929/0.947），第一版默认预置拿
# 1/1.56、1/1.59 当预置，结果吸附永远吸不上、钳位每帧都触发。
#
# 比值近似与传感器增益无关（增益同时乘四通道），所以同一种灯在不同 +dB 下拍的
# 素材可以共用一条预置；但 GAIN_PCG 在列 ADC 之前、各通道增益误差不完全同比例，
# 换增益后仍应重跑 --calibrate 复核。
#
# IMX415 手册 Image Sensor Characteristics 的响应比容差带（3200K 卤素 + CM500S
# IR-cut、wafer 状态、不含封玻璃与镜头）：R/G 0.42~0.58、B/G 0.26~0.44。那是
# **均值口径**的传感器响应比，只在 --calibrate 输出的"均值口径"那一行用来对方向，
# 不进本表。

AWB_PRESETS_DEFAULT = {
    # raw10_awb_eval.py --calibrate capture2/capture2.bin --warm 30 实测
    # （室内单盏白灯 + 显示器场景，mode=auto 走的是 shade 支路）
    'capture2-lamp': (0.929, 0.947),
}


def uv_dist(a, b):
    """光源色度 (R/G, B/G) 的欧氏距离；两个轴同为比值，量纲一致，不再加权。"""
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5


class AwbOptions:
    """AWB 门控/钳位/收敛参数。默认值 = viewer 与 raw10_play 的命令行默认。"""

    def __init__(self, lo=25.0, sat_hi=1010.0, min_frac=0.005, snap=0.06,
                 pad=0.45, speed=0.10, speed_fast=0.45, fast_frames=8,
                 cut=0.18, rate=0.06, gain_db=0.0, presets=None):
        self.lo = float(lo)
        self.sat_hi = float(sat_hi)
        self.min_frac = float(min_frac)
        self.snap = float(snap)
        self.pad = float(pad)
        self.speed = float(speed)
        self.speed_fast = float(speed_fast)
        self.fast_frames = int(fast_frames)
        self.cut = float(cut)
        self.rate = float(rate)
        self.gain_db = float(gain_db)
        self.presets = dict(AWB_PRESETS_DEFAULT)
        if presets:
            self.presets.update(presets)
        rg = [v[0] for v in self.presets.values()]
        bg = [v[1] for v in self.presets.values()]
        # 钳位框 = 所有预置的包围盒 ± pad。pad 是给"还没枚举到的灯"留的余量，
        # 所以默认给到 0.45（一种灯从 2700K 换到 6500K 也就这个量级）；把办公
        # 室里真会出现的几种灯都 --calibrate 进预置之后，再把 pad 收紧到 0.1 左右，
        # 这时钳位才真正是"只挡荒谬解"而不是"把新灯当荒谬解"。
        self.box = (max(0.05, min(rg) - self.pad), max(rg) + self.pad,
                    max(0.05, min(bg) - self.pad), max(bg) + self.pad)

    @property
    def lin_gain(self):
        """传感器模拟/数字增益的线性倍数（GAIN_PCG_0 值 = dB*10/3）。"""
        return 10.0 ** (self.gain_db / 20.0)

    @staticmethod
    def parse_presets(spec):
        """'name:0.64,0.63;name2:0.50,0.35' -> dict（--awb-preset，可重复给）"""
        out = {}
        for item in spec.split(';'):
            item = item.strip()
            if not item:
                continue
            name, _, pair = item.partition(':')
            rg, _, bg = pair.partition(',')
            if not name or not rg or not bg:
                raise ValueError(f'--awb-preset 格式应为 name:R/G,B/G，收到 {item!r}')
            out[name.strip()] = (float(rg), float(bg))
        return out


class AwbState:
    """AWB 跨帧状态。每条流一个实例（viewer/player 各一份，eval 每个序列新建）。"""

    def __init__(self):
        self.slow_uv = None      # 色度慢参考（relock 判据的分母）
        self.fast = 0            # 剩余快速收敛帧数（relock 期间 >0）
        self.uv = None           # 本帧光源色度（吸附/钳位之后）
        self.uv_raw = None       # 本帧光源色度（吸附/钳位之前，定标读这个）
        self.est = None          # 本帧原始四通道均值（--calibrate 读这个）
        self.src = '-'
        self.n_frozen = 0        # 累计冻结帧数（低信噪比拒更新）

    def reset(self):
        self.__init__()


def auto_gains(img, gains, cfa='RGGB', mode='auto', opts=None, state=None,
               speed=None):
    """自动白平衡 v4：估计内核沿用 v3，外面补门控 / 预置吸附 / 钳位 / 时序。

    v3 的内核（stage 1/2）本来就是对的：有中性亮块时走白块法（高光即光源色，
    最准），中性块占比不足 1% 时切 Shades-of-Grey（Minkowski p=6 范数；p=1 退化
    成灰世界均值、p→∞ 退化成白块最大值，p=6 兼取两者，单色主导场景不再把场景
    色当光源，板测那次"草地满屏→整体补色偏"就是这么救回来的）。换灯和暗场这两
    个时刻暴露的问题都不在估计器本身，所以 v4 只加外围三层：

      stage 0 门控：暗块（噪声底）与饱和块（G 先削顶把 R/G 人为拉到 1.0，是饱和
             伪影不是色度，见 raw10_wbcal 的分层表）从统计里剔掉，且四通道共用
             同一份块掩膜——各通道挑各自的像素集合，均值就不可比了。有效块占比
             < min_frac 时**不更新增益**，OSD 显示 frozen(占比)。capture1 那种
             素材（p50=0、53% 像素压在 pedestal 上）以前是直接把噪声的形状喂进
             估计器，输出看着"收敛了"，其实收敛的是噪声。
      stage 3 钳位：估计出的 (R/G, B/G) 先跟预置表比——距离 <= snap 直接吸附到
             预置（顺带把残余偏色和逐帧抖动一起消掉）；离所有预置都远就钳进包围
             盒 ± pad。IMX415 手册的响应比只有 0.42~0.58 / 0.26~0.44 这种带（还
             是 wafer 状态），而镜头 IR-cut 的红外泄漏会让 R 抬升、统计上与"暖
             光源"同形，算出物理上不成立的解时钳位比相信它安全。
      stage 4 时序：色度帧间跳变 > cut 判为灯变了，时间常数临时提到 speed_fast
             （默认 0.45，几帧回中）；小偏差仍用 speed 慢收敛压工频闪烁；非
             relock 时每通道每帧变化限幅 rate，防单帧坏统计把增益拽飞。

    通道归属经 cfa_channel_map 与 apply_wb 同源；锚定最亮通道（只补短不压长，
    白灯不被拖灰）；增益限幅 0.25..4.0。返回 (gains, source)，source 里带
    patch/shade 与 snap/clamp/relock/frozen 标记，可直接上 OSD。
    回归与定标见 raw10_awb_eval.py（人造换灯序列 + --calibrate 反算预置）。
    """
    opts = opts if opts is not None else AwbOptions()
    st = state if state is not None else AwbState()
    sp = opts.speed if speed is None else speed

    p00 = img[0::2, 0::2]
    p01 = img[0::2, 1::2]
    p10 = img[1::2, 0::2]
    p11 = img[1::2, 1::2]
    sub = {(0, 0): p00, (0, 1): p01, (1, 0): p10, (1, 1): p11}
    chn = cfa_channel_map(cfa)
    # 2x2 块网格（原图 [::4,::4]，每块恰含 R/Gr/Gb/B 各一个亚像素，270x480）。
    # 门控和 SoG 共用这一份，float32 只转一次。
    blk = {rc: sub[rc][::2, ::2].astype(np.float32) for rc in sub}
    L2 = (blk[(0, 0)] + blk[(0, 1)] + blk[(1, 0)] + blk[(1, 1)]) * 0.25

    # stage 0：门限。信号 DN = 光子 * 增益，读出噪声 DN = 0.5 * 增益，两者同比例
    # 放大 => SNR 与增益无关，所以门限必须**跟着增益折算**（lo * lin_gain），不能
    # 固定一个 DN 数：+12dB 下 25DN 的信号折算回 0dB 只有 6DN，早进噪声底了。
    floor = max(opts.lo * opts.lin_gain, 6.0)
    gate = (L2 >= floor) & (L2 < opts.sat_hi)
    frac = float(gate.mean())
    if float(L2.mean()) < 1.0:
        return gains, 'none'
    if frac < opts.min_frac:
        # 有效块太少 => 不更新增益（原样返回），预置/上一帧的增益继续用
        st.n_frozen += 1
        return gains, f'frozen({frac * 100:.2f}%)'

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
        # v4：中性判据之外再叠 stage 0 的门限——旧写法只挡饱和，暗块只要"未饱和
        # 且四通道接近"就进统计，而暗块的四通道接近恰恰是噪声造成的假象（ pedestal
        # 附近噪声同分布），85 分位在暗场景里本身就只有几十个 DN。
        mask = ((L >= np.percentile(L, 85)) & (L < opts.sat_hi) & (L >= floor)
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
    # 回退/指定：Shades of Grey（p=6 Minkowski 范数，2x2 块网格）
    if not means:
        # v4：旧写法对全子面做范数，暗块把均值往 pedestal 拉、饱和块把 R/G 拉到
        # 1.0，两头都是系统性偏差。现在只在 gate 上算，而且**四通道共用同一份块
        # 掩膜**：各通道各自挑像素集合的话，四个均值来自不同的亮度分布，它们的
        # 比值就不再是光源色度了。
        if int(gate.sum()) >= 64:
            for rc, ch in chn.items():
                x = blk[rc][gate] * (1.0 / 1023.0)
                means[ch] = float((x ** 6).mean()) ** (1.0 / 6.0) * 1023.0
    if not means:
        return gains, 'none'
    st.est = dict(means)

    # stage 3：光源色度 (R/G, B/G) + 预置吸附 / 包围盒钳位。G 取 Gr/Gb 的均值
    # （手册 §1 的灵敏度定义就是 (VGr+VGb)/2），Gr/Gb 之间的失配不参与色度判定，
    # 留给各自的增益去补。
    g_val = 0.5 * (means['Gr'] + means['Gb'])
    uv = (means['R'] / g_val, means['B'] / g_val)
    st.uv_raw = uv
    tags = []
    near = min(opts.presets.items(), key=lambda kv: uv_dist(uv, kv[1]))
    if uv_dist(uv, near[1]) <= opts.snap:
        uv = near[1]                      # 吸附：残余偏色和逐帧抖动一起消掉
        tags.append(f'snap:{near[0]}')
    else:
        lo_rg, hi_rg, lo_bg, hi_bg = opts.box
        crg = min(max(uv[0], lo_rg), hi_rg)
        cbg = min(max(uv[1], lo_bg), hi_bg)
        if (crg, cbg) != uv:
            uv = (crg, cbg)
            tags.append('clamp')
    # 吸附/钳位只改 R、B 两个比值；G 的电平和 Gr/Gb 失配原样保留
    means['R'] = uv[0] * g_val
    means['B'] = uv[1] * g_val

    # stage 4：时序。色度相对**慢参考**跳变超过 cut 才判"灯变了/镜头转了"，切到
    # 快速时间常数；小偏差维持慢收敛压工频闪烁（室内 100Hz 纹波让逐帧色度小幅
    # 摆动，若一有摆动就快收敛，画面会呼吸）。
    # 参考必须是 EMA 慢参考而不是上一帧：上一帧本身带噪声，暗场里单帧噪声就能
    # 把色度甩出 cut，于是每帧都误判 relock、每帧 45% 跳变（flicker 用例实测
    # 33%，就是这个自激）。慢参考跟着走，真换灯时 2~3 帧内仍会越过 cut。
    if st.slow_uv is None:
        st.slow_uv = uv
    if uv_dist(uv, st.slow_uv) > opts.cut:
        st.fast = opts.fast_frames
        st.slow_uv = uv           # 参考重新锚到新灯，避免同一跳变连续多帧误触发
    sp_eff = opts.speed_fast if st.fast > 0 else sp
    rate_limit = (st.fast == 0)
    if st.fast > 0:
        st.fast -= 1
        tags.append('relock')
    else:
        st.slow_uv = tuple((1.0 - sp) * a + sp * b
                           for a, b in zip(st.slow_uv, uv))

    # 锚定最亮通道：只补短不压长——若锚全图均值，草地主导场景会把白块/灯
    # 整体拖暗到场景均值（白灯变灰）；锚 max 则最亮通道增益恒 1，白块保持
    # 原有亮度，其余通道按响应差补齐
    target = max(means.values())
    lim = 1.0 + opts.rate
    for ch, m in means.items():
        g = min(4.0, max(0.25, target / m))
        g = gains[ch] * (1.0 - sp_eff) + g * sp_eff
        if rate_limit:
            # 非 relock 时每帧每通道最多变 rate（相对量）：坏帧的单帧统计（一片
            # 高光、镜头被遮）最坏拖 6% 一格，下一帧自然回来，不会拽飞。
            g = min(max(g, gains[ch] / lim), gains[ch] * lim)
        gains[ch] = g
    st.uv = uv
    st.src = source + (f'[{",".join(tags)}]' if tags else '')
    return gains, st.src


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
                    help='自动白平衡（相机模式用）：白块法 >=1%% 中性块，否则 Shades of '
                         'Grey (p=6)；v4 另加门控/预置吸附/钳位/换灯快速回中')
    ap.add_argument('--awb-mode', default='auto', choices=('auto', 'patch', 'shade'),
                    help='AWB 算法（--autowb 时生效）：auto=按场景自动路由；'
                         'patch=锁定白块法；shade=锁定 Shades of Grey')
    ap.add_argument('--awb-lo', type=float, default=25.0,
                    help='AWB 门限（折算到 0dB 的 DN）：块亮度低于它的像素不进统计，'
                         '有效块占比 <0.5%% 时冻结增益。暗场+高增益场景调这个')
    ap.add_argument('--awb-gain-db', type=float, default=0.0,
                    help='板端当前传感器增益 dB（=GAIN_PCG_0 值 x3/10），只用来把 '
                         'AWB 门限折算到输出 DN（噪声与信号同倍放大，门限必须跟着走）')
    ap.add_argument('--awb-preset', action='append', default=[], metavar='N:RG,BG',
                    help='白点预置（可重复给，也可分号分隔一条）：N:R/G,B/G，'
                         '口径=估计器统计量，用 raw10_awb_eval.py --calibrate 生成，'
                         '不要填 --wb 的倒数')
    ap.add_argument('--awb-snap', type=float, default=0.06,
                    help='距预置小于该色度距离时直接吸附到预置（消残余偏色/抖动）')
    ap.add_argument('--awb-pad', type=float, default=0.45,
                    help='预置包围盒外扩量，超出则钳位。灯都枚举进预置之后可收紧到 0.1')
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
    ap.add_argument('--black', type=int, default=0,
                    help='黑电平（BLC）扣除，链首最先施加。传感器暗区不是 0 而是'
                         '一个 pedestal（本素材最低值 50），不扣的话它被 R/B 增益'
                         '放大、再被 gamma 提亮，整片阴影发粉。0=保持旧行为')
    args = ap.parse_args()

    gains = parse_gains(args.wb)
    awb_src = '-'
    awb_presets = {}
    for spec in args.awb_preset:
        awb_presets.update(AwbOptions.parse_presets(spec))
    awb_opts = AwbOptions(lo=args.awb_lo, snap=args.awb_snap, pad=args.awb_pad,
                          gain_db=args.awb_gain_db, presets=awb_presets)
    awb_state = AwbState()
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
    print(f'listening on {args.bind}:{args.port}  cfa={args.cfa} wb={gains} '
          f'black={args.black}')
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

        if args.black:
            # 链首先扣黑电平：后面的 TNR/列FPN/AWB 都该在扣过底的数据上统计
            img = cv2.subtract(img, float(args.black))
        if tnr is not None:
            img = tnr(img)
        if args.decol:
            img = decol_columns(img)
        if args.autowb:
            gains, awb_src = auto_gains(img, gains, args.cfa,
                                        mode=args.awb_mode,
                                        opts=awb_opts, state=awb_state)
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
        draw_osd(disp, osd)          # 默认 x=10 / y0=24 / dy=22，与旧写法同参数
        cv2.imshow(win, cv2.cvtColor(disp, cv2.COLOR_RGB2BGR))
        # 处理链输出是 RGB，imshow 按 BGR 解释——必须换轴，见 isp_render.to_bgr
        # （viewer 不能 import isp_render：那边反过来 import 本模块，会成环）
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
                cv2.imwrite(fn, cv2.cvtColor(disp, cv2.COLOR_RGB2BGR))   # 同上，RGB->BGR
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
