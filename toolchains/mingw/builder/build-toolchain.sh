#!/usr/bin/env bash
set -euo pipefail
umask 022

readonly TARGET="x86_64-w64-mingw32"
readonly GCC_VERSION="13.2.0"
readonly MINGW_W64_VERSION="10.0.0"
readonly CROSSTOOL_MINGW_W64_VERSION="v$MINGW_W64_VERSION"
readonly BINUTILS_VERSION="2.40"
readonly ZLIB_VERSION="1.2.13"
readonly CROSSTOOL_NG_VERSION="1.26.0"
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

[[ -d "$ARTIFACT_ROOT" && -w "$ARTIFACT_ROOT" ]] ||
    die "$ARTIFACT_ROOT must be a writable bind mount"
[[ "${BUILDER_ARCH:-}" == "amd64" || "${BUILDER_ARCH:-}" == "arm64" ]] ||
    die "BUILDER_ARCH must be amd64 or arm64"
[[ ! -e "$ARTIFACT_ROOT/toolchain" ]] ||
    die "$ARTIFACT_ROOT/toolchain already exists"

build_root="/home/ct/build-mingw_x64"
toolchain_root="/home/ct/x-tools/$TARGET"
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

ensure_konan_layout "$toolchain_root"
target_sysroot="$toolchain_root/$TARGET/sysroot/usr/$TARGET"
gcc_runtime="$toolchain_root/lib/gcc/$TARGET/$GCC_VERSION"

[[ -x "$toolchain_root/bin/$TARGET-gcc" ]] ||
    die "crosstool-NG did not produce $TARGET-gcc"
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

mkdir "$ARTIFACT_ROOT/toolchain"
cp -a "$toolchain_root/." "$ARTIFACT_ROOT/toolchain/"

cat >"$ARTIFACT_ROOT/builder.properties" <<EOF
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

printf 'Built MinGW target toolchain in %s\n' "$ARTIFACT_ROOT/toolchain"
