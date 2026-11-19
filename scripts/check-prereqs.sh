#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Check everything the host needs to build, flash and log in, and report all
# problems at once (not just the first).
#
#   scripts/check-prereqs.sh            # build + flash + login checks
#   scripts/check-prereqs.sh --build    # only what building needs (build-all.sh)
#   OFFLINE=1 scripts/check-prereqs.sh  # skip the network checks
#
# Exit status: 1 if anything required for building is missing, else 0.
# Flash/login gaps are warnings: you can build on one Mac and flash from another.
# Everything else (compilers, mkbootimg, simg2img, ...) runs inside Docker.
set -uo pipefail
cd "$(dirname "$0")/.."
ONLY_BUILD=0; [ "${1:-}" = --build ] && ONLY_BUILD=1

fails=0; warns=0
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fails=$((fails + 1)); }
soft() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; warns=$((warns + 1)); }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

if [ "$(uname -s)" = Darwin ]; then
    pkg() { echo "brew install $1"; }
else
    pkg() { echo "sudo apt install $2"; }
fi

# need <cmd> <brew formula> <apt package> [why]
need() {
    if command -v "$1" >/dev/null 2>&1; then ok "$1"
    else bad "$1 missing${4:+ ($4)}: $(pkg "$2" "$3")"; fi
}

hdr "Host"
case "$(uname -s)/$(uname -m)" in
    Darwin/arm64)  ok "macOS on Apple Silicon" ;;
    Linux/aarch64) ok "Linux arm64 (untested host; the scripts target macOS)" ;;
    Linux/x86_64)  ok "Linux x86_64 (kernels cross-compile natively; the rest runs emulated arm64)" ;;
    *) soft "$(uname -s)/$(uname -m): builds run arm64 containers; on x86 they are emulated and many times slower" ;;
esac
if [ "$(uname -s)" = Darwin ]; then
    # /usr/bin/git and /usr/bin/python3 exist on a fresh Mac but are stubs that
    # pop up an installer dialog until the Command Line Tools are installed.
    if xcode-select -p >/dev/null 2>&1; then ok "Xcode Command Line Tools"
    else bad "Xcode Command Line Tools missing (git and python3 are stubs without them): xcode-select --install"; fi
fi

hdr "Tools for building"
if command -v docker >/dev/null 2>&1; then ok docker
elif [ "$(uname -s)" = Darwin ]; then bad "docker missing: brew install --cask docker (Docker Desktop; the plain 'docker' formula has no engine)"
else bad "docker missing: sudo apt install docker.io (then add yourself to group docker)"; fi
need git     git     git
need curl    curl    curl
need unzip   unzip   unzip      "unpacks Google's factory image"
need shasum  perl    perl       "checks download hashes"
need tar     gnu-tar tar
need python3 python  python3
if command -v python3 >/dev/null 2>&1 && ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null; then
    bad "python3 is older than 3.8"
fi

hdr "Docker"
if ! command -v docker >/dev/null 2>&1; then
    printf '  --    skipped (no docker)\n'
elif ! docker info >/dev/null 2>&1; then
    bad "Docker is not running: start it (Docker Desktop, colima start, or OrbStack)"
