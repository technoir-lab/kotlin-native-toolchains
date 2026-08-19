#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

readonly RUNTIME_IMAGE="ubuntu:22.04@sha256:0e0a0fc6d18feda9db1590da249ac93e8d5abfea8f4c3c0c849ce512b5ef8982"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"

# shellcheck source=lib/sample-verifier.sh
# shellcheck disable=SC1091
source "$script_dir/lib/sample-verifier.sh"
# shellcheck source=lib/docker-mount.sh
# shellcheck disable=SC1091
source "$script_dir/lib/docker-mount.sh"

init_sample_verifier \
    "$project_root" \
    linux \
    "${LINUX_TOOLCHAIN:-}"
require_supported_sample_host Linux
prepare_konan_data "$project_root/build/konan-linux-check"

printf 'Building Linux x64 and ARM64 debug and release samples with GCC sysroots...\n'
(
    cd "$sample_root"
    run_isolated_gradle \
        buildLinuxX64Hello \
        buildLinuxArm64Hello \
        "-PlinuxToolchain=$toolchain_root" \
        "$@"
)

objdump_tool="$(require_verifier_tool objdump "inspect Linux samples")"

verify_linux_binary() {
    local target_label="$1"
    local build_type="$2"
    local binary="$3"
    local architecture_pattern="$4"
    local interpreter="$5"
    local file_description

    [[ -x "$binary" ]] ||
        verifier_error "missing $target_label $build_type sample: $binary"

    file_description="$(file "$binary")"
    printf '%s\n' "$file_description"
    grep -Eq "ELF 64-bit.*($architecture_pattern)" <<<"$file_description" ||
        verifier_error "$target_label $build_type sample has the wrong ELF architecture"
    grep -F "$interpreter" <<<"$file_description" >/dev/null ||
        verifier_error "$target_label $build_type sample has the wrong dynamic interpreter"
    grep -F 'for GNU/Linux 5.15.118' <<<"$file_description" >/dev/null ||
        verifier_error "$target_label $build_type sample did not use the Linux 5.15.118 sysroot"
    "$objdump_tool" --private-headers "$binary" |
        grep -F 'GLIBC_2.34' >/dev/null ||
        verifier_error \
            "$target_label $build_type sample did not link against the glibc 2.35 sysroot"
}

x64_debug_binary="$sample_root/build/bin/linuxX64/debugExecutable/hello.kexe"
x64_release_binary="$sample_root/build/bin/linuxX64/releaseExecutable/hello.kexe"
arm64_debug_binary="$sample_root/build/bin/linuxArm64/debugExecutable/hello.kexe"
arm64_release_binary="$sample_root/build/bin/linuxArm64/releaseExecutable/hello.kexe"

verify_linux_binary \
    "Linux x64" debug "$x64_debug_binary" 'x86-64|x86_64' \
    '/lib64/ld-linux-x86-64.so.2'
verify_linux_binary \
    "Linux x64" release "$x64_release_binary" 'x86-64|x86_64' \
    '/lib64/ld-linux-x86-64.so.2'
verify_linux_binary \
    "Linux ARM64" debug "$arm64_debug_binary" 'ARM aarch64|aarch64' \
    '/lib/ld-linux-aarch64.so.1'
verify_linux_binary \
    "Linux ARM64" release "$arm64_release_binary" 'ARM aarch64|aarch64' \
    '/lib/ld-linux-aarch64.so.1'

require_verifier_tool docker "execute Linux samples" >/dev/null

run_sample() {
    local platform="$1"
    local build_type="$2"
    local binary="$3"
    local actual
    local mount_source
    mount_source="$(quote_docker_mount_field "src=$binary")"
    actual="$(
        docker run \
            --rm \
            --platform "$platform" \
            --mount "type=bind,$mount_source,dst=/opt/hello,readonly" \
            "$RUNTIME_IMAGE" \
            /opt/hello
    )"
    verify_sample_output "$platform $build_type" "$actual"
    printf 'Executed %s %s sample successfully.\n' "$platform" "$build_type"
}

run_sample linux/amd64 debug "$x64_debug_binary"
run_sample linux/amd64 release "$x64_release_binary"
run_sample linux/arm64 debug "$arm64_debug_binary"
run_sample linux/arm64 release "$arm64_release_binary"
