# Workflow efficiency

## Scope

Improve repeatability and developer turnaround without weakening source review,
native provenance, privacy, signing, runtime acceptance, or distribution gates.
This work does not authorize a new release, engine update, paid runner, dependency,
or deployment. Keep original release evidence and logs recoverable.

## Implementation plan

1. Classify changed inputs and fingerprint each check conservatively. Reuse only
   matching successful evidence from a trusted workflow. Missing or uncertain
   evidence means run the check, not assume success.
2. Resolve existing native artifacts through the existing candidate verifier.
   Record source, workflow/artifact IDs, checksums, toolchain, and verification
   evidence. An expired or mismatched artifact is not a reusable candidate.
3. Add a resumable release controller around the existing guarded scripts.
   Preserve exact inputs and outputs; block ambiguous external mutations until
   reconciled. Do not upload again just to finish tester distribution.
4. Make UI fixtures and test invocation deterministic, with scoped accessibility
   queries, bounded scrolling, and source/binary identity checks before reuse.
5. Extract cohesive board layout code without changing rendering or rules.
   Continue incremental extraction during relevant feature work, not a wholesale
   rewrite of the app.
6. Correct stale local release skill guidance and use repo-owned instructions for
   release policy. Delegate independent scopes to Sol; Astra integrates and reviews.

## Agent execution contract

- Start with the exact checkout, branch, relevant diff, and a measurable outcome.
- Main agent owns integration and shared files. Each delegate owns disjoint files
  and receives constraints and specific verification criteria.
- Run one heavy local Xcode/Gradle/simulator workload at a time on the 8 GB Mac.
- Compile the integrated UI early, before expensive visual acceptance, and once
  more after integration. Do not confuse parsing or compiling tests with execution.
- Freeze engine inputs before starting native CI. Run independent UI work while
  it builds, but invalidate the candidate if engine inputs later change.
- Use one bounded external-run watcher, not repeated agent/manual polls. Report
  transitions, failures, or required decisions. Stop and diagnose repeated failure.
- Graph lookup is optional when no current index exists; use rg immediately.
  Index creation and freshness maintenance should be evaluated separately rather
  than becoming an ordinary edit prerequisite.

## Entry points

Run from the selected checkout. These examples do not prepare a new version,
dispatch native CI, publish an artifact, or change tester groups.

```sh
# Before an expensive iOS update: inspect, then run fresh sequential early checks.
python3 scripts/release/preflight.py plan --profile ios-fast
python3 scripts/release/preflight.py run --profile ios-fast
# Tooling-only changes do not need app compilation or simulator work.
python3 scripts/release/preflight.py run --profile tooling

# Offline tool safety tests (temporary fixture repositories only).
python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v
python3 -m unittest discover -s scripts/release -p 'test_*.py' -v
python3 -m unittest discover -s scripts/deck-studio -p 'test_ios_ui_tests.py' -v

# Read-only release plan. Requires committed reviewed source and staged inputs.
python3 scripts/release/controller.py plan --platform ios
python3 scripts/release/controller.py status --run-id YOUR_RUN_ID
python3 scripts/release/controller.py status --run-id YOUR_RUN_ID --summary

# Find an existing exact-input iOS engine candidate (read-only GitHub lookup).
# GH_TOKEN must already be configured; do not print it. Use a new manifest path.
python3 scripts/ci/verify_reusable_native.py \
  --output build_output/native-reuse/candidate.json

# Preview a targeted test workflow; does not boot a simulator.
python3 scripts/deck-studio/ios-ui-tests.py plan \
  --preset presentation-smoke

# Saved GitHub timing evidence, analyzed without further network requests.
gh run view RUN_ID --json createdAt,updatedAt,jobs > /tmp/run-timing.json
python3 scripts/workflow-metrics.py /tmp/run-timing.json
```

### Build-9 follow-up: catch failures earlier

