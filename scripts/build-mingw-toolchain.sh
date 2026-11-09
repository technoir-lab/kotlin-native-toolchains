#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
umask 022

readonly GCC_VERSION="13.4.0"
readonly MINGW_W64_VERSION="14.0.0"
readonly BINUTILS_VERSION="2.40"
readonly ZLIB_VERSION="1.2.13"
readonly CROSSTOOL_NG_VERSION="1.29.0"
readonly TARGET_TRIPLE="x86_64-w64-mingw32"
readonly KONAN_TRIPLE="x86_64-pc-windows-gnu"
readonly UBUNTU_IMAGE="ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
builder_root="$project_root/toolchains/mingw/builder"
builder_dockerfile="$project_root/toolchains/common/builder/Dockerfile"

# shellcheck source=lib/native-toolchain-registry.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-registry.sh"
# shellcheck source=lib/native-toolchain-checksum.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-checksum.sh"
# shellcheck source=lib/docker-builder.sh
# shellcheck disable=SC1091
source "$script_dir/lib/docker-builder.sh"
configure_docker_builder \
    "MinGW" \
    "io-technoirlab/mingw-konan-toolchain-builder" \
    "ctng-$CROSSTOOL_NG_VERSION" \
    "ubuntu24.04"

platform_descriptor="$project_root/toolchains/mingw/mingw.properties"
package_name="$(
    package_name_for \
        "$platform_descriptor" \
        "$NATIVE_TOOLCHAIN_KONAN_HOST"
)"
readonly package_name
artifact_identity="$(
    artifact_identity_for \
        "$platform_descriptor" \
        "$NATIVE_TOOLCHAIN_KONAN_HOST"
)"
readonly artifact_identity
default_output="$project_root/build/toolchains/$package_name"
init_build "$default_output"

usage() {
    sed -n 's/^# //p' <<'USAGE'
# Usage:
#   scripts/build-mingw-toolchain.sh [options]
#
# Builds a pinned GCC/MinGW-w64 x86-64 Windows target toolchain from source
# in an Ubuntu 24.04 Docker container matching the supported host architecture.
#
# Options:
#   --output-dir PATH  Destination artifact directory.
#   --archive          Also create build/dist/OUTPUT_NAME.tar.gz.
#   --force            Replace the exact output and archive paths.
#   -h, --help         Show this help.
USAGE
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

trap cleanup_build EXIT
parse_build_args usage "$@"
prepare_output \
    "$project_root" \
    "$builder_root" \
    "builder source"

run_docker_builder \
    "$builder_root" \
    "$builder_dockerfile" \
    "build-toolchain.sh" \
    "$UBUNTU_IMAGE" \
    "Building pinned Ubuntu 24.04 MinGW toolchain builder image..." \
    "Building GCC $GCC_VERSION / MinGW-w64 $MINGW_W64_VERSION target toolchain..."

toolchain="$staging_dir/toolchain"
target_sysroot="$toolchain/$TARGET_TRIPLE/sysroot/usr/$TARGET_TRIPLE"
require_stripped_gcc_prefix \
    "$toolchain" "$TARGET_TRIPLE" "$GCC_VERSION" "the MinGW toolchain"
[[ -f "$target_sysroot/include/windows.h" ]] ||
    die "missing MinGW Windows headers"
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
require_no_builder_paths "$staging_dir" "the MinGW toolchain"

builder_properties="$staging_dir/builder.properties"
[[ -f "$builder_properties" ]] || die "builder metadata was not produced"
for expected in \
    "builder.container.version=24.04" \
    "builder.container.arch=$builder_arch" \
    "crosstool.ng.version=$CROSSTOOL_NG_VERSION" \
    "gcc.version=$GCC_VERSION" \
    "mingw.w64.version=$MINGW_W64_VERSION" \
    "binutils.version=$BINUTILS_VERSION" \
    "zlib.version=$ZLIB_VERSION" \
    "mingw.crt=msvcrt" \
    "mingw.threads=posix"; do
    grep -Fxq "$expected" "$builder_properties" ||
        die "builder metadata is missing $expected"
done

mkdir -p "$staging_dir/konan-sysroot/include" "$staging_dir/konan-sysroot/lib"
ln -s \
    "../toolchain/$TARGET_TRIPLE/sysroot/usr/$TARGET_TRIPLE" \
    "$staging_dir/konan-sysroot/$TARGET_TRIPLE"
ln -s "$TARGET_TRIPLE" "$staging_dir/konan-sysroot/mingw"
ln -s "../../toolchain/lib/gcc" "$staging_dir/konan-sysroot/lib/gcc"
# Clang's MinGW driver looks for the libstdc++ headers in
# <sysroot>/include/c++/<version>, taking the version from lib/gcc above.
ln -s \
    "../../toolchain/$TARGET_TRIPLE/include/c++" \
    "$staging_dir/konan-sysroot/include/c++"

config_sha256="$(
    sha256_file "$builder_root/configs/mingw-x64.config"
)"

manifest="$staging_dir/manifest.properties"
write_manifest_header \
    "$platform_descriptor" \
    "$package_name" \
    "$artifact_identity" \
    "$NATIVE_TOOLCHAIN_HOST_OS" \
    "$NATIVE_TOOLCHAIN_HOST_ARCH" \
    "$NATIVE_TOOLCHAIN_KONAN_HOST" \
    "$builder_host_tag" \
    >"$manifest"
cat >>"$manifest" <<EOF
builder.container.image=$UBUNTU_IMAGE
builder.container.platform=$builder_platform
builder.image.id=$builder_image_id
builder.kotlin.version=2.4.21
builder.crosstool.ng.version=$CROSSTOOL_NG_VERSION
gcc.version=$GCC_VERSION
mingw.w64.version=$MINGW_W64_VERSION
binutils.version=$BINUTILS_VERSION
zlib.version=$ZLIB_VERSION
mingw.crt=msvcrt
mingw.threads=posix
target.mingw_x64.triple=$TARGET_TRIPLE
target.mingw_x64.konan.triple=$KONAN_TRIPLE
config.mingw_x64.sha256=$config_sha256
EOF

chmod 0755 "$staging_dir"
normalize_tree_metadata "$staging_dir"

publish_output "Created MinGW toolchain"
publish_archive
