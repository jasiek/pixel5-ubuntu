#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Pack a header-v3 boot.img for redfin: kernel + our ramdisk, with every other
# field (header version, os_version, os_patch_level, cmdline) copied from the
# factory boot.img, so nothing walleye-style is hardcoded.
#
#   scripts/make-bootimg.sh <kernel Image.lz4|stock> <ramdisk.cpio.lz4> <out.img> [extra cmdline]
#     kernel "stock" = the factory boot.img's own kernel (Phase 2).
#   AVB_FOOTER=1 adds an AVB hash footer (P1.10 decides whether it is needed).
#
# On redfin the DTB, vendor ramdisk and most of the cmdline come from the
# flashed vendor_boot; this image only carries kernel + generic ramdisk.
set -euo pipefail

if [ ! -f /.dockerenv ]; then
    exec "$(dirname "$0")/dev.sh" /work/scripts/make-bootimg.sh "$@"
fi
[ $# -ge 3 ] || { sed -n '3,13p' "$0"; exit 2; }
KERNEL=$1 RAMDISK=/work/$2 OUT=/work/$3 EXTRA=${4:-}

MKB=/work/external/mkbootimg
STOCK=${STOCK_BOOT:-/work/firmware/boot.img}   # STOCK_BOOT: test with a synthetic image
ST=/work/build/stock-boot
rm -rf "$ST"; mkdir -p "$ST"
python3 "$MKB/unpack_bootimg.py" --boot_img "$STOCK" --out "$ST" >"$ST/info.txt"
grep -E 'header version|os version|os patch level|command line' "$ST/info.txt" >&2

# --format=mkbootimg prints the arguments that rebuild the stock image.
eval "set -- $(python3 "$MKB/unpack_bootimg.py" --boot_img "$STOCK" --out "$ST" --format=mkbootimg)"
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --kernel) shift; [ "$KERNEL" = stock ] && args+=(--kernel "$1") || args+=(--kernel "/work/$KERNEL") ;;
        --ramdisk) shift; args+=(--ramdisk "$RAMDISK") ;;
        --cmdline) shift; args+=(--cmdline "${1:+$1 }$EXTRA") ;;
        *) args+=("$1") ;;
    esac
    shift
done
# A stock image without a cmdline field still gets our extra arguments.
printf '%s\n' "${args[@]}" | grep -qx -- --cmdline || args+=(--cmdline "$EXTRA")

python3 "$MKB/mkbootimg.py" "${args[@]}" --output "$OUT"
if [ "${AVB_FOOTER:-0}" = 1 ]; then
    python3 /work/external/avb/avbtool.py add_hash_footer --image "$OUT" \
        --partition_name boot --partition_size 100663296
fi
ls -la "$OUT"
