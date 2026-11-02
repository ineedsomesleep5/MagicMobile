# Android 0.1.1 build 55: painted coins for the older trophies

Published November 1, 2026 as the latest public release,
[android-v0.1.1-build.55](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.55), from
PR #284 (TestFlight 78 from the same source).

## Signed artifact
- **Source:** `codex/android-build-55` (`fccf2272`) = PR head `5475f449` + bump, versionCode `2026110103`, `RELEASE_BUILD` 55.
- **Native engine:** unchanged from build 52, identity `sha256:caaa30a0…1be1`.
- **APK SHA-256:** `403ed84cf0fd93d43da4abe6f67ba7cf14fe4d0bebcdf562bac50e7b37205373` (144288327 bytes), with a copy in `~/Documents/MagicMobile-releases/android-55/`. The public download re-hashes the same.
- **Signer:** `b10ca2cd…d4bb`, the existing release key.

## What changed
The painted coins as in TestFlight 78 (`release/RELEASE_0.1.1_BUILD78.md`).

## Verification
- `build_release.sh`; emulator API 35: in-place update `2026110102` → `2026110103`, 6 of 6 device tests with a 16-turn native game. `:core` tests, contract checks, and CI on #284.
- **Not verified on a phone**, and the coins haven't been seen running on Android.
