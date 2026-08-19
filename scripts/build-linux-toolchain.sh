#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
umask 022

readonly GCC_VERSION="13.2.0"
readonly GLIBC_VERSION="2.35"
readonly LINUX_HEADERS_VERSION="5.15.118"
readonly BINUTILS_VERSION="2.40"
readonly ZLIB_VERSION="1.2.13"
readonly CROSSTOOL_NG_VERSION="1.26.0"
readonly UBUNTU_IMAGE="ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
builder_root="$project_root/toolchains/linux/builder"
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
    "Linux" \
    "io-technoirlab/linux-konan-toolchain-builder" \
    "ctng-$CROSSTOOL_NG_VERSION" \
    "ubuntu24.04"

platform_descriptor="$project_root/toolchains/linux/linux.properties"
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
#   scripts/build-linux-toolchain.sh [options]
#
# Builds linux_x64 and linux_arm64 GCC/sysroot distributions from source in
# a pinned Ubuntu 24.04 Docker container matching the supported host architecture.
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
    "build-toolchains.sh" \
    true \
    "$UBUNTU_IMAGE" \
    "Building pinned Ubuntu 24.04 toolchain builder image..." \
    "Building GCC $GCC_VERSION Linux target toolchains..."

readonly target_rows=(
    "linux_x64|x86_64-unknown-linux-gnu|lib64/ld-linux-x86-64.so.2"
    "linux_arm64|aarch64-unknown-linux-gnu|lib/ld-linux-aarch64.so.1"
)

for row in "${target_rows[@]}"; do
    IFS='|' read -r konan_target triple loader <<<"$row"
    target_root="$staging_dir/targets/$konan_target"
    sysroot="$target_root/$triple/sysroot"
    gcc_runtime="$target_root/lib/gcc/$triple/$GCC_VERSION"
    [[ -x "$target_root/bin/$triple-gcc" ]] ||
        die "missing GCC driver for $konan_target"
    [[ -x "$target_root/bin/$triple-ar" ]] ||
        die "missing archive tool for $konan_target"
    [[ -d "$sysroot/usr/include/linux" ]] ||
        die "missing Linux headers for $konan_target"
    [[ -f "$sysroot/usr/lib/crt1.o" && -f "$sysroot/usr/lib/libc.so" ]] ||
        die "missing glibc startup or linker inputs for $konan_target"
    [[ -f "$sysroot/$loader" ]] ||
        die "missing dynamic loader $loader for $konan_target"
    [[ -f "$sysroot/lib/libstdc++.a" ]] ||
        die "missing static libstdc++ for $konan_target"
    [[ -f "$sysroot/usr/lib/libz.a" ]] ||
        die "missing target zlib for $konan_target"
    [[ -f "$gcc_runtime/libgcc.a" && -f "$gcc_runtime/libgcc_eh.a" ]] ||
        die "missing GCC runtime for $konan_target"
done

builder_properties="$staging_dir/builder.properties"
[[ -f "$builder_properties" ]] || die "builder metadata was not produced"
for expected in \
    "builder.container.version=24.04" \
    "builder.container.arch=$builder_arch" \
    "crosstool.ng.version=$CROSSTOOL_NG_VERSION" \
    "gcc.version=$GCC_VERSION" \
    "glibc.version=$GLIBC_VERSION" \
    "linux.headers.version=$LINUX_HEADERS_VERSION" \
    "binutils.version=$BINUTILS_VERSION" \
    "zlib.version=$ZLIB_VERSION"; do
    grep -Fxq "$expected" "$builder_properties" ||
        die "builder metadata is missing $expected"
done

x64_config_sha256="$(
    sha256_file "$builder_root/configs/linux-x64.config"
)"
arm64_config_sha256="$(
    sha256_file "$builder_root/configs/linux-arm64.config"
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
builder.kotlin.version=2.4.10
builder.kotlin.commit=5687445832cd835b4509b9fbc264cdf1a8201093
builder.crosstool.ng.version=$CROSSTOOL_NG_VERSION
builder.crosstool.ng.commit=334f6d6479096b20e80fd39e35f404319bc251b5
gcc.version=$GCC_VERSION
glibc.version=$GLIBC_VERSION
linux.headers.version=$LINUX_HEADERS_VERSION
binutils.version=$BINUTILS_VERSION
zlib.version=$ZLIB_VERSION
target.linux_x64.triple=x86_64-unknown-linux-gnu
target.linux_x64.dynamic.loader=/lib64/ld-linux-x86-64.so.2
target.linux_arm64.triple=aarch64-unknown-linux-gnu
target.linux_arm64.dynamic.loader=/lib/ld-linux-aarch64.so.1
config.linux_x64.sha256=$x64_config_sha256
config.linux_arm64.sha256=$arm64_config_sha256
EOF

chmod 0755 "$staging_dir"
normalize_tree_metadata "$staging_dir"

publish_output "Created Linux toolchain"
publish_archive
