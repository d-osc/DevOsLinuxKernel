#!/usr/bin/env bash
# common.sh — shared configuration for DevOs build scripts
# DevOs: a minimal Linux OS built from the latest mainline kernel + BusyBox
#
# Architecture is auto-detected from the build host: aarch64 (arm64) or
# x86_64. Everything downstream (kernel image, musl target, QEMU binary,
# GitHub CLI asset, ...) is derived from it.

set -euo pipefail

# ---- versions ------------------------------------------------------------
export KERNEL_VERSION="7.2.11"
export BUSYBOX_VERSION="1.38.0"
export DEVOS_VERSION="1.0.0"

# ---- helpers -------------------------------------------------------------
log() { printf '\033[1;36m[devos]\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m[devos]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[devos]\033[0m %s\n' "$*" >&2; }
die() { err "ERROR: $*"; exit 1; }

require_tools() {
    local missing=()
    local t
    for t in "$@"; do
        if ! command -v "$t" >/dev/null 2>&1; then
            missing+=("$t")
        fi
    done
    if [ "${#missing[@]}" -ne 0 ]; then
        die "missing tools: ${missing[*]} — run scripts/00-check-env.sh"
    fi
}

# ---- architecture (auto: aarch64 | x86_64) --------------------------------
case "$(uname -m)" in
    aarch64|arm64) DEVOS_ARCH=aarch64 ;;
    x86_64|amd64)  DEVOS_ARCH=x86_64 ;;
    *) die "unsupported build host architecture: $(uname -m) (supported: aarch64/arm64, x86_64/amd64)" ;;
esac
export DEVOS_ARCH

if [ "$DEVOS_ARCH" = "aarch64" ]; then
    KERNEL_MAKE_TARGET=Image
    KERNEL_IMAGE_RELPATH=arch/arm64/boot/Image
    QEMU_BINARY=qemu-system-aarch64
    QEMU_MACHINE=virt
    QEMU_CPU=cortex-a57
    QEMU_APPEND="console=ttyAMA0"
    MUSL_TARGET=aarch64-unknown-linux-musl
    MUSL_NATIVE_URL=https://musl.cc/aarch64-linux-musl-native.tgz
    OPENSSL_TARGET=linux-aarch64
    GRUB_EFI_DIR=arm64-efi
    GH_ASSET_ARCH=linux_arm64
else
    KERNEL_MAKE_TARGET=bzImage
    KERNEL_IMAGE_RELPATH=arch/x86/boot/bzImage
    QEMU_BINARY=qemu-system-x86_64
    QEMU_MACHINE=q35
    QEMU_CPU=max
    QEMU_APPEND="console=ttyS0"
    MUSL_TARGET=x86_64-unknown-linux-musl
    MUSL_NATIVE_URL=https://musl.cc/x86_64-linux-musl-native.tgz
    OPENSSL_TARGET=linux-x86_64
    GRUB_EFI_DIR=x86_64-efi
    GH_ASSET_ARCH=linux_amd64
fi
export KERNEL_MAKE_TARGET KERNEL_IMAGE_RELPATH QEMU_BINARY QEMU_MACHINE QEMU_CPU \
       QEMU_APPEND MUSL_TARGET MUSL_NATIVE_URL OPENSSL_TARGET GRUB_EFI_DIR GH_ASSET_ARCH

# ---- paths ---------------------------------------------------------------
# Repository root (parent of scripts/) — resolved from this file's location
export REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Build workspace — kept in the Linux filesystem for speed.
# Override with DEVOS_WORK=/somewhere if needed.
export WORK="${DEVOS_WORK:-$HOME/devos}"
export DL="$WORK/downloads"
export OUT="$REPO/output"

export KERNEL_SRC="$WORK/linux-$KERNEL_VERSION"
export BUSYBOX_SRC="$WORK/busybox-$BUSYBOX_VERSION"
export ROOTFS="$WORK/rootfs"

export KERNEL_TARBALL="$DL/linux-$KERNEL_VERSION.tar.xz"
export BUSYBOX_TARBALL="$DL/busybox-$BUSYBOX_VERSION.tar.bz2"

export KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$KERNEL_VERSION.tar.xz"
export BUSYBOX_URL="https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2"

export KERNEL_IMAGE="$KERNEL_SRC/$KERNEL_IMAGE_RELPATH"
export INITRAMFS="$OUT/devos-initramfs-$KERNEL_VERSION.cpio.gz"

mkdir -p "$DL" "$OUT"
