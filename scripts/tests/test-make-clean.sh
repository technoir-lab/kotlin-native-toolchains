#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"

clean_commands="$(
    make --no-print-directory --dry-run -C "$project_root" clean
)"

grep -Fq \
    'rm -rf -- build/konan-linux-check build/konan-mingw-check' \
    <<<"$clean_commands" || {
    printf 'error: make clean does not remove toolchain intermediates\n' >&2
    printf '%s\n' "$clean_commands" >&2
    exit 1
}

if grep -Eq 'rm .*build/(toolchains|dist)' <<<"$clean_commands"; then
    printf 'error: make clean removes published toolchain artifacts\n' >&2
    printf '%s\n' "$clean_commands" >&2
    exit 1
fi

printf 'Make clean test passed.\n'
