# SPDX-License-Identifier: MIT
# Build environment for the Pixel 5 (redfin) Ubuntu port: kernels (downstream
# 4.19 and mainline), initramfs, boot images and rootfs packing.
# One Ubuntu 24.04 image with LLVM 18 (based on the Pixel 2 project's mainline
# container). If the LineageOS 4.19 tree won't build with clang 18, P3.2 adds
# a pinned older clang here and logs why.
# Native arm64 on Apple Silicon. On an x86 host scripts/dev.sh (DEV_CROSS=1)
# uses an amd64 build of this image; clang targets arm64 by itself.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential bc bison flex libssl-dev libelf-dev \
        clang-18 lld-18 llvm-18 ccache \
        lz4 gzip xz-utils cpio kmod git ca-certificates curl file \
        python3 python3-protobuf device-tree-compiler \
        android-sdk-libsparse-utils e2fsprogs busybox-static \
        libqrtr-dev libudev-dev \
    && rm -rf /var/lib/apt/lists/*

# Unversioned clang/ld.lld names, as kernel Makefiles expect.
RUN for t in clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-strip; do \
        ln -sf /usr/bin/$t-18 /usr/local/bin/$t; \
    done

# Third-party sources are git submodules in external/, mounted at
# /work/external at run time. See scripts/dev.sh.
ENV PATH="/work/scripts/bin:${PATH}"

WORKDIR /work
