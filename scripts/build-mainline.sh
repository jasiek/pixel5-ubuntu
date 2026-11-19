#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build the mainline kernel (P6): external/linux-next + kernel/mainline/series.
#   scripts/build-mainline.sh     -> build/mainline/out/arch/arm64/boot/Image
#                                    and .../dts/qcom/sm7250-google-redfin.dtb
# Our DTS files (kernel/mainline/dts/) are copied into the worktree each run.
# MODULES=1 also builds and installs the modules (see below).
# The submodule is never patched: the series is applied with `git am` in a
# worktree at build/mainline/src (one commit per patch, so failures bisect),
# rebuilt only when the stamp of (pin, series, patch files) changes.
# The worktree's .git points at the container path (/work/...; git 2.43 has
# no relative worktree paths), so inspect it inside the container:
#   scripts/dev.sh git -c safe.directory='*' -C /work/build/mainline/src log
set -euo pipefail

if [ ! -f /.dockerenv ]; then
    DEV_CROSS=1 DEV_DOCKER_ARGS="-e MODULES" exec "$(dirname "$0")/dev.sh" /work/scripts/build-mainline.sh "$@"
fi

BASE=/work/external/linux-next
SRC=/work/build/mainline/src
OUT=/work/build/mainline/out
SERIES=/work/kernel/mainline/series
FRAG=/work/kernel/mainline/redfin.config
G=(git -c safe.directory='*')
mkdir -p "$OUT" /work/build/ccache
export CCACHE_DIR=/work/build/ccache

patch_path() {   # <source> <path>
    case "$1" in
        nairo) echo "/work/external/nairo/kernel/patches/$2" ;;
        local) echo "/work/kernel/mainline/patches/$2" ;;
        *) echo "unknown source '$1' in series" >&2; exit 1 ;;
    esac
}
mapfile -t entries < <(grep -v -e '^#' -e '^[[:space:]]*$' "$SERIES")

pin=$("${G[@]}" -C "$BASE" rev-parse HEAD)
stamp=$( { echo "$pin"; cat "$SERIES"
           for e in "${entries[@]}"; do cat "$(patch_path $e)"; done; } | sha256sum | cut -c1-16)
if [ "$(cat "$SRC/.pixel5-stamp" 2>/dev/null)" != "$stamp" ]; then
    echo "preparing source tree (stamp $stamp)"
    rm -rf "$SRC"
    "${G[@]}" -C "$BASE" worktree prune
    "${G[@]}" -C "$BASE" worktree add -q --detach "$SRC" "$pin"
    # Fixed committer date: the same series gives the same commit hashes,
    # so the kernel release (-g<hash>) and its module directory only change
    # when the series does.
    export GIT_COMMITTER_NAME=pixel5 GIT_COMMITTER_EMAIL=pixel5@localhost
    GIT_COMMITTER_DATE=$("${G[@]}" -C "$BASE" log -1 --format=%cI "$pin")
    export GIT_COMMITTER_DATE
    for e in "${entries[@]}"; do
        p=$(patch_path $e)
        "${G[@]}" -C "$SRC" am -q --3way "$p" || {
            echo "FAILED to apply: $e" >&2; "${G[@]}" -C "$SRC" am --abort; exit 1; }
    done
    echo "$stamp" > "$SRC/.pixel5-stamp"
    echo "applied ${#entries[@]} patches"
fi

ARGS=(-C "$SRC" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 CC="ccache clang"
      KBUILD_BUILD_USER=pixel5 KBUILD_BUILD_HOST=build)

make "${ARGS[@]}" defconfig
(cd "$OUT" && "$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$FRAG" >/dev/null)
make "${ARGS[@]}" olddefconfig

missing=0
while IFS= read -r line; do
    case "$line" in
        CONFIG_*=*) grep -qxF "$line" "$OUT/.config" || { echo "WARN not applied: $line"; missing=1; } ;;
    esac
done < "$FRAG"
[ $missing = 0 ] && echo "fragment: all options applied"

DTS=arch/arm64/boot/dts/qcom
cp /work/kernel/mainline/dts/*.dts* "$SRC/$DTS/"
# Battery OCV tables come from the phone's own DT (vendor data: generated
# here, never committed). firmware/live.dts is made in P1 (see docs/log.md).
[ -f /work/firmware/live.dts ] || { echo "firmware/live.dts missing (battery OCV tables)" >&2; exit 1; }
python3 -I /work/scripts/gen-battery-ocv.py /work/firmware/live.dts > "$SRC/$DTS/sm7250-google-redfin-battery-ocv.dtsi"
make "${ARGS[@]}" -j"$(nproc)" Image qcom/sm7250-google-redfin.dtb "$@"
# MODULES=1: also build the modules and install them (stripped) to
# build/mainline/out/modules-install/lib/modules/<release>.
if [ "${MODULES:-0}" = 1 ]; then
    make "${ARGS[@]}" -j"$(nproc)" modules
    rm -rf "$OUT/modules-install"
    make "${ARGS[@]}" INSTALL_MOD_PATH="$OUT/modules-install" INSTALL_MOD_STRIP=1 modules_install >/dev/null
    echo "modules: $(find "$OUT/modules-install" -name '*.ko*' | wc -l) installed"
fi
# The dtbo sink only works if real labels are not exported (no dtc -@):
# __symbols__ must hold exactly the sink's own entries.
DTB=$OUT/$DTS/sm7250-google-redfin.dtb
nsym=$(fdtget -p "$DTB" /__symbols__ | wc -l)
nsink=$(grep -c '= "/redfin-dtbo-sink/' "$SRC/$DTS/sm7250-google-redfin-dtbo-sink.dtsi")
[ "$nsym" = "$nsink" ] || { echo "DTB exports $nsym symbols, sink has $nsink (built with -@?)" >&2; exit 1; }
echo "dtb: $(stat -c %s "$DTB") bytes, $nsym symbols (all sink)"
echo "mainline $(cat "$OUT/include/config/kernel.release")"
ls -la "$OUT/arch/arm64/boot/Image"
