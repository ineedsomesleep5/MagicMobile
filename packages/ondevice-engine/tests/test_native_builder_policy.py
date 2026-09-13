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

    def test_heap_guard_and_telemetry_remain(self):
        script = (ROOT / 'scripts/build_native_ios.sh').read_text()
        self.assertIn('sysctl -n hw.memsize', script)
        self.assertIn('12884901888', script)
        self.assertNotIn('NATIVE_NEW_RATIO', script)
        probe = (ROOT / 'scripts/test_ios_toolchain.sh').read_text()
        self.assertIn("grep -q 'Using G1'", probe)


if __name__ == '__main__':
    unittest.main()
