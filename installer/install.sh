#!/bin/bash
# OpenFang OS — Interactive Disk Installer
# Run this from the live environment to install to disk.

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
ask()     { echo -en "${BOLD}$*${RESET} "; }

# ─── Check prerequisites ──────────────────────────────────────────────────────
check_root() {
    [ "$(id -u)" -eq 0 ] || error "Installer must run as root."
}

check_uefi() {
    if [ -d /sys/firmware/efi ]; then
        BOOT_MODE="uefi"
    else
        BOOT_MODE="bios"
    fi
    info "Boot mode: ${BOOT_MODE}"
}

# ─── Welcome ──────────────────────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║         OpenFang OS Installer v0.1.0         ║"
    echo "  ║   AI-Native Linux OS · Alpine-based · Rust   ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo "  This installer will:"
    echo "    1. Partition a disk (EFI + /boot + LUKS2 encrypted root)"
    echo "    2. Install OpenFang OS"
    echo "    3. Configure bootloader (GRUB)"
    echo "    4. Set up AI configuration"
    echo
    warn "All data on the target disk will be ERASED."
    echo
}

# ─── Disk selection ───────────────────────────────────────────────────────────
select_disk() {
    info "Available disks:"
    echo
    lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -v "loop\|rom" | head -20
    echo
    ask "Target disk (e.g. /dev/sda, /dev/nvme0n1):"
    read -r TARGET_DISK

    [ -b "${TARGET_DISK}" ] || error "Not a block device: ${TARGET_DISK}"

    DISK_SIZE=$(lsblk -d -n -o SIZE "${TARGET_DISK}")
    echo
    warn "You selected: ${TARGET_DISK} (${DISK_SIZE})"
    ask "All data will be ERASED. Type 'yes' to continue:"
    read -r CONFIRM
    [ "${CONFIRM}" = "yes" ] || error "Aborted."
}

# ─── Hostname ─────────────────────────────────────────────────────────────────
get_hostname() {
    ask "Hostname [openfang]:"
    read -r HOSTNAME
    HOSTNAME="${HOSTNAME:-openfang}"
}

# ─── Encryption passphrase ────────────────────────────────────────────────────
get_passphrase() {
    echo
    info "Disk encryption (LUKS2)"
    echo "  Your root partition will be encrypted with AES-256-XTS."
    echo
    while true; do
        ask "Encryption passphrase:"
        read -rs LUKS_PASS
        echo
        ask "Confirm passphrase:"
        read -rs LUKS_PASS2
        echo
        if [ "${LUKS_PASS}" = "${LUKS_PASS2}" ]; then
            [ -n "${LUKS_PASS}" ] || { warn "Passphrase cannot be empty."; continue; }
            break
        fi
        warn "Passphrases do not match. Try again."
    done
}

# ─── LLM Configuration ────────────────────────────────────────────────────────
get_llm_config() {
    echo
    info "AI / LLM Configuration"
    echo "  OpenFang supports OpenAI, Anthropic, Ollama, Groq, and more."
    echo
    ask "LLM provider [openai]:"
    read -r LLM_PROVIDER
    LLM_PROVIDER="${LLM_PROVIDER:-openai}"

    case "${LLM_PROVIDER}" in
        ollama)
            ask "Ollama URL [http://localhost:11434]:"
            read -r LLM_URL
            LLM_URL="${LLM_URL:-http://localhost:11434}"
            LLM_KEY=""
            ask "Model [llama3.2]:"
            read -r LLM_MODEL
            LLM_MODEL="${LLM_MODEL:-llama3.2}"
            ;;
        anthropic)
            ask "Anthropic API key:"
            read -rs LLM_KEY
            echo
            LLM_URL="https://api.anthropic.com/v1"
            ask "Model [claude-opus-4-6]:"
            read -r LLM_MODEL
            LLM_MODEL="${LLM_MODEL:-claude-opus-4-6}"
            ;;
        *)
            ask "OpenAI API key:"
            read -rs LLM_KEY
            echo
            ask "Base URL [https://api.openai.com/v1]:"
            read -r LLM_URL
            LLM_URL="${LLM_URL:-https://api.openai.com/v1}"
            ask "Model [gpt-4o-mini]:"
            read -r LLM_MODEL
            LLM_MODEL="${LLM_MODEL:-gpt-4o-mini}"
            ;;
    esac
}

