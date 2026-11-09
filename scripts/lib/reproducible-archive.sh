#!/usr/bin/env bash
# Deterministic metadata and tar/gzip creation shared by platform builders.

normalize_tree_metadata() {
    local artifact_root="$1"

    [[ -d "$artifact_root" ]] || {
        printf 'error: artifact root does not exist: %s\n' "$artifact_root" >&2
        return 2
    }

    # A fixed UTC timestamp avoids source-install and build-time differences.
    TZ=UTC find "$artifact_root" -exec touch -h -t 200001010000.00 {} +
}

create_reproducible_tar_gz() {
    local source_parent="$1"
    local source_name="$2"
    local destination="$3"
    local tar_version
    local destination_parent
    local destination_name
    local source_root
    local -a tar_options

    case "$source_name" in
        ''|.|..|*/*|*\\*)
            printf 'error: archive source name must be one directory component: %s\n' \
                "$source_name" >&2
            return 2
            ;;
    esac
    [[ -d "$source_parent/$source_name" ]] || {
        printf 'error: archive source does not exist: %s/%s\n' \
            "$source_parent" "$source_name" >&2
        return 2
    }

    source_parent="$(cd "$source_parent" && pwd -P)"
    source_root="$source_parent/$source_name"
    destination_parent="$(dirname "$destination")"
    destination_name="$(basename "$destination")"
    [[ -d "$destination_parent" ]] || {
        printf 'error: archive destination parent does not exist: %s\n' \
            "$destination_parent" >&2
        return 2
    }
    destination_parent="$(cd "$destination_parent" && pwd -P)"
    destination="$destination_parent/$destination_name"
    if [[ "$destination" == "$source_root" || "$destination" == "$source_root/"* ]]; then
        printf 'error: archive destination cannot be inside its source: %s\n' \
            "$destination" >&2
        return 2
    fi

    tar_version="$(tar --version 2>&1 | head -n 1)"
    # Pax extensions are required for link targets beyond ustar's 100-byte
    # limit. Avoid volatile atime/ctime pax keys to keep output reproducible.
    case "$tar_version" in
        *bsdtar*)
            tar_options=(
                -c -f -
                --format paxr
                --uid 0 --gid 0
                --uname root --gname root
                --no-xattrs --no-acls --no-fflags
            )
            ;;
        *"GNU tar"*)
            tar_options=(
                --create --file=-
                --format=pax
                --pax-option="delete=atime,delete=ctime"
                --owner=0 --group=0 --numeric-owner
                --no-xattrs --no-acls
            )
            ;;
        *)
            printf 'error: reproducible archives require bsdtar or GNU tar; found: %s\n' \
                "$tar_version" >&2
            return 3
            ;;
    esac

    (
        set -o pipefail
        cd "$source_parent" || exit
        COPYFILE_DISABLE=1 LC_ALL=C find "$source_name" -print0 |
            LC_ALL=C sort -z |
            COPYFILE_DISABLE=1 tar \
                "${tar_options[@]}" \
                --null \
                --no-recursion \
                -T - |
            gzip -n -9 >"$destination"
    )
}
