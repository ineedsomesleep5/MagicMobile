# Android 0.1.1 build 54: trophies from the server

Published November 1, 2026 as the latest public release,
[android-v0.1.1-build.54](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.54), from
PR #281 (TestFlight 77 from the same source).

## Signed artifact
- **Source:** `codex/android-build-54` (`97c15ae2`) = PR head `c57f1c6b` + bump, versionCode `2026110102`, `RELEASE_BUILD` 54.
- **Native engine:** unchanged from build 52, identity `sha256:caaa30a0…1be1`.
- **APK SHA-256:** `17402427d1cdd3beffc2db943cc823b7b7be424bfa864d4aeb8aad7e7a382134` (144287163 bytes), with a copy in `~/Documents/MagicMobile-releases/android-54/`. The public download re-hashes the same.
- **Signer:** `b10ca2cd…d4bb`, the existing release key.

## What changed
Trophies, the season shelf and the pile lean as in TestFlight 77 (`release/RELEASE_0.1.1_BUILD77.md`). Android's season shelf didn't clip, so its glow is unchanged.

## Verification
- `build_release.sh`; emulator API 35: in-place update `2026110101` → `2026110102`, 6 of 6 device tests with a 13-turn native game. `:core` tests (443), contract checks, and CI on #281.
- **Not verified on a phone**, and the Trophies shelf hasn't been seen running on Android.
