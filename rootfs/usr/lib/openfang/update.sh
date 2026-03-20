#!/bin/bash
# OpenFang OS — Update Script
#
# Updates two independent layers:
#   1. Ubuntu OS packages  (apt)
#   2. OpenFang components (aish, openfang-ctl, overlay files) via GitHub Releases
#
# Usage:
#   update.sh                 Full update (OS + OpenFang)
#   update.sh --check         Dry-run: show available updates, install nothing
#   update.sh --os-only       OS packages only (skip OpenFang release check)
#   update.sh --openfang-only OpenFang release only (skip apt)
#
# Invoked by:
#   openfang-ctl update [--check]
#   systemd openfang-update.timer  (when auto_update = true in config)

set -euo pipefail

GITHUB_REPO="RightNow-AI/openfang-OS"
VERSION_FILE="/var/lib/openfang/version"
UPDATE_LOG="/var/log/openfang/update.log"
BASELINE_FILE="/var/lib/openfang/security/file-baseline.sha256"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${UPDATE_LOG}"; }
die()  { log "ERROR: $*"; exit 1; }
info() { echo "$*"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
CHECK_ONLY=false
DO_OS=true
DO_OPENFANG=true

for arg in "$@"; do
    case "$arg" in
        --check)         CHECK_ONLY=true ;;
        --os-only)       DO_OPENFANG=false ;;
        --openfang-only) DO_OS=false ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

mkdir -p "$(dirname "${UPDATE_LOG}")" /var/lib/openfang/security

# ── Helper: semver comparison (returns 0 if $1 < $2) ─────────────────────────
version_lt() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ] && [ "$1" != "$2" ]
}

# ── Step 1: OS packages (apt) ─────────────────────────────────────────────────
if $DO_OS; then
    info ""
    info "── Ubuntu OS Packages ──────────────────────────────────────"

    if $CHECK_ONLY; then
        info "Checking for OS package updates..."
        apt-get update -qq 2>&1 | tee -a "${UPDATE_LOG}"
        UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)
        if [ "${UPGRADABLE}" -gt 0 ]; then
            info "  ${UPGRADABLE} package(s) can be upgraded:"
            apt list --upgradable 2>/dev/null | grep -v "Listing..."
        else
            info "  OS packages are up to date."
        fi
    else
        log "Updating OS packages..."
        apt-get update -qq 2>&1 | tee -a "${UPDATE_LOG}"
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y 2>&1 | tee -a "${UPDATE_LOG}"
        log "OS packages updated."
    fi
fi

# ── Step 2: OpenFang components ───────────────────────────────────────────────
if $DO_OPENFANG; then
    info ""
    info "── OpenFang Components ─────────────────────────────────────"

    # Current installed version
    CURRENT="0.0.0"
    if [ -f "${VERSION_FILE}" ]; then
        CURRENT=$(cat "${VERSION_FILE}")
    fi

    # Fetch latest release tag from GitHub
    LATEST_JSON=$(curl -sf \
        --connect-timeout 10 \
        --max-time 30 \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null || echo "")

    if [ -z "${LATEST_JSON}" ]; then
        log "WARN: Could not reach GitHub — skipping OpenFang component update."
        info "  Could not reach GitHub. OS packages were still updated."
        exit 0
    fi

    LATEST=$(echo "${LATEST_JSON}" | grep '"tag_name"' | sed 's/.*"tag_name": *"v\?\([^"]*\)".*/\1/')

    if [ -z "${LATEST}" ] || [ "${LATEST}" = "null" ]; then
        log "WARN: No release found on GitHub."
        exit 0
    fi

    info "  Installed : v${CURRENT}"
    info "  Available : v${LATEST}"

    if ! version_lt "${CURRENT}" "${LATEST}"; then
        info "  OpenFang is up to date."
        exit 0
    fi

    info "  New version available: v${CURRENT} → v${LATEST}"

    if $CHECK_ONLY; then
        info ""
        info "  Run 'sudo openfang-ctl update' to install."
        exit 0
    fi

    # Download release tarball
    TARBALL="openfang-update-${LATEST}-amd64.tar.gz"
    RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/download/v${LATEST}/${TARBALL}"
    CHECKSUM_URL="${RELEASE_URL}.sha256"

    TMPDIR=$(mktemp -d /tmp/openfang-update.XXXXXX)
    trap 'rm -rf "${TMPDIR}"' EXIT

    log "Downloading v${LATEST}..."
    info "  Downloading ${TARBALL}..."

    if ! curl -fsSL --progress-bar "${RELEASE_URL}" -o "${TMPDIR}/${TARBALL}"; then
        die "Download failed: ${RELEASE_URL}"
    fi

    # Verify checksum if available
    if curl -fsSL --connect-timeout 10 "${CHECKSUM_URL}" -o "${TMPDIR}/${TARBALL}.sha256" 2>/dev/null; then
        info "  Verifying checksum..."
        (cd "${TMPDIR}" && sha256sum -c "${TARBALL}.sha256") \
            || die "Checksum verification failed — aborting update."
        log "Checksum verified."
    else
        log "WARN: No checksum file found — skipping verification."
    fi

    # Extract
    info "  Extracting..."
    tar -xzf "${TMPDIR}/${TARBALL}" -C "${TMPDIR}"
    EXTRACT_DIR="${TMPDIR}/openfang-update-${LATEST}-amd64"

    [ -d "${EXTRACT_DIR}" ] || die "Unexpected tarball structure — expected directory: ${EXTRACT_DIR}"

    # Install binaries
    info "  Installing binaries..."
    if [ -f "${EXTRACT_DIR}/bin/aish" ]; then
        install -m 755 "${EXTRACT_DIR}/bin/aish" /usr/bin/aish
        log "Installed aish v${LATEST}"
    fi
    if [ -f "${EXTRACT_DIR}/bin/openfang-ctl" ]; then
        install -m 755 "${EXTRACT_DIR}/bin/openfang-ctl" /usr/bin/openfang-ctl
        log "Installed openfang-ctl v${LATEST}"
    fi

    # Apply rootfs overlay — skip user-modified config files
    if [ -d "${EXTRACT_DIR}/rootfs" ]; then
        info "  Applying system overlay..."
        rsync -a \
            --exclude='etc/openfang/config.toml' \
            --exclude='etc/openfang/agents/' \
            --exclude='etc/hostname' \
            --exclude='home/' \
            "${EXTRACT_DIR}/rootfs/" /
        log "Overlay applied."
    fi

    # Record new version
    echo "${LATEST}" > "${VERSION_FILE}"

    # Refresh systemd and restart OpenFang if running
    systemctl daemon-reload 2>/dev/null || true
    if systemctl is-active --quiet openfang 2>/dev/null; then
        info "  Restarting openfang service..."
        systemctl restart openfang || log "WARN: Failed to restart openfang service."
    fi

    # Reload AppArmor profiles if present
    if command -v apparmor_parser >/dev/null 2>&1; then
        apparmor_parser -r /etc/apparmor.d/openfang 2>/dev/null || true
        apparmor_parser -r /etc/apparmor.d/aish      2>/dev/null || true
    fi

    # Update file integrity baseline
    sha256sum \
        /usr/bin/aish /usr/bin/openfang-ctl \
        /etc/openfang/config.toml 2>/dev/null \
        > "${BASELINE_FILE}" || true

    log "OpenFang update complete: ${CURRENT} → ${LATEST}"
    info ""
    info "  OpenFang updated: v${CURRENT} → v${LATEST}"
fi

info ""
info "Update complete. Log: ${UPDATE_LOG}"
