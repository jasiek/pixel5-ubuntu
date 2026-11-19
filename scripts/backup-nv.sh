#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# P2.4: back up the IMEI / calibration partitions from the initramfs debug
# shell (scripts/initrd-sh.py, phone at 172.16.42.1) to firmware/backup/.
#
#   scripts/backup-nv.sh [partition ...]   (default: persist modemst1 modemst2 fsg fsc)
#
# Read-only on the phone: each partition is found by PARTNAME, hashed there,
# streamed raw over nc, and hashed again on the Mac. Files are never
# committed (firmware/ is gitignored) and never leave the Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
PHONE=172.16.42.1
PORT=5000
OUT=firmware/backup
mkdir -p "$OUT"
chmod 700 "$OUT"

parts=("$@")
[ ${#parts[@]} -gt 0 ] || parts=(persist modemst1 modemst2 fsg fsc)

for p in "${parts[@]}"; do
    # "<dev> <bytes> <sha256>" from the phone (last matching line of output).
    info=$(scripts/initrd-sh.py "for u in /sys/class/block/*/uevent; do grep -q '^PARTNAME=$p\$' \$u && d=\$(sed -n 's/^DEVNAME=//p' \$u) && echo \"INFO \$d \$((\$(cat /sys/class/block/\$d/size)*512)) \$(sha256sum < /dev/\$d | cut -d' ' -f1)\"; done" \
           | tr -d '\r' | sed -n 's/^INFO //p' | tail -n1)
    [ -n "$info" ] || { echo "$p: not found on the phone" >&2; exit 1; }
    read -r dev bytes sum <<< "$info"

    # The phone-side listener runs in the foreground of a telnet session that
    # stays open (in the background here) until the copy is done. Detaching it
    # (setsid, &) was flaky: it died with the session after 1 KiB.
    TIMEOUT=900 scripts/initrd-sh.py "nc -l -p $PORT < /dev/$dev >/dev/null 2>&1" >/dev/null 2>&1 &
    lpid=$!
    sleep 2
    nc "$PHONE" "$PORT" | head -c "$bytes" > "$OUT/$p.img" || true
    wait "$lpid" || true
    got=$(shasum -a 256 "$OUT/$p.img" | cut -d' ' -f1)
    size=$(wc -c < "$OUT/$p.img" | tr -d ' ')
    if [ "$got" = "$sum" ] && [ "$size" = "$bytes" ]; then
        echo "$sum  $p.img" >> "$OUT/SHA256SUMS.new"
        echo "$p: $bytes bytes, SHA-256 matches"
    else
        echo "$p: MISMATCH (got $size bytes)" >&2
        exit 1
    fi
done
sort -u -k2 "$OUT/SHA256SUMS.new" > "$OUT/SHA256SUMS"
rm -f "$OUT/SHA256SUMS.new"
chmod 600 "$OUT"/*
