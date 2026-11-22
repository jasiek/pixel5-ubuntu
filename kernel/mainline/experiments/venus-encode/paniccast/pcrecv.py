#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# usage: pcrecv.py <outfile> [seconds]  - receive paniccast UDP broadcasts, reassemble the log tail
import socket, sys, time, struct
out = sys.argv[1]; dur = float(sys.argv[2]) if len(sys.argv) > 2 else 600
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try: s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
except Exception: pass
s.bind(('', 6666)); s.settimeout(1)
chunks = {}; total = 0; end = time.time() + dur; last = None; n = 0
while time.time() < end:
    try: d, a = s.recvfrom(4096)
    except socket.timeout:
        if last and time.time() - last > 5: break
        continue
    off, tot = struct.unpack('>II', d[:8]); chunks[off] = d[8:]; total = tot; last = time.time(); n += 1
    if n == 1: open(out + '.t', 'w').write(time.strftime('%H:%M:%S first packet\n'))
buf = bytearray(b'?' * total)
for off, c in chunks.items(): buf[off:off+len(c)] = c
open(out, 'wb').write(bytes(buf))
print(f"packets {n} chunks {len(chunks)} total {total} got {sum(len(c) for c in chunks.values())}")
