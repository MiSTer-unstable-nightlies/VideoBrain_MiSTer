#!/usr/bin/env python3
"""Convert VideoBrain text, physical keys or Music Teacher MML to VBK."""
import argparse
import binascii
from fractions import Fraction
from pathlib import Path
import re
import struct
import sys

LETTERS = {"I": 0, "O": 1, "P": 2, "U": 4, "K": 5, "L": 6,
           "Y": 8, "J": 9, "M": 10, "T": 12, "H": 13, "N": 14,
           "R": 16, "G": 17, "B": 18, "E": 20, "F": 21, "V": 22,
           "W": 24, "D": 25, "C": 26, "Q": 28, "S": 29, "X": 30,
           "A": 32, "Z": 33, "?": 34}
SYMBOLS = dict(zip("0123456789", [34, 33, 30, 26, 29, 25, 21, 24, 20, 16]))
SYMBOLS.update({".": 32, "-": 17, "+": 22, "=": 18, "(": 9, ")": 5,
                "*": 7, "/": 13, ",": 14, ":": 10, '"': 0, "!": 4, "$": 6, "#": 1,
                "\u00d7": 12, "\u00f7": 8, "\u03c0": 3, "\u00af": 2})
SYMBOLS.update({"{MUL}": 12, "{DIV}": 8, "{PI}": 3, "{NEG}": 2})
NORMALIZE = {"\u201c": '"', "\u201d": '"', "\u2212": "-",
             "\u00a0": " ", "\t": " "}
MAX_KEYS = 4096


KEYS = dict(LETTERS, SEMI=3, COMMA=7, SHIFT=11, ERASE=15, SPACE=19,
            SPECIAL=23, NEXT=27, PREVIOUS=31, BACK=35, QUESTION=34)
PRINTED_SYMBOLS = {k: v for k, v in SYMBOLS.items()
                   if k not in (",", "\u00af", "{NEG}")}
PRINTED_SYMBOLS.update({"%": 28, "\u00a2": 2, "{CENT}": 2})
LOWER = dict(LETTERS, **{",": 7, ";": 3})
TINYBASIC_SYMBOLS = {",": 14, "@": 2}
FUNCTIONS = {name: bit for name, bit in KEYS.items() if len(name) > 1}
BASE_NOTES = [34, 30, 35, 26, 31, 27, 18, 23, 14, 15, 10, 32,
              29, 20, 25, 16, 21, 17, 8, 13, 4, 9, 0, 5, 6, 2, 3]
FIELD_HZ = Fraction(14318181, 228 * 4) / Fraction(525, 2)
MUSIC_REPLAY = 0xfd
MUSIC_RECORD = 0xfe
MUSIC_BANKS = {-12: 0xfa, 0: 0xfb, 12: 0xfc}
RTC_INSERT = 0xf7
MODE_LETTERS = 0xf8
MODE_SYMBOLS = 0xf9


def encode(text, hold_final=False):
    if text.startswith("\ufeff"):
        text = text[1:]
    keys = bytearray()
    for line_no, line in enumerate(text.splitlines(), 1):
        offset = len(line) - len(line.lstrip(" \t"))
        line = line.strip(" \t")
        if not line:
            continue
        for match in re.finditer(r"\{[A-Z]+\}|.", line):
            column = offset + match.start() + 1
            char = match.group()
            char = NORMALIZE.get(char, char)
            if char == " ":
                keys.append(0x80 | 19)
            elif char in SYMBOLS:
                keys.append(0x40 | SYMBOLS[char])
            elif char.isascii() and char.upper() in LETTERS:
                keys.append(LETTERS[char.upper()])
            else:
                raise ValueError(f"line {line_no}, column {column}: unsupported character {char!r}")
        keys.append(0x80 | 27)
    if not keys:
        raise ValueError("source contains no input")
    if hold_final:
        keys.pop()
    if len(keys) > MAX_KEYS:
        raise ValueError(f"source needs {len(keys)} keys; limit is {MAX_KEYS}")
    return b"VBK1" + struct.pack("<HH", len(keys), binascii.crc_hqx(keys, 0xffff)) + keys


