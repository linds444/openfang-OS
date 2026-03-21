#!/bin/bash
# OpenFang OS — Disk Image Builder
# Creates a flashable raw disk image with LUKS2 encryption

set -euo pipefail

VERSION="${VERSION:-0.1.0}"
ISO_NAME="${ISO_NAME:-openfang-os-${VERSION}-x86_64.iso}"
IMG_NAME="${IMG_NAME:-openfang-os-${VERSION}-x86_64.img}"
OUTPUT_DIR="/output"
WORK_DIR="/build/work/image"
IMG_SIZE="4G"  # Minimum image size

log() { echo "[image] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "${OUTPUT_DIR}/${ISO_NAME}" ] || die "ISO not found: ${ISO_NAME}"

log "Creating ${IMG_SIZE} disk image..."

mkdir -p "${WORK_DIR}"

# ─── Create raw image ─────────────────────────────────────────────────────────
truncate -s "${IMG_SIZE}" "${OUTPUT_DIR}/${IMG_NAME}"

# ─── Partition layout ─────────────────────────────────────────────────────────
# GPT partition table:
#   1: EFI System Partition (512MB, FAT32)
#   2: Boot partition (512MB, ext4, /boot)
#   3: LUKS2 encrypted root (remainder)

log "Partitioning..."
parted -s "${OUTPUT_DIR}/${IMG_NAME}" \
    mklabel gpt \
    mkpart "EFI"  fat32  1MiB   513MiB \
    mkpart "BOOT" ext4   513MiB 1025MiB \
    mkpart "ROOT" ext4   1025MiB 100% \
    set 1 esp on \
    set 1 boot on

# ─── Set up loop device ───────────────────────────────────────────────────────
LOOP=$(losetup --find --show --partscan "${OUTPUT_DIR}/${IMG_NAME}")
log "Loop device: ${LOOP}"

cleanup() {
    log "Cleaning up..."
    umount -R /mnt/openfang 2>/dev/null || true
    cryptsetup luksClose openfang_root 2>/dev/null || true
    losetup -d "${LOOP}" 2>/dev/null || true
}
trap cleanup EXIT

EFI_PART="${LOOP}p1"
BOOT_PART="${LOOP}p2"
ROOT_PART="${LOOP}p3"

# ─── Format partitions ────────────────────────────────────────────────────────
log "Formatting EFI partition..."
mkfs.vfat -F32 -n "EFI" "${EFI_PART}"

log "Formatting boot partition..."
mkfs.ext4 -L "openfang-boot" -q "${BOOT_PART}"

log "Setting up LUKS2 encryption..."
# For automated image building, use a temporary key
# Users will set their own passphrase during first boot
echo "openfang-default-key" | cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --pbkdf argon2id \
    --iter-time 2000 \
    --sector-size 4096 \
    "${ROOT_PART}" -

echo "openfang-default-key" | cryptsetup luksOpen \
    "${ROOT_PART}" openfang_root -

log "Formatting root filesystem..."
mkfs.ext4 -L "openfang-root" -q /dev/mapper/openfang_root

# ─── Mount and copy ───────────────────────────────────────────────────────────
mkdir -p /mnt/openfang
mount /dev/mapper/openfang_root /mnt/openfang
mkdir -p /mnt/openfang/boot
mount "${BOOT_PART}" /mnt/openfang/boot
mkdir -p /mnt/openfang/boot/efi
mount "${EFI_PART}" /mnt/openfang/boot/efi

log "Extracting system..."
# Mount and extract the squashfs from the ISO
mkdir -p /mnt/iso
mount -o loop,ro "${OUTPUT_DIR}/${ISO_NAME}" /mnt/iso
unsquashfs -f -d /mnt/openfang /mnt/iso/casper/filesystem.squashfs

# Copy kernel and initramfs before unmounting the ISO
cp /mnt/iso/casper/vmlinuz    /mnt/openfang/boot/vmlinuz
cp /mnt/iso/casper/initrd     /mnt/openfang/boot/initramfs
umount /mnt/iso

# ─── Install GRUB ─────────────────────────────────────────────────────────────
log "Installing GRUB..."

# Generate crypttab
LUKS_UUID=$(blkid -s UUID -o value "${ROOT_PART}")
cat > /mnt/openfang/etc/crypttab << EOF
openfang_root UUID=${LUKS_UUID} none luks,discard
EOF

# Generate fstab
ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/openfang_root)
BOOT_UUID=$(blkid -s UUID -o value "${BOOT_PART}")
EFI_UUID=$(blkid -s UUID -o value "${EFI_PART}")

cat > /mnt/openfang/etc/fstab << EOF
# OpenFang OS fstab
UUID=${ROOT_UUID}  /          ext4  defaults,noatime  0 1
UUID=${BOOT_UUID}  /boot      ext4  defaults,noatime  0 2
UUID=${EFI_UUID}   /boot/efi  vfat  umask=0077        0 2
tmpfs              /tmp       tmpfs defaults,noatime,nosuid,nodev,size=512M  0 0
tmpfs              /run       tmpfs defaults,noatime,nosuid,nodev,mode=755   0 0
EOF

# GRUB config for encrypted root
cat > /mnt/openfang/boot/grub/grub.cfg << EOF
set default=0
set timeout=5

menuentry "OpenFang OS" {
    insmod part_gpt
    insmod cryptodisk
    insmod luks2
    insmod ext2
    cryptomount -u ${LUKS_UUID//\-/}
    set root='cryptouuid/${LUKS_UUID//\-/}'
    linux  /boot/vmlinuz \\
        root=/dev/mapper/openfang_root \\
        cryptdevice=UUID=${LUKS_UUID}:openfang_root \\
        init=/sbin/init \\
        quiet apparmor=1 security=apparmor \\
        mitigations=auto kaslr
    initrd /boot/initramfs
}

menuentry "OpenFang OS (recovery)" {
    insmod part_gpt
    insmod cryptodisk
    insmod luks2
    insmod ext2
    cryptomount -u ${LUKS_UUID//\-/}
    set root='cryptouuid/${LUKS_UUID//\-/}'
    linux  /boot/vmlinuz \\
        root=/dev/mapper/openfang_root \\
        cryptdevice=UUID=${LUKS_UUID}:openfang_root \\
        init=/sbin/init \\
        single
    initrd /boot/initramfs
}
EOF

for bind in proc sys dev dev/pts; do
    mount --bind "/$bind" "/mnt/openfang/$bind"
done

chroot /mnt/openfang grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=OpenFangOS \
    --removable

chroot /mnt/openfang grub-install \
    --target=i386-pc \
    "${LOOP}"

for bind in dev/pts dev sys proc; do
    umount "/mnt/openfang/$bind"
done

log "Disk image ready: ${OUTPUT_DIR}/${IMG_NAME}"
ls -lh "${OUTPUT_DIR}/${IMG_NAME}"
sha256sum "${OUTPUT_DIR}/${IMG_NAME}" | tee "${OUTPUT_DIR}/${IMG_NAME}.sha256"
