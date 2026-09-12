import pathlib
import sys
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from verify_issue4_unsigned_product import inspect_text, inspect_info, REQUIRED

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

class ProductMetadataTests(unittest.TestCase):
    def metadata(self):
        return {'CFBundleIdentifier': 'com.calebfeliciano.magicmobile',
                'MagicMobileEngineMode': 'embedded-xmage',
                'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '123',
                'CFBundleExecutable': 'MagicMobile'}
    def test_embedded_resolved_metadata_accepted(self):
        inspect_info(self.metadata())
    def test_legacy_mode_rejected(self):
        info = self.metadata(); info['MagicMobileEngineMode'] = 'reference'
        with self.assertRaises(ValueError): inspect_info(info)
    def test_missing_mode_rejected(self):
        info = self.metadata(); del info['MagicMobileEngineMode']
        with self.assertRaises(ValueError): inspect_info(info)
    def test_wrong_app_identity_rejected(self):
        info = self.metadata(); info['CFBundleIdentifier'] += '.ondevice'
        with self.assertRaises(ValueError): inspect_info(info)
    def test_blank_marketing_version_rejected(self):
        info = self.metadata(); info['CFBundleShortVersionString'] = ' '
        with self.assertRaises(ValueError): inspect_info(info)
    def test_unresolved_build_variable_rejected(self):
        info = self.metadata(); info['CFBundleVersion'] = '$(CURRENT_PROJECT_VERSION)'
        with self.assertRaises(ValueError): inspect_info(info)
    def test_non_string_build_version_rejected(self):
        info = self.metadata(); info['CFBundleVersion'] = 123
        with self.assertRaises(ValueError): inspect_info(info)
    def test_invalid_executable_names_rejected(self):
        for name in ('', '.', '..', '../MagicMobile', '/tmp/MagicMobile'):
            info = self.metadata(); info['CFBundleExecutable'] = name
            with self.assertRaises(ValueError, msg=name): inspect_info(info)


# Real temporary Git repositories exercise source provenance, not app/runtime behavior.
import tempfile
import subprocess
from verify_issue4_unsigned_product import GENERATED_PROJECT_FILES, generated_project_receipt, verify_generated_project

class GeneratedProjectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.repo = pathlib.Path(self.temp.name).resolve()
        self.git('init', '-q'); self.git('config', 'user.name', 'Project receipt fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'gc.auto', '0'); self.git('config', 'maintenance.auto', 'false')
        for name in GENERATED_PROJECT_FILES:
            path = self.repo / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('original project fixture')
        (self.repo / 'App.swift').write_text('// original source fixture')
        self.git('add', '.'); self.git('commit', '-qm', 'source fixture')
    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True, stderr=subprocess.DEVNULL).strip()
    def record(self):
        import json
        path = self.repo / 'receipt.json'
        path.write_text(json.dumps(generated_project_receipt(self.repo)))
        return path
    def test_clean_source_and_generated_project_record(self):
        result = verify_generated_project(self.repo, self.record())
        self.assertEqual(set(result['files']), GENERATED_PROJECT_FILES)
    def test_only_expected_project_generation_is_allowed(self):
        for name in GENERATED_PROJECT_FILES: (self.repo / name).write_text('generated fixture output')
        verify_generated_project(self.repo, self.record())
    def test_source_change_is_never_allowed(self):
        (self.repo / 'App.swift').write_text('// changed source')
        with self.assertRaises(ValueError): self.record()
    def test_project_mutation_after_record_is_rejected(self):
        record = self.record()
        (self.repo / sorted(GENERATED_PROJECT_FILES)[0]).write_text('changed after record')
        with self.assertRaises(ValueError): verify_generated_project(self.repo, record)
    def test_missing_generated_file_is_rejected(self):
        (self.repo / sorted(GENERATED_PROJECT_FILES)[0]).unlink()
        with self.assertRaises(ValueError): self.record()
    def test_symlinked_generated_file_is_rejected(self):
        p = self.repo / sorted(GENERATED_PROJECT_FILES)[0]; p.unlink(); p.symlink_to(self.repo / 'App.swift')
        with self.assertRaises(ValueError): self.record()
    def test_untracked_product_source_is_rejected(self):
        p = self.repo / 'apps/ios/MagicMobile/Uncommitted.swift'
        p.parent.mkdir(parents=True, exist_ok=True); p.write_text('// unexpected untracked source')
        with self.assertRaises(ValueError): self.record()
    def test_record_cannot_be_reused_for_another_source_commit(self):
        record = self.record()
        self.git('commit', '--allow-empty', '-qm', 'different source identity')
        with self.assertRaises(ValueError): verify_generated_project(self.repo, record)

if __name__=='__main__': unittest.main()
