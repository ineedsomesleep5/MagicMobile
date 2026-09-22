"""Fake TestFlight stages and Apple reads; no external release actions."""
import json
from pathlib import Path
import unittest

import test_controller as fixture_module

controller = fixture_module.controller
run_git = fixture_module.run_git


class IOSStageTests(unittest.TestCase):
    def setUp(self):
        fixture = fixture_module.ControllerTests(methodName="runTest")
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.repo = fixture.repo
        self.calls = 0
        self.put("scripts/ios/deploy-testflight.sh", "#!/bin/sh\nexit 99\n")
        self.put("release/testflight/ExportOptionsExternal.plist", "fixture")
        self.put("packages/ondevice-engine/build/native-candidate-provenance.json", "{}")
        self.put("apps/ios/NativeEngine/lib/libmmengine.a", "native iOS bytes")
        digest = controller.sha(self.repo / "apps/ios/NativeEngine/lib/libmmengine.a")
        self.put("apps/ios/NativeEngine/manifest.json", json.dumps({
            "schema": 1, "files": {"lib/libmmengine.a": {"sha256": digest}}}))
        self.put("release/testflight/build-ledger.json", json.dumps({
            "bundleId": "com.calebfeliciano.magicmobile", "marketingVersion": "0.1.1",
            "lastPreparedBuild": "8", "uploads": []}))
        run_git(self.repo, "add", ".")
        run_git(self.repo, "commit", "-qm", "iOS fixture")

    def put(self, name, content):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def apple_build(self):
        return {"data": [{"type": "builds", "id": "41352360-e944-453e-9882-b90a4356877b",
                          "attributes": {"version": "8", "processingState": "VALID"},
                          "relationships": {"preReleaseVersion": {"data": {"id": "version-8"}}}}],
                "included": [{"type": "preReleaseVersions", "id": "version-8",
                              "attributes": {"version": "0.1.1"}}]}

    def fake_ios(self, command, log):
        self.calls += 1
        root = self.repo / "build_output/testflight/native-release.fixture"
        root.mkdir(parents=True, exist_ok=True)
        if "--stop-after-upload" in command:
            ipa = root / "export/MagicMobile.ipa"
            ipa.parent.mkdir(parents=True, exist_ok=True)
            ipa.write_text("signed iOS fixture")
            digest = controller.sha(ipa)
            (root / "signed-receipt.json").write_text(json.dumps({
                "bundleID": "com.calebfeliciano.magicmobile", "appVersion": "0.1.1",
                "appBuild": "8", "ipaSHA256": digest}))
            (root / "upload-input-receipt.json").write_text(json.dumps({"ipaSHA256": digest}))
            (root / "altool-upload.log").write_text("Delivery UUID: 41352360-e944-453e-9882-b90a4356877b\n")
            ledger = json.loads((self.repo / "release/testflight/build-ledger.json").read_text())
            ledger.update({"bundleId": "com.calebfeliciano.magicmobile",
                           "marketingVersion": "0.1.1", "lastPreparedBuild": "8",
                           "lastPreparedMarketingVersion": "0.1.1",
                           "lastUploadedBuild": "8", "lastUploadedMarketingVersion": "0.1.1"})
            ledger["uploads"] = [{"build": "8", "marketingVersion": "0.1.1",
                                   "deliveryUuid": "41352360-e944-453e-9882-b90a4356877b",
                                   "ipaPath": str(ipa.relative_to(self.repo)), "uploadedAt": "fixture"}]
            self.put("release/testflight/build-ledger.json", json.dumps(ledger))
            log.write_text(f"Release evidence: {root}\n")
        else:
            self.assertTrue(command[0].endswith("distribute-testflight-groups.sh"))
            for name, content in {"apple-build.json": self.apple_build(),
                                  "testflight-groups.json": {"complete": True},
                                  "beta-app-review.json": {"data": {}},
                                  "testflight-distribution.json": {"data": {}}}.items():
                (root / name).write_text(json.dumps(content))
            log.write_text("fixture distribution complete\n")
        return 0

    def test_upload_then_distribution_resume(self):
        c = controller.Controller(self.repo, self.fake_ios)
        fingerprint = c.plan("ios")["identity"]["fingerprint"]
        first = c.resume("ios", "ios-8", fingerprint)
        self.assertEqual(first["state"], "uploaded")
        self.assertEqual(c.plan("ios", "ios-8")["state"], "uploaded")
        second = c.resume("ios", "ios-8", fingerprint)
        self.assertEqual(second["state"], "completed")
        self.assertEqual(self.calls, 2)
        self.assertEqual(c.resume("ios", "ios-8", fingerprint)["action"], "no-op")

    def test_reconcile_uncertain_upload_with_exact_apple_read(self):
        def upload_then_fail(command, log):
            self.fake_ios(command, log)
            return 1
        c = controller.Controller(self.repo, upload_then_fail)
        fingerprint = c.plan("ios")["identity"]["fingerprint"]
        with self.assertRaisesRegex(controller.ReleaseError, "requires reconciliation"):
            c.resume("ios", "uncertain-ios", fingerprint)
        with self.assertRaisesRegex(controller.ReleaseError, "Apple returned"):
            c.reconcile("uncertain-ios", fingerprint, lambda version, build: {"data": []})
        result = c.reconcile("uncertain-ios", fingerprint, lambda version, build: self.apple_build())
        self.assertEqual(result["state"], "uploaded")
        self.assertEqual(self.calls, 1)

    def test_native_binary_hash_is_checked(self):
        self.put("apps/ios/NativeEngine/lib/libmmengine.a", "changed")
        run_git(self.repo, "add", ".")
        run_git(self.repo, "commit", "-qm", "changed binary")
        with self.assertRaisesRegex(controller.ReleaseError, "native input changed"):
            controller.Controller(self.repo).plan("ios")

    def test_saved_build7_apple_response_shape(self):
        saved = Path(__file__).resolve().parents[2] / "build_output/testflight/build7/native-release.a3ZhW5/apple-build.json"
        if not saved.is_file():
            self.skipTest("Optional saved build 7 read-only evidence unavailable")
        response = json.loads(saved.read_text())
        row = response["data"][0]
        version_id = row["relationships"]["preReleaseVersion"]["data"]["id"]
        version = next(r["attributes"]["version"] for r in response["included"] if r["id"] == version_id)
        controller.verify_apple_build(response, {"deliveryUuid": row["id"].lower(),
                                                "build": str(row["attributes"]["version"]),
                                                "version": version})


if __name__ == "__main__":
    unittest.main()
