"""stage-native with fake GitHub reads and fake scripts; no network, download or staging."""
import copy
import json
from pathlib import Path
import shutil
import unittest

import test_controller as fixture_module

controller = fixture_module.controller
run_git = fixture_module.run_git
REAL_GATE = Path(__file__).resolve().parents[2] / "packages/ondevice-engine/scripts/wait_issue4_native.py"
COMMIT = "a" * 40
RUN = 36311846082
ARTIFACT = 10931357619
DIGEST = "sha256:" + "f" * 64


class StageNativeTests(unittest.TestCase):
    def setUp(self):
        fixture = fixture_module.ControllerTests(methodName="runTest")
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.repo = fixture.repo
        gate = self.repo / controller.ENGINE_SCRIPTS / "wait_issue4_native.py"
        gate.parent.mkdir(parents=True)
        shutil.copyfile(REAL_GATE, gate)  # the real required-step policy, not a copy of its list
        self.gate = controller.importlib.util.spec_from_file_location("fixture_gate", gate)
        module = controller.importlib.util.module_from_spec(self.gate)
        self.gate.loader.exec_module(module)
        self.required = module.REQUIRED_STEPS
        (self.repo / ".gitignore").write_text("build_output/\nbuild/\napps/ios/NativeEngine/\n")
        run_git(self.repo, "add", ".")
        run_git(self.repo, "commit", "-qm", "stage fixture")
        self.responses = self.github()
        self.calls, self.api_paths, self.tokens = [], [], 0

    def github(self):
        run = {"id": RUN, "head_sha": COMMIT, "run_attempt": 1, "event": "workflow_dispatch",
               "status": "completed", "conclusion": "success",
               "path": ".github/workflows/magicmobile-far-calls.yml",
               "repository": {"full_name": controller.GITHUB_REPOSITORY},
               "head_repository": {"full_name": controller.GITHUB_REPOSITORY}}
        jobs = [{"id": number, "name": name, "run_id": RUN, "head_sha": COMMIT, "run_attempt": 1,
                 "status": "completed", "conclusion": "success",
                 "steps": [{"name": step, "status": "completed", "conclusion": "success"} for step in steps]}
                for number, (name, steps) in enumerate(self.required.items(), 1)]
        return {f"/actions/runs/{RUN}": run,
                f"/actions/runs/{RUN}/attempts/1/jobs?per_page=100&page=1": {"total_count": len(jobs), "jobs": jobs},
                f"/actions/runs/{RUN}/artifacts?per_page=100": {"artifacts": [
                    {"id": 1, "name": "issue4-far-call-evidence-" + COMMIT, "expired": False,
                     "digest": "sha256:" + "0" * 64, "workflow_run": {"id": RUN}},
                    {"id": ARTIFACT, "name": "issue4-full-native-candidate-" + COMMIT, "expired": False,
                     "digest": DIGEST, "workflow_run": {"id": RUN}}]}}

    def api(self, path):
        self.api_paths.append(path)
        return copy.deepcopy(self.responses[path])

    def token(self):
        self.tokens += 1
        return "fixture-token-value"

    def runner(self, command, log, env, *, fail=None, receipt=None):
        step = Path(command[1]).name
        self.calls.append((step, "GH_TOKEN" in env, env.get("GH_TOKEN")))
        log.write_text("fixture log for " + step)
        if step == fail:
            return 3
        if step == "verify_native_candidate.py":
            output = Path(command[command.index("--output") + 1])
            output.write_text(json.dumps(receipt or {
                "engineSourceCommit": COMMIT, "workflowRunID": RUN, "artifactID": ARTIFACT,
                "artifactDigest": DIGEST, "scope": "fixture"}))
        if step == "prepare_ios_app_native.py":
            (self.repo / "apps/ios/NativeEngine").mkdir(parents=True)
            (self.repo / "apps/ios/NativeEngine/manifest.json").write_text("{}")
        return 0

    def stage(self, **runner_options):
        return controller.stage_native(
            self.repo, str(RUN), api=self.api, token=self.token,
            runner=lambda command, log, env: self.runner(command, log, env, **runner_options))

    def test_stages_in_order_and_only_the_download_sees_the_token(self):
        result = self.stage()
        self.assertEqual([call[0] for call in self.calls],
                         ["download_issue4_native.py", "verify_native_candidate.py", "prepare_ios_app_native.py"])
        self.assertEqual([call[1] for call in self.calls], [True, False, False])
        self.assertEqual(self.calls[0][2], "fixture-token-value")
        self.assertEqual((result["state"], result["artifactID"], result["artifactDigest"], result["engineCommit"]),
                         ("staged", ARTIFACT, DIGEST, COMMIT))
        provenance = self.repo / "packages/ondevice-engine/build/native-candidate-provenance.json"
        self.assertEqual(json.loads(provenance.read_text())["artifactID"], ARTIFACT)
        self.assertEqual(result["provenanceSHA256"], controller.sha(provenance))
        saved = Path(result["evidenceDirectory"]) / "stage-native.json"
        self.assertEqual(json.loads(saved.read_text()), json.loads(json.dumps(result)))
        self.assertNotIn("fixture-token-value", saved.read_text())
        self.assertIn(f"/actions/runs/{RUN}/attempts/1/jobs?per_page=100&page=1", self.api_paths)

    def test_dirty_tree_or_existing_engine_is_refused_before_github(self):
        (self.repo / ".gitignore").write_text("changed\n")
        with self.assertRaisesRegex(controller.ReleaseError, "clean HEAD"):
            self.stage()
        run_git(self.repo, "checkout", "--", ".gitignore")
        (self.repo / "apps/ios/NativeEngine").mkdir(parents=True)
        with self.assertRaisesRegex(controller.ReleaseError, "already exists; move it aside"):
            self.stage()
        self.assertEqual((self.api_paths, self.calls, self.tokens), ([], [], 0))

    def test_run_id_must_be_a_positive_number(self):
        for value in ("0", "-1", "12a", "", "1" * 21):
            with self.assertRaisesRegex(controller.ReleaseError, "positive GitHub Actions run ID"):
                controller.stage_native(self.repo, value, api=self.api, token=self.token, runner=None)
        self.assertEqual(self.api_paths, [])

    def test_untrusted_or_unfinished_runs_are_refused_before_download(self):
        run_path = f"/actions/runs/{RUN}"
        jobs_path = f"/actions/runs/{RUN}/attempts/1/jobs?per_page=100&page=1"
        edits = [
            lambda r: r[run_path].update(conclusion="failure"),
            lambda r: r[run_path].update(status="in_progress", conclusion=None),
            lambda r: r[run_path].update(path=".github/workflows/magicmobile-native-ios.yml"),
            lambda r: r[run_path].update(event="push"),
            lambda r: r[run_path].update(head_sha="main"),
            # The approval job's steps are required, so an ungated build cannot be staged.
            lambda r: r[jobs_path]["jobs"][0]["steps"].pop(),
            lambda r: r[jobs_path]["jobs"][1]["steps"][0].update(conclusion="skipped"),
        ]
        for edit in edits:
            self.responses = self.github()
            edit(self.responses)
            with self.assertRaisesRegex(controller.ReleaseError, "not a trusted far-calls engine build"):
                self.stage()
        self.assertEqual((self.calls, self.tokens), ([], 0))

    def test_artifact_must_be_unique_unexpired_and_attributed(self):
        path = f"/actions/runs/{RUN}/artifacts?per_page=100"
        edits = [
            lambda items: items.pop(),
            lambda items: items[1].update(expired=True),
            lambda items: items.append(dict(items[1], id=ARTIFACT + 1)),
            lambda items: items[1].update(digest="sha256:short"),
            lambda items: items[1].update(workflow_run={"id": RUN + 1}),
        ]
        for edit in edits:
            self.responses = self.github()
            edit(self.responses[path]["artifacts"])
            with self.assertRaises(controller.ReleaseError):
                self.stage()
        self.assertEqual((self.calls, self.tokens), ([], 0))

    def test_existing_download_directory_is_refused(self):
        (self.repo / f"packages/ondevice-engine/build/verified-native-{ARTIFACT}").mkdir(parents=True)
        with self.assertRaisesRegex(controller.ReleaseError, "move it aside to download again"):
            self.stage()
        self.assertEqual(self.calls, [])

    def test_failed_step_stops_later_steps_and_writes_no_provenance(self):
        with self.assertRaisesRegex(controller.ReleaseError, "stage-native verify failed \\(exit 3\\)"):
            self.stage(fail="verify_native_candidate.py")
        self.assertEqual([call[0] for call in self.calls], ["download_issue4_native.py", "verify_native_candidate.py"])
        self.assertFalse((self.repo / "packages/ondevice-engine/build/native-candidate-provenance.json").exists())
        report = next((self.repo / "build_output/native-stage").glob("run-*/stage-native.json"))
        self.assertEqual(json.loads(report.read_text())["state"], "failed")

    def test_mismatched_receipt_is_not_promoted(self):
        receipt = {"engineSourceCommit": COMMIT, "workflowRunID": RUN, "artifactID": ARTIFACT + 1,
                   "artifactDigest": DIGEST}
        with self.assertRaisesRegex(controller.ReleaseError, "does not match the selected run"):
            self.stage(receipt=receipt)
        self.assertFalse((self.repo / "packages/ondevice-engine/build/native-candidate-provenance.json").exists())


if __name__ == "__main__":
    unittest.main()
