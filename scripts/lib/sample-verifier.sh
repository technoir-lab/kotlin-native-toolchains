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

konan_data_gradle_property() {
    [[ -n "$konan_data_dir" ]] || {
        verifier_error "Kotlin/Native data directory was not prepared"
        return 1
    }
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
