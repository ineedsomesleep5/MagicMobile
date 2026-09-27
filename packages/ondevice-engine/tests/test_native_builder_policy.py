"""Builder configuration checks, not proof of full native compilation."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class NativeBuilderPolicyTests(unittest.TestCase):
    def test_g1_changes_only_the_builder_collector(self):
        args = [e.text for e in ET.parse(ROOT / 'native/gluon/pom.xml').iter(
            '{http://maven.apache.org/POM/4.0.0}arg')]
        self.assertIn('-J-XX:-UseParallelGC', args)
        self.assertIn('-J-XX:+UseG1GC', args)
        self.assertFalse(any('NewRatio' in a for a in args if a))
        self.assertFalse(any(a.startswith('--gc=') for a in args if a))
        self.assertIn('-J-Xmx${native.max.heap}', args)
        self.assertIn('-H:NumberOfThreads=2', args)

    def test_checkpoint_classes_use_the_light_registration_feature(self):
        # GraalVM 22.1 serialization configuration would make every declared method of the
        # 48,730 checkpoint types invocable (docs/NATIVE_METADATA.md).
        args = [e.text for e in ET.parse(ROOT / 'native/gluon/pom.xml').iter(
            '{http://maven.apache.org/POM/4.0.0}arg')]
        self.assertFalse(any(a and a.startswith('-H:SerializationConfigurationFiles') for a in args))
        self.assertIn('-Dmagicmobile.checkpoint.serialization=${native.serialization.config}', args)
        self.assertIn('${native.checkpoint.feature}', args)
        enable = '-Dnative.checkpoint.feature=--features=io.magicmobile.nativebridge.CheckpointSerializationFeature'
        for script in (ROOT / 'scripts/build_native_ios.sh', ROOT.parents[1] / 'scripts/android/build_native.sh'):
            with self.subTest(script=script.name):
                text = script.read_text()
                self.assertIn(enable, text)
                self.assertIn('nativebridge/CheckpointSerializationFeature.java"', text)
                self.assertIn('-Dnative.serialization.config=', text)

    def test_heap_guard_and_telemetry_remain(self):
        script = (ROOT / 'scripts/build_native_ios.sh').read_text()
        self.assertIn('sysctl -n hw.memsize', script)
        self.assertIn('12884901888', script)
        self.assertNotIn('NATIVE_NEW_RATIO', script)
        probe = (ROOT / 'scripts/test_ios_toolchain.sh').read_text()
        self.assertIn("grep -q 'Using G1'", probe)


if __name__ == '__main__':
    unittest.main()
