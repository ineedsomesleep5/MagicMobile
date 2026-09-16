# Explicit native approval gate

The far-call workflow is dispatch-only. Ordinary pushes cannot launch its full
ARM64 build. Existing native runner, compiler/build steps, artifact names and
timeouts are retained. Concurrency uses the candidate SHA and never cancels a
running build. GitHub concurrency is not permanent deduplication: another manual
dispatch can rebuild a candidate after completion.

## Interfaces

Workflow `.github/workflows/magicmobile-far-calls.yml` inputs:

- `candidate_sha`: exact lowercase, nonzero 40-character Git commit SHA.
- `cheap_run_id`: positive decimal run ID for
  `.github/workflows/magicmobile-issue4-nonsimulator.yml`.
- The dispatch branch/tag must resolve to `candidate_sha`, including the captured
  `github.sha`. Moving/deleting it before validation fails closed. Native checkout
  uses the immutable SHA after approval; later branch movement cannot change it.

This preserves `scripts/wait_issue4_native.py`'s run `head_sha` validation and
`issue4-full-native-candidate-${github.sha}` artifact lookup. The helper does not
dispatch, download artifacts, sign, upload, or claim native runtime acceptance.

CLI (read-only GitHub API; `GH_TOKEN` must have contents/actions read access):

```sh
python3 -I scripts/magicmobile-native-gate/approve_native.py \
  --repository ineedsomesleep5/MagicMobile \
  --candidate-sha "$CANDIDATE_SHA" --cheap-run-id "$CHEAP_RUN_ID" \
  --dispatch-ref "$GITHUB_REF" --dispatch-sha "$GITHUB_SHA" \
  --trusted-sha "$TRUSTED_POLICY_SHA"
```

`TRUSTED_POLICY_SHA` is the reviewed immutable policy commit pinned in the
approval job's workflow `env`, never a dispatch input or mutable branch name.
The workflow rejects the placeholder, malformed pins and zero SHAs before
checkout, then verifies the checked-out HEAD equals the pin.
Success writes a JSON receipt to stdout and exits
0; invalid or unavailable evidence exits 2. The importable
`approve(..., get_json=callable)` uses injected repository-relative GET responses.
It requires successful exact-repository/head/workflow identity, push or manual
dispatch provenance, a completed run attempt, every required job and step, and
no skipped/failed steps in required jobs. It paginates attempt-specific jobs and
rechecks the run afterward. Required checks include real JVM games, the bounded
seeded driver lifecycle matrix, Swift app/deck export, same-commit artifact
retrieval and all five XMage deck validations, portable contracts and SDK build.

## Trust and integration

The token-bearing job executes only the helper from the repository's pinned
reviewed policy commit, with isolated Python imports and checkout credentials disabled.
Candidate code runs only in the dependent native job, without a token environment
variable or configured secrets. Permissions are read-only; only the approval job
gets actions read. API redirects are refused and raw API errors are never printed.
Inputs enter shell commands through quoted environment variables.

Candidate authorization also requires independent review of the exact code,
test, and test-driver diff. Pinned YAML and successful same-SHA jobs establish
provenance and reported execution status, not semantic test quality: they cannot
detect a candidate-owned check replaced with a successful no-op.

Bootstrap on the reviewed working branch in two commits (root owns publishing;
this helper performs no writes):

1. Create a reviewed commit containing the final helper/tests and approved cheap
   workflow, including `Test native approval and upstream maintenance orchestration`,
   the bounded seeded driver lifecycle step and the evidence-only push path
   exclusions. Record its full 40-character SHA as the policy commit. Create this
   commit after these changes are final, so the compared workflow blobs match.
2. In a second commit, replace `REPLACE_WITH_REVIEWED_POLICY_COMMIT` in the
   far-call workflow's `TRUSTED_POLICY_SHA` with that SHA. Obtain a successful
   cheap run for the exact candidate, then dispatch its branch/tag with that
   candidate SHA and cheap run ID. Publish both commits together after the pin is
   resolved; never dispatch the placeholder policy.

No merge or default-branch change is required by this policy setup. Until root
fills the placeholder, approval intentionally fails closed. The candidate
cheap-workflow blob must equal the pinned policy blob: forged jobs with matching
step labels are insufficient. A cheap-workflow change requires a newly reviewed
policy commit and an updated pin. The reviewed workflow at dispatch is the trust
boundary; workflow editors can replace the gate itself, so the pin and workflow
must be reviewed together. API errors or unavailable policy commits block the build.

Root owns the cheap workflow. Wire this offline command into its portable job
(from the repository root):

```sh
python3 -B -m unittest discover -s scripts/magicmobile-native-gate -p 'test_*.py' -v
git diff --check
```

With that job's existing package working directory, use
`python3 -B -m unittest discover -s ../../scripts/magicmobile-native-gate -p 'test_*.py' -v`.
Fixtures inject API responses and forbid network. No engine build is needed.
Keep `REQUIRED_STEPS` synchronized with reviewed cheap-workflow step names;
missing/renamed checks block approval instead of silently reducing coverage.

This directory is intentionally at the repository root, outside
`packages/ondevice-engine/`. The existing `source_identity` guard scans engine
package paths; neither this directory nor the workflow is an engine input.
Orchestration-only changes therefore do not require rebuilding a native archive.
No guard modification or exemption is introduced.

API contracts: [workflow jobs](https://docs.github.com/en/rest/actions/workflow-jobs),
[workflow runs](https://docs.github.com/en/rest/actions/workflow-runs), and
[dispatch SHA/ref](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch).
