# Verilator harness

Verilator reads Verilog only, so every build first runs the VHDL through `ghdl synth --out=verilog`. Module, instance and RAM names survive that step; intermediate combinational nodes become `nNNNN`.

    make            # graphical sim (SDL2 + ImGui)  -> ./obj_dir/Vtop
    make headless   # batch sim (no SDL)            -> ./obj_dir_headless/Vtop
    make netlist    # just the Verilog netlist      -> gen/videobrain.v
    make lint

Requires ghdl (VHDL-2008), verilator, zlib, and sdl2 for the graphical target. Run from this directory. Supply ROM paths explicitly; see [contributing](../CONTRIBUTING.md).

## Regression suite

From the repository root in WSL, Linux or macOS:

```sh
python3 -B verilator/tests/run_regressions.py
```

This runs the focused CPU, interrupt, bus, video, audio, input, cartridge,
tape, printer, tool and analyzer checks, followed by simulator lint. It does
not build Quartus or the graphical simulator. It requires GNU make, GHDL,
Verilator, Icarus Verilog (`iverilog` and `vvp`), g++, Python 3.9 or newer,
and NumPy. Missing prerequisites stop the run before testing. The suite may
take several minutes, particularly when generated models need rebuilding.

`--list` prints the selected targets and exclusions without running anything.
Tests run serially to protect shared GHDL work directories; make continues
independent targets after a failure and the runner returns nonzero if any
target fails. Each run prints its log path under `verilator/out/regressions/`
and a final PASS/FAIL summary. Logs include the source revision, working-tree
state, tool versions, selected targets, exclusions and final result. Inspect that log for assertion failures and
explicit optional-fixture skips; a successful run does not imply hardware
validation or exhaustive software coverage.

Bus-wait checks use measurement-only mode in this suite. The strict
documented-range assertion remains available with
`make -C verilator test-cpu-bus-wait`; the recorded 6..7-half-clock RAM/cart
wait falls below its 7..9 expectation. The runner labels this exclusion and
does not treat an arbitrary failure as expected.

Add `--roms` to include the shorter APL/S and Music Teacher recognition,
Expander serial/record/playback/edit, printer-ROM and tape-contention checks.
Supply the Expander, APL/S and Music Teacher ROM files;
missing files fail preflight. Paths can be supplied with repeatable
`--make-arg NAME=VALUE` options using `EXPANDER1_ROM`, `APL_ROM` and `MT1_ROM`.
or an untracked local configuration as described in [contributing](../CONTRIBUTING.md).
ROMs are not bundled or downloaded by the runner. Generated printer outputs
are checked immediately after their producer target; the ROM-free tool suite
uses only self-contained printer-image fixtures.

Long full-machine checks remain separate: `test-apl-reload`,
`test-printer-cartridge`, `test-printer-infoman`,
`test-printer-infoman-apple`, `capture-apl-save`, `replay-apl-tape` and
`replay-clock-source`. They need original ROMs and, for some targets, a
separately supplied recording. The master suite lists these exclusions.
Original-machine measurements and MiSTer acceptance tests remain separate.

`make test-rtc-boot` checks optional RTC clock initialization against the original BIOS, including reset reseeding, disabled/missing and late RTC, and midnight rollover. Supply RES1 and RES2 ROMs. MiSTer verification remains separate.

`make test-video` checks native and progressive timing, staged output selection and application, and uncropped 480p line duplication. It compares pixels, sync and blanking against the source and checks the 189 by 484 active area within the 526-line output raster. The top-level routing test substitutes a passthrough mixer; hardware output still requires MiSTer validation.

`make test-cpu-branches` runs ROM-free GHDL checks for BR7 across all 64 ISAR values and every BT/BF mask across all 32 status-register values, including directly loaded zero/sign combinations. The 4,160 cases use signed displacement boundaries, check branch destinations and operand/fetch cycle lengths, and verify that ISAR or status flags remain unchanged.

`make test-cpu-opcode-timing` checks all 242 documented opcodes against an independent transcription of Fairchild F3850 Table 3 (printed pp. 3-21 through 3-25). Its 968 cases execute the CPU/bus interface with initialized scratchpad, two flag patterns and two ISAR values, checking ROMC order and every short/long cycle duration. It excludes undefined opcodes and external waits. See [timing sources](../docs/TIMING-SOURCES.md) for the source discrepancies and capture limits.

`make test-cpu-ports` runs 1,280 cases through the full core using generated F8 programs. It checks every output value on both CPU ports, including port 1 readback with joystick fire and selected/unselected keyboard columns.

