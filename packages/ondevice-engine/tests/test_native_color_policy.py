"""Guard the narrow native Color policy; execution is covered by test_color_native.sh.

JDK 23's java.awt.Color has no desktop JNI initializer, so release D builds the JDK's own
class: no java.desktop patch, Color and Toolkit still initialized at run time.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class NativeColorPolicyTests(unittest.TestCase):
    def test_color_and_toolkit_remain_runtime_initialized_without_a_patch(self):
        args = [e.text or '' for e in ET.parse(ROOT / 'native/gluon/pom.xml').iter(
            '{http://maven.apache.org/POM/4.0.0}arg')]
        awt = [a for a in args if a.startswith('--initialize-at-build-time=') and 'java.awt' in a]
        self.assertEqual(awt, [])
        self.assertIn('--initialize-at-run-time=java.awt.Color,java.awt.Toolkit', args)
        self.assertIn('--initialize-at-run-time=io.magicmobile,mage', args)
        self.assertEqual([a for a in args if 'java.desktop' in a or 'color.patch' in a], [])

    def test_no_build_prepares_or_passes_a_color_patch(self):
        self.assertFalse((ROOT / 'scripts/prepare_native_color.py').exists())
        scripts = [ROOT / 'scripts' / name for name in (
            'build_native_ios.sh', 'test_ios_toolchain.sh', 'test_ios_link.sh')]
        scripts.append(ROOT.parents[1] / 'scripts/android/build_native.sh')
        for script in scripts:
            with self.subTest(script=script.name):
                text = script.read_text()
                self.assertNotIn('prepare_native_color', text)
                self.assertNotIn('native.color.patch', text)
                self.assertNotIn('color-patch', text)

    def test_native_regression_guards_the_jdk_color_source(self):
        script = (ROOT / 'scripts/test_color_native.sh').read_text()
        for guard in ("'Toolkit.loadLibraries()'", "'initIDs()'", "java.desktop/java/awt/Color.java",
                      '--initialize-at-run-time=java.awt.Color,java.awt.Toolkit', '--desktop-guard'):
            self.assertIn(guard, script)


if __name__ == '__main__':
    unittest.main()
