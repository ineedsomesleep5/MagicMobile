"""Read-only harness checks; run with python3 -m unittest discover scripts/deck-studio -p test_ios_ui_tests.py."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("ios-ui-tests.py")
SPEC = importlib.util.spec_from_file_location("ios_ui_tests", SCRIPT)
harness = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(harness)


def put(root, relative, content):
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content.encode())
    return path


class IosUITestHarnessTests(unittest.TestCase):
    def test_source_digest_tracks_tests_c_and_specs_but_skips_swift_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ("apps/ios/project.yml", "apps/ios/native-engine.yml", "apps/ios/Package.swift",
                         "apps/ios/MagicMobileiOS.xcodeproj/project.pbxproj", "packages/ondevice-engine/swift/Package.swift"):
                put(root, name, "initial")
            source = put(root, "apps/ios/MagicMobileUITests/ExampleUITests.swift", "class ExampleUITests: XCTestCase {}")
            c_header = put(root, "packages/ondevice-engine/swift/Sources/CMagicEngine/include/runtime.h", "v1")
            cache = put(root, "packages/ondevice-engine/swift/.build/cache.swift", "v1")
            original = harness.source_digest(root)
            cache.write_text("v2")
            self.assertEqual(original, harness.source_digest(root))
            for path in (source, c_header, root / "apps/ios/native-engine.yml",
                         root / "apps/ios/MagicMobileiOS.xcodeproj/project.pbxproj"):
                old = path.read_bytes()
                path.write_bytes(old + b" changed")
                self.assertNotEqual(original, harness.source_digest(root), str(path))
                path.write_bytes(old)

    def test_bundle_digest_tracks_test_dylib_and_resources(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = Path(temporary) / "MagicMobile.app"
            dylib = put(bundle, "MagicMobile.debug.dylib", "code")
            resource = put(bundle, "Assets.car", "asset")
            original = harness.bundle_digest(bundle)
            for path in (dylib, resource):
                path.write_bytes(path.read_bytes() + b" changed")
                self.assertNotEqual(original, harness.bundle_digest(bundle))
                path.write_bytes(path.read_bytes().removesuffix(b" changed"))

    def test_stamp_mismatch_names_changed_field(self):
        with self.assertRaisesRegex(ValueError, "test_bundle"):
            harness.verify_identity({"source": "a", "test_bundle": "old"},
                                    {"source": "a", "test_bundle": "new"})

    def test_selection_rejects_missing_class_method_and_unit_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            ios = Path(temporary)
            put(ios, "MagicMobileUITests/ExampleUITests.swift",
                "final class ExampleUITests: XCTestCase { func testFlow() {} }")
            harness.check_selection(["MagicMobileUITests/ExampleUITests/testFlow"], ios)
            for selected in ([], ["MagicMobileTests/ExampleUITests"],
                             ["MagicMobileUITests/MissingUITests"],
                             ["MagicMobileUITests/ExampleUITests/testMissing"]):
                with self.subTest(selected=selected), self.assertRaises(ValueError):
                    harness.check_selection(selected, ios)

    def test_shutdown_simulator_is_rejected_without_booting(self):
        udid = "12345678-1234-1234-1234-123456789ABC"
        calls = []
        def snapshot(command, **_):
            calls.append(command)
            return json.dumps({"devices": {"runtime": [{"udid": udid, "state": "Shutdown"}]}})
        with self.assertRaisesRegex(ValueError, "not already Booted"):
            harness.require_booted(udid, check_output=snapshot)
        self.assertEqual(calls[0][1:], ["simctl", "list", "devices", "booted", "--json"])

    def test_compile_command_is_generic_and_bounded(self):
        args = harness.command("build-for-testing", Path("/tmp/derived"))
        self.assertIn("generic/platform=iOS Simulator", args)
        self.assertEqual(args[args.index("-jobs") + 1], "2")
        self.assertEqual(args[args.index("-parallel-testing-enabled") + 1], "NO")

    def test_native_project_guard_and_generated_content_comparison(self):
        with tempfile.TemporaryDirectory() as temporary:
            ios = Path(temporary)
            project = put(ios, "MagicMobileiOS.xcodeproj/project.pbxproj", "ordinary UI project")
            with self.assertRaisesRegex(ValueError, "native-engine.yml"):
                harness.project_is_native(ios)
            project.write_text('mm_graal_backend_far.c in Sources\ngraal_far_calls.S in Sources\n'
                               '"MM_ENGINE_MODE[sdk=iphoneos*]" = "embedded-xmage"')
            harness.project_is_native(ios)
            self.assertNotEqual(harness.normalized_project(project.read_text()),
                                harness.normalized_project(project.read_text() + "\nNew.swift in Sources"))

    def test_run_spec_prefers_exact_arm64_and_rejects_ambiguity(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            self.assertIsNone(harness.select_run(base))
            arm64 = put(base, "MagicMobile_iphonesimulator26.5-arm64.xctestrun", "arm64")
            put(base, "MagicMobile_iphonesimulator26.5-arm64-x86_64.xctestrun", "mixed")
            self.assertEqual(harness.select_run(base), arm64)
            put(base, "MagicMobile_iphonesimulator27.0-arm64.xctestrun", "other")
            with self.assertRaisesRegex(ValueError, "Ambiguous xctestrun"):
                harness.select_run(base)


if __name__ == "__main__":
    unittest.main()
