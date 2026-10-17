#!/usr/bin/env bash
# 26-build-git-gh.sh — build a fully static git (HTTPS via openssl+curl on
# musl) and add the official GitHub CLI (gh, static Go binary), for DevOs.
#
# Native builds use the musl.cc native toolchain. Cross builds (e.g. x86_64
# target on an aarch64 host) first build musl itself from source with the GNU
# cross gcc — musl's `musl-gcc` wrapper then gives a native-speed static-musl
# compiler for the target.
#
# Stages are cached with marker files — re-running skips finished stages.
set -euo pipefail
source "$(dirname "$0")/common.sh"

N="$(nproc)"
MUSL_VERSION="1.2.5"
THIRD="$WORK/third-$DEVOS_ARCH"            # zlib/openssl/curl install prefix
STAGE="$WORK/tools-stage-$DEVOS_ARCH"      # final /usr tree for the image
MARK="$WORK/.marks-gitgh-$DEVOS_ARCH"
BUILD_TRIPLE="$DEVOS_HOST_ARCH-linux-gnu"
# autoconf --host/--build only when actually cross-building; on native builds
# they would make configure refuse to run its (passing) test programs
HOST_ARGS=()
if [ "$IS_CROSS" = "1" ]; then
    HOST_ARGS=(--host="$MUSL_TARGET" --build="$BUILD_TRIPLE")
    # known-Linux answers for git's unguarded AC_TRY_RUN checks (same set
    # Buildroot uses for cross git)
    export ac_cv_snprintf_returns_bogus=no ac_cv_fread_reads_directories=yes ac_cv_iconv_omits_bom=yes
fi
mkdir -p "$MARK" "$DL"

log "=== DevOs: building git + gh ($DEVOS_ARCH target, $DEVOS_HOST_ARCH host) ==="
require_tools curl tar make gcc perl file xz

fetch() { # fetch <url> <dest>
    # /usr/bin/curl explicitly when possible: a musl binary we may have just
    # built into $THIRD/bin cannot run on a glibc host
    CURL_BIN=/usr/bin/curl
    command -v "$CURL_BIN" >/dev/null 2>&1 || CURL_BIN=curl
    if [ ! -f "$2" ]; then
        log "downloading $(basename "$2")"
        "$CURL_BIN" -fL --retry 3 -C - -o "$2" "$1"
    fi
}

# ---- resolve latest upstream versions ------------------------------------
gh_tag="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
    | sed -n 's/.*"tag_name": *"v\([0-9.]*\)".*/\1/p' | head -1)"
git_tar="$(curl -fsSL https://www.kernel.org/pub/software/scm/git/ \
    | grep -oE 'git-2\.[0-9]+\.[0-9]+\.tar\.xz' | sort -uV | tail -1)"
ossl_ver="$(curl -fsSL https://api.github.com/repos/openssl/openssl/releases/latest \
    | sed -n 's/.*"tag_name": *"openssl-\([0-9.]*\)".*/\1/p' | head -1)"
curl_tag="$(curl -fsSL https://api.github.com/repos/curl/curl/releases/latest \
    | sed -n 's/.*"tag_name": *"curl-\([0-9_]*\)".*/\1/p' | head -1)"
curl_ver="$(echo "$curl_tag" | tr '_' '.')"
git_ver="${git_tar#git-}"; git_ver="${git_ver%.tar.xz}"
if [ -z "${gh_tag:-}" ] || [ -z "$git_ver" ] || [ -z "${ossl_ver:-}" ] || [ -z "$curl_ver" ]; then
    die "could not resolve upstream versions (git=$git_ver openssl=$ossl_ver curl=$curl_ver gh=$gh_tag)"
fi
log "git $git_ver · openssl $ossl_ver · curl $curl_ver · gh $gh_tag"

