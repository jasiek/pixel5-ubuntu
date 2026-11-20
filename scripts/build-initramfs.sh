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
#
# KMODS=1: ship our own kernel's modules (scripts/build-kernel.sh) for the
# first-stage list, overriding the vendor ramdisk's (stock vermagic, won't
# load into our kernel). Same file names, so ours replace theirs when the
# ramdisks are merged. Load order: the vendor's modules.load
# (MODLOAD=build/stock/vbx/lib/modules/modules.load); dependencies and
# softdeps are generated from our modules with modinfo, flat /lib/modules
# paths as the vendor uses.
set -euo pipefail

if [ ! -f /.dockerenv ]; then
    exec "$(dirname "$0")/dev.sh" env KMODS="${KMODS:-0}" MODLOAD="${MODLOAD:-}" /work/scripts/build-initramfs.sh "$@"
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

if [ "${KMODS:-0}" = 1 ]; then
    KD=$(echo /work/build/kernel/modules-install/lib/modules/*)
    [ -d "$KD" ] || { echo "no modules: run scripts/build-kernel.sh" >&2; exit 1; }
    LOADLIST=/work/${MODLOAD:-build/stock/vbx/lib/modules/modules.load}
    if [ ! -f "$LOADLIST" ] && [ -z "${MODLOAD:-}" ]; then
        # The default list is the stock vendor ramdisk's: unpack it from the
        # factory vendor_boot.img (scripts/get-firmware.sh) on first use.
        V=/tmp/vendor_boot; rm -rf "$V"; mkdir -p "$V/x"
        python3 /work/external/mkbootimg/unpack_bootimg.py \
            --boot_img /work/firmware/vendor_boot.img --out "$V" >/dev/null
        for rd in "$V"/vendor_ramdisk*; do
            (cd "$V/x" && lz4 -dc "$rd" | cpio -id --quiet 'lib/modules/*' 2>/dev/null) || true
        done
        [ -f "$V/x/lib/modules/modules.load" ] && install -D -m 644 "$V/x/lib/modules/modules.load" "$LOADLIST"
    fi
    [ -f "$LOADLIST" ] || { echo "no $LOADLIST" >&2; exit 1; }
    M="$T/lib/modules"; mkdir -p "$M"
    # name (with "_") -> path in our build
    find "$KD" -name '*.ko' | while read -r f; do b=${f##*/}; echo "$(echo "${b%.ko}" | tr - _) $f"; done > /tmp/kmap
    path_of() { sed -n "s|^$(echo "$1" | tr - _) ||p" /tmp/kmap; }
    # Copy the list plus the closure of its hard dependencies.
    todo=$(cat "$LOADLIST")
    while [ -n "$todo" ]; do
        next=""
        for m in $todo; do
            n=${m##*/}; n=${n%.ko}
            src=$(path_of "$n"); [ -n "$src" ] || { echo "missing module $n" >&2; exit 1; }
            dst="$M/${src##*/}"
            [ -e "$dst" ] && continue
            llvm-strip --strip-debug -o "$dst" "$src"
            for d in $(modinfo -F depends "$src" | tr , ' '); do next="$next $d"; done
        done
        todo=$next
    done
    : > "$M/modules.dep"; : > "$M/modules.softdep"
    for f in "$M"/*.ko; do
        deps=""
        for d in $(modinfo -F depends "$f" | tr , ' '); do
            deps="$deps /lib/modules/$(basename "$(path_of "$d")")"
        done
        echo "/lib/modules/${f##*/}:$deps" >> "$M/modules.dep"
        modinfo -F softdep "$f" | while read -r sd; do
            [ -n "$sd" ] && echo "softdep $(modinfo -F name "$f") $sd" >> "$M/modules.softdep"
        done
    done
    cp "$LOADLIST" "$M/modules.load"
    echo "modules: $(ls "$M"/*.ko | wc -l) from $(basename "$KD"), $(wc -l < "$M/modules.softdep") softdeps"
fi

mkdir -p /work/build
OUTF="/work/${2:-build/initramfs.cpio.lz4}"
(cd "$T" && find . | sort | cpio -o -H newc --quiet | lz4 -l -9 -c) > "$OUTF"
rm -rf "$T"
ls -la "$OUTF"