`make test-smi` checks external-interrupt rearming and the F3853 timer. Timer tests use all 255 seeds from the Mostek 1978 data book's Table 2 (printed p.170), checking initial delays and 255-count repeats with dividers 31 and 1. They also cover paused clock enables, masked expiries, acknowledge isolation, reload priority and `$FF` stopping. These are checks in timer input-clock periods.

`make test-smi-clock` runs a ROM through the full core and checks repeated timer IRQs at the DAC against 255 * 31 nominal 2 MHz PHI periods. Board records connect U16.2 to U17.1 (CPU PHI), and saved traces show this clock stopping during waits. The core derives one timer enable per two accepted CPU half-period enables. This regression checks the integrated rate without buffered-bus contention; it does not establish exact PHI edge phase or measured original-machine timer intervals.

    ./obj_dir/Vtop --res1 /path/to/res1.bin --res2 /path/to/res2.bin --run
    ./obj_dir_headless/Vtop --res1 /path/to/res1.bin --res2 /path/to/res2.bin --cart /path/to/cartridge.bin --frames 300 --shot-last
    ./obj_dir_headless/Vtop --help

Known cartridge ROMs are identified by CRC-32. `--cart-type` selects the slot profile only for unrecognized images.

`--expander1 <file>` loads the separate 2K Expander 1 firmware. See [Expander 1](../docs/EXPANDER1.md) for firmware and peripheral details. `make test-expander1` tests its ROM loading, host wiring, 3870 timer and interrupt execution. `make test-expander1-record` exercises original-ROM recording, decodes its digital capture and checks good/bad checksum status. It requires the firmware.

`make replay-apl-tape` boots APL/S and LOADs the user-supplied `APL_TAPE`, with a final screenshot and host signal trace in `out/expander1/apl-load`. This is a long run. The headless `--playback FILE` option replays the VBT1 waveform directly at the Expander input, bypassing SD service; remote stops pause playback without rewinding. `--expander-trace FILE` logs host signals, interrupt acknowledgements and VideoBrain receive-register writes, including counters and interrupt sources.

## Keyboard input

The GUI uses the core's PC key aliases: number row and keypad `1234567890` map to `ZXCSDFWER/`, Backspace maps to BACK (F1), Home to PREVIOUS (F2), Enter and keypad Enter to NEXT (F3), End to SPECIAL (F4), and Ctrl+Enter to ERASE (F5). Either Ctrl key works with either Enter key; the destination stays fixed until Enter is released. SHIFT mode and cartridge overlays still determine the result. Timeshare uses F5 or Ctrl+Enter for carriage return. See [keyboard controls](../docs/HOW-TO-PLAY.md#keyboard-and-controllers).

User converters live in [tools](../tools). `--source FILE@FRAME` accepts VBK1 and VBK2, including built-in Text without a cartridge. `make test-apl-source` runs the Python converter tests and RTL loader checks. `make test-music-input` checks the Music Teacher readiness hooks using the original ROM. Set `MT1_PATCHED_ROM=/path/to/modified.bin` to check an optional modified ROM too.

`make replay-clock-source` uses the bundled Price Clock keyboard file. `make capture-apl-save` and `make replay-apl-tape` generate keyboard files with `../tools/keyboard_input.py`.

### Keyboard file formats

VBK1 has an eight-byte header: magic `VBK1`, a little-endian 16-bit token count, and CRC-16/CCITT (polynomial 1021, initial FFFF) of the payload. Each byte contains a matrix key in bits 5:0 and desired symbol mode in bit 6. Bit 7 marks mode-independent SPACE (93 hex) or NEXT (9B hex). Raw SHIFT tokens are rejected. VBK1 is gated to the CRC-recognized Computational Language ROM.

The APL/S handshake observes bank D opcode fetches: $3C14 follows the all-keys-up loop at $3C0A; $3C20 follows acceptance at $3C14-$3C1E. Cursor drawing at $3C04 is not readiness.

VBK2 retains the eight-byte VBK1 header, with magic `VBK2`. Count is payload bytes, not event count; CRC is unchanged. Each three-byte event is matrix key 0..35 (or FF for WAIT), held fields 1..255, released fields 0..255. Limit: 4095 bytes / 1365 complete events. Raw SHIFT and function keys are valid in VBK2. APL-only VBK1 remains gated to the recognized Computational Language ROM.

