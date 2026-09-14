# Native runtime continuation — 2026-09-14

## Scope and source

Based on `7992311b4a41720f9a37858e44dbd5122ae5bdb2` from PR #6.
Review branch: `codex/native-runtime-audit-20260914`; the release continuation and
main branches are not overwritten. This imports the previous unpushed runtime-fix
package and extends it. Do not apply that older ZIP again over this branch.
The full XMage rules/card registry and existing iOS product remain unchanged in
scope. No simulator execution, remote rules fallback, signing, paid runner or
TestFlight upload is part of this audit.

The existing Color patch, native metadata catalogue and token-resource repair are
preserved. Their previous successful build is not evidence for this changed source.

## Concrete fixes

- Lazy trusted engine service: reading/deleting a private error report or closing
  an unopened service does not attempt to initialize the failed engine again.
- Request/native boundaries capture linkage/initialization failures privately and
  return sanitized errors. Capture is diagnostic, not a fake successful recovery.
- A Throwable in the actual response-delivery executor marks the match failed and
  clears pending prompts instead of abandoning a queued action indefinitely.
- Expected close interrupts do not overwrite the original engine failure report.
  A late delivery failure cannot replace an already ended/failed terminal state.
- Shutdown waits for the CALL response-delivery executor as well as GAME/AI
  workers, using the same bounded deadline. A still-running callback returns busy
  and retains the native owner; waiting does not hold the mailbox monitor.
- The Swift runtime serializes the complete destroy/close transaction. A retry
  after successful match destruction does not destroy the same match twice.
- One bounded startup diagnostic survives failed initialization and isolate close,
  and remains local and explicitly deletable.
- Session refresh cannot enter during teardown; cancelled/backgrounded late polls
  are discarded, and a closed poll clears the old private board and log.
- Native workflow push filters include actual engine/platform/native inputs so a
  production Java change no longer silently skips the full rebuild. Existing
  non-simulator checks also cover this audit branch and the new core regressions.

## Local evidence and its boundary

Executed against the production core classes on OpenJDK 21 with `--release 17`:
405 existing core assertions, 54 failure-boundary assertions and 15 delivery-
shutdown assertions passed. The delivery regression first produced five failing
assertions: two reproduced diagnostic overwrite behavior; three exposed the absent
worker-drain API. The same test passes after the fix. Controlled sinks deliberately
resist interrupts to test a genuinely running executor and bounded ownership.

The prior package's isolated Swift lifecycle check was rerun: 18 assertions pass.
It compiles the modified runtime/session with explicitly test-only observation,
presentation and backend fixtures on Linux. It is not Apple SDK or XMage execution.
Four XCTest cases are included in the existing Mac presentation package for the
real repository workflow. Their full Mac execution must be checked separately.

These tests are not full XMage JVM gameplay, native ARM64 execution or phone
acceptance. The workflow results associated with the final commit are the authority
for wider compilation/test evidence; do not convert a queued run into a pass.

## Required build and desktop continuation

1. Preserve any newer local work; fetch and review this branch before integrating
   it into PR #6. Run the repository's non-simulator checks on the exact final source.
2. Require a NEW successful full native ARM64 archive from
   `magicmobile-far-calls.yml`, including paired headers, SDK libraries, registry,
   Color/catalogue metadata and checksums. The previous `00b33cb` archive cannot
   contain these Java/native-entrypoint fixes. No artifact guard may be bypassed.
3. Set the existing product workflow's `ENGINE_RUN_ID` and `ENGINE_COMMIT` to that
   actual successful run/source, then require source equivalence and actual unsigned
   Release linking. Merely compiling the diagnostic harness is insufficient.
4. Desktop Codex stages the verified inputs using the existing preparation script,
   rechecks the actual Release and exported signed native layout, and preserves
   `com.calebfeliciano.magicmobile` / App Store Connect app `6784735182`.
5. Check an unused build number in App Store Connect before an authorized internal-
   only TestFlight upload. Confirm processing and access to the existing Internal
   group. Do not merely bump the version while using an older library.

## Physical acceptance remains unexecuted

First manually test Token Triumph against one Grave Danger AI, starting-player
selection, mulligan, keep hand and reaching turn one. Then play a complete offline
match; exercise 1–3 AI opponents, mana/X/targets/combat/ordering, repeated starts and
leaves, background/foreground, and real 2–4-device Game Center games. Record memory,
thermal behavior and latency on the actual phone. Review/share diagnostics only
with explicit user action because they can contain hidden card information.
No durable save/resume, host migration, exhaustive card parity or perfect gameplay
is claimed. Build validation and internal distribution are not phone acceptance.
