"""Release safety fixtures only: no signing, upload, native engine, or simulator."""
import copy
from datetime import datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

REPO = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('testflight_native_guard', REPO / 'scripts/ios/testflight_native_guard.py')
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


def settings():
    return [{'target': 'MagicMobile', 'buildSettings': {
        'CONFIGURATION': 'Release', 'PLATFORM_NAME': 'iphoneos',
        'PRODUCT_BUNDLE_IDENTIFIER': guard.BUNDLE, 'DEVELOPMENT_TEAM': guard.TEAM,
        'MM_ENGINE_MODE': 'embedded-xmage', 'PRODUCT_NAME': 'MagicMobile',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'XMAGE_NATIVE_LINKED',
        'CODE_SIGNING_ALLOWED': 'YES', 'ARCHS': 'arm64',
        'MARKETING_VERSION': '0.1.0', 'CURRENT_PROJECT_VERSION': '2026091401'}}]


def signing():
    entitlements = {'application-identifier': guard.TEAM + '.' + guard.BUNDLE,
                    'com.apple.developer.team-identifier': guard.TEAM,
                    'get-task-allow': False, 'com.apple.developer.game-center': True}
    profile = {'TeamIdentifier': [guard.TEAM], 'ApplicationIdentifierPrefix': [guard.TEAM],
               'Entitlements': dict(entitlements),
               'ExpirationDate': datetime.now(timezone.utc) + timedelta(days=1)}
    return entitlements, profile


