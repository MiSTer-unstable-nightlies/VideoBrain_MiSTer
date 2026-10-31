"""Check patch write bounds and ROM invariants; no full-machine emulation."""
import hashlib
import math
import os
from pathlib import Path
import sys
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import patch_music_teacher as patch


class PageWrapTests(unittest.TestCase):
    def test_execute_clear_routine(self):
        code = bytes.fromhex(patch.PAGE_WRAP)
        memory = bytearray([0xA5] * 65536)
        registers = list(range(12))
        a, dc, pc, zero = 0xFF, 0, 0, False
        writes = []
        for _ in range(1000):
            op = code[pc]
            pc += 1
            if op == 0x70:  # lis 0
                a = 0
            elif op in (0x50, 0x51, 0x58):
                registers[op - 0x50] = a
            elif op == 0x2A:  # dci
                dc = int.from_bytes(code[pc:pc + 2], "big")
                pc += 2
            elif op == 0x20:  # li
                a = code[pc]
                pc += 1
            elif op == 0x17:  # st (a unchanged)
                memory[dc] = a
                writes.append(dc)
                dc += 1
            elif op == 0x38:  # ds r8 (a unchanged)
                registers[8] = (registers[8] - 1) & 255
                zero = registers[8] == 0
            elif op == 0x94:  # bf 4, relative to displacement byte
                offset = code[pc]
                pc += 1 if zero else offset - 256 if offset > 127 else offset
            elif op == 0x1C:  # pop
                break
            else:
                self.fail(f"unexpected opcode {op:02x}")
        else:
            self.fail("clear routine did not return")
        self.assertEqual(writes, list(range(0x0EC4, 0x0F00)))
        self.assertEqual(memory[0x0EC4:0x0F00], bytes(60))
        self.assertEqual(memory[:0x0EC4], bytes([0xA5]) * 0x0EC4)
        self.assertEqual(memory[0x0F00:], bytes([0xA5]) * (65536 - 0x0F00))
        self.assertEqual(registers[:2], [0, 0])
        self.assertEqual(registers[2:8], list(range(2, 8)))
        self.assertEqual(registers[9:], list(range(9, 12)))

    def test_reject_wrong_rom(self):
        for data in (b"", bytes(2048), bytes(4096)):
            with self.assertRaises(ValueError):
                patch.patch_rom(data)


class OctavePollTests(unittest.TestCase):
    def run_scanner(self, scans, video_ready=False):
        code = bytearray(65536)
        code[0x1397:0x13CA] = bytes.fromhex(patch.OCTAVE_POLL)
        service = bytes.fromhex(patch.VIDEO_SERVICE)
        code[0x1434:0x1434 + len(service)] = service
        pc, a, k, flags, dc = 0x1397, 0, 0, 0, 0
        registers = list(range(12))
        stack, services = [], []
        scans = iter(scans)
        for _ in range(1000):
            if pc == 0x13D5:  # original popk/pk epilogue
                pc = stack.pop()
                continue
            op = code[pc]
            pc += 1
            if op == 0x28:  # pi; BIOS calls return immediately in this model
                target = int.from_bytes(code[pc:pc + 2], 'big')
                pc += 2
                if target in (0x13A0, 0x1434):
                    link, pc = pc, target
                elif target == 0x40A9:
                    stack.append(k)
                elif target == 0x40BC:
                    k = stack.pop()
                elif target == 0x4361:
                    registers[8] = next(scans)
                    k = pc
                elif target == 0x424D:
                    services.append(pc)
                    k = pc
                else:
                    self.fail(f'unexpected call {target:04x}')
            elif op == 0x08:  # lr k,p
                k = link
            elif op == 0x0C:  # pk
                pc = k
            elif op == 0x2B:  # nop; keep readiness hook addresses fixed
                pass
            elif op == 0x68:  # lisl 0, as in the BIOS video-service epilogue
                pass
            elif op == 0x2A:
                dc = int.from_bytes(code[pc:pc + 2], 'big')
                pc += 2
            elif op == 0x16:
                self.assertEqual(dc, 0x0FE5)
                a = 249
                dc += 1
            elif op == 0x8D:
                self.assertEqual(dc, 0x08FB)
                video_y = 250 if video_ready else 200
                flags = 2 if video_y >= a else 0
                dc += 1
            elif op in (0x70, 0x78):
                a = op - 0x70
            elif op == 0x54:
                registers[4] = a
            elif op == 0xE8:  # xs r8; F8 S is set for a nonnegative result
                a ^= registers[8]
                flags = (1 if a < 128 else 0) | (4 if a == 0 else 0)
            elif op == 0x34:
                registers[4] = (registers[4] - 1) & 255
                flags = 4 if registers[4] == 0 else 0
            elif op in (0x84, 0x90, 0x91, 0x92, 0x94):
                offset = code[pc]
                take = bool(flags & (op & 15))
                if op & 0x10:
                    take = not take
                pc += (offset - 256 if offset > 127 else offset) if take else 1
            elif op == 0x29:
                target = int.from_bytes(code[pc:pc + 2], 'big')
                if target == 0x13D5:  # original popk/pk epilogue
                    pc = stack.pop()
                elif target == 0x10A1:
                    self.assertFalse(stack)
                    self.assertEqual(registers[4], 0)
                    self.assertEqual(registers[:4], list(range(4)))
                    self.assertEqual(registers[5:8], list(range(5, 8)))
                    self.assertEqual(registers[9:], list(range(9, 12)))
                    return registers[8], services
                else:
                    self.fail(f'unexpected jump {target:04x}')
            else:
                self.fail(f'unexpected opcode {op:02x} at {pc - 1:04x}')
        self.fail('scanner did not return')

    def test_release_and_stable_new_key_without_video_wait(self):
        key, services = self.run_scanner([0, 0x85, 5])
        self.assertEqual(key, 5)
        self.assertEqual(services, [])

    def test_held_octave_and_idle_wait_do_not_wait_for_video(self):
        key, services = self.run_scanner([19] * 16 + [0] * 17 + [0x85, 5])
        self.assertEqual(key, 5)
        self.assertEqual(services, [])

    def test_service_video_when_bios_comparison_is_ready(self):
        key, services = self.run_scanner([19, 0, 0x85, 5], video_ready=True)
        self.assertEqual(key, 5)
        self.assertEqual(len(services), 2)


