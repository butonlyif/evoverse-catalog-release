# G6 千兆吞吐压测接收端（iperf 风格）v2
# 用法：uv run test_udp_thr.py [--seconds 60] [--port 10005]
# 板侧：TEST_MODE=0 + PAT_TYPE=0（v2 inc 递增 UDP，PAT_DLEN=1458，PAT_NUM=0 无限，IPG=12 线速）
#
# 载荷规律（2026-11-06 板级 3 包实测交叉验证）：
#   UDP socket 只给载荷（无 IP 头）。v2 inc 模式载荷是跨包连续的 mod-256
#   递增字节流，每个包推进 1458+8=1466 字节（包边界 meta 跳 8）。
#   => 期望起始字节 start_k = (start_0 + k*1466) & 0xFF
#   => 丢 L 包时起始字节跳 186*(L+1) mod 256（周期 128，>127 连丢才歧义）
#   => 逐包校验 data[i]==(start+i)&0xFF；干净包推进 start；失配=丢包事件，
#      跳变量译码估算丢包数后重新同步。
import socket
import sys
import time
import gc
import ctypes

STEP = 1466          #每包字节流推进量（1458 载荷 + 8 meta 跳变）
PLEN = 1458
#delta(byte) -> 丢包数 L 的译码表（取最小 L；周期 128，大跳变歧义按 burst 报）
DELTA2LOSS = {}
for L in range(0, 256):
    d = (STEP * (L + 1)) & 0xFF
    if d not in DELTA2LOSS:
        DELTA2LOSS[d] = L
#256 个可能起始字节的期望载荷模板（memcmp 用；现算会拖垮 82k pps 接收率）
EXP = {s: bytes((s + i) & 0xFF for i in range(PLEN)) for s in range(256)}


def main():
    seconds = 60.0
    port = 10005
    args = sys.argv[1:]
    for i, a in enumerate(args):
        if a == '--seconds':
            seconds = float(args[i + 1])
        elif a == '--port':
            port = int(args[i + 1])

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 32 * 1024 * 1024)
    s.bind(('0.0.0.0', port))
    s.settimeout(1.0)
    print(f'listening on 0.0.0.0:{port}  payload={PLEN}B inc-stream step={STEP}  run {seconds:.0f}s')

    buf = bytearray(2048)
    mv = memoryview(buf)
    gc.disable()
    #提升进程优先级，缓解 Windows 调度停顿导致的内核 socket 队列溢出
    ctypes.windll.kernel32.SetPriorityClass(
        ctypes.windll.kernel32.GetCurrentProcess(), 0x00000080)  #HIGH_PRIORITY_CLASS

    pkts = 0
    plen_err = 0
    pay_err = 0          #字节失配的包数
    loss_events = 0      #跳变事件数
    lost_est = 0         #估算丢包总数
    bursts = []          #大跳变（歧义）记录
    total_bytes = 0
    t0 = None
    t_end = None
    sec_prev = -1
    sec_pkts = 0
    sec_bytes = 0
    start_exp = None     #期望起始字节（首个干净包锁定）

    try:
        while True:
            try:
                n = s.recv_into(mv, 2048)
            except socket.timeout:
                if t0 is not None and time.monotonic() >= t_end:
                    break
                continue
            now = time.monotonic()
            if t0 is None:
                t0 = now
                t_end = t0 + seconds
                print('stream detected, measuring...')
            if now >= t_end:
                break

            data = bytes(mv[:n])
            pkts += 1
            sec_pkts += 1
            total_bytes += len(data)
            sec_bytes += len(data)

            if len(data) != PLEN:
                plen_err += 1
                continue

            c0 = data[0]
            exp = EXP[c0]
            if start_exp is None:
                start_exp = c0       #首包锁定基准
            diff = (c0 - start_exp) & 0xFF
            if diff == 0:
                if data != exp:
                    pay_err += 1
                start_exp = (start_exp + STEP) & 0xFF
            else:
                #跳变 = 丢包事件；译码丢包数后同步到本包
                loss_events += 1
                L = DELTA2LOSS.get(diff)
                if L is None or L > 120:
                    if L is None:
                        L = -1
                    bursts.append(f't={now-t0:.1f}s delta={diff}')
                else:
                    lost_est += L
                #本包自身逐字节校验（跳变起点也应是干净递增流）
                if data != exp:
                    pay_err += 1
                start_exp = (c0 + STEP) & 0xFF

            sec_now = int(now - t0)
            if sec_now != sec_prev and sec_now > 0:
                mbps = sec_bytes * 8 / 1e6
                print(f'[{sec_now:3d}s] {mbps:7.1f} Mbps  {sec_pkts:6d} pkt/s  '
                      f'loss_ev={loss_events} lost~{lost_est} badpay={pay_err}')
                sec_prev = sec_now
                sec_pkts = 0
                sec_bytes = 0
    finally:
        el = (time.monotonic() - t0) if t0 else 0
        mbps = total_bytes * 8 / el / 1e6 if el > 0 else 0
        print('=' * 60)
        print(f'duration   : {el:.1f} s')
        print(f'packets    : {pkts}')
        print(f'throughput : {mbps:.1f} Mbps (UDP payload)  '
              f'{"PASS >=900" if mbps >= 900 else "FAIL <900"}')
        print(f'loss events: {loss_events}')
        print(f'lost ~     : {lost_est} pkts')
        if bursts:
            print('bursts     :', '; '.join(bursts[:8]))
        print(f'bad length : {plen_err}')
        print(f'bad payload: {pay_err}')
        verdict = (mbps >= 900 and loss_events == 0 and plen_err == 0 and pay_err == 0)
        print(f'G6 verdict : {"PASS" if verdict else "FAIL"}')


if __name__ == '__main__':
    main()
