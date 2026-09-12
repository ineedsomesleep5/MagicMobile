"""Build-tool fixtures only; these tests never execute an ARM64 instruction."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

PATH = Path(__file__).resolve().parents[1] / 'scripts/prepare_gluon_far_calls.py'
SPEC = importlib.util.spec_from_file_location('far_call_tools', PATH)
tools = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tools)


class CompilerPatchToolsTests(unittest.TestCase):
    def test_jvmci_exports_reach_graal_compiler_as_well_as_builder(self):
        descriptions = {
            'org.graalvm.sdk': 'exports org.graalvm.word\ncontains org.graalvm.nativeimage.impl\n',
            'jdk.internal.vm.compiler': 'contains org.graalvm.compiler.code\n',
            'jdk.internal.vm.ci': 'qualified exports jdk.vm.ci.code.site to jdk.aot\ncontains jdk.vm.ci.aarch64\n',
        }
        with patch.object(tools.subprocess, 'check_output', side_effect=lambda args, **kw: descriptions[args[-1]]):
            flags = tools.module_exports(Path('/test-only/java'))
        exports = dict(value.split('=', 1) for value in flags[1::2])
        self.assertIn('jdk.internal.vm.compiler', exports['jdk.internal.vm.ci/jdk.vm.ci.code.site'].split(','))
        self.assertIn('ALL-UNNAMED', exports['jdk.internal.vm.ci/jdk.vm.ci.code.site'].split(','))
        self.assertNotIn('jdk.internal.vm.ci', exports['jdk.internal.vm.ci/jdk.vm.ci.code.site'].split(','))
        self.assertEqual(flags[::2], ['--add-exports'] * 5)

    def test_hash_rejects_tampered_or_symlinked_source(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw); source = root / 'source'; link = root / 'link'
            source.write_bytes(b'original')
            expected = hashlib.sha256(b'original').hexdigest()
            tools.verify(source, expected)
            link.symlink_to(source)
            with self.assertRaises(ValueError): tools.verify(link, expected)
            source.write_bytes(b'tampered')
            with self.assertRaises(ValueError): tools.verify(source, expected)

    def test_private_jar_replacement_preserves_other_entries(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw); jar = root / 'svm.jar'; classes = root / 'classes'
            name = 'com/oracle/svm/Test.class'
            (classes / name).parent.mkdir(parents=True)
            (classes / name).write_bytes(b'new-test-fixture')
            with zipfile.ZipFile(jar, 'w') as output:
                output.writestr(name, b'old-test-fixture')
                output.writestr('keep.txt', b'unchanged')
            hashes = tools.replace_classes(jar, classes)
            with zipfile.ZipFile(jar) as actual:
                self.assertEqual(actual.read(name), b'new-test-fixture')
                self.assertEqual(actual.read('keep.txt'), b'unchanged')
                self.assertEqual(actual.namelist().count(name), 1)
            self.assertEqual(hashes[name], hashlib.sha256(b'new-test-fixture').hexdigest())

    def test_signed_jar_is_rejected_without_altering_original(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw); jar = root / 'svm.jar'; classes = root / 'classes'
            target = classes / 'com/oracle/svm/Test.class'
            target.parent.mkdir(parents=True); target.write_bytes(b'fixture')
            with zipfile.ZipFile(jar, 'w') as output: output.writestr('META-INF/SIGN.RSA', b'signature')
            before = tools.sha256(jar)
            with self.assertRaises(ValueError): tools.replace_classes(jar, classes)
            self.assertEqual(tools.sha256(jar), before)

    def test_no_arbitrary_package_or_empty_replacement(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw); classes = root / 'classes'; classes.mkdir()
            with self.assertRaises(ValueError): tools.replace_classes(root / 'absent.jar', classes)
            (classes / 'Wrong.class').write_bytes(b'fixture')
            with self.assertRaises(ValueError): tools.replace_classes(root / 'absent.jar', classes)


if __name__ == '__main__': unittest.main()
