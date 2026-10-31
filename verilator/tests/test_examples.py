"""Check shipped examples without cartridge ROMs or an HDL toolchain."""
import binascii
import hashlib
from contextlib import redirect_stderr
import io
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from keyboard_input import encode
from keyboard_input import keyboard_text, music, physical_keys
from extract_printer import inspect
from tape_convert import read_vbt


EXAMPLES = Path(__file__).resolve().parents[2] / "examples"


class ExampleTests(unittest.TestCase):
    def test_keyboard_sources(self):
        sources = sorted(p for p in EXAMPLES.rglob("*.txt")
                         if p.stem.endswith(" (Source)") or
                         not p.with_name(p.stem + " (Source).txt").exists()) + sorted(EXAMPLES.rglob("*.mml"))
        self.assertTrue(sources)
        self.assertEqual({p.with_name(p.stem.removesuffix(" (Source)") + ".vbk") for p in sources},
                         set(EXAMPLES.rglob("*.vbk")))
        for source in sources:
            with self.subTest(source=source.relative_to(EXAMPLES)):
                text = source.read_text(encoding="utf-8")
                with redirect_stderr(io.StringIO()):
                    timing = ("score-ready" if source.stem == "rimsky-korsakov-flight-of-the-bumblebee"
                              else "score")
                    expected = (music(text, "letters", timing=timing)
                                if source.suffix == ".mml" else
                                keyboard_text(text, "letters", profile="tinybasic") if source.parent.name == "tinybasic" else
                                physical_keys(text) if source.name in ("clock-from-rtc.txt", "clock-from-rtc-v2.txt") else
                                encode(text))
                keyboard = source.with_name(source.stem.removesuffix(" (Source)") + ".vbk")
                actual = keyboard.read_bytes()
                magic, count, crc = struct.unpack("<4sHH", actual[:8])
                self.assertIn(magic, (b"VBK1", b"VBK2", b"VBK3"))
                self.assertEqual(count, len(actual) - 8)
                self.assertEqual(crc, binascii.crc_hqx(actual[8:], 0xffff))
                self.assertEqual(actual, expected)
                if source.stem.endswith(" (Source)"):
                    sidecar = keyboard.with_suffix(".txt").read_text(encoding="utf-8")
                    self.assertIn(f"SHA1: {hashlib.sha1(actual).hexdigest()}", sidecar)

    def test_tape_images(self):
        paths = sorted(EXAMPLES.rglob("*.vbt"))
        self.assertTrue(paths)
        for path in paths:
            with self.subTest(image=path.relative_to(EXAMPLES)):
                self.assertEqual(path.read_bytes()[12:512], bytes(500))
                runs = read_vbt(path)
                if path == EXAMPLES / "blank-tape.vbt":
                    self.assertEqual(runs, [])
                    raw = path.read_bytes()
                    self.assertEqual(raw[512:], bytes(len(raw) - 512))
                else:
                    self.assertTrue(runs)

    def test_blank_printer(self):
        sessions, fault = inspect(EXAMPLES / "blank-printer.vbp")
        self.assertIsNone(fault)
        self.assertEqual(sessions, [])


if __name__ == "__main__":
    unittest.main()
