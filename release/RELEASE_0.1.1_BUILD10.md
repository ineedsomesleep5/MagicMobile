# iOS 0.1.1 build 10 — Internal and External TestFlight

App Store Connect reports build `c9d499b3-e1e9-4b17-9658-10b19bf8e3a9`
as `VALID`, Beta App Review `APPROVED`, and both Internal and External build
states `IN_BETA_TESTING` (verified September 23, 2026 UTC). The public External
invitation remains https://testflight.apple.com/join/2mSHE8rZ. These are
distribution gates, not physical two-device gameplay acceptance.

## Scope

- Game Center can combine human players and AI opponents in a four-seat match.
  The host sets bot deck and skill before the game. Dedicated Online mode is
  unchanged.
- The host generates authoritative D20 results, including tied-player rerolls,
  and both clients show the same SceneKit 3D die animation, result, and seat
  feedback. The animation never determines or changes the game result.
- Solo AI games offer the existing choose-starting-player path or a D20 roll.
- Multiplayer seats can skip optional priority windows to the end of a turn or
  their next turn, cancel skipping before the next window, and still stop for
  mandatory choices. Already-passed windows cannot be undone.
- iOS-only app and website update. Android source, build, and release unchanged.

## Reviewed source and verification

- Feature source commit `8ba45f0a39ba18f414d74e861741cd1a210fcdec`;
  signed release candidate commit `1220a67fdc577aa927934929f362940424292f52`.
  The latter prepared version `0.1.1` build `10`; no native engine source changed.
- `ios-fast` preflight passed: 421 presentation tests, five skipped, zero failed;
  tooling, native Swift compilation, and generated-project checks passed.
  Evidence: `build_output/preflight/ios-fast-_q6648m1/`.
- Focused starting-player/roll tests passed. Two simulator UI fixtures passed
  for D20 presentation in portrait and landscape and the solo-AI setup option;
  screenshots were reviewed. Result bundle:
  `build_output/ios-ui-harness/dice-ai-build/Logs/Test/Test-MagicMobile-2026.09.22_20-13-10--0500.xcresult`.
  Fixtures are not native multiplayer acceptance.
- PR #20 checks passed: boundary, tooling, Swift, real JVM, general checks,
  and Vercel preview. See https://github.com/ineedsomesleep5/MagicMobile/pull/20.
- Reused exact-input native artifact `10674460689` from engine source
  `54264b0ae2645515b8dacf908c9be6bfd0db247c`, workflow run
  `35673448459`. Native ZIP SHA-256:
  `9454b75e886a670d524c2782851a6b073f09c0df952d8daf509b438dfd54fa00`.
  Archive SHA-256:
  `cc30f89075fca4e413147b9159b07e665603eaea9bfa3cb0bb09e7adf4809daf`.
  Exact-input reuse and staging guard passed; no engine rebuild was needed.
- Physical Caleb and Ruthie devices were unavailable to the local host. A
  two-device Game Center match, bot-seat gameplay, and interruption/cancel
  behavior on phones still require hands-on acceptance.

## Signed artifact and distribution

- Fingerprint-bound release controller run `ios-0.1.1-10-retry1` completed.
  The first run stopped during linking for lack of local disk space before an
  archive or upload existed. Only regenerable local build and package caches
  were cleared; release evidence and prior archives were preserved. The retry
  used the same source fingerprint
  `1bbbd14452e125040be8f2ee738c0eca78dc14f13ba742aaef75dbbb0d047f9e`.
- Signed archive, IPA export, native/signing/privacy guards, and Apple validation
  passed. Exported IPA:
  `build_output/testflight/native-release.A05S37/export/MagicMobile.ipa`.
  IPA SHA-256:
  `20ed74e9353a19718f9227de36756b50a28a497bbbb895144d9cee19e6d35f25`.
  Signed receipt SHA-256:
  `4f837b97468d0b44c3c2d9dd297ad3a6c6581a13bb7eb47adf71b469eea8e460`.
- Upload, unique Apple build lookup, group membership, and Beta App Review were
  verified from App Store Connect responses preserved under
  `build_output/testflight/native-release.A05S37/`. External group
  `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb`; Internal group
  `dd37d7bb-26d8-4a0c-b8a3-7811d648a699`. Both build-beta-detail states
  were freshly read as `IN_BETA_TESTING`.

Website production deployment and final main merge are tracked in PR #20;
verify the public page after merging rather than treating a preview as live.
