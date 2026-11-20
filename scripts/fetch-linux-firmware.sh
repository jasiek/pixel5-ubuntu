#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Fetch the few linux-firmware files the mainline kernel needs into
# build/linux-firmware/ (gitignored), pinned by commit and SHA-256.
#   scripts/fetch-linux-firmware.sh
# ath10k/WCN3990/hw1.0/firmware-5.bin: ath10k's host-side API file for the
# WCN3990 (60 bytes of feature flags; the WLAN firmware itself runs in the
# modem). WHENCE: "Licence: Redistributable. See
# LICENSE.QualcommAtheros_ath10k". The board file is the phone's own
# bdwlan-redfin.bin (symlink in the rootfs overlay).
# qcom/a650_sqe.fw: the A620's CP microcode. The vendor copy is version 93,
# mainline msm needs >= 95 (Test 98); msm tries qcom/ before the vendor
# file on firmware_class.path. WHENCE: "Licence: Redistributable. See
# LICENSE.qcom and NOTICE.qcom".
set -euo pipefail
cd "$(dirname "$0")/.."
COMMIT=73e8acec66b0a91513e0699567b7854f4161d8b5
BASE=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain
FILES=(
    "ath10k/WCN3990/hw1.0/firmware-5.bin fef6539e0127579536bc977be57a90d018b83f2931fedc3a8870fbe38d6c4127"
    "qcom/a650_sqe.fw c863ceac3a823af215205d7803776bfdc68098c2c2a5d2fd05b4aa77cd336b4b"
)
for e in "${FILES[@]}"; do
    f=${e% *} sum=${e#* }
    out=build/linux-firmware/$f
    if [ -f "$out" ] && echo "$sum  $out" | shasum -a 256 -c --status; then
        continue
    fi
    mkdir -p "$(dirname "$out")"
    curl -sSfL -o "$out.tmp" "$BASE/$f?id=$COMMIT"
    echo "$sum  $out.tmp" | shasum -a 256 -c --status || { echo "checksum mismatch: $f" >&2; rm -f "$out.tmp"; exit 1; }
    mv "$out.tmp" "$out"
    echo "fetched $f"
done
echo "linux-firmware files ok (commit ${COMMIT:0:12})"
