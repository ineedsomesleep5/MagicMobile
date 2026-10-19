# iOS 0.1.1 build 40: the engine release (Release 2 of the improvement program)

Apple reports build `6fc5463e-68a4-47fe-a7a9-94712c069042` as `VALID`, with Internal and External both
`IN_BETA_TESTING` and Beta App Review `APPROVED`, on October 15, 2026. The External invitation remains
https://testflight.apple.com/join/2mSHE8rZ. It ships a new native engine built from main `160e250`, together with
Android build 24 (`release/RELEASE_ANDROID_0.1.1_BUILD24.md`). Release 3 (the game record) was folded into this
release, so there is no build 41 for it.

## Changes (docs/GAME_IMPROVEMENT_PROGRAM.md, Phases 2 to 5)
- C2 engine release A (#163): stack controllers and a response signal; smart pass lets your own spells and triggers
  resolve and stops only for a play that answers (#175, Settings > Stop for My Own Spells).
- AI difficulty by tier: C2's depths, C3's mistake rates (#176: Bronze and Silver 15%, Gold 10%), C4's expert combat
  planner from Diamond (#170, integrated with the record in #178). Mythic now beats Gold-level AI in 62% of 318 games.
- C4's table-driven card factory: native code 202.0 → 191.1 MB on Android's build of the same engine.
- C5's engine game record (#171); ranked AI games play the server's seed and send the record (#177, #180), and the
  server checks it before a win counts.
- Live on the server with this build: migration `ranked_ai_records` and this engine's build
  `sha256:225ee7decca23267926427ae04d0d89cab105b8ef182032f8838f5c3b45d9869` in `ranked_engine_builds` (docs/RANKED.md).

## Release
- **Engine:** gate `magicmobile-issue4-nonsimulator.yml` run 38771620168, then `magicmobile-far-calls.yml` run
  38776095404 on candidate `codex/native-build-r2` = main `160e250`; staged with `controller.py stage-native`. The
  archive contains the registered engine build identity.
- **Source:** `codex/ios-build-40` (main `160e250` + build number 40). Preflight native decision `equivalent-source`.
  Xcode 27.0 (27A266a).
- **Run:** `ios-0.1.1-40`, fingerprint `13a00038…`, delivery `6fc5463e-68a4-47fe-a7a9-94712c069042`, IPA `d4d15615…`.
  The first distribution attempt refused a stray untracked file in the release worktree; it passed once removed.

## Verification
- Preflight `ios-fast`: 14/14 on the final source, with the new engine staged.
- CI on main: the real-engine JVM suite, including the game record and replay tests and two expert-AI record scenarios.
- iOS unit tests for the record wiring and smart pass (25/0 targeted; the full suite passed 687/0 earlier on the
  smart pass branch); the macOS presentation package after #180.
- **Not run for this build:** the UI test suites, a physical iPhone, and a ranked AI game against the live server.
  Caleb tests from TestFlight.
