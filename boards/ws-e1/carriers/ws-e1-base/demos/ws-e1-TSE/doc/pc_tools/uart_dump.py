#!/usr/bin/env python3
"""uart_dump.py - UART 抓取（打印 + 存档）
用法: uv run --with pyserial uart_dump.py [seconds] [port] [baud] [outfile]
默认: 20s COM8 115200 uart_dump.txt
"""
import sys
import time
import serial

def main():
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 20.0
    port = sys.argv[2] if len(sys.argv) > 2 else "COM8"
    baud = int(sys.argv[3]) if len(sys.argv) > 3 else 115200
    out = sys.argv[4] if len(sys.argv) > 4 else "uart_dump.txt"
    ser = serial.Serial(port, baud, timeout=0.2)
    t0 = time.time()
    buf = []
    print(f"[uart_dump] {port}@{baud} for {secs}s")
    while time.time() - t0 < secs:
        data = ser.read(4096)
        if data:
            text = data.decode(errors="replace")
            buf.append(text)
            print(text, end="", flush=True)
    ser.close()
    with open(out, "w", encoding="utf-8") as f:
        f.write("".join(buf))
    print(f"\n[uart_dump] saved {out} ({sum(len(b) for b in buf)} chars)")

if __name__ == "__main__":
    main()
