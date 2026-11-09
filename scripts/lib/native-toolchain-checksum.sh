#!/usr/bin/env bash
# Portable digest helpers shared by macOS and Linux toolchain builders.

sha256_file() {
    local input="$1"

    [[ -f "$input" ]] || {
        printf 'error: checksum input does not exist: %s\n' "$input" >&2
        return 2
    }

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$input" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$input" | awk '{print $1}'
    else
        printf 'error: SHA-256 requires sha256sum or shasum\n' >&2
        return 3
    fi
}
