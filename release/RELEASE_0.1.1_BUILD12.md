# iOS 0.1.1 build 12 — shared D20 presentation and new icon

Apple reports build `0ce1291d-182a-4b38-835f-2f2bdfb05039` as `VALID`, Beta App Review `APPROVED`, and both Internal and External `IN_BETA_TESTING` on September 23, 2026 UTC. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. These states do not prove a completed physical-phone game.

## Changes

- Includes the previously merged shared, host-verified D20 flow: humans tap in turn to roll, the die rebounds from the screen edge, the result appears above the player squares, and ties reroll. Solo AI offers Choose or Roll D20. Game Center AI seats and cancellable turn-skipping remain in the iOS build.
- Replaces the iOS and website icons with an opaque, full-bleed square adaptation of Caleb's supplied artwork. The reference and master are preserved in `design/brand/`. Android was not changed.
- Keeps marketing version `0.1.1`; build number `12` was checked against live App Store Connect before preparation.

## Verification

- Signed source: `7af000c0b963f4d646aeb0e377c76b39f60684ab` ([PR #23](https://github.com/ineedsomesleep5/MagicMobile/pull/23)); the D20 source was previously merged in PR #22.
- Clean-source `ios-fast` preflight passed: `build_output/preflight/ios-fast-rbyv3kfm/`. App, Swift, real-JVM, boundary, checks and website-preview CI checks passed on PR #23.
- The D20 development fixture passed on iPhone 17 Pro Max simulator in portrait and landscape, including distinct human taps and the result-to-player-square spacing. It is not a two-device Game Center or real-engine gameplay test. The compiled icon was inspected on the simulator Home Screen, and the opaque packaged icon was inspected from the signed IPA.
- The website production build passed locally. Public production deployment is a separate check after merge.
- Exact-input native engine artifact `10674460689` was reused from engine commit `54264b0ae2645515b8dacf908c9be6bfd0db247c`, workflow run `35673448459`; staged engine archive SHA-256 `cc30f89075fca4e413147b9159b07e665603eaea9bfa3cb0bb09e7adf4809daf`. Source, provenance, export, linkage, signing, privacy and Game Center entitlement guards passed. No engine rebuild was needed.

## Signed artifact and Apple distribution

- Fingerprint-bound release controller run `ios-0.1.1-12` completed for source `7af000c0b963f4d646aeb0e377c76b39f60684ab`.
- IPA: `build_output/testflight/native-release.h6VCfZ/export/MagicMobile.ipa`; SHA-256 `cffca9d704f152318c78b0486026db23c3e48b0afb6b7dda03c5700a30008277`. Apple validation passed with no errors.
- Apple delivery UUID and build ID: `0ce1291d-182a-4b38-835f-2f2bdfb05039`. Internal group `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` and External group `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb` are assigned. Live beta detail reports `IN_BETA_TESTING` for both; Beta App Review is `APPROVED`.
- Physical-phone installation of this exact TestFlight build and a completed live game were not checked in this release run.
