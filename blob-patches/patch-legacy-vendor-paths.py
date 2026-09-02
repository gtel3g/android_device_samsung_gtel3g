#!/usr/bin/env python3

from pathlib import Path
import sys

if len(sys.argv) != 3:
    raise SystemExit(
        f"usage: {sys.argv[0]} LOGICAL_PATH BLOB"
    )

logical = sys.argv[1]
path = Path(sys.argv[2])

if not path.is_file():
    raise SystemExit(f"ERROR: blob not found: {path}")

PATCHES = {
    "bin/engpc": [
        (
            b"/system/lib/hw/gps.default.so",
            b"/vendor/lib/hw/gps.default.so",
            1,
            "gps HAL path",
        ),
    ],

    "bin/gpsd": [
        (
            b"/system/etc/gps.conf",
            b"/vendor/etc/gps.conf",
            2,
            "gps.conf paths",
        ),
    ],

    "lib/hw/gps.default.so": [
        (
            b"/system/bin/gpsd",
            b"/vendor/bin/gpsd",
            1,
            "gpsd executable path",
        ),
        (
            b"/system/etc/gps.xml",
            b"/vendor/etc/gps.xml",
            1,
            "gps.xml path",
        ),
    ],
}

if logical not in PATCHES:
    raise SystemExit(f"ERROR: unsupported blob: {logical}")

data = path.read_bytes()
changed = False

for old, new, expected, description in PATCHES[logical]:
    if len(old) != len(new):
        raise SystemExit(
            f"ERROR: size-changing replacement for {description}"
        )

    old_count = data.count(old)
    new_count = data.count(new)

    if old_count == expected and new_count == 0:
        print(
            f"  patch: {description}: "
            f"{old_count} occurrence(s)"
        )
        data = data.replace(old, new)
        changed = True

    elif old_count == 0 and new_count == expected:
        print(f"  already patched: {description}")

    elif old_count + new_count == expected and old_count:
        print(
            f"  completing partial patch: {description}: "
            f"old={old_count} new={new_count}"
        )
        data = data.replace(old, new)
        changed = True

    else:
        raise SystemExit(
            f"ERROR: unexpected state for {logical}: "
            f"{description}: "
            f"old={old_count} new={new_count} "
            f"expected={expected}"
        )

if changed:
    path.write_bytes(data)

# Validate final state.
data = path.read_bytes()

for old, new, expected, description in PATCHES[logical]:
    if data.count(old) != 0 or data.count(new) != expected:
        raise SystemExit(
            f"ERROR: validation failed: "
            f"{logical}: {description}"
        )

print(f"  {logical}: vendor path fixups OK")
