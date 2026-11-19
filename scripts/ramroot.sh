#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# P3.3: boot the Ubuntu rootfs from RAM, tethered, without flashing userdata.
#
#   scripts/ramroot.sh            (phone in the initramfs debug shell, 172.16.42.1)
#
# Unpacks build/rootfs-final.tar (scripts/build-rootfs.sh) into a tmpfs on
# /newroot, drops the userdata line from its fstab (root is the tmpfs), and
# touches /tmp/switch: init's debug shell then hands over to systemd exactly
# as a normal boot would. Nothing is written to the phone's storage; a
# reboot forgets it all.
set -euo pipefail
cd "$(dirname "$0")/.."
PHONE=172.16.42.1
PORT=5002
TAR=build/rootfs-final.tar
[ -f "$TAR" ] || { echo "no $TAR: run scripts/build-rootfs.sh" >&2; exit 1; }

sh() { scripts/initrd-sh.py "$1" | tr -d '\r'; }

# (no mountpoint applet in this busybox)
sh 'touch /tmp/keep; grep -q " /newroot " /proc/mounts || mount -t tmpfs -o size=4g,mode=0755 tmpfs /newroot' >/dev/null
# Listener in the foreground of a telnet session held open here (see
# initrd-pull.sh); macOS nc -w closes 5 s after the tar is sent.
TIMEOUT=900 scripts/initrd-sh.py "nc -l -p $PORT | tar -x -C /newroot; echo TAR_RC=\$?" > build/ramroot-tar.log 2>&1 &
lpid=$!
sleep 2
echo "sending $(du -h "$TAR" | cut -f1) ..."
nc -w 5 "$PHONE" "$PORT" < "$TAR"
wait "$lpid" || true
grep -q 'TAR_RC=0' build/ramroot-tar.log || { echo "tar on the phone failed:" >&2; tail -5 build/ramroot-tar.log >&2; exit 1; }

# Root is the tmpfs: no userdata mount, no growfs.
sh "sed -i 's|^/dev/disk/by-partlabel/userdata|# RAM test: &|' /newroot/etc/fstab; du -sh /newroot | cut -f1; ls -l /newroot/sbin/init" | grep -E '^[0-9.]+[MG]|init'
sh 'echo tmpfs > /tmp/switch' >/dev/null
echo "switching to systemd; waiting for ssh ..."
for i in $(seq 1 90); do
    if scripts/ssh.sh true 2>/dev/null; then
        echo "ssh works after ~$((i * 2)) s"; exit 0
    fi
    sleep 2
done
echo "no ssh after 3 min" >&2; exit 1
