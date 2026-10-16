# Android 0.1.1 build 25: removal plays out, token piles, attachment tabs

Published October 15, 2026 as [android-v0.1.1-build.25](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.25),
together with iPhone build 41 (`release/RELEASE_0.1.1_BUILD41.md`), on the same native engine as build 24.

## Scope
Same changes as iPhone build 41 (#183): removal plays out before smart pass moves on, multi-select from token piles
with a check seal, and lower-row attachment tabs that no longer cover the card above.

## Signed artifact
- **Source:** `ae1b280` (`codex/android-build-25`): main `1f99736` plus versionCode `2026101503` and `RELEASE_BUILD` 25.
  The engine package is unchanged since the engine's source commit `160e250`.
- **Native engine:** unchanged (`android-build24-engine-160e250`).
- **APK SHA-256:** `37d3b55a3fa952d125c2dca7c0648c1565a08c767cd7b34052e5f9a0d8e7ba6d` (143098630 bytes). The public
  download re-hashes to the same value.
- **Signer:** unchanged, so it updates in place.

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** an in-place update `2026101502` → `2026101503`; 5/5 packaged-engine device tests in the
  first run (including a 22-turn native Commander game). The new `packagedEngineKeepsASeededGameRecord` failed at turn
  0 there because it stopped polling during the game's setup phases (#184, test-only); rerun against the installed
  build it passed: a seeded native game kept a record of 51 entries by turn 3 with the server's seed and engine build
  `sha256:225ee7de…9869`, the identity registered in `ranked_engine_builds`. The main menu reached cleanly.
- Android core tests 258/0 and the app and device-test compile on the merged source.
- **Not verified:** a physical phone, and a ranked AI game against the live server.
