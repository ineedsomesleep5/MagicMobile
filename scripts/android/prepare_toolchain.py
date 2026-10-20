#!/usr/bin/env python3
"""Prepare a private Linux Gluon compiler and Android static JDK; never mutate the iOS SDK or source.

Pins: packages/ondevice-engine/native/gluon/toolchain.json. GraalVM 24.1 places AArch64 direct-call
trampolines itself (AArch64HostedTrampolineSupport), so the compiler is used as released; the 22.1
far-call backport is retired.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import platform
import shutil
import tempfile
import urllib.request
import zipfile
from toolchain_archive import extract_toolchain

ROOT = Path(__file__).resolve().parents[2]
PINS = json.loads((ROOT / 'packages/ondevice-engine/native/gluon/toolchain.json').read_text())
GRAALVM = PINS['graalvm']['archives']['linux-amd64']
STATIC_JDK = PINS['static_jdk']['archives']['android-linux-aarch64']
TOOLCHAIN = GRAALVM['name'].removesuffix('.tar.gz')


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def fetch(url, archive, expected):
    """Download once into the owned toolchain directory; refuse any other bytes."""
    if not archive.exists():
        temporary = archive.with_suffix('.download')
        temporary.unlink(missing_ok=True)
        with urllib.request.urlopen(url, timeout=120) as response, temporary.open('xb') as output:
            shutil.copyfileobj(response, output)
        if sha256(temporary) != expected:
            raise ValueError('Checksum mismatch: ' + url)
        temporary.rename(archive)
    if archive.is_symlink() or sha256(archive) != expected:
        raise ValueError('Checksum/type mismatch: ' + str(archive))


def extract_static_jdk(archive, destination):
    """The vmone archive holds exactly lib/libvmone.a."""
    with zipfile.ZipFile(archive) as source:
        files = [m for m in source.infolist() if not m.is_dir()]
        if [m.filename for m in files] != ['lib/libvmone.a'] or files[0].file_size > 64 * 1024 * 1024:
            raise ValueError('Unexpected static JDK archive members: ' + repr([m.filename for m in files]))
        library = destination / PurePosixPath(files[0].filename)
        library.parent.mkdir(parents=True)
        with source.open(files[0]) as stream, library.open('xb') as output:
            shutil.copyfileobj(stream, output)
    return library


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--result-file', type=Path, required=True, help='receives the GraalVM home')
    parser.add_argument('--static-libs-file', type=Path, required=True, help='receives the libvmone.a directory')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        parser.error('The reviewed Android cross-compiler requires Linux x86_64')
    if args.result_file.exists() or args.static_libs_file.exists():
        parser.error('Refusing to overwrite another build result')
    root = ROOT / 'build_output/android/toolchains'
    root.mkdir(parents=True, exist_ok=True)
    archive = root / GRAALVM['name']
    fetch(PINS['graalvm']['url'] + GRAALVM['name'].replace('+', '%2B'), archive, GRAALVM['sha256'])
    static_archive = root / STATIC_JDK['name']
    fetch(PINS['static_jdk']['url'] + STATIC_JDK['name'], static_archive, STATIC_JDK['sha256'])
    build = Path(tempfile.mkdtemp(prefix='compiler-', dir=root))
    extract_toolchain(archive, build)
    home = build / TOOLCHAIN
    release = (home / 'release').read_text().splitlines()
    for line in PINS['graalvm']['release_lines'] + ['OS_NAME="Linux"', 'OS_ARCH="x86_64"']:
        if line not in release:
            raise ValueError('Unreviewed native toolchain release: missing ' + line)
    if 'substratevm:' + PINS['graalvm']['substratevm_commit'] not in (home / 'release').read_text():
        raise ValueError('Unreviewed native toolchain release: unexpected substratevm commit')
    # The Android build passes --libc=bionic (errno through __errno). The driver then puts clibraries/<host>/bionic
    # on the library path (Substrate 0.0.65 passes no --target) and fails when it is missing. Substrate writes a
    # relocatable object and links it itself with libvmone.a, so the directory only has to exist.
    (home / 'lib/svm/clibraries/linux-amd64/bionic').mkdir()
    library = extract_static_jdk(static_archive, build / 'static-jdk')
    manifest = dict(schema=2, platform='linux-host/android-target', graalvmRelease=PINS['graalvm']['release'],
                    officialArchiveSha256=GRAALVM['sha256'], svmJarSha256=sha256(home / 'lib/svm/builder/svm.jar'),
                    compilerPatches=[], farCalls='upstream AArch64HostedTrampolineSupport (GraalVM 24.1)',
                    gluonfxPlugin=PINS['gluonfx']['plugin'], substrate=PINS['gluonfx']['substrate'],
                    staticJdkRelease=PINS['static_jdk']['release'], staticJdkArchiveSha256=STATIC_JDK['sha256'],
                    libvmoneSha256=sha256(library), javaHome=str(home))
    (build / 'compiler-patch-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    shutil.copyfile(build / 'compiler-patch-manifest.json', ROOT / 'build_output/android/compiler-patch-manifest.json')
    args.result_file.parent.mkdir(parents=True, exist_ok=True)
    with args.result_file.open('x') as output:
        output.write(str(home) + '\n')
    with args.static_libs_file.open('x') as output:
        output.write(str(library.parent) + '\n')
    print('Prepared checksum-pinned Linux compiler and Android static JDK; not an Android execution result.')

if __name__ == '__main__':
    main()
