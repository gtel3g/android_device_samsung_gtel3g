#!/bin/bash
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

DEVICE=gtel3g
VENDOR=samsung

MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then
    MY_DIR="${PWD}"
fi

LINEAGE_ROOT="${MY_DIR}/../../.."

HELPER="${LINEAGE_ROOT}/vendor/lineage/build/tools/extract_utils.sh"

if [ ! -f "${HELPER}" ]; then
    echo "Unable to find extract_utils.sh at ${HELPER}"
    exit 1
fi

. "${HELPER}"


find_patchelf()
{
    if command -v patchelf >/dev/null 2>&1; then
        command -v patchelf
        return 0
    fi

    local TOOL

    TOOL="$(
        find "${LINEAGE_ROOT}/prebuilts" \
            -type f \
            -name 'patchelf' \
            -perm -111 \
            -print \
            -quit \
            2>/dev/null
    )"

    if [ -n "${TOOL}" ]; then
        echo "${TOOL}"
        return 0
    fi

    echo "ERROR: patchelf not found" >&2
    return 1
}


has_needed()
{
    local FILE="${1}"
    local LIB="${2}"

    LC_ALL=C readelf -d "${FILE}" 2>/dev/null |
        grep -F 'NEEDED' |
        grep -Fq "[${LIB}]"
}


must()
{
    "$@"
    local RC=$?

    if [ "${RC}" -ne 0 ]; then
        echo "ERROR: command failed (${RC}): $*" >&2
        exit "${RC}"
    fi
}


blob_fixup()
{
    local BLOB="${1}"
    local FILE="${2}"

    case "${BLOB}" in

        lib/egl/libGLES_mali.so)
            #
            # T561 stock Mali r403:
            #
            #   /system/lib/libboost.so
            #       -> /vendor/lib/libboost.so
            #
            #   framebuffer numBuffers
            #       -> force 3
            #
            must python3 \
                "${MY_DIR}/blob-patches/patch-mali.py" \
                "${FILE}"
            ;;


        lib/hw/camera.vendor.sc8830.so)
            local PATCHELF_BIN
            local HAD_SKIA=false

            PATCHELF_BIN="$(find_patchelf)" || exit 1

            echo \
                "  camera: using $("${PATCHELF_BIN}" --version)"

            #
            # Stock T561 camera HAL links against libskia.so.
            # Android 9 vendor HAL does not need it.
            #
            if has_needed "${FILE}" "libskia.so"; then
                HAD_SKIA=true

                echo \
                    "  camera: removing libskia.so"

                must "${PATCHELF_BIN}" \
                    --remove-needed libskia.so \
                    "${FILE}"
            else
                echo \
                    "  camera: libskia.so already removed"
            fi

            #
            # Stock T561 camera HAL does not contain a direct
            # MemoryHeapIon DT_NEEDED entry.
            #
            # Add our private legacy implementation.
            #
            # Also support the intermediate historical state
            # which used libmemoryheapion.so directly.
            #
            if has_needed \
                    "${FILE}" \
                    "libmemoryheapion_sprd_legacy.so"; then

                echo \
                    "  camera: legacy MemoryHeapIon already present"

            elif has_needed \
                    "${FILE}" \
                    "libmemoryheapion.so"; then

                echo \
                    "  camera: replacing libmemoryheapion.so"

                must "${PATCHELF_BIN}" \
                    --replace-needed \
                    libmemoryheapion.so \
                    libmemoryheapion_sprd_legacy.so \
                    "${FILE}"

            elif [ "${HAD_SKIA}" = true ]; then

                echo \
                    "  camera: adding legacy MemoryHeapIon dependency"

                must "${PATCHELF_BIN}" \
                    --add-needed \
                    libmemoryheapion_sprd_legacy.so \
                    "${FILE}"

            else
                echo \
                    "ERROR: unexpected camera MemoryHeapIon state" \
                    >&2

                LC_ALL=C readelf -d "${FILE}" |
                    grep NEEDED >&2 || true

                exit 1
            fi

            #
            # Force the two DCAM preview buffers used by the
            # legacy raw recording path.
            #
            must python3 \
                "${MY_DIR}/blob-patches/patch-camera.py" \
                "${FILE}"

            #
            # Final validation.
            #
            if has_needed "${FILE}" "libskia.so"; then
                echo \
                    "ERROR: camera still depends on libskia.so" \
                    >&2

                exit 1
            fi

            if ! has_needed \
                    "${FILE}" \
                    "libmemoryheapion_sprd_legacy.so"; then

                echo \
                    "ERROR: camera legacy MemoryHeapIon dependency missing" \
                    >&2

                exit 1
            fi

            echo \
                "  camera: ELF compatibility fixups OK"
            ;;


        bin/engpc|\
        bin/gpsd|\
        lib/hw/gps.default.so)

            must python3 \
                "${MY_DIR}/blob-patches/patch-legacy-vendor-paths.py" \
                "${BLOB}" \
                "${FILE}"
            ;;

    esac
}


#
# Arguments:
#
#   ./extract-files.sh
#       extract from a stock device through adb
#
#   ./extract-files.sh /path/to/system-dump
#       extract from an unpacked stock system
#
#   ./extract-files.sh /path/to/system-dump --kang
#
#   ./extract-files.sh --no-cleanup /path/to/system-dump
#

SRC=adb
CLEAN_VENDOR=true
EXTRACT_ARGS=()

while [ "$#" -gt 0 ]; do
    case "${1}" in

        -n|--no-cleanup)
            CLEAN_VENDOR=false
            ;;

        -k|--kang)
            EXTRACT_ARGS+=("${1}")
            ;;

        -s|--section)
            if [ "$#" -lt 2 ]; then
                echo "ERROR: --section requires a section name"
                exit 1
            fi

            EXTRACT_ARGS+=("${1}" "${2}")
            CLEAN_VENDOR=false
            shift
            ;;

        -*)
            echo "ERROR: unknown option: ${1}"
            exit 1
            ;;

        *)
            SRC="${1}"
            ;;

    esac

    shift
done


setup_vendor \
    "${DEVICE}" \
    "${VENDOR}" \
    "${LINEAGE_ROOT}" \
    false \
    "${CLEAN_VENDOR}"


extract \
    "${MY_DIR}/proprietary-files.txt" \
    "${SRC}" \
    "${EXTRACT_ARGS[@]}"


"${MY_DIR}/setup-makefiles.sh"
