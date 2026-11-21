# SPDX-License-Identifier: MIT
# Ubuntu 24.04 arm64 root filesystem for the Pixel 5 (redfin).
# Built with `docker build`, then exported and packed into an ext4 image by
# scripts/build-rootfs.sh. The official ubuntu:24.04 image is ubuntu-base
# plus a few Docker tweaks, and already has user `ubuntu` (uid 1000, sudo).
# Headless first: no camera/GPU/audio userspace until those phases. The GPU
# works on mainline (Test 98); Mesa is an `apt install` away, not in the image.
# Small helpers in C, built in a throwaway stage (no compiler in the image).
FROM ubuntu:24.04 AS tools
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*
COPY tools/ /src/
RUN gcc -O2 -Wall -Werror -o /pixel5-rumble /src/pixel5-rumble.c

# hexagonrpcd (linux-msm/hexagonrpc, GPL-3.0-or-later, external/hexagonrpc)
# with our patches (patches/hexagonrpc): the FastRPC file server the ADSP
# sensor process needs (docs/log.md Tests 119-131).
FROM ubuntu:24.04 AS hexagonrpc-build
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev \
        meson ninja-build pkg-config patch \
    && rm -rf /var/lib/apt/lists/*
COPY --from=hexagonrpc . /src/
COPY --from=hexagonrpc-patches *.patch /patches/
RUN cd /src && for p in /patches/*.patch; do patch -p1 --quiet < "$p"; done \
    && meson setup /build --prefix=/usr --buildtype=release \
    && ninja -C /build \
    && DESTDIR=/inst meson install -C /build

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        systemd systemd-sysv systemd-timesyncd systemd-resolved udev dbus kmod \
        openssh-server sudo \
        iproute2 iputils-ping netbase ca-certificates curl \
        network-manager dnsmasq-base wpasupplicant iw rfkill wireless-regdb \
        avahi-daemon libnss-mdns \
        e2fsprogs dmsetup nano less htop usbutils file \
        unattended-upgrades \
        rmtfs tqftpserv qrtr-tools \
        bluez \
        alsa-utils \
        libdrm-tests \
    && rm -rf /var/lib/apt/lists/*

COPY overlay/ /
COPY --from=tools /pixel5-rumble /usr/local/bin/pixel5-rumble
COPY --from=hexagonrpc-build /inst/usr/bin/hexagonrpcd /usr/bin/
COPY --from=hexagonrpc-build /inst/usr/lib/libhexagonrpc.so.0.5 /usr/lib/

RUN chmod 600 /etc/NetworkManager/system-connections/*.nmconnection \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && mkdir -p /vendor /var/log/journal \
    && systemctl enable usb-gadget.service \
        ssh.service NetworkManager.service avahi-daemon.service \
        systemd-timesyncd.service systemd-resolved.service \
        serial-getty@ttyGS0.service pixel5-boot-successful.service \
        pixel5-firmware.service pd-mapper.service \
        rmtfs.service tqftpserv.service pixel5-wifi.service pixel5-wifi-ok.timer \
        pixel5-qgauge.service pixel5-charge-hold.service pixel5-alive.service \
        pixel5-modem-rproc.service pixel5-bt.service pixel5-adsp.service \
        pixel5-audio.service \
    # Host keys are generated on first boot (ssh.service drop-in).
    && rm -f /etc/ssh/ssh_host_* \
    # Fresh machine-id on first boot.
    && : > /etc/machine-id \
    && passwd -l ubuntu \
    # /dev/dri/renderD128 (Adreno, mainline) is group render.
    && (getent group render >/dev/null || groupadd -r render) \
    && usermod -aG render ubuntu \
    # hexagonrpcd (ADSP FastRPC server) runs as its own user.
    && useradd -r -U -d /nonexistent -s /usr/sbin/nologin fastrpc \
    && ldconfig
