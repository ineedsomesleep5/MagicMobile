"""The staging guards read a real ELF layout: class files in the image heap and packed relocations."""
import importlib.util
import pathlib
import shutil
import struct
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    'stage_native', pathlib.Path(__file__).resolve().parents[1] / 'stage_native.py')
stage_native = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(stage_native)

CLASS_17 = b'\xca\xfe\xba\xbe\x00\x00\x00\x3d'  # a Java 17 class file header


def elf(sections):
    """A minimal ELF64 little-endian shared object with the given (name, type, data) sections."""
    names = b'\0' + b''.join(name.encode() + b'\0' for name, _, _ in sections) + b'.shstrtab\0'
    body, headers, offset = b'', [b'\0' * 64], 64
    name_offset = 1
    for name, kind, data in sections:
        headers.append(struct.pack('<IIQQQQIIQQ', name_offset, kind, 0, 0, offset, len(data), 0, 0, 1, 0))
        name_offset += len(name) + 1
        body += data; offset += len(data)
    headers.append(struct.pack('<IIQQQQIIQQ', name_offset, 3, 0, 0, offset, len(names), 0, 0, 1, 0))
    body += names; offset += len(names)
    ident = b'\x7fELF\x02\x01\x01' + b'\0' * 9
    header = ident + struct.pack('<HHIQQQIHHHHHH', 3, 0xb7, 1, 0, 0, offset, 0, 64, 0, 0, 64, len(headers), len(headers) - 1)
    return header + body + b''.join(headers)


def dynamic(*tags):
    return b''.join(struct.pack('<qQ', tag, value) for tag, value in tags) + struct.pack('<qQ', 0, 0)


class NativeSizeGuardTests(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)

    def write(self, data):
        path = self.dir / 'libmmengine.so'
        path.write_bytes(data)
        return path

    def test_counts_class_files_in_the_image_heap_only(self):
        heap = b'x' * 100 + CLASS_17 + b'y' * 50 + CLASS_17 + b'\xca\xfe\xba\xbe\x12\x34\x00\x3d'
        path = self.write(elf([('.text', 1, CLASS_17 * 3), ('.svm_heap', 1, heap),
                               ('.dynamic', 6, dynamic((stage_native.DT_RELASZ, 48)))]))
        self.assertEqual(stage_native.class_files(path), 2)
        self.assertEqual(stage_native.elf_sections(path)['.svm_heap'][2], len(heap))

    def test_clean_image_heap(self):
        path = self.write(elf([('.svm_heap', 1, b'\xca\xfe\xba\xbe' + b'\0' * 64), ('.dynamic', 6, dynamic())]))
        self.assertEqual(stage_native.class_files(path), 0)

    def test_packed_and_plain_relocations(self):
        packed = self.write(elf([('.svm_heap', 1, b'\0' * 8), ('.dynamic', 6, dynamic(
            (stage_native.DT_ANDROID_RELA, 0x1000), (stage_native.DT_ANDROID_RELASZ, 1234), (stage_native.DT_RELASZ, 0)))]))
        self.assertEqual(stage_native.relocations(packed),
                         {'packedAndroidRelaBytes': 1234, 'relaBytes': 0, 'relrBytes': 0, 'packed': True})
        plain = self.write(elf([('.svm_heap', 1, b'\0' * 8), ('.dynamic', 6, dynamic(
            (stage_native.DT_RELA, 0x1000), (stage_native.DT_RELASZ, 107974728)))]))
        self.assertEqual(stage_native.relocations(plain),
                         {'packedAndroidRelaBytes': 0, 'relaBytes': 107974728, 'relrBytes': 0, 'packed': False})

    def test_peak_rss_from_the_builder_log(self):
        log = self.dir / 'full-native.log'
        log.write_text('[INFO] [SUB]   153.0s (14.7% of total time) in 1085 GCs | Peak RSS: 12.27GB | CPU load: 3.46\n')
        self.assertEqual(stage_native.peak_rss(log), '12.27GB')
        self.assertIsNone(stage_native.peak_rss(self.dir / 'missing.log'))

    def test_rejects_non_elf(self):
        with self.assertRaises(ValueError):
            stage_native.elf_sections(self.write(b'not an elf' * 10))


if __name__ == '__main__':
    unittest.main()
