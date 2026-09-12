#!/usr/bin/env python3
"""Stage explicitly supplied iOS AOT inputs; never compile, link, sign or run them.

Dry run by default. --apply owns only apps/ios/NativeEngine, refuses an existing
different tree, and accepts an identical tree. Header and archive must come from
the same real CI build; symbol checks cannot establish that provenance or engine
capabilities. --verify-installed checks the recorded bytes for the optional
native-engine.yml build. It does not prove that the native engine works.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
DESTINATION = ROOT / 'apps/ios/NativeEngine'
ENGINE_SYMBOLS = ('mm_engine_request', 'mm_engine_free', 'mm_engine_shutdown_v2')
GRAAL_SYMBOLS = ('graal_create_isolate', 'graal_attach_thread',
                 'graal_detach_thread', 'graal_tear_down_isolate')
CLIBS = ('jvm', 'libchelper', 'ffi', 'darwin')
JDKLIBS = ('java', 'nio', 'zip', 'net', 'prefs', 'fdlibm', 'j2pkcs11', 'jaas', 'extnet')
OWNED_FILES = {'lib/libmmengine.a', 'include/libmmengine.h', 'include/graal_isolate.h'} | {
    f'lib/lib{name}.a' for name in CLIBS + JDKLIBS}


def xcrun(*args):
    return subprocess.check_output(['xcrun', *map(str, args)], text=True,
                                   stderr=subprocess.PIPE)


def validate_archive(path, *, engine=False):
    with path.open('rb') as stream:
        if stream.read(8) != b'!<arch>\n':
            raise ValueError(f'Expected a static archive: {path}')
    if xcrun('lipo', '-archs', path).strip() != 'arm64':
        raise ValueError(f'Expected ARM64 only: {path}')
    commands = xcrun('otool', '-l', path)
    platforms = re.findall(r'^\s*platform\s+(\S+)', commands, re.M)
    legacy = re.findall(r'\bcmd (LC_VERSION_MIN_\w+)', commands)
    if (not platforms and not legacy or
            any(p not in ('2', 'IOS') for p in platforms) or
            any(p != 'LC_VERSION_MIN_IPHONEOS' for p in legacy)):
        raise ValueError(f'Missing or conflicting IOS platform tags: {path}')
    # Gluon AOT objects can lack load commands. Require IOS evidence in the
    # archive and reject every conflicting tag; this is not per-object proof.
    if engine:
        symbols = xcrun('nm', '-g', path)
        if re.search(r'_mm_toolchain_probe\b', symbols):
            raise ValueError('Refusing toy probe archive')
        # Gluon bundles a separate AppDelegate/main member. Ordinary archive
        # linking with Swift's main must leave it out; inspect the final binary.
        defined = set(re.findall(r'^\s*[0-9a-fA-F]+\s+T\s+_(\w+)\s*$', symbols, re.M))
        missing = set(ENGINE_SYMBOLS + GRAAL_SYMBOLS) - defined
        if missing:
            raise ValueError('Missing defined native exports: ' + ', '.join(sorted(missing)))
    return {'architecture': 'arm64', 'platform_tags': platforms + legacy}


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def validate_header(header):
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', header.read_text(), flags=re.S)
    signatures = (
        r'char\s*\*\s*mm_engine_request\s*\(\s*graal_isolatethread_t\s*\*\s*,\s*char\s*\*\s*,\s*int\s*\)\s*;',
        r'void\s+mm_engine_free\s*\(\s*graal_isolatethread_t\s*\*\s*,\s*char\s*\*\s*\)\s*;',
        r'int\s+mm_engine_shutdown_v2\s*\(\s*graal_isolatethread_t\s*\*\s*\)\s*;',
    )
    if any(not re.search(pattern, text) for pattern in signatures):
        raise ValueError('Generated header must declare the expected ABI v2 signatures')
    includes = re.findall(r'^\s*#\s*include\s*[<"]([^>"]+)[>"]', text, re.M)
    if includes != ['graal_isolate.h'] or 'mm_toolchain_probe' in text:
        raise ValueError('Unexpected generated header includes or toy entry point')
    sdk_header = header.parent / 'graal_isolate.h'
    if not sdk_header.is_file() or not sdk_header.stat().st_size:
        raise ValueError('Missing sibling graal_isolate.h')
    if re.search(r'^\s*#\s*include', sdk_header.read_text(), re.M):
        raise ValueError('Unexpected transitive SDK header dependency; review explicitly')
    return sdk_header


def check_destination(destination):
    for path in (destination, *destination.parents):
        if path.is_symlink():
            raise ValueError(f'Refusing symlink destination: {path}')


def verify_installed(destination=DESTINATION):
    check_destination(destination)
    paths = list(destination.rglob('*'))
    if any(p.is_symlink() for p in paths):
        raise ValueError('Refusing symlink inside owned destination')
    files = {p.relative_to(destination).as_posix() for p in paths if p.is_file()}
    if files != OWNED_FILES | {'manifest.json'}:
        raise ValueError('Installed file set differs from owned native inputs')
    manifest = json.loads((destination / 'manifest.json').read_text())
    if manifest.get('schema') != 1 or set(manifest.get('files', {})) != OWNED_FILES:
        raise ValueError('Invalid native input manifest')
    for name, entry in manifest['files'].items():
        if digest(destination / name) != entry['sha256']:
            raise ValueError(f'Installed hash mismatch: {name}')
    return manifest


def prepare(archive, header, clib_dir, jdk_lib_dir, destination=DESTINATION, *, apply=False):
    check_destination(destination)
    sdk_header = validate_header(header)
    inputs = {'lib/libmmengine.a': archive, 'include/libmmengine.h': header,
              'include/graal_isolate.h': sdk_header}
    for directory, names in ((clib_dir, CLIBS), (jdk_lib_dir, JDKLIBS)):
        inputs.update({f'lib/lib{name}.a': directory / f'lib{name}.a' for name in names})
    files = {}
    for name, source in sorted(inputs.items()):
        if not source.is_file() or not source.stat().st_size:
            raise ValueError(f'Missing input: {source}')
        entry = {'source': str(source.resolve()), 'sha256': digest(source)}
        if name.endswith('.a'):
            entry['inspection'] = validate_archive(source, engine=source == archive)
        if digest(source) != entry['sha256']:
            raise ValueError(f'Input changed during inspection: {source}')
        files[name] = entry
    manifest = {'schema': 1, 'files': files,
                'validation': 'Archive tags, exported symbols and header shape only; '
                              'no link, runtime, gameplay or capability evidence.'}
    if destination.exists():
        if verify_installed(destination) != manifest:
            raise ValueError('Destination differs; refusing to overwrite existing native inputs')
        return manifest
    if apply:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.mkdir()  # Exclusive ownership; never merge or replace a tree.
        for name, source in inputs.items():
            target = destination / name
            target.parent.mkdir(exist_ok=True)
            with source.open('rb') as src, target.open('xb') as dst:
                shutil.copyfileobj(src, dst)
            if digest(target) != files[name]['sha256']:
                raise ValueError(f'Input changed while copying: {source}; staging is incomplete')
        with (destination / 'manifest.json').open('x') as stream:
            json.dump(manifest, stream, indent=2, sort_keys=True)
            stream.write('\n')
        verify_installed(destination)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('archive', 'header', 'clib-dir', 'jdk-lib-dir'):
        parser.add_argument('--' + name, type=Path)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--verify-installed', action='store_true')
    args = parser.parse_args()
    inputs = (args.archive, args.header, args.clib_dir, args.jdk_lib_dir)
    if args.verify_installed:
        if any(inputs) or args.apply:
            parser.error('--verify-installed cannot be combined with input or apply options')
    elif not all(inputs):
        parser.error('--archive, --header, --clib-dir and --jdk-lib-dir are all required')
    try:
        result = verify_installed() if args.verify_installed else prepare(*inputs, apply=args.apply)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Native preparation refused: {error}\n')
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
