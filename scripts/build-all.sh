#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build everything the phone needs, from a fresh clone:
#   build/boot-mainline-default.img  mainline kernel + initramfs + DTB (boot_b)
#   build/rootfs.simg                Ubuntu 24.04 (userdata)
#   build/boot.img                   downstream 4.19 kernel (fallback, boot_b;
#                                    skipped with DOWNSTREAM=0)
#
#   scripts/build-all.sh                # only the steps whose inputs changed
#   FORCE=1 scripts/build-all.sh        # every step again
#   DOWNSTREAM=0 scripts/build-all.sh   # mainline only (no 4.19 kernel)
#
# Needs once, by hand: the factory zip in firmware/ (scripts/get-firmware.sh
# says which). Asks once for wifi (build/wifi.ssid + build/wifi.pass).
#
# Each step stores a hash of its inputs in build/.stamps/<step> and runs again
# when that hash changes or its output is missing. Hashes rather than mtimes:
# a fresh clone gives every file a new mtime, and the kernel trees are too big
# to scan (their submodule commits stand in for them; our patches are inputs).
# Cold run: about 1.5 h on an M-series Mac (two kernels; mainline modules
# alone ~35 min).
set -euo pipefail
cd "$(dirname "$0")/.."

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARN:\033[0m %s\n' "$*"; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
DOWNSTREAM=${DOWNSTREAM:-1}

# ---- 1. Prerequisites ------------------------------------------------------
say "1/5 Prerequisites"
scripts/check-prereqs.sh --build || die "Prerequisites missing (see FAIL lines above)."

# On an x86 Docker the kernels cross-compile (scripts/dev.sh, DEV_CROSS), but
# the initramfs, tools and rootfs are arm64 images: register qemu for them.
# Privileged, and only until the host reboots, so it is checked every run.
BINFMT=tonistiigi/binfmt:qemu-v10.2.3-68@sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0
arm64_runs() { docker run --rm --platform linux/arm64 ubuntu:24.04 true >/dev/null 2>&1; }
case "$(docker info --format '{{.Architecture}}')" in
    aarch64|arm64) ;;
    *) if ! arm64_runs; then
           echo "Registering qemu for arm64 containers ($BINFMT)"
           docker run --privileged --rm "$BINFMT" --install arm64 >/dev/null
           arm64_runs || die "arm64 containers still don't run after installing qemu binfmt."
       fi
       echo "arm64 containers: emulated (kernels cross-compile natively)" ;;
esac
mkdir -p build/.stamps

# ---- 2. Sources and firmware -----------------------------------------------
say "2/5 Sources and firmware"
# Only what this build uses. kernel-redbull is needed even for mainline: it
# holds the battery profile (scripts/build-mainline.sh).
SUBS=(external/linux-next external/nairo external/kernel-redbull external/mkbootimg
      external/avb external/qbootctl external/pd-mapper external/tqftpserv
      external/hexagonrpc)
# grep without -q: -q exits at the first match, git then dies of SIGPIPE and
# pipefail makes the test false exactly when a submodule is missing.
if git submodule status "${SUBS[@]}" | grep '^-' >/dev/null; then
    echo "Fetching submodules (shallow; linux-next and kernel-redbull are a few GB)."
    git submodule update --init "${SUBS[@]}"
fi
{ git submodule status "${SUBS[@]}" | grep '^+' || true; } | while read -r line; do
    warn "submodule not at the committed version: $line"
done
scripts/get-firmware.sh

# ---- 3. Wifi ---------------------------------------------------------------
# build/wifi.ssid + build/wifi.pass (gitignored, mode 600) become a wifi
# profile in the rootfs. An empty build/wifi.ssid means "no wifi, don't ask".
say "3/5 Wifi"
if [ ! -e build/wifi.ssid ]; then
    if [ -t 0 ]; then
        read -r -p "Wifi network name for the phone (empty = no wifi, USB only): " ssid
        ( umask 077; printf '%s' "$ssid" > build/wifi.ssid )
        if [ -n "$ssid" ]; then
            read -r -s -p "Wifi password: " pass; echo
            ( umask 077; printf '%s' "$pass" > build/wifi.pass )
        fi
        unset ssid pass
    else
        warn "No build/wifi.ssid and no terminal to ask: the phone gets no wifi profile."
    fi
fi
if [ -s build/wifi.ssid ] && [ -s build/wifi.pass ]; then
    echo "wifi: profile from build/wifi.ssid + build/wifi.pass (delete both to be asked again)"
elif [ -e build/wifi.ssid ]; then
    echo "wifi: none (delete build/wifi.ssid to be asked again)"
else
    echo "wifi: none (run this in a terminal to be asked)"
fi

# ---- 4. Build container ----------------------------------------------------
say "4/5 Build container"
# dev.sh only builds the image when it is missing; rebuild here so a changed
# docker/Dockerfile takes effect (cached otherwise).
docker build -q --platform linux/arm64 -t pixel5-build docker/ >/dev/null
echo "ok"

# ---- 5. Build steps --------------------------------------------------------
# hash_of <path|@text>...: one SHA-256 over the contents of every file under
# the given paths (missing paths are skipped) plus any @text values.
hash_of() {
    local a paths=()
    {
        for a in "$@"; do
            case "$a" in
                @*) printf '%s\n' "$a" ;;
                *)  [ -e "$a" ] && paths+=("$a") ;;
            esac
        done
        if [ ${#paths[@]} -gt 0 ]; then
            find "${paths[@]}" -type f ! -name '*~' ! -name .DS_Store ! -name '._*' -print0 \
                | LC_ALL=C sort -z | xargs -0 shasum -a 256
        fi
    } | shasum -a 256 | cut -d' ' -f1
}
head_of() { git -C "external/$1" rev-parse HEAD; }

