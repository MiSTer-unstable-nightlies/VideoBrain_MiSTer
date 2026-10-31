# Cartridge status

All eighteen known cartridges are recognized. Current MiSTer coverage includes gameplay, APL/S programs, tape round trips and peripheral operations. Financier entry submission currently restarts the title. The table below lists recognized image sizes and slot devices. Information Manager exploration continues primarily to complete its manual. See [current accuracy and remaining work](ACCURACY.md).

Known raw dumps are identified by CRC-32 and use the matching slot behavior. `--cart-type` and the OSD's System > Mapper Fallback setting apply only to unrecognized images: 0 standard, 1 Timeshare, 2 Money Minder, 3 CompLang, 4 Infoman, 5 4K RAM, 6 BASIC. Assembled APL/S and Information Manager images are also identified automatically.

For power cycle, Master Control, cartridge unloading and hot loading, see [reset behavior](RESET.md).

Fingerprints for all sixteen released single-image cartridges come from MAME's [VideoBrain software list](https://github.com/mamedev/mame/blob/master/hash/vidbrain.xml).

## Summary

| Cartridge | Size | Slot device |
|---|---|---|
| Blackjack | 2K | standard |
| Checkers | 4K | standard |
| Demonstration | 4K | standard |
| Financier | 4K | standard |
| Gladiator | 4K | standard |
| Lemonade Stand | 4K | standard |
| Math Tutor 1 | 4K | standard |
| Money Minder | 4K | money_minder |
| Music Teacher 1 | 2K | standard |
| Pinball | 2K | standard |
| Tennis | 4K | standard |
| Timeshare | 2K | timeshare |
| Vice Versa | 4K | standard |
| VideoArtist | 2K | standard |
| Wordwise 1 | 2K | standard |
| Wordwise 2 | 2K | standard |
| APL/S: The Computational Language | 16K | comp_language |
| Information Manager | 8K | info_manager |

## Split cartridge conversion

Use the [cartridge converter](../tools/README.md#cartridges) to assemble MAME archives automatically, or follow the layouts below.

Extract the chip dumps from each archive and concatenate them in the order below. Every chip is 2,048 bytes; each padding block is 2,048 zero bytes.

### APL/S: The Computational Language (`complang.zip`)

Concatenate A, B, C, D, E, F, G, then 2,048 zero bytes:

```text
0310_apls-a.u1
0311_apls-b.u4
0312_apls-c.u3
0313_apls-d.u6
0314_apls-e.u2
0315_apls-f.u5
0316_apls-g.u11
2,048 zero bytes
```

Save as a `.bin` file: 16,384 bytes.

### Information Manager (`infoman.zip`)

Concatenate the 1000 chip, 2,048 zero bytes, the 3000 chip, then the 3800 chip:

```text
vb1200a_1000-17ff_9_25_78_51
2,048 zero bytes
vb1200c_3000-37ff_9_25_78_51
vb-1200_3800-3fff_9_26_78
```

Save as a `.bin` file: 8,192 bytes. Information Manager also requires [Expander 1 firmware](EXPANDER1.md).

## Mapper tests

`make -C verilator test-cartridges` checks bank selection, RAM, DMA, reset behavior, and the existing cartridge mappings without ROM files.

## Software behavior

### Financier

The title resets itself after pressing NEXT or typing for a bit due to an incomplete dump. The CPU calls `30F7` from `1C9F`, reads `FF` from the unmapped cartridge expansion window, and continues to the BIOS entry at `4000`. The published [disassembly](https://orphanedgames.com/videobrain/f8_programming/f8_source.htm) contains this call and further calls into `3000-3FFF`. A simple mirror of the 4K image would put `30F7` inside an instruction operand at `10F7`. The expected code and cartridge decoding for this region remain unverified.

## Slot device reference

From MAME `bus/vidbrain/`. `/CS1` is 1000-17FF and `/CS2` is 1800-1FFF.

| Mapper | CS1 | CS2 | 3000-3FFF |
|---|---|---|---|
| standard | ROM | ROM | - |
| timeshare | 2K ROM | 1K RAM, mirrored | - |
| money_minder | 4K ROM | 4K ROM | 1K RAM at 3800, mirrored |
| info_manager | 2K ROM | 1K RAM | ROM |
| comp_language | 2K ROM, bank writes | ROM to 1BFF, RAM at 1C00 | banked ROM |

## BASIC homebrew mapping

The BASIC fallback is a new homebrew profile, not a historical cartridge.
It combines the Timeshare framebuffer layout with expansion workspace:

| CPU address | Storage |
| --- | --- |
| `1000-17FF` | Selected 2 KiB ROM bank, eight banks in a 16 KiB image |
| `1800-1BFF` | 1 KiB cartridge RAM |
| `1C00-1FFF` | Mirror of cartridge RAM |
| `3000-3FFF` | 4 KiB workspace RAM |

A CPU write to `17FF` selects the bank from data bits 2:0. Other ROM writes
have no effect; reads of `17FF` return ROM data. Selection takes effect on
the next access. CPU and video DMA see the same selected ROM bank; DMA
reads cartridge RAM through both CS2 mirrors. Workspace RAM is CPU-only.

Reset, power cycle, cartridge unload, and the first byte of a replacement
download select bank zero. Reset preserves RAM. Power cycle clears internal
and cartridge RAM; workspace RAM retains the existing 4K RAM profile's
behavior and must be initialized by software. Known cartridge fingerprints
take precedence over this fallback.

Software reserves `1700-17FF` as identical common code/data in every bank,
including bank-switch call and return stubs. This convention is enforced by
image builders, not the mapper. Code that switches elsewhere must ensure
the next instruction exists at the same address in the selected bank.
