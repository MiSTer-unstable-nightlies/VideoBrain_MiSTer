| Item | Details |
| --- | --- |
| Title | Tiny BASIC Enhanced 1.9 |
| Based on | Tiny BASIC for F8 by Jerry D. Fox |
| Port | Continuing port work previously done by Sean Riddle |
| Display | 24 x 15; 3072 bytes for programs and arrays |
| Serial | Expander 1; modem + printer; 300 baud, CR/LF |
| Tape | Expander 1; program text only; rewind before reading |
| Keyboard | Shift+T: <; Shift+Y: >; Shift toggles symbols |

Version 1.9 completes a hardware-confirmed two-record SAVE with matching CRCs,
reports TAPE OK and returns to READY. Restart/LOAD, LIST/RUN, VERI and COMP remain
the release checks against the same candidate.

| Command | Aliases | Function |
| --- | --- | --- |
| GE | >= | Greater than or equal |
| GT | > | Greater than |
| LE | <= | Less than or equal |
| LT | < | Less than |
| CLS | CL. | Clear screen; home cursor |
| MOVE x,y | MOV. | Cursor position: x 0-23, y 0-14 |
| COLOR n | C.   | Background color, 0-31 |
| TCOLOR n | TC. | All text color, 0-31 |
| SAVE | S. | Save program to record tape |
| LOAD | LO. | Clears program and attempts to load from tape |
| VERI | V. | Validate tape; preserve program |
| COMP | COM. | Compare tape with program |
| DUPE | D. | Copy playback to separate record tape |

TAPE OK/TAPE ERROR=pass/fail
WHAT=unrecognized syntax
SORRY=stack error
