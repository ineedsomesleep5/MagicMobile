#!/usr/bin/env python3
"""Stage real Android ELF output and paired ABI headers; reject an empty/probe build."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''): h.update(chunk)
    return h.hexdigest()


def main():
    repo, build = map(lambda x: Path(x).resolve(), sys.argv[1:])
    ndk = Path(os.environ['ANDROID_NDK']) / 'toolchains/llvm/prebuilt/linux-x86_64/bin'
    candidates = [p for p in (build / 'gluonfx').rglob('*') if p.is_file() and p.suffix in ('.so', '.dylib') and 'mmengine' in p.name]
    if len(candidates) != 1: raise ValueError('Expected exactly one full Android engine shared library: ' + repr(candidates))
    library = candidates[0]
    with library.open('rb') as f: header = f.read(20)
    if library.stat().st_size < 1024 * 1024 or header[:5] != b'\x7fELF\x02' or header[18:20] != b'\xb7\x00':
        raise ValueError('Not an ELF64 AArch64 engine library')
    symbols = subprocess.check_output([str(ndk/'llvm-nm'), '-D', '--defined-only', str(library)], text=True)
    for symbol in ['mm_engine_request', 'mm_engine_free', 'mm_engine_shutdown_v2', 'graal_create_isolate']:
        if not any(line.split()[-1:] == [symbol] for line in symbols.splitlines()): raise ValueError('Missing exported definition: ' + symbol)
    layout = subprocess.check_output([str(ndk/'llvm-readelf'), '-lW', str(library)], text=True)
    loads = [line.split() for line in layout.splitlines() if line.strip().startswith('LOAD ')]
    if not loads or any(int(row[-1], 16) < 16384 for row in loads): raise ValueError('Engine LOAD segments are not 16 KiB aligned')
    dynamic = subprocess.check_output([str(ndk/'llvm-readelf'), '-dW', str(library)], text=True)
    if 'libmmengine.so' not in dynamic: raise ValueError('Expected a stable libmmengine.so SONAME')
    stage = repo / 'apps/android/native-artifact'; stage.mkdir(parents=True, exist_ok=False)
    include = stage / 'include'; include.mkdir()
    shutil.copyfile(library, stage / 'libmmengine.so')
    found = {}
    for path in (build/'gluonfx').rglob('*.h'):
        if path.name in found and digest(found[path.name]) != digest(path): raise ValueError('Conflicting generated headers')
        found[path.name] = path
    for name, path in found.items(): shutil.copyfile(path, include/name)
    # Graal emits both `<entrypoint>.h` and `<entrypoint>_dynamic.h`; the dynamic variant
    # declares the same symbols as function-pointer typedefs for runtime loading, so a
    # substring search matches both. The C ABI we compile against is the static header, so
    # select it the same way the iOS staging does: by name, not by scanning contents.
    ENTRIES = ('mm_engine_request', 'mm_engine_free', 'mm_engine_shutdown_v2')
    def declares_abi(path):
        text = path.read_text()
        return all(entry in text for entry in ENTRIES)
    if not (include/'libmmengine.h').exists():
        static = [p for p in sorted(include.glob('*.h'))
                  if not p.stem.endswith('_dynamic') and declares_abi(p)]
        if len(static) != 1:
            dynamic = sorted(p.name for p in include.glob('*_dynamic.h') if declares_abi(p))
            raise ValueError('Expected exactly one static engine ABI header, found %r (dynamic variants present: %r)'
                             % ([p.name for p in static], dynamic))
        shutil.copyfile(static[0], include/'libmmengine.h')
    if not declares_abi(include/'libmmengine.h'):
        raise ValueError('Staged libmmengine.h does not declare the full engine ABI')
    if not (include/'graal_isolate.h').exists(): raise ValueError('Missing paired isolate header')
    (stage/'elf-layout.txt').write_text(layout + '\n' + dynamic + '\n' + symbols)
    shutil.copyfile(repo/'build_output/android/compiler-patch-manifest.json', stage/'compiler-patch-manifest.json')
    manifest = {'schema':1, 'target':'android-arm64', 'sourceCommit':subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),
                'files':{p.relative_to(stage).as_posix():digest(p) for p in sorted(stage.rglob('*')) if p.is_file()},
                'classSnapshotSha256':digest(build/'class-snapshot.sha256'),
                'upstream':json.loads((repo/'packages/ondevice-engine/upstream.lock.json').read_text()),
                'scope':'Full ELF AOT compilation/link verification; not APK or device execution'}
    (stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest,indent=2))

if __name__ == '__main__': main()
