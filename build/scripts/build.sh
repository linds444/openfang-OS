#!/bin/bash
# OpenFang OS — Ubuntu 24.04 LTS Build Script
# Bootstraps a full Ubuntu desktop system with AI integration

set -euo pipefail

VERSION="${VERSION:-0.1.0}"
ARCH="${ARCH:-amd64}"
UBUNTU_VER="${UBUNTU_VER:-noble}"   # Ubuntu 24.04 LTS = Noble Numbat
WORK_DIR="/build/work"
OUTPUT_DIR="/output"
ROOTFS="${WORK_DIR}/rootfs"

log()     { echo "[$(date '+%H:%M:%S')] $*"; }
section() { echo; echo "══════════════════════════════════════════════"; echo "  $*"; echo "══════════════════════════════════════════════"; }
die()     { echo "ERROR: $*" >&2; exit 1; }

log "=== OpenFang OS Build — Ubuntu ${UBUNTU_VER} — v${VERSION} ==="

mkdir -p "${ROOTFS}" "${OUTPUT_DIR}"

# ─── Step 1: Bootstrap Ubuntu Noble ──────────────────────────────────────────
section "Bootstrapping Ubuntu 24.04 LTS (Noble Numbat)"

if [ ! -f "${ROOTFS}/etc/os-release" ]; then
    # Note: apt-transport-https was merged into apt itself in Ubuntu 22.04+
    debootstrap \
        --arch="${ARCH}" \
        --include="ca-certificates,gnupg,curl" \
        "${UBUNTU_VER}" \
        "${ROOTFS}" \
        http://archive.ubuntu.com/ubuntu/
    log "Bootstrap complete"
else
    log "Rootfs already bootstrapped, skipping"
fi

# ─── Step 2: Configure APT repositories ──────────────────────────────────────
section "Configuring APT repositories"

cat > "${ROOTFS}/etc/apt/sources.list" << EOF
# OpenFang OS — Ubuntu 24.04 LTS Noble Numbat
deb http://archive.ubuntu.com/ubuntu noble           main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates   main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-security  main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse
EOF

# Firefox via Mozilla's official PPA (avoids snap)
install -d -m 0755 "${ROOTFS}/etc/apt/keyrings"
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
    -o "${ROOTFS}/etc/apt/keyrings/packages.mozilla.org.asc"

cat > "${ROOTFS}/etc/apt/sources.list.d/mozilla.list" << 'EOF'
deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main
EOF

cat > "${ROOTFS}/etc/apt/preferences.d/mozilla" << 'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

# ─── Step 3: Bind mounts for chroot ──────────────────────────────────────────
mount_chroot() {
    for fs in proc sys dev dev/pts; do
        mountpoint -q "${ROOTFS}/$fs" 2>/dev/null && continue
        mount --bind "/$fs" "${ROOTFS}/$fs"
    done
}

umount_chroot() {
    for fs in dev/pts dev sys proc; do
        umount "${ROOTFS}/$fs" 2>/dev/null || true
    done
}

trap umount_chroot EXIT
mount_chroot

# ─── Step 4: Install packages ────────────────────────────────────────────────
section "Installing packages"

chroot "${ROOTFS}" /bin/bash << 'CHROOT'
set -e
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8

apt-get update

# Upgrade base system
apt-get upgrade -y

# ── Core system ─────────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    ubuntu-standard \
    systemd \
    systemd-sysv \
    dbus \
    udev \
    bash \
    bash-completion \
    sudo \
    login \
    passwd \
    adduser \
    coreutils \
    util-linux \
    procps \
    less \
    nano \
    vim-tiny \
    git \
    curl \
    wget \
    ca-certificates \
    openssl \
    gnupg \
    apt-transport-https \
    software-properties-common \
    lsb-release \
    tzdata \
    locales \
    man-db \
    manpages

# ── Networking ──────────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    network-manager \
    network-manager-gnome \
    iproute2 \
    iputils-ping \
    nftables \
    ufw \
    openssh-server \
    openssh-client \
    net-tools \
    dnsutils \
    wireless-tools \
    wpasupplicant \
    rfkill

# ── Desktop — Display server + XFCE ─────────────────────────────────────────
apt-get install -y --no-install-recommends \
    xorg \
    xserver-xorg \
    xserver-xorg-video-all \
    xserver-xorg-input-all \
    x11-utils \
    x11-xserver-utils \
    xinit \
    lightdm \
    lightdm-gtk-greeter \
    lightdm-gtk-greeter-settings \
    xfce4 \
    xfce4-goodies \
    xfce4-terminal \
    xfce4-whiskermenu-plugin \
    xfce4-notifyd \
    xfce4-screensaver \
    xfce4-power-manager \
    xfce4-taskmanager \
    thunar \
    thunar-archive-plugin \
    mousepad \
    ristretto \
    xfburn \
    pavucontrol

# ── Web browser (Firefox from Mozilla, not snap) ────────────────────────────
apt-get install -y --no-install-recommends firefox

