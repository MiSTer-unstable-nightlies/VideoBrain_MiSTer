"""Container validation and ROM-free hardware fixture generation."""

from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import uuid
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import vbc


def chunk(tag, payload):
    return tag + struct.pack("<I", len(payload)) + payload + bytes(len(payload) % 2)


def container(profile=0, rom=None, extras=(), head=None):
    if rom is None:
        size = 2048 if profile in (0, 5) else dict(vbc.PROFILES.values())[profile][0]
        rom = bytes([0x6D]) * size
    if head is None:
        head = struct.pack("<HHHH16sII", 1, 0, profile, 1,
                           uuid.UUID("12345678-1234-5678-9abc-123456789abc").bytes, 1, 0)
    body = b"VBCR" + chunk(b"HEAD", head)
    body += b"".join(chunk(tag, data) for tag, data in extras)
    body += chunk(b"ROM ", rom)
    return b"RIFF" + struct.pack("<I", len(body)) + body


def cases():
    # valid, mapper, preset (0 = default; 2 = Tennis)
    for profile in range(7):
        yield container(profile), 1, profile, 0
    yield container(extras=((b"JOYS", bytes((255, 255, 2, 0))),)), 1, 0, 2
    yield container(extras=((b"JOYS", bytes(4)),)), 1, 0, 0
    yield container(extras=((b"NAME", b"Odd"), (b"zzzz", b"abcde"))), 1, 0, 0
    yield container(extras=((b"SUPP", struct.pack("<II", 0x8000001F, 16)),)), 1, 0, 0
    rom = bytes([0x6D]) * 2048
    yield container(rom=rom, extras=((b"CRC ", struct.pack("<I", zlib.crc32(rom))),)), 1, 0, 0
    # Header plus payload crosses the 16-bit transport address boundary.
    yield container(extras=((b"zzzz", bytes(65460)),)), 1, 0, 0
    yield container(6, extras=((b"zzzz", bytes(65468)),)), 1, 6, 0
    yield container(rom=rom, extras=((b"CRC ", bytes(4)),)), 0, 0, 0
    yield container(extras=((b"JOYS", bytes(4)), (b"JOYS", bytes(4)))), 0, 0, 0
    yield container(extras=((b"JOYS", bytes(3)),)), 0, 0, 0
    yield container(extras=((b"JOYS", bytes((0, 0, 3, 0))),)), 0, 0, 0
    yield container(extras=((b"SUPP", struct.pack("<II", 1, 2)),)), 0, 0, 0
    yield container(extras=((b"STAT", struct.pack("<I", 4)),)), 0, 0, 0
    yield container(rom=b""), 0, 0, 0
    yield container(rom=bytes(4097)), 0, 0, 0
    for profile in (0, 5):
        for size in (1, 37, 180, 1024, 2049, 4095):
            yield container(profile, bytes([0x6D]) * size), 1, profile, 0
    for offset, value in ((0, 2), (2, 1), (4, 7), (6, 2), (24, 0), (28, 1)):
        head = bytearray(container()[20:52])
        head[offset] = value
        yield container(head=head), 0, 0, 0
    good = container()
    yield good[:-1], 0, 0, 0
    yield good + b"x", 0, 0, 0
    wrong_form = bytearray(good)
    wrong_form[8] = 0
    yield bytes(wrong_form), 0, 0, 0
    nonzero_pad = bytearray(container(extras=((b"zzzz", b"x"),)))
    nonzero_pad[61] = 1
    yield bytes(nonzero_pad), 0, 0, 0
    yield container(extras=((b"ROM ", rom),)), 0, 0, 0
    # Unknown metadata cannot precede the mandatory configuration.
    body = b"VBCR" + chunk(b"zzzz", b"") + good[12:]
    yield b"RIFF" + struct.pack("<I", len(body)) + body, 0, 0, 0
    # Oversized metadata cannot move the payload beyond the loader bound.
    yield container(extras=((b"zzzz", bytes(65480)),)), 0, 0, 0
    yield b"", 0, 0, 0
    # Raw images, including an R prefix, remain supported after rejected files.
    yield bytes([0x6D]) * 2048, 1, 6, 0
    yield b"Rabc" + bytes([0x6D]) * 2044, 1, 6, 0
    yield container(6), 1, 6, 0
    tennis = bytes(4092) + bytes.fromhex("78f61a44")
    yield container(5, tennis), 1, 5, 2
    yield container(5, tennis, ((b"JOYS", bytes((255, 255, 1, 0))),)), 1, 5, 0
    yield container(5, tennis, ((b"JOYS", bytes((255, 255, 0, 0))),)), 1, 5, 2


class ContainerTests(unittest.TestCase):
    def test_validation(self):
        for number, (data, valid, _, _) in enumerate(cases()):
            if data[:4] != b"RIFF":
                continue
            with self.subTest(case=number):
                if valid:
                    self.assertEqual(vbc.decode(data).encode(), data)
                else:
                    with self.assertRaises(ValueError):
                        vbc.decode(data)

    def test_identity_and_absence(self):
        cart = vbc.decode(container())
        self.assertEqual(cart.describe()["id"], "12345678-1234-5678-9abc-123456789abc")
        self.assertNotIn("peripherals", cart.describe())
        self.assertNotIn("joysticks", cart.describe())

    def test_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            rom, packed, extracted = (path / name for name in ("in.bin", "out.vbc", "out.bin"))
            rom.write_bytes(bytes(16384))
            command = [sys.executable, str(ROOT / "tools/vbc.py")]
            pack = command + ["pack", str(rom), str(packed), "--profile", "basic",
                              "--id", "12345678-1234-5678-9abc-123456789abc",
                              "--revision", "1", "--joy-preset", "tennis",
                              "--support", "printer,cassette1", "--require", "cassette1"]
            subprocess.run(pack, check=True, capture_output=True)
            fields = dict(vbc.decode(packed.read_bytes()).chunks)
            self.assertEqual(fields[b"JOYS"], bytes((255, 255, 2, 0)))
            self.assertEqual(fields[b"SUPP"], struct.pack("<II", 3, 2))
            subprocess.run(command + ["inspect", str(packed)], check=True, capture_output=True)
            subprocess.run(command + ["extract", str(packed), str(extracted)], check=True, capture_output=True)
            self.assertEqual(extracted.read_bytes(), rom.read_bytes())
            self.assertNotEqual(subprocess.run(pack, capture_output=True).returncode, 0)


def fixtures(output):
    output.mkdir(parents=True, exist_ok=True)
    rows = []
    for number, (data, valid, profile, preset) in enumerate(cases()):
        (output / f"{number}.vbc").write_bytes(data)
        rom = dict(vbc.decode(data).chunks)[b"ROM "] if valid and data[:4] == b"RIFF" else data
        first = rom[0] if rom else 0
        rows.append(f"{valid} {profile} {preset} {first} {len(rom)}\n")
    (output / "cases.txt").write_text("".join(rows), encoding="ascii")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--fixtures":
        fixtures(Path(sys.argv[2]))
    else:
        unittest.main()
