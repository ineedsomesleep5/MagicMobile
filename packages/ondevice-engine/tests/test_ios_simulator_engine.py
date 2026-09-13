"""Small orchestration checks only; these do not compile or run XMage."""
import os
import copy
import json
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class NativeTargetTests(unittest.TestCase):
    def test_invalid_target_fails_before_building(self):
        # Exercise a copied script with no compiler or classpath. Even RED must
        # never reach a real local build on the 8 GB developer machine.
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / 'scripts/build_native_ios.sh'
            script.parent.mkdir()
            script.write_text((ROOT / 'scripts/build_native_ios.sh').read_text())
            result = subprocess.run(
                ['bash', str(script)],
                env={**os.environ, 'MM_NATIVE_TARGET': 'macos',
                     'MM_GRAALVM_HOME': str(Path(directory) / 'missing-compiler')},
                capture_output=True, text=True, timeout=10,
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn('MM_NATIVE_TARGET must be ios or ios-sim', result.stdout + result.stderr)

    def build_to_maven_boundary(self, target):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / 'scripts/build_native_ios.sh'
            script.parent.mkdir()
            script.write_text((ROOT / 'scripts/build_native_ios.sh').read_text())
            # This orchestration fixture records the preparation boundary only.
            # Real Color patch compilation/execution lives in test_color_native.sh.
            (script.parent / 'prepare_native_color.py').write_text(
                'import json, sys\nfrom pathlib import Path\n'
                'Path(__file__).resolve().parents[1].joinpath("color-args.json")'
                '.write_text(json.dumps(sys.argv[1:]))\n')
            for name in ('core', 'engine', 'generated'):
                (root / 'build' / name).mkdir(parents=True)
            (root / 'build/core/Core.class').write_text('tooling fixture only')
            (root / 'build/engine/Engine.class').write_text('tooling fixture only')
            (root / 'build/generated/reflect-config.json').write_text('[]')
            (root / 'build/runtime-classpath.txt').write_text(
                f'{root}/build/core:{root}/build/engine:/full-production-dependencies.jar')
            compiler = root / 'compiler'
            commands = compiler / 'bin'
            commands.mkdir(parents=True)
            (compiler / 'release').write_text(
                'GRAALVM_VERSION="22.1.0.1"\nJAVA_VERSION="17.0.3"\nVENDOR=Gluon\n')
            for name, body in {
                'native-image': 'exit 0', 'javac': 'exit 0', 'xcodebuild': 'exit 0',
                'uname': 'if [[ "$1" == -s ]]; then echo Darwin; else echo x86_64; fi',
                'mvn': 'printf "%s\\n" "$@" > "$MM_TEST_ARGS"; exit 73',
            }.items():
                file = commands / name
                file.write_text('#!/bin/bash\n' + body + '\n')
                file.chmod(0o755)
            env = {**os.environ, 'MM_GRAALVM_HOME': str(compiler),
                   'PATH': str(commands) + os.pathsep + os.environ['PATH'],
                   'MM_TEST_ARGS': str(root / 'args.txt'), 'MM_NATIVE_MAX_HEAP': '4g',
                   'MM_NATIVE_NEW_RATIO': '2', 'MM_NATIVE_REFLECTION_PROFILE': 'broad',
                   'MM_NATIVE_INIT_PROFILE': 'runtime', 'MM_NATIVE_ORM_PROFILE': 'runtime'}
            env.pop('MM_NATIVE_TARGET', None)
            if target is not None:
                env['MM_NATIVE_TARGET'] = target
            result = subprocess.run(['bash', str(script)], env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 73, result.stdout + result.stderr)
            args = (root / 'args.txt').read_text().splitlines()
            color_args = json.loads((root / 'color-args.json').read_text())
            self.assertEqual(color_args[:3], ['--graalvm-home', str(compiler), '--output'])
            self.assertTrue(color_args[3].endswith('/color-patch'))
            self.assertIn('-Dnative.color.patch=' + color_args[3] + '/classes', args)
            return args

    def test_default_keeps_device_compile_and_staticlib(self):
        args = self.build_to_maven_boundary(None)
        self.assertIn('-Dnative.target=ios', args)
        self.assertEqual([x for x in args if x.startswith('com.gluonhq:')], [
            'com.gluonhq:gluonfx-maven-plugin:1.0.29:compile',
            'com.gluonhq:gluonfx-maven-plugin:1.0.29:staticlib'])

    def test_simulator_uses_full_classpath_and_downloads_static_jdk(self):
        args = self.build_to_maven_boundary('ios-sim')
        self.assertIn('-Dnative.target=ios-sim', args)
        self.assertIn('com.gluonhq:gluonfx-maven-plugin:1.0.29:link', args)
        cp = next(x for x in args if x.startswith('-Dnative.classpath='))
        self.assertTrue(cp.endswith('/full-production-dependencies.jar'))
        self.assertIn('/ios-native-', cp)


class RuntimeDriverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (ROOT / 'scripts/test_ios_simulator_engine.sh').read_text()
        driver = source.split("<<'PY_RUNTIME'\n", 1)[1].split('\nPY_RUNTIME\n', 1)[0]
        sys.path.insert(0, str(ROOT / 'scripts'))
        cls.namespace = {'__name__': 'tooling_runtime_check'}
        exec(compile(driver, 'check_runtime.py', 'exec'), cls.namespace)

    @classmethod
    def tearDownClass(cls):
        sys.path.remove(str(ROOT / 'scripts'))

    def run_driver(self, mode):
        # External process fixture tests the diagnostic orchestration only.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            server = root / 'fixture.py'
            server.write_text('''import json, sys
mode = sys.argv[1]
stage = 0
ai_step = 0
four_started = False
four_captures = set()
opening_owner_polls = 0
configuration = None
original = None
player_ids = ['00000000-0000-0000-0000-%012d' % i for i in range(1, 5)]
destroyed = False
responded = False
for line in sys.stdin:
    request = json.loads(line)
    op = request['op']
    if op not in ('create', 'capabilities'): assert request['matchId'] == str(stage)
    ok, result = True, {}
    if op == 'capabilities':
        result = dict(engine='xmage', execution='native-aot', catalogueHash='full', upstream='pinned')
        if mode == 'wrong_backend': result['execution'] = 'jvm-integration'
        if mode == 'wrong_hash': result['catalogueHash'] = 'pruned'
    elif op == 'create':
        assert stage == 0 or destroyed
        stage += 1
        destroyed = False
        configuration = request['configuration']
        seats = configuration['seats']
        if stage == 1: original = configuration
        elif stage == 2:
            assert [s['controller'] for s in seats] == ['human', 'ai']
            assert all(s['deck'] == original['seats'][0]['deck'] for s in seats)
        elif stage == 3:
            assert len(seats) == len({s['seatId'] for s in seats}) == len({s['name'] for s in seats}) == 4
            assert all(s['controller'] == 'human' and s['deck'] == original['seats'][i % 2]['deck']
                       for i, s in enumerate(seats))
        elif stage == 4: assert configuration == original
        else: raise AssertionError('Unexpected extra match')
        result = dict(matchId=str(stage), seats=[s['seatId'] for s in seats])
    elif op == 'poll':
        if destroyed:
            ok, result = False, dict(code='unknown_match')
        elif stage == 1:
            result = dict(phase='running', prompt=dict(promptId='next' if responded else 'first',
                revision=8 if responded else 7, payload=dict(candidates=['one'])))
            if mode == 'failed_state' or (mode == 'failed_after_response' and responded):
                result = dict(phase='failed', failure='native reachability failure')
        else:
            viewer = request['viewerId']
            seats = configuration['seats']
            assert stage != 2 or viewer == 'native-human', 'Never poll AI'
            index = next(i for i, s in enumerate(seats) if s['seatId'] == viewer)
            players = [dict(playerId=player_ids[i], name=s['name'], battlefield={}, handCount=1)
                       for i, s in enumerate(seats)]
            view = dict(players=players, myPlayerId=player_ids[index], myHand={'own-card': {}},
                        opponentHands={}, watchedHands={}, stack={}, combat=[])
            snapshot = dict(enginePlayerId=player_ids[index], gameView=view, commanders={},
                            authorizedOpponentHands={}, controlledPlayerViews={})
            result = dict(phase='running', viewerId=viewer, snapshot=snapshot, prompt=None)
            if stage == 2:
                kinds = ['PICK_TARGET', 'ASK', 'SELECT', 'PICK_TARGET', 'CHOOSE_CHOICE']
                if ai_step >= 5:
                    owner = 0 if mode == 'human_actions_only' else 1
                    players[owner]['battlefield'] = {'land': {'name': 'Plains'}, 'dog': {'name': 'Isamaru, Hound of Konda'}}
                    snapshot['commanders'] = {'dog': dict(name='Isamaru, Hound of Konda',
                        ownerPlayerId=player_ids[owner], castsFromCommandZone=1)}
                    view['combat'] = [dict(attackers={'dog': {}})]
                    if mode == 'missing_land': players[owner]['battlefield'].pop('land')
                    if mode == 'missing_cast': snapshot['commanders']['dog']['castsFromCommandZone'] = 0
                    if mode == 'wrong_cast_owner': snapshot['commanders']['dog']['ownerPlayerId'] = player_ids[0]
                    if mode == 'missing_attack': view['combat'] = []
                    if mode == 'human_attack_only': view['combat'] = [dict(attackers={'human-dog': {}})]
                payload = dict(candidates=player_ids[:2], choiceOrder=['exact:{first}', 'other'],
                               message='Choose starting player' if ai_step == 0 else 'Choose target')
                if mode == 'invalid_ai_candidate' and ai_step == 0: payload['candidates'] = player_ids[:1]
                result['prompt'] = dict(promptId='ai-' + str(ai_step), revision=100 + ai_step,
                    kind=kinds[ai_step] if ai_step < 5 else 'SELECT', payload=payload)
                if mode == 'unexpected_prompt': result['prompt']['kind'] = 'INVENTED'
                if mode == 'ai_failed': result.update(phase='failed', failure='native AI failure')
            elif stage == 3:
                result['revision'] = 201 if four_started else 200
                view['myHand'] = {'private-%d-%d' % (index, n): {'id': 'private-%d-%d' % (index, n)}
                                  for n in range(7)} if four_started else {}
                for player in players: player['handCount'] = 7 if four_started else 0
                if index == 0:
                    result['prompt'] = dict(promptId='opening' if four_started else 'four-start',
                        revision=result['revision'], kind='ASK' if four_started else 'PICK_TARGET',
                        payload=dict(message='Mulligan?' if four_started else 'Choose starting player',
                                     candidates=player_ids), submitted=False)
                if four_started:
                    four_captures.add(viewer)
                    if index == 0: opening_owner_polls += 1
                    if mode == 'empty_opening_hands':
                        view['myHand'] = {}
                        for player in players: player['handCount'] = 0
                    if mode == 'nested_private_leak': snapshot['nested'] = {'data': ['private-%d-0' % ((index + 1) % 4)]}
                    if mode == 'shared_private_ids': view['myHand'] = {'shared-%d' % n: {} for n in range(7)}
                    if mode == 'changed_parked_revision' and index == 3: result['revision'] += 1
                    if mode == 'changed_parked_prompt' and opening_owner_polls >= 3 and index == 0:
                        result['prompt']['promptId'] = 'changed-opening'
                if mode == 'wrong_viewer': result['viewerId'] = 'other-seat'
                if mode == 'wrong_player': view['myPlayerId'] = player_ids[(index + 1) % 4]
                if mode == 'leaked_hand': view['opponentHands'] = {'other': {'secret': {}}}
                if mode == 'wrong_hand_count': players[index]['handCount'] = 6
                if mode == 'wrong_player_count': players.pop()
            elif stage == 4 and mode == 'recreate_failed':
                result.update(phase='failed', failure='native recreation failure')
    elif op == 'respond':
        if stage == 1:
            assert request['command']['promptId'] == 'first'
            assert request['command']['promptRevision'] == 7
            assert request['command']['answer'] == dict(kind='uuid', value='one')
            responded = True
        elif stage == 3:
            assert not four_started and not four_captures, 'No answers during four-seat capture'
            assert request['viewerId'] == seats[0]['seatId']
            assert request['command']['promptId'] == 'four-start'
            assert request['command']['promptRevision'] == 200
            assert request['command']['answer'] == dict(kind='uuid', value=player_ids[0])
            four_started = True
        else:
            assert stage == 2 and request['viewerId'] == 'native-human'
            assert request['command']['promptId'] == 'ai-' + str(ai_step)
            assert request['command']['promptRevision'] == 100 + ai_step
            expected = {0: dict(kind='uuid', value=player_ids[1]),
                        3: dict(kind='uuid', value=player_ids[0]),
                        4: dict(kind='string', value='exact:{first}')}.get(ai_step, dict(kind='boolean', value=False))
            assert request['command']['answer'] == expected
            ai_step += 1
        result = dict(status='queued', requestId=request['command']['requestId'])
        if mode == 'bad_receipt': result = {}
        if mode == 'bad_ai_receipt' and stage == 2: result = {}
    elif op == 'destroy':
        assert not destroyed
        if stage == 3: assert four_started and len(four_captures) == 4
        destroyed = True
    print(json.dumps(dict(protocol=1, ok=ok, **{('result' if ok else 'error'): result})), flush=True)
if mode == 'success': assert stage == 4 and destroyed
if mode != 'no_teardown': print('SIMULATOR_ENGINE runtime_destroy=0', file=sys.stderr)
sys.exit(6 if mode == 'bad_exit' else 0)
''')
            configuration = {'seats': [dict(seatId=name, name=name, controller='human',
                deck={'fixtureOnly': deck}) for name, deck in [('one', 'Isamaru/99 Plains'), ('two', 'Yargle/99 Swamps')]]}
            original = copy.deepcopy(configuration)
            try:
                return self.namespace['check_runtime'](
                    [sys.executable, str(server), mode], configuration, 'full', root / 'stderr.txt')
            finally:
                self.assertEqual(configuration, original)

    def test_rejects_missing_response_acceptance(self):
        with self.assertRaisesRegex(RuntimeError, 'response receipt'):
            self.run_driver('bad_receipt')

    def test_lifecycle_requires_native_identity_full_registry_and_clean_teardown(self):
        report = self.run_driver('success')
        self.assertEqual(report['operations'], ['capabilities', 'create', 'poll', 'respond', 'destroy'])
        self.assertTrue(report['runtimeDestroyed'])
        self.assertTrue(report['sameIsolateReused'])
        self.assertEqual(report['aiLifecycle']['observations'], dict(land=True, commanderCast=True, attack=True))
        self.assertEqual(report['aiLifecycle']['humanResponses'], 5)
        self.assertEqual(len(report['fourHumanInitialPrivacy']['seats']), 4)
        self.assertTrue(report['fourHumanInitialPrivacy']['pairwisePrivateIDsAbsent'])
        self.assertEqual(report['fourHumanInitialPrivacy']['scope'], 'seven-card-opening-hands-at-parked-ASK')
        self.assertEqual([seat['privateHandCount'] for seat in report['fourHumanInitialPrivacy']['seats'].values()], [7] * 4)
        self.assertEqual(len(report['twoHumanRecreated']['seats']), 2)
        self.assertFalse(report['completedGame'])
        self.assertFalse(report['physicalDevice'])
        self.assertFalse(report['testFlight'])

    def test_wrong_backend_fails(self):
        with self.assertRaisesRegex(RuntimeError, 'real native XMage'):
            self.run_driver('wrong_backend')

    def test_wrong_catalogue_fails(self):
        with self.assertRaisesRegex(RuntimeError, 'full generated registry'):
            self.run_driver('wrong_hash')

    def test_native_reachability_error_fails(self):
        with self.assertRaisesRegex(RuntimeError, 'native reachability failure'):
            self.run_driver('failed_state')

    def test_shutdown_failure_cannot_pass(self):
        with self.assertRaisesRegex(RuntimeError, 'shutdown failed'):
            self.run_driver('bad_exit')

    def test_missing_teardown_evidence_cannot_pass(self):
        with self.assertRaisesRegex(RuntimeError, 'teardown evidence'):
            self.run_driver('no_teardown')

    def test_failure_while_applying_response_cannot_pass(self):
        with self.assertRaisesRegex(RuntimeError, 'native reachability failure'):
            self.run_driver('failed_after_response')

    def test_ai_requires_all_actions_attributed_to_actual_ai_uuid(self):
        for mode in ('human_actions_only', 'missing_land', 'missing_cast', 'wrong_cast_owner',
                     'missing_attack', 'human_attack_only'):
            with self.subTest(mode=mode), self.assertRaisesRegex(RuntimeError, 'within 180s'):
                with patch.object(self.namespace['time'], 'monotonic', side_effect=range(0, 10000, 10)):
                    self.run_driver(mode)

    def test_ai_response_count_is_bounded(self):
        with self.assertRaisesRegex(RuntimeError, '1000 human responses'):
            self.run_driver('missing_attack')

    def test_ai_fails_on_invalid_prompt_candidate_receipt_or_engine_failure(self):
        for mode, error in [('invalid_ai_candidate', 'legal UUID candidate'),
                            ('unexpected_prompt', 'Unexpected native human prompt'),
                            ('bad_ai_receipt', 'response receipt'), ('ai_failed', 'native AI failure')]:
            with self.subTest(mode=mode), self.assertRaisesRegex(RuntimeError, error):
                self.run_driver(mode)

    def test_four_seat_initial_privacy_guards(self):
        for mode in ('wrong_viewer', 'wrong_player', 'leaked_hand', 'wrong_hand_count', 'wrong_player_count'):
            with self.subTest(mode=mode), self.assertRaisesRegex(RuntimeError, 'viewer|privacy mismatch'):
                self.run_driver(mode)

    def test_recreation_failure_cannot_pass(self):
        with self.assertRaisesRegex(RuntimeError, 'native recreation failure'):
            self.run_driver('recreate_failed')

    def test_four_hands_cannot_pass_empty_leaking_or_changing_capture(self):
        for mode, error in [('empty_opening_hands', 'requires seven cards'),
                            ('nested_private_leak', 'private card ID leaked'),
                            ('shared_private_ids', 'private card ID leaked'),
                            ('changed_parked_revision', 'same parked decision'),
                            ('changed_parked_prompt', 'decision changed')]:
            with self.subTest(mode=mode), self.assertRaisesRegex(RuntimeError, error):
                self.run_driver(mode)


class SimulatorHarnessTests(unittest.TestCase):
    def test_generated_c_transport_compiles_without_any_engine_fixture(self):
        compiler = shutil.which('clang')
        if not compiler:
            self.skipTest('clang unavailable for tiny C syntax check')
        source = (ROOT / 'scripts/test_ios_simulator_engine.sh').read_text()
        caller = source.split("<<'C'\n", 1)[1].split('\nC\n', 1)[0]
        result = subprocess.run([
            compiler, '-x', 'c', '-fsyntax-only', '-std=c11', '-D_POSIX_C_SOURCE=200809L',
            '-Wall', '-Wextra', '-Werror', '-I' + str(ROOT / 'native'),
            '-I' + str(ROOT / 'swift/Sources/CMagicEngine/include'), '-'],
            input=caller, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)

    def cleanup_with_created_output(self, output, delete_status=0):
        source = (ROOT / 'scripts/test_ios_simulator_engine.sh').read_text()
        # Run the real timeout and cleanup functions against only an external
        # simctl stand-in. No simulator command can reach the host toolchain.
        cleanup = source.split('bounded() {', 1)[1].split("printf 'FULL XMAGE", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'created-uuid.txt').write_text(output)
            command = root / 'xcrun'
            command.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$MM_TEST_CALLS"\n'
                               'if [[ "$2" == delete ]]; then exit "$MM_TEST_DELETE_STATUS"; fi\n')
            command.chmod(0o755)
            env = {**os.environ, 'PATH': str(root) + os.pathsep + os.environ['PATH'],
                   'ENGINE_BUILD': str(root), 'MM_TEST_CALLS': str(root / 'calls.txt'),
                   'MM_TEST_DELETE_STATUS': str(delete_status)}
            result = subprocess.run(['bash', '-c', 'set -euo pipefail\nbounded() {' + cleanup],
                                    env=env, capture_output=True, text=True, timeout=10)
            calls = (root / 'calls.txt').read_text().splitlines() if (root / 'calls.txt').exists() else []
            return result.returncode, calls

    def test_cleanup_targets_only_uuid_returned_by_owned_create(self):
        owned = '12345678-1234-1234-1234-123456789ABC'
        code, calls = self.cleanup_with_created_output(owned + '\n')
        self.assertEqual(code, 0)
        self.assertEqual(calls, ['simctl shutdown ' + owned, 'simctl delete ' + owned])

    def test_malformed_create_output_never_deletes_any_simulator(self):
        code, calls = self.cleanup_with_created_output('booted\nall\n')
        self.assertEqual(code, 0)
        self.assertEqual(calls, [])

    def test_failed_owned_cleanup_fails_the_run(self):
        code, calls = self.cleanup_with_created_output('12345678-1234-1234-1234-123456789ABC', 1)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 2)


if __name__ == '__main__':
    unittest.main()
