"""Offline API-fixture tests. No GitHub credentials, network, or native build."""
import copy
import unittest
from unittest.mock import patch

import approve_native as gate

SHA = 'a' * 40
TRUSTED = 'b' * 40
RUN = '12345'
RUN_PATH = '/actions/runs/' + RUN
JOBS_PATH = RUN_PATH + '/attempts/2/jobs?per_page=100&page='


class ApprovalTests(unittest.TestCase):
    def setUp(self):
        self.args = dict(repository=gate.REPOSITORY, candidate_sha=SHA,
                         cheap_run_id=RUN, dispatch_ref='refs/heads/reviewed',
                         dispatch_sha=SHA, trusted_sha=TRUSTED)
        run = dict(id=int(RUN), head_sha=SHA, path=gate.WORKFLOW,
                   repository={'full_name': gate.REPOSITORY},
                   head_repository={'full_name': gate.REPOSITORY},
                   event='push', head_branch='reviewed', status='completed',
                   conclusion='success', run_attempt=2)
        jobs = [dict(id=i, name=name, run_id=int(RUN), head_sha=SHA,
                     status='completed', conclusion='success',
                     steps=[dict(name=step, status='completed', conclusion='success')
                            for step in steps])
                for i, (name, steps) in enumerate(gate.REQUIRED_STEPS.items(), 1)]
        self.responses = {
            '/commits/refs%2Fheads%2Freviewed': {'sha': SHA},
            '/commits/' + SHA: {'sha': SHA},
            RUN_PATH: run,
            JOBS_PATH + '1': {'total_count': len(jobs), 'jobs': jobs},
        }
        for sha in (SHA, TRUSTED):
            self.responses['/contents/' + gate.WORKFLOW + '?ref=' + sha] = {
                'type': 'file', 'path': gate.WORKFLOW, 'sha': 'c' * 40}
        self.calls = []
        # An accidental production API call fails instead of accessing network.
        self.network = patch('urllib.request.OpenerDirector.open',
                             side_effect=AssertionError('Network forbidden'))
        self.network.start()
        self.addCleanup(self.network.stop)

    def get(self, path):
        self.calls.append(path)
        return copy.deepcopy(self.responses[path])

    def approve(self):
        return gate.approve(**self.args, get_json=self.get)

    def test_success(self):
        result = self.approve()
        self.assertEqual(result['candidateSHA'], SHA)
        self.assertEqual(result['cheapRunAttempt'], 2)
        self.assertFalse(result['nativeRuntimeTested'])

    def test_manual_cheap_run_and_tag_dispatch(self):
        self.responses[RUN_PATH]['event'] = 'workflow_dispatch'
        self.args['dispatch_ref'] = 'refs/tags/reviewed'
        self.responses['/commits/refs%2Ftags%2Freviewed'] = {'sha': SHA}
        self.approve()

    def test_invalid_inputs_fail_before_api(self):
        cases = {
            'repository': ('fork/MagicMobile', ''),
            'candidate_sha': ('', 'main', 'a' * 39, 'A' * 40, '0' * 40, SHA + '\n'),
            'trusted_sha': ('', 'main', '0' * 40),
            'cheap_run_id': ('', '0', '-1', '1.0', ' 12345', '01', '12345\n'),
            'dispatch_sha': ('', 'd' * 40),
            'dispatch_ref': ('', ' ', 'main', SHA, 'refs/heads/', 'refs/heads/a..b',
                             'refs/heads/a\nb', 'refs/pull/1/merge', 'refs/heads/a?b'),
        }
        for key, values in cases.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    args = dict(self.args, **{key: value})
                    with self.assertRaises(ValueError):
                        gate.approve(**args, get_json=self.get)
                    self.assertEqual(self.calls, [])

    def test_fake_or_moved_commit(self):
        for path in ('/commits/refs%2Fheads%2Freviewed', '/commits/' + SHA):
            with self.subTest(path=path):
                original = self.responses[path]
                self.responses[path] = {'sha': 'd' * 40}
                with self.assertRaises(ValueError):
                    self.approve()
                self.responses[path] = original

    def test_untrusted_workflow_blob(self):
        path = '/contents/' + gate.WORKFLOW + '?ref=' + SHA
        for field, value in (('sha', 'd' * 40), ('sha', ''), ('type', 'symlink'),
                             ('path', 'other.yml')):
            with self.subTest(field=field, value=value):
                original = copy.deepcopy(self.responses[path])
                self.responses[path][field] = value
                with self.assertRaises(ValueError):
                    self.approve()
                self.responses[path] = original

    def test_invalid_run_identity_or_result(self):
        cases = {'id': 9, 'head_sha': 'd' * 40, 'path': 'other.yml',
                 'repository': {'full_name': 'fork/MagicMobile'},
                 'head_repository': {'full_name': 'fork/MagicMobile'},
                 'head_branch': '', 'event': 'pull_request_target',
                 'status': 'in_progress', 'conclusion': 'skipped', 'run_attempt': 0}
        for key, value in cases.items():
            with self.subTest(key=key):
                original = self.responses[RUN_PATH][key]
                self.responses[RUN_PATH][key] = value
                with self.assertRaises(ValueError):
                    self.approve()
                self.responses[RUN_PATH][key] = original
        for event in ('pull_request', 'workflow_run', 'schedule'):
            self.responses[RUN_PATH]['event'] = event
            with self.assertRaises(ValueError):
                self.approve()

    def test_every_job_and_step_is_required(self):
        response = self.responses[JOBS_PATH + '1']
        original = copy.deepcopy(response['jobs'])
        for index, job in enumerate(original):
            with self.subTest(missing_job=job['name']):
                response['jobs'] = original[:index] + original[index + 1:]
                response['total_count'] = len(response['jobs'])
                with self.assertRaises(ValueError):
                    self.approve()
            response['total_count'] = len(original)
            for step_index, step in enumerate(job['steps']):
                for failure in ('missing', 'skipped', 'failure', 'cancelled', 'neutral'):
                    with self.subTest(job=job['name'], step=step['name'], failure=failure):
                        response['jobs'] = copy.deepcopy(original)
                        steps = response['jobs'][index]['steps']
                        if failure == 'missing':
                            steps.pop(step_index)
                        else:
                            steps[step_index]['conclusion'] = failure
                        with self.assertRaises(ValueError):
                            self.approve()

    def test_wrong_job_identity_failed_job_and_duplicate_evidence(self):
        response = self.responses[JOBS_PATH + '1']
        original = copy.deepcopy(response['jobs'])
        for field, value in (('run_id', 1), ('head_sha', TRUSTED),
                             ('status', 'queued'), ('conclusion', 'failure')):
            response['jobs'] = copy.deepcopy(original)
            response['jobs'][0][field] = value
            with self.assertRaises(ValueError):
                self.approve()
        response['jobs'] = copy.deepcopy(original) + [copy.deepcopy(original[0])]
        response['total_count'] += 1
        with self.assertRaises(ValueError):
            self.approve()
        response['jobs'] = copy.deepcopy(original)
        response['total_count'] -= 1
        response['jobs'][0]['steps'] *= 2
        with self.assertRaises(ValueError):
            self.approve()

    def test_pagination_and_incomplete_pages(self):
        jobs = self.responses[JOBS_PATH + '1']['jobs']
        self.responses[JOBS_PATH + '1']['jobs'] = jobs[:2]
        self.responses[JOBS_PATH + '2'] = {'jobs': jobs[2:], 'total_count': len(jobs)}
        self.approve()
        self.assertIn(JOBS_PATH + '2', self.calls)
        self.responses[JOBS_PATH + '2']['jobs'] = []
        with self.assertRaises(ValueError):
            self.approve()

    def test_rerun_during_validation(self):
        def changing_get(path):
            result = self.get(path)
            if path == RUN_PATH and self.calls.count(RUN_PATH) == 2:
                result['run_attempt'] += 1
            return result
        with self.assertRaises(ValueError):
            gate.approve(**self.args, get_json=changing_get)

    def test_api_failure_is_sanitized(self):
        with patch.dict('os.environ', GH_TOKEN='SECRET_SENTINEL'), patch(
                'urllib.request.OpenerDirector.open', side_effect=OSError('SECRET_SENTINEL')):
            with self.assertRaisesRegex(ValueError, '^GitHub read failed; approval remains blocked$'):
                gate.api_get('/actions/runs/12345')

    def test_redirect_is_refused(self):
        self.assertIsNone(gate.NoRedirect().redirect_request(
            None, None, 302, 'Found', {}, 'https://attacker.invalid/'))


if __name__ == '__main__':
    unittest.main()