else
    ok "Docker is running"
    arch=$(docker info --format '{{.Architecture}}' 2>/dev/null)
    # Explicit platforms below: a plain ubuntu:24.04 tag is whichever
    # architecture was pulled last.
    native=linux/arm64
    case "$arch" in aarch64|arm64) ok "Docker runs arm64 natively" ;;
        *) native=linux/amd64
           ok "Docker architecture '$arch': kernels cross-compile in amd64 images"
           # Everything else (initramfs, userspace tools, the rootfs) is arm64
           # and needs qemu registered with binfmt_misc.
           if docker run --rm --platform linux/arm64 ubuntu:24.04 true >/dev/null 2>&1; then
               ok "Docker runs arm64 images (emulated: slower, but only the small steps)"
           else
               soft "Docker can't run arm64 images yet; build-all.sh registers qemu for them (or: $(pkg qemu qemu-user-static))"
           fi ;; esac
    mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null); mem_gb=$(( ${mem:-0} / 1073741824 ))
    if [ "$mem_gb" -ge 6 ]; then ok "Docker memory ${mem_gb} GB"
    else soft "Docker has ${mem_gb} GB memory; builds were tested with 8 GB (Docker Desktop > Settings > Resources)"; fi
    # The repo must be visible inside containers. Docker's VM only sees the
    # host folders it shares (Colima: just $HOME by default); for any other
    # path, -v quietly mounts an empty directory.
    if docker pull -q --platform "$native" ubuntu:24.04 >/dev/null 2>&1; then
        if docker run --rm --platform "$native" -v "$PWD":/w:ro ubuntu:24.04 test -f /w/scripts/check-prereqs.sh 2>/dev/null; then
            ok "containers can see this folder"
        else
            vol=$(printf '%s' "$PWD" | cut -d/ -f1-3)
            bad "containers can't see $PWD (they get an empty folder). Share $vol with Docker's VM:"
            printf '        Colima:         colima stop; colima start --mount "$HOME:w" --mount %s:w\n' "$vol"
            printf '        Docker Desktop: Settings > Resources > File sharing, add %s\n' "$vol"
            printf '        OrbStack:       shares /Volumes already; check Settings > File sharing\n'
        fi
    else
        bad "can't pull ubuntu:24.04 from Docker Hub (network, login, or a credsStore helper named in ~/.docker/config.json that isn't installed?)"
    fi
fi

hdr "Disk"
mkdir -p build/.stamps
touch build/.stamps/CaseTest
if [ -e build/.stamps/casetest ]; then
    bad "this folder is on a case-insensitive filesystem; the kernel needs a case-sensitive one (README, Install step 1)"
else
    ok "case-sensitive filesystem"
fi
rm -f build/.stamps/CaseTest
free_gb=$(df -Pk . | awk 'NR==2 {print int($4 / 1048576)}')
if [ -n "$(ls build/.stamps 2>/dev/null)" ]; then want=10; else want=50; fi
if [ "$free_gb" -ge "$want" ]; then ok "${free_gb} GB free here"
else soft "${free_gb} GB free here; a first full build uses ~45 GB (plus ~40 GB inside Docker's own disk)"; fi

if [ "${OFFLINE:-0}" != 1 ]; then
    hdr "Network (first build downloads from these)"
    for u in https://registry-1.docker.io/v2/ http://ports.ubuntu.com/ubuntu-ports/ \
             https://dl.google.com/ https://android.googlesource.com/ https://git.kernel.org/ \
             https://github.com/ https://gitlab.freedesktop.org/; do
        host=${u#*://}; host=${host%%/*}
        if curl -s -o /dev/null -m 10 "$u"; then ok "$host"
        else soft "$host unreachable (only matters if that step still has to run)"; fi
    done
fi

if [ "$ONLY_BUILD" = 0 ]; then
    hdr "Flashing and logging in (warnings only)"
    for c in adb fastboot; do
        if command -v $c >/dev/null 2>&1; then ok "$c ($($c --version 2>/dev/null | head -1))"
        else soft "$c missing, needed to flash: $(pkg android-platform-tools android-sdk-platform-tools)"; fi
    done
    command -v ssh >/dev/null 2>&1 && ok "ssh" || soft "ssh missing: $(pkg openssh openssh-client)"
    command -v nc  >/dev/null 2>&1 && ok "nc"  || soft "nc missing (scripts/try-boot.sh uses it): $(pkg netcat netcat-openbsd)"
    if ls ~/.ssh/*.pub >/dev/null 2>&1; then ok "SSH public key in ~/.ssh"
    else soft "no ~/.ssh/*.pub: only the project key works (scripts/ssh.sh uses it); make one with ssh-keygen -t ed25519"; fi
fi

printf '\n'
if [ "$fails" -gt 0 ]; then
    printf '\033[31m%d problem(s) block the build\033[0m, %d warning(s). Fix the FAIL lines above and run this again.\n' "$fails" "$warns"
    exit 1
fi
printf '\033[32mReady to build.\033[0m %d warning(s).\n' "$warns"
