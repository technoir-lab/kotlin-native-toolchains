#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"

# shellcheck source=lib/sample-verifier.sh
# shellcheck disable=SC1091
source "$script_dir/lib/sample-verifier.sh"

init_sample_verifier \
    "$project_root" \
    android \
    "${ANDROID_TOOLCHAIN:-}"

printf 'Building all Android Native debug and release samples...\n'
(
    cd "$sample_root"
    ./gradlew \
        buildAndroidNativeArm32Hello \
        buildAndroidNativeArm64Hello \
        buildAndroidNativeX86Hello \
        buildAndroidNativeX64Hello \
        "-PandroidToolchain=$toolchain_root" \
        "$@"
)

for target in androidNativeArm32 androidNativeArm64 androidNativeX86 androidNativeX64; do
    for build_type in debug release; do
        binary="$sample_root/build/bin/$target/${build_type}Executable/hello.kexe"
        [[ -x "$binary" ]] ||
            verifier_error "missing Android $target $build_type sample: $binary"
    done
done
