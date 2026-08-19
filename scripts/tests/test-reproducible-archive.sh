#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_dir="$(cd "$test_dir/.." && pwd -P)"

# shellcheck source=../lib/reproducible-archive.sh
# shellcheck disable=SC1091
source "$script_dir/lib/reproducible-archive.sh"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/native-toolchain-reproducibility.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

first_parent="$test_root/first-location"
second_parent="$test_root/second-location"
long_dir="$(printf 'long-directory-%.0s' {1..8})"
mkdir -p \
    "$first_parent/artifact/dir" \
    "$first_parent/artifact/$long_dir" \
    "$second_parent/artifact/dir" \
    "$second_parent/artifact/$long_dir"

# Create identical content in different orders and give it different mtimes.
printf 'beta\n' >"$first_parent/artifact/dir/b.txt"
printf 'alpha\n' >"$first_parent/artifact/a.txt"
ln -s "dir/b.txt" "$first_parent/artifact/link"
printf 'hard link payload\n' >"$first_parent/artifact/$long_dir/original-tool"
ln \
    "$first_parent/artifact/$long_dir/original-tool" \
    "$first_parent/artifact/z-hard-link"

printf 'alpha\n' >"$second_parent/artifact/a.txt"
ln -s "dir/b.txt" "$second_parent/artifact/link"
printf 'beta\n' >"$second_parent/artifact/dir/b.txt"
printf 'hard link payload\n' >"$second_parent/artifact/$long_dir/original-tool"
ln \
    "$second_parent/artifact/$long_dir/original-tool" \
    "$second_parent/artifact/z-hard-link"

TZ=UTC find "$first_parent/artifact" -exec touch -h -t 201001020304.05 {} +
TZ=UTC find "$second_parent/artifact" -exec touch -h -t 202506070809.10 {} +

normalize_tree_metadata "$first_parent/artifact"
normalize_tree_metadata "$second_parent/artifact"

first_archive="$test_root/first.tar.gz"
second_archive="$test_root/second.tar.gz"
create_reproducible_tar_gz \
    "$first_parent" "artifact" "$first_archive"
create_reproducible_tar_gz \
    "$second_parent" "artifact" "$second_archive"

cmp -s "$first_archive" "$second_archive" || {
    printf 'error: archives differ across source paths, creation orders, or mtimes\n' >&2
    exit 1
}

gzip_mtime="$(od -An -tx1 -j4 -N4 "$first_archive" | tr -d '[:space:]')"
[[ "$gzip_mtime" == "00000000" ]] || {
    printf 'error: gzip header contains a timestamp: %s\n' "$gzip_mtime" >&2
    exit 1
}

expected_order="$(printf '%s\n' \
    "artifact/" \
    "artifact/a.txt" \
    "artifact/dir/" \
    "artifact/dir/b.txt" \
    "artifact/link" \
    "artifact/$long_dir/" \
    "artifact/$long_dir/original-tool" \
    "artifact/z-hard-link")"
actual_order="$(tar -tzf "$first_archive")"
[[ "$actual_order" == "$expected_order" ]] || {
    printf 'error: archive entries are not in canonical order\n' >&2
    printf 'expected:\n%s\nactual:\n%s\n' "$expected_order" "$actual_order" >&2
    exit 1
}

if tar --numeric-owner -tvzf "$first_archive" |
    awk '$2 == "0/0" || ($3 == "0" && $4 == "0") { next } { exit 1 }'; then
    :
else
    printf 'error: archive owner metadata is not normalized to uid/gid 0\n' >&2
    exit 1
fi

extracted="$test_root/extracted"
mkdir "$extracted"
tar -xzf "$first_archive" -C "$extracted"
[[ \
    "$extracted/artifact/$long_dir/original-tool" \
    -ef "$extracted/artifact/z-hard-link" \
]] || {
    printf 'error: archive did not preserve a hard link with a long target\n' >&2
    exit 1
}
while IFS= read -r path; do
    if stat -f '%m' "$path" >/dev/null 2>&1; then
        mtime="$(stat -f '%m' "$path")"
    else
        mtime="$(stat -c '%Y' "$path")"
    fi
    [[ "$mtime" == "946684800" ]] || {
        printf 'error: archive timestamp is not normalized for %s: %s\n' \
            "$path" "$mtime" >&2
        exit 1
    }
done < <(find "$extracted/artifact" -print)

printf 'Reproducible native toolchain archive tests passed.\n'
