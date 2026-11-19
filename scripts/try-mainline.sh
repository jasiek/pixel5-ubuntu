#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# One tethered mainline test (writes nothing): Ubuntu -> fastboot ->
# `fastboot boot <img>` -> see where the phone lands.
#   scripts/try-mainline.sh build/boot-mainline-t1.img
# Prints FASTBOOT (the test kernel rebooted into the bootloader) or the
# boot reason Ubuntu got (watchdog = the test kernel hung or died).
set -uo pipefail
IMG=${1:?usage: try-mainline.sh <boot.img>}
cd "$(dirname "$0")/.."
ssh_ok() { scripts/ssh.sh true >/dev/null 2>&1; }
in_fastboot() { [ "$(fastboot devices | wc -l)" -ge 1 ]; }

if ! in_fastboot; then
    scripts/ssh.sh 'sudo -n systemctl reboot --reboot-argument=bootloader' >/dev/null 2>&1
    for _ in $(seq 1 90); do in_fastboot && break; sleep 1; done
fi
in_fastboot || { echo "phone not in fastboot"; exit 1; }
out=$(fastboot boot "$IMG" 2>&1 | grep -iv serial | tail -1)
echo "fastboot boot: $out"
case "$out" in *FAILED*|*error*) exit 1 ;; esac
start=$(date +%s); left=0
while [ $(( $(date +%s) - start )) -lt 240 ]; do
    if in_fastboot; then
        [ $left = 1 ] && { echo "RESULT: FASTBOOT after $(( $(date +%s) - start )) s"; exit 0; }
    else
        left=1
    fi
    if ssh_ok; then
        r=$(scripts/ssh.sh 'tr " " "\n" < /proc/cmdline | sed -n "s/^androidboot.bootreason=//p"' 2>/dev/null)
        echo "RESULT: Ubuntu after $(( $(date +%s) - start )) s, bootreason=$r"; exit 0
    fi
    sleep 1
done
echo "RESULT: nothing after 240 s (hang? check the webcam)"; exit 2
