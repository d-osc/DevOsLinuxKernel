#!/usr/bin/env bash
# 10-build-kernel.sh — download, configure and build the Linux kernel for DevOs
# Base: mainline stable Linux $KERNEL_VERSION (arm64), configured with
# defconfig + the DevOs fragment (config/kernel-fragment.config).
set -euo pipefail
source "$(dirname "$0")/common.sh"

log "=== DevOs: building Linux kernel $KERNEL_VERSION ==="
require_tools gcc make flex bison bc perl curl tar xz

log "downloading kernel tarball (if needed)"
if [ ! -f "$KERNEL_TARBALL" ]; then
    curl -fL --retry 3 -C - -o "$KERNEL_TARBALL" "$KERNEL_URL"
fi

log "extracting"
if [ ! -d "$KERNEL_SRC" ]; then
    tar -C "$WORK" -xf "$KERNEL_TARBALL"
fi

cd "$KERNEL_SRC"

if [ ! -f .config.devos-done ]; then
    log "configuring: $DEVOS_ARCH defconfig + DevOs fragment"
    make defconfig >/dev/null
    # shared fragment + arch-specific serial console bits
    FRAGMENT="$WORK/kernel-fragment-$DEVOS_ARCH.config"
    cat "$REPO/config/kernel-fragment.config" > "$FRAGMENT"
    if [ "$DEVOS_ARCH" = "aarch64" ]; then
        printf 'CONFIG_SERIAL_AMBA_PL011=y\nCONFIG_SERIAL_AMBA_PL011_CONSOLE=y\nCONFIG_SERIAL_EARLYCON=y\n' >> "$FRAGMENT"
    else
        printf 'CONFIG_SERIAL_8250=y\nCONFIG_SERIAL_8250_CONSOLE=y\n' >> "$FRAGMENT"
    fi
    ./scripts/kconfig/merge_config.sh -m .config "$FRAGMENT"
    make olddefconfig >/dev/null
    touch .config.devos-done
else
    log "already configured — skipping (delete $KERNEL_SRC/.config.devos-done to reconfigure)"
fi

log "building $KERNEL_MAKE_TARGET ($DEVOS_ARCH) with $(nproc) jobs — this can take a while"
make -j"$(nproc)" "$KERNEL_MAKE_TARGET"

if [ ! -f "$KERNEL_IMAGE" ]; then
    die "kernel image missing after build"
fi

cp "$KERNEL_IMAGE" "$OUT/devos-Image-$KERNEL_VERSION"
cp .config "$OUT/kernel-$KERNEL_VERSION.config"
ok "kernel image: $OUT/devos-Image-$KERNEL_VERSION ($(du -h "$KERNEL_IMAGE" | cut -f1))"
ok "kernel release string: $(make -s kernelrelease 2>/dev/null || echo "$KERNEL_VERSION-devos")"
