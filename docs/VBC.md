# VideoBrain cartridge format, version 1.0

`.vbc` files describe a cartridge independently of its ROM fingerprint.
Explicit hardware declarations override detection and Mapper Fallback.
Absent optional declarations and unspecified values leave existing behavior
unchanged. Peripheral metadata does not connect devices or change settings.
Software identity does not enable patches or address-dependent input helpers.

## Container

All integers are unsigned, little-endian. FourCCs are four literal ASCII bytes.

```text
RIFF <u32: file length minus 8> VBCR
HEAD <u32: 32> <configuration>
[optional chunks]
ROM  <u32: payload length> <assembled ROM bytes>
```

Each chunk has a FourCC, a four-byte payload length, and its payload. Odd
payload lengths require one zero padding byte, excluded from the chunk length.
RIFF length includes all padding. HEAD must be first and ROM must be last;
each is mandatory. Defined chunks may occur only once. Unknown chunks are
optional and skipped by length; rewriting tools must preserve their bytes
and order. No compression or embedded firmware is defined.

The ROM payload must begin at or before byte offset 65536. Maximum file length
is 81920 bytes. A loader must reject truncated or inconsistent lengths,
duplicate defined chunks, nonzero padding, invalid fixed chunk sizes,
unsupported format/profile versions or required feature bits, and ROM sizes
that do not match the profile. A supplied CRC mismatch rejects the file.
The cartridge remains unavailable until the complete download is validated.
A rejected replacement leaves the cartridge unloaded.

Raw BIN loading retains fingerprint detection and Mapper Fallback. Files
beginning with `RIFF` are interpreted as containers, including when named BIN.

## HEAD: required configuration

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 2 | Major version, 1 |
| 2 | 2 | Minor version, 0 |
| 4 | 2 | Hardware profile, 0-6 |
| 6 | 2 | Profile version, 1 |
| 8 | 16 | Software UUID |
| 24 | 4 | Software revision, nonzero |
| 28 | 4 | Required feature flags, zero |

UUID bytes follow the canonical hexadecimal spelling from left to right,
without platform GUID byte swapping. Assign a UUID once per software project;
retain it across revisions. Independently maintained forks receive a new UUID.
Revision values are opaque identifiers, not compatibility levels. Change the
revision when program bytes or hardware requirements change. Metadata-only
corrections retain the revision. Neither field verifies ROM contents.

New mandatory behavior requires an allocated feature bit or format version.
Unknown optional metadata must not introduce mandatory behavior.

## Hardware profiles, version 1

Addresses are hexadecimal CPU addresses after the machine's address folding.
Sizes below are exact except for profiles 0 and 5. Unmapped cartridge expansion reads return FF.
ROM writes have no effect except the defined bank-selection writes.

| ID | Profile | ROM bytes | CPU storage |
| --- | --- | --- | --- |
| 0 | Standard | 1-4096 | ROM at 1000-1FFF; images up to 2K repeat in both 2K windows |
| 1 | Timeshare | 2048 | ROM at 1000-17FF; 1K RAM mirrored at 1800-1FFF |
| 2 | Money Minder | 4096 | ROM at 1000-1FFF; 1K RAM mirrored at 3800-3FFF |
| 3 | APL/S | 16384 | Fixed ROM at 1000-1BFF; 1K RAM at 1C00-1FFF; banked ROM at 3000-3FFF |
| 4 | Information Manager | 8192 | ROM at 1000-17FF and 3000-3FFF; 1K RAM mirrored at 1800-1FFF |
| 5 | Standard + 4K RAM | 1-4096 | Profile 0 plus 4K workspace RAM at 3000-3FFF |
| 6 | BASIC | 16384 | Selected 2K ROM bank at 1000-17FF; 1K RAM mirrored at 1800-1FFF; 4K workspace RAM at 3000-3FFF |

Standard, Timeshare, Money Minder, and profile 5 store their ROM consecutively
from payload offset zero. Information Manager stores its 2K CS1 ROM at offset
0000, 2K zero padding at 0800, and its expansion ROM at 1000.

Profiles 0 and 5 retain short payloads without file padding. Unpopulated ROM
bytes read as FF, including through DMA. Images of 1-2048 bytes use a 2K
window mirrored at 1800; images of 2049-4096 bytes use one 4K window.
RIFF alignment padding is not ROM data and is excluded from the ROM CRC.

APL/S stores seven 2K chips A-G consecutively, followed by 2K zero padding.
A and the lower half of B supply 1000-1BFF. Expansion banks select C/D, E/G,
or E/F for 3000-37FF / 3800-3FFF. Writes anywhere in 1000-17FF select the
next bank using this table; rows are data bits 1:0, columns address bits 1:0.

