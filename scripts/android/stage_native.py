#!/usr/bin/env python3
"""Stage real Android ELF output and paired ABI headers; reject an empty/probe build.

The staged libmmengine.so is stripped (llvm-strip --strip-unneeded keeps the dynamic symbols JNI
and dlopen use); the manifest and verify_native.py hash that stripped file. The unstripped
library is kept in build_output/android/unstripped/ for the workflow to upload for symbolication.
"""
import hashlib
import json
import mmap
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

ENTRY_POINTS = ['mm_engine_request', 'mm_engine_free', 'mm_engine_shutdown_v2', 'graal_create_isolate']
# Dynamic tags: plain and Android-packed (lld --pack-dyn-relocs=android) relocation tables.
DT_NULL, DT_RELA, DT_RELASZ, DT_RELRSZ, DT_RELR = 0, 7, 8, 35, 36
DT_ANDROID_RELA, DT_ANDROID_RELASZ = 0x60000011, 0x60000012
# A Java class file: magic, minor version 0, major version 45 (1.1) to 69 (Java 25).
CLASS_FILE = re.compile(rb'\xca\xfe\xba\xbe\x00\x00\x00[\x2d-\x45]')


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''): h.update(chunk)
    return h.hexdigest()


def elf_sections(path):
    """{name: (type, offset, size)} from an ELF64 little-endian file's section headers."""
    with open(path, 'rb') as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
        if m[:6] != b'\x7fELF\x02\x01': raise ValueError('Not an ELF64 little-endian file: ' + str(path))
        shoff, = struct.unpack_from('<Q', m, 0x28)
        shentsize, shnum, shstrndx = struct.unpack_from('<HHH', m, 0x3a)
        headers = [struct.unpack_from('<IIQQQQ', m, shoff + i * shentsize) for i in range(shnum)]
        strings = headers[shstrndx][4]
        def name(offset):
            end = m.find(b'\0', strings + offset)
            return m[strings + offset:end].decode()
        return {name(h[0]): (h[1], h[4], h[5]) for h in headers if h[1] != 0}


def dynamic_tags(path):
    """{tag: value} from the .dynamic section."""
    kind, offset, size = elf_sections(path)['.dynamic']
    tags = {}
    with open(path, 'rb') as f:
        f.seek(offset); data = f.read(size)
    for tag, value in struct.iter_unpack('<qQ', data):
        if tag == DT_NULL: break
        tags.setdefault(tag, value)
    return tags


def class_files(path):
    """Java class files embedded in the image heap (.svm_heap), or in the whole file without one."""
    sections = elf_sections(path)
    with open(path, 'rb') as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
        start, size = (sections['.svm_heap'][1], sections['.svm_heap'][2]) if '.svm_heap' in sections else (0, len(m))
        return sum(1 for _ in CLASS_FILE.finditer(m, start, start + size))


def relocations(path):
    tags = dynamic_tags(path)
    return {'packedAndroidRelaBytes': tags.get(DT_ANDROID_RELASZ, 0), 'relaBytes': tags.get(DT_RELASZ, 0),
            'relrBytes': tags.get(DT_RELRSZ, 0), 'packed': DT_ANDROID_RELA in tags}


def peak_rss(log):
    """The native-image builder's 'Peak RSS' line from the build log, if present."""
    if not log.is_file(): return None
    found = re.findall(r'Peak RSS: ([0-9.]+\s*[KMGT]?B)', log.read_text(errors='replace'))
    return found[-1] if found else None


def check_library(ndk, library, provided):
    """Exported entry points, 16 KiB LOAD alignment, SONAME and resolvable imports."""
    symbols = subprocess.check_output([str(ndk/'llvm-nm'), '-D', '--defined-only', str(library)], text=True)
    for symbol in ENTRY_POINTS:
        if not any(line.split()[-1:] == [symbol] for line in symbols.splitlines()): raise ValueError('Missing exported definition: ' + symbol)
    layout = subprocess.check_output([str(ndk/'llvm-readelf'), '-lW', str(library)], text=True)
    loads = [line.split() for line in layout.splitlines() if line.strip().startswith('LOAD ')]
    if not loads or any(int(row[-1], 16) < 16384 for row in loads): raise ValueError('Engine LOAD segments are not 16 KiB aligned')
    dynamic = subprocess.check_output([str(ndk/'llvm-readelf'), '-dW', str(library)], text=True)
    if 'libmmengine.so' not in dynamic: raise ValueError('Expected a stable libmmengine.so SONAME')
    # A green link is not a loadable engine: Android resolves every symbol at dlopen, so
    # an undefined reference outside the declared DT_NEEDED set fails on the device only.
    unresolved = {line.split()[-1] for line in subprocess.check_output(
        [str(ndk/'llvm-nm'), '-D', '--undefined-only', str(library)], text=True).splitlines()
        if line.split() and '@' not in line.split()[-1]}
    # System zlib (already resolved for inflate). Save/resume checkpoints are gzip'd, which makes
    # the JDK Deflater reachable and adds its deflate entry points from the same library.
    system = {'crc32','inflate','inflateEnd','inflateInit2_','inflateReset','getgrgid_r','stderr',
              'deflate','deflateEnd','deflateInit2_','deflateParams','deflateReset','deflateSetDictionary'}
    missing = unresolved - provided - system
    if missing:
        raise ValueError('Engine has undefined symbols nothing provides: ' + repr(sorted(missing)))
    return layout, dynamic, symbols


