#!/usr/bin/env bash
set -euo pipefail
umask 022

readonly GCC_VERSION="13.2.0"
readonly GLIBC_VERSION="2.35"
readonly LINUX_VERSION="5.15.118"
readonly BINUTILS_VERSION="2.40"
readonly ZLIB_VERSION="1.2.13"
readonly CROSSTOOL_NG_VERSION="1.26.0"
readonly BUILDER_ROOT="/opt/toolchain-builder"
readonly ARTIFACT_ROOT="/artifacts"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

assert_config_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(sed -n "s/^${key}=//p" .config | head -n 1)"
    [[ "$actual" == "\"$expected\"" ]] ||
        die "crosstool-NG resolved $key=${actual:-unset}; expected \"$expected\""
}

build_target_zlib() {
    local target="$1"
    local toolchain_root="$2"
    local zlib_build
    zlib_build="$(mktemp -d "/home/ct/zlib-${target}.XXXXXX")"
    tar --extract --gzip --file /opt/zlib.tar.gz \
        --directory "$zlib_build" --strip-components=1
    (
        cd "$zlib_build"
        CHOST="$target" \
            CC="$toolchain_root/bin/$target-gcc" \
            AR="$toolchain_root/bin/$target-ar" \
            RANLIB="$toolchain_root/bin/$target-ranlib" \
            ./configure \
                --static \
                --prefix="$toolchain_root/$target/sysroot/usr"
        make -j"$(nproc)" libz.a
        make install-libs
        install -m 0644 zlib.h zconf.h \
            "$toolchain_root/$target/sysroot/usr/include/"
    )
    rm -rf -- "$zlib_build"
}

ensure_konan_layout() {
    local target="$1"
    local toolchain_root="$2"
    local sysroot="$toolchain_root/$target/sysroot"
    local static_cxx="$sysroot/lib/libstdc++.a"
    local candidate

    if [[ ! -f "$static_cxx" ]]; then
        for candidate in \
            "$toolchain_root/$target/lib/libstdc++.a" \
            "$toolchain_root/$target/lib64/libstdc++.a" \
            "$sysroot/usr/lib/libstdc++.a" \
            "$sysroot/usr/lib64/libstdc++.a"; do
            if [[ -f "$candidate" ]]; then
                mkdir -p "$sysroot/lib"
                cp -a "$candidate" "$static_cxx"
                break
            fi
        done
    fi
    [[ -f "$static_cxx" ]] ||
        die "cannot locate static libstdc++ for $target"
}

prepare_casefold_header_aliases() {
    local target="$1"
    local toolchain_root="$2"
    local include_root="$toolchain_root/$target/sysroot/usr/include"
    local pair
    local alias
    local canonical

    # The Linux UAPI installs compatibility aliases whose names differ from
    # their canonical headers only by case. A case-insensitive macOS bind mount
    # cannot represent both names, so keep the lowercase implementation there;
    # it remains reachable through either spelling on that filesystem.
    for pair in \
        "linux/netfilter/xt_CONNMARK.h|linux/netfilter/xt_connmark.h" \
        "linux/netfilter/xt_DSCP.h|linux/netfilter/xt_dscp.h" \
        "linux/netfilter/xt_MARK.h|linux/netfilter/xt_mark.h" \
        "linux/netfilter/xt_RATEEST.h|linux/netfilter/xt_rateest.h" \
        "linux/netfilter/xt_TCPMSS.h|linux/netfilter/xt_tcpmss.h" \
        "linux/netfilter_ipv4/ipt_ECN.h|linux/netfilter_ipv4/ipt_ecn.h" \
        "linux/netfilter_ipv4/ipt_TTL.h|linux/netfilter_ipv4/ipt_ttl.h" \
        "linux/netfilter_ipv6/ip6t_HL.h|linux/netfilter_ipv6/ip6t_hl.h"; do
        IFS='|' read -r alias canonical <<<"$pair"
        [[ -f "$include_root/$alias" && -f "$include_root/$canonical" ]] ||
            die "expected Linux case-folded header pair $alias and $canonical"
        if [[ "$ARTIFACT_FILESYSTEM_CASE_SENSITIVE" != true ]]; then
            rm -f -- "$include_root/$alias"
        fi
    done
}