1. Integrate delegate changes before preflight. Run the `ios-fast` profile before
   expensive native dispatch or release work. It checks tooling, the generated
   project, standalone Deck Studio compile contracts and portable Swift tests.
   The standalone checks would have caught build 9's missing timeline dependency
   before its late PR failure. Full CI still runs; no gate is weakened.
2. Inspect `nativeDecision` in preflight. It calls the existing conservative
   source verifier, not a new list of loosely matched filenames. Unknown means
   resolve the missing/dirty evidence; it means neither "reuse" nor "rebuild".
   For equivalent source, verify retained native inputs or use the existing
   exact-input GitHub resolver before considering a new build. No network lookup
   or native build is automatically started by preflight.
3. For UI changes, run `presentation-smoke` early through the existing UI harness.
   It selects five existing tests: portrait/landscape searchable library chooser
   (including keyboard), full-screen dashboard inspection/scrubbing/rotation, and
   portrait/landscape MDFC affordances. Use explicit `--only-testing` for additional
   affected cases. This is a regression preset, not all UI acceptance.
4. Freeze app source before final accepted UI tests. Retain one dedicated derived
   data directory and reuse `test-without-building` only while its source, Xcode,
   runner and app fingerprints match. Do not keep polishing during verification.
5. Use controller `status --summary` for release handoffs and retain full receipts.
   Upload and distribution remain separate. Historical completion never proves
   current Apple availability or current-source acceptance.
6. Analyze saved GitHub timing with `workflow-metrics.py`. The report ranks slow
   completed steps and separates skipped work from failed work. Missing timings
   are unknown, not zero-duration successes. It cannot measure model usage or
   infer time savings from one run.

Preflight logs and per-step timing are saved under a fresh `build_output/preflight/`
directory, including when a check fails or is interrupted. A changed source
fingerprint invalidates the overall result. Outputs are development evidence,
not trusted CI receipts. The tooling workflow uses the same entry point and
uploads its logs, reducing drift between local and CI checks. No signing,
simulator boot, engine build, paid runner, dependency or Android work is introduced.

The slow native compilation itself is unchanged: build 9's full ARM64 step took
73 minutes 5 seconds. These improvements target unnecessary builds and late
failures, not a promised reduction in genuine compiler time. Measure comparable
future updates before claiming an end-to-end speedup.

Local follow-up verification (September 22, 2026 UTC): the integrated `ios-fast`
preflight passed in 66.666 seconds on the existing checkout/caches. All 72 Python
tooling tests, standalone Deck Studio assertions, 34 Swift protocol tests and
413 presentation tests passed (five optional presentation checks skipped).
The generated project comparison and shell syntax checks passed. Original logs
and step timings: `build_output/preflight/ios-fast-f9itjtdm/`. Timing analysis was
also exercised against build 9's actual saved GitHub response. The UI preset's
five methods resolve and plan mode is read-only; no UI execution, app build,
native compilation, signing, upload, Android change or hosted-CI acceptance is
claimed for this tooling change. This is a measured preflight cost, not measured
end-to-end time saved; cold caches and different machines will vary.

The final safety review added a duplicate-run lock regression (73 tooling tests
total), disabled inherited precon-export test output, and ensured distribution
script changes trigger the tooling workflow. A tooling-only run took 2.658 seconds
before the final safety adjustments; this is not an end-to-end release benchmark.

The UI helper's `build` command compiles and fingerprints the app, actual test
bundle, resources, sources and Xcode. Its `test` command requires an explicitly
selected, already-booted simulator and a matching build stamp. Neither compilation
nor fixture execution is physical-device or real-engine acceptance.

CI reuse is deliberately limited to trusted successful **main-push** evidence,
with matching source and runner/toolchain identity and a seven-day freshness limit.
PRs and manual runs still execute their checks. Reused evidence is not reissued
with a fresh timestamp. This avoids laundering untrusted PR results into a release
gate, but does not eliminate repeated documentation-follow-up PR runs yet.

