#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Prepares the Linux builder image. The shared Dockerfile runs this as root in
# its prepare stage, so Docker reuses the result until a file in this
# directory changes. It:
#
# - downloads every source in sources.lock, checks its SHA-512 digest, and
#   extracts it to a temporary sources/<name> directory;
# - copies the declared license files to ../licenses/<name>;
# - builds the X11, xcb, Wayland, xkbcommon, Vulkan, and audio headers into
#   ../graphics-headers, which build-toolchains.sh merges into every target
#   sysroot; and
# - keeps only zlib's source, in ../sources/zlib, from which
#   build-toolchains.sh builds each target's zlib.
#
# The builder image receives only /opt/toolchain-builder from the stage, so the
# packages installed here to build the headers stay out of it, and the
# toolchain build runs with the same packages as the other platforms.
set -euo pipefail
umask 022

image_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=sources.sh
# shellcheck disable=SC1091
source "$image_dir/sources.sh"

graphics_build_packages=(
    libexpat1-dev
    libffi-dev
    libxau-dev
    meson
    ninja-build
    pkg-config
)

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

fetch_sources() {
    local lock="$1"
    local sources_root="$2"
    local entries
    local archive
    local name
    local version
    local url
    local sha512

    entries="$(source_lock_entries "$lock")" || exit 1
    archive="$(mktemp)"
    mkdir "$sources_root"
    while read -r name version _ url sha512 <&3; do
        [[ -n "$name" ]] || continue
        printf 'Fetching %s %s\n' "$name" "$version"
        curl --fail --location --retry 3 --silent --show-error \
            --output "$archive" "$url"
        printf '%s  %s\n' "$sha512" "$archive" |
            sha512sum --check --strict --quiet ||
            die "$name $version does not match its pinned SHA-512 digest"
        mkdir "$sources_root/$name"
        tar --extract --file "$archive" --directory "$sources_root/$name" \
            --strip-components=1 --no-same-owner
    done 3<<<"$entries"
    rm -f -- "$archive"
}

# Checks the installed headers before they are kept: every listed header must
# exist, and no header may refer to the directory it was built in.
verify_graphics_header_bundle() {
    local include_root="$1"
    local header_list="$2"
    local build_root="$3"
    local references
    local status=0

    require_listed_files \
        "$include_root" "$header_list" "the graphics header bundle" ||
        exit 1
    references="$(grep -rlF -- "$build_root" "$include_root")" || status=$?
    case "$status" in
        0) die "graphics headers refer to their build directory: ${references//$'\n'/, }" ;;
        1) ;;
        *) die "cannot scan the graphics headers for build paths" ;;
    esac
}

# Prints the quoted items of the meson array literal assigned to variable in
# a meson.build file, one per line.
meson_array_items() {
    local file="$1"
    local variable="$2"
    local items

    items="$(
        awk -v head="$variable = [" '
            index($0, head) == 1 { inside = 1; next }
            inside && /^\]/ { exit }
            inside { print }
        ' "$file" |
            sed -n "s/^[[:space:]]*'\([^']*\)',*[[:space:]]*\$/\1/p"
    )"
    [[ -n "$items" ]] || die "$file declares no $variable items"
    printf '%s\n' "$items"
}

# Installs the headers listed in the meson array literal assigned to variable,
# relative to the meson.build file, into destination by file name.
install_meson_headers() {
    local meson_build="$1"
    local variable="$2"
    local destination="$3"
    local headers
    local header

    headers="$(meson_array_items "$meson_build" "$variable")" || exit 1
    mkdir -p "$destination"
    while IFS= read -r header; do
        install -m 0644 "$(dirname "$meson_build")/$header" "$destination/"
    done <<<"$headers"
}

