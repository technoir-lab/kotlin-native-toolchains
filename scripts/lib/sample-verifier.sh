#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Shared setup for platform sample verifiers.

sample_verifier_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=native-toolchain-host.sh
# shellcheck disable=SC1091
source "$sample_verifier_lib_dir/native-toolchain-host.sh"
# shellcheck source=native-toolchain-registry.sh
# shellcheck disable=SC1091
source "$sample_verifier_lib_dir/native-toolchain-registry.sh"
unset sample_verifier_lib_dir

# Public verifier contract consumed by the platform scripts.
readonly SAMPLE_OUTPUT_PREFIX="Hello from "

sample_root=""
platform_descriptor=""
toolchain_root=""
konan_data_dir=""

verifier_error() {
    printf 'error: %s\n' "$*" >&2
    return 1
}

verify_sample_output() {
    local platform="$1"
    local actual="$2"
    local compiler="${actual#"$SAMPLE_OUTPUT_PREFIX"}"

    [[ "$actual" == "$SAMPLE_OUTPUT_PREFIX"* && -n "$compiler" && "$actual" != *$'\n'* ]] ||
        verifier_error \
            "$platform sample printed '$actual'; expected 'Hello from <compiler>'"
}

validate_gradle_property_path() {
    local path="$1"
    local description="$2"

    [[ "$path" != *";"* && ! "$path" =~ [[:space:]] ]] ||
        verifier_error "$description cannot contain whitespace or semicolons"
}

init_sample_verifier() {
    local project_root="$1"
    local platform="$2"
    local legacy_toolchain="${3:-}"
    local default_package_name

    sample_root="$project_root/sample"
    platform_descriptor="$project_root/toolchains/$platform/$platform.properties"

    if [[ ! -x "$sample_root/gradlew" ]]; then
        verifier_error "sample Gradle project not found: $sample_root"
        return 1
    fi
    if [[ ! -f "$platform_descriptor" ]]; then
        verifier_error "platform descriptor not found: $platform_descriptor"
        return 1
    fi

    detect_host
    default_package_name="$(
        package_name_for \
            "$platform_descriptor" \
            "$NATIVE_TOOLCHAIN_KONAN_HOST"
    )"
    toolchain_root="${NATIVE_TOOLCHAIN:-${legacy_toolchain:-$project_root/build/toolchains/$default_package_name}}"

    # URL mode does not require a local artifact. In local mode, the Gradle
    # verifier reports a missing or invalid directory as part of the task graph.
    if [[ -d "$toolchain_root" ]]; then
        toolchain_root="$(cd "$toolchain_root" && pwd -P)"
    fi
    validate_gradle_property_path \
        "$toolchain_root" \
        "the toolchain path"
}

require_supported_sample_host() {
    local platform_label="$1"

    case "$NATIVE_TOOLCHAIN_HOST_OS/$NATIVE_TOOLCHAIN_HOST_ARCH" in
        macos/arm64|linux/x64) ;;
        *)
            verifier_error \
                "$platform_label sample verification does not support $NATIVE_TOOLCHAIN_HOST_OS/$NATIVE_TOOLCHAIN_HOST_ARCH hosts"
            ;;
    esac
}

prepare_konan_data() {
    local default_dir="$1"

    konan_data_dir="${KONAN_DATA_DIR:-$default_dir}"
    validate_gradle_property_path "$konan_data_dir" "KONAN_DATA_DIR" || return
    mkdir -p "$konan_data_dir"
    konan_data_dir="$(cd "$konan_data_dir" && pwd -P)"
}

_require_konan_data_dir() {
    [[ -n "$konan_data_dir" ]] ||
        verifier_error "Kotlin/Native data directory was not prepared"
}

konan_data_gradle_property() {
    _require_konan_data_dir || return
    printf '%s\n' "-Pkonan.data.dir=$konan_data_dir"
}

run_isolated_gradle() {
    [[ -x ./gradlew ]] || {
        verifier_error "Gradle wrapper not found in $(pwd -P)"
        return 1
    }
    KONAN_DATA_DIR="$konan_data_dir" ./gradlew \
        "$@" \
        "$(konan_data_gradle_property)" \
        --project-cache-dir "$konan_data_dir/gradle-project-cache" \
        --no-daemon
}

require_verifier_tool() {
    local tool="$1"
    local purpose="$2"
    local executable

    executable="$(command -v "$tool" || true)"
    if [[ -z "$executable" ]]; then
        verifier_error "$tool is required to $purpose"
        return 1
    fi
    printf '%s\n' "$executable"
}

# Prints the artifact the sample build used. With a URL source, the plugin
# extracts the artifact into the sample build instead of reading toolchain_root.
resolved_toolchain_root() {
    local platform="$1"
    local extracted="$sample_root/build/native-toolchains/$platform"

    if [[ -d "$toolchain_root" ]]; then
        printf '%s\n' "$toolchain_root"
    elif [[ -f "$extracted/manifest.properties" ]]; then
        printf '%s\n' "$extracted"
    else
        verifier_error \
            "the sample build used neither $toolchain_root nor an extracted $platform toolchain in $extracted"
    fi
}

# Prints the clang++ of the LLVM distribution that the sample build downloaded
# into the isolated Kotlin/Native data directory.
kotlin_native_clangxx() {
    local dependencies="$konan_data_dir/dependencies"
    local candidate
    local -a candidates=()

    _require_konan_data_dir || return
    for candidate in "$dependencies"/llvm-*/bin/clang++; do
        if [[ -x "$candidate" ]]; then
            candidates+=("$candidate")
        fi
    done
    case "${#candidates[@]}" in
        1) printf '%s\n' "${candidates[0]}" ;;
        0)
            verifier_error \
                "Kotlin/Native's clang++ was not found in $dependencies/llvm-*/bin"
            ;;
        *)
            verifier_error \
                "expected one Kotlin/Native LLVM distribution in $dependencies, found ${#candidates[@]}; remove the stale llvm-* directories:$(printf ' %s' "${candidates[@]%/bin/clang++}")"
            ;;
    esac
}

# Checks that Kotlin/Native's clang++ finds the libstdc++ headers of the given
# GCC major version with a target's clang options. Include paths from the
# environment are dropped so that only the toolchain is searched.
verify_cxx_standard_headers() {
    local label="$1"
    local gcc_major="$2"
    shift 2
    local clangxx
    local diagnostics

    clangxx="$(kotlin_native_clangxx)" || return 1
    if ! diagnostics="$(
        printf '%s\n' \
            '#include <string>' \
            "static_assert(_GLIBCXX_RELEASE == $gcc_major, \"expected GCC $gcc_major libstdc++\");" |
            without_include_path_env \
                "$clangxx" "$@" -x c++ -fsyntax-only - 2>&1
    )"; then
        printf '%s\n' "$diagnostics" >&2
        verifier_error \
            "$label: Kotlin/Native's clang++ cannot compile <string> with the GCC $gcc_major libstdc++ headers"
        return 1
    fi
    printf 'Kotlin/Native clang++ found the GCC %s C++ standard headers for %s.\n' \
        "$gcc_major" "$label"
}
