#!/usr/bin/env python3

from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit(
        f"usage: {sys.argv[0]} CAMERA_BLOB"
    )

path = Path(sys.argv[1])

if not path.is_file():
    raise SystemExit(f"ERROR: blob not found: {path}")

PATCHES = [
    (
        bytes.fromhex(
            "52 84 f8 94 "
            "52 84 f8 95 "
            "52 c4 f8 98 12 "
            "c4 f8 9c 12 "
            "c4 f8 c0 12 "
            "84 f8 96 52 "
            "39 46 "
            "84 f8 97 52 "
            "c4 f8"
        ),
        bytes.fromhex(
            "52 84 f8 94 "
            "52 84 f8 95 "
            "52 c4 f8 98 12 "
            "c4 f8 9c 52 "
            "c4 f8 c0 12 "
            "84 f8 96 52 "
            "39 46 "
            "84 f8 97 52 "
            "c4 f8"
        ),
        "first DCAM preview buffer",
    ),

    (
        bytes.fromhex(
            "72 86 f8 94 "
            "72 86 f8 95 "
            "72 c6 f8 98 22 "
            "c6 f8 9c 22 "
            "c6 f8 c0 22 "
            "4c 4a "
            "7c 44 "
            "7a 44 "
            "43 46 "
            "04 20 "
            "21 46"
        ),
        bytes.fromhex(
            "72 86 f8 94 "
            "72 86 f8 95 "
            "72 c6 f8 98 22 "
            "c6 f8 9c 72 "
            "c6 f8 c0 22 "
            "4c 4a "
            "7c 44 "
            "7a 44 "
            "43 46 "
            "04 20 "
            "21 46"
        ),
        "second DCAM preview buffer",
    ),
]

data = path.read_bytes()
changed = False

for old, new, description in PATCHES:
    old_count = data.count(old)
    new_count = data.count(new)

    if old_count == 1 and new_count == 0:
        print(f"  camera: patching {description}")
        data = data.replace(old, new, 1)
        changed = True

    elif old_count == 0 and new_count == 1:
        print(f"  camera: already patched: {description}")

    else:
        raise SystemExit(
            f"ERROR: unexpected camera state for {description}: "
            f"old={old_count} new={new_count}"
        )

if changed:
    path.write_bytes(data)

# Final validation.
data = path.read_bytes()

for old, new, description in PATCHES:
    old_count = data.count(old)
    new_count = data.count(new)

    if old_count != 0 or new_count != 1:
        raise SystemExit(
            f"ERROR: validation failed for {description}: "
            f"old={old_count} new={new_count}"
        )

print("  camera: DCAM preview buffer fixups OK")
