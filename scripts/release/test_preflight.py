"""Preflight safety tests use temporary repos and injected commands; no builds/network."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('preflight', Path(__file__).with_name('preflight.py'))
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name).resolve()
        def git(*args):
            subprocess.run(['git', '-C', str(self.repo), *args], check=True, capture_output=True)
        self.git = git
        git('init', '-q')
        git('config', 'user.email', 'fixture@example.invalid')
        git('config', 'user.name', 'Fixture')
        (self.repo / '.gitignore').write_text('build_output/\n')
        (self.repo / 'source').write_text('initial')
        git('add', '.')
        git('commit', '-qm', 'fixture')

    def test_plan_is_read_only_and_commands_are_bounded(self):
        before = preflight.source_snapshot(self.repo)
        report = preflight.plan(self.repo, 'ios-fast')
        self.assertEqual(before, preflight.source_snapshot(self.repo))
        self.assertFalse((self.repo / 'build_output').exists())
        self.assertEqual(report['nativeDecision']['state'], 'unknown')
        names = [c['name'] for c in report['checks']]
        self.assertIn('standalone-deck-contracts', names)
        self.assertIn('generated-project', names)
        for check in report['checks']:
            command = check['command']
            self.assertNotIn('asc', command)
            self.assertNotIn('gh', command)
            self.assertNotIn('xcodebuild', command)
            if command[0] == 'swift':
                self.assertEqual(command[-2:], ['--jobs', '2'])

    def test_snapshot_covers_dirty_untracked_deleted_and_ignores_logs(self):
        before = preflight.source_snapshot(self.repo)
        (self.repo / 'untracked').write_text('new')
        self.assertNotEqual(before, preflight.source_snapshot(self.repo))
        (self.repo / 'untracked').unlink()
        (self.repo / 'source').write_text('changed')
        self.assertNotEqual(before, preflight.source_snapshot(self.repo))
        (self.repo / 'source').unlink()
        self.assertNotEqual(before, preflight.source_snapshot(self.repo))
        (self.repo / 'source').write_text('initial')
        (self.repo / 'build_output').mkdir()
        (self.repo / 'build_output/log').write_text('evidence')
        self.assertEqual(before, preflight.source_snapshot(self.repo))

    def test_failure_stops_later_checks_and_preserves_original_log(self):
        calls = []
        def runner(command, log, repo):
            calls.append(command)
            log.write_text('original failure evidence')
            return 7
        with contextlib.redirect_stdout(io.StringIO()):
            report = preflight.run(self.repo, 'tooling', runner=runner)
        self.assertEqual(len(calls), 1)
        self.assertEqual(report['state'], 'failed')
        self.assertEqual(Path(report['results'][0]['log']).read_text(), 'original failure evidence')
        self.assertEqual(json.loads((Path(report['evidenceDirectory']) / 'report.json').read_text()), report)

    def test_pass_and_source_change_are_distinct_and_each_run_is_unique(self):
        def runner(command, log, repo):
            log.write_text('passed')
            return 0
        with contextlib.redirect_stdout(io.StringIO()):
            first = preflight.run(self.repo, 'tooling', runner=runner)
            def changing(command, log, repo):
                (repo / 'source').write_text('changed during check')
                return runner(command, log, repo)
            second = preflight.run(self.repo, 'tooling', runner=changing)
        self.assertEqual(first['state'], 'passed')
        self.assertEqual(second['state'], 'source-changed')
        self.assertNotEqual(first['evidenceDirectory'], second['evidenceDirectory'])

    def test_interruption_keeps_report_and_log(self):
        def interrupted(command, log, repo):
            log.write_text('partial output')
            raise KeyboardInterrupt()
        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(KeyboardInterrupt):
            preflight.run(self.repo, 'tooling', runner=interrupted)
        path = next((self.repo / 'build_output/preflight').glob('tooling-*/report.json'))
        report = json.loads(path.read_text())
        self.assertEqual(report['state'], 'interrupted')
        self.assertEqual(report['errorType'], 'KeyboardInterrupt')
        self.assertEqual(next(path.parent.glob('*.log')).read_text(), 'partial output')

    def test_output_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as outside:
            (self.repo / 'build_output').symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'symlinked'):
                preflight.run(self.repo, 'tooling')
            self.assertEqual(list(Path(outside).iterdir()), [])

    def test_second_preflight_is_rejected_before_running_commands(self):
        root = preflight.output_root(self.repo)
        with (root / '.lock').open('a+b') as lock:
            preflight.fcntl.flock(lock, preflight.fcntl.LOCK_EX | preflight.fcntl.LOCK_NB)
            runner = mock.Mock()
            with self.assertRaisesRegex(ValueError, 'already running'):
                preflight.run(self.repo, 'tooling', runner=runner)
            runner.assert_not_called()

    def test_execute_disables_live_opt_ins_and_pins_xcode(self):
        with mock.patch.dict(os.environ, {'MM_LIVE_TOKEN_ARTWORK_TEST': '1', 'MAGICMOBILE_BULK_FIXTURE': '/private/fixture',
                                         'MAGICMOBILE_PRECON_EXPORT_DIR': '/private/export'}), \
             mock.patch.object(preflight.subprocess, 'run', return_value=mock.Mock(returncode=0)) as run:
            preflight.execute(['fixture'], self.repo / 'log', self.repo)
        env = run.call_args.kwargs['env']
        self.assertNotIn('MM_LIVE_TOKEN_ARTWORK_TEST', env)
        self.assertNotIn('MAGICMOBILE_BULK_FIXTURE', env)
        self.assertNotIn('MAGICMOBILE_PRECON_EXPORT_DIR', env)
        self.assertEqual(env['DEVELOPER_DIR'], preflight.DEVELOPER_DIR)
        self.assertEqual(run.call_args.kwargs['timeout'], 900)

    def test_native_unknown_is_not_mismatch_or_approval(self):
        verifier = mock.Mock()
        with mock.patch.object(preflight, 'load', return_value=verifier):
            verifier.source_identity.side_effect = subprocess.CalledProcessError(1, ['git'])
            self.assertEqual(preflight.native_decision(self.repo, 'a' * 40)['state'], 'unknown')
            verifier.source_identity.side_effect = ValueError('App and native artifact have different engine inputs:\nengine.java')
            self.assertEqual(preflight.native_decision(self.repo, 'a' * 40)['state'], 'different-source')
            verifier.source_identity.side_effect = None
            verifier.source_identity.return_value = {'equivalentInputTreeSHA256': 'fixture-hash'}
            result = preflight.native_decision(self.repo, 'a' * 40)
            self.assertEqual(result['state'], 'equivalent-source')
            self.assertIn('artifact bytes', result['scope'])
            (self.repo / 'new-source').write_text('untracked')
            self.assertEqual(preflight.native_decision(self.repo, 'a' * 40)['state'], 'unknown')


if __name__ == '__main__':
    unittest.main()
