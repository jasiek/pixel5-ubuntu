#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Pack a mainline test boot image (P6.2 T1): header v2 with our DTB, for
# `fastboot boot` only (writes nothing on the phone).
#   scripts/build-mainline-test.sh t1   -> build/boot-mainline-t1.img
# t1: the initramfs is one static program that reboots into the bootloader.
#     Back in fastboot = the kernel reached userspace and PON reboot-mode
#     works. Back in Ubuntu instead = panic (panic=10) or no reboot-mode:
#     androidboot.bootreason tells which. No earlycon (no UART).
# Needs scripts/build-mainline.sh first.
set -euo pipefail

if [ ! -f /.dockerenv ]; then
    exec "$(dirname "$0")/dev.sh" /work/scripts/build-mainline-test.sh "$@"
fi
TEST=${1:?usage: build-mainline-test.sh t1}
OUT=/work/build/mainline/out
T=/work/build/mainline/$TEST
rm -rf "$T"; mkdir -p "$T"
# The initramfs tree lives in the container (no mknod on the shared volume).
R=$(mktemp -d); mkdir -p "$R/dev"

# Kernel: Google's bootloader checks the header text_offset (Heidelberg
# U-Boot 338dbbba87); mainline writes 0 there and never reads it.
cp "$OUT/arch/arm64/boot/Image" "$T/Image"
python3 -I - "$T/Image" <<'PY'
import struct, sys
p = sys.argv[1]
with open(p, "r+b") as f:
    h = f.read(64)
    assert h[56:60] == b"ARMd", "not an arm64 Image"
    f.seek(8); f.write(struct.pack("<Q", 0x80000))
PY
# LZ4 frame format, like the downstream Image.lz4: ABL refuses legacy
# LZ4 ("Error verifying the received boot.img: Unsupported", Test 29).
lz4 -q -f -12 --favor-decSpeed "$T/Image" "$T/Image.lz4"

case "$TEST" in
t1)
    gcc -static -Os -s -o "$R/reboot-bootloader" /work/initramfs/reboot-bootloader.c
    mknod -m 600 "$R/dev/console" c 5 1
    CMD="rdinit=/reboot-bootloader panic=${PANIC:--1} clk_ignore_unused pd_ignore_unused"
    ;;
*) echo "unknown test $TEST" >&2; exit 2 ;;
esac
(cd "$R" && find . | sort | cpio -o -H newc --quiet | gzip -9) > "$T/initramfs.cpio.gz"
rm -rf "$R"

VENDOR_CMDLINE=0 /work/scripts/make-bootimg-v2.sh \
    "${T#/work/}/Image.lz4" "${T#/work/}/initramfs.cpio.gz" \
    build/mainline/out/arch/arm64/boot/dts/qcom/sm7250-google-redfin.dtb \
    "build/boot-mainline-$TEST.img" "$CMD"
