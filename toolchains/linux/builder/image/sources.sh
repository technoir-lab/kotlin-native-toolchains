#!/usr/bin/env bash
# Shared helpers for the Linux builder's pinned sources and header list.
#
# The builder image (prepare.sh), the container build (build-toolchains.sh),
# the host-side artifact checks (scripts/build-linux-toolchain.sh), and the
# tests source this file, so sources.lock and graphics-headers.txt are read
# the same way everywhere. sources.lock documents its own format.
#
# The helpers print `error:` messages and return non-zero instead of exiting.

_linux_sources_error() {
    printf 'error: %s\n' "$*" >&2
    return 1
}

_linux_sources_relative_path() {
    local path="$1"
    local allowed="$2"

    [[ "$path" =~ $allowed && "/$path/" != */./* && "/$path/" != */../* ]]
}

# Prints every source in a lock file as `name version licenses url sha512`,
# with {version} expanded in the URL. Validates the whole file first and
# prints nothing if any line is invalid.
source_lock_entries() {
    local lock="$1"
    local skip='^[[:space:]]*(#.*)?$'
    local valid_name='^[a-z0-9]+(-[a-z0-9]+)*$'
    local valid_version='^[0-9A-Za-z][0-9A-Za-z._+-]*$'
    local valid_license='^[A-Za-z0-9._+*-]+(/[A-Za-z0-9._+*-]+)*$'
    local valid_sha512='^[0-9a-f]{128}$'
    local placeholder='{version}'
    local entries=""
    local names=" "
    local line_number=0
    local line
    local location
    local name
    local version
    local licenses
    local url
    local sha512
    local extra
    local pattern
    local patterns

    [[ -f "$lock" ]] || {
        _linux_sources_error "source lock not found: $lock"
        return
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        [[ "$line" =~ $skip ]] && continue
        location="$lock:$line_number"
        read -r name version licenses url sha512 extra <<<"$line"
        [[ -n "$sha512" && -z "$extra" ]] || {
            _linux_sources_error \
                "$location: expected name, version, licenses, url, and sha512"
            return
        }
        [[ "$name" =~ $valid_name ]] || {
            _linux_sources_error "$location: invalid source name: $name"
            return
        }
        [[ "$names" != *" $name "* ]] || {
            _linux_sources_error "$location: duplicate source: $name"
            return
        }
        [[ "$version" =~ $valid_version ]] || {
            _linux_sources_error "$location: invalid $name version: $version"
            return
        }
        [[ "$licenses" != ,* && "$licenses" != *, && "$licenses" != *,,* ]] || {
            _linux_sources_error "$location: empty $name license pattern"
            return
        }
        IFS=, read -r -a patterns <<<"$licenses"
        for pattern in "${patterns[@]}"; do
            _linux_sources_relative_path "$pattern" "$valid_license" || {
                _linux_sources_error \
                    "$location: invalid $name license pattern: $pattern"
                return
            }
        done
        [[ "$url" == https://* && "$url" == *"$placeholder"* ]] || {
            _linux_sources_error \
                "$location: the $name URL must use https and contain $placeholder"
            return
        }
        [[ "$sha512" =~ $valid_sha512 ]] || {
            _linux_sources_error "$location: invalid $name SHA-512 digest"
            return
        }
        names+="$name "
        entries+="$name $version $licenses ${url//"$placeholder"/$version} $sha512"$'\n'
    done <"$lock"
    printf '%s' "$entries"
}

# Prints the version of one source.
source_version() {
    local lock="$1"
    local requested="$2"
    local entries
    local name
    local version

    entries="$(source_lock_entries "$lock")" || return
    while read -r name version _; do
        if [[ "$name" == "$requested" ]]; then
            printf '%s\n' "$version"
            return 0
        fi
    done <<<"$entries"
    _linux_sources_error "$lock does not declare $requested"
}

# Prints a `<name>.version=<version>` metadata line for every source, in lock
# order, with hyphens in the name written as dots.
source_version_properties() {
    local lock="$1"
    local entries
    local name
    local version

    entries="$(source_lock_entries "$lock")" || return
    while read -r name version _; do
        [[ -n "$name" ]] || continue
        printf '%s.version=%s\n' "${name//-/.}" "$version"
    done <<<"$entries"
}

# Prints the non-empty regular files under root that match a license pattern,
# relative to root. Fails when nothing matches.
matching_license_files() {
    local root="$1"
    local pattern="$2"
    local candidates
    local candidate
    local status=1

    candidates="$(cd "$root" 2>/dev/null && compgen -G "$pattern")" || true
    while IFS= read -r candidate; do
        if [[ -n "$candidate" && -f "$root/$candidate" && -s "$root/$candidate" ]]; then
            printf '%s\n' "$candidate"
            status=0
        fi
    done <<<"$candidates"
    return "$status"
}

# Copies the license files of every source from sources_root/<name>/ to
# license_root/<name>/, keeping their paths relative to the source root.
collect_source_licenses() {
    local lock="$1"
    local sources_root="$2"
    local license_root="$3"
    local entries
    local name
    local licenses
    local patterns
    local pattern
    local files
    local file

    entries="$(source_lock_entries "$lock")" || return
    while read -r name _ licenses _ <&3; do
        [[ -n "$name" ]] || continue
        IFS=, read -r -a patterns <<<"$licenses"
        for pattern in "${patterns[@]}"; do
            files="$(matching_license_files "$sources_root/$name" "$pattern")" || {
                _linux_sources_error \
                    "$name has no license file matching $pattern"
                return
            }
            while IFS= read -r file; do
                mkdir -p "$license_root/$name/$(dirname "$file")"
                cp "$sources_root/$name/$file" "$license_root/$name/$file"
            done <<<"$files"
        done
    done 3<<<"$entries"
}

# Fails unless every license pattern of every source matches a non-empty
# regular file under license_root/<name>/.
require_source_licenses() {
    local lock="$1"
    local license_root="$2"
    local description="$3"
    local entries
    local name
    local licenses
    local patterns
    local pattern

    entries="$(source_lock_entries "$lock")" || return
    while read -r name _ licenses _ <&3; do
        [[ -n "$name" ]] || continue
        IFS=, read -r -a patterns <<<"$licenses"
        for pattern in "${patterns[@]}"; do
            matching_license_files "$license_root/$name" "$pattern" >/dev/null || {
                _linux_sources_error \
                    "$description has no $name license file matching $pattern"
                return
            }
        done
    done 3<<<"$entries"
}

# Prints the relative paths listed in a file such as graphics-headers.txt,
# skipping blank lines and # comments.
list_file_entries() {
    local file="$1"
    local skip='^[[:space:]]*(#.*)?$'
    local valid_path='^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$'
    local entries=""
    local line_number=0
    local line

    [[ -f "$file" ]] || {
        _linux_sources_error "list file not found: $file"
        return
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        [[ "$line" =~ $skip ]] && continue
        _linux_sources_relative_path "$line" "$valid_path" || {
            _linux_sources_error "$file:$line_number: invalid path: $line"
            return
        }
        entries+="$line"$'\n'
    done <"$file"
    printf '%s' "$entries"
}

# Fails unless every path in list_file is a regular file under root.
require_listed_files() {
    local root="$1"
    local list_file="$2"
    local description="$3"
    local entries
    local entry

    entries="$(list_file_entries "$list_file")" || return
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        [[ -f "$root/$entry" ]] || {
            _linux_sources_error "$description is missing $entry"
            return
        }
    done <<<"$entries"
}
