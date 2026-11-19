#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build the initramfs: static busybox + initramfs/init -> build/initramfs.cpio.gz
#   scripts/build-initramfs.sh [init-script] [output]   (e.g. initramfs/probe-init build/initramfs-probe.cpio.gz)
set -euo pipefail

if [ ! -f /.dockerenv ]; then
    exec "$(dirname "$0")/dev.sh" /work/scripts/build-initramfs.sh "$@"
fi

T=/tmp/initramfs
rm -rf "$T"; mkdir -p "$T"/{bin,dev,proc,sys,tmp,run,newroot}
cp /bin/busybox "$T/bin/busybox"
install -m 755 "/work/${1:-initramfs/init}" "$T/init"
# reboot-bootloader [arg]: reboot into fastboot (or recovery, ...).
gcc -static -Os -s -o "$T/bin/reboot-bootloader" /work/initramfs/reboot-bootloader.c
# The kernel needs /dev/console before devtmpfs is mounted.
mknod -m 600 "$T/dev/console" c 5 1
mknod -m 666 "$T/dev/null" c 1 3

mkdir -p /work/build
OUTF="/work/${2:-build/initramfs.cpio.gz}"
(cd "$T" && find . | sort | cpio -o -H newc --quiet | gzip -9) > "$OUTF"
rm -rf "$T"
ls -la "$OUTF"
