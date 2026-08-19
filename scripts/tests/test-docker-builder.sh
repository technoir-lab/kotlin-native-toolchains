#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/docker-builder.XXXXXX")"

# Public state populated by the sourced orchestration libraries.
builder_arch=""
builder_platform=""
builder_host_tag=""
builder_image=""
builder_image_id=""
builder_uid=""
builder_gid=""
staging_dir=""

# shellcheck source=../lib/docker-builder.sh
# shellcheck disable=SC1091
source "$script_dir/lib/docker-builder.sh"
# shellcheck source=lib/assertions.sh
# shellcheck disable=SC1091
source "$test_dir/lib/assertions.sh"

cleanup() {
    cleanup_build
    rm -rf -- "$test_root"
}
trap cleanup EXIT

docker_log="$test_root/docker.log"
docker() {
    {
        printf 'docker'
        printf ' <%s>' "$@"
        printf '\n'
    } >>"$docker_log"
    if [[ "${1:-}" == "image" && "${2:-}" == "inspect" ]]; then
        printf 'sha256:test-builder-image\n'
    fi
}

common_dockerfile="$project_root/toolchains/common/builder/Dockerfile"
assert_docker_arg \
    "$common_dockerfile" \
    UBUNTU_IMAGE \
    'ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90'
assert_docker_arg "$common_dockerfile" CROSSTOOL_NG_VERSION '1.26.0'
assert_docker_arg "$common_dockerfile" ZLIB_VERSION '1.2.13'
assert_docker_arg "$common_dockerfile" BUILDER_UID '10001'
assert_docker_arg "$common_dockerfile" BUILDER_GID '10001'
assert_docker_arg "$common_dockerfile" BUILD_SCRIPT ''
assert_docker_arg "$common_dockerfile" DOWNLOAD_ZLIB_ARCHIVE false
assert_file_contains_line \
    "$common_dockerfile" \
    'ENTRYPOINT ["/opt/toolchain-builder/build.sh"]'
[[ ! -e "$project_root/toolchains/linux/builder/Dockerfile" &&
    ! -e "$project_root/toolchains/mingw/builder/Dockerfile" ]] ||
    fail "platform-specific builder Dockerfiles were not removed"

configure_docker_builder \
    "Linux" \
    "example/linux-builder" \
    "ctng-test" \
    "ubuntu-test" \
    Darwin \
    arm64
assert_equals arm64 "$builder_arch" "macOS host architecture was not mapped"
assert_equals linux/arm64 "$builder_platform" "Docker platform was not mapped"
assert_equals ubuntu-test-arm64 "$builder_host_tag" "host tag was not mapped"
assert_equals \
    example/linux-builder:ctng-test-arm64 \
    "$builder_image" \
    "builder image was not mapped"

fixture_root="$test_root/project,with-comma"
builder_root="$fixture_root/builder"
output="$fixture_root/output/artifact"
mkdir -p "$builder_root"
: >"$builder_root/Dockerfile.input"
printf '#!/usr/bin/env bash\n' >"$builder_root/build-toolchains.sh"
chmod 0755 "$builder_root/build-toolchains.sh"

init_build "$output"
prepare_output "$fixture_root"
run_docker_builder \
    "$builder_root" \
    "$builder_root/Dockerfile.input" \
    "build-toolchains.sh" \
    true \
    "ubuntu:test" \
    "Building test image..." \
    "Building test toolchain..." \
    >"$test_root/output.log"

assert_file_contains_line "$test_root/output.log" 'Building test image...'
assert_file_contains_line "$test_root/output.log" 'Building test toolchain...'
assert_equals \
    sha256:test-builder-image \
    "$builder_image_id" \
    "builder image id was not captured"

assert_file_contains "$docker_log" '<build> <--file>' "docker build was not invoked"
assert_file_contains \
    "$docker_log" "<$builder_root/Dockerfile.input>" \
    "shared Dockerfile was not passed to docker build"
assert_file_contains \
    "$docker_log" '<BUILDER_ARCH=arm64>' \
    "builder architecture was not propagated"
assert_file_contains \
    "$docker_log" "<BUILDER_UID=$builder_uid>" \
    "builder uid was not propagated"
assert_file_contains \
    "$docker_log" "<BUILDER_GID=$builder_gid>" \
    "builder gid was not propagated"
assert_file_contains \
    "$docker_log" '<BUILD_SCRIPT=build-toolchains.sh>' \
    "build script was not propagated"
assert_file_contains \
    "$docker_log" '<DOWNLOAD_ZLIB_ARCHIVE=true>' \
    "zlib archive selection was not propagated"
mount_source="$(quote_docker_mount_field "src=$staging_dir")"
assert_file_contains \
    "$docker_log" "<type=bind,$mount_source,dst=/artifacts>" \
    "artifact bind mount was not quoted"
assert_file_contains \
    "$docker_log" '<image> <inspect>' \
    "builder image was not inspected"

cleanup_build
configure_docker_builder \
    "Linux" "example/linux-builder" "ctng-test" "ubuntu-test" Linux x86_64
assert_equals amd64 "$builder_arch" "Linux host architecture was not mapped"
assert_equals linux/amd64 "$builder_platform" "Linux Docker platform was not mapped"

if configure_docker_builder \
    "Linux" "example/linux-builder" "ctng-test" "ubuntu-test" Darwin x86_64 \
    >"$test_root/unsupported.error" 2>&1; then
    fail "unsupported Docker builder host was accepted"
fi
assert_file_contains \
    "$test_root/unsupported.error" \
    'do not support macos/x64 hosts' \
    "unsupported host rejection was not reported"

printf 'Docker builder orchestration tests passed.\n'
