# iOS 0.1.1 build 29: friend challenges, the 3D tavern room, art profile pictures

Apple reports build `db99ccf9-765e-4f1f-8ab6-303c58fb8816` as `VALID`, with internal and external state
`IN_BETA_TESTING` (Beta App Review passed), in the Internal (all builds) and External (added) groups, on
October 5, 2026 UTC. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. None of this
proves anything on a physical iPhone or iPad.

## Changes ([#114](https://github.com/ineedsomesleep5/MagicMobile/pull/114))
- **Friend challenges:** challenge an online friend from the friends list to a Quick Match (friendly) or to
  Ranked (same tier only, Gold with Gold; it counts for both). The friend's menu shows an Accept/Decline banner;
  the challenger waits on an overlay they can withdraw. The Supabase `friend_challenges` migration went live on
  October 4.
- **3D tavern room:** the main menu sits in a stylised Blender room with Meshy props, drawn as three depth layers
  that slide with the phone's tilt, with flickering candles, lanterns and hearth.
- **Main menu:** fits the screen in portrait without scrolling; Friends and Profile share a row.
- **Profile picture:** the favorite commander's art alone, chosen from commanders played or any deck.
- **Rank badges:** 32-frame turns, decoded once and crossfaded.
- **Downloads:** rebuilt in the tavern style (wax-seal close, leather cards, parchment pickers, brass progress).
- **Performance:** board FX flights and endless badge spins capped at 60 fps; the room decodes off the main
  thread and its tilt only redraws on a visible move.

## Verification
- **Signed source:** `codex/ios-build-29` at `d793664`: `main` at `7bf463a` (#114 merged, CI green) plus the
  build-29 bump.
- **`ios-fast` preflight:** passed 14/14. The native decision is `equivalent-source` with `ad2e8c3`.
- **Engine:** the build 21 engine, re-staged from `verified-native-10945664948`; `libmmengine.a` SHA-256
  `466597b2…9753`, unchanged.
- **Tests (on #114):** iOS unit tests (ranked parity, AI pools, record store, matchmaker, friend challenges);
  UI suites `NativeDownloadsUITests`, `RankedUITests`, `OnDeviceSetupUITests` green after fixing a tilt
  republishing churn that made the simulator drop taps in Deck Studio; PGlite SQL suites; Android core tests.
- **Run:** `ios-0.1.1-29`, fingerprint `dd94b6a1…f033`, IPA SHA-256 `7e6eb3f8…f60c`, delivery `db99ccf9…`,
  Xcode 27.0 (27A266a).
- **Not verified:** a physical iPhone or iPad; a friend challenge between two phones.
