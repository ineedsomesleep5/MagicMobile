#!/usr/bin/env python3
"""Wait for one explicitly pinned GitHub engine build; never dispatch a workflow."""
import argparse
import json
import os
from pathlib import Path
import re
import time
import urllib.request

REPOSITORY = 'ineedsomesleep5/MagicMobile'
API = f'https://api.github.com/repos/{REPOSITORY}'


def get_json(path):
    request = urllib.request.Request(API + path, headers={
        'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28',
        'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
    })
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


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
        run = get_json(f'/actions/runs/{args.run_id}')
        validate_run(run, args.run_id, args.commit)
        state = (run.get('status'), run.get('conclusion'))
        if state != previous:
            print(f'Pinned native build {args.run_id}: {state}', flush=True)
            previous = state
        if state[0] == 'completed':
            if state[1] != 'success':
                raise SystemExit('Full native workflow did not succeed; product gate remains blocked')
            name = 'issue4-full-native-candidate-' + args.commit
            artifacts = get_json(f'/actions/runs/{args.run_id}/artifacts?per_page=100')['artifacts']
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
