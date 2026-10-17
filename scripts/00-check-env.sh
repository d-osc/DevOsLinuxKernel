#!/usr/bin/env bash
# 00-check-env.sh — verify the DevOs build environment (run inside WSL/Linux)
set -euo pipefail
source "$(dirname "$0")/common.sh"

log "DevOs $DEVOS_VERSION — build environment check"
log "Architecture : $(uname -m)   (target: $DEVOS_ARCH — auto-detected)"
log "Host kernel  : $(uname -r)"
log "CPU cores    : $(nproc)"
log "Memory       : $(free -h | awk '/^Mem:/ {print $2}')"
log "Repo         : $REPO"
log "Workspace    : $WORK"
echo

log "Required tools:"
for t in gcc make flex bison bc perl cpio gzip xz bzip2 curl tar sed awk; do
    if command -v "$t" >/dev/null 2>&1; then
        printf '  \033[1;32mok  \033[0m %s\n' "$t"
    else
        printf '  \033[1;31mMISS\033[0m %s\n' "$t"
    fi
done
echo

log "Required tools with version:"
for t in gcc make "$QEMU_BINARY"; do
    if command -v "$t" >/dev/null 2>&1; then
        printf '  \033[1;32mok  \033[0m %-20s %s\n' "$t" "$("$t" --version | head -1 | cut -c1-70)"
    else
        printf '  \033[1;31mMISS\033[0m %s\n' "$t"
    fi
done
echo

log "Optional tools (ISO build):"
for t in grub-mkrescue xorriso mformat; do
    if command -v "$t" >/dev/null 2>&1; then
        printf '  ok  %s\n' "$t"
    else
        printf '  --  %s (ISO step will be skipped)\n' "$t"
    fi
done
echo

log "Internet access:"
if curl -fsI --max-time 15 "$KERNEL_URL" >/dev/null 2>&1; then
    ok "cdn.kernel.org reachable (linux-$KERNEL_VERSION.tar.xz)"
else
    err "cannot reach $KERNEL_URL"
fi
if curl -fsI --max-time 15 "$BUSYBOX_URL" >/dev/null 2>&1; then
    ok "busybox.net reachable (busybox-$BUSYBOX_VERSION.tar.bz2)"
else
    err "cannot reach $BUSYBOX_URL"
fi
echo
ok "environment check complete"
