import copy
import importlib.util
import json
from pathlib import Path
import random
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("soak", SCRIPTS / "test_seeded_soak.py")
soak = importlib.util.module_from_spec(spec)
spec.loader.exec_module(soak)


class SoakDriverTests(unittest.TestCase):
    def test_reviewed_matrix_unchanged(self):
        self.assertEqual(soak.SEEDS, (1907, 2909))
        self.assertEqual(soak.CONFIGURATIONS, ((2, 0), (4, 0), (2, 1), (3, 2), (4, 3)))

    def test_matrix_preserves_deck_identity_and_human_recipients(self):
        base = {"seats": [{"deck": {"main": [{"count": 99, "name": "Plains"}], "commanders": [{"count": 1, "name": "Isamaru"}]}}]}
        original = copy.deepcopy(base)
        for seats, ai in soak.CONFIGURATIONS:
            config = soak.configuration(base, seats, ai, 1907)
            self.assertEqual(len(config["seats"]), seats)
            self.assertEqual(sum(s["controller"] == "ai" for s in config["seats"]), ai)
            self.assertEqual(len({s["seatId"] for s in config["seats"]}), seats)
            for seat in config["seats"]:
                self.assertEqual(seat["deck"], base["seats"][0]["deck"])
        self.assertEqual(base, original)

    def test_target_never_invents_identity(self):
        prompt = {"kind": "PICK_TARGET", "payload": {"message": "starting player", "candidates": ["one", "two"]}}
        for own in ("one", "missing"):
            reply = soak.answer(prompt, {"enginePlayerId": own}, random.Random(1907))
            self.assertIn(reply["value"], prompt["payload"]["candidates"])
        prompt["payload"]["candidates"] = []
        with self.assertRaises(AssertionError):
            soak.answer(prompt, {"enginePlayerId": "missing"}, random.Random(1907))

    def test_unhandled_choice_fails_instead_of_guessing(self):
        for kind in ("ASK", "PLAY_MANA", "UNKNOWN"):
            with self.assertRaises(AssertionError):
                soak.answer({"kind": kind, "payload": {"message": "Sacrifice a creature?"}}, {}, random.Random(1))


class LifecycleProgressTests(unittest.TestCase):
    def exercise(self, final_state):
        class Engine:
            def __init__(self, **kwargs):
                self.responses = 0
                self.final_polls = 0
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass
            def call(self, op, **fields):
                if op == 'create':
                    self.responses = 0
                    return {'matchId': 'm', 'seats': ['seat-0']}
                if op == 'poll':
                    state = {'phase': 'running', 'snapshot': {}, 'prompt': {
                        'kind': 'SELECT', 'payload': {}, 'promptId': 'p' + str(self.responses),
                        'revision': self.responses * 10 + 1}}
                    if self.responses == 8:
                        self.final_polls += 1
                        if final_state == 'failed':
                            state['phase'] = 'failed'
                        elif final_state == 'missing':
                            state['prompt'] = None
                        elif final_state == 'submitted':
                            state['prompt']['submitted'] = True
                        elif final_state == 'old-revision':
                            state['prompt']['revision'] = 80
                        elif final_state == 'same-prompt':
                            state['prompt']['promptId'] = 'p7'
                        elif final_state == 'delayed' and self.final_polls < 3:
                            state['prompt'] = None
                    return state
                if op == 'respond':
                    self.responses += 1
                    command = fields['command']
                    return {'status': 'queued', 'requestId': command['requestId'],
                            'promptId': command['promptId'], 'revision': self.responses * 10}
                if op == 'shutdown':
                    return {}
                raise AssertionError(op)
            def request(self, op, **fields):
                if op == 'destroy':
                    return {'ok': True}
                return {'ok': False, 'error': {'code': 'unknown_match' if op == 'poll' else 'engine_closed'}}

        report = Mock()
        tick = iter(i * .5 for i in range(1000))
        with patch.object(soak, 'EngineProcess', Engine), patch.object(soak, 'cached_identity', return_value={
                'sourceIdentity': 'unverified-cached-class-source'}), patch.object(
                soak.time, 'monotonic', side_effect=lambda: next(tick)), patch.object(soak.time, 'sleep'):
            try:
                soak.scenario({'seats': [{'deck': {'main': []}}]}, 2, 1, 1907, report)
            finally:
                self.record = json.loads(report.write_text.call_args.args[0])

    def test_final_queued_delivery_failure_cannot_pass(self):
        with self.assertRaisesRegex(AssertionError, 'terminal phase'):
            self.exercise('failed')
        self.assertEqual(self.record['result'], 'failed')
        self.assertEqual(len(self.record['commands']), 8)

    def test_disappearance_submitted_or_stale_prompt_is_not_progress(self):
        for state in ('missing', 'submitted', 'old-revision', 'same-prompt'):
            with self.subTest(state=state), self.assertRaisesRegex(AssertionError, 'progression'):
                self.exercise(state)
            self.assertEqual(self.record['result'], 'failed')

    def test_newer_running_prompt_after_wait_passes(self):
        self.exercise('delayed')
        self.assertEqual(self.record['result'], 'passed')
        self.assertEqual(len(self.record['commands']), 8)


