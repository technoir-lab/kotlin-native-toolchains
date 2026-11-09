#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
umask 022

readonly EXPECTED_NDK_REVISION="29.0.14206865"
readonly EXPECTED_CLANG_MAJOR="21"
readonly EXPECTED_VULKAN_HEADER_VERSION="275"
readonly API_LEVEL="21"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"

# shellcheck source=lib/native-toolchain-host.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-host.sh"
# shellcheck source=lib/native-toolchain-registry.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-registry.sh"
# shellcheck source=lib/native-toolchain-checksum.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-checksum.sh"
# shellcheck source=lib/reproducible-archive.sh
# shellcheck disable=SC1091
source "$script_dir/lib/reproducible-archive.sh"
# shellcheck source=lib/native-toolchain-build-lifecycle.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-build-lifecycle.sh"
detect_host

case "$NATIVE_TOOLCHAIN_HOST_OS/$NATIVE_TOOLCHAIN_HOST_ARCH" in
    macos/arm64)
        HOST_TAG="darwin-x86_64"
        ;;
    linux/x64)
        HOST_TAG="linux-x86_64"
        ;;
    *)
        HOST_TAG="unsupported"
        ;;
esac
readonly HOST_TAG

platform_descriptor="$project_root/toolchains/android/android.properties"
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
ndk_dir=""
init_build "$default_output"

usage() {
    sed -n 's/^# //p' <<'USAGE'
# Usage:
#   scripts/build-android-toolchain.sh [options]
#
# Options:
#   --ndk-dir PATH     NDK r29 directory. Defaults to
#                      $ANDROID_HOME/ndk/29.0.14206865.
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
add_build_value_option --ndk-dir ndk_dir
parse_build_args usage "$@"

if [[ "$HOST_TAG" == "unsupported" ||
    "$NATIVE_TOOLCHAIN_KONAN_HOST" == "unsupported" ]]; then
    die "Android toolchain builds do not support $NATIVE_TOOLCHAIN_HOST_OS/$NATIVE_TOOLCHAIN_HOST_ARCH hosts"
fi

if [[ -z "$ndk_dir" ]]; then
    [[ -n "${ANDROID_HOME:-}" ]] ||
        die "ANDROID_HOME is unset; pass --ndk-dir explicitly"
    ndk_dir="$ANDROID_HOME/ndk/$EXPECTED_NDK_REVISION"
fi

[[ -d "$ndk_dir" ]] || die "NDK directory does not exist: $ndk_dir"
command -v rsync >/dev/null 2>&1 ||
    die "rsync is required to copy the Android NDK toolchain"
ndk_dir="$(cd "$ndk_dir" && pwd -P)"
prepare_output "$project_root" "$ndk_dir" "source NDK"

source_properties="$ndk_dir/source.properties"
[[ -f "$source_properties" ]] ||
    die "missing NDK source.properties: $source_properties"
actual_revision="$(
    sed -n 's/^Pkg\.Revision[[:space:]]*=[[:space:]]*//p' "$source_properties" |
        head -n 1
)"
[[ "$actual_revision" == "$EXPECTED_NDK_REVISION" ]] ||
    die "expected NDK $EXPECTED_NDK_REVISION, found ${actual_revision:-unknown}"

prebuilt="$ndk_dir/toolchains/llvm/prebuilt/$HOST_TAG"
[[ -d "$prebuilt" ]] || die "missing NDK host toolchain: $prebuilt"

readonly target_rows=(
    "android_arm32|arm|arm-linux-androideabi|armv7a-linux-androideabi21"
    "android_arm64|arm64|aarch64-linux-android|aarch64-linux-android21"
    "android_x86|x86|i686-linux-android|i686-linux-android21"
    "android_x64|x86_64|x86_64-linux-android|x86_64-linux-android21"
)

for row in "${target_rows[@]}"; do
    IFS='|' read -r konan_target architecture lib_triple clang_target <<<"$row"
    [[ -x "$prebuilt/bin/$clang_target-clang" ]] ||
        die "missing Clang wrapper for $konan_target"
    [[ -f "$prebuilt/sysroot/usr/lib/$lib_triple/$API_LEVEL/crtbegin_dynamic.o" ]] ||
        die "missing API $API_LEVEL runtime for $konan_target"
done

for tool in clang llvm-ar llvm-nm llvm-readelf; do
    [[ -x "$prebuilt/bin/$tool" ]] || die "missing required LLVM tool: $tool"
done

clang_version="$("$prebuilt/bin/clang" --version | head -n 1)"
clang_major="$(
    printf '%s\n' "$clang_version" |
        sed -n 's/.*clang version \([0-9][0-9]*\).*/\1/p'
)"
[[ "$clang_major" == "$EXPECTED_CLANG_MAJOR" ]] ||
    die "expected Clang $EXPECTED_CLANG_MAJOR.x, found: $clang_version"

source_vulkan_headers="$prebuilt/sysroot/usr/include/vulkan"
source_vulkan_header="$source_vulkan_headers/vulkan.h"
source_vulkan_core="$source_vulkan_headers/vulkan_core.h"
[[ -f "$source_vulkan_header" && -f "$source_vulkan_core" ]] ||
    die "NDK Vulkan headers are missing"
