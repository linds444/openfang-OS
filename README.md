# OpenFang OS

**An AI-native Linux operating system built on [OpenFang](https://github.com/RightNow-AI/openfang) — the open-source Rust Agent OS.**

OpenFang OS is a minimal, security-hardened Linux distribution where AI agents are first-class citizens. It boots into a fully autonomous AI environment powered by the OpenFang agent runtime, with an AI-enhanced shell (`aish`), pre-configured autonomous agents, and a hardened kernel — all designed to run reliably and safely.

---

## What It Is

- **Base**: Alpine Linux (musl libc, minimal footprint, security-focused)
- **Kernel**: Linux 6.6 LTS with hardening patches
- **AI Engine**: OpenFang Rust Agent OS (137K LOC, 14 crates)
- **AI Shell**: `aish` — a natural language shell that wraps standard commands with AI assistance
- **Init**: OpenRC with OpenFang as a core system service
- **Security**: AppArmor, nftables firewall, mandatory sandboxing for agents

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    User Interface                    │
│         aish (AI Shell)  •  openfang-ctl TUI        │
├─────────────────────────────────────────────────────┤
│                  OpenFang Agent Runtime              │
│   system-monitor  •  security-guard  •  assistant   │
│   40+ channel adapters  •  27 LLM providers         │
├─────────────────────────────────────────────────────┤
│                   Alpine Linux Base                  │
│   musl libc  •  BusyBox  •  OpenRC  •  nftables    │
├─────────────────────────────────────────────────────┤
│               Linux 6.6 LTS Kernel                  │
│   Hardening: KASLR, SMEP, SMAP, CET, Lockdown      │
└─────────────────────────────────────────────────────┘
```

## Features

### AI Shell (`aish`)
- Natural language command execution (`find all log files older than 7 days` → runs the right command)
- Safety confirmation for destructive operations
- Context-aware command suggestions
- Session memory and history
- Integrates with any OpenAI-compatible API (OpenFang, Claude, GPT-4, local models)

### OpenFang Agent Runtime
- Autonomous agents that run on schedules, not just on demand
- Pre-configured agents: system monitor, security guard, AI assistant
- 40 channel adapters (Slack, Discord, Telegram, WhatsApp, email, etc.)
- 123+ LLM model support
- REST/WebSocket API on port 8080

### Security Hardening
- Kernel: KASLR, SMEP, SMAP, CET, Lockdown mode
- AppArmor profiles for all system services and agents
- Mandatory firewall (nftables) — allow-list only
- Agent sandboxing: each agent runs in isolated cgroup/namespace
- Read-only root filesystem (overlay on tmpfs)
- Automatic security updates via cron
- No default passwords — SSH key-only auth

### System Design
- Immutable root filesystem (tmpfs overlay)
- Atomic updates (A/B partition scheme)
- Disk encryption (LUKS2)
- TPM2 attestation support
- ~512MB RAM minimum (2GB recommended for AI workloads)

## Quick Start

### Prerequisites
- Docker 24+ and Docker Buildx
- `qemu-system-x86_64` (for testing)
- 8GB free disk space

### Build

```bash
# Clone
git clone https://github.com/RightNow-AI/openfang-OS
cd openfang-OS

# Configure (copy and edit your API keys)
cp openfang.toml.example openfang.toml
$EDITOR openfang.toml

# Build the ISO
make iso

# Run in QEMU for testing
make run

# Build a flashable image for USB/SD card
make image
```

### Install to Disk

Boot the ISO and run:

```bash
openfang-install
```

The installer will:
1. Partition the disk (EFI + LUKS2 encrypted root)
2. Copy the system
3. Configure bootloader (GRUB)
4. Generate SSH host keys
5. Set up agent configuration

### First Boot

After installation, OpenFang OS boots to `aish`. Configure your AI:

```bash
# Set your LLM provider (OpenFang self-hosted, Claude, GPT, local Ollama, etc.)
openfang-ctl config set llm.provider openai
openfang-ctl config set llm.api_key "sk-..."
openfang-ctl config set llm.model "gpt-4o"

# Or use a local model via Ollama
openfang-ctl config set llm.provider ollama
openfang-ctl config set llm.base_url "http://localhost:11434"

# Start all AI agents
openfang-ctl agents start-all

# Check system status
openfang-ctl status
```

## Directory Structure

```
openfang-OS/
├── README.md
├── Makefile                    # Build orchestration
├── openfang.toml.example       # Configuration template
├── build/                      # Build system
│   ├── Dockerfile              # Build container
│   ├── build.sh                # Main build script
│   ├── iso.sh                  # ISO image creation
│   └── rootfs.sh               # Rootfs overlay assembly
├── kernel/                     # Kernel configuration
│   ├── config-6.6              # Kernel .config
│   └── patches/                # Kernel patches
├── rootfs/                     # Filesystem overlay
│   ├── etc/                    # System configuration
│   ├── usr/                    # System binaries
│   └── home/ai/                # Default AI user home
├── aish/                       # AI Shell (Rust)
│   ├── Cargo.toml
│   └── src/main.rs
├── openfang-ctl/               # Control TUI (Rust)
│   ├── Cargo.toml
│   └── src/main.rs
├── agents/                     # Agent configurations
│   ├── system-monitor.toml
│   ├── security-guard.toml
│   └── ai-assistant.toml
├── installer/                  # OS installer
│   ├── install.sh
│   └── partitions.conf
└── docs/                       # Documentation
    ├── getting-started.md
    ├── architecture.md
    ├── security.md
    └── agents.md
```

## Agent System

OpenFang OS ships with three built-in agents:

| Agent | Purpose | Schedule |
|-------|---------|---------|
| `system-monitor` | CPU/RAM/disk/network monitoring, alerts | Every 60s |
| `security-guard` | Log scanning, intrusion detection, CVE checks | Every 5min |
| `ai-assistant` | Interactive help, task automation, research | On demand |

Add custom agents in `/etc/openfang/agents/`:

```toml
# /etc/openfang/agents/my-agent.toml
[agent]
name = "my-agent"
description = "Does something useful"
schedule = "*/10 * * * *"  # Every 10 minutes

[llm]
model = "gpt-4o-mini"
system_prompt = "You are a helpful system agent..."

[triggers]
on_start = true
on_schedule = true
```

## aish — AI Shell

`aish` is the default shell in OpenFang OS. It understands natural language:

```
[ai@openfang ~]$ show me all processes using more than 100MB of RAM
→ ps aux --sort=-%mem | awk 'NR==1 || $6 > 100000'
  (run? [Y/n])

[ai@openfang ~]$ compress all jpg files in this directory to webp
→ for f in *.jpg; do cwebp "$f" -o "${f%.jpg}.webp"; done
  (run? [Y/n])

[ai@openfang ~]$ what's using port 8080?
→ lsof -i :8080
  (running...)
  COMMAND   PID  USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
  openfang 1234 ai     7u  IPv4  12345      0t0  TCP *:8080 (LISTEN)
```

Regular shell commands work as normal:

```
[ai@openfang ~]$ ls -la
[ai@openfang ~]$ grep -r "error" /var/log/
[ai@openfang ~]$ vim config.toml
```

## Security Model

OpenFang OS follows a defense-in-depth model:

1. **Hardware**: Secure Boot + TPM2 attestation
2. **Kernel**: Hardening flags, read-only rootfs
3. **Init**: Minimal services, each sandboxed
4. **Agents**: Isolated cgroups + namespaces + AppArmor
5. **Network**: Default-deny firewall, no open ports by default
6. **Updates**: Signed packages, automatic security patches

## License

OpenFang OS is MIT licensed. The OpenFang agent runtime is licensed separately — see [RightNow-AI/openfang](https://github.com/RightNow-AI/openfang).

## Contributing

PRs welcome. See [docs/contributing.md](docs/contributing.md).

```bash
# Development workflow
make dev-shell   # Drop into the build environment
make test-iso    # Build a minimal test ISO
make lint        # Run all linters
```
