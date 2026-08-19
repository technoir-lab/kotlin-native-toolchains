#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/native-toolchain-host.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

# shellcheck source=../lib/native-toolchain-host.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-host.sh"
# shellcheck source=../lib/native-toolchain-checksum.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-checksum.sh"
# shellcheck source=lib/assertions.sh
# shellcheck disable=SC1091
source "$test_dir/lib/assertions.sh"

assert_host() {
    local raw_os="$1"
    local raw_arch="$2"
    local expected_os="$3"
    local expected_arch="$4"
    local expected_konan="$5"

    detect_host "$raw_os" "$raw_arch"
    assert_equals "$expected_os" "$NATIVE_TOOLCHAIN_HOST_OS" \
        "$raw_os/$raw_arch normalized to the wrong OS"
    assert_equals "$expected_arch" "$NATIVE_TOOLCHAIN_HOST_ARCH" \
        "$raw_os/$raw_arch normalized to the wrong architecture"
    assert_equals "$expected_konan" "$NATIVE_TOOLCHAIN_KONAN_HOST" \
        "$raw_os/$raw_arch normalized to the wrong Kotlin/Native host"
}

assert_host Darwin arm64 macos arm64 macos_arm64
assert_host Darwin x86_64 macos x64 unsupported
assert_host Linux x86_64 linux x64 linux_x64
assert_host Linux aarch64 linux arm64 unsupported
assert_host MINGW64_NT-10.0 AMD64 unknown x64 unsupported

for descriptor in "$project_root"/toolchains/*/*.properties; do
    if grep -q '^host\.' "$descriptor"; then
        fail "platform descriptor contains host gates: $descriptor"
    fi
done

printf 'abc' >"$test_root/checksum-input"
expected_checksum="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
actual_checksum="$(sha256_file "$test_root/checksum-input")"
assert_equals "$expected_checksum" "$actual_checksum" "SHA-256 did not match"

printf 'Native toolchain host and portability tests passed.\n'
