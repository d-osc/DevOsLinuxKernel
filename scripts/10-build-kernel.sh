#!/usr/bin/env bash
# 10-build-kernel.sh — download, configure and build the Linux kernel for DevOs
# Base: mainline stable Linux $KERNEL_VERSION, configured with defconfig +
# the DevOs fragment (config/kernel-fragment.config) for the TARGET arch.
# Native build by default; set DEVOS_TARGET_ARCH to cross-build (needs a GNU
# cross toolchain with $CROSS_PREFIX prefix, e.g. crossbuild-essential-amd64).
set -euo pipefail
source "$(dirname "$0")/common.sh"

log "=== DevOs: building Linux kernel $KERNEL_VERSION ($DEVOS_ARCH target, $DEVOS_HOST_ARCH host) ==="
require_tools gcc make flex bison bc perl curl tar xz

if [ "$IS_CROSS" = "1" ]; then
    command -v "${CROSS_PREFIX}gcc" >/dev/null 2>&1 \
        || die "cross compiler ${CROSS_PREFIX}gcc not found — install e.g. crossbuild-essential-amd64"
fi

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
    make ARCH="$KARCH" CROSS_COMPILE="$CROSS_PREFIX" defconfig >/dev/null
    # shared fragment + arch-specific serial console bits
    FRAGMENT="$WORK/kernel-fragment-$DEVOS_ARCH.config"
    cat "$REPO/config/kernel-fragment.config" > "$FRAGMENT"
    if [ "$DEVOS_ARCH" = "aarch64" ]; then
        printf 'CONFIG_SERIAL_AMBA_PL011=y\nCONFIG_SERIAL_AMBA_PL011_CONSOLE=y\nCONFIG_SERIAL_EARLYCON=y\n' >> "$FRAGMENT"
    else
        printf 'CONFIG_SERIAL_8250=y\nCONFIG_SERIAL_8250_CONSOLE=y\n' >> "$FRAGMENT"
    fi
    ./scripts/kconfig/merge_config.sh -m .config "$FRAGMENT"
    make ARCH="$KARCH" CROSS_COMPILE="$CROSS_PREFIX" olddefconfig >/dev/null
    touch .config.devos-done
else
    log "already configured — skipping (delete $KERNEL_SRC/.config.devos-done to reconfigure)"
fi

log "building $KERNEL_MAKE_TARGET ($DEVOS_ARCH) with $(nproc) jobs — this can take a while"
make ARCH="$KARCH" CROSS_COMPILE="$CROSS_PREFIX" -j"$(nproc)" "$KERNEL_MAKE_TARGET"

if [ ! -f "$KERNEL_IMAGE" ]; then
    die "kernel image missing after build"
fi

cp "$KERNEL_IMAGE" "$KERNEL_IMAGE_OUT"
cp .config "$OUT/kernel-$KERNEL_VERSION-$DEVOS_ARCH.config"
ok "kernel image: $KERNEL_IMAGE_OUT ($(du -h "$KERNEL_IMAGE" | cut -f1))"
ok "kernel release string: $(make ARCH="$KARCH" CROSS_COMPILE="$CROSS_PREFIX" -s kernelrelease)"
