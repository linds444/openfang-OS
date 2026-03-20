#!/bin/bash
# OpenFang OS — Rootfs Overlay Assembly (host-side)
# Copies local overlay files into build output directory

set -euo pipefail

BUILD_DIR="${1:-build/output}"
WORK_DIR="${2:-build/work}"

log() { echo "[rootfs] $*"; }

log "Assembling rootfs overlay..."

mkdir -p "${BUILD_DIR}" "${WORK_DIR}"

# Nothing to do on the host side — the Docker container handles the
# actual chroot overlay. This script is a hook for future host-side
# preprocessing (e.g. signing binaries, generating manifests).

log "Rootfs overlay ready (Docker build will apply it)."
