#!/usr/bin/env bash
# Shared platform descriptor lookup and dispatch.

read_descriptor_property() {
    local descriptor="$1"
    local key="$2"

    awk -F= -v requested_key="$key" '
        $1 == requested_key {
            sub(/^[^=]*=/, "")
            print
            exit
        }
    ' "$descriptor"
}

_package_coordinates() {
    local descriptor="$1"
    local konan_host="$2"
    local separator="$3"
    local namespace
    local role
    local revision
    local target_family
    local component

    namespace="$(read_descriptor_property "$descriptor" "package.namespace")"
    role="$(read_descriptor_property "$descriptor" "package.role")"
    revision="$(read_descriptor_property "$descriptor" "package.revision")"
    target_family="$(read_descriptor_property "$descriptor" "package.target.family")"

    for component in "$namespace" "$role" "$revision" "$konan_host" "$target_family"; do
        case "$component" in
            ''|*[!a-z0-9._-]*)
                printf 'error: invalid native toolchain package component: %s\n' \
                    "${component:-<empty>}" >&2
                return 4
                ;;
        esac
        case "$component" in
            [a-z0-9]*) ;;
            *)
                printf 'error: native toolchain package component must start with a letter or digit: %s\n' \
                    "$component" >&2
                return 4
                ;;
        esac
    done

    printf '%s%s%s%s%s%s%s%s%s\n' \
        "$namespace" "$separator" \
        "$role" "$separator" \
        "$revision" "$separator" \
        "$konan_host" "$separator" \
        "$target_family"
}

package_name_for() {
    _package_coordinates "$1" "$2" "-"
}

artifact_identity_for() {
    _package_coordinates "$1" "$2" ":"
}

write_manifest_header() {
    local manifest_descriptor="$1"
    local manifest_package_name="$2"
    local manifest_artifact_identity="$3"
    local manifest_host_os="$4"
    local manifest_host_arch="$5"
    local manifest_konan_host="$6"
    local manifest_host_tag="$7"

    cat <<EOF
format.version=1
artifact.platform=$(read_descriptor_property "$manifest_descriptor" "platform.id")
artifact.layout.version=1
artifact.package.namespace=$(read_descriptor_property "$manifest_descriptor" "package.namespace")
artifact.package.role=$(read_descriptor_property "$manifest_descriptor" "package.role")
artifact.package.revision=$(read_descriptor_property "$manifest_descriptor" "package.revision")
artifact.package.host=$manifest_konan_host
artifact.package.target.family=$(read_descriptor_property "$manifest_descriptor" "package.target.family")
artifact.package.name=$manifest_package_name
artifact.identity=$manifest_artifact_identity
host.os=$manifest_host_os
host.arch=$manifest_host_arch
host.konan=$manifest_konan_host
host.tag=$manifest_host_tag
konan.targets=$(read_descriptor_property "$manifest_descriptor" "konan.targets")
EOF
}

print_platforms() {
    local registry_dir="$1"
    local descriptor
    local platform
    local status
    local targets

    for descriptor in "$registry_dir"/*/*.properties; do
        [[ -f "$descriptor" ]] || continue
        platform="$(read_descriptor_property "$descriptor" "platform.id")"
        status="$(read_descriptor_property "$descriptor" "platform.status")"
        targets="$(read_descriptor_property "$descriptor" "konan.targets")"
        printf '  %-8s %-12s %s\n' "$platform" "$status" "$targets"
    done
}

# Prints the descriptor of an enabled platform, or reports why the platform
# cannot be used.
enabled_platform_descriptor() {
    local project_root="$1"
    local platform="$2"

    case "$platform" in
        *[!a-z0-9_-]*|'')
            printf 'error: invalid platform id: %s\n' "$platform" >&2
            return 2
            ;;
    esac

    local descriptor="$project_root/toolchains/$platform/$platform.properties"
    if [[ ! -f "$descriptor" ]]; then
        printf 'error: unknown native toolchain platform: %s\n' "$platform" >&2
        print_platforms "$project_root/toolchains" >&2
        return 2
    fi

    local status
    local targets
    local schema_version
    local descriptor_platform
    schema_version="$(read_descriptor_property "$descriptor" "schema.version")"
    descriptor_platform="$(read_descriptor_property "$descriptor" "platform.id")"
    status="$(read_descriptor_property "$descriptor" "platform.status")"
    targets="$(read_descriptor_property "$descriptor" "konan.targets")"

    if [[ "$schema_version" != "1" || "$descriptor_platform" != "$platform" ]]; then
        printf 'error: invalid platform descriptor: %s\n' "$descriptor" >&2
        return 4
    fi

    if [[ "$status" != "enabled" ]]; then
        printf 'error: platform %s is a %s; targets are not enabled: %s\n' \
            "$platform" "${status:-placeholder}" "${targets:-unspecified}" >&2
        printf 'See %s and toolchains/README.md.\n' "$descriptor" >&2
        return 3
    fi

    printf '%s\n' "$descriptor"
}

dispatch_platform() {
    local project_root="$1"
    local platform="$2"
    local entrypoint_key="$3"
    shift 3

    local descriptor
    local entrypoint
    descriptor="$(enabled_platform_descriptor "$project_root" "$platform")" || return
    entrypoint="$(read_descriptor_property "$descriptor" "$entrypoint_key")"

    if [[ -z "$entrypoint" || ! -x "$project_root/$entrypoint" ]]; then
        printf 'error: enabled platform %s has no executable %s entry point\n' \
            "$platform" "$entrypoint_key" >&2
        return 4
    fi

    exec "$project_root/$entrypoint" "$@"
}