# ─── SSH Key ──────────────────────────────────────────────────────────────────
get_ssh_key() {
    echo
    info "SSH Configuration"
    echo "  Password login is disabled. You need an SSH public key."
    echo
    ask "Paste your SSH public key (or press Enter to skip):"
    read -r SSH_KEY
}

# ─── Partition ────────────────────────────────────────────────────────────────
partition_disk() {
    info "Partitioning ${TARGET_DISK}..."

    # Wipe existing signatures
    wipefs -af "${TARGET_DISK}"
    sgdisk -Z "${TARGET_DISK}"

    # Create GPT partition table
    if [ "${BOOT_MODE}" = "uefi" ]; then
        # EFI + boot + root
        sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI"   "${TARGET_DISK}"
        sgdisk -n 2:0:+512M -t 2:8300 -c 2:"boot"  "${TARGET_DISK}"
        sgdisk -n 3:0:0     -t 3:8309 -c 3:"root"  "${TARGET_DISK}"
    else
        # BIOS boot + boot + root
        sgdisk -n 1:0:+1M   -t 1:ef02 -c 1:"bios"  "${TARGET_DISK}"
        sgdisk -n 2:0:+512M -t 2:8300 -c 2:"boot"  "${TARGET_DISK}"
        sgdisk -n 3:0:0     -t 3:8309 -c 3:"root"  "${TARGET_DISK}"
    fi

    partprobe "${TARGET_DISK}"
    sleep 2

    # Determine partition names
    if echo "${TARGET_DISK}" | grep -q nvme; then
        EFI_PART="${TARGET_DISK}p1"
        BOOT_PART="${TARGET_DISK}p2"
        ROOT_PART="${TARGET_DISK}p3"
    else
        EFI_PART="${TARGET_DISK}1"
        BOOT_PART="${TARGET_DISK}2"
        ROOT_PART="${TARGET_DISK}3"
    fi

    success "Partitioned ${TARGET_DISK}"
}

# ─── Format ───────────────────────────────────────────────────────────────────
format_partitions() {
    info "Formatting partitions..."

    # EFI
    if [ "${BOOT_MODE}" = "uefi" ]; then
        mkfs.vfat -F32 -n "EFI" "${EFI_PART}"
        success "EFI partition formatted"
    fi

    # Boot
    mkfs.ext4 -L "openfang-boot" -q "${BOOT_PART}"
    success "Boot partition formatted"

    # LUKS2 root
    info "Setting up LUKS2 encryption on root partition..."
    echo -n "${LUKS_PASS}" | cryptsetup luksFormat \
        --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha512 \
        --pbkdf argon2id \
        --iter-time 3000 \
        --sector-size 4096 \
        -d - \
        "${ROOT_PART}"

    echo -n "${LUKS_PASS}" | cryptsetup luksOpen \
        -d - "${ROOT_PART}" openfang_root

    mkfs.ext4 -L "openfang-root" -q /dev/mapper/openfang_root
    success "Root partition encrypted and formatted"
}

# ─── Mount ────────────────────────────────────────────────────────────────────
mount_partitions() {
    info "Mounting partitions..."
    mkdir -p /mnt/openfang
    mount /dev/mapper/openfang_root /mnt/openfang
    mkdir -p /mnt/openfang/boot
    mount "${BOOT_PART}" /mnt/openfang/boot
    if [ "${BOOT_MODE}" = "uefi" ]; then
        mkdir -p /mnt/openfang/boot/efi
        mount "${EFI_PART}" /mnt/openfang/boot/efi
    fi
    success "Partitions mounted at /mnt/openfang"
}

