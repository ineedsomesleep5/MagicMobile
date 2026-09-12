#!/usr/bin/env python3
"""Verify a full-engine CI candidate, then stage the paired inputs. Never sign/run.

The required source commit must come from the successful producer workflow, not
from a guessed filename. Checksums establish input consistency, not gameplay.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''): h.update(block)
    return h.hexdigest()


def verify_checksum_manifest(directory: Path) -> dict[str, str]:
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError('Candidate must be a real directory')
    for path in directory.rglob('*'):
        if path.is_symlink(): raise ValueError(f'Symlink in candidate: {path.name}')
    hashes = {}
    for line in (directory / 'SHA256SUMS').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  (?:\./)?(.+)', line)
        if not match: raise ValueError('Malformed candidate checksum line')
        digest, name = match.groups()
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or str(path) != name or '\\' in name or name in hashes:
            raise ValueError('Unsafe or duplicate candidate checksum path')
        file = directory / name
        if not file.is_file() or sha(file) != digest: raise ValueError(f'Candidate checksum mismatch: {name}')
        hashes[name] = digest
    actual = {p.relative_to(directory).as_posix() for p in directory.rglob('*') if p.is_file()}
    # The first producer wrote its informational scope after SHA256SUMS.
    # It is never parsed as evidence. All executable/build inputs must be covered.
    if actual - {'SHA256SUMS', 'SCOPE.txt'} != set(hashes) - {'SCOPE.txt'}:
        raise ValueError('Candidate file set is not completely covered by checksums')
    return hashes


def verify(directory: Path, expected_source: str, *, repo: Path = REPO) -> dict:
    if not re.fullmatch(r'[0-9a-f]{40}', expected_source): raise ValueError('Expected a full source commit SHA')
    hashes = verify_checksum_manifest(directory)
    required = {'commit.txt', 'libmmengine.a', 'include/libmmengine.h', 'include/graal_isolate.h',
                'compiler-patch-manifest.json', 'class-snapshot.sha256', 'reflect-config.json', 'registry-report.json'}
    if not required.issubset(hashes): raise ValueError('Missing checksummed full-engine build inputs')
    if (directory / 'commit.txt').read_text().strip() != expected_source:
        raise ValueError('Native candidate source commit mismatch')
    engine = repo / 'packages/ondevice-engine'
    lock = json.loads((engine / 'upstream.lock.json').read_text())
    catalogue = json.loads((repo / 'apps/ios/MagicMobile/Resources/ondevice-catalogue.json').read_text())
    registry = json.loads((directory / 'registry-report.json').read_text())
    if catalogue['upstreamCommit'] != lock['commit'] or registry.get('registryHash') != catalogue['catalogueHash']:
        raise ValueError('Native registry and bundled iOS catalogue do not match')
    if sha(directory / 'registry-report.json') != catalogue['sourceRegistrySHA256']:
        raise ValueError('Full registry report does not match reviewed iOS export')
    compiler = json.loads((directory / 'compiler-patch-manifest.json').read_text())
    patch_root = engine / 'native/gluon/compiler-patches'
    if compiler.get('officialArchiveSha256') != '61084c8e12a500e5019657d3160fa3394cd8230a0e780718a051d59028fbfb99':
        raise ValueError('Unknown compiler distribution')
    for key, path in [('patchSha256', patch_root/'far-calls.patch'),
                      ('sourceManifestSha256', patch_root/'upstream-sources.json'),
                      ('plannerSha256', patch_root/'src/com/oracle/svm/hosted/image/FarCallPlanner.java')]:
        if compiler.get(key) != sha(path): raise ValueError(f'Compiler backport mismatch: {key}')
    if not compiler.get('replacementClasses') or not re.fullmatch(r'[0-9a-f]{64}', compiler.get('patchedSvmJarSha256', '')):
        raise ValueError('Missing compiled compiler-backport identity')
    # Frozen JVM input identities, not a count claiming every card was played.
    lines = (directory / 'class-snapshot.sha256').read_text().splitlines()
    if not lines or any(not re.fullmatch(r'[0-9a-f]{64}  (?:core|engine)/[^\r\n]+\.class', line) for line in lines):
        raise ValueError('Malformed frozen JVM class manifest')
    return {
        'schema': 1, 'kind': 'xmage-full-ios-arm64-candidate', 'sourceCommit': expected_source,
        'upstreamCommit': lock['commit'], 'catalogueHash': catalogue['catalogueHash'],
        'archiveSha256': hashes['libmmengine.a'], 'headerSha256': hashes['include/libmmengine.h'],
        'candidateChecksumsSha256': sha(directory/'SHA256SUMS'),
        'compilerManifestSha256': hashes['compiler-patch-manifest.json'],
        'classSnapshotSha256': hashes['class-snapshot.sha256'],
        'cardFactories': registry['cardClasses'], 'setClasses': registry['setClasses'],
        'nativeExecutionVerified': False,
        'scope': 'paired build-input consistency; native execution and phone gameplay remain separate'
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--stage', action='store_true', help='Stage verified inputs atomically; never overwrite a different install')
    parser.add_argument('--destination', type=Path, default=REPO/'apps/ios/NativeEngine')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    try:
        report = verify(args.directory, args.source_commit)
        if args.stage:
            from prepare_ios_app_native import prepare
            prepare(args.directory/'libmmengine.a', args.directory/'include/libmmengine.h',
                    args.directory/'clib', args.directory/'jdk', args.destination, apply=True)
        text = json.dumps(report, indent=2, sort_keys=True) + '\n'
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            with args.report.open('x') as output: output.write(text)
        print(text, end='')
        return 0
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f'Native candidate rejected: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__': raise SystemExit(main())