# Writes a meson configure_file() template with every @NAME@ replaced by the
# value of a NAME=VALUE argument, and fails if a placeholder remains.
configure_header() {
    local input="$1"
    local output="$2"
    local assignment
    local -a expressions=()

    shift 2
    for assignment in "$@"; do
        expressions+=(-e "s|@${assignment%%=*}@|${assignment#*=}|g")
    done
    mkdir -p "$(dirname "$output")"
    sed "${expressions[@]}" "$input" >"$output"
    if grep -Eq '@[A-Z][A-Z0-9_]*@' "$output"; then
        die "$output keeps an unreplaced placeholder"
    fi
}

# Installs the libpulse and libpulse-simple headers that PulseAudio's meson
# build lists, and generates version.h as its configure_file() does. Even a
# client-only meson configuration requires libsndfile and more.
install_pulseaudio_headers() {
    local source="$1"
    local version="$2"
    local include_root="$3"
    local major
    local minor
    local api_version
    local protocol_version

    IFS=. read -r major minor _ <<<"$version"
    api_version="$(sed -n 's/^pa_api_version = \([0-9][0-9]*\)$/\1/p' "$source/meson.build")"
    protocol_version="$(sed -n 's/^pa_protocol_version = \([0-9][0-9]*\)$/\1/p' "$source/meson.build")"
    [[ -n "$major" && -n "$minor" && -n "$api_version" && -n "$protocol_version" ]] ||
        die "cannot read the PulseAudio $version version numbers"
    install_meson_headers \
        "$source/src/pulse/meson.build" libpulse_headers "$include_root/pulse"
    install -m 0644 "$source/src/pulse/simple.h" "$include_root/pulse/"
    configure_header \
        "$source/src/pulse/version.h.in" "$include_root/pulse/version.h" \
        "PA_MAJOR=$major" \
        "PA_MINOR=$minor" \
        "PA_API_VERSION=$api_version" \
        "PA_PROTOCOL_VERSION=$protocol_version"
}

# Installs the SPA and PipeWire headers into the versioned directories that
# PipeWire's pkg-config files add to the include path, following its meson
# install rules, and generates version.h as its configure_file() does. Its
# meson configuration enables many features with build dependencies by
# default.
install_pipewire_headers() {
    local source="$1"
    local version="$2"
    local include_root="$3"
    local extensions="$source/src/pipewire/extensions"
    local major
    local minor
    local micro
    local api_version
    local spa_version
    local pipewire_root

    IFS=. read -r major minor micro _ <<<"$version"
    api_version="$(sed -n "s/^apiversion = '\([0-9][0-9.]*\)'\$/\1/p" "$source/meson.build")"
    spa_version="$(sed -n "s/^spaversion = '\([0-9][0-9.]*\)'\$/\1/p" "$source/meson.build")"
    [[ -n "$major" && -n "$minor" && -n "$micro" && -n "$api_version" && -n "$spa_version" ]] ||
        die "cannot read the PipeWire $version version numbers"

    mkdir -p "$include_root/spa-$spa_version"
    cp -R "$source/spa/include/spa" "$include_root/spa-$spa_version/"

    pipewire_root="$include_root/pipewire-$api_version/pipewire"
    install_meson_headers \
        "$source/src/pipewire/meson.build" pipewire_headers "$pipewire_root"
    install_meson_headers \
        "$extensions/meson.build" pipewire_ext_headers "$pipewire_root/extensions"
    # meson installs these by file name into extensions/session-manager.
    install_meson_headers \
        "$extensions/meson.build" pipewire_ext_sm_headers \
        "$pipewire_root/extensions/session-manager"
    configure_header \
        "$source/src/pipewire/version.h.in" "$pipewire_root/version.h" \
        "PIPEWIRE_VERSION_MAJOR=$major" \
        "PIPEWIRE_VERSION_MINOR=$minor" \
        "PIPEWIRE_VERSION_MICRO=$micro" \
        "PIPEWIRE_VERSION_NANO=0" \
        "PIPEWIRE_API_VERSION=\"$api_version\""
}

