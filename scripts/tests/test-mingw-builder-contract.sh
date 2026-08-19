#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
builder_root="$project_root/toolchains/mingw/builder"
runner_root="$project_root/toolchains/mingw/runner"
config="$builder_root/configs/mingw-x64.config"

# shellcheck source=lib/assertions.sh
# shellcheck disable=SC1091
source "$test_dir/lib/assertions.sh"

for line in \
    'CT_EXPERIMENTAL=y' \
    '# CT_PREFIX_DIR_RO is not set' \
    'CT_ARCH_X86=y' \
    'CT_ARCH_64=y' \
    '# CT_MULTILIB is not set' \
    'CT_TARGET_VENDOR="w64"' \
    'CT_KERNEL_WINDOWS=y' \
    'CT_BINUTILS_V_2_40=y' \
    'CT_LIBC_MINGW_W64=y' \
    'CT_MINGW_W64_V_10_0_0=y' \
    'CT_MINGW_DEFAULT_MSVCRT_MSVCRT=y' \
    'CT_THREADS_POSIX=y' \
    'CT_CC_GCC=y' \
    'CT_GCC_V_13=y' \
    'CT_CC_LANG_CXX=y'; do
    assert_file_contains_line "$config" "$line"
done

assert_file_contains_line \
    "$runner_root/Dockerfile" \
    'FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90'
assert_file_contains_line "$runner_root/Dockerfile" "    && apt-get install --yes --no-install-recommends wine64 \\"

for version in \
    'GCC_VERSION|13.2.0' \
    'MINGW_W64_VERSION|10.0.0' \
    'BINUTILS_VERSION|2.40' \
    'ZLIB_VERSION|1.2.13' \
    'CROSSTOOL_NG_VERSION|1.26.0'; do
    IFS='|' read -r key expected <<<"$version"
    assert_shell_constant "$builder_root/build-toolchain.sh" "$key" "$expected"
done

printf 'MinGW source-builder contract tests passed.\n'
