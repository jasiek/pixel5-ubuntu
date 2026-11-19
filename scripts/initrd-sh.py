#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run a shell command in the phone's initramfs debug shell (telnet, port 23).

    scripts/initrd-sh.py 'cat /tmp/init.log'
    scripts/initrd-sh.py 'cat /sys/fs/pstore/console-ramoops*' > build/last_kmsg.txt

macOS no longer ships telnet; this speaks just enough of the protocol
(refuses every option) to drive busybox telnetd.
"""
import socket
import sys
import time

HOST, PORT = "172.16.42.1", 23
IAC, DONT, DO, WONT, WILL, SB, SE = 255, 254, 253, 252, 251, 250, 240
MARK = "__PIXEL5_DONE__"


def strip_telnet(sock, data):
    out, i = bytearray(), 0
    while i < len(data):
        b = data[i]
        if b == IAC and i + 1 < len(data):
            cmd = data[i + 1]
            if cmd in (DO, DONT, WILL, WONT) and i + 2 < len(data):
                opt = data[i + 2]
                sock.sendall(bytes([IAC, WONT if cmd in (DO, DONT) else DONT, opt]))
                i += 3
                continue
            if cmd == SB:
                end = data.find(bytes([IAC, SE]), i)
                i = len(data) if end < 0 else end + 2
                continue
            i += 2
            continue
        out.append(b)
        i += 1
    return bytes(out)


def main():
    cmd = " ".join(sys.argv[1:]) or "uname -a"
    timeout = float(__import__("os").environ.get("TIMEOUT", "60"))
    s = socket.create_connection((HOST, PORT), timeout=10)
    s.settimeout(1)
    time.sleep(0.5)
    try:
        strip_telnet(s, s.recv(65536))
    except socket.timeout:
        pass
    # Quote-split marker: the echoed command line never contains MARK itself.
    s.sendall(f"stty -echo 2>/dev/null; {cmd}; echo __PIXEL5_''DONE__\n".encode())
    buf, deadline = b"", time.time() + timeout
    while time.time() < deadline:
        try:
            chunk = s.recv(65536)
        except socket.timeout:
            continue
        if not chunk:
            break
        buf += strip_telnet(s, chunk)
        if MARK.encode() + b"\r\n" in buf or buf.rstrip().endswith(MARK.encode()):
            break
    s.close()
    text = buf.decode(errors="replace").replace("\r", "")
    # Drop the echoed command line (if any) and the end marker.
    lines = [l for l in text.split("\n") if MARK not in l and "__PIXEL5_''DONE__" not in l]
    sys.stdout.write("\n".join(lines).strip("\n") + "\n")


if __name__ == "__main__":
    main()
