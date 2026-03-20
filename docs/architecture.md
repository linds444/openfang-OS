# OpenFang OS Architecture

## Overview

```
┌───────────────────────────────────────────────────────────────────┐
│                        User Interface Layer                        │
│                                                                    │
│  ┌─────────────────────────┐  ┌──────────────────────────────┐   │
│  │     aish (AI Shell)     │  │    openfang-ctl (Control)    │   │
│  │  Rust · readline · LLM  │  │  Rust · clap · REST client  │   │
│  └─────────────────────────┘  └──────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────┘
                              │
                              ▼ HTTP (127.0.0.1:8080)
┌───────────────────────────────────────────────────────────────────┐
│                    OpenFang Agent Runtime                          │
│             (Rust · 137K LOC · 14 crates · 1767+ tests)           │
│                                                                    │
│  ┌──────────────┐  ┌────────────────┐  ┌─────────────────────┐   │
│  │system-monitor│  │security-guard  │  │   ai-assistant      │   │
│  │  cgroup/ns   │  │  cgroup/ns     │  │   cgroup/ns         │   │
│  └──────────────┘  └────────────────┘  └─────────────────────┘   │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │  Channel Adapters (40+): Slack, Discord, Telegram, ...     │   │
│  │  LLM Providers (27): OpenAI, Anthropic, Ollama, Groq, ... │   │
│  │  REST/WebSocket API (140+ endpoints)                       │   │
│  └────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────┘
                              │
┌───────────────────────────────────────────────────────────────────┐
│                        System Layer                                │
│                                                                    │
│  Alpine Linux (musl libc · BusyBox · OpenRC)                      │
│  nftables firewall  ·  AppArmor  ·  syslog-ng  ·  chrony          │
│  OpenSSH (key-only) ·  sysctl hardening                           │
└───────────────────────────────────────────────────────────────────┘
                              │
┌───────────────────────────────────────────────────────────────────┐
│                       Kernel Layer                                 │
│                                                                    │
│  Linux 6.6 LTS — Hardened Configuration                           │
│  KASLR · SMEP · SMAP · Lockdown · AppArmor LSM                   │
│  Namespaces · cgroups v2 · eBPF · DM-Crypt (LUKS2)               │
└───────────────────────────────────────────────────────────────────┘
                              │
┌───────────────────────────────────────────────────────────────────┐
│                      Hardware Layer                                │
│  TPM2 attestation · Secure Boot · LUKS2 full disk encryption      │
└───────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### aish (AI Shell)
**Location**: `aish/src/main.rs`
**Language**: Rust
**Purpose**: Default interactive shell with AI capabilities

Key behaviors:
1. **Command passthrough**: Regular shell commands (`ls`, `git`, `vim`) are executed directly
2. **NL detection**: Heuristic + keyword detection identifies natural language input
3. **LLM translation**: Natural language → shell command via OpenAI-compatible API
4. **Safety**: Destructive commands (rm -rf, dd, etc.) require explicit confirmation
5. **Session memory**: Conversation history sent with each LLM request for context

```
User input
    │
    ├─ built-in? (cd, exit, history) ──→ handle internally
    │
    ├─ natural language? ──→ LLM API ──→ show generated command
    │                                         │
    │                                    confirm? ──→ execute
    │
    └─ shell command ──→ destructive? ──→ confirm ──→ execute
                                │
                           not destructive ──→ execute directly
```

### openfang-ctl
**Location**: `openfang-ctl/src/main.rs`
**Language**: Rust
**Purpose**: System management CLI

Subcommands: `status`, `agents`, `config`, `logs`, `ask`, `info`, `update`, `generate-token`

Communicates with the OpenFang runtime via REST API at `http://127.0.0.1:8080`.

### OpenFang Agent Runtime
**Source**: [github.com/RightNow-AI/openfang](https://github.com/RightNow-AI/openfang)
**Language**: Rust
**Binary**: `/usr/bin/openfang`

The agent runtime is the heart of OpenFang OS. It:
- Manages autonomous agents that run on schedules
- Provides a REST/WebSocket API for control
- Connects to 27+ LLM providers
- Supports 40+ channel adapters

### Agent Sandboxing

Each agent runs in an isolated environment:

```
Agent process
├── Separate cgroup (CPU, memory, I/O limits)
├── Separate network namespace (or shared with restrictions)
├── AppArmor MAC policy
└── Seccomp syscall filter
```

### Boot Flow

```
GRUB
  │
  └─ Linux kernel (vmlinuz)
       │
       └─ initramfs
            ├─ Decrypt LUKS2 root (passphrase prompt)
            ├─ Mount root filesystem
            └─ /sbin/init (OpenRC)
                 ├─ sysinit: mount /proc /sys /dev, AppArmor
                 ├─ boot: fsck, networking basics
                 └─ default:
                      ├─ sshd
                      ├─ chrony (NTP)
                      ├─ syslog-ng
                      ├─ nftables (firewall)
                      └─ openfang (agent runtime)
                              └─ aish (login shell for user 'ai')
```

---

## Build System

```
make iso
  │
  ├─ make builder          → Build Docker build container
  │     └─ build/Dockerfile
  │
  ├─ make aish             → Compile aish (cargo build --release)
  │     └─ aish/src/main.rs
  │
  ├─ make openfang-ctl     → Compile openfang-ctl
  │     └─ openfang-ctl/src/main.rs
  │
  ├─ make rootfs           → Assemble rootfs overlay
  │     └─ rootfs/ → build/output/
  │
  └─ ISO build (in Docker)
        ├─ Download Alpine minirootfs
        ├─ Install packages via apk
        ├─ Apply rootfs overlay
        ├─ Install aish + openfang-ctl
        ├─ Create squashfs
        ├─ Build GRUB (BIOS + UEFI)
        └─ Create hybrid ISO via xorriso
```

---

## Filesystem Layout

```
/
├── boot/
│   ├── vmlinuz          Linux kernel
│   ├── initramfs        Initial ramdisk
│   └── grub/            GRUB configuration
│
├── etc/
│   ├── openfang/
│   │   ├── config.toml  Main configuration (secrets here)
│   │   └── agents/      Per-agent config files
│   ├── apparmor.d/      AppArmor profiles
│   ├── nftables.conf    Firewall rules
│   ├── sysctl.d/        Kernel hardening
│   └── init.d/openfang  OpenRC service
│
├── usr/bin/
│   ├── aish             AI Shell
│   ├── openfang         Agent runtime
│   └── openfang-ctl     Control tool
│
├── var/
│   ├── log/openfang/    System logs
│   │   └── agents/      Per-agent logs
│   └── lib/openfang/    Runtime state
│
├── data/                Persistent data (separate partition)
│   └── openfang/        Agent data, memory, artifacts
│
└── home/ai/             Default user home
    ├── .aish_config     aish configuration
    └── .ssh/            SSH keys
```

---

## Security Architecture

See [security.md](security.md) for full details.

```
Defense layers (outer → inner):
1. Network: nftables default-deny, allow-list
2. Authentication: SSH key-only, no root login
3. Kernel: KASLR, SMEP, SMAP, Lockdown
4. Mandatory Access Control: AppArmor (enforcing)
5. Namespaces: agents isolated in cgroup + network NS
6. Filesystem: LUKS2 encryption, /tmp on tmpfs
7. Runtime: Seccomp syscall filtering
```
