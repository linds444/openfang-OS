# OpenFang OS — Build Container (Ubuntu 24.04 LTS)
# Produces a full desktop Linux ISO with AI-native features

ARG UBUNTU_VER=24.04
# Force amd64 — the ISO we build is always x86_64 regardless of host arch (Mac M1/M2/M3)
FROM --platform=linux/amd64 ubuntu:${UBUNTU_VER} AS builder

ARG VERSION=0.1.0
ARG ARCH=amd64

LABEL org.opencontainers.image.title="OpenFang OS Builder"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.description="Build environment for OpenFang OS (Ubuntu 24.04 base)"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Debootstrap (creates Ubuntu rootfs from scratch)
    debootstrap \
    # Squashfs
    squashfs-tools \
    # ISO creation
    xorriso \
    isolinux \
    syslinux-common \
    grub-pc-bin \
    grub-efi-amd64-bin \
    grub2-common \
    mtools \
    dosfstools \
    # Disk tools
    gdisk \
    parted \
    # Encryption
    cryptsetup-bin \
    # Filesystem
    e2fsprogs \
    # Kernel and initramfs
    linux-image-generic \
    initramfs-tools \
    # Build utils
    wget \
    curl \
    git \
    rsync \
    jq \
    pigz \
    zstd \
    xz-utils \
    # Rust (for aish + openfang-ctl)
    rustup \
    # System
    bash \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Rust stable
RUN rustup toolchain install stable 2>/dev/null || true

# Copy build scripts
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

WORKDIR /build

CMD ["/bin/bash"]