vulkan_header_version="$(
    sed -n 's/^#define VK_HEADER_VERSION \([0-9][0-9]*\)$/\1/p' \
        "$source_vulkan_core"
)"
[[ "$vulkan_header_version" == "$EXPECTED_VULKAN_HEADER_VERSION" ]] ||
    die "expected Vulkan header 1.3.$EXPECTED_VULKAN_HEADER_VERSION, found patch ${vulkan_header_version:-unknown}"
grep -Eq \
    '^#define VK_HEADER_VERSION_COMPLETE VK_MAKE_API_VERSION\(0, 1, 3, VK_HEADER_VERSION\)$' \
    "$source_vulkan_core" ||
    die "NDK Vulkan header does not declare the expected 1.3 version"
vulkan_header_sha256="$(sha256_file "$source_vulkan_header")"
vulkan_core_sha256="$(sha256_file "$source_vulkan_core")"

source_kib="$(du -sk "$prebuilt" | awk '{print $1}')"
available_kib="$(df -Pk "$output_parent" | awk 'NR == 2 {print $4}')"
required_kib=$((source_kib + source_kib / 4))
if [[ "$archive_requested" == true ]]; then
    required_kib=$((source_kib * 2 + source_kib / 2))
fi
(( available_kib >= required_kib )) ||
    die "insufficient disk space: need about $((required_kib / 1024 / 1024 + 1)) GiB"

create_staging 0755
mkdir -p "$staging_dir/toolchain"
printf 'Copying NDK toolchain into %s...\n' "$staging_dir"
rsync -a "$prebuilt/" "$staging_dir/toolchain/"

artifact_vulkan_headers="$staging_dir/toolchain/sysroot/usr/include/vulkan"
diff -qr "$source_vulkan_headers" "$artifact_vulkan_headers" >/dev/null ||
    die "copied Vulkan headers differ from NDK $EXPECTED_NDK_REVISION"

mkdir -p "$staging_dir/konan-sysroot/android-$API_LEVEL"
for row in "${target_rows[@]}"; do
    IFS='|' read -r konan_target architecture lib_triple clang_target <<<"$row"
    ln -s "../../toolchain/sysroot" \
        "$staging_dir/konan-sysroot/android-$API_LEVEL/arch-$architecture"
done

shim_source="$project_root/toolchains/android/compat/android-arm32-legacy-sync.c"
[[ -f "$shim_source" ]] || die "missing ARM32 compatibility source: $shim_source"
mkdir -p "$staging_dir/compat"
shim_object="$staging_dir/compat/android-arm32-legacy-sync.o"
without_include_path_env \
    "$staging_dir/toolchain/bin/armv7a-linux-androideabi21-clang" \
    -std=c11 \
    -O2 \
    -fPIC \
    -ffreestanding \
    -Wall \
    -Wextra \
    -Werror \
    -c "$shim_source" \
    -o "$shim_object"
"$staging_dir/toolchain/bin/llvm-ar" rcs \
    "$staging_dir/compat/liblegacy-sync-arm32.a" \
    "$shim_object"
rm -f -- "$shim_object"

required_sync_symbols=(
    "__sync_synchronize"
    "__sync_val_compare_and_swap_1"
    "__sync_val_compare_and_swap_4"
    "__sync_val_compare_and_swap_8"
    "__sync_lock_test_and_set_1"
    "__sync_lock_test_and_set_4"
    "__sync_lock_test_and_set_8"
    "__sync_fetch_and_or_2"
)
shim_symbols="$(
    "$staging_dir/toolchain/bin/llvm-nm" \
        --defined-only "$staging_dir/compat/liblegacy-sync-arm32.a"
)"
for symbol in "${required_sync_symbols[@]}"; do
    grep -Eq "[[:space:]]${symbol}$" <<<"$shim_symbols" ||
        die "ARM32 compatibility archive is missing $symbol"
done

manifest="$staging_dir/manifest.properties"
write_manifest_header \
    "$platform_descriptor" \
    "$package_name" \
    "$artifact_identity" \
    "$NATIVE_TOOLCHAIN_HOST_OS" \
    "$NATIVE_TOOLCHAIN_HOST_ARCH" \
    "$NATIVE_TOOLCHAIN_KONAN_HOST" \
    "$HOST_TAG" \
    >"$manifest"
cat >>"$manifest" <<EOF
ndk.revision=$actual_revision
clang.major=$clang_major
clang.version=$clang_version
api.level=$API_LEVEL
vulkan.header.version=1.3.$vulkan_header_version
vulkan.header.sha256=$vulkan_header_sha256
vulkan.core.sha256=$vulkan_core_sha256
EOF

for row in "${target_rows[@]}"; do
    IFS='|' read -r konan_target architecture lib_triple clang_target <<<"$row"
    sysroot_link="$staging_dir/konan-sysroot/android-$API_LEVEL/arch-$architecture"
    [[ -L "$sysroot_link" ]] || die "sysroot link was not created for $konan_target"
    [[ "$(readlink "$sysroot_link")" == "../../toolchain/sysroot" ]] ||
        die "sysroot link is not relocatable for $konan_target"
    [[ -x "$staging_dir/toolchain/bin/$clang_target-clang" ]] ||
        die "copied compiler is not executable for $konan_target"
done

normalize_tree_metadata "$staging_dir"

publish_output "Created Android toolchain"
publish_archive
