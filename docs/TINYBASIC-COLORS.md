# Tiny BASIC colors

COLOR sets the background; TCOLOR (also TC.) sets all displayed text,
including existing text. Both accept expressions from 0 to 31 and work directly
or in programs. Values outside that range report HOW. The text cursor retains
its own color. These are direct UV201 values; no palette renumbering is applied.

| Hue | Intensity 00 | Intensity 01 | Intensity 10 | Intensity 11 |
| --- | ---: | ---: | ---: | ---: |
| Black / gray | 0 | 8 | 16 | 24 |
| Red | 1 | 9 | 17 | 25 |
| Green | 2 | 10 | 18 | 26 |
| Yellow | 3 | 11 | 19 | 27 |
| Blue | 4 | 12 | 20 | 28 |
| Magenta | 5 | 13 | 21 | 29 |
| Cyan | 6 | 14 | 22 | 30 |
| Gray / white | 7 | 15 | 23 | 31 |

Video > Colors defaults to 16 (Original), preserving the established two-level
palette. Bit 3 is ignored in this mode: 0-7 duplicate 8-15, and 16-23 duplicate
24-31. Channel levels are 0/160 for codes 0-15 and 192/255 for codes 16-31.

Select 32 (Patent) to use both intensity bits. Its RGB channel levels are
below; each hue bit selects the on or off level for that channel. These are
approximate digital levels, not measurements of original hardware. The option
takes effect immediately and changes all cartridge output, including BIOS bars.

| Intensity | Off | On |
| --- | ---: | ---: |
| 00 | 0 | 160 |
| 01 | 64 | 192 |
| 10 | 128 | 224 |
| 11 | 192 | 255 |

With 32 (Patent), 0, 8, 16 and 24 produce four gray levels. Values 15
and 24 still produce the same RGB gray, so 32 codes do not imply 32 distinct RGB
colors. The BIOS color bars use only intensity 01 and 10: eight hues each.

The [Umtech patent](https://patents.google.com/patent/US4232374A/en) specifies
three hue bits and two intensity bits. It describes additional display composers
on cartridges for more display segments and superimposed objects; this does not
establish an expanded color palette. Original-machine analog intensity behavior
remains to be measured.

Examples:

```basic
COLOR 0
TCOLOR 31
TC. 9
TC. 23
```
