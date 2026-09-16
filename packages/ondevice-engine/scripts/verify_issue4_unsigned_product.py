#!/usr/bin/env python3
"""Inspect a built iOS product; this is binary/link evidence, NOT gameplay proof."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess

REQUIRED = {'mm_engine_request', 'mm_engine_free', 'mm_engine_shutdown_v2', 'graal_create_isolate', 'mm_runtime_create'}
GENERATED_PROJECT_FILES = {
    'apps/ios/MagicMobileiOS.xcodeproj/project.pbxproj',
    'apps/ios/MagicMobileiOS.xcodeproj/project.xcworkspace/contents.xcworkspacedata',
    'apps/ios/MagicMobileiOS.xcodeproj/xcshareddata/xcschemes/MagicMobile.xcscheme',
}


def inspect_text(architectures: str, load_commands: str, symbols: str) -> None:
    if architectures.strip() != 'arm64':
        raise ValueError('Expected ARM64-only device product')
    platforms = re.findall(r'^\s*platform\s+(\S+)', load_commands, re.M)
    legacy = re.findall(r'\bcmd (LC_VERSION_MIN_\w+)', load_commands)
    if (not platforms and not legacy or any(p not in ('2', 'IOS') for p in platforms)
            or any(p != 'LC_VERSION_MIN_IPHONEOS' for p in legacy)):
        raise ValueError('Missing/conflicting device platform tags')
    if re.search(r'_OBJC_(?:META)?CLASS_\$_AppDelegate\b', symbols):
        raise ValueError('Refusing the Gluon AppDelegate in the Swift product')
    if re.search(r'_mm_toolchain_probe\b', symbols):
        raise ValueError('Refusing ABI-only probe in product')
    defined = set(re.findall(r'^\s*[0-9a-fA-F]+\s+T\s+_(\w+)\s*$', symbols, re.M))
    if not REQUIRED <= defined:
        raise ValueError('Missing native definitions: ' + ', '.join(sorted(REQUIRED - defined)))


def inspect_info(info: dict) -> None:
    """Require resolved release metadata for the embedded product, not a reference app."""
    if info.get('CFBundleIdentifier') != 'com.calebfeliciano.magicmobile':
        raise ValueError('Wrong app identity')
    if info.get('MagicMobileEngineMode') != 'embedded-xmage':
        raise ValueError('Product metadata does not identify the embedded engine')
    for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
        value = info.get(key)
        if not isinstance(value, str) or not value.strip() or '$(' in value:
            raise ValueError('Missing or unresolved version metadata: ' + key)
    executable = info.get('CFBundleExecutable')
    if (not isinstance(executable, str) or not executable
            or executable in ('.', '..') or pathlib.Path(executable).name != executable):
        raise ValueError('Invalid executable name')


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024*1024), b''): h.update(block)
    return h.hexdigest()


def generated_project_receipt(repo: pathlib.Path) -> dict:
    """Accept only XcodeGen's three tracked outputs; all other source stays clean."""
    source = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
    if not re.fullmatch('[a-f0-9]{40}', source):
        raise ValueError('Invalid source commit')
    changed = subprocess.check_output(
        ['git', '-C', str(repo), 'diff', '--name-only', '-z', 'HEAD', '--'])
    names = {name.decode('utf-8') for name in changed.split(b'\0') if name}
    if names - GENERATED_PROJECT_FILES:
        raise ValueError('Source changed during product generation: ' + ', '.join(sorted(names - GENERATED_PROJECT_FILES)))
    untracked = subprocess.check_output([
        'git', '-C', str(repo), 'ls-files', '--others', '--exclude-standard', '-z', '--',
        'apps/ios/MagicMobile', 'apps/ios/NativeLink',
        'packages/ondevice-engine/swift/Sources', 'packages/ondevice-engine/native'])
    if untracked:
        raise ValueError('Uncommitted source files would enter the generated product')
    files = {}
    for name in sorted(GENERATED_PROJECT_FILES):
        path = repo / name
        if not path.is_file() or path.is_symlink() or any(parent.is_symlink() for parent in path.parents):
            raise ValueError('Missing or symlinked generated project file: ' + name)
        files[name] = digest(path)
    return {'schema': 1, 'sourceCommit': source, 'files': files}


def verify_generated_project(repo: pathlib.Path, record: pathlib.Path) -> dict:
    expected = json.loads(record.read_text())
    actual = generated_project_receipt(repo)
    if expected != actual:
        raise ValueError('Generated project or source changed after the pre-build receipt')
    return actual


def main():
    p=argparse.ArgumentParser(description=__doc__)
    action=p.add_mutually_exclusive_group(required=True)
    action.add_argument('--app',type=pathlib.Path)
    action.add_argument('--record-generated-project',action='store_true')
    p.add_argument('--project-record',type=pathlib.Path)
    p.add_argument('--repo',type=pathlib.Path,required=True)
    p.add_argument('--output',type=pathlib.Path,required=True)
    a=p.parse_args()
    try:
        if a.record_generated_project:
            if a.project_record: raise ValueError('Recording does not accept an existing project receipt')
            receipt=generated_project_receipt(a.repo)
            a.output.write_text(json.dumps(receipt,indent=2)+'\n')
            print('PASS: generated project hashes recorded; other tracked sources remain unchanged')
            return
        if not a.project_record: raise ValueError('Product inspection requires the pre-build generated-project receipt')
        project=verify_generated_project(a.repo,a.project_record)
        info=plistlib.loads((a.app/'Info.plist').read_bytes())
        inspect_info(info)
        executable=info['CFBundleExecutable']
        binary=a.app/executable
        def command(*args): return subprocess.check_output(args,text=True,stderr=subprocess.PIPE)
        arch=command('xcrun','lipo','-archs',str(binary))
        load=command('xcrun','otool','-l',str(binary))
        symbols=command('xcrun','nm','-g',str(binary))
        inspect_text(arch,load,symbols)
        from verify_graal_product_layout import verify_files
        layout = verify_files(a.repo/'apps/ios/NativeEngine/lib/libmmengine.a', binary)
        source=project['sourceCommit']
        manifest=a.repo/'apps/ios/NativeEngine/manifest.json'
        from prepare_ios_app_native import verify_installed
        verify_installed(manifest.parent)
        # The staging verifier performs its own per-file hash checks before linking.
        receipt={'schema':1,'sourceCommit':source,'bundleID':info['CFBundleIdentifier'],
            'binarySHA256':digest(binary),'stagedManifestSHA256':digest(manifest),
            'architecture':'arm64','platform':'iphoneos','definedNativeSymbols':sorted(REQUIRED),
            'evidenceScope':'product link and inspection only',
            'generatedProject':project,
            'graalCodeLayout':layout,
            'nativeRuntimeTested':False,'nativeDeviceValidated':False,'testFlightUploaded':False,
            'engineMode':info['MagicMobileEngineMode'],
            'appVersion':info.get('CFBundleShortVersionString'),
            'appBuild':info.get('CFBundleVersion')}
        provenance=a.repo/'packages/ondevice-engine/build/native-candidate-provenance.json'
        if provenance.is_file():
            receipt['engineBuildProvenance']=json.loads(provenance.read_text())
        a.output.write_text(json.dumps(receipt,indent=2)+'\n')
        print(json.dumps(receipt,indent=2))
    except (OSError,ValueError,KeyError,subprocess.CalledProcessError) as error:
        p.exit(2,f'Unsigned product verification refused: {error}\n')
if __name__=='__main__': main()
