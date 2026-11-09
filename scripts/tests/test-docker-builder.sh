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
assert_docker_arg "$common_dockerfile" CROSSTOOL_NG_VERSION '1.29.0'
assert_docker_arg "$common_dockerfile" BUILDER_UID '10001'
assert_docker_arg "$common_dockerfile" BUILDER_GID '10001'
assert_docker_arg "$common_dockerfile" BUILD_SCRIPT ''
# Platform-specific inputs come from the builder directory, not build arguments.
# DEBIAN_FRONTEND is declared in both stages that install packages.
assert_equals \
    "BUILDER_ARCH BUILDER_GID BUILDER_UID BUILD_SCRIPT CROSSTOOL_NG_ARCHIVE_SHA512 CROSSTOOL_NG_VERSION DEBIAN_FRONTEND UBUNTU_IMAGE " \
    "$(awk '$1 == "ARG" { sub(/=.*/, "", $2); print $2 }' "$common_dockerfile" |
        LC_ALL=C sort -u | tr '\n' ' ')" \
    "the shared Dockerfile declares unexpected build arguments"
# The prepare stage builds on the shared packages alone, and the builder image
# receives only its /opt/toolchain-builder.
for line in \
    'FROM base AS prepare' \
    'COPY image /opt/toolchain-builder/image' \
    'RUN /opt/toolchain-builder/image/prepare.sh' \
    'COPY --from=prepare /opt/toolchain-builder /opt/toolchain-builder'; do
    assert_file_contains_line "$common_dockerfile" "$line"
done
assert_file_contains_line \
    "$common_dockerfile" \
    'ENTRYPOINT ["/opt/toolchain-builder/build.sh"]'
[[ ! -e "$project_root/toolchains/linux/builder/Dockerfile" &&
    ! -e "$project_root/toolchains/mingw/builder/Dockerfile" ]] ||
    fail "platform-specific builder Dockerfiles were not removed"
for platform in linux mingw; do
    [[ -x "$project_root/toolchains/$platform/builder/image/prepare.sh" ]] ||
        fail "the $platform builder does not provide an executable image/prepare.sh"
done

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
mkdir -p "$builder_root/image"
: >"$builder_root/Dockerfile.input"
printf '#!/usr/bin/env bash\n' >"$builder_root/build-toolchains.sh"
printf '#!/usr/bin/env bash\n' >"$builder_root/image/prepare.sh"
chmod 0755 "$builder_root/build-toolchains.sh" "$builder_root/image/prepare.sh"

init_build "$output"
prepare_output "$fixture_root"
run_docker_builder \
    "$builder_root" \
    "$builder_root/Dockerfile.input" \
    "build-toolchains.sh" \
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
assert_equals \
    "UBUNTU_IMAGE BUILDER_ARCH BUILDER_UID BUILDER_GID BUILD_SCRIPT " \
    "$(grep -F '<build>' "$docker_log" |
        grep -o '<--build-arg> <[A-Z_]*=' |
        sed -e 's/^<--build-arg> <//' -e 's/=$//' |
        tr '\n' ' ')" \
    "docker build received platform-specific build arguments"
mount_source="$(quote_docker_mount_field "src=$staging_dir")"
assert_file_contains \
    "$docker_log" "<type=bind,$mount_source,dst=/artifacts>" \
    "artifact bind mount was not quoted"
assert_file_contains \
    "$docker_log" '<image> <inspect>' \
    "builder image was not inspected"

chmod 0644 "$builder_root/image/prepare.sh"
if run_docker_builder \
    "$builder_root" \
    "$builder_root/Dockerfile.input" \
    "build-toolchains.sh" \
    "ubuntu:test" \
    "Building test image..." \
    "Building test toolchain..." \
    >"$test_root/incomplete.log" 2>&1; then
    fail "a builder without an executable image/prepare.sh was accepted"
fi
assert_file_contains \
    "$test_root/incomplete.log" \
    'Linux builder sources are incomplete' \
    "an incomplete builder directory was not reported"

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

# Text files must not name the builder's home directory, which does not exist
# where the artifact is used. Binary files may, through their debug info.
relocated_root="$test_root/relocated"
mkdir -p "$relocated_root/usr/lib/pkgconfig"
printf 'prefix=/usr\n' >"$relocated_root/usr/lib/pkgconfig/zlib.pc"
printf 'debug\0/home/ct/build-target/zlib\0' >"$relocated_root/usr/lib/libz.a"
require_no_builder_paths "$relocated_root" "the test toolchain" ||
    fail "a toolchain without builder paths in text files was rejected"

printf 'prefix=/home/ct/x-tools/target/sysroot/usr\n' \
    >"$relocated_root/usr/lib/pkgconfig/zlib.pc"
if require_no_builder_paths "$relocated_root" "the test toolchain" \
    2>"$test_root/builder-paths.error"; then
    fail "a text file naming the builder's home directory was accepted"
fi
assert_file_contains \
    "$test_root/builder-paths.error" \
    "the test toolchain names the builder's /home/ct in usr/lib/pkgconfig/zlib.pc"

# A stripped crosstool-NG prefix has no host programs left but keeps the
# libstdc++ headers and the GCC runtime.
gcc_prefix="$test_root/gcc-prefix"
gcc_triple="x86_64-unknown-linux-gnu"
gcc_headers="$gcc_prefix/$gcc_triple/include/c++/13.4.0"
gcc_runtime="$gcc_prefix/lib/gcc/$gcc_triple/13.4.0"
mkdir -p "$gcc_headers" "$gcc_runtime"
: >"$gcc_headers/string"
for input in crtbegin.o crtend.o libgcc.a libgcc_eh.a; do
    : >"$gcc_runtime/$input"
done
require_stripped_gcc_prefix \
    "$gcc_prefix" "$gcc_triple" 13.4.0 "the test toolchain" ||
    fail "a stripped GCC prefix was rejected"

assert_gcc_prefix_rejected() {
    local message="$1"

    if require_stripped_gcc_prefix \
        "$gcc_prefix" "$gcc_triple" 13.4.0 "the test toolchain" \
        2>"$test_root/gcc-prefix.error"; then
        fail "a GCC prefix was accepted although $message"
    fi
    assert_file_contains "$test_root/gcc-prefix.error" "$message"
}

mkdir "$gcc_prefix/bin"
assert_gcc_prefix_rejected \
    "the test toolchain still contains the host programs in bin/"
rmdir "$gcc_prefix/bin"
ln -s missing "$gcc_prefix/libexec"
assert_gcc_prefix_rejected \
    "the test toolchain still contains the host programs in libexec/"
rm -f -- "$gcc_prefix/libexec"
mv "$gcc_headers/string" "$test_root/string"
assert_gcc_prefix_rejected \
    "the test toolchain is missing the GCC 13.4.0 libstdc++ headers"
mv "$test_root/string" "$gcc_headers/string"
rm -f -- "$gcc_runtime/crtend.o"
assert_gcc_prefix_rejected \
    "the test toolchain is missing the GCC runtime input crtend.o"

printf 'Docker builder orchestration tests passed.\n'
