#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Run a command inside the arm64 build container with the repo at /work.
#   scripts/dev.sh uname -m
#   scripts/dev.sh            # interactive shell
# Builds the image on first use. Pass --privileged only to scripts that need
# loop devices (rootfs packing); see build-rootfs.sh.
#
# DEV_CROSS=1 marks a command that cross-compiles (the kernels: clang targets
# arm64 from any host). On an x86 Docker it then runs in an amd64 build of the
# same image (tag <image>-amd64) at native speed instead of under qemu, as the
# host user so its output in build/ stays the host's. On arm64 nothing changes.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"   # physical path on the case-sensitive volume
IMAGE="${DEV_IMAGE:-pixel5-build}"
DOCKERDIR="${DEV_DOCKERDIR:-docker}"

PLATFORM=linux/arm64
run_flags=()
if [ "${DEV_CROSS:-0}" = 1 ]; then
    case "$(docker info --format '{{.Architecture}}')" in
        x86_64|amd64)
            PLATFORM=linux/amd64 IMAGE=$IMAGE-amd64
            run_flags=(--user "$(id -u):$(id -g)" -e HOME=/tmp)
            # Cached after the first time; rebuilds when the Dockerfile changes.
            docker build -q --platform "$PLATFORM" -t "$IMAGE" "$REPO/$DOCKERDIR" >/dev/null ;;
    esac
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker build --platform "$PLATFORM" -t "$IMAGE" "$REPO/$DOCKERDIR"
fi

tty_flags=()
[ -t 0 ] && [ -t 1 ] && tty_flags=(-it)

[ $# -eq 0 ] && set -- bash

exec docker run --rm "${tty_flags[@]}" --platform "$PLATFORM" ${run_flags[@]+"${run_flags[@]}"} \
    ${DEV_DOCKER_ARGS:-} \
    -v "$REPO:/work" -w /work \
    "$IMAGE" "$@"
