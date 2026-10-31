# Examples

Copy tape and printer images under new names before recording. BIOS,
cartridge ROMs and Expander 1 firmware are supplied separately; see
[installation](../README.md#installing).

| Collection | Contents |
| --- | --- |
| [APL/S manual chapter 6](apl-s-manual-chapter-6/README.md) | Source listings and ready-to-load `.vbk` files. |
| [APL/S brochure](apl-s-brochure/README.md) | Earthlander, portfolio and immediate calculations with `.txt` sources and `.vbk` files. |
| [Save and reload tutorials](saves/README.md) | Money Minder, Information Manager and APL/S working tapes. |
| [Music](music/README.md) | Music Teacher 1 MML sources and `.vbk` playback files. |
| [Tiny BASIC](tinybasic/README.md) | Small interpreter checks with `.txt` sources and `.vbk` files. |
| [Blank tape](blank-tape.vbt) | Writable image for [tape recording](../docs/TAPE.md). |
| [Blank printer image](blank-printer.vbp) | Empty image for [printer capture](../docs/PRINTER.md). |

Load `.vbk` files with **Keyboard > Load Keyboard File** at the appropriate
software prompt. Mount `.vbt` files in a tape deck and `.vbp` files under
**Printer > Mount Capture Image**. Follow each collection's instructions for
required firmware, software and validation limits.

## Validation

Run the file checks from the repository root:

```sh
python3 -B verilator/tests/test_examples.py
```

These check source/VBK pairs, byte-identical regeneration, keyboard checksums,
tape image structure and blank images. They do not execute cartridge software.
Manual type-ins still need interpreter testing; the save tutorials and full
music playback still need MiSTer checks. See each collection's instructions.
