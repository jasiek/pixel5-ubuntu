#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build qbootctl (external/qbootctl, linux-msm) -> build/qbootctl/qbootctl
# Static, so it runs whatever the rootfs glibc is.
# Used by pixel5-boot-successful.service to mark the A/B slot successful;
# otherwise the bootloader counts down the retry counter on every boot and
# finally marks the slot "unbootable: load error".
set -euo pipefail
if [ ! -f /.dockerenv ]; then
    exec "$(dirname "$0")/dev.sh" /work/scripts/build-qbootctl.sh "$@"
fi
SRC=/work/external/qbootctl
OUT=/work/build/qbootctl
mkdir -p "$OUT"
gcc -std=gnu11 -O2 -static -I"$SRC" -o "$OUT/qbootctl" \
    "$SRC"/qbootctl.c "$SRC"/bootctrl_impl.c "$SRC"/gpt-utils.c "$SRC"/ufs-bsg.c "$SRC"/crc32.c
file "$OUT/qbootctl"
