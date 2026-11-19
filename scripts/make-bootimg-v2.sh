#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Pack a header-v2 boot.img that carries its own DTB (P6.2, option (a) in
# docs/research/mainline-boot.md). With v2 the bootloader loads no
# vendor_boot: no vendor ramdisk and no vendor cmdline, so the stock vendor
# cmdline is copied into this image's cmdline. os_version/patch level come
# from the factory boot.img. Always gets an AVB hash footer (redfin's
# unlocked bootloader refuses boot images without one).
#
#   scripts/make-bootimg-v2.sh <kernel> <ramdisk.cpio.lz4> <dtb> <out.img> [extra cmdline]
#   VENDOR_CMDLINE=0: leave out the stock vendor cmdline (mainline kernels).
set -euo pipefail

if [ ! -f /.dockerenv ]; then
    exec "$(dirname "$0")/dev.sh" /work/scripts/make-bootimg-v2.sh "$@"
fi
[ $# -ge 4 ] || { sed -n '3,12p' "$0"; exit 2; }
KERNEL=/work/$1 RAMDISK=/work/$2 DTB=/work/$3 OUT=/work/$4 EXTRA=${5:-}
MKB=/work/external/mkbootimg
T=/work/build/v2-unpack
rm -rf "$T"; mkdir -p "$T/boot" "$T/vboot"
info() { python3 "$MKB/unpack_bootimg.py" --boot_img "$1" --out "$2"; }
osv=$(info /work/firmware/boot.img "$T/boot" | sed -n 's/^os version: //p')
ospl=$(info /work/firmware/boot.img "$T/boot" | sed -n 's/^os patch level: //p')
vcmd=$(info /work/firmware/vendor_boot.img "$T/vboot" | sed -n 's/^vendor command line args: //p')
[ "${VENDOR_CMDLINE:-1}" = 1 ] || vcmd=""
cmd="$vcmd${vcmd:+${EXTRA:+ }}$EXTRA"
[ ${#cmd} -le 1536 ] || { echo "cmdline ${#cmd} > 1536 bytes (v2 limit)" >&2; exit 1; }
echo "v2: os $osv / $ospl, cmdline ${#cmd} bytes (vendor ${#vcmd})" >&2
python3 "$MKB/mkbootimg.py" --header_version 2 --pagesize 4096 --base 0 \
    --kernel_offset 0x8000 --ramdisk_offset 0x01000000 --tags_offset 0x100 \
    --dtb_offset 0x01f00000 --os_version "$osv" --os_patch_level "$ospl" \
    --kernel "$KERNEL" --ramdisk "$RAMDISK" --dtb "$DTB" --cmdline "$cmd" \
    --output "$OUT"
python3 /work/external/avb/avbtool.py add_hash_footer --image "$OUT" \
    --partition_name boot --partition_size 100663296
ls -la "$OUT"
