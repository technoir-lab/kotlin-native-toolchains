#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
builder_root="$project_root/toolchains/linux/builder"
image_root="$builder_root/image"
source_lock="$image_root/sources.lock"
graphics_header_list="$image_root/graphics-headers.txt"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/linux-builder-contract.XXXXXX")"
trap 'command rm -rf -- "$test_root"' EXIT

# shellcheck source=lib/assertions.sh
# shellcheck disable=SC1091
source "$test_dir/lib/assertions.sh"
# shellcheck source=../../toolchains/linux/builder/image/sources.sh
# shellcheck disable=SC1091
source "$image_root/sources.sh"

zlib_version="$(source_version "$source_lock" zlib)"
for config in \
    "$builder_root/configs/linux-x64.config" \
    "$builder_root/configs/linux-arm64.config"; do
    for line in \
        '# CT_PREFIX_DIR_RO is not set' \
        'CT_KERNEL_LINUX=y' \
        'CT_LINUX_V_5_15=y' \
        'CT_BINUTILS_V_2_29=y' \
        'CT_LIBC_GLIBC=y' \
        'CT_GLIBC_V_2_25=y' \
        'CT_GLIBC_EXTRA_CONFIG_ARRAY="MAKEINFO=:"' \
        'CT_GLIBC_KERNEL_VERSION_AS_HEADERS=y' \
        'CT_CC_GCC=y' \
        'CT_GCC_V_13=y' \
        'CT_CC_LANG_CXX=y' \
        'CT_CC_GCC_STATIC_LIBSTDCXX=y'; do
        assert_file_contains_line "$config" "$line"
    done
    # crosstool-NG's companion zlib must match the pinned target zlib.
    assert_file_contains_line "$config" "CT_ZLIB_V_${zlib_version//./_}=y"
done

assert_file_contains_line "$builder_root/configs/linux-x64.config" 'CT_ARCH_X86=y'
assert_file_contains_line "$builder_root/configs/linux-arm64.config" 'CT_ARCH_ARM=y'
assert_file_contains_line "$builder_root/configs/linux-arm64.config" 'CT_TARGET_VENDOR=""'

for version in \
    'GCC_VERSION|13.4.0' \
    'GLIBC_VERSION|2.25' \
    'LINUX_VERSION|5.15.209' \
    'BINUTILS_VERSION|2.29.1' \
    'CROSSTOOL_NG_VERSION|1.29.0'; do
    IFS='|' read -r key expected <<<"$version"
    assert_shell_constant "$builder_root/build-toolchains.sh" "$key" "$expected"
done

# The builder reads these sources by name: build-toolchains.sh builds zlib, and
# image/prepare.sh builds the header bundle from the rest.
lock_names="$(
    source_lock_entries "$source_lock" | awk '{ printf "%s ", $1 }'
)"
expected_lock_names="zlib xorgproto xtrans xcb-proto libxcb libx11 libxext wayland"
expected_lock_names+=" libxkbcommon vulkan-header"
expected_lock_names+=" alsa-lib pulseaudio pipewire jack2 sndio "
assert_equals \
    "$expected_lock_names" \
    "$lock_names" \
    "the Linux source lock does not declare the bundled sources"

fake_sha512="$(printf '%0128d' 0)"
lock_fixture="$test_root/sources.lock"

assert_lock_rejected() {
    local message="$1"
    shift

    printf '%s\n' "$@" >"$lock_fixture"
    if source_lock_entries "$lock_fixture" \
        >"$test_root/lock.out" 2>"$test_root/lock.error"; then
        fail "a source lock was accepted despite: $message"
    fi
    assert_file_contains "$test_root/lock.error" "$message"
    [[ ! -s "$test_root/lock.out" ]] ||
        fail "a rejected source lock printed entries"
}

valid_url='https://example.test/alpha-{version}.tar.gz'
assert_lock_rejected \
    'expected name, version, licenses, url, and sha512' \
    "alpha 1.0 COPYING $valid_url"
assert_lock_rejected \
    'expected name, version, licenses, url, and sha512' \
    "alpha 1.0 COPYING $valid_url $fake_sha512 extra"
assert_lock_rejected \
    'invalid source name: Alpha' \
    "Alpha 1.0 COPYING $valid_url $fake_sha512"
assert_lock_rejected \
    ':2: duplicate source: alpha' \
    "alpha 1.0 COPYING $valid_url $fake_sha512" \
    "alpha 2.0 COPYING $valid_url $fake_sha512"
