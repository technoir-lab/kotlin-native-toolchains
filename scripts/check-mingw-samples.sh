#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

readonly RUNNER_PLATFORM="linux/amd64"
readonly RUNNER_IMAGE="io-technoirlab/mingw-konan-sample-runner:ubuntu24.04-wine-amd64"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
runner_root="$project_root/toolchains/mingw/runner"

# shellcheck source=lib/sample-verifier.sh
# shellcheck disable=SC1091
source "$script_dir/lib/sample-verifier.sh"
# shellcheck source=lib/docker-mount.sh
# shellcheck disable=SC1091
source "$script_dir/lib/docker-mount.sh"

init_sample_verifier \
    "$project_root" \
    mingw \
    "${MINGW_TOOLCHAIN:-}"
require_supported_sample_host MinGW

[[ -f "$runner_root/Dockerfile" ]] ||
    verifier_error "MinGW Wine runner definition not found: $runner_root"
prepare_konan_data "$project_root/build/konan-mingw-check"

printf 'Building the MinGW x64 debug and release samples with the GCC/MinGW-w64 sysroot...\n'
(
    cd "$sample_root"
    run_isolated_gradle \
        buildMingwX64Hello \
        "-PmingwToolchain=$toolchain_root" \
        "$@"
)

resolved_toolchain="$(resolved_toolchain_root mingw)"
verify_cxx_standard_headers "MinGW x64" 13 \
    -target x86_64-pc-windows-gnu \
    "--sysroot=$resolved_toolchain/konan-sysroot"

objdump_tool="$(require_verifier_tool objdump "inspect the MinGW sample")"
strings_tool="$(require_verifier_tool strings "inspect the MinGW sample")"

verify_mingw_binary() {
    local build_type="$1"
    local binary="$2"
    local file_description
    local pe_headers
    local runtime_dll
    local gcc_signatures

    [[ -f "$binary" ]] ||
        verifier_error "missing MinGW x64 $build_type sample: $binary"

    file_description="$(file "$binary")"
    printf '%s\n' "$file_description"
    grep -Eq 'PE32\+ executable.*x86-64.*MS Windows' <<<"$file_description" ||
        verifier_error "MinGW $build_type sample is not an x86-64 PE executable"

    pe_headers="$("$objdump_tool" -p "$binary")"
    grep -Fi 'DLL Name: msvcrt.dll' <<<"$pe_headers" >/dev/null ||
        verifier_error "MinGW $build_type sample did not link against MSVCRT"
    if grep -Eqi 'DLL Name: (api-ms-win-crt-|ucrtbase\.dll)' <<<"$pe_headers"; then
        verifier_error "MinGW $build_type sample unexpectedly imports the Universal CRT"
    fi
    for runtime_dll in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll; do
        if grep -Fi "DLL Name: $runtime_dll" <<<"$pe_headers" >/dev/null; then
            verifier_error "MinGW $build_type sample dynamically imports $runtime_dll"
        fi
    done

    gcc_signatures="$("$strings_tool" "$binary" | grep -F 'GCC:' || true)"
    grep -Eq '^GCC: \(crosstool-NG [^)]*\) 13\.4\.0$' <<<"$gcc_signatures" ||
        verifier_error \
            "MinGW $build_type sample does not contain the source-built GCC 13.4.0 runtime marker"
}

debug_binary="$sample_root/build/bin/mingwX64/debugExecutable/hello.exe"
release_binary="$sample_root/build/bin/mingwX64/releaseExecutable/hello.exe"
verify_mingw_binary debug "$debug_binary"
verify_mingw_binary release "$release_binary"

require_verifier_tool docker "execute the MinGW samples under Wine" >/dev/null
printf 'Building the pinned amd64 Wine runner image...\n'
docker build \
    --platform "$RUNNER_PLATFORM" \
    --tag "$RUNNER_IMAGE" \
    "$runner_root"

run_sample() {
    local build_type="$1"
    local binary="$2"
    local actual
    local binary_mount_source

    binary_mount_source="$(
        quote_docker_mount_field "src=$binary"
    )"
    actual="$(
        docker run \
            --rm \
            --platform "$RUNNER_PLATFORM" \
            --mount "type=bind,$binary_mount_source,dst=/opt/hello.exe,readonly" \
            "$RUNNER_IMAGE" \
            /opt/hello.exe |
            tr -d '\r'
    )"
    verify_sample_output "MinGW $build_type" "$actual"
    printf 'Executed the MinGW x64 %s sample successfully under Wine.\n' "$build_type"
}

run_sample debug "$debug_binary"
run_sample release "$release_binary"
