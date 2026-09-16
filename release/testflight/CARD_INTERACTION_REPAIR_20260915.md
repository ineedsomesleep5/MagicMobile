# Card interaction repair candidate — 2026-09-15

Selected checkout: `MagicMobile-runtime-hardening`, branch
`codex/native-runtime-hardening`, PR #9. Baseline: `c76b9a41c858cb5ebcae483cd028f60a90ba47c5`.
Prepared internal-only TestFlight build: **0.1.0 (2026091502)**.
Uploaded application source: `654850ea8d27e0e7fe28f81a3c557c393560c28d`.

## Changes and acceptance contract

- Sideways swipes browse the entire hand; upward drags retain the existing legal
  play resolver. Tap/hold and accessibility actions inspect the card. The scrubber
  follows the actual scroll offset. No command is invented by the gesture layer.
- Native single-UUID card choices open an automatically sized card browser.
  Supplied nonmatching cards remain visible but disabled; `possibleTargets` and
  `chosenTargets`, not the broader transport candidate inventory, govern legality.
  Face aliases inherit their base card's eligibility. Hidden cards lose identity,
  rules and nested reverse-face details. ID-only offboard choices recover only
  matching cards from the current authenticated snapshot.
- Mixed card/player/other targets remain available. Selection and deselection
  submit one original ID and current prompt revision. Optional Done uses only
  the engine's explicit Boolean response. XMage owns subsequent choice/order loops.
- Priority does not automatically open a large action sheet over the stack.
  Scry/search inspection is separate from ordinary Pass/Skip/card controls.
- Game logs use native styled text: player/card emphasis, readable actions and
  turn separation, no raw HTML or UUID attributes. Only UUID-matching card suffixes
  are suppressed. The log stays closed until requested and does not force readers
  back to the bottom when they are reading earlier events.

## Verification checkpoint

Evidence is retained locally under `build_output/choice-repair/`.

- `presentation-final.log`: 236 tests, one optional fixture test skipped, zero failures.
- `protocol-final.log`: 33 protocol/transport tests passed.
- `core.log`: 419 core assertions plus 72 failure-boundary assertions passed.
- `adapter-javac.log`: current production Java adapter compiled without diagnostics.
- `real-card-choices.log`: eight real-JVM cases passed, including actual ScryEffect,
  filtered/restricted/zero-match searches and mailbox seat isolation. Pinned
  upstream compiled dependencies were reused locally; hosted clean-build evidence
  remains a separate gate. The same bounded runner is wired into the real-JVM job.
- `build-number.log`: six build-number tests passed. App Store Connect returned
  no existing build 2026091502 at preparation. Existing Internal group has all-build access.
- Simulator unit suite: 422 tests, one optional fixture test skipped, zero failures.
- Initial simulator failures exposed priority-sheet routing and competing hand
  gestures. Both were repaired; a separate subpixel edge assertion was corrected
  after confirming the final hand card was fully visible.
- `gesture-arbitration.xcresult`: five focused hand drag/scroll and stack/rotation
  cases passed. Native pan failure dependencies preserve horizontal browsing and
  upward casting in both orientations. Temporary diagnostics were removed.
- `final-ui.xcresult`: all 38 UI tests passed on the frozen candidate: 26 board
  cases across portrait/landscape/rotation and 12 setup/deck cases. Coverage includes
  import/draft retention, catalogue add/quantity, basic lands/statistics, saved
  edit/relaunch, bundled-deck preservation and explicit missing-native failure.
- Independent diff review found mixed-target omission and inaccessible hand
  inspection; both were repaired. Final independent source review found no remaining
  concrete P1/P2 blockers. No new runtime acceptance is inferred from that review.

Exact final UI command (Xcode 26.6, build 17F113; one iOS 26.5 simulator):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apps/ios/MagicMobileiOS.xcodeproj -scheme MagicMobile \
  -destination 'platform=iOS Simulator,id=20430895-8C80-4FFA-B4A0-6C4E9B126DD0' \
  -derivedDataPath build_output/deck-ui-preview -jobs 2 \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  GENERATE_INFOPLIST_FILE=YES CODE_SIGNING_ALLOWED=NO \
  -only-testing:MagicMobileUITests/BoardPolishUITests \
  -only-testing:MagicMobileUITests/OnDeviceSetupUITests \
  -resultBundlePath build_output/choice-repair/final-ui.xcresult test
```

Same-source hosted gates all succeeded:

- [CI 34984735380](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34984735380).
- [On-device gates 34984735232](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34984735232).
- [Non-simulator 34984729875](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34984729875):
  Apple source/SDK, protocol/presentation, portable contracts, clean real JVM,
  all eight new card-choice cases, ten lifecycle scenarios with 1/2/3 MAD opponents
  (driver seeds, not seeded XMage RNG), and all five exact Swift-exported bundled
  decks through Commander validation and first prompt. No required job skipped.
- [Unsigned native product 34984748470](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34984748470):
  source-matched ARM64 iPhone product, native exports, intact Graal code image,
  818 relocated instructions and all seven far-call veneers verified. Evidence
  artifact `10403776137`; unsigned binary SHA-256
  `2bb12f660357e787b5e9ede3cc3a029a896f3b8690a952edbd0645f75ee15935`.

## Engine reuse and release boundary

No guarded engine input changed. Existing native run **34930407016**, engine source
`aa50beea953d7c820417826128d88de72123686b`, artifact **10383692026** remains available.
All 51 hash-covered artifact files passed validation locally. Archive SHA-256:
`cc5b79e978d2669d491a6cc9b25703af0cd8367d28429769373599e423a4bf3c`.

Final clean-source equivalence and same-source hosted checks passed. The unchanged
engine was reused without a new ARM64 engine build. The signed/exported app passed
source, signing, profile/entitlement, UUID-matched dSYM, code layout and Apple
validation gates. The simulator was shut down before archiving to free memory.
No Three.js migration, new rules engine, simulator engine, public release or
automatic upstream upgrade is included.

Fixture simulator screenshots prove presentation/interaction only. Real-JVM
checks do not prove native gameplay or Game Center transport. Apple processing,
Internal availability and physical acceptance must be recorded separately.
Phone follow-up: browse/inspect the full hand, drag a legal spell, scry with
Temple of Plenty, inspect authorized graveyard/exile/search pools, check the
formatted log and stack response in both orientations. Retain failures privately.

## Internal TestFlight delivery

- Apple validation and upload succeeded with no errors on 2026-09-15.
- Build **0.1.0 (2026091502)**; delivery UUID
  `3661e758-7029-40ce-9912-f38c2c928920`.
- IPA SHA-256: `134d6859164357552025f6b81d16aab0f7a604a6063d95e4ecb671012f523029`.
- Local archive, dSYM, IPA and all release receipts:
  `build_output/testflight/card-choice-2026091502/native-release.UqHj8V/`.
- Repository-owned `scripts/ios/deploy-testflight.sh` ran with the separately
  prepared/checked build number, `PREPARE_TESTFLIGHT_BUILD_NUMBER=0`, and a new
  task-specific output root. No prior artifact was overwritten.
- App Store Connect upload state is currently `PROCESSING`; installable build
  availability is not yet confirmed. The existing Internal group remains internal,
  has all-build access, and has no public link. No group or tester changes were made.
- Physical gameplay acceptance for this build remains Caleb's manual check.

This document and the upload-ledger receipt may be committed after upload. Such a
documentation commit is not the application source baked into the IPA; that is
the exact `654850e` source recorded above and in the signed receipt.
