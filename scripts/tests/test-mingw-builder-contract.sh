#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
builder_root="$project_root/toolchains/mingw/builder"
runner_root="$project_root/toolchains/mingw/runner"
config="$builder_root/configs/mingw-x64.config"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mingw-builder-contract.XXXXXX")"
trap 'command rm -rf -- "$test_root"' EXIT

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
    'CT_MINGW_W64_V_V14_0=y' \
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
    'GCC_VERSION|13.4.0' \
    'MINGW_W64_VERSION|14.0.0' \
    'BINUTILS_VERSION|2.40' \
    'ZLIB_VERSION|1.2.13' \
    'CROSSTOOL_NG_VERSION|1.29.0'; do
    IFS='|' read -r key expected <<<"$version"
    assert_shell_constant "$builder_root/build-toolchain.sh" "$key" "$expected"
done

# Kotlin/Native's clang reaches the libstdc++ headers only through the
# konan-sysroot/include/c++ link.
for line in \
    "require_stripped_gcc_prefix \\" \
    "    \"\$toolchain\" \"\$TARGET_TRIPLE\" \"\$GCC_VERSION\" \"the MinGW toolchain\"" \
    "    \"../../toolchain/\$TARGET_TRIPLE/include/c++\" \\" \
    "    \"\$staging_dir/konan-sysroot/include/c++\""; do
    assert_file_contains_line "$script_dir/build-mingw-toolchain.sh" "$line"
done

# Source the guarded builder to exercise its strip without crosstool-NG.
# shellcheck source=../../toolchains/mingw/builder/build-toolchain.sh
# shellcheck disable=SC1091
source "$builder_root/build-toolchain.sh"

# The strip removes exactly these paths from the crosstool-NG prefix and keeps
# the files Kotlin/Native compiles and links with.
mingw_target="x86_64-w64-mingw32"
mingw_gcc_lib="lib/gcc/$mingw_target/13.4.0"
mingw_sysroot="$mingw_target/sysroot/usr/$mingw_target"
removed_paths=(
    bin
    build.log.bz2
    include
    lib/bfd-plugins
    "$mingw_gcc_lib/include"
    "$mingw_gcc_lib/include-fixed"
    "$mingw_gcc_lib/install-tools"
    "$mingw_gcc_lib/libgcov.a"
    libexec
    share/gcc-13.4.0
    toolchain.cmake
    "$mingw_target/bin"
    "$mingw_target/debug-root"
    "$mingw_target/lib/ldscripts"
    "$mingw_target/lib/libstdc++.dll.a-gdb.py"
    "$mingw_target/sysroot/lib/libstdc++.dll.a-gdb.py"
    "$mingw_sysroot/lib32"
)
kept_paths=(
    "$mingw_gcc_lib/crtbegin.o"
    "$mingw_gcc_lib/crtend.o"
    "$mingw_gcc_lib/crtfastmath.o"
    "$mingw_gcc_lib/libgcc.a"
    "$mingw_gcc_lib/libgcc_eh.a"
    share/licenses/mingw-w64/COPYING
    "share/$mingw_target-ct-ng.config.bz2"
    "$mingw_target/include/c++/13.4.0/string"
    "$mingw_target/lib/libstdc++-6.dll"
    "$mingw_target/lib/libstdc++.a"
    "$mingw_target/sysroot/lib/libstdc++.a"
    "$mingw_target/sysroot/mingw"
    "$mingw_sysroot/include/windows.h"
    "$mingw_sysroot/lib/libmsvcrt.a"
)

# Creates the crosstool-NG prefix layout, including the GCC runtime links in
# the target directory.
create_crosstool_prefix() {
    local root="$1"
    local file
    local library

    for file in \
        "bin/$mingw_target-gcc" \
        build.log.bz2 \
        toolchain.cmake \
        lib/bfd-plugins/libdep.so \
        "$mingw_gcc_lib/include/stddef.h" \
        "$mingw_gcc_lib/include-fixed/limits.h" \
        "$mingw_gcc_lib/install-tools/mkheaders.conf" \
        "$mingw_gcc_lib/libgcov.a" \
        "$mingw_gcc_lib/crtbegin.o" \
        "$mingw_gcc_lib/crtend.o" \
        "$mingw_gcc_lib/crtfastmath.o" \
        "$mingw_gcc_lib/libgcc.a" \
        "$mingw_gcc_lib/libgcc_eh.a" \
        "libexec/gcc/$mingw_target/13.4.0/cc1" \
        share/gcc-13.4.0/python/libstdcxx/__init__.py \
        share/licenses/mingw-w64/COPYING \
        "share/$mingw_target-ct-ng.config.bz2" \
        "$mingw_target/bin/ld" \
        "$mingw_target/include/c++/13.4.0/string" \
        "$mingw_target/lib/ldscripts/i386pep.x" \
        "$mingw_target/sysroot/lib/libstdc++-6.dll" \
        "$mingw_target/sysroot/lib/libstdc++.a" \
        "$mingw_target/sysroot/lib/libstdc++.dll.a-gdb.py" \
        "$mingw_sysroot/include/windows.h" \
        "$mingw_sysroot/lib/libmsvcrt.a" \
        "$mingw_sysroot/lib32/libmsvcrt.a"; do
        mkdir -p "$(dirname "$root/$file")"
        : >"$root/$file"
    done
    mkdir -p "$root/include" "$root/$mingw_target/debug-root"
    for library in libstdc++-6.dll libstdc++.a libstdc++.dll.a-gdb.py; do
        ln -s "../../$mingw_target/sysroot/lib/$library" \
            "$root/$mingw_target/lib/$library"
    done
    ln -s "usr/$mingw_target" "$root/$mingw_target/sysroot/mingw"
}

strip_prefix="$test_root/complete"
create_crosstool_prefix "$strip_prefix"
(strip_unused_toolchain_files "$strip_prefix") ||
    fail "the strip rejected a complete crosstool-NG prefix"
for path in "${removed_paths[@]}"; do
    assert_path_missing "$strip_prefix/$path" "the strip kept $path"
done
for path in "${kept_paths[@]}"; do
    [[ -e "$strip_prefix/$path" ]] || fail "the strip removed $path"
done

# A listed path that crosstool-NG no longer installs fails the build, so the
# list follows the pinned layout.
strip_prefix="$test_root/drifted"
create_crosstool_prefix "$strip_prefix"
command rm -rf -- "${strip_prefix:?}/$mingw_sysroot/lib32"
if (strip_unused_toolchain_files "$strip_prefix") \
    2>"$test_root/strip-drifted.error"; then
    fail "the strip accepted a prefix without lib32"
fi
assert_file_contains "$test_root/strip-drifted.error" \
    "the $mingw_target toolchain has no $mingw_sysroot/lib32 to remove"

strip_prefix="$test_root/incomplete"
create_crosstool_prefix "$strip_prefix"
command rm -f -- "$strip_prefix/$mingw_target/include/c++/13.4.0/string"
if (strip_unused_toolchain_files "$strip_prefix") \
    2>"$test_root/strip-incomplete.error"; then
    fail "the strip accepted a prefix without the libstdc++ headers"
fi
assert_file_contains "$test_root/strip-incomplete.error" \
    "the $mingw_target toolchain is missing $mingw_target/include/c++/13.4.0/string"

printf 'MinGW source-builder contract tests passed.\n'
