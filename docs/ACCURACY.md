# Accuracy report

Current source status, November 3, 2026. The core is nearly ready for 1.0. This describes the source, rather than a particular released RBF.

## What this core represents

The aim is to recreate the VideoBrain's hardware behavior as faithfully as the available evidence allows. The implementation includes the Fairchild F8 processor, UV201 video system, UV202 clock and bus control, memory and cartridge interfaces, keyboard, joystick timing, sound output, and Expander 1 support.

The evidence consists of preserved documentation, reverse engineering, board connection records, original software and cassette data, photographs, screenshots, and videos, together with MAME and implementation tests. Direct access to an original VideoBrain is unavailable. Tests on MiSTer establish behavior of this core; they are not direct measurements of an original VideoBrain.

No core bugs are currently known. Release qualification still requires validation of the exact candidate source and RBF, including timing closure and MiSTer checks of the supported output modes and peripheral workflows. Positive timing results alone do not establish that the current source or release artifact has been qualified.

Tiny BASIC Enhanced and the Tennis adaptation are separate software projects; their remaining work does not define core release readiness.

## Evidence and confidence

- Circuit records, component documentation, patents, and reverse-engineering notes explain how the machine is believed to work. Some records conflict or leave details unspecified.
- Original-machine images and recordings provide visible or audible comparison points. Their capture paths limit conclusions about exact timing, color, and analog response.
- Original-machine cassette data provides an independent compatibility check through the software and tape interface. Money Minder has completed a load, edit, save, restart, and reload cycle using such data.
- Simulation checks instruction timing, bus transactions, signal sequencing, and regressions against explicit expectations. A passing test supports those expectations; it does not independently prove the hardware model.
- MiSTer testing checks the implemented machine in use, including software, controls, and the output path. Coverage varies by application and feature.