build_graphics_headers() {
    local sources_root="$1"
    local bundle_root="$2"
    local header_list="$3"
    local lock="$4"
    local work
    local prefix
    local name

    work="$(mktemp -d)"
    prefix="$work/prefix"
    # Keep the archive timestamps: otherwise make finds configure.ac newer
    # than the generated autotools files and tries to regenerate them.
    for name in xorgproto xtrans xcb-proto libxcb libx11 wayland alsa-lib; do
        cp -R --preserve=timestamps "$sources_root/$name" "$work/$name"
    done
    export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/share/pkgconfig"

    # The X.Org protocol headers and the X transport sources install without
    # compiling anything.
    (cd "$work/xorgproto" &&
        ./configure --prefix="$prefix" --disable-specs &&
        make install)
    (cd "$work/xtrans" && ./configure --prefix="$prefix" && make install)
    # libxcb generates its headers from the xcb-proto descriptions, but only
    # as part of its library build.
    (cd "$work/xcb-proto" && ./configure --prefix="$prefix" && make install)
    (cd "$work/libxcb" &&
        ./configure --prefix="$prefix" \
            --disable-devel-docs --without-doxygen &&
        make -j"$(nproc)" &&
        make install)
    # configure generates libX11's only generated header, XlibConf.h, so the
    # library itself is not compiled. It installs after xorgproto because
    # both provide X11/extensions/XKBgeom.h, and libX11 owns it.
    (cd "$work/libx11" &&
        ./configure --prefix="$prefix" --disable-specs &&
        make -C include install)
    # libXext installs every header of its include directory unchanged.
    cp -R "$sources_root/libxext/include/." "$prefix/include/"
    # Wayland installs its headers only together with its libraries.
    meson setup "$work/wayland-build" "$work/wayland" \
        --prefix="$prefix" \
        --libdir=lib \
        -Ddocumentation=false \
        -Ddtd_validation=false \
        -Dtests=false
    meson compile -C "$work/wayland-build"
    meson install -C "$work/wayland-build"
    # libxkbcommon's default build installs every header of include/xkbcommon
    # unchanged.
    cp -R "$sources_root/libxkbcommon/include/xkbcommon" "$prefix/include/"
    cp -R "$sources_root/vulkan-header/include/." "$prefix/include/"

    # alsa-lib's configure generates asoundlib.h and version.h, and its
    # include directory installs without compiling the library.
    (cd "$work/alsa-lib" &&
        ./configure --prefix="$prefix" &&
        make -C include install)
    install_pulseaudio_headers \
        "$sources_root/pulseaudio" \
        "$(source_version "$lock" pulseaudio)" \
        "$prefix/include"
    install_pipewire_headers \
        "$sources_root/pipewire" \
        "$(source_version "$lock" pipewire)" \
        "$prefix/include"
    # JACK and sndio install their headers unchanged.
    mkdir -p "$prefix/include/jack"
    cp "$sources_root/jack2/common/jack/"*.h "$prefix/include/jack/"
    cp "$sources_root/sndio/libsndio/sndio.h" "$prefix/include/"

    verify_graphics_header_bundle "$prefix/include" "$header_list" "$work"
    cp -R "$prefix/include" "$bundle_root"
    rm -rf -- "$work"
}

main() {
    local builder_root
    local lock="$image_dir/sources.lock"
    local work

    builder_root="$(dirname "$image_dir")"
    apt-get update
    apt-get install --yes --no-install-recommends \
        "${graphics_build_packages[@]}"

    work="$(mktemp -d)"
    fetch_sources "$lock" "$work/sources"
    collect_source_licenses \
        "$lock" "$work/sources" "$builder_root/licenses" ||
        exit 1
    build_graphics_headers \
        "$work/sources" \
        "$builder_root/graphics-headers" \
        "$image_dir/graphics-headers.txt" \
        "$lock"
    # build-toolchains.sh builds zlib for every target. The other sources
    # supply only the header bundle and their license files.
    mkdir "$builder_root/sources"
    mv "$work/sources/zlib" "$builder_root/sources/"
    rm -rf -- "$work"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