def packet(events, rtc=False):
    payload = bytearray()
    for key, hold, gap in events:
        if (key not in range(36) and
                key not in (MODE_LETTERS, MODE_SYMBOLS, *MUSIC_BANKS.values(),
                            MUSIC_REPLAY, MUSIC_RECORD, 255) and
                not (rtc and key == RTC_INSERT)):
            raise ValueError("event must be a matrix key, mode control, music control or WAIT")
        if not 1 <= hold <= 255 or not 0 <= gap <= 255:
            raise ValueError("hold must be 1..255 fields; gap must be 0..255")
        payload.extend((key, hold, gap))
    if not payload or len(payload) > 4096:
        raise ValueError("input must contain 1..1365 timed events")
    return (b"VBK3" if rtc else b"VBK2") + struct.pack("<HH", len(payload), binascii.crc_hqx(payload, 0xffff)) + payload


def wait(events, fields):
    if fields < 1:
        raise ValueError("WAIT must be positive")
    while fields:
        count = min(fields, 255)
        events.append((255, count, 0))
        fields -= count


def physical_keys(text):
    events = []
    rtc = False
    controls = KEYS | {"LETTERS": MODE_LETTERS, "SYMBOLS": MODE_SYMBOLS, "RTC": RTC_INSERT}
    for line_no, line in enumerate(text.splitlines(), 1):
        parts = line.upper().split()
        if not parts:
            continue
        try:
            if parts[0] == "WAIT" and len(parts) == 2:
                wait(events, int(parts[1]))
            elif parts[0] in controls and len(parts) in (1, 3):
                hold, gap = (8, 8) if len(parts) == 1 else map(int, parts[1:])
                events.append((controls[parts[0]], hold, gap))
                rtc |= parts[0] == "RTC"
            else:
                raise ValueError("expected KEY [hold gap], RTC [hold gap] or WAIT fields")
        except ValueError as error:
            raise ValueError(f"line {line_no}: {error}") from error
    return packet(events, rtc=rtc)


def keyboard_text(text, start_mode, profile="keyboard", hold_final=False):
    if start_mode not in ("letters", "symbols"):
        raise ValueError("text input requires --start-mode letters or symbols")
    mode = start_mode == "symbols"
    events = [(MODE_SYMBOLS if mode else MODE_LETTERS, 8, 8)]
    lines = text.removeprefix("\ufeff").splitlines()
    if profile == "text" and (len(lines) > 7 or any(len(line) > 16 for line in lines)):
        raise ValueError("built-in Text accepts at most 7 lines of 16 characters")
    for line_no, line in enumerate(lines, 1):
        for match in re.finditer(r"\{[^}]*\}|.", line):
            char = NORMALIZE.get(match.group(), match.group())
            desired = None
            if char == " ":
                key = 19
            elif profile == "tinybasic" and char in TINYBASIC_SYMBOLS:
                key, desired = TINYBASIC_SYMBOLS[char], True
            elif char in LOWER:
                key, desired = LOWER[char], False
            elif char.isascii() and char.upper() in LOWER:
                key, desired = LOWER[char.upper()], False
            elif char in PRINTED_SYMBOLS:
                key, desired = PRINTED_SYMBOLS[char], True
            elif char.startswith("{WAIT:") and char.endswith("}"):
                wait(events, int(char[6:-1]))
                continue
            elif char[1:-1] in FUNCTIONS and char.startswith("{"):
                key, desired = FUNCTIONS[char[1:-1]], False
                if key == 11:
                    mode = not mode
                    desired = None
            else:
                raise ValueError(f"line {line_no}, column {match.start()+1}: unsupported character {char!r}")
            if desired is not None and desired != mode:
                events.append((MODE_SYMBOLS if desired else MODE_LETTERS, 8, 8))
                mode = desired
            events.append((key, 8, 8))
        # full text lines wrap, next in upper mode selects clock
        if not (profile == "text" and len(line) == 16) and not (hold_final and line_no == len(lines)):
            if mode:
                events.append((MODE_LETTERS, 8, 8))
                mode = False
            events.append((27, 8, 72))
    return packet(events)


