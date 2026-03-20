#!/bin/sh
# OpenFang OS — Shell profile (Ubuntu 24.04 LTS)
# Sourced for all interactive bash/sh sessions

# ─── Colors ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    CYAN='\033[1;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    RESET='\033[0m'
fi

# ─── PATH ─────────────────────────────────────────────────────────────────────
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin"

# ─── OpenFang environment ─────────────────────────────────────────────────────
export OPENFANG_HOME="/etc/openfang"
export OPENFANG_DATA="/data/openfang"
export OPENFANG_LOGS="/var/log/openfang"
export OPENFANG_API="http://127.0.0.1:8080"

# Load API key from config if available
if [ -f "${OPENFANG_HOME}/config.toml" ] && command -v python3 >/dev/null 2>&1; then
    _API_KEY=$(python3 -c "
import re, sys
try:
    content = open('${OPENFANG_HOME}/config.toml').read()
    m = re.search(r'api_key\s*=\s*\"([^\"]+)\"', content)
    print(m.group(1) if m else '')
except: pass
" 2>/dev/null || true)
    if [ -n "${_API_KEY}" ]; then
        export OPENAI_API_KEY="${_API_KEY}"
    fi
fi

# ─── Editor ───────────────────────────────────────────────────────────────────
export EDITOR="mousepad"
export VISUAL="mousepad"
export TERMINAL="xfce4-terminal"

# ─── History ──────────────────────────────────────────────────────────────────
export HISTFILE="$HOME/.bash_history"
export HISTSIZE=50000
export HISTFILESIZE=50000
export HISTCONTROL="ignoredups:erasedups"
shopt -s histappend 2>/dev/null || true

# ─── Aliases ──────────────────────────────────────────────────────────────────
alias ll='ls -lah --color=auto'
alias la='ls -la --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias cls='clear'
alias open='xdg-open'

# OpenFang shortcuts
alias ofs='openfang-ctl status'
alias ofa='openfang-ctl agents'
alias ofl='openfang-ctl logs'
alias ofc='openfang-ctl config'

# Safety
alias rm='rm -I --preserve-root'
alias mv='mv -i'
alias cp='cp -i'

# ─── Functions ────────────────────────────────────────────────────────────────

# AI help: ask the assistant
help() {
    if [ -z "$*" ]; then
        echo "Usage: help <question>"
        echo "Example: help how do I find large files?"
        return 0
    fi
    openfang-ctl ask "$*"
}

# Quick browser launch
browser() {
    if command -v firefox >/dev/null 2>&1; then
        firefox "${1:-about:newtab}" &
    elif command -v chromium-browser >/dev/null 2>&1; then
        chromium-browser "${1:-}" &
    fi
}

# Show status on interactive login shells
_openfang_prompt_status() {
    local api_ok=false
    if curl -sf "${OPENFANG_API}/health" >/dev/null 2>&1; then
        api_ok=true
    fi
    if ${api_ok}; then
        printf "  OpenFang API: ${GREEN}online${RESET}\n" 2>/dev/null || true
    fi
}

# Only on interactive login shells
case "$-" in
    *i*) [ -n "${DISPLAY}" ] || _openfang_prompt_status ;;
esac
