"""Guard the narrow native policy; execution is covered by test_color_native.sh."""
from pathlib import Path
import importlib.util
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class NativeColorPolicyTests(unittest.TestCase):
    def test_color_and_toolkit_remain_runtime_initialized(self):
        args = [e.text for e in ET.parse(ROOT / 'native/gluon/pom.xml').iter(
            '{http://maven.apache.org/POM/4.0.0}arg')]
        awt = [a for a in args if a and a.startswith('--initialize-at-build-time=') and 'java.awt' in a]
        self.assertEqual(awt, [])
        self.assertIn('--initialize-at-run-time=java.awt.Color,java.awt.Toolkit', args)
        self.assertIn('-J--patch-module=java.desktop=${native.color.patch}', args)
        self.assertIn('--initialize-at-run-time=io.magicmobile,mage', args)

    def test_unreviewed_color_source_is_rejected(self):
        spec = importlib.util.spec_from_file_location('native_color', ROOT / 'scripts/prepare_native_color.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with self.assertRaisesRegex(ValueError, 'Unreviewed JDK Color source'):
            module.patched_source(module.DESKTOP_INIT.encode())


if __name__ == '__main__':
    unittest.main()
