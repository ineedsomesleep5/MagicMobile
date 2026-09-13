"""Synthetic binary-layout guards; these fixtures never execute instructions."""
import pathlib
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'scripts'))
from verify_graal_product_layout import MachO, TARGETS, engine_object, veneer_target, verify_files, verify_layout


def veneer(address, target):
    pages = ((target & ~4095) - (address & ~4095)) // 4096
    immediate = pages & 0x1fffff
    return struct.pack('<3I', 0x90000010 | ((immediate & 3) << 29) | ((immediate >> 2) << 5),
                       0x91000210 | ((target & 4095) << 10), 0xd61f0200)


def with_uuid(data, value=bytes(range(16))):
    data = bytearray(data)
    count, size = struct.unpack_from('<II', data, 16)
    data[32 + size:32 + size + 24] = struct.pack('<II16s', 0x1b, 24, value)
    struct.pack_into('<II', data, 16, count + 1, size + 24)
    return data


class ImageFixture(MachO):
    def __init__(self, code, address, filetype):
        entries = [('___text', address, 1), ('___data', address + 0x4000, 2)]
        for index, (wrapper, target) in enumerate(TARGETS.items()):
            entries.append(('_' + target, address + 20 + 4 * index, 1))
            if filetype == 2: entries.append(('_' + wrapper, address + 128 + 12 * index, 1))
        strings, symbols = bytearray(b'\0'), bytearray()
        for name, value, section in entries:
            symbols += struct.pack('<IBBHQ', len(strings), 0x0e, section, 0, value)
            strings += name.encode() + b'\0'
        def segment(name, vmaddr, fileoff, filesize, protection, section, sectionaddr, size, offset, reloc):
            return struct.pack('<II16sQQQQiiII', 0x19, 152, name, vmaddr, 0x8000, fileoff, filesize,
                               protection, protection, 1, 0) + struct.pack('<16s16sQQIIIIIIII',
                               section, name, sectionaddr, size, offset, 14, reloc, 0, 0, 0, 0, 0)
        commands = segment(b'__TEXT', address - 0x4000, 0, 0x8000, 5, b'__text', address, len(code), 0x4000, 0x8020)
        commands += segment(b'__DATA', address + 0x4000, 0x8000, 32, 3, b'__data', address + 0x4000, 32, 0x8000, 0)
        commands += struct.pack('<6I', 2, 24, 0x8120, len(entries), 0x8120 + len(symbols), len(strings))
        data = bytearray(struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, filetype, 3, len(commands), 0, 0) + commands)
        data += bytes(0x8120 - len(data)) + symbols + strings
        data[0x4000:0x4000 + len(code)] = code
        super().__init__(data)