# ---- target C toolchain (CC/AR/RANLIB env for everything below) -----------
if [ "$IS_CROSS" = "1" ]; then
    # cross: build musl from source with the GNU cross gcc -> musl-gcc wrapper
    MUSL_PREFIX="$WORK/musl-$DEVOS_ARCH"
    export CC="$MUSL_PREFIX/bin/musl-gcc"
    export AR="${CROSS_PREFIX}ar"
    export RANLIB="${CROSS_PREFIX}ranlib"
    if [ ! -f "$MARK/tc.done" ]; then
        command -v "${CROSS_PREFIX}gcc" >/dev/null 2>&1 \
            || die "cross compiler ${CROSS_PREFIX}gcc not found — install e.g. crossbuild-essential-amd64"
        log "building musl $MUSL_VERSION for $DEVOS_ARCH with ${CROSS_PREFIX}gcc"
        fetch "https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz" "$DL/musl-$MUSL_VERSION.tar.gz"
        rm -rf "$WORK/musl-$MUSL_VERSION" "$MUSL_PREFIX"
        tar -C "$WORK" -xzf "$DL/musl-$MUSL_VERSION.tar.gz"
        ( cd "$WORK/musl-$MUSL_VERSION" \
            && CC="${CROSS_PREFIX}gcc" ./configure --disable-shared --prefix="$MUSL_PREFIX" \
            && make -j"$N" && make install )
        file "$MUSL_PREFIX/lib/libc.a" | grep -q "$DEVOS_ARCH" \
            || die "musl built for wrong arch: $(file "$MUSL_PREFIX/lib/libc.a")"
        ok "musl toolchain: $CC"
        touch "$MARK/tc.done"
    fi
    # source-built musl lacks the kernel UAPI headers (musl.cc toolchains
    # ship them) — install them from the kernel tree; openssl's mem_sec.c
    # and friends need linux/*.h
    if [ ! -f "$MARK/hdr.done" ]; then
        if [ ! -d "$KERNEL_SRC" ]; then
            die "kernel source missing at $KERNEL_SRC — run 10-build-kernel.sh first"
        fi
        log "installing kernel UAPI headers into $MUSL_PREFIX"
        make -C "$KERNEL_SRC" ARCH="$KARCH" INSTALL_HDR_PATH="$MUSL_PREFIX" -s headers_install
        touch "$MARK/hdr.done"
    fi
else
    # native: musl.cc toolchain (user-local, no sudo needed)
    if [ ! -f "$MARK/tc.done" ]; then
        fetch "$MUSL_NATIVE_URL" "$DL/$(basename "$MUSL_NATIVE_URL")"
        rm -rf "$WORK/musl-extract"; mkdir -p "$WORK/musl-extract"
        tar -C "$WORK/musl-extract" -xzf "$DL/$(basename "$MUSL_NATIVE_URL")"
        GCC_BIN="$(find "$WORK/musl-extract" -type f \
            \( -name "${DEVOS_ARCH}-linux-musl-gcc" -o -name 'musl-gcc' -o -name 'gcc' \) | head -1)"
        if [ -z "$GCC_BIN" ]; then
            die "no gcc found inside the musl toolchain archive"
        fi
        TCBIN="$(dirname "$GCC_BIN")"
        CC_NAME="$(basename "$GCC_BIN")"
        printf 'TCBIN=%q\nCC_NAME=%q\n' "$TCBIN" "$CC_NAME" > "$MARK/env"
        export PATH="$TCBIN:$PATH"
        export CC="$CC_NAME"
        printf 'int main(void){return 0;}\n' > "$WORK/tcsmoke.c"
        "$CC" -static -o "$WORK/tcsmoke" "$WORK/tcsmoke.c"
        file "$WORK/tcsmoke" | grep -Eq 'statically linked|static-pie' \
            || die "musl gcc did not produce a static binary"
        ok "musl toolchain ready: $CC"
        touch "$MARK/tc.done"
    fi
    . "$MARK/env"
    export PATH="$TCBIN:$THIRD/bin:$PATH"
    export CC="$CC_NAME"
    export AR=ar
    export RANLIB=ranlib
fi

# ---- zlib (static) ----------------------------------------------------------
if [ ! -f "$MARK/zlib.done" ]; then
    log "building zlib 1.3.1 (static)"
    fetch https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz \
        "$DL/zlib-1.3.1.tar.gz"
    rm -rf "$WORK/zlib-1.3.1"
    tar -C "$WORK" -xzf "$DL/zlib-1.3.1.tar.gz"
    ( cd "$WORK/zlib-1.3.1" \
        && CC="$CC" CFLAGS="-O2" ./configure --static --prefix="$THIRD" \
        && make -j"$N" && make install )
    touch "$MARK/zlib.done"
fi

# ---- openssl (static, libs only) ---------------------------------------------
if [ ! -f "$MARK/openssl.done" ]; then
    log "building openssl $ossl_ver (static, no-asm)"
    fetch "https://github.com/openssl/openssl/releases/download/openssl-$ossl_ver/openssl-$ossl_ver.tar.gz" \
        "$DL/openssl-$ossl_ver.tar.gz"
    rm -rf "$WORK/openssl-$ossl_ver"
    tar -C "$WORK" -xzf "$DL/openssl-$ossl_ver.tar.gz"
    ( cd "$WORK/openssl-$ossl_ver" \
        && ./Configure "$OPENSSL_TARGET" no-shared no-apps no-tests no-docs no-asm \
               --prefix="$THIRD" --libdir=lib CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="-O2" \
        && make -j"$N" \
        && make install_sw )
    touch "$MARK/openssl.done"
fi

