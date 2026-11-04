"""Generate Tiny BASIC input ABI fixtures without cartridge ROM dependencies."""
import argparse
from pathlib import Path
import struct
import sys
import uuid
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from vbc import Cartridge


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    original = bytearray(16384)
    original[0x6D0:0x6D9] = bytes.fromhex('56 42 4B 01 06 10 09 3F F9')
    cases = []
    for name, supported in [('marker', True), ('changed', True), ('version', False),
                            ('hook', False), ('unmarked', False)]:
        rom = original.copy()
        if name == 'changed':
            rom[123] = 0xA5
        elif name == 'version':
            rom[0x6D3] = 2
        elif name == 'hook':
            rom[0x6D6] = 10
        elif name == 'unmarked':
            rom[0x6D0:0x6D9] = bytes(9)
        (args.output / f'{name}.bin').write_bytes(rom)
        cases.append(f'{name}.bin {str(supported).lower()} 6')
        if name in ('marker', 'version'):
            head = struct.pack('<HHHH16sII', 1, 0, 6, 1,
                               uuid.UUID('f1b99b2e-6b46-498c-83e9-ade8c5d89600').bytes, 11, 0)
            cart = Cartridge(((b'HEAD', head), (b'CRC ', struct.pack('<I', zlib.crc32(rom))),
                              (b'ROM ', bytes(rom))))
            (args.output / f'{name}.vbc').write_bytes(cart.encode())
            cases.append(f'{name}.vbc {str(supported).lower()} 6')
    cases.append('marker.bin false 5')
    (args.output / 'cases.txt').write_text('\n'.join(cases) + '\n', encoding='ascii')


if __name__ == '__main__':
    main()
