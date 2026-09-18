#!/usr/bin/env python3
"""Stage the actual full Android archive and paired generated headers, not iOS/probe files."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    repo, build = map(lambda x: Path(x).resolve(), sys.argv[1:])
    candidates = list((build / 'gluonfx').glob('*-android/gvm/libmmengine.a'))
    if len(candidates) != 1:
        raise ValueError('Expected exactly one Android full engine archive')
    archive = candidates[0]
    if archive.stat().st_size < 1024 * 1024:
        raise ValueError('Unexpectedly small engine archive; not accepting a probe')
    symbols = subprocess.check_output(['nm', '-g', str(archive)], text=True)
    for symbol in ['mm_engine_request', 'mm_engine_free', 'mm_engine_shutdown_v2', 'graal_create_isolate']:
        if not any(line.split()[-2:] == ['T', symbol] for line in symbols.splitlines() if len(line.split()) >= 2):
            raise ValueError('Missing actual native definition: ' + symbol)
    stage = repo / 'apps/android/native-artifact'
    stage.mkdir(parents=True, exist_ok=False)
    headers = stage / 'include'
    headers.mkdir()
    shutil.copyfile(archive, stage / archive.name)
    found = {}
    for path in archive.parent.rglob('*.h'):
        if path.name in found and digest(found[path.name]) != digest(path):
            raise ValueError('Conflicting generated native headers')
        found[path.name] = path
    for name, path in found.items():
        shutil.copyfile(path, headers / name)
    if not (headers / 'libmmengine.h').exists():
        matches = [p for p in headers.glob('*.h') if 'mm_engine_request' in p.read_text()]
        if len(matches) != 1:
            raise ValueError('Missing generated mm_engine_request ABI header')
        shutil.copyfile(matches[0], headers / 'libmmengine.h')
    if not (headers / 'graal_isolate.h').exists():
        raise ValueError('Missing paired Graal isolate header')
    vmone = list(archive.parent.glob('libvmone.a'))
    for path in vmone:
        shutil.copyfile(path, stage / path.name)
    files = {p.relative_to(stage).as_posix(): digest(p) for p in sorted(stage.rglob('*')) if p.is_file()}
    manifest = {'schema': 1, 'target': 'android-arm64', 'sourceCommit': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
                'files': files, 'classSnapshotSha256': digest(build / 'class-snapshot.sha256'),
                'scope': 'Full AOT compilation only; no device acceptance or APK signing',
                'upstream': json.loads((repo / 'packages/ondevice-engine/upstream.lock.json').read_text())}
    (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))

if __name__ == '__main__':
    main()
