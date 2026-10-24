# Android 0.1.1 build 37: the freeze logger

Published October 24, 2026 as the latest public release,
[android-v0.1.1-build.37](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.37), together
with iPhone build 60 (`release/RELEASE_0.1.1_BUILD60.md`). The app change is the freeze logger from PR #239
(docs/FREEZE_LOG.md): a main-thread watchdog, a game-stall check, breadcrumbs, and reports sent only on the player's Send
(the next launch asks; the game menu has Report a freeze).

## Signed artifact
- **Source:** `codex/android-build-37`: main's PR #239 branch (`claude/freeze-logger`) with versionCode `2026102401` and
  `RELEASE_BUILD` 37.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `a5f69cd5ac453d733bcfd56d8372b0505c8b9feaab35f4660999d0a0fdb3eae5` (136377937 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-37/`. The public download was re-hashed and matches.
- **Signer:** unchanged, so it updates in place.

## Verification
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026102303` → `2026102401`; 6/6 packaged-engine device tests,
  including a 13-turn native Commander game and a seeded game record (60 entries by turn 3, engine
  `sha256:9f06efbe…906f`).
- **JVM:** `:core:test` (398, FreezeLogTest runs every case of parity/freeze-cases.json) and `:app:testDebugUnitTest` (96),
  `:app:lintDebug`, `:app:assembleDebug`.
- **Not verified:** the watchdog, the dialogs and a real send on a phone.
