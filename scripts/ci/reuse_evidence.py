#!/usr/bin/env python3
"""Reuse a successful main-branch job only with exact tracked inputs and GitHub evidence.

PRs always execute checks. A failed or malformed lookup is a cache miss.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.request
import zipfile
from io import BytesIO

REPO = 'ineedsomesleep5/MagicMobile'
WORKFLOW = '.github/workflows/magicmobile-ondevice.yml'
JOBS = {
    'boundary-tests': ('packages/ondevice-engine',),
    'real-jvm': ('packages/ondevice-engine',),
    'swift': ('packages/ondevice-engine', 'apps/ios', 'apps/ios-ondevice', 'scripts/deck-studio'),
}
POLICY = 'ci-evidence-v1'
API = f'https://api.github.com/repos/{REPO}'
ROOT = Path(__file__).resolve().parents[2]
MAX_AGE_SECONDS = 7 * 24 * 60 * 60
LOOKUP_DEADLINE = None


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()


def fingerprint(commit, job):
    if job not in JOBS or not re.fullmatch('[0-9a-f]{40}', commit):
        raise ValueError('Invalid job or commit')
    # Blob identities, paths and modes; the complete workflow guards steps,
    # action versions, runner labels, permissions and this helper's behavior.
    paths = (WORKFLOW, 'scripts/ci', *JOBS[job])
    tree = subprocess.check_output(['git', '-C', str(ROOT), 'ls-tree', '-r', '-z', commit, '--', *paths])
    if not tree or not any(row.endswith(b'\t' + WORKFLOW.encode())
                           for row in tree.split(b'\0') if row):
        raise ValueError('Missing workflow input')
    return hashlib.sha256(POLICY.encode() + b'\0' + job.encode() + b'\0' + tree).hexdigest()


def toolchain(job):
    commands = [['uname', '-srm'], ['java', '-version']]
    if job == 'swift':
        commands += [['sw_vers', '-productVersion'], ['xcodebuild', '-version'],
                     ['swift', '--version'], ['xcodegen', '--version']]
    result = {'imageOS': os.environ.get('ImageOS', ''),
              'imageVersion': os.environ.get('ImageVersion', ''),
              'runnerArch': os.environ.get('RUNNER_ARCH', '')}
    if job == 'swift':
        result['developerDir'] = os.environ.get('DEVELOPER_DIR', '')
    for command in commands:
        proc = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, check=True, timeout=10)
        result[command[0]] = proc.stdout.strip()
    if not all(result.values()):
        raise ValueError('Runner image or toolchain identity missing')
    return result


class NoTokenRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        if not new_url.startswith('https://'):
            raise ValueError('Non-HTTPS artifact redirect')
        redirected = super().redirect_request(request, fp, code, message, headers, new_url)
        if redirected:
            redirected.remove_header('Authorization')
        return redirected


OPENER = urllib.request.build_opener(NoTokenRedirect())


def get(path, *, binary=False):
    remaining = 30 if LOOKUP_DEADLINE is None else min(30, LOOKUP_DEADLINE - time.monotonic())
    if remaining <= 0:
        raise TimeoutError('CI evidence lookup budget exhausted; execute checks')
    request = urllib.request.Request(API + path, headers={
        'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
    })
    with OPENER.open(request, timeout=remaining) as response:
        payload = response.read(2 * 1024 * 1024 + 1)
    if len(payload) > 2 * 1024 * 1024:
        raise ValueError('Oversized CI evidence')
    return payload if binary else json.loads(payload)


def trusted_run(run):
    return (isinstance(run, dict)
            and isinstance(run.get('repository'), dict)
            and isinstance(run.get('head_repository'), dict)
            and run.get('repository', {}).get('full_name') == REPO
            and run.get('head_repository', {}).get('full_name') == REPO
            and run.get('path') == WORKFLOW and run.get('event') == 'push'
            and run.get('head_branch') == 'main' and run.get('status') == 'completed'
            and run.get('conclusion') == 'success' and run.get('run_attempt') == 1
            and type(run.get('id')) is int and run['id'] > 0
            and isinstance(run.get('head_sha'), str)
            and bool(re.fullmatch('[0-9a-f]{40}', run.get('head_sha', '')))
            and isinstance(run.get('created_at'), str)
            and recent(run['created_at']))


def recent(iso):
    try:
        from datetime import datetime, timezone
        age = time.time() - datetime.fromisoformat(iso.replace('Z', '+00:00')).timestamp()
        return 0 <= age <= MAX_AGE_SECONDS
    except (ValueError, TypeError):
        return False


def valid_receipt(run, job, current_fingerprint, current_toolchain):
    run_id = run['id']
    jobs = get(f'/actions/runs/{run_id}/attempts/1/jobs?per_page=100')
    if not isinstance(jobs, dict) or not isinstance(jobs.get('jobs'), list):
        return None
    matched = [item for item in jobs['jobs'] if isinstance(item, dict) and item.get('name') == job]
    if len(matched) != 1 or matched[0].get('run_id') != run_id or matched[0].get('conclusion') != 'success' or matched[0].get('status') != 'completed':
        return None
    listing = get(f'/actions/runs/{run_id}/artifacts?per_page=100')
    if not isinstance(listing, dict) or not isinstance(listing.get('artifacts'), list):
        return None
    name = f'ci-evidence-{job}-{run_id}'
    found = [item for item in listing['artifacts'] if isinstance(item, dict)
             and item.get('name') == name and not item.get('expired')]
    if len(found) != 1:
        return None
    artifact = found[0]
    if (not isinstance(artifact.get('workflow_run'), dict)
            or artifact['workflow_run'].get('id') != run_id
            or type(artifact.get('id')) is not int or artifact['id'] <= 0
            or not isinstance(artifact.get('digest'), str)
            or not re.fullmatch('sha256:[0-9a-f]{64}', artifact.get('digest', ''))):
        return None
    payload = get(f"/actions/artifacts/{artifact['id']}/zip", binary=True)
    if 'sha256:' + hashlib.sha256(payload).hexdigest() != artifact['digest']:
        return None
    with zipfile.ZipFile(BytesIO(payload)) as archive:
        if archive.namelist() != ['receipt.json']:
            return None
        info = archive.getinfo('receipt.json')
        if info.file_size > 64 * 1024:
            return None
        with archive.open(info) as stream:
            body = stream.read(64 * 1024 + 1)
        if len(body) > 64 * 1024:
            return None
        receipt = json.loads(body)
    expected = {'schema': 1, 'job': job, 'commit': run['head_sha'],
                'runID': run_id, 'fingerprint': current_fingerprint,
                'toolchain': current_toolchain, 'scope': 'CI job success only'}
    return {'runID': run_id, 'artifactID': artifact['id'],
            'artifactDigest': artifact['digest']} if receipt == expected else None


def reusable(job, commit):
    global LOOKUP_DEADLINE
    LOOKUP_DEADLINE = time.monotonic() + 60
    current = fingerprint(commit, job)
    current_toolchain = toolchain(job)
    listing = get('/actions/workflows/magicmobile-ondevice.yml/runs?branch=main&event=push&status=success&per_page=30')
    if not isinstance(listing, dict) or not isinstance(listing.get('workflow_runs'), list):
        return None
    for run in listing['workflow_runs']:
        if time.monotonic() >= LOOKUP_DEADLINE:
            return None
        try:
            if (trusted_run(run) and run['head_sha'] != commit
                    and fingerprint(run['head_sha'], job) == current
                    and (evidence := valid_receipt(run, job, current, current_toolchain))):
                return evidence
        except (ValueError, TypeError, AttributeError, KeyError, OSError,
                subprocess.CalledProcessError, subprocess.TimeoutExpired, zipfile.BadZipFile):
            continue
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('check', 'write'))
    parser.add_argument('--job', choices=JOBS, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    commit = git('rev-parse', 'HEAD')
    if args.mode == 'check':
        reused = None
        if (os.environ.get('GITHUB_EVENT_NAME') == 'push'
                and os.environ.get('GITHUB_REF') == 'refs/heads/main'
                and os.environ.get('GITHUB_REPOSITORY') == REPO):
            try:
                reused = reusable(args.job, commit)
            except (ValueError, TypeError, AttributeError, KeyError, OSError,
                    subprocess.CalledProcessError, subprocess.TimeoutExpired, zipfile.BadZipFile):
                pass
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
                output.write(f"reused={'true' if reused else 'false'}\n")
                if reused:
                    output.write(f"source_run_id={reused['runID']}\nsource_artifact_id={reused['artifactID']}\nsource_artifact_digest={reused['artifactDigest']}\n")
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
                if reused:
                    summary.write(f"### {args.job}: reused CI evidence\n\n"
                                  f"Original run: `{reused['runID']}`; artifact: `{reused['artifactID']}`; "
                                  f"digest: `{reused['artifactDigest']}`. Exact inputs, runner toolchain, and job success verified.\n")
                else:
                    summary.write(f'### {args.job}: checks required\n\nNo reusable trusted evidence matched; subsequent steps must execute.\n')
        print(f'{args.job}: ' + (f'reused trusted evidence {reused}' if reused else 'execute checks'))
    else:
        if not args.output or os.environ.get('GITHUB_EVENT_NAME') != 'push' or os.environ.get('GITHUB_REF') != 'refs/heads/main':
            raise ValueError('Receipts are written only on trusted main pushes')
        receipt = {'schema': 1, 'job': args.job, 'commit': commit,
                   'runID': int(os.environ['GITHUB_RUN_ID']),
                   'fingerprint': fingerprint(commit, args.job),
                   'toolchain': toolchain(args.job), 'scope': 'CI job success only'}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(receipt, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