VBK2 also accepts FE for the music Record/No-Record selector (inside shifted mode), and FD for Replay (inside lower mode). The menu setting is latched at download: Record maps FE to Z and FD to T; Playback maps FE to COMMA and FD to a silent wait with the encoded duration. Older cores reject these events. FA/FB/FC select Low/Middle/High with ROM acknowledgment. Their gap byte specifies a musical interval counted concurrently with the handshake; the next event requires both readiness and interval completion. Score-ready files use this to overlap switches with preceding note gaps. Their hold/gap bytes are placeholders (the converter emits 1/0); handshake state determines timing. These controls require lower SHIFT, as do physical octave keys. Keyboard > Music Repeat applies to both VBK1 and VBK2 and can be disabled during entry.

F8/F9 request lower/upper SHIFT using the tracked mode at RAM 0FE2 bit 0. The loader presses SHIFT only when needed, retaining the encoded hold/gap timing. If the mode has not changed by the end of the hold, SHIFT remains held for up to 255 additional fields before an error. Generated text and music use these controls; music finishes in lower mode. Raw SHIFT remains a physical toggle. Older cores reject F8/F9; regenerate older files to use mode synchronization.

## Joystick simulation

Joystick pulse timing is runtime-configurable without rebuilding. Headless defaults to Linear, `--joy-timer-base 2580 --joy-timer-step 7`; MiSTer uses cartridge-selected linear presets. `--joy-timer-curve` retains the older shared curve for diagnostics. Values are MCLK ticks. With `--joy-trace`, `[joy-measure]` reports the selected axis, pot value, timer parameters, and measured pulse length. `make test-joystick` and `make test-joystick-timing` check the controller and integrated pulse timing.

## selftest.rom

A hand-assembled F8 program that sets up one 16x16 object and halts, so the CPU, bus, UV201 registers, fetcher, FIFO and renderer can be exercised without the BIOS. The 2K ROM is tracked; no regeneration script is provided.

    ./obj_dir_headless/Vtop --res1 selftest.rom --frames 8 --shot-last --ascii

`make test-render` checks UV201 background/object modifiers, zoom and blanking.

## Converting VHDL to Verilog one file at a time

The netlist is the reference. Write `rtl_v/<entity>.v`, add the entity name to `CONVERTED` in the Makefile, and rebuild: that module is stripped from the netlist and yours is compiled in its place. The VHDL stays in `VHD_SRC` so the rest of the hierarchy still elaborates.

Check equivalence by frame hash, before and after:

    ./obj_dir_headless/Vtop --res1 selftest.rom --frames 8 --frame-log
    ./obj_dir_headless/Vtop --res1 /path/to/res1.bin --res2 /path/to/res2.bin --frames 60 --frame-log

`CONVERTED` is currently empty. The F8 CPU and packages derive from the Channel F core; preserve attribution when changing them.

## Development utilities

Run these from `verilator/`. ROM-based captures require user-supplied BIOS, firmware and cartridges. Configure their paths as described in [contributing](../CONTRIBUTING.md); ROMs are not bundled.

| Utilities | Purpose |
| --- | --- |
| `tests/tb_*` | Run CPU, bus, video, audio, cartridge, keyboard, joystick and tape regressions. |
| `tests/run_regressions.py` | Run the focused regression suite with logs and explicit exclusions. |
| `tests/run_tools.py` | Check APL/S, keyboard/music, tape, printer-image and printer-capture tools. |
| `tests/test_examples.py` | Check bundled source/VBK pairs, checksums, tape structure and blank images; included in `test-tools`. |
| `tests/audio_filter_design.py`, `tests/test_audio_alias.py` | Check filter coefficients and alias rejection with `make test-audio`. |
| `tests/check_audio_path.py` | Check the MiSTer I2S output path with `make test-audio-path` (requires NumPy). |
| `tests/analyze_logic_csv.cpp`, `tests/check_logic_csv.py`, `tests/summarize_logic_captures.py` | Analyze logic captures and check the analyzer with `make test-logic-csv`. |
| `strip_modules.py` | Replace selected synthesized modules during Verilog conversion. |

Historical joystick sweeps, APL/S NEXT probes, Music Teacher IRQ/phase captures, and Pinball snapshot comparisons have been archived outside the repository with their saved outputs and original paths. They are not part of the current regression harness.

Run all tool checks without building the simulator (Python 3.9 or newer, standard library only):

```sh
python3 -B tests/run_tools.py
```

The same checks are available as `make test-tools`, and are included in `make test-apl-source`. From the repository root, use `python3 -B verilator/tests/run_tools.py`. Use `python` if that is how Python is installed on your system. Optional tape-reference checks use separately supplied recordings; unavailable fixtures are reported as skipped. Printer file-capture checks require POSIX tty support and are explicitly skipped on Windows; use WSL to include them.
