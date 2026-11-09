#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
umask 022

readonly GCC_VERSION="13.4.0"
readonly GLIBC_VERSION="2.25"
readonly LINUX_VERSION="5.15.209"
readonly BINUTILS_VERSION="2.29.1"
readonly CROSSTOOL_NG_VERSION="1.29.0"
BUILDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly BUILDER_ROOT
readonly ARTIFACT_ROOT="/artifacts"
readonly SOURCE_LOCK="$BUILDER_ROOT/image/sources.lock"
# Written by image/prepare.sh while the builder image is built.
readonly SOURCES_ROOT="$BUILDER_ROOT/sources"
readonly LICENSES_ROOT="$BUILDER_ROOT/licenses"
readonly GRAPHICS_HEADERS_ROOT="$BUILDER_ROOT/graphics-headers"

# shellcheck source=image/sources.sh
# shellcheck disable=SC1091
source "$BUILDER_ROOT/image/sources.sh"
ZLIB_VERSION="$(source_version "$SOURCE_LOCK" zlib)"
readonly ZLIB_VERSION

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

# Builds zlib with the prefix it has on the target and stages it into the
# sysroot, so zlib.pc says prefix=/usr and pkg-config maps its paths into the
# sysroot through PKG_CONFIG_SYSROOT_DIR.
build_target_zlib() {
    local target="$1"
    local toolchain_root="$2"
    local sysroot="$toolchain_root/$target/sysroot"
    local zlib_build
    zlib_build="$(mktemp -d "/home/ct/zlib-${target}.XXXXXX")"
    cp -R --preserve=timestamps "$SOURCES_ROOT/zlib/." "$zlib_build/"
    (
        cd "$zlib_build"
        CHOST="$target" \
            CC="$toolchain_root/bin/$target-gcc" \
            AR="$toolchain_root/bin/$target-ar" \
            RANLIB="$toolchain_root/bin/$target-ranlib" \
            ./configure \
                --static \
                --prefix=/usr
        make -j"$(nproc)" libz.a
        make install-libs DESTDIR="$sysroot"
        install -m 0644 zlib.h zconf.h "$sysroot/usr/include/"
    )
    rm -rf -- "$zlib_build"
}

# Prints the files under root as relative, lowercase, sorted paths.
lowercase_file_paths() {
    local root="$1"

    (cd "$root" && find . ! -type d -print) |
        sed 's|^\./||' |
        LC_ALL=C tr '[:upper:]' '[:lower:]' |
        LC_ALL=C sort
}

# Prints, in lowercase, every file of new_root whose path ignoring case equals
# another file in new_root or a file already under existing_root.
case_insensitive_collisions() {
    local new_root="$1"
    local existing_root="$2"
    local new_paths
    local existing_paths

    new_paths="$(lowercase_file_paths "$new_root")" || return
    existing_paths="$(lowercase_file_paths "$existing_root")" || return
    [[ -n "$new_paths" ]] || return 0
    {
        printf '%s\n' "$new_paths" | LC_ALL=C uniq -d
        LC_ALL=C comm -12 \
            <(printf '%s\n' "$new_paths" | LC_ALL=C sort -u) \
            <(printf '%s\n' "$existing_paths")
    } | LC_ALL=C sort -u
}

# Merges the prebuilt graphics headers into a target sysroot. They must not
# replace an existing glibc, Linux UAPI, or zlib header, or collide with any
# header by case alone, because macOS artifact directories ignore case.
install_linux_graphics_headers() {
    local headers_root="$1"
    local include_root="$2"
    local collisions

    collisions="$(case_insensitive_collisions "$headers_root" "$include_root")" ||
        die "cannot compare the graphics headers with $include_root"
    [[ -z "$collisions" ]] ||
        die "graphics headers collide with other sysroot headers: ${collisions//$'\n'/, }"
    cp -R "$headers_root/." "$include_root/"
}

# Checks C source from stdin against a target sysroot with the target's GCC
# and the given options, failing on any warning.
check_target_c_source() {
    local target="$1"
    local toolchain_root="$2"
    shift 2

    "$toolchain_root/bin/$target-gcc" \
        --sysroot="$toolchain_root/$target/sysroot" \
        "$@" \
        -Werror \
        -fsyntax-only \
        -x c \
        -
}

verify_linux_graphics_headers() {
    local target="$1"
    local toolchain_root="$2"

    check_target_c_source "$target" "$toolchain_root" -std=c11 <<'EOF'
#define VK_USE_PLATFORM_WAYLAND_KHR
#define VK_USE_PLATFORM_XCB_KHR
#define VK_USE_PLATFORM_XLIB_KHR
#include <X11/Xlib.h>
#include <X11/Xlib-xcb.h>
#include <X11/extensions/Xext.h>
#include <X11/extensions/XShm.h>
#include <X11/extensions/Xdbe.h>
#include <X11/extensions/shape.h>
#include <X11/extensions/sync.h>
#include <xcb/xcb.h>
#include <xcb/randr.h>
#include <wayland-client.h>
#include <wayland-cursor.h>
#include <wayland-egl.h>
#include <wayland-server.h>
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-compose.h>
#include <xkbcommon/xkbcommon-x11.h>
#include <vulkan/vulkan.h>

int main(void) {
    return 0;
}
EOF
}

