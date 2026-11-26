"""RAW10 UDP 流解包/重组库 —— 对齐 rtl/udp_pat_gen_v2.v 输出格式（G7）

流格式（每包 UDP 载荷）：
    8B 元数据：帧号 u32 大端 + 帧内字节偏移 u32 大端
    RAW10 数据：非末包 1450B（290 组 × 5B），末包（第 1788 包）850B（170 组）
    RAW10 打包（MIPI CSI-2 惯例）：4 像素 = 5 字节
        b0 = P1[9:2]
        b1 = {P1[1:0], P2[7:2]}
        b2 = {P2[1:0], P3[7:2]}
        b3 = {P3[1:0], P4[7:2]}
        b4 = {P4[1:0], 4'h0}
    图案公式：RGGB 8 彩条（每条 240px：白黄青绿品红红蓝黑，10bit 饱和 0x3FF/0x000；
    行偶 {R,Gr} 行奇 {Gb,B}，为 RGGB 摄像头接入对齐 CFA）（2026-11-06 与 RTL cbar_quad 同步）
    帧率 30.00fps；UDP checksum = 0x0000（RFC 768 合法"不使用"）

G11n15 相机流（2026-11-08）：RTL 改纯流式发送 + 帧首前插 2 组魔数
（5B 全白 0xFF×5 + 5B 全黑 0x00×5），帧尾短包精确排空 FIFO → 数据流按帧分节，
动态包长 min(290,occ)、帧尾短包；meta fn/off 在相机模式无帧界语义（PC 忽略）。
FrameReassembler 主路径按 10B 魔数切帧。

G11n16 重构（2026-11-08）：图案生成迁到 200MHz 相机域 raw10_pat_src，与相机
共用同一条 FIFO 链路 → 图案流同样带帧首魔数 + 动态包长，魔数切帧路径对图案流
自动生效（无需改动）。legacy (fn,off) 重组仅作 inc 线速 debug 流兜底（'t'）。
"""

import numpy as np
from struct import Struct

W, H = 1920, 1080
BYTES_PER_FRAME = W * H * 10 // 8        # 2,592,000
PKTS_PER_FRAME = 1788
DATA_PER_PKT = 1450
LAST_DATA = 850
META_LEN = 8
PAYLOAD_FULL = META_LEN + DATA_PER_PKT   # 1458
PAYLOAD_LAST = META_LEN + LAST_DATA      # 858
FRAME_PERIOD_MS = 1000.0 / 30.0          # 33.33

_hdr = Struct('>II')  # frame_num, byte_offset（大端）

PAT_NAMES = ('colorbar', 'h-gradient', 'v-gradient', 'checker')


