# iOS 0.1.1 build 32: paper page curl, dice on the table, visual profile and friends

Apple reports build `44e82cb2-7134-41a6-b787-0667b4da2f6a` as `VALID`, with internal and external state `IN_BETA_TESTING`
(Beta App Review passed), in the Internal (all builds) and External (added) groups, on October 7, 2026. The External
invitation remains https://testflight.apple.com/join/2mSHE8rZ. None of this proves anything on a physical iPhone or iPad.

## Changes ([#121](https://github.com/ineedsomesleep5/MagicMobile/pull/121), on [#119](https://github.com/ineedsomesleep5/MagicMobile/pull/119))
- **Pages curl like paper** and can be dragged by hand (Metal; `docs/deck-studio/PAGE_CURL.md`).
- **The head is on the paper** on every screen, so facing pages are the same height and turn together; a compact
  landscape title plate and filter panel; Quick Add / Add cards float over the page.
- **The binder's own menus and confirmations** everywhere in Deck Studio (parchment in brass, mana symbols).
- **No Playtest chapter**: Cards, Ideas, Analysis; game history moved to the profile.
- **The starting roll on the tavern table**: a Blender-built d20 per player lands on the decided number (SceneKit;
  `docs/STARTING_ROLL.md`).
- **Visual profile, friend search as you type, public profiles and a privacy setting** (public by default), with
  finished games uploaded for signed-in players (`docs/social/PROFILES.md`). The `public_profiles` migration is live.

## Verification
- **Signed source:** `codex/ios-build-32` at `1d60adf`: the build-31 release branch merged with `codex/polish-studio`
  at `d6454c4`, plus the build-32 bump.
- **`ios-fast` preflight:** passed 14/14 (after fixing the UI runner's presentation preset, which named the moved
  match-dashboard test), native decision `equivalent-source`.
- **Engine:** the build 21 engine re-staged from `verified-native-10945664948`; `libmmengine.a` SHA-256 `466597b2…9753`.
- **Tests (on #121):** `swift test` 615 / 0 failures; `MagicMobileTests` 870 / 0 failures; 52 UI tests (Grimoire, Deck
  Studio, OnDeviceSetup, ProfileHistory, Social, Ranked, NativeDownloads, HowToPlay, the D20 board tests): 51 first time,
  1 on retry (a dropped simulator tap). Menus, confirmations and the floating bar checked by hand on the simulator.
- **Run:** `ios-0.1.1-32`, fingerprint `343fa172…74ce`, IPA SHA-256 `9545b94a…1357`, delivery `44e82cb2…`, Xcode 27.0 (27A266a).
- **Not verified:** a physical iPhone or iPad (curl feel, frame rate, dice on older devices).
