# Tiny BASIC checks

Use Tiny BASIC cancelfix (CRC32 F3BFF3D3) with Mapper Fallback set to
4K RAM. Wait for the input prompt, then select Keyboard > Load Keyboard
File. Load one file at a time with automatic repeat disabled. Keep hands
off the keyboard while loading. Each file selects letter mode initially
and ends in letter mode.

These are VBK2 inputs. Cores supporting automatic Tiny BASIC acknowledgement
wait for each key and command to complete; older cores use the encoded timing.
See [acknowledged entry](../../docs/KEYBOARD-INPUT.md#tiny-basic-acknowledged-entry).
File integrity and source regeneration are
checked; interpreter results still require MiSTer testing. Stop at the
first unexpected result and report the filename and displayed output.
Leading spaces before numbers are allowed.

See the [direct color values and text-color commands](../../docs/TINYBASIC-COLORS.md).

## Enhanced acceptance

Files 27-33 extend the checks for Tiny BASIC Enhanced. They are generated
VBK2 inputs, also copied to the software library's Tiny BASIC/Examples
directory. Load them one at a time after the Enhanced prompt appears.
Each replaces the current program with NEW. Files 27-29 pass on Enhanced
0.8. Files 25 and 30-33 pass on Enhanced 1.0.

Enhanced 1.0 passes the smoke program and a complete Nim game on hardware:
inline IF, THEN branches, numeric INPUT, mixed string/numeric PRINT, integer
division, and return to READY. Lunar Lander reaches SAFE LANDING and
Treasure Maze reaches OUT OF TIME and GAME OVER. Pig Dice reaches the seed
prompt; gameplay remains pending. Both serial sessions are clean, with no
framing or overflow errors. Remaining acceptance includes BACK across
a 24-column boundary, cancellation, input and stack limits, program-memory
exhaustion, and readable prompts and error locations while scrolling.

| File | Expected result |
| --- | --- |
| `27-relations-if.vbk` | 1, 0, 1, 0, PASS, DONE. Neither BAD branch executes. |
| `28-random-bounds.vbk` | 1, then twelve random integers from 1 through 6 inclusive, then DONE. |
| `29-peek-poke.vbk` | 42, 42, 0. The POKE changes the low byte of array element @(1), then the element is cleared. |
| `30-print-layout.vbk` | 7 and 8 in three-character fields; AB on one line from successive PRINTs; AB from CHR; Y after four leading spaces; DONE. |
| `31-array-string-aliases.vbk` | 123, 456, HELLO, 5. Strings share numeric variable storage. |
| `32-list-stop.vbk` | LIST prints only lines 20 and 30. RUN prints SECOND and stops; BAD is not printed. |
| `33-input-expression.vbk` | VALUE prompt accepts 2+3*4, then PRINT outputs 14 and 28. |

Jerry D. Fox's *Tiny BASIC for the F8*, Dr. Dobb's Journal no. 39,
documents these features. The VideoBrain port calls the machine-code
entry command USR rather than the article's CALL; MON resets to the BIOS.
Those commands are excluded from these language checks.

Relational syntax is `>=`, `#` (not equal), `>`, `=`, `<=`, `<`.
Enhanced 1.3 maps `<` and `>` to Shift+T and Shift+Y. File 27 covers
the available `=` and `#` operators. Comparisons return 1 for true and 0
for false.

## Enhanced additional checks (34-37)

Files 34-35 require Enhanced 1.1 or later; tape checks require 1.2.
Hardware acceptance for the relational aliases and background color is pending.

| File | Expected result |
| --- | --- |
| `34-relational-aliases.vbk` | GE: 1, 1, 0; GT: 1, 0, 0; LE: 1, 1, 0; LT: 1, 0, 0; four signed comparisons produce 1; PASS, DONE. No BAD output. |
| `35-background-color.vbk` | Background changes to colors 4, 6 and 0; prints COLOR 4, COLOR 6, DONE. |
| `36-tape-save.vbk` | With Expander firmware loaded and a writable record tape mounted, saves the test program and reports TAPE OK. |
| `37-tape-load.vbk` | Mount the saved tape for playback and rewind first. LOAD reports TAPE OK; LIST shows lines 10-50; RUN prints TAPE PASS, 7 and 9. |

GE, GT, LE and LT stand for `>=`, `>`, `<=` and `<`. `COLOR expression`
accepts values 0-31. These checks replace the current program with NEW.

File 36 replaces the program; file 37 replaces it with the tape contents.
Wait for TAPE OK and the record deck becoming idle before mounting the saved
image for playback. A failed LOAD reports TAPE ERROR and clears the program.
SAVE/LOAD preserve program text, including DATA, rather than variable or array
values. Enhanced 1.2 passes a hardware round trip with a 39-byte INPUT program:
VBK entry, SAVE, core reload, playback-only mounting, LOAD, LIST and RUN.
The saved record has a valid CRC. Multi-record hardware acceptance remains pending.

## Color combinations (38-42)

Require Enhanced 1.3 with TCOLOR. Each file replaces the current program and
runs to completion. Run 40 with both Video > Colors settings; other checks
also work in either mode. TCOLOR recolors the entire text display, so these
are sequential color changes rather than simultaneous multicolor text rows.

| File | Expected result |
| --- | --- |
| `38-color-pass.vbk` | Checks arithmetic, FOR/NEXT, GOSUB, DATA, signed comparison and both text-color spellings. White PASS on green when all checks succeed; white FAIL on red otherwise. |
| `39-text-rainbow.vbk` | Text cycles red, yellow, green, cyan, blue and magenta twice, then returns to white and prints RAINBOW DONE. |
| `40-text-intensities.vbk` | Cycles text through codes 0-31 on black, then restores white and prints 32 CODES DONE. Some steps are invisible against black. Original mode repeats colors; Patent mode distinguishes the intensity groups. |
| `41-color-combinations.vbk` | Six contrasting background/text pairs, with their values printed. Finishes white on black with COMBINATIONS DONE. |
| `42-color-scroll.vbk` | Prints 24 numbered rows and squares in cyan, scrolling past the 15-row display. Text stays cyan while scrolling; finishes white on green with SCROLL DONE. |

The color cycles use finite delay loops. Serial mirroring affects their speed.
DATA lines execute before READ; RESTORE rewinds the initialized data pointer.
Re-enter RUN to repeat; load another VBK to replace the program. The green
background in 42 marks completion; 38 also checks computed results. Visual
palette accuracy still requires inspection on MiSTer.

## IF syntax probes (23-26)

`THEN` is an alias for `GOTO` and requires a line-number expression.
Use `IF A=7 THEN 50` to branch, or `IF A=7 PRINT "PASS"` for an inline
statement. Do not put `THEN` before an inline statement.

Files 23, 24 and 26 pass on Enhanced 0.8. File 25 uses inline IF without
THEN and prints PASS, DONE on Enhanced 1.0.
`IF A=7 THEN PRINT "PASS"` is invalid and reports WHAT on line 20.

## Baseline results

Hardware results on recordfix: files 01, 02, and corrected 03 pass.
Mixed output has a small numeric spacing gap and no WHAT errors.
File 04 provisionally passes: final RUN output is A, X. Exact edited
LIST contents have not been separately confirmed.
Files 05 and 06 pass on hardware, including their final DONE output.
Files 07 and 08 pass: SUB/BACK and numeric INPUT producing 5.
Files 09 and 10 pass: DATA/RESTORE and recovery after HOW/WHAT errors.
Files 11 and 12 pass: negative STEP and nested GOSUB/RETURN.
File 15 passes: nested FOR produces 11, 12, 21, 22, DONE. The small
display can scroll the first result out of view before completion.
Files 13 and 13b pass on stringfix: HI/2 and A/ABC/ABCD/4. The original
recordfix displays a fallback glyph for the marked final character.
Files 16 and 17 pass on stringfix: string INPUT, ABS, integer division,
and true/false equality results.
File 18 fails on stringfix at BACK on an empty input line (WHAT after
the initial 12). Tests 18 and 18b pass on inputfix CRC32 FC982273:
12/2 and 3/4. Earlier repeated failures used the wrong ROM.
File 19 passes on stringfix.
File 20 fails on inputfix: 2, 3 instead of 14, 3. It passes on cancelfix
CRC32 F3BFF3D3: 14, 3. This is the current tested variant.
Files 21 and 22 pass on cancelfix: excess input is discarded and stack
exhaustion reports SORRY before accepting the next command. The displayed
line 10 with a question-mark marker is the normal error-location display.
SPECIAL starts a new input line; old X characters remain on earlier rows.
Tiny BASIC types comma with SHIFT+N;
the generic keyboard profile instead sends the ordinary COMMA key,
which entered the wrong separator (observed as / on hardware). The
experimental bank-only PRINT ROM is not required by this test result.

| File | Expected result |
| --- | --- |
| `01-signs.vbk` | 1, then -1, without stray sign symbols. |
| `02-arithmetic.vbk` | 14, then 20. |
| `03-mixed-output.vbk` | A followed by 1; 1 followed by 2; B followed by 5. |
| `04-line-editing.vbk` | LIST shows only lines 10 and 20, printing A and X. RUN prints A, X, then READY. |
| `05-goto.vbk` | 1, 2, 3, DONE, then READY. |
| `06-for-next.vbk` | 1, 2, 3, DONE, then READY. |
| `07-gosub.vbk` | SUB, BACK, then READY. |
| `08-input.vbk` | Enters 4 at the INPUT prompt; prints 5, then READY. |
| `09-data-restore.vbk` | 7, 9, 7, then READY. |
| `10-error-recovery.vbk` | HOW, 2, WHAT, 3; each command returns to READY. |
| `11-negative-step.vbk` | 3, 2, 1, DONE, then READY. |
| `12-nested-gosub.vbk` | OUTER, INNER, RETURNED, BACK, then READY. |
| `13-strings.vbk` | HI, 2, then READY. |
| `13b-string-lengths.vbk` | A, ABC, ABCD, 4, then READY. |
| `14-arrays.vbk` | 16, then READY. |
| `15-nested-for.vbk` | 11, 12, 21, 22, DONE, then READY. |
| `16-string-input.vbk` | Enters HI at the INPUT prompt; prints HI, 2, then READY. |
| `17-numeric-functions.vbk` | 7, 3, 1, 0; each command returns to READY. |
| `18-backspace.vbk` | 12, then 2; tests ordinary deletion and BACK on an empty input line. |
| `18b-backspace-boundary.vbk` | 3, then 4; repeated BACK on empty input and deletion back to empty. |
| `19-multiple-statements.vbk` | 2, 3, DONE, then READY. |
| `20-cancel-line.vbk` | Cancels 64 X characters with SPECIAL; prints 14, then 3. |
| `21-input-limit.vbk` | 2, then 3; excess X characters after 71 input characters should be discarded. |
| `22-stack-limit.vbk` | SORRY on recursive GOSUB, then 3 from the next command. |
| `23-then-line.vbk` | `IF A=7 THEN 50`; PASS, DONE. |
| `24-no-then.vbk` | `IF A=7 GOTO 50`; PASS, DONE. |
| `25-then-print.vbk` | `IF A=7 PRINT "PASS"`; PASS, DONE. |
| `26-goto-alone.vbk` | `GOTO 30`; PASS. |

Files 04-09, 11-16, 13b, 19, and 22-33 run NEW and replace the current BASIC program. The loops are
intended to terminate; if interpreter execution fails to finish, use
MASTER CONTROL and reload the cartridge before continuing.
File 22 deliberately exhausts the software stack. It should report
SORRY and recover; reset if it fails to return to the prompt.

Rebuild each matching text source from the repository root:

```sh
python tools/keyboard_input.py examples/tinybasic-examples/01-signs.txt --profile tinybasic --start-mode letters
```

## Display control (43)

Requires Enhanced 1.4. `43-display-control.vbk` replaces the program and
prints TOP LEFT at (0,0), CENTER at (12,7), and DISPLAY OK at (0,11).
CLS preserves the program and colors; MOVE uses zero-based character positions.

## Additional display and keyboard checks (44-48)

Files 44-47 require Enhanced 1.4. File 48 requires the Shift+T/Y symbol
mapping. Each file replaces the current program. Results await MiSTer testing.

| File | Expected result |
| --- | --- |
| `44-cls-state.vbk` | ERASE ME disappears. Prints KEEP, 123 and 456, then CLS PASS on green. Checks CL. inside GOSUB, variable/array preservation, retained colors and cleared bitmap samples. |
| `45-move-grid.vbk` | L/R at columns 0/22 on rows 0/10; X at (12,7). MOVE GRID DONE at (0,2). Checks expression coordinates, MOV. and PRINT without a newline. |
| `46-move-scroll.vbk` | Counts 1-20, clears, then MOVE SCROLL PASS on green. Checks (23,14), expression coordinates and visible-row positioning after scrolling. |
| `47-move-errors.vbk` | Six HOW errors, then two WHAT errors; recovery PRINTs produce 1-8. RUN still prints ERROR RECOVERY OK. |
| `48-symbol-comparisons.vbk` | Eight PASS lines for symbolic and word comparisons, then COMPARE PASS on green. No FAIL output. |

Coordinates are zero-based. READY and the input prompt appear after completion;
file 45 leaves them below MOVE GRID DONE. CLS FAIL, MOVE SCROLL FAIL or
COMPARE FAIL on red indicates a failed check. Re-enter RUN to repeat stored
programs; file 47's invalid direct commands require reloading its VBK to repeat.
