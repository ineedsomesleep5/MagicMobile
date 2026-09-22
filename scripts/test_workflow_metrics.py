import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('metrics', Path(__file__).with_name('workflow-metrics.py'))
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class MetricsTests(unittest.TestCase):
    def fixture(self):
        return {'createdAt': '2026-09-21T10:00:00Z', 'updatedAt': '2026-09-21T10:10:00Z',
                'jobs': [
                    {'name': 'A', 'status': 'completed', 'conclusion': 'success',
                     'startedAt': '2026-09-21T10:01:00Z', 'completedAt': '2026-09-21T10:07:00Z'},
                    {'name': 'B', 'status': 'completed', 'conclusion': 'failure',
                     'startedAt': '2026-09-21T10:03:00Z', 'completedAt': '2026-09-21T10:09:00Z'}]}

    def test_parallel_jobs_not_added_to_elapsed(self):
        result = metrics.summarize(self.fixture())
        self.assertEqual(result['elapsedSeconds'], 600)
        self.assertEqual(result['summedJobSeconds'], 720)
        self.assertEqual(result['occupiedWallSeconds'], 480)
        self.assertEqual(result['nonSuccessJobs'], 1)

    def test_pending_is_not_completed_evidence(self):
        run = self.fixture()
        run['jobs'][0]['status'] = 'in_progress'
        with self.assertRaises(ValueError): metrics.summarize(run)

    def test_invalid_clock_is_rejected(self):
        run = self.fixture()
        run['jobs'][0]['completedAt'] = '2026-09-21T09:00:00Z'
        with self.assertRaises(ValueError): metrics.summarize(run)


if __name__ == '__main__':
    unittest.main()