# step <name> <output> <hash> <command...>
step() {
    local name=$1 out=$2 hash=$3; shift 3
    local stamp=build/.stamps/$name start=$SECONDS
    if [ "${FORCE:-0}" != 1 ] && [ -e "$out" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$hash" ]; then
        echo "$name: up to date"
        return
    fi
    echo "$name: building..."
    rm -f "$stamp"
    "$@" > "build/$name.log" 2>&1 || {
        tail -n 30 "build/$name.log"
        die "$name failed. Full log: build/$name.log"
    }
    [ -e "$out" ] || die "$name finished but $out is missing. Log: build/$name.log"
    echo "$hash" > "$stamp"
    echo "$name: done in $(( (SECONDS - start) / 60 )) min $(( (SECONDS - start) % 60 )) s (log: build/$name.log)"
}

say "5/5 Build (first run: the kernels take longest)"
H_DOCKER=$(hash_of docker scripts/dev.sh)
H_STOCK=$(hash_of firmware/boot.img firmware/vendor_boot.img)
H_MKB="@$(head_of mkbootimg) $(head_of avb)"

# Mainline kernel, DTB and modules (the default kernel).
H_MAINLINE=$(hash_of kernel/mainline scripts/build-mainline.sh scripts/gen-battery-ocv.py \
    "@$(head_of linux-next) $(head_of nairo) $(head_of kernel-redbull)" "@$H_DOCKER")
step mainline build/mainline/out/modules-install "$H_MAINLINE" env MODULES=1 scripts/build-mainline.sh

# Its boot image: header v2 with our DTB, AVB footer, cmdline from
# build-mainline-test.sh `default`. Its initramfs is built inside.
H_MBOOT=$(hash_of scripts/build-mainline-test.sh scripts/make-bootimg-v2.sh scripts/build-initramfs.sh \
    initramfs "$H_MKB" "@$H_STOCK" "@$H_MAINLINE")
step mainline-bootimg build/boot-mainline-default.img "$H_MBOOT" scripts/build-mainline-test.sh default

H_KERNEL=@no-downstream
if [ "$DOWNSTREAM" != 0 ]; then
    H_KERNEL=$(hash_of kernel/redfin-ubuntu.config kernel/patches scripts/build-kernel.sh \
        "@$(head_of kernel-redbull)" "@$H_DOCKER")
    step kernel build/kernel/modules-install "$H_KERNEL" scripts/build-kernel.sh

    # Downstream boot image: header v3 from the stock boot.img, initramfs
    # with our builds of the vendor's first-stage modules (KMODS=1).
    H_BOOT=$(hash_of scripts/make-bootimg.sh scripts/build-initramfs.sh initramfs \
        "$H_MKB" "@$H_STOCK" "@$H_KERNEL")
    step bootimg build/boot.img "$H_BOOT" sh -c '
        KMODS=1 scripts/build-initramfs.sh &&
        AVB_FOOTER=1 scripts/make-bootimg.sh build/kernel/arch/arm64/boot/Image.lz4 \
            build/initramfs.cpio.lz4 build/boot.img'
else
    # Don't let an old downstream build slip into the rootfs.
    rm -rf build/kernel/modules-install
fi

H_QBOOTCTL=$(hash_of scripts/build-qbootctl.sh "@$(head_of qbootctl)" "@$H_DOCKER")
step qbootctl build/qbootctl/qbootctl "$H_QBOOTCTL" scripts/build-qbootctl.sh

H_QCOM=$(hash_of scripts/build-qcom-daemons.sh "@$(head_of pd-mapper) $(head_of tqftpserv)" "@$H_DOCKER")
step qcom-daemons build/qcom/tqftpserv "$H_QCOM" scripts/build-qcom-daemons.sh

H_LFW=$(hash_of scripts/fetch-linux-firmware.sh)
step linux-firmware build/linux-firmware "$H_LFW" scripts/fetch-linux-firmware.sh

# The project SSH key goes into the image; make it before hashing (as
# build-rootfs.sh would), or the second run rebuilds the rootfs for nothing.
mkdir -p build/ssh
[ -f build/ssh/pixel5_ed25519 ] || ssh-keygen -q -t ed25519 -N "" -C pixel5-port-automation -f build/ssh/pixel5_ed25519
H_ROOTFS=$(hash_of rootfs scripts/build-rootfs.sh patches/hexagonrpc \
    build/wifi.ssid build/wifi.pass build/ssh/pixel5_ed25519.pub \
    "@$(head_of hexagonrpc)" "@$(cat ~/.ssh/*.pub 2>/dev/null | sort -u)" \
    "@$H_MAINLINE $H_KERNEL $H_QBOOTCTL $H_QCOM $H_LFW")
step rootfs build/rootfs.simg "$H_ROOTFS" scripts/build-rootfs.sh

say "Done"
ls -lh build/boot-mainline-default.img build/rootfs.simg | awk '{print $5, $9}'
[ "$DOWNSTREAM" = 0 ] || ls -lh build/boot.img | awk '{print $5, $9, "(downstream fallback)"}'
echo "Next: flash the phone (PLAN.md P7.2, scripts/flash.sh)."
