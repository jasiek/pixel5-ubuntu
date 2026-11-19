#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build pd-mapper and tqftpserv (external/, BSD-3-Clause, linux-msm) for the
# rootfs: noble has no pd-mapper, and its tqftpserv 1.0 can't serve
# /readonly/vendor/firmware/ (where the modem asks for wlanmdsp.mbn).
# Dynamically linked against noble's libqrtr1, liblzma5, libzstd1.
#   scripts/build-qcom-daemons.sh   -> build/qcom/{pd-mapper,tqftpserv}
set -euo pipefail
if [ ! -f /.dockerenv ]; then
    exec "$(dirname "$0")/dev.sh" /work/scripts/build-qcom-daemons.sh "$@"
fi
OUT=/work/build/qcom
mkdir -p "$OUT"
P=/work/external/pd-mapper
gcc -Wall -O2 -o "$OUT/pd-mapper" \
    "$P"/pd-mapper.c "$P"/assoc.c "$P"/json.c "$P"/servreg_loc.c "$P"/lzma_decomp.c \
    -lqrtr -llzma
T=/work/external/tqftpserv
gcc -Wall -O2 -DHAVE_XZ -DHAVE_ZSTD -o "$OUT/tqftpserv" \
    "$T"/tqftpserv.c "$T"/translate.c "$T"/xz-decompress.c "$T"/zstd-decompress.c \
    -lqrtr -llzma -lzstd
file "$OUT"/pd-mapper "$OUT"/tqftpserv | cut -c1-90
