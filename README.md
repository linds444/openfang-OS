# OpenFang OS

**A full desktop Linux operating system built on Ubuntu 24.04 LTS, centered on the [OpenFang](https://github.com/RightNow-AI/openfang) AI agent runtime.**

OpenFang OS is a complete, usable desktop OS — Firefox, LibreOffice, VLC, file manager, everything you expect — with AI built in at every level. Boot it, browse the web, open documents, and run AI agents in the background, all without configuration.

---

## What You Get

| Category | Applications |
|----------|-------------|
| **Web** | Firefox (from Mozilla's official repo, not snap) |
| **Office** | LibreOffice Writer, Calc, Impress |
| **Files** | Thunar file manager with archive support |
| **Media** | VLC, GIMP, Ristretto image viewer |
| **Terminal** | XFCE4 Terminal running `aish` (AI Shell) |
| **System** | Task Manager, Disk, Settings, Calculator |
| **AI** | AI Shell, AI Assistant, Agent Runtime (OpenFang) |
| **Desktop** | XFCE4, Arc-Dark theme, Papirus icons |

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     XFCE4 Desktop                            │
│  Firefox · LibreOffice · Thunar · VLC · GIMP · Terminal      │
│  LightDM login · Arc-Dark theme · Papirus icons             │
├──────────────────────────────────────────────────────────────┤
│                  AI Layer (OpenFang)                          │
│  aish (AI Shell)  ·  openfang-ctl  ·  AI Assistant          │
│  system-monitor  ·  security-guard  ·  ai-assistant agents   │
├──────────────────────────────────────────────────────────────┤
│               Ubuntu 24.04 LTS (Noble Numbat)                │
│  systemd  ·  NetworkManager  ·  AppArmor  ·  UFW firewall   │
│  OpenSSH  ·  fail2ban  ·  unattended-upgrades               │
├──────────────────────────────────────────────────────────────┤
│              Linux 6.6 LTS Kernel (Hardened)                 │
│  KASLR · SMEP · SMAP · Lockdown · cgroups v2 · LUKS2       │
└──────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Requirements
- Docker 24+ (for building)
- 20GB free disk space
- `qemu-system-x86_64` + KVM (for testing in a VM)

### Build and Run

```bash
# 1. Clone
git clone https://github.com/RightNow-AI/openfang-OS
cd openfang-OS

# 2. Build the ISO (takes ~20 min first time, cached after)
make iso

# 3. Run with full desktop in QEMU (requires KVM + GUI)
make run-gui

# 4. Or run headless (console only)
make run
```

### Flash to USB / install

```bash
# Flash to USB
sudo dd if=build/output/openfang-os-0.1.0-amd64.iso of=/dev/sdX bs=4M status=progress conv=fsync

# Boot from USB, then open "Install OpenFang OS" from the desktop
# Or run in a terminal:
sudo openfang-install
```

---

## First Boot Experience

### Live Environment

Boot the ISO and you're immediately in the XFCE4 desktop, logged in as `ai`:

- **Firefox** is on the taskbar — open it and browse the web
- **AI Terminal** is on the desktop — type natural language commands
- **AI Assistant** is on the desktop — ask anything
- **Install OpenFang OS** icon installs to your hard disk

### Configure AI (optional for live, required for agents)

```bash
# Open a terminal and configure your LLM:
openfang-ctl config set llm.provider openai
openfang-ctl config set llm.api_key "sk-..."
openfang-ctl config set llm.model gpt-4o

# Or use Claude:
openfang-ctl config set llm.provider anthropic
openfang-ctl config set llm.api_key "sk-ant-..."
openfang-ctl config set llm.model claude-opus-4-6

# Or use local Ollama (no API key needed):
openfang-ctl config set llm.provider ollama
openfang-ctl config set llm.base_url http://localhost:11434
openfang-ctl config set llm.model llama3.2

# Start the AI agent runtime
sudo systemctl start openfang

# Check everything is working
openfang-ctl status
```

---

## The AI Shell (aish)

Open the AI Terminal from the desktop and type naturally:

```
[ai@openfang ~]$ find all PDF files in my Downloads
→ find ~/Downloads -name "*.pdf" -type f
  [Run? Y/n]: Y
/home/ai/Downloads/report.pdf
/home/ai/Downloads/manual.pdf

[ai@openfang ~]$ what process is using the most memory right now
→ ps aux --sort=-%mem | head -10
  (running...)

[ai@openfang ~]$ compress the photos folder to a zip file
→ zip -r photos.zip ~/Photos/
  [Run? Y/n]: Y

[ai@openfang ~]$ open firefox to google.com
→ firefox https://google.com &
  (running...)
```

Regular shell commands work normally — just type them:

```bash
ls -la
git clone https://github.com/...
python3 my_script.py
vim config.toml
```

---

## AI Agents (Background Automation)

OpenFang runs three agents automatically once configured:

| Agent | What it does | Schedule |
|-------|-------------|---------|
| `system-monitor` | Watches CPU/RAM/disk, sends alerts | Every 60s |
| `security-guard` | Detects intrusion, auto-bans attackers | Every 5min |
| `ai-assistant` | Answers questions via `openfang-ctl ask` | On demand |

```bash
# Manage agents
openfang-ctl agents list
openfang-ctl agents start system-monitor
openfang-ctl agents logs security-guard -f

# Ask the assistant
openfang-ctl ask "how do I add a printer?"
openfang-ctl ask "what's using all my disk space?"
```

Add your own agents in `/etc/openfang/agents/` — see [docs/agents.md](docs/agents.md).

---

## Security

- **LUKS2 full-disk encryption** (installed system)
- **AppArmor** profiles for all services
- **UFW firewall** (deny-by-default)
- **fail2ban** for SSH/service protection
- **Unattended security upgrades** enabled
- **No default open ports** — only SSH (22) and OpenFang API (8080/localhost)
- Kernel hardening: KASLR, SMEP, SMAP, sysctl security defaults

---

## Project Layout

```
openfang-OS/
├── README.md
├── Makefile                     # make iso / make run-gui / make image
├── openfang.toml.example        # Config template
├── build/
│   ├── Dockerfile               # Ubuntu 24.04 build container
│   └── scripts/
│       ├── build.sh             # debootstrap + package install
│       ├── iso.sh               # casper live ISO creation
│       └── image.sh             # flashable disk image
├── kernel/
│   └── config-6.6               # Hardened kernel config
├── rootfs/                      # OS overlay (applied over Ubuntu base)
│   ├── etc/
│   │   ├── systemd/system/      # systemd services
│   │   ├── lightdm/             # Display manager config
│   │   ├── xdg/xfce4/           # XFCE4 default config
│   │   ├── openfang/            # OpenFang config
│   │   ├── apparmor.d/          # AppArmor profiles
│   │   ├── sysctl.d/            # Kernel hardening
│   │   └── sudoers.d/           # Sudo rules
│   ├── usr/
│   │   ├── share/applications/  # .desktop app launchers
│   │   └── lib/openfang/        # Helper scripts
│   └── etc/skel/Desktop/        # Default desktop icons
├── aish/                        # AI Shell (Rust)
├── openfang-ctl/                # Control tool (Rust)
├── agents/                      # Agent configs
├── installer/install.sh         # Interactive disk installer
└── docs/                        # Documentation
```

---

## License

MIT. OpenFang agent runtime is licensed separately — see [RightNow-AI/openfang](https://github.com/RightNow-AI/openfang).