def expected_image(mode=0):
    """参考帧（与 rtl/udp_pat_gen_v2.v pattern_quad 严格同步）：(1080,1920) uint16

    mode 0: RGGB 8 彩条——8 条 × 240px（白黄青绿品红红蓝黑），10bit 饱和
            0x3FF / 0x000；RGGB：行偶 {R,Gr}、行奇 {Gb,B}（Gr/Gb 同值）
    mode 1: 横向灰度——col>>1（0..959 线性渐变），全平面同值
    mode 2: 垂直灰度——row 饱和 1023（0..1023 渐变 + 底部 56 行白），全平面同值
    mode 3: 棋盘——120px 黑白格（16×9 格，块奇偶异或），全平面同值
    """
    r = np.arange(H, dtype=np.int64)[:, None]
    c = np.arange(W, dtype=np.int64)[None, :]
    if mode == 1:
        return np.repeat(c >> 1, H, axis=0).astype(np.uint16)       # 每行相同
    if mode == 2:
        return np.repeat(np.minimum(r, 1023), W, axis=1).astype(np.uint16)
    if mode == 3:
        return (((c // 120 + r // 120) & 1) * 1023).astype(np.uint16)
    # mode 0：RGGB 彩条
    bar = np.minimum(c // 240, 7)                       # (1,1920) 每像素彩条号
    on = np.array([[1, 1, 1], [1, 1, 0], [0, 1, 1], [0, 1, 0],
                   [1, 0, 1], [1, 0, 0], [0, 0, 1], [0, 0, 0]],
                  dtype=np.uint16)                      # 每条 {R,G,B} 使能
    r_on = on[:, 0][bar[0]][None, :]
    g_on = on[:, 1][bar[0]][None, :]
    b_on = on[:, 2][bar[0]][None, :]
    rowp = np.arange(H, dtype=np.int64)[:, None] & 1    # (H,1) 行奇偶
    even = ((c & 1) == 0)                               # (1,1920) 列奇偶
    img = np.where(rowp == 0,
                   np.where(even, r_on, g_on),          # 行偶：偶列 R / 奇列 Gr
                   np.where(even, g_on, b_on)           # 行奇：偶列 Gb / 奇列 B
                   ) * np.uint16(1023)
    return img.astype(np.uint16)


def unpack_raw10(data_u8):
    """标准 MIPI CSI-2 RAW10 解包（2026-11-03 与 RTL 修正同步）: (N*5,) uint8 -> (N*4,) uint16

    字节布局（每 5B 组）：b0=P1[9:2] b1={P1[1:0],P2[9:4]} b2={P2[3:0],P3[9:6]}
    b3={P3[5:0],P4[9:8]} b4=P4[7:0]（无损 10bit×4px=5B）
    """
    b = data_u8.reshape(-1, 5).astype(np.uint16)
    p1 = (b[:, 0] << 2) | (b[:, 1] >> 6)
    p2 = ((b[:, 1] & 0x3F) << 4) | (b[:, 2] >> 4)
    p3 = ((b[:, 2] & 0x0F) << 6) | (b[:, 3] >> 2)
    p4 = ((b[:, 3] & 0x03) << 8) | b[:, 4]
    out = np.empty(len(b) * 4, dtype=np.uint16)
    out[0::4] = p1
    out[1::4] = p2
    out[2::4] = p3
    out[3::4] = p4
    return out


def frame_to_image(buf_u8):
    """2,592,000B 扁平缓冲 -> (1080,1920) uint16 RAW10 像素图"""
    return unpack_raw10(buf_u8).reshape(H, W)


class FrameReassembler:
    """G11n16 双模式重组器：相机流与图案流均按魔数切帧，legacy 作 inc debug 兜底。

    相机流/图案流（G11n16：200M 图案源与相机共用 FIFO 链路，同构帧格式）：每帧
    帧首前插 2 组魔数（40'hFFFFFFFFFF +
    40'h0000000000 = 5B 全白紧跟 5B 全黑，RAW10 中自然出现概率极低），帧尾短包
    精确排空 FIFO → 数据流按帧分节。PC 剥离 8B meta 后按字节流累积：魔数 =
    帧起始标记（消费后 _pending，按字节计数凑满 BYTES_PER_FRAME 即成帧，无
    下一帧依赖）；魔数前残数据按短帧落账（中段接入自愈）。每帧魔数重对齐，
    图案/相机切换无需重算帧号；动态包长下 off 元数据无帧界语义（忽略）。
    图案流（pat_gen 直发，无魔数）：累积超帧长仍无魔数 → 粘性锁定元数据模式，
    每包直接按 (fn,off) 重组；数据段头重现魔数（相机流每帧帧首必有）→ 自动切回
    相机模式。两种模式可随时切换互不干扰。
    feed() 返回 (fn, idx, is_complete, frame_dict) 兼容 viewer；
    相机模式 fn 为合成帧序号（每完成一帧 +1）。只保留最近 max_frames 帧。
    """

    MAGIC = bytes([0xFF] * 5 + [0x00] * 5)   # 10B 帧界魔数（RTL 写侧帧首前插 2 组）

    def __init__(self, max_frames=4):
        self.max_frames = max_frames
        self.frames = {}          # fn -> frame_dict
        self.n_dups = 0           # 元数据模式重复/乱序包计数（offset 重收）
        self._buf = bytearray()   # 相机模式字节流累积（已剥离 8B meta 的数据段）
        self._pending = False     # 已消费帧界魔数、正在按字节计数凑帧
        self._scanned = 0         # 非 pending 态增量魔数扫描游标（已扫到 buf 末尾的位置）
        self._meta_mode = False   # 粘性模式：已判定元数据流（图案），直到数据段头重现魔数
        self.frame_seq = 0        # 相机模式完成帧计数（合成 fn）
        self.n_resync = 0         # 相机模式超帧长无魔数丢弃次数（流损坏/中段接入自愈）

    def feed(self, pkt_payload):
        if self._meta_mode:
            # 元数据流模式：每包直接按 (fn,off) 重组；数据段头重现帧界魔数
            # （相机流每帧帧首必为 10B 魔数）→ 切回相机模式，从魔数后继续字节流
            if pkt_payload[META_LEN:META_LEN + 10] == self.MAGIC:
                self._meta_mode = False
                self._buf.clear()
                self._scanned = 0
                self._buf += pkt_payload[META_LEN + 10:]
                # G11n15b 修复：魔数已消费，必须置 _pending=True 开始按字节计数
                # 凑帧。原版漏置 → buf 凑过帧长又触发"超帧长无魔数"判回
                # _meta_mode → 无限振荡回 legacy（legacy 按 (fn,off) 重组相机流
                # 因帧首短包 off 与字节位置错开 → 永不成帧 → fps=0/画面冻结，
                # 板测"帧号在涨、丢帧 0、fps=0"画像精确吻合）
                self._pending = True
                return self.frame_seq + 1, -1, False, None
            return self._feed_legacy(pkt_payload)
        self._buf += pkt_payload[META_LEN:]
        result = None
        while True:
            if self._pending:
                # 凑帧中：纯字节计数，不搜索魔数。帧内数据是合法像素流，
                # 可能天然构成伪帧界魔数（FF×5+00×5 = 4 白像素紧跟 4 黑像素：
                # 棋盘格每个黑白块边界、相机高光/暗场边缘）——一旦误认就会把
                # 整帧切碎成短帧、字节计数清零，永远凑不满 BYTES_PER_FRAME
                # （G11n16d 板测冻结根因之一）；且全缓冲 find 是 O(N)/包，
                # 2.6MB 缓冲 × 53.7K pps 纯 CPU 扫描即把收包循环拖垮（实测
                # 8.2K pps、内核缓冲溢出丢 5/6）。帧长由 RTL 精确保证。
                if len(self._buf) >= BYTES_PER_FRAME:
                    result = self._emit(bytes(self._buf[:BYTES_PER_FRAME]))
                    del self._buf[:BYTES_PER_FRAME]
                    self._pending = False           # 下一帧应从魔数开始
                    self._scanned = 0
                    continue
                break
            # 非 pending：增量搜索帧界魔数（只扫新到字节，9B 重叠防跨包魔数漏检）
            p = self._buf.find(self.MAGIC, max(0, self._scanned - (len(self.MAGIC) - 1)))
            if p >= 0:
                if p:
                    # 魔数前残数据（中段接入/异常尾帧）→ 短帧落账，不显示
                    self._emit(bytes(self._buf[:p]))
                del self._buf[:p + len(self.MAGIC)]
                self._scanned = 0
                self._pending = True
                continue
            self._scanned = len(self._buf)
            break
        if result is not None:
            return result
        if not self._pending and len(self._buf) > BYTES_PER_FRAME:
            # 超帧长无魔数 → 图案（元数据）流：锁定 legacy 模式（粘性），清缓冲
            self._meta_mode = True
            self._buf.clear()
            self._scanned = 0
            return self._feed_legacy(pkt_payload)
        return self.frame_seq + 1, -1, False, None   # 帧累积中（无帧界事件）

    def _emit(self, data):
        """落账一帧：完整帧（恰 BYTES_PER_FRAME）或短帧（丢数损坏，零填充不显示）。"""
        self.frame_seq += 1
        fn = self.frame_seq
        complete = (len(data) == BYTES_PER_FRAME)
        buf = np.zeros(BYTES_PER_FRAME, np.uint8)
        n = min(len(data), BYTES_PER_FRAME)
        if n:
            buf[:n] = np.frombuffer(data[:n], np.uint8)
        f = {'buf': buf, 'got': None, 'bytes': len(data)}
        self.frames[fn] = f
        while len(self.frames) > self.max_frames:    # 清最老残帧
            del self.frames[min(self.frames)]
        return fn, -1, complete, f

    def _feed_legacy(self, pkt_payload):
        """图案（元数据）流重组：按 (fn,off) 写入帧缓冲（G7 原语义）。"""
        fn, off = _hdr.unpack_from(pkt_payload, 0)
        data = pkt_payload[META_LEN:]
        #中段接入/串流保护（2026-11-06）：非 RAW10 流（如 inc 压测流）或乱序垃圾
        #meta 会解析出越界 off——直接丢弃等待重新同步，防止 idx 越界崩溃
        if off + len(data) > BYTES_PER_FRAME:
            return -1, -1, False, None
        f = self.frames.get(fn)
        if f is None:
            f = {
                'buf': np.empty(BYTES_PER_FRAME, np.uint8),
                'got': np.zeros(PKTS_PER_FRAME, bool),
                'bytes': 0,
            }
            self.frames[fn] = f
            while len(self.frames) > self.max_frames:   # 清最老残帧
                del self.frames[min(self.frames)]
        idx = off // DATA_PER_PKT
        if idx < 0 or idx >= PKTS_PER_FRAME:
            return -1, -1, False, None
        if not f['got'][idx]:
            f['got'][idx] = True
            f['bytes'] += len(data)
            f['buf'][off:off + len(data)] = np.frombuffer(data, np.uint8)
        else:
            self.n_dups += 1
        complete = f['bytes'] == BYTES_PER_FRAME
        return fn, idx, complete, f


# ---------------- 白平衡（demosaic 之前的 RAW 域通道增益） ----------------

# 2x2 CFA 位置 -> 通道名（(row%2, col%2)）
CFA_MAP = {
    'RGGB': {(0, 0): 'R', (0, 1): 'G', (1, 0): 'G', (1, 1): 'B'},
    'BGGB': {(0, 0): 'B', (0, 1): 'G', (1, 0): 'G', (1, 1): 'R'},
    'GRBG': {(0, 0): 'G', (0, 1): 'R', (1, 0): 'B', (1, 1): 'G'},
    'GBRG': {(0, 0): 'G', (0, 1): 'B', (1, 0): 'R', (1, 1): 'G'},
}


def cfa_channel_map(cfa):
    """CFA 相位 -> {(row%2, col%2): 'R'|'Gr'|'Gb'|'B'}。

    Gr = 与 R 同行的 G，Gb = 与 B 同行的 G（Sony 约定，IMX415 数据手册 L316）。
    apply_wb 与 viewer 的 auto_gains 共用本映射，保证增益算/施两侧同源。
    """
    pos = dict(CFA_MAP[cfa])
    r_pos = next((rc for rc, ch in pos.items() if ch == 'R'), None)
    if r_pos is not None:
        for rc, ch in pos.items():
            if ch == 'G':
                pos[rc] = 'Gr' if rc[0] == r_pos[0] else 'Gb'
    return pos


def apply_wb(img, gains, cfa='BGGB'):
    """按 CFA 位置乘通道增益。gains: {'R':g,'Gr':g,'Gb':g,'B':g}；灰度图案增益 1.0 直通。
    """
    pos = cfa_channel_map(cfa)
    out = img.copy()
    for (rm, cm), ch in pos.items():
        g = gains.get(ch, 1.0)
        if g != 1.0:
            sel = img[rm::2, cm::2].astype(np.float32) * g
            out[rm::2, cm::2] = np.clip(sel, 0, 1023).astype(np.uint16)
    return out
