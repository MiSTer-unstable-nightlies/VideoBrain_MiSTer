# Video output

Select **Video > Output**, then **Apply Video Output**.

| Output | Behavior |
| --- | --- |
| 480i (Original) | Native interlaced output |
| 240p | Native video buffered into progressive frames |
| 480p | Each buffered line doubled without cropping |

All modes retain native machine and audio timing. The shorter native field
receives a black bottom row in progressive output. Output changes take effect
at a native field boundary; progressive output briefly blanks while its buffer
starts. See [video timing and accuracy](ACCURACY.md#approximations-and-conveniences).

## Colors

**Video > Colors > 16 (Original)** is the default palette. **32 (Patent)** uses
both intensity bits with experimental RGB levels. The change takes effect
immediately and affects all cartridge output, including the BIOS color bars.
The 32 codes do not all produce distinct RGB colors. See
[color values and accuracy limits](TINYBASIC-COLORS.md).