filesystem_preserves_case_distinct_names() {
    local root="$1"
    local probe_dir
    local result=1

    probe_dir="$(mktemp -d "$root/.case-sensitivity.XXXXXX")"
    : >"$probe_dir/lowercase"
    if [[ ! -e "$probe_dir/LOWERCASE" ]]; then
        result=0
    fi
    rm -f -- "$probe_dir/lowercase"
    rmdir -- "$probe_dir"
    return "$result"
}

build_target() {
    local konan_target="$1"
    local target="$2"
    local config="$3"
    local build_root="/home/ct/build-$konan_target"
    local toolchain_root="/home/ct/x-tools/$target"
    local artifact_target="$ARTIFACT_ROOT/targets/$konan_target"

    printf 'Building %s (%s)...\n' "$konan_target" "$target"
    mkdir "$build_root"
    cp "$BUILDER_ROOT/configs/$config" "$build_root/.config"
    (
        cd "$build_root"
        ct-ng olddefconfig
        assert_config_value CT_GCC_VERSION "$GCC_VERSION"
        assert_config_value CT_GLIBC_VERSION "$GLIBC_VERSION"
        assert_config_value CT_LINUX_VERSION "$LINUX_VERSION"
        assert_config_value CT_BINUTILS_VERSION "$BINUTILS_VERSION"
        assert_config_value CT_ZLIB_VERSION "$ZLIB_VERSION"
        ct-ng build
    )

    [[ -x "$toolchain_root/bin/$target-gcc" ]] ||
        die "crosstool-NG did not produce $target-gcc"
    build_target_zlib "$target" "$toolchain_root"
    ensure_konan_layout "$target" "$toolchain_root"
    prepare_casefold_header_aliases "$target" "$toolchain_root"
    [[ -f "$toolchain_root/$target/sysroot/usr/lib/libz.a" ]] ||
        die "target zlib was not installed for $target"

    mkdir -p "$artifact_target"
    cp -a "$toolchain_root/." "$artifact_target/"
}

main() {
    [[ -d "$ARTIFACT_ROOT" && -w "$ARTIFACT_ROOT" ]] ||
        die "$ARTIFACT_ROOT must be a writable bind mount"
    [[ "${BUILDER_ARCH:-}" == "amd64" || "${BUILDER_ARCH:-}" == "arm64" ]] ||
        die "BUILDER_ARCH must be amd64 or arm64"
    [[ ! -e "$ARTIFACT_ROOT/targets" ]] ||
        die "$ARTIFACT_ROOT/targets already exists"

    mkdir "$ARTIFACT_ROOT/targets"
    if filesystem_preserves_case_distinct_names "$ARTIFACT_ROOT"; then
        ARTIFACT_FILESYSTEM_CASE_SENSITIVE=true
    else
        ARTIFACT_FILESYSTEM_CASE_SENSITIVE=false
    fi
    readonly ARTIFACT_FILESYSTEM_CASE_SENSITIVE
    build_target linux_x64 x86_64-unknown-linux-gnu linux-x64.config
    build_target linux_arm64 aarch64-unknown-linux-gnu linux-arm64.config

    cat >"$ARTIFACT_ROOT/builder.properties" <<EOF
builder.container.os=ubuntu
builder.container.version=24.04
builder.container.arch=$BUILDER_ARCH
crosstool.ng.version=$CROSSTOOL_NG_VERSION
gcc.version=$GCC_VERSION
glibc.version=$GLIBC_VERSION
linux.headers.version=$LINUX_VERSION
binutils.version=$BINUTILS_VERSION
zlib.version=$ZLIB_VERSION
EOF

    printf 'Built Linux target toolchains in %s\n' "$ARTIFACT_ROOT/targets"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
