#!/usr/bin/env bash
set -euo pipefail
umask 022

readonly TARGET="x86_64-w64-mingw32"
readonly GCC_VERSION="13.4.0"
readonly MINGW_W64_VERSION="14.0.0"
readonly CROSSTOOL_MINGW_W64_VERSION="v$MINGW_W64_VERSION"
readonly BINUTILS_VERSION="2.40"
readonly ZLIB_VERSION="1.2.13"
readonly CROSSTOOL_NG_VERSION="1.29.0"
readonly BUILDER_ROOT="/opt/toolchain-builder"
readonly ARTIFACT_ROOT="/artifacts"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

assert_config_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(sed -n "s/^${key}=//p" .config | head -n 1)"
    [[ "$actual" == "\"$expected\"" ]] ||
        die "crosstool-NG resolved $key=${actual:-unset}; expected \"$expected\""
}

assert_config_enabled() {
    local key="$1"
    grep -Fxq "$key=y" .config ||
        die "crosstool-NG did not enable $key"
}

build_toolchain() {
    local build_root="$1"

    mkdir "$build_root"
    cp "$BUILDER_ROOT/configs/mingw-x64.config" "$build_root/.config"
    (
        cd "$build_root"
        ct-ng olddefconfig
        assert_config_value CT_GCC_VERSION "$GCC_VERSION"
        assert_config_value CT_MINGW_W64_VERSION "$CROSSTOOL_MINGW_W64_VERSION"
        assert_config_value CT_BINUTILS_VERSION "$BINUTILS_VERSION"
        assert_config_value CT_ZLIB_VERSION "$ZLIB_VERSION"
        assert_config_enabled CT_MINGW_DEFAULT_MSVCRT_MSVCRT
        assert_config_enabled CT_THREADS_POSIX
        ct-ng build
    )
}

ensure_konan_layout() {
    local toolchain_root="$1"
    local target_sysroot="$toolchain_root/$TARGET/sysroot/usr/$TARGET"
    local target_lib="$target_sysroot/lib"
    local static_cxx="$target_lib/libstdc++.a"
    local candidate

    if [[ ! -f "$static_cxx" ]]; then
        candidate="$(
            find "$toolchain_root" -type f -name libstdc++.a -print -quit
        )"
        [[ -n "$candidate" ]] && cp -a "$candidate" "$static_cxx"
    fi
    [[ -f "$static_cxx" ]] ||
        die "cannot locate static libstdc++ for $TARGET"
}

verify_toolchain_inputs() {
    local toolchain_root="$1"
    local target_sysroot="$toolchain_root/$TARGET/sysroot/usr/$TARGET"
    local gcc_runtime="$toolchain_root/lib/gcc/$TARGET/$GCC_VERSION"
    local input

    [[ -d "$target_sysroot/include" && -f "$target_sysroot/include/windows.h" ]] ||
        die "MinGW-w64 headers were not installed"
    for input in \
        crt2.o \
        dllcrt2.o \
        libbcrypt.a \
        libkernel32.a \
        libmsvcrt.a \
        libstdc++.a \
        libwinpthread.a; do
        [[ -f "$target_sysroot/lib/$input" ]] ||
            die "missing MinGW linker input $input"
    done
    for input in libgcc.a libgcc_eh.a; do
        [[ -f "$gcc_runtime/$input" ]] ||
            die "missing GCC runtime input $input"
    done
}

