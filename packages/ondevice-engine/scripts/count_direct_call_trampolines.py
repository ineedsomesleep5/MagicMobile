#!/usr/bin/env python3
"""Count GraalVM's AArch64 direct-call trampolines in an object, archive or library.

GraalVM 24.1 places a trampoline after a method whose direct call cannot reach its target
(AArch64HostedTrampolineSupport): ADRP Xr, page; ADD Xr, Xr, #offset; BR Xr. This replaced the
22.1 far-call backport. Byte-pattern evidence only; it does not execute native code.
"""
import argparse
import mmap
from pathlib import Path
import re
import struct

BR = re.compile(rb'[\x00-\xe0][\x00-\x03]\x1f\xd6', re.DOTALL)  # BR Xn, little-endian


def count(data):
    found = 0
    for match in BR.finditer(data):
        start = match.start() - 8
        if start < 0:
            continue
        adrp, add, branch = struct.unpack_from('<3I', data, start)
        if branch & 0xfffffc1f != 0xd61f0000:
            continue
        register = (branch >> 5) & 0x1f
        if (adrp & 0x9f00001f == 0x90000000 | register
                and add & 0xffc003ff == 0x91000000 | register << 5 | register):
            found += 1
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    parser.add_argument('--minimum', type=int, default=0, help='fail below this many trampolines')
    args = parser.parse_args()
    with args.path.open('rb') as source, mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as data:
        found = count(data)
    print(f'DIRECT-CALL-TRAMPOLINES {found} {args.path}')
    if found < args.minimum:
        raise SystemExit(f'Expected at least {args.minimum} AArch64 direct-call trampolines')


if __name__ == '__main__':
    main()
