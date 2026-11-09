#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
umask 022

readonly GCC_VERSION="13.4.0"
readonly GLIBC_VERSION="2.25"
readonly LINUX_HEADERS_VERSION="5.15.209"
readonly BINUTILS_VERSION="2.29.1"
readonly CROSSTOOL_NG_VERSION="1.29.0"
readonly UBUNTU_IMAGE="ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
builder_root="$project_root/toolchains/linux/builder"
builder_dockerfile="$project_root/toolchains/common/builder/Dockerfile"
# The sources the builder downloads itself are pinned only in this lock file.
source_lock="$builder_root/image/sources.lock"
graphics_header_list="$builder_root/image/graphics-headers.txt"

# shellcheck source=../toolchains/linux/builder/image/sources.sh
# shellcheck disable=SC1091
source "$builder_root/image/sources.sh"
source_versions="$(source_version_properties "$source_lock")"
readonly source_versions

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
    require_stripped_gcc_prefix \
        "$target_root" "$triple" "$GCC_VERSION" "the $konan_target toolchain"
    [[ -d "$sysroot/usr/include/linux" ]] ||
        die "missing Linux headers for $konan_target"
    require_listed_files \
        "$sysroot/usr/include" \
        "$graphics_header_list" \
        "the $konan_target sysroot"
    require_source_licenses \
        "$source_lock" \
        "$target_root/share/licenses" \
        "the $konan_target toolchain"
    [[ -f "$sysroot/usr/lib/crt1.o" && -f "$sysroot/usr/lib/libc.so" ]] ||
        die "missing glibc startup or linker inputs for $konan_target"
    [[ -f "$sysroot/$loader" ]] ||
        die "missing dynamic loader $loader for $konan_target"
    [[ -f "$sysroot/lib/libstdc++.a" ]] ||
        die "missing static libstdc++ for $konan_target"
    [[ -f "$sysroot/usr/lib/libz.a" ]] ||
        die "missing target zlib for $konan_target"
done
require_no_builder_paths "$staging_dir" "the Linux toolchain"

builder_properties="$staging_dir/builder.properties"
[[ -f "$builder_properties" ]] || die "builder metadata was not produced"
while IFS= read -r expected; do
    grep -Fxq "$expected" "$builder_properties" ||
        die "builder metadata is missing $expected"
done < <(
    printf '%s\n' \
        "builder.container.version=24.04" \
        "builder.container.arch=$builder_arch" \
        "crosstool.ng.version=$CROSSTOOL_NG_VERSION" \
        "gcc.version=$GCC_VERSION" \
        "glibc.version=$GLIBC_VERSION" \
        "linux.headers.version=$LINUX_HEADERS_VERSION" \
        "binutils.version=$BINUTILS_VERSION" \
        "$source_versions"
)

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
builder.kotlin.version=2.4.21
builder.kotlin.commit=9180ce6a7a7d3627f88b424717583f28ddca052d
builder.crosstool.ng.version=$CROSSTOOL_NG_VERSION
builder.crosstool.ng.commit=d7a90ff11aae5e59d6acd8c491f0297c15b7fa37
gcc.version=$GCC_VERSION
glibc.version=$GLIBC_VERSION
linux.headers.version=$LINUX_HEADERS_VERSION
binutils.version=$BINUTILS_VERSION
$source_versions
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
