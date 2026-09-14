#!/usr/bin/env python3
"""Wait for one explicitly pinned GitHub engine build; never dispatch a workflow.

Only the new gated producer is eligible. Historical ungated native runs require
recorded evidence and a separate independent manual review; this helper never
silently treats them as eligible future build evidence. Successful named steps
prove recorded execution status, not source semantics. The immutable candidate
and its workflow must still be explicitly reviewed by the human/root reviewer.
"""
import argparse
from collections import Counter
import json
import math
import os
from pathlib import Path
import re
import time
import urllib.request
import urllib.error

REPOSITORY = 'ineedsomesleep5/MagicMobile'
API = f'https://api.github.com/repos/{REPOSITORY}'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Even a same-host repository rename must not forward the bearer token.
        return None


API_OPENER = urllib.request.build_opener(NoRedirect())
# Only the explicitly gated producer is accepted. Historical compiler-only runs
# need separate historical inspection; they cannot satisfy this future-build gate.
REQUIRED_STEPS = {
    'approve-candidate': (
        'Require an immutable reviewed policy pin',
        'Check out trusted approval policy only',
        'Validate explicit candidate and completed cheap evidence',
    ),
    'compiler-probe': (
        'Record source and run actual layout-planner tests',
        'Fetch checksum-pinned compiler',
        'Build private compiler backport',
        'Verify bounded builder-heap regression (not engine execution)',
        'Force veneers in a separate unsigned ARM64 toolchain-only probe',
        'Compile full pinned engine including AI',
        'Execute real JVM regressions (not native acceptance)',
        'Reproduce and verify native Color compatibility (not iPhone acceptance)',
        'Verify real token repository resource inclusion (not iPhone acceptance)',
        'Verify bundled catalogue native decoding (not engine or iPhone acceptance)',
        'Build full ARM64 engine using verified compiler backport',
        'Preserve successful archive and paired build inputs',
        # Both existing uploads have the same default Actions step name.
        'Run actions/upload-artifact@v4',
        'Run actions/upload-artifact@v4',
    ),
}


def _number(value):
    try:
        number = float(value)
        return number if math.isfinite(number) and number >= 0 else None
    except (TypeError, ValueError):
        return None


def _retry_delay(error, attempt):
    """Retry only transient GET failures; never convert a failed build into success."""
    backoff = 2 ** (attempt + 1)
    if isinstance(error, urllib.error.HTTPError):
        headers = {key.lower(): value for key, value in (error.headers or {}).items()}
        limited = error.code == 429 or (error.code == 403 and (
            'retry-after' in headers or headers.get('x-ratelimit-remaining') == '0'))
        if not limited and error.code not in (408, 500, 502, 503, 504):
            return None
        hints = []
        retry_after = _number(headers.get('retry-after'))
        if retry_after is not None:
            hints.append(retry_after)
        if headers.get('x-ratelimit-remaining') == '0':
            reset = _number(headers.get('x-ratelimit-reset'))
            if reset is not None:
                hints.append(max(0, reset - time.time()))
        # GitHub requires at least one minute for rate limits without a usable hint.
        return max(backoff, *hints) if hints else max(backoff, 60 * 2 ** attempt if limited else 0)
    return backoff


def get_json(path, *, deadline=None):
    if deadline is None:
        deadline = time.monotonic() + 300
    request = urllib.request.Request(API + path, headers={
        'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28',
        'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
    })
    for attempt in range(5):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Pinned native gate deadline expired before its API request')
        try:
            with API_OPENER.open(request, timeout=min(60, remaining)) as response:
                value = json.load(response)
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            try:
                delay = _retry_delay(error, attempt)
            finally:
                if isinstance(error, urllib.error.HTTPError):
                    error.close()
            if delay is None or attempt == 4:
                raise
            if delay >= deadline - time.monotonic():
                raise TimeoutError('API retry would exceed the pinned native gate deadline') from error
            # Do not print credentials, response bodies or private exception contents.
            print(f'Transient GitHub API failure; retry {attempt + 1}/4 after {delay:g}s', flush=True)
            time.sleep(delay)
            continue
        if time.monotonic() >= deadline:
            raise TimeoutError('API response arrived after the pinned native gate deadline')
        return value


def validate_run(run, run_id, commit):
    if (run.get('id') != run_id or run.get('head_sha') != commit
            or run.get('repository', {}).get('full_name') != REPOSITORY
            or run.get('head_repository', {}).get('full_name') != REPOSITORY
            or run.get('path') != '.github/workflows/magicmobile-far-calls.yml'):
        raise ValueError('Native run identity differs from the pinned build')