| Data / address | 0 | 1 | 2 | 3 |
| --- | --- | --- | --- | --- |
| 0 | 0 | 1 | 2 | 0 |
| 1 | 2 | 1 | 2 | 1 |
| 2 | 0 | 2 | 2 | 0 |
| 3 | 2 | 2 | 2 | 2 |

BASIC stores eight consecutive 2K banks. A write to 17FF selects data bits
2:0 for the next access. Reading 17FF returns ROM. Common bank-switch code
is a software convention and imposes no additional format restriction.

CPU and video DMA share cartridge ROM and 1K cartridge RAM. DMA uses the same
CS2 RAM mirrors and BASIC ROM bank. Expansion ROM and 4K workspace are CPU-only.

APL/S and BASIC select bank zero on cartridge replacement, unload, and power
cycle. Master Control preserves the APL/S bank but resets the BASIC bank.
Cartridge replacement and Master Control preserve RAM; a power cycle clears
the 1K cartridge RAM. Workspace RAM is not cleared by those operations and
must be initialized by software. The container adds no RAM initialization or
persistence behavior. See [reset controls](RESET.md).

Existing profile behavior is fixed. Different paging or RAM hardware requires
a new profile or profile version, rather than a title-specific exception.

## Optional declarations

### JOYS: four bytes

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 1 | Analog input mask; bits 0-3 are physical joysticks 1-4 |
| 1 | 1 | Fire-button mask; bits 0-3 are physical buttons 1-4 |
| 2 | 1 | Timing preset: 0 unspecified, 1 Gladiator, 2 Tennis |
| 3 | 1 | Reserved, zero |

For either input mask, FF means unspecified; 00 explicitly declares no use.
Other values must be 00-0F. Masks describe physical inputs, not player counts
or host-controller routing. They are advisory and do not disable input.
Preset zero preserves existing automatic detection. Explicit presets replace
automatic detection; manual OSD timing selection still takes precedence.

### SUPP: eight bytes

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 4 | Supported peripheral bits |
| 4 | 4 | Required peripheral bits, a subset of supported bits |

| Bit | Peripheral |
| --- | --- |
| 0 | Printer |
| 1 | Cassette 1 |
| 2 | Cassette 2 |
| 3 | Serial terminal |
| 4 | Modem |

Required means necessary for the program's primary function. Optional modes
and alternative requirements can be explained in NOTE. Absence of SUPP means
unspecified. Set bits assert support or a requirement; clear bits make no
claim about unlisted capabilities. Unassigned bits are retained and ignored.
No expander firmware
is selected or supplied by this chunk. The current core does not act on SUPP.

### Identity and dump information

| Chunk | Payload |
| --- | --- |
| BASE | Parent software UUID, 16 bytes; parent revision, u32 |
| STAT | u32: 0 unknown, 1 good, 2 suspect, 3 incomplete |
| CRC followed by a space | u32 CRC-32/ISO-HDLC of ROM payload only |

STAT records completeness/confidence, not whether software is original or
modified. Good means verified against the source. Absence means unknown.
BASE records derivation; it conveys no execution compatibility.

### Text metadata

UTF-8 without a terminating NUL. The core skips these payloads without
interpreting their contents. Dates use YYYY, YYYY-MM, or YYYY-MM-DD.

| Chunk | Contents |
| --- | --- |
| NAME | Display title |
| AUTH | Software author credits |
| PUBL | Publisher |
| DUMP | Dumper credits |
| DATE | Release date |
| DDAT | Dump date |
| VERS | Human-readable release/version |
| NOTE | Notes |
| MAME | Advisory software-list reference, such as vidbrain:complang |

MAME references do not override mapping or affect loading. Original chip
filenames remain in MAME's catalog rather than being duplicated here.

## Tools

Use [vbc.py](../tools/vbc.py) to pack, inspect, or extract a container. Packing
requires an explicit profile, UUID, and revision; it adds a payload CRC.
No title, capabilities, or dump quality are inferred. Output files must not
already exist.

```sh
python3 tools/vbc.py pack game.bin game.vbc --profile basic \
  --id 12345678-1234-5678-9abc-123456789abc --revision 1 --name "Example"
python3 tools/vbc.py inspect game.vbc
python3 tools/vbc.py extract game.vbc extracted.bin
```

Generate a distinct UUID for an actual project; the example is illustrative.
Optional declarations include `--axes 0x03 --buttons 0x03`,
`--joy-preset tennis`, `--support printer,cassette1`, and
`--require cassette1`. Use `pack --help` for all metadata options.

`make -C verilator test-vbc` checks the software parser and streaming hardware
loader using generated ROM-free fixtures, including invalid containers.
