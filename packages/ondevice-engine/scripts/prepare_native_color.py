#!/usr/bin/env python3
"""Prepare an isolated, pinned JDK Color value-only patch for native builds."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

SOURCE_SHA256 = "4010cb2e2fee98b0f285a7a191997fd23a140430d8aa344917c7c55f8b87bc30"
DESKTOP_INIT = """        /* ensure that the necessary native libraries are loaded */
        Toolkit.loadLibraries();
        if (!GraphicsEnvironment.isHeadless()) {
            initIDs();
        }
"""
VALUE_INIT = """        // MagicMobile native adaptation: Color is used for Java RGB values.
        // Do not register desktop JNI fields or initialize a desktop Toolkit.
        // All original constants, constructors and color operations are retained.
"""


def patched_source(source: bytes) -> bytes:
    if hashlib.sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError("Unreviewed JDK Color source; refusing to patch")
    text = source.decode("utf-8")
    if text.count(DESKTOP_INIT) != 1:
        raise ValueError("Expected exactly one reviewed desktop initialization block")
    return text.replace(DESKTOP_INIT, VALUE_INIT).encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--graalvm-home", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    with zipfile.ZipFile(args.graalvm_home / "lib/src.zip") as archive:
        original = archive.read("java.desktop/java/awt/Color.java")
    patched = patched_source(original)
    args.output.mkdir(parents=True, exist_ok=False)
    source = args.output / "src/java/awt/Color.java"
    source.parent.mkdir(parents=True)
    source.write_bytes(patched)
    classes = args.output / "classes"
    classes.mkdir()
    command = [str(args.graalvm_home / "bin/javac"), "-J-Xmx128m", "-proc:none",
               "--patch-module", f"java.desktop={args.output / 'src'}",
               "-d", str(classes), str(source)]
    subprocess.run(command, check=True)
    outputs = sorted(p.relative_to(classes).as_posix() for p in classes.rglob("*.class"))
    if outputs != ["java/awt/Color.class"]:
        raise ValueError(f"Unexpected module patch classes: {outputs}")
    manifest = {
        "scope": "Color desktop JNI initialization only; not AWT graphics support",
        "originalSourceSha256": SOURCE_SHA256,
        "patchedSourceSha256": hashlib.sha256(patched).hexdigest(),
        "classSha256": hashlib.sha256((classes / outputs[0]).read_bytes()).hexdigest(),
        "javacArguments": command,
    }
    (args.output / "color-patch-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(classes.resolve())


if __name__ == "__main__":
    main()
