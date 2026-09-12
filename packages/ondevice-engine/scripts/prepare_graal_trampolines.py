#!/usr/bin/env python3
"""Backport long ARM64 call veneers into the owned, checksum-pinned Gluon builder.

This changes a build-tool class, never XMage rules or the phone's Java sources.
The Oracle vm-22.1.0 input is blob-checked. The distribution tarball is SHA-256
checked, and only its exact svm.jar (or our manifest-verified prior patch) is
accepted. The generated upstream file retains its GPLv2/Classpath notice.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE_BLOB = 'f9ba40a80afae95789fb685f268c1d80c5852570'
DISTRIBUTION_SHA = '61084c8e12a500e5019657d3160fa3394cd8230a0e780718a051d59028fbfb99'
DISTRIBUTION = 'graalvm-svm-java17-darwin-gluon-22.1.0.1-Final'
HELPER = ROOT / 'native/gluon/compiler-patch/MagicMobileTrampolineLayout.java'
PACKAGE = 'com/oracle/svm/hosted/image/'

LAYOUT = r'''
    /* MagicMobile builder-only backport of the append-only ARM64 veneer design.
     * See Graal vm-22.2.0 LIRNativeImageCodeCache / AArch64HostedTrampolineSupport.
     * Original code, card registry, GC maps and method bodies are not pruned.
     */
    private final Map<HostedMethod, Map<HostedMethod, Integer>> mmTrampolines = new HashMap<>();

    private void mmLayoutAarch64() {
        List<HostedMethod> methods = new java.util.ArrayList<>(compilations.keySet());
        Map<HostedMethod, Integer> indices = new java.util.IdentityHashMap<>();
        int n = methods.size();
        for (int i = 0; i < n; i++) indices.put(methods.get(i), i);
        int[] sizes = new int[n];
        int[][] targets = new int[n][], offsets = new int[n][];
        for (int i = 0; i < n; i++) {
            CompilationResult result = compilations.get(methods.get(i));
            sizes[i] = result.getTargetCodeSize();
            List<Call> calls = new java.util.ArrayList<>();
            for (Infopoint point : result.getInfopoints()) {
                if (point instanceof Call && ((Call) point).direct) calls.add((Call) point);
            }
            targets[i] = new int[calls.size()]; offsets[i] = new int[calls.size()];
            for (int j = 0; j < calls.size(); j++) {
                Integer targetIndex = indices.get((HostedMethod) calls.get(j).target);
                VMError.guarantee(targetIndex != null, "Direct call has no compiled target");
                targets[i][j] = targetIndex; offsets[i][j] = calls.get(j).pcOffset;
            }
        }
        int limit = Integer.getInteger("magicmobile.aarch64.maxDirectCallDistance",
                                       MagicMobileTrampolineLayout.ARM64_CALL_LIMIT);
        MagicMobileTrampolineLayout.Layout layout = MagicMobileTrampolineLayout.plan(
            sizes, targets, offsets, SubstrateOptions.codeAlignment(), limit);
        int count = 0;
        for (int i = 0; i < n; i++) {
            HostedMethod method = methods.get(i);
            method.setCodeAddressOffset(layout.starts[i]);
            compilationsByStart.put(layout.starts[i], compilations.get(method));
            if (!layout.veneers[i].isEmpty()) {
                Map<HostedMethod, Integer> redirects = new java.util.LinkedHashMap<>();
                for (Map.Entry<Integer, Integer> veneer : layout.veneers[i].entrySet()) {
                    redirects.put(methods.get(veneer.getKey()), veneer.getValue()); count++;
                }
                mmTrampolines.put(method, redirects);
            }
        }
        codeCacheSize = layout.size;
        System.out.printf("MAGICMOBILE_AARCH64_TRAMPOLINES count=%d codeBytes=%d passes=%d limit=%d%n",
                          count, codeCacheSize, layout.passes, limit);
        buildRuntimeMetadata(new MethodPointer(methods.get(0)), WordFactory.unsigned(codeCacheSize));
    }

    private byte[] mmVeneer(HostedMethod destination, int position) {
        org.graalvm.compiler.asm.aarch64.AArch64MacroAssembler assembler =
            new org.graalvm.compiler.asm.aarch64.AArch64MacroAssembler(target);
        CompilationResult result = new CompilationResult("MagicMobile ARM64 veneer");
        assembler.setCodePatchingAnnotationConsumer(
            com.oracle.svm.core.graal.code.PatchConsumerFactory.HostedPatchConsumerFactory.factory().newConsumer(result));
        try (org.graalvm.compiler.asm.aarch64.AArch64MacroAssembler.ScratchRegister scratch = assembler.getScratchRegister()) {
            assembler.adrpAdd(scratch.getRegister());
            assembler.jmp(scratch.getRegister());
        }
        byte[] bytes = assembler.close(true);
        VMError.guarantee(bytes.length == MagicMobileTrampolineLayout.VENEER_BYTES, "Unexpected veneer size");
        VMError.guarantee(result.getCodeAnnotations().size() == 1, "Unexpected veneer patch count");
        HostedPatcher patch = (HostedPatcher) result.getCodeAnnotations().get(0);
        patch.patch(position, destination.getCodeAddressOffset() - position, bytes);
        return bytes;
    }
'''

WRITE = r'''
        ByteBuffer bytes = buffer.getByteBuffer();
        int origin = bytes.position();
        for (Entry<HostedMethod, CompilationResult> entry : compilations.entrySet()) {
            HostedMethod method = entry.getKey();
            CompilationResult result = entry.getValue();
            bytes.position(origin + method.getCodeAddressOffset());
            bytes.put(result.getTargetCode(), 0, result.getTargetCodeSize());
            Map<HostedMethod, Integer> veneers = mmTrampolines.get(method);
            if (veneers != null) {
                for (Map.Entry<HostedMethod, Integer> veneer : veneers.entrySet()) {
                    int position = origin + veneer.getValue();
                    VMError.guarantee(bytes.position() <= position, "Overlapping veneer");
                    while (bytes.position() < position) bytes.put(CODE_FILLER_BYTE);
                    bytes.put(mmVeneer(veneer.getKey(), veneer.getValue()));
                }
            }
            while ((bytes.position() - origin) % SubstrateOptions.codeAlignment() != 0) bytes.put(CODE_FILLER_BYTE);
        }
        bytes.position(origin);
'''


def sha(data):
    return hashlib.sha256(data).hexdigest()


def source_blob(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Pinned compiler source anchor mismatch: ' + old[:70])
    return text.replace(old, new, 1)


def transform(data):
    if source_blob(data) != SOURCE_BLOB:
        raise ValueError('Unreviewed Oracle compiler source blob')
    source = data.decode('utf-8')
    source = once(source, '    private int codeCacheSize;', '    private int codeCacheSize;\n' + LAYOUT)
    signature = 'public void layoutMethods(DebugContext debug, String imageName, BigBang bb, ForkJoinPool threadPool) {'
    source = once(source, signature, signature + '\n        if (target.arch instanceof jdk.vm.ci.aarch64.AArch64) { mmLayoutAarch64(); return; }')
    anchor = 'int callTargetStart = ((HostedMethod) call.target).getCodeAddressOffset();'
    source = once(source, anchor, anchor + '''
                    Map<HostedMethod, Integer> mmRedirects = mmTrampolines.get(method);
                    if (mmRedirects != null) {
                        callTargetStart = mmRedirects.getOrDefault((HostedMethod) call.target, callTargetStart);
                    }''')
    # Hash-pinned known body: it contains no brace characters in literals/comments.
    start = source.index('public void writeCode(RelocatableBuffer buffer) {')
    opening = source.index('{', start)
    depth = 1; end = opening + 1
    while depth:
        if source[end] == '{': depth += 1
        if source[end] == '}': depth -= 1
        end += 1
    return (source[:opening + 1] + WRITE + '    }' + source[end:]).encode()


def owned_home(home):
    home = home.resolve()
    if not home.is_relative_to((ROOT / 'build/toolchains').resolve()):
        raise ValueError('Only an owned build/toolchains installation may be modified')
    release = (home / 'release').read_text()
    for line in ('GRAALVM_VERSION="22.1.0.1"', 'JAVA_VERSION="17.0.3"', 'VENDOR=Gluon', 'OS_ARCH="x86_64"'):
        if line not in release.splitlines(): raise ValueError('Wrong compiler release: ' + line)
    return home


def fingerprints():
    return {'patchScriptSHA256': sha(Path(__file__).read_bytes()), 'layoutSHA256': sha(HELPER.read_bytes()),
            'oracleSourceBlob': SOURCE_BLOB, 'distributionSHA256': DISTRIBUTION_SHA}


def verify(home):
    home = owned_home(home)
    manifest = json.loads((home / 'magicmobile-compiler-patch.json').read_text())
    if any(manifest.get(k) != v for k, v in fingerprints().items()):
        raise ValueError('Compiler patch does not match the current source')
    if sha((home / 'lib/svm/builder/svm.jar').read_bytes()) != manifest['patchedSvmSHA256']:
        raise ValueError('Installed patched builder hash mismatch')
    return manifest


def prepare(home, source):
    home = owned_home(home)
    archive = ROOT / 'build/toolchains/gluon-graal17-intel.tar.gz'
    if sha(archive.read_bytes()) != DISTRIBUTION_SHA: raise ValueError('Distribution checksum mismatch')
    member = DISTRIBUTION + '/Contents/Home/lib/svm/builder/svm.jar'
    with tarfile.open(archive, 'r:gz') as distribution:
        original = distribution.extractfile(member).read()
    jar = home / 'lib/svm/builder/svm.jar'
    previous = home / 'magicmobile-compiler-patch.json'
    current_hash = sha(jar.read_bytes())
    if previous.exists():
        old = json.loads(previous.read_text())
        if old.get('originalSvmSHA256') != sha(original) or old.get('patchedSvmSHA256') != current_hash:
            raise ValueError('Existing builder patch is not the recorded owned artifact')
    elif current_hash != sha(original):
        raise ValueError('Builder differs from the checksum-pinned distribution')
    generated = transform(source.read_bytes())
    work = ROOT / 'build/compiler-patch'
    work.mkdir(parents=True, exist_ok=True)
    (work / 'original-svm.jar').write_bytes(original)
    (work / 'LIRNativeImageCodeCache.java').write_bytes(generated)
    classes = Path(tempfile.mkdtemp(prefix='classes-', dir=work))
    # The distribution exposes JVMCI both through its system modules and Graal
    # jars. Mixing those universes makes javac see two incompatible Infopoints.
    # Compile against one flat copy of the *same pinned* builder APIs, keeping
    # only Java SE modules in javac's application module graph.
    api = work / 'compiler-api.jar'
    extracted = Path(tempfile.mkdtemp(prefix='module-api-', dir=work))
    subprocess.run([str(home / 'bin/jimage'), 'extract', '--dir', str(extracted),
                    str(home / 'lib/modules')], check=True)
    with zipfile.ZipFile(api, 'w', compression=zipfile.ZIP_DEFLATED) as target:
        names = set()
        for module in ('jdk.internal.vm.ci', 'jdk.internal.vm.compiler', 'org.graalvm.sdk'):
            directory = extracted / module
            if not directory.is_dir(): raise ValueError('Missing pinned compiler API module: ' + module)
            for path in sorted(directory.rglob('*.class')):
                name = path.relative_to(directory).as_posix()
                if name == 'module-info.class': continue
                if name in names: raise ValueError('Duplicate compiler API class: ' + name)
                names.add(name); target.writestr(name, path.read_bytes())
        if 'jdk/vm/ci/code/site/Infopoint.class' not in names:
            raise ValueError('Pinned JVMCI API extraction is incomplete')
    cp = os.pathsep.join([str(api), str(work / 'original-svm.jar'),
                         str(home / 'lib/svm/builder/*'), str(home / 'lib/graalvm/*')])
    command = [str(home / 'bin/javac'), '-J-Xmx512m', '-source', '17', '-target', '17',
               '--limit-modules', 'java.se,jdk.unsupported', '-cp', cp, '-d', str(classes)]
    subprocess.run(command + [str(work / 'LIRNativeImageCodeCache.java'), str(HELPER)], check=True)
    replacements = {p.relative_to(classes).as_posix(): p.read_bytes() for p in classes.rglob('*.class')}
    if not replacements or any(not (name.startswith(PACKAGE + 'LIRNativeImageCodeCache')
                                    or name.startswith(PACKAGE + 'MagicMobileTrampolineLayout')) for name in replacements):
        raise ValueError('Unexpected builder classes; refusing patch')
    original_path = work / 'original-svm.jar'
    temporary = work / 'patched-svm.jar'
    with zipfile.ZipFile(original_path) as src, zipfile.ZipFile(temporary, 'w') as dst:
        for info in src.infolist():
            if info.filename.upper().startswith('META-INF/') and info.filename.upper().endswith(('.SF', '.RSA', '.DSA')):
                raise ValueError('Refusing to alter a signed builder jar')
            if info.filename not in replacements: dst.writestr(info, src.read(info.filename))
        for name, data in sorted(replacements.items()):
            info = zipfile.ZipInfo(name, date_time=(2000, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            dst.writestr(info, data)
    manifest = dict(fingerprints(), schema=1, originalSvmSHA256=sha(original),
                    patchedSvmSHA256=sha(temporary.read_bytes()), generatedSourceSHA256=sha(generated),
                    classes={name: sha(data) for name, data in sorted(replacements.items())},
                    scope='build-tool-only ARM64 veneers; no native gameplay assertion')
    # Commit the owned jar only after successful compilation, never touch a system JDK.
    replacement = jar.with_suffix('.magicmobile-new.jar')
    replacement.write_bytes(temporary.read_bytes())
    os.replace(replacement, jar)
    previous.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    return verify(home)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--graal-home', type=Path, required=True)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--verify-installed', action='store_true')
    args = parser.parse_args()
    if args.verify_installed == bool(args.source): parser.error('Choose --source or --verify-installed')
    try:
        manifest = verify(args.graal_home) if args.verify_installed else prepare(args.graal_home, args.source)
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Compiler preparation refused: {error}\n')
    print(json.dumps(manifest, indent=2, sort_keys=True))

if __name__ == '__main__': main()
