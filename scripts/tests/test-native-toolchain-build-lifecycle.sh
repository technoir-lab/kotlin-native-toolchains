#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/native-toolchain-build-lifecycle.XXXXXX")"

# Public state populated by the sourced lifecycle library.
output_dir=""
archive_requested=false
force=false
staging_dir=""
archive_staging=""

# shellcheck source=../lib/reproducible-archive.sh
# shellcheck disable=SC1091
source "$script_dir/lib/reproducible-archive.sh"
# shellcheck source=../lib/native-toolchain-build-lifecycle.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-build-lifecycle.sh"
# shellcheck source=lib/assertions.sh
# shellcheck disable=SC1091
source "$test_dir/lib/assertions.sh"

cleanup() {
    cleanup_build
    rm -rf -- "$test_root"
}
trap cleanup EXIT

usage() {
    printf 'test usage\n'
}

fixture_root="$test_root/project"
source_root="$fixture_root/source"
requested_output="$fixture_root/generated/artifact"
mkdir -p "$source_root"

custom_source=""
init_build "$fixture_root/default-output"
add_build_value_option --source-dir custom_source
parse_build_args \
    usage \
    --source-dir "$source_root" \
    --output-dir "$requested_output" \
    --archive \
    --force

assert_equals "$source_root" "$custom_source" "custom value option was not parsed"
assert_equals "$requested_output" "$output_dir" "output option was not parsed"
assert_equals true "$archive_requested" "archive option was not parsed"
assert_equals true "$force" "force option was not parsed"

prepare_output \
    "$fixture_root" \
    "$source_root" \
    "source"
create_staging 0755
printf 'payload\n' >"$staging_dir/payload.txt"
normalize_tree_metadata "$staging_dir"
publish_output "Created test artifact" >/dev/null
publish_archive >/dev/null

assert_equals \
    payload \
    "$(<"$requested_output/payload.txt")" \
    "published artifact content is missing"
assert_path_exists "$fixture_root/build/dist/artifact.tar.gz" \
    "archive was not published"
tar -tzf "$fixture_root/build/dist/artifact.tar.gz" |
    grep -Fxq 'artifact/payload.txt' ||
    fail "archive does not contain the published artifact"
assert_equals "" "$staging_dir" "published staging directory state was not cleared"
assert_equals "" "$archive_staging" "published archive state was not cleared"

init_build "$requested_output"
if prepare_output "$fixture_root" \
    >"$test_root/existing-output.error" 2>&1; then
    fail "existing output was accepted without --force"
fi
assert_file_contains \
    "$test_root/existing-output.error" \
    'output already exists' \
    "existing output rejection was not reported"

init_build "$source_root/nested-output"
if prepare_output \
    "$fixture_root" "$source_root" "source" \
    >"$test_root/overlap.error" 2>&1; then
    fail "an output nested in its protected source was accepted"
fi
assert_file_contains \
    "$test_root/overlap.error" \
    'cannot contain one another' \
    "protected source overlap was not reported"

abandoned_output="$fixture_root/generated/abandoned"
init_build "$abandoned_output"
prepare_output "$fixture_root"
create_staging 0755
abandoned_staging="$staging_dir"
archive_staging="$test_root/abandoned-archive.tmp"
: >"$archive_staging"
cleanup_build
assert_path_missing "$abandoned_staging" "cleanup left staging output behind"
assert_path_missing "$archive_staging" "cleanup left archive staging behind"

printf 'Native toolchain build lifecycle tests passed.\n'
