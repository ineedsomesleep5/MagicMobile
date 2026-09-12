#!/usr/bin/env python3
"""Verify the intact Graal code image and seven ARM64 product long-call veneers.

Binary layout evidence only: this does not execute native code or prove gameplay.
Use memory mapping so the full-card archive/product need not fit in Python's heap.
"""
import argparse
import json
import mmap
from pathlib import Path
import struct

TARGETS = {
    'mm_far_graal_create_isolate': 'graal_create_isolate',
    'mm_far_graal_attach_thread': 'graal_attach_thread',
    'mm_far_graal_detach_thread': 'graal_detach_thread',
    'mm_far_graal_tear_down_isolate': 'graal_tear_down_isolate',
    'mm_far_engine_request': 'mm_engine_request',
    'mm_far_engine_free': 'mm_engine_free',
    'mm_far_engine_shutdown_v2': 'mm_engine_shutdown_v2',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


class MachO:
    def __init__(self, data, base=0, size=None):
        self.data, self.base = data, base
        self.size = len(data) - base if size is None else size
        header = self.unpack('<8I', 0)
        require(header[0:3] == (0xfeedfacf, 0x100000c, 0), 'Expected ARM64 Mach-O')
        self.filetype, self.flags = header[3], header[6]
        self.sections, self.symbols = {}, {}
        section_names = []
        cursor, symtab = 32, None
        for _ in range(header[4]):
            command, size = self.unpack('<II', cursor)
            require(size >= 8 and cursor + size <= 32 + header[5], 'Invalid load command')
            if command == 0x19:
                segment = self.unpack('<II16sQQQQiiII', cursor)
                count = self.unpack('<I', cursor + 64)[0]
                require(size == 72 + 80 * count, 'Invalid segment command')
                for index in range(count):
                    fields = self.unpack('<16s16sQQIIIIIIII', cursor + 72 + 80 * index)
                    key = tuple(value.rstrip(b'\0').decode() for value in (fields[1], fields[0]))
                    require(key not in self.sections, 'Duplicate section')
                    section_names.append(key)
                    self.sections[key] = dict(address=fields[2], size=fields[3], offset=fields[4],
                                              alignment=fields[5], relocations=fields[6], count=fields[7])
                    if key in (('__TEXT', '__text'), ('__DATA', '__data')):
                        self.bytes(fields[4], fields[3])
                        if self.filetype == 2:
                            protection = 5 if key[0] == '__TEXT' else 3
                            require(segment[2].rstrip(b'\0').decode() == key[0]
                                    and segment[7] == protection and segment[8] == protection,
                                    'Product section has incorrect loader protections')
                            require(segment[3] <= fields[2] and fields[2] + fields[3] <= segment[3] + segment[4]
                                    and segment[5] <= fields[4] and fields[4] + fields[3] <= segment[5] + segment[6]
                                    and fields[2] - segment[3] == fields[4] - segment[5],
                                    'Section does not match its loader mapping')
            elif command == 2:
                symtab = self.unpack('<4I', cursor + 8)
            cursor += size
        require(cursor == 32 + header[5] and symtab is not None, 'Missing symbols or invalid commands')
        symoff, count, stroff, strsize = symtab
        self.symtab = symtab
        self.bytes(stroff, strsize)
        required = {'___text', '___data'} | {'_' + s for s in set(TARGETS) | set(TARGETS.values())}
        for index in range(count):
            nameoff, kind, section, _, value = self.unpack('<IBBHQ', symoff + index * 16)
            if kind & 0xe0 or kind & 0x0e != 0x0e or section == 0:
                continue
            require(nameoff < strsize, 'Invalid symbol name')
            start = base + stroff + nameoff
            end = data.find(b'\0', start, base + stroff + strsize)
            require(end >= start, 'Unterminated symbol')
            name = data[start:end].decode()
            if name in required:
                require(name not in self.symbols, 'Duplicate required symbol: ' + name)
                expected = ('__DATA', '__data') if name == '___data' else ('__TEXT', '__text')
                require(section <= len(section_names) and section_names[section - 1] == expected,
                        'Required symbol belongs to the wrong section: ' + name)
                bounds = self.sections[expected]
                require(bounds['address'] <= value < bounds['address'] + bounds['size'],
                        'Required symbol is outside its section: ' + name)
                self.symbols[name] = value

    def relocation_symbol(self, index):
        symoff, count, stroff, strsize = self.symtab
        require(index < count, 'Invalid relocation symbol index')
        nameoff, kind, section, _, value = self.unpack('<IBBHQ', symoff + index * 16)
        require(kind == 0x0e and nameoff < strsize and section > 0, 'Expected defined Graal data relocation')
        start = self.base + stroff + nameoff
        end = self.data.find(b'\0', start, self.base + stroff + strsize)
        require(end >= start and self.data[start:end] == b'___data' and self.symbols.get('___data') == value,
                'Unexpected Graal relocation target; review the new compiler layout')
        return '___data'

    def bytes(self, offset, count):
        require(offset >= 0 and count >= 0 and offset + count <= self.size, 'Mach-O range outside file')
        return self.data[self.base + offset:self.base + offset + count]

    def unpack(self, format, offset):
        count = struct.calcsize(format)
        require(offset >= 0 and offset + count <= self.size, 'Mach-O structure outside file')
        return struct.unpack_from(format, self.data, self.base + offset)


def engine_object(data):
    require(data[:8] == b'!<arch>\n', 'Expected static archive')
    cursor, found = 8, None
    while cursor < len(data):
        header = data[cursor:cursor + 60]
        require(len(header) == 60 and header[58:60] == b'`\n', 'Invalid archive member')
        size = int(header[48:58])
        start, name = cursor + 60, header[:16].decode().strip()
        require(size >= 0 and start + size <= len(data), 'Archive member outside file')
        payload = size
        if name.startswith('#1/'):
            length = int(name[3:])
            require(0 < length <= size, 'Invalid archive member name')
            name = data[start:start + length].rstrip(b'\0').decode()
            start, payload = start + length, size - length
        if name == 'io.magicmobile.nativebridge.ioslibrarymain.o':
            require(found is None, 'Duplicate Graal object')
            found = MachO(data, start, payload)
        cursor += 60 + size + size % 2
    require(cursor == len(data) and found is not None, 'Missing Graal object or malformed archive')
    return found


def veneer_target(instructions, address):
    adrp, add, branch = struct.unpack('<3I', instructions)
    require(adrp & 0x9f00001f == 0x90000010 and add & 0xffc003ff == 0x91000210
            and branch == 0xd61f0200, 'Invalid ADRP/ADD/BR x16 veneer')
    pages = ((adrp >> 29) & 3) | (((adrp >> 5) & 0x7ffff) << 2)
    if pages & (1 << 20):
        pages -= 1 << 21
    return (address & ~0xfff) + pages * 4096 + ((add >> 10) & 0xfff)


def verify_layout(engine, product):
    require(engine.filetype == 1 and not engine.flags & 0x2000, 'Graal must remain non-atomized')
    require(product.filetype == 2, 'Expected product executable')
    source = engine.sections[('__TEXT', '__text')]
    final = product.sections[('__TEXT', '__text')]
    require(source['alignment'] >= 12 and final['address'] % (1 << source['alignment']) == 0,
            'Graal page alignment changed')
    require(product.symbols['___text'] == final['address'] and source['size'] <= final['size'],
            'Graal image must begin the product text section')
    # Graal's internal calls and veneers are already patched. Only the declared
    # linker PAGE21/PAGEOFF12 immediate bits may differ from the original image.
    masks, addend = {}, None
    for index in range(source['count']):
        offset, bits = engine.unpack('<iI', source['relocations'] + index * 8)
        kind = bits >> 28
        require(kind in (3, 4, 10), 'Unexpected Graal text relocation (including BRANCH26)')
        require(offset >= 0 and offset % 4 == 0 and offset + 4 <= source['size'], 'Invalid text relocation')
        if kind == 10:  # ADDEND metadata does not itself modify an instruction.
            require(bits & 0x0f000000 == 0x04000000 and addend is None, 'Invalid ADDEND relocation')
            value = bits & 0xffffff
            addend = (offset, value - (1 << 24) if value & (1 << 23) else value)
            continue
        require(bits & 0x0f000000 == (0x0d000000 if kind == 3 else 0x0c000000),
                'Invalid PAGE relocation flags or width')
        require(addend is None or addend[0] == offset, 'Unpaired ADDEND relocation')
        name = engine.relocation_symbol(bits & 0xffffff)
        destination = product.symbols[name] + (addend[1] if addend else 0)
        addend = None
        require(offset not in masks, 'Duplicate instruction relocation')
        before = engine.unpack('<I', source['offset'] + offset)[0]
        after = product.unpack('<I', final['offset'] + offset)[0]
        if kind == 3:
            require(before & 0xffffffe0 == 0x90000000, 'PAGE21 requires an unpatched ADRP')
            immediate = ((after >> 29) & 3) | (((after >> 5) & 0x7ffff) << 2)
            if immediate & (1 << 20): immediate -= 1 << 21
            actual = ((final['address'] + offset) & ~4095) + immediate * 4096
            require(actual == destination & ~4095, 'PAGE21 resolves to the wrong page')
            masks[offset] = 0x60ffffe0
        else:
            # Gluon 22.1 emits either ADD Xd,Xn,#imm12 or LDR Xt,[Xn,#imm12*8].
            opcode = before & 0xffc00000
            require(opcode in (0x91000000, 0xf9400000) and before & 0x003ffc00 == 0,
                    'PAGEOFF12 requires an unpatched ADD or 64-bit LDR')
            scale = 8 if opcode == 0xf9400000 else 1
            require(((after >> 10) & 0xfff) * scale == destination & 4095,
                    'PAGEOFF12 resolves to the wrong offset')
            masks[offset] = 0x003ffc00
    require(addend is None, 'Dangling ADDEND relocation')
    cursor = 0
    for offset in sorted(masks) + [source['size']]:
        while cursor < offset:
            count = min(offset - cursor, 1024 * 1024)
            require(engine.bytes(source['offset'] + cursor, count) == product.bytes(final['offset'] + cursor, count),
                    f'Graal code bytes changed at or after offset {cursor:#x}')
            cursor += count
        if offset < source['size']:
            before = engine.unpack('<I', source['offset'] + offset)[0]
            after = product.unpack('<I', final['offset'] + offset)[0]
            require((before ^ after) & ~masks[offset] == 0, 'Relocation changed instruction opcode/registers')
            cursor += 4
    veneers = {}
    for wrapper, target in TARGETS.items():
        address, destination = product.symbols['_' + wrapper], product.symbols['_' + target]
        require(destination - final['address'] == engine.symbols['_' + target] - source['address'],
                'Graal entrypoint offset changed: ' + target)
        require(final['address'] + source['size'] <= address <= final['address'] + final['size'] - 12,
                'Long-call veneer is not after the intact Graal image')
        instructions = product.bytes(final['offset'] + address - final['address'], 12)
        require(veneer_target(instructions, address) == destination, 'Long-call veneer points to wrong entrypoint')
        veneers[wrapper] = {'target': target, 'distanceBytes': destination - address}
    return {'graalCodeBytes': source['size'], 'graalAlignmentBytes': 1 << source['alignment'],
            'relocatedInstructions': len(masks), 'relocatedTargetsVerified': True,
            'intactCodeImage': True, 'veneers': veneers,
            'scope': 'binary layout only; no native execution'}


def verify_files(archive, executable):
    with Path(archive).open('rb') as source, Path(executable).open('rb') as final:
        with mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as a:
            with mmap.mmap(final.fileno(), 0, access=mmap.ACCESS_READ) as b:
                return verify_layout(engine_object(a), MachO(b))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', required=True, type=Path)
    parser.add_argument('--executable', required=True, type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(verify_files(args.archive, args.executable), indent=2))
    except (ValueError, KeyError, OSError, struct.error) as error:
        parser.exit(2, f'Graal product layout refused: {error}\n')