assert_lock_rejected \
    'invalid alpha version: -1' \
    "alpha -1 COPYING $valid_url $fake_sha512"
assert_lock_rejected \
    'empty alpha license pattern' \
    "alpha 1.0 COPYING, $valid_url $fake_sha512"
assert_lock_rejected \
    'invalid alpha license pattern: /COPYING' \
    "alpha 1.0 /COPYING $valid_url $fake_sha512"
assert_lock_rejected \
    'invalid alpha license pattern: docs/../COPYING' \
    "alpha 1.0 docs/../COPYING $valid_url $fake_sha512"
assert_lock_rejected \
    'the alpha URL must use https and contain {version}' \
    "alpha 1.0 COPYING http://example.test/alpha-{version}.tar.gz $fake_sha512"
assert_lock_rejected \
    'the alpha URL must use https and contain {version}' \
    "alpha 1.0 COPYING https://example.test/alpha-1.0.tar.gz $fake_sha512"
assert_lock_rejected \
    'invalid alpha SHA-512 digest' \
    "alpha 1.0 COPYING $valid_url ${fake_sha512%0}"

printf '%s\n' \
    '# Fixture lock.' \
    '' \
    "alpha-beta 1.2 COPYING,LICENSES/*.txt https://example.test/{version}/alpha-{version}.tar.gz $fake_sha512" \
    "gamma 3 LICENSE https://example.test/gamma-{version}.tgz $fake_sha512" \
    >"$lock_fixture"
assert_equals \
    "alpha-beta 1.2 COPYING,LICENSES/*.txt https://example.test/1.2/alpha-1.2.tar.gz $fake_sha512"$'\n'"gamma 3 LICENSE https://example.test/gamma-3.tgz $fake_sha512" \
    "$(source_lock_entries "$lock_fixture")" \
    "source lock entries were not expanded"
assert_equals \
    $'alpha.beta.version=1.2\ngamma.version=3' \
    "$(source_version_properties "$lock_fixture")" \
    "source versions were not recorded under their metadata keys"
assert_equals 3 "$(source_version "$lock_fixture" gamma)" \
    "a source version was not found"
if source_version "$lock_fixture" delta >/dev/null 2>"$test_root/version.error"; then
    fail "an undeclared source version was reported"
fi
assert_file_contains "$test_root/version.error" 'does not declare delta'

# License files are copied with their source-relative paths, and every
# pattern must match a non-empty regular file.
fixture_sources="$test_root/sources"
licenses="$test_root/licenses"
mkdir -p "$fixture_sources/alpha-beta/LICENSES" "$fixture_sources/gamma"
printf 'alpha\n' >"$fixture_sources/alpha-beta/COPYING"
printf 'apache\n' >"$fixture_sources/alpha-beta/LICENSES/Apache-2.0.txt"
printf 'mit\n' >"$fixture_sources/alpha-beta/LICENSES/MIT.txt"
printf 'gamma\n' >"$fixture_sources/gamma/LICENSE"
collect_source_licenses "$lock_fixture" "$fixture_sources" "$licenses"
for license in \
    alpha-beta/COPYING \
    alpha-beta/LICENSES/Apache-2.0.txt \
    alpha-beta/LICENSES/MIT.txt \
    gamma/LICENSE; do
    assert_path_exists "$licenses/$license"
done
require_source_licenses "$lock_fixture" "$licenses" "the fixture toolchain"

assert_licenses_rejected() {
    local message="$1"

    if require_source_licenses \
        "$lock_fixture" "$licenses" "the fixture toolchain" \
        2>"$test_root/licenses.error"; then
        fail "incomplete licenses were accepted: $message"
    fi
    assert_file_contains "$test_root/licenses.error" "$message"
}

: >"$licenses/gamma/LICENSE"
assert_licenses_rejected \
    'the fixture toolchain has no gamma license file matching LICENSE'
command rm -f -- "$licenses/gamma/LICENSE"
assert_licenses_rejected \
    'the fixture toolchain has no gamma license file matching LICENSE'
printf 'gamma\n' >"$licenses/gamma/LICENSE"
command rm -f -- "$licenses/alpha-beta/LICENSES/"*.txt
assert_licenses_rejected \
    'the fixture toolchain has no alpha-beta license file matching LICENSES/*.txt'