# Prints the paths, relative to the crosstool-NG prefix, that Kotlin/Native
# never uses. Its own LLVM compiles, links, and archives, so no GCC, binutils,
# or MinGW-w64 host program runs; Clang has its own headers and runtime; and
# LLD ignores GNU ld scripts. toolchain.cmake points at the removed gcc. The
# libstdc++ GDB printers, their auto-load hooks, which embed build paths, and
# crosstool-NG's build log are left out too. Kotlin/Native has no 32-bit
# Windows target, but mingw-w64-crt builds lib32 even without CT_MULTILIB.
unused_toolchain_paths() {
    local gcc_lib="lib/gcc/$TARGET/$GCC_VERSION"

    printf '%s\n' \
        bin \
        build.log.bz2 \
        include \
        lib/bfd-plugins \
        "$gcc_lib/include" \
        "$gcc_lib/include-fixed" \
        "$gcc_lib/install-tools" \
        "$gcc_lib/libgcov.a" \
        libexec \
        "share/gcc-$GCC_VERSION" \
        toolchain.cmake \
        "$TARGET/bin" \
        "$TARGET/debug-root" \
        "$TARGET/lib/ldscripts" \
        "$TARGET/lib/libstdc++.dll.a-gdb.py" \
        "$TARGET/sysroot/lib/libstdc++.dll.a-gdb.py" \
        "$TARGET/sysroot/usr/$TARGET/lib32"
}

# Prints the Kotlin/Native inputs that share directories with unused paths.
retained_toolchain_paths() {
    local gcc_lib="lib/gcc/$TARGET/$GCC_VERSION"

    printf '%s\n' \
        "$gcc_lib/crtbegin.o" \
        "$gcc_lib/crtend.o" \
        "$gcc_lib/libgcc.a" \
        "$gcc_lib/libgcc_eh.a" \
        share/licenses \
        "share/$TARGET-ct-ng.config.bz2" \
        "$TARGET/include/c++/$GCC_VERSION/string" \
        "$TARGET/lib/libstdc++.a" \
        "$TARGET/sysroot/lib/libstdc++.a" \
        "$TARGET/sysroot/usr/$TARGET/lib/libmsvcrt.a"
}

# Removes the unused paths from the toolchain prefix. Every listed path must
# exist, so a crosstool-NG layout change fails the build until the list is
# updated.
strip_unused_toolchain_files() {
    local toolchain_root="$1"
    local path

    while IFS= read -r path; do
        [[ -e "$toolchain_root/$path" || -L "$toolchain_root/$path" ]] ||
            die "the $TARGET toolchain has no $path to remove"
        rm -rf -- "${toolchain_root:?}/$path"
    done < <(unused_toolchain_paths)
    while IFS= read -r path; do
        [[ -e "$toolchain_root/$path" ]] ||
            die "the $TARGET toolchain is missing $path"
    done < <(retained_toolchain_paths)
}

write_builder_properties() {
    cat <<EOF
builder.container.os=ubuntu
builder.container.version=24.04
builder.container.arch=$BUILDER_ARCH
crosstool.ng.version=$CROSSTOOL_NG_VERSION
gcc.version=$GCC_VERSION
mingw.w64.version=$MINGW_W64_VERSION
binutils.version=$BINUTILS_VERSION
zlib.version=$ZLIB_VERSION
mingw.crt=msvcrt
mingw.threads=posix
EOF
}

main() {
    local build_root="/home/ct/build-mingw_x64"
    local toolchain_root="/home/ct/x-tools/$TARGET"

    [[ -d "$ARTIFACT_ROOT" && -w "$ARTIFACT_ROOT" ]] ||
        die "$ARTIFACT_ROOT must be a writable bind mount"
    [[ "${BUILDER_ARCH:-}" == "amd64" || "${BUILDER_ARCH:-}" == "arm64" ]] ||
        die "BUILDER_ARCH must be amd64 or arm64"
    [[ ! -e "$ARTIFACT_ROOT/toolchain" ]] ||
        die "$ARTIFACT_ROOT/toolchain already exists"

    build_toolchain "$build_root"
    ensure_konan_layout "$toolchain_root"
    verify_toolchain_inputs "$toolchain_root"
    strip_unused_toolchain_files "$toolchain_root"

    mkdir "$ARTIFACT_ROOT/toolchain"
    cp -a "$toolchain_root/." "$ARTIFACT_ROOT/toolchain/"
    write_builder_properties >"$ARTIFACT_ROOT/builder.properties"

    printf 'Built MinGW target toolchain in %s\n' "$ARTIFACT_ROOT/toolchain"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
