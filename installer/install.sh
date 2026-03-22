#!/bin/bash
# OpenFang OS — Disk Installer (Ubuntu 24.04 LTS)
# Run from the live environment to install to disk.
# Usage: sudo openfang-install  OR  sudo bash /usr/lib/openfang/install.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[1;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[ OK ]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERR ]${RESET} $*" >&2; exit 1; }
ask()     { echo -en "${BOLD}$*${RESET} "; }

[ "$(id -u)" -eq 0 ] || error "Run as root: sudo $0"

check_uefi() {
    if [ -d /sys/firmware/efi ]; then BOOT_MODE="uefi"
    else BOOT_MODE="bios"; fi
    info "Boot mode: ${BOOT_MODE}"
}

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'BANNER'
  ╔═══════════════════════════════════════════════════════╗
  ║         OpenFang OS Installer                         ║
  ║   AI-Native Desktop OS · Ubuntu 24.04 LTS · XFCE    ║
  ╚═══════════════════════════════════════════════════════╝
BANNER
    echo -e "${RESET}"
    echo "  This installer will:"
    echo "    • Partition your disk (EFI + /boot + LUKS2 encrypted root)"
    echo "    • Install OpenFang OS with full desktop (Firefox, LibreOffice, etc.)"
    echo "    • Configure the AI agent runtime"
    echo "    • Install GRUB bootloader"
    echo
    warn "ALL DATA ON THE TARGET DISK WILL BE PERMANENTLY ERASED."
    echo
}

select_disk() {
    info "Available disks:"
    echo
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -v "^loop\|rom"
    echo
    ask "Target disk [e.g. /dev/sda or /dev/nvme0n1]:"
    read -r TARGET_DISK
    [ -b "${TARGET_DISK}" ] || error "Not a block device: ${TARGET_DISK}"
    DISK_SIZE=$(lsblk -d -n -o SIZE "${TARGET_DISK}")
    echo
    warn "SELECTED: ${TARGET_DISK} (${DISK_SIZE}) — ALL DATA WILL BE ERASED"
    ask "Type 'yes' to continue:"
    read -r CONFIRM
    [ "${CONFIRM}" = "yes" ] || error "Aborted."
}

get_user_info() {
    echo
    ask "Username [ai]:"
    read -r USERNAME; USERNAME="${USERNAME:-ai}"

    ask "Full name [AI User]:"
    read -r FULLNAME; FULLNAME="${FULLNAME:-AI User}"

    while true; do
        ask "Password for ${USERNAME}:"
        read -rs USER_PASS; echo
        ask "Confirm password:"
        read -rs USER_PASS2; echo
        [ "${USER_PASS}" = "${USER_PASS2}" ] && [ -n "${USER_PASS}" ] && break
        warn "Passwords do not match or empty. Try again."
    done

    ask "Hostname [openfang]:"
    read -r HOSTNAME; HOSTNAME="${HOSTNAME:-openfang}"
}

get_passphrase() {
    echo
    info "Disk encryption (LUKS2 / AES-256-XTS)"
    while true; do
        ask "Encryption passphrase:"
        read -rs LUKS_PASS; echo
        ask "Confirm passphrase:"
        read -rs LUKS_PASS2; echo
        [ "${LUKS_PASS}" = "${LUKS_PASS2}" ] && [ -n "${LUKS_PASS}" ] && break
        warn "Passphrases do not match or empty."
    done
}

get_llm_config() {
    echo
    info "AI / LLM Configuration"
    echo "  Supported: OpenAI, Anthropic/Claude, Ollama (local), Groq, and more."
    echo
    ask "Provider [openai / anthropic / ollama]:"
    read -r LLM_PROVIDER; LLM_PROVIDER="${LLM_PROVIDER:-openai}"

    case "${LLM_PROVIDER}" in
        ollama)
            ask "Ollama base URL [http://localhost:11434]:"
            read -r LLM_URL; LLM_URL="${LLM_URL:-http://localhost:11434}"
            LLM_KEY=""; ask "Model [llama3.2]:"; read -r LLM_MODEL; LLM_MODEL="${LLM_MODEL:-llama3.2}"
            ;;
        anthropic)
            ask "Anthropic API key (sk-ant-...):"
            read -rs LLM_KEY; echo
            LLM_URL="https://api.anthropic.com/v1"
            ask "Model [claude-opus-4-6]:"
            read -r LLM_MODEL; LLM_MODEL="${LLM_MODEL:-claude-opus-4-6}"
            ;;
        *)
            ask "OpenAI API key (sk-...):"
            read -rs LLM_KEY; echo
            ask "Base URL [https://api.openai.com/v1]:"
            read -r LLM_URL; LLM_URL="${LLM_URL:-https://api.openai.com/v1}"
            ask "Model [gpt-4o-mini]:"
            read -r LLM_MODEL; LLM_MODEL="${LLM_MODEL:-gpt-4o-mini}"
            ;;
    esac
}

