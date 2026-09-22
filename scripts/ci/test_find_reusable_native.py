"""Lookup fixtures; no fixture represents real native execution."""
import sys
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout
from io import StringIO

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_reusable_native as finder

SHA = 'a' * 40


class NativeLookupTests(unittest.TestCase):
    def run_value(self):
        return {'id': 17, 'head_sha': SHA, 'repository': {'full_name': finder.gate.REPOSITORY},
                'head_repository': {'full_name': finder.gate.REPOSITORY},
                'path': '.github/workflows/magicmobile-far-calls.yml',
                'status': 'completed', 'conclusion': 'success'}

    def lookup(self, run=None, artifact=None):
        run = run or self.run_value()
        artifact = artifact if artifact is not None else {'id': 9, 'name': 'issue4-full-native-candidate-' + SHA,
            'expired': False, 'workflow_run': {'id': 17}, 'digest': 'sha256:' + 'b' * 64}
        def get(path, *, deadline):
            return {'workflow_runs': [run]} if '/runs?' in path else {'artifacts': [artifact]}
        with patch.object(finder.candidate, 'source_identity', return_value={'equivalentInputTreeSHA256': 'c' * 64}), \
             patch.object(finder.gate, 'validate_attempt', return_value=1):
            return finder.find(Path('/fixture'), get)

    def test_exact_candidate(self):
        self.assertEqual(self.lookup()['artifactID'], 9)
    def test_foreign_run_rejected(self):
        run = self.run_value(); run['head_repository']['full_name'] = 'fork/other'
        with self.assertRaises(ValueError): self.lookup(run=run)
    def test_missing_artifact_rejected(self):
        def get(path, *, deadline):
            return {'workflow_runs': [self.run_value()]} if '/runs?' in path else {'artifacts': []}
        with patch.object(finder.candidate, 'source_identity', return_value={'equivalentInputTreeSHA256': 'c' * 64}), \
             patch.object(finder.gate, 'validate_attempt', return_value=1):
            with self.assertRaises(ValueError): finder.find(Path('/fixture'), get)
    def test_corrupt_digest_rejected(self):
        artifact = {'id': 9, 'name': 'issue4-full-native-candidate-' + SHA,
                    'expired': False, 'workflow_run': {'id': 17}, 'digest': 'bad'}
        with self.assertRaises(ValueError): self.lookup(artifact=artifact)
    def test_changed_inputs_rejected(self):
        with patch.object(finder.candidate, 'source_identity', side_effect=ValueError('inputs differ')), \
             patch.object(finder.gate, 'validate_attempt', return_value=1):
            with self.assertRaises(ValueError): finder.find(Path('/fixture'), lambda path, deadline: {'workflow_runs': [self.run_value()]})


class ActualSourceIdentityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.write('packages/ondevice-engine/engine/Fixture.java', 'engine')
        self.write('apps/ios/View.swift', 'ui')
        self.commit()
        self.base = self.git('rev-parse', 'HEAD')

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], text=True).strip()

    def write(self, name, text):
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def commit(self):
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')

    def test_ui_only_change_maps_to_same_native_inputs(self):
        self.write('apps/ios/View.swift', 'new ui')
        self.commit()
        self.assertEqual(finder.candidate.source_identity(self.root, self.base)['engineSourceCommit'], self.base)

    def test_engine_change_invalidates(self):
        self.write('packages/ondevice-engine/engine/Fixture.java', 'new engine')
        self.commit()
        with self.assertRaises(ValueError): finder.candidate.source_identity(self.root, self.base)

    def test_unrelated_dirty_file_rejected(self):
        self.write('apps/ios/View.swift', 'uncommitted ui')
        with self.assertRaises(subprocess.CalledProcessError):
            finder.candidate.source_identity(self.root, self.base)


class ManifestTests(unittest.TestCase):
    def test_existing_manifest_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'manifest.json'
            path.write_text('keep')
            with patch.object(sys, 'argv', ['finder', '--output', str(path)]), \
                 patch.object(finder, 'find', side_effect=AssertionError('lookup should not start')):
                with self.assertRaises(SystemExit): finder.main()
            self.assertEqual(path.read_text(), 'keep')

    def test_manifest_and_commands_keep_original_ids(self):
        receipt = {'runID': 17, 'runAttempt': 1, 'engineCommit': SHA, 'artifactID': 9,
                   'artifactDigest': 'sha256:' + 'b' * 64, 'equivalentInputTreeSHA256': 'c' * 64,
                   'scope': 'fixture only'}
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'manifest.json'
            output = StringIO()
            with patch.object(sys, 'argv', ['finder', '--output', str(path)]), \
                 patch.object(finder, 'find', return_value=receipt), redirect_stdout(output):
                finder.main()
            self.assertEqual(__import__('json').loads(path.read_text()), receipt)
            for fragment in ('--run-id 17', '--artifact-id 9', receipt['artifactDigest'], SHA):
                self.assertIn(fragment, output.getvalue())


if __name__ == '__main__': unittest.main()
