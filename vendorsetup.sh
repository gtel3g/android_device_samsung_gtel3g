#!/usr/bin/env bash

DEVICE_PATH="${BASH_SOURCE[0]%/*}"

if [ -x "$DEVICE_PATH/apply-patches.sh" ]; then
    "$DEVICE_PATH/apply-patches.sh"
fi
