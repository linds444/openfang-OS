#!/bin/bash
# OpenFang OS — First Boot Setup Script
# Runs once via systemd on first boot

set -euo pipefail

log() { echo "[first-boot] $*" | tee -a /var/log/openfang/first-boot.log; }

log "=== OpenFang OS First Boot Setup ==="

mkdir -p /var/log/openfang /data/openfang /var/lib/openfang/security /run/openfang

# Create openfang system user if it doesn't exist
if ! id openfang >/dev/null 2>&1; then
    useradd -r -s /sbin/nologin -d /var/lib/openfang -c "OpenFang Agent Runtime" openfang
    log "Created openfang system user"
fi

# Set up directory permissions
chown -R openfang:openfang /var/log/openfang /data/openfang /var/lib/openfang /run/openfang 2>/dev/null || true

# Copy default config if none exists
if [ ! -f /etc/openfang/config.toml ]; then
    cp /etc/openfang/config.toml.default /etc/openfang/config.toml
    chown openfang:openfang /etc/openfang/config.toml
    chmod 640 /etc/openfang/config.toml
    log "Installed default config"
fi

# Copy agent configs if directory is empty
if [ ! "$(ls -A /etc/openfang/agents 2>/dev/null)" ]; then
    cp -r /usr/share/openfang/agents/. /etc/openfang/agents/ 2>/dev/null || true
    chown -R openfang:openfang /etc/openfang/agents/
    log "Installed default agent configs"
fi

# Apply file integrity baseline
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum \
        /etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config \
        /etc/openfang/config.toml \
        /usr/bin/aish /usr/bin/openfang-ctl 2>/dev/null \
        > /var/lib/openfang/security/file-baseline.sha256 || true
    log "File integrity baseline created"
fi

# Apply AppArmor profiles
if command -v apparmor_parser >/dev/null 2>&1; then
    apparmor_parser -r /etc/apparmor.d/openfang 2>/dev/null || true
    apparmor_parser -r /etc/apparmor.d/aish 2>/dev/null || true
    log "AppArmor profiles loaded"
fi

# Enable UFW
if command -v ufw >/dev/null 2>&1; then
    ufw --force enable 2>/dev/null || true
    log "UFW firewall enabled"
fi

# Apply sysctl hardening
if [ -f /etc/sysctl.d/99-openfang-hardening.conf ]; then
    sysctl -p /etc/sysctl.d/99-openfang-hardening.conf >/dev/null 2>&1 || true
    log "Kernel hardening applied"
fi

# Enable OpenFang service for future boots
systemctl enable openfang 2>/dev/null || true

# Start OpenFang if binary exists
if [ -x /usr/bin/openfang ]; then
    systemctl start openfang 2>/dev/null || true
    log "OpenFang agent runtime started"
else
    log "OpenFang binary not found at /usr/bin/openfang — install it to enable AI agents"
fi

# Set up desktop for ai user
if [ -d /home/ai ]; then
    # Copy skeleton if Desktop doesn't exist
    if [ ! -d /home/ai/Desktop ]; then
        cp -r /etc/skel/. /home/ai/ 2>/dev/null || true
        chown -R ai:ai /home/ai/
        log "Set up desktop for ai user"
    fi
    # Mark desktop files as trusted
    for f in /home/ai/Desktop/*.desktop; do
        [ -f "$f" ] && chmod +x "$f" || true
    done
fi

log "First boot setup complete"
