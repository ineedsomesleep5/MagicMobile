# Android 0.1.1 build 34: the Arena look

Published October 23, 2026 as the latest public release,
[android-v0.1.1-build.34](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.34), together
with iPhone build 57 (`release/RELEASE_0.1.1_BUILD57.md`). The app is the Android Arena port (#226): the Arena menus,
the Arena board in both orientations, the full-table browsers, the D20 roll on the board, Arena's mulligan and the
Victory/Defeat screens, with Hearth kept as a separate board mode.

## Signed artifact
- **Source:** `d8a9bfac` (`codex/android-build-34`): #226's `53fddad2` with versionCode `2026102301` and
  `RELEASE_BUILD` 34. #226's later commit is LESSONS only.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`,
  `~/Documents/MagicMobile-releases/engines/android-build31-engine-21a82eb/artifact`).
- **APK SHA-256:** `3704af92b669264b060879b7d94f2a55ccc70fc3e362e061fd72b008c25951b9` (136342373 bytes). A copy is kept
  in `~/Documents/MagicMobile-releases/android-34/`. The public download was re-hashed and matches.
- **Signer:** unchanged, so it updates in place.

## Verification
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner. The first run stopped at
  `lintRelease` (SuspiciousIndentation in MultiplayerD20View), fixed in `53fddad2`.
- **Emulator (API 35, headless):** in-place update `2026101902` → `2026102301`; 6/6 packaged-engine device tests,
  including a 20-turn native Commander game and a seeded game record (53 entries by turn 3, engine build
  `sha256:9f06efbe…906f`). The release menu screenshot shows the Arena home.
- **Debug design previews on the emulator, portrait and landscape:** roll, opening hand, victory, scry, library search,
  modes, may-trigger, player target, ability choice, stack tray, home, Play panel (Quick and Custom), Decks, Friends.
- **JVM:** `:core:test` (379) and `:app:testDebugUnitTest` (95). PR CI `app` passed.
- **Not verified:** a physical Android phone, or a live online game against an iPhone.
