#!/usr/bin/env python3
"""Find an exact-input, successful full ARM64 candidate; never download or install it.

The returned immutable IDs must still pass download_issue4_native.py and
verify_native_candidate.py before product linkage. No match is an error.
"""
import argparse
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/ondevice-engine/scripts'))
import verify_native_candidate as candidate
import wait_issue4_native as gate


def find(repo, get_json, *, timeout=60):
    if not 1 <= timeout <= 300:
        raise ValueError('Native lookup timeout must be 1..300 seconds')
    deadline = time.monotonic() + timeout
    def fetch(path):
        if time.monotonic() >= deadline:
            raise TimeoutError('Native candidate lookup deadline expired')
        return get_json(path, deadline=deadline)
    listing = fetch('/actions/workflows/magicmobile-far-calls.yml/runs?event=workflow_dispatch&status=success&per_page=30')
    for run in listing.get('workflow_runs', []):
        if time.monotonic() >= deadline:
            raise TimeoutError('Native candidate lookup deadline expired')
        commit = run.get('head_sha', '')
        run_id = run.get('id')
        if type(run_id) is not int or run_id <= 0 or not re.fullmatch('[a-f0-9]{40}', commit):
            continue
        try:
            gate.validate_run(run, run_id, commit)
            if run.get('status') != 'completed' or run.get('conclusion') != 'success':
                continue
            # This guard covers all engine/compiler inputs, including new files.
            identity = candidate.source_identity(repo, commit)
            attempt = gate.validate_attempt(run, run_id, commit, deadline=deadline)
            if attempt != 1:
                continue  # no candidate artifact attribution across reruns
            artifacts = fetch(f'/actions/runs/{run_id}/artifacts?per_page=100').get('artifacts', [])
            name = 'issue4-full-native-candidate-' + commit
            found = [a for a in artifacts if a.get('name') == name and not a.get('expired')]
            if len(found) != 1:
                continue
            artifact = found[0]
            if (artifact.get('workflow_run', {}).get('id') != run_id
                    or type(artifact.get('id')) is not int or artifact['id'] <= 0
                    or not re.fullmatch('sha256:[a-f0-9]{64}', artifact.get('digest', ''))):
                continue
            return {'runID': run_id, 'runAttempt': attempt, 'engineCommit': commit,
                    'artifactID': artifact['id'], 'artifactDigest': artifact['digest'],
                    'equivalentInputTreeSHA256': identity['equivalentInputTreeSHA256'],
                    'scope': 'Native candidate provenance only; download, receipt validation and native execution pending'}
        except (ValueError, OSError, KeyError, subprocess.CalledProcessError):
            continue
    raise ValueError('No successful exact-input native candidate with complete trusted evidence')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=60)
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        parser.error('Output manifest already exists; choose a new path')
    receipt = find(candidate.ROOT, gate.get_json, timeout=args.timeout)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as output:
        output.write(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    dest = 'packages/ondevice-engine/build/reused-native-candidate'
    provenance = 'packages/ondevice-engine/build/reused-native-provenance.json'
    print('Exact-input native candidate found. From repository root, with GH_TOKEN set:')
    print('python3 packages/ondevice-engine/scripts/download_issue4_native.py'
          f" --artifact-id {receipt['artifactID']} --digest {shlex.quote(receipt['artifactDigest'])}"
          f' --destination {shlex.quote(dest)}')
    print('python3 packages/ondevice-engine/scripts/verify_native_candidate.py'
          f' --directory {shlex.quote(dest)} --engine-commit {receipt["engineCommit"]}'
          f' --run-id {receipt["runID"]} --artifact-id {receipt["artifactID"]}'
          f' --artifact-digest {shlex.quote(receipt["artifactDigest"])}'
          f' --output {shlex.quote(provenance)}')
    print('Manifest: ' + str(args.output) + '; native runtime execution remains unverified')


if __name__ == '__main__':
    main()
