#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/native-toolchain-output-safety.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

assert_unsafe_output_rejected() {
    local builder="$1"
    local output_path="$2"
    local error_file="$test_root/error"
    shift 2

    if "$builder" \
        "$@" \
        --output-dir "$output_path" \
        --force >"$error_file" 2>&1; then
        printf 'error: unsafe output path was accepted: %q\n' "$output_path" >&2
        exit 1
    fi
    if ! grep -Fq "refusing unsafe output path" "$error_file"; then
        printf 'error: output path was not rejected by the safety guard: %q\n' \
            "$output_path" >&2
        cat "$error_file" >&2
        exit 1
    fi
}

for builder in \
    "$script_dir/build-android-toolchain.sh" \
    "$script_dir/build-linux-toolchain.sh" \
    "$script_dir/build-mingw-toolchain.sh"; do
    builder_args=()
    if [[ "$(basename "$builder")" == "build-android-toolchain.sh" ]]; then
        builder_args=(--ndk-dir "$project_root")
    fi
    assert_unsafe_output_rejected "$builder" "" "${builder_args[@]}"
    assert_unsafe_output_rejected "$builder" "." "${builder_args[@]}"
    assert_unsafe_output_rejected "$builder" ".." "${builder_args[@]}"
    assert_unsafe_output_rejected "$builder" "/" "${builder_args[@]}"
    assert_unsafe_output_rejected "$builder" "$project_root" "${builder_args[@]}"
    assert_unsafe_output_rejected "$builder" "$project_root/." "${builder_args[@]}"
done

printf 'Native toolchain builder output safety tests passed.\n'