command rm -f -- "$fixture_sources/gamma/LICENSE"
if collect_source_licenses \
    "$lock_fixture" "$fixture_sources" "$test_root/licenses-without-gamma" \
    2>"$test_root/collect.error"; then
    fail "a source without its declared license file was accepted"
fi
assert_file_contains "$test_root/collect.error" \
    'gamma has no license file matching LICENSE'

list_fixture="$test_root/headers.txt"
for entry in '/X11/X.h' 'X11/../X.h' 'X11/X.h '; do
    printf '%s\n' "$entry" >"$list_fixture"
    if list_file_entries "$list_fixture" >/dev/null 2>"$test_root/list.error"; then
        fail "an invalid header list entry was accepted: '$entry'"
    fi
    assert_file_contains "$test_root/list.error" 'invalid path'
done

# The image preparation script checks the bundle it builds.
# shellcheck source=../../toolchains/linux/builder/image/prepare.sh
# shellcheck disable=SC1091
source "$image_root/prepare.sh"

graphics_headers="$(list_file_entries "$graphics_header_list")"
[[ -n "$graphics_headers" ]] || fail "the graphics header list is empty"
graphics_build="$test_root/graphics-build"
graphics_bundle="$graphics_build/prefix/include"
while IFS= read -r header; do
    mkdir -p "$(dirname "$graphics_bundle/$header")"
    printf '/* %s */\n' "$header" >"$graphics_bundle/$header"
done <<<"$graphics_headers"
(verify_graphics_header_bundle \
    "$graphics_bundle" "$graphics_header_list" "$graphics_build") ||
    fail "a complete graphics header bundle was rejected"

assert_bundle_rejected() {
    local message="$1"

    if (verify_graphics_header_bundle \
        "$graphics_bundle" "$graphics_header_list" "$graphics_build") \
        2>"$test_root/bundle.error"; then
        fail "an invalid graphics header bundle was accepted: $message"
    fi
    assert_file_contains "$test_root/bundle.error" "$message"
}

cp "$graphics_bundle/wayland-version.h" "$test_root/wayland-version.h"
printf '#define DATADIR "%s/prefix/share"\n' "$graphics_build" \
    >>"$graphics_bundle/wayland-version.h"
assert_bundle_rejected \
    "graphics headers refer to their build directory: $graphics_bundle/wayland-version.h"
cp "$test_root/wayland-version.h" "$graphics_bundle/wayland-version.h"
command mv "$graphics_bundle/X11/XlibConf.h" "$test_root/XlibConf.h"
assert_bundle_rejected 'the graphics header bundle is missing X11/XlibConf.h'
command mv "$test_root/XlibConf.h" "$graphics_bundle/X11/XlibConf.h"

# Source the guarded builder to exercise its sysroot installation and
# case-fold compatibility behavior without invoking crosstool-NG.
ARTIFACT_FILESYSTEM_CASE_SENSITIVE=false
# shellcheck source=../../toolchains/linux/builder/build-toolchains.sh
# shellcheck disable=SC1091
source "$builder_root/build-toolchains.sh"
# shellcheck disable=SC2153 # ZLIB_VERSION is assigned by the sourced builder.
assert_equals "$zlib_version" "$ZLIB_VERSION" \
    "the container build does not read zlib from the source lock"

sysroot_include="$test_root/sysroot/usr/include"
mkdir -p "$sysroot_include/linux/netfilter"
: >"$sysroot_include/features.h"
: >"$sysroot_include/linux/netfilter/xt_MARK.h"
: >"$sysroot_include/linux/netfilter/xt_mark.h"
install_linux_graphics_headers "$graphics_bundle" "$sysroot_include"
require_listed_files \
    "$sysroot_include" "$graphics_header_list" "the fixture sysroot"
assert_path_exists "$sysroot_include/features.h"

assert_install_rejected() {
    local existing="$1"
    local collision="$2"
    local include_root

    include_root="$(mktemp -d "$test_root/colliding-include.XXXXXX")"
    mkdir -p "$(dirname "$include_root/$existing")"
    : >"$include_root/$existing"
    if (install_linux_graphics_headers "$graphics_bundle" "$include_root") \
        2>"$test_root/install.error"; then
        fail "graphics headers replaced $existing"
    fi
    assert_file_contains "$test_root/install.error" \
        "graphics headers collide with other sysroot headers: $collision"
    assert_path_missing "$include_root/vulkan/vulkan.h" \
        "a rejected graphics header installation copied headers"
}

