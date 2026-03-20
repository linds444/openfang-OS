#!/bin/sh
# OpenFang OS — Shell profile
# Loaded for all interactive shells

# ─── Colors ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    CYAN='\033[1;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    RESET='\033[0m'
fi

# ─── PATH ─────────────────────────────────────────────────────────────────────
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"

# ─── OpenFang environment ─────────────────────────────────────────────────────
export OPENFANG_HOME="/etc/openfang"
export OPENFANG_DATA="/data/openfang"
export OPENFANG_LOGS="/var/log/openfang"
export OPENFANG_API="http://127.0.0.1:8080"

# Load config from openfang.toml if it exists
if [ -f "${OPENFANG_HOME}/config.toml" ]; then
    # Export LLM provider for aish
    _LLM_PROVIDER=$(grep '^provider' "${OPENFANG_HOME}/config.toml" 2>/dev/null | head -1 | cut -d'"' -f2)
    export AISH_LLM_PROVIDER="${_LLM_PROVIDER:-openai}"
fi

# ─── Editor ───────────────────────────────────────────────────────────────────
export EDITOR="nano"
export VISUAL="nano"
export PAGER="less"

# ─── History ──────────────────────────────────────────────────────────────────
export HISTFILE="$HOME/.aish_history"
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTCONTROL="ignoredups:erasedups"

# ─── Aliases ──────────────────────────────────────────────────────────────────
alias ll='ls -lah --color=auto'
alias la='ls -la --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias cls='clear'

# OpenFang aliases
alias ofs='openfang-ctl status'
alias ofa='openfang-ctl agents'
alias ofl='openfang-ctl logs'
alias ofc='openfang-ctl config'

# Safety aliases
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# ─── Functions ────────────────────────────────────────────────────────────────

# Quick help: ask the AI assistant
help() {
    if [ -z "$*" ]; then
        echo "Usage: help <question>"
        echo "Example: help how do I list all open ports?"
    else
        openfang-ctl ask "$*"
    fi
}

# Show system status on login
_openfang_login_status() {
    local api_status="offline"
    if curl -sf "${OPENFANG_API}/health" >/dev/null 2>&1; then
        api_status="${GREEN}online${RESET}"
    else
        api_status="${RED}offline${RESET}"
    fi
    printf "  OpenFang API: ${api_status}\n" 2>/dev/null || true
}

# Only show status for interactive login shells
case "$-" in
    *i*)
        _openfang_login_status
        ;;
esac
