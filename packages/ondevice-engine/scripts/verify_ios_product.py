#!/usr/bin/env python3
"""Inspect the actual linked iOS app without signing, installation or execution."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

BUNDLE_ID = 'com.calebfeliciano.magicmobile'
REQUIRED = ('mm_install_graal_backend', 'mm_engine_request', 'mm_engine_free',
            'mm_engine_shutdown_v2', 'graal_create_isolate', 'graal_attach_thread',
            'graal_detach_thread', 'graal_tear_down_isolate')


def xcrun(*args: str) -> str:
    return subprocess.check_output(['xcrun', *map(str, args)], text=True, stderr=subprocess.STDOUT)


def verify(app: Path) -> dict:
    if app.is_symlink() or not app.is_dir(): raise ValueError('Expected a real app bundle')
    with (app/'Info.plist').open('rb') as stream: info = plistlib.load(stream)
    if info.get('CFBundleIdentifier') != BUNDLE_ID: raise ValueError('Wrong existing product identity')
    if info.get('MagicMobileEngineMode') != 'embedded-xmage': raise ValueError('App was not built with the embedded engine overlay')
    name = info.get('CFBundleExecutable')
    if not isinstance(name, str) or Path(name).name != name or name in ('', '.', '..'):
        raise ValueError('Invalid executable name')
    binary = app / name
    if binary.is_symlink() or not binary.is_file(): raise ValueError('Missing linked executable')
    arch = xcrun('lipo', '-archs', binary).strip().split()
    if arch != ['arm64']: raise ValueError('Product must be iOS ARM64 only')
    commands = xcrun('vtool', '-show-build', binary)
    platforms = re.findall(r'^\s*platform\s+(\w+)\s*$', commands, re.M)
    if not platforms or set(platforms) != {'IOS'}: raise ValueError('Product has wrong/missing iOS platform metadata')
    minimum = re.findall(r'^\s*minos\s+([0-9.]+)\s*$', commands, re.M)
    if not minimum or any(tuple(map(int, item.split('.'))) + (0, 0) < (17, 0, 0) for item in minimum):
        raise ValueError('Product minimum deployment target is below iOS 17')
    symbols = xcrun('nm', '-g', binary)
    defined = set(re.findall(r'\bT\s+_([A-Za-z0-9_]+)\s*$', symbols, re.M))
    missing = set(REQUIRED) - defined
    if missing: raise ValueError(f'Missing linked native definitions: {sorted(missing)}')
    if 'mm_toolchain_probe' in symbols or 'runtime_swift_close' in symbols or '_OBJC_CLASS_$_AppDelegate' in symbols:
        raise ValueError('Probe, fixture or Gluon-owned AppDelegate was linked into the product')
    dylibs = xcrun('otool', '-L', binary)
    if re.search(r'(?:libjvm\.dylib|JavaVM\.framework|/build/|/Users/|/home/)', '\n'.join(dylibs.splitlines()[1:])):
        raise ValueError('Product depends on a desktop/build-machine dynamic library')
    orientations = set(info.get('UISupportedInterfaceOrientations', []))
    if not {'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'}.issubset(orientations):
        raise ValueError('Existing portrait/landscape support was lost')
    for key in ('CFBundleVersion', 'CFBundleShortVersionString'):
        if not isinstance(info.get(key), str) or not info[key] or '$(' in info[key]:
            raise ValueError(f'Missing resolved version: {key}')
    digest = hashlib.sha256()
    with binary.open('rb') as stream:
        for block in iter(lambda: stream.read(1024*1024), b''): digest.update(block)
    return {'schema': 1, 'scope': 'actual unsigned iOS product linkage; not runtime or phone acceptance',
            'bundleIdentifier': BUNDLE_ID, 'build': info['CFBundleVersion'], 'version': info['CFBundleShortVersionString'],
            'mode': info['MagicMobileEngineMode'], 'architecture': 'arm64', 'platform': 'IOS',
            'minimumOS': minimum, 'executableSHA256': digest.hexdigest(), 'executableBytes': binary.stat().st_size,
            'requiredDefinedSymbols': sorted(REQUIRED), 'nativeExecutionVerified': False,
            'signingPerformedByThisCheck': False, 'uploadPerformedByThisCheck': False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    try:
        text = json.dumps(verify(args.app), indent=2, sort_keys=True)+'\n'
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            with args.report.open('x') as output: output.write(text)
        print(text, end=''); return 0
    except (ValueError, OSError, TypeError, subprocess.SubprocessError) as error:
        print(f'iOS product verification failed: {error}', file=sys.stderr); return 2


if __name__ == '__main__': raise SystemExit(main())
