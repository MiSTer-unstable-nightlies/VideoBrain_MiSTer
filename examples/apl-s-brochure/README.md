# APL/S brochure examples

Type-ins from the VideoBrain *APL/S: The Computational Language* brochure,
PDF pages 3-5.

Load one `.vbk` at a fresh Computational Language prompt using
Keyboard > Load Keyboard File. Each has an entry-ready `(Source).txt`
listing and a descriptive `.txt` sidecar with the keyboard file's SHA1.

| Example / matching VBK | Page | Use |
| --- | --- | --- |
| `Earthlander Simulation.vbk` | 3 | Type `EART`, then enter burn rate and duration at each pair of prompts. |
| `Portfolio Example.vbk` | 4 | Type `PORT`; displays 22925. |
| `Inflation Example.vbk` | 5 | Immediate; increases four amounts by 10%. |
| `Sum and Average Example.vbk` | 5 | Immediate; displays 550 and 55. |
| `Parallel Resistance Example.vbk` | 5 | Immediate; displays approximately 76.9231. |
| `Geometric Mean Example.vbk` | 5 | Immediate; geometric mean of three values. |
| `Present Value Example.vbk` | 5 | Immediate; discounts three cash flows at 10%. |

Definitions use `EDIT` and `ENDE`, significant four-letter names and
keywords, and ASCII `{MUL}` and `{DIV}` tokens. Earthlander uses `CLOC`
consistently, adds the missing closing parenthesis and program terminator,
and corrects the printed `BT` multiplication by 2 to `BT*2` (squaring).
Its simplified distance calculation is retained when fuel runs out early.
The sum example expands the printed `10 20 30 ... 100` into ten values.

The cropped beta, tax and polynomial listings are omitted. Circle area and
standard deviation are not included in this set.

Regenerate a keyboard file from the repository root:

```sh
python3 tools/keyboard_input.py "examples/apl-s-brochure/Portfolio Example (Source).txt" "examples/apl-s-brochure/Portfolio Example.vbk"
```

Keyboard encoding, checksums and byte-identical regeneration have been
checked. Interpreter execution and MiSTer testing remain pending.
