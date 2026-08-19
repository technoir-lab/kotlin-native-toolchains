#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
sample_build="$project_root/sample/build.gradle.kts"
android_verifier="$script_dir/check-android-samples.sh"
linux_verifier="$script_dir/check-linux-samples.sh"
mingw_verifier="$script_dir/check-mingw-samples.sh"

# shellcheck source=lib/assertions.sh
# shellcheck disable=SC1091
source "$test_dir/lib/assertions.sh"

assert_file_contains_line \
    "$sample_build" \
    'import org.jetbrains.kotlin.gradle.plugin.mpp.NativeBuildType.RELEASE'
assert_file_contains_line \
    "$sample_build" \
    '        binaries.executable(listOf(DEBUG, RELEASE)) {'
assert_file_contains_line \
    "$sample_build" \
    '                dependsOn(helloLinkTask)'

assert_file_contains_line \
    "$android_verifier" \
    '    for build_type in debug release; do'
for target in androidNativeArm32 androidNativeArm64 androidNativeX86 androidNativeX64; do
    assert_file_contains "$android_verifier" "$target"
done

for target in linuxX64 linuxArm64; do
    for build_type in debug release; do
        assert_file_contains \
            "$linux_verifier" \
            "$target/${build_type}Executable/hello.kexe"
    done
done
for invocation in \
    "run_sample linux/amd64 debug \"\$x64_debug_binary\"" \
    "run_sample linux/amd64 release \"\$x64_release_binary\"" \
    "run_sample linux/arm64 debug \"\$arm64_debug_binary\"" \
    "run_sample linux/arm64 release \"\$arm64_release_binary\""; do
    assert_file_contains_line "$linux_verifier" "$invocation"
done
for invocation in \
    "\"Linux x64\" debug \"\$x64_debug_binary\"" \
    "\"Linux x64\" release \"\$x64_release_binary\"" \
    "\"Linux ARM64\" debug \"\$arm64_debug_binary\"" \
    "\"Linux ARM64\" release \"\$arm64_release_binary\""; do
    assert_file_contains "$linux_verifier" "$invocation"
done

for build_type in debug release; do
    assert_file_contains \
        "$mingw_verifier" \
        "mingwX64/${build_type}Executable/hello.exe"
    assert_file_contains_line \
        "$mingw_verifier" \
        "verify_mingw_binary $build_type \"\$${build_type}_binary\""
    assert_file_contains_line \
        "$mingw_verifier" \
        "run_sample $build_type \"\$${build_type}_binary\""
done

printf 'Sample debug and release build contract tests passed.\n'
