#!/usr/bin/env python3
"""Read-only, fail-closed approval of one explicitly requested native candidate."""
import argparse
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request

REPOSITORY = 'ineedsomesleep5/MagicMobile'
WORKFLOW = '.github/workflows/magicmobile-issue4-nonsimulator.yml'
# GitHub names unnamed run steps "Run <first command line>". Treat renames as
# policy changes: update this contract alongside the reviewed cheap workflow.
REQUIRED_STEPS = {
    'source-provenance': ('Preserve exact source',),
    'portable-contracts': (
        'Run bash scripts/test_tooling.sh',
        'Run bash scripts/test_native_boundary.sh',
        'Test native approval and upstream maintenance orchestration',
    ),
    'apple-source-and-sdk': (
        'Prepare owned evidence and exact identity',
        'Execute portable native protocol tests on macOS',
        'Execute portable app tests and export exact bundled decks',
        'Execute macOS build-number and upload-ledger regressions',
        'Native-close fixture tests (not XMage runtime)',
        'Runtime-manager native-ABI fixtures (not XMage runtime)',
        'Compile existing product and SDK-only tests without signing or execution',
    ),
    'real-jvm': (
        'Run mkdir -p evidence; bash scripts/build_jvm.sh 2>&1 | tee evidence/issue4-jvm-build.log',
        'Run bash scripts/test_real_engine.sh 2>&1 | tee evidence/issue4-real-engine.log',
        'Bounded seeded driver lifecycle matrix (real JVM, not seeded XMage RNG)',
        'Audit compiled desktop API references (static only, not native execution)',
        'Retrieve exact same-commit Swift-exported bundled decks',
        'Validate all five actual bundled decks with XMage',
    ),
    'compiler-source-inspection': (
        'Preserve upstream compiler source for branch-range investigation',
    ),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def is_sha(value):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{40}', value) and value != '0' * 40


def successful(item):
    return item.get('status') == 'completed' and item.get('conclusion') == 'success'


def approve(*, repository, candidate_sha, cheap_run_id, dispatch_ref,
            dispatch_sha, trusted_sha, get_json):
    """Validate via an injected repository-relative GET API; return a receipt.

    No filesystem execution, artifact extraction, shell commands, or mutations.
    get_json receives only paths under the hard-coded repository API endpoint.
    """
    require(repository == REPOSITORY, 'Unexpected repository')
    require(is_sha(candidate_sha) and is_sha(trusted_sha), 'Exact nonzero lowercase SHAs required')
    require(dispatch_sha == candidate_sha, 'Dispatch SHA differs from candidate')
    require(isinstance(cheap_run_id, str) and re.fullmatch('[1-9][0-9]*', cheap_run_id),
            'Positive decimal cheap run ID required')
    require(isinstance(dispatch_ref, str) and
            re.fullmatch(r'refs/(heads|tags)/[^\s~^:?*\[\\]+', dispatch_ref) and
            '..' not in dispatch_ref and '@{' not in dispatch_ref and
            not dispatch_ref.endswith(('/', '.', '.lock')),
            'Full nonblank branch or tag dispatch ref required')
    # This also rejects deleted/moved refs and nonexistent syntactically valid SHAs.
    resolved = get_json('/commits/' + urllib.parse.quote(dispatch_ref, safe=''))
    require(resolved.get('sha') == candidate_sha, 'Dispatch ref no longer resolves to candidate')
    candidate = get_json('/commits/' + candidate_sha)
    require(candidate.get('sha') == candidate_sha, 'Candidate commit does not exist')

    # Identical step labels alone are not trustworthy. Require the actual cheap
    # workflow blob to equal the reviewed immutable policy snapshot.
    blobs = [get_json('/contents/' + WORKFLOW + '?ref=' + sha)
             for sha in (trusted_sha, candidate_sha)]
    require(all(blob.get('type') == 'file' and blob.get('path') == WORKFLOW
                and is_sha(blob.get('sha')) for blob in blobs) and
            blobs[0]['sha'] == blobs[1]['sha'], 'Cheap workflow differs from trusted policy')

    run_path = '/actions/runs/' + cheap_run_id
    run = get_json(run_path)
    require(run.get('id') == int(cheap_run_id) and run.get('head_sha') == candidate_sha
            and run.get('repository', {}).get('full_name') == REPOSITORY
            and run.get('head_repository', {}).get('full_name') == REPOSITORY
            and run.get('path') == WORKFLOW
            and run.get('event') in ('push', 'workflow_dispatch')
            and isinstance(run.get('head_branch'), str) and run['head_branch'].strip()
            and successful(run), 'Cheap run identity, event, or result is not trusted success')
    attempt = run.get('run_attempt')
    require(type(attempt) is int and attempt > 0, 'Missing cheap run attempt')
    jobs = []
    # Pin the attempt so a rerun cannot combine old and new successful jobs.
    for page in range(1, 101):
        result = get_json(f'{run_path}/attempts/{attempt}/jobs?per_page=100&page={page}')
        batch = result.get('jobs')
        require(isinstance(batch, list) and type(result.get('total_count')) is int,
                'Malformed jobs response')
        jobs.extend(batch)
        if len(jobs) == result['total_count']:
            break
        require(batch and len(jobs) < result['total_count'], 'Incomplete jobs response')
    else:
        raise ValueError('Too many jobs pages')
    require(len({job.get('id') for job in jobs}) == len(jobs), 'Duplicate job IDs')
    for name, required in REQUIRED_STEPS.items():
        matches = [job for job in jobs if job.get('name') == name]
        require(len(matches) == 1, 'Required job missing or duplicated: ' + name)
        job = matches[0]
        require(job.get('run_id') == int(cheap_run_id) and job.get('head_sha') == candidate_sha
                and successful(job), 'Required job did not succeed: ' + name)
        steps = job.get('steps')
        require(isinstance(steps, list) and steps and all(successful(step) for step in steps),
                'Job has missing, skipped, or unsuccessful steps: ' + name)
        for step_name in required:
            require(sum(step.get('name') == step_name for step in steps) == 1,
                    'Required step missing or duplicated: ' + step_name)
    # Detect a rerun started while evidence was being inspected.
    final = get_json(run_path)
    require(final == run, 'Cheap run changed during approval; retry after it completes')
    return {'repository': REPOSITORY, 'candidateSHA': candidate_sha,
            'cheapRunID': int(cheap_run_id), 'cheapRunAttempt': attempt,
            'trustedPolicySHA': trusted_sha, 'nativeRuntimeTested': False}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward the bearer token, even to a repository rename redirect.
        return None


def api_get(path):
    request = urllib.request.Request('https://api.github.com/repos/' + REPOSITORY + path,
                                     headers={
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
    })
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
            return json.load(response)
    except (OSError, ValueError) as error:
        if isinstance(error, urllib.error.HTTPError):
            error.close()
        # Deliberately omit request headers, response bodies, and exception text.
        raise ValueError('GitHub read failed; approval remains blocked') from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ('repository', 'candidate-sha', 'cheap-run-id', 'dispatch-ref',
                 'dispatch-sha', 'trusted-sha'):
        parser.add_argument('--' + flag, required=True)
    args = parser.parse_args()
    try:
        receipt = approve(**vars(args), get_json=api_get)
    except (ValueError, KeyError, TypeError, AttributeError):
        parser.exit(2, 'Native approval refused: invalid inputs, policy, API response, or cheap evidence.\n')
    print(json.dumps(receipt, sort_keys=True))


if __name__ == '__main__':
    main()
