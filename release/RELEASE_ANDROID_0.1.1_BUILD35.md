# Android 0.1.1 build 35: Arena is the default board, the real card back

Published October 23, 2026 as the latest public release,
[android-v0.1.1-build.35](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.35), together
with iPhone build 58 (`release/RELEASE_0.1.1_BUILD58.md`). The app change is PR #228:
- Arena is the default board.
- The real Magic card back from `backs.scryfall.io`, fetched with artwork consent and cached.
- The landscape gear moves 3 pt down.

## Signed artifact
- **Source:** `060e4422` (`codex/android-build-35`): main `02c4d79d` (after #228) with versionCode `2026102302` and
  `RELEASE_BUILD` 35.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `9cf0ebc38584d2b4ba713eba9e8995c5318854b23582ddb97138364f293da4bf` (136343685 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-35/`. The public download was re-hashed and matches.
- **Signer:** unchanged, so it updates in place.

## Verification
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026102301` → `2026102302`; 6/6 packaged-engine device tests,
  including a 19-turn native Commander game and a seeded game record (56 entries by turn 3, engine
  `sha256:9f06efbe…906f`).
- **Debug build on the emulator:** a fresh install opens a game on the Arena board, and the real card back downloads
  (131415 bytes, cached) and shows on both libraries and the opponent's hand.
- **JVM:** 474 tests and `lintDebug` pass; PR #228 CI passed.
- **Not verified:** a physical Android phone.
