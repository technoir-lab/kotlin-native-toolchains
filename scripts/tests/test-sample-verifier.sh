#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/sample-verifier.XXXXXX")"
test_root="$(cd "$test_root" && pwd -P)"
trap 'rm -rf -- "$test_root"' EXIT

# Public state populated by the sourced verifier library.
sample_root=""
platform_descriptor=""
toolchain_root=""
konan_data_dir=""

# shellcheck source=../lib/sample-verifier.sh
# shellcheck disable=SC1091
source "$script_dir/lib/sample-verifier.sh"
# shellcheck source=lib/assertions.sh
# shellcheck disable=SC1091
source "$test_dir/lib/assertions.sh"

verify_sample_output Linux 'Hello from Clang 19.1.7'
if verify_sample_output Linux 'Hello from ' \
    >"$test_root/missing-compiler.output" \
    2>"$test_root/missing-compiler.error"; then
    fail "sample output without a compiler was accepted"
fi
assert_file_contains \
    "$test_root/missing-compiler.error" \
    "expected 'Hello from <compiler>'"
if verify_sample_output Linux $'Hello from Clang 19.1.7\nunexpected' \
    >"$test_root/multiline-output.output" \
    2>"$test_root/multiline-output.error"; then
    fail "multiline sample output was accepted"
fi
assert_file_contains \
    "$test_root/multiline-output.error" \
    "expected 'Hello from <compiler>'"

fixture_root="$test_root/project"
mkdir -p \
    "$fixture_root/sample" \
    "$fixture_root/toolchains/linux" \
    "$test_root/legacy-toolchain" \
    "$test_root/custom-toolchain"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    "printf 'KONAN_DATA_DIR=%s\\n' \"\${KONAN_DATA_DIR:-}\"" \
    "printf 'argument=%s\\n' \"\$@\"" \
    >"$fixture_root/sample/gradlew"
chmod 0755 "$fixture_root/sample/gradlew"
cp \
    "$project_root/toolchains/linux/linux.properties" \
    "$fixture_root/toolchains/linux/linux.properties"

legacy_toolchain="$test_root/legacy-toolchain"
init_sample_verifier "$fixture_root" linux "$legacy_toolchain"
assert_equals "$fixture_root/sample" "$sample_root" \
    "sample root was not initialized"
assert_equals \
    "$fixture_root/toolchains/linux/linux.properties" \
    "$platform_descriptor" \
    "platform descriptor was not initialized"
assert_equals "$legacy_toolchain" "$toolchain_root" \
    "legacy platform override was not selected"

NATIVE_TOOLCHAIN="$test_root/custom-toolchain"
init_sample_verifier "$fixture_root" linux "$legacy_toolchain"
assert_equals "$NATIVE_TOOLCHAIN" "$toolchain_root" \
    "generic toolchain override did not take precedence"
unset NATIVE_TOOLCHAIN

unsafe_toolchain="$test_root/toolchain with spaces"
NATIVE_TOOLCHAIN="$unsafe_toolchain"
if init_sample_verifier "$fixture_root" linux "$legacy_toolchain" \
    >"$test_root/unsafe-toolchain.error" 2>&1; then
    fail "unsafe toolchain path was accepted"
fi
unset NATIVE_TOOLCHAIN
assert_file_contains \
    "$test_root/unsafe-toolchain.error" \
    'toolchain path cannot contain whitespace or semicolons'

prepare_konan_data "$test_root/default-konan-data"
assert_path_exists "$konan_data_dir"
assert_equals "$test_root/default-konan-data" "$konan_data_dir" \
    "default Kotlin/Native data directory was not selected"
assert_equals \
    "-Pkonan.data.dir=$test_root/default-konan-data" \
    "$(konan_data_gradle_property)" \
    "Kotlin/Native data Gradle property was not configured"
gradle_invocation_output="$test_root/gradle-invocation.output"
(
    cd "$fixture_root/sample"
    run_isolated_gradle sampleTask
) >"$gradle_invocation_output"
assert_file_contains_line \
    "$gradle_invocation_output" \
    "KONAN_DATA_DIR=$test_root/default-konan-data" \
    "isolated Gradle invocation did not export KONAN_DATA_DIR"
assert_file_contains_line \
    "$gradle_invocation_output" \
    "argument=-Pkonan.data.dir=$test_root/default-konan-data" \
    "isolated Gradle invocation did not set konan.data.dir"
assert_file_contains_line \
    "$gradle_invocation_output" \
    'argument=--project-cache-dir' \
    "isolated Gradle invocation did not set a project cache"
assert_file_contains_line \
    "$gradle_invocation_output" \
    "argument=$test_root/default-konan-data/gradle-project-cache" \
    "isolated Gradle invocation used the wrong project cache"
assert_file_contains_line \
    "$gradle_invocation_output" \
    'argument=--no-daemon' \
    "isolated Gradle invocation did not disable daemon reuse"

KONAN_DATA_DIR="$test_root/custom-konan-data"
prepare_konan_data "$test_root/ignored-konan-data"
assert_equals "$KONAN_DATA_DIR" "$konan_data_dir" \
    "KONAN_DATA_DIR did not override the default"
unset KONAN_DATA_DIR

KONAN_DATA_DIR="$test_root/konan data with spaces"
if prepare_konan_data "$test_root/ignored-konan-data" \
    >"$test_root/unsafe-konan-data.error" 2>&1; then
    fail "unsafe Kotlin/Native data path was accepted"
fi
unset KONAN_DATA_DIR
assert_file_contains \
    "$test_root/unsafe-konan-data.error" \
    'KONAN_DATA_DIR cannot contain whitespace or semicolons'

# Consumed by require_supported_sample_host from the sourced verifier library.
# shellcheck disable=SC2034
NATIVE_TOOLCHAIN_HOST_OS=macos
# shellcheck disable=SC2034
NATIVE_TOOLCHAIN_HOST_ARCH=arm64
require_supported_sample_host Test
# shellcheck disable=SC2034
NATIVE_TOOLCHAIN_HOST_ARCH=x64
if require_supported_sample_host Test \
    >"$test_root/unsupported-host.error" 2>&1; then
    fail "unsupported sample-verifier host was accepted"
fi
assert_file_contains \
    "$test_root/unsupported-host.error" \
    'Test sample verification does not support macos/x64 hosts'

assert_equals \
    "$(command -v sh)" \
    "$(require_verifier_tool sh "run the verifier test")" \
    "required verifier tool was not resolved"
if require_verifier_tool sample-verifier-missing-command "run the verifier test" \
    >"$test_root/missing-tool.output" 2>"$test_root/missing-tool.error"; then
    fail "missing verifier tool was accepted"
fi
assert_file_contains \
    "$test_root/missing-tool.error" \
    'sample-verifier-missing-command is required to run the verifier test'

printf 'Sample verifier setup tests passed.\n'