get_timezone() {
    ask "Timezone [UTC]:"
    read -r TIMEZONE; TIMEZONE="${TIMEZONE:-UTC}"
}

partition_disk() {
    info "Partitioning ${TARGET_DISK}..."
    wipefs -af "${TARGET_DISK}"
    sgdisk -Z "${TARGET_DISK}"

    if [ "${BOOT_MODE}" = "uefi" ]; then
        sgdisk -n 1:0:+1G   -t 1:ef00 -c 1:"EFI"  "${TARGET_DISK}"
        sgdisk -n 2:0:+2G   -t 2:8300 -c 2:"boot" "${TARGET_DISK}"
        sgdisk -n 3:0:0     -t 3:8309 -c 3:"root" "${TARGET_DISK}"
    else
        sgdisk -n 1:0:+1M   -t 1:ef02 -c 1:"bios" "${TARGET_DISK}"
        sgdisk -n 2:0:+2G   -t 2:8300 -c 2:"boot" "${TARGET_DISK}"
        sgdisk -n 3:0:0     -t 3:8309 -c 3:"root" "${TARGET_DISK}"
    fi

    partprobe "${TARGET_DISK}"; sleep 2

    if echo "${TARGET_DISK}" | grep -q "nvme\|mmcblk"; then
        PFX="${TARGET_DISK}p"
    else
        PFX="${TARGET_DISK}"
    fi

    if [ "${BOOT_MODE}" = "uefi" ]; then
        EFI_PART="${PFX}1"; BOOT_PART="${PFX}2"; ROOT_PART="${PFX}3"
    else
        BIOS_PART="${PFX}1"; BOOT_PART="${PFX}2"; ROOT_PART="${PFX}3"
    fi

    success "Partitioned ${TARGET_DISK}"
}

format_partitions() {
    info "Formatting partitions..."

    [ "${BOOT_MODE}" = "uefi" ] && mkfs.vfat -F32 -n "EFI" "${EFI_PART}"
    mkfs.ext4 -L "openfang-boot" -q "${BOOT_PART}"

    info "Setting up LUKS2 encryption..."
    echo -n "${LUKS_PASS}" | cryptsetup luksFormat \
        --type luks2 --cipher aes-xts-plain64 --key-size 512 \
        --hash sha512 --pbkdf argon2id --iter-time 3000 \
        --sector-size 4096 -d - "${ROOT_PART}"

    echo -n "${LUKS_PASS}" | cryptsetup luksOpen -d - "${ROOT_PART}" openfang_root
    mkfs.ext4 -L "openfang-root" -q /dev/mapper/openfang_root

    success "Partitions formatted"
}

mount_partitions() {
    mkdir -p /mnt/openfang
    mount /dev/mapper/openfang_root /mnt/openfang
    mkdir -p /mnt/openfang/boot
    mount "${BOOT_PART}" /mnt/openfang/boot
    if [ "${BOOT_MODE}" = "uefi" ]; then
        mkdir -p /mnt/openfang/boot/efi
        mount "${EFI_PART}" /mnt/openfang/boot/efi
    fi
    success "Mounted at /mnt/openfang"
}

install_system() {
    info "Installing OpenFang OS (this takes a few minutes)..."
    # The live system is in /run/casper or / — rsync it
    rsync -ax \
        --exclude={"/proc/*","/sys/*","/dev/*","/run/*","/tmp/*","/mnt/*","/media/*","/lost+found"} \
        / /mnt/openfang/
    success "System files copied"
}