def main():
    repo, build = map(lambda x: Path(x).resolve(), sys.argv[1:])
    ndk = Path(os.environ['ANDROID_NDK']) / 'toolchains/llvm/prebuilt/linux-x86_64/bin'
    out = repo / 'build_output/android'
    candidates = [p for p in (build / 'gluonfx').rglob('*') if p.is_file() and p.suffix in ('.so', '.dylib') and 'mmengine' in p.name]
    if len(candidates) != 1: raise ValueError('Expected exactly one full Android engine shared library: ' + repr(candidates))
    library = candidates[0]
    with library.open('rb') as f: header = f.read(20)
    if library.stat().st_size < 1024 * 1024 or header[:5] != b'\x7fELF\x02' or header[18:20] != b'\xb7\x00':
        raise ValueError('Not an ELF64 AArch64 engine library')
    stub = next(iter(sorted((build / 'awtstub').glob('libmmawtstub.so'))), None)
    if stub is None: raise ValueError('Missing the AWT stub the engine links against')
    provided = {line.split()[-1] for line in subprocess.check_output(
        [str(ndk/'llvm-nm'), '-D', '--defined-only', str(stub)], text=True).splitlines() if line.split()}
    check_library(ndk, library, provided)
    # Resources are only what native/resource-config.json names: no embedded .class files.
    embedded = class_files(library)
    sections = {name: size for name, (kind, offset, size) in elf_sections(library).items()}
    reloc = relocations(library)
    report = {'unstrippedBytes': library.stat().st_size, 'imageHeapBytes': sections.get('.svm_heap'),
              'textBytes': sections.get('.text'), 'classFilesInImageHeap': embedded, 'relocations': reloc,
              'peakBuilderRss': peak_rss(out / 'full-native.log'),
              'unstrippedSectionsOver1MiB': {n: s for n, s in sorted(sections.items()) if s > 1 << 20}}
    print('NATIVE-SIZE ' + json.dumps(report, sort_keys=True))
    if embedded: raise ValueError(f'The image heap embeds {embedded} Java class files as resources; see native/resource-config.json')
    if not reloc['packed']: raise ValueError('Expected Android-packed relocations (-Wl,--pack-dyn-relocs=android)')

    stage = repo / 'apps/android/native-artifact'; stage.mkdir(parents=True, exist_ok=False)
    include = stage / 'include'; include.mkdir()
    shipped = stage / 'libmmengine.so'
    # Dynamic symbols (JNI and dlopen entry points) survive --strip-unneeded; .symtab and debug go.
    subprocess.run([str(ndk/'llvm-strip'), '--strip-unneeded', '-o', str(shipped), str(library)], check=True)
    shutil.copyfile(stub, stage / 'libmmawtstub.so')
    layout, dynamic, symbols = check_library(ndk, shipped, provided)
    if '.symtab' in elf_sections(shipped): raise ValueError('The staged engine still has a static symbol table')
    report['strippedBytes'] = shipped.stat().st_size
    symbols_dir = out / 'unstripped'; symbols_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(library, symbols_dir / 'libmmengine.so')
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
            dynamic_headers = sorted(p.name for p in include.glob('*_dynamic.h') if declares_abi(p))
            raise ValueError('Expected exactly one static engine ABI header, found %r (dynamic variants present: %r)'
                             % ([p.name for p in static], dynamic_headers))
        shutil.copyfile(static[0], include/'libmmengine.h')
    if not declares_abi(include/'libmmengine.h'):
        raise ValueError('Staged libmmengine.h does not declare the full engine ABI')
    if not (include/'graal_isolate.h').exists(): raise ValueError('Missing paired isolate header')
    (stage/'elf-layout.txt').write_text(layout + '\n' + dynamic + '\n' + symbols)
    (stage/'size-report.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    shutil.copyfile(repo/'build_output/android/compiler-patch-manifest.json', stage/'compiler-patch-manifest.json')
    source = subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()
    manifest = {'schema':1, 'target':'android-arm64', 'sourceCommit':source,
                'files':{p.relative_to(stage).as_posix():digest(p) for p in sorted(stage.rglob('*')) if p.is_file()},
                'classSnapshotSha256':digest(build/'class-snapshot.sha256'),
                'unstrippedLibmmengineSha256':digest(symbols_dir/'libmmengine.so'),
                'upstream':json.loads((repo/'packages/ondevice-engine/upstream.lock.json').read_text()),
                'scope':'Full ELF AOT compilation/link verification; not APK or device execution'}
    (stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (symbols_dir/'symbols.json').write_text(json.dumps({'sourceCommit': source,
        'strippedLibmmengineSha256': manifest['files']['libmmengine.so'],
        'unstrippedLibmmengineSha256': manifest['unstrippedLibmmengineSha256']}, indent=2) + '\n')
    print(json.dumps(manifest,indent=2))
    print('NATIVE-SIZE ' + json.dumps(report, sort_keys=True))

if __name__ == '__main__': main()
