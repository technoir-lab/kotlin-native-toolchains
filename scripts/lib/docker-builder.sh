#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Shared Docker orchestration for source-built Linux-hosted toolchains.
#
# Platforms differ only in their builder directory, which is the Docker build
# context of the shared Dockerfile. It provides image/prepare.sh, configs/,
# and the build script; no platform-specific build arguments exist.

docker_builder_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=native-toolchain-host.sh
# shellcheck disable=SC1091
source "$docker_builder_lib_dir/native-toolchain-host.sh"
# shellcheck source=docker-mount.sh
# shellcheck disable=SC1091
source "$docker_builder_lib_dir/docker-mount.sh"
# shellcheck source=reproducible-archive.sh
# shellcheck disable=SC1091
source "$docker_builder_lib_dir/reproducible-archive.sh"
# shellcheck source=native-toolchain-build-lifecycle.sh
# shellcheck disable=SC1091
source "$docker_builder_lib_dir/native-toolchain-build-lifecycle.sh"
unset docker_builder_lib_dir

builder_label=""
builder_arch=""
builder_platform=""
builder_host_tag=""
builder_image=""
builder_image_id=""
builder_uid=""
builder_gid=""

# The shared Dockerfile builds as the ct user in this home directory.
readonly DOCKER_BUILDER_HOME="/home/ct"

_docker_builder_error() {
    printf 'error: %s\n' "$*" >&2
    return 1
}

configure_docker_builder() {
    local label="$1"
    local image_repository="$2"
    local image_tag="$3"
    local host_tag_prefix="$4"

    if [[ $# -ge 6 ]]; then
        detect_host "$5" "$6"
    else
        detect_host
    fi

    case "$NATIVE_TOOLCHAIN_HOST_OS/$NATIVE_TOOLCHAIN_HOST_ARCH" in
        macos/arm64)
            builder_arch="arm64"
            ;;
        linux/x64)
            builder_arch="amd64"
            ;;
        *)
            _docker_builder_error \
                "$label toolchain builds do not support $NATIVE_TOOLCHAIN_HOST_OS/$NATIVE_TOOLCHAIN_HOST_ARCH hosts"
            return
            ;;
    esac

    builder_label="$label"
    builder_platform="linux/$builder_arch"
    # Public state consumed when platform manifests are generated.
    # shellcheck disable=SC2034
    builder_host_tag="$host_tag_prefix-$builder_arch"
    builder_image="$image_repository:$image_tag-$builder_arch"
    builder_image_id=""
    builder_uid="$(id -u)"
    builder_gid="$(id -g)"
}

run_docker_builder() {
    local builder_root="$1"
    local dockerfile="$2"
    local build_script="$3"
    local ubuntu_image="$4"
    local image_message="$5"
    local build_message="$6"
    local artifact_mount_source

    [[ -f "$dockerfile" && -x "$builder_root/$build_script" &&
        -x "$builder_root/image/prepare.sh" ]] || {
        _docker_builder_error \
            "$builder_label builder sources are incomplete: $builder_root"
        return
    }
    command -v docker >/dev/null 2>&1 || {
        _docker_builder_error \
            "Docker is required to build $builder_label toolchains"
        return
    }

    # The builder image uses the invoking uid/gid so bind-mounted outputs remain
    # writable by the host on both macOS and native Linux.
    create_staging 0777
    artifact_mount_source="$(quote_docker_mount_field "src=$staging_dir")"

    printf '%s\n' "$image_message"
    docker build \
        --file "$dockerfile" \
        --platform "$builder_platform" \
        --build-arg "UBUNTU_IMAGE=$ubuntu_image" \
        --build-arg "BUILDER_ARCH=$builder_arch" \
        --build-arg "BUILDER_UID=$builder_uid" \
        --build-arg "BUILDER_GID=$builder_gid" \
        --build-arg "BUILD_SCRIPT=$build_script" \
        --tag "$builder_image" \
        "$builder_root"

    printf '%s\n' "$build_message"
    docker run \
        --rm \
        --platform "$builder_platform" \
        --mount "type=bind,$artifact_mount_source,dst=/artifacts" \
        "$builder_image"

    builder_image_id="$(docker image inspect --format '{{.Id}}' "$builder_image")"
    [[ "$builder_image_id" == sha256:* ]] || {
        _docker_builder_error \
            "cannot determine the $builder_label builder image id"
        return
    }
}

# Fails if a text file under root names the builder's home directory.
# Consumers read text files such as pkg-config files and linker scripts on
# machines where those paths do not exist. Binary files are not checked, since
# their debug info records build directories.
require_no_builder_paths() {
    local root="$1"
    local description="$2"
    local root_prefix="$root/"
    local matches
    local file
    local files=""
    local status=0

    matches="$(LC_ALL=C grep -rIlF -- "$DOCKER_BUILDER_HOME/" "$root")" || status=$?
    case "$status" in
        0)
            while IFS= read -r file; do
                files+="${files:+, }${file#"$root_prefix"}"
            done <<<"$matches"
            _docker_builder_error \
                "$description names the builder's $DOCKER_BUILDER_HOME in $files"
            ;;
        1) ;;
        *)
            _docker_builder_error "cannot search $description for builder paths"
            ;;
    esac
}

# Fails unless a crosstool-NG prefix that the container builder stripped has
# no host programs left but keeps the libstdc++ headers and the GCC runtime
# that Kotlin/Native compiles and links with.
require_stripped_gcc_prefix() {
    local prefix="$1"
    local triple="$2"
    local gcc_version="$3"
    local description="$4"
    local gcc_runtime="$prefix/lib/gcc/$triple/$gcc_version"
    local host_programs
    local input

    for host_programs in bin libexec; do
        [[ ! -e "$prefix/$host_programs" && ! -L "$prefix/$host_programs" ]] || {
            _docker_builder_error \
                "$description still contains the host programs in $host_programs/"
            return
        }
    done
    [[ -f "$prefix/$triple/include/c++/$gcc_version/string" ]] || {
        _docker_builder_error \
            "$description is missing the GCC $gcc_version libstdc++ headers"
        return
    }
    for input in crtbegin.o crtend.o libgcc.a libgcc_eh.a; do
        [[ -f "$gcc_runtime/$input" ]] || {
            _docker_builder_error \
                "$description is missing the GCC runtime input $input"
            return
        }
    done
}