assert_install_rejected X11/Xlib.h x11/xlib.h
assert_install_rejected x11/XLIB.H x11/xlib.h
if filesystem_preserves_case_distinct_names "$test_root"; then
    : >"$graphics_bundle/X11/xlib.h"
    assert_install_rejected features.h x11/xlib.h
    command rm -f -- "$graphics_bundle/X11/xlib.h"
fi

target="x86_64-unknown-linux-gnu"
toolchain_root="$test_root/toolchain"
include_root="$toolchain_root/$target/sysroot/usr/include"
header_pairs=(
    "linux/netfilter/xt_CONNMARK.h|linux/netfilter/xt_connmark.h"
    "linux/netfilter/xt_DSCP.h|linux/netfilter/xt_dscp.h"
    "linux/netfilter/xt_MARK.h|linux/netfilter/xt_mark.h"
    "linux/netfilter/xt_RATEEST.h|linux/netfilter/xt_rateest.h"
    "linux/netfilter/xt_TCPMSS.h|linux/netfilter/xt_tcpmss.h"
    "linux/netfilter_ipv4/ipt_ECN.h|linux/netfilter_ipv4/ipt_ecn.h"
    "linux/netfilter_ipv4/ipt_TTL.h|linux/netfilter_ipv4/ipt_ttl.h"
    "linux/netfilter_ipv6/ip6t_HL.h|linux/netfilter_ipv6/ip6t_hl.h"
)

create_header_pairs() {
    local pair
    local alias
    local canonical

    for pair in "${header_pairs[@]}"; do
        IFS='|' read -r alias canonical <<<"$pair"
        mkdir -p \
            "$(dirname "$include_root/$alias")" \
            "$(dirname "$include_root/$canonical")"
        : >"$include_root/$alias"
        : >"$include_root/$canonical"
    done
}

create_header_pairs
removal_log="$test_root/removals.log"
# Invoked indirectly by prepare_casefold_header_aliases from the sourced builder.
# shellcheck disable=SC2329
rm() {
    local argument

    for argument in "$@"; do
        if [[ "$argument" != -* && "$argument" != "--" ]]; then
            printf '%s\n' "$argument" >>"$removal_log"
        fi
    done
}

ARTIFACT_FILESYSTEM_CASE_SENSITIVE=false
prepare_casefold_header_aliases "$target" "$toolchain_root"
for pair in "${header_pairs[@]}"; do
    IFS='|' read -r alias _ <<<"$pair"
    assert_file_contains_line "$removal_log" "$include_root/$alias"
done
assert_equals "${#header_pairs[@]}" "$(wc -l <"$removal_log" | tr -d ' ')" \
    "case-insensitive artifacts did not prune every conflicting alias"

: >"$removal_log"
# Consumed by prepare_casefold_header_aliases from the sourced builder.
# shellcheck disable=SC2034
ARTIFACT_FILESYSTEM_CASE_SENSITIVE=true
prepare_casefold_header_aliases "$target" "$toolchain_root"
[[ ! -s "$removal_log" ]] ||
    fail "case-sensitive artifacts did not preserve header aliases"
unset -f rm

# The strip removes exactly these paths from a crosstool-NG prefix and keeps
# the files Kotlin/Native compiles and links with.
strip_target="x86_64-unknown-linux-gnu"
strip_gcc_lib="lib/gcc/$strip_target/13.4.0"
removed_paths=(
    bin
    build.log.bz2
    include
    lib/ldscripts
    "$strip_gcc_lib/include"
    "$strip_gcc_lib/include-fixed"
    "$strip_gcc_lib/install-tools"
    "$strip_gcc_lib/libgcov.a"
    libexec
    share/gcc-13.4.0
    "$strip_target/bin"
    "$strip_target/debug-root"
    "$strip_target/lib64/libstdc++.so.6.0.32-gdb.py"
    "$strip_target/sysroot/lib/libstdc++.so.6.0.32-gdb.py"
)
kept_paths=(
    "$strip_gcc_lib/crtbegin.o"
    "$strip_gcc_lib/crtbeginS.o"
    "$strip_gcc_lib/crtend.o"
    "$strip_gcc_lib/crtendS.o"
    "$strip_gcc_lib/libgcc.a"
    "$strip_gcc_lib/libgcc_eh.a"
    share/licenses/gcc/COPYING
    "share/$strip_target-ct-ng.config.bz2"
    "$strip_target/include/c++/13.4.0/string"
    "$strip_target/lib"
    "$strip_target/lib64/libgcc_s.so.1"
    "$strip_target/lib64/libstdc++.a"
    "$strip_target/sysroot/lib/libgcc_s.so.1"
    "$strip_target/sysroot/lib/libstdc++.a"
    "$strip_target/sysroot/usr/include/stdio.h"
)

