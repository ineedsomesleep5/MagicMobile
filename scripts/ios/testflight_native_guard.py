#!/usr/bin/env python3
"""Fail-closed native TestFlight checks. Never signs, uploads, or executes a game.

Reuses the on-device package's source, staging, Mach-O and dSYM validators.
Receipts describe inspected bytes; they are not physical-device acceptance.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ENGINE = Path('packages/ondevice-engine')
sys.path.insert(0, str(ROOT / ENGINE / 'scripts'))
from prepare_ios_app_native import CLIBS, JDKLIBS, verify_installed
from verify_native_candidate import digest, source_identity, validate_receipt
from verify_issue4_unsigned_product import generated_project_receipt, inspect_info, inspect_text
from verify_graal_product_layout import verify_files

BUNDLE = 'com.calebfeliciano.magicmobile'
TEAM = '82HPAY85M8'
REPOSITORY = 'ineedsomesleep5/MagicMobile'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_json(path):
    return json.loads(Path(path).read_text())


def export_policy(options, audience='internal'):
    require(audience in ('internal', 'external'), 'Unknown TestFlight audience')
    require(options.get('method') == 'app-store-connect' and options.get('destination') == 'export',
            'Require an App Store Connect export, not automatic upload')
    require(options.get('testFlightInternalTestingOnly') is (audience == 'internal'),
            'Export options do not match the explicitly selected TestFlight audience')
    require(options.get('manageAppVersionAndBuildNumber') is False,
            'Xcode must not replace the prepared build number')
    require(options.get('teamID') == TEAM, 'Wrong export team')


def inspect_settings(rows):
    require(isinstance(rows, list), 'Expected xcodebuild JSON settings')
    targets = [r['buildSettings'] for r in rows if r.get('target') == 'MagicMobile']
    require(len(targets) == 1, 'Expected exactly one MagicMobile product target')
    settings = targets[0]
    expected = {'CONFIGURATION': 'Release', 'PLATFORM_NAME': 'iphoneos',
                'PRODUCT_BUNDLE_IDENTIFIER': BUNDLE, 'DEVELOPMENT_TEAM': TEAM,
                'MM_ENGINE_MODE': 'embedded-xmage', 'PRODUCT_NAME': 'MagicMobile'}
    for key, value in expected.items():
        require(settings.get(key) == value, 'Incorrect native release setting: ' + key)
    flags = settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '')
    flags = flags if isinstance(flags, list) else shlex.split(flags)
    require('XMAGE_NATIVE_LINKED' in flags, 'Native Release entrypoint is not enabled')
    require(settings.get('CODE_SIGNING_ALLOWED') != 'NO', 'Signing is disabled for the release')
    require(shlex.split(settings.get('ARCHS', '')) == ['arm64'], 'Release must target ARM64 iPhone')
    version, build = settings.get('MARKETING_VERSION', ''), settings.get('CURRENT_PROJECT_VERSION', '')
    require(bool(re.fullmatch(r'\d+(?:\.\d+){0,2}', version)) and bool(re.fullmatch(r'[1-9]\d{0,9}', build)),
            'Missing or unresolved release version/build')
    return {'appVersion': version, 'appBuild': build, 'bundleID': BUNDLE, 'teamID': TEAM}


def prepared_build(repo, identity):
    ledger = read_json(repo / 'release/testflight/build-ledger.json')
    build = identity['appBuild']
    version = identity['appVersion']
    # Compatibility only for historical ten-digit ledgers predating version ownership.
    # Short/sequential trains must explicitly identify both the ledger and preparation.
    legacy = bool(re.fullmatch(r'[1-9]\d{9}', build)) and 'versionSequential' not in ledger
    require(ledger.get('bundleId') == BUNDLE and ledger.get('lastPreparedBuild') == build
            and (ledger.get('marketingVersion') == version or (legacy and 'marketingVersion' not in ledger))
            and (ledger.get('lastPreparedMarketingVersion') == version or (legacy and 'lastPreparedMarketingVersion' not in ledger))
            and ('versionSequential' not in ledger or ledger['versionSequential'].get('marketingVersion') == version),
            'Prepare and commit the TestFlight build number before releasing')
    used = {str(row.get('build')) for row in ledger.get('uploads', [])
            if row.get('marketingVersion') in (None, version)}
    last_uploaded = ledger.get('lastUploadedBuild') if ledger.get('lastUploadedMarketingVersion', version) == version else None
    require(build != last_uploaded and build not in used,
            'This build number is already recorded as uploaded')
    info = plistlib.loads((repo / 'apps/ios/MagicMobile/Info.plist').read_bytes())
    for key, setting, expected in (('CFBundleVersion', 'CURRENT_PROJECT_VERSION', build),
                                  ('CFBundleShortVersionString', 'MARKETING_VERSION', identity['appVersion'])):
        require(info.get(key) in (expected, '$(' + setting + ')'), 'Source Info.plist disagrees with build settings: ' + key)


def paired_staging(manifest, hashes):
    mapping = {'lib/libmmengine.a': 'libmmengine.a',
               'include/libmmengine.h': 'include/io.magicmobile.nativebridge.ioslibrarymain.h',
               'include/graal_isolate.h': 'include/graal_isolate.h'}
    for group, names in (('clib', CLIBS), ('jdk', JDKLIBS)):
        mapping.update({f'lib/lib{name}.a': f'{group}/lib{name}.a' for name in names})
    require(set(manifest.get('files', {})) == set(mapping), 'Unexpected staged native input set')
    for staged, original in mapping.items():
        require(manifest['files'][staged].get('sha256') == hashes.get(original),
                'Staged input is not paired with the verified engine: ' + staged)


def preflight(repo, options_path, audience='internal'):
    options_path = options_path.resolve()
    export_policy(plistlib.loads(options_path.read_bytes()), audience)
    provenance_path = repo / ENGINE / 'build/native-candidate-provenance.json'
    proof = read_json(provenance_path)
    require(proof.get('schema') == 1 and proof.get('repository') == REPOSITORY, 'Wrong native provenance repository/schema')
    require(isinstance(proof.get('artifactID'), int) and proof['artifactID'] > 0
            and isinstance(proof.get('workflowRunID'), int) and proof['workflowRunID'] > 0
            and re.fullmatch(r'sha256:[a-f0-9]{64}', proof.get('artifactDigest', '')), 'Missing native artifact identity')
    identity = source_identity(repo, proof['engineSourceCommit'])
    manifest_path = repo / 'apps/ios/NativeEngine/manifest.json'
    manifest = verify_installed(manifest_path.parent)
    original = Path(manifest['files']['lib/libmmengine.a']['source']).parent
    hashes = validate_receipt(original, proof['engineSourceCommit'])
    require(hashes == proof.get('files'), 'Original native artifact no longer matches its provenance receipt')
    paired_staging(manifest, hashes)
    compiler = read_json(original / 'compiler-patch-manifest.json')
    require(compiler.get('patchSha256') == digest(repo / ENGINE / 'native/gluon/compiler-patches/far-calls.patch'),
            'Compiler patch differs from the verified artifact')
    return {'schema': 1, **identity, 'engineArtifactID': proof['artifactID'],
            'engineWorkflowRunID': proof['workflowRunID'], 'engineArchiveSHA256': hashes['libmmengine.a'],
            'stagedManifestSHA256': digest(manifest_path), 'provenanceSHA256': digest(provenance_path),
            'exportOptionsPath': str(options_path), 'exportOptionsSHA256': digest(options_path),
            'testFlightAudience': audience,
            'scope': 'Source/artifact integrity only; not native execution or App Store Connect build availability'}


def unchanged_inputs(repo, receipt):
    require(receipt.get('schema') == 1, 'Unknown release receipt schema')
    head = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
    require(head == receipt['appSourceCommit'], 'Source commit changed during release')
    manifest_path = repo / 'apps/ios/NativeEngine/manifest.json'
    verify_installed(manifest_path.parent)
    for path, expected in ((manifest_path, receipt['stagedManifestSHA256']),
                           (repo / ENGINE / 'build/native-candidate-provenance.json', receipt['provenanceSHA256']),
                           (Path(receipt['exportOptionsPath']), receipt['exportOptionsSHA256'])):
        require(digest(path) == expected, 'Verified release input changed: ' + str(path))
    project = generated_project_receipt(repo)
    if 'generatedProject' in receipt:
        require(project == receipt['generatedProject'], 'Generated project changed after release configuration was checked')
    return project


def configure(repo, receipt, settings):
    result = dict(receipt)
    result['generatedProject'] = unchanged_inputs(repo, receipt)
    identity = inspect_settings(settings)
    prepared_build(repo, identity)
    result.update(identity)
    return result


def inspect_signing(entitlements, profile, now=None):
    now = now or datetime.now(timezone.utc)
    require(entitlements.get('com.apple.developer.team-identifier') == TEAM
            and TEAM in profile.get('TeamIdentifier', []), 'Incorrect signed app/profile team')
    profile_entitlements = profile.get('Entitlements', {})
    app_id = entitlements.get('application-identifier', '')
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    require(any(app_id == prefix + '.' + BUNDLE for prefix in prefixes)
            and profile_entitlements.get('application-identifier') == app_id, 'Signed app/profile identifier mismatch')
    for source in (entitlements, profile_entitlements):
        require(source.get('get-task-allow') is False, 'Refusing a development/debuggable distribution')
        require(source.get('com.apple.developer.game-center') is True, 'Game Center entitlement is missing')
    require(not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'),
            'Require App Store distribution, not device/ad-hoc/enterprise provisioning')
    expiration = profile.get('ExpirationDate')
    require(isinstance(expiration, datetime), 'Missing provisioning expiration')
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    require(expiration > now, 'Provisioning profile has expired')


def extract_app(ipa, directory):
    """Extract one owned app without allowing ZIP traversal, links or unbounded expansion."""
    with zipfile.ZipFile(ipa) as archive:
        members = archive.infolist()
        require(len(members) <= 20000 and sum(m.file_size for m in members) <= 3 * 1024**3, 'IPA exceeds inspection limits')
        seen, apps = set(), set()
        for member in members:
            raw = member.filename.rstrip('/')
            path = PurePosixPath(raw)
            require(raw and not path.is_absolute() and str(path) == raw and '..' not in path.parts
                    and '\\' not in raw and raw not in seen, 'Unsafe or duplicate IPA entry')
            seen.add(raw)
            mode = member.external_attr >> 16
            require(not stat.S_ISLNK(mode) and stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR), 'IPA links/devices are not supported')
            if len(path.parts) >= 2 and path.parts[0] == 'Payload' and path.parts[1].endswith('.app'):
                apps.add(path.parts[1])
        require(apps == {'MagicMobile.app'}, 'IPA does not contain exactly the intended product')
        for member in members:
            path = PurePosixPath(member.filename.rstrip('/'))
            if path.parts[:2] != ('Payload', 'MagicMobile.app'):
                continue
            target = directory / str(path)
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(member) as src, target.open('xb') as dst:
                    shutil.copyfileobj(src, dst)
                target.chmod((member.external_attr >> 16) & 0o777 or 0o644)
    return directory / 'Payload/MagicMobile.app'


def command(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def exported(repo, receipt, ipa, archive):
    require('generatedProject' in receipt and 'appBuild' in receipt, 'Missing configured release receipt')
    unchanged_inputs(repo, receipt)
    before = digest(ipa)
    with tempfile.TemporaryDirectory(prefix='magicmobile-signed-inspection-') as temporary:
        app = extract_app(ipa, Path(temporary))
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        inspect_info(info)
        require(info['CFBundleVersion'] == receipt['appBuild']
                and info['CFBundleShortVersionString'] == receipt['appVersion'], 'Exported app has a different version/build')
        binary = app / info['CFBundleExecutable']
        dsym = archive / 'dSYMs/MagicMobile.app.dSYM/Contents/Resources/DWARF' / info['CFBundleExecutable']
        command('codesign', '--verify', '--deep', '--strict', str(app))
        entitlements = plistlib.loads(command('codesign', '--display', '--entitlements', ':-', str(app)))
        profile = plistlib.loads(command('security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')))
        inspect_signing(entitlements, profile)
        inspect_text(command('xcrun', 'lipo', '-archs', str(binary)).decode(),
                     command('xcrun', 'otool', '-l', str(binary)).decode(),
                     command('xcrun', 'nm', '-g', str(dsym)).decode())
        layout = verify_files(repo / 'apps/ios/NativeEngine/lib/libmmengine.a', binary, dsym)
        result = {**receipt, 'ipaSHA256': before, 'binarySHA256': digest(binary),
                  'graalCodeLayout': layout, 'signedGameCenterChecked': True,
                  'scope': 'Signed exported binary inspection only; not phone gameplay or tester availability',
                  'nativeDeviceValidated': False, 'testFlightUploaded': False}
    require(digest(ipa) == before, 'IPA changed during verification')
    unchanged_inputs(repo, receipt)
    return result


def upload_input(repo, receipt, ipa):
    require(receipt.get('signedGameCenterChecked') is True and receipt.get('graalCodeLayout', {}).get('intactCodeImage') is True,
            'Signed native product has not passed export inspection')
    unchanged_inputs(repo, receipt)
    require(digest(ipa) == receipt.get('ipaSHA256'), 'IPA changed after signed export inspection')
    return {'appSourceCommit': receipt['appSourceCommit'], 'appBuild': receipt['appBuild'],
            'ipaSHA256': receipt['ipaSHA256'], 'scope': 'Unchanged upload input only; no upload performed'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('source', 'settings', 'exported', 'upload-input'))
    parser.add_argument('--repo', type=Path, default=ROOT)
    parser.add_argument('--receipt', type=Path)
    parser.add_argument('--settings', type=Path)
    parser.add_argument('--export-options', type=Path)
    parser.add_argument('--ipa', type=Path)
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--audience', choices=('internal', 'external'), default='internal')
    args = parser.parse_args()
    try:
        repo = args.repo.resolve()
        if args.operation == 'source':
            require(args.export_options is not None, 'Source check requires export options')
            result = preflight(repo, args.export_options, args.audience)
        else:
            require(args.receipt is not None, 'A preceding release receipt is required')
            receipt = read_json(args.receipt)
            if args.operation == 'settings':
                require(args.settings is not None, 'Settings JSON is required')
                result = configure(repo, receipt, read_json(args.settings))
            elif args.operation == 'exported':
                require(args.ipa is not None and args.archive is not None, 'IPA and matching archive/dSYM are required')
                result = exported(repo, receipt, args.ipa, args.archive)
            else:
                require(args.ipa is not None, 'IPA is required')
                result = upload_input(repo, receipt, args.ipa)
        if args.output:
            with args.output.open('x') as out:
                json.dump(result, out, indent=2, sort_keys=True)
                out.write('\n')
        print(json.dumps(result, indent=2, sort_keys=True))
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(2, 'Native TestFlight guard refused: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