# ---- curl (static libcurl for git HTTPS) --------------------------------------
if [ ! -f "$MARK/curl.done" ]; then
    log "building curl $curl_ver (static)"
    fetch "https://curl.se/download/curl-$curl_ver.tar.xz" "$DL/curl-$curl_ver.tar.xz"
    rm -rf "$WORK/curl-$curl_ver"
    tar -C "$WORK" -xJf "$DL/curl-$curl_ver.tar.xz"
    ( cd "$WORK/curl-$curl_ver" \
        && ./configure --prefix="$THIRD" --disable-shared --enable-static \
               "${HOST_ARGS[@]}" \
               --with-openssl="$THIRD" --with-zlib="$THIRD" \
               --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
               --without-libpsl --without-nghttp2 --without-brotli --without-zstd \
               --without-libidn2 --without-librtmp --disable-ldap --disable-ldaps \
               CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="-Os" LDFLAGS="-static" \
        && make -j"$N" && make install )
    touch "$MARK/curl.done"
fi

# ---- git (static, HTTPS via our curl/openssl) ----------------------------------
if [ ! -f "$MARK/git.done" ]; then
    log "building git $git_ver (static musl)"
    fetch "https://www.kernel.org/pub/software/scm/git/$git_tar" "$DL/$git_tar"
    rm -rf "$WORK/git-$git_ver" "$STAGE" "$MARK/gh.done"
    tar -C "$WORK" -xJf "$DL/$git_tar"
    # configure's `-lcurl` probe fails against static-only libcurl.a (its
    # deps must follow on the link line), so configure sets NO_CURL. Undo
    # that at make time and spell out the full static link order instead.
    ( cd "$WORK/git-$git_ver" \
        && ./configure --prefix=/usr --libexecdir=/usr/libexec \
               "${HOST_ARGS[@]}" \
               --with-curl="$THIRD" --with-openssl="$THIRD" --with-zlib="$THIRD" \
               --without-tcltk --disable-nls \
               CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="-O2" LDFLAGS="-static" \
        && make -j"$N" NO_PERL=1 NO_PYTHON=1 NO_TCLTK=1 NO_GETTEXT=1 NO_RUST=1 \
               NO_CURL= CURLDIR="$THIRD" \
               CURL_LDFLAGS="-lcurl -lssl -lcrypto -lz" \
        && make install NO_PERL=1 NO_PYTHON=1 NO_TCLTK=1 NO_GETTEXT=1 NO_RUST=1 \
               NO_CURL= CURLDIR="$THIRD" \
               CURL_LDFLAGS="-lcurl -lssl -lcrypto -lz" \
               NO_INSTALL_HARDLINKS=1 DESTDIR="$STAGE" )
    file "$STAGE/usr/bin/git" | grep -Eq 'statically linked|static-pie' \
        || die "git binary is not static: $(file "$STAGE/usr/bin/git")"
    # git-remote-https is the whole point of the curl/openssl stack
    # (-L: it is installed as a symlink to git-remote-http)
    file -L "$STAGE/usr/libexec/git-core/git-remote-https" | grep -Eq 'statically linked|static-pie' \
        || die "git-remote-https is missing or not static"
    if [ "$IS_CROSS" = "0" ]; then
        # end-to-end HTTPS smoke test on the build host (same static binaries)
        log "smoke test: git ls-remote over HTTPS"
        GIT_EXEC_PATH="$STAGE/usr/libexec/git-core" \
            "$STAGE/usr/bin/git" ls-remote https://github.com/octocat/Hello-World.git HEAD \
            || die "git HTTPS smoke test failed on the build host"
    else
        log "cross build — HTTPS smoke test happens in the QEMU boot test instead"
    fi
    touch "$MARK/git.done"
fi

# ---- gh (official static binary) ------------------------------------------
if [ ! -f "$MARK/gh.done" ]; then
    log "fetching gh $gh_tag (official static, $GH_ASSET_ARCH)"
    fetch "https://github.com/cli/cli/releases/download/v$gh_tag/gh_${gh_tag#v}_${GH_ASSET_ARCH}.tar.gz" \
        "$DL/gh_${gh_tag#v}_${GH_ASSET_ARCH}.tar.gz"
    rm -rf "$WORK/gh-extract"; mkdir -p "$WORK/gh-extract"
    tar -C "$WORK/gh-extract" -xzf "$DL/gh_${gh_tag#v}_${GH_ASSET_ARCH}.tar.gz"
    GH_BIN="$(find "$WORK/gh-extract" -type f -name gh | head -1)"
    [ -n "$GH_BIN" ] || die "gh binary not found in tarball"
    install -m 755 "$GH_BIN" "$STAGE/usr/bin/gh"
    touch "$MARK/gh.done"
fi

# ---- verify + record --------------------------------------------------------------
if [ "$IS_CROSS" = "0" ]; then
    "$STAGE/usr/bin/git" --version
    "$STAGE/usr/bin/gh" --version | head -1
else
    file "$STAGE/usr/bin/git" | cut -d: -f2 | xargs
    file "$STAGE/usr/bin/gh" | cut -d: -f2 | xargs
fi
printf 'git %s / gh %s' "$git_ver" "${gh_tag#v}" > "$WORK/tools-versions.txt"
ok "git + gh staged in $STAGE ($(du -sh "$STAGE" | cut -f1))"
