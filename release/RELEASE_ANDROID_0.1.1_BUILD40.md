# Android 0.1.1 build 40: on-screen navigation buttons, hand drag, turn-judged ranked, season badges

Published October 26, 2026 as the latest public release,
[android-v0.1.1-build.40](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.40), from
PR #246 (Android only; iOS not shipped).

## Signed artifact
- **Source:** `codex/android-build-40` (`73594640`) = `claude/ranked-turns-history` at `93fb801b` with versionCode
  `2026102601`, `RELEASE_BUILD` 40, and the calibration tooling at build 37's version (release branch only; never merged).
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `50d1e6b66b41fae4d9c11daf5369279fbf9b4e8f5db3a362c67120364772cba7` (136428641 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-40/`. The public download was re-hashed and matches.

## What changed
- Full-screen dialogs (messages, profiles, friends, the on-device game) span the screen and take insets themselves, so
  on 3-button navigation the reply box and buttons sit above the bars and the keyboard (a tester's report).
- The Arena board pads for the tappable navigation bar; a hand drag that starts upward carries the card it started on.
- Ranked wins judged by turn, the reason a win didn't count, quarterly seasons from November, season badges, the tier
  frame on the versus screen, the yellow ability glow, your own face-down cards' art, and attachment tabs.

## Verification
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner; debug lint passes.
- **Emulator (API 35, headless):** in-place update `2026102502` → `2026102601`; 6/6 packaged-engine device tests,
  including a 16-turn native Commander game.
- **Not verified on a phone:** 3-button navigation on real hardware, the hand drag, and the season badges.
