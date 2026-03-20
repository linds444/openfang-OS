# OpenFang OS Security Model

OpenFang OS uses defense-in-depth: multiple independent layers of protection. Compromising one layer should not compromise the system.

## Layer 1: Hardware Security

### Disk Encryption (LUKS2)
- All data at rest is encrypted with AES-256-XTS
- Key derivation: Argon2id with high memory/time cost
- The encrypted volume must be unlocked at every boot

### Secure Boot
- GRUB is signed with the OpenFang OS signing key
- Prevents booting modified kernels or bootloaders
- Combined with TPM2 for remote attestation

### TPM2 Attestation
- System measurements (firmware, bootloader, kernel) stored in PCRs
- Optional: bind LUKS key to PCR values (keyless boot on unmodified system)

---

## Layer 2: Kernel Hardening

OpenFang OS uses Linux 6.6 LTS with these security features enabled:

| Feature | Effect |
|---------|--------|
| KASLR | Kernel and module base addresses randomized |
| SMEP | Kernel cannot execute user-space code |
| SMAP | Kernel cannot accidentally access user-space memory |
| Lockdown | Restricts /dev/mem, kexec, kernel module loading |
| Stack protector | Detects stack overflow attacks |
| INIT_ON_ALLOC/FREE | Zeroes memory on allocation/free (prevents info leaks) |
| Heap freelist randomization | Makes heap exploitation harder |
| Fortify source | Additional bounds checking in libc |
| Module signing | Only signed modules can load |

### sysctl hardening (`/etc/sysctl.d/99-openfang-hardening.conf`)

```ini
kernel.randomize_va_space = 2      # Full ASLR
kernel.kptr_restrict = 2           # Hide kernel pointers
kernel.dmesg_restrict = 1          # Restrict dmesg to root
kernel.unprivileged_bpf_disabled = 1  # Restrict BPF
net.core.bpf_jit_harden = 2       # Harden BPF JIT
kernel.yama.ptrace_scope = 2       # Restrict ptrace
fs.protected_hardlinks = 1         # Prevent hardlink attacks
fs.protected_symlinks = 1          # Prevent symlink attacks
net.ipv4.tcp_syncookies = 1        # SYN flood protection
```

---

## Layer 3: Mandatory Access Control (AppArmor)

Every service and the AI agent runtime has an AppArmor profile in `/etc/apparmor.d/`.

### openfang profile
- Can only read `/etc/openfang/`
- Can write to `/data/openfang/` and `/var/log/openfang/`
- Network access allowed (HTTPS to LLM APIs)
- Explicitly denied: write to `/etc/passwd`, `/etc/shadow`, `/proc/sys/`

### aish profile
- Can execute user commands (with user confirmation)
- Cannot run `sudo` or `su` directly
- Reads user's home directory

To view active profiles:
```bash
aa-status
```

To enforce a profile:
```bash
aa-enforce /etc/apparmor.d/openfang
```

---

## Layer 4: Firewall (nftables)

Default policy: **drop all inbound, allow all outbound**.

Allowed inbound:
- `22/tcp` — SSH
- `8080/tcp` — OpenFang API (localhost only by default)

Configuration in `/etc/nftables.conf`.

To add a temporary rule:
```bash
nft add rule inet openfang_firewall input tcp dport 3000 accept
```

To add a permanent rule, edit `/etc/openfang/config.toml`:
```toml
[security]
firewall_allow_ports = [22, 8080, 3000]
```

---

## Layer 5: Authentication

### SSH
- **Password authentication: disabled**
- **Root login: disabled**
- Only `ai` user with SSH key authentication
- Configuration: `/etc/ssh/sshd_config`

### OpenFang API
- Protected by Bearer token authentication
- Generate a token: `openfang-ctl generate-token`
- Set in config: `openfang-ctl config set agents.api.auth_token <token>`

---

## Layer 6: Agent Sandboxing

Each OpenFang agent is isolated:

```
Agent "security-guard"
├── cgroup v2
│   ├── cpu.max: 50% of 1 core
│   ├── memory.max: 256MB
│   └── io.max: 10MB/s
├── Linux namespaces
│   ├── PID namespace (isolated process tree)
│   ├── Network namespace (or shared with policy)
│   └── Mount namespace (read-only overlay)
├── AppArmor profile
└── Seccomp filter (deny dangerous syscalls)
```

---

## Layer 7: Security Guard Agent

The `security-guard` agent runs every 5 minutes and:

1. **Scans auth logs** for SSH brute-force attempts
2. **Auto-bans IPs** that exceed the threshold (default: 10 failures in 5 minutes)
3. **Monitors file integrity** of critical system files
4. **Checks for CVEs** in installed packages (daily)
5. **Scans for unexpected open ports**

Auto-ban example:
```bash
# An IP that brute-forced SSH will be blocked:
nft add element inet openfang_firewall blocked_ips { 1.2.3.4 }
```

View bans:
```bash
cat /var/log/openfang/agents/security-guard-bans.log
```

---

## Security Best Practices

### Regular Updates
```bash
openfang-ctl update
```

Or let it happen automatically (enabled by default):
```toml
[security]
auto_update = true
```

### Monitoring
```bash
# View security events
openfang-ctl logs security-guard -f

# Get a summary
openfang-ctl status
```

### Rotate API Keys
Regularly rotate your LLM API keys:
```bash
openfang-ctl config set llm.api_key "sk-new-key"
rc-service openfang restart
```

### SSH Key Rotation
```bash
# Generate a new key pair
ssh-keygen -t ed25519 -C "openfang-$(date +%Y)"

# Add new key
echo "ssh-ed25519 AAAA..." >> /home/ai/.ssh/authorized_keys

# Remove old key
vim /home/ai/.ssh/authorized_keys
```

### Review Agent Logs
```bash
# Check for any anomalies
openfang-ctl logs system-monitor | grep -E "warning|critical"
openfang-ctl logs security-guard | grep -E "threat|ban|blocked"
```

---

## Security Reporting

Report vulnerabilities at: https://github.com/RightNow-AI/openfang-OS/issues

Please use responsible disclosure — allow 90 days for a fix before public disclosure.
