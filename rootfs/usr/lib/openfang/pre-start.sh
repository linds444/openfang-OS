#!/bin/bash
# OpenFang service pre-start hook
set -euo pipefail
mkdir -p /run/openfang /var/log/openfang/agents /data/openfang
chown openfang:openfang /run/openfang /var/log/openfang /data/openfang 2>/dev/null || true
