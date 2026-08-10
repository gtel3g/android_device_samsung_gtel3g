#!/usr/bin/env bash

set -euo pipefail

DEVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$DEVICE_DIR/../../.." && pwd)"

apply_series() {
    local project="$1"
    local directory="$2"
    local patch
    local patches=()

    shopt -s nullglob
    patches=("$DEVICE_DIR/patches/$directory"/*.patch)
    shopt -u nullglob

    for patch in "${patches[@]}"; do
        echo "==> $project: $(basename "$patch")"

        if git -C "$TOP/$project" apply \
            --reverse --check "$patch" >/dev/null 2>&1; then
            echo "    already applied"
        elif git -C "$TOP/$project" apply \
            --check "$patch" >/dev/null 2>&1; then
            git -C "$TOP/$project" am --3way "$patch"
        else
            echo "ERROR: patch does not apply cleanly"
            echo "Project: $project"
            echo "Patch:   $patch"
            exit 1
        fi
    done
}

apply_series frameworks/native frameworks_native
apply_series hardware/interfaces hardware_interfaces


echo "All gtel3g source patches applied."
