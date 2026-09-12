"""Fixture-only packaging guards. No native compilation, linking or execution."""
import importlib.util
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/prepare_ios_app_native.py'


class PrepareNativeTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('prepare_native', SCRIPT)
        self.native = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.native)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.archive = self.root / 'libmmengine.a'
        self.archive.write_bytes(b'!<arch>\nfixture only, not a native artifact')

    def packaging_fixture(self):
        header = self.root / 'generated.h'
        header.write_text('#include <graal_isolate.h>\n'
                          'char* mm_engine_request(graal_isolatethread_t*, char*, int);\n'
                          'void mm_engine_free(graal_isolatethread_t*, char*);\n'
                          'int mm_engine_shutdown_v2(graal_isolatethread_t*);\n')
        (self.root / 'graal_isolate.h').write_text('/* SDK header fixture only */')
        for name in ('clib', 'jdk'):
            (self.root / name).mkdir()
        for directory, names in (
                ('clib', ('jvm', 'libchelper', 'ffi', 'darwin')),
                ('jdk', ('java', 'nio', 'zip', 'net', 'prefs', 'fdlibm',
                         'j2pkcs11', 'jaas', 'extnet'))):
            for name in names:
                (self.root / directory / f'lib{name}.a').write_bytes(self.archive.read_bytes())
        (self.root / 'jdk/not-needed.a').write_text('do not copy')
        self.header = header
        self.destination = self.root / 'app/NativeEngine'
        # The only mocked seam is Apple's inspection process output. Fixture
        # bytes are deliberately not valid executable/object code.
        def inspect(*args):
            return {'lipo': 'arm64', 'otool': 'cmd LC_BUILD_VERSION\n platform 2\n',
                    'nm': '\n'.join('000 T _' + s for s in
                                    self.native.ENGINE_SYMBOLS + self.native.GRAAL_SYMBOLS)}[args[0]]
        self.inspection = patch.object(self.native, 'xcrun', side_effect=inspect)
        self.inspection.start()
        self.addCleanup(self.inspection.stop)
        return (self.archive, header, self.root / 'clib', self.root / 'jdk', self.destination)

    def test_dry_run_then_apply_copies_only_required_inputs_with_hashes(self):
        args = self.packaging_fixture()
        manifest = self.native.prepare(*args)
        self.assertFalse(self.destination.exists())
        self.assertNotIn('capabilities', manifest)
        self.native.prepare(*args, apply=True)
        self.assertEqual((self.destination / 'include/libmmengine.h').read_bytes(), self.header.read_bytes())
        self.assertFalse((self.destination / 'lib/not-needed.a').exists())
        self.assertEqual(self.native.verify_installed(self.destination), manifest)

    def test_missing_runtime_library_copies_nothing(self):
        args = self.packaging_fixture()
        (self.root / 'clib/libffi.a').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing input'):
            self.native.prepare(*args, apply=True)
        self.assertFalse(self.destination.exists())

    def test_runtime_archive_must_also_be_ios_arm64(self):
        args = self.packaging_fixture()
        original = self.native.xcrun.side_effect
        def inspect(*command):
            if command[0] == 'lipo' and command[-1].name == 'libjava.a':
                return 'x86_64'
            return original(*command)
        self.native.xcrun.side_effect = inspect
        with self.assertRaisesRegex(ValueError, 'ARM64'):
            self.native.prepare(*args, apply=True)
        self.assertFalse(self.destination.exists())

    def test_changing_source_during_inspection_copies_nothing(self):
        args = self.packaging_fixture()
        original = self.native.xcrun.side_effect
        def inspect(*command):
            if command[0] == 'nm':
                self.archive.write_bytes(self.archive.read_bytes() + b'changed fixture')
            return original(*command)
        self.native.xcrun.side_effect = inspect
        with self.assertRaisesRegex(ValueError, 'changed during inspection'):
            self.native.prepare(*args, apply=True)
        self.assertFalse(self.destination.exists())

    def test_missing_sdk_header_copies_nothing(self):
        args = self.packaging_fixture()
        (self.root / 'graal_isolate.h').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing sibling'):
            self.native.prepare(*args, apply=True)
        self.assertFalse(self.destination.exists())

    def test_nonarchive_fails_before_tool_inspection(self):
        self.archive.write_text('fixture without archive magic')
        with patch.object(self.native, 'xcrun', side_effect=AssertionError('must not inspect')):
            with self.assertRaisesRegex(ValueError, 'static archive'):
                self.native.validate_archive(self.archive)

    def test_wrong_header_signature_copies_nothing(self):
        args = self.packaging_fixture()
        self.header.write_text(self.header.read_text().replace('int mm_engine_shutdown_v2',
                                                             'void mm_engine_shutdown_v2'))
        with self.assertRaisesRegex(ValueError, 'ABI v2'):
            self.native.prepare(*args, apply=True)
        self.assertFalse(self.destination.exists())

    def test_identical_install_is_idempotent_but_changed_input_is_refused(self):
        args = self.packaging_fixture()
        self.native.prepare(*args, apply=True)
        before = (self.destination / 'manifest.json').read_bytes()
        self.native.prepare(*args, apply=True)
        self.archive.write_bytes(self.archive.read_bytes() + b'changed fixture')
        with self.assertRaisesRegex(ValueError, 'refusing to overwrite'):
            self.native.prepare(*args, apply=True)
        self.assertEqual((self.destination / 'manifest.json').read_bytes(), before)

    def test_modified_installed_file_fails_hash_check(self):
        self.native.prepare(*self.packaging_fixture(), apply=True)
        (self.destination / 'lib/libjava.a').write_bytes(b'changed fixture')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            self.native.verify_installed(self.destination)

    def test_extra_file_or_symlink_in_owned_tree_is_refused(self):
        args = self.packaging_fixture()
        self.native.prepare(*args, apply=True)
        extra = self.destination / 'unowned.txt'
        extra.write_text('keep me')
        with self.assertRaisesRegex(ValueError, 'file set'):
            self.native.prepare(*args, apply=True)
        extra.unlink()
        extra.symlink_to(self.archive)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.native.prepare(*args, apply=True)

    def test_symlink_destination_does_not_modify_target(self):
        args = self.packaging_fixture()
        self.destination.parent.mkdir()
        self.destination.symlink_to(self.root / 'jdk', target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink destination'):
            self.native.prepare(*args, apply=True)
        self.assertFalse((self.root / 'jdk/manifest.json').exists())

    def test_cli_requires_all_explicit_inputs(self):
        result = subprocess.run([sys.executable, '-B', str(SCRIPT), '--apply'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('are all required', result.stderr)

    def test_rejects_wrong_architecture_and_conflicting_or_missing_platform(self):
        for arch, commands, message in (
                ('x86_64', 'cmd LC_BUILD_VERSION\n platform 7\n', 'ARM64'),
                ('arm64 x86_64', 'cmd LC_BUILD_VERSION\n platform 2\n', 'ARM64'),
                ('arm64', 'cmd LC_BUILD_VERSION\n platform 7\n', 'IOS platform'),
                ('arm64', 'cmd LC_BUILD_VERSION\n platform 2\n platform 1\n', 'IOS platform'),
                ('arm64', 'cmd LC_VERSION_MIN_MACOSX\n', 'IOS platform'),
                ('arm64', 'cmd LC_SEGMENT_64\n', 'IOS platform')):
            with self.subTest(arch=arch, commands=commands):
                with patch.object(self.native, 'xcrun', side_effect=[arch, commands]):
                    with self.assertRaisesRegex(ValueError, message):
                        self.native.validate_archive(self.archive)

    def test_undefined_exports_do_not_count_as_real_engine(self):
        with patch.object(self.native, 'xcrun', side_effect=[
                'arm64', 'cmd LC_BUILD_VERSION\n platform 2\n',
                '\n'.join(' U _' + s for s in self.native.ENGINE_SYMBOLS + self.native.GRAAL_SYMBOLS)]):
            with self.assertRaisesRegex(ValueError, 'Missing defined native exports'):
                self.native.validate_archive(self.archive, engine=True)

    def test_rejects_toy_archive_even_with_engine_exports(self):
        symbols = '\n'.join('000 T _' + s for s in (
            'mm_engine_request', 'mm_engine_free', 'mm_engine_shutdown_v2',
            'graal_create_isolate', 'graal_attach_thread', 'graal_detach_thread',
            'graal_tear_down_isolate', 'mm_toolchain_probe'))
        def inspect(*args):
            return {'lipo': 'arm64', 'otool': 'cmd LC_BUILD_VERSION\n platform 2\n',
                    'nm': symbols}[args[0]]
        with patch.object(self.native, 'xcrun', side_effect=inspect):
            with self.assertRaisesRegex(ValueError, 'toy'):
                self.native.validate_archive(self.archive, engine=True)

    def test_archive_may_contain_unreferenced_gluon_delegate_member(self):
        self.packaging_fixture()
        original = self.native.xcrun.side_effect
        def inspect(*command):
            output = original(*command)
            return output + '\n000 S _OBJC_CLASS_$_AppDelegate\n' if command[0] == 'nm' else output
        self.native.xcrun.side_effect = inspect
        # Caller-owned main must exclude it from the final linked executable;
        # Gluon legitimately bundles this separate object in its static archive.
        self.native.validate_archive(self.archive, engine=True)

    def test_copy_failure_never_publishes_partial_tree_and_can_retry(self):
        args = self.packaging_fixture()
        original = self.native.shutil.copyfileobj
        def broken_copy(src, dst):
            dst.write(b'partial fixture')
            raise OSError('injected disk failure')
        with patch.object(self.native.shutil, 'copyfileobj', side_effect=broken_copy):
            with self.assertRaisesRegex(OSError, 'injected disk failure'):
                self.native.prepare(*args, apply=True)
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.destination.parent.iterdir()), [])
        self.native.prepare(*args, apply=True)
        self.native.verify_installed(self.destination)

    def test_source_changes_during_copy_leave_no_native_tree(self):
        args = self.packaging_fixture()
        original = self.native.shutil.copyfileobj
        def changed_copy(src, dst):
            original(src, dst)
            dst.write(b'changed fixture')
        with patch.object(self.native.shutil, 'copyfileobj', side_effect=changed_copy):
            with self.assertRaisesRegex(ValueError, 'changed while copying'):
                self.native.prepare(*args, apply=True)
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.destination.parent.iterdir()), [])

    def test_existing_staging_lock_is_preserved(self):
        args = self.packaging_fixture()
        self.destination.parent.mkdir()
        lock = self.destination.parent / '.NativeEngine.stage.lock'
        lock.write_text('another installer owns this')
        with self.assertRaisesRegex(ValueError, 'Another staging operation'):
            self.native.prepare(*args, apply=True)
        self.assertFalse(self.destination.exists())
        self.assertEqual(lock.read_text(), 'another installer owns this')

    def test_symlink_input_is_rejected_without_creating_destination(self):
        args = self.packaging_fixture()
        target = self.root / 'real-engine-fixture.a'
        self.archive.rename(target)
        self.archive.symlink_to(target)
        with self.assertRaisesRegex(ValueError, 'symlink native input'):
            self.native.prepare(*args, apply=True)
        self.assertFalse(self.destination.exists())

    def test_tree_is_fully_verified_before_atomic_publish(self):
        args = self.packaging_fixture()
        original = self.native.os.rename
        seen = []
        def inspect_publish(source, destination):
            self.assertFalse(destination.exists())
            self.native.verify_installed(source)
            seen.append(source)
            return original(source, destination)
        with patch.object(self.native.os, 'rename', side_effect=inspect_publish):
            self.native.prepare(*args, apply=True)
        self.assertEqual(len(seen), 1)
        self.native.verify_installed(self.destination)


if __name__ == '__main__':
    unittest.main()
