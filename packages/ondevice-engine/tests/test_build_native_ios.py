"""Small orchestration checks of build_native_ios.sh only; these do not compile or run XMage."""
import os
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeTargetTests(unittest.TestCase):
    def test_invalid_target_fails_before_building(self):
        # Exercise a copied script with no compiler or classpath. Even RED must
        # never reach a real local build on the 8 GB developer machine.
        for target in ('macos', 'ios-sim'):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as directory:
                script = Path(directory) / 'scripts/build_native_ios.sh'
                script.parent.mkdir()
                script.write_text((ROOT / 'scripts/build_native_ios.sh').read_text())
                result = subprocess.run(
                    ['bash', str(script)],
                    env={**os.environ, 'MM_NATIVE_TARGET': target,
                         'MM_GRAALVM_HOME': str(Path(directory) / 'missing-compiler')},
                    capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn('MM_NATIVE_TARGET must be ios', result.stdout + result.stderr)

    def build_to_maven_boundary(self, optimize=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / 'scripts/build_native_ios.sh'
            script.parent.mkdir()
            script.write_text((ROOT / 'scripts/build_native_ios.sh').read_text())
            (root / 'native/gluon').mkdir(parents=True)
            pins = (ROOT / 'native/gluon/toolchain.json').read_text()
            (root / 'native/gluon/toolchain.json').write_text(pins)
            # The resource guard's own checks are in test_native_resources.py; record its inputs.
            (script.parent / 'check_native_resources.py').write_text(
                'import json, sys\nfrom pathlib import Path\n'
                'Path(__file__).resolve().parents[1].joinpath("resource-args.json")'
                '.write_text(json.dumps(sys.argv[1:]))\n')
            for name in ('core', 'engine', 'generated'):
                (root / 'build' / name).mkdir(parents=True)
            (root / 'build/core/Core.class').write_text('tooling fixture only')
            (root / 'build/engine/Engine.class').write_text('tooling fixture only')
            (root / 'build/generated/reflect-config.json').write_text('[]')
            (root / 'build/runtime-classpath.txt').write_text(
                f'{root}/build/core:{root}/build/engine:/full-production-dependencies.jar')
            static = root / 'vmone/lib'
            static.mkdir(parents=True)
            (static / 'libvmone.a').write_text('static JDK fixture only')
            compiler = root / 'compiler'
            commands = compiler / 'bin'
            commands.mkdir(parents=True)
            (compiler / 'release').write_text(
                '\n'.join(json.loads(pins)['graalvm']['release_lines']) + '\n')
            for name, body in {
                'native-image': 'exit 0', 'xcodebuild': 'exit 0',
                # Compiler stand-in: creates the output packages the script copies between.
                'javac': 'out=; prev=; for a in "$@"; do [[ "$prev" == -d ]] && out="$a"; prev="$a"; done\n'
                         'mkdir -p "$out/io/magicmobile/nativebridge" "$out/jdk/internal/reflect"\n'
                         'touch "$out/jdk/internal/reflect/MobileCheckpointConstructorAccessor.class"',
                'uname': 'if [[ "$1" == -s ]]; then echo Darwin; else echo x86_64; fi',
                'mvn': 'printf "%s\\n" "$@" > "$MM_TEST_ARGS"; exit 73',
                # Metadata exporter stand-in: records its arguments and writes both outputs.
                'java': 'printf "%s\\n" "$@" > "$MM_TEST_ARGS.exporter"\n'
                        'while [[ $# -gt 0 && "$1" != NativeReflectionExporter ]]; do shift; done\n'
                        'mkdir -p "$2"; echo "[]" > "$2/reflect-config.json"\n'
                        'echo \'{"types":[],"lambdaCapturingTypes":[]}\' > "$2/serialization-config.json"',
            }.items():
                file = commands / name
                file.write_text('#!/bin/bash\n' + body + '\n')
                file.chmod(0o755)
            env = {**os.environ, 'MM_GRAALVM_HOME': str(compiler), 'MM_JAVA_STATIC_LIBS': str(static),
                   'PATH': str(commands) + os.pathsep + os.environ['PATH'],
                   'MM_TEST_ARGS': str(root / 'args.txt'), 'MM_NATIVE_MAX_HEAP': '4g',
                   'MM_NATIVE_REFLECTION_PROFILE': 'broad',
                   'MM_NATIVE_INIT_PROFILE': 'runtime', 'MM_NATIVE_ORM_PROFILE': 'runtime'}
            env.pop('MM_NATIVE_TARGET', None)
            env.pop('MM_NATIVE_OPTIMIZE', None)
            if optimize is not None:
                env['MM_NATIVE_OPTIMIZE'] = optimize
            result = subprocess.run(['bash', str(script)], env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 73, result.stdout + result.stderr)
            args = (root / 'args.txt').read_text().splitlines()
            # JDK 23's Color needs no patch; nothing prepares or passes one.
            self.assertFalse(any('color' in a.lower() for a in args), args)
            self.assertIn('-Djavalibspath=' + str(static), args)
            # The resource guard sees the exact native classpath before the native build starts.
            resource_args = json.loads((root / 'resource-args.json').read_text())
            self.assertEqual(resource_args[0], '--classpath')
            self.assertTrue(resource_args[1].endswith('/native-java:' + next(
                x for x in args if x.startswith('-Dnative.classpath='))[len('-Dnative.classpath='):]))
            self.assertEqual(resource_args[2:4], ['--config', str(root / 'native/resource-config.json')])
            # Every profile passes save/resume serialization metadata from the exporter.
            exporter = (root / 'args.txt.exporter').read_text().splitlines()
            self.assertIn('--serialization', exporter)
            self.assertIn('-Dnative.serialization.config=' + str(root / 'build/native-metadata/serialization-config.json'), args)
            return args

    def test_default_is_device_staticlib_at_o2(self):
        args = self.build_to_maven_boundary()
        self.assertIn('-Dnative.target=ios', args)
        self.assertIn('-Dnative.optimize=2', args)
        # Substrate 0.0.65's staticlib compiles by itself; a separate compile goal would compile twice.
        self.assertEqual([x for x in args if x.startswith('com.gluonhq:')], [
            'com.gluonhq:gluonfx-maven-plugin:1.0.25:staticlib'])
        cp = next(x for x in args if x.startswith('-Dnative.classpath='))
        self.assertTrue(cp.endswith('/full-production-dependencies.jar'))
        self.assertIn('/ios-native-', cp)

    def test_size_optimized_build(self):
        self.assertIn('-Dnative.optimize=s', self.build_to_maven_boundary('s'))

    def test_unreviewed_compiler_release_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / 'scripts/build_native_ios.sh'
            script.parent.mkdir()
            script.write_text((ROOT / 'scripts/build_native_ios.sh').read_text())
            (root / 'native/gluon').mkdir(parents=True)
            (root / 'native/gluon/toolchain.json').write_text((ROOT / 'native/gluon/toolchain.json').read_text())
            for name in ('build/core', 'build/engine', 'build/generated', 'compiler/bin'):
                (root / name).mkdir(parents=True)
            (root / 'build/generated/reflect-config.json').write_text('[]')
            (root / 'build/runtime-classpath.txt').write_text('fixture')
            (root / 'compiler/release').write_text('GRAALVM_VERSION="22.1.0.1"\nJAVA_VERSION="17.0.3"\nVENDOR=Gluon\n')
            native_image = root / 'compiler/bin/native-image'
            native_image.write_text('#!/bin/bash\nexit 0\n')
            native_image.chmod(0o755)
            result = subprocess.run(['bash', str(script)], capture_output=True, text=True, timeout=10,
                                    env={**os.environ, 'MM_GRAALVM_HOME': str(root / 'compiler'),
                                         'MM_NATIVE_MAX_HEAP': '4g'})
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'build/native-metadata').exists())


if __name__ == '__main__':
    unittest.main()
