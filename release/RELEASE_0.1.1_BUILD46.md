# iOS 0.1.1 build 46: Ranked Hall, friend messages and the combo loop (releases A and B)

Apple reports build `6a77fe6d-71c8-4f3d-8b51-cca25cc05fcb` as `VALID`, with Internal and External both
`IN_BETA_TESTING` and Beta App Review `APPROVED`, on October 17, 2026. The External invitation remains
https://testflight.apple.com/join/2mSHE8rZ. Same native engine as builds 40–41 (main `160e250`), together with Android
build 29 (`release/RELEASE_ANDROID_0.1.1_BUILD29.md`). Builds 42–45 went to Internal testers only; this is the first
External build since 41 (docs/ROADMAP_LATE_2026.md, releases A and B).

## Changes
- Release A (#188, #189): Ranked opens the Ranked Hall with a live leaderboard (server `mm_ranked_leaderboard`, live
  since October 16); the Stack chip and auto-restack for spread-out token piles; heat and memory awareness, with
  Settings → Game Performance for the per-game report.
- Release B (#191): messages between friends, outside and inside games (server `friend_messages` and `mm_message_*`,
  live since October 17); the combo loop shortcut in solo games.
- #192: build 44 crashed on the first action of a solo game (`ComboLoop.cycle(in:)` built `1...0`); fixed in 45.
- #193: the combo loop reworked from Caleb's Chatterfang test of build 45: choices kept by kind and the same target
  until it's gone, passes for the player's own triggers, a count picker with Until I can't and Until they lose, no
  prompt flicker, up to 10 rounds at a watchable pace and longer runs fast, round lines and clear stop reasons.

## Release
- **Source:** `codex/ios-build-46` at `c6fb0f77` (`claude/combo-loop-2` `495579c1`, merged as main `428ab6e9`, plus the
  build 42–45 ledger and build number 46). Engine staged from build 40; preflight native decision `equivalent-source`.
  Xcode 27.1 (27A9275).
- **Run:** `ios-0.1.1-46`, fingerprint `c6969225…`, delivery `6a77fe6d-71c8-4f3d-8b51-cca25cc05fcb`, IPA `b8f8375a…`.
  Uploaded to Internal first; External added by the same run's guarded distribution after Caleb said ship.

## Verification
- Preflight `ios-fast`: 14/14 on the final source.
- `swift test` for ComboLoop, OnDeviceSession, BoardEventTimeline, message session and readiness: 72 tests, 0 failures;
  generic-device app build succeeded. PR CI green on every PR above.
- Release B UI tests on the simulator: Messages tab, conversation and quick reply passed.
- **Not run for this build:** the full UI test suites and a physical iPhone. Caleb tests from TestFlight; the reworked
  combo loop has not yet been played with a real loop on a phone.
