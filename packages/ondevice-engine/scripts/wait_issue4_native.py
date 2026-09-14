#!/usr/bin/env python3
"""Wait for one explicitly pinned GitHub engine build; never dispatch a workflow."""
import argparse
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
            with urllib.request.urlopen(request, timeout=min(60, remaining)) as response:
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
            name = 'issue4-full-native-candidate-' + args.commit
            artifacts = get_json(f'/actions/runs/{args.run_id}/artifacts?per_page=100', deadline=deadline)['artifacts']
            selected = [item for item in artifacts if item.get('name') == name and not item.get('expired')]
            if len(selected) != 1:
                raise SystemExit('Expected one unexpired full-engine artifact')
            artifact = selected[0]
            if not re.fullmatch('sha256:[a-f0-9]{64}', artifact.get('digest', '')):
                raise SystemExit('Missing artifact digest')
            receipt = {'repository': REPOSITORY, 'runID': args.run_id, 'commit': args.commit,
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