def validate_attempt(run, run_id, commit, *, deadline):
    """Require successful critical work from this attempt, never blended reruns."""
    attempt = run.get('run_attempt')
    if type(attempt) is not int or attempt <= 0 or run.get('event') != 'workflow_dispatch':
        raise ValueError('A manually gated native producer with an exact attempt is required')
    jobs = []
    for page in range(1, 101):
        result = get_json(f'/actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100&page={page}', deadline=deadline)
        batch = result.get('jobs')
        count = result.get('total_count')
        if not isinstance(batch, list) or type(count) is not int or count < 0:
            raise ValueError('Malformed native job evidence')
        jobs.extend(batch)
        if len(jobs) == count:
            break
        if not batch or len(jobs) > count:
            raise ValueError('Incomplete native job evidence')
    else:
        raise ValueError('Native job evidence exceeds pagination limit')
    if any(type(job.get('id')) is not int or job['id'] <= 0 for job in jobs) or len({job['id'] for job in jobs}) != len(jobs):
        raise ValueError('Invalid or duplicate native job identities')
    for name, required in REQUIRED_STEPS.items():
        selected = [job for job in jobs if job.get('name') == name]
        if len(selected) != 1:
            raise ValueError('Missing or duplicate required native job: ' + name)
        job = selected[0]
        if (job.get('run_id') != run_id or job.get('head_sha') != commit
                or job.get('run_attempt', attempt) != attempt
                or job.get('status') != 'completed' or job.get('conclusion') != 'success'):
            raise ValueError('Required native job did not succeed for this source/attempt: ' + name)
        steps = job.get('steps')
        if not isinstance(steps, list):
            raise ValueError('Missing native step evidence: ' + name)
        for step_name, expected in Counter(required).items():
            matches = [step for step in steps if step.get('name') == step_name]
            if len(matches) != expected or any(step.get('status') != 'completed' or step.get('conclusion') != 'success' for step in matches):
                raise ValueError('Missing, duplicated, skipped or unsuccessful critical native step: ' + step_name)
    return attempt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-id', type=int, required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--timeout', type=int, default=10800)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.run_id <= 0 or not re.fullmatch('[a-f0-9]{40}', args.commit) or not 1 <= args.timeout <= 12600:
        parser.error('Exact run/commit and bounded timeout required')
    deadline = time.monotonic() + args.timeout
    previous = None
    while True:
        run = get_json(f'/actions/runs/{args.run_id}', deadline=deadline)
        validate_run(run, args.run_id, args.commit)
        state = (run.get('status'), run.get('conclusion'))
        if state != previous:
            print(f'Pinned native build {args.run_id}: {state}', flush=True)
            previous = state
        if state[0] == 'completed':
            if state[1] != 'success':
                raise SystemExit('Full native workflow did not succeed; product gate remains blocked')
            attempt = validate_attempt(run, args.run_id, args.commit, deadline=deadline)
            name = 'issue4-full-native-candidate-' + args.commit
            artifacts = get_json(f'/actions/runs/{args.run_id}/artifacts?per_page=100', deadline=deadline)['artifacts']
            selected = [item for item in artifacts if item.get('name') == name and not item.get('expired')]
            if len(selected) != 1:
                raise SystemExit('Expected one unexpired full-engine artifact')
            artifact = selected[0]
            if not re.fullmatch('sha256:[a-f0-9]{64}', artifact.get('digest', '')):
                raise SystemExit('Missing artifact digest')
            current = get_json(f'/actions/runs/{args.run_id}', deadline=deadline)
            validate_run(current, args.run_id, args.commit)
            if current.get('run_attempt') != attempt or current.get('status') != 'completed' or current.get('conclusion') != 'success':
                raise ValueError('Native run changed during artifact inspection; approval remains blocked')
            receipt = {'repository': REPOSITORY, 'runID': args.run_id, 'commit': args.commit,
                       'runAttempt': attempt,
                       'artifactID': artifact['id'], 'artifactDigest': artifact['digest'],
                       'artifactName': name, 'nativeRuntimeTested': False}
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(receipt, indent=2) + '\n')
            if os.environ.get('GITHUB_OUTPUT'):
                with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
                    output.write(f"artifact_id={artifact['id']}\nartifact_digest={artifact['digest']}\n")
            print('Pinned full-engine artifact ready for inspection and unsigned product link', flush=True)
            return
        if time.monotonic() >= deadline:
            raise SystemExit('Full native build has no successful conclusion before this gate deadline')
        time.sleep(min(60, max(1, deadline - time.monotonic())))


if __name__ == '__main__':
    main()
