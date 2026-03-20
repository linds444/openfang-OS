# OpenFang OS — Build Container
# Provides a reproducible Alpine-based build environment

ARG ALPINE_VER=3.19
FROM alpine:${ALPINE_VER} AS builder

ARG VERSION=0.1.0
ARG ARCH=x86_64

LABEL org.opencontainers.image.title="OpenFang OS Builder"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.description="Build environment for OpenFang OS"

# Install build tools
RUN apk add --no-cache \
    # Core build tools
    alpine-sdk \
    build-base \
    abuild \
    # Kernel build deps
    linux-headers \
    openssl-dev \
    flex \
    bison \
    elfutils-dev \
    # ISO/image creation
    grub \
    grub-efi \
    xorriso \
    squashfs-tools \
    mtools \
    dosfstools \
    # Network & crypto
    curl \
    wget \
    openssl \
    # Filesystems
    e2fsprogs \
    btrfs-progs \
    cryptsetup \
    # Compression
    zstd \
    xz \
    gzip \
    # AppArmor
    apparmor \
    apparmor-utils \
    # Rust (for aish and openfang-ctl)
    rust \
    cargo \
    # Misc
    bash \
    git \
    jq \
    python3 \
    py3-pip

# Alpine mkimage tooling
RUN apk add --no-cache \
    alpine-conf \
    alpine-base

# Copy build scripts into the container
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

WORKDIR /build

CMD ["/bin/bash"]
