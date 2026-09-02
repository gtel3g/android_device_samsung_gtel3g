#!/usr/bin/env python3

import hashlib
import sys
from pathlib import Path


RAW_SHA1 = "8b9a9b0974dfc0be78fe0d0a833ab49259addefe"
BOOST_SHA1 = "901dbf6609cb36f2deffcd3b02cdf63a98083a4f"
FINAL_SHA1 = "c96e4331893c12486d8b69e41a5010f9dae2dc6b"


def sha1(data):
    return hashlib.sha1(data).hexdigest()


if len(sys.argv) != 2:
    raise SystemExit(
        f"usage: {sys.argv[0]} <libGLES_mali.so>"
    )

path = Path(sys.argv[1])

if not path.is_file():
    raise SystemExit(f"missing file: {path}")

data = path.read_bytes()

before = sha1(data)

print(f"Mali SHA1 before: {before}")

if before not in {
    RAW_SHA1,
    BOOST_SHA1,
    FINAL_SHA1,
}:
    raise SystemExit(
        "ERROR: unexpected Mali blob.\n"
        f"SHA1: {before}\n"
        "Expected stock T561 r403 or a known patched state."
    )


# ------------------------------------------------------------
# 1. Android vendor path
# ------------------------------------------------------------

old_path = b"/system/lib/libboost.so"
new_path = b"/vendor/lib/libboost.so"

old_count = data.count(old_path)
new_count = data.count(new_path)

print(
    "libboost path: "
    f"old={old_count} new={new_count}"
)

if old_count == 1 and new_count == 0:
    data = data.replace(
        old_path,
        new_path,
        1,
    )

elif old_count == 0 and new_count == 1:
    print("libboost path already patched")

else:
    raise SystemExit(
        "ERROR: unexpected libboost path state"
    )


# ------------------------------------------------------------
# 2. Android 9 framebuffer compatibility
#
# Stock Mali reads numBuffers from an incompatible framebuffer
# structure field:
#
#     ldr r2, [lr, #184]
#
# On the Android 9 framebuffer path this becomes zero and breaks
# PLBU heap initialization.
#
# Force the known framebuffer buffer count to 3:
#
#     mov r2, #3
# ------------------------------------------------------------

old_num_buffers = bytes.fromhex(
    "b8 20 9e e5 "  # ldr r2, [lr, #184]
    "2c 20 84 e5 "  # str r2, [r4, #44]
    "30 20 84 e5 "  # str r2, [r4, #48]
    "02 30 a0 e1"   # mov r3, r2
)

new_num_buffers = bytes.fromhex(
    "03 20 a0 e3 "  # mov r2, #3
    "2c 20 84 e5 "
    "30 20 84 e5 "
    "02 30 a0 e1"
)

old_count = data.count(old_num_buffers)
new_count = data.count(new_num_buffers)

print(
    "numBuffers: "
    f"old={old_count} new={new_count}"
)

if old_count == 1 and new_count == 0:
    offset = data.find(old_num_buffers)

    print(
        f"patching numBuffers at 0x{offset:x}"
    )

    data = data.replace(
        old_num_buffers,
        new_num_buffers,
        1,
    )

elif old_count == 0 and new_count == 1:
    print("numBuffers already patched")

else:
    raise SystemExit(
        "ERROR: unexpected numBuffers pattern state"
    )


# ------------------------------------------------------------
# Validate final blob
# ------------------------------------------------------------

final_sha1 = sha1(data)

print(f"Mali SHA1 after:  {final_sha1}")

if final_sha1 != FINAL_SHA1:
    raise SystemExit(
        "ERROR: patched Mali hash mismatch\n"
        f"got:      {final_sha1}\n"
        f"expected: {FINAL_SHA1}"
    )

path.write_bytes(data)

print("T561 Mali r403 compatibility patch OK")
