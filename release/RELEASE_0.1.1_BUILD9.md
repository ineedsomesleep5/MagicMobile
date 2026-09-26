# iOS 0.1.1 build 9 — Internal and External TestFlight

Apple processing is VALID, Beta App Review is APPROVED, and both Internal and
External build states are IN_BETA_TESTING (verified September 22, 2026 UTC).
Physical-iPhone gameplay acceptance remains separate and has not been claimed.

## Scope

- iOS only. Android development, versioning and distribution remain paused.
- Resolve compiled MDFCs by combined, front and unambiguous reverse names,
  including existing saved decks and text imports. Unknown cards still fail closed.
- Show green land offers, white spell offers, or a split border when the engine
  currently offers both. Native spell metadata, not a guessed phase or card type,
  distinguishes modal spell offers from other playable actions.
- Match Food's self-named sacrifice cost to the equivalent downloaded token
  identity without collapsing incompatible token variants or replacing valid art.
- Search visible card choices by name, type and rules text. Keep engine selection
  eligibility intact. Center the responsive chooser in both orientations.
- Keep the primary completion action distinct from special actions such as Attack
  all, and bind its view identity to the current prompt/message revision. Actual
  forced attacks from rules such as Kardur remain engine-owned.
- Open opponent-led match history as a full-screen dashboard with responsive
  charts, observation review and inspectable public events. This is sampled
  public evidence, not deterministic replay or reconstructed hidden information.

## Verification recorded so far

- Portable suite: 413 tests, four optional live checks skipped, zero failures.
  Original log: `/tmp/magicmobile-build9-portable-full.log`.
- Separate bulk audit: all 31,881 supported ordinary card names resolved, zero
  unresolved. This is reference coverage, not a fresh download of every image.
  Log: `/tmp/magicmobile-build9-bulk-audit.log`.
- Persisted offline token audit covers runtime Food wording and stored Food,
  Treasure, Clue and Blood; existing missing/corrupt repair tests preserve valid
  cached images. Public token-store evidence remains at
  `/tmp/magicmobile-offline-artwork.zvEZKT/live/`.
- Exporter: 12 self-tests pass. The regenerated alias map adds 44 missing compiled
  MDFCs; no ordinary catalogue values were changed. Full exporter regeneration
  was not claimed: exact complete generation inputs are not available locally.
- Real pinned-JVM modal spell and land-only regressions pass independently:
  `/tmp/magicmobile-build9-real-modal-spell.log` and
  `/tmp/magicmobile-build9-real-modal-land.log`.
- Simulator app/test compilation passes. Five focused UI tests pass for both
  orientations of library search and scry, plus full-screen history inspection,
  preserved observation, rotation, side-by-side charts and legacy fallback.
  Keyboard-open search results stay reachable. Screenshots were visually reviewed.
  Original log: `/tmp/magicmobile-build9-ui-run7.log`; screenshots and earlier
  failed runs remain under `build_output/ios-ui-build9/`. The run exposed unstable
  presentation ownership inside adaptive/lazy content; the full-screen dashboard
  is now owned by the workspace root. These are labeled development fixtures,
  not real native gameplay or physical-device acceptance.
- Ten additional integrated UI regressions pass: both orientations of MDFC
  offer glows and mixed choices, two pinned workspace checks, and four download
  coverage/consent/preference checks. Log:
  `/tmp/magicmobile-build9-ui-regressions.log`. Copies of the accepted logs and
  UI source/binary fingerprint are retained in `build_output/build9-evidence.LP48ic/`.
- Final build-9 rerun: both library-choice orientations and the full-screen
  dashboard pass again, including the no-results message and Clear search action.
  Log: `/tmp/magicmobile-build9-ui-final.log`. App source is frozen after this pass.

## Native and release gates

Upstream remains `4825513287ba6c42c32fd205d227f4a5fc44c2f3`. This candidate
changes the adapter and requires a newly verified native artifact; build 8's
archive is not a substitute.

Frozen native source: `54264b0ae2645515b8dacf908c9be6bfd0db247c` on
`codex/ios-build9-native`. Cheap gate: GitHub run `35672119944` passed all
required jobs, including the real-game lifecycle and bundled-deck checks.
Native run `35673448459` passed, including the complete ARM64 engine build.
The earlier cheap run `35671388465` failed on stale runtime-manager fixture
dependencies. The repair compiles the real production timeline and sanitizer;
it does not stub or weaken the assertions.

The final standalone Deck Studio checks initially missed the production public
timeline dependency. Both recording scripts now compile it; all deterministic
core checks and the fresh PR checks pass. This changed no app or engine inputs.

## Shipped artifact and evidence

- Workflow PR #18 merged as `c184fb31ec38b60777c5be17b65d128ee6cd544b`.
- App PR #19 merged as `f951ee6da7e3c5169452f7d150b38a802e001a3d`.
  This exact clean main commit was signed and uploaded. Its tree equals reviewed
  candidate `3518684c3e418b35354448918ea910d5e8ad275e`; no app changes followed
  the accepted simulator tests.
- Native artifact: `10674460689`; ZIP SHA-256
  `9454b75e886a670d524c2782851a6b073f09c0df952d8daf509b438dfd54fa00`.
  Engine archive SHA-256:
  `cc30f89075fca4e413147b9159b07e665603eaea9bfa3cb0bb09e7adf4809daf`.
- The actual unsigned iphoneos Release product passed native symbol and full
  code-layout inspection. Receipt:
  `packages/ondevice-engine/build/issue4-device-link.dXKb9Y/product-receipt.json`.
- Signed archive/export, UUID-matched dSYM, native code layout, Game Center
  entitlements/profile, Apple validation and upload passed.
- IPA: `build_output/testflight/native-release.ntpIOl/export/MagicMobile.ipa`.
  SHA-256: `23e14222b4b830920932d4a2ba5c724fbbb0d92a0aec3daf69e1c11d0f0faa91`.
- Delivery / Apple build ID: `77b0d94e-623d-41e6-8d64-8b2e603af7f1`.
- Internal group `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` and External group
  `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb` membership verified. English What to Test
  notes saved. Review APPROVED; both groups IN_BETA_TESTING.
- Fingerprint-bound controller `ios-0.1.1-9` completed upload and distribution
  as separate checkpoints. Original receipts, archive, dSYM, validation/upload
  logs and Apple responses remain under the release root above. Previous native
  staging was preserved in `build_output/build9-evidence.LP48ic/NativeEngine-build8-preserved`.

This verifies distribution, not physical-device gameplay or exhaustive card parity.
No Android version, build, artifact or release was changed.
