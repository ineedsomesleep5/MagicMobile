"""Read-only presentation of validated controller status, no store mutations."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('summary_controller', Path(__file__).with_name('controller.py'))
controller = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controller)


class SummaryTests(unittest.TestCase):
    def fixture(self, state):
        return {'runId': 'fixture', 'state': state, 'events': [
            {'kind': 'planned', 'identity': {'sourceCommit': 'a' * 40, 'fingerprint': 'b' * 64, 'platform': 'ios'}},
            {'kind': 'uploaded', 'version': '0.1.1', 'build': '9', 'deliveryUuid': 'fixture', 'ipaSHA256': 'c' * 64},
            {'kind': 'completed', 'timeUTC': '2026-09-22T01:00:00Z'},
        ]}

    def test_new_never_suggests_unreviewed_upload(self):
        summary = controller.status_summary({'runId': 'new', 'state': 'new', 'events': []})
        self.assertEqual(summary['eventCount'], 0)
        self.assertIn('prerequisite gates', summary['next'])

    def test_stale_keeps_historical_completion_distinct(self):
        summary = controller.status_summary(self.fixture('stale'))
        self.assertEqual(summary['state'], 'stale')
        self.assertEqual(summary['recordedStage'], 'completed')
        self.assertEqual(summary['uploadedBuild']['build'], '9')
        self.assertIn('Historical', summary['next'])
        self.assertIn('not a fresh Apple', summary['scope'])

    def test_uploaded_and_uncertain_never_suggest_upload_retry(self):
        self.assertIn('do not upload again', controller.status_summary(self.fixture('uploaded'))['next'])
        self.assertIn('never retry blindly', controller.status_summary(self.fixture('uncertain'))['next'])

    def test_summary_does_not_modify_full_evidence(self):
        status = self.fixture('completed')
        before = repr(status)
        summary = controller.status_summary(status)
        self.assertEqual(repr(status), before)
        self.assertNotIn('events', summary)
        self.assertEqual(summary['sourceCommit'], 'a' * 40)


if __name__ == '__main__':
    unittest.main()
