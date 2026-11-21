#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SSH into the phone's Ubuntu over USB (or pass another host via PIXEL5_HOST).
#   scripts/ssh.sh                 # interactive shell
#   scripts/ssh.sh 'uptime'        # run a command
cd "$(dirname "$0")/.."
exec ssh -i build/ssh/pixel5_ed25519 -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR \
    "ubuntu@${PIXEL5_HOST:-172.16.43.1}" "$@"
