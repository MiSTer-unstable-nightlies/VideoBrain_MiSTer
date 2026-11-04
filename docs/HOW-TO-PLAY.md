# How to play and use VideoBrain software

Control references for the built-in programs and all eighteen cartridges. The illustrations are extracts from the original manuals. They describe the original software; see [cartridge coverage](CARTRIDGES.md) for hardware-tested behavior and remaining limits. Click an image to read it at full size.

## Contents

- [Keyboard and controllers](#keyboard-and-controllers)
- [Built-in Text, Clock, Alarm, and Color](#built-in-programs)
- [APL/S](#apls), [Financier](#financier), [Money Minder](#money-minder), [Information Manager](#information-manager), [Timeshare](#timeshare)
- [Music Teacher 1](#music-teacher-1), [VideoArtist](#videoartist), [Wordwise 1](#wordwise-1), [Wordwise 2](#wordwise-2), [Math Tutor 1](#math-tutor-1)
- [Blackjack](#blackjack), [Checkers](#checkers), [Gladiator](#gladiator), [Lemonade Stand](#lemonade-stand), [Pinball](#pinball), [Tennis](#tennis), [Vice Versa](#vice-versa), [Demonstration](#demonstration)

## Keyboard and controllers

The core maps physical VideoBrain key positions. A cartridge can give those keys different meanings, as shown in its manual overlay. Every special key has a PC alias, listed below. These aliases follow the same SHIFT mode and cartridge functions. Ctrl+Enter (including keypad Enter, with either Ctrl key) sends F5, giving Timeshare a carriage return. The Enter destination is chosen when pressed and stays the same until released.

![Original VideoBrain keyboard](../images/VB_Keyboard.gif)

| PC key | VideoBrain key position |
| --- | --- |
| F1 / Backspace | BACK / TEXT |
| F2 / Home | PREVIOUS / COLOR |
| F3 / Enter / keypad Enter | NEXT / CLOCK |
| F4 / End | SPECIAL / ALARM |
| F5 / Ctrl+Enter | ERASE / RESTART |
| Space | SPACE / RUN/STOP |
| Shift | SHIFT |
| `/` key | `?` / `0` |
| Esc | MASTER CONTROL |

Letters, comma, and semicolon use their matching PC keys. The PC number row and numeric keypad map `1234567890` to VideoBrain positions `ZXCSDFWER/`. These aliases do not change SHIFT: use numeric mode when the software requires it; in letter mode they produce the corresponding letters (or `?` for `0`). Cartridge overlays can give these positions other meanings. Other symbols use the VideoBrain layout. SHIFT toggles in the BIOS, APL/S, and Financier; Timeshare uses held Shift. Follow each title's controls.

**Keyboard > Esc Soft Reset > Off** disables keyboard Master Control to protect against accidental presses beside F1. **System > Master Control (Soft Reset)** remains available. Master Control can discard entered work; it is not a backspace.

The manuals' HIT or trigger button is MiSTer's **Fire**. Joystick numbers refer to the four VideoBrain sockets. Use **Joysticks > Calibrate Sticks** while a game is reading its joysticks. **Joysticks > Paired Sticks** can assign a controller's right stick and **Fire (Paired)** to a second socket. See [joystick setup](JOYSTICK.md).

## Built-in programs

Unload the cartridge to use Text, Clock, Alarm, and Color. In the BIOS, select upper SHIFT mode, then F1 for TEXT, F2 for COLOR, F3 for CLOCK, or F4 for ALARM. The lower-right square is light in upper mode and dark in lower mode. Switch back to lower mode to type letters in TEXT.

In Text, F1 backs up, F2 moves to the preceding line, F3 moves to the next line, and F5 erases the character under the cursor. F4 opens Special mode, where the letter keys select effects; F4 again leaves it. Clock and Alarm use their own setting prompts and the original keyboard's numeric positions.

![Text editing and Special mode, owner's manual pp. 11-12](../images/controls/bios-text.jpg)

<details>
<summary>Clock, Alarm, and Color instructions (owner's manual pp. 14 and 16)</summary>

![Clock, Alarm, and Color controls](../images/controls/bios-clock-alarm.jpg)

</details>

## Utilities and programming

### APL/S

SHIFT toggles letters/symbols; the cursor shows L or U. Use symbol mode for numbers. F3 (NEXT) submits an expression, command, or program line. F1 (BACK) backs up and erases; F5 (ERASE) discards the current line. The special-key instructions below are from the user's manual, p. 2.

![APL/S special-key instructions](../images/controls/apl-special-keys.jpg)

Type `1+1` using the VideoBrain symbol positions, then F3 to evaluate it. For entering and launching programs, see [APL/S source entry](KEYBOARD-INPUT.md#apls-source-entry). For SD cassette SAVE/LOAD, see [tape images](TAPE.md).

<details>
<summary>APL/S command and function reference (original foldout, inside)</summary>

![APL/S foldout command and function reference](../images/controls/apl-reference.jpg)

</details>

### Financier

Enter a function name from the opening menu, or a formula, then F3 (NEXT). SHIFT toggles the cursor's U/L mode. F1 (BACK) corrects an entry; F5 (ERASE) discards the current formula. F2 and F4 are ignored. The manual's p. 4 shows the keyboard and explains the special keys.

![Financier keyboard and special keys](../images/controls/financier.jpg)

### Money Minder

This cartridge turns the keyboard into a financial keypad. Enter numbers at their printed positions without shifting. **Space is ENTER**, with INITIAL VALUE as its shifted function. A SHIFT selection applies to one upper function, then returns automatically to the lower function.

For example, a cash purchase follows AMOUNT, EXPENSE CATEGORY, CASH, ENTER. Use the overlay rather than typing category names. The manual's pp. 7 and 9 show the category layout and function keys.

![Money Minder keyboard overlay](../images/controls/money-minder-keyboard.jpg)

<details>
<summary>Money Minder function-key reference</summary>

![Money Minder function keys](../images/controls/money-minder-functions.jpg)

</details>

Original-machine Money Minder recordings and SD SAVE/LOAD are covered in [tape setup](TAPE.md).

### Information Manager

This prototype needs Expander 1 firmware. See the [user manual](INFOMAN-MANUAL.md) for database terms, planning fields, entering records, reading saved data and making an edited copy. NEXT is F3 or Enter; SPECIAL is F4. To display saved records, enter `REVIEW` at `:`, then `PRINT ALL` at `/`. `LIST` is not a recognized command. The manual identifies features that still need verification.

### Timeshare

Requires Expander 1 firmware for serial communication. **F5 or Ctrl+Enter sends Carriage Return**, **F4 or End is CONTROL**, and **Shift is held**, not toggled. Shift+H types `/`. Hold F4+Shift and tap D for full duplex (remote echo), or H for half duplex (local echo). The four layouts below are from the manual, pp. 11-14. Match their key positions to the PC mappings above.

![Timeshare unshifted keyboard](../images/controls/timeshare-unshifted.jpg)

<details>
<summary>Timeshare shifted, CONTROL, and CONTROL+SHIFT layouts</summary>

![Timeshare shifted keyboard](../images/controls/timeshare-shifted.jpg)

![Timeshare CONTROL keyboard](../images/controls/timeshare-control.jpg)

![Timeshare CONTROL+SHIFT keyboard](../images/controls/timeshare-control-shift.jpg)

</details>

The core connects the serial port to MiSTer's UART. See the [working Linux/Telnet bridge and Telehack setup](EXPANDER1.md#timeshare-over-uart).

## Music, art, and education

### Music Teacher 1

Choose 1 for Play/Record or 2 for Learn a Song, using the VideoBrain numeric positions. In Play/Record, the letter and function keys become musical notes. The diagram shows both note names and physical key positions (manual p. 5).

![Music Teacher note and keyboard layouts](../images/controls/music-teacher-keyboard.jpg)

T replays, Z selects Low, V selects High, and Space selects Middle. SHIFT selects the alternate functions, including Record, No-Record, and Erase. See the manual's p. 6 below for their use.

![Music Teacher special functions](../images/controls/music-teacher-functions.jpg)

Ready-to-play `.vbk` examples and recording instructions are in [keyboard entry and music](KEYBOARD-INPUT.md#music-teacher-1).

### VideoArtist

Choose Design 1-4 for one to four joystick-controlled drawing cursors, or 5 for an automatic design. The joystick chooses direction; its HIT button raises or lowers the pen. H stops/starts cursors, L toggles wraparound, V changes the background, F changes line and background colors, C changes line color, X exchanges line/background colors, M mirrors, and W starts the fountain effect. F5 (ERASE) clears the drawing.

![VideoArtist effects reference, manual p. 8](../images/controls/videoartist.jpg)

The manual's effects list gives V for background color, while its earlier instructions give B. That binding needs hardware confirmation.

### Wordwise 1

Choose level 1-3, then the number of players. F3 (NEXT) moves from the score display into play. Build words by entering a letter's current numbered position followed by its destination position. These are numeric moves, not typed letters. Space moves the word marker forward; F1 (BACK) moves it back. F4 (SPECIAL) scores the marked word; F3 ends the turn or advances.

![Wordwise 1 letter movement and scoring, manual pp. 5-6](../images/controls/wordwise-1.jpg)

### Wordwise 2

Choose 1 Key Learn, 2 Skill Trainer, 3 Speed Quiz, or 4 Cypher. The typing exercises use the displayed character keys. F1 (BACK) corrects mistakes. The original touch-typing layout is shown on p. 13 of the manual.

![Wordwise 2 typing layout](../images/controls/wordwise-2-keyboard.jpg)

In Cypher, type the message, separating words with Space, then press F3 (NEXT) when ready. The other team decodes it against the timer; F3 ends an early solution and submits it for scoring.

<details>
<summary>Cypher entry, solving, and scoring (manual pp. 9-10)</summary>

![Wordwise 2 Cypher instructions](../images/controls/wordwise-2-cypher.jpg)

</details>

### Math Tutor 1

Type your name, then F3 (NEXT). The cartridge selects numeric mode for subsequent number entry. Choose 1 Tutor to supply problems, or 2 Problem for generated exercises. Space (RUN) submits numbers and completed answers; F1 (BACK) corrects an entry. Enter arithmetic answers from right to left, following the on-screen asterisk.

![Math Tutor name entry and problem entry, manual pp. 3 and 5](../images/controls/math-tutor.jpg)

## Games

### Blackjack

Choose one or two players at the opening prompt. Move the joystick forward or back to change the bet, then press HIT to place it. During play, push forward and press HIT for another card; pull back and press HIT to stand. Use the prompted side-to-side choice for doubling (manual pp. 6-7).

![Blackjack play, standing, and doubling](../images/controls/blackjack-play.jpg)

### Checkers

Choose A-D for the computer opponent, then Y or N for the first move. Move joystick 1's cursor over a piece and press HIT to select it; move to the destination and press HIT again. For multiple jumps, select each landing square in turn. The manual's p. 7 explains cursor selection.

![Checkers joystick selection](../images/controls/checkers.jpg)

### Gladiator

Enter a game number, then Space (RUN/STOP). Game 0 is a basic Ancient Gladiator starting point; 128 starts basic Scrimmage and 256 basic Future Gladiator. Use joystick 1 or 2 to move and its HIT button to fire in the direction you are pointing. Space repeats a completed game; F3 (NEXT) returns to game selection. Manual p. 6 describes movement and firing.

![Gladiator joystick controls](../images/controls/gladiator-controls.jpg)

<details>
<summary>All 384 game selections (manual pp. 12-13)</summary>

![Gladiator game-selection charts](../images/controls/gladiator-games.jpg)

</details>

### Lemonade Stand

Enter the level and number of stands at the opening prompts. For each day's decisions, type the requested numbers and press F3 (NEXT). Enter both digits when requested, including a leading zero. F1 (BACK) corrects an entry before submission. F3 also advances the results screens (manual pp. 6-7).

![Lemonade Stand daily decision controls](../images/controls/lemonade-stand.jpg)

### Pinball

Enter a game number, then Space (RUN/STOP); games 1-4 are the basic game for one to four players. **Joystick 1's HIT button is the left flipper; joystick 2's is the right flipper.** Joystick 1's button also starts a ball. Select **Joysticks > Paired Sticks > 1+2 / 3+4 (Pinball)** to use controller 1's Fire and Fire (Paired) for the two flippers (manual p. 5).

![Pinball flipper controls](../images/controls/pinball-controls.jpg)

<details>
<summary>All 32 game selections (manual p. 9)</summary>

![Pinball game-selection chart](../images/controls/pinball-games.jpg)

</details>

### Tennis

Enter a game number, then Space (RUN/STOP); game 0 is basic two-player Tennis. Move the joystick to position the racket and use HIT to serve; returns do not require the button. Joysticks 1/2 are the left/right backcourt players; 3/4 are the left/right forecourt players. **Joysticks > Paired Sticks > 1+3 / 2+4 (Doubles)** pairs each team's backcourt and forecourt controls. Space repeats a completed game; F3 (NEXT) selects another (manual p. 5).

![Tennis movement and serving controls](../images/controls/tennis-controls.jpg)

<details>
<summary>All 96 game selections (manual pp. 8-9)</summary>

![Tennis game-selection charts](../images/controls/tennis-games.jpg)

</details>

### Vice Versa

Choose A-E for a computer opponent or F for a friend, then Y or N for the first move. Move joystick 1's cursor to a legal empty square and press HIT. Black moves first. In a two-player game, pass joystick 1 between players.

![Vice Versa joystick controls, manual p. 8](../images/controls/vice-versa.jpg)

### Demonstration

This cartridge presents the VideoBrain demonstration. Its first screen is covered by core validation; a title-specific manual and a complete control reference are not available here.

## Manual sources

Illustrations retain the original VideoBrain Computer Company artwork and wording; they are not covered by the core's GPL license. Page references above use the manuals' printed numbers. The APL/S foldout uses its inside face.

The source scans are the owner's manual, APL/S user's manual and foldout, and the individual manuals for the sixteen released cartridges. Timeshare uses Sean Riddle's `VB_Time_Share_Manual.pdf`. See [Sean Riddle's VideoBrain archive](https://www.seanriddle.com/vbinfo.html) and [Orphaned Games](https://orphanedgames.com/videobrain/) for further references.
