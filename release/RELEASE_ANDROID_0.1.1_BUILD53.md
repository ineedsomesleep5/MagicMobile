# Android 0.1.1 build 53: placement matches

Published November 1, 2026 as the latest public release,
[android-v0.1.1-build.53](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.53), from
PR #279 (TestFlight 76 from the same source).

## Signed artifact
- **Source:** `codex/android-build-53` (`f5e46d98`) = `claude/ranked-placements` `296c7d34` + bump, versionCode `2026110101`, `RELEASE_BUILD` 53.
- **Native engine:** unchanged from build 52, identity `sha256:caaa30a0…1be1`.
- **APK SHA-256:** `4278a72c8c4c6c6f227fb62185be238ee43d8f55951b9b976faeb85b96c1d645` (144281927 bytes), with a copy in `~/Documents/MagicMobile-releases/android-53/`. The signer is unchanged (`b10ca2cd…d4bb`).

## What changed
Placement matches as in TestFlight 76 (`release/RELEASE_0.1.1_BUILD76.md`).

## Verification
- `build_release.sh`; emulator API 35: in-place update `2026103101` → `2026110101`, 6 of 6 device tests with a 20-turn native game. `:core` tests and web tests on the placement branch.
- **Not verified on a phone**, and the placement screens themselves haven't been seen running on Android.