# Creates the crosstool-NG prefix layout, including the sysroot's lib64 link
# and the GCC runtime links that point through it.
create_crosstool_prefix() {
    local root="$1"
    local file
    local library

    for file in \
        "bin/$strip_target-gcc" \
        build.log.bz2 \
        lib/ldscripts/elf_x86_64.x \
        "$strip_gcc_lib/include/stddef.h" \
        "$strip_gcc_lib/include-fixed/limits.h" \
        "$strip_gcc_lib/install-tools/mkheaders.conf" \
        "$strip_gcc_lib/libgcov.a" \
        "$strip_gcc_lib/crtbegin.o" \
        "$strip_gcc_lib/crtbeginS.o" \
        "$strip_gcc_lib/crtend.o" \
        "$strip_gcc_lib/crtendS.o" \
        "$strip_gcc_lib/libgcc.a" \
        "$strip_gcc_lib/libgcc_eh.a" \
        "libexec/gcc/$strip_target/13.4.0/cc1" \
        share/gcc-13.4.0/python/libstdcxx/__init__.py \
        share/licenses/gcc/COPYING \
        "share/$strip_target-ct-ng.config.bz2" \
        "$strip_target/bin/ld" \
        "$strip_target/include/c++/13.4.0/string" \
        "$strip_target/sysroot/lib/libgcc_s.so.1" \
        "$strip_target/sysroot/lib/libstdc++.a" \
        "$strip_target/sysroot/lib/libstdc++.so.6.0.32-gdb.py" \
        "$strip_target/sysroot/usr/include/stdio.h"; do
        mkdir -p "$(dirname "$root/$file")"
        : >"$root/$file"
    done
    mkdir -p \
        "$root/include" \
        "$root/$strip_target/debug-root" \
        "$root/$strip_target/lib" \
        "$root/$strip_target/lib64"
    ln -s lib "$root/$strip_target/sysroot/lib64"
    for library in libgcc_s.so.1 libstdc++.a libstdc++.so.6.0.32-gdb.py; do
        ln -s "../../$strip_target/sysroot/lib64/$library" \
            "$root/$strip_target/lib64/$library"
    done
}

strip_prefix="$test_root/strip/complete"
create_crosstool_prefix "$strip_prefix"
(strip_unused_toolchain_files "$strip_target" "$strip_prefix") ||
    fail "the strip rejected a complete crosstool-NG prefix"
for path in "${removed_paths[@]}"; do
    assert_path_missing "$strip_prefix/$path" "the strip kept $path"
done
for path in "${kept_paths[@]}"; do
    [[ -e "$strip_prefix/$path" ]] || fail "the strip removed $path"
done

# A listed path that crosstool-NG no longer installs fails the build, so the
# list follows the pinned layout.
strip_prefix="$test_root/strip/drifted"
create_crosstool_prefix "$strip_prefix"
command rm -rf -- "$strip_prefix/lib/ldscripts"
if (strip_unused_toolchain_files "$strip_target" "$strip_prefix") \
    2>"$test_root/strip-drifted.error"; then
    fail "the strip accepted a prefix without lib/ldscripts"
fi
assert_file_contains "$test_root/strip-drifted.error" \
    "the $strip_target toolchain has no lib/ldscripts to remove"

strip_prefix="$test_root/strip/incomplete"
create_crosstool_prefix "$strip_prefix"
command rm -f -- "$strip_prefix/$strip_gcc_lib/crtbegin.o"
if (strip_unused_toolchain_files "$strip_target" "$strip_prefix") \
    2>"$test_root/strip-incomplete.error"; then
    fail "the strip accepted a prefix without crtbegin.o"
fi
assert_file_contains "$test_root/strip-incomplete.error" \
    "the $strip_target toolchain is missing $strip_gcc_lib/crtbegin.o"

printf 'Linux source-builder contract tests passed.\n'
