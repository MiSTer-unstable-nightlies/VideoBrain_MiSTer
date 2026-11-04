#!/usr/bin/env python3
"""Pack, inspect, and extract RIFF VideoBrain cartridges."""

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import struct
import uuid
import zlib


PROFILES = {
    "standard": (0, range(1, 4097)),
    "timeshare": (1, (2048,)),
    "money-minder": (2, (4096,)),
    "apls": (3, (16384,)),
    "information-manager": (4, (8192,)),
    "4k-ram": (5, range(1, 4097)),
    "basic": (6, (16384,)),
}
TEXT = {
    "name": b"NAME", "author": b"AUTH", "publisher": b"PUBL",
    "dumper": b"DUMP", "date": b"DATE", "dump_date": b"DDAT",
    "version": b"VERS", "note": b"NOTE", "mame": b"MAME",
}
SIZES = {b"HEAD": 32, b"JOYS": 4, b"SUPP": 8, b"CRC ": 4,
         b"STAT": 4, b"BASE": 20}
KNOWN = set(TEXT.values()) | set(SIZES) | {b"ROM "}
PERIPHERALS = {"printer": 1, "cassette1": 2, "cassette2": 4,
               "terminal": 8, "modem": 16}


@dataclass(frozen=True)
class Cartridge:
    # Preserve chunk order and unknown payloads when rewriting a container.
    chunks: tuple

    def encode(self):
        body = b"VBCR" + b"".join(
            tag + struct.pack("<I", len(data)) + data + bytes(len(data) % 2)
            for tag, data in self.chunks)
        result = b"RIFF" + struct.pack("<I", len(body)) + body
        decode(result)
        return result

    def describe(self):
        chunks = dict(self.chunks)
        major, minor, profile, profile_version, ident, revision, features = struct.unpack(
            "<HHHH16sII", chunks[b"HEAD"])
        result = {"format": f"{major}.{minor}", "profile": profile,
                  "profile_version": profile_version, "id": str(uuid.UUID(bytes=ident)),
                  "revision": revision, "required_features": features,
                  "rom_bytes": len(chunks[b"ROM "]),
                  "rom_crc32": f'{zlib.crc32(chunks[b"ROM "]):08x}'}
        for name, tag in TEXT.items():
            if tag in chunks:
                result[name] = chunks[tag].decode("utf-8")
        if b"JOYS" in chunks:
            axes, buttons, preset, _ = chunks[b"JOYS"]
            result["joysticks"] = {"axes": axes, "buttons": buttons, "preset": preset}
        if b"SUPP" in chunks:
            supported, required = struct.unpack("<II", chunks[b"SUPP"])
            result["peripherals"] = {"supported": supported, "required": required}
        if b"STAT" in chunks:
            result["dump_status"] = struct.unpack("<I", chunks[b"STAT"])[0]
        if b"BASE" in chunks:
            ident, revision = struct.unpack("<16sI", chunks[b"BASE"])
            result["base"] = {"id": str(uuid.UUID(bytes=ident)), "revision": revision}
        result["chunks"] = [{"tag": tag.decode("ascii", errors="backslashreplace"),
                             "bytes": len(data)} for tag, data in self.chunks]
        return result


def decode(data):
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"VBCR":
        raise ValueError("Not a RIFF VBCR cartridge")
    if len(data) > 81920 or struct.unpack_from("<I", data, 4)[0] != len(data) - 8:
        raise ValueError("Invalid RIFF length")
    chunks, seen = [], set()
    pos = 12
    while pos < len(data):
        if pos + 8 > len(data):
            raise ValueError("Truncated chunk header")
        tag, size = struct.unpack_from("<4sI", data, pos)
        pos += 8
        end = pos + size
        if end + size % 2 > len(data):
            raise ValueError("Truncated chunk payload")
        if size % 2 and data[end] != 0:
            raise ValueError("Nonzero chunk padding")
        if tag in KNOWN and tag in seen:
            raise ValueError(f"Duplicate {tag!r} chunk")
        if tag in SIZES and size != SIZES[tag]:
            raise ValueError(f"Invalid {tag!r} size")
        if not chunks and tag != b"HEAD":
            raise ValueError("HEAD must be first")
        if tag == b"ROM " and (end + size % 2 != len(data) or pos > 65536):
            raise ValueError("ROM must be last and start within 64 KiB")
        chunks.append((tag, data[pos:end]))
        seen.add(tag)
        pos = end + size % 2
    fields = dict(chunks)
    if b"HEAD" not in fields or b"ROM " not in fields:
        raise ValueError("HEAD and ROM are required")
    major, minor, profile, version, _, revision, features = struct.unpack(
        "<HHHH16sII", fields[b"HEAD"])
    if (major, minor, version, features) != (1, 0, 1, 0) or profile > 6:
        raise ValueError("Unsupported format, hardware profile, or required features")
    if revision == 0:
        raise ValueError("Revision must be nonzero")
    sizes = next(sizes for ident, sizes in PROFILES.values() if ident == profile)
    if len(fields[b"ROM "]) not in sizes:
        raise ValueError("ROM size does not match hardware profile")
    if b"CRC " in fields and struct.unpack("<I", fields[b"CRC "])[0] != zlib.crc32(fields[b"ROM "]):
        raise ValueError("ROM checksum mismatch")
    if b"JOYS" in fields:
        axes, buttons, preset, reserved = fields[b"JOYS"]
        if axes not in (*range(16), 255) or buttons not in (*range(16), 255) or preset > 2 or reserved:
            raise ValueError("Unsupported JOYS declaration")
    if b"SUPP" in fields:
        supported, required = struct.unpack("<II", fields[b"SUPP"])
        if required & ~supported:
            raise ValueError("Required peripherals must also be supported")
    if b"STAT" in fields and struct.unpack("<I", fields[b"STAT"])[0] > 3:
        raise ValueError("Unsupported dump status")
    return Cartridge(tuple(chunks))


