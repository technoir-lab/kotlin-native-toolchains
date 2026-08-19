#!/usr/bin/env bash
# Shared assertions for shell tests.

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-values differ}"

    if [[ "$actual" != "$expected" ]]; then
        printf 'error: %s\n' "$message" >&2
        printf 'expected: %s\nactual:   %s\n' "$expected" "$actual" >&2
        exit 1
    fi
}

assert_file_contains() {
    local file="$1"
    local text="$2"
    local message="${3:-$file does not contain: $text}"

    grep -Fq -- "$text" "$file" || fail "$message"
}

assert_file_contains_line() {
    local file="$1"
    local line="$2"
    local message="${3:-$file is missing required line: $line}"

    grep -Fxq -- "$line" "$file" || fail "$message"
}

assert_path_exists() {
    local path="$1"
    local message="${2:-expected path does not exist: $path}"

    [[ -e "$path" || -L "$path" ]] || fail "$message"
}

assert_path_missing() {
    local path="$1"
    local message="${2:-unexpected path exists: $path}"

    [[ ! -e "$path" && ! -L "$path" ]] || fail "$message"
}

read_shell_constant() {
    local file="$1"
    local key="$2"

    awk -v requested_key="$key" '
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            sub(/^readonly[[:space:]]+/, "", line)
            prefix = requested_key "="
            if (index(line, prefix) != 1) {
                next
            }
            value = substr(line, length(prefix) + 1)
            if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) {
                value = substr(value, 2, length(value) - 2)
            }
            print value
            exit
        }
    ' "$file"
}

assert_shell_constant() {
    local file="$1"
    local key="$2"
    local expected="$3"
    local actual

    actual="$(read_shell_constant "$file" "$key")"
    assert_equals \
        "$expected" \
        "$actual" \
        "$file has the wrong $key value"
}

read_docker_arg() {
    local file="$1"
    local key="$2"

    awk -v requested_key="$key" '
        $1 == "ARG" {
            separator = index($2, "=")
            name = separator ? substr($2, 1, separator - 1) : $2
            if (name != requested_key) {
                next
            }
            print separator ? substr($2, separator + 1) : ""
            exit
        }
    ' "$file"
}

assert_docker_arg() {
    local file="$1"
    local key="$2"
    local expected="$3"
    local actual

    actual="$(read_docker_arg "$file" "$key")"
    assert_equals \
        "$expected" \
        "$actual" \
        "$file has the wrong $key build argument"
}