The local release controller preserves append-only hashed events and original
logs. iOS upload and distribution are separate checkpoints; a completed upload
must never be repeated to finish distribution. Unknown outcomes stop for exact
reconciliation. Android builds retain their existing source, native, signing and
version gates. Website/server publication and device acceptance remain explicit
release steps, not capabilities inferred from a successful controller command.
See [controller usage and recovery](../scripts/release/README.md) for the explicit
mutation commands. No automatic website or server publisher was introduced.

## Implementation verification (2026-09-21)

- Implemented in the `MagicMobile-board-polish` checkout, local branch
  `codex/workflow-efficiency`; no push, merge, release or CI dispatch in this task.
- 51 new tooling tests pass: 26 CI/native discovery, 14 release recovery,
  8 UI-runner identity/selection, and 3 timing aggregation tests.
- Existing checks pass: 32 native candidate tests, 20 TestFlight
  distribution/version tests, and 10 build-number tests.
- Integrated app and test compilation passes. A fresh dedicated compile through
  the new helper also passes and writes the exact-source bundle stamp in
  `build_output/ios-ui-harness/magicmobile-ui-build.json`. Independent live stamp
  verification took 0.355 seconds. Logs: `/tmp/magicmobile-efficiency-integrated-build.log`
  and `/tmp/magicmobile-efficiency-fresh-build.log`.
- An initial helper run against old multi-architecture derived data compiled but
  refused ambiguous test outputs. The final helper explicitly selects its ARM64
  test run and has regression coverage; the fresh dedicated build passed.
- The 562 extracted battlefield layout lines match their original declarations
  byte-for-byte. No layout values, engine rules or gameplay behavior changed.
- Existing Android staged native files and source equivalence were independently
  verified. No engine package or Android source changes were needed.
- YAML parses, shell syntax and diff checks pass. The local TestFlight skill was
  corrected; its normal validator lacked PyYAML, so Ruby YAML parsing and a
  direct placeholder/frontmatter check were used without installing dependencies.
- No UI test execution, simulator boot, physical-device gameplay, live release
  recovery, or hosted CI reuse is claimed. Those remain distinct future gates.
  CI changes take effect only after review and publication to GitHub.

## Baseline and savings model

Build 7's observed iOS native workflow `35630421619` took about 121 minutes:
roughly 35 minutes of prerequisites/probes, 82 minutes for full native compilation,
and the remainder for artifact preservation. The compiler backport itself took
30 seconds. Unsigned product compilation took about 7.5 minutes, local signing
and upload about 6 minutes, and Apple processing/discovery about 7 minutes.
These overlap in the full release; do not add waiting jobs as active build time.

Build 7 needed changed bridge metadata, so skipping its native compilation would
not have been safe. Exact reuse mainly helps future UI-only changes. Some reuse
was already manually possible; automation saves discovery/error recovery and
prevents unnecessary rebuilds rather than making every release 121 minutes faster.

Expected opportunities, not measured post-change end-to-end results:

| Situation | Potential elapsed saving | Condition |
| --- | --- | --- |
| UI-only release that would otherwise rebuild the engine | Up to about 2 hours | Verified matching native inputs and retained artifact |
| UI-only release already reusing the engine manually | Several minutes of coordination | Resolver and resume avoid repeated discovery |
| Unchanged CI jobs on subsequent main pushes | About 7–15 minutes per critical-path repeat | Trusted matching check evidence; PR runs remain fresh and parallel jobs are not additive |
| Interrupted release/distribution | Minutes to much longer | Resume completed work; uncertain uploads require reconciliation |
| Engine-changing release | Modest orchestration/rework savings | Full native checks/build still required |

## Measure the next comparable runs

Record task start/finish, active agent time and model usage when available,
critical-path duration, runner minutes, cache/evidence hit rate, number of native
builds, UI reruns, upload attempts, failures caught, and escaped regressions.
Compare UI-only to UI-only and engine-changing to engine-changing. Preserve
requirements, unresolved errors, checksums, test logs, and acceptance boundaries.
Reduced context or fewer commands alone is not success. Never invent model cost
or token usage when the host does not expose it.
