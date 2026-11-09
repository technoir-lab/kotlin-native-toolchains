#!/usr/bin/env bash
# Shared host normalization for native toolchain builders.
# shellcheck disable=SC2034
#
# Call detect_host before reading the exported shell
# variables. Detection does not imply that a platform builder supports that
# host; each builder must enforce its supported host combinations.

detect_host() {
    local raw_os
    local raw_arch

    raw_os="${1:-$(uname -s)}"
    raw_arch="${2:-$(uname -m)}"

    case "$raw_os" in
        Darwin)
            NATIVE_TOOLCHAIN_HOST_OS="macos"
            ;;
        Linux)
            NATIVE_TOOLCHAIN_HOST_OS="linux"
            ;;
        *)
            NATIVE_TOOLCHAIN_HOST_OS="unknown"
            ;;
    esac

    case "$raw_arch" in
        arm64|aarch64)
            NATIVE_TOOLCHAIN_HOST_ARCH="arm64"
            ;;
        x86_64|amd64|AMD64)
            NATIVE_TOOLCHAIN_HOST_ARCH="x64"
            ;;
        *)
            NATIVE_TOOLCHAIN_HOST_ARCH="$raw_arch"
            ;;
    esac

    case "$NATIVE_TOOLCHAIN_HOST_OS/$NATIVE_TOOLCHAIN_HOST_ARCH" in
        macos/arm64)
            NATIVE_TOOLCHAIN_KONAN_HOST="macos_arm64"
            ;;
        linux/x64)
            NATIVE_TOOLCHAIN_KONAN_HOST="linux_x64"
            ;;
        *)
            NATIVE_TOOLCHAIN_KONAN_HOST="unsupported"
            ;;
    esac
}

# Runs a command without the environment variables that add compiler include
# paths, so that a compiler searches only its toolchain's directories.
without_include_path_env() {
    env \
        -u CPATH \
        -u C_INCLUDE_PATH \
        -u CPLUS_INCLUDE_PATH \
        -u OBJC_INCLUDE_PATH \
        -u OBJCPLUS_INCLUDE_PATH \
        "$@"
}
