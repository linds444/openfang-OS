# Getting Started with OpenFang OS

## Overview

OpenFang OS is a complete desktop Linux OS based on Ubuntu 24.04 LTS with:
- Full XFCE4 desktop environment
- Firefox browser
- LibreOffice, VLC, GIMP, and all standard apps
- AI shell (`aish`) that understands natural language
- OpenFang agent runtime for background AI automation

---

## System Requirements

| | Minimum | Recommended |
|--|---------|-------------|
| CPU | 64-bit, 2 cores | 4+ cores |
| RAM | 2GB | 8GB (4GB for AI models) |
| Disk | 15GB | 50GB+ SSD |
| GPU | Any | Any (no GPU required) |
| Network | Optional | Ethernet/WiFi |

---

## Building the ISO

You need Docker 24+ and ~20GB free disk space.

```bash
git clone https://github.com/RightNow-AI/openfang-OS
cd openfang-OS

# Build (first run takes ~20-40 minutes, then cached)
make iso

# ISO will be at:
ls -lh build/output/openfang-os-*.iso
```

---

## Running in a VM (QEMU)

```bash
# Full desktop with GUI (recommended for testing)
make run-gui

# Headless / console mode
make run
```

For `run-gui` you need:
- `qemu-system-x86_64` with KVM
- SDL or GTK display backend
- At least 4GB RAM allocated

---

## Booting from USB

```bash
# Find your USB drive
lsblk

# Flash (replace /dev/sdX with your drive)
sudo dd if=build/output/openfang-os-0.1.0-amd64.iso \
         of=/dev/sdX bs=4M status=progress conv=fsync && sync
```

Boot from USB. You'll see the GRUB menu with options:
- **OpenFang OS (Live)** — try without installing
- **Install OpenFang OS to disk** — persistent installation
- **Safe graphics** — if display has issues

---

## Live Environment

The live environment boots directly to the XFCE4 desktop, logged in as user `ai`.

### Desktop layout

```
┌─────────────────────────────────────────────────────┐
│ [OpenFang ▼] [Firefox] [Files] [Terminal] [AI]      │  ← Taskbar
├─────────────────────────────────────────────────────┤
│                                                     │
│   [Firefox]    [AI Assistant]   [AI Terminal]       │  ← Desktop icons
│                                                     │
│   [Install]                                         │
│   OpenFang                                          │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Immediate things to try

1. **Open Firefox** — click the Firefox icon on the taskbar
2. **Open AI Terminal** — double-click "AI Terminal" on the desktop
3. **Ask AI Assistant** — double-click "AI Assistant" and type anything
4. **Open Files** — click the folder icon on the taskbar

---

## Installing to Disk

From the live environment, click **"Install OpenFang OS"** on the desktop, or open a terminal and run:

```bash
sudo openfang-install
```

The installer will ask:
1. **Target disk** — which disk to install to (ALL DATA WILL BE ERASED)
2. **Username and password** — your login credentials
3. **Disk encryption passphrase** — LUKS2 password (remember this!)
4. **LLM provider** — which AI backend to use
5. **Timezone** — your timezone

Installation takes about 5-10 minutes. After, remove the USB and reboot.

---

## First Login (After Installing)

Enter your LUKS2 passphrase at the boot screen, then log in with your username and password.

The desktop is identical to the live environment. All apps are immediately usable.

---

## Configuring the AI

For AI features to work, you need to configure an LLM provider. Open a terminal:

### Option 1: OpenAI

```bash
openfang-ctl config set llm.provider openai
openfang-ctl config set llm.api_key "sk-..."
openfang-ctl config set llm.model gpt-4o-mini
```

### Option 2: Anthropic (Claude)

```bash
openfang-ctl config set llm.provider anthropic
openfang-ctl config set llm.api_key "sk-ant-..."
openfang-ctl config set llm.model claude-opus-4-6
```

### Option 3: Local Ollama (free, private, no internet needed)

```bash
# Install Ollama first
curl -fsSL https://ollama.com/install.sh | sh

