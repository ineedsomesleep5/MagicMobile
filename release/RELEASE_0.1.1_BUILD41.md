# iOS 0.1.1 build 41: removal plays out, token piles, attachment tabs

Apple reports build `000ab666-8cb1-4feb-93c7-72c6a4b18941` as `VALID`, with Internal and External both
`IN_BETA_TESTING` and Beta App Review `APPROVED`, on October 15, 2026. The External invitation remains
https://testflight.apple.com/join/2mSHE8rZ. Same native engine as build 40 (main `160e250`), together with Android
build 25 (`release/RELEASE_ANDROID_0.1.1_BUILD25.md`).

## Changes (Caleb's critiques of build 40, #183)
- Removal plays out: a spell is read to its end and a card leaving play finishes before the next group or snapshot
  plays; the turn banner waits for them; smart pass gives the board up to 1 s to take in a snapshot (was 150 ms).
  Abilities keep their quick handoff, so trigger stacks stay fast.
- Choosing several from a token pile: chosen cards come out beside the pile with an ember check, the next tap chooses
  another, and tapping a chosen card takes it back.
- Equipment and aura tabs in a lower row sit inside their creature instead of covering the card above.

## Release
- **Source:** `codex/ios-build-41` (main `1f99736` + build number 41). Engine staged from build 40
  (`prepare_ios_app_native.py --verify-installed`); preflight native decision `equivalent-source`. Xcode 27.0 (27A266a).
- **Run:** `ios-0.1.1-41`, fingerprint `3648febc…`, delivery `000ab666-8cb1-4feb-93c7-72c6a4b18941`, IPA `01625b7f…`.

## Verification
- Preflight `ios-fast`: 14/14 on the final source.
- `swift test --package-path apps/ios`: 692 tests, 0 failures (5 skipped). Simulator tests for the changed areas
  (BoardEventTimeline, ParityGolden, PortraitPolish with every design preview, smart pass, interaction policy): 83/0
  and 42/0 after the test move. Simulator screenshots of the token pile and lower-row attachment tab checked.
- The full iOS unit suite in the simulator froze this 8 GB Mac into a kernel panic during this work; it is no longer
  run locally (docs/LESSONS.md, CI covers it).
- **Not run for this build:** the UI test suites and a physical iPhone. Caleb tests from TestFlight.
