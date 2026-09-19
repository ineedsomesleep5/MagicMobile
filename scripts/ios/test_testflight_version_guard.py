"""Version-train release checks; temporary files only, no builds or uploads."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('version_guard', Path(__file__).with_name('testflight_native_guard.py'))
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class VersionGuardTests(unittest.TestCase):
    def test_version_scoped_history_and_strict_preparation(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            ledger = repo / 'release/testflight/build-ledger.json'
            ledger.parent.mkdir(parents=True)
            info = repo / 'apps/ios/MagicMobile/Info.plist'
            info.parent.mkdir(parents=True)
            info.write_bytes(plistlib.dumps({'CFBundleVersion': '1', 'CFBundleShortVersionString': '0.1.1'}))
            valid = {'bundleId': guard.BUNDLE, 'marketingVersion': '0.1.1', 'lastPreparedBuild': '1',
                     'lastPreparedMarketingVersion': '0.1.1',
                     'lastUploadedBuild': '1', 'lastUploadedMarketingVersion': '0.1.0',
                     'uploads': [{'build': '1', 'marketingVersion': '0.1.0'}]}
            identity = {'appBuild': '1', 'appVersion': '0.1.1'}
            ledger.write_text(json.dumps(valid))
            guard.prepared_build(repo, identity)
            for bad in [{**valid, 'marketingVersion': '0.1.0'}, {**valid, 'marketingVersion': None},
                        {**valid, 'lastPreparedMarketingVersion': '0.1.0'},
                        {**valid, 'lastUploadedMarketingVersion': '0.1.1'},
                        {**valid, 'uploads': [{'build': '1', 'marketingVersion': '0.1.1'}]},
                        {**valid, 'uploads': [{'build': '1'}]}]:
                ledger.write_text(json.dumps(bad))
                with self.subTest(bad=bad), self.assertRaises(ValueError):
                    guard.prepared_build(repo, identity)
            missing = dict(valid); missing.pop('lastPreparedMarketingVersion')
            ledger.write_text(json.dumps(missing))
            with self.assertRaises(ValueError): guard.prepared_build(repo, identity)
            info.write_bytes(plistlib.dumps({'CFBundleVersion': '5000000001', 'CFBundleShortVersionString': '0.1.1'}))
            legacy = {'bundleId': guard.BUNDLE, 'lastPreparedBuild': '5000000001', 'uploads': []}
            identity['appBuild'] = '5000000001'
            ledger.write_text(json.dumps(legacy)); guard.prepared_build(repo, identity)
            legacy['versionSequential'] = {'marketingVersion': '0.1.1'}
            ledger.write_text(json.dumps(legacy))
            with self.assertRaises(ValueError): guard.prepared_build(repo, identity)

    def test_positive_one_to_ten_digit_builds(self):
        fixture = Path(__file__).resolve().parents[2] / 'packages/ondevice-engine/tests/test_testflight_native_guard.py'
        spec = importlib.util.spec_from_file_location('legacy_guard_fixtures', fixture)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for build in ['1', '2', '9999999999', '0', '01', '-1', '10000000000']:
            rows = module.settings()
            rows[0]['buildSettings']['CURRENT_PROJECT_VERSION'] = build
            if build in ['1', '2', '9999999999']:
                self.assertEqual(guard.inspect_settings(rows)['appBuild'], build)
            else:
                with self.subTest(build=build), self.assertRaises(ValueError): guard.inspect_settings(rows)


if __name__ == '__main__':
    unittest.main()
