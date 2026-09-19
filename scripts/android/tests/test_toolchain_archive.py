import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from toolchain_archive import extract_toolchain, TOOLCHAIN, IGNORED_ABSOLUTE_LINK


class ArchiveTests(unittest.TestCase):
    def make(self, root, entries):
        archive = root / 'fixture.tar'
        with tarfile.open(archive, 'w') as output:
            for path, target in entries:
                member = tarfile.TarInfo(path)
                if target is None:
                    member.size = 4
                    output.addfile(member, io.BytesIO(b'test'))
                else:
                    member.type = tarfile.SYMTYPE
                    member.linkname = target
                    output.addfile(member)
        return archive

    def test_exact_unused_link_omitted(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name); out = root / 'out'; out.mkdir()
            archive = self.make(root, [(TOOLCHAIN + '/release', None), (IGNORED_ABSOLUTE_LINK, '/builder/private/libfreetype.a')])
            omissions = extract_toolchain(archive, out)
            self.assertEqual(len(omissions), 1)
            self.assertEqual((out / TOOLCHAIN / 'release').read_bytes(), b'test')
            self.assertFalse((out / IGNORED_ABSOLUTE_LINK).is_symlink())
            self.assertTrue((out / 'archive-omissions.json').exists())

    def test_other_unsafe_links_and_paths_rejected(self):
        cases = [('../escaped', None), ('/tmp/escaped', None),
                 ('other/release', None), (TOOLCHAIN + '/lib/bad', '/tmp/escaped'),
                 (TOOLCHAIN + '/bad', '../../escaped')]
        for entry in cases:
            with self.subTest(entry=entry), tempfile.TemporaryDirectory() as name:
                root = Path(name); out = root / 'out'; out.mkdir()
                with self.assertRaises((ValueError, tarfile.FilterError)):
                    extract_toolchain(self.make(root, [entry]), out)

    def test_safe_relative_link_and_regular_freetype_retained(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name); out = root / 'out'; out.mkdir()
            entries = [(TOOLCHAIN + '/lib/real', None), (TOOLCHAIN + '/lib/link', 'real'), (IGNORED_ABSOLUTE_LINK, None)]
            self.assertEqual(extract_toolchain(self.make(root, entries), out), [])
            self.assertEqual((out / TOOLCHAIN / 'lib/link').read_bytes(), b'test')
            self.assertEqual((out / IGNORED_ABSOLUTE_LINK).read_bytes(), b'test')

    def test_duplicate_and_nonempty_destinations_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name); out = root / 'out'; out.mkdir()
            entry = (TOOLCHAIN + '/release', None)
            archive = self.make(root, [entry, entry])
            with self.assertRaises(ValueError): extract_toolchain(archive, out)
            (out / 'valuable').write_text('keep')
            with self.assertRaises(ValueError): extract_toolchain(archive, out)
            self.assertEqual((out / 'valuable').read_text(), 'keep')

if __name__ == '__main__': unittest.main()
