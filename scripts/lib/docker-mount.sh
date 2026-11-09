#!/usr/bin/env bash
# Helpers for Docker's comma-separated --mount syntax.

quote_docker_mount_field() {
    local field="$1"

    # Docker parses --mount with CSV rules. Quote the whole key=value field so
    # commas in a bind source stay in the value, and double embedded quotes.
    field="${field//\"/\"\"}"
    printf '"%s"' "$field"
}
