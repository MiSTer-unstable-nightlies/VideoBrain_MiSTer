# Tools

Run commands from the repository root. Python tools require Python 3.9 or
later; use `python` instead of `python3` where appropriate.

## Telehack

Copy [telehack.sh](telehack.sh) to `/media/fat/Scripts/` and run it from MiSTer's
Scripts menu. It waits for F5 from Timeshare before connecting; run it again
to stop. See [Timeshare setup](../docs/EXPANDER1.md#internet-connection).

## BIOS

Combine the two 2,048-byte BIOS dumps in RES1, RES2 order using a POSIX shell:

```sh
sh tools/make_boot_rom.sh uvres1.bin uvres2.bin boot0.rom
```

See [installation](../README.md#installing) for ROM checksums and placement.

## Cartridges

`convert_software.py` assembles APL/S and Information Manager from MAME chip
archives. Supply a directory containing `vidbrain (MAME)/complang.zip` and
`vidbrain (MAME)/infoman.zip`; assembled images go in its `converted/` folder.

```sh
python3 tools/convert_software.py /path/to/roms
```

See [cartridge layouts](../docs/CARTRIDGES.md#split-cartridge-conversion).
ROMs and firmware are not bundled.

`patch_music_teacher.py` and `patch_infoman_printer.py` each take an original
ROM path and a separate output path. The Music Teacher patch is experimental
and suppresses staff rendering. Version 0.5 corrects G#2 and C2 tuning while
preserving or improving their octaves, fifths and fourths. It polls Program 1
input directly and services video when the BIOS RAM threshold and video Y permit it, without
waiting for a field. Minimum octave timing uses ROM-acknowledged bank controls;
ordinary unshifted octave keys also wait for ROM acceptance and release. Experimental
`--timing score-ready` overlaps acknowledged switches with musical gaps and
requires the corresponding loader update.
Hardware validation remains necessary.
For the Information Manager correction option,
see [printer capture](../docs/PRINTER.md#capture-a-report-or-session).

## Keyboard files

Convert APL/S input, text, physical keys or Music Teacher MML to `.vbk`:

```sh
python3 tools/keyboard_input.py program.txt program.vbk
python3 tools/keyboard_input.py text.txt text.vbk --profile keyboard --start-mode letters
python3 tools/keyboard_input.py basic.txt basic.vbk --profile tinybasic --start-mode letters
python3 tools/keyboard_input.py keys.txt keys.vbk --profile keys
python3 tools/keyboard_input.py examples/clock-from-rtc.txt examples/clock-from-rtc.vbk --profile keys
python3 tools/keyboard_input.py music.mml music.vbk --profile music --start-mode letters
```

The default `keyboard_input.py --profile apl` generates
APL/S input with NEXT after each nonblank line. `--hold-final` leaves the
last line unsubmitted. The `text` profile handles the built-in Text screen;
`keyboard` follows the printed keyboard. Both require `--start-mode`, which
the generated file establishes using tracked SHIFT state. Music synchronizes
SHIFT automatically and finishes in lower mode. Regenerate older VBK2 files
to use mode synchronization; updated files require a core supporting F8/F9.
The `keys` profile accepts physical key scripts such as `NEXT 8 8` and
`WAIT 120`, with durations in video fields.

The `tinybasic` profile uses Tiny BASIC's comma mapping (SHIFT+N) instead
of the printed COMMA key, and supports `@` with SHIFT+P for arrays.
It also requires `--start-mode`.

Music conversion defaults to score timing. `--timing note` retains note
lengths and adds octave-switch time; `--replay` requests replay after entry.
Use `--help` for all options. See [keyboard input](../docs/KEYBOARD-INPUT.md),
[APL/S entry](../docs/KEYBOARD-INPUT.md#apls-source-entry) and [examples](../examples/README.md).

## Printer images

Copy `examples/blank-printer.vbp` to a new name and mount it under Printer in
the OSD, or create one with Python:

```sh
python3 tools/new_printer.py session.vbp
python3 tools/extract_printer.py inspect session.vbp
python3 tools/extract_printer.py export session.vbp printer.bin
```

The creator defaults to a 1 MiB image; `--size BYTES` changes its capacity.
Omit its filename to create a timestamped name. Creation and extraction are
independent scripts.

After Stop and Save, wait for Ready and unmount before exporting. Export
preserves all eight bits and exact payload length. It refuses existing outputs
and incomplete/error sessions unless `--recover` is explicit. Optional
`--session N`, `--text FILE`, `--remove-nul` and `--normalize-crlf` select a
session or create a separate readable copy. See [printer images](../docs/PRINTER.md)
for operation, format, errors and hardware validation limits.

`capture_printer.py` remains the shared-UART diagnostic tool. Select System >
UART Output > Printer for it; simultaneous modem service uses the mounted-image
path instead.

## Tape images

`new_tape.py`, `trim_tape.py` and `tape_convert.py` create blank images, trim
unused capacity and convert VBT/WAV waveforms. See [tape images](../docs/TAPE.md).

```sh
python3 tools/new_tape.py recording.vbt
python3 tools/trim_tape.py recording.vbt trimmed.vbt
python3 tools/tape_convert.py to-wav recording.vbt recording.wav
python3 tools/tape_convert.py to-vbt recording.wav recording.vbt
```

Each script runs independently and refuses existing outputs. The blank creator
defaults to 8 MiB and accepts an omitted filename for a timestamped name.

## SHA1 reports

```sh
python3 tools/sha1.py /path/to/roms
```

Recursively hashes BIN, VBT, VBK, VBP and ROM files, sorted by title, and writes
`sha1-hashes-by-title-videobrain_YYYYMMDD.txt` in the selected folder. With no
folder argument it scans the script's own folder. Use `--overwrite` to replace
the same day's report. Media and companion notes are unchanged.
