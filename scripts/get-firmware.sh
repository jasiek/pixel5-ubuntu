#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unpack the Pixel 5 factory image that the build and flashing need -> firmware/
#
#   scripts/get-firmware.sh
#
# The owner downloads the zip once (Google's terms must be accepted on the
# page, so this script does not fetch it):
#   https://developers.google.com/android/images#redfin
#   -> redfin-up1a.231105.001.b2-factory-<sha8>.zip into firmware/
# Optional: FACTORY_SHA256=<full hash from the page> for a full check.
#
# - firmware/<build>/        flash-all.sh, bootloader, radio, image zip (restore)
# - firmware/{boot,vendor_boot,dtbo,vbmeta}.img   for boot images and flashing
# - firmware/vendor.img      firmware lists / wifi board data (if in the zip)
# Proprietary Google files: firmware/ is gitignored, never commit it.
set -euo pipefail
cd "$(dirname "$0")/.."

# Final redfin release (Android 14, Feb 2024), see docs/research/bootchain.md.
BUILD=redfin-up1a.231105.001.b2
WANT="boot.img vendor_boot.img dtbo.img vbmeta.img"

have_all() { for f in $WANT; do [ -f "firmware/$f" ] || return 1; done; [ -f "firmware/$BUILD/flash-all.sh" ]; }
if have_all; then echo "firmware: up to date ($BUILD)"; exit 0; fi

mkdir -p firmware
shopt -s nullglob
zips=(firmware/"$BUILD"-factory-*.zip)
if [ ${#zips[@]} -ne 1 ]; then
    echo "Need exactly one firmware/$BUILD-factory-*.zip (found ${#zips[@]})." >&2
    echo "Download it from https://developers.google.com/android/images#redfin" >&2
    echo "(accept Google's terms there) and put it in firmware/." >&2
    exit 1
fi
ZIP=${zips[0]}

echo "Checking SHA-256 of $ZIP"
got=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
# Google's file name carries the first 8 hex digits of the SHA-256.
sha8=${ZIP##*-factory-}; sha8=${sha8%.zip}
if [ "${got:0:8}" != "$sha8" ]; then
    echo "ERROR: SHA-256 $got does not start with $sha8 (from the file name)." >&2
    exit 1
fi
if [ -n "${FACTORY_SHA256:-}" ] && [ "$got" != "$FACTORY_SHA256" ]; then
    echo "ERROR: SHA-256 mismatch: got $got, expected $FACTORY_SHA256." >&2
    exit 1
fi
echo "SHA-256 $got"

unzip -o -q "$ZIP" -d firmware/
IMG="firmware/$BUILD/image-$BUILD.zip"
unzip -o -q -j "$IMG" $WANT -d firmware/
# vendor is normally its own image in factory zips (fastboot builds super
# from super_empty.img); fall back to listing what is there.
if unzip -l "$IMG" vendor.img >/dev/null 2>&1; then
    unzip -o -q -j "$IMG" vendor.img -d firmware/
else
    echo "NOTE: no vendor.img in $IMG; contents:"; unzip -l "$IMG"
fi
ls -la firmware/*.img "firmware/$BUILD/flash-all.sh"