class GraalLayoutTests(unittest.TestCase):
    def setUp(self):
        code = struct.pack('<I', 0xd503201f) * 32
        self.engine = ImageFixture(code, 0x1cb7c000, 1)
        address = 0x100004000
        self.product = ImageFixture(code + bytes(12 * len(TARGETS)), address, 2)
        for index, (wrapper, target) in enumerate(TARGETS.items()):
            offset, destination = 128 + 12 * index, address + 20 + 4 * index
            self.engine.symbols['_' + target] = 0x1cb7c000 + 20 + 4 * index
            self.product.symbols['_' + target] = destination
            self.product.symbols['_' + wrapper] = address + offset
            self.product.data[0x4000 + offset:0x4000 + offset + 12] = veneer(address + offset, destination)

    def test_intact_layout_accepted(self):
        result = verify_layout(self.engine, self.product)
        self.assertEqual(result['graalCodeBytes'], 128)
        self.assertEqual(len(result['veneers']), 7)

    def test_long_forward_and_backward_veneers(self):
        for address, target in ((0x100004000, 0x10be8da20), (0x10be8da20, 0x1001d5820)):
            self.assertEqual(veneer_target(veneer(address, target), address), target)

    def test_wrong_register_or_non_tail_branch_rejected(self):
        for index, bit in ((0, 1), (4, 1), (8, 1 << 21)):
            instructions = bytearray(veneer(0x1000, 0x2000))
            word = struct.unpack_from('<I', instructions, index)[0] ^ bit
            struct.pack_into('<I', instructions, index, word)
            with self.assertRaises(ValueError): veneer_target(instructions, 0x1000)

    def test_unchanged_graal_body_required(self):
        self.product.data[0x4000 + 100] ^= 1
        with self.assertRaisesRegex(ValueError, 'code bytes changed'): verify_layout(self.engine, self.product)

    def test_graal_alignment_required(self):
        self.product.sections[('__TEXT', '__text')]['address'] += 4
        with self.assertRaisesRegex(ValueError, 'alignment'): verify_layout(self.engine, self.product)

    def test_graal_first_required(self):
        self.product.symbols['___text'] += 16384
        with self.assertRaisesRegex(ValueError, 'begin'): verify_layout(self.engine, self.product)

    def test_atomization_rejected(self):
        self.engine.flags = 0x2000
        with self.assertRaisesRegex(ValueError, 'non-atomized'): verify_layout(self.engine, self.product)

    def test_entrypoint_offset_change_rejected(self):
        self.engine.symbols['_graal_create_isolate'] += 4
        with self.assertRaisesRegex(ValueError, 'entrypoint offset'): verify_layout(self.engine, self.product)

    def test_wrong_veneer_destination_rejected(self):
        self.product.data[0x4080:0x408c] = veneer(0x100004080, 0x100004018)
        with self.assertRaisesRegex(ValueError, 'wrong entrypoint'): verify_layout(self.engine, self.product)

    def add_relocation(self, kind, offset=0):
        section = self.engine.sections[('__TEXT', '__text')]
        flags = 0x0d000000 if kind == 3 else 0x0c000000
        struct.pack_into('<iI', self.engine.data, section['relocations'] + section['count'] * 8,
                         offset, kind << 28 | flags | 1)
        section['count'] += 1

    def test_declared_page_immediate_may_change(self):
        self.add_relocation(3)
        struct.pack_into('<I', self.engine.data, 0x4000, 0x90000010)
        self.product.data[0x4000:0x4004] = veneer(0x100004000, self.product.symbols['___data'])[:4]
        verify_layout(self.engine, self.product)

    def test_relocation_must_not_change_registers(self):
        self.test_declared_page_immediate_may_change()
        self.product.data[0x4000] ^= 1
        with self.assertRaisesRegex(ValueError, 'opcode/registers'): verify_layout(self.engine, self.product)

    def test_relocated_page_must_resolve_to_declared_target(self):
        self.test_declared_page_immediate_may_change()
        self.product.data[0x4003] ^= 0x20
        with self.assertRaisesRegex(ValueError, 'wrong page'): verify_layout(self.engine, self.product)

    def test_nop_cannot_be_used_as_page_relocation(self):
        self.add_relocation(3)
        with self.assertRaisesRegex(ValueError, 'ADRP'): verify_layout(self.engine, self.product)

    def test_loader_mapping_decoy_is_rejected(self):
        # Point the section bytes somewhere other than the bytes mapped at its VA.
        struct.pack_into('<I', self.product.data, 32 + 72 + 48, 0x5000)
        with self.assertRaisesRegex(ValueError, 'loader mapping'): MachO(self.product.data)

    def test_nonexecutable_or_writable_text_rejected(self):
        for protection in (1, 7):
            data = bytearray(self.product.data)
            struct.pack_into('<ii', data, 32 + 56, protection, protection)
            with self.assertRaisesRegex(ValueError, 'protections'): MachO(data)

    def test_required_symbol_section_and_range_checked(self):
        data = bytearray(self.product.data)
        data[0x8120 + 5] = 255
        with self.assertRaisesRegex(ValueError, 'wrong section'): MachO(data)
        data = bytearray(self.product.data)
        struct.pack_into('<Q', data, 0x8120 + 8, 0x100009000)
        with self.assertRaisesRegex(ValueError, 'outside its section'): MachO(data)

    def test_branch26_and_unknown_relocations_rejected(self):
        for kind in (2, 7):
            with self.subTest(kind=kind):
                self.setUp(); self.add_relocation(kind)
                with self.assertRaisesRegex(ValueError, 'Unexpected'): verify_layout(self.engine, self.product)

    def test_duplicate_or_out_of_range_relocations_rejected(self):
        for offset in (0, 128, -4):
            with self.subTest(offset=offset):
                self.setUp(); self.add_relocation(3); self.add_relocation(3, offset)
                with self.assertRaises(ValueError): verify_layout(self.engine, self.product)

    def test_invalid_archive_and_macho_refused(self):
        for data in (b'not an archive', b'!<arch>\n', b'!<arch>\ntruncated'):
            with self.assertRaises(ValueError): engine_object(data)
        for data in (bytes(32), struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 0, 0, 0, 0)):
            with self.assertRaises(ValueError): MachO(data)

    def dsym_pair(self, stripped=True):
        executable = with_uuid(self.product.data)
        debug = bytearray(executable)
        struct.pack_into('<I', debug, 12, 10)
        for command in (32, 32 + 152):
            struct.pack_into('<I', debug, command + 72 + 48, 0)
        # dSYM code bytes must never be used, even if coincidentally present.
        debug[0x4000:0x4080] = bytes(128)
        if stripped:
            struct.pack_into('<I', executable, 32 + 304 + 12, 0)  # empty LC_SYMTAB
        return executable, debug

    def test_matching_dsym_supplies_stripped_symbols(self):
        executable, debug = self.dsym_pair()
        product = MachO(executable)
        self.assertEqual(product.symbols, {})
        product.use_dsym(MachO(debug))
        self.assertTrue(verify_layout(self.engine, product)['intactCodeImage'])

    def test_existing_matching_executable_symbols_accepted(self):
        executable, debug = self.dsym_pair(stripped=False)
        product = MachO(executable)
        product.use_dsym(MachO(debug))
        verify_layout(self.engine, product)

    def test_dsym_virtual_section_has_no_file_range_requirement(self):
        _, debug = self.dsym_pair()
        struct.pack_into('<Q', debug, 32 + 72 + 40, 1 << 30)
        self.assertEqual(MachO(debug).sections[('__TEXT', '__text')]['size'], 1 << 30)
        for filetype in (1, 2):
            struct.pack_into('<I', debug, 12, filetype)
            with self.assertRaisesRegex(ValueError, 'outside file'): MachO(debug)

    def test_missing_uuid_in_either_file_rejected(self):
        for target in (0, 1):
            pair = self.dsym_pair()
            struct.pack_into('<I', pair[target], 32 + 328, 0x7fffffff)
            with self.assertRaisesRegex(ValueError, 'Missing.*UUID'):
                MachO(pair[0]).use_dsym(MachO(pair[1]))

    def test_zero_duplicate_malformed_uuid_rejected(self):
        for target in (0, 1):
            for failure in ('zero', 'duplicate', 'size'):
                with self.subTest(target=target, failure=failure):
                    data = self.dsym_pair()[target]
                    if failure == 'zero': data[32 + 328 + 8:32 + 328 + 24] = bytes(16)
                    elif failure == 'duplicate': data = with_uuid(data)
                    else: struct.pack_into('<I', data, 32 + 328 + 4, 16)
                    with self.assertRaisesRegex(ValueError, 'UUID'): MachO(data)

    def test_foreign_uuid_rejected(self):
        executable, debug = self.dsym_pair()
        debug[32 + 328 + 8] ^= 1
        with self.assertRaisesRegex(ValueError, 'UUID mismatch'):
            MachO(executable).use_dsym(MachO(debug))

    def test_wrong_dsym_filetype_rejected(self):
        executable, debug = self.dsym_pair()
        for filetype in (1, 2, 6):
            data = with_uuid(self.product.data)
            struct.pack_into('<I', data, 12, filetype)
            with self.assertRaises(ValueError): MachO(executable).use_dsym(MachO(data))
        with self.assertRaisesRegex(ValueError, 'executable and MH_DSYM'):
            MachO(debug).use_dsym(MachO(debug))

    def test_bad_or_missing_dsym_symbols_rejected(self):
        for failure in ('kind', 'zero-section', 'section', 'range', 'missing', 'duplicate'):
            with self.subTest(failure=failure):
                executable, debug = self.dsym_pair()
                if failure == 'kind': debug[0x8120 + 4] = 0
                elif failure == 'zero-section': debug[0x8120 + 5] = 0
                elif failure == 'section': debug[0x8120 + 5] = 2
                elif failure == 'range': struct.pack_into('<Q', debug, 0x8120 + 8, 0x100009000)
                elif failure == 'missing': struct.pack_into('<I', debug, 32 + 304 + 12, 1)
                else: debug[0x8120 + 16:0x8120 + 32] = debug[0x8120:0x8120 + 16]
                with self.assertRaises(ValueError): MachO(executable).use_dsym(MachO(debug))

    def test_dsym_section_must_match_actual_product(self):
        for field, value in ((32, 0x100003000), (40, 0x1000)):
            executable, debug = self.dsym_pair()
            struct.pack_into('<Q', debug, 32 + 72 + field, value)
            with self.assertRaises(ValueError): MachO(executable).use_dsym(MachO(debug))

    def test_existing_executable_symbol_conflict_rejected(self):
        executable, debug = self.dsym_pair(stripped=False)
        struct.pack_into('<Q', executable, 0x8120 + 2 * 16 + 8, 0x100004018)
        with self.assertRaisesRegex(ValueError, 'symbol conflict'):
            MachO(executable).use_dsym(MachO(debug))

    def test_dsym_does_not_bypass_product_mapping_or_code_checks(self):
        executable, debug = self.dsym_pair()
        struct.pack_into('<I', executable, 32 + 72 + 48, 0x5000)
        with self.assertRaisesRegex(ValueError, 'loader mapping'): MachO(executable)
        executable, debug = self.dsym_pair()
        executable[0x4064] ^= 1
        product = MachO(executable)
        product.use_dsym(MachO(debug))
        with self.assertRaisesRegex(ValueError, 'code bytes changed'): verify_layout(self.engine, product)

    def test_mapped_file_api_with_and_without_dsym(self):
        name = b'io.magicmobile.nativebridge.ioslibrarymain.o'
        payload = name + self.engine.data
        header = f'{"#1/" + str(len(name)):<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(payload):<10}`\n'.encode()
        archive = b'!<arch>\n' + header + payload + (b'\n' if len(payload) % 2 else b'')
        with tempfile.TemporaryDirectory(prefix='graal-layout-fixture-') as directory:
            root = pathlib.Path(directory)
            a, b, d = (root / name for name in ('engine.a', 'executable', 'dwarf'))
            a.write_bytes(archive)
            b.write_bytes(self.product.data)
            expected = verify_files(a, b)
            executable, debug = self.dsym_pair()
            # A completely stripped product may omit LC_SYMTAB, not just its entries.
            struct.pack_into('<I', executable, 32 + 304, 0x7fffffff)
            b.write_bytes(executable); d.write_bytes(debug)
            with self.assertRaisesRegex(ValueError, 'Missing symbols'): verify_files(a, b)
            result = verify_files(a, b, d)
            self.assertEqual(result.pop('uuid'), bytes(range(16)).hex())
            self.assertEqual(result.pop('symbolSource'), 'uuid-matched-dsym')
            self.assertEqual(result, expected)


if __name__ == '__main__': unittest.main()
