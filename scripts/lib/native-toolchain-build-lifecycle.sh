#!/usr/bin/env bash
# Shared output lifecycle for native toolchain builders.
#
# Call init_build before parsing arguments. The public state
# variables intentionally use the names already consumed by the platform
# builders: output_dir, output_parent, output_name, archive_dir, archive_path,
# archive_requested, force, staging_dir, and archive_staging.

# Declare shared state at source time so callers and static analysis can see the
# library's interface. init_build resets every value.
output_dir=""
output_parent=""
output_name=""
archive_dir=""
archive_path=""
archive_requested=false
force=false
staging_dir=""
archive_staging=""
output_prepared=false
build_value_options=()
build_value_variables=()

_build_error() {
    printf 'error: %s\n' "$*" >&2
    return 1
}

init_build() {
    output_dir="$1"
    output_parent=""
    output_name=""
    archive_dir=""
    archive_path=""
    archive_requested=false
    force=false
    staging_dir=""
    archive_staging=""
    output_prepared=false

    # Platform builders may populate these parallel arrays before calling
    # parse_build_args. Each option consumes one path value
    # and stores it in the named shell variable.
    build_value_options=()
    build_value_variables=()
}

add_build_value_option() {
    build_value_options+=("$1")
    build_value_variables+=("$2")
}

parse_build_args() {
    local usage_function="$1"
    local matched
    local variable
    local i
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output-dir)
                [[ $# -ge 2 ]] || {
                    _build_error "--output-dir requires a path"
                    return
                }
                output_dir="$2"
                shift 2
                ;;
            --archive)
                archive_requested=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            -h|--help)
                "$usage_function"
                exit 0
                ;;
            *)
                matched=false
                for ((i = 0; i < ${#build_value_options[@]}; i++)); do
                    if [[ "$1" == "${build_value_options[$i]}" ]]; then
                        [[ $# -ge 2 ]] || {
                            _build_error "$1 requires a path"
                            return
                        }
                        variable="${build_value_variables[$i]}"
                        printf -v "$variable" '%s' "$2"
                        shift 2
                        matched=true
                        break
                    fi
                done
                [[ "$matched" == true ]] || {
                    _build_error "unknown option: $1"
                    return
                }
                ;;
        esac
    done
}

prepare_output() {
    local project_root="$1"
    local protected_root="${2:-}"
    local protected_description="${3:-source}"

    project_root="$(cd "$project_root" && pwd -P)"
    if [[ -n "$protected_root" ]]; then
        protected_root="$(cd "$protected_root" && pwd -P)"
    fi

    [[ -n "$output_dir" ]] || {
        _build_error \
            "refusing unsafe output path: the path is empty"
        return
    }
    [[ "$output_dir" != *";"* && ! "$output_dir" =~ [[:space:]] ]] || {
        _build_error \
            "the output path cannot contain whitespace or semicolons"
        return
    }

    output_parent="$(dirname -- "$output_dir")"
    output_name="$(basename -- "$output_dir")"
    [[ -n "$output_name" && "$output_name" != "." &&
        "$output_name" != ".." && "$output_name" != "/" ]] || {
        _build_error "refusing unsafe output path: $output_dir"
        return
    }

    mkdir -p -- "$output_parent"
    output_parent="$(cd "$output_parent" && pwd -P)"
    output_dir="$output_parent/$output_name"
    archive_dir="$project_root/build/dist"
    archive_path="$archive_dir/$output_name.tar.gz"

    [[ "$output_dir" != "/" && "$output_dir" != "$project_root" ]] || {
        _build_error "refusing unsafe output path: $output_dir"
        return
    }
    if [[ -n "$protected_root" &&
        ( "$output_dir/" == "$protected_root/"* ||
            "$protected_root/" == "$output_dir/"* ) ]]; then
        _build_error \
            "the output and $protected_description directories cannot contain one another"
        return
    fi

    if [[ -e "$output_dir" && "$force" != true ]]; then
        _build_error \
            "output already exists (pass --force to replace it): $output_dir"
        return
    fi
    if [[ "$archive_requested" == true ]]; then
        mkdir -p -- "$archive_dir"
        archive_dir="$(cd "$archive_dir" && pwd -P)"
        archive_path="$archive_dir/$output_name.tar.gz"
        if [[ -e "$archive_path" && "$force" != true ]]; then
            _build_error \
                "archive already exists (pass --force to replace it): $archive_path"
            return
        fi
    fi

    output_prepared=true
}

create_staging() {
    local mode="$1"

    [[ "$output_prepared" == true ]] || {
        _build_error \
            "cannot create staging directory before preparing the output"
        return
    }
    [[ -z "$staging_dir" ]] || {
        _build_error "a staging directory already exists: $staging_dir"
        return
    }

    staging_dir="$(mktemp -d "$output_parent/.${output_name}.tmp.XXXXXX")"
    chmod "$mode" "$staging_dir"
}

publish_output() {
    local description="$1"

    [[ "$output_prepared" == true &&
        -n "$staging_dir" && -d "$staging_dir" ]] || {
        _build_error "cannot publish without a staging directory"
        return
    }

    if [[ -e "$output_dir" ]]; then
        rm -rf -- "$output_dir"
    fi
    mv "$staging_dir" "$output_dir"
    staging_dir=""
    printf '%s: %s\n' "$description" "$output_dir"
}

publish_archive() {
    [[ "$archive_requested" == true ]] || return 0
    [[ "$output_prepared" == true &&
        -d "$output_dir" ]] || {
        _build_error "cannot archive before publishing the output"
        return
    }

    archive_staging="$archive_dir/.${output_name}.tar.gz.tmp.$$"
    create_reproducible_tar_gz \
        "$output_parent" \
        "$output_name" \
        "$archive_staging"
    if [[ -e "$archive_path" ]]; then
        rm -f -- "$archive_path"
    fi
    mv "$archive_staging" "$archive_path"
    archive_staging=""
    printf 'Created archive: %s\n' "$archive_path"
}

cleanup_build() {
    if [[ -n "$staging_dir" && -d "$staging_dir" ]]; then
        rm -rf -- "$staging_dir"
    fi
    if [[ -n "$archive_staging" && -f "$archive_staging" ]]; then
        rm -f -- "$archive_staging"
    fi
}
