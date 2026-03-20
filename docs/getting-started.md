# Getting Started with OpenFang OS

## What Is OpenFang OS?

OpenFang OS is a minimal, security-hardened Linux distribution where AI agents are first-class citizens. It combines:

- **Alpine Linux** as the base (small, fast, musl libc)
- **Linux 6.6 LTS** kernel with security hardening
- **OpenFang** — an open-source Rust agent runtime (autonomous AI workers)
- **aish** — an AI-powered shell that understands natural language
- **openfang-ctl** — a system control tool

---

## Requirements

### Hardware (minimum)
| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 64-bit, 1 core | 4+ cores |
| RAM | 512MB | 4GB+ |
| Disk | 4GB | 20GB+ SSD |
| Network | Ethernet | Ethernet + optional WiFi |

### For building
- Docker 24+
- 8GB free disk space

---

## Quick Start (QEMU)

The fastest way to try OpenFang OS is in a VM:

```bash
# 1. Clone the repo
git clone https://github.com/RightNow-AI/openfang-OS
cd openfang-OS

# 2. Build the ISO (requires Docker)
make iso

# 3. Run in QEMU
make run
```

This boots a live environment. No changes are persisted — perfect for testing.

---

## Installation

### 1. Boot the ISO

Flash the ISO to a USB drive:

```bash
# Linux
sudo dd if=build/output/openfang-os-0.1.0-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fsync

# macOS
sudo diskutil unmountDisk /dev/diskX
sudo dd if=build/output/openfang-os-0.1.0-x86_64.iso of=/dev/rdiskX bs=4m
```

### 2. Run the Installer

Boot from USB and run:

```bash
openfang-install
```

The installer will guide you through:

1. Disk selection
2. Hostname configuration
3. LUKS2 encryption passphrase
4. LLM provider configuration (OpenAI, Claude, Ollama, etc.)
5. SSH public key setup
6. GRUB installation

### 3. First Boot

After rebooting into the installed system:

```bash
# SSH in (password auth is disabled — use your key)
ssh ai@<your-ip>

# You'll land in aish (AI Shell)
[ai@openfang ~]$

# Check system status
openfang-ctl status

# Start all agents
openfang-ctl agents start-all
```

---

## Using aish (AI Shell)

`aish` is the default shell. It works like a normal shell but also understands natural language.

### Regular Commands
```bash
[ai@openfang ~]$ ls -la
[ai@openfang ~]$ ps aux
[ai@openfang ~]$ vim /etc/openfang/config.toml
```

### Natural Language Commands
```bash
[ai@openfang ~]$ show me all processes using more than 100MB of memory
→ ps aux --sort=-%mem | awk 'NR==1 || $6 > 102400'
  [Run? Y/n]: Y
USER       PID  CPU  MEM    VSZ   RSS ...

[ai@openfang ~]$ find all log files older than 7 days and delete them
→ find /var/log -name "*.log" -mtime +7 -exec rm {} \;
  ⚠  DESTRUCTIVE COMMAND
  Run anyway? [y/N]: y

[ai@openfang ~]$ what's listening on port 8080?
→ lsof -i :8080
  (running...)
```

### Built-in Help
```bash
help how do I set up a cron job?
help what does the security-guard agent do?
help show me how to add an SSH key
```

### aish Keyboard Shortcuts
| Key | Action |
|-----|--------|
| `↑` / `↓` | History navigation |
| `Ctrl-A` | Beginning of line |
| `Ctrl-E` | End of line |
| `Ctrl-R` | Reverse history search |
| `Ctrl-C` | Cancel current input |
| `Ctrl-D` | Exit aish |

---

## Using openfang-ctl

`openfang-ctl` is the system management tool:

```bash
# System overview
openfang-ctl status

# System information
openfang-ctl info

# Agent management
openfang-ctl agents list
openfang-ctl agents start system-monitor
openfang-ctl agents stop security-guard
openfang-ctl agents restart ai-assistant
openfang-ctl agents start-all

# View logs
openfang-ctl logs                     # System logs
openfang-ctl logs security-guard      # Agent-specific logs
openfang-ctl logs system-monitor -f   # Follow logs

# Configuration
openfang-ctl config show
openfang-ctl config get llm.model
openfang-ctl config set llm.model gpt-4o
openfang-ctl config edit              # Opens in $EDITOR

# Ask the AI assistant
openfang-ctl ask "how do I add a firewall rule?"

# Updates
openfang-ctl update --check   # Check for updates
openfang-ctl update           # Apply updates
```

---

## Configuring the LLM

Edit `/etc/openfang/config.toml`:

```bash
openfang-ctl config edit
```

### OpenAI
```toml
[llm]
provider = "openai"
api_key  = "sk-..."
model    = "gpt-4o"
```

### Claude (Anthropic)
```toml
[llm]
provider = "anthropic"
api_key  = "sk-ant-..."
model    = "claude-opus-4-6"
```

### Local Ollama
```toml
[llm]
provider = "ollama"
base_url = "http://localhost:11434"
model    = "llama3.2"
api_key  = ""
```

After changing the config, restart the agent runtime:
```bash
rc-service openfang restart
```

---

## Adding Custom Agents

Create a file in `/etc/openfang/agents/my-agent.toml`:

```toml
[agent]
name        = "my-agent"
description = "My custom agent"
enabled     = true
schedule    = "*/10 * * * *"  # Every 10 minutes

[llm]
model       = "gpt-4o-mini"
max_tokens  = 256
system_prompt = "You are a helpful agent that..."
```

Then restart OpenFang:
```bash
rc-service openfang restart
openfang-ctl agents list
```

---

## Security

See [security.md](security.md) for a full description of the security model.

Key points:
- **No password login** — SSH key only
- **LUKS2 encryption** on the root partition
- **AppArmor** profiles for all services
- **nftables** firewall — default deny
- **Automatic security updates** enabled by default

To temporarily allow a port:
```bash
# Allow port 3000 (temporary — lost on reboot)
nft add rule inet openfang_firewall input tcp dport 3000 accept

# Permanent: edit /etc/openfang/config.toml
openfang-ctl config set security.firewall_allow_ports "[22, 8080, 3000]"
rc-service nftables restart
```

---

## Troubleshooting

### OpenFang won't start
```bash
rc-service openfang status
cat /var/log/openfang/openfang.log
```

### aish AI features not working
```bash
# Check API key
openfang-ctl config get llm.api_key

# Test API connectivity
curl https://api.openai.com/v1/models -H "Authorization: Bearer $YOUR_KEY"
```

### Can't SSH in
```bash
# Check SSH key is correct
cat /home/ai/.ssh/authorized_keys

# Check sshd is running
rc-service sshd status

# Check firewall
nft list ruleset
```

### Disk full
```bash
# Find large files
find / -xdev -size +100M -exec ls -lh {} \; 2>/dev/null

# Clean logs
find /var/log -name "*.log" -mtime +7 -delete

# Check agent logs
du -sh /var/log/openfang/agents/*
```
