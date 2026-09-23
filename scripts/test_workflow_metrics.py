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

    def test_slowest_completed_steps_exclude_skips_and_untimed(self):
        run = self.fixture()
        run['jobs'][0]['steps'] = [
            {'name': 'Compile', 'status': 'completed', 'conclusion': 'success',
             'startedAt': '2026-09-21T10:01:00Z', 'completedAt': '2026-09-21T10:06:00Z'},
            {'name': 'Setup', 'status': 'completed', 'conclusion': 'success',
             'startedAt': '2026-09-21T10:01:00Z', 'completedAt': '2026-09-21T10:02:00Z'},
            {'name': 'Skipped', 'status': 'completed', 'conclusion': 'skipped',
             'startedAt': '0001-01-01T00:00:00Z', 'completedAt': '0001-01-01T00:00:00Z'},
            {'name': 'Unknown duration', 'status': 'completed', 'conclusion': 'success',
             'startedAt': None, 'completedAt': None}]
        run['jobs'][1]['steps'] = [
            {'name': 'Upload', 'status': 'completed', 'conclusion': 'failure',
             'startedAt': '2026-09-21T10:03:00Z', 'completedAt': '2026-09-21T10:09:00Z'},
            {'name': 'Pending', 'status': 'in_progress', 'conclusion': None,
             'startedAt': None, 'completedAt': None}]
        result = metrics.summarize(run)
        self.assertEqual([(s['name'], s['seconds']) for s in result['slowSteps']],
                         [('Upload', 360), ('Compile', 300), ('Setup', 60)])
        self.assertEqual(result['untimedSteps'], 1)

    def test_skipped_job_is_not_failure_or_runner_time(self):
        run = self.fixture()
        run['jobs'].append({'name': 'Conditional', 'status': 'completed',
                            'conclusion': 'skipped', 'startedAt': None,
                            'completedAt': '0001-01-01T00:00:00Z',
                            'steps': [{'name': 'Never ran', 'status': 'completed',
                                       'conclusion': 'skipped', 'startedAt': None,
                                       'completedAt': None}]})
        result = metrics.summarize(run)
        self.assertEqual(result['skippedJobs'], 1)
        self.assertEqual(result['nonSuccessJobs'], 1)
        self.assertEqual(result['summedJobSeconds'], 720)
        self.assertEqual(result['jobs'][-1]['seconds'], None)
        self.assertEqual(result['untimedJobs'], 0)

    def test_failed_and_cancelled_jobs_are_non_success(self):
        run = self.fixture()
        run['jobs'][1]['conclusion'] = 'cancelled'
        run['jobs'].append({'name': 'Failed', 'status': 'completed',
                            'conclusion': 'failure', 'startedAt': None,
                            'completedAt': None})
        result = metrics.summarize(run)
        self.assertEqual(result['nonSuccessJobs'], 2)
        self.assertEqual(result['untimedJobs'], 1)
        self.assertEqual(result['jobs'][-1]['seconds'], None)
        self.assertEqual(result['summedJobSeconds'], 720)

    def test_malformed_active_timestamps_are_rejected(self):
        run = self.fixture()
        run['jobs'][0]['steps'] = [{'name': 'Bad step', 'status': 'completed',
                                   'conclusion': 'success', 'startedAt': 'not-a-date',
                                   'completedAt': '2026-09-21T10:02:00Z'}]
        with self.assertRaises(ValueError): metrics.summarize(run)
        run['jobs'][0]['steps'] = []
        run['jobs'][0]['startedAt'] = 'not-a-date'
        with self.assertRaises(ValueError): metrics.summarize(run)
        run['jobs'][0]['startedAt'] = 123
        with self.assertRaises(ValueError): metrics.summarize(run)

    def test_untimed_completed_job_and_step_do_not_invent_duration(self):
        run = self.fixture()
        run['jobs'][0]['startedAt'] = '0001-01-01T00:00:00Z'
        run['jobs'][0]['steps'] = [{'name': 'No clock', 'status': 'completed',
                                   'conclusion': 'success', 'startedAt': '',
                                   'completedAt': '2026-09-21T10:03:00Z'}]
        result = metrics.summarize(run)
        self.assertEqual(result['untimedJobs'], 1)
        self.assertEqual(result['untimedSteps'], 1)
        self.assertEqual(result['summedJobSeconds'], 360)
        self.assertEqual(result['occupiedWallSeconds'], 360)

    def test_slow_steps_are_bounded_to_ten(self):
        run = self.fixture()
        run['jobs'][0]['steps'] = [
            {'name': str(i), 'status': 'completed', 'conclusion': 'success',
             'startedAt': '2026-09-21T10:01:00Z',
             'completedAt': '2026-09-21T10:02:00Z'} for i in range(11)]
        self.assertEqual(len(metrics.summarize(run)['slowSteps']), 10)


if __name__ == '__main__':
    unittest.main()
