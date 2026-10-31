from pathlib import Path
from contextlib import redirect_stderr
import io
import struct
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from keyboard_input import encode
from keyboard_input import MODE_LETTERS, MODE_SYMBOLS, RTC_INSERT, MUSIC_BANKS, MUSIC_RECORD, MUSIC_REPLAY, keyboard_text, music, physical_keys


def events(data):
    assert data[:4] in (b"VBK2", b"VBK3")
    assert struct.unpack("<H", data[4:6])[0] == len(data) - 8
    crc = 0xffff
    for byte in data[8:]:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ (0x1021 if crc & 0x8000 else 0)) & 0xffff
    assert struct.unpack("<H", data[6:8])[0] == crc
    return list(zip(*[iter(data[8:])] * 3))


def music_pitches(body):
    # ed01 rom $1616 key table; bios $4361 key codes; $1255 bank offsets
    table = bytes.fromhex("00 0d 0f 11 f2 14 16 f0 f0 18 f0 0c 0e 10 12 13 15 17 "
                          "f3 0a 0b 19 1b 1d f1 20 22 23 09 f0 f0 1a f4 1c 1e 1f 21")
    bank = 0
    pitches = []
    for key, _, _ in body:
        key = {0xfa: 33, 0xfb: 19, 0xfc: 22}.get(key, key)
        if key in (33, 19, 22):
            bank = {33: 12, 19: 0, 22: -12}[key]
        elif key != 255:
            index = table[(key % 4) * 9 + key // 4 + 1]
            assert index < 0x80 and 0 <= index + bank <= 47
            pitches.append(83 - index - bank)
    return pitches


class KeyboardTests(unittest.TestCase):
    def test_tinybasic_keyboard_round_trip(self):
        # Tiny BASIC VBCHARS table; BIOS READKBJOY matrix scan order.
        table = (' I"U!Y\\T&R9E8W7Q'
                 '%A.O#K)J(H/G-F6D'
                 '5S4Z1P@L$M:N,B=V'
                 "+C3X2?0;^'*")
        text = ('PRINT "A",1\nPRINT 1,2\nPRINT "B",2+3\n'
                '@(1)=7\nA$="HI"\nPRINT A$\nPRINT LEN(0)\n')
        symbols = False
        decoded = []
        for key, _, _ in events(keyboard_text(text, 'letters', profile='tinybasic')):
            if key in (MODE_LETTERS, MODE_SYMBOLS):
                symbols = key == MODE_SYMBOLS
            elif key == 19:
                decoded.append(' ')
            elif key == 27:
                decoded.append('\n')
            else:
                index = 2 * ((key % 4) * 9 + key // 4 + 1) - (not symbols)
                decoded.append(table[index])
        self.assertEqual(''.join(decoded), text)

    def test_music_timing_presets(self):
        text = 'O4 C R8 O5 B O2 C O4 C'
        self.assertEqual(music(text, 'letters', timing='score'),
                         music(text, 'letters', gap=2, min_hold=2, bank_fields=2))
        self.assertEqual(music(text, 'letters', timing='note'),
                         music(text, 'letters', gap=2, min_hold=2, bank_ready=True))
        for options in ({'timing': 'normal'}, {'timing': 'score', 'bank_ready': True},
                        {'timing': 'note', 'bank_fields': 2}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                music(text, 'letters', **options)

    def test_music_timing_cli(self):
        script = Path(__file__).resolve().parents[2] / 'tools' / 'keyboard_input.py'
        text = 'O4 C O5 B O2 C O4 C'
        with tempfile.TemporaryDirectory(dir=script.parent) as directory:
            source = Path(directory) / 'song.mml'
            output = source.with_suffix('.vbk')
            source.write_text(text)
            command = [sys.executable, '-B', str(script), str(source), str(output),
                       '--profile', 'music', '--start-mode', 'letters']
            for arguments, expected in (
                ([], music(text, 'letters', timing='score')),
                (['--timing', 'score'], music(text, 'letters', timing='score')),
                (['--timing', 'note'], music(text, 'letters', timing='note')),
                (['--timing', 'note', '--gap', '3'],
                 music(text, 'letters', timing='note', gap=3)),
                (['--bank-fields', '2'], music(text, 'letters', bank_fields=2)),
                (['--bank-ready'], music(text, 'letters', bank_ready=True)),
            ):
                with self.subTest(arguments=arguments):
                    result = subprocess.run(command + arguments, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(output.read_bytes(), expected)
            for arguments in (['--timing', 'note', '--bank-fields', '2'],
                              ['--timing', 'normal'], ['--profile', 'keys', '--timing', 'score']):
                with self.subTest(arguments=arguments):
                    self.assertNotEqual(subprocess.run(command + arguments,
                                                       capture_output=True).returncode, 0)

    def test_music_timing_examples(self):
        directory = Path(__file__).resolve().parents[2] / 'examples' / 'music'
        score = {p.stem: p for p in directory.glob('*.vbk')}
        sources = {p.stem: p for p in directory.glob('*.mml')}
        self.assertTrue(score, 'bundled music examples are missing')
        self.assertEqual(set(score), set(sources))
        for name in score:
            with self.subTest(song=name):
                text = sources[name].read_text(encoding='utf-8')
                self.assertEqual(score[name].read_bytes(),
                                 music(text, 'letters', timing='score'))
                score_events = events(score[name].read_bytes())
                note_events = events(music(text, 'letters', timing='note'))
                self.assertEqual(score_events[:5], note_events[:5])
                self.assertEqual(score_events[-3:], note_events[-3:])
                self.assertEqual(music_pitches(score_events[5:-3]),
                                 music_pitches(note_events[5:-3]))

    def test_music_bank_ready(self):
        text = 'T120 O2 C O5 B O3 C'
        timed = events(music(text, 'letters', gap=2, min_hold=2))[5:-3]
        ready = events(music(text, 'letters', gap=2, min_hold=2, bank_ready=True))[5:-3]
        self.assertEqual([event for event in ready if event[0] in MUSIC_BANKS.values()],
                         [(0xfa, 1, 0), (0xfc, 1, 0), (0xfb, 1, 0)])
        self.assertEqual([event for event in ready if event[0] not in MUSIC_BANKS.values()],
                         [event for event in timed if event[0] not in (33, 19, 22)])
        self.assertEqual(music_pitches(ready), [36, 83, 48])
        with self.assertRaisesRegex(ValueError, 'mutually exclusive'):
            music(text, 'letters', bank_fields=2, bank_ready=True)

    def test_music_score_ready_overlaps_release_without_shortening_notes(self):
        body = events(music('T120 O4 C O5 B O2 C', 'letters', timing='score-ready'))[5:-3]
        self.assertEqual(music_pitches(body), [60, 83, 36])
        self.assertEqual([event[1:] for event in body if event[0] in MUSIC_BANKS.values()],
                         [(1, 2), (1, 2)])
        self.assertEqual([event[1:] for event in body if event[0] not in MUSIC_BANKS.values()],
                         [(28, 0), (28, 0), (28, 2)])

    def test_music_score_ready_uses_rest_before_next_note(self):
        body = events(music('O4 C R4 O5 B', 'letters', timing='score-ready'))[5:-3]
        self.assertEqual([event for event in body if event[0] == 255], [(255, 28, 0)])
        self.assertEqual(body[-2], (MUSIC_BANKS[12], 1, 2))
        body = events(music('O2 C', 'letters', timing='score-ready'))[5:-3]
        self.assertEqual(body[0], (MUSIC_BANKS[-12], 1, 0))

    def test_apl_hold_final(self):
        normal = encode("EDIT DEMO\nA=1\nENDE\nRUN DEMO\n")
        held = encode("EDIT DEMO\nA=1\nENDE\nRUN DEMO\n", hold_final=True)
        self.assertEqual(held[8:], normal[8:-1])
        self.assertEqual(held[-1], 1)

    def test_physical_keys(self):
        self.assertEqual(events(physical_keys("SHIFT 3 4\nBACK\nWAIT 300")),
                         [(11, 3, 4), (35, 8, 8), (255, 255, 0), (255, 45, 0)])
        for text in ("A 0 8", "A 8 256", "WAIT 0", "UNKNOWN"):
            with self.assertRaises(ValueError):
                physical_keys(text)

    def test_rtc_clock_script(self):
        source = Path(__file__).resolve().parents[2] / 'examples' / 'clock-from-rtc.txt'
        blob = physical_keys(source.read_text())
        self.assertEqual(blob[:4], b'VBK3')
        self.assertEqual(events(blob), [
            (MODE_SYMBOLS, 8, 8), (27, 8, 24), (MODE_LETTERS, 8, 8),
            (29, 8, 16), (MODE_SYMBOLS, 8, 8), (RTC_INSERT, 8, 8), (17, 8, 8)
        ])
        self.assertEqual(blob, source.with_suffix('.vbk').read_bytes())
        self.assertEqual(physical_keys('SHIFT\nG')[:4], b'VBK2')
        with self.assertRaises(ValueError):
            physical_keys('RTC 0 8')

    def test_standard_symbols_and_initial_mode(self):
        a = events(keyboard_text('A,;?1', 'letters', hold_final=True))
        self.assertEqual([key for key, _, _ in a], [MODE_LETTERS, 32, 7, 3, 34, MODE_SYMBOLS, 33])
        self.assertEqual(events(keyboard_text('A', 'symbols', hold_final=True))[:2],
                         [(MODE_SYMBOLS, 8, 8), (MODE_LETTERS, 8, 8)])
        with self.assertRaises(ValueError):
            keyboard_text('A', None)

    def test_text_wrap_and_blank_lines(self):
        a = events(keyboard_text('ABCDEFGHIJKLMNOP\n\n1', 'letters', 'text', True))
        self.assertEqual([key for key, _, _ in a].count(27), 1)
        self.assertEqual(a[-2:], [(MODE_SYMBOLS, 8, 8), (33, 8, 8)])
        for text in ('A' * 17, '\n' * 8):
            with self.assertRaises(ValueError):
                keyboard_text(text, 'letters', 'text')

    def test_music_scale_record_and_replay(self):
        a = events(music('T120 O4 L4 C D E F G A B > C', 'letters', replay=True))
        self.assertEqual(a[:5], [(MODE_SYMBOLS, 8, 8), (19, 8, 64), (MUSIC_RECORD, 8, 8), (MODE_LETTERS, 8, 8), (19, 8, 8)])
        self.assertEqual([key for key, _, _ in a[5:-4]], [29, 25, 21, 17, 13, 9, 5, 6])
        self.assertEqual(a[5][1:], (22, 8))
        self.assertEqual(a[-4:-1], [(MODE_SYMBOLS, 8, 8), (7, 8, 8), (MODE_LETTERS, 8, 8)])
        self.assertEqual(music('C', 'letters'), music('C', 'symbols'))
        self.assertEqual(a[-1], (MUSIC_REPLAY, 8, 8))

    def test_music_accidentals_banks_rests_and_page_wait(self):
        a = events(music('O2 C C# D- R4 O5 B', 'symbols', page_notes=2))
        self.assertIn((33, 8, 8), a)
        self.assertIn((22, 8, 8), a)
        self.assertEqual([key for key, hold, gap in a if hold == 22], [34, 30, 30, 5])
        self.assertIn((255, 64, 0), a)
        self.assertIn((255, 30, 0), a)
        self.assertEqual(events(music('C4.', 'letters'))[-4][1:], (37, 8))

    def test_music_range_boundaries(self):
        for text, pitch in (('O2 C', 36), ('O2 D-', 37),
                            ('O5 C', 72), ('O5 A#', 82), ('O5 B', 83),
                            ('O6 C-', 83), ('O5 > C-', 83)):
            with self.subTest(text=text):
                self.assertEqual(music_pitches(events(music(text, 'letters'))[5:-3]), [pitch])
        for text in ('O2 C-', 'O5 B#', 'O5 B+', 'O6 C', 'O6 C#', 'O6 D-',
                     'O6 D', 'O5 > C', 'O6 C- C'):
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, r'range is C2\.\.B5'):
                music(text, 'letters')

    def test_music_retains_bank_in_overlap(self):
        a = events(music('O2 C O3 C O4 C O5 C O4 C O5 B O4 C', 'letters'))
        body = a[5:-3]
        self.assertEqual(music_pitches(body), [36, 48, 60, 72, 60, 83, 60])
        self.assertEqual([key for key, _, _ in body if key in (33, 19, 22)], [33, 19, 22])

    def test_music_bank_timing_preserves_onsets_and_pitches(self):
        body = events(music('O4 C O5 B O2 C O4 C', 'letters', gap=2,
                            min_hold=2, bank_fields=2))[5:-3]
        elapsed = 0
        onsets = []
        for key, hold, gap in body:
            if key not in (33, 19, 22, 255):
                onsets.append(elapsed)
            elapsed += hold + gap
        self.assertEqual(onsets, [0, 30, 60, 90])
        self.assertEqual(elapsed, 120)
        self.assertEqual(music_pitches(body), [60, 83, 36, 60])
        self.assertEqual(body[0][1:], (24, 2))
        self.assertEqual([event[1:] for event in body if event[0] in (33, 19, 22)],
                         [(2, 2), (2, 2)])

    def test_music_bank_timing_uses_silence_first(self):
        body = events(music('O4 C O5 B', 'letters', bank_fields=2))[5:-3]
        self.assertEqual(body[0][1:], (22, 4))
        for rest, expected in (('R4', [(255, 26, 0)]),
                               ('T32 R1', [(255, 255, 0), (255, 190, 0)]),
                               ('T255 R64', [])):
            with self.subTest(rest=rest):
                body = events(music(f'O4 C {rest} T120 O5 B', 'letters', gap=2,
                                    min_hold=2, bank_fields=2))[5:-3]
                self.assertEqual([event for event in body if event[0] == 255], expected)
                self.assertEqual(body[0][1:], (25 if rest == 'T255 R64' else 28, 2))

    def test_music_bank_timing_startup_and_limits(self):
        body = events(music('O2 C', 'letters', bank_fields=2))[5:-3]
        self.assertEqual(body[0], (33, 2, 2))
        self.assertEqual(body[1][1:], (22, 8))
        for value in (0, 256):
            with self.assertRaisesRegex(ValueError, 'bank fields'):
                music('C', 'letters', bank_fields=value)
        warning = io.StringIO()
        with redirect_stderr(warning):
            body = events(music('T255 L16 O4 C O5 B', 'letters', gap=2,
                                min_hold=2, bank_fields=2))[5:-3]
        self.assertIn('octave switch adds 4 fields', warning.getvalue())
        self.assertEqual(body[0][1:], (2, 2))

    def test_music_range(self):
        scale = ' '.join(f'O{octave} C C# D D# E F F# G G# A A# B'
                         for octave in range(2, 6))
        for text, expected in ((scale, list(range(36, 84))),
                               ('O2 C O3 C O4 C O5 C B O2 C', [36, 48, 60, 72, 83, 36])):
            for timing in ('score', 'note'):
                with self.subTest(text=text, timing=timing):
                    body = events(music(text, 'letters', replay=True, timing=timing))
                    self.assertEqual(body[2], (MUSIC_RECORD, 8, 8))
                    self.assertEqual(body[-1], (MUSIC_REPLAY, 8, 8))
                    self.assertEqual(music_pitches(body[5:-4]), expected)

    def test_music_rejects_unsupported_or_unsafe_timing(self):
        for text in ('C,E,G', 'O7 C', 'O6 E', 'T120 C64', 'L0 C', 'R4'):
            with self.assertRaises(ValueError, msg=text):
                music(text, 'letters')
        with self.assertRaises(ValueError):
            music('C', None)

    def test_music_playback_capacity(self):
        warning = io.StringIO()
        with redirect_stderr(warning):
            music('C ' * 79, 'letters')
            music('C R ' * 79, 'letters')
        self.assertEqual(warning.getvalue(), '')
        with redirect_stderr(warning):
            a = events(music('C ' * 80, 'letters'))
        self.assertEqual(len(a), 5 + 80 + 3)
        self.assertIn('80 notes; Record will truncate', warning.getvalue())
        self.assertIn('79-note limit', warning.getvalue())
        self.assertIn('Use Playback', warning.getvalue())
        with redirect_stderr(io.StringIO()):
            self.assertEqual(len(events(music('C ' * 1357, 'letters'))), 1365)
        with self.assertRaisesRegex(ValueError, '1365'):
            music('C ' * 1358, 'letters')


if __name__ == '__main__':
    unittest.main()