configure_system() {
    info "Configuring system..."

    # Hostname
    echo "${HOSTNAME}" > /mnt/openfang/etc/hostname
    cat > /mnt/openfang/etc/hosts << EOF
127.0.0.1   localhost
127.0.1.1   ${HOSTNAME} ${HOSTNAME}.local
::1         localhost ip6-localhost ip6-loopback
EOF

    # Timezone
    chroot /mnt/openfang ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
    chroot /mnt/openfang dpkg-reconfigure -f noninteractive tzdata

    # Create user
    chroot /mnt/openfang useradd -m -s /usr/bin/aish \
        -c "${FULLNAME}" -G sudo,audio,video,plugdev,netdev ai 2>/dev/null || true
    echo "ai:${USER_PASS}" | chroot /mnt/openfang chpasswd

    # Disable autologin for installed system (live env had it)
    sed -i '/^autologin/d' /mnt/openfang/etc/lightdm/lightdm.conf.d/50-openfang.conf

    # SSH host keys
    chroot /mnt/openfang ssh-keygen -A

    # Write OpenFang config
    mkdir -p /mnt/openfang/etc/openfang
    cat > /mnt/openfang/etc/openfang/config.toml << EOF
# OpenFang OS Configuration — generated by installer

[system]
hostname = "${HOSTNAME}"
timezone = "${TIMEZONE}"
locale   = "en_US.UTF-8"

[user]
name  = "${USERNAME}"
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

[network]
interface = "eth0"
dhcp      = true

[storage]
encrypt_root  = true
data_mount    = "/data"

[logging]
level     = "info"
log_dir   = "/var/log/openfang"
max_size  = "100MB"
max_files = 10
EOF
    chmod 640 /mnt/openfang/etc/openfang/config.toml

    # Generate crypttab / fstab
    LUKS_UUID=$(blkid -s UUID -o value "${ROOT_PART}")
    ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/openfang_root)
    BOOT_UUID=$(blkid -s UUID -o value "${BOOT_PART}")

    echo "openfang_root UUID=${LUKS_UUID} none luks,discard" \
        > /mnt/openfang/etc/crypttab

    cat > /mnt/openfang/etc/fstab << EOF
# OpenFang OS fstab
UUID=${ROOT_UUID}  /      ext4  defaults,noatime  0 1
UUID=${BOOT_UUID}  /boot  ext4  defaults,noatime  0 2
tmpfs              /tmp   tmpfs defaults,noatime,nosuid,nodev,size=2G  0 0
EOF

    if [ "${BOOT_MODE}" = "uefi" ]; then
        EFI_UUID=$(blkid -s UUID -o value "${EFI_PART}")
        echo "UUID=${EFI_UUID}  /boot/efi  vfat  umask=0077  0 2" \
            >> /mnt/openfang/etc/fstab
    fi

    success "System configured"
}

install_bootloader() {
    info "Installing GRUB bootloader..."
    LUKS_UUID=$(blkid -s UUID -o value "${ROOT_PART}")

    # Update GRUB defaults for encrypted root
    cat > /mnt/openfang/etc/default/grub << EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="OpenFang OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX="cryptdevice=UUID=${LUKS_UUID}:openfang_root apparmor=1 security=apparmor mitigations=auto kaslr"
GRUB_ENABLE_CRYPTODISK=y
GRUB_PRELOAD_MODULES="part_gpt part_msdos luks2 cryptodisk"
EOF

    # Bind mounts
    for fs in proc sys dev dev/pts; do
        mount --bind "/$fs" "/mnt/openfang/$fs"
    done

    chroot /mnt/openfang update-initramfs -u -k all

    if [ "${BOOT_MODE}" = "uefi" ]; then
        chroot /mnt/openfang grub-install \
            --target=x86_64-efi \
            --efi-directory=/boot/efi \
            --bootloader-id="OpenFang OS" \
            --removable
    else
        chroot /mnt/openfang grub-install \
            --target=i386-pc \
            "${TARGET_DISK}"
    fi

    chroot /mnt/openfang update-grub

    for fs in dev/pts dev sys proc; do
        umount "/mnt/openfang/$fs" 2>/dev/null || true
    done

    success "GRUB installed"
}

cleanup() {
    info "Unmounting..."
    umount -R /mnt/openfang 2>/dev/null || true
    cryptsetup luksClose openfang_root 2>/dev/null || true
}

print_summary() {
    echo
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}   OpenFang OS installed successfully!          ${RESET}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo
    echo "  Disk:      ${TARGET_DISK}"
    echo "  Hostname:  ${HOSTNAME}"
    echo "  User:      ${USERNAME}"
    echo "  Timezone:  ${TIMEZONE}"
    echo "  LLM:       ${LLM_PROVIDER} / ${LLM_MODEL}"
    echo
    echo "  First boot:"
    echo "    1. Remove USB / reboot"
    echo "    2. Enter LUKS2 passphrase at boot"
    echo "    3. Log in as '${USERNAME}'"
    echo "    4. Firefox, LibreOffice, and all apps are ready"
    echo "    5. Open AI Assistant from the desktop"
    echo
}

trap 'cleanup; error "Installation failed at line ${LINENO}"' ERR

main() {
    print_banner
    check_uefi
    select_disk
    get_user_info
    get_passphrase
    get_llm_config
    get_timezone

    echo; info "Starting installation..."; echo

    partition_disk
    format_partitions
    mount_partitions
    install_system
    configure_system
    install_bootloader
    cleanup
    print_summary
}

main "$@"
