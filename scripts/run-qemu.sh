#!/usr/bin/env bash
# run-qemu.sh — boot DevOs in QEMU (aarch64 'virt' machine)
#   interactive : scripts/run-qemu.sh
#   automated   : scripts/run-qemu.sh --test   (boots, runs checks, powers off)
set -euo pipefail
source "$(dirname "$0")/common.sh"

IMG="$OUT/devos-Image-$KERNEL_VERSION"
if [ ! -f "$IMG" ]; then
    die "kernel image not found — run scripts/10-build-kernel.sh first"
fi
if [ ! -f "$INITRAMFS" ]; then
    die "initramfs not found — run scripts/30-build-rootfs.sh first"
fi

QEMU_CMD=(
    "$QEMU_BINARY"
    -M "$QEMU_MACHINE" -cpu "$QEMU_CPU" -smp 2 -m 1G
    -kernel "$IMG"
    -initrd "$INITRAMFS"
    -append "$QEMU_APPEND"
    -device virtio-net-pci,netdev=n0
    -netdev user,id=n0
    -device virtio-rng-pci
    -no-reboot
    -nographic
)

if [ "${1:-}" = "--test" ]; then
    log "automated boot test — starting DevOs in QEMU"
    rm -f "$OUT/boot-test.log"
    set +e
    (
        sleep 30          # let the kernel boot to the askfirst prompt
        echo ""           # press Enter to activate the console
        sleep 3
        echo "cat /etc/os-release"
        sleep 2
        echo "uname -r"
        sleep 2
        echo "dev --version"
        sleep 2
        echo "dev list"
        sleep 2
        echo "dev install /root/packages/hello-1.0.0.dpk"
        sleep 5
        echo "dev run hello"
        sleep 3
        echo "dev list"
        sleep 2
        echo "git --version"
        sleep 2
        # TERM=dumb stops gh from querying the terminal (OSC/DSR), which
        # would otherwise swallow the next input line
        echo "TERM=dumb gh --version"
        sleep 3
        echo "git ls-remote https://github.com/octocat/Hello-World.git HEAD"
        sleep 12
        echo "echo DEVOS_BOOT_TEST_COMPLETE"
        sleep 2
        echo "poweroff -f"
        sleep 5
        echo "echo TEST_HAD_TO_TIMEOUT"
    ) | timeout 300 "${QEMU_CMD[@]}" 2>&1 | tee "$OUT/boot-test.log"
    rc=$?
    set -e
    echo
    if grep -q "DEVOS_BOOT_TEST_COMPLETE" "$OUT/boot-test.log" \
       && grep -q "$KERNEL_VERSION-devos" "$OUT/boot-test.log" \
       && grep -q "PRETTY_NAME=\"DevOs" "$OUT/boot-test.log" \
       && grep -Eq 'dev [0-9]+\.[0-9]+' "$OUT/boot-test.log" \
       && grep -q "Hello, Dev OS!" "$OUT/boot-test.log" \
       && grep -q "git version" "$OUT/boot-test.log" \
       && grep -q "gh version" "$OUT/boot-test.log" \
       && grep -Eq '^[0-9a-f]{40}[[:space:]]+HEAD' "$OUT/boot-test.log"; then
        ok "boot test PASSED — full log: $OUT/boot-test.log"
        exit 0
    else
        err "boot test FAILED — inspect $OUT/boot-test.log"
        exit 1
    fi
fi

log "booting DevOs (exit QEMU with Ctrl-A then X)"
exec "${QEMU_CMD[@]}"
