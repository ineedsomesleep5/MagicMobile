"""Artifact/source guard fixtures only; no fixture is an XMage/native engine."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import verify_native_candidate as candidate
import download_issue4_native as download
import wait_issue4_native as wait

SHA = 'a' * 40


class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in candidate.REQUIRED_FILES:
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(SHA + '\n' if name == 'commit.txt' else 'EXPLICIT artifact-parser fixture')
        self.rehash()
    def rehash(self):
        lines = [candidate.digest(self.root / name) + '  ./' + name for name in sorted(candidate.REQUIRED_FILES)]
        (self.root / 'SHA256SUMS').write_text('\n'.join(lines) + '\n')
    def test_consistent_receipt(self):
        self.assertEqual(set(candidate.validate_receipt(self.root, SHA)), candidate.REQUIRED_FILES)
    def test_color_patch_is_a_required_hash_covered_build_input(self):
        names = {'color-patch/src/java/awt/Color.java', 'color-patch/classes/java/awt/Color.class',
                 'color-patch/color-patch-manifest.json'}
        self.assertTrue(names <= candidate.REQUIRED_FILES)
    def test_missing_required_file(self):
        (self.root / 'libmmengine.a').unlink()
        with self.assertRaises(ValueError): candidate.validate_receipt(self.root, SHA)
    def test_changed_library(self):
        (self.root / 'jdk/libjava.a').write_text('changed fixture')
        with self.assertRaises(ValueError): candidate.validate_receipt(self.root, SHA)
    def test_different_source(self):
        with self.assertRaises(ValueError): candidate.validate_receipt(self.root, 'b' * 40)
    def test_unhashed_extra(self):
        (self.root / 'extra.a').write_text('extra')
        with self.assertRaises(ValueError): candidate.validate_receipt(self.root, SHA)
    def test_unhashed_scope_is_nonlinking_text_only(self):
        (self.root / 'SCOPE.txt').write_text('fixture scope')
        candidate.validate_receipt(self.root, SHA)
    def test_escape_hash_path(self):
        with (self.root / 'SHA256SUMS').open('a') as stream:
            stream.write('0' * 64 + '  ../escape\n')
        with self.assertRaises(ValueError): candidate.validate_receipt(self.root, SHA)
    def test_duplicate_hash_path(self):
        p = self.root / 'SHA256SUMS'
        p.write_text(p.read_text() + p.read_text().splitlines()[0] + '\n')
        with self.assertRaises(ValueError): candidate.validate_receipt(self.root, SHA)
    def test_symlink(self):
        p = self.root / 'clib/libffi.a'; p.unlink(); p.symlink_to('../libmmengine.a')
        with self.assertRaises(ValueError): candidate.validate_receipt(self.root, SHA)
    def test_unpinned_source(self):
        with self.assertRaises(ValueError): candidate.validate_receipt(self.root, 'main')


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Artifact guard fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.write('engine/core/Fixture.java', 'fixture source, not executable rules')
        self.write('scripts/build_native_ios.sh', '# fixture')
        self.git('add', '.'); self.git('commit', '-qm', 'fixture source')
        self.base = self.git('rev-parse', 'HEAD')
    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], text=True, stderr=subprocess.DEVNULL).strip()
    def write(self, relative, text):
        p = self.root / candidate.ENGINE / relative
        p.parent.mkdir(parents=True, exist_ok=True); p.write_text(text)
    def commit(self):
        self.git('add', '.'); self.git('commit', '-qm', 'fixture change')
    def test_same_source(self):
        result = candidate.source_identity(self.root, self.base)
        self.assertEqual(result['engineSourceCommit'], result['appSourceCommit'])
    def test_swift_only_change_keeps_engine_equal(self):
        self.write('swift/New.swift', '// fixture'); self.commit()
        result = candidate.source_identity(self.root, self.base)
        self.assertNotEqual(result['engineSourceCommit'], result['appSourceCommit'])
    def test_engine_change_rejected(self):
        self.write('engine/core/Fixture.java', 'changed'); self.commit()
        with self.assertRaises(ValueError): candidate.source_identity(self.root, self.base)
    def test_new_engine_file_rejected(self):
        self.write('engine/core/New.java', 'added'); self.commit()
        with self.assertRaises(ValueError): candidate.source_identity(self.root, self.base)
    def test_xmage_test_only_changes_remain_conservatively_guarded(self):
        path = 'engine/xmage/src/test/java/Fixture.java'
        self.write(path, '// compiled only to build/test-real'); self.commit()
        with self.assertRaises(ValueError): candidate.source_identity(self.root, self.base)
    def test_xmage_main_changes_remain_rejected(self):
        self.write('engine/xmage/src/main/java/Fixture.java', '// runtime'); self.commit()
        with self.assertRaises(ValueError): candidate.source_identity(self.root, self.base)
    def test_core_test_changes_remain_rejected_because_they_are_on_aot_classpath(self):
        self.write('engine/core/src/test/java/Fixture.java', '// compiled to build/core'); self.commit()
        with self.assertRaises(ValueError): candidate.source_identity(self.root, self.base)
    def test_runtime_changes_cannot_hide_beside_test_changes(self):
        self.write('engine/xmage/src/test/java/Fixture.java', '// test')
        self.write('engine/xmage/src/main/java/Fixture.java', '// runtime'); self.commit()
        with self.assertRaises(ValueError): candidate.source_identity(self.root, self.base)
    def test_build_input_change_rejected(self):
        self.write('scripts/build_native_ios.sh', '# changed'); self.commit()
        with self.assertRaises(ValueError): candidate.source_identity(self.root, self.base)
    def test_dirty_tracked_source_rejected(self):
        self.write('engine/core/Fixture.java', 'uncommitted')
        with self.assertRaises(subprocess.CalledProcessError): candidate.source_identity(self.root, self.base)


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
    def archive(self, name='include/fixture.h'):
        archive = self.root / 'fixture.zip'
        with zipfile.ZipFile(archive, 'w') as out: out.writestr(name, 'fixture')
        return archive
    def test_safe_extract(self):
        download.extract(self.archive(), self.root / 'new')
        self.assertEqual((self.root / 'new/include/fixture.h').read_text(), 'fixture')
    def test_existing_destination_refused(self):
        with self.assertRaises(ValueError): download.extract(self.archive(), self.root)
    def test_escape_refused(self):
        with self.assertRaises(ValueError): download.extract(self.archive('../escape'), self.root / 'new')
    def test_absolute_refused(self):
        with self.assertRaises(ValueError): download.extract(self.archive('/escape'), self.root / 'new')
    def test_redirect_does_not_forward_credentials(self):
        request = urllib.request.Request('https://api.github.com/f', headers={'Authorization': 'Bearer FIXTURE'})
        redirect = download.PrivateRedirect().redirect_request(request, None, 302, 'Found', {}, 'https://blob.example.invalid/file')
        self.assertIsNone(redirect.get_header('Authorization'))
    def test_http_redirect_refused(self):
        request = urllib.request.Request('https://api.github.com/f')
        with self.assertRaises(ValueError):
            download.PrivateRedirect().redirect_request(request, None, 302, 'Found', {}, 'http://example.invalid/file')


class RunTests(unittest.TestCase):
    def run_value(self):
        return {'id': 10, 'head_sha': SHA, 'repository': {'full_name': wait.REPOSITORY},
                'head_repository': {'full_name': wait.REPOSITORY},
                'path': '.github/workflows/magicmobile-far-calls.yml'}
    def test_exact_run(self): wait.validate_run(self.run_value(), 10, SHA)
    def test_wrong_revision(self):
        with self.assertRaises(ValueError): wait.validate_run(self.run_value(), 10, 'b' * 40)
    def test_foreign_head_repository(self):
        run = self.run_value(); run['head_repository']['full_name'] = 'fixture/other'
        with self.assertRaises(ValueError): wait.validate_run(run, 10, SHA)
    def test_wrong_workflow(self):
        run = self.run_value(); run['path'] = '.github/workflows/probe.yml'
        with self.assertRaises(ValueError): wait.validate_run(run, 10, SHA)


if __name__ == '__main__': unittest.main()
