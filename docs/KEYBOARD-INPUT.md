# Keyboard input files

Choose **Keyboard > Load Keyboard File** and select a `.vbk`. A keyboard key cancels entry. **Keyboard > Menu Aborts VBK > Off** lets entry continue while the OSD is open.

See [converter commands and options](../tools/README.md#keyboard-files).

`--profile apl` is the default. Text profiles require `--start-mode`: `letters` means lower/unshifted; `symbols` means upper/shifted. Generated VBK2 files establish that mode and request later mode changes using the tracked SHIFT latch. Music synchronizes its own mode. Regenerate older files to use this behavior; updated files require a core supporting F8/F9 mode controls. The physical `keys` profile retains raw SHIFT toggles.

## Set built-in clock from RTC

With no cartridge inserted, load `examples/clock-from-rtc.vbk` from **Keyboard > Load Keyboard File**. It selects CLOCK, enters the host local date and time, then starts the clock. The script is intended for the built-in clock screen, not cartridges.

`examples/clock-from-rtc-v2.vbk` is an alternative for a clock that has not yet been set. It selects CLOCK, ensures upper SHIFT, enters the RTC digits, sends one additional 0 to advance to the start screen, ensures lower SHIFT, then presses G. The source uses QUESTION for the physical 0/? key. It sends no S and inserts no wait. The revised file requires hardware verification.

The new `VBK3` format accepts `RTC [hold gap]` in the physical-keys converter. It expands to the 16 physical numeric keys for `YYYYMMDDWWHHMMSS` when reached. `WW` is Monday=01 through Sunday=07. Existing VBK1/VBK2 files are unchanged; an older core rejects VBK3.

MiSTer supplies RTC once at core startup. The loader advances it locally and allows roughly four seconds for the numeric keypresses. The host RTC must be set; this feature does not synchronize time over the network itself. Clock setting on hardware still needs verification.

## APL/S source entry

Boot the Computational Language cartridge and wait for its input prompt before loading a `.vbk`. Once the OSD closes, the core types the listing. Canceling leaves partial input; reset or reload the cartridge before retrying a partial listing.

The bundled [Price games and listings](../examples/21-apl_s-games-james-price) come with `.txt` sources and ready-to-load `.vbk` files.

The [APL/S manual chapter 6 listings](../examples/apl-s-manual-chapter-6) include numerical utilities, inverse trig functions, bar-graph demos and games from printed pages 49-59.

### Starting a program

Load a definition and wait for entry to finish. Type its launch name in letter mode, then press NEXT (PC F3 or Enter). No RUN command is needed. SHIFT toggles letter/symbol mode; use symbol mode for numbers and NEXT after each answer.

| File | Launch | Use |
| --- | --- | --- |
| `04-guess.vbk` | `GUES` | Enter a limit, then guess the number. |
| `08-acey.vbk` | `ACEY` | Starts with cash 100 and two cards. Bet on the third card falling strictly between them; `99` at BET? exits. |
| `20-bulls.vbk` | `MOO4` | Enter four distinct digits separated by spaces. WHITE/RED counts report exact/misplaced matches; `99` exits. |
| `22-roulette.vbk` | `RO` | Follow the betting prompts; `3` then `99` at the next round exits. |
| `23-change.vbk` | `C` | Starts with X=89 and calculates coin change. |

Immediate expressions, such as `01-sine.vbk`, execute as they are entered. For other programs, see the launch name and prompts in their `.txt` source. Roulette preserves the printed listing's omission of 23 from both betting lists.

Gunner corrects the printed listing's `BAR -30` and `BAR 30` to `BARH -30` and `BARH 30`. The original lines cause a syntax error; continued automatic entry appends later text to the rejected line and can produce repeated `SYNTAX 168` errors. Restart from a fresh cartridge prompt before loading the corrected file.

Dicejack uses `BUSTED` instead of the printed dealer message `I BUSTED`, matching the stored dump. The longer message exceeds APL/S's 255-byte program limit, causing `CAPACITY 6` followed by `SYNTAX 6` at the final `ENDE`. Launch the corrected program with `D`.

### Preparing a listing

See [keyboard converters](../tools/README.md#keyboard-files) for commands. Supply UTF-8 text containing exactly the lines to enter at the APL/S prompt. Program definitions must include EDIT and ENDE; remove printed headings, line numbers and OCR errors. Each nonblank line ends with NEXT.

To load a definition without running it, end the source with ENDE and omit its launch command. ENDE must receive NEXT to finish the definition. `--hold-final` leaves the final line unsubmitted; earlier lines still submit and may execute. Do not use it on a final ENDE for a completed definition.

Letters become uppercase. Blank lines and surrounding indentation are ignored; CRLF and LF are accepted. Tabs and nonbreaking spaces become spaces, smart double quotes become plain quotes, and Unicode minus becomes hyphen. Multiplication, division, pi and high minus accept the corresponding Unicode characters or `{MUL}`, `{DIV}`, `{PI}` and `{NEG}`. ASCII `*` means exponentiation. Unsupported characters are rejected with their line and column. The limit is 4096 key tokens, including spaces and NEXT.

APL/S entry waits for the interpreter to accept each key and its release. After NEXT, it waits for parsing, execution and screen updates before typing the next line. There is no entry-speed setting. Timed VBK2 files, including music, use their encoded timings; see [Music Teacher 1](#music-teacher-1).

## Text and title behavior

`keyboard` uses the printed keyboard: letters become uppercase, comma and semicolon use their lower keys, numbers use upper keys. Unlike APL/S, P's upper character is cent, not high minus. `{CENT}`, `{MUL}`, `{DIV}` and `{PI}` are accepted. Whitespace and blank lines are preserved. Each line ends in lower NEXT unless `--hold-final` suppresses the last one. NEXT receives an additional 72 released fields. No RUN is appended. `{BACK}`, `{ERASE}`, `{NEXT}`, `{PREVIOUS}`, `{SPECIAL}`, `{SPACE}`, `{SHIFT}` and `{WAIT:120}` are available.

| Program | Entry behavior and profile |
| --- | --- |
| Built-in Text | Enter TEXT manually with upper SHIFT, then check its dark/lower indicator. Use `text --start-mode letters`. Seven lines of 16 characters; full lines wrap automatically, so the converter omits their NEXT. NEXT moves down; upper NEXT selects CLOCK. Start with an empty display. |
| Financier / VB-81 | Use `keyboard`. Its cursor starts L (lower); SHIFT toggles U/L. NEXT submits formulas, commands or answers. Maximum formula: three lines of 15 characters. BACK erases; PREVIOUS and SPECIAL are ignored. |
| Money Minder / VB-1000 | Use `keys`. It replaces text entry with a cash-register layout. Digits are the printed numeric positions without automatic SHIFT; punctuation and dollar formatting are automatic. Category keys depend on SHIFT. SPACE is ENTER/INITIAL VALUE, not a text space. Follow its account prompts. |
| Wordwise 1 | Use `keys` for numeric position moves and NEXT; it builds words by moving displayed letters, rather than by typing words. |
| Wordwise 2 | Its typing exercises accept printed character keys. Use `keyboard` for an appropriate exercise or `keys` for prompts; inspect the expected line before submitting NEXT. |
| Timeshare | F5 sends Carriage Return; F4 is CONTROL. Shift is held, not toggled; Shift+H types `/`. Hold F4 + Shift and tap D for full duplex or H for half duplex/local echo. Use manual input for its held-key combinations. See [Timeshare setup and keys](EXPANDER1.md#timeshare-over-uart). |
| Other titles, including Information Manager | Use physical key scripts that follow the program's prompts and SHIFT behavior. |

VBK2 files can be loaded in any program; use the profile that matches its current screen and key handling. Automatic mode selection requires the standard SHIFT latch; use physical key scripts for programs with custom SHIFT handling.

## Physical keys

One event per line: `KEY`, `KEY hold gap`, or `WAIT fields`. Times are video fields (about 60 per second), not milliseconds. Bare keys use 8/8. Key names are letters and SEMI, COMMA, QUESTION, SHIFT, ERASE, SPACE, SPECIAL, NEXT, PREVIOUS, BACK. They refer to physical keys, irrespective of program meaning. WAIT holds no key. Holds are 1..255 fields; gaps are 0..255. Long waits split into events. MASTER CONTROL is excluded because it resets/cancels entry.

## Music Teacher 1

Select Program 1 / Play-Record manually, then load an example from `examples/music`. Each generated song synchronizes SHIFT, erases the previous recording, selects Middle, enters the notes, and ends with No-Record and lower SHIFT. **Keyboard > Music Mode** selects **Playback** (default) or **Record**. Record enables the cartridge recorder; `--replay` presses REPLAY afterward. Playback keeps Record off and ignores that replay request, playing the file live. Regenerate older music files to use mode synchronization and the Record/Replay selectors. After recording, press physical T to replay the stored song again. **Keyboard > Music Repeat** restarts the file from the top until entry is canceled. Repeat forces Playback and grays out Music Mode, preserving the selected mode for when Repeat is turned off. The loader does not wait for the cartridge's Replay routine. Each music pass establishes its own SHIFT mode. This uses the cartridge's own recorder and sound routines; the loader supplies no replacement audio engine.

The monophonic MML subset accepts A-G, `#`/`+` sharp, `-` flat, O2-O6, `<`/`>`, T32-T255, L1-L64, per-note lengths, one dot, and R/P rests. Default: O4, T120, L4. C4 means middle C. Range: C2 through B5, checked after accidentals; O6 permits only C- (B5). Chords, ties, loops, voices and other MML commands are rejected. MML conventions follow the [QB64 PLAY notation](https://qb64phoenix.com/qb64wiki/index.php/PLAY).

```text
T100 O4 L4 C C G G A A G2 F F E E D D C2
```

The manual's Middle layout uses S for C4, D/F/G/H/J/K for D4..B4 and L for C5. Lower staff C3..A3 uses QUESTION, BACK, PREVIOUS, NEXT, SPECIAL, ERASE. The black-note keys complete the chromatic scale. Z selects Low (-1 octave), V High (+1), SPACE Middle. Shifted SPACE erases, shifted Z records, shifted COMMA selects No-Record, and unshifted T replays. Octave controls select a fixed bank; repeated Low/High does not step indefinitely. The cartridge's key table and bank routine confirm Low C2..D4, Middle C3..D5, and High C4..B5.

The converter keeps the current octave bank while it contains the next pitch. Choose one of two music timing styles. Both default to `--min-hold 2 --gap 2`:

- **Score timing** (`--timing score`, default) fits a four-field octave-switch allowance into preceding rests or release gaps, then shortens the preceding held note if needed. At least two held and two released note fields remain with the defaults. If insufficient time remains, the converter warns and adds the excess delay. A switch before the first note adds startup time.
- **Acknowledged score timing** (`--timing score-ready`, experimental) starts each octave switch inside the preceding note's key-off gap or the end of a rest. It uses ROM acceptance and release signals, and starts the next note when both the musical gap and the handshake are complete. Held notes are not shortened. This requires a core supporting overlap gaps on FA/FB/FC events; use the Better Playback patch for faster ROM input handling. A handshake that exceeds the gap still delays the next note.
- **Note timing** (`--timing note`) preserves note/rest durations and adds the minimum ROM-acknowledged octave-switch time. The loader presses the bank key when the ROM is ready, releases it when accepted, then waits for confirmed readiness before continuing. Each stage times out after 255 fields.

With a recognized Music Teacher 1 cartridge, unshifted Z/SPACE/V events also use the octave handshake, including older fixed-duration files. The loader releases the key when accepted, but preserves the full encoded hold-plus-gap interval before the next event. That interval runs concurrently with readiness, acceptance and release. A slow switch can delay the next note. Timeout stops playback with an error. Shifted Record and Erase commands retain their encoded timing.

Timing is rounded to video fields; the key-off gap is included in each note's duration.

Ready-to-load songs are in [music examples](../examples/music/README.md).

The manual specifies songs of up to 80 notes; this ROM's recorder appears to stop at 79 note/rest records. Key-off gaps may also consume entries. The loader enters at most 79 note keys in Record mode, skipping the remaining music and delays before No-Record and optional Replay. Rests and bank changes do not count toward this input limit, but may leave fewer notes in the cartridge's recording. Playback bypasses recorder capacity; files still have a 1365-event limit, including control keys, octave changes and waits. The converter warns above 79 notes that Record will truncate the song.
