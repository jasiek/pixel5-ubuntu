#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build the initramfs: static busybox + initramfs/init -> build/initramfs.cpio.lz4
#   scripts/build-initramfs.sh [init-script] [output]   (e.g. initramfs/probe-init build/initramfs-probe.cpio.lz4)
#
# LZ4 *legacy* format (lz4 -l), like the stock boot ramdisk. The bootloader
# puts the vendor ramdisk (LZ4 legacy) in front of ours, and the kernel's
# legacy LZ4 decoder only accepts more LZ4 legacy after it: a gzip archive
# there fails with "Decoding failed" and is silently dropped, so the vendor's
# recovery /init runs instead of ours (Test 1, Test 2).
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
OUTF="/work/${2:-build/initramfs.cpio.lz4}"
(cd "$T" && find . | sort | cpio -o -H newc --quiet | lz4 -l -9 -c) > "$OUTF"
rm -rf "$T"
ls -la "$OUTF"
