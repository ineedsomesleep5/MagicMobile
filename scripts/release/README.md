# Guarded local release controller

`controller.py` records one exact, clean Git checkout and native input set for an
iOS or Android release. It wraps the existing guarded scripts; it does not replace
their native, signing, Apple, or Android checks. This is a local release aid, not
release approval or phone acceptance.

Before expensive work, use `python3 scripts/release/preflight.py plan --profile ios-fast`
to inspect the local checks, then `run --profile ios-fast` to execute them sequentially.
`tooling` runs Python tooling tests, diff checks and shell syntax only. `ios-fast`
adds temporary generated-project comparison, standalone Deck Studio compilation,
and the two portable Swift suites. Neither profile boots a simulator, builds the
native engine, signs or uploads. Live artwork and precon-export test opt-ins are removed from the
child environment. Results are fresh development feedback, never CI reuse receipts.
Logs and timing survive failures under a unique `build_output/preflight/` directory;
do not edit source during the run. A per-checkout lock prevents duplicate preflights.

The native decision is conservative **source equivalence only**, using the existing
native verifier and local provenance receipt (or `--engine-commit FULL_SHA`). Dirty,
untracked, missing or invalid evidence reports unknown. Different inputs mean to
look for another exact artifact, not automatically rebuild. Equivalent inputs still
require artifact byte/provenance verification, product linkage and release gates.

Use a committed, reviewed candidate in the selected checkout. Finish the separate
native resolver and validation work first when it applies; the controller verifies
the actual staged native binaries against their manifests and the existing scripts
perform their own source/native gates. No CI evidence is silently promoted to
signed or distributed evidence.

```sh
# Android: set the normal signing environment plus exact non-secret version targets.
export MM_ANDROID_VERSION_CODE=2026092102 MM_ANDROID_VERSION_NAME=0.1.1
python3 scripts/release/controller.py plan --platform android --run-id android-0.1.1-8

# iOS: the prepared build number and App Store Connect availability remain
# prerequisites of deploy-testflight.sh.
python3 scripts/release/controller.py plan --platform ios --run-id ios-0.1.1-8
```

`plan` is read-only and prints `identity.fingerprint`. A release invocation is
explicit and bound to that fingerprint:

```sh
python3 scripts/release/controller.py resume --platform ios --run-id ios-0.1.1-8 \
  --authorize-fingerprint SHA256_FROM_PLAN
python3 scripts/release/controller.py status --run-id ios-0.1.1-8
python3 scripts/release/controller.py status --run-id ios-0.1.1-8 --summary
```

`status --summary` retains the validated state, source/fingerprint, recorded upload
identity and next action without dumping the full event history. A stale historical
completion stays stale; this command makes no live Apple request and does not prove
current tester availability. Use full `status` for the underlying event trail.

The first iOS `resume` runs `deploy-testflight.sh --stop-after-upload`, including
its existing guards, signed export, Apple validation, upload, and ledger record.
It stops at `uploaded` after verifying the exact IPA, receipts, delivery UUID,
and narrowly scoped ledger change. A second `resume` with the same fingerprint
runs `distribute-testflight-groups.sh` for that exact release root. That script
waits for the exact Apple build, verifies its processing and Internal/External
groups and Beta App Review state, and records its own evidence. The controller
checks the Apple build response again before marking `completed`. The default
invocation of `deploy-testflight.sh` remains the original full flow.

An interrupted or failed upload or distribution is `uncertain`; `resume` never
repeats it. For an uncertain upload that has a complete local upload log,
receipts, IPA, and ledger entry, `reconcile` makes one read-only exact-build
Apple query and attaches the verified result. It can then proceed to the
distribution stage with `resume`. If those local identifiers are missing or
Apple has no exact valid build, manual investigation is required. An uncertain
distribution requires manual inspection of Apple group and review state; no
automatic repeat is offered.

```sh
python3 scripts/release/controller.py reconcile --run-id ios-0.1.1-8 \
  --authorize-fingerprint SHA256_FROM_PLAN
python3 scripts/release/controller.py watch --run-id ios-0.1.1-8 \
  --github-run-id EXISTING_RUN_ID --timeout-seconds 30 --interval-seconds 10
```

`watch` only polls an existing GitHub Actions run, checks its exact head SHA, and
stops within 60 seconds. It does not dispatch anything. Evidence records live
under ignored `build_output/release-controller/<run-id>/events/` as a sequenced,
hash-chained local audit trail. The trail detects accidental edits but is not a
trusted external timestamp or tamperproof remote ledger. Artifacts and logs are
recorded by SHA-256 and rechecked on completed status. A stale completed run is
reported as historical and will not run a mutation again. Android completion
means the existing script built and verified a signed APK; it does not publish
the APK or prove device gameplay.
