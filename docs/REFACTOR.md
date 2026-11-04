# Refactor investigations

Candidates for review after feature lock. Implement only where the maintenance
benefit justifies the change. Preserve cartridge validation and user-visible
messages. Keep `sys` identical to upstream MiSTer.

## Equivalence gate

Before each step, record the baseline revision, inputs, settings and relevant
results. Use the [existing regression workflow](../CONTRIBUTING.md#validation).
Add coverage only where the affected behavior lacks a useful check.

Make one bounded change at a time. Compare the same inputs against the baseline:
is function the same? If yes, proceed to the next step. If no, fix the current
step before proceeding. An unexplained difference or missing evidence leaves
the step unverified. Keep functional fixes separate from refactors.

Compare timing and externally observable behavior, including reset, cancellation
and failure paths. Frame hashes alone cannot establish input, audio or storage
equivalence. Use cycle-level traces, output bytes or focused assertions where
appropriate. Simulation equivalence does not establish FPGA timing closure;
the user runs Quartus builds and MiSTer acceptance checks when needed.

## Candidates

### 1. Named status messages

Problem: the ordered MiSTer message string, numeric event assignments and printer
status arithmetic must remain synchronized by hand.

Investigate named message IDs and a consistency check first. Consider generating
the string and IDs from one definition only if it removes more maintenance work
than it introduces. Do not renumber or rewrite messages as part of this step.

Gate: preserve the complete message string, event-to-ID mapping, simultaneous
event priority, OSD deferral, repeat timing and printer error retention. Extend
the existing status-message checks only for uncovered mappings and interactions.

### 2. Common VBK handshake interface

Problem: APL/S and Music Teacher share misleadingly named handshake signals,
while BASIC has another pair routed through the module hierarchy.

Investigate selecting the active ROM's readiness and acceptance signals near
their detectors, then exposing one common pair. Keep ROM-specific detectors and
playback capabilities explicit. Check loader state use before merging signals;
do not change detector addresses, register timing or event scheduling.

Gate: preserve cycle-level ready/accepted and keyboard-matrix sequences for
APL/S, both supported BASIC layouts, and supported Music Teacher variants.
Include timed and acknowledged files, SHIFT, octave changes, WAIT, timeouts,
reset, replacement and cancellation. Fewer ports alone do not prove less FPGA
routing or logic; measure any claimed hardware benefit.

### 3. Cartridge identity checks

Problem: input helpers and patches select known ROM revisions using size, CRC
and mapper conditions. Repeated conditions can diverge as variants are added.

Investigate whether shared, named identity predicates would remove actual
duplication without coupling independent features. Keep file validity, hardware
profile, software identity and feature eligibility distinct. Avoid a general
registry unless existing repetition warrants it.

Gate: preserve recognition and feature eligibility for original and patched
ROMs, unknown raw images, explicit VBC profiles and mapper overrides. A declared
profile must not enable address-dependent helpers or patches for an unknown ROM.
Cartridge acceptance, rejection and unload behavior must remain unchanged.

## Module ownership

The current approach mixes chip models, functional blocks and board integration.
Prefer clear subsystem ownership over a universal one-IC-per-file rule. Keep
useful internal splits and host conveniences identifiable. File size or mixed
HDL alone does not justify restructuring.

- `sys_bus`: investigate separating ROM-specific input observation from memory
  ownership. Cartridge mapping, storage, recognition and patching also share this
  file; assess boundaries carefully to preserve RAM inference and read latency.
- UV201: registers live under `sys_bus`, while fetching, FIFO, rendering and Y
  interrupt live under `videobrain_core`. Investigate a `uv201_top` owner, similar
  to UV202, only if it reduces exposed internal wiring.
- Expander 1: investigate a 3870 wrapper around CPU, ROM, ports, timer and
  interrupt behavior, leaving Expander board circuitry outside. Retain smaller
  internal modules. Keep unresolved [F3850/3870 behavior differences](TIMING-SOURCES.md#mostek-3870)
  separate from structural changes.
- Shared definitions: `f8_busif` lives under `uv202` but serves both processors
  and includes VideoBrain address classification. `uv202_pack` mixes video timing
  and machine memory-map definitions. Investigate more accurate ownership and
  placement without creating needless packages.
- Naming and inactive interfaces: review the broader role of `apl_source_loader`
  and the tied-inactive `apl_hold`, `apl_paused` and `apl_load_error` connections.
  Check all consumers before renaming or removing ports.

Apply the equivalence gate to each extraction or interface change separately.
Preserve clock enables, reset behavior, bus timing and memory port semantics.
Do not merge small, independently testable blocks merely to reduce file count,
or rewrite inherited F8 packages without a concrete maintenance benefit.
