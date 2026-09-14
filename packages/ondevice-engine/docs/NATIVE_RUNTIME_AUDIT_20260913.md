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
This real-JVM integration regression needs the full pinned engine build; do not
label it passed until its run completes. Native compilation and actual product
linking are still distinct from real-device execution.

Additional local checks: 182 tooling tests completed (two platform-dependent
checks skipped); 33 Swift protocol/transport tests passed; C boundary sanitizers
passed 9,000 fixture requests and five shutdown scenarios. The 16 release-guard
tests are a subset of the tooling suite, not 16 additional tests. The isolated
Swift lifecycle runner passed 18 assertions using actual session/runtime code
with test-only presentation/observation/backend fixtures; it is not an Apple SDK
build. Five build-number tests were skipped on Linux and are now explicitly
executed by the existing macOS non-simulator job. The complete presentation suite
and the new real-XMage delivery regression still require those hosted results.

The continuation branch runs the existing non-simulator workflow. The existing
full ARM64 compiler workflow also runs for the changed engine inputs, with its
real JVM, Color, token, catalogue and compiler checks. No simulator, signing,
TestFlight upload, larger runner or remote rules engine is enabled here.

## Release handoff

1. Use the final continuation commit and its successful full ARM64 run. Preserve
   archive, generated headers, static dependencies, manifests and hashes together.
2. Point the product workflow's ENGINE_RUN_ID/ENGINE_COMMIT at that exact new
   successful native run/source, enable the continuation branch for the existing
   product gate, and verify the actual unsigned native-linked Release product.
   Do not bypass any mismatch or package the older 2026091301 engine.
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
