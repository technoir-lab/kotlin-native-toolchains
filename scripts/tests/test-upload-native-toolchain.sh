#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/native-toolchain-upload-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

# shellcheck source=../lib/native-toolchain-host.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-host.sh"
# shellcheck source=../lib/native-toolchain-registry.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-registry.sh"
# shellcheck source=../lib/native-toolchain-checksum.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-checksum.sh"
# shellcheck source=lib/assertions.sh
# shellcheck disable=SC1091
source "$test_dir/lib/assertions.sh"

upload_script="$script_dir/upload-native-toolchain.sh"
stub_dir="$test_root/bin"
state_dir="$test_root/gh-state"
# gh reads text after a '#' in a file argument as a label, so the fixture
# paths contain one.
upload_tmp="$test_root/tmp#1"
dist_dir="$test_root/dist#1"
output_file="$test_root/output"
gh_log="$state_dir/gh.log"
mkdir -p "$stub_dir" "$state_dir" "$upload_tmp" "$dist_dir"

# The stub serves the release's assets from assets.tsv, in the format the
# upload script requests from the REST API, and records uploads there.
cat >"$stub_dir/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "$GH_STUB_CHECKSUM_LIB"
{
    printf 'gh'
    printf ' <%s>' "$@"
    printf '\n'
} >>"$GH_STUB_STATE/gh.log"
assets="$GH_STUB_STATE/assets.tsv"
touch "$assets"

case "${1:-}" in
    api)
        if [[ -e "$GH_STUB_STATE/release-missing" ]]; then
            printf 'gh: Not Found (HTTP 404)\n' >&2
            exit 1
        fi
        cat "$assets"
        ;;
    release)
        [[ "${2:-}" == upload ]] || {
            printf 'unexpected gh invocation: %s\n' "$*" >&2
            exit 1
        }
        release="$3"
        shift 3
        repo=""
        files=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --repo) repo="$2"; shift 2 ;;
                --clobber) shift ;;
                *) files+=("${1%%#*}"); shift ;;
            esac
        done
        for file in "${files[@]}"; do
            name="$(basename "$file")"
            cp "$file" "$GH_STUB_STATE/uploaded-$name"
            digest="sha256:$(sha256_file "$file")"
            if [[ -e "$GH_STUB_STATE/corrupt-upload" ]]; then
                digest="sha256:0000000000000000000000000000000000000000000000000000000000000000"
            fi
            awk -F '\t' -v name="$name" '$1 != name' "$assets" >"$assets.next"
            printf '%s\t%s\t%s\tuploaded\thttps://github.com/%s/releases/download/%s/%s\n' \
                "$name" "$(wc -c <"$file" | tr -d '[:space:]')" "$digest" \
                "$repo" "$release" "$name" >>"$assets.next"
            mv "$assets.next" "$assets"
        done
        ;;
    *)
        printf 'unexpected gh invocation: %s\n' "$*" >&2
        exit 1
        ;;
esac
STUB
chmod 0755 "$stub_dir/gh"

upload_status=0
run_upload() {
    set +e
    PATH="$stub_dir:$PATH" \
        TMPDIR="$upload_tmp" \
        GH_STUB_STATE="$state_dir" \
        GH_STUB_CHECKSUM_LIB="$script_dir/lib/native-toolchain-checksum.sh" \
        "$upload_script" "$@" >"$output_file" 2>&1
    upload_status=$?
    set -e
}

expect_upload_failure() {
    local message="$1"
    shift

    run_upload "$@"
    if [[ "$upload_status" -eq 0 ]]; then
        cat "$output_file" >&2
        fail "upload unexpectedly succeeded: $*"
    fi
    assert_file_contains "$output_file" "$message" \
        "upload did not report '$message' for: $*"
}

expect_upload_success() {
    run_upload "$@"
    if [[ "$upload_status" -ne 0 ]]; then
        cat "$output_file" >&2
        fail "upload failed: $*"
    fi
}

upload_count() {
    if [[ -f "$gh_log" ]]; then
        grep -c '^gh <release> <upload>' "$gh_log" || true
    else
        printf '0\n'
    fi
}

run_upload --help
assert_equals 0 "$upload_status" "--help failed"
assert_file_contains "$output_file" "scripts/upload-native-toolchain.sh PLATFORM RELEASE"

expect_upload_failure "PLATFORM and RELEASE are required" android
assert_equals 2 "$upload_status" "a missing RELEASE was not a usage error"
expect_upload_failure "unknown option: --clobber" android v1 --clobber
for release in "" 1 v v1.0 v1-rc1 latest; do
    expect_upload_failure "release tags look like v1, v2 or v3" android "$release"
done
expect_upload_failure "unknown native toolchain platform: example" example v1
expect_upload_failure "the repository must be OWNER/NAME: example" \
    android v1 --repo example

