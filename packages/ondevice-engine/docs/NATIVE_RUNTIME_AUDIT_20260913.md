# Runtime hardening continuation

## Source and scope

Continues `79ac0d36bcba0791032b10a465e29ef6f4c45180` (PR #8), which is based on
`7992311b4a41720f9a37858e44dbd5122ae5bdb2` (PR #6). Preserve PR #8's equal-revision
poll ordering, durable closing state and native TestFlight release guard. The
older downloadable runtime patch must not replace those newer session changes.

This patch retains XMage/MAD, the full card registry, Color/AWT adaptation,
bundled metadata and exact artifact/source verification. It changes production
Java/native entrypoint bytes, so the `00b33cb` engine artifact is NOT reusable.

## Repairs

- Keep trusted, local diagnostics readable/deletable even when XMage bootstrap
  fails. Capture LinkageError at request boundaries and failures at native entry
  points, returning sanitized responses rather than private exception text.
- A failed answer delivery, including Error subclasses, explicitly fails the
  match and clears pending prompts instead of leaving a permanently queued action.
- Mark service shutdown durably before calling the backend. Reject new engine
  operations during and after shutdown; retain a busy backend for retry, and do
  not close a successfully terminated backend twice.
- Wait for the actual mailbox CALL executor as well as GAME/AI workers before
  confirming shutdown. `shutdownNow()` requests interruption, not termination.
  The wait is outside the mailbox monitor and shares the existing deadline.
- Preserve one bounded private startup diagnostic before closing an isolate.
  Guard the whole Swift match-destroy/runtime-close transaction across awaits.
- Discard late poll responses after backgrounding, cancellation or teardown.
  Preserve PR #8's stronger retryable-close and same-revision ordering behavior.
- Wire four added session regressions into the existing presentation package;
  retain PR #8's separate readiness regressions. Expand the existing ARM64
  workflow's source filters so engine/platform/build changes trigger validation.

## Checks and interpretation

Local JDK checks compile the actual core code with `--release 17`: 405 original
assertions and 72 fault/concurrency assertions pass. Seven shutdown assertions
failed before the additional service correction. The mailbox test deliberately
holds its real executor and verifies bounded refusal, drain and no monitor
deadlock. These are injected boundary faults, not gameplay or phone acceptance.

`RealBusyShutdownTests` now additionally holds the actual XmageEngine CALL
executor while letting its GAME worker terminate. It requires busy shutdown,
retention of the same match, explicit release and successful cleanup retry.
This regression passed with the full pinned engine in non-simulator run
**34803650505** at engine source **f8e16802bf033adfd844b878248b30042b838481**.
Its four actual-JVM cases passed, including the new held CALL worker. The full
real-JVM suite, completed two-/four-seat and token/mulligan games, and all five
exact Swift-exported bundled precons passed in the same run. JVM evidence
artifact **10332427518**, ZIP SHA-256
`e95b04319f66f663a97abea9d9e33e557693d97e783e5f74ca41fc7a7e03b7f2`,
was downloaded and hash-verified. Native compilation and actual product linking
remain distinct from real-device execution.

Additional local checks: 182 tooling tests completed (two platform-dependent
checks skipped); 33 Swift protocol/transport tests passed; C boundary sanitizers
passed 9,000 fixture requests and five shutdown scenarios. The 16 release-guard
tests are a subset of the tooling suite, not 16 additional tests. The isolated
Swift lifecycle runner passed 18 assertions using actual session/runtime code
with test-only presentation/observation/backend fixtures; it is not an Apple SDK
build. The latest downloaded artifact for **101985d** records **121** complete Mac
presentation tests, **33** protocol tests and **five** build-number/ledger tests
passed. These exact logs supersede earlier summary counts. Actual unsigned generic-iOS
app and SDK-only tests compiled successfully (`build-for-testing`); no simulator
or device execution occurred. Those hosted checks resolve the earlier five
Linux build-number skips; they do not validate native-linked Release execution.

The additional `scripts/test_runtime_manager.sh` compiles the actual production
Swift manager/client/C boundary in an isolated process with a clearly test-only
native ABI backend. Its **27** assertions pass locally; **eight** fail against
the unmodified PR #8 runtime manager. It tests startup diagnostic retention,
overlapping destroy/close, busy cleanup retry without duplicate destruction,
and creation of a new runtime after teardown. Its files stay under `tests/`,
never enter a product target, and are not a rules simulator. The existing Mac
non-simulator job also executes this new regression and preserves its log.

The continuation branch runs the existing non-simulator workflow. The existing
full ARM64 compiler workflow also runs for the changed engine inputs, with its
real JVM, Color, token, catalogue and compiler checks. No simulator, signing,
TestFlight upload, larger runner or remote rules engine is enabled here.

## Release handoff

1. The selected full ARM64 run is **34803650513**, engine source
   **f8e16802bf033adfd844b878248b30042b838481**. It was still running when this
   record was written; it is NOT passing native evidence yet. Preserve archive,
   generated headers, static dependencies, manifests and hashes only after success.
2. The existing product workflow is now pinned to that exact run/source and
   enabled on this repair branch. Its unchanged success/artifact/source guards
   wait for the real candidate and refuse failed, missing or mismatched inputs.
   A later test/workflow-only commit can reuse f8e1680 only after source identity
   verification. Require actual unsigned native-linked Release success; do not
   bypass a mismatch or package the older 2026091301 engine.
3. Desktop Codex should preserve the existing app identity, check App Store
   Connect for an unused build number, prepare/commit it, stage verified matching
   inputs, and use PR #8's guarded native release script for signing/export and
   an authorized internal TestFlight update. Confirm Apple processing/group access.
4. Caleb performs phone checks manually: Token Triumph versus one Grave Danger
   AI, starting player and mulligan; then mana/commander/combat/tokens, AI turns,
   background/return and repeated leave/new game. Keep private error reports out
   of public issues. Multiplayer needs separate real two-to-four-phone checks.

Do not close physical acceptance issue #7 or claim perfect/full-card behavior
from fixtures, JVM games, a native library, successful linking or an upload.


## Follow-up: resilient exact-run API reads

`wait_issue4_native.py` previously aborted after a single transient API failure.
A fault injection against the unchanged version reproduced HTTP 503 stopping
on its first request, without attempting the next available successful reply.
The repaired GET helper retries a bounded five attempts within the SAME overall
monotonic gate deadline; per-request timeouts are clamped to the remaining window.
It honors valid Retry-After and exhausted-rate reset hints, waits at least a
minute for rate limits without usable hints, and never retries ordinary
permission/not-found/validation errors or malformed JSON. Logs exclude tokens,
response bodies and private exception text. This does not dispatch or restart
an engine workflow, and does not change Java/native/compiler inputs.

Sixteen additional network-free fault tests cover recovery, finite retries,
rate limits, deadlines, and unchanged refusal of failed/cancelled builds,
wrong commits and missing/expired/duplicate/digestless artifacts. These are
orchestration fixtures, not additional gameplay or iPhone acceptance.
GitHub's rate-limit guidance is the reference:
https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api

The selected engine remains f8e1680 / run 34803650513. A product rerun on the
new app/test/workflow-only head still has to pass exact-source and actual
native-linked Release inspection. Do not reuse the old TestFlight engine.

## Current evidence and static desktop-API audit

The complete non-simulator run **34805592973** passed on **101985d**. Its Mac
evidence artifact **10333157959** and real-JVM artifact **10333039647** were
downloaded and hash-verified. The latter records four busy-shutdown cases,
completed two-/four-seat and token/mulligan games, and validation/first prompt
of all five bundled precons. See `implementation-status.json` for exact hashes.
The source-tree comparison also confirms no engine input changes between the
f8e1680 native build and the 101985d application code. This does not replace
inspection of the real native archive or the actual linked product.

The existing non-simulator workflow now preserves a `jdeps` audit of desktop
API references and missing dependencies in the selected compiled XMage modules.
This is static evidence for reviewing possible additional Color-style platform
risks, not method reachability or a native execution claim. The helper does not
execute a game, Graal executable or simulator; it is a test-only diagnostic and
does not alter engine/compiler inputs. Its actual engine audit still needs to
complete in the new workflow run before its findings can be reported.

The current handoff/status/checklist now distinguish the new runtime candidate
from the older uploaded build 2026091301 and the superseded diagnostic 1203.
The source/build, signing/upload and physical acceptance boundaries remain
separate; old chronological notes are preserved in the linked Git history.