# Compiles the audio headers apart from X11, whose macros such as None and
# Status would clash with them. PipeWire's pkg-config files add its versioned
# include directories, and SPA's inline functions use the POSIX locale API,
# which glibc does not declare in strict ISO C mode.
verify_linux_audio_headers() {
    local target="$1"
    local toolchain_root="$2"
    local sysroot="$toolchain_root/$target/sysroot"

    check_target_c_source "$target" "$toolchain_root" \
        -isystem "$sysroot/usr/include/pipewire-0.3" \
        -isystem "$sysroot/usr/include/spa-0.2" \
        -std=gnu11 <<'EOF'
#include <alsa/asoundlib.h>
#include <jack/jack.h>
#include <jack/ringbuffer.h>
#include <pipewire/pipewire.h>
#include <pulse/pulseaudio.h>
#include <pulse/simple.h>
#include <sndio.h>
#include <spa/param/audio/format-utils.h>

int main(void) {
    return 0;
}
EOF
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

# Prints the paths, relative to a crosstool-NG prefix, that Kotlin/Native never
# uses. Its own LLVM compiles, links, and archives, so no GCC or binutils host
# program runs; Clang has its own headers and runtime; and LLD ignores GNU ld
# scripts. The libstdc++ GDB printers, their auto-load hooks, which embed build
# paths, and crosstool-NG's build log are left out too.
unused_toolchain_paths() {
    local target="$1"
    local gcc_lib="lib/gcc/$target/$GCC_VERSION"

    printf '%s\n' \
        bin \
        build.log.bz2 \
        include \
        lib/ldscripts \
        "$gcc_lib/include" \
        "$gcc_lib/include-fixed" \
        "$gcc_lib/install-tools" \
        "$gcc_lib/libgcov.a" \
        libexec \
        "share/gcc-$GCC_VERSION" \
        "$target/bin" \
        "$target/debug-root" \
        "$target/lib64/libstdc++.so.6.0.32-gdb.py" \
        "$target/sysroot/lib/libstdc++.so.6.0.32-gdb.py"
}

# Prints the Kotlin/Native inputs that share directories with unused paths.
retained_toolchain_paths() {
    local target="$1"
    local gcc_lib="lib/gcc/$target/$GCC_VERSION"

    printf '%s\n' \
        "$gcc_lib/crtbegin.o" \
        "$gcc_lib/crtend.o" \
        "$gcc_lib/libgcc.a" \
        "$gcc_lib/libgcc_eh.a" \
        share/licenses \
        "share/$target-ct-ng.config.bz2" \
        "$target/include/c++/$GCC_VERSION/string" \
        "$target/lib64/libstdc++.a" \
        "$target/sysroot/lib/libstdc++.a"
}

# Removes the unused paths from a toolchain prefix. Every listed path must
# exist, so a crosstool-NG layout change fails the build until the list is
# updated.
strip_unused_toolchain_files() {
    local target="$1"
    local toolchain_root="$2"
    local path

    while IFS= read -r path; do
        [[ -e "$toolchain_root/$path" || -L "$toolchain_root/$path" ]] ||
            die "the $target toolchain has no $path to remove"
        rm -rf -- "${toolchain_root:?}/$path"
    done < <(unused_toolchain_paths "$target")
    while IFS= read -r path; do
        [[ -e "$toolchain_root/$path" ]] ||
            die "the $target toolchain is missing $path"
    done < <(retained_toolchain_paths "$target")
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
    install_linux_graphics_headers \
        "$GRAPHICS_HEADERS_ROOT" \
        "$toolchain_root/$target/sysroot/usr/include"
    verify_linux_graphics_headers "$target" "$toolchain_root"
    verify_linux_audio_headers "$target" "$toolchain_root"
    # Add the pinned sources' licenses to those crosstool-NG installed. Its zlib
    # license is the same file, because the configs pin the same zlib version.
    mkdir -p "$toolchain_root/share/licenses"
    cp -Rf "$LICENSES_ROOT/." "$toolchain_root/share/licenses/"
    prepare_casefold_header_aliases "$target" "$toolchain_root"
    [[ -f "$toolchain_root/$target/sysroot/usr/lib/libz.a" ]] ||
        die "target zlib was not installed for $target"
    # The steps above run the toolchain's gcc, which this removes.
    strip_unused_toolchain_files "$target" "$toolchain_root"

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
    [[ -d "$SOURCES_ROOT/zlib" && -d "$LICENSES_ROOT" &&
        -d "$GRAPHICS_HEADERS_ROOT" ]] ||
        die "the builder image was not prepared by image/prepare.sh"

    mkdir "$ARTIFACT_ROOT/targets"
    if filesystem_preserves_case_distinct_names "$ARTIFACT_ROOT"; then
        ARTIFACT_FILESYSTEM_CASE_SENSITIVE=true
    else
        ARTIFACT_FILESYSTEM_CASE_SENSITIVE=false
    fi
    readonly ARTIFACT_FILESYSTEM_CASE_SENSITIVE
    build_target linux_x64 x86_64-unknown-linux-gnu linux-x64.config
    build_target linux_arm64 aarch64-unknown-linux-gnu linux-arm64.config

    {
        cat <<EOF
builder.container.os=ubuntu
builder.container.version=24.04
builder.container.arch=$BUILDER_ARCH
crosstool.ng.version=$CROSSTOOL_NG_VERSION
gcc.version=$GCC_VERSION
glibc.version=$GLIBC_VERSION
linux.headers.version=$LINUX_VERSION
binutils.version=$BINUTILS_VERSION
EOF
        source_version_properties "$SOURCE_LOCK"
    } >"$ARTIFACT_ROOT/builder.properties"

    printf 'Built Linux target toolchains in %s\n' "$ARTIFACT_ROOT/targets"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
