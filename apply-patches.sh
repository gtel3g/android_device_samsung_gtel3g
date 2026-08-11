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
            git -C "$TOP/$project" apply "$patch"
        else
            echo "ERROR: patch does not apply cleanly"
            echo "Project: $project"
            echo "Patch:   $patch"
            exit 1
        fi
    done
}

apply_series bionic bionic
apply_series frameworks/base frameworks_base
apply_series frameworks/native frameworks_native
apply_series hardware/interfaces hardware_interfaces
apply_series packages/apps/Settings packages_apps_Settings
apply_series packages/providers/MediaProvider packages_providers_MediaProvider

echo "All gtel3g source patches applied."
