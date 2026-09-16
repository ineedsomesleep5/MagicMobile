#!/usr/bin/env python3
"""Build an owned, auditable Gluon 22.1 compiler with AArch64 far-call veneers.

Never edits an installed SDK. Extracts a checksum-pinned official archive into a
new build directory, verifies upstream sources before AND after the small patch,
compiles against that exact SDK, and changes only its private svm.jar copy.
This is compiler preparation, not proof of a native engine or a working phone.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PATCH_ROOT = ROOT / "native/gluon/compiler-patches"
ARCHIVE_SHA256 = "61084c8e12a500e5019657d3160fa3394cd8230a0e780718a051d59028fbfb99"
TOOLCHAIN = "graalvm-svm-java17-darwin-gluon-22.1.0.1-Final"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify(path: Path, expected: str) -> None:
    if not path.is_file() or path.is_symlink() or sha256(path) != expected:
        raise ValueError(f"Checksum/type mismatch: {path}")


def module_exports(java: Path) -> list[str]:
    result: list[str] = []
    for module in ("org.graalvm.sdk", "jdk.internal.vm.compiler", "jdk.internal.vm.ci"):
        description = subprocess.check_output([str(java), "--describe-module", module], text=True)
        packages: set[str] = set()
        for line in description.splitlines():
            words = line.split()
            if words and words[0] in ("contains", "exports"):
                packages.add(words[1])
            elif words[:2] == ["qualified", "exports"]:
                packages.add(words[2])
        for package in sorted(packages):
            # javac must resolve JVMCI types inside Graal's generic signatures as
            # well as in our unnamed-module source. Exporting only to the
            # unnamed module makes DataPatch/Infopoint appear inaccessible
            # when loaded through CompilationResult in the named module.
            targets = "ALL-UNNAMED"
            if module in ("jdk.internal.vm.ci", "org.graalvm.sdk"):
                targets += ",jdk.internal.vm.compiler"
            result += ["--add-exports", f"{module}/{package}={targets}"]
    return result


def patch_sources(destination: Path) -> list[Path]:
    manifest = json.loads((PATCH_ROOT / "upstream-sources.json").read_text())
    revision = manifest["upstreamCommit"]
    sources = []
    for item in manifest["files"]:
        relative = Path(item["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Unsafe compiler source path")
        source = destination / relative
        source.parent.mkdir(parents=True, exist_ok=True)
        url = f"https://raw.githubusercontent.com/oracle/graal/{revision}/{relative.as_posix()}"
        with urllib.request.urlopen(url, timeout=60) as response, source.open("xb") as output:
            shutil.copyfileobj(response, output)
        verify(source, item["sha256"])
        sources.append(source)
    subprocess.run(["patch", "--batch", "--fuzz=0", "-p1", "-i", str(PATCH_ROOT / "far-calls.patch")],
                   cwd=destination, check=True)
    for source, item in zip(sources, manifest["files"]):
        verify(source, item["patchedSha256"])
    return sources


def replace_classes(jar_path: Path, classes: Path) -> dict[str, str]:
    replacements = {p.relative_to(classes).as_posix(): p.read_bytes() for p in classes.rglob("*.class")}
    if not replacements or any(not key.startswith("com/oracle/svm/") for key in replacements):
        raise ValueError("Unexpected compiler replacement class set")
    temporary = jar_path.with_suffix(".patched.jar")
    with zipfile.ZipFile(jar_path) as original, zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as output:
        for entry in original.infolist():
            if entry.filename in replacements:
                continue
            # Reject signed builder JARs instead of silently discarding signatures.
            if entry.filename.upper().startswith("META-INF/") and entry.filename.upper().endswith((".SF", ".RSA", ".DSA")):
                raise ValueError("Cannot patch a signed compiler JAR")
            output.writestr(entry, original.read(entry.filename))
        for name, data in sorted(replacements.items()):
            output.writestr(name, data)
    os.replace(temporary, jar_path)
    return {name: hashlib.sha256(data).hexdigest() for name, data in sorted(replacements.items())}


def prepare(archive: Path) -> tuple[Path, Path]:
    verify(archive, ARCHIVE_SHA256)
    build_root = ROOT / "build"
    build_root.mkdir(exist_ok=True)
    build = Path(tempfile.mkdtemp(prefix="ios-compiler-patch-", dir=build_root))
    sdk_root = build / "sdk"
    sdk_root.mkdir()
    print(f"Preparing private compiler in {build}", flush=True)
    # The archive is official and hash-pinned; data_filter additionally rejects escapes.
    with tarfile.open(archive, "r:gz") as source:
        source.extractall(sdk_root, filter="data")
    home = sdk_root / TOOLCHAIN / "Contents/Home"
    release = (home / "release").read_text().splitlines()
    if not all(x in release for x in ('GRAALVM_VERSION="22.1.0.1"', 'JAVA_VERSION="17.0.3"', 'VENDOR=Gluon', 'OS_ARCH="x86_64"')):
        raise ValueError("Wrong SDK release")
    jar = home / "lib/svm/builder/svm.jar"
    original_jar_hash = sha256(jar)
    sources_root = build / "sources"
    sources_root.mkdir()
    sources = patch_sources(sources_root)
    planner = sources_root / "FarCallPlanner.java"
    shutil.copyfile(PATCH_ROOT / "src/com/oracle/svm/hosted/image/FarCallPlanner.java", planner)
    sources.append(planner)
    classes = build / "classes"
    classes.mkdir()
    command = [str(home / "bin/javac"), "-J-Xmx768m", "-proc:none", "-source", "17", "-target", "17",
               "--add-modules", "org.graalvm.sdk,jdk.internal.vm.compiler,jdk.internal.vm.ci"]
    # Use one JVMCI type universe for the SDK compiler and replacement classes.
    command += ["--add-reads", "jdk.internal.vm.compiler=jdk.internal.vm.ci",
                "--add-reads", "jdk.internal.vm.compiler=org.graalvm.sdk"]
    command += module_exports(home / "bin/java")
    descriptors = {module: subprocess.check_output(
        [str(home / "bin/java"), "--describe-module", module], text=True)
        for module in ("org.graalvm.sdk", "jdk.internal.vm.compiler", "jdk.internal.vm.ci")}
    (build / "compiler-module-descriptors.json").write_text(json.dumps(descriptors, indent=2) + "\n")
    command += ["--add-exports", "java.base/jdk.internal.misc=ALL-UNNAMED",
                "-cp", str(home / "lib/svm/builder/*"), "-d", str(classes)]
    command += [str(p) for p in sources]
    (build / "javac-arguments.json").write_text(json.dumps(command, indent=2) + "\n")
    subprocess.run(command, check=True)
    class_hashes = replace_classes(jar, classes)
    evidence = {
        "schema": 1, "scope": "build-time compiler adaptation; no native runtime acceptance",
        "officialArchiveSha256": ARCHIVE_SHA256,
        "originalSvmJarSha256": original_jar_hash, "patchedSvmJarSha256": sha256(jar),
        "patchSha256": sha256(PATCH_ROOT / "far-calls.patch"),
        "sourceManifestSha256": sha256(PATCH_ROOT / "upstream-sources.json"),
        "plannerSha256": sha256(planner), "replacementClasses": class_hashes,
        "javaHome": str(home), "upstreamSources": json.loads((PATCH_ROOT / "upstream-sources.json").read_text()),
    }
    report = build / "compiler-patch-manifest.json"
    report.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    (build / "JAVA_HOME.txt").write_text(str(home) + "\n")
    print(f"Prepared compiler; manifest {report}", flush=True)
    return home, report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=ROOT / "build/toolchains/gluon-graal17-intel.tar.gz")
    parser.add_argument("--result-file", type=Path, required=True)
    args = parser.parse_args()
    # Output identity is created exclusively; never overwrite a concurrent build's result.
    if args.result_file.exists() or args.result_file.is_symlink():
        parser.error("Result file already exists")
    home, _ = prepare(args.archive)
    with args.result_file.open("x") as output:
        output.write(str(home) + "\n")


if __name__ == "__main__":
    main()
