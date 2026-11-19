#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copy one file from the initramfs debug shell (172.16.42.1) to the Mac,
# checked with SHA-256 on both ends.
#
#   scripts/initrd-pull.sh <path on phone> <local file>
#
# Same nc method as backup-nv.sh: the phone-side listener needs setsid and a
# short wait, or it dies with the telnet session.
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -eq 2 ] || { echo "usage: $0 <remote path> <local file>" >&2; exit 2; }
remote=$1; local_file=$2
PHONE=172.16.42.1
PORT=5001

# Sysfs files report size 4096 or 0; copy to /tmp first for a real size.
info=$(scripts/initrd-sh.py "cat '$remote' > /tmp/pull.bin && echo \"INFO \$(wc -c < /tmp/pull.bin) \$(sha256sum < /tmp/pull.bin | cut -d' ' -f1)\"" \
       | tr -d '\r' | sed -n 's/^INFO //p' | tail -n1)
[ -n "$info" ] || { echo "$remote: could not read on the phone" >&2; exit 1; }
read -r bytes sum <<< "$info"
scripts/initrd-sh.py "setsid nc -l -p $PORT < /tmp/pull.bin >/dev/null 2>&1 & sleep 1" >/dev/null
mkdir -p "$(dirname "$local_file")"
nc "$PHONE" "$PORT" | head -c "$bytes" > "$local_file" || true
got=$(shasum -a 256 "$local_file" | cut -d' ' -f1)
[ "$got" = "$sum" ] || { echo "$remote: SHA-256 mismatch" >&2; exit 1; }
scripts/initrd-sh.py "rm -f /tmp/pull.bin" >/dev/null
echo "$remote -> $local_file ($bytes bytes, SHA-256 ok)"
