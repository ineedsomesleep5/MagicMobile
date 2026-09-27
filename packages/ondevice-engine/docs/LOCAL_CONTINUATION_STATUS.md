# Current continuation: runtime hardening for the next internal TestFlight

Use [PR #9](https://github.com/ineedsomesleep5/MagicMobile/pull/9), branch
`codex/native-runtime-hardening`. It includes PR #8's release/session safeguards
and PR #6's native engine integration. Do not reinstall an earlier ZIP or reset
the project to its original checkpoint. Preserve uncommitted desktop work.

## Save/resume checkpoints for solo games: JVM-verified, native pending (September 26, 2026)

Branch `codex/save-resume-engine`. Engine phase 1 of
[the save/resume spike](../../../docs/SAVE_RESUME_SPIKE.md) plus the native metadata it needs
(phase 2 preparation). Contract: [PROTOCOL.md](PROTOCOL.md#saveresume-checkpoints-solo-games).
The app Resume/Abandon flow, file location and 10-minute window are app-side work.

- **Engine.** `create` takes `checkpoint.path` for exactly one human seat; the GAME thread
  writes the match atomically at each human priority decision before publishing it; polls
  report `checkpoint`/`checkpointFailure`; `restore` rebuilds the match in a new process and
  re-asks that decision. The RNG state is saved and restored. Twenty reviewed upstream
  sources are now patched by `prepare_upstream.py`: `Exile`, `GameImpl`, `RandomUtil`,
  `ComputerPlayer` and `HumanPlayer` complete deserialization, and (September 27) thirteen
  classes holding Serializable `Condition`/`Predicate` lambdas get named enum singletons that
  call the same upstream code, so no checkpoint needs a serializable lambda (see below).
  Existing `.upstream/mage` checkouts must be bootstrapped again; the patcher refuses an old stamp.
- **Verified (desktop JVM only).** `RealCheckpointTests`, now part of `test_real_engine.sh`
  and so of the real-jvm CI job. One human seat against 1 or 3 AI seats:
  - In each of two consecutive full-suite runs, 8 of 8 fresh-JVM restores matched the
    checkpoint's turn, step, life, hands, full library order, battlefield, graveyards, exile and
    stack, re-asked the same prompt, kept checkpointing and played to a legal end (win or turn
    cap) with 0 game errors.
  - Every run restores checkpoints holding tokens, exile, a token copy, a control change and a
    stack object. The four-seat precon scenario saves the first natural appearance of each;
    whatever play has not produced by turn 10 is put on the live game through upstream rules
    code (a Soldier token, a token copy of a basic land, the top library card moved to exile,
    Zedruu's own gain-control effect, a reflexive trigger on the stack) while the GAME thread
    waits for the human's priority answer. A click on no object then makes XMage re-ask that
    decision, and that next checkpoint is restored like the others. The log names natural and
    placed features (`FEATURES`, `PLACED`); both runs had a natural stack object and placed the
    other four (the stack placement was checked separately). This replaced waiting up to three
    AI-driven games for them, which failed once in CI.
  - 97–103 checkpoint writes per run: median 26–27 ms, p90 35–38 ms, max 115–127 ms; 162–318 KB
    each. Restores took 0.4–0.75 s in a cold JVM. `RealCheckpointTests` took 109–118 s (was 319 s).
  - RNG continuity: 64 draws after a restore equal the saved process's next 64 draws.
  - Rejections: more than one human seat, bad paths, header identity, format, SHA-256,
    truncation, a filter-rejected class and a wrong root; a failed write keeps the game playing;
    a failed restore leaves no match or threads.
- **First native attempt failed; fixed without serializable lambdas (September 27).** Android
  run 36287088288 (`9b26186`) stopped 20 s into image generation: GraalVM 22.1 requires
  `writeReplace` on every lambda of a `lambdaCapturingTypes` class, and `Checkpoints` and
  `XmageEngine$Running` also create ordinary lambdas. Branch `codex/native-serialization-fix`
  removes the need for any: the 13 upstream classes use named singletons, the adapter uses named
  classes, the checkpoint allowlist drops `SerializedLambda` (writer and reader refuse lambdas),
  the writer now reports the refused class instead of its own follow-on error, and
  `NativeReflectionExporter` fails if any scanned class still declares `$deserializeLambda$`. The
  export registers 48,730 types and an empty `lambdaCapturingTypes`
  ([NATIVE_METADATA.md](NATIVE_METADATA.md#saveresume-serialization-metadata-september-26-2026)).
  Android run 36289659903 on this branch then got past that point, but `[2/7] Performing
  analysis` was still running when the 120-minute job limit cancelled it, 110 minutes later.
  GraalVM 22.1's serialization configuration makes every declared constructor and method of each
  entry reflectively invocable (roughly 315,000 compiled stubs here). So the class list now
  registers through `CheckpointSerializationFeature`: classes, fields, queried constructors,
  serialization hooks and GraalVM-generated constructor accessors only (see NATIVE_METADATA.md).
  The next Android run on this branch is pending. The PR records its result.
- **Not verified.** A complete native image with this metadata unless stated above, native
  serialization at runtime, phone write/restore times, iOS/Android app integration,
  process-kill acceptance.
- **Next native gates (need dispatch).** iOS: `magicmobile-issue4-nonsimulator.yml` on the
  candidate SHA, then `magicmobile-far-calls.yml` with `candidate_sha` and that run's
  `cheap_run_id`, then `magicmobile-product-device.yml` with `engine_run_id`/`engine_commit`.
  Android: `magicmobile-android.yml`. A build without the metadata reports
  `saveResume: false` rather than failing games.

## Subsequent authorized internal TestFlight upload

[Build 2026091401](TESTFLIGHT_2026091401.md), release source
`a718978e59b0fe4ef90568cf190d5fe5b0ecff41`, passed archive/export/signing/layout
and Apple validation, then uploaded successfully. Delivery UUID:
`4e99955e-55eb-4371-9fc2-46e9c5ab0da2`. Apple confirms VALID and IN_BETA_TESTING, with verified access for the existing
Internal group. Build 2026091401 is available in internal TestFlight. It uses the exact new engine below, not the
older 2026091301 archive. No public release or physical acceptance occurred.
The following pre-phone/old-build sections are historical evidence for this release;
the separate release handoff supersedes their no-upload/build-number statements.

## Verified pre-phone candidate — September 14, 2026

Functional application and engine source: `d04f9cac88d680af10fe7174fab85f624e5ad491`.
[Non-simulator 34871098576](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34871098576),
[CI 34871103720](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34871103720)
and [package 34871103725](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34871103725)
passed. All five non-simulator jobs and their required steps executed successfully;
package upstream reporting was intentionally skipped on the PR event.

A **new** full ARM64 engine was required by the production mana validation and
guarded engine regressions. [Native 34872508758](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34872508758)
passed on attempt 1 after the exact-SHA cheap approval gate.
[Unsigned Release product 34883826069](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34883826069)
passed on the same application source with that exact artifact; all required
verification, staging, release-source, linking and settings steps passed.

Native artifact `10363785536`, ZIP SHA-256
`b82f90f08f7ac0b3505b96cf23e83e1759e517bbf4243b4543dd296051fa4c0a`,
was downloaded safely and all 51 hash-covered inputs verified. Archive SHA-256:
`b4e361b5687474e658dcc25470e70de6f8816c08c8f11e4fd49be78eec9424f8`.
Guarded input digest:
`1a9a449fd8af68bd96bc7f5d4b3f729ff1ecc5c4122e4b38c69c8ff1ffe2db95`.
Product evidence artifact `10364317309`, ZIP SHA-256
`0458ffd778cd4b207be53fe8011302dcd93637554350f5b7c1d0359d88ff743b`,
was downloaded/hash-checked. Its receipt binds the exact engine provenance and
records unsigned binary SHA-256
`3c7deafd526ed09a2d85cdfe6dc2c48b34089b3f3cead652167d898c05f8442c`,
191,584,800 intact Graal code bytes, 818 verified relocated instructions and seven
verified veneers. This is ARM64 compilation/product linkage, **not native execution**.

The final documentation commit may be newer than this functional source. Reuse
requires unchanged guarded engine and application/product inputs; a newer document
timestamp is not a new hosted build. No signing, upload, simulator, phone execution
or actual Game Center transport acceptance occurred. The unsigned product still
uses the old build-number setting `2026091301`; it is not upload-ready with that
number. Select an unused number only in a separately authorized release task.

See [MAINTENANCE_CHECKPOINT.md](MAINTENANCE_CHECKPOINT.md) and
[PRODUCTION_COVERAGE_LEDGER.md](PRODUCTION_COVERAGE_LEDGER.md) for the tested matrix
and remaining per-family limitations. Upstream schedules/publishing remain inactive.

## Prior verified candidate, not an already-uploaded app

- Reviewed application code: `101985d7f8175c2ec4ddb3c2945b7062055b704d`.
- Production engine source: `f8e16802bf033adfd844b878248b30042b838481`.
- Full ARM64 engine gate: [34803650513](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34803650513).
- Actual native-linked unsigned Release product: [34805592902](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34805592902).
- Full non-simulator suite on the application code: [34805592973](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34805592973), passed.
- CI [34805598621](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34805598621) and
  package gates [34805598624](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34805598624), passed.

Both native and product gates concluded successfully, verified live September 14.
Native artifact `10334439109` ZIP SHA-256 is
`4fcb8e958f9e4b95082f0b6e0f242312b8232072d038215eeb885cf82b91fbba`;
all 51 hash-covered paired inputs passed receipt verification. The engine archive
SHA-256 is `99c8d7ef186c37d3c409473101eaeb89abc8075cbb5eaddad9196eff43e97a9b`.
Product evidence `10334294606` ZIP SHA-256 is
`1d002beee11ac869a333923e5f14e4e16b677e1a7e6e920755ffba918d68f306`.
Its receipt records 191,665,664 intact Graal code bytes, 818 verified relocated
instructions and seven veneers. These are compilation/linkage results, not
native gameplay. Maintenance continuation must recheck final guarded-input equality.

## Implemented and verified boundaries

The repairs retain the full XMage/MAD implementation and the Color/AWT, token,
and bundled catalogue adaptations. They add safe startup diagnostics, explicit
failed-delivery handling, durable and retryable shutdown, CALL/GAME/AI worker
termination checks, late-poll rejection, and bounded transient API retries in
the exact-native gate. No cloud rules engine, pruned card registry, simulator
execution, new paid runner, signing or upload is introduced by this continuation.

The final hosted Mac logs report **124 app tests**, **21 XCTest plus 33 Swift Testing protocol cases**,
**five build-number tests**, and **27 runtime-manager fixture assertions** passed.
The actual generic-iOS app and SDK tests compiled; they were not executed.
Real XMage JVM regressions, completed two-/four-seat and token/mulligan games,
and validation/first prompt of all five exact bundled decks passed. The ten bounded
real-JVM soak scenarios passed with two/four humans and one/two/three MAD opponents.
Core checks passed 419 assertions plus 72 failure-boundary assertions; tooling ran
228 cases with two explicit skips. Boundary,
JVM, native compilation, product linking, signing and phone gameplay are distinct.
See [the audit](NATIVE_RUNTIME_AUDIT_20260913.md) for failure reproductions and scope.

## Last recorded uploaded build is older

[0.1.0 (2026091301)](TESTFLIGHT_2026091301.md) was recorded as uploaded and
available to the existing Internal group. It uses engine `00b33cb`, not the
runtime-hardened engine above. This GitHub continuation does not upload a new
TestFlight build. Do not reuse that old archive, old build number or old success
receipt for these repairs. Build 2026091203 is an earlier diagnostic release;
its Color/AWT failure was identified, not an unknown exception awaiting diagnosis.

## Separate, explicitly authorized desktop release sequence

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
