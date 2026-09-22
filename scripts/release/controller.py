#!/usr/bin/env python3
"""Local, fail-closed wrapper for the existing MagicMobile release scripts.

No command here prepares a build number, signs, uploads, or distributes by itself.
The only mutation path invokes an existing guarded script once, after an exact
fingerprint is explicitly authorized. An interrupted invocation is never retried.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

REPO = Path(__file__).resolve().parents[2]
SCRIPT = {
    "ios": "scripts/ios/deploy-testflight.sh",
    "android": "scripts/android/build_release.sh",
}
INPUTS = {
    "ios": (
        "packages/ondevice-engine/build/native-candidate-provenance.json",
        "apps/ios/NativeEngine/manifest.json",
        "release/testflight/ExportOptionsExternal.plist",
    ),
    "android": ("apps/android/native-artifact/manifest.json",),
}
RUN_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}\Z")
SHA = re.compile(r"[a-f0-9]{64}\Z")


class ReleaseError(Exception):
    pass


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def checked_file(repo: Path, relative: str) -> Path:
    path = repo / relative
    if not path.resolve().is_relative_to(repo.resolve()) or not path.is_file():
        raise ReleaseError(f"Missing or escaping release input: {relative}")
    if any(part.is_symlink() for part in (path, *path.parents) if part.is_relative_to(repo)):
        raise ReleaseError(f"Symlinked release input: {relative}")
    return path


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True)
    if result.returncode:
        raise ReleaseError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.rstrip("\n")


def identity(repo: Path, platform: str, *, after_upload: bool = False) -> dict:
    if git(repo, "rev-parse", "--show-toplevel") != str(repo.resolve()):
        raise ReleaseError("Controller is not using the selected Git root")
    head = git(repo, "rev-parse", "HEAD")
    changes = git(repo, "status", "--porcelain=v1", "--untracked-files=normal").splitlines()
    if changes and not (after_upload and platform == "ios" and
                        changes == [" M release/testflight/build-ledger.json"]):
        raise ReleaseError("Release source is dirty outside the recorded iOS upload ledger")
    paths = [*INPUTS[platform], SCRIPT[platform]]
    hashes = {name: sha(checked_file(repo, name)) for name in paths}
    if platform == "android":
        manifest = json.loads(checked_file(repo, INPUTS["android"][0]).read_text())
        if manifest.get("schema") != 1 or manifest.get("target") != "android-arm64":
            raise ReleaseError("Invalid Android native manifest")
        files = manifest.get("files")
        if not isinstance(files, dict) or not files:
            raise ReleaseError("Android native manifest has no files")
        for name, expected in files.items():
            if not isinstance(name, str) or name.startswith("/") or ".." in Path(name).parts or not SHA.fullmatch(str(expected)):
                raise ReleaseError("Invalid Android native manifest entry")
            relative = f"apps/android/native-artifact/{name}"
            actual = sha(checked_file(repo, relative))
            if actual != expected:
                raise ReleaseError(f"Android native input changed: {name}")
            hashes[relative] = actual
    else:
        manifest = json.loads(checked_file(repo, "apps/ios/NativeEngine/manifest.json").read_text())
        files = manifest.get("files")
        if manifest.get("schema") != 1 or not isinstance(files, dict) or not files:
            raise ReleaseError("Invalid iOS native manifest")
        for name, row in files.items():
            if not isinstance(name, str) or name.startswith("/") or ".." in Path(name).parts or not isinstance(row, dict) or not SHA.fullmatch(str(row.get("sha256"))):
                raise ReleaseError("Invalid iOS native manifest entry")
            relative = f"apps/ios/NativeEngine/{name}"
            actual = sha(checked_file(repo, relative))
            if actual != row["sha256"]:
                raise ReleaseError(f"iOS native input changed: {name}")
            hashes[relative] = actual
    config = {}
    if platform == "android":
        code = os.environ.get("MM_ANDROID_VERSION_CODE", "")
        version = os.environ.get("MM_ANDROID_VERSION_NAME", "")
        if not re.fullmatch(r"[1-9][0-9]{0,9}", code) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", version):
            raise ReleaseError("Set exact MM_ANDROID_VERSION_CODE and MM_ANDROID_VERSION_NAME before planning")
        config = {"versionCode": code, "versionName": version,
                  "keyAlias": os.environ.get("MM_ANDROID_KEY_ALIAS", "magicmobile")}
    payload = {"schema": 1, "checkout": str(repo.resolve()), "platform": platform,
               "sourceCommit": head, "inputSHA256": hashes, "config": config}
    return {**payload, "fingerprint": hashlib.sha256(canonical(payload)).hexdigest()}


def run_dir(repo: Path, run_id: str) -> Path:
    if not RUN_ID.fullmatch(run_id) or run_id in (".", ".."):
        raise ReleaseError("Invalid run ID")
    directory = repo / "build_output/release-controller" / run_id
    if any(path.is_symlink() for path in (directory, *directory.parents)
           if path.is_relative_to(repo)):
        raise ReleaseError("Symlinked release state directory")
    return directory


def events(directory: Path) -> list[dict]:
    folder = directory / "events"
    if folder.is_symlink():
        raise ReleaseError("Symlinked evidence directory")
    if not folder.exists():
        return []
    names = sorted(folder.iterdir())
    if any(p.is_symlink() or not p.is_file() for p in names):
        raise ReleaseError("Invalid evidence entry")
    records = []
    previous = "0" * 64
    for number, path in enumerate(names, 1):
        if path.name != f"{number:06d}.json":
            raise ReleaseError("Evidence sequence is incomplete")
        record = json.loads(path.read_bytes())
        digest = record.pop("recordSHA256", None)
        if record.get("sequence") != number or record.get("previousSHA256") != previous or digest != hashlib.sha256(canonical(record)).hexdigest():
            raise ReleaseError("Evidence chain failed verification")
        record["recordSHA256"] = digest
        records.append(record)
        previous = digest
    return records


def append(directory: Path, kind: str, details: dict) -> dict:
    history = events(directory)
    record = {"schema": 1, "sequence": len(history) + 1,
              "previousSHA256": history[-1]["recordSHA256"] if history else "0" * 64,
              "timeUTC": datetime.now(timezone.utc).isoformat(), "kind": kind, **details}
    record["recordSHA256"] = hashlib.sha256(canonical(record)).hexdigest()
    folder = directory / "events"
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{record['sequence']:06d}.json"
    with path.open("xb") as output:
        output.write(canonical(record) + b"\n")
        output.flush()
        os.fsync(output.fileno())
    fd = os.open(folder, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
    return record


def default_runner(command: list[str], log: Path) -> int:
    with log.open("xb") as output:
        result = subprocess.run(command, cwd=REPO, stdout=output, stderr=subprocess.STDOUT, check=False)
        output.flush()
        os.fsync(output.fileno())
    return result.returncode


def ios_root(repo: Path, log: Path) -> Path:
    lines = log.read_text(errors="replace").splitlines()
    roots = [line.removeprefix("Release evidence: ") for line in lines if line.startswith("Release evidence: ")]
    if len(roots) != 1:
        raise ReleaseError("Expected one iOS release evidence directory")
    root = Path(roots[0])
    allowed = repo / "build_output/testflight"
    if not root.is_absolute() or not root.resolve().is_relative_to(allowed.resolve()) or root.is_symlink():
        raise ReleaseError("iOS release evidence escaped the selected checkout")
    return root


def artifacts(repo: Path, platform: str, log: Path, *, distributed: bool = False) -> dict:
    paths: dict[str, Path] = {"controllerLog": log}
    if platform == "android":
        paths["signedAPK"] = repo / "apps/android/app/build/outputs/apk/release/app-release.apk"
    else:
        root = ios_root(repo, log)
        paths.update({name: root / relative for name, relative in {
            "signedIPA": "export/MagicMobile.ipa",
            "signedReceipt": "signed-receipt.json",
            "uploadInputReceipt": "upload-input-receipt.json",
            "uploadLog": "altool-upload.log",
        }.items()})
        if distributed:
            paths.update({name: root / relative for name, relative in {
                "distribution": "testflight-distribution.json", "groups": "testflight-groups.json",
                "review": "beta-app-review.json", "appleBuild": "apple-build.json"}.items()})
    return {name: {"path": str(path), "sha256": sha(checked_file(repo, str(path.relative_to(repo))))}
            for name, path in paths.items()}


def upload_details(repo: Path, root: Path, evidence: dict, original: dict) -> dict:
    receipt = json.loads((root / "signed-receipt.json").read_text())
    upload_input = json.loads((root / "upload-input-receipt.json").read_text())
    ipa = root / "export/MagicMobile.ipa"
    if receipt.get("bundleID") != "com.calebfeliciano.magicmobile" or not receipt.get("appVersion") or not receipt.get("appBuild"):
        raise ReleaseError("Signed receipt has wrong app identity")
    if receipt.get("ipaSHA256") != sha(ipa) or upload_input.get("ipaSHA256") != receipt["ipaSHA256"]:
        raise ReleaseError("Signed IPA differs from upload receipts")
    match = re.search(r"Delivery UUID:\s*([0-9a-fA-F-]{36})", (root / "altool-upload.log").read_text())
    if not match:
        raise ReleaseError("Upload log has no delivery UUID; manual reconciliation required")
    delivery = match.group(1).lower()
    ledger_path = repo / "release/testflight/build-ledger.json"
    before = json.loads(subprocess.check_output(
        ["git", "-C", str(repo), "show", f"{original['sourceCommit']}:release/testflight/build-ledger.json"], text=True))
    after = json.loads(ledger_path.read_text())
    allowed = {"bundleId", "marketingVersion", "lastPreparedBuild", "lastPreparedMarketingVersion",
               "lastUploadedBuild", "lastUploadedMarketingVersion", "uploads"}
    if {k: v for k, v in before.items() if k not in allowed} != {k: v for k, v in after.items() if k not in allowed}:
        raise ReleaseError("Upload ledger contains unrelated edits")
    previous = [row for row in before.get("uploads", []) if not (str(row.get("build")) == str(receipt["appBuild"]) and row.get("marketingVersion") == receipt["appVersion"])]
    rows = after.get("uploads", [])
    matching = [row for row in rows if str(row.get("build")) == str(receipt["appBuild"]) and row.get("marketingVersion") == receipt["appVersion"]]
    if len(matching) != 1 or [row for row in rows if row not in matching] != previous or matching[0].get("deliveryUuid", "").lower() != delivery:
        raise ReleaseError("Upload ledger does not match this exact delivery")
    if (matching[0].get("ipaPath") != str(ipa.relative_to(repo))
            or str(after.get("lastUploadedBuild")) != str(receipt["appBuild"])
            or after.get("lastUploadedMarketingVersion") != receipt["appVersion"]
            or str(after.get("lastPreparedBuild")) != str(receipt["appBuild"])
            or after.get("lastPreparedMarketingVersion") != receipt["appVersion"]
            or after.get("marketingVersion") != receipt["appVersion"]
            or after.get("bundleId") != "com.calebfeliciano.magicmobile"
            or str(before.get("lastPreparedBuild")) != str(receipt["appBuild"])):
        raise ReleaseError("Upload ledger points to a different IPA/build")
    return {"version": receipt["appVersion"], "build": str(receipt["appBuild"]),
            "deliveryUuid": delivery, "releaseRoot": str(root), "ipaSHA256": receipt["ipaSHA256"],
            "ledgerSHA256": sha(ledger_path), "evidence": evidence}


def verify_apple_build(observed: dict, upload: dict) -> None:
    rows = observed.get("data")
    if not isinstance(rows, list) or len(rows) != 1:
        raise ReleaseError("Apple returned no unique exact build")
    row = rows[0]
    attributes = row.get("attributes", {})
    version_id = row.get("relationships", {}).get("preReleaseVersion", {}).get("data", {}).get("id")
    versions = [item for item in observed.get("included", [])
                if item.get("type") == "preReleaseVersions" and item.get("id") == version_id]
    if (row.get("type") != "builds" or str(row.get("id", "")).lower() != upload["deliveryUuid"]
            or str(attributes.get("version")) != upload["build"]
            or attributes.get("processingState") != "VALID"
            or len(versions) != 1 or versions[0].get("attributes", {}).get("version") != upload["version"]):
        raise ReleaseError("Apple build does not match exact delivered version, build, and UUID")


def read_apple_build(version: str, build: str) -> dict:
    result = subprocess.run(["asc", "builds", "list", "--app", "6784735182", "--version", version,
                             "--build-number", build, "--platform", "IOS", "--include", "preReleaseVersion",
                             "--paginate", "--output", "json"],
                            capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise ReleaseError(f"Apple exact-build lookup failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


class Controller:
    def __init__(self, repo: Path, runner=None):
        self.repo = repo.resolve()
        self.runner = runner or default_runner

    def plan(self, platform: str, run_id: str | None = None) -> dict:
        history = events(run_dir(self.repo, run_id)) if run_id else []
        after_upload = bool(history and platform == "ios" and history[-1]["kind"] in
                            ("started", "uncertain", "uploaded", "distribution-started", "completed"))
        current = identity(self.repo, platform, after_upload=after_upload)
        state = history[-1]["kind"] if history else "new"
        stale = bool(history and history[0]["identity"] != current)
        if state == "completed" and not self.completion_fresh(history):
            stale = True
        return {"identity": current, "runId": run_id, "state": "stale" if stale else state,
                "next": "reconcile upload; never retry" if state in ("started", "uncertain") else
                        "authorize guarded distribution" if state == "uploaded" else
                        "already complete" if state == "completed" and not stale else
                        "authorize one guarded invocation" if state == "new" else "stop"}

    def completion_fresh(self, history: list[dict]) -> bool:
        original = history[0]["identity"]
        try:
            if identity(self.repo, original["platform"], after_upload=original["platform"] == "ios") != original:
                return False
            for record in history:
                if record.get("kind") == "uploaded" and record.get("ledgerSHA256") != sha(self.repo / "release/testflight/build-ledger.json"):
                    return False
                for item in record.get("evidence", {}).values():
                    path = Path(item["path"])
                    if not path.is_relative_to(self.repo) or sha(checked_file(self.repo, str(path.relative_to(self.repo)))) != item["sha256"]:
                        return False
            return True
        except (ReleaseError, OSError, ValueError, KeyError):
            return False

    def status(self, run_id: str) -> dict:
        history = events(run_dir(self.repo, run_id))
        if not history:
            return {"runId": run_id, "state": "new", "events": []}
        platform = history[0]["identity"]["platform"]
        try:
            after_upload = platform == "ios" and history[-1]["kind"] in (
                "started", "uncertain", "uploaded", "distribution-started", "completed")
            stale = identity(self.repo, platform, after_upload=after_upload) != history[0]["identity"]
        except (ReleaseError, OSError, ValueError):
            stale = True
        if history[-1]["kind"] == "completed" and not self.completion_fresh(history):
            stale = True
        return {"runId": run_id, "state": "stale" if stale else history[-1]["kind"],
                "events": history}

    def resume(self, platform: str, run_id: str, expected: str) -> dict:
        directory = run_dir(self.repo, run_id)
        base = directory.parent
        base.mkdir(parents=True, exist_ok=True)
        if base.is_symlink() or directory.is_symlink():
            raise ReleaseError("Symlinked release state directory")
        lock = base / ".controller.lock"
        if lock.is_symlink():
            raise ReleaseError("Symlinked release lock")
        with lock.open("a+b") as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise ReleaseError("Another release controller holds the lock") from error
            history = events(directory)
            if history and history[0]["identity"]["platform"] != platform:
                raise ReleaseError("Run belongs to a different platform")
            if history and history[-1]["kind"] == "completed":
                return {"state": "completed" if self.completion_fresh(history) else "stale",
                        "action": "no-op", "runId": run_id}
            after_upload = bool(history and history[-1]["kind"] == "uploaded")
            current = identity(self.repo, platform, after_upload=after_upload)
            if history:
                if history[0]["identity"] != current:
                    append(directory, "invalidated", {"currentFingerprint": current["fingerprint"]})
                    raise ReleaseError("Run is stale; use a new run ID after reviewing the new plan")
            if expected != current["fingerprint"]:
                raise ReleaseError("Authorization fingerprint does not match current source and inputs")
            if history:
                if after_upload:
                    return self._distribute(directory, history, expected)
                raise ReleaseError("Prior invocation is unresolved; reconcile externally, never retry blindly")
            directory.mkdir(parents=True, exist_ok=True)
            append(directory, "planned", {"identity": current, "runId": run_id})
            command = [str(self.repo / SCRIPT[platform])]
            if platform == "ios":
                command.append("--stop-after-upload")
            append(directory, "started", {"command": command, "authorizationFingerprint": expected})
            log = directory / "upload-or-build.log"
            try:
                # The runner invokes the original script, including all of its release gates.
                code = self.runner(command, log)
                proof = artifacts(self.repo, platform, log) if code == 0 else {"controllerLog": {
                    "path": str(log), "sha256": sha(log)}} if log.exists() else {}
                if code != 0:
                    append(directory, "uncertain", {"exitCode": code, "evidence": proof})
                    raise ReleaseError("Guarded script failed; mutation outcome is uncertain and requires reconciliation")
                if platform == "ios":
                    details = upload_details(self.repo, ios_root(self.repo, log), proof, current)
                    append(directory, "uploaded", details)
                    return {"state": "uploaded", "runId": run_id, "upload": details,
                            "next": "resume with the same fingerprint to run guarded distribution"}
                append(directory, "completed", {"exitCode": 0, "evidence": proof})
                return {"state": "completed", "runId": run_id, "evidence": proof}
            except ReleaseError:
                if events(directory)[-1]["kind"] == "started":
                    append(directory, "uncertain", {"errorType": "ReleaseError", "logSHA256": sha(log) if log.exists() else None})
                raise
            except BaseException as error:
                append(directory, "uncertain", {"errorType": type(error).__name__,
                                                 "logSHA256": sha(log) if log.exists() else None})
                raise

    def _distribute(self, directory: Path, history: list[dict], expected: str) -> dict:
        uploaded = history[-1]
        root = Path(uploaded["releaseRoot"])
        log = directory / "upload-or-build.log"
        proof = artifacts(self.repo, "ios", log)
        if proof != uploaded["evidence"]:
            raise ReleaseError("Upload evidence changed after checkpoint")
        details = upload_details(self.repo, root, proof, history[0]["identity"])
        if any(details[key] != uploaded[key] for key in ("version", "build", "deliveryUuid", "ipaSHA256", "ledgerSHA256")):
            raise ReleaseError("Upload identity changed after checkpoint")
        command = [str(self.repo / "scripts/ios/distribute-testflight-groups.sh"),
                   "--version", uploaded["version"], "--build-number", uploaded["build"],
                   "--release-root", str(root)]
        append(directory, "distribution-started", {"command": command,
                                                    "authorizationFingerprint": expected})
        distribution_log = directory / "distribution.log"
        try:
            code = self.runner(command, distribution_log)
            if code:
                append(directory, "uncertain", {"stage": "distribution", "exitCode": code,
                                                 "logSHA256": sha(distribution_log) if distribution_log.exists() else None})
                raise ReleaseError("Distribution outcome uncertain; reconcile externally, never retry blindly")
            evidence = {name: {"path": str(path), "sha256": sha(checked_file(self.repo, str(path.relative_to(self.repo))))}
                        for name, path in {"distributionLog": distribution_log,
                                           "appleBuild": root / "apple-build.json",
                                           "groups": root / "testflight-groups.json",
                                           "review": root / "beta-app-review.json",
                                           "distribution": root / "testflight-distribution.json"}.items()}
            apple_build = json.loads((root / "apple-build.json").read_text())
            verify_apple_build(apple_build, uploaded)
            append(directory, "completed", {"stage": "distribution", "evidence": evidence})
            return {"state": "completed", "evidence": evidence}
        except ReleaseError:
            if events(directory)[-1]["kind"] == "distribution-started":
                append(directory, "uncertain", {"stage": "distribution", "errorType": "ReleaseError"})
            raise
        except BaseException as error:
            append(directory, "uncertain", {"stage": "distribution", "errorType": type(error).__name__})
            raise

    def reconcile(self, run_id: str, expected: str, apple_reader=None) -> dict:
        """Attach a verified exact Apple result after an uncertain upload.

        Requires a complete local upload receipt and matching ledger. An upload
        without these cannot be identified safely and remains unresolved.
        """
        directory = run_dir(self.repo, run_id)
        lock = directory.parent / ".controller.lock"
        if lock.is_symlink():
            raise ReleaseError("Symlinked release lock")
        with lock.open("a+b") as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise ReleaseError("Another release controller holds the lock") from error
            history = events(directory)
            if not history or history[-1]["kind"] != "uncertain" or history[0]["identity"]["platform"] != "ios":
                raise ReleaseError("Only an uncertain iOS upload can be reconciled")
            if history[-1].get("stage") == "distribution":
                raise ReleaseError("Distribution is uncertain; inspect Apple groups/review manually")
            original = history[0]["identity"]
            if expected != original["fingerprint"] or identity(self.repo, "ios", after_upload=True) != original:
                raise ReleaseError("Source/input identity changed before reconciliation")
            log = directory / "upload-or-build.log"
            proof = artifacts(self.repo, "ios", log)
            details = upload_details(self.repo, ios_root(self.repo, log), proof, original)
            reader = apple_reader or read_apple_build
            observed = reader(details["version"], details["build"])
            verify_apple_build(observed, details)
            details["appleEvidenceSHA256"] = hashlib.sha256(canonical(observed)).hexdigest()
            details["appleBuild"] = observed
            append(directory, "uploaded", details)
            return {"state": "uploaded", "runId": run_id, "upload": details}


def watch(repo: Path, run_id: str, service: str, run_number: str, timeout: int,
          interval: int = 10) -> dict:
    """Bounded polling of one existing GitHub Actions run; never starts a run."""
    if service != "github" or not run_number.isdecimal() or timeout < 1 or timeout > 60 or interval < 1 or interval > timeout:
        raise ReleaseError("Watcher requires an existing GitHub run ID, 1-60 second timeout, and bounded interval")
    directory = run_dir(repo, run_id)
    history = events(directory)
    if not history:
        raise ReleaseError("Watcher requires an existing controller run")
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ReleaseError("Watcher timed out before reading existing run")
        result = subprocess.run(["gh", "run", "view", run_number, "--json", "databaseId,status,conclusion,headSha,url"],
                                cwd=repo, capture_output=True, text=True, timeout=remaining)
        if result.returncode:
            raise ReleaseError(f"Existing run lookup failed: {result.stderr.strip()}")
        observed = json.loads(result.stdout)
        if str(observed.get("databaseId")) != run_number or observed.get("headSha") != history[0]["identity"]["sourceCommit"]:
            raise ReleaseError("Watcher run ID or source commit differs from controller identity")
        if observed.get("status") == "completed" or deadline - time.monotonic() <= interval:
            return {**observed, "watchTimedOut": observed.get("status") != "completed"}
        time.sleep(interval)


def status_summary(status: dict) -> dict:
    """Compact view of already-validated local history; never queries Apple."""
    history = status.get("events", [])
    original = history[0].get("identity", {}) if history else {}
    last = history[-1] if history else {}
    upload = next((record for record in reversed(history) if record["kind"] == "uploaded"), {})
    state = status["state"]
    next_action = {
        "new": "Plan exact source and complete prerequisite gates before authorizing a release.",
        "uploaded": "Resume the same fingerprint for distribution; do not upload again.",
        "started": "Inspect the running command or reconcile an interrupted upload; do not retry blindly.",
        "distribution-started": "Inspect the running distribution or exact Apple state; do not re-upload.",
        "uncertain": "Inspect exact external state and reconcile; never retry blindly.",
        "completed": "No further release mutation. Apple/device availability requires its own evidence.",
        "stale": "Historical evidence only; current source or evidence differs. Reassess before any mutation.",
    }.get(state, "Inspect full status before proceeding.")
    return {"runId": status["runId"], "state": state,
            "recordedStage": last.get("kind", "new"), "lastEventAt": last.get("timeUTC"),
            "sourceCommit": original.get("sourceCommit"), "fingerprint": original.get("fingerprint"),
            "platform": original.get("platform"), "eventCount": len(history),
            "uploadedBuild": {key: upload[key] for key in
                              ("version", "build", "deliveryUuid", "ipaSHA256", "releaseRoot") if key in upload},
            "next": next_action, "scope": "Verified local event history, not a fresh Apple or device check."}


def main() -> int:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    plan = sub.add_parser("plan", help="Read-only source/input plan")
    plan.add_argument("--platform", choices=SCRIPT, required=True)
    plan.add_argument("--run-id")
    status = sub.add_parser("status", help="Read-only immutable evidence status")
    status.add_argument("--run-id", required=True)
    status.add_argument("--summary", action="store_true", help="Compact local stage and next action; no external lookup")
    resume = sub.add_parser("resume", help="Invoke one guarded script, with explicit authorization")
    resume.add_argument("--platform", choices=SCRIPT, required=True)
    resume.add_argument("--run-id", required=True)
    resume.add_argument("--authorize-fingerprint", required=True, metavar="SHA256")
    reconcile = sub.add_parser("reconcile", help="Read Apple exact build and attach an uncertain upload result")
    reconcile.add_argument("--run-id", required=True)
    reconcile.add_argument("--authorize-fingerprint", required=True, metavar="SHA256")
    watcher = sub.add_parser("watch", help="Bounded read-only polling of an existing GitHub run")
    watcher.add_argument("--run-id", required=True)
    watcher.add_argument("--github-run-id", required=True)
    watcher.add_argument("--timeout-seconds", type=int, default=20)
    watcher.add_argument("--interval-seconds", type=int, default=10)
    args = parser.parse_args()
    try:
        controller = Controller(REPO)
        if args.action == "plan":
            output = controller.plan(args.platform, args.run_id)
        elif args.action == "status":
            output = controller.status(args.run_id)
            if args.summary:
                output = status_summary(output)
        elif args.action == "resume":
            output = controller.resume(args.platform, args.run_id, args.authorize_fingerprint)
        elif args.action == "reconcile":
            output = controller.reconcile(args.run_id, args.authorize_fingerprint)
        else:
            output = watch(REPO, args.run_id, "github", args.github_run_id,
                           args.timeout_seconds, args.interval_seconds)
        print(json.dumps(output, indent=2, sort_keys=True))
        return 0
    except (ReleaseError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"release controller: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
