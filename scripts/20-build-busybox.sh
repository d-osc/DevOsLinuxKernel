#!/usr/bin/env bash
# 20-build-busybox.sh — download and statically build BusyBox (DevOs userland)
# for the TARGET arch (native by default, cross with DEVOS_TARGET_ARCH).
set -euo pipefail
source "$(dirname "$0")/common.sh"

BUSYBOX_ROOT="$WORK/busybox-root-$DEVOS_ARCH"

log "=== DevOs: building BusyBox $BUSYBOX_VERSION (static, $DEVOS_ARCH) ==="
require_tools gcc make curl tar bzip2

log "downloading BusyBox tarball (if needed)"
if [ ! -f "$BUSYBOX_TARBALL" ]; then
    curl -fL --retry 3 -C - -o "$BUSYBOX_TARBALL" "$BUSYBOX_URL"
fi

log "extracting"
if [ ! -d "$BUSYBOX_SRC" ]; then
    tar -C "$WORK" -xf "$BUSYBOX_TARBALL"
fi

cd "$BUSYBOX_SRC"

if [ ! -f .config.devos-done ]; then
    log "configuring: defconfig + static linking"
    make CROSS_COMPILE="$CROSS_PREFIX" defconfig >/dev/null
    sed -i \
        -e 's/^CONFIG_PIE=y/# CONFIG_PIE is not set/' \
        -e 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' \
        -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' \
        .config
    # CONFIG_TC: busybox tc.c still references CBQ uapi symbols that recent
    # kernels removed from linux/pkt_sched.h — it cannot compile against
    # Ubuntu 26.04's linux-libc-dev. Disabled; not needed in DevOs.
    # </dev/null lets oldconfig take defaults for new symbols; piping
    # `yes ''` into it would SIGPIPE under pipefail and kill the script
    make CROSS_COMPILE="$CROSS_PREFIX" oldconfig </dev/null >/dev/null
    make CROSS_COMPILE="$CROSS_PREFIX" clean >/dev/null
    touch .config.devos-done
else
    log "already configured — skipping (delete $BUSYBOX_SRC/.config.devos-done to reconfigure)"
fi

log "building with $(nproc) jobs"
make CROSS_COMPILE="$CROSS_PREFIX" -j"$(nproc)"

log "installing into $BUSYBOX_ROOT"
rm -rf "$BUSYBOX_ROOT"
make CROSS_COMPILE="$CROSS_PREFIX" CONFIG_PREFIX="$BUSYBOX_ROOT" install >/dev/null

cp .config "$OUT/busybox-$BUSYBOX_VERSION-$DEVOS_ARCH.config"
ok "busybox installed: $BUSYBOX_ROOT/bin/busybox"
file "$BUSYBOX_ROOT/bin/busybox" | cut -d: -f2 | xargs
