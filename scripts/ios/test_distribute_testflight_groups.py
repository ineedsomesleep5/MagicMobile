"""Offline distribution regressions; every asc invocation hits the temporary mock."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("distribute-testflight-groups.sh")
EXTERNAL = "72b71a7a-bf62-43b5-8eda-b12a62e5c3eb"
MOCK = r'''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
a = sys.argv[1:]
root = Path(os.environ['MOCK_ROOT'])
config = json.loads((root / 'config.json').read_text())
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps(a) + '\n')
if a[:2] == ['builds', 'wait']:
    assert '--fail-on-invalid' in a
    assert a[a.index('--version') + 1] == '0.1.0'
    command = 'wait'
elif a[:2] == ['builds', 'list']:
    assert '--paginate' in a
    assert a[a.index('--version') + 1] == '0.1.0'
    assert a[a.index('--build-number') + 1] == '5000000000'
    command = 'build'
elif a[:3] == ['testflight', 'groups', 'list']:
    assert '--internal' not in a and '--paginate' in a
    command = 'internal'
elif a[:3] == ['builds', 'beta-app-review-submission', 'view']:
    marker = root / 'review-read'
    command = 'review_after' if marker.exists() else 'review_before'
    marker.touch()
elif a[:2] == ['builds', 'add-groups']:
    assert a[a.index('--build-id') + 1] == 'build-5000000000'
    assert a[a.index('--group') + 1] == os.environ.get('TESTFLIGHT_EXTERNAL_GROUP_ID', '72b71a7a-bf62-43b5-8eda-b12a62e5c3eb')
    assert '--skip-internal' not in a
    command = 'add'
elif a[:3] == ['builds', 'groups', 'list']:
    command = 'groups'
else:
    sys.exit('Unexpected ASC call: ' + repr(a))
response = config[command]
if isinstance(response, dict) and '_exit' in response:
    print(response.get('stderr', 'mock failure'), file=sys.stderr)
    sys.exit(response['_exit'])
print(response if isinstance(response, str) else json.dumps(response))
'''


def review(state):
    return {'data': {'type': 'betaAppReviewSubmissions', 'id': 'submission-1',
                     'attributes': {'betaReviewState': state}}}


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.evidence = self.root / 'release evidence'
        self.evidence.mkdir()
        mock = self.root / 'asc'
        mock.write_text(MOCK)
        mock.chmod(0o700)
        self.env = {**os.environ, 'PATH': str(self.root) + ':/usr/bin:/bin',
                    'MOCK_ROOT': str(self.root)}
        self.env.pop('TESTFLIGHT_EXTERNAL_GROUP_ID', None)
        self.config = {
            'wait': {'processingState': 'VALID'},
            'build': {'data': [{'type': 'builds', 'id': 'build-5000000000',
                               'attributes': {'version': '5000000000', 'processingState': 'VALID'},
                               'relationships': {'preReleaseVersion': {'data': {'id': 'version-1'}}}}],
                      'included': [{'type': 'preReleaseVersions', 'id': 'version-1', 'attributes': {'version': '0.1.0'}}]},
            'internal': {'data': [{'id': 'internal-1', 'attributes': {'isInternalGroup': True}}]},
            'review_before': {'_exit': 4, 'stderr': 'Error: builds beta-app-review-submission view: no beta app review submission found for build "build-5000000000"'},
            'add': {},
            'groups': {'buildId': 'build-5000000000', 'complete': True, 'failures': [], 'groupCount': 2,
                       'groups': [{'id': 'internal-1', 'type': 'internal', 'membership': 'all-builds'},
                                  {'id': EXTERNAL, 'type': 'external', 'membership': 'explicit'}]},
            'review_after': review('WAITING_FOR_REVIEW'),
        }

    def run_script(self, args=None):
        (self.root / 'config.json').write_text(json.dumps(self.config))
        return subprocess.run(['/bin/bash', str(SCRIPT)] + (args if args is not None else
                              ['--version', '0.1.0', '--build-number', '5000000000', '--release-root', str(self.evidence)]),
                              env=self.env, text=True, capture_output=True, timeout=10)

    def calls(self):
        log = self.root / 'calls.jsonl'
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def assert_failure(self, before_add=False):
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn('is assigned to Internal and External', result.stdout)
        if before_add:
            self.assertFalse(any(c[:2] == ['builds', 'add-groups'] for c in self.calls()))

    def test_fresh_submission_and_evidence(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('WAITING_FOR_REVIEW', result.stdout)
        addition = next(c for c in self.calls() if c[:2] == ['builds', 'add-groups'])
        self.assertIn('--submit', addition)
        self.assertIn('--confirm', addition)
        self.assertTrue((self.evidence / 'testflight-groups.json').is_file())
        self.assertTrue((self.evidence / 'beta-app-review.json').is_file())

    def test_resume_states_do_not_resubmit(self):
        for state in ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'APPROVED'):
            with self.subTest(state=state):
                self.config['review_before'] = self.config['review_after'] = review(state)
                result = self.run_script()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(state, result.stdout)
        for call in self.calls():
            self.assertNotIn('--submit', call)
            self.assertNotIn('--confirm', call)

    def test_successful_live_cli_shape_omits_empty_failures(self):
        self.config['groups'].pop('failures')
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_wait_invalid_failed_or_timeout_stops(self):
        for code in (1, 3, 4):
            with self.subTest(code=code):
                self.config['wait'] = {'_exit': code}
                self.assert_failure(before_add=True)

    def test_invalid_build_evidence(self):
        good = self.config['build']['data'][0]
        for payload in ({'data': []}, {'data': [good, good]}, 'not json',
                        {'data': [{**good, 'attributes': {'version': '5000000000', 'processingState': 'INVALID'}}]},
                        {'data': [{**good, 'attributes': {'version': '4999999999', 'processingState': 'VALID'}}]}):
            with self.subTest(payload=payload):
                self.config['build'] = payload
                self.assert_failure(before_add=True)

    def test_internal_discovery_errors_stop(self):
        for payload in ({'data': []}, {'data': None}, 'bad json', {'_exit': 1},
                        {'data': [{'id': 'x', 'attributes': {'isInternalGroup': False}}]}):
            with self.subTest(payload=payload):
                self.config['internal'] = payload
                self.assert_failure(before_add=True)

    def test_wrong_or_missing_marketing_version_stops(self):
        self.config['build']['included'][0]['attributes']['version'] = '0.3.0'
        self.assert_failure(before_add=True)
        self.config['build'].pop('included')
        self.assert_failure(before_add=True)

    def test_review_preflight_errors_do_not_submit(self):
        for payload in ({'_exit': 1, 'stderr': 'unauthorized'},
                        {'_exit': 4, 'stderr': 'failed to fetch: Not Found: build not found'},
                        review('REJECTED'), review('UNKNOWN'), {'data': None}, 'bad json'):
            with self.subTest(payload=payload):
                (self.root / 'review-read').unlink(missing_ok=True)
                self.config['review_before'] = payload
                self.assert_failure(before_add=True)

    def test_membership_failures_never_report_success(self):
        good = self.config['groups']
        variants = [{'complete': False}, {'failures': [{'groupId': 'x'}]},
                    {'buildId': 'other-build'}, {'groupCount': 9},
                    {'groups': good['groups'][:1], 'groupCount': 1},
                    {'groups': good['groups'][1:], 'groupCount': 1},
                    {'groups': [{**g, 'membership': 'unknown'} for g in good['groups']]},
                    {'groups': [{**g, 'type': 'external'} for g in good['groups']]},
                    {'groups': [{**g, 'id': 'wrong-id'} for g in good['groups']]}]
        for changes in variants:
            with self.subTest(changes=changes):
                self.config['groups'] = {**good, **changes}
                self.assert_failure()
        for payload in ('bad json', {'_exit': 1}):
            self.config['groups'] = payload
            self.assert_failure()

    def test_all_internal_groups_required(self):
        self.config['internal']['data'].append({'id': 'internal-2', 'attributes': {'isInternalGroup': True}})
        self.assert_failure()

    def test_app_scoped_discovery_filters_external_groups(self):
        self.config['internal']['data'].append({'id': EXTERNAL, 'attributes': {'isInternalGroup': False}})
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        discovered = json.loads((self.evidence / 'testflight-internal-groups.json').read_text())
        self.assertEqual([g['id'] for g in discovered['data']], ['internal-1'])

    def test_incomplete_or_untyped_app_groups_stop(self):
        for payload in (
            {'data': self.config['internal']['data'], 'links': {'next': 'another-page'}},
            {'data': [{'id': 'x', 'attributes': {'isInternalGroup': 'true'}}]},
        ):
            with self.subTest(payload=payload):
                self.config['internal'] = payload
                self.assert_failure(before_add=True)

    def test_final_review_failures_never_report_success(self):
        self.config['review_before'] = review('IN_REVIEW')
        for payload in (review('REJECTED'), review('UNKNOWN'), {'data': None}, 'bad json', {'_exit': 1}):
            with self.subTest(payload=payload):
                (self.root / 'review-read').unlink(missing_ok=True)
                self.config['review_after'] = payload
                self.assert_failure()

    def test_add_failure_stops(self):
        self.config['add'] = {'_exit': 1}
        self.assert_failure()
        self.assertFalse(any(c[:3] == ['builds', 'groups', 'list'] for c in self.calls()))

    def test_external_override_preserved(self):
        override = '11111111-2222-3333-4444-555555555555'
        self.env['TESTFLIGHT_EXTERNAL_GROUP_ID'] = override
        self.config['groups']['groups'][1]['id'] = override
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_bad_arguments_never_call_asc(self):
        for args in ([], ['--build-number'], ['--release-root'], ['--unknown'],
                     ['--build-number', '--release-root', str(self.evidence)],
                     ['--build-number', '', '--release-root', str(self.evidence)],
                     ['--build-number', '1', '--build-number', '2'],
                     ['--release-root', 'a', '--release-root', 'b'],
                     ['--build-number', 'oops', '--release-root', str(self.evidence)],
                     ['--build-number', '5000000000', '--release-root', '/does-not-exist']):
            with self.subTest(args=args):
                result = self.run_script(args)
                self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(self.calls(), [])

    def test_invalid_group_override_never_calls_asc(self):
        self.env['TESTFLIGHT_EXTERNAL_GROUP_ID'] = EXTERNAL + ',extra'
        self.assertEqual(self.run_script().returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_help_never_calls_asc(self):
        self.assertEqual(self.run_script(['--help']).returncode, 0)
        self.assertEqual(self.calls(), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
