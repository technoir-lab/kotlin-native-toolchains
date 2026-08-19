#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
builder_root="$project_root/toolchains/linux/builder"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/linux-builder-contract.XXXXXX")"
trap 'command rm -rf -- "$test_root"' EXIT

# shellcheck source=lib/assertions.sh
# shellcheck disable=SC1091
source "$test_dir/lib/assertions.sh"

for config in \
    "$builder_root/configs/linux-x64.config" \
    "$builder_root/configs/linux-arm64.config"; do
    for line in \
        '# CT_PREFIX_DIR_RO is not set' \
        'CT_KERNEL_LINUX=y' \
        'CT_LINUX_V_5_15=y' \
        'CT_BINUTILS_V_2_40=y' \
        'CT_LIBC_GLIBC=y' \
        'CT_GLIBC_V_2_35=y' \
        'CT_GLIBC_KERNEL_VERSION_AS_HEADERS=y' \
        'CT_CC_GCC=y' \
        'CT_GCC_V_13=y' \
        'CT_CC_LANG_CXX=y' \
        'CT_CC_GCC_STATIC_LIBSTDCXX=y' \
        'CT_ZLIB_V_1_2_13=y'; do
        assert_file_contains_line "$config" "$line"
    done
done

assert_file_contains_line "$builder_root/configs/linux-x64.config" 'CT_ARCH_X86=y'
assert_file_contains_line "$builder_root/configs/linux-arm64.config" 'CT_ARCH_ARM=y'
assert_file_contains_line "$builder_root/configs/linux-arm64.config" 'CT_TARGET_VENDOR=""'

for version in \
    'GCC_VERSION|13.2.0' \
    'GLIBC_VERSION|2.35' \
    'LINUX_VERSION|5.15.118' \
    'BINUTILS_VERSION|2.40' \
    'ZLIB_VERSION|1.2.13' \
    'CROSSTOOL_NG_VERSION|1.26.0'; do
    IFS='|' read -r key expected <<<"$version"
    assert_shell_constant "$builder_root/build-toolchains.sh" "$key" "$expected"
done

# Source the guarded builder to exercise its case-fold compatibility behavior
# without invoking crosstool-NG.
ARTIFACT_FILESYSTEM_CASE_SENSITIVE=false
# shellcheck source=../../toolchains/linux/builder/build-toolchains.sh
# shellcheck disable=SC1091
source "$builder_root/build-toolchains.sh"

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

printf 'Linux source-builder contract tests passed.\n'
