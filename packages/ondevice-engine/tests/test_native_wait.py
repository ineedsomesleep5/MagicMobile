"""Pinned-run wait fault injection only. No network, engine, Apple calls or real sleeps."""
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import wait_issue4_native as wait

SHA = 'a' * 40


class Clock:
    def __init__(self):
        self.now = 100.0
        self.sleeps = []
    def monotonic(self): return self.now
    def time(self): return 1000.0 + self.now
    def sleep(self, duration):
        self.sleeps.append(duration)
        self.now += duration


def response(value): return io.BytesIO(json.dumps(value).encode())


def http(code, headers=None):
    return urllib.error.HTTPError(wait.API + '/actions/runs/10', code, 'fixture', headers or {}, io.BytesIO(b'private-fixture'))


class RetryTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.dict(os.environ, {'GH_TOKEN': 'PRIVATE-fixture-token'}))
        self.stack.enter_context(patch.object(wait.time, 'monotonic', self.clock.monotonic))
        self.stack.enter_context(patch.object(wait.time, 'time', self.clock.time))
        self.stack.enter_context(patch.object(wait.time, 'sleep', self.clock.sleep))
        self.log = self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))

    def request(self, effects, deadline=600):
        with patch.object(wait.API_OPENER, 'open', side_effect=effects) as opened:
            result = wait.get_json('/actions/runs/10', deadline=deadline)
        self.assertNotIn('PRIVATE', self.log.getvalue())
        return result, opened

    def test_server_error_recovers_and_closes_error_response(self):
        failure = http(503)
        result, opened = self.request([failure, response({'ok': 1})])
        self.assertEqual(result, {'ok': 1})
        self.assertEqual(opened.call_count, 2)
        self.assertEqual(self.clock.sleeps, [2])
        self.assertTrue(failure.fp.closed)

    def test_timeout_and_connection_error_recover(self):
        result, opened = self.request([TimeoutError('PRIVATE timeout'), urllib.error.URLError('PRIVATE connection'), response({})])
        self.assertEqual(result, {})
        self.assertEqual(opened.call_count, 3)
        self.assertEqual(self.clock.sleeps, [2, 4])

    def test_secondary_rate_limit_waits_at_least_one_minute(self):
        self.request([http(429), response({})])
        self.assertEqual(self.clock.sleeps, [60])

    def test_retry_after_is_respected(self):
        self.request([http(503, {'Retry-After': '17'}), response({})])
        self.assertEqual(self.clock.sleeps, [17])

    def test_primary_rate_limit_reset_is_respected(self):
        self.request([http(403, {'X-RateLimit-Remaining': '0', 'X-RateLimit-Reset': '1130'}), response({})])
        self.assertGreaterEqual(self.clock.sleeps[0], 30)

    def test_permission_missing_resource_and_validation_errors_are_not_retried(self):
        for code in (400, 401, 403, 404, 422):
            with self.subTest(code=code), patch.object(wait.API_OPENER, 'open', side_effect=http(code)) as opened:
                with self.assertRaises(urllib.error.HTTPError):
                    wait.get_json('/actions/runs/10', deadline=600)
                self.assertEqual(opened.call_count, 1)
        self.assertEqual(self.clock.sleeps, [])

    def test_rate_limit_hint_beyond_deadline_never_causes_an_early_retry(self):
        with patch.object(wait.API_OPENER, 'open', side_effect=http(429, {'Retry-After': '1000'})) as opened:
            with self.assertRaises(TimeoutError): wait.get_json('/actions/runs/10', deadline=120)
            self.assertEqual(opened.call_count, 1)
        self.assertEqual(self.clock.sleeps, [])

    def test_deadline_already_expired_never_calls_network(self):
        with patch.object(wait.API_OPENER, 'open') as opened:
            with self.assertRaises(TimeoutError): wait.get_json('/actions/runs/10', deadline=100)
            opened.assert_not_called()

    def test_request_timeout_is_clamped_to_remaining_window(self):
        _, opened = self.request([response({})], deadline=103)
        self.assertEqual(opened.call_args.kwargs['timeout'], 3)

    def test_persistent_server_errors_have_a_finite_retry_budget(self):
        with patch.object(wait.API_OPENER, 'open', side_effect=lambda *a, **kw: http_raise()) as opened:
            with self.assertRaises(urllib.error.HTTPError): wait.get_json('/actions/runs/10', deadline=10000)
            self.assertEqual(opened.call_count, 5)
        self.assertEqual(self.clock.sleeps, [2, 4, 8, 16])

    def test_invalid_json_is_not_retried(self):
        with patch.object(wait.API_OPENER, 'open', return_value=io.BytesIO(b'{broken')) as opened:
            with self.assertRaises(json.JSONDecodeError): wait.get_json('/actions/runs/10', deadline=600)
            self.assertEqual(opened.call_count, 1)

    def test_late_success_does_not_extend_the_deadline(self):
        def late(*args, **kwargs):
            self.clock.now = 120
            return response({})
        with patch.object(wait.API_OPENER, 'open', side_effect=late):
            with self.assertRaises(TimeoutError): wait.get_json('/actions/runs/10', deadline=110)

    def test_redirects_never_forward_token_or_retry(self):
        request = wait.urllib.request.Request(wait.API + '/actions/runs/10',
                                             headers={'Authorization': 'Bearer PRIVATE-fixture-token'})
        handler = next(item for item in wait.API_OPENER.handlers if isinstance(item, wait.NoRedirect))
        for target in ('https://attacker.invalid/path', wait.API + '/renamed', 'http://api.github.com/path'):
            with self.subTest(target=target):
                self.assertIsNone(handler.redirect_request(request, None, 302, 'Found', {}, target))
        for code in (301, 302, 303, 307, 308):
            failure = http(code, {'Location': 'https://attacker.invalid/path'})
            with patch.object(wait.API_OPENER, 'open', side_effect=failure) as opened:
                with self.assertRaises(urllib.error.HTTPError):
                    wait.get_json('/actions/runs/10', deadline=600)
                self.assertEqual(opened.call_count, 1)
                self.assertTrue(failure.fp.closed)
        self.assertEqual(self.clock.sleeps, [])
        self.assertNotIn('PRIVATE', self.log.getvalue())


