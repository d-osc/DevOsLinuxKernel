#!/usr/bin/env bash
# 40-mkiso.sh — build a bootable DevOs ISO (arm64 EFI via GRUB) — best effort
set -euo pipefail
source "$(dirname "$0")/common.sh"

log "=== DevOs: building bootable ISO ==="

GRUB_MODULE_DIR=""
if [ -d "/usr/lib/grub/$GRUB_EFI_DIR" ]; then
    GRUB_MODULE_DIR="/usr/lib/grub/$GRUB_EFI_DIR"
fi

if ! command -v grub-mkrescue >/dev/null 2>&1 \
   || [ -z "$GRUB_MODULE_DIR" ] \
   || ! command -v mformat >/dev/null 2>&1; then
    err "grub-mkrescue / grub $GRUB_EFI_DIR modules / mtools not available"
    err "install with:  sudo apt install grub-efi-$DEVOS_ARCH-bin mtools xorriso"
    err "skipping ISO build (kernel+initramfs still boot fine via scripts/run-qemu.sh)"
    exit 0
fi

if [ ! -f "$OUT/devos-Image-$KERNEL_VERSION" ]; then
    die "kernel image missing — run scripts/10-build-kernel.sh first"
fi
if [ ! -f "$INITRAMFS" ]; then
    die "initramfs missing — run scripts/30-build-rootfs.sh first"
fi

ISO_ROOT="$WORK/iso"
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/boot/grub"
cp "$OUT/devos-Image-$KERNEL_VERSION" "$ISO_ROOT/boot/Image"
cp "$INITRAMFS" "$ISO_ROOT/boot/initramfs.cpio.gz"

cat > "$ISO_ROOT/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=3

menuentry "DevOs $DEVOS_VERSION (Linux $KERNEL_VERSION-devos)" {
    linux /boot/Image $QEMU_APPEND rw
    initrd /boot/initramfs.cpio.gz
}
menuentry "DevOs $DEVOS_VERSION (verbose boot)" {
    linux /boot/Image $QEMU_APPEND ignore_loglevel rw
    initrd /boot/initramfs.cpio.gz
}
EOF

log "running grub-mkrescue"
grub-mkrescue -o "$OUT/devos-$DEVOS_VERSION.iso" "$ISO_ROOT" >/dev/null
ok "ISO: $OUT/devos-$DEVOS_VERSION.iso ($(du -h "$OUT/devos-$DEVOS_VERSION.iso" | cut -f1))"
