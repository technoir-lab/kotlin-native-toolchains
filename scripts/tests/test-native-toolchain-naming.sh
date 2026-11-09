#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"

# shellcheck source=../lib/native-toolchain-registry.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-registry.sh"
# shellcheck source=lib/assertions.sh
# shellcheck disable=SC1091
source "$test_dir/lib/assertions.sh"

assert_name() {
    local descriptor="$1"
    local host="$2"
    local expected="$3"
    local actual
    actual="$(package_name_for "$descriptor" "$host")"
    assert_equals "$expected" "$actual" "package name did not match registry contract"
}

assert_name \
    "$project_root/toolchains/android/android.properties" \
    "macos_arm64" \
    "io.technoirlab-target-toolchain-1-macos_arm64-android_ndk_r29"
assert_name \
    "$project_root/toolchains/android/android.properties" \
    "linux_x64" \
    "io.technoirlab-target-toolchain-1-linux_x64-android_ndk_r29"
assert_name \
    "$project_root/toolchains/linux/linux.properties" \
    "macos_arm64" \
    "io.technoirlab-target-toolchain-1-macos_arm64-linux_gcc13_glibc2.25"
assert_name \
    "$project_root/toolchains/linux/linux.properties" \
    "linux_x64" \
    "io.technoirlab-target-toolchain-1-linux_x64-linux_gcc13_glibc2.25"
assert_name \
    "$project_root/toolchains/mingw/mingw.properties" \
    "macos_arm64" \
    "io.technoirlab-target-toolchain-1-macos_arm64-mingw_gcc13_mingw-w64_14_msvcrt"
assert_name \
    "$project_root/toolchains/mingw/mingw.properties" \
    "linux_x64" \
    "io.technoirlab-target-toolchain-1-linux_x64-mingw_gcc13_mingw-w64_14_msvcrt"

for descriptor in "$project_root"/toolchains/*/*.properties; do
    for entrypoint_key in builder.script verifier.script; do
        entrypoint="$(read_descriptor_property "$descriptor" "$entrypoint_key")"
        [[ -n "$entrypoint" && -x "$project_root/$entrypoint" ]] ||
            fail "$(basename "$descriptor") has no executable $entrypoint_key entry point"
    done
done

descriptor="$project_root/toolchains/android/android.properties"
identity="$(artifact_identity_for "$descriptor" "macos_arm64")"
expected_identity="io.technoirlab:target-toolchain:1:macos_arm64:android_ndk_r29"
assert_equals "$expected_identity" "$identity" \
    "Android identity did not match registry contract"

descriptor="$project_root/toolchains/mingw/mingw.properties"
identity="$(artifact_identity_for "$descriptor" "macos_arm64")"
expected_identity="io.technoirlab:target-toolchain:1:macos_arm64:mingw_gcc13_mingw-w64_14_msvcrt"
assert_equals "$expected_identity" "$identity" \
    "MinGW identity did not match registry contract"

descriptor="$project_root/toolchains/linux/linux.properties"
identity="$(artifact_identity_for "$descriptor" "linux_x64")"
expected_identity="io.technoirlab:target-toolchain:1:linux_x64:linux_gcc13_glibc2.25"
assert_equals "$expected_identity" "$identity" \
    "Linux identity did not match registry contract"

if package_name_for "$descriptor" "invalid host" >/dev/null 2>&1; then
    fail "invalid package host was accepted"
fi

descriptor="$project_root/toolchains/android/android.properties"
package_name="$(package_name_for "$descriptor" "macos_arm64")"
artifact_identity="$(artifact_identity_for "$descriptor" "macos_arm64")"
readonly package_name artifact_identity
actual_manifest_header="$(
    write_manifest_header \
        "$descriptor" \
        "$package_name" \
        "$artifact_identity" \
        "macos" \
        "arm64" \
        "macos_arm64" \
        "darwin-x86_64"
)"
expected_manifest_header="$(cat <<'EOF'
format.version=1
artifact.platform=android
artifact.layout.version=1
artifact.package.namespace=io.technoirlab
artifact.package.role=target-toolchain
artifact.package.revision=1
artifact.package.host=macos_arm64
artifact.package.target.family=android_ndk_r29
artifact.package.name=io.technoirlab-target-toolchain-1-macos_arm64-android_ndk_r29
artifact.identity=io.technoirlab:target-toolchain:1:macos_arm64:android_ndk_r29
host.os=macos
host.arch=arm64
host.konan=macos_arm64
host.tag=darwin-x86_64
konan.targets=android_arm32,android_arm64,android_x86,android_x64
EOF
)"
if [[ "$actual_manifest_header" != "$expected_manifest_header" ]]; then
    printf 'error: manifest header did not match the registry contract\n' >&2
    diff -u \
        <(printf '%s\n' "$expected_manifest_header") \
        <(printf '%s\n' "$actual_manifest_header") >&2 || true
    exit 1
fi

printf 'Native toolchain registry and naming tests passed.\n'
