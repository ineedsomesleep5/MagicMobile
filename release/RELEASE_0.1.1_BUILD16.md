# iOS 0.1.1 build 16 — board FX build 18 (audio, brand menus, versus intro)

Apple reports build `5a228c23-8cae-441d-8c53-eba6675afcbd` as `VALID` with Beta App Review `APPROVED`, in the Internal (all builds) and External (added) groups, on September 24, 2026 UTC. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. These states do not prove a completed physical-phone game or the audio mix on device.

## Changes

These come from [PR #33](https://github.com/ineedsomesleep5/MagicMobile/pull/33): Caleb's notes on build 15, plus the AAA pass he asked for.

- **Result screen:** the victory/defeat tint is one continuous wash from edge to edge, with no band.
- **Stack tray:** moved into the dock beside the floating mana. It shows the top card's art, the count and grouped triggers, and opens the stack. The center strip stays clear.
- **Audio:**
  - `GameAudio` plays 54 cues plus menu and table music, with effects and music settings. Sounds follow the Silent switch.
  - Sources: Kenney CC0 foley layered with original synthesis (`scripts/audio`).
  - Cues cover color-identity casts, arrivals, combat, deaths and exile, life, draws, mana taps, resolutions, turn bells, choices, errors, dice, the versus intro, victory and defeat.
- **Menus, setup and loading:** brand-styled from the app icon and `apps/site/DESIGN.md`.
  - The traced logo mark with a glinting sparkle.
  - An ember backdrop with fanned cards and sparks.
  - A floating hero commander and ember buttons.
  - A VS medallion on setup and a versus intro before the first draw.
  - A loading screen with tips and a branded launch screen.
- **Board:**
  - Tapped lands keep their art.
  - Permanent names shrink before truncating.
  - The hand pill is themed.
- **Fixes:**
  - The menu glint no longer widens the Play button's accessibility frame.
  - Wrapped button styles keep their disabled state.
- **Versions:** marketing version stays `0.1.1`. Build `16` was prepared with `scripts/ios/testflight-build-number.mjs` after build 15. Android is unchanged.

## Verification

- Signed source: `4498d37a1335660bee7194d76fd24113a4c8bf50`, which is `main` at `b8ba97a` plus the build-16 number bump.
- Checks:
  - `ios-fast` preflight: 11/11.
  - MagicMobileTests: 715 run. GameAudioTests check that every cue decodes and that sounds map correctly. One landscape dock-height assertion fails, and it already failed before this build.
  - UI tests passed: presentation-smoke 5/5, CardChoiceDraft 5/5, DeckStudioPinnedTabs 3/3, NativeDownloads 4/4, IndependentAIDecks 1/1, and OnDeviceSetup's menu, name, AI-skill, missing-library and updates tests.
  - Other OnDeviceSetup tests are stale on `main`. They expect labels removed in 7d39dbf and 80d2927.
  - PR #33 CI passed (swift, real-jvm, boundary, checks).
- Simulator (iPhone 17 Pro, Debug) screens checked:
  - home, setup and the versus fixture
  - stack-tray and victory previews
  - spectrograms of the synthesized cues, checked for end clicks
- Native engine: reused, unchanged since build 15.
  - Artifact `10818031401` from run [36014055598](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36014055598), engine commit `5d2cb18`.
  - Staged `libmmengine.a` SHA-256: `5a170286e42d693bd3ee3de2a8a7e746fc578005eca8b03ca55158b134ffd076`.
  - Preflight's native decision is `equivalent-source`.
- Not verified: audio on a phone speaker, phone feel, and a real-engine game on device.

## Signed artifact and Apple distribution

- Release controller run `ios-0.1.1-16`, fingerprint `dcb68b9d26a7c8560241b8c8861ee82e63021b130dd1a68fa3094c35057ad14c`, state `completed`.
- IPA SHA-256 `568b6466be069b4d43b9a7768d121112e91b1a99097c3a9ed214094b393c6dda`; Apple processing state `VALID`.
- Build ID `5a228c23-8cae-441d-8c53-eba6675afcbd`.
- Groups: Internal `dd37d7bb-26d8-4a0c-b8a3-7811d648a699` (all builds) and External `72b71a7a-bf62-43b5-8eda-b12a62e5c3eb` (added).
- Beta App Review: `APPROVED`.