# ── Productivity & media ────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    libreoffice-gtk3 \
    vlc \
    gimp \
    file-roller \
    evince \
    gnome-calculator \
    eog

# ── Fonts ───────────────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    fonts-ubuntu \
    fonts-noto \
    fonts-noto-color-emoji \
    fonts-liberation \
    fonts-dejavu

# ── Themes & icons ──────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    arc-theme \
    papirus-icon-theme \
    yaru-theme-gtk \
    yaru-theme-icon \
    adwaita-icon-theme

# ── Audio ───────────────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    pulseaudio \
    pulseaudio-utils \
    alsa-utils \
    pavucontrol

# ── Security ────────────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    apparmor \
    apparmor-utils \
    apparmor-profiles \
    apparmor-profiles-extra \
    ufw \
    cryptsetup \
    libpam-tmpdir \
    libpam-umask \
    fail2ban \
    unattended-upgrades \
    apt-listchanges

# ── Development tools ───────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm

# ── Disk & filesystem ───────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    gparted \
    e2fsprogs \
    dosfstools \
    ntfs-3g \
    lsblk \
    smartmontools

# ── Kernel & bootloader ─────────────────────────────────────────────────────
apt-get install -y \
    linux-image-generic \
    linux-headers-generic \
    grub-pc \
    grub-efi-amd64 \
    grub-efi-amd64-signed \
    shim-signed \
    initramfs-tools \
    casper \
    lupin-casper

# ── Misc utilities ──────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    htop \
    tree \
    unzip \
    zip \
    p7zip-full \
    rsync \
    screen \
    tmux \
    jq \
    ffmpeg \
    imagemagick \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly

# ── Locale & time ───────────────────────────────────────────────────────────
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# ── Clean up ────────────────────────────────────────────────────────────────
apt-get autoremove -y
apt-get autoclean
rm -rf /var/lib/apt/lists/*

CHROOT

# ─── Step 5: Apply OpenFang OS overlay ───────────────────────────────────────
section "Applying OpenFang OS overlay"
rsync -av --exclude='*.md' /rootfs/ "${ROOTFS}/"

# ─── Step 6: Install compiled binaries ───────────────────────────────────────
section "Installing OpenFang binaries"

if [ -f "/output/bin/aish" ]; then
    install -m 755 /output/bin/aish "${ROOTFS}/usr/bin/aish"
    log "Installed aish"
fi
if [ -f "/output/bin/openfang-ctl" ]; then
    install -m 755 /output/bin/openfang-ctl "${ROOTFS}/usr/bin/openfang-ctl"
    log "Installed openfang-ctl"
fi
# Create symlinks for convenience
ln -sf /usr/bin/openfang-ctl "${ROOTFS}/usr/local/bin/ofs"
ln -sf /usr/bin/aish         "${ROOTFS}/usr/local/bin/aish"

# ─── Step 7: Configure the system ────────────────────────────────────────────
section "Configuring system"

chroot "${ROOTFS}" /bin/bash << 'CHROOT'
set -e
export DEBIAN_FRONTEND=noninteractive

# Hostname
echo "openfang" > /etc/hostname
cat > /etc/hosts << 'EOF'
127.0.0.1   localhost
127.0.1.1   openfang openfang.local
::1         localhost ip6-localhost ip6-loopback
EOF

# Create AI user (primary user)
useradd -m -s /usr/bin/aish -c "AI User" -G sudo,audio,video,plugdev,netdev,bluetooth ai 2>/dev/null || true
# Set a temporary password that must be changed on first login
echo "ai:openfang" | chpasswd
chage -d 0 ai  # Force password change on first login

# Also create a normal sudo user for setup
usermod -aG sudo ai

# Autologin for live environment
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-openfang.conf << 'EOF'
[SeatDefaults]
autologin-user=ai
autologin-user-timeout=0
user-session=xfce
greeter-session=lightdm-gtk-greeter
EOF

# Enable essential services
systemctl enable lightdm
systemctl enable NetworkManager
systemctl enable ssh
systemctl enable ufw
systemctl enable apparmor
systemctl enable fail2ban

# Disable services not needed
systemctl disable ModemManager 2>/dev/null || true

# Configure UFW (uncomplicated firewall)
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 8080/tcp comment 'OpenFang API'

# SSH configuration
sed -i \
    -e 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' \
    -e 's/#X11Forwarding yes/X11Forwarding yes/' \
    /etc/ssh/sshd_config

# Enable unattended security upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# Enable AppArmor
sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="apparmor=1 security=apparmor"/' \
    /etc/default/grub 2>/dev/null || true

# Register aish as a valid shell
echo "/usr/bin/aish" >> /etc/shells

# Create required directories
mkdir -p \
    /etc/openfang/agents \
    /var/log/openfang/agents \
    /data/openfang \
    /var/lib/openfang/security

CHROOT

log "System configuration complete"
