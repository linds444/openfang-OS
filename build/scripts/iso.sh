#!/bin/bash
# OpenFang OS — Ubuntu 24.04 ISO Builder
# Creates a hybrid live ISO (BIOS + UEFI) with casper live-boot

set -euo pipefail

VERSION="${VERSION:-0.1.0}"
ARCH="${ARCH:-amd64}"
ISO_NAME="${ISO_NAME:-openfang-os-${VERSION}-${ARCH}.iso}"
WORK_DIR="/build/work"
OUTPUT_DIR="/output"
ROOTFS="${WORK_DIR}/rootfs"
ISO_WORK="${WORK_DIR}/iso"

log()     { echo "[iso] $*"; }
section() { echo; echo "── $* ──"; }
die()     { echo "ERROR: $*" >&2; exit 1; }

log "=== Building OpenFang OS ISO: ${ISO_NAME} ==="

# Run main build first
bash /scripts/build.sh

# ─── Prepare ISO structure ────────────────────────────────────────────────────
section "Preparing ISO directory structure"
mkdir -p \
    "${ISO_WORK}/casper" \
    "${ISO_WORK}/boot/grub" \
    "${ISO_WORK}/EFI/BOOT" \
    "${ISO_WORK}/.disk"

# ─── Copy kernel and initramfs ────────────────────────────────────────────────
section "Copying kernel and initramfs"

