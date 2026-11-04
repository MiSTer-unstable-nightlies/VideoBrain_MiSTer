#!/usr/bin/env python3
"""Run focused regression targets without a Quartus build or long captures."""
import argparse
from datetime import datetime, timezone
import importlib.util
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import time


TARGETS = (
    "test-tools", "test-cpu-opcode-timing", "test-cpu-branches",
    "test-cpu-reset", "test-cpu-interrupt", "test-cpu-irq-chain",
    "test-cpu-gate", "test-cpu-clock", "test-cpu-ports", "test-smi",
    "test-smi-clock", "test-sean-diag", "test-cpu-bus-wait",
    "test-uv201-wait", "test-arbiter", "test-fetcher-bus", "test-yint",
    "test-render", "test-video", "test-cartridges", "test-tiny-input", "test-source-loader",
    "test-download-reset", "test-status-messages", "test-joystick",
    "test-joystick-timing", "test-audio", "test-cpu-audio",
    "test-audio-path", "test-expander1", "test-tape", "test-dual-tape",
    "test-printer-uart", "test-printer-image", "test-printer-hps", "test-logic-csv", "lint",
)
ROM_TARGETS = (
    "test-apl-input", "test-music-input", "test-printer",
    "test-expander1-record", "test-expander1-playback", "test-expander1-edit",
    "test-printer-tapes",
)
LONG_TARGETS = (
    "test-apl-reload", "test-printer-cartridge", "test-printer-infoman",
    "test-printer-infoman-apple", "capture-apl-save", "replay-apl-tape",
    "replay-clock-source",
)


def describe(roms, output=None):
    targets = TARGETS + (ROM_TARGETS if roms else ())
    print("Targets: " + " ".join(targets), file=output, flush=True)
    print("Bus waits: measurement-only; strict documented-range assertion is excluded.", file=output, flush=True)
    if not roms:
        print("ROM checks excluded (enable with --roms): " + " ".join(ROM_TARGETS), file=output, flush=True)
    print("Long runs excluded: " + " ".join(LONG_TARGETS), file=output, flush=True)
    print("Hardware validation excluded: original-machine measurements and MiSTer acceptance tests.",
          file=output, flush=True)
    return targets


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="show the plan without running tests")
    parser.add_argument("--roms", action="store_true", help="include short original-ROM regressions")
    parser.add_argument("--make-arg", action="append", default=[], metavar="NAME=VALUE",
                        help="override a make variable, such as EXPANDER1_ROM")
    args = parser.parse_args(argv)
    for value in args.make_arg:
        name, separator, unused = value.partition("=")
        if not separator or not name.replace("_", "").isalnum() or name[0].isdigit():
            parser.error("--make-arg requires NAME=VALUE")
        if name in ("BUS_WAIT_ARGS", "MAKEFLAGS", "MFLAGS"):
            parser.error(name + " cannot be overridden by this runner")
    targets = describe(args.roms)
    if args.list:
        return 0
    directory = Path(__file__).resolve().parents[1]
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", MAKEFLAGS="", MFLAGS="")
    command = ["make", "--jobs=1", "--keep-going", *args.make_arg]
    log_directory = directory / "out/regressions"
    log_directory.mkdir(parents=True, exist_ok=True)
    started = datetime.now(timezone.utc)
    log_path = log_directory / (started.strftime("%Y%m%d-%H%M%S-%fZ") + ".log")
    print("Log: " + str(log_path), flush=True)
    start = time.monotonic()
    exit_code = 2
    status = "ERROR"
    with log_path.open("x", encoding="utf-8") as log:
        print("UTC start: " + started.isoformat(), file=log)
        print("Working directory: " + str(directory), file=log)
        describe(args.roms, log)
        print("Planned command: " + shlex.join(
            command + ["BUS_WAIT_ARGS=-gcheck_documented=false", *targets]), file=log)
        checks = (
            ("Git HEAD", ["git", "rev-parse", "HEAD"]),
            ("Git status (untracked included, ignored excluded)",
             ["git", "status", "--short", "--untracked-files=all"]),
            ("make", ["make", "--version"]),
            ("GHDL", ["ghdl", "--version"]),
            ("Verilator", ["verilator", "--version"]),
            ("Icarus Verilog", ["iverilog", "-V"]),
            ("vvp", ["vvp", "-V"]),
            ("g++", ["g++", "--version"]),
            ("Python", ["python3", "--version"]),
            ("NumPy", ["python3", "-c", "import numpy; print(numpy.__version__)"]),
        )
        try:
            for label, check in checks:
                print("\n" + label + ": " + shlex.join(check), file=log, flush=True)
                try:
                    version = subprocess.run(check, cwd=directory, env=environment,
                                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                             text=True, timeout=10)
                    empty = "(clean)" if label.startswith("Git status") else "(no output)"
                    print(version.stdout.rstrip() or empty, file=log)
                    if label.startswith("Git status") and version.returncode == 0:
                        print("Working tree: " + ("dirty" if version.stdout.strip() else "clean"), file=log)
                    print("Exit code: " + str(version.returncode), file=log)
                except (OSError, subprocess.TimeoutExpired) as error:
                    print("Unavailable: " + str(error), file=log)
            if os.name != "posix":
                raise RuntimeError("run this suite in WSL, Linux or macOS")
            missing = [tool for tool in ("git", "make", "ghdl", "verilator", "iverilog", "vvp", "g++", "python3")
                       if shutil.which(tool) is None]
            if missing:
                raise RuntimeError("missing required tools: " + ", ".join(missing))
            if importlib.util.find_spec("numpy") is None:
                raise RuntimeError("NumPy is required for the audio checks")
            exit_code = 0
            if args.roms:
                preflight = command + ["check-regression-roms"]
                print("\nCommand: " + shlex.join(preflight), file=log, flush=True)
                exit_code = subprocess.run(preflight, cwd=directory, env=environment,
                                           stdout=log, stderr=subprocess.STDOUT).returncode
                if exit_code:
                    print("ROM preflight failed; regressions were not run.", file=log)
            if not exit_code:
                actual_command = command + ["BUS_WAIT_ARGS=-gcheck_documented=false", *targets]
                print("\nCommand: " + shlex.join(actual_command), file=log, flush=True)
                exit_code = subprocess.run(actual_command, cwd=directory, env=environment,
                                           stdout=log, stderr=subprocess.STDOUT).returncode
            status = "PASS" if exit_code == 0 else "FAIL"
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            print("Preflight/execution error: " + str(error), file=log)
            exit_code = 2
        except KeyboardInterrupt:
            print("Interrupted by user.", file=log)
            status = "INTERRUPTED"
            exit_code = 130
        finally:
            duration = time.monotonic() - start
            print("\nUTC end: " + datetime.now(timezone.utc).isoformat(), file=log)
            print(f"Final status: {status}; exit code: {exit_code}; duration: {duration:.3f}s", file=log)
    print(f"{status}: exit code {exit_code}; {duration:.1f}s; log: {log_path}")
    print("Bus waits were measurement-only; long captures and hardware checks were not run.")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
