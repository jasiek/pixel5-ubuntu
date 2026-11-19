#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# P5.4: reboot the phone N times; each time, time SSH over wifi.
#   scripts/reboot-test.sh [N] [wifi-host]     (default 5, pixel5.local)
# Reboots over whichever path answers (USB first). Per round prints the
# seconds to SSH over wifi, slot, failed units and the wifi guard state.
# Stops at the first round without wifi SSH within 120 s.
set -uo pipefail
cd "$(dirname "$0")/.."
N=${1:-5}
WIFI=${2:-pixel5.local}
K=build/ssh/pixel5_ed25519
s() { ssh -i "$K" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -o ConnectTimeout=4 "ubuntu@$1" "${@:2}"; }
for r in $(seq 1 "$N"); do
    s "$WIFI" 'sudo -n systemctl reboot' >/dev/null 2>&1 \
        || scripts/ssh.sh 'sudo -n systemctl reboot' >/dev/null 2>&1
    t0=$(date +%s)
    sleep 10
    ok=""
    while [ $(( $(date +%s) - t0 )) -lt 120 ]; do
        if s "$WIFI" 'ip -4 -br addr show wlan0 | grep -q UP' 2>/dev/null; then
            ok=$(( $(date +%s) - t0 )); break
        fi
        sleep 2
    done
    if [ -z "$ok" ]; then
        echo "round $r: NO wifi SSH within 120 s"
        [ "$(fastboot devices | wc -l)" -ge 1 ] && echo "  (phone is in fastboot)"
        exit 1
    fi
    info=$(s "$WIFI" 'echo "slot $(sudo -n qbootctl 2>/dev/null | sed -n "s/^Current slot: //p"), failed units $(systemctl --failed --no-legend | wc -l), guard [$(ls /var/lib/pixel5 2>/dev/null | tr "\n" " ")]"')
    echo "round $r: wifi SSH after ${ok} s; $info"
done
