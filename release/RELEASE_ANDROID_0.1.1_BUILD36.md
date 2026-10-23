# Android 0.1.1 build 36: deck sync

Published October 23, 2026 as the latest public release,
[android-v0.1.1-build.36](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.36), together
with iPhone build 59 (`release/RELEASE_0.1.1_BUILD59.md`). The app change is deck sync from PR #230
(docs/DECK_SYNC.md): your saved decks follow your profile to every phone and to the web app; a conflict keeps both
versions ("(this device)"), and deletions reach the other devices.

## Signed artifact
- **Source:** `76c4fcfe` (`codex/android-build-36`): `claude/web-arena-v2` (`18efd9dc`, main `2162a55e` plus PR #230)
  with versionCode `2026102303` and `RELEASE_BUILD` 36.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `b96a92505f8c8a7cd13dd27949e6b21b5e9c8aece92d28d86ae03dfb91135a23` (136357985 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-36/`. The public download was re-hashed and matches.
- **Signer:** unchanged, so it updates in place.

## Verification
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026102302` → `2026102303`; 6/6 packaged-engine device tests,
  including a 17-turn native Commander game and a seeded game record (48 entries by turn 3, engine
  `sha256:9f06efbe…906f`).
- **JVM:** `:core:test` studio.* (102 tests; DeckSyncTest runs all 12 cases of parity/deck-sync-cases.json),
  `:app:compileDebugKotlin` and `:app:lintDebug`.
- **Not verified:** deck sync on a physical phone or against the live server from Android.
