#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"

# shellcheck source=lib/native-toolchain-host.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-host.sh"
# shellcheck source=lib/native-toolchain-registry.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-registry.sh"
# shellcheck source=lib/native-toolchain-checksum.sh
# shellcheck disable=SC1091
source "$script_dir/lib/native-toolchain-checksum.sh"

readonly DEFAULT_REPOSITORY="technoir-lab/kotlin-native-toolchains"
# GitHub rejects release assets of 2 GiB or more.
readonly MAX_ASSET_SIZE=2147483648

usage() {
    cat <<'USAGE'
Usage:
  scripts/upload-native-toolchain.sh PLATFORM RELEASE [options]

Attaches the current host's PLATFORM archive and its SHA-256 file to the
existing GitHub release RELEASE, such as v1.

Options:
  --archive-dir PATH  Directory containing the archive. Defaults to build/dist.
  --repo OWNER/NAME   Repository that owns the release. Defaults to
                      technoir-lab/kotlin-native-toolchains.
  --force             Replace assets that the release already has. gh
                      deletes each one before uploading its replacement.
  -h, --help          Show this help.
USAGE
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage_error() {
    printf 'error: %s\n' "$*" >&2
    usage >&2
    exit 2
}

work_dir=""
cleanup() {
    if [[ -n "$work_dir" && -d "$work_dir" ]]; then
        rm -rf -- "$work_dir"
    fi
}
trap cleanup EXIT

archive_dir="$project_root/build/dist"
repository="$DEFAULT_REPOSITORY"
force=false
positional=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive-dir)
            [[ $# -ge 2 ]] || usage_error "--archive-dir requires a path"
            archive_dir="$2"
            shift 2
            ;;
        --repo)
            [[ $# -ge 2 ]] || usage_error "--repo requires OWNER/NAME"
            repository="$2"
            shift 2
            ;;
        --force)
            force=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            usage_error "unknown option: $1"
            ;;
        *)
            positional+=("$1")
            shift
            ;;
    esac
done
[[ ${#positional[@]} -eq 2 ]] || usage_error "PLATFORM and RELEASE are required"
platform="${positional[0]}"
release="${positional[1]}"

# The Release workflow creates releases only for tags of this form.
[[ "$release" =~ ^v[0-9]+$ ]] ||
    die "release tags look like v1, v2 or v3: ${release:-<empty>}"
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
    die "the repository must be OWNER/NAME: $repository"

descriptor="$(enabled_platform_descriptor "$project_root" "$platform")" || exit
detect_host
[[ "$NATIVE_TOOLCHAIN_KONAN_HOST" != "unsupported" ]] ||
    die "toolchain uploads do not support $NATIVE_TOOLCHAIN_HOST_OS/$NATIVE_TOOLCHAIN_HOST_ARCH hosts"
package_name="$(package_name_for "$descriptor" "$NATIVE_TOOLCHAIN_KONAN_HOST")"
asset_name="$package_name.tar.gz"
checksum_name="$asset_name.sha256"

archive="$archive_dir/$asset_name"
[[ -f "$archive" ]] ||
    die "archive not found: $archive; build it with make archive PLATFORM=$platform"
archive="$(cd "$(dirname -- "$archive")" && pwd -P)/$asset_name"
archive_size="$(wc -c <"$archive" | tr -d '[:space:]')"
((archive_size < MAX_ASSET_SIZE)) ||
    die "$asset_name is $archive_size bytes; GitHub release assets must be smaller than 2 GiB"

command -v gh >/dev/null 2>&1 ||
    die "GitHub CLI is required; install it with brew install gh, then run gh auth login"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/native-toolchain-upload.XXXXXX")"
assets_file="$work_dir/assets.tsv"

# Records one tab-separated line per release asset: name, size, digest, state,
# and download URL. The REST fields don't depend on the gh version, unlike
# gh release view, whose JSON gained the digest only in later versions.
read_release_assets() {
    gh api "repos/$repository/releases/tags/$release" \
        --jq '.assets[] | [.name, (.size | tostring), (.digest // ""), .state, .browser_download_url] | @tsv' \
        >"$assets_file"
}

asset_field() {
    local name="$1"
    local field="$2"

    awk -F '\t' -v name="$name" -v field="$field" \
        '$1 == name { print $field; exit }' "$assets_file"
}

has_asset() {
    awk -F '\t' -v name="$1" '$1 == name { found = 1 } END { exit !found }' \
        "$assets_file"
}

verify_uploaded_asset() {
    local name="$1"
    local file="$2"
    local expected_digest="sha256:$3"
    local expected_size
    local state
    local size
    local digest

    has_asset "$name" ||
        die "release $release does not list $name after the upload"
    expected_size="$(wc -c <"$file" | tr -d '[:space:]')"
    state="$(asset_field "$name" 4)"
    size="$(asset_field "$name" 2)"
    digest="$(asset_field "$name" 3)"
    [[ "$state" == "uploaded" ]] ||
        die "GitHub reports $name as $state instead of uploaded; rerun with --force to replace it"
    [[ "$size" == "$expected_size" ]] ||
        die "GitHub reports $name as $size bytes; the local file has $expected_size; rerun with --force to replace it"
    [[ "$digest" == "$expected_digest" ]] ||
        die "GitHub reports $name with digest ${digest:-<none>}; the local file has $expected_digest; rerun with --force to replace it"
}

if ! read_release_assets; then
    die "cannot read release $release of $repository. The Release workflow creates it after the $release tag is pushed; check gh auth status if the release exists"
fi
for name in "$asset_name" "$checksum_name"; do
    if has_asset "$name" && [[ "$force" != true ]]; then
        die "release $release already has $name (pass --force to replace it)"
    fi
done

printf 'Computing the SHA-256 of %s...\n' "$asset_name"
sha256="$(sha256_file "$archive")"
checksum_file="$work_dir/$checksum_name"
printf '%s  %s\n' "$sha256" "$asset_name" >"$checksum_file"

# gh reads anything after a '#' in a file argument as the asset's label, so
# upload bare asset names from the work directory instead of the paths.
ln -s "$archive" "$work_dir/$asset_name"
upload_args=(release upload "$release" "$asset_name" "$checksum_name" --repo "$repository")
if [[ "$force" == true ]]; then
    # gh deletes each existing asset before uploading its replacement.
    upload_args+=(--clobber)
fi
printf 'Uploading %s to %s release %s...\n' "$asset_name" "$repository" "$release"
(cd "$work_dir" && gh "${upload_args[@]}")

read_release_assets ||
    die "uploaded $asset_name, but cannot read release $release back to verify it"
verify_uploaded_asset "$asset_name" "$archive" "$sha256"
verify_uploaded_asset "$checksum_name" "$checksum_file" "$(sha256_file "$checksum_file")"

printf 'Uploaded %s and %s to %s release %s.\n' \
    "$asset_name" "$checksum_name" "$repository" "$release"
printf 'URL: %s\n' "$(asset_field "$asset_name" 5)"
printf 'SHA-256: %s\n' "$sha256"
