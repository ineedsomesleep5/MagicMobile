"""Guard the narrow native policy; execution is covered by test_color_native.sh."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class NativeColorPolicyTests(unittest.TestCase):
    def test_only_reviewed_color_class_is_explicitly_build_time(self):
        args = [e.text for e in ET.parse(ROOT / 'native/gluon/pom.xml').iter(
            '{http://maven.apache.org/POM/4.0.0}arg')]
        awt = [a for a in args if a and a.startswith('--initialize-at-build-time=') and 'java.awt' in a]
        self.assertEqual(awt, ['--initialize-at-build-time=java.awt.Color'])
        self.assertIn('--initialize-at-run-time=io.magicmobile,mage', args)


if __name__ == '__main__':
    unittest.main()
