import pathlib
import sys
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from verify_issue4_unsigned_product import inspect_text, REQUIRED

SYMBOLS='\n'.join('0000000100000000 T _'+name for name in sorted(REQUIRED))
class ProductInspectionTests(unittest.TestCase):
    def test_device_symbol_fixture_accepted(self): inspect_text('arm64\n','  platform 2\n',SYMBOLS)
    def test_named_ios_tag_accepted(self): inspect_text('arm64','  platform IOS\n',SYMBOLS)
    def test_legacy_ios_tag_accepted(self): inspect_text('arm64',' cmd LC_VERSION_MIN_IPHONEOS\n',SYMBOLS)
    def test_simulator_tag_rejected(self):
        with self.assertRaises(ValueError): inspect_text('arm64',' platform 7\n',SYMBOLS)
    def test_macos_tag_rejected(self):
        with self.assertRaises(ValueError): inspect_text('arm64',' platform MACOS\n',SYMBOLS)
    def test_conflicting_tags_rejected(self):
        with self.assertRaises(ValueError): inspect_text('arm64',' platform IOS\n platform IOSSIMULATOR\n',SYMBOLS)
    def test_no_platform_evidence_rejected(self):
        with self.assertRaises(ValueError): inspect_text('arm64','',SYMBOLS)
    def test_other_arch_rejected(self):
        with self.assertRaises(ValueError): inspect_text('x86_64',' platform 2\n',SYMBOLS)
    def test_fat_archives_rejected(self):
        with self.assertRaises(ValueError): inspect_text('arm64 x86_64',' platform 2\n',SYMBOLS)
    def test_undefined_exports_are_not_success(self):
        with self.assertRaises(ValueError): inspect_text('arm64',' platform 2\n',SYMBOLS.replace(' T ',' U '))
    def test_missing_shutdown_refused(self):
        with self.assertRaises(ValueError): inspect_text('arm64',' platform 2\n','\n'.join(line for line in SYMBOLS.splitlines() if 'shutdown' not in line))
    def test_toy_probe_refused(self):
        with self.assertRaises(ValueError): inspect_text('arm64',' platform 2\n',SYMBOLS+'\n0000000100000000 T _mm_toolchain_probe')

    def test_gluon_app_delegate_rejected(self):
        with self.assertRaises(ValueError):
            inspect_text('arm64', ' platform IOS\n', SYMBOLS+'\n0000000100000000 S _OBJC_CLASS_$_AppDelegate')
    def test_swift_product_delegate_is_not_gluon_delegate(self):
        inspect_text('arm64', ' platform IOS\n', SYMBOLS+'\n0000000100000000 S _OBJC_CLASS_$_MagicMobileAppDelegate')

if __name__=='__main__': unittest.main()