def peripheral_mask(value):
    try:
        return sum(PERIPHERALS[name] for name in set(value.split(",")) if name)
    except KeyError as error:
        raise argparse.ArgumentTypeError(f"Unknown peripheral: {error.args[0]}") from error


def integer(value):
    return int(value, 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    pack = commands.add_parser("pack")
    pack.add_argument("input", type=Path)
    pack.add_argument("output", type=Path)
    pack.add_argument("--profile", choices=PROFILES, required=True)
    pack.add_argument("--id", type=uuid.UUID, required=True)
    pack.add_argument("--revision", type=integer, required=True)
    for name in TEXT:
        pack.add_argument("--" + name.replace("_", "-"))
    pack.add_argument("--axes", type=integer)
    pack.add_argument("--buttons", type=integer)
    pack.add_argument("--joy-preset", choices=("unspecified", "gladiator", "tennis"))
    pack.add_argument("--support", type=peripheral_mask)
    pack.add_argument("--require", type=peripheral_mask)
    pack.add_argument("--dump-status", choices=("unknown", "good", "suspect", "incomplete"))
    pack.add_argument("--base-id", type=uuid.UUID)
    pack.add_argument("--base-revision", type=integer)
    inspect = commands.add_parser("inspect")
    inspect.add_argument("input", type=Path)
    extract = commands.add_parser("extract")
    extract.add_argument("input", type=Path)
    extract.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "pack":
            rom = args.input.read_bytes()
            head = struct.pack("<HHHH16sII", 1, 0, PROFILES[args.profile][0], 1,
                               args.id.bytes, args.revision, 0)
            chunks = [(b"HEAD", head)]
            for name, tag in TEXT.items():
                value = getattr(args, name)
                if value is not None:
                    chunks.append((tag, value.encode("utf-8")))
            if any(value is not None for value in (args.axes, args.buttons, args.joy_preset)):
                # Missing masks remain undeclared; no port use is inferred from a preset.
                chunks.append((b"JOYS", bytes((255 if args.axes is None else args.axes,
                    255 if args.buttons is None else args.buttons,
                    ("unspecified", "gladiator", "tennis").index(args.joy_preset or "unspecified"), 0))))
            if args.support is not None or args.require is not None:
                if args.support is None:
                    raise ValueError("--require needs an explicit --support declaration")
                chunks.append((b"SUPP", struct.pack("<II", args.support, args.require or 0)))
            if args.dump_status is not None:
                chunks.append((b"STAT", struct.pack("<I", ("unknown", "good", "suspect", "incomplete").index(args.dump_status))))
            if args.base_id is not None or args.base_revision is not None:
                if args.base_id is None or args.base_revision is None:
                    raise ValueError("Supply both --base-id and --base-revision")
                chunks.append((b"BASE", struct.pack("<16sI", args.base_id.bytes, args.base_revision)))
            chunks.extend(((b"CRC ", struct.pack("<I", zlib.crc32(rom))), (b"ROM ", rom)))
            output = Cartridge(tuple(chunks)).encode()
            with args.output.open("xb") as target:
                target.write(output)
        else:
            cart = decode(args.input.read_bytes())
            if args.command == "inspect":
                print(json.dumps(cart.describe(), indent=2, ensure_ascii=True))
            else:
                with args.output.open("xb") as target:
                    target.write(dict(cart.chunks)[b"ROM "])
    except (OSError, ValueError, struct.error) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
