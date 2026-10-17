#!/usr/bin/env bash
# 25-build-devospm.sh — build DevOsPM (the `dev` package manager) as a static
# musl aarch64 binary so it runs on the DevOs initramfs, and pack the hello
# example package for an offline demo.
#
# Source: $DEVOSPM_SRC (default: the sibling DevOsPM checkout next to this
# repository, i.e. $REPO/../DevOsPM). Rust is installed user-locally via
# rustup when missing (no sudo required).
set -euo pipefail
source "$(dirname "$0")/common.sh"

DEVOSPM_SRC="${DEVOSPM_SRC:-$REPO/../DevOsPM}"
DEVOSPM_BUILD="$WORK/devospm"
DEVOSPM_OUT="$WORK/devospm-bin"
TARGET="$MUSL_TARGET"   # auto: aarch64- or x86_64-unknown-linux-musl

log "=== DevOs: building DevOsPM (dev package manager) ==="
require_tools curl tar gcc file

if [ ! -f "$DEVOSPM_SRC/Cargo.toml" ]; then
    die "DevOsPM source not found at $DEVOSPM_SRC — set DEVOSPM_SRC=... or clone the repo there"
fi
DEVOSPM_VERSION="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$DEVOSPM_SRC/Cargo.toml" | head -1)"
log "DevOsPM source: $DEVOSPM_SRC (v$DEVOSPM_VERSION)"

# --- Rust toolchain (user-local rustup install, no sudo needed) -------------
if ! command -v cargo >/dev/null 2>&1; then
    log "cargo not found — installing Rust via rustup (user-local)"
    curl -fsS https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
fi
if [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi
command -v rustup >/dev/null 2>&1 \
    || die "rustup not available — a system Rust install cannot add the musl target; install rustup"
rustup target add "$TARGET"

# --- copy source to the fast filesystem --------------------------------------
log "copying source into $DEVOSPM_BUILD"
rm -rf "$DEVOSPM_BUILD"
mkdir -p "$DEVOSPM_BUILD"
( cd "$DEVOSPM_SRC" && tar --exclude=.git --exclude=target --exclude=dist -cf - . ) \
    | ( cd "$DEVOSPM_BUILD" && tar -xf - )

log "building static $TARGET binary — the first build takes a few minutes"
# ring (pulled in by rustls) compiles a little freestanding C for the target.
# On a native host the regular gcc already emits code for the same arch and
# ring's C does not reference libc, so pointing the target CC/AR at the host
# toolchain produces linkable objects for the musl build.
CC_VAR="CC_${TARGET//-/_}"
AR_VAR="AR_${TARGET//-/_}"
export "$CC_VAR"="${!CC_VAR:-cc}"
export "$AR_VAR"="${!AR_VAR:-ar}"
( cd "$DEVOSPM_BUILD" && cargo build --release --locked --target "$TARGET" )

BIN="$DEVOSPM_BUILD/target/$TARGET/release/dev"
if [ ! -f "$BIN" ]; then
    die "build produced no binary at $BIN"
fi
if ! file "$BIN" | grep -q 'statically linked'; then
    err "warning: $BIN does not report as static — it may not run on the DevOs initramfs"
fi

mkdir -p "$DEVOSPM_OUT"
install -m 755 "$BIN" "$DEVOSPM_OUT/dev"

# --- pack the hello example package (offline demo inside DevOs) -------------
log "packing example package (hello)"
rm -f "$WORK"/hello-*.dpk
( cd "$WORK" && "$DEVOSPM_OUT/dev" pack "$DEVOSPM_BUILD/examples/hello" >/dev/null )

printf '%s' "$DEVOSPM_VERSION" > "$WORK/devospm-version.txt"
ok "DevOsPM $DEVOSPM_VERSION built: $DEVOSPM_OUT/dev ($(du -h "$DEVOSPM_OUT/dev" | cut -f1))"
"$DEVOSPM_OUT/dev" --version
ok "example package: $(echo "$WORK"/hello-*.dpk)"