The main references are Kevtris's *VideoBrain Unwrapped*, Sean Riddle's preserved hardware material, VideoBrain patents and manuals, processor documentation, and MAME. The [project source list](../README.md#sources) provides starting points. The [timing evidence](TIMING-SOURCES.md) distinguishes active opcode cycles from board waits, records discrepancies in secondary tables, and inventories the saved capture channels.

## Current implementation

| Area | What is implemented and supported | Remaining limits |
| --- | --- | --- |
| F8 CPU and bus | Instruction cycle timings have been cross-referenced against the available manufacturer documentation and secondary references. Execution, ROMC cycles, interrupts, clock gating and contention have extensive focused coverage. | Further progress chiefly needs test ROMs, diagnostics and oscilloscope or logic-analyzer measurements. Board wait costs and oscillator phase need direct comparison. No comparative accuracy ranking against MAME is established. |
| UV201 | Registers, object fetching, FIFO, rendering, modifiers, zoom and freeze capture work across tested software. No current visible discrepancy has been identified. | Highest priority for exhaustive original-machine tests, including access timing, counter phase and edge cases that ordinary software may not expose. |
| UV202 | Clock and bus control, DMA arbitration and native interlaced output work across tested software. | Lower-priority hardware verification of clock/bus timing, field transitions, half-line seams and sync widths. |
| Cartridges and software | All eighteen known cartridges are supported. Coverage extends beyond startup to gameplay, APL/S programs, tape round trips, Timeshare sessions and Information Manager operations. | Financier does not fully work because the ROM is incomplete; no good dump exists at time of writing. Information Manager has some bugs due to its prototype nature. |
| Keyboard and joysticks | Keyboard matrix, calibration, four analog sticks, fire buttons and paired controls work well in MiSTer use. Games are fully playable with the current timing model. | Physical pot ranges, pulse widths, trim effects and UV201 freeze-counter phase need measurements. Current presets provide practical travel and centering; exact hardware behavior may be less convenient. |
| Audio | DAC writes, sound-clock latching, filtering and output work. Tempest's Music Teacher 1 recordings confirm sidebands on original hardware, supporting the audible grit as characteristic of the machine. | Exact sideband levels, timing and analog response remain unverified. The receiver and recording path affect comparisons. |
| Expander 1 and tape | Firmware execution, host signaling, digital tape save/load, Timeshare UART and independent printer capture are implemented. Difficult tape and peripheral paths have been exercised. | Detailed guides retain the evidence limits for individual workflows. Analog cassette circuitry, physical printing and Expander 2 acoustic modem behavior are outside the implemented digital interfaces. |

The [cartridge status](CARTRIDGES.md), [joystick notes](JOYSTICK.md), and [Expander 1 notes](EXPANDER1.md) describe the boundaries in more detail.

## Software validation

### Money Minder

A Money Minder cassette save from Sean Riddle's original VideoBrain, converted to VBT, passes load, edit, save, restart and reload on MiSTer. The original values and edits survive the round trip. Playback of the edited recording on an original VideoBrain remains untested.

### Pinball and the final color modifier

The renderer applies the final color modifier after object/background selection, including background pixels. This agrees with the patent's final-output selection logic and original-machine Pinball screenshots. Regression coverage checks CPU and video-register state, object pixels and background pixels.

### Audio and CPU clock gating

The external clock gate models the request latch, WACK sampling and request synchronization from board connection records. A circuit-derived edge test checks its sequencing. The CPU/bus wait test reports 6..7 lost half-clocks for RAM/cartridge reads against a 7..9 expectation derived from a secondary description; that assertion fails. Exact board wait costs remain a hardware measurement question.

Tempest's Music Teacher 1 recordings contain sidebands on an original VideoBrain, supporting audible grit as original-machine behavior. Exact agreement in sideband strength, timing and analog response remains unverified.

### APL/S and Expander 1

APL/S tests cover entering and executing arithmetic, graphics and selected type-in games through the keyboard matrix.

Expander 1 tests execute its firmware and digital tape transactions. Original-ROM tests cover record framing, checksums, successive records, and playback through a remounted image. MiSTer tests confirm selected converted workspace loads and continued execution. These results support the implemented digital path; they do not establish interoperability with a physical cassette recorder or original Expander. See [APL/S](KEYBOARD-INPUT.md#apls-source-entry) and [tape images](TAPE.md).

## Where MAME contributes

MAME is an important preserved implementation and a practical reference where hardware measurements are missing. The core uses MAME-derived information for cartridge identification and slot layouts, parts of address decoding, and device behavior. The F8 implementation credits assistance from MAME's CPU model; the F3853 implementation explicitly references MAME.

This creates shared assumptions that software compatibility cannot resolve. The F3853 timer uses the documented feedback shift-register sequence, with all 255 running seeds checked against the Mostek 1978 data book's conversion table (printed p.170). Tests also cover repeat periods, masked pending interrupts, reloads, stopping, and external-interrupt isolation. The initial timer clock follows the two-input-period delay shown in the F3852/F3853 timer block diagram (Figure 6).

The timer input uses CPU PHI periods, including CPU wait gating. [Sean Riddle's board connection workbook and captures](https://www.seanriddle.com/vbinfo.html) connect F3853 U16 pin 2 to F3850 U17 pin 1 and TP4 on the PHI net, and show PHI stopping with XTALY during waits. The core advances the CPU twice per PHI period, so the timer advances on every second accepted CPU enable. A full-core regression checks repeated timer interrupts against the nominal 2 MHz PHI rate. Exact edge phase and timer intervals under board-level contention remain unmeasured. The implemented single-device subset also omits memory addressing and priority daisy chaining.

## Approximations and conveniences

Joystick presets select linear delay ranges by cartridge to provide useful centering and travel. Preserved notes describe game-dependent physical trim adjustments, but do not establish the preset values. These presets are calibrated input behavior, not measured replicas of particular pots.

The audio filter is tuned against available recordings, including their unknown receiver and capture response. Its band limit also provides alias protection. It is not a component-level recreation of the RF sound chain.

Keyboard files supply timed matrix inputs. Tape images preserve digital recording intervals and replay them at the Expander input. Both retain firmware participation while replacing physical input or storage media. Progressive output (240p and line-doubled 480p) buffers native video without changing machine timing. A dedicated fractional PLL provides constant pixel spacing and line lengths. Each output frame has 263 lines at the nominal native average field cadence; the shorter native field receives a black bottom row. PLL frequency quantization contributes less than two source pixels of buffer drift per day.

## Remaining accuracy work

Original-machine testing is the principal next step, with UV201 the highest priority and UV202 next. Useful evidence includes:

- Exhaustive UV201 test ROMs covering register access, fetching, modifiers, zoom, counter/freeze behavior and boundary conditions.
- CPU oscillator, request, WACK, and CPU clock traces during buffered reads, writes, and DMA contention, to reconcile total wait costs and restart phase.
- UV202 field transitions, equalization and sync pulses, with a clear counter origin, to resolve the current half-line and pulse-width uncertainties.
- F3853 PHI and timer interrupt traces, including wait gating, reload phase, and interrupt timing.
- Joystick pot ranges and pulse widths at known positions, together with UV201 freeze-counter phase and the effect of trim adjustments.
- Matched audio captures at the DAC and receiver output, with the cartridge, key sequence, and recording path identified.
- Expander cassette and serial signal captures, plus broader application and gameplay comparisons against original machines.

## Documentation and optional future work

The remaining Information Manager pass is intended to complete the [manual](INFOMAN-MANUAL.md): exercise its commands, document supported workflows and distinguish prototype software bugs from hardware behavior.

Core quality-of-life features meet the current release goals, including relative analog movement for Tennis with three speed settings. Spinner support and MIDI input for Music Teacher or homebrew are optional future work. A 1080p 5x crop is deferred because native interlacing needs separate handling.

Further Music Teacher patch improvements and a possible musical homebrew exploring the machine's full audible frequency range are software projects, separate from core release requirements.

### Experimental intensity mapping

Video > Colors defaults to 16 (Original), retaining the established two-level
palette. The optional 32 (Patent) mode uses both intensity bits for four
ordered RGB levels. The [Umtech patent](https://patents.google.com/patent/US4232374A/en) specifies four
intensities; the current numerical levels are experimental and have not been
matched to analog measurements. See [color values](TINYBASIC-COLORS.md). This
optional mode changes the BIOS color bars, which use intensity codes 01 and 10.
Whether the original machine supported four distinct intensities is unresolved.