def music(text, start_mode, gap=None, min_hold=None, page_notes=None, page_wait=64, replay=False,
          bank_fields=None, bank_ready=False, timing=None):
    if timing is not None:
        if timing not in ("score", "score-ready", "note"):
            raise ValueError("music timing must be score, score-ready or note")
        if bank_fields is not None or bank_ready:
            raise ValueError("timing and legacy bank options are mutually exclusive")
        bank_fields = 2 if timing == "score" else None
        bank_ready = timing in ("score-ready", "note")
    gap = gap if gap is not None else (2 if timing is not None else 8)
    min_hold = min_hold if min_hold is not None else (2 if timing is not None else 8)
    if start_mode not in ("letters", "symbols"):
        raise ValueError("music input requires --start-mode letters or symbols")
    if not 1 <= gap <= 255 or not 1 <= min_hold <= 255:
        raise ValueError("music gap and minimum hold must be 1..255 fields")
    if page_notes is not None and page_notes < 1:
        raise ValueError("--page-notes must be positive")
    if bank_fields is not None and not 1 <= bank_fields <= 255:
        raise ValueError("music bank fields must be 1..255")
    if bank_ready and bank_fields is not None:
        raise ValueError("--bank-ready and --bank-fields are mutually exclusive")
    # shift-space clears the play/record song
    events = [(MODE_SYMBOLS, 8, 8), (19, 8, 64), (MUSIC_RECORD, 8, 8),
              (MODE_LETTERS, 8, 8), (19, 8, 8)]
    music_start = len(events)
    octave, tempo, length, bank = 4, 120, 4, 0
    count = 0
    notes = 0
    sounding = False
    position = 0
    text = text.removeprefix("\ufeff").upper()
    pattern = re.compile(r"\s+|[<>]|[OLT]\d+|[A-GRP][+#-]?\d*\.?", re.ASCII)
    while position < len(text):
        match = pattern.match(text, position)
        if not match:
            raise ValueError(f"MML column {position+1}: unsupported notation")
        token = match.group()
        position = match.end()
        if token.isspace():
            continue
        command = token[0]
        if command in "<>OLT":
            if command == "O":
                octave = int(token[1:])
            elif command == "<":
                octave -= 1
            elif command == ">":
                octave += 1
            elif command == "T":
                tempo = int(token[1:])
                if not 32 <= tempo <= 255:
                    raise ValueError("tempo must be 32..255")
            else:
                length = int(token[1:])
                if not 1 <= length <= 64:
                    raise ValueError("length must be 1..64")
            if not 2 <= octave <= 6:
                raise ValueError("Music Teacher octave must be 2..6")
            continue
        suffix = token[1:].rstrip(".")
        accidental = suffix[:1] if suffix[:1] in ("+", "#", "-") else ""
        if accidental:
            suffix = suffix[1:]
        denominator = int(suffix) if suffix else length
        if not 1 <= denominator <= 64 or (command in "RP" and accidental):
            raise ValueError("invalid note or rest length")
        duration = FIELD_HZ * Fraction(240, tempo * denominator)
        if token.endswith("."):
            duration *= Fraction(3, 2)
        fields = round(duration)
        if command in "RP":
            wait(events, fields)
            count += 1
            continue
        pitch = 12 * (octave + 1) + {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}[command]
        pitch += {"": 0, "+": 1, "#": 1, "-": -1}[accidental]
        if not 36 <= pitch <= 83:
            raise ValueError("Music Teacher range is C2..B5")
        if not 48 <= pitch - bank <= 74:
            bank = next(offset for offset in (0, -12, 12) if 48 <= pitch - offset <= 74)
            control_fields = 8 if bank_fields is None else bank_fields
            if bank_fields is not None:
                remaining = 2 * bank_fields
                # use trailing silence before shortening previous note
                while remaining and len(events) > music_start and events[-1][0] == 255:
                    _, held, released = events.pop()
                    used = min(remaining, held)
                    remaining -= used
                    if held > used:
                        events.append((255, held - used, released))
                if remaining and sounding:
                    key, held, released = events[-1]
                    used = min(remaining, max(0, released - min(gap, bank_fields)))
                    released -= used
                    remaining -= used
                    if held - remaining < min_hold:
                        extra = remaining - (held - min_hold)
                        print(f"warning: note {count+1}: octave switch adds {extra} fields; "
                              "previous note is too short to compensate fully", file=sys.stderr)
                        remaining = held - min_hold
                    events[-1] = (key, held - remaining, released)
            if bank_ready:
                bank_gap = 0
                if timing == "score-ready" and len(events) > music_start:
                    key, held, released = events[-1]
                    if key == 255:
                        bank_gap = min(gap, held)
                        if held == bank_gap:
                            events.pop()
                        else:
                            events[-1] = (key, held - bank_gap, released)
                    else:
                        bank_gap = released
                        events[-1] = (key, held, 0)
                events.append((MUSIC_BANKS[bank], 1, bank_gap))
            else:
                events.append(({-12: 33, 0: 19, 12: 22}[bank], control_fields, control_fields))
        hold = fields - gap
        if not min_hold <= hold <= 255:
            raise ValueError(f"note {count+1}: needs {hold} held fields; choose a slower/faster tempo or length")
        events.append((BASE_NOTES[pitch - bank - 48], hold, gap))
        sounding = True
        notes += 1
        count += 1
        if page_notes and count % page_notes == 0:
            wait(events, page_wait)
    if not sounding:
        raise ValueError("music contains no notes")
    events.extend([(MODE_SYMBOLS, 8, 8), (7, 8, 8), (MODE_LETTERS, 8, 8)])
    if replay:
        events.append((MUSIC_REPLAY, 8, 8))
    data = packet(events)
    if notes > 79:
        print(f"warning: {notes} notes; Record will truncate this song at the "
              "79-note limit. Use Playback for the full file.", file=sys.stderr)
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--profile", choices=("apl", "keyboard", "text", "tinybasic", "keys", "music"), default="apl",
                        help="input profile (music range: C2..B5)")
    parser.add_argument("--start-mode", choices=("letters", "symbols"))
    parser.add_argument("--hold-final", action="store_true", help="omit the final NEXT; earlier lines still submit")
    parser.add_argument("--gap", type=int, help="music key-off fields (default: 2)")
    parser.add_argument("--min-hold", type=int, help="music minimum held fields (default: 2)")
    timing_options = parser.add_mutually_exclusive_group()
    timing_options.add_argument("--timing", choices=("score", "score-ready", "note"),
                                help="score: preserve tempo (default); note: preserve note lengths, "
                                     "adding ROM-acknowledged octave-switch time; score-ready: "
                                     "overlap acknowledged switches with note gaps (requires updated core)")
    timing_options.add_argument("--bank-fields", type=int, help=argparse.SUPPRESS)
    timing_options.add_argument("--bank-ready", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--page-notes", type=int, help="insert a wait at this measured entry interval")
    parser.add_argument("--page-wait", type=int, default=64, help="additional fields at a configured page boundary")
    parser.add_argument("--replay", action="store_true", help="press Music Teacher REPLAY after entry")
    args = parser.parse_args()
    if args.hold_final and args.profile in ("music", "keys"):
        parser.error("--hold-final applies to text input")
    if (args.replay or args.page_notes is not None or args.timing is not None
            or args.bank_fields is not None or args.bank_ready) and args.profile != "music":
        parser.error("music timing, bank options, --replay and --page-notes require --profile music")
    try:
        text = args.source.read_text(encoding="utf-8")
        if args.profile == "apl":
            data = encode(text, args.hold_final)
        elif args.profile == "keys":
            data = physical_keys(text)
        elif args.profile == "music":
            legacy = args.bank_fields is not None or args.bank_ready
            timing = args.timing or (None if legacy else "score")
            data = music(text, args.start_mode, args.gap, args.min_hold,
                         args.page_notes, args.page_wait, args.replay,
                         args.bank_fields, args.bank_ready, timing)
        else:
            data = keyboard_text(text, args.start_mode, args.profile, args.hold_final)
        output = args.output or args.source.with_suffix(".vbk")
        if output.resolve() == args.source.resolve():
            raise ValueError("output would overwrite source")
        output.write_bytes(data)
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f"error: {error}\n")
    print(f"{output}: {len(data)-8} payload bytes, {data[:4].decode('ascii')}")


if __name__ == "__main__":
    main()
