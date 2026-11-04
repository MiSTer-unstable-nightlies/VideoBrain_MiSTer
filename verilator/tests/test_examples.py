"""Check pinned input fixtures without cartridge ROMs or an HDL toolchain."""
import binascii
from contextlib import redirect_stderr
import io
import json
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from keyboard_input import encode
from keyboard_input import keyboard_text, music, physical_keys
from extract_printer import inspect
from tape_convert import read_vbt


FIXTURES = Path(__file__).resolve().parent / "fixtures" / "input"
CASES = json.loads((FIXTURES / "cases.json").read_text(encoding="utf-8"))


class InputFixtureTests(unittest.TestCase):
    def test_keyboard_sources(self):
        self.assertTrue(CASES)
        self.assertEqual({FIXTURES / case["output"] for case in CASES},
                         set(FIXTURES.rglob("*.vbk")))
        converters = {"apl": encode, "keys": physical_keys, "music": music,
                      "tinybasic": keyboard_text}
        for case in CASES:
            source = FIXTURES / case["source"]
            with self.subTest(source=case["source"]):
                text = source.read_text(encoding="utf-8")
                options = dict(case["options"])
                if case["profile"] == "tinybasic":
                    options["profile"] = "tinybasic"
                with redirect_stderr(io.StringIO()):
                    expected = converters[case["profile"]](text, **options)
                keyboard = FIXTURES / case["output"]
                actual = keyboard.read_bytes()
                magic, count, crc = struct.unpack("<4sHH", actual[:8])
                self.assertIn(magic, (b"VBK1", b"VBK2", b"VBK3", b"VBK4"))
                self.assertEqual(count, len(actual) - 8)
                self.assertEqual(crc, binascii.crc_hqx(actual[8:], 0xffff))
                self.assertEqual(actual, expected)

    def test_tape_images(self):
        paths = sorted(FIXTURES.rglob("*.vbt"))
        self.assertTrue(paths)
        for path in paths:
            with self.subTest(image=path.relative_to(FIXTURES)):
                self.assertEqual(path.read_bytes()[12:512], bytes(500))
                runs = read_vbt(path)
                if path == FIXTURES / "blank-tape.vbt":
                    self.assertEqual(runs, [])
                    raw = path.read_bytes()
                    self.assertEqual(raw[512:], bytes(len(raw) - 512))
                else:
                    self.assertTrue(runs)

    def test_blank_printer(self):
        sessions, fault = inspect(FIXTURES / "blank-printer.vbp")
        self.assertIsNone(fault)
        self.assertEqual(sessions, [])


if __name__ == "__main__":
    unittest.main()
