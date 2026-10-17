#!/usr/bin/env bash
# build.sh — full DevOs build (run inside WSL/Linux):
#   wsl -d Ubuntu -- bash /mnt/c/Users/ondev/Projects/DevOsLinuxKernel/scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./common.sh

log "DevOs $DEVOS_VERSION — full build starting at $(date)"
./00-check-env.sh
echo
./10-build-kernel.sh
echo
./20-build-busybox.sh
echo
./25-build-devospm.sh
echo
./26-build-git-gh.sh
echo
./30-build-rootfs.sh
echo
./40-mkiso.sh
echo

# checksums for the produced artifacts
: > "$OUT/SHA256SUMS"
for f in "$OUT"/devos-Image-* "$OUT"/devos-initramfs-*.cpio.gz "$OUT"/devos-*.iso; do
    if [ -f "$f" ]; then
        ( cd "$OUT" && sha256sum "$(basename "$f")" >> SHA256SUMS )
    fi
done

log "artifacts in $OUT:"
ls -lh "$OUT"
echo
ok "build finished at $(date)"
ok "boot it:  wsl -d Ubuntu -- bash $REPO/scripts/run-qemu.sh"
