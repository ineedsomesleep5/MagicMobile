#!/usr/bin/env python3
"""Validate a same-repository native build artifact before linking the product.

This is source/artifact provenance, NOT native execution. A subsequent app commit
may reuse a completed engine build only if all engine/compiler inputs are equal.
Never accepts a probe, unsigned downloaded code update, or a foreign repository.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
ENGINE = 'packages/ondevice-engine/'
# Keep broad directories; do not accidentally omit new files inside them.
INPUT_PATHS = tuple(ENGINE + name for name in (
    'engine', 'native', 'patches', 'tools', 'upstream.lock.json',
    'scripts/build_jvm.sh', 'scripts/build_native_ios.sh',
    'scripts/prepare_upstream.py', 'scripts/generate_registry.py',
    'scripts/generate_native_metadata.py', 'scripts/setup_gluon_intel.sh',
    'scripts/prepare_gluon_far_calls.py', 'scripts/prepare_ios_orm.py',
    'scripts/prepare_native_orm.py', 'scripts/test_ios_toolchain.sh', 'scripts/test_ios_link.sh',
))
REQUIRED_FILES = {
    'libmmengine.a', 'include/io.magicmobile.nativebridge.ioslibrarymain.h', 'include/graal_isolate.h',
    'class-snapshot.sha256', 'reflect-config.json', 'registry-report.json',
    'commit.txt', 'compiler-patch-manifest.json',
} | {'clib/lib' + name + '.a' for name in ('jvm', 'libchelper', 'ffi', 'darwin')} | {
    'jdk/lib' + name + '.a' for name in ('java', 'nio', 'zip', 'net', 'prefs', 'fdlibm', 'j2pkcs11', 'jaas', 'extnet')
}


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def validate_receipt(root: Path, expected_commit: str) -> dict[str, str]:
    if not re.fullmatch(r'[a-f0-9]{40}', expected_commit):
        raise ValueError('An exact engine source commit is required')
    if root.is_symlink() or any(p.is_symlink() for p in root.rglob('*')):
        raise ValueError('Symlinks are not accepted in build artifacts')
    if (root / 'commit.txt').read_text().strip() != expected_commit:
        raise ValueError('Native artifact source differs from the selected run')
    hashes: dict[str, str] = {}
    for line in (root / 'SHA256SUMS').read_text().splitlines():
        match = re.fullmatch(r'([a-f0-9]{64})  (?:\./)?(.+)', line)
        if not match:
            raise ValueError('Invalid artifact hash record')
        checksum, name = match.groups()
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or '\\' in name or name in hashes:
            raise ValueError('Unsafe/duplicate artifact hash path')
        if str(path) != name or name == 'SHA256SUMS':
            raise ValueError('Noncanonical artifact hash path')
        file = root / name
        if not file.is_file() or digest(file) != checksum:
            raise ValueError('Native artifact bytes differ: ' + name)
        hashes[name] = checksum
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
    # The existing publisher appends only SCOPE.txt after writing its hashes.
    # Every byte used for linking or provenance must already be hash-covered.
    if not REQUIRED_FILES <= hashes.keys() or actual - hashes.keys() - {'SHA256SUMS', 'SCOPE.txt'}:
        raise ValueError('Missing required inputs or unhashed artifact files')
    return hashes


def source_identity(repo: Path, source: str) -> dict:
    if not re.fullmatch(r'[a-f0-9]{40}', source):
        raise ValueError('Invalid engine commit')
    def git(*args):
        return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()
    head = git('rev-parse', 'HEAD')
    # Include tracked paths under the engine package except presentation/client,
    # tests and documentation. This intentionally also rejects changes to other
    # build scripts instead of guessing whether they matter.
    names = git('ls-tree', '-r', '--name-only', source, '--', ENGINE).splitlines()
    names += git('ls-tree', '-r', '--name-only', head, '--', ENGINE).splitlines()
    excludes = ('swift/', 'tests/', 'docs/', 'evidence/')
    extension_excludes = ('.md', '.txt')
    selected = set(INPUT_PATHS)
    # Source and compiler directories are guarded above. Script changes are
    # guarded except the explicit post-build/product verifiers and test drivers.
    for name in names:
        relative = name[len(ENGINE):]
        if relative.startswith(excludes):
            continue
        if relative.startswith('scripts/'):
            base = Path(relative).name
            if base.startswith(('test_', 'verify_', 'build_issue4_', 'wait_issue4_', 'download_issue4_')):
                continue
            if base in ('prepare_ios_app_native.py', 'install_into_magicmobile.py', 'check_upstream.py'):
                continue
        elif relative.endswith(extension_excludes) or relative in ('implementation-status.json', 'SHA256SUMS.txt'):
            continue
        selected.add(name)
    changes = git('diff', '--name-only', source, head, '--', *sorted(selected))
    if changes:
        raise ValueError('App and native artifact have different engine inputs:\n' + changes)
    subprocess.run(['git', '-C', str(repo), 'diff', '--quiet', 'HEAD', '--'], check=True)
    tree = git('ls-tree', '-r', source, '--', *sorted(selected))
    return {'engineSourceCommit': source, 'appSourceCommit': head,
            'equivalentInputTreeSHA256': hashlib.sha256(tree.encode()).hexdigest(),
            'comparedPaths': sorted(selected)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--engine-commit', required=True)
    parser.add_argument('--run-id', type=int, required=True)
    parser.add_argument('--artifact-id', type=int, required=True)
    parser.add_argument('--artifact-digest', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.run_id <= 0 or args.artifact_id <= 0 or not re.fullmatch('sha256:[a-f0-9]{64}', args.artifact_digest):
            raise ValueError('Invalid GitHub artifact identity')
        hashes = validate_receipt(args.directory, args.engine_commit)
        identity = source_identity(ROOT, args.engine_commit)
        compiler = json.loads((args.directory / 'compiler-patch-manifest.json').read_text())
        if compiler.get('patchSha256') != digest(ROOT / ENGINE / 'native/gluon/compiler-patches/far-calls.patch'):
            raise ValueError('Artifact compiler patch differs from source')
        receipt = {'schema': 1, 'repository': 'ineedsomesleep5/MagicMobile', **identity,
                   'workflowRunID': args.run_id, 'artifactID': args.artifact_id,
                   'artifactDigest': args.artifact_digest, 'files': hashes,
                   'scope': 'Source and artifact provenance only; not native runtime acceptance'}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
        print(json.dumps({key: receipt[key] for key in ('engineSourceCommit', 'appSourceCommit', 'artifactID', 'scope')}, indent=2))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(2, 'Native candidate refused: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
