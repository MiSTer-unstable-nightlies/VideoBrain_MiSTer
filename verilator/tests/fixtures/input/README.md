# Input fixtures

These versioned snapshots belong to the regression suite. Tests read them
directly and do not copy or discover files from the example collection.
Update fixtures deliberately when the tested behavior changes; renaming or
editing an example does not require a fixture update.

`cases.json` records each keyboard source, expected VBK, converter profile and
options. Music timing is explicit. Expected VBKs are checked in, not generated
at test startup. `rtc-clock` preserves the seven-event sequence used by the
RTC loader test; it is not a clock-screen usage recommendation.

Tape snapshots retain their headers and waveform intervals, with unused
trailing capacity reduced to a sector boundary. The APPLE tape is also used
by the printer regressions. Sources and expected keyboard files are unchanged
snapshots, apart from the RTC protocol fixture.

Music attribution and licenses are in [music/SOURCES.md](music/SOURCES.md).

Run from the repository root:

```sh
python3 -B verilator/tests/test_examples.py
python3 -B verilator/tests/test_keyboard_input.py
```