detect_host
if [[ "$NATIVE_TOOLCHAIN_KONAN_HOST" == "unsupported" ]]; then
    expect_upload_failure "toolchain uploads do not support" android v1
    printf 'Native toolchain upload tests passed (unsupported host).\n'
    exit 0
fi

package_name="$(
    package_name_for \
        "$project_root/toolchains/android/android.properties" \
        "$NATIVE_TOOLCHAIN_KONAN_HOST"
)"
asset_name="$package_name.tar.gz"
checksum_name="$asset_name.sha256"
archive="$dist_dir/$asset_name"
release_api="repos/technoir-lab/kotlin-native-toolchains/releases/tags/v1"

expect_upload_failure \
    "archive not found: $archive; build it with make archive PLATFORM=android" \
    android v1 --archive-dir "$dist_dir"

# A sparse file exercises GitHub's 2 GiB asset limit without writing 2 GiB.
dd if=/dev/zero of="$archive" bs=1 count=0 seek=2147483648 2>/dev/null
expect_upload_failure \
    "$asset_name is 2147483648 bytes; GitHub release assets must be smaller than 2 GiB" \
    android v1 --archive-dir "$dist_dir"
assert_path_missing "$gh_log" "gh was called for an archive GitHub would reject"

printf 'test toolchain archive\n' >"$archive"
archive_sha256="$(sha256_file "$archive")"

touch "$state_dir/release-missing"
expect_upload_failure "cannot read release v1 of technoir-lab/kotlin-native-toolchains" \
    android v1 --archive-dir "$dist_dir"
assert_file_contains "$output_file" "gh: Not Found (HTTP 404)"
assert_file_contains "$gh_log" "gh <api> <$release_api> <--jq>"
assert_equals 0 "$(upload_count)" "an upload ran without a release"
rm -f -- "$state_dir/release-missing"

expect_upload_success android v1 --archive-dir "$dist_dir"
assert_equals 1 "$(upload_count)" "the archive was not uploaded once"
assert_file_contains_line "$gh_log" \
    "gh <release> <upload> <v1> <$asset_name> <$checksum_name> <--repo> <technoir-lab/kotlin-native-toolchains>"
assert_equals \
    "$(cat "$archive")" \
    "$(cat "$state_dir/uploaded-$asset_name")" \
    "the uploaded archive differs from the local archive"
assert_equals \
    "$archive_sha256  $asset_name" \
    "$(cat "$state_dir/uploaded-$checksum_name")" \
    "the checksum asset does not use the sha256sum format"
assert_file_contains_line "$output_file" \
    "URL: https://github.com/technoir-lab/kotlin-native-toolchains/releases/download/v1/$asset_name"
assert_file_contains_line "$output_file" "SHA-256: $archive_sha256"
[[ -z "$(ls -A "$upload_tmp")" ]] ||
    fail "the upload left temporary files behind: $(ls -A "$upload_tmp")"

expect_upload_failure \
    "release v1 already has $asset_name (pass --force to replace it)" \
    android v1 --archive-dir "$dist_dir"
assert_equals 1 "$(upload_count)" "an existing asset was replaced without --force"

expect_upload_success android v1 --archive-dir "$dist_dir" --force
assert_equals 2 "$(upload_count)" "--force did not upload the archive"
assert_file_contains_line "$gh_log" \
    "gh <release> <upload> <v1> <$asset_name> <$checksum_name> <--repo> <technoir-lab/kotlin-native-toolchains> <--clobber>"

touch "$state_dir/corrupt-upload"
expect_upload_failure \
    "GitHub reports $asset_name with digest sha256:0000000000000000000000000000000000000000000000000000000000000000; the local file has sha256:$archive_sha256; rerun with --force to replace it" \
    android v1 --archive-dir "$dist_dir" --force
rm -f -- "$state_dir/corrupt-upload"

rm -f -- "$state_dir/assets.tsv"
expect_upload_success android v2 --archive-dir "$dist_dir" --repo example/fork
assert_file_contains "$gh_log" "gh <api> <repos/example/fork/releases/tags/v2> <--jq>"
assert_file_contains "$gh_log" "<--repo> <example/fork>"
assert_file_contains_line "$output_file" \
    "URL: https://github.com/example/fork/releases/download/v2/$asset_name"

if make --no-print-directory -C "$project_root" upload PLATFORM=android RELEASE= \
    >"$output_file" 2>&1; then
    fail "make upload succeeded without RELEASE"
fi
assert_file_contains "$output_file" \
    "error: RELEASE is required; choose an existing release tag such as v1"
make --no-print-directory --dry-run -C "$project_root" \
    upload PLATFORM=android RELEASE=v1 FORCE=1 >"$output_file"
grep -Eq '^\./scripts/upload-native-toolchain\.sh "android" "v1" +--force$' "$output_file" || {
    cat "$output_file" >&2
    fail "make upload does not pass FORCE=1 as --force"
}

printf 'Native toolchain upload tests passed.\n'
