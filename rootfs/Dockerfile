# SPDX-License-Identifier: MIT
# Ubuntu 24.04 arm64 root filesystem for the Pixel 5 (redfin).
# Built with `docker build`, then exported and packed into an ext4 image by
# scripts/build-rootfs.sh. The official ubuntu:24.04 image is ubuntu-base
# plus a few Docker tweaks, and already has user `ubuntu` (uid 1000, sudo).
# Headless first: no camera/GPU/audio userspace until those phases.
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
    && rm -rf /var/lib/apt/lists/*

COPY overlay/ /

RUN chmod 600 /etc/NetworkManager/system-connections/*.nmconnection \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && mkdir -p /vendor /var/log/journal \
    && systemctl enable usb-gadget.service \
        ssh.service NetworkManager.service avahi-daemon.service \
        systemd-timesyncd.service systemd-resolved.service \
        serial-getty@ttyGS0.service pixel5-boot-successful.service \
    # Wifi/modem daemons stay off until Phase 4 decides how wifi comes up.
    && { systemctl disable rmtfs.service tqftpserv.service 2>/dev/null || true; } \
    # Host keys are generated on first boot (ssh.service drop-in).
    && rm -f /etc/ssh/ssh_host_* \
    # Fresh machine-id on first boot.
    && : > /etc/machine-id \
    && passwd -l ubuntu
