# Android 0.1.1 build 30: a cooler board

Published October 18, 2026 as [android-v0.1.1-build.30](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.30),
first as a test prerelease and then as the latest release, together with iPhone build 47
(`release/RELEASE_0.1.1_BUILD47.md`), on the same native engine as builds 24–29.

## Scope
Same heat fix as iPhone build 47 (#201): the breathing glows step at 10 Hz while hot and rest when the board is idle,
the thinking ring draws once and turns its layer, the inspector foil steps at 30/15 Hz, ribbon banners fit once, and
byte-identical poll replies return the previous poll undecoded.

## Signed artifact
- **Source:** `5aaae657` (`codex/android-build-30`): main `3c916f21` plus versionCode `2026101801` and `RELEASE_BUILD` 30.
  The engine package is unchanged since the engine's source commit `160e250`.
- **Native engine:** unchanged (`android-build24-engine-160e250`).
- **APK SHA-256:** `e9838625a71f69a21c47c5587085dd55f53848ea0145d7129727b631c0593a26` (143263544 bytes). The public
  download re-hashes to the same value.
- **Signer:** unchanged, so it updates in place.

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** an in-place update `2026101703` → `2026101801`; 6/6 packaged-engine device tests,
  including a 12-turn native Commander game and a seeded game record (56 entries by turn 3, engine build
  `sha256:225ee7de…9869`).
- PR #201's CI green (Android app checks, unit tests).
- **Not verified:** a physical Android phone.
