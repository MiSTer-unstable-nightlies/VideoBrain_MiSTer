# Tiny BASIC checks

Use Tiny BASIC cancelfix (CRC32 F3BFF3D3) with Mapper Fallback set to
4K RAM. Wait for the input prompt, then select Keyboard > Load Keyboard
File. Load one file at a time with automatic repeat disabled. Keep hands
off the keyboard while loading. Each file selects letter mode initially
and ends in letter mode. Commands pause for about 1.2 seconds after Enter.

These are VBK2 timed inputs. File integrity and source regeneration are
checked; interpreter results still require MiSTer testing. Stop at the
first unexpected result and report the filename and displayed output.
Leading spaces before numbers are allowed.

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

Files 04-09, 11-16, 13b, 19, and 22 run NEW and replace the current BASIC program. The loops are
intended to terminate; if interpreter execution fails to finish, use
MASTER CONTROL and reload the cartridge before continuing.
File 22 deliberately exhausts the software stack. It should report
SORRY and recover; reset if it fails to return to the prompt.

Rebuild each matching text source from the repository root:

```sh
python tools/keyboard_input.py examples/tinybasic/01-signs.txt --profile tinybasic --start-mode letters
```
