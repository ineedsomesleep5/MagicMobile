# Android 0.1.1 build 48: your own card art is the whole card and follows you to every device

Published October 28, 2026 as the latest public release,
[android-v0.1.1-build.48](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.48), from
PR #263 (TestFlight 70 from the same source on `codex/ios-build-70`).

## Signed artifact
- **Source:** `codex/android-build-48` (`433935e9`) = PR #263's head merged with `codex/android-build-47` (calibration
  tooling and `PROTOCOL.md` at engine release C, no `LessonCli.java`), versionCode `2026102803`, `RELEASE_BUILD` 48.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `c78302219c8ed1194605759c00a4505c83f8f7128b887f7da680840d0e0f93ef` (144305727 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-48/`. The public download was re-hashed and matches.

## What changed
Same as TestFlight 70 (`release/RELEASE_0.1.1_BUILD70.md`): your own picture is the card's whole face, and pictures sync
to every phone and browser signed in to the profile (docs/CARD_ART_SYNC.md).

## Verification
- **Unit:** `:core:test` CardArtSyncTest (the 11 shared cases) and DeckSyncTest; `:app:compileDebugKotlin`; CI on #263.
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026102802` → `2026102803`; 6/6 packaged-engine device tests,
  including a 22-turn native Commander game and a seeded game record.
- **Not verified on a phone:** a picture syncing between a phone and the web.
