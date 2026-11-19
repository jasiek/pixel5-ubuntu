#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run a command on the phone's USB serial console (ACM, /dev/cu.usbmodempixel5*).

    scripts/serial-sh.py 'dmesg | tail'

Works with the initramfs debug shell and (later) the Ubuntu autologin getty.
No pyserial needed: plain termios.
"""
import glob
import os
import sys
import termios
import time

MARK = "__PIXEL5_DONE__"


def open_port():
    ports = sorted(glob.glob("/dev/cu.usbmodempixel5*"))
    if not ports:
        sys.exit("no /dev/cu.usbmodempixel5* serial port (phone not in our system?)")
    fd = os.open(ports[-1], os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0                                   # iflag
    attrs[1] = 0                                   # oflag
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0                                   # lflag: raw
    attrs[4] = attrs[5] = termios.B115200
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    return fd


def read_until(fd, needle, timeout):
    buf, end = b"", time.time() + timeout
    while time.time() < end:
        try:
            chunk = os.read(fd, 65536)
            if chunk:
                buf += chunk
                if needle in buf:
                    break
                continue
        except BlockingIOError:
            pass
        time.sleep(0.05)
    return buf


def main():
    cmd = " ".join(sys.argv[1:]) or "uname -a"
    timeout = float(os.environ.get("TIMEOUT", "60"))
    fd = open_port()
    os.write(fd, b"\n")
    read_until(fd, b"#", 2)                        # flush prompt / banner
    os.write(fd, f"stty -echo 2>/dev/null; {cmd}; echo __PIXEL5_''DONE__\n".encode())
    out = read_until(fd, MARK.encode(), timeout).decode(errors="replace").replace("\r", "")
    os.close(fd)
    lines = [l for l in out.split("\n") if MARK not in l and "__PIXEL5_''DONE__" not in l]
    sys.stdout.write("\n".join(lines).strip("\n") + "\n")


if __name__ == "__main__":
    main()
