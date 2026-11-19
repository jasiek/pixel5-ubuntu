#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build the downstream 4.19 kernel (LineageOS redbull) with our fragment.
#   scripts/build-kernel.sh            -> build/kernel/arch/arm64/boot/Image.lz4
# Out-of-tree build (O=build/kernel); the submodule stays clean.
set -euo pipefail

if [ ! -f /.dockerenv ]; then
    DEV_CROSS=1 exec "$(dirname "$0")/dev.sh" /work/scripts/build-kernel.sh "$@"
fi

SRC=/work/external/kernel-redbull
OUT=/work/build/kernel
FRAG=/work/kernel/redfin-ubuntu.config
mkdir -p "$OUT" /work/build/ccache
export CCACHE_DIR=/work/build/ccache

ARGS=(-C "$SRC" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 CC="ccache clang"
      KBUILD_BUILD_USER=pixel5 KBUILD_BUILD_HOST=build)
if [ "$(uname -m)" != aarch64 ]; then
    ARGS+=(CROSS_COMPILE=aarch64-linux-gnu-)
fi

make "${ARGS[@]}" redbull_defconfig
# merge_config.sh writes sed temp files into the current directory; run it
# inside $OUT so none land in the repo (Pixel 2 lesson).
(cd "$OUT" && "$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$FRAG" >/dev/null)
make "${ARGS[@]}" olddefconfig

# Every fragment line that did not survive olddefconfig, so nothing is
# silently dropped.
missing=0
while IFS= read -r line; do
    case "$line" in
        CONFIG_*=*) grep -qxF "$line" "$OUT/.config" || { echo "WARN not applied: $line"; missing=1; } ;;
        "# CONFIG_"*" is not set")
            opt=${line#\# }; opt=${opt%% *}
            grep -q "^$opt=" "$OUT/.config" && { echo "WARN still set: $opt"; missing=1; } ;;
    esac
done < "$FRAG"
[ $missing = 0 ] && echo "fragment: all options applied"

make "${ARGS[@]}" -j"$(nproc)" Image.lz4 modules
rm -rf "$OUT/modules-install"
make "${ARGS[@]}" INSTALL_MOD_PATH="$OUT/modules-install" INSTALL_MOD_STRIP=1 modules_install >/dev/null
echo "kernel $(cat "$OUT/include/config/kernel.release"): $(find "$OUT/modules-install" -name '*.ko' | wc -l) modules"
ls -la "$OUT/arch/arm64/boot/Image.lz4"
