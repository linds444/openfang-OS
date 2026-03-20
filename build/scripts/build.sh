#!/bin/bash
# OpenFang OS — Main Build Script
# Run inside the build container

set -euo pipefail

VERSION="${VERSION:-0.1.0}"
ARCH="${ARCH:-x86_64}"
ALPINE_VER="${ALPINE_VER:-3.19}"
WORK_DIR="/build/work"
OUTPUT_DIR="/output"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

log "=== OpenFang OS Build System v${VERSION} ==="
log "Architecture: ${ARCH}"
log "Alpine: ${ALPINE_VER}"

# ─── Step 1: Fetch Alpine minirootfs ──────────────────────────────────────────
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/releases/${ARCH}"
ROOTFS_TAR="alpine-minirootfs-${ALPINE_VER}.0-${ARCH}.tar.gz"

mkdir -p "${WORK_DIR}/rootfs"

if [ ! -f "${WORK_DIR}/${ROOTFS_TAR}" ]; then
    log "Downloading Alpine minirootfs..."
    wget -q "${ALPINE_URL}/${ROOTFS_TAR}" -O "${WORK_DIR}/${ROOTFS_TAR}"
    wget -q "${ALPINE_URL}/${ROOTFS_TAR}.sha256" -O "${WORK_DIR}/${ROOTFS_TAR}.sha256"
    (cd "${WORK_DIR}" && sha256sum -c "${ROOTFS_TAR}.sha256") || die "Checksum failed!"
fi

log "Extracting Alpine rootfs..."
tar -xzf "${WORK_DIR}/${ROOTFS_TAR}" -C "${WORK_DIR}/rootfs"

# ─── Step 2: Configure Alpine package repositories ────────────────────────────
log "Configuring repositories..."
cat > "${WORK_DIR}/rootfs/etc/apk/repositories" << EOF
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/community
EOF

# ─── Step 3: Install packages into rootfs ────────────────────────────────────
log "Installing packages..."
chroot "${WORK_DIR}/rootfs" /bin/sh << 'CHROOT'
apk update
apk upgrade

# Core system
apk add --no-cache \
    busybox-static \
    musl \
    openrc \
    # Shell and utilities
    bash \
    fish \
    util-linux \
    procps \
    coreutils \
    findutils \
    grep \
    sed \
    awk \
    # Networking
    iproute2 \
    iptables \
    nftables \
    openssh \
    curl \
    wget \
    # Security
    apparmor \
    apparmor-profiles \
    # Crypto
    gnupg \
    openssl \
    cryptsetup \
    # Disk tools
    e2fsprogs \
    dosfstools \
    lsblk \
    # Monitoring
    htop \
    lsof \
    strace \
    # Editors
    nano \
    vim \
    # Build essentials (for compilation on-device)
    gcc \
    musl-dev \
    # Dev tools
    git \
    # Python for scripting
    python3 \
    py3-pip \
    # CA certificates
    ca-certificates \
    # Time sync
    chrony \
    # Logging
    syslog-ng

CHROOT

# ─── Step 4: Apply OpenFang OS overlay ───────────────────────────────────────
log "Applying rootfs overlay..."
cp -r /rootfs/. "${WORK_DIR}/rootfs/"

# ─── Step 5: Copy binaries ───────────────────────────────────────────────────
log "Installing OpenFang binaries..."
if [ -f "/output/bin/aish" ]; then
    install -m 755 /output/bin/aish "${WORK_DIR}/rootfs/usr/bin/aish"
fi
if [ -f "/output/bin/openfang-ctl" ]; then
    install -m 755 /output/bin/openfang-ctl "${WORK_DIR}/rootfs/usr/bin/openfang-ctl"
fi

# ─── Step 6: Configure system ────────────────────────────────────────────────
log "Configuring system..."
chroot "${WORK_DIR}/rootfs" /bin/sh << 'CHROOT'
# Set hostname
echo "openfang" > /etc/hostname

# Enable services
rc-update add sshd default
rc-update add networking default
rc-update add chronyd default
rc-update add syslog-ng default
rc-update add apparmor boot
rc-update add openfang default

# Configure SSH — key-only auth
sed -i \
    -e 's/#PasswordAuthentication yes/PasswordAuthentication no/' \
    -e 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' \
    -e 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' \
    /etc/ssh/sshd_config

# Create AI user
adduser -D -s /usr/bin/aish ai
echo "ai:*" | chpasswd -e  # Locked password — SSH key only

# Create necessary directories
mkdir -p /data /var/log/openfang/agents /etc/openfang/agents

# Set permissions
chown -R ai:ai /home/ai
chmod 700 /home/ai

CHROOT

log "Build complete!"