# ─── Install system ───────────────────────────────────────────────────────────
install_system() {
    info "Installing OpenFang OS..."

    # Copy the live system (squashfs is already mounted at /)
    # This works because we boot from the live ISO
    rsync -ax --exclude={"/proc/*","/sys/*","/dev/*","/run/*","/tmp/*","/mnt/*"} \
        / /mnt/openfang/

    success "System files copied"
}

# ─── Generate fstab ───────────────────────────────────────────────────────────
generate_fstab() {
    info "Generating /etc/fstab..."

    ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/openfang_root)
    BOOT_UUID=$(blkid -s UUID -o value "${BOOT_PART}")

    cat > /mnt/openfang/etc/fstab << EOF
# OpenFang OS fstab — generated by installer
UUID=${ROOT_UUID}  /      ext4  defaults,noatime               0 1
UUID=${BOOT_UUID}  /boot  ext4  defaults,noatime               0 2
tmpfs              /tmp   tmpfs defaults,noatime,nosuid,nodev  0 0
tmpfs              /run   tmpfs defaults,noatime,nosuid,nodev  0 0
EOF

    if [ "${BOOT_MODE}" = "uefi" ]; then
        EFI_UUID=$(blkid -s UUID -o value "${EFI_PART}")
        echo "UUID=${EFI_UUID}  /boot/efi  vfat  umask=0077  0 2" >> /mnt/openfang/etc/fstab
    fi

    # crypttab
    LUKS_UUID=$(blkid -s UUID -o value "${ROOT_PART}")
    echo "openfang_root UUID=${LUKS_UUID} none luks,discard" > /mnt/openfang/etc/crypttab

    success "fstab and crypttab generated"
}

# ─── Configure system ─────────────────────────────────────────────────────────
configure_system() {
    info "Configuring system..."

    # Hostname
    echo "${HOSTNAME}" > /mnt/openfang/etc/hostname

    # Generate SSH host keys
    chroot /mnt/openfang ssh-keygen -A

    # Set up AI user SSH key
    if [ -n "${SSH_KEY}" ]; then
        mkdir -p /mnt/openfang/home/ai/.ssh
        echo "${SSH_KEY}" > /mnt/openfang/home/ai/.ssh/authorized_keys
        chmod 700 /mnt/openfang/home/ai/.ssh
        chmod 600 /mnt/openfang/home/ai/.ssh/authorized_keys
        chroot /mnt/openfang chown -R ai:ai /home/ai/.ssh
        success "SSH key installed for user 'ai'"
    else
        warn "No SSH key provided. You won't be able to SSH in unless you add one later."
    fi

    # Write OpenFang config
    cat > /mnt/openfang/etc/openfang/config.toml << EOF
# OpenFang OS Configuration — generated by installer

[system]
hostname = "${HOSTNAME}"
timezone = "UTC"
locale   = "en_US.UTF-8"

[user]
name  = "ai"
shell = "/usr/bin/aish"

[llm]
provider = "${LLM_PROVIDER}"
api_key  = "${LLM_KEY}"
base_url = "${LLM_URL}"
model    = "${LLM_MODEL}"
timeout  = 30

[aish]
confirm_before_run  = true
confirm_destructive = true
show_generated_cmd  = true
max_tokens          = 512
system_prompt       = ""

[agents]
enabled    = true
config_dir = "/etc/openfang/agents"
log_dir    = "/var/log/openfang/agents"

[agents.api]
host       = "127.0.0.1"
port       = 8080
auth_token = ""

[agents.system_monitor]
enabled  = true
interval = 60

[agents.security_guard]
enabled  = true
interval = 300

[agents.ai_assistant]
enabled = true

[security]
apparmor             = true
firewall_allow_ports = [22, 8080]
auto_update          = true
ssh_key_only         = true

[network]
interface = "eth0"
dhcp      = true

[storage]
encrypt_root  = true
readonly_root = false
data_mount    = "/data"

[logging]
level     = "info"
log_dir   = "/var/log/openfang"
max_size  = "100MB"
max_files = 10
EOF

    chmod 600 /mnt/openfang/etc/openfang/config.toml
    success "System configured"
}

