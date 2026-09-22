import hashlib
from datetime import datetime, timezone
from io import BytesIO
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import reuse_evidence as reuse


class FingerprintTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(['git', '-C', str(self.root), 'config', 'user.name', 'Fixture'], check=True)
        subprocess.run(['git', '-C', str(self.root), 'config', 'user.email', 'fixture@example.invalid'], check=True)
        self.write(reuse.WORKFLOW, 'steps: [test]')
        self.write('scripts/ci/reuse_evidence.py', 'policy')
        self.write('packages/ondevice-engine/engine/Fixture.java', 'engine')
        self.write('apps/ios/View.swift', 'view')
        self.base = self.commit()

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def commit(self):
        subprocess.run(['git', '-C', str(self.root), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.root), 'commit', '-qm', 'fixture'], check=True)
        return subprocess.check_output(['git', '-C', str(self.root), 'rev-parse', 'HEAD'], text=True).strip()

    def fp(self, sha, job):
        with patch.object(reuse, 'ROOT', self.root):
            return reuse.fingerprint(sha, job)

    def test_unchanged_job_inputs_reuse(self):
        self.write('apps/ios/View.swift', 'changed')
        newer = self.commit()
        self.assertEqual(self.fp(self.base, 'boundary-tests'), self.fp(newer, 'boundary-tests'))
        self.assertNotEqual(self.fp(self.base, 'swift'), self.fp(newer, 'swift'))

    def test_engine_and_workflow_invalidate(self):
        self.write('packages/ondevice-engine/engine/Fixture.java', 'changed')
        changed = self.commit()
        self.assertNotEqual(self.fp(self.base, 'real-jvm'), self.fp(changed, 'real-jvm'))
        self.write(reuse.WORKFLOW, 'steps: [different]')
        newer = self.commit()
        self.assertNotEqual(self.fp(changed, 'boundary-tests'), self.fp(newer, 'boundary-tests'))


class EvidenceTests(unittest.TestCase):
    def test_expired_lookup_budget_does_not_issue_request(self):
        with patch.object(reuse, 'LOOKUP_DEADLINE', 0), patch.object(reuse.OPENER, 'open') as request:
            with self.assertRaises(TimeoutError):
                reuse.get('/fixture')
            request.assert_not_called()

    def setUp(self):
        self.run = {'id': 42, 'head_sha': 'a' * 40, 'repository': {'full_name': reuse.REPO},
                    'head_repository': {'full_name': reuse.REPO}, 'path': reuse.WORKFLOW,
                    'event': 'push', 'head_branch': 'main', 'status': 'completed',
                    'conclusion': 'success', 'run_attempt': 1,
                    'created_at': datetime.now(timezone.utc).isoformat()}
        self.toolchain = {'imageOS': 'ubuntu', 'imageVersion': 'fixture', 'runnerArch': 'X64',
                          'uname': 'fixture', 'java': 'fixture'}
        self.receipt = {'schema': 1, 'job': 'real-jvm', 'commit': 'a' * 40,
                        'runID': 42, 'fingerprint': 'b' * 64,
                        'toolchain': self.toolchain, 'scope': 'CI job success only'}

    def payload(self, receipt=None):
        stream = BytesIO()
        with zipfile.ZipFile(stream, 'w') as archive:
            archive.writestr('receipt.json', json.dumps(self.receipt if receipt is None else receipt))
        return stream.getvalue()

    def check(self, receipt=None, missing=False, corrupt=False, failed_job=False):
        payload = self.payload(receipt)
        artifact = {'name': 'ci-evidence-real-jvm-42', 'id': 8, 'expired': False,
                    'workflow_run': {'id': 42}, 'digest': 'sha256:' + hashlib.sha256(payload).hexdigest()}
        if corrupt:
            artifact['digest'] = 'sha256:' + '0' * 64
        def fake(path, binary=False):
            if path.endswith('/jobs?per_page=100'):
                return {'jobs': [{'name': 'real-jvm', 'run_id': 42, 'status': 'completed',
                                  'conclusion': 'failure' if failed_job else 'success'}]}
            if path.endswith('/artifacts?per_page=100'):
                return {'artifacts': [] if missing else [artifact]}
            return payload
        with patch.object(reuse, 'get', side_effect=fake):
            return reuse.valid_receipt(self.run, 'real-jvm', 'b' * 64, self.toolchain)

    def test_exact_evidence(self): self.assertTrue(self.check())
    def test_missing_evidence(self): self.assertFalse(self.check(missing=True))
    def test_corrupt_archive(self): self.assertFalse(self.check(corrupt=True))
    def test_failed_job(self): self.assertFalse(self.check(failed_job=True))
    def test_wrong_fingerprint(self):
        receipt = dict(self.receipt, fingerprint='c' * 64)
        self.assertFalse(self.check(receipt=receipt))
    def test_changed_toolchain(self):
        receipt = dict(self.receipt, toolchain=dict(self.toolchain, imageVersion='other'))
        self.assertFalse(self.check(receipt=receipt))
    def test_oversized_decompressed_receipt(self):
        self.assertFalse(self.check(receipt='x' * (64 * 1024)))
    def test_receipt_array(self):
        self.assertFalse(self.check(receipt=[]))
    def test_malformed_job_listing(self):
        with patch.object(reuse, 'get', return_value=[]):
            self.assertIsNone(reuse.valid_receipt(self.run, 'real-jvm', 'b' * 64, self.toolchain))
    def test_malformed_run_listing_is_miss(self):
        with patch.object(reuse, 'fingerprint', return_value='b' * 64), \
             patch.object(reuse, 'toolchain', return_value=self.toolchain), \
             patch.object(reuse, 'get', return_value=[]):
            self.assertIsNone(reuse.reusable('real-jvm', 'a' * 40))
    def test_old_run_not_trusted(self):
        self.run['created_at'] = '2020-01-01T00:00:00Z'
        self.assertFalse(reuse.trusted_run(self.run))
    def test_pr_run_not_trusted(self):
        self.run['event'] = 'pull_request'
        self.assertFalse(reuse.trusted_run(self.run))
    def test_fork_run_not_trusted(self):
        self.run['head_repository']['full_name'] = 'attacker/fork'
        self.assertFalse(reuse.trusted_run(self.run))


if __name__ == '__main__': unittest.main()
