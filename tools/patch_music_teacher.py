#!/usr/bin/env python3
"""Create the experimental Music Teacher 1 Better Playback 0.5 cartridge.

Correct G#2 and C2 tuning; keep sound, recording and rest timing intact.
Suppress staff glyphs and clear the five-row note-name strip at page wrap.
Poll Program 1 keys directly and service video only when the BIOS is ready.
"""
import argparse
import hashlib
from pathlib import Path


ED01_SHA256 = "6f68d96533795159a18d757629a0fb5d5fa5d228c43361d8565b84cb1ee3d198"

# $1388 is unreachable after bypassing the staff renderer at $1368
# no nested pi calls: pop returns directly to the page-wrap caller
# lis 0 / lr r0,a / lr r1,a     reset the original page counters
# dci $0ec4 / li 60 / lr r8,a   five scanlines, twelve bytes each
# lis 0
# loop: st / ds r8 / bf 4,loop
# pop
PAGE_WRAP = "70 50 51 2a 0e c4 20 3c 58 70 17 38 94 fd 1c"

# $1397: call the octave-only scanner, then resume with R4 cleared.
# $13a0: retain the BIOS pushk/popk pair and new-key flag check.
# $13b5 is ready for a new key; $13c0 leaves readiness after accepting it.
OCTAVE_POLL = (
    "28 13 a0 70 54 29 10 a1 2b "
    "08 28 40 a9 2b 2b "
    "28 43 61 70 e8 84 09 28 14 34 90 f5 2b 2b 2b "
    "2b 2b 28 43 61 70 e8 84 05 91 03 90 14 "
    "28 14 34 90 f1 2b 2b 2b"
)

# Use the BIOS's RAM threshold and video-Y comparison, without its wait loop.
# $1434 is unreachable after bypassing note and rest glyph rendering.
VIDEO_SERVICE = "08 28 40 a9 2a 0f e5 16 2a 08 fb 8d 92 05 28 42 4d 68 28 40 bc 0c"

# Accept a newly scanned octave key immediately in unshifted Program 1.
# Other keys and Program 2 retain the BIOS new-key flag.
BANK_SCAN = (
    "72 f5 94 1c 2a 0f e2 16 21 01 94 14 "
    "48 21 7f 25 12 84 09 25 20 84 05 25 18 94 05 "
    "58 29 13 d5 29 13 d5"
)

PATCHES = (
    # preserve decoding and the pushk/popk pairing in a1341
    # $136b remains the page-wrap entry used by the original static patch
    (0x1368, "65 6d 20 10 5c 28 14", "29 13 d5 29 13 88 2b"),
    (0x1388, "2a 0c 00 40 18 1f 24 03 58 84 10 20 54 8e 8e", PAGE_WRAP),
    (0x10DC, "28 13 d9", "28 13 6b"),  # live note page wrap
    (0x1288, "28 13 d9", "28 13 6b"),  # replay page wrap
    (0x1540, "28 13 d9", "28 13 6b"),  # rest page wrap
    # preserve rest slots/counters; bypass only the rest glyph
    (0x1546, "65 6d 2a", "29 15 5f"),
    (0x115B, "29 10 9c", "29 13 97"),
    (0x109C, "28 14 c8", "28 13 a0"),
    (0x1397,
     "38 84 09 71 e8 94 f6 7c 8e 90 f2 42 18 1f 24 0b 58 28 14 27 "
     "28 14 27 28 14 27 84 0b 20 18 8e 38 28 14 27 28 14 27 28 14 e8 "
     "78 f5 84 04 20 d0 8e 2c 78 58",
     OCTAVE_POLL),
    (0x1434,
     "08 28 40 a9 2c 2a 0f 9f 0e 20 10 58 70 17 38 94 fd 0f 28 43 cd 0f",
     VIDEO_SERVICE),
    (0x13CA, "2a 0f 9f 28 14 ee 7a 8e 2c 94", "08 28 40 a9 28 43 61 29 14 4a"),
    (0x144A,
     "20 30 f5 84 1a 13 13 91 03 16 16 20 80 8b 58 20 ff 8e 48 17 16 "
     "20 c0 8b 58 20 ff 8e 48 17 28 40 bc 0c", BANK_SCAN),
    (0x1585, "28 43 61", "28 13 ca"),
    # preserve interval tuning rather than rounding each pitch toward A440
    (0x1692, "cc", "4c"),  # G#2: match the upper octaves
    (0x169A, "f9", "f8"),  # C2: improve octaves, fifths and fourths
)


def patch_rom(data):
    if len(data) != 2048 or hashlib.sha256(data).hexdigest() != ED01_SHA256:
        raise ValueError("expected the original 2048-byte Music Teacher 1 ED01 ROM")
    patched = bytearray(data)
    for address, before, after in PATCHES:
        offset = address - 0x1000
        expected, replacement = bytes.fromhex(before), bytes.fromhex(after)
        if (len(expected) != len(replacement)
                or data[offset:offset + len(expected)] != expected):
            raise ValueError(f"unexpected instructions at ${address:04X}")
        patched[offset:offset + len(replacement)] = replacement
    return bytes(patched)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="original ED01 cartridge image")
    parser.add_argument("output", type=Path, help="new experimental cartridge image")
    args = parser.parse_args()
    try:
        patched = patch_rom(args.source.read_bytes())
        with args.output.open("xb") as output:
            output.write(patched)
    except (OSError, ValueError) as error:
        parser.exit(1, f"error: {error}\n")
    print(f"{args.output}: {len(patched)} bytes, "
          f"SHA256 {hashlib.sha256(patched).hexdigest()}")


if __name__ == "__main__":
    main()
