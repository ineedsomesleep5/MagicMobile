"""Local fixture tests: no signing, builds, uploads, or remote calls."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

MODULE = Path(__file__).with_name("controller.py")
spec = importlib.util.spec_from_file_location("release_controller", MODULE)
controller = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controller)


def run_git(repo, *args):
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


class ControllerTests(unittest.TestCase):
    def test_symlinked_state_root_is_rejected_before_writes(self):
        with tempfile.TemporaryDirectory() as outside:
            (self.repo / 'build_output').symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(controller.ReleaseError, 'Symlinked'):
                controller.run_dir(self.repo, 'escape')
            self.assertEqual(list(Path(outside).iterdir()), [])

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name).resolve()
        previous_code = os.environ.get("MM_ANDROID_VERSION_CODE")
        previous_name = os.environ.get("MM_ANDROID_VERSION_NAME")
        os.environ["MM_ANDROID_VERSION_CODE"] = "2026092102"
        os.environ["MM_ANDROID_VERSION_NAME"] = "0.1.1"
        def restore_env():
            for key, value in (("MM_ANDROID_VERSION_CODE", previous_code),
                               ("MM_ANDROID_VERSION_NAME", previous_name)):
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        self.addCleanup(restore_env)
        run_git(self.repo, "init", "-q")
        run_git(self.repo, "config", "user.email", "fixture@example.invalid")
        run_git(self.repo, "config", "user.name", "Fixture")
        self.put(".gitignore", "build_output/\nbuild/\n")
        self.put("scripts/android/build_release.sh", "#!/bin/sh\nexit 99\n")
        self.put("apps/android/native-artifact/libmmengine.so", "native bytes")
        digest = controller.sha(self.repo / "apps/android/native-artifact/libmmengine.so")
        self.put("apps/android/native-artifact/manifest.json", json.dumps({
            "schema": 1, "target": "android-arm64", "files": {"libmmengine.so": digest}}))
        run_git(self.repo, "add", ".")
        run_git(self.repo, "commit", "-qm", "fixture")
        self.calls = 0

    def put(self, name, content):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def fake_success(self, command, log):
        self.calls += 1
        log.write_text("Guarded fixture success\n")
        self.put("apps/android/app/build/outputs/apk/release/app-release.apk", "signed fixture APK")
        return 0

    def test_plan_is_read_only_and_resume_is_noop_after_completion(self):
        c = controller.Controller(self.repo, self.fake_success)
        plan = c.plan("android", "test-run")
        self.assertEqual(plan["state"], "new")
        self.assertFalse((self.repo / "build_output").exists())
        result = c.resume("android", "test-run", plan["identity"]["fingerprint"])
        self.assertEqual(result["state"], "completed")
        self.assertEqual(result["evidence"]["signedAPK"]["sha256"],
                         controller.sha(self.repo / "apps/android/app/build/outputs/apk/release/app-release.apk"))
        self.assertEqual(c.resume("android", "test-run", plan["identity"]["fingerprint"])["action"], "no-op")
        self.assertEqual(self.calls, 1)
        self.assertEqual([e["kind"] for e in c.status("test-run")["events"]],
                         ["planned", "started", "completed"])

    def test_uncertain_mutation_never_retries(self):
        def failed(command, log):
            self.calls += 1
            log.write_text("network outcome unknown\n")
            return 1
        c = controller.Controller(self.repo, failed)
        fingerprint = c.plan("android")["identity"]["fingerprint"]
        with self.assertRaisesRegex(controller.ReleaseError, "requires reconciliation"):
            c.resume("android", "uncertain", fingerprint)
        with self.assertRaisesRegex(controller.ReleaseError, "never retry"):
            c.resume("android", "uncertain", fingerprint)
        self.assertEqual(self.calls, 1)
        self.assertEqual(c.status("uncertain")["state"], "uncertain")

    def test_crashed_started_event_never_retries(self):
        c = controller.Controller(self.repo, self.fake_success)
        current = c.plan("android")["identity"]
        directory = controller.run_dir(self.repo, "crashed")
        controller.append(directory, "planned", {"identity": current, "runId": "crashed"})
        controller.append(directory, "started", {"command": ["fixture"]})
        with self.assertRaisesRegex(controller.ReleaseError, "never retry"):
            c.resume("android", "crashed", current["fingerprint"])
        self.assertEqual(self.calls, 0)

    def test_stale_identity_invalidates_run(self):
        c = controller.Controller(self.repo, self.fake_success)
        current = c.plan("android")["identity"]
        directory = controller.run_dir(self.repo, "stale")
        controller.append(directory, "planned", {"identity": current, "runId": "stale"})
        self.put("scripts/android/build_release.sh", "#!/bin/sh\nexit 98\n")
        run_git(self.repo, "add", ".")
        run_git(self.repo, "commit", "-qm", "new reviewed source")
        with self.assertRaisesRegex(controller.ReleaseError, "stale"):
            c.resume("android", "stale", current["fingerprint"])
        self.assertEqual(c.status("stale")["state"], "stale")
        self.assertEqual(controller.events(directory)[-1]["kind"], "invalidated")
        self.assertEqual(self.calls, 0)

    def test_concurrent_lock_refuses_second_controller(self):
        c = controller.Controller(self.repo, self.fake_success)
        fingerprint = c.plan("android")["identity"]["fingerprint"]
        lock = self.repo / "build_output/release-controller/.controller.lock"
        lock.parent.mkdir(parents=True)
        with lock.open("a+b") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(controller.ReleaseError, "holds the lock"):
                c.resume("android", "locked", fingerprint)
        self.assertEqual(self.calls, 0)

    def test_authorization_and_evidence_tamper_fail_closed(self):
        c = controller.Controller(self.repo, self.fake_success)
        current = c.plan("android")["identity"]
        with self.assertRaisesRegex(controller.ReleaseError, "Authorization fingerprint"):
            c.resume("android", "wrong", "0" * 64)
        self.assertEqual(self.calls, 0)
        c.resume("android", "good", current["fingerprint"])
        event = controller.run_dir(self.repo, "good") / "events/000001.json"
        event.write_text(event.read_text().replace("planned", "complete"))
        with self.assertRaisesRegex(controller.ReleaseError, "chain failed"):
            c.status("good")

    def test_completed_artifact_tamper_reports_stale(self):
        c = controller.Controller(self.repo, self.fake_success)
        fingerprint = c.plan("android")["identity"]["fingerprint"]
        c.resume("android", "artifact", fingerprint)
        self.put("apps/android/app/build/outputs/apk/release/app-release.apk", "changed")
        self.assertEqual(c.status("artifact")["state"], "stale")
        self.assertEqual(c.resume("android", "artifact", fingerprint)["state"], "stale")

    def test_android_version_target_invalidates_fingerprint(self):
        c = controller.Controller(self.repo, self.fake_success)
        original = c.plan("android")["identity"]["fingerprint"]
        os.environ["MM_ANDROID_VERSION_CODE"] = "2026092103"
        changed = c.plan("android")["identity"]["fingerprint"]
        self.assertNotEqual(original, changed)
        with self.assertRaisesRegex(controller.ReleaseError, "Authorization fingerprint"):
            c.resume("android", "wrong-version", original)

    def test_watcher_rejects_wrong_head_without_mutation(self):
        c = controller.Controller(self.repo, self.fake_success)
        current = c.plan("android")["identity"]
        directory = controller.run_dir(self.repo, "watch")
        controller.append(directory, "planned", {"identity": current, "runId": "watch"})
        real_run = controller.subprocess.run
        def fake_run(args, **kwargs):
            if args[:3] == ["gh", "run", "view"]:
                return subprocess.CompletedProcess(args, 0, json.dumps({
                    "databaseId": 123, "headSha": "other", "status": "completed"}), "")
            return real_run(args, **kwargs)
        controller.subprocess.run = fake_run
        try:
            with self.assertRaisesRegex(controller.ReleaseError, "differs"):
                controller.watch(self.repo, "watch", "github", "123", 1, 1)
        finally:
            controller.subprocess.run = real_run
        self.assertEqual(len(controller.events(directory)), 1)


if __name__ == "__main__":
    unittest.main()