class OwnedProcessTests(unittest.TestCase):
    def test_parent_preserves_ten_scenarios_and_budgets(self):
        with patch.object(sys, 'argv', ['test_seeded_soak.py']), patch.object(Path, 'mkdir'), patch.object(
                Path, 'write_text') as write, patch.object(soak, 'run_owned', return_value=0) as run, patch.object(
                soak.time, 'monotonic', return_value=0), patch('builtins.print'):
            soak.main()
        self.assertEqual(run.call_count, 10)
        self.assertEqual([tuple(map(int, call.args[0][3:6])) for call in run.call_args_list],
                         [(seats, ai, seed) for seats, ai in soak.CONFIGURATIONS for seed in soak.SEEDS])
        self.assertTrue(all(call.args[1] == 150 for call in run.call_args_list))
        matrix = json.loads(write.call_args.args[0])
        self.assertEqual(matrix['totalTimeoutSeconds'], 1550)
        self.assertEqual(matrix['scenarioTimeoutSeconds'], 150)

    def exercise(self, outcome, missing_group=False):
        process = Mock(pid=424242)
        if outcome == 'sigterm':
            def wait(**kwargs):
                if process.wait.call_count == 1:
                    signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)
                return 0
            process.wait.side_effect = wait
        else:
            process.wait.side_effect = [outcome, 0]
        original = {sig: signal.getsignal(sig) for sig in (signal.SIGINT, signal.SIGTERM)}
        with patch.object(soak.subprocess, 'Popen', return_value=process) as spawn, patch.object(
                soak.os, 'killpg', side_effect=ProcessLookupError if missing_group else None) as kill:
            try:
                return soak.run_owned(['owned-driver'], 150)
            finally:
                spawn.assert_called_once_with(['owned-driver'], start_new_session=True)
                kill.assert_called_once_with(process.pid, signal.SIGKILL)
                self.assertEqual(process.wait.call_count, 2)
                self.assertLessEqual(process.wait.call_args_list[0].kwargs['timeout'], 145)
                self.assertLessEqual(process.wait.call_args_list[1].kwargs['timeout'], 5)
                for sig, handler in original.items():
                    self.assertEqual(signal.getsignal(sig), handler)

    def test_success_cleans_lingering_descendants(self):
        self.assertEqual(self.exercise(0), 0)

    def test_abnormal_child_exit_cleans_group(self):
        self.assertEqual(self.exercise(-9), -9)

    def test_timeout_cleans_group(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            self.exercise(subprocess.TimeoutExpired('owned-driver', 145))

    def test_keyboard_interrupt_cleans_group(self):
        with self.assertRaises(KeyboardInterrupt):
            self.exercise(KeyboardInterrupt())

    def test_sigterm_cleans_group(self):
        with self.assertRaises(KeyboardInterrupt):
            self.exercise('sigterm')

    def test_already_exited_group_is_safe(self):
        self.assertEqual(self.exercise(0, missing_group=True), 0)

    def test_exhausted_budget_never_spawns(self):
        with patch.object(soak.subprocess, 'Popen') as spawn:
            with self.assertRaises(subprocess.TimeoutExpired):
                soak.run_owned(['owned-driver'], 5)
            spawn.assert_not_called()


class CachedIdentityTests(unittest.TestCase):
    def test_cached_bytes_are_hashed_without_claiming_source_equivalence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = root / 'build'
            build.mkdir()
            classes = build / 'classes'
            classes.mkdir()
            file = classes / 'Example.class'
            file.write_bytes(b'old bytecode')
            jar = build / 'dependency.jar'
            jar.write_bytes(b'jar bytes')
            (build / 'runtime-classpath.txt').write_text(str(classes) + soak.os.pathsep + str(jar))
            def git_output(command, **kwargs):
                return str(root.resolve().parents[1]) if '--show-toplevel' in command else 'a' * 40
            with patch.object(soak.subprocess, 'check_output', side_effect=git_output):
                original = soak.cached_identity(root)
                file.write_bytes(b'new bytecode')
                changed = soak.cached_identity(root)
                jar.write_bytes(b'new jar bytes')
                changed_jar = soak.cached_identity(root)
            with patch.object(soak.subprocess, 'check_output', side_effect=subprocess.CalledProcessError(128, 'git')):
                self.assertIsNone(soak.cached_identity(root)['observedCheckoutHEAD'])
            with patch.object(soak.subprocess, 'check_output', return_value='/unrelated/enclosing/repository'):
                self.assertIsNone(soak.cached_identity(root)['observedCheckoutHEAD'])
            self.assertEqual(original['sourceIdentity'], 'unverified-cached-class-source')
            self.assertEqual(original['observedCheckoutHEAD'], 'a' * 40)
            self.assertNotEqual(original['classSnapshotSHA256'], changed['classSnapshotSHA256'])
            self.assertNotEqual(changed['classSnapshotSHA256'], changed_jar['classSnapshotSHA256'])
            self.assertNotIn(directory, json.dumps(original))
            self.assertNotIn('old bytecode', json.dumps(original))
            self.assertEqual(len(original['driverSHA256']), 64)


if __name__ == "__main__":
    unittest.main()