class ReleaseGuardTests(unittest.TestCase):
    def test_actual_internal_export_policy(self):
        options = plistlib.loads((REPO / 'release/testflight/ExportOptions.plist').read_bytes())
        guard.export_policy(options)
        for key, bad in [('destination', 'upload'), ('method', 'development'),
                         ('teamID', 'other'), ('testFlightInternalTestingOnly', False),
                         ('manageAppVersionAndBuildNumber', True)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                guard.export_policy({**options, key: bad})

    def test_linked_release_settings(self):
        self.assertEqual(guard.inspect_settings(settings())['appBuild'], '2026091401')

    def test_refuses_unlinked_release_even_with_correct_bundle(self):
        rows = settings(); rows[0]['buildSettings']['MM_ENGINE_MODE'] = 'unlinked-reference'
        with self.assertRaisesRegex(ValueError, 'MM_ENGINE_MODE'): guard.inspect_settings(rows)

    def test_refuses_missing_or_partial_native_flag(self):
        for flag in ['', 'DEBUG', 'NOT_XMAGE_NATIVE_LINKED', ['DEBUG']]:
            rows = settings(); rows[0]['buildSettings']['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = flag
            with self.subTest(flag=flag), self.assertRaises(ValueError): guard.inspect_settings(rows)
        rows[0]['buildSettings']['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = ['XMAGE_NATIVE_LINKED']
        guard.inspect_settings(rows)

    def test_rejects_wrong_product_sdk_architecture_or_signing(self):
        for key, value in [('CONFIGURATION', 'Debug'), ('PLATFORM_NAME', 'iphonesimulator'),
                           ('ARCHS', 'x86_64'), ('ARCHS', 'arm64 x86_64'),
                           ('PRODUCT_BUNDLE_IDENTIFIER', 'other.app'), ('PRODUCT_NAME', 'EngineLab'),
                           ('DEVELOPMENT_TEAM', 'other'), ('CODE_SIGNING_ALLOWED', 'NO')]:
            rows = settings(); rows[0]['buildSettings'][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError): guard.inspect_settings(rows)

    def test_rejects_ambiguous_target_and_unresolved_versions(self):
        for rows in [[], settings() + settings(), [{'target': 'Other', 'buildSettings': {}}]]:
            with self.subTest(rows=rows), self.assertRaises(ValueError): guard.inspect_settings(rows)
        for key in ['MARKETING_VERSION', 'CURRENT_PROJECT_VERSION']:
            rows = settings(); rows[0]['buildSettings'][key] = '$(UNKNOWN)'
            with self.subTest(key=key), self.assertRaises(ValueError): guard.inspect_settings(rows)

    def test_prepared_number_must_not_already_be_uploaded(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            ledger = repo / 'release/testflight/build-ledger.json'
            ledger.parent.mkdir(parents=True)
            info = repo / 'apps/ios/MagicMobile/Info.plist'; info.parent.mkdir(parents=True)
            info.write_bytes(plistlib.dumps({'CFBundleVersion': '2026091401', 'CFBundleShortVersionString': '$(MARKETING_VERSION)'}))
            identity = guard.inspect_settings(settings())
            valid = {'bundleId': guard.BUNDLE, 'lastPreparedBuild': '2026091401', 'lastUploadedBuild': '2026091301', 'uploads': []}
            ledger.write_text(json.dumps(valid)); guard.prepared_build(repo, identity)
            for bad in [{**valid, 'lastPreparedBuild': '2026091301'}, {**valid, 'lastUploadedBuild': '2026091401'},
                        {**valid, 'uploads': [{'build': '2026091401'}]}, {**valid, 'bundleId': 'another.app'}]:
                ledger.write_text(json.dumps(bad))
                with self.subTest(bad=bad), self.assertRaises(ValueError): guard.prepared_build(repo, identity)
            ledger.write_text(json.dumps(valid))
            info.write_bytes(plistlib.dumps({'CFBundleVersion': '2026091301', 'CFBundleShortVersionString': '0.1.0'}))
            with self.assertRaisesRegex(ValueError, 'Info.plist'): guard.prepared_build(repo, identity)

    def test_paired_library_and_headers_are_all_required(self):
        mapping = {'lib/libmmengine.a': 'libmmengine.a', 'include/libmmengine.h': 'include/io.magicmobile.nativebridge.ioslibrarymain.h',
                   'include/graal_isolate.h': 'include/graal_isolate.h'}
        for group, names in [('clib', guard.CLIBS), ('jdk', guard.JDKLIBS)]:
            mapping.update({f'lib/lib{name}.a': f'{group}/lib{name}.a' for name in names})
        hashes = {name: str(i) for i, name in enumerate(mapping.values())}
        manifest = {'files': {name: {'sha256': hashes[source]} for name, source in mapping.items()}}
        guard.paired_staging(manifest, hashes)
        for name in mapping:
            changed = copy.deepcopy(manifest); changed['files'][name]['sha256'] = 'wrong'
            with self.subTest(name=name), self.assertRaises(ValueError): guard.paired_staging(changed, hashes)
        del manifest['files']['include/libmmengine.h']
        with self.assertRaises(ValueError): guard.paired_staging(manifest, hashes)

    def test_signing_and_profile_gamecenter_both_required(self):
        entitlements, profile = signing(); guard.inspect_signing(entitlements, profile)
        for target in ['app', 'profile']:
            e, p = signing()
            (e if target == 'app' else p['Entitlements']).pop('com.apple.developer.game-center')
            with self.subTest(target=target), self.assertRaisesRegex(ValueError, 'Game Center'): guard.inspect_signing(e, p)

    def test_refuses_debug_adhoc_enterprise_wrong_identity_or_expired_profile(self):
        e, p = signing()
        cases = [(dict(e, **{'get-task-allow': True}), p),
                 (dict(e, **{'application-identifier': guard.TEAM + '.wrong'}), p),
                 (dict(e, **{'com.apple.developer.team-identifier': 'other'}), p),
                 (e, {**p, 'TeamIdentifier': ['other']}), (e, {**p, 'ProvisionedDevices': ['device']}),
                 (e, {**p, 'ProvisionsAllDevices': True}), (e, {**p, 'ExpirationDate': datetime(2000, 1, 1)}),
                 (e, {**p, 'Entitlements': dict(e, **{'application-identifier': guard.TEAM + '.*'})})]
        for case in cases:
            with self.subTest(case=case), self.assertRaises(ValueError): guard.inspect_signing(*case)

    def test_app_identifier_prefix_can_differ_from_team(self):
        e, p = signing()
        e['application-identifier'] = 'OLDPREFIX.' + guard.BUNDLE
        p['ApplicationIdentifierPrefix'] = ['OLDPREFIX']; p['Entitlements'] = dict(e)
        guard.inspect_signing(e, p)

    def test_extracts_only_expected_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); ipa = root / 'test.ipa'
            with zipfile.ZipFile(ipa, 'w') as z:
                z.writestr('Payload/', b''); z.writestr('Payload/MagicMobile.app/', b'')
                z.writestr('Payload/MagicMobile.app/Info.plist', b'fixture')
                z.writestr('SwiftSupport/unused', b'outside app')
            app = guard.extract_app(ipa, root / 'unpacked')
            self.assertEqual((app / 'Info.plist').read_bytes(), b'fixture')
            self.assertFalse((root / 'unpacked/SwiftSupport').exists())

    def test_ipa_paths_links_duplicate_apps_and_entries_fail_closed(self):
        for name in ['../escape', '/absolute', 'Payload/MagicMobile.app/../escape', 'Payload//double',
                     'Payload\\backslash', 'Payload/Other.app/Info.plist', 'Payload/MagicMobile.app/Info.plist']:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); ipa = root / 'test.ipa'
                with zipfile.ZipFile(ipa, 'w') as z:
                    z.writestr('Payload/MagicMobile.app/Info.plist', b'fixture')
                    z.writestr(name, b'bad')
                with self.assertRaises(ValueError): guard.extract_app(ipa, root / 'out')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); ipa = root / 'test.ipa'
            with zipfile.ZipFile(ipa, 'w') as z:
                link = zipfile.ZipInfo('Payload/MagicMobile.app/Info.plist')
                link.external_attr = (stat.S_IFLNK | 0o777) << 16
                z.writestr(link, '/outside')
            with self.assertRaises(ValueError): guard.extract_app(ipa, root / 'out')

    def test_upload_checks_exact_ipa_and_never_calls_apple(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); ipa = root / 'test.ipa'; ipa.write_bytes(b'not an engine; receipt fixture')
            receipt = {'signedGameCenterChecked': True, 'graalCodeLayout': {'intactCodeImage': True},
                       'ipaSHA256': guard.digest(ipa), 'appSourceCommit': 'a' * 40, 'appBuild': '2026091401'}
            with patch.object(guard, 'unchanged_inputs') as source, patch.object(guard, 'command') as apple:
                guard.upload_input(root, receipt, ipa); source.assert_called_once(); apple.assert_not_called()
                ipa.write_bytes(b'changed')
                with self.assertRaisesRegex(ValueError, 'IPA changed'): guard.upload_input(root, receipt, ipa)
                with self.assertRaisesRegex(ValueError, 'not passed'): guard.upload_input(root, {}, ipa)

    def test_generation_or_source_changes_refuse_upload(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); ipa = root / 'test.ipa'; ipa.write_bytes(b'fixture')
            receipt = {'signedGameCenterChecked': True, 'graalCodeLayout': {'intactCodeImage': True}}
            with patch.object(guard, 'unchanged_inputs', side_effect=ValueError('Source changed')):
                with self.assertRaisesRegex(ValueError, 'Source changed'): guard.upload_input(root, receipt, ipa)

    def test_shell_refuses_without_native_provenance_and_preserves_prior_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary).resolve() / 'repo'
            scripts = repo / 'scripts/ios'; scripts.mkdir(parents=True)
            for name in ['deploy-testflight.sh', 'testflight_native_guard.py']:
                shutil.copyfile(REPO / 'scripts/ios' / name, scripts / name)
            package = repo / 'packages/ondevice-engine/scripts'; package.mkdir(parents=True)
            for name in ['prepare_ios_app_native.py', 'verify_native_candidate.py',
                         'verify_issue4_unsigned_product.py', 'verify_graal_product_layout.py']:
                shutil.copyfile(REPO / 'packages/ondevice-engine/scripts' / name, package / name)
            options = repo / 'release/testflight/ExportOptions.plist'; options.parent.mkdir(parents=True)
            shutil.copyfile(REPO / 'release/testflight/ExportOptions.plist', options)
            sentinel = repo / 'build_output/testflight/MagicMobile.xcarchive/keep'
            sentinel.parent.mkdir(parents=True); sentinel.write_text('previous evidence')
            bins = repo / 'test-bin'; bins.mkdir(); log = repo / 'apple-calls'
            for tool in ['uname', 'xcodegen', 'xcodebuild', 'xcrun', 'codesign', 'security', 'node']:
                path = bins / tool
                path.write_text('#!/bin/sh\n' + ('echo Darwin\n' if tool == 'uname' else f'echo {tool} >> "{log}"\nexit 97\n'))
                path.chmod(0o755)
            key = repo / 'not-a-real-key'; key.write_text('fixture')
            env = {k: v for k, v in os.environ.items() if k not in ['ARCHIVE_PATH', 'EXPORT_PATH', 'PROJECT_PATH', 'OUTPUT_ROOT',
                  'PREPARE_TESTFLIGHT_BUILD_NUMBER', 'BUNDLE_ID', 'TEAM_ID', 'SCHEME', 'CONFIGURATION']}
            env.update(PATH=str(bins) + os.pathsep + env['PATH'], ASC_KEY_PATH=str(key))
            result = subprocess.run(['bash', str(scripts / 'deploy-testflight.sh')], env=env, text=True, capture_output=True, timeout=15)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sentinel.read_text(), 'previous evidence')
            self.assertFalse(log.exists(), 'Missing provenance must fail before any Apple build/sign/upload call')


if __name__ == '__main__': unittest.main()
