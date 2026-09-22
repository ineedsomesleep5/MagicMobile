#!/usr/bin/env python3
"""Guard a generic-simulator UI compile, then run selected tests on an already booted device.

Plan/build use no simulator ID. Test requires --destination-id and --only-testing.
Use a dedicated --derived-data directory for each acceptance build.
The release controller owns Xcode project generation from native-engine.yml.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / "apps/ios"
DERIVED = ROOT / "build_output/ios-ui-harness"
STAMP = "magicmobile-ui-build.json"
DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer"
SOURCE_EXCLUDES = {".build", ".swiftpm", ".git", ".DS_Store", "DerivedData", "build_output", "__pycache__"}


def digest_file(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def digest_tree(root, files):
    h = hashlib.sha256()
    for path in sorted(files):
        if not path.is_file() or path.is_symlink():
            raise ValueError(f"Missing or linked build input: {path}")
        h.update(str(path.relative_to(root)).encode())
        h.update(b"\0")
        h.update(digest_file(path).encode())
        h.update(b"\0")
    return h.hexdigest()


def source_digest(root=ROOT):
    fixed = ["apps/ios/project.yml", "apps/ios/native-engine.yml", "apps/ios/Package.swift",
             "apps/ios/MagicMobileiOS.xcodeproj/project.pbxproj", "packages/ondevice-engine/swift/Package.swift"]
    folders = ["apps/ios/MagicMobile", "apps/ios/MagicMobileTests", "apps/ios/MagicMobileUITests",
               "apps/ios/NativeLink", "packages/ondevice-engine/swift/Sources",
               "packages/ondevice-engine/swift/Tests", "packages/ondevice-engine/native"]
    files = [root / name for name in fixed]
    for name in folders:
        folder = root / name
        files.extend(path for path in folder.rglob("*") if path.is_file()
                     and not any(part in SOURCE_EXCLUDES for part in path.relative_to(root).parts))
    return digest_tree(root, set(files))


def bundle_digest(bundle):
    if not bundle.is_dir():
        raise ValueError(f"Missing product bundle: {bundle}")
    files = [path for path in bundle.rglob("*") if path.is_file()]
    if not files:
        raise ValueError(f"Empty product bundle: {bundle}")
    return digest_tree(bundle, files)


def select_run(base):
    all_runs = sorted(base.glob("*.xctestrun"))
    runs = [path for path in all_runs if path.name.endswith("-arm64.xctestrun")]
    if len(runs) == 1:
        return runs[0]
    if len(all_runs) == 1:
        return all_runs[0]
    if all_runs:
        raise ValueError("Ambiguous xctestrun outputs; use a dedicated fresh --derived-data directory")
    return None


def products(derived):
    base = derived / "Build/Products"
    run = select_run(base)
    runners = sorted(base.glob("Debug-iphonesimulator/MagicMobileUITests-Runner.app"))
    apps = sorted(base.glob("Debug-iphonesimulator/MagicMobile.app"))
    if run is None or len(runners) != 1 or len(apps) != 1:
        raise ValueError("Expected one arm64 xctestrun, UI runner and app in a dedicated derived-data directory")
    test_bundle = runners[0] / "PlugIns/MagicMobileUITests.xctest"
    if not test_bundle.is_dir():
        raise ValueError(f"Missing compiled UI test bundle: {test_bundle}")
    return run, runners[0], test_bundle, apps[0]


def xcode_env():
    return {**os.environ, "DEVELOPER_DIR": DEVELOPER_DIR}


def xcode_identity():
    return subprocess.check_output(["/usr/bin/xcodebuild", "-version"], env=xcode_env(), text=True).strip()


def normalized_project(text):
    # XcodeGen emits location-relative group paths when output goes to a temp
    # directory. Build entries and settings should otherwise be identical.
    lines = [re.sub(r'(?:name|path) = (?:"[^"]*"|[^;]+);\s*', '', line).strip()
             for line in text.splitlines()]
    return [line for line in lines if line]


def project_is_native(ios=IOS, verify_generated=False):
    project = (ios / "MagicMobileiOS.xcodeproj/project.pbxproj").read_text()
    markers = ("mm_graal_backend_far.c in Sources", "graal_far_calls.S in Sources",
               '"MM_ENGINE_MODE[sdk=iphoneos*]" = "embedded-xmage"')
    if any(marker not in project for marker in markers):
        raise ValueError("Xcode project does not match native-engine.yml; ask the project owner to regenerate it")
    if verify_generated:
        with tempfile.TemporaryDirectory(prefix="magicmobile-ui-project-") as temporary:
            subprocess.run(["xcodegen", "generate", "--spec", str(ios / "native-engine.yml"),
                            "--project", temporary, "--project-root", str(ios), "--no-env", "--quiet"],
                           check=True, env=xcode_env())
            generated = (Path(temporary) / "MagicMobileiOS.xcodeproj/project.pbxproj").read_text()
        if normalized_project(project) != normalized_project(generated):
            raise ValueError("Generated Xcode project is stale for native-engine.yml; project owner must regenerate it")


def check_selection(selected, ios=IOS):
    if not selected:
        raise ValueError("Select at least one UI test class or method with --only-testing")
    for item in selected:
        parts = item.split("/")
        if len(parts) not in (2, 3) or parts[0] != "MagicMobileUITests" or not re.fullmatch(r"[A-Za-z0-9_]+UITests", parts[1]):
            raise ValueError(f"Invalid UI test selection: {item}")
        source = ios / "MagicMobileUITests" / (parts[1] + ".swift")
        if not source.is_file() or f"class {parts[1]}:" not in source.read_text():
            raise ValueError(f"Unknown UI test class: {item}")
        if len(parts) == 3 and (not re.fullmatch(r"test[A-Za-z0-9_]+", parts[2])
                                or not re.search(r"\bfunc\s+" + re.escape(parts[2]) + r"\s*\(", source.read_text())):
            raise ValueError(f"Unknown UI test method: {item}")


def identity(derived):
    run, runner, tests, app = products(derived)
    return {"source": source_digest(), "xcode": xcode_identity(), "xctestrun": digest_file(run),
            "runner_bundle": bundle_digest(runner), "test_bundle": bundle_digest(tests),
            "app_bundle": bundle_digest(app)}


def verify_identity(recorded, observed):
    if observed != recorded:
        changed = ", ".join(key for key in observed if observed[key] != recorded.get(key))
        raise ValueError(f"Build identity changed ({changed}); compile again")


def command(mode, derived, destination=None, selected=()):
    args = ["/usr/bin/xcodebuild", mode]
    if mode == "test-without-building":
        args += ["-xctestrun", str(products(derived)[0])]
        args += ["-only-testing:" + item for item in selected]
    else:
        args += ["-project", str(IOS / "MagicMobileiOS.xcodeproj"), "-scheme", "MagicMobile",
                 "-configuration", "Debug", "-jobs", "2", "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES"]
    args += ["-destination", f"platform=iOS Simulator,id={destination}" if destination else "generic/platform=iOS Simulator",
             "-derivedDataPath", str(derived), "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO"]
    return args


def require_booted(destination, check_output=subprocess.check_output):
    if not re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", destination or ""):
        raise ValueError("Test requires an explicit simulator UDID")
    raw = check_output(["/usr/bin/xcrun", "simctl", "list", "devices", "booted", "--json"],
                       env=xcode_env(), text=True)
    devices = json.loads(raw)["devices"]
    if not any(device.get("udid", "").lower() == destination.lower() and device.get("state") == "Booted"
               for group in devices.values() for device in group):
        raise ValueError(f"Simulator {destination} is not already Booted; this helper will not boot it")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("plan", "build", "test"))
    parser.add_argument("--destination-id")
    parser.add_argument("--derived-data", type=Path, default=DERIVED)
    parser.add_argument("--only-testing", action="append", default=[])
    args = parser.parse_args()
    derived = args.derived_data.resolve()
    if args.mode != "build":
        check_selection(args.only_testing)
    if args.mode == "plan":
        project_is_native()
        select_run(derived / "Build/Products")
        print("Compile:", " ".join(command("build-for-testing", derived)))
        print("Use a dedicated derived-data directory; then run test after explicitly booting one simulator.")
        return
    if args.mode == "build":
        select_run(derived / "Build/Products")  # Reject ambiguous old outputs before expensive compilation.
        project_is_native(verify_generated=True)
        (derived / STAMP).unlink(missing_ok=True)
        before = (source_digest(), xcode_identity())
        subprocess.run(command("build-for-testing", derived), cwd=IOS, check=True, env=xcode_env())
        if before != (source_digest(), xcode_identity()):
            raise ValueError("Source or Xcode changed during compilation; compile again")
        (derived / STAMP).write_text(json.dumps(identity(derived), indent=2) + "\n")
        print(f"Stamped exact app and UI test bundles in {derived}")
        return
    require_booted(args.destination_id)
    stamp = derived / STAMP
    if not stamp.is_file():
        raise ValueError("No build stamp; compile in this derived-data directory first")
    recorded = json.loads(stamp.read_text())
    before = identity(derived)
    verify_identity(recorded, before)
    subprocess.run(command("test-without-building", derived, args.destination_id, args.only_testing),
                   cwd=IOS, check=True, env=xcode_env())
    after = identity(derived)
    if after != before:
        changed = ", ".join(key for key in after if after[key] != before[key])
        raise ValueError(f"Source or build products changed during test ({changed}); result is not exact-source evidence")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
