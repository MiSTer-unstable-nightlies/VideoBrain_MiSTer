# Contributing

Use Quartus 17.0.2 for FPGA builds. See the [simulation guide](verilator/README.md) for tool requirements and regression coverage. Keep `sys` identical to upstream MiSTer and preserve third-party attribution.

## ROM inputs

Supply your own BIOS, Expander firmware and cartridge images. The [installation guide](README.md#installing) lists BIOS hashes; [cartridge assembly](docs/CARTRIDGES.md#split-cartridge-conversion) describes split images.

Set paths with make command-line variables or in `verilator/roms.local.mk`, which is excluded from version control. Use absolute paths in WSL/Linux form when invoking tests from WSL. In the local makefile, do not quote assignment values containing spaces; recipes quote the resulting paths.

```make
RES1_ROM = /path/to/res1.bin
RES2_ROM = /path/to/res2.bin
EXPANDER1_ROM = /path/to/expander1.bin
APL_ROM = /path/to/apls.bin
MT1_ROM = /path/to/music-teacher.bin
TIMESHARE_ROM = /path/to/timeshare.bin
INFOMAN_ROM = /path/to/information-manager.bin
APL_TAPE = /path/to/apls-workspace.vbt
```

The short ROM suite needs `EXPANDER1_ROM`, `APL_ROM` and `MT1_ROM`. Full-machine tests also need the relevant BIOS and cartridge inputs. `APL_TAPE` is only needed for tape replay. Optional `MT1_PATCHED_ROM` selects a patched Music Teacher image for recognition checks.

The tool suite uses `MT1_ROM` for its optional original-ROM patch checks. When invoking the Python tool runner directly, export that variable explicitly; make reads it from the local configuration and passes it to the tool runner.

Simulators accept `--res1`, `--res2`, `--cart` and, for the headless simulator, `--expander1`. Supply both BIOS halves for normal software. The bundled synthetic self-test only needs `--res1 selftest.rom`.

## Validation

Post-feature-lock [refactor investigations](docs/REFACTOR.md) use behavior
equivalence as the gate for each bounded change.

From the repository root in WSL or Linux:

```sh
python3 -B verilator/tests/run_regressions.py --list
python3 -B verilator/tests/run_regressions.py --roms
```

Omit `--roms` for the ROM-free suite. A one-run path override is also supported:

```sh
python3 -B verilator/tests/run_regressions.py --roms \
  --make-arg 'EXPANDER1_ROM=/path/to/expander1.bin' \
  --make-arg 'APL_ROM=/path/to/apls.bin' \
  --make-arg 'MT1_ROM=/path/to/music-teacher.bin'
```

Retain the regression log with its revision, working-tree state, tool versions and result. Long captures, strict hardware-timing comparisons and MiSTer acceptance checks are listed separately in the simulation guide. Simulation results do not replace Quartus timing checks or hardware testing.