def http_raise(): raise http(502)


class PinnedGateTests(unittest.TestCase):
    def run_value(self, conclusion='success'):
        return {'id': 10, 'head_sha': SHA, 'repository': {'full_name': wait.REPOSITORY},
                'head_repository': {'full_name': wait.REPOSITORY},
                'path': '.github/workflows/magicmobile-far-calls.yml', 'status': 'completed', 'conclusion': conclusion,
                'event': 'workflow_dispatch', 'run_attempt': 2}
    def jobs(self):
        return {'total_count': 2, 'jobs': [
            {'id': index, 'name': name, 'run_id': 10, 'head_sha': SHA, 'run_attempt': 2,
             'status': 'completed', 'conclusion': 'success',
             'steps': [{'name': step, 'status': 'completed', 'conclusion': 'success'} for step in steps]}
            for index, (name, steps) in enumerate(wait.REQUIRED_STEPS.items(), 1)]}
    def artifacts(self):
        return {'artifacts': [{'id': 42, 'name': 'issue4-full-native-candidate-' + SHA,
                              'expired': False, 'digest': 'sha256:' + 'b' * 64}]}
    def invoke(self, run, artifacts, jobs=None, final=None, pages=None):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        output = Path(temporary.name) / 'receipt.json'
        effects = [run, *(pages if pages is not None else [jobs if jobs is not None else self.jobs()]),
                   artifacts, final if final is not None else copy.deepcopy(run)]
        argv = ['wait', '--run-id', '10', '--commit', SHA, '--timeout', '120', '--output', str(output)]
        with patch.object(sys, 'argv', argv), patch.object(wait, 'get_json', side_effect=effects) as request, \
             patch.dict(os.environ, {'GITHUB_OUTPUT': ''}), contextlib.redirect_stdout(io.StringIO()):
            try:
                wait.main()
            except (ValueError, SystemExit) as error:
                return output, request, error
        return output, request, None

    def test_success_keeps_exact_receipt_and_never_claims_runtime_acceptance(self):
        output, request, error = self.invoke(self.run_value(), self.artifacts())
        self.assertIsNone(error)
        receipt = json.loads(output.read_text())
        self.assertEqual(receipt['commit'], SHA)
        self.assertEqual(receipt['artifactID'], 42)
        self.assertFalse(receipt['nativeRuntimeTested'])
        self.assertEqual(receipt['runAttempt'], 2)
        self.assertEqual(request.call_count, 4)
        self.assertEqual(request.call_args_list[1].args[0], '/actions/runs/10/attempts/2/jobs?per_page=100&page=1')
        self.assertEqual(len({call.kwargs['deadline'] for call in request.call_args_list}), 1)

    def test_historical_ungated_producers_are_not_accepted(self):
        for field, value in (('event', 'push'), ('run_attempt', None), ('run_attempt', 0), ('run_attempt', True)):
            run = self.run_value(); run[field] = value
            output, request, error = self.invoke(run, self.artifacts())
            self.assertIsInstance(error, ValueError)
            self.assertFalse(output.exists()); self.assertEqual(request.call_count, 1)
        jobs = self.jobs(); jobs['jobs'].pop(0); jobs['total_count'] = 1
        output, _, error = self.invoke(self.run_value(), self.artifacts(), jobs=jobs)
        self.assertIsInstance(error, ValueError)
        self.assertFalse(output.exists())

    def test_missing_skipped_failed_or_wrong_identity_jobs_are_rejected(self):
        for index in range(2):
            for field, value in (('name', 'other'), ('status', 'queued'), ('conclusion', 'skipped'),
                                 ('conclusion', 'failure'), ('head_sha', 'c' * 40), ('run_id', 11), ('run_attempt', 1)):
                with self.subTest(job=index, field=field, value=value):
                    jobs = self.jobs(); jobs['jobs'][index][field] = value
                    output, request, error = self.invoke(self.run_value(), self.artifacts(), jobs=jobs)
                    self.assertIsInstance(error, ValueError)
                    self.assertFalse(output.exists()); self.assertEqual(request.call_count, 2)

    def test_each_critical_step_must_exist_and_succeed(self):
        for index, job in enumerate(self.jobs()['jobs']):
            for step_index, step in enumerate(job['steps']):
                for failure in ('missing', 'skipped', 'failure', 'cancelled', 'neutral'):
                    with self.subTest(job=job['name'], step=step['name'], failure=failure):
                        jobs = self.jobs(); steps = jobs['jobs'][index]['steps']
                        if failure == 'missing':
                            steps.pop(step_index)
                        else:
                            steps[step_index]['conclusion'] = failure
                        output, request, error = self.invoke(self.run_value(), self.artifacts(), jobs=jobs)
                        self.assertIsInstance(error, ValueError)
                        self.assertFalse(output.exists()); self.assertEqual(request.call_count, 2)

    def test_duplicate_jobs_and_steps_are_rejected(self):
        for duplicate in ('job', 'step'):
            jobs = self.jobs()
            if duplicate == 'job':
                jobs['jobs'].append(copy.deepcopy(jobs['jobs'][0])); jobs['total_count'] += 1
            else:
                jobs['jobs'][0]['steps'].append(copy.deepcopy(jobs['jobs'][0]['steps'][0]))
            output, _, error = self.invoke(self.run_value(), self.artifacts(), jobs=jobs)
            self.assertIsInstance(error, ValueError)
            self.assertFalse(output.exists())

    def test_attempt_job_pagination_and_incomplete_evidence(self):
        rows = self.jobs()['jobs']
        pages = [{'total_count': 2, 'jobs': [rows[0]]}, {'total_count': 2, 'jobs': [rows[1]]}]
        output, request, error = self.invoke(self.run_value(), self.artifacts(), pages=pages)
        self.assertIsNone(error); self.assertTrue(output.exists())
        self.assertEqual(request.call_args_list[2].args[0], '/actions/runs/10/attempts/2/jobs?per_page=100&page=2')
        pages[1]['jobs'] = []
        output, _, error = self.invoke(self.run_value(), self.artifacts(), pages=pages)
        self.assertIsInstance(error, ValueError); self.assertFalse(output.exists())

    def test_rerun_or_source_change_during_inspection_cannot_publish(self):
        for field, value in (('run_attempt', 3), ('status', 'in_progress'), ('conclusion', 'failure'), ('head_sha', 'c' * 40)):
            final = self.run_value(); final[field] = value
            output, _, error = self.invoke(self.run_value(), self.artifacts(), final=final)
            self.assertIsInstance(error, ValueError); self.assertFalse(output.exists())

    def test_failed_or_cancelled_build_never_selects_an_artifact(self):
        for conclusion in ('failure', 'cancelled', 'timed_out', None):
            with self.subTest(conclusion=conclusion):
                output, request, error = self.invoke(self.run_value(conclusion), self.artifacts())
                self.assertIsInstance(error, SystemExit)
                self.assertFalse(output.exists()); self.assertEqual(request.call_count, 1)

    def test_wrong_source_is_not_retried_or_published(self):
        run = self.run_value(); run['head_sha'] = 'c' * 40
        output, request, error = self.invoke(run, self.artifacts())
        self.assertIsInstance(error, ValueError)
        self.assertFalse(output.exists()); self.assertEqual(request.call_count, 1)

    def test_missing_expired_duplicate_or_digestless_artifacts_remain_blocked(self):
        original = self.artifacts()['artifacts'][0]
        for rows in ([], [{**original, 'expired': True}], [original, original], [{**original, 'digest': ''}]):
            with self.subTest(rows=rows):
                output, _, error = self.invoke(self.run_value(), {'artifacts': rows})
                self.assertIsInstance(error, SystemExit)
                self.assertFalse(output.exists())


if __name__ == '__main__': unittest.main()
