# iOS 0.1.1 build 11 — solo AI D20 startup fix

App Store Connect reports build `02e8a9d9-db4a-4192-879b-5b887fe209a8`
as `VALID`, Beta App Review `APPROVED`, and both Internal and External
`IN_BETA_TESTING` (verified September 23, 2026 UTC). The External invitation
remains https://testflight.apple.com/join/2mSHE8rZ. These distribution checks
do not prove gameplay on a physical phone.

## Change

- The native engine's starting-player prompt arrives as `GAME_PICK_TARGET`.
  Solo AI Roll D20 previously recognized only `PICK_TARGET`, leaving the manual
  player-choice prompt on screen. Prompt validation now accepts the native
  method and legacy method while retaining viewer, player, response-command,
  revision, and candidate-ID checks.
- Regression tests exercise the adapter-generated native prompt through the
  rolled-winner response. No engine or Android code changed.

## Verification and source

- Fix commit `043232bccce16e10be1c72607a31fd4ad569417a`; prepared signed
  candidate `1b0f31706a6629014eb728d21b083a8d53404ee8`.
- Committed-candidate `ios-fast` preflight passed, including 424 presentation
  tests (five skipped, zero failed), generated-project checks, tooling tests,
  and native Swift contracts. Evidence:
  `build_output/preflight/ios-fast-h100h8lo/`.
- PR #21 boundary, Swift/iOS compilation, real JVM, general, and website
  preview checks passed: https://github.com/ineedsomesleep5/MagicMobile/pull/21.
- The D20 simulator fixture passed on iPhone 17 Pro Max for portrait and
  landscape. On the smaller iPhone 17 Pro, the same fixture timed out waiting
  for a landscape rotation; that orientation behavior was not changed or
  treated as a D20 pass. Physical solo AI gameplay remains to be checked.
- Exact-input engine artifact `10674460689` was reused from engine commit
  `54264b0ae2645515b8dacf908c9be6bfd0db247c`, workflow run
  `35673448459`. Native ZIP SHA-256:
  `9454b75e886a670d524c2782851a6b073f09c0df952d8daf509b438dfd54fa00`;
  staged engine archive SHA-256:
  `cc30f89075fca4e413147b9159b07e665603eaea9bfa3cb0bb09e7adf4809daf`.
  Source and staging guards passed; no engine rebuild was needed.

## Signed artifact and distribution

- Fingerprint-bound release controller run `ios-0.1.1-11` completed for source
  `1b0f31706a6629014eb728d21b083a8d53404ee8`.
- Signed archive, export, native/signing/privacy checks, and Apple validation
  passed. IPA:
  `build_output/testflight/native-release.uEtLoV/export/MagicMobile.ipa`;
  SHA-256 `0643bd89223daeb9da06626736e84216d5f268b444065802d76f8d9a467ac673`.
- Apple upload Delivery UUID and build ID are both
  `02e8a9d9-db4a-4192-879b-5b887fe209a8`. Internal group
  `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` and External group
  `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb` are assigned. Live build beta
  detail reported both as `IN_BETA_TESTING`, with review `APPROVED`.
- To make room for the archive, older build 7–9 signed archives in this
  checkout were ZIP-compressed and verified before their uncompressed copies
  were removed. Their IPAs, logs, receipts, and recoverable archive ZIPs remain.

Website production deployment and final main merge are tracked in PR #21;
verify the public page after merging rather than treating a preview as live.
