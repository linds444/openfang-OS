#!/bin/bash
# OpenFang OS — ISO Image Builder
# Creates a bootable hybrid ISO (BIOS + UEFI)

set -euo pipefail

VERSION="${VERSION:-0.1.0}"
ARCH="${ARCH:-x86_64}"
ISO_NAME="${ISO_NAME:-openfang-os-${VERSION}-${ARCH}.iso}"
WORK_DIR="/build/work"
OUTPUT_DIR="/output"
ISO_WORK="${WORK_DIR}/iso"

log() { echo "[iso] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

log "Building ISO: ${ISO_NAME}"

# Run the main build first
bash /scripts/build.sh

# ─── Create ISO tree ──────────────────────────────────────────────────────────
mkdir -p "${ISO_WORK}/boot/grub"
mkdir -p "${ISO_WORK}/EFI/BOOT"
mkdir -p "${ISO_WORK}/isolinux"

# ─── Create squashfs root filesystem ─────────────────────────────────────────
log "Creating squashfs..."
mksquashfs "${WORK_DIR}/rootfs" "${ISO_WORK}/openfang.squashfs" \
    -comp zstd -Xcompression-level 19 \
    -noappend \
    -wildcards \
    -e "proc/*" -e "sys/*" -e "dev/*" -e "tmp/*" -e "run/*"

# ─── Copy kernel and initramfs ────────────────────────────────────────────────
KERNEL=$(ls "${WORK_DIR}/rootfs/boot/vmlinuz-"* 2>/dev/null | head -1)
INITRD=$(ls "${WORK_DIR}/rootfs/boot/initramfs-"* 2>/dev/null | head -1)

if [ -z "${KERNEL}" ]; then
    # Fall back to Alpine's kernel from the build container
    KERNEL="/boot/vmlinuz-lts"
    INITRD="/boot/initramfs-lts"
fi

[ -f "${KERNEL}" ] || die "Kernel not found: ${KERNEL}"
[ -f "${INITRD}" ] || die "Initramfs not found: ${INITRD}"

cp "${KERNEL}" "${ISO_WORK}/boot/vmlinuz"
cp "${INITRD}" "${ISO_WORK}/boot/initramfs"

# ─── GRUB configuration ──────────────────────────────────────────────────────
log "Writing GRUB config..."
cat > "${ISO_WORK}/boot/grub/grub.cfg" << 'GRUB'
set default=0
set timeout=5
set timeout_style=menu

# OpenFang OS color theme
set color_normal=white/black
set color_highlight=black/light-cyan

menuentry "OpenFang OS" {
    linux  /boot/vmlinuz \
        root=/dev/ram0 \
        init=/sbin/init \
        modules=loop,squashfs,sd-mod,usb-storage \
        quiet \
        loglevel=3 \
        apparmor=1 security=apparmor \
        mitigations=auto \
        kaslr \
        page_alloc.shuffle=1 \
        init_on_alloc=1 \
        init_on_free=1
    initrd /boot/initramfs
}

menuentry "OpenFang OS (verbose)" {
    linux  /boot/vmlinuz \
        root=/dev/ram0 \
        init=/sbin/init \
        modules=loop,squashfs,sd-mod,usb-storage \
        apparmor=1 security=apparmor
    initrd /boot/initramfs
}

menuentry "Install OpenFang OS to disk" {
    linux  /boot/vmlinuz \
        root=/dev/ram0 \
        init=/sbin/init \
        modules=loop,squashfs,sd-mod,usb-storage \
        openfang.install=1
    initrd /boot/initramfs
}

menuentry "Memory test (memtest86+)" {
    linux /boot/memtest
}
GRUB

# ─── UEFI GRUB image ─────────────────────────────────────────────────────────
log "Building GRUB EFI image..."
grub-mkstandalone \
    --format=x86_64-efi \
    --output="${ISO_WORK}/EFI/BOOT/BOOTX64.EFI" \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=${ISO_WORK}/boot/grub/grub.cfg"

# Create EFI boot disk image
dd if=/dev/zero of="${ISO_WORK}/boot/efi.img" bs=1M count=4
mkfs.vfat "${ISO_WORK}/boot/efi.img"
mmd -i "${ISO_WORK}/boot/efi.img" ::EFI ::EFI/BOOT
mcopy -i "${ISO_WORK}/boot/efi.img" \
    "${ISO_WORK}/EFI/BOOT/BOOTX64.EFI" ::EFI/BOOT/

# ─── BIOS GRUB ───────────────────────────────────────────────────────────────
log "Installing BIOS GRUB..."
grub-mkstandalone \
    --format=i386-pc \
    --output="${ISO_WORK}/isolinux/core.img" \
    --install-modules="linux normal iso9660 biosdisk memdisk search tar ls" \
    --modules="linux normal iso9660 biosdisk search" \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=${ISO_WORK}/boot/grub/grub.cfg"

cat /usr/lib/grub/i386-pc/cdboot.img \
    "${ISO_WORK}/isolinux/core.img" \
    > "${ISO_WORK}/isolinux/bios.img"

# ─── Create ISO ───────────────────────────────────────────────────────────────
log "Creating ISO..."
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "OPENFANG_OS" \
    -preparer "OpenFang OS Build System" \
    -publisher "OpenFang OS Project" \
    -appid "OpenFang OS ${VERSION}" \
    -output "${OUTPUT_DIR}/${ISO_NAME}" \
    -eltorito-boot isolinux/bios.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --eltorito-catalog isolinux/boot.cat \
    --grub2-boot-info \
    --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
    -eltorito-alt-boot \
    -e boot/efi.img \
    -no-emul-boot \
    -append_partition 2 0xef "${ISO_WORK}/boot/efi.img" \
    -graft-points \
        "${ISO_WORK}" \
        /boot/grub/grub.cfg="${ISO_WORK}/boot/grub/grub.cfg"

log "ISO created: ${OUTPUT_DIR}/${ISO_NAME}"
ls -lh "${OUTPUT_DIR}/${ISO_NAME}"
sha256sum "${OUTPUT_DIR}/${ISO_NAME}" | tee "${OUTPUT_DIR}/${ISO_NAME}.sha256"
log "Done!"