# Pull a model
ollama pull llama3.2

# Configure OpenFang to use it
openfang-ctl config set llm.provider ollama
openfang-ctl config set llm.base_url http://localhost:11434
openfang-ctl config set llm.model llama3.2
```

Then start the agent runtime:

```bash
sudo systemctl start openfang
sudo systemctl enable openfang   # auto-start on boot

# Check it's running
openfang-ctl status
```

---

## Using the AI Shell (aish)

Open a terminal from the taskbar or desktop. `aish` is the default shell.

### Type naturally

```bash
[ai@openfang ~]$ show me all files larger than 100MB
→ find / -xdev -size +100M -exec ls -lh {} \; 2>/dev/null

[ai@openfang ~]$ list all running services
→ systemctl list-units --type=service --state=running

[ai@openfang ~]$ how much disk space is being used
→ df -h

[ai@openfang ~]$ open firefox and go to youtube
→ firefox https://www.youtube.com &
```

### Safety features

- AI-generated commands show the command before running
- Type `Y` to run, `n` to skip
- Destructive commands (`rm -rf`, `dd`, etc.) require explicit confirmation

### Type regular shell commands as normal

```bash
ls -la
cd ~/Downloads
python3 script.py
git clone https://github.com/...
nano config.txt
```

---

## Common Tasks

### Install software

```bash
sudo apt install vlc
sudo apt install code          # VS Code
sudo apt install steam
sudo snap install spotify      # or via software center
```

Or just ask aish:

```bash
[ai@openfang ~]$ install the Discord app
→ wget -O discord.deb "https://discord.com/api/download?platform=linux&format=deb" && sudo dpkg -i discord.deb
```

### Connect to WiFi

Click the network icon in the taskbar (top right). Select your network and enter the password.

Or from the terminal:

```bash
nmcli device wifi connect "NetworkName" password "YourPassword"
```

### Change settings

Right-click the desktop → Settings, or use the Whisker Menu (top left) → Settings.

### Take a screenshot

Press `Print Screen` or use the Whisker Menu → Accessories → Screenshot.

### Update the system

```bash
openfang-ctl update
# Or:
sudo apt update && sudo apt upgrade
```

---

## AI Agents

Once OpenFang is running (`sudo systemctl start openfang`):

```bash
# See all agents
openfang-ctl agents list

# Start all agents
openfang-ctl agents start-all

# Ask the AI anything
openfang-ctl ask "why is my CPU at 100%?"
openfang-ctl ask "how do I set up a VPN?"
openfang-ctl ask "write a bash script to backup my home directory"

# View agent logs
openfang-ctl logs system-monitor -f
```

---

## Troubleshooting

### Display won't start
Boot with "safe graphics" option in GRUB. Then:
```bash
sudo apt install xserver-xorg-video-nouveau  # for NVIDIA
sudo apt install xserver-xorg-video-amdgpu   # for AMD
```

### No sound
```bash
pulseaudio --start
pavucontrol   # opens volume control GUI
```

### Can't connect to WiFi
```bash
sudo systemctl restart NetworkManager
nmcli radio wifi on
```

### OpenFang API not responding
```bash
sudo systemctl status openfang
sudo journalctl -u openfang -f
openfang-ctl config validate
```

### Firefox crashes
```bash
# Clear profile
rm -rf ~/.mozilla/firefox/*.default-release/sessionstore*
```

### Forgot LUKS passphrase
Recovery is not possible — this is by design. Keep a backup of your passphrase.

---

## Getting Help

```bash
# AI help (if configured)
help how do I add a user?
openfang-ctl ask "how do I mount a USB drive?"

# Manual pages
man ls
man systemctl
man firefox

# GitHub issues
# https://github.com/RightNow-AI/openfang-OS/issues
```