class BankScanTests(unittest.TestCase):
    def scan(self, key, program=0, shifted=0):
        code = bytes.fromhex(patch.BANK_SCAN)
        pc, a, zero = 0, 0, False
        for _ in range(30):
            op = code[pc]
            pc += 1
            if op == 0x72:
                a = 2
            elif op == 0xF5:
                a &= program
                zero = a == 0
            elif op == 0x2A:
                self.assertEqual(code[pc:pc + 2], bytes.fromhex('0f e2'))
                pc += 2
            elif op == 0x16:
                a = shifted
            elif op == 0x48:
                a = key
            elif op == 0x21:
                a &= code[pc]
                zero = a == 0
                pc += 1
            elif op == 0x25:
                zero = a == code[pc]
                pc += 1
            elif op in (0x84, 0x94):
                take = zero if op == 0x84 else not zero
                pc += code[pc] if take else 1
            elif op == 0x58:
                key = a
            elif op == 0x29:
                self.assertEqual(code[pc:pc + 2], bytes.fromhex('13 d5'))
                return key
            else:
                self.fail(f'unexpected bank scan opcode {op:02x}')
        self.fail('bank scan did not return')

    def test_only_unshifted_program_one_octave_keys_skip_new_key_flag(self):
        for key in (0x92, 0xA0, 0x98):
            self.assertEqual(self.scan(key), key & 0x7F)
            self.assertEqual(self.scan(key, shifted=1), key)
            self.assertEqual(self.scan(key, program=2), key)
        for key in (0, 0x85, 0x9B, 0x12, 0x20, 0x18):
            self.assertEqual(self.scan(key), key)


class OriginalRomTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        filename = os.environ.get("MT1_ROM")
        if not filename:
            raise unittest.SkipTest("set MT1_ROM to the original ED01 cartridge")
        data = Path(filename).read_bytes()
        if hashlib.sha256(data).hexdigest() != patch.ED01_SHA256:
            raise ValueError("MT1_ROM is not the original ED01 cartridge")
        cls.original = data
        cls.patched = patch.patch_rom(data)

    def test_changes_are_confined_to_declared_ranges(self):
        expected = bytearray(self.original)
        for address, before, after in patch.PATCHES:
            start = address - 0x1000
            self.assertEqual(self.original[start:start + len(bytes.fromhex(before))],
                             bytes.fromhex(before))
            expected[start:start + len(bytes.fromhex(after))] = bytes.fromhex(after)
        self.assertEqual(self.patched, bytes(expected))
        self.assertEqual(len(self.patched), 2048)
        self.assertEqual(self.original[0x4EE:0x500], self.patched[0x4EE:0x500])
        self.assertEqual(self.original[0x4C8:0x4E8], self.patched[0x4C8:0x4E8])
        self.assertEqual(self.original[0x14E:0x15B], self.patched[0x14E:0x15B])
        self.assertEqual(self.original[0x15E:0x16B], self.patched[0x15E:0x16B])

    def test_core_recognizes_output(self):
        crc = f'{zlib.crc32(self.patched):08X}'
        self.assertIn(f'x"{crc}"', (ROOT / "rtl" / "sys_bus.vhd").read_text())

    def test_pitch_intervals_do_not_worsen(self):
        original = self.original[0x66B:0x69B]
        patched = self.patched[0x66B:0x69B]
        self.assertEqual([i for i in range(48) if original[i] != patched[i]],
                         [39, 47])

        def period(value):
            return 2 * (value & 0x7F) + (value >> 7)

        for distance, target in ((1, 100), (2, 200),
                                 (5, 1200 * math.log2(4 / 3)),
                                 (7, 1200 * math.log2(3 / 2)),
                                 (12, 1200), (24, 2400), (36, 3600)):
            for i in range(48 - distance):
                before = 1200 * math.log2(period(original[i + distance])
                                          / period(original[i])) - target
                after = 1200 * math.log2(period(patched[i + distance])
                                         / period(patched[i])) - target
                with self.subTest(distance=distance, index=i):
                    self.assertLessEqual(abs(after), abs(before) + 1e-9)

    def test_reject_already_patched_rom(self):
        with self.assertRaises(ValueError):
            patch.patch_rom(self.patched)


if __name__ == "__main__":
    unittest.main()
