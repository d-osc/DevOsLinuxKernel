#!/usr/bin/env bash
# 20-build-busybox.sh — download and statically build BusyBox (DevOs userland)
set -euo pipefail
source "$(dirname "$0")/common.sh"

log "=== DevOs: building BusyBox $BUSYBOX_VERSION (static) ==="
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
    make defconfig >/dev/null
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
    make oldconfig </dev/null >/dev/null
    make clean >/dev/null
    touch .config.devos-done
else
    log "already configured — skipping (delete $BUSYBOX_SRC/.config.devos-done to reconfigure)"
fi

log "building with $(nproc) jobs"
make -j"$(nproc)"

log "installing into $WORK/busybox-root"
rm -rf "$WORK/busybox-root"
make CONFIG_PREFIX="$WORK/busybox-root" install >/dev/null

cp .config "$OUT/busybox-$BUSYBOX_VERSION.config"
ok "busybox installed: $WORK/busybox-root/bin/busybox"
bb_banner="$("$WORK/busybox-root/bin/busybox" 2>&1 || true)"
echo "$bb_banner" | head -1