KERNEL=$(ls "${ROOTFS}/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1)
INITRD=$(ls "${ROOTFS}/boot/initrd.img-"* 2>/dev/null | sort -V | tail -1)

[ -f "${KERNEL}" ] || die "Kernel not found in ${ROOTFS}/boot/"
[ -f "${INITRD}" ] || die "Initrd not found in ${ROOTFS}/boot/"

KERNEL_VER=$(basename "${KERNEL}" | sed 's/vmlinuz-//')
log "Kernel: ${KERNEL_VER}"

cp "${KERNEL}" "${ISO_WORK}/casper/vmlinuz"
cp "${INITRD}" "${ISO_WORK}/casper/initrd"

# ─── Create squashfs ──────────────────────────────────────────────────────────
section "Creating squashfs filesystem"
log "This may take several minutes..."

mksquashfs "${ROOTFS}" "${ISO_WORK}/casper/filesystem.squashfs" \
    -comp zstd -Xcompression-level 19 \
    -noappend \
    -wildcards \
    -e "boot/*" \
    -e "proc/*" \
    -e "sys/*" \
    -e "dev/*" \
    -e "tmp/*" \
    -e "run/*" \
    -e "var/cache/apt/*" \
    -e "var/lib/apt/lists/*"

printf $(du -sx --block-size=1 "${ROOTFS}" | cut -f1) \
    > "${ISO_WORK}/casper/filesystem.size"

log "Squashfs: $(du -sh ${ISO_WORK}/casper/filesystem.squashfs | cut -f1)"

# ─── Disk metadata ────────────────────────────────────────────────────────────
echo "OpenFang OS ${VERSION}" > "${ISO_WORK}/.disk/info"
echo "http://github.com/RightNow-AI/openfang-OS" > "${ISO_WORK}/.disk/release_notes_url"
touch "${ISO_WORK}/.disk/base_installable"

# ─── MD5 manifest ────────────────────────────────────────────────────────────
section "Generating filesystem manifest"
chroot "${ROOTFS}" dpkg-query -W --showformat='${Package} ${Version}\n' \
    > "${ISO_WORK}/casper/filesystem.manifest"

# ─── GRUB configuration ──────────────────────────────────────────────────────
section "Writing GRUB configuration"

KERNEL_PARAMS="boot=casper quiet splash apparmor=1 security=apparmor mitigations=auto kaslr"

cat > "${ISO_WORK}/boot/grub/grub.cfg" << GRUB
# OpenFang OS — GRUB Boot Menu
# Ubuntu 24.04 LTS base

set default=0
set timeout=10
set timeout_style=menu

insmod all_video
insmod gfxterm
insmod png

# Colors
set color_normal=white/black
set color_highlight=black/cyan

if background_image /boot/grub/splash.png; then true; fi

menuentry "OpenFang OS ${VERSION} (Live)" --class openfang --class ubuntu --class os {
    set gfxpayload=keep
    linux  /casper/vmlinuz ${KERNEL_PARAMS}
    initrd /casper/initrd
}

menuentry "OpenFang OS ${VERSION} (Live, safe graphics)" --class openfang {
    set gfxpayload=keep
    linux  /casper/vmlinuz ${KERNEL_PARAMS} nomodeset
    initrd /casper/initrd
}

menuentry "Install OpenFang OS to disk" --class openfang {
    set gfxpayload=keep
    linux  /casper/vmlinuz ${KERNEL_PARAMS} openfang.install=1 automatic-ubiquity
    initrd /casper/initrd
}

menuentry "Check disk for defects" --class openfang {
    linux  /casper/vmlinuz ${KERNEL_PARAMS} integrity-check
    initrd /casper/initrd
}

menuentry "Boot from first hard disk" --class hdd {
    set root=(hd0)
    chainloader +1
}

menuentry "UEFI Firmware Settings" {
    fwsetup
}
GRUB

# Copy splash if it exists
if [ -f "/rootfs/usr/share/openfang/splash.png" ]; then
    cp /rootfs/usr/share/openfang/splash.png "${ISO_WORK}/boot/grub/"
fi

# ─── Build GRUB EFI image ────────────────────────────────────────────────────
section "Building GRUB EFI image"

grub-mkstandalone \
    --format=x86_64-efi \
    --output="${ISO_WORK}/EFI/BOOT/BOOTX64.EFI" \
    --locales="" \
    --fonts="unicode" \
    "boot/grub/grub.cfg=${ISO_WORK}/boot/grub/grub.cfg"

# EFI boot partition image (for ISO)
dd if=/dev/zero of="${ISO_WORK}/boot/efi.img" bs=1M count=10
mkfs.vfat -n "OPENFANG_EFI" "${ISO_WORK}/boot/efi.img"
mmd -i "${ISO_WORK}/boot/efi.img" ::EFI ::EFI/BOOT
mcopy -i "${ISO_WORK}/boot/efi.img" \
    "${ISO_WORK}/EFI/BOOT/BOOTX64.EFI" ::EFI/BOOT/

# ─── Build BIOS GRUB image ───────────────────────────────────────────────────
section "Building BIOS GRUB image"

grub-mkstandalone \
    --format=i386-pc \
    --output="${ISO_WORK}/boot/grub/core.img" \
    --install-modules="linux normal iso9660 biosdisk memdisk search tar ls all_video gfxterm png" \
    --modules="linux normal iso9660 biosdisk search" \
    --locales="" \
    "boot/grub/grub.cfg=${ISO_WORK}/boot/grub/grub.cfg"

cat /usr/lib/grub/i386-pc/cdboot.img \
    "${ISO_WORK}/boot/grub/core.img" \
    > "${ISO_WORK}/boot/grub/bios.img"

# ─── Create ISO ───────────────────────────────────────────────────────────────
section "Creating hybrid ISO"

xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "OPENFANG_OS" \
    -volset "OpenFang OS ${VERSION}" \
    -preparer "OpenFang OS Build" \
    -publisher "OpenFang OS Project" \
    -output "${OUTPUT_DIR}/${ISO_NAME}" \
    -eltorito-boot boot/grub/bios.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog boot/grub/boot.cat \
        --grub2-boot-info \
        --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
    -eltorito-alt-boot \
        -e boot/efi.img \
        -no-emul-boot \
    -append_partition 2 0xef "${ISO_WORK}/boot/efi.img" \
    -graft-points \
        "${ISO_WORK}" \
        /boot/grub/grub.cfg="${ISO_WORK}/boot/grub/grub.cfg"

section "ISO complete"
log "Output: ${OUTPUT_DIR}/${ISO_NAME}"
ls -lh "${OUTPUT_DIR}/${ISO_NAME}"
echo
sha256sum "${OUTPUT_DIR}/${ISO_NAME}" | tee "${OUTPUT_DIR}/${ISO_NAME}.sha256"
log "Done!"
