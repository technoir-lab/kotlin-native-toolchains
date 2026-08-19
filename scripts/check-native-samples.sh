#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"

# shellcheck source=lib/native-toolchain-registry.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-registry.sh"

usage() {
    printf 'Usage: scripts/check-native-samples.sh PLATFORM [verifier options]\n'
    printf '\nRegistered platforms:\n'
    print_platforms "$project_root/toolchains"
}

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
fi

platform="$1"
shift
dispatch_platform "$project_root" "$platform" "verifier.script" "$@"
