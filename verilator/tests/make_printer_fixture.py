"""Build a synthetic two-record integer database from the checked APPLE schema."""
import binascii
from pathlib import Path
import struct
import sys

root = Path(__file__).resolve().parent / 'fixtures' / 'input'
b = (root / 'saves/Information Manager - APPLE.vbt').read_bytes()
n = struct.unpack_from('<I', b, 8)[0]
falls = []
stamp = 0
previous = 1
for j in range(n):
    w = struct.unpack_from('<I', b, 512 + 4 * j)[0]
    level = w >> 31
    if previous and not level:
        falls.append(stamp)
    stamp += w & 0x7fffffff
    previous = level
bits = []
i = 0
while i < len(falls):
    one = i + 1 < len(falls) and falls[i + 1] - falls[i] < 17182
    bits.append(int(one))
    i += 2 if one else 1
assert len(bits) % 8 == 0
decoded = bytes(sum(bits[i + j] << (7 - j) for j in range(8))
                for i in range(0, len(bits), 8))
assert decoded[:18] == b'\xff' * 16 + b'\x01\xcd'
size = int.from_bytes(decoded[18:20], 'big')
assert size == 253
assert binascii.crc_hqx(decoded[18:20 + size], 0) == int.from_bytes(decoded[20 + size:22 + size], 'little')
definition = bytearray(decoded[20:20 + size])
assert definition[231] == 0x11 and definition[211] == 8
definition[231] = 1  # type i, eight-byte signed packed decimal
payloads = [bytes(definition), bytes(7) + b'\x02', bytes(7) + b'\x03', b'']
runs = []


def run(level, ticks):
    if runs and runs[-1] >> 31 == level:
        runs[-1] += ticks
    else:
        runs.append(level << 31 | ticks)


for payload in payloads:
    body = len(payload).to_bytes(2, 'big') + payload
    block = b'\xff' * 16 + b'\x01\xcd' + body + binascii.crc_hqx(body, 0).to_bytes(2, 'little') + b'\0'
    for copy in range(3):
        run(1, 2 * 14318180)
        for value in block:
            for shift in range(7, -1, -1):
                run(0, 2143)
                if value >> shift & 1:
                    run(1, 14318 - 2143)
                    run(0, 2143)
                    run(1, 14318 - 2143)
                else:
                    run(1, 28636 - 2143)
run(1, 1431818)
image = bytearray(131072)
struct.pack_into('<4sII', image, 0, b'VBT1', 14318180, len(runs))
assert 512 + len(runs) * 4 <= len(image)
for j, word in enumerate(runs):
    struct.pack_into('<I', image, 512 + j * 4, word)
Path(sys.argv[1]).write_bytes(image)
print(f'Synthetic ITEM integers 2,3; {len(runs)} intervals; expected TOTAL 5')
