#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build the Ubuntu 24.04 root filesystem image for the phone.
#
#   scripts/build-rootfs.sh
#
# 1. docker build rootfs/            -> image pixel5-rootfs
# 2. docker export                   -> build/rootfs.tar
# 3. in the build container: unpack, add kernel modules + SSH keys,
#    mkfs.ext4 -d (label "ubuntu")    -> build/rootfs.img (grows on the phone)
#    img2simg                         -> build/rootfs.simg (for fastboot)
#    + the same tree as build/rootfs-final.tar (P3.3 RAM test)
#
# SSH keys installed for user ubuntu: every ~/.ssh/*.pub plus the project
# key build/ssh/pixel5_ed25519.pub (created if missing).
# Wifi: build/wifi.ssid + build/wifi.pass become an autoconnect NM profile.
# Kernel modules: from scripts/build-kernel.sh if built; a stock-kernel
# rootfs (P3.1) has none of its own.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
SIZE="${ROOTFS_SIZE:-4G}"

if [ ! -f /.dockerenv ]; then
    cd "$REPO"
    [ -f build/qbootctl/qbootctl ] || scripts/build-qbootctl.sh
    mkdir -p build/ssh
    [ -f build/ssh/pixel5_ed25519 ] || ssh-keygen -q -t ed25519 -N "" -C pixel5-port-automation -f build/ssh/pixel5_ed25519
    # A host without ~/.ssh/*.pub is fine (the project key still goes in);
    # without the `|| true`, cat's failure on the unmatched glob kills the
    # build silently under pipefail (Pixel 2 lesson).
    { cat ~/.ssh/*.pub 2>/dev/null || true; cat build/ssh/pixel5_ed25519.pub; } | sort -u > build/ssh/authorized_keys

    docker build --platform linux/arm64 -t pixel5-rootfs rootfs/
    cid=$(docker create --platform linux/arm64 pixel5-rootfs)
    trap 'docker rm -f "$cid" >/dev/null' EXIT
    docker export "$cid" -o build/rootfs.tar
    exec "$REPO/scripts/dev.sh" env ROOTFS_SIZE="$SIZE" /work/scripts/build-rootfs.sh
fi

# ---- inside the build container (as root) ----
cd /work
R=/tmp/rootfs          # container-internal FS: keeps ownership/modes exact
rm -rf "$R"; mkdir -p "$R"
tar -xpf build/rootfs.tar -C "$R" --numeric-owner

# Docker leftovers / files Docker managed at runtime.
rm -f "$R/.dockerenv"
echo pixel5 > "$R/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\tpixel5\n::1\tlocalhost ip6-localhost ip6-loopback\n' > "$R/etc/hosts"
# Docker's exported stubs for these are mode 0755; make them normal files.
chmod 644 "$R/etc/hostname" "$R/etc/hosts"
rm -f "$R/etc/resolv.conf"
ln -s ../run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"

# Kernel modules built by scripts/build-kernel.sh.
KREL=none
MODS=build/kernel/modules-install/lib/modules
if [ -d "$MODS" ]; then
    KREL=$(ls "$MODS")
    mkdir -p "$R/lib/modules"
    cp -a "$MODS/$KREL" "$R/lib/modules/"
    rm -f "$R/lib/modules/$KREL/build" "$R/lib/modules/$KREL/source"
    depmod -b "$R" "$KREL"
    echo "kernel modules $KREL included"
else
    echo "no kernel modules (stock kernel, or build-kernel.sh not run)"
fi
# A/B slot marking (scripts/build-qbootctl.sh, pixel5-boot-successful.service).
install -m 755 build/qbootctl/qbootctl "$R/usr/local/sbin/qbootctl"

# SSH access.
install -d -m 700 -o 1000 -g 1000 "$R/home/ubuntu/.ssh"
install -m 600 -o 1000 -g 1000 build/ssh/authorized_keys "$R/home/ubuntu/.ssh/authorized_keys"

# Wifi profile from build/wifi.ssid + build/wifi.pass (gitignored). An empty
# or missing ssid file means no wifi profile. Never echo these values.
if [ -s build/wifi.ssid ] && [ -s build/wifi.pass ]; then
    ssid=$(cat build/wifi.ssid); psk=$(cat build/wifi.pass)   # $(...) drops trailing newlines
    nm="$R/etc/NetworkManager/system-connections/wifi.nmconnection"
    (umask 077
     printf '[connection]\nid=wifi\ntype=wifi\ninterface-name=wlan0\nautoconnect=true\n\n[wifi]\nmode=infrastructure\nssid=%s\n\n[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n' "$ssid" "$psk" > "$nm")
    chown 0:0 "$nm"; chmod 600 "$nm"
    unset ssid psk
    echo "wifi profile added"
else
    echo "no wifi profile (build/wifi.ssid empty or missing)"
fi

echo "built $(date -u +%FT%TZ) kernel $KREL" > "$R/etc/pixel5-build"

# The same tree as a tar, for the tethered test from RAM (P3.3:
# scripts/ramroot.sh unpacks it into a tmpfs on the phone; nothing flashed).
tar -C "$R" --numeric-owner -cpf build/rootfs-final.tar .

rm -f build/rootfs.img build/rootfs.simg
# e2fsprogs 1.47 (Ubuntu 24.04) enables orphan_file and metadata_csum_seed by
# default; a 4.19 kernel refuses to mount ext4 with orphan_file read-write.
# lazy_*_init=0: the phone grows the fs on first boot (x-systemd.growfs).
mkfs.ext4 -q -F -L ubuntu -O ^orphan_file,^metadata_csum_seed \
    -E root_owner=0:0,lazy_itable_init=0,lazy_journal_init=0 -d "$R" build/rootfs.img "$SIZE"
img2simg build/rootfs.img build/rootfs.simg
rm -rf "$R"
ls -la build/rootfs.img build/rootfs.simg
