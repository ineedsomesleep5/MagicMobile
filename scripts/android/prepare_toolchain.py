#!/usr/bin/env python3
"""Prepare a private Linux Gluon compiler; never mutate the iOS SDK or source."""
import argparse
import importlib.util
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import urllib.request
from toolchain_archive import extract_toolchain

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / 'packages/ondevice-engine'
ARCHIVE_SHA256 = '70df79831e4e55289414b4e9c4ab78b74e31d7b7db7ba70cfff86ab8f9f8d4ef'
TOOLCHAIN = 'graalvm-svm-java17-linux-gluon-22.1.0.1-Final'
URL = f'https://github.com/gluonhq/graal/releases/download/gluon-22.1.0.1-Final/{TOOLCHAIN}.tar.gz'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--result-file', type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        parser.error('The reviewed Android cross-compiler requires Linux x86_64')
    if args.result_file.exists():
        parser.error('Refusing to overwrite another build result')
    spec = importlib.util.spec_from_file_location('far_calls', ENGINE / 'scripts/prepare_gluon_far_calls.py')
    shared = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(shared)
    root = ROOT / 'build_output/android/toolchains'
    root.mkdir(parents=True, exist_ok=True)
    archive = root / (TOOLCHAIN + '.tar.gz')
    if not archive.exists():
        temporary = archive.with_suffix('.download')
        with urllib.request.urlopen(URL, timeout=120) as response, temporary.open('xb') as output:
            shutil.copyfileobj(response, output)
        shared.verify(temporary, ARCHIVE_SHA256)
        temporary.rename(archive)
    shared.verify(archive, ARCHIVE_SHA256)
    build = Path(tempfile.mkdtemp(prefix='compiler-', dir=root))
    omitted = extract_toolchain(archive, build)
    shutil.copyfile(build / 'archive-omissions.json', ROOT / 'build_output/android/archive-omissions.json')
    print('Omitted unused producer links:', json.dumps(omitted), flush=True)
    home = build / TOOLCHAIN
    release = (home / 'release').read_text().splitlines()
    for line in ['GRAALVM_VERSION="22.1.0.1"', 'JAVA_VERSION="17.0.3"', 'VENDOR=Gluon', 'OS_NAME="Linux"', 'OS_ARCH="x86_64"']:
        if line not in release:
            raise ValueError('Unreviewed native toolchain release')
    sources_root = build / 'sources'
    sources_root.mkdir()
    sources = shared.patch_sources(sources_root)
    planner = sources_root / 'FarCallPlanner.java'
    shutil.copyfile(shared.PATCH_ROOT / 'src/com/oracle/svm/hosted/image/FarCallPlanner.java', planner)
    sources.append(planner)
    classes = build / 'classes'
    classes.mkdir()
    jar = home / 'lib/svm/builder/svm.jar'
    original = shared.sha256(jar)
    command = [str(home / 'bin/javac'), '-J-Xmx768m', '-proc:none', '-source', '17', '-target', '17',
               '--add-modules', 'org.graalvm.sdk,jdk.internal.vm.compiler,jdk.internal.vm.ci',
               '--add-reads', 'jdk.internal.vm.compiler=jdk.internal.vm.ci',
               '--add-reads', 'jdk.internal.vm.compiler=org.graalvm.sdk']
    command += shared.module_exports(home / 'bin/java')
    command += ['--add-exports', 'java.base/jdk.internal.misc=ALL-UNNAMED', '-cp', str(home / 'lib/svm/builder/*'), '-d', str(classes)]
    command += list(map(str, sources))
    (build / 'javac-arguments.json').write_text(json.dumps(command, indent=2))
    subprocess.run(command, check=True)
    replacements = shared.replace_classes(jar, classes)
    manifest = dict(schema=1, platform='linux-host/android-target', officialArchiveSha256=ARCHIVE_SHA256,
                    originalSvmJarSha256=original, patchedSvmJarSha256=shared.sha256(jar),
                    patchSha256=shared.sha256(shared.PATCH_ROOT / 'far-calls.patch'),
                    sourceManifestSha256=shared.sha256(shared.PATCH_ROOT / 'upstream-sources.json'),
                    replacementClasses=replacements, javaHome=str(home), archiveOmissions=omitted)
    (build / 'compiler-patch-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    shutil.copyfile(build / 'compiler-patch-manifest.json', ROOT / 'build_output/android/compiler-patch-manifest.json')
    args.result_file.parent.mkdir(parents=True, exist_ok=True)
    with args.result_file.open('x') as output:
        output.write(str(home) + '\n')
    print('Prepared checksum-pinned Linux compiler; not an Android execution result.')

if __name__ == '__main__':
    main()