# ─── Install bootloader ───────────────────────────────────────────────────────
install_bootloader() {
    info "Installing GRUB bootloader..."

    LUKS_UUID=$(blkid -s UUID -o value "${ROOT_PART}")

    # GRUB config for encrypted root
    mkdir -p /mnt/openfang/boot/grub
    cat > /mnt/openfang/boot/grub/grub.cfg << EOF
set default=0
set timeout=5

menuentry "OpenFang OS" {
    insmod part_gpt
    insmod cryptodisk
    insmod luks2
    insmod ext2
    cryptomount -u ${LUKS_UUID//-/}
    set root='cryptouuid/${LUKS_UUID//-/}'
    linux  /boot/vmlinuz \\
        root=/dev/mapper/openfang_root \\
        cryptdevice=UUID=${LUKS_UUID}:openfang_root \\
        init=/sbin/init \\
        quiet apparmor=1 security=apparmor \\
        mitigations=auto kaslr
    initrd /boot/initramfs
}

menuentry "OpenFang OS (recovery mode)" {
    insmod part_gpt
    insmod cryptodisk
    insmod luks2
    insmod ext2
    cryptomount -u ${LUKS_UUID//-/}
    set root='cryptouuid/${LUKS_UUID//-/}'
    linux  /boot/vmlinuz \\
        root=/dev/mapper/openfang_root \\
        cryptdevice=UUID=${LUKS_UUID}:openfang_root \\
        init=/sbin/init \\
        single
    initrd /boot/initramfs
}
EOF

    # Bind mounts for chroot
    for bind in proc sys dev dev/pts; do
        mount --bind "/$bind" "/mnt/openfang/$bind"
    done

    if [ "${BOOT_MODE}" = "uefi" ]; then
        chroot /mnt/openfang grub-install \
            --target=x86_64-efi \
            --efi-directory=/boot/efi \
            --bootloader-id=OpenFangOS \
            --removable
    else
        chroot /mnt/openfang grub-install \
            --target=i386-pc \
            "${TARGET_DISK}"
    fi

    # Unmount binds
    for bind in dev/pts dev sys proc; do
        umount "/mnt/openfang/$bind" 2>/dev/null || true
    done

    success "GRUB installed"
}

# ─── Cleanup ──────────────────────────────────────────────────────────────────
cleanup() {
    info "Cleaning up..."
    umount -R /mnt/openfang 2>/dev/null || true
    cryptsetup luksClose openfang_root 2>/dev/null || true
    success "Done"
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
    echo
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}  OpenFang OS installed successfully!        ${RESET}"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════${RESET}"
    echo
    echo "  Disk:     ${TARGET_DISK}"
    echo "  Hostname: ${HOSTNAME}"
    echo "  LLM:      ${LLM_PROVIDER} / ${LLM_MODEL}"
    echo
    echo "  First boot:"
    echo "    1. Remove the installation media"
    echo "    2. Boot the system"
    echo "    3. Enter your LUKS2 passphrase"
    echo "    4. Log in as 'ai' via SSH"
    echo "    5. Run: openfang-ctl status"
    echo
    if [ -z "${SSH_KEY}" ]; then
        warn "No SSH key was installed. Add one before rebooting:"
        echo "  echo 'ssh-ed25519 AAAA...' >> /mnt/openfang/home/ai/.ssh/authorized_keys"
    fi
    echo
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    check_root
    print_banner
    check_uefi
    select_disk
    get_hostname
    get_passphrase
    get_llm_config
    get_ssh_key

    echo
    info "Starting installation..."
    echo

    partition_disk
    format_partitions
    mount_partitions
    install_system
    generate_fstab
    configure_system
    install_bootloader
    cleanup
    print_summary
}

trap 'cleanup; error "Installation failed at line ${LINENO}"' ERR
main "$@"
