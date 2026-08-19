#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
output_file="$(mktemp "${TMPDIR:-/tmp}/native-toolchain-platform.XXXXXX")"

cleanup() {
    rm -f -- "$output_file"
}
trap cleanup EXIT

for target in toolchain archive sample verify check pipeline build; do
    if make --no-print-directory -C "$project_root" "$target" PLATFORM= \
        >"$output_file" 2>&1; then
        printf 'error: make %s succeeded without PLATFORM\n' "$target" >&2
        exit 1
    fi

    grep -Fq \
        'error: PLATFORM is required; choose android, linux, or mingw' \
        "$output_file" || {
        printf 'error: make %s did not report the missing PLATFORM clearly\n' \
            "$target" >&2
        cat "$output_file" >&2
        exit 1
    }
done

printf 'Make platform-selection test passed.\n'
