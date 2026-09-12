"""Small orchestration checks only; these do not compile or run XMage."""
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest

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
            return (root / 'args.txt').read_text().splitlines()

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
destroyed = False
responded = False
for line in sys.stdin:
    request = json.loads(line)
    op = request['op']
    ok, result = True, {}
    if op == 'capabilities':
        result = dict(engine='xmage', execution='native-aot', catalogueHash='full', upstream='pinned')
        if mode == 'wrong_backend': result['execution'] = 'jvm-integration'
        if mode == 'wrong_hash': result['catalogueHash'] = 'pruned'
    elif op == 'create': result = dict(matchId='match', seats=['one', 'two'])
    elif op == 'poll':
        if destroyed:
            ok, result = False, dict(code='unknown_match')
        else:
            result = dict(phase='running', prompt=dict(promptId='next' if responded else 'first',
                revision=8 if responded else 7, payload=dict(candidates=['one'])))
            if mode == 'failed_state' or (mode == 'failed_after_response' and responded):
                result = dict(phase='failed', failure='native reachability failure')
    elif op == 'respond':
        assert request['command']['promptId'] == 'first'
        assert request['command']['promptRevision'] == 7
        assert request['command']['answer'] == dict(kind='uuid', value='one')
        responded = True
        result = dict(status='queued', requestId=request['command']['requestId'])
        if mode == 'bad_receipt': result = {}
    elif op == 'destroy': destroyed = True
    print(json.dumps(dict(protocol=1, ok=ok, **{('result' if ok else 'error'): result})), flush=True)
if mode != 'no_teardown': print('SIMULATOR_ENGINE runtime_destroy=0', file=sys.stderr)
sys.exit(6 if mode == 'bad_exit' else 0)
''')
            return self.namespace['check_runtime'](
                [sys.executable, str(server), mode], {'seats': []}, 'full', root / 'stderr.txt')

    def test_rejects_missing_response_acceptance(self):
        with self.assertRaisesRegex(RuntimeError, 'response receipt'):
            self.run_driver('bad_receipt')

    def test_lifecycle_requires_native_identity_full_registry_and_clean_teardown(self):
        report = self.run_driver('success')
        self.assertEqual(report['operations'], ['capabilities', 'create', 'poll', 'respond', 'destroy'])
        self.assertTrue(report['runtimeDestroyed'])
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
