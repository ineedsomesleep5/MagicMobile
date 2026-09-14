# Current continuation: runtime hardening for the next internal TestFlight

Use [PR #9](https://github.com/ineedsomesleep5/MagicMobile/pull/9), branch
`codex/native-runtime-hardening`. It includes PR #8's release/session safeguards
and PR #6's native engine integration. Do not reinstall an earlier ZIP or reset
the project to its original checkpoint. Preserve uncommitted desktop work.

## Exact candidate, not an already-uploaded app

- Reviewed application code: `101985d7f8175c2ec4ddb3c2945b7062055b704d`.
- Production engine source: `f8e16802bf033adfd844b878248b30042b838481`.
- Full ARM64 engine gate: [34803650513](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34803650513).
- Actual native-linked unsigned Release product: [34805592902](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34805592902).
- Full non-simulator suite on the application code: [34805592973](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34805592973), passed.
- CI [34805598621](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34805598621) and
  package gates [34805598624](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34805598624), passed.

The native and product gates must actually conclude successfully before staging
or release. Their names, queued/running state, small probes, and old green builds
are not substitutes. Read `implementation-status.json` and the latest PR #9
evidence for their recorded conclusions and exact artifacts. A documentation-only
continuation can retain the code/engine identities above; verify source equality.

## Implemented and verified boundaries

The repairs retain the full XMage/MAD implementation and the Color/AWT, token,
and bundled catalogue adaptations. They add safe startup diagnostics, explicit
failed-delivery handling, durable and retryable shutdown, CALL/GAME/AI worker
termination checks, late-poll rejection, and bounded transient API retries in
the exact-native gate. No cloud rules engine, pruned card registry, simulator
execution, new paid runner, signing or upload is introduced by this continuation.

The latest downloaded Mac logs report **121 app tests**, **33 protocol tests**,
**five build-number tests**, and **27 runtime-manager fixture assertions** passed.
The actual generic-iOS app and SDK tests compiled; they were not executed.
Real XMage JVM regressions, completed two-/four-seat and token/mulligan games,
and validation/first prompt of all five exact bundled decks passed. Boundary,
JVM, native compilation, product linking, signing and phone gameplay are distinct.
See [the audit](NATIVE_RUNTIME_AUDIT_20260913.md) for failure reproductions and scope.

## Last recorded uploaded build is older

[0.1.0 (2026091301)](TESTFLIGHT_2026091301.md) was recorded as uploaded and
available to the existing Internal group. It uses engine `00b33cb`, not the
runtime-hardened engine above. This GitHub continuation does not upload a new
TestFlight build. Do not reuse that old archive, old build number or old success
receipt for these repairs. Build 2026091203 is an earlier diagnostic release;
its Color/AWT failure was identified, not an unknown exception awaiting diagnosis.

## Desktop Codex release sequence

1. Reconcile the latest PR #9 branch in the selected checkout. Use the real
   `apps/ios` product; `apps/ios-ondevice` is only a diagnostic harness.
2. Require the exact successful engine and product results above (or reviewed
   replacements), download/hash-check their artifacts and preserve paired headers,
   static libraries, Color patch, compiler manifest, metadata and source receipts.
3. Stage verified native inputs with the existing helpers. Do not weaken source,
   archive, code-layout or entitlement checks. Do not rebuild AOT on the 8 GB Mac
   merely to replace the already-verified hosted archive.
4. Check App Store Connect for an unused build number, prepare and commit it,
   regenerate the native product, and use the existing guarded release script.
   Preserve `com.calebfeliciano.magicmobile`, app `6784735182`, and internal-only
   distribution. Signing/export/Apple validation/upload are desktop tasks.
5. Confirm Apple processing and Internal-group availability. Then Caleb follows
   [physical acceptance](TESTFLIGHT_ACCEPTANCE.md) on the exact new build. USB is
   not required for this TestFlight route. No phone acceptance is inferred here.

Previous chronological notes remain in
[Git history at the last uploaded-build source](https://github.com/ineedsomesleep5/MagicMobile/blob/7992311b4a41720f9a37858e44dbd5122ae5bdb2/packages/ondevice-engine/docs/LOCAL_CONTINUATION_STATUS.md).
Those notes and old release documents are historical, not the current handoff.
