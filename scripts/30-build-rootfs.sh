#!/usr/bin/env bash
# 30-build-rootfs.sh — assemble the DevOs initramfs rootfs
# BusyBox install + DevOs overlay (rootfs-overlay/) + device nodes, packed
# as a gzip'd newc cpio archive usable directly as a QEMU/UEFI initrd.
set -euo pipefail
source "$(dirname "$0")/common.sh"

log "=== DevOs: assembling DevOs initramfs ==="
require_tools cpio gzip find

if [ ! -x "$WORK/busybox-root/bin/busybox" ]; then
    die "busybox not built — run scripts/20-build-busybox.sh first"
fi
if [ ! -f "$KERNEL_IMAGE" ]; then
    die "kernel not built — run scripts/10-build-kernel.sh first"
fi

log "creating rootfs tree at $ROOTFS"
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"
cp -a "$WORK/busybox-root/." "$ROOTFS/"

# directory skeleton
mkdir -p "$ROOTFS"/{proc,sys,dev,etc/init.d,tmp,root,home,opt,run,srv,boot,mnt,media}
mkdir -p "$ROOTFS"/var/{log,tmp,empty}
chmod 1777 "$ROOTFS/tmp" "$ROOTFS/var/tmp"

log "applying DevOs overlay (rootfs-overlay/)"
cp -a "$REPO/rootfs-overlay/." "$ROOTFS/"
chmod 0755 "$ROOTFS/init" "$ROOTFS/etc/init.d/rcS" "$ROOTFS/etc/init.d/rcK" \
    "$ROOTFS/usr/share/udhcpc/default.script"

log "installing DevOsPM package manager (/bin/dev)"
DEVOSPM_BIN="$WORK/devospm-bin/dev"
if [ ! -x "$DEVOSPM_BIN" ]; then
    die "DevOsPM binary missing — run scripts/25-build-devospm.sh first"
fi
install -m 755 "$DEVOSPM_BIN" "$ROOTFS/bin/dev"
mkdir -p "$ROOTFS/var/lib/devos" "$ROOTFS/root/packages"
for dpk in "$WORK"/hello-*.dpk; do
    if [ -f "$dpk" ]; then
        cp "$dpk" "$ROOTFS/root/packages/"
    fi
done

log "installing git + gh"
TOOLS_STAGE="$WORK/tools-stage"
if [ ! -x "$TOOLS_STAGE/usr/bin/git" ] || [ ! -x "$TOOLS_STAGE/usr/bin/gh" ]; then
    die "git/gh missing — run scripts/26-build-git-gh.sh first"
fi
cp -a "$TOOLS_STAGE/usr/." "$ROOTFS/usr/"
# TLS roots for git/gh HTTPS — must match curl's --with-ca-bundle path
mkdir -p "$ROOTFS/etc/ssl/certs"
if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
    cp /etc/ssl/certs/ca-certificates.crt "$ROOTFS/etc/ssl/certs/"
else
    err "warning: no CA bundle on the build host — git/gh HTTPS will fail"
fi
# ---- inject live versions/arch into /etc/os-release and /etc/motd --------
DEVOS_PM_VER="$(cat "$WORK/devospm-version.txt" 2>/dev/null || echo unknown)"
DEVOS_TOOLS_VER="$(cat "$WORK/tools-versions.txt" 2>/dev/null || echo 'git + gh')"
sed -i \
    -e "s|^DEVOS_KERNEL=.*|DEVOS_KERNEL=\"Linux $KERNEL_VERSION-devos\"|" \
    -e "s|^DEVOS_PM=.*|DEVOS_PM=\"DevOsPM $DEVOS_PM_VER\"|" \
    -e "s|^DEVOS_TOOLS=.*|DEVOS_TOOLS=\"$DEVOS_TOOLS_VER\"|" \
    -e "s|^DEVOS_ARCH=.*|DEVOS_ARCH=\"$DEVOS_ARCH\"|" \
    "$ROOTFS/etc/os-release"
sed -i \
    -e "s|$KERNEL_VERSION-devos ([a-z0-9]*)|$KERNEL_VERSION-devos ($DEVOS_ARCH)|" \
    -e "s|DevOsPM [0-9][0-9.]*|DevOsPM $DEVOS_PM_VER|" \
    "$ROOTFS/etc/motd"

log "generating device nodes with gen_init_cpio (no root required)"
# gen_init_cpio is a kernel host tool that can emit device nodes into a cpio
# archive without root; archives concatenate, so nodes are appended after the
# main tree archive. (Since ~6.12 it takes the description as a file argument.)
make -C "$KERNEL_SRC" -s usr/gen_init_cpio
cat > "$WORK/nodes.cpio.desc" <<EOF
nod /dev/console 0600 0 0 c 5 1
nod /dev/null    0666 0 0 c 1 3
nod /dev/zero    0666 0 0 c 1 5
nod /dev/tty     0666 0 0 c 5 0
nod /dev/ptmx    0666 0 0 c 5 2
nod /dev/random  0666 0 0 c 1 8
nod /dev/urandom 0666 0 0 c 1 9
nod /dev/ttyAMA0 0666 0 0 c 204 64
nod /dev/ttyS0   0666 0 0 c 4 64
EOF
"$KERNEL_SRC/usr/gen_init_cpio" "$WORK/nodes.cpio.desc" > "$WORK/nodes.cpio"

log "packing initramfs (newc cpio + gzip)"
set +e
( cd "$ROOTFS" && find . -print0 | cpio --null -o -H newc --owner=+0:+0 > "$WORK/main.cpio" 2>/dev/null )
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
    ( cd "$ROOTFS" && find . -print0 | cpio --null -o -H newc > "$WORK/main.cpio" 2>/dev/null )
fi
cat "$WORK/main.cpio" "$WORK/nodes.cpio" | gzip -9 > "$INITRAMFS"

ok "initramfs: $INITRAMFS ($(du -h "$INITRAMFS" | cut -f1))"
log "rootfs summary:"
echo "  applets : $(ls "$ROOTFS/bin" | grep -v busybox | wc -l) commands in /bin"
echo "  /init   : $(head -3 "$ROOTFS/init" | tail -1 | sed 's/^# *//')"
