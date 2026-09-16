# Weekly upstream detection and draft candidate handoff

This handoff supersedes the README's **inactive schedule** description. The
existing `magicmobile-upstream-maintenance.yml` now declares Monday 09:23 UTC
detection. It becomes eligible to run only after the workflow reaches the default
branch and GitHub Actions schedules are enabled. No workflow was dispatched and
no branch or PR was published during this implementation.

## Detection and upstream news

The scheduled job uses the existing `detect` helper: resolve upstream master once,
then inspect immutable old/new objects from `https://github.com/magefree/mage.git`.
The production lock is unchanged. The `upstream-detection` artifact contains the
exact candidate, comparison URL, changed modules/files, dependency paths, blob
hashes and review digest (also printed in the run log). No upstream code executes.
An unchanged SHA is a successful no-update report; errors fail the job.

This is source-change monitoring, not a general Magic news feed. It does not
scrape announcements, infer card legality or claim new cards are playable. There
is no durable notification/dedup service: weekly reports may repeat the same
candidate. The helper's existing optional records and stable candidate branch
remain the mechanisms for owner-managed review tracking and later publication.

## Prepare a draft packet

After reviewing the detection artifact, manually choose `mode=candidate`, supply
the exact 40-character upstream SHA and `reviewed_detection_digest`, and leave
`regenerate=false`. Candidate preparation uses an Ubuntu runner, existing trusted
transformers and the existing `prepare` helper; it does not run Maven, Swift or
upstream programs. Its artifact includes `draft-pr/`:

- `candidate.patch`: only the seven existing preparer's lock/status/identity files.
- `draft-pr.json`: base MagicMobile commit, exact upstream SHA, detection digest,
  stable branch name, draft title, file hashes and patch hash; `published=false`.
- `body.md`: draft review text and outstanding gates.

Equivalent local packet generation after the existing approved `prepare` command:

```sh
python3 scripts/magicmobile-maintenance/upstream.py draft-packet \
  --project /path/to/clean/committed/MagicMobile \
  --candidate /path/to/prepared-candidate --output /path/to/NEW-draft-pr
```

The command requires the original clean base commit and a new output directory.
It does not stage or commit files, create a branch, push, open a PR or dispatch CI.
Review and apply the patch in a separate checkout at `baseProjectCommit`. This
source-pin-only patch deliberately leaves generated hashes at the prior baseline:
it is **not merge-ready**. Never merge it as a completed upstream update.

## Separate build, publication and release gates

The existing regeneration path remains available only with explicit
`regenerate=true`. That opts into the existing macOS/JDK builder. A separately
reviewed generated digest is required to accept new generated pins and run the
post-review validation gates. Supplying that digest without regeneration fails.
The draft packet is produced before regeneration and is not a final validated
patch, even when the same run later generates additional review artifacts.

All jobs retain `contents: read`; checkout credentials are not persisted. There
are no signing secrets, write-token publication job, `pull_request_target`, or
release/merge commands. Explicit upstream execution uses the existing stripped
environment and isolated build home; those controls are not an OS/network sandbox.

After separately integrating and validating a final exact MagicMobile commit,
the existing `publish` command previews its draft-PR plan by default. Its
`--execute` option still requires explicit authorization for remote writes. It is
not invoked by this workflow. Human review before merge, exact-commit native
gates, device acceptance and separate release authorization remain required.

## Local verification

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s scripts/magicmobile-maintenance -p 'test_*.py'
```

Fixtures use temporary synthetic Git repositories, real patch application and
mocked remote commands. They do not execute upstream builds or publish anything.
Passing fixtures do not establish live schedule delivery, runner availability,
upstream transformer compatibility, generated catalogue parity or native/device
acceptance. Those require separately authorized execution after integration.
